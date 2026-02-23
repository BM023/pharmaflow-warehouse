"""
python/etl/pipeline.py
PharmaFlow Analytics — ETL Pipeline Runner

Standalone entry point that wires extract → transform → load together.
Can be run directly or called by Airflow PythonOperators.

Usage:
    python -m python.etl.pipeline                    # run for today
    python -m python.etl.pipeline --date 2026-02-23  # run for specific date
    python -m python.etl.pipeline --dry-run          # extract + transform only
"""

import os
import sys
import logging
import argparse
from datetime import datetime, date
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
LOG_DIR = Path(os.getenv('LOG_DIR', 'logs'))
LOG_DIR.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)-5s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_DIR / f"etl_{datetime.now().strftime('%Y-%m-%d')}.log"),
    ]
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Import ETL modules
# ---------------------------------------------------------------------------
try:
    from python.etl.extract import run_extract, extract_existing_prescription_numbers, \
                                    extract_existing_patient_ids, extract_dimension_keys
    from python.etl.transform import run_transform
    from python.etl.load import run_load
except ModuleNotFoundError:
    # Allow running from project root without package prefix
    sys.path.insert(0, str(Path(__file__).parent.parent.parent))
    from python.etl.extract import run_extract, extract_existing_prescription_numbers, \
                                    extract_existing_patient_ids, extract_dimension_keys
    from python.etl.transform import run_transform
    from python.etl.load import run_load

RAW_DATA_DIR = os.getenv('RAW_DATA_DIR', 'raw_data')


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------
def run_pipeline(target_date: date = None, dry_run: bool = False) -> dict:
    """
    Full ETL pipeline: extract → transform → load.

    Args:
        target_date: date to process (defaults to today)
        dry_run:     if True, skip the load stage

    Returns:
        results dict with row counts per stage
    """
    if target_date is None:
        target_date = date.today()

    pipeline_start = datetime.now()
    date_str = target_date.isoformat()

    logger.info("=" * 70)
    logger.info("PHARMAFLOW ANALYTICS — ETL PIPELINE")
    logger.info(f"Date     : {date_str}")
    logger.info(f"Dry run  : {dry_run}")
    logger.info(f"Started  : {pipeline_start.strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 70)

    results = {
        'date': date_str,
        'dry_run': dry_run,
        'extract': {},
        'transform': {},
        'load': {},
        'status': 'success',
    }

    try:
        # ------------------------------------------------------------------
        # EXTRACT
        # ------------------------------------------------------------------
        logger.info("\n--- STAGE 1: EXTRACT ---")
        dataframes = run_extract(RAW_DATA_DIR, target_date)
        results['extract'] = {k: len(v) for k, v in dataframes.items() if v is not None}

        if not any(df is not None and not df.empty for df in dataframes.values()):
            logger.warning("No files found for this date — pipeline complete with nothing to process.")
            results['status'] = 'no_data'
            return results

        # ------------------------------------------------------------------
        # TRANSFORM
        # ------------------------------------------------------------------
        logger.info("\n--- STAGE 2: TRANSFORM ---")
        existing_rx      = extract_existing_prescription_numbers()
        existing_patients = extract_existing_patient_ids()

        logger.info(f"  Existing prescription numbers in warehouse: {len(existing_rx):,}")
        logger.info(f"  Existing patient IDs in warehouse: {len(existing_patients):,}")

        transformed = run_transform(dataframes, existing_rx, existing_patients)
        results['transform'] = {k: len(v) for k, v in transformed.items()}

        if dry_run:
            logger.info("\n[DRY RUN] Skipping load stage.")
            logger.info("Transform output:")
            for name, df in transformed.items():
                logger.info(f"  {name}: {len(df):,} rows ready")
            results['status'] = 'dry_run_complete'
            return results

        # ------------------------------------------------------------------
        # LOAD
        # ------------------------------------------------------------------
        logger.info("\n--- STAGE 3: LOAD ---")
        dim_keys = extract_dimension_keys()
        load_results = run_load(
            transformed=transformed,
            dim_keys=dim_keys,
            existing_rx_numbers=existing_rx,
            existing_patient_ids=existing_patients,
            run_date=date_str,
        )
        results['load'] = load_results

    except Exception as e:
        logger.error(f"Pipeline failed: {e}", exc_info=True)
        results['status'] = 'failed'
        results['error'] = str(e)
        raise

    finally:
        elapsed = (datetime.now() - pipeline_start).total_seconds()
        logger.info("\n" + "=" * 70)
        logger.info(f"PIPELINE COMPLETE — {elapsed:.1f}s | status: {results['status']}")
        logger.info("=" * 70)

    return results


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='PharmaFlow ETL Pipeline')
    parser.add_argument('--date',    type=str,  default=None,
                        help='Date to process (YYYY-MM-DD). Defaults to today.')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run extract + transform only, skip load.')
    args = parser.parse_args()

    target_date = None
    if args.date:
        try:
            target_date = datetime.strptime(args.date, '%Y-%m-%d').date()
        except ValueError:
            logger.error(f"Invalid date format: {args.date}. Use YYYY-MM-DD.")
            sys.exit(1)

    results = run_pipeline(target_date=target_date, dry_run=args.dry_run)

    if results['status'] == 'failed':
        sys.exit(1)


if __name__ == '__main__':
    main()
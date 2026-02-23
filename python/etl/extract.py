"""
python/etl/extract.py
PharmaFlow Analytics — Extract Module

Reads raw source files (CSV, JSON, Excel) from raw_data/ and returns
clean DataFrames ready for the transform stage.

Supports:
  - Prescription CSVs
  - Inventory Excel snapshots
  - Medication catalog JSON
  - Patient registration CSVs
"""

import os
import json
import logging
from datetime import datetime, date
from pathlib import Path
from typing import Optional

import pandas as pd
import psycopg2

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Database connection
# ---------------------------------------------------------------------------
DB_CONFIG = {
    'host':     os.getenv('DB_HOST', 'localhost'),
    'port':     os.getenv('DB_PORT', '5433'),
    'database': os.getenv('DB_NAME', 'pharmaflow_warehouse'),
    'user':     os.getenv('DB_USER', 'pharmaflow'),
    'password': os.getenv('DB_PASSWORD', 'pharmaflow2024'),
}


def get_connection():
    """Return a psycopg2 connection to the warehouse."""
    return psycopg2.connect(**DB_CONFIG)


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------
def find_files_for_date(base_dir: str, target_date: Optional[date] = None) -> dict:
    """
    Scan raw_data/<YYYY-MM-DD>/ and return a dict of file paths by type.

    Returns:
        {
            'prescriptions': Path | None,
            'inventory':     Path | None,
            'medications':   Path | None,
            'patients':      Path | None,
        }
    """
    if target_date is None:
        target_date = date.today()

    date_str = target_date.strftime('%Y-%m-%d')
    folder = Path(base_dir) / date_str

    result = {
        'prescriptions': None,
        'inventory':     None,
        'medications':   None,
        'patients':      None,
    }

    if not folder.exists():
        logger.warning(f"Raw data folder not found: {folder}")
        return result

    for file in folder.iterdir():
        name = file.name.lower()
        if name.startswith('prescriptions_') and name.endswith('.csv'):
            result['prescriptions'] = file
        elif name.startswith('inventory_snapshot_') and name.endswith('.xlsx'):
            result['inventory'] = file
        elif name == 'medication_catalog.json':
            result['medications'] = file
        elif name == 'new_patients.csv':
            result['patients'] = file

    found = [k for k, v in result.items() if v is not None]
    logger.info(f"Found {len(found)} file(s) for {date_str}: {found}")
    return result


# ---------------------------------------------------------------------------
# Extractors
# ---------------------------------------------------------------------------
def extract_prescriptions(file_path: Path) -> pd.DataFrame:
    """
    Read prescription CSV into a DataFrame.

    Expected columns (may have data quality issues — transform handles those):
        prescription_number, prescription_date, patient_id, medication_id,
        doctor_id, pharmacy_id, insurance_id, quantity_dispensed,
        unit_price, total_amount, patient_copay, insurance_coverage_amount,
        prescription_type, payment_method, dispensing_timestamp
    """
    logger.info(f"Extracting prescriptions from: {file_path}")

    df = pd.read_csv(
        file_path,
        dtype=str,           # read everything as string — transform will cast
        keep_default_na=False,
        na_values=['', 'NULL', 'null', 'None', 'NA', 'N/A'],
    )

    row_count = len(df)
    col_count = len(df.columns)
    file_size = file_path.stat().st_size

    logger.info(f"  Rows: {row_count:,} | Columns: {col_count} | Size: {file_size:,} bytes")

    # Tag with source metadata
    df['_source_file'] = file_path.name
    df['_extracted_at'] = datetime.now().isoformat()
    df['_file_type'] = 'prescriptions'

    return df


def extract_inventory(file_path: Path) -> pd.DataFrame:
    """
    Read inventory Excel snapshot — 'Inventory' sheet only.

    Expected columns:
        pharmacy_id, location_name, medication_id, medication_name,
        quantity_on_hand, quantity_allocated, reorder_point,
        maximum_stock_level, stock_value_at_cost, stock_value_at_retail,
        stock_status_code, min_days_until_expiry, snapshot_timestamp
    """
    logger.info(f"Extracting inventory from: {file_path}")

    df = pd.read_excel(
        file_path,
        sheet_name='Inventory',
        dtype=str,
        keep_default_na=False,
        na_values=['', 'NULL', 'null', 'None', 'NA', 'N/A'],
    )

    logger.info(f"  Rows: {len(df):,} | Columns: {len(df.columns)}")

    df['_source_file'] = file_path.name
    df['_extracted_at'] = datetime.now().isoformat()
    df['_file_type'] = 'inventory'

    return df


def extract_medications(file_path: Path) -> pd.DataFrame:
    """
    Read medication catalog JSON into a DataFrame.

    JSON is a list of medication objects — malformed records are logged
    and excluded rather than crashing the pipeline.
    """
    logger.info(f"Extracting medications from: {file_path}")

    with open(file_path, 'r') as f:
        raw = json.load(f)

    valid = []
    skipped = 0

    for record in raw:
        # Must have medication_id and medication_name to be usable
        if not record.get('medication_id') or not record.get('medication_name'):
            logger.warning(f"  Skipping malformed record: {record}")
            skipped += 1
            continue
        valid.append(record)

    if skipped:
        logger.warning(f"  Skipped {skipped} malformed records out of {len(raw)}")

    df = pd.DataFrame(valid)
    df = df.astype(str)

    logger.info(f"  Valid records: {len(df):,} | Skipped: {skipped}")

    df['_source_file'] = file_path.name
    df['_extracted_at'] = datetime.now().isoformat()
    df['_file_type'] = 'medications'

    return df


def extract_patients(file_path: Path) -> pd.DataFrame:
    """
    Read new patient registration CSV.

    Expected columns:
        patient_id, title, first_name, last_name, date_of_birth, gender,
        phone_number, email, address_line1, suburb, city, postal_code,
        registration_date, is_chronic_patient, has_medical_aid
    """
    logger.info(f"Extracting patients from: {file_path}")

    df = pd.read_csv(
        file_path,
        dtype=str,
        keep_default_na=False,
        na_values=['', 'NULL', 'null', 'None', 'NA', 'N/A'],
    )

    logger.info(f"  Rows: {len(df):,} | Columns: {len(df.columns)}")

    df['_source_file'] = file_path.name
    df['_extracted_at'] = datetime.now().isoformat()
    df['_file_type'] = 'patients'

    return df


# ---------------------------------------------------------------------------
# Database extractors (for incremental loads)
# ---------------------------------------------------------------------------
def extract_existing_prescription_numbers() -> set:
    """Return set of prescription_number values already in the warehouse."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute("SELECT prescription_number FROM dwh.fact_prescription_transactions")
        return {row[0] for row in cur.fetchall()}
    finally:
        conn.close()


def extract_existing_patient_ids() -> set:
    """Return set of patient_id values already in dim_patient."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute("SELECT patient_id FROM dwh.dim_patient WHERE is_current = TRUE")
        return {row[0] for row in cur.fetchall()}
    finally:
        conn.close()


def extract_dimension_keys() -> dict:
    """
    Fetch all dimension surrogate keys needed for fact table loading.

    Returns:
        {
            'medications':  {medication_id: medication_key},
            'pharmacies':   {pharmacy_id:   pharmacy_key},
            'doctors':      {doctor_id:     doctor_key},
            'insurance':    {insurance_id:  insurance_key},
            'patients':     {patient_id:    patient_key},
            'dates':        {date_str:      date_key},   # YYYY-MM-DD → YYYYMMDD
        }
    """
    conn = get_connection()
    try:
        cur = conn.cursor()
        keys = {}

        cur.execute("SELECT medication_id, medication_key FROM dwh.dim_medication WHERE is_current = TRUE")
        keys['medications'] = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT pharmacy_id, pharmacy_key FROM dwh.dim_pharmacy WHERE is_active = TRUE")
        keys['pharmacies'] = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT doctor_id, doctor_key FROM dwh.dim_doctor WHERE is_active = TRUE")
        keys['doctors'] = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT insurance_id, insurance_key FROM dwh.dim_insurance WHERE is_active = TRUE")
        keys['insurance'] = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT patient_id, patient_key FROM dwh.dim_patient WHERE is_current = TRUE")
        keys['patients'] = {r[0]: r[1] for r in cur.fetchall()}

        cur.execute("SELECT TO_CHAR(full_date, 'YYYY-MM-DD'), date_key FROM dwh.dim_date")
        keys['dates'] = {r[0]: r[1] for r in cur.fetchall()}

        logger.info(f"  Dimension keys loaded: "
                    f"{len(keys['medications'])} meds, "
                    f"{len(keys['pharmacies'])} pharmacies, "
                    f"{len(keys['doctors'])} doctors, "
                    f"{len(keys['patients'])} patients")
        return keys

    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Extraction summary for logging/metadata
# ---------------------------------------------------------------------------
def extraction_summary(dataframes: dict) -> dict:
    """Return row counts and file names for each extracted dataset."""
    summary = {}
    for name, df in dataframes.items():
        if df is not None and not df.empty:
            summary[name] = {
                'rows': len(df),
                'columns': len(df.columns),
                'source': df['_source_file'].iloc[0] if '_source_file' in df.columns else 'unknown',
            }
        else:
            summary[name] = {'rows': 0, 'columns': 0, 'source': None}
    return summary


# ---------------------------------------------------------------------------
# Main extract entry point (called by Airflow PythonOperator)
# ---------------------------------------------------------------------------
def run_extract(raw_data_dir: str, target_date: Optional[date] = None) -> dict:
    """
    Full extraction run for a given date.

    Returns dict of DataFrames:
        {'prescriptions': df, 'inventory': df, 'medications': df, 'patients': df}
    """
    logger.info("=" * 60)
    logger.info("EXTRACT STAGE STARTING")
    logger.info("=" * 60)

    files = find_files_for_date(raw_data_dir, target_date)

    dataframes = {
        'prescriptions': extract_prescriptions(files['prescriptions']) if files['prescriptions'] else None,
        'inventory':     extract_inventory(files['inventory'])         if files['inventory']     else None,
        'medications':   extract_medications(files['medications'])     if files['medications']   else None,
        'patients':      extract_patients(files['patients'])           if files['patients']      else None,
    }

    summary = extraction_summary({k: v for k, v in dataframes.items() if v is not None})
    for name, info in summary.items():
        logger.info(f"  {name}: {info['rows']:,} rows from {info['source']}")

    logger.info("EXTRACT STAGE COMPLETE")
    return dataframes
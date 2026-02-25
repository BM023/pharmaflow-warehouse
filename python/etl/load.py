"""
python/etl/load.py
PharmaFlow Analytics — Load Module

Loads transformed DataFrames into the warehouse using:
  - Upsert logic (insert if new, skip/update if exists)
  - SCD Type 2 for patient dimension (historical tracking)
  - Bulk loading via execute_batch for performance
  - Metadata table updates (load timestamps, row counts, status)
"""

import os
import logging
from datetime import datetime
from typing import Optional

import psycopg2
from psycopg2.extras import execute_batch
import pandas as pd

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

DB_CONFIG = {
    'host':     os.getenv('PHARMAFLOW_DB_HOST', os.getenv('DB_HOST', 'localhost')),
    'port':     os.getenv('PHARMAFLOW_DB_PORT', os.getenv('DB_PORT', '5433')),
    'database': os.getenv('PHARMAFLOW_DB_NAME', os.getenv('DB_NAME', 'pharmaflow_warehouse')),
    'user':     os.getenv('PHARMAFLOW_DB_USER', os.getenv('DB_USER', 'pharmaflow')),
    'password': os.getenv('PHARMAFLOW_DB_PASSWORD', os.getenv('DB_PASSWORD', 'pharmaflow2024')),
}

BATCH_SIZE = 500


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


# ---------------------------------------------------------------------------
# Metadata table — tracks every pipeline run
# ---------------------------------------------------------------------------
def ensure_metadata_table(conn):
    """Create pipeline_runs metadata table if it doesn't exist."""
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS dwh.pipeline_runs (
            run_id              BIGSERIAL PRIMARY KEY,
            run_date            DATE          NOT NULL,
            stage               VARCHAR(50)   NOT NULL,
            source_file         VARCHAR(255),
            rows_extracted      INTEGER       DEFAULT 0,
            rows_transformed    INTEGER       DEFAULT 0,
            rows_loaded         INTEGER       DEFAULT 0,
            rows_skipped        INTEGER       DEFAULT 0,
            rows_failed         INTEGER       DEFAULT 0,
            status              VARCHAR(20)   NOT NULL DEFAULT 'running',
            error_message       TEXT,
            started_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
            completed_at        TIMESTAMP,
            duration_seconds    INTEGER
        );
    """)
    conn.commit()
    cur.close()


def log_pipeline_run(conn, run_date: str, stage: str, source_file: str,
                     rows_extracted: int, rows_transformed: int,
                     rows_loaded: int, rows_skipped: int = 0,
                     rows_failed: int = 0, status: str = 'success',
                     error_message: str = None, started_at: datetime = None) -> int:
    """Insert a pipeline run record and return its run_id."""
    ensure_metadata_table(conn)
    cur = conn.cursor()
    completed_at = datetime.now()
    duration = int((completed_at - started_at).total_seconds()) if started_at else None

    cur.execute("""
        INSERT INTO dwh.pipeline_runs (
            run_date, stage, source_file,
            rows_extracted, rows_transformed, rows_loaded,
            rows_skipped, rows_failed, status,
            error_message, started_at, completed_at, duration_seconds
        ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        RETURNING run_id
    """, (run_date, stage, source_file,
          rows_extracted, rows_transformed, rows_loaded,
          rows_skipped, rows_failed, status,
          error_message, started_at, completed_at, duration))

    run_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    logger.info(f"  Pipeline run logged: run_id={run_id}, status={status}, "
                f"loaded={rows_loaded:,}, skipped={rows_skipped:,}")
    return run_id


# ---------------------------------------------------------------------------
# Dimension key lookups
# ---------------------------------------------------------------------------
def get_surrogate_key(cur, table: str, id_col: str, id_val: str,
                      key_col: str) -> Optional[int]:
    """Fetch a surrogate key from a dimension table."""
    cur.execute(f"SELECT {key_col} FROM dwh.{table} WHERE {id_col} = %s LIMIT 1", (id_val,))
    row = cur.fetchone()
    return row[0] if row else None


# ---------------------------------------------------------------------------
# Load prescriptions
# ---------------------------------------------------------------------------
def load_prescriptions(df: pd.DataFrame, dim_keys: dict) -> dict:
    """
    Insert new prescription transactions.
    Skips records where dimension keys can't be resolved.
    Returns stats dict.
    """
    if df is None or df.empty:
        return {'loaded': 0, 'skipped': 0, 'failed': 0}

    started_at = datetime.now()
    conn = get_connection()
    conn.autocommit = False

    loaded = skipped = failed = 0
    records = []

    for _, row in df.iterrows():
        try:
            patient_key    = dim_keys['patients'].get(str(row.get('patient_id', '')))
            medication_key = dim_keys['medications'].get(str(row.get('medication_id', '')))
            doctor_key     = dim_keys['doctors'].get(str(row.get('doctor_id', '')))
            pharmacy_key   = dim_keys['pharmacies'].get(str(row.get('pharmacy_id', '')))
            date_str       = str(row.get('prescription_date', ''))[:10]
            date_key       = dim_keys['dates'].get(date_str)

            # Insurance is optional (cash patients have none)
            insurance_id  = row.get('insurance_id')
            insurance_key = dim_keys['insurance'].get(str(insurance_id)) if pd.notna(insurance_id) else None

            if not all([patient_key, medication_key, doctor_key, pharmacy_key, date_key]):
                logger.debug(f"  Skipping {row.get('prescription_number')}: unresolved FK")
                skipped += 1
                continue

            records.append({
                'prescription_number':       row.get('prescription_number'),
                'transaction_date_key':      date_key,
                'patient_key':               patient_key,
                'medication_key':            medication_key,
                'doctor_key':                doctor_key,
                'pharmacy_key':              pharmacy_key,
                'insurance_key':             insurance_key,
                'prescription_type':         row.get('prescription_type'),
                'payment_method':            row.get('payment_method'),
                'dispensing_pharmacist_name': row.get('dispensing_pharmacist_name'),
                'quantity_dispensed':        int(float(row.get('quantity_dispensed', 0))),
                'unit_price':                float(row.get('unit_price', 0)),
                'total_amount':              float(row.get('total_amount', 0)),
                'cost_price':                float(row.get('cost_price', 0)) if pd.notna(row.get('cost_price')) else None,
                'insurance_coverage_amount': float(row.get('insurance_coverage_amount', 0)),
                'patient_copay':             float(row.get('patient_copay', 0)),
                'discount_amount':           float(row.get('discount_amount', 0)) if pd.notna(row.get('discount_amount')) else 0,
                'days_supply':               int(float(row.get('days_supply', 0))) if pd.notna(row.get('days_supply')) else None,
                'refills_remaining':         int(float(row.get('refills_remaining', 0))) if pd.notna(row.get('refills_remaining')) else None,
                'prescription_date':         row.get('prescription_date'),
                'dispensing_timestamp':      row.get('dispensing_timestamp'),
            })

        except Exception as e:
            logger.warning(f"  Row error: {e}")
            failed += 1

    if records:
        try:
            cur = conn.cursor()
            execute_batch(cur, """
                INSERT INTO dwh.fact_prescription_transactions (
                    prescription_number, transaction_date_key, patient_key,
                    medication_key, doctor_key, pharmacy_key, insurance_key,
                    prescription_type, payment_method, dispensing_pharmacist_name,
                    quantity_dispensed, unit_price, total_amount, cost_price,
                    insurance_coverage_amount, patient_copay, discount_amount,
                    days_supply, refills_remaining, prescription_date,
                    dispensing_timestamp
                ) VALUES (
                    %(prescription_number)s, %(transaction_date_key)s, %(patient_key)s,
                    %(medication_key)s, %(doctor_key)s, %(pharmacy_key)s, %(insurance_key)s,
                    %(prescription_type)s, %(payment_method)s, %(dispensing_pharmacist_name)s,
                    %(quantity_dispensed)s, %(unit_price)s, %(total_amount)s, %(cost_price)s,
                    %(insurance_coverage_amount)s, %(patient_copay)s, %(discount_amount)s,
                    %(days_supply)s, %(refills_remaining)s, %(prescription_date)s,
                    %(dispensing_timestamp)s
                )
                ON CONFLICT (prescription_number) DO NOTHING
            """, records, page_size=BATCH_SIZE)
            conn.commit()
            loaded = len(records)
            cur.close()
        except Exception as e:
            conn.rollback()
            logger.error(f"  Prescription batch insert failed: {e}")
            failed += len(records)

    conn.close()

    log_result = {'loaded': loaded, 'skipped': skipped, 'failed': failed}
    logger.info(f"  Prescriptions — loaded: {loaded:,}, skipped: {skipped:,}, failed: {failed:,}")
    return log_result


# ---------------------------------------------------------------------------
# Load patients (SCD Type 2)
# ---------------------------------------------------------------------------
def load_patients_scd2(df: pd.DataFrame) -> dict:
    """
    Insert new patients using SCD Type 2 logic:
      - New patients: insert with is_current=TRUE, effective_from=today
      - Existing patients with changes: expire old record, insert new version
      - Unchanged existing patients: skip
    """
    if df is None or df.empty:
        return {'loaded': 0, 'skipped': 0, 'failed': 0}

    conn = get_connection()
    loaded = skipped = failed = 0
    today = datetime.now().date()

    for _, row in df.iterrows():
        try:
            patient_id = str(row.get('patient_id', ''))
            cur = conn.cursor()

            # Check if patient already exists
            cur.execute("""
                SELECT patient_key, first_name, last_name, phone_number, has_medical_aid
                FROM dwh.dim_patient
                WHERE patient_id = %s AND is_current = TRUE
            """, (patient_id,))
            existing = cur.fetchone()

            if existing:
                # Check if anything material changed
                changed = (
                    str(existing[1]) != str(row.get('first_name', '')) or
                    str(existing[2]) != str(row.get('last_name', '')) or
                    str(existing[4]) != str(row.get('has_medical_aid', ''))
                )
                if not changed:
                    skipped += 1
                    cur.close()
                    continue

                # Expire old record (SCD Type 2)
                cur.execute("""
                    UPDATE dwh.dim_patient
                    SET is_current = FALSE,
                        effective_to = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE patient_key = %s
                """, (today, existing[0]))

            # Insert new/updated record
            cur.execute("""
                INSERT INTO dwh.dim_patient (
                    patient_id, title, first_name, last_name, date_of_birth, gender,
                    phone_number, email, address_line1, address_line2, suburb,
                    city, province, postal_code, primary_pharmacy_key,
                    patient_type, registration_date, is_chronic_patient,
                    has_medical_aid, preferred_contact_method, is_active,
                    is_current, effective_from
                ) VALUES (
                    %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                    (SELECT pharmacy_key FROM dwh.dim_pharmacy
                     WHERE is_active=TRUE ORDER BY RANDOM() LIMIT 1),
                    %s,%s,%s,%s,%s,TRUE,TRUE,%s
                )
            """, (
                patient_id,
                row.get('title'),
                row.get('first_name'),
                row.get('last_name'),
                row.get('date_of_birth'),
                row.get('gender'),
                row.get('phone_number'),
                row.get('email') if is_valid_email_simple(str(row.get('email', ''))) else None,
                row.get('address_line1'),
                row.get('address_line2'),
                row.get('suburb'),
                row.get('city', 'Johannesburg'),
                row.get('province', 'Gauteng'),
                row.get('postal_code'),
                row.get('patient_type', 'Regular'),
                row.get('registration_date'),
                row.get('is_chronic_patient', False),
                row.get('has_medical_aid', False),
                row.get('preferred_contact_method', 'Phone'),
                today,
            ))
            conn.commit()
            loaded += 1
            cur.close()

        except Exception as e:
            conn.rollback()
            logger.warning(f"  Patient {row.get('patient_id')} error: {e}")
            failed += 1

    conn.close()
    logger.info(f"  Patients (SCD2) — loaded: {loaded:,}, skipped: {skipped:,}, failed: {failed:,}")
    return {'loaded': loaded, 'skipped': skipped, 'failed': failed}


def is_valid_email_simple(email: str) -> bool:
    import re
    if not email or email == 'nan':
        return False
    return bool(re.match(r'^[^@]+@[^@]+\.[^@]+$', email))


# ---------------------------------------------------------------------------
# Load inventory snapshots
# ---------------------------------------------------------------------------
def load_inventory(df: pd.DataFrame, dim_keys: dict) -> dict:
    """Insert inventory snapshots with ON CONFLICT DO NOTHING (idempotent)."""
    if df is None or df.empty:
        return {'loaded': 0, 'skipped': 0, 'failed': 0}

    conn = get_connection()
    loaded = skipped = failed = 0
    records = []

    for _, row in df.iterrows():
        try:
            medication_key = dim_keys['medications'].get(str(row.get('medication_id', '')))
            pharmacy_key   = dim_keys['pharmacies'].get(str(row.get('pharmacy_id', '')))

            snapshot_ts = row.get('snapshot_timestamp', '')
            date_str    = str(snapshot_ts)[:10]
            date_key    = dim_keys['dates'].get(date_str)

            if not all([medication_key, pharmacy_key, date_key]):
                skipped += 1
                continue

            records.append({
                'snapshot_date_key':    date_key,
                'medication_key':       medication_key,
                'pharmacy_key':         pharmacy_key,
                'quantity_on_hand':     int(float(row.get('quantity_on_hand', 0))),
                'quantity_allocated':   int(float(row.get('quantity_allocated', 0))) if pd.notna(row.get('quantity_allocated')) else 0,
                'reorder_point':        int(float(row.get('reorder_point', 0))) if pd.notna(row.get('reorder_point')) else 0,
                'maximum_stock_level':  int(float(row.get('maximum_stock_level', 0))) if pd.notna(row.get('maximum_stock_level')) else 0,
                'stock_value_at_cost':  float(row.get('stock_value_at_cost', 0)) if pd.notna(row.get('stock_value_at_cost')) else 0,
                'stock_value_at_retail': float(row.get('stock_value_at_retail', 0)) if pd.notna(row.get('stock_value_at_retail')) else 0,
                'stock_status_code':    row.get('stock_status_code', 'OK'),
                'min_days_until_expiry': int(float(row.get('min_days_until_expiry', 0))) if pd.notna(row.get('min_days_until_expiry')) else None,
                'snapshot_timestamp':   snapshot_ts,
            })

        except Exception as e:
            logger.warning(f"  Inventory row error: {e}")
            failed += 1

    if records:
        try:
            cur = conn.cursor()
            execute_batch(cur, """
                INSERT INTO dwh.fact_inventory_snapshots (
                    snapshot_date_key, medication_key, pharmacy_key,
                    quantity_on_hand, quantity_allocated, reorder_point,
                    maximum_stock_level, stock_value_at_cost, stock_value_at_retail,
                    stock_status_code, min_days_until_expiry, snapshot_timestamp
                ) VALUES (
                    %(snapshot_date_key)s, %(medication_key)s, %(pharmacy_key)s,
                    %(quantity_on_hand)s, %(quantity_allocated)s, %(reorder_point)s,
                    %(maximum_stock_level)s, %(stock_value_at_cost)s, %(stock_value_at_retail)s,
                    %(stock_status_code)s, %(min_days_until_expiry)s, %(snapshot_timestamp)s
                )
                ON CONFLICT (snapshot_date_key, medication_key, pharmacy_key) DO NOTHING
            """, records, page_size=BATCH_SIZE)
            conn.commit()
            loaded = len(records)
            cur.close()
        except Exception as e:
            conn.rollback()
            logger.error(f"  Inventory batch insert failed: {e}")
            failed += len(records)

    conn.close()
    logger.info(f"  Inventory — loaded: {loaded:,}, skipped: {skipped:,}, failed: {failed:,}")
    return {'loaded': loaded, 'skipped': skipped, 'failed': failed}


# ---------------------------------------------------------------------------
# Main load entry point (called by Airflow PythonOperator)
# ---------------------------------------------------------------------------
def run_load(transformed: dict, dim_keys: dict,
             existing_rx_numbers: set, existing_patient_ids: set,
             run_date: str = None) -> dict:
    """
    Full load run across all transformed datasets.

    Returns summary of rows loaded/skipped/failed per stage.
    """
    logger.info("=" * 60)
    logger.info("LOAD STAGE STARTING")
    logger.info("=" * 60)

    if run_date is None:
        run_date = datetime.now().date().isoformat()

    conn = get_connection()
    ensure_metadata_table(conn)
    conn.close()

    results = {}
    started_at = datetime.now()

    if 'patients' in transformed:
        results['patients'] = load_patients_scd2(transformed['patients'])

    # Refresh patient keys after potential new inserts
    from python.etl.extract import extract_dimension_keys
    dim_keys = extract_dimension_keys()

    if 'prescriptions' in transformed:
        results['prescriptions'] = load_prescriptions(transformed['prescriptions'], dim_keys)

    if 'inventory' in transformed:
        results['inventory'] = load_inventory(transformed['inventory'], dim_keys)

    # Log summary to metadata table
    conn = get_connection()
    total_loaded  = sum(r.get('loaded', 0)  for r in results.values())
    total_skipped = sum(r.get('skipped', 0) for r in results.values())
    total_failed  = sum(r.get('failed', 0)  for r in results.values())

    log_pipeline_run(
        conn=conn,
        run_date=run_date,
        stage='full_etl',
        source_file=f"raw_data/{run_date}/",
        rows_extracted=0,
        rows_transformed=sum(len(df) for df in transformed.values()),
        rows_loaded=total_loaded,
        rows_skipped=total_skipped,
        rows_failed=total_failed,
        status='success' if total_failed == 0 else 'partial',
        started_at=started_at,
    )
    conn.close()

    logger.info("=" * 60)
    logger.info(f"LOAD STAGE COMPLETE — loaded: {total_loaded:,}, "
                f"skipped: {total_skipped:,}, failed: {total_failed:,}")
    logger.info("=" * 60)
    return results
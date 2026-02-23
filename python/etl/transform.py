"""
python/etl/transform.py
PharmaFlow Analytics — Transform Module

Cleans, validates, deduplicates, and applies business logic to raw
DataFrames produced by extract.py. Returns warehouse-ready DataFrames.

Handles all known data quality issues introduced by export_sample_files.py:
  - Duplicates (~5%)
  - Missing phone numbers / insurance IDs
  - Currency symbols in numeric fields (R prefix)
  - Outlier quantities (0, negative, 500+)
  - Invalid email formats
  - Inconsistent date formats
  - Type mismatches (numeric fields as strings)
"""

import re
import logging
from datetime import datetime, date
from typing import Optional

import pandas as pd
import numpy as np

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Generic utilities
# ---------------------------------------------------------------------------
def strip_currency(value: str) -> Optional[str]:
    """Remove R prefix and commas from currency strings. Returns None if unparseable."""
    if pd.isna(value) or value is None:
        return None
    cleaned = str(value).replace('R', '').replace(',', '').strip()
    try:
        float(cleaned)
        return cleaned
    except ValueError:
        return None


def parse_date_flexible(value: str) -> Optional[date]:
    """
    Parse dates in multiple formats:
      - YYYY-MM-DD (standard)
      - DD/MM/YYYY (SA format introduced as quality issue)
      - YYYY-MM-DD HH:MM:SS (timestamp)
    """
    if pd.isna(value) or not value:
        return None
    formats = ['%Y-%m-%d', '%d/%m/%Y', '%Y-%m-%d %H:%M:%S', '%d-%m-%Y']
    for fmt in formats:
        try:
            return datetime.strptime(str(value).strip(), fmt).date()
        except ValueError:
            continue
    logger.warning(f"  Could not parse date: {value}")
    return None


def is_valid_email(email: str) -> bool:
    """Basic email format validation."""
    if pd.isna(email) or not email:
        return False
    pattern = r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, str(email)))


def is_valid_sa_phone(phone: str) -> bool:
    """Validate SA phone number (allows +27 and 0 prefixed formats)."""
    if pd.isna(phone) or not phone:
        return False
    digits = re.sub(r'[\s\-\(\)]', '', str(phone))
    return bool(re.match(r'^(\+27|0)\d{9,10}$', digits))


def log_quality_report(stage: str, original: int, final: int, issues: dict):
    """Log a data quality summary for a transform stage."""
    logger.info(f"  [{stage}] {original:,} → {final:,} rows")
    for issue, count in issues.items():
        if count:
            logger.info(f"    {issue}: {count:,}")


# ---------------------------------------------------------------------------
# Prescription transforms
# ---------------------------------------------------------------------------
def transform_prescriptions(df: pd.DataFrame, existing_rx_numbers: set) -> pd.DataFrame:
    """
    Clean and validate prescription data.

    Fixes:
      1. Remove duplicates (on prescription_number)
      2. Strip currency symbols from total_amount
      3. Cast numeric columns
      4. Filter outlier quantities (<=0 or >365)
      5. Standardise prescription_type and payment_method values
      6. Parse prescription_date
      7. Remove already-loaded records (incremental dedup)
    """
    original_count = len(df)
    issues = {}

    # 1. Remove exact duplicates
    df = df.drop_duplicates()
    issues['exact_duplicates_removed'] = original_count - len(df)

    # Remove duplicate prescription numbers (keep first)
    before = len(df)
    df = df.drop_duplicates(subset=['prescription_number'], keep='first')
    issues['duplicate_rx_numbers_removed'] = before - len(df)

    # 2. Fix currency symbols in total_amount
    currency_mask = df['total_amount'].astype(str).str.startswith('R')
    issues['currency_format_errors_fixed'] = int(currency_mask.sum())
    df['total_amount'] = df['total_amount'].apply(strip_currency)

    # 3. Cast numeric columns
    numeric_cols = ['quantity_dispensed', 'unit_price', 'total_amount',
                    'patient_copay', 'insurance_coverage_amount']
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # 4. Filter outlier quantities
    before = len(df)
    df = df[df['quantity_dispensed'].notna()]
    df = df[(df['quantity_dispensed'] > 0) & (df['quantity_dispensed'] <= 365)]
    issues['outlier_quantities_removed'] = before - len(df)

    # 5. Standardise categorical values
    type_map = {'New': 'New', 'Refill': 'Refill', 'Emergency': 'Emergency'}
    df['prescription_type'] = df['prescription_type'].map(type_map)

    payment_map = {
        'Cash': 'Cash', 'Medical Aid': 'Medical_Aid',
        'Medical_Aid': 'Medical_Aid', 'Both': 'Both'
    }
    df['payment_method'] = df['payment_method'].map(payment_map)

    # 6. Parse dates
    df['prescription_date'] = df['prescription_date'].apply(parse_date_flexible)

    # 7. Drop records with missing critical fields
    before = len(df)
    df = df.dropna(subset=['prescription_number', 'prescription_date',
                            'patient_id', 'medication_id', 'quantity_dispensed'])
    issues['missing_critical_fields_dropped'] = before - len(df)

    # 8. Incremental dedup — remove already-loaded records
    before = len(df)
    df = df[~df['prescription_number'].isin(existing_rx_numbers)]
    issues['already_loaded_skipped'] = before - len(df)

    log_quality_report('prescriptions', original_count, len(df), issues)
    return df.reset_index(drop=True)


# ---------------------------------------------------------------------------
# Inventory transforms
# ---------------------------------------------------------------------------
def transform_inventory(df: pd.DataFrame) -> pd.DataFrame:
    """
    Clean inventory snapshot data.

    Fixes:
      1. Fix negative quantities (data errors)
      2. Handle missing stock_status_codes
      3. Fix pharmacy_id typos (trailing X)
      4. Cast numeric columns
      5. Standardise stock status codes
    """
    original_count = len(df)
    issues = {}

    # 1. Fix negative quantities — set to 0 (can't have negative stock)
    qty_col = 'quantity_on_hand'
    if qty_col in df.columns:
        df[qty_col] = pd.to_numeric(df[qty_col], errors='coerce').fillna(0)
        negative_mask = df[qty_col] < 0
        issues['negative_quantities_fixed'] = int(negative_mask.sum())
        df.loc[negative_mask, qty_col] = 0

    # 2. Fix pharmacy_id typos (trailing X added as quality issue)
    if 'pharmacy_id' in df.columns:
        typo_mask = df['pharmacy_id'].astype(str).str.endswith('X')
        issues['pharmacy_id_typos_fixed'] = int(typo_mask.sum())
        df.loc[typo_mask, 'pharmacy_id'] = df.loc[typo_mask, 'pharmacy_id'].str.rstrip('X')

    # 3. Fix missing stock_status_code — derive from quantities
    if 'stock_status_code' in df.columns:
        missing_status = df['stock_status_code'].isna()
        issues['missing_status_codes_derived'] = int(missing_status.sum())
        if missing_status.any() and 'reorder_point' in df.columns:
            df['reorder_point'] = pd.to_numeric(df['reorder_point'], errors='coerce').fillna(0)
            df.loc[missing_status & (df[qty_col] <= 0), 'stock_status_code'] = 'OUT'
            df.loc[missing_status & (df[qty_col] > 0) & \
                   (df[qty_col] <= df['reorder_point']), 'stock_status_code'] = 'LOW'
            df.loc[missing_status & (df[qty_col] > df['reorder_point']), 'stock_status_code'] = 'OK'

    # 4. Cast numeric columns
    numeric_cols = ['quantity_allocated', 'quantity_on_order', 'reorder_point',
                    'maximum_stock_level', 'stock_value_at_cost', 'stock_value_at_retail',
                    'min_days_until_expiry']
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # 5. Standardise status codes to known values
    valid_statuses = {'OUT', 'LOW', 'OK', 'NEAR_EXPIRY', 'OVERSTOCKED'}
    if 'stock_status_code' in df.columns:
        invalid_mask = ~df['stock_status_code'].isin(valid_statuses) & df['stock_status_code'].notna()
        df.loc[invalid_mask, 'stock_status_code'] = 'OK'

    log_quality_report('inventory', original_count, len(df), issues)
    return df.reset_index(drop=True)


# ---------------------------------------------------------------------------
# Patient transforms
# ---------------------------------------------------------------------------
def transform_patients(df: pd.DataFrame, existing_patient_ids: set) -> pd.DataFrame:
    """
    Clean patient registration data.

    Fixes:
      1. Fix invalid email formats (AT → @)
      2. Parse inconsistent date formats
      3. Validate phone numbers
      4. Remove already-registered patients (incremental)
      5. Cast boolean columns
    """
    original_count = len(df)
    issues = {}

    # 1. Fix invalid emails (AT substituted for @)
    if 'email' in df.columns:
        invalid_email_mask = df['email'].notna() & ~df['email'].apply(is_valid_email)
        issues['invalid_emails_fixed'] = int(invalid_email_mask.sum())
        df.loc[invalid_email_mask, 'email'] = df.loc[invalid_email_mask, 'email'].str.replace('AT', '@', regex=False)
        # Re-validate — set to None if still invalid after fix
        still_invalid = df['email'].notna() & ~df['email'].apply(is_valid_email)
        df.loc[still_invalid, 'email'] = None

    # 2. Parse dates
    if 'date_of_birth' in df.columns:
        df['date_of_birth'] = df['date_of_birth'].apply(parse_date_flexible)

    if 'registration_date' in df.columns:
        df['registration_date'] = df['registration_date'].apply(parse_date_flexible)

    # 3. Validate phone numbers — null out invalid ones
    if 'phone_number' in df.columns:
        invalid_phone = df['phone_number'].notna() & ~df['phone_number'].apply(is_valid_sa_phone)
        issues['invalid_phones_nulled'] = int(invalid_phone.sum())
        df.loc[invalid_phone, 'phone_number'] = None

    # 4. Cast booleans
    bool_map = {'True': True, 'False': False, 'true': True, 'false': False,
                '1': True, '0': False, True: True, False: False}
    for col in ['is_chronic_patient', 'has_medical_aid']:
        if col in df.columns:
            df[col] = df[col].map(bool_map)

    # 5. Drop records missing critical fields
    before = len(df)
    df = df.dropna(subset=['patient_id', 'first_name', 'last_name', 'date_of_birth'])
    issues['missing_critical_fields_dropped'] = before - len(df)

    # 6. Incremental dedup
    before = len(df)
    df = df[~df['patient_id'].isin(existing_patient_ids)]
    issues['already_registered_skipped'] = before - len(df)

    log_quality_report('patients', original_count, len(df), issues)
    return df.reset_index(drop=True)


# ---------------------------------------------------------------------------
# Medication transforms
# ---------------------------------------------------------------------------
def transform_medications(df: pd.DataFrame) -> pd.DataFrame:
    """
    Clean medication catalog data.

    Fixes:
      1. Cast numeric fields (stored as strings in quality issue)
      2. Cast boolean fields
      3. Validate schedule classifications
    """
    original_count = len(df)
    issues = {}

    # 1. Cast numeric columns
    numeric_cols = ['unit_cost_price', 'unit_retail_price', 'pack_size',
                    'typical_shelf_life_days']
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # 2. Cast booleans
    bool_map = {'True': True, 'False': False, 'true': True, 'false': False,
                '1': True, '0': False}
    for col in ['requires_prescription', 'is_controlled_substance']:
        if col in df.columns:
            df[col] = df[col].map(bool_map)

    # 3. Validate schedule classifications
    valid_schedules = {'S0', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8'}
    if 'schedule_classification' in df.columns:
        invalid_sched = ~df['schedule_classification'].isin(valid_schedules)
        issues['invalid_schedule_nulled'] = int(invalid_sched.sum())
        df.loc[invalid_sched, 'schedule_classification'] = None

    log_quality_report('medications', original_count, len(df), issues)
    return df.reset_index(drop=True)


# ---------------------------------------------------------------------------
# Business logic — derived metrics
# ---------------------------------------------------------------------------
def apply_prescription_business_logic(df: pd.DataFrame) -> pd.DataFrame:
    """
    Calculate derived metrics on prescription data:
      - profit_margin = total_amount - (cost_price * quantity_dispensed)
      - is_fully_covered = insurance_coverage_amount >= total_amount
      - discount_flag = discount_amount > 0
    """
    if 'total_amount' in df.columns and 'cost_price' in df.columns:
        df['profit_margin'] = (
            df['total_amount'] - (df['cost_price'].fillna(0) * df['quantity_dispensed'])
        ).round(2)

    if 'insurance_coverage_amount' in df.columns and 'total_amount' in df.columns:
        df['is_fully_covered'] = df['insurance_coverage_amount'] >= df['total_amount']

    if 'discount_amount' in df.columns:
        df['discount_flag'] = df['discount_amount'].fillna(0) > 0

    return df


def apply_inventory_business_logic(df: pd.DataFrame) -> pd.DataFrame:
    """
    Calculate derived inventory metrics:
      - gross_margin_pct per item
      - days_of_supply = quantity_on_hand / avg_daily_usage (estimated)
      - restock_urgency = HIGH / MEDIUM / LOW based on status
    """
    if 'stock_value_at_retail' in df.columns and 'stock_value_at_cost' in df.columns:
        cost = pd.to_numeric(df['stock_value_at_cost'], errors='coerce')
        retail = pd.to_numeric(df['stock_value_at_retail'], errors='coerce')
        df['gross_margin_pct'] = ((retail - cost) / retail.replace(0, np.nan) * 100).round(2)

    if 'stock_status_code' in df.columns:
        urgency_map = {'OUT': 'HIGH', 'LOW': 'HIGH', 'NEAR_EXPIRY': 'MEDIUM',
                       'OK': 'LOW', 'OVERSTOCKED': 'LOW'}
        df['restock_urgency'] = df['stock_status_code'].map(urgency_map).fillna('LOW')

    return df


# ---------------------------------------------------------------------------
# Main transform entry point (called by Airflow PythonOperator)
# ---------------------------------------------------------------------------
def run_transform(dataframes: dict, existing_rx_numbers: set,
                  existing_patient_ids: set) -> dict:
    """
    Full transform run across all extracted datasets.

    Args:
        dataframes:           output of extract.run_extract()
        existing_rx_numbers:  set of already-loaded prescription numbers
        existing_patient_ids: set of already-registered patient IDs

    Returns:
        dict of cleaned DataFrames ready for load stage
    """
    logger.info("=" * 60)
    logger.info("TRANSFORM STAGE STARTING")
    logger.info("=" * 60)

    transformed = {}

    if dataframes.get('prescriptions') is not None:
        df = transform_prescriptions(dataframes['prescriptions'], existing_rx_numbers)
        df = apply_prescription_business_logic(df)
        transformed['prescriptions'] = df

    if dataframes.get('inventory') is not None:
        df = transform_inventory(dataframes['inventory'])
        df = apply_inventory_business_logic(df)
        transformed['inventory'] = df

    if dataframes.get('patients') is not None:
        transformed['patients'] = transform_patients(
            dataframes['patients'], existing_patient_ids
        )

    if dataframes.get('medications') is not None:
        transformed['medications'] = transform_medications(dataframes['medications'])

    total_rows = sum(len(df) for df in transformed.values())
    logger.info(f"TRANSFORM STAGE COMPLETE — {total_rows:,} total rows ready for load")
    return transformed
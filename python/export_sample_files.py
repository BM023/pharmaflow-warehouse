"""
Export sample data files for ETL pipeline testing
Creates CSV, JSON, and Excel files with intentional data quality issues
"""

import os
from datetime import datetime, timedelta
import psycopg2
import pandas as pd
import json
import random
from dotenv import load_dotenv

load_dotenv()

random.seed(500)

DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5433'),
    'database': os.getenv('DB_NAME', 'pharmaflow_warehouse'),
    'user': os.getenv('DB_USER', 'pharmaflow'),
    'password': os.getenv('DB_PASSWORD', 'pharmaflow2024')
}


def get_database_connection():
    """Create database connection"""
    return psycopg2.connect(**DB_CONFIG)


def export_prescriptions_csv(output_folder, date_str):
    """
    Export prescription transactions to CSV with data quality issues
    """
    conn = get_database_connection()
    
    # Get prescriptions from the specified date
    query = f"""
        SELECT 
            f.prescription_number,
            f.prescription_date,
            f.dispensing_timestamp,
            p.patient_id,
            p.first_name,
            p.last_name,
            p.phone_number,
            m.medication_id,
            m.medication_name,
            f.quantity_dispensed,
            f.unit_price,
            f.total_amount,
            f.patient_copay,
            f.insurance_coverage_amount,
            d.doctor_id,
            d.first_name as doctor_first_name,
            d.last_name as doctor_last_name,
            ph.pharmacy_id,
            ph.location_name,
            i.insurance_id,
            i.provider_name,
            f.prescription_type,
            f.payment_method
        FROM dwh.fact_prescription_transactions f
        JOIN dwh.dim_patient p ON f.patient_key = p.patient_key
        JOIN dwh.dim_medication m ON f.medication_key = m.medication_key
        JOIN dwh.dim_doctor d ON f.doctor_key = d.doctor_key
        JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
        LEFT JOIN dwh.dim_insurance i ON f.insurance_key = i.insurance_key
        WHERE f.prescription_date = '{date_str}'
        ORDER BY f.dispensing_timestamp
        LIMIT 100
    """
    
    df = pd.read_sql(query, conn)
    conn.close()
    
    if len(df) == 0:
        print(f"  No prescriptions found for {date_str}, using recent data...")
        conn = get_database_connection()
        query = query.replace(f"WHERE f.prescription_date = '{date_str}'", 
                             "WHERE f.prescription_date >= CURRENT_DATE - INTERVAL '7 days'")
        df = pd.read_sql(query, conn)
        conn.close()
        df = df.head(100)
    
    # Introduce data quality issues
    print(f"  Original records: {len(df)}")
    
    # 1. Add duplicates (5%)
    num_duplicates = int(len(df) * 0.05)
    if num_duplicates > 0:
        duplicate_rows = df.sample(n=num_duplicates)
        df = pd.concat([df, duplicate_rows], ignore_index=True)
        print(f"  Added {num_duplicates} duplicate records")
    
    # 2. Add missing values (10% of phone numbers, 5% of insurance)
    missing_phone = int(len(df) * 0.10)
    missing_insurance = int(len(df) * 0.05)
    
    if missing_phone > 0:
        phone_indices = df.sample(n=missing_phone).index
        df.loc[phone_indices, 'phone_number'] = None
        print(f"  Added {missing_phone} missing phone numbers")
    
    if missing_insurance > 0:
        insurance_indices = df.sample(n=missing_insurance).index
        df.loc[insurance_indices, 'insurance_id'] = None
        df.loc[insurance_indices, 'provider_name'] = None
        print(f"  Added {missing_insurance} missing insurance records")
    
    # 3. Add incorrect formats (dates as strings, prices with currency symbols)
    format_errors = int(len(df) * 0.03)
    if format_errors > 0:
        error_indices = df.sample(n=format_errors).index
        # Convert column to object type first to allow mixed types
        df['total_amount'] = df['total_amount'].astype(str)
        for idx in error_indices:
            df.at[idx, 'total_amount'] = f"R{df.at[idx, 'total_amount']}"
        print(f"  Added {format_errors} format errors (currency symbols)")
    
    # 4. Add outliers (unrealistic quantities)
    outlier_count = int(len(df) * 0.02)
    if outlier_count > 0:
        outlier_indices = df.sample(n=outlier_count).index
        for idx in outlier_indices:
            df.at[idx, 'quantity_dispensed'] = random.choice([0, 500, 1000, -5])
        print(f"  Added {outlier_count} outliers (unrealistic quantities)")
    
    # 5. Shuffle rows
    df = df.sample(frac=1).reset_index(drop=True)
    
    # Export to CSV
    output_file = os.path.join(output_folder, f'prescriptions_{date_str}.csv')
    df.to_csv(output_file, index=False)
    print(f"  Exported to: {output_file}")
    print(f"  Final record count: {len(df)}")
    
    return len(df)


def export_medications_json(output_folder):
    """
    Export medication catalog to JSON format
    """
    conn = get_database_connection()
    
    query = """
        SELECT 
            m.medication_id,
            m.medication_name,
            m.generic_name,
            m.manufacturer,
            m.dosage_form,
            m.strength,
            m.pack_size,
            m.unit_of_measure,
            m.unit_cost_price,
            m.unit_retail_price,
            m.therapeutic_class,
            m.schedule_classification,
            m.requires_prescription,
            m.is_controlled_substance,
            m.storage_requirements,
            m.typical_shelf_life_days,
            c.clinical_category,
            c.movement_class
        FROM dwh.dim_medication m
        JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
        WHERE m.is_active = TRUE AND m.is_current = TRUE
    """
    
    df = pd.read_sql(query, conn)
    conn.close()
    
    print(f"  Original records: {len(df)}")
    
    # Convert to list of dictionaries
    medications = df.to_dict('records')
    
    # Introduce data quality issues
    # 1. Add malformed records (missing required fields)
    malformed_count = 3
    for i in range(malformed_count):
        bad_record = medications[i].copy()
        # Remove critical fields
        bad_record.pop('medication_id', None)
        bad_record.pop('medication_name', None)
        medications.append(bad_record)
    print(f"  Added {malformed_count} malformed records (missing IDs/names)")
    
    # 2. Add inconsistent data types
    type_errors = 5
    for i in range(type_errors):
        medications[i]['unit_cost_price'] = str(medications[i]['unit_cost_price'])
        medications[i]['pack_size'] = str(medications[i]['pack_size'])
    print(f"  Added {type_errors} type inconsistencies")
    
    # Export to JSON
    output_file = os.path.join(output_folder, 'medication_catalog.json')
    with open(output_file, 'w') as f:
        json.dump(medications, f, indent=2, default=str)
    
    print(f"  Exported to: {output_file}")
    print(f"  Final record count: {len(medications)}")
    
    return len(medications)


def export_inventory_excel(output_folder, date_str):
    """
    Export inventory snapshot to Excel with data quality issues
    """
    conn = get_database_connection()
    
    query = f"""
        SELECT 
            ph.pharmacy_id,
            ph.location_name,
            m.medication_id,
            m.medication_name,
            f.quantity_on_hand,
            f.quantity_allocated,
            f.reorder_point,
            f.maximum_stock_level,
            f.stock_value_at_cost,
            f.stock_value_at_retail,
            f.stock_status_code,
            f.min_days_until_expiry,
            f.snapshot_timestamp
        FROM dwh.fact_inventory_snapshots f
        JOIN dwh.dim_medication m ON f.medication_key = m.medication_key
        JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
        WHERE f.snapshot_date_key = {date_str.replace('-', '')}
    """
    
    df = pd.read_sql(query, conn)
    conn.close()
    
    if len(df) == 0:
        print(f"  No inventory data for {date_str}, using latest snapshot...")
        conn = get_database_connection()
        query = """
            SELECT 
                ph.pharmacy_id,
                ph.location_name,
                m.medication_id,
                m.medication_name,
                f.quantity_on_hand,
                f.quantity_allocated,
                f.reorder_point,
                f.maximum_stock_level,
                f.stock_value_at_cost,
                f.stock_value_at_retail,
                f.stock_status_code,
                f.min_days_until_expiry,
                f.snapshot_timestamp
            FROM dwh.fact_inventory_snapshots f
            JOIN dwh.dim_medication m ON f.medication_key = m.medication_key
            JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
            WHERE f.snapshot_date_key = (SELECT MAX(snapshot_date_key) FROM dwh.fact_inventory_snapshots)
        """
        df = pd.read_sql(query, conn)
        conn.close()
    
    print(f"  Original records: {len(df)}")
    
    # Introduce data quality issues
    # 1. Add negative quantities (data errors)
    negative_count = int(len(df) * 0.02)
    if negative_count > 0:
        neg_indices = df.sample(n=negative_count).index
        for idx in neg_indices:
            df.at[idx, 'quantity_on_hand'] = -abs(df.at[idx, 'quantity_on_hand'])
        print(f"  Added {negative_count} negative quantity errors")
    
    # 2. Add missing stock status codes
    missing_status = int(len(df) * 0.05)
    if missing_status > 0:
        status_indices = df.sample(n=missing_status).index
        df.loc[status_indices, 'stock_status_code'] = None
        print(f"  Added {missing_status} missing status codes")
    
    # 3. Add inconsistent pharmacy IDs (typos)
    typo_count = int(len(df) * 0.03)
    if typo_count > 0:
        typo_indices = df.sample(n=typo_count).index
        for idx in typo_indices:
            original = df.at[idx, 'pharmacy_id']
            df.at[idx, 'pharmacy_id'] = original + 'X'  # Add typo
        print(f"  Added {typo_count} pharmacy ID typos")
    
    # Export to Excel
    output_file = os.path.join(output_folder, f'inventory_snapshot_{date_str}.xlsx')
    
    # Create Excel writer with multiple sheets
    with pd.ExcelWriter(output_file, engine='openpyxl') as writer:
        # Main inventory sheet
        df.to_excel(writer, sheet_name='Inventory', index=False)
        
        # Summary sheet
        summary = df.groupby('location_name').agg({
            'quantity_on_hand': 'sum',
            'stock_value_at_retail': 'sum'
        }).reset_index()
        summary.to_excel(writer, sheet_name='Summary', index=False)
    
    print(f"  Exported to: {output_file}")
    print(f"  Final record count: {len(df)}")
    
    return len(df)


def export_patients_csv(output_folder):
    """
    Export new patient registrations to CSV
    """
    conn = get_database_connection()
    
    # Get recent patient registrations
    query = """
        SELECT 
            patient_id,
            title,
            first_name,
            last_name,
            date_of_birth,
            gender,
            phone_number,
            email,
            address_line1,
            suburb,
            city,
            postal_code,
            registration_date,
            is_chronic_patient,
            has_medical_aid
        FROM dwh.dim_patient
        WHERE registration_date >= CURRENT_DATE - INTERVAL '30 days'
        AND is_current = TRUE
        LIMIT 50
    """
    
    df = pd.read_sql(query, conn)
    conn.close()
    
    if len(df) == 0:
        # Get any 50 patients
        conn = get_database_connection()
        query = query.replace("WHERE registration_date >= CURRENT_DATE - INTERVAL '30 days'", "")
        df = pd.read_sql(query, conn)
        conn.close()
        df = df.head(50)
    
    print(f"  Original records: {len(df)}")
    
    # Introduce data quality issues
    # 1. Invalid email formats
    email_errors = int(len(df) * 0.10)
    if email_errors > 0:
        email_indices = df[df['email'].notna()].sample(n=min(email_errors, len(df[df['email'].notna()]))).index
        for idx in email_indices:
            df.at[idx, 'email'] = df.at[idx, 'email'].replace('@', 'AT')  # Invalid format
        print(f"  Added {len(email_indices)} invalid email formats")
    
    # 2. Inconsistent date formats
    date_errors = int(len(df) * 0.05)
    if date_errors > 0:
        date_indices = df.sample(n=date_errors).index
        for idx in date_indices:
            # Convert to different format
            original_date = df.at[idx, 'date_of_birth']
            df.at[idx, 'date_of_birth'] = original_date.strftime('%d/%m/%Y')
        print(f"  Added {date_errors} inconsistent date formats")
    
    # Export
    output_file = os.path.join(output_folder, 'new_patients.csv')
    df.to_csv(output_file, index=False)
    
    print(f"  Exported to: {output_file}")
    print(f"  Final record count: {len(df)}")
    
    return len(df)


def create_readme(output_folder):
    """Create README file explaining the data"""
    readme_content = """# PharmaFlow Sample Data Files

This folder contains sample data files for testing the ETL pipeline.

## Files Generated:

### CSV Files:
- **prescriptions_YYYY-MM-DD.csv**: Daily prescription transactions
  - Contains patient, medication, doctor, and payment information
  - Intentional issues: duplicates, missing values, format errors, outliers

- **new_patients.csv**: New patient registrations
  - Contains patient demographic and contact information
  - Intentional issues: invalid emails, inconsistent date formats

### JSON Files:
- **medication_catalog.json**: Complete medication catalog
  - Contains medication details, pricing, and classifications
  - Intentional issues: missing IDs, type inconsistencies

### Excel Files:
- **inventory_snapshot_YYYY-MM-DD.xlsx**: Daily inventory levels
  - Sheet 1: Full inventory by medication and pharmacy
  - Sheet 2: Summary by pharmacy
  - Intentional issues: negative quantities, missing status codes, ID typos

## Data Quality Issues (Intentional):

These files contain intentional data quality issues to test your ETL pipeline:

1. **Duplicates**: ~5% duplicate records in prescription data
2. **Missing Values**: 5-10% missing phone numbers, insurance IDs
3. **Format Errors**: Currency symbols in numeric fields, inconsistent date formats
4. **Outliers**: Unrealistic quantities (0, negative, extremely high)
5. **Type Errors**: Numeric fields stored as strings
6. **Invalid Data**: Malformed emails, typos in IDs

## ETL Pipeline Tasks:

Your pipeline should:
- Detect and remove duplicates
- Handle missing values appropriately
- Standardize formats (dates, currency, etc.)
- Validate data ranges and identify outliers
- Transform data types correctly
- Clean and validate all fields before loading

Generated: """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """
"""
    
    readme_file = os.path.join(output_folder, 'README.md')
    with open(readme_file, 'w') as f:
        f.write(readme_content)
    
    print(f"  Created README: {readme_file}")


def main():
    print("=" * 70)
    print("PHARMAFLOW ANALYTICS - SAMPLE DATA FILE GENERATOR")
    print("=" * 70)
    
    # Export for today
    today = datetime.now().date()
    today_str = today.strftime('%Y-%m-%d')
    today_folder = f'raw_data/{today_str}'
    
    os.makedirs(today_folder, exist_ok=True)
    
    print(f"\nGenerating sample files for {today_str}...")
    print(f"Output folder: {today_folder}\n")
    
    # Export different file formats
    print("1. Exporting prescriptions to CSV...")
    rx_count = export_prescriptions_csv(today_folder, str(today))
    
    print("\n2. Exporting medication catalog to JSON...")
    med_count = export_medications_json(today_folder)
    
    print("\n3. Exporting inventory to Excel...")
    inv_count = export_inventory_excel(today_folder, today_str)
    
    print("\n4. Exporting new patients to CSV...")
    pat_count = export_patients_csv(today_folder)
    
    print("\n5. Creating README...")
    create_readme(today_folder)
    
    # Export for yesterday (for testing)
    yesterday = today - timedelta(days=1)
    yesterday_str = yesterday.strftime('%Y-%m-%d')
    yesterday_folder = f'raw_data/{yesterday_str}'
    
    os.makedirs(yesterday_folder, exist_ok=True)
    
    print(f"\n\nGenerating sample files for {yesterday_str} (for testing)...")
    export_prescriptions_csv(yesterday_folder, str(yesterday))
    export_medications_json(yesterday_folder)
    export_inventory_excel(yesterday_folder, yesterday_str)
    
    print("\n" + "=" * 70)
    print("SAMPLE DATA FILE GENERATION COMPLETE!")
    print("=" * 70)
    print(f"\nFiles created in:")
    print(f"  - {today_folder}/")
    print(f"  - {yesterday_folder}/")
    print(f"\nNext steps:")
    print(f"  1. Review the generated files")
    print(f"  2. Note the intentional data quality issues")
    print(f"  3. Build ETL pipeline to clean and load this data")


if __name__ == "__main__":
    main()
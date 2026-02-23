"""
Generate realistic prescription transaction data
Links patients, doctors, medications, pharmacies, and insurance
Generates 5000+ transactions over the past 6 months
"""

import os
from faker import Faker
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_batch
import random
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

fake = Faker('en_US')
Faker.seed(100)
random.seed(100)

# Database connection
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5433'),
    'database': os.getenv('DB_NAME', 'pharmaflow_warehouse'),
    'user': os.getenv('DB_USER', 'pharmaflow'),
    'password': os.getenv('DB_PASSWORD', 'pharmaflow2024')
}

PRESCRIPTION_TYPES = ['New', 'Refill', 'Emergency']
PAYMENT_METHODS = ['Cash', 'Medical_Aid', 'Both']


def get_reference_data():
    """Fetch reference data from dimension tables"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    print("Fetching reference data from database...")
    
    # Get patients with their details
    cur.execute("""
        SELECT 
            patient_key, 
            primary_pharmacy_key, 
            is_chronic_patient, 
            has_medical_aid,
            age_group
        FROM dwh.dim_patient 
        WHERE is_active = TRUE AND is_current = TRUE
    """)
    patients = [{'key': r[0], 'pharmacy': r[1], 'chronic': r[2], 'medical_aid': r[3], 'age_group': r[4]} 
                for r in cur.fetchall()]
    
    # Get medications with their details
    cur.execute("""
        SELECT 
            m.medication_key,
            m.unit_cost_price,
            m.unit_retail_price,
            m.requires_prescription,
            m.is_controlled_substance,
            m.is_seasonal,
            m.seasonal_peak_months,
            c.clinical_category
        FROM dwh.dim_medication m
        JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
        WHERE m.is_active = TRUE AND m.is_current = TRUE
    """)
    medications = [{'key': r[0], 'cost': r[1], 'retail': r[2], 'rx_required': r[3], 
                   'controlled': r[4], 'seasonal': r[5], 'peak_months': r[6], 'category': r[7]} 
                   for r in cur.fetchall()]
    
    # Get doctors
    cur.execute("""
        SELECT doctor_key, specialty 
        FROM dwh.dim_doctor 
        WHERE is_active = TRUE
    """)
    doctors = [{'key': r[0], 'specialty': r[1]} for r in cur.fetchall()]
    
    # Get pharmacies
    cur.execute("""
        SELECT pharmacy_key, location_name 
        FROM dwh.dim_pharmacy 
        WHERE is_active = TRUE
    """)
    pharmacies = [{'key': r[0], 'name': r[1]} for r in cur.fetchall()]
    
    # Get insurance schemes
    cur.execute("""
        SELECT 
            insurance_key, 
            default_coverage_percentage,
            default_copay_amount
        FROM dwh.dim_insurance 
        WHERE is_active = TRUE
    """)
    insurance = [{'key': r[0], 'coverage': float(r[1]), 'copay': float(r[2]) if r[2] else 0} 
                 for r in cur.fetchall()]
    
    cur.close()
    conn.close()
    
    print(f"  ✓ Loaded {len(patients)} patients")
    print(f"  ✓ Loaded {len(medications)} medications")
    print(f"  ✓ Loaded {len(doctors)} doctors")
    print(f"  ✓ Loaded {len(pharmacies)} pharmacies")
    print(f"  ✓ Loaded {len(insurance)} insurance schemes")
    
    return patients, medications, doctors, pharmacies, insurance


def get_date_key(date):
    """Convert date to date_key format (YYYYMMDD)"""
    return int(date.strftime('%Y%m%d'))


def select_medication_by_patient(patient, medications, current_month):
    """Select appropriate medication based on patient characteristics and season"""
    
    # Filter medications based on patient type
    if patient['chronic']:
        # Chronic patients get chronic medications
        suitable_meds = [m for m in medications if m['category'] == 'Chronic']
    else:
        # Non-chronic patients get regular, acute, or seasonal
        suitable_meds = [m for m in medications if m['category'] in ['Regular', 'Acute', 'Seasonal']]
    
    # Consider seasonal medications
    seasonal_boost = []
    for med in suitable_meds:
        if med['seasonal'] and med['peak_months']:
            peak_months = [int(m) for m in med['peak_months'].split(',')]
            if current_month in peak_months:
                seasonal_boost.extend([med] * 3)  # Triple the chance during peak season
    
    suitable_meds.extend(seasonal_boost)
    
    if not suitable_meds:
        suitable_meds = medications  # Fallback
    
    return random.choice(suitable_meds)


def generate_prescription_transactions(patients, medications, doctors, pharmacies, insurance, num_transactions=5000):
    """Generate prescription transactions"""
    
    transactions = []
    prescription_counter = 1
    
    # Generate transactions over past 6 months
    start_date = datetime.now().date() - timedelta(days=180)
    end_date = datetime.now().date()
    
    print(f"\nGenerating {num_transactions} prescription transactions...")
    print(f"Date range: {start_date} to {end_date}")
    
    # Weight transactions towards recent dates (more recent = more transactions)
    date_weights = []
    current_date = start_date
    while current_date <= end_date:
        # More transactions on weekdays
        weight = 3 if current_date.weekday() < 5 else 1
        date_weights.append((current_date, weight))
        current_date += timedelta(days=1)
    
    for i in range(num_transactions):
        # Select weighted random date
        transaction_date = random.choices(
            [d[0] for d in date_weights],
            weights=[d[1] for d in date_weights],
            k=1
        )[0]
        
        current_month = transaction_date.month
        
        # Select patient
        patient = random.choice(patients)
        
        # Patient's primary pharmacy (70% of time) or another pharmacy
        if random.random() < 0.70 and patient['pharmacy']:
            pharmacy = next((p for p in pharmacies if p['key'] == patient['pharmacy']), random.choice(pharmacies))
        else:
            pharmacy = random.choice(pharmacies)
        
        # Select appropriate medication
        medication = select_medication_by_patient(patient, medications, current_month)
        
        # Select doctor
        # Chronic patients tend to see GPs, others see various doctors
        if patient['chronic']:
            gp_doctors = [d for d in doctors if d['specialty'] == 'General_Practitioner']
            doctor = random.choice(gp_doctors) if gp_doctors else random.choice(doctors)
        else:
            doctor = random.choice(doctors)
        
        # Prescription type
        if patient['chronic']:
            # Chronic patients mostly get refills
            prescription_type = random.choices(
                PRESCRIPTION_TYPES,
                weights=[0.10, 0.85, 0.05],
                k=1
            )[0]
        else:
            # Non-chronic mostly new prescriptions
            prescription_type = random.choices(
                PRESCRIPTION_TYPES,
                weights=[0.75, 0.20, 0.05],
                k=1
            )[0]
        
        # Quantity (realistic based on medication type and patient)
        if patient['chronic']:
            quantity = random.choice([28, 30, 60, 90])  # Monthly or 3-month supply
            days_supply = quantity
        else:
            quantity = random.choice([7, 10, 14, 21, 28])
            days_supply = quantity
        
        # Pricing
        unit_price = float(medication['retail'])
        cost_price = float(medication['cost'])
        total_amount = unit_price * quantity
        
        # Insurance and payment
        if patient['medical_aid']:
            insurance_scheme = random.choice(insurance)
            insurance_key = insurance_scheme['key']
            coverage_pct = insurance_scheme['coverage'] / 100.0
            insurance_coverage = round(total_amount * coverage_pct, 2)
            patient_copay = round(total_amount - insurance_coverage, 2)
            discount_amount = 0.00
            payment_method = 'Medical_Aid'
        else:
            insurance_key = None
            insurance_coverage = 0.00
            # Cash patients sometimes get discount
            if random.random() < 0.15:
                discount_pct = random.choice([0.05, 0.10, 0.15])
                discount_amount = round(total_amount * discount_pct, 2)
                patient_copay = round(total_amount - discount_amount, 2)
            else:
                discount_amount = 0.00
                patient_copay = total_amount
            payment_method = 'Cash'
        
        # Round to avoid floating point issues
        total_amount = insurance_coverage + patient_copay + discount_amount
        
        # Refills
        if prescription_type == 'Refill':
            refills_remaining = random.choice([0, 1, 2, 3, 5])
        else:
            refills_remaining = random.choice([0, 1, 2, 3, 5, 11])  # 0 or up to 11 refills
        
        # Prescription and dispensing timestamps
        prescription_date = transaction_date
        dispensing_time = datetime.combine(
            transaction_date,
            datetime.min.time().replace(
                hour=random.randint(8, 18),
                minute=random.randint(0, 59)
            )
        )
        
        # Pharmacist name
        pharmacist_names = [
            'Sarah Nkosi', 'John Maseko', 'David Chen', 'Precious Dlamini',
            'Michael van Wyk', 'Lerato Mahlangu', 'Zanele Sithole',
            'Thandi Ndlovu', 'Ahmed Patel', 'Lisa Robertson'
        ]
        
        transaction = {
            'prescription_number': f'RX-{prescription_counter:07d}',
            'transaction_date_key': get_date_key(transaction_date),
            'patient_key': patient['key'],
            'medication_key': medication['key'],
            'doctor_key': doctor['key'],
            'pharmacy_key': pharmacy['key'],
            'insurance_key': insurance_key,
            'prescription_type': prescription_type,
            'payment_method': payment_method,
            'dispensing_pharmacist_name': random.choice(pharmacist_names),
            'quantity_dispensed': quantity,
            'unit_price': unit_price,
            'total_amount': total_amount,
            'cost_price': cost_price,
            'insurance_coverage_amount': insurance_coverage,
            'patient_copay': patient_copay,
            'discount_amount': discount_amount,
            'days_supply': days_supply,
            'refills_remaining': refills_remaining,
            'prescription_date': prescription_date,
            'dispensing_timestamp': dispensing_time
        }
        
        transactions.append(transaction)
        prescription_counter += 1
        
        if (i + 1) % 500 == 0:
            print(f"  Generated {i + 1}/{num_transactions} transactions...")
    
    return transactions


def insert_transactions(transactions):
    """Insert transactions into database"""
    
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    insert_query = """
        INSERT INTO dwh.fact_prescription_transactions (
            prescription_number, transaction_date_key, patient_key, medication_key,
            doctor_key, pharmacy_key, insurance_key, prescription_type, payment_method,
            dispensing_pharmacist_name, quantity_dispensed, unit_price, total_amount,
            cost_price, insurance_coverage_amount, patient_copay, discount_amount,
            days_supply, refills_remaining, prescription_date, dispensing_timestamp
        ) VALUES (
            %(prescription_number)s, %(transaction_date_key)s, %(patient_key)s, %(medication_key)s,
            %(doctor_key)s, %(pharmacy_key)s, %(insurance_key)s, %(prescription_type)s, %(payment_method)s,
            %(dispensing_pharmacist_name)s, %(quantity_dispensed)s, %(unit_price)s, %(total_amount)s,
            %(cost_price)s, %(insurance_coverage_amount)s, %(patient_copay)s, %(discount_amount)s,
            %(days_supply)s, %(refills_remaining)s, %(prescription_date)s, %(dispensing_timestamp)s
        )
    """
    
    try:
        print(f"\nInserting {len(transactions)} transactions into database...")
        execute_batch(cur, insert_query, transactions, page_size=500)
        conn.commit()
        print(f"✓ Successfully inserted {len(transactions)} transactions!")
        
        # Show statistics
        cur.execute("""
            SELECT 
                COUNT(*) as total_transactions,
                SUM(total_amount) as total_revenue,
                AVG(total_amount) as avg_transaction,
                SUM(profit_margin) as total_profit
            FROM dwh.fact_prescription_transactions
        """)
        stats = cur.fetchone()
        print(f"\nTransaction Statistics:")
        print(f"  Total Transactions: {stats[0]:,}")
        print(f"  Total Revenue: R {stats[1]:,.2f}")
        print(f"  Average Transaction: R {stats[2]:,.2f}")
        print(f"  Total Profit: R {stats[3]:,.2f}")
        
        # Prescription type distribution
        cur.execute("""
            SELECT prescription_type, COUNT(*) as count
            FROM dwh.fact_prescription_transactions
            GROUP BY prescription_type
            ORDER BY count DESC
        """)
        print(f"\nPrescription Type Distribution:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,}")
        
        # Payment method distribution
        cur.execute("""
            SELECT payment_method, COUNT(*) as count
            FROM dwh.fact_prescription_transactions
            GROUP BY payment_method
            ORDER BY count DESC
        """)
        print(f"\nPayment Method Distribution:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,}")
        
        # Top 5 medications
        cur.execute("""
            SELECT 
                m.medication_name,
                COUNT(*) as prescription_count,
                SUM(f.total_amount) as revenue
            FROM dwh.fact_prescription_transactions f
            JOIN dwh.dim_medication m ON f.medication_key = m.medication_key
            GROUP BY m.medication_name
            ORDER BY prescription_count DESC
            LIMIT 5
        """)
        print(f"\nTop 5 Prescribed Medications:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,} prescriptions (R {row[2]:,.2f})")
        
    except Exception as e:
        conn.rollback()
        print(f"✗ Error inserting transactions: {e}")
        raise
    finally:
        cur.close()
        conn.close()


def main():
    """Main execution"""
    print("=" * 70)
    print("PHARMAFLOW ANALYTICS - PRESCRIPTION TRANSACTION GENERATOR")
    print("=" * 70)
    
    # Get reference data
    patients, medications, doctors, pharmacies, insurance = get_reference_data()
    
    # Generate transactions
    transactions = generate_prescription_transactions(
        patients, medications, doctors, pharmacies, insurance,
        num_transactions=5000
    )
    
    # Insert into database
    insert_transactions(transactions)
    
    print("\n" + "=" * 70)
    print("PRESCRIPTION TRANSACTION GENERATION COMPLETE!")
    print("=" * 70)


if __name__ == "__main__":
    main()
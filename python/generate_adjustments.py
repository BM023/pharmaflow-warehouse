"""
Generate stock adjustment data
Creates records of inventory adjustments (expired, damaged, corrections, etc.)
"""

import os
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_batch
import random
from dotenv import load_dotenv

load_dotenv()

random.seed(400)

DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5433'),
    'database': os.getenv('DB_NAME', 'pharmaflow_warehouse'),
    'user': os.getenv('DB_USER', 'pharmaflow'),
    'password': os.getenv('DB_PASSWORD', 'pharmaflow2024')
}


def get_date_key(date):
    """Convert date to date_key format (YYYYMMDD)"""
    return int(date.strftime('%Y%m%d'))


def get_reference_data():
    """Fetch medications and pharmacies"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    print("Fetching reference data...")
    
    # Get medications with pricing
    cur.execute("""
        SELECT 
            m.medication_key,
            m.medication_name,
            m.unit_cost_price,
            m.dosage_form,
            c.clinical_category
        FROM dwh.dim_medication m
        JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
        WHERE m.is_active = TRUE AND m.is_current = TRUE
    """)
    medications = [
        {
            'key': r[0], 'name': r[1], 'cost': float(r[2]),
            'form': r[3], 'category': r[4]
        }
        for r in cur.fetchall()
    ]
    
    # Get pharmacies
    cur.execute("""
        SELECT pharmacy_key, location_name
        FROM dwh.dim_pharmacy
        WHERE is_active = TRUE
    """)
    pharmacies = [{'key': r[0], 'name': r[1]} for r in cur.fetchall()]
    
    cur.close()
    conn.close()
    
    print(f"  Loaded {len(medications)} medications")
    print(f"  Loaded {len(pharmacies)} pharmacies")
    
    return medications, pharmacies


def generate_batch_number():
    """Generate realistic batch number"""
    return f"BATCH{random.randint(100000, 999999)}"


def generate_adjustments(medications, pharmacies, num_adjustments=200):
    """Generate stock adjustment records"""
    
    adjustments = []
    adjustment_counter = 1
    
    # Adjustment types with probabilities
    adjustment_types = [
        ('Expired_Disposal', 0.35),      # Most common - expired meds
        ('Damaged', 0.20),               # Damaged packaging/product
        ('Count_Correction', 0.15),      # Inventory count discrepancies
        ('Theft', 0.05),                 # Theft/loss
        ('Return_to_Supplier', 0.10),    # Quality issues returned
        ('Transfer_Out', 0.075),         # Transfer to another pharmacy
        ('Transfer_In', 0.075)           # Receive from another pharmacy
    ]
    
    # Generate adjustments over past 60 days
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=60)
    
    print(f"\nGenerating {num_adjustments} stock adjustments...")
    print(f"Date range: {start_date} to {end_date}")
    
    for i in range(num_adjustments):
        # Random adjustment date
        days_ago = random.randint(0, 60)
        adjustment_date = end_date - timedelta(days=days_ago)
        
        # Select medication
        medication = random.choice(medications)
        
        # Select pharmacy
        pharmacy = random.choice(pharmacies)
        
        # Select adjustment type (weighted)
        adjustment_type = random.choices(
            [t[0] for t in adjustment_types],
            weights=[t[1] for t in adjustment_types],
            k=1
        )[0]
        
        # Generate quantity adjusted (negative for removals, positive for additions)
        if adjustment_type in ['Expired_Disposal', 'Damaged', 'Theft']:
            # Removals (negative)
            if medication['form'] in ['Liquid', 'Cream', 'Spray']:
                # Liquids usually disposed in smaller quantities
                quantity = -random.randint(1, 10)
            else:
                # Tablets/capsules
                quantity = -random.randint(5, 50)
        
        elif adjustment_type == 'Count_Correction':
            # Can be positive or negative
            quantity = random.randint(-20, 20)
        
        elif adjustment_type == 'Return_to_Supplier':
            # Negative (returning stock)
            quantity = -random.randint(10, 100)
        
        elif adjustment_type == 'Transfer_Out':
            # Negative (sending to another pharmacy)
            quantity = -random.randint(10, 50)
        
        elif adjustment_type == 'Transfer_In':
            # Positive (receiving from another pharmacy)
            quantity = random.randint(10, 50)
        
        # Adjustment reason
        reasons = {
            'Expired_Disposal': [
                'Product expired - disposed as per protocol',
                'Batch expiry date reached',
                'Expired medication found during stock check'
            ],
            'Damaged': [
                'Damaged packaging during handling',
                'Product integrity compromised',
                'Broken tablets/damaged units',
                'Water damage to stock'
            ],
            'Count_Correction': [
                'Discrepancy found during cycle count',
                'Annual stock take adjustment',
                'System vs physical count mismatch',
                'Reconciliation adjustment'
            ],
            'Theft': [
                'Stock shortage identified',
                'Suspected theft',
                'Security incident'
            ],
            'Return_to_Supplier': [
                'Quality issue - returned to supplier',
                'Wrong product delivered',
                'Damaged on arrival',
                'Near expiry - returned for credit'
            ],
            'Transfer_Out': [
                'Stock transfer to sister branch',
                'Emergency stock request from another pharmacy',
                'Rebalancing inventory across locations'
            ],
            'Transfer_In': [
                'Stock received from sister branch',
                'Emergency stock transfer received',
                'Inventory rebalancing'
            ]
        }
        
        adjustment_reason = random.choice(reasons[adjustment_type])
        
        # Cost impact (quantity × cost)
        cost_impact = round(abs(quantity) * medication['cost'], 2)
        
        # Make negative for losses
        if quantity < 0:
            cost_impact = -cost_impact
        
        # Batch number (if applicable)
        batch_number = generate_batch_number() if random.random() > 0.3 else None
        
        # Performed by (staff names)
        staff_members = [
            'Sarah Nkosi', 'John Maseko', 'David Chen', 'Precious Dlamini',
            'Michael van Wyk', 'Lerato Mahlangu', 'Zanele Sithole',
            'Thandi Ndlovu', 'Ahmed Patel', 'Lisa Robertson'
        ]
        performed_by = random.choice(staff_members)
        
        # Approved by (for significant adjustments)
        if abs(cost_impact) > 500:
            approved_by = random.choice([
                'Manager: Thandi Ndlovu',
                'Manager: Sipho Mokoena',
                'Manager: Nomsa Khumalo',
                'Manager: Lerato Mahlangu',
                'Manager: Zanele Sithole'
            ])
            # Approval timestamp (a few hours after adjustment)
            approval_delay = random.randint(1, 8)
            approval_timestamp = datetime.combine(
                adjustment_date,
                datetime.min.time().replace(hour=random.randint(10, 17))
            ) + timedelta(hours=approval_delay)
        else:
            approved_by = None
            approval_timestamp = None
        
        # Adjustment timestamp
        adjustment_timestamp = datetime.combine(
            adjustment_date,
            datetime.min.time().replace(hour=random.randint(8, 18), minute=random.randint(0, 59))
        )
        
        adjustment = {
            'adjustment_reference_number': f'ADJ-{adjustment_counter:06d}',
            'adjustment_date_key': get_date_key(adjustment_date),
            'medication_key': medication['key'],
            'pharmacy_key': pharmacy['key'],
            'adjustment_type': adjustment_type,
            'adjustment_reason': adjustment_reason,
            'performed_by': performed_by,
            'quantity_adjusted': quantity,
            'cost_impact': cost_impact,
            'batch_number_affected': batch_number,
            'adjustment_timestamp': adjustment_timestamp,
            'approval_timestamp': approval_timestamp,
            'approved_by': approved_by
        }
        
        adjustments.append(adjustment)
        adjustment_counter += 1
        
        if (i + 1) % 50 == 0:
            print(f"  Generated {i + 1}/{num_adjustments} adjustments...")
    
    return adjustments


def insert_adjustments(adjustments):
    """Insert adjustments into database"""
    
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    insert_query = """
        INSERT INTO dwh.fact_stock_adjustments (
            adjustment_reference_number,
            adjustment_date_key,
            medication_key,
            pharmacy_key,
            adjustment_type,
            adjustment_reason,
            performed_by,
            quantity_adjusted,
            cost_impact,
            batch_number_affected,
            adjustment_timestamp,
            approval_timestamp,
            approved_by
        ) VALUES (
            %(adjustment_reference_number)s,
            %(adjustment_date_key)s,
            %(medication_key)s,
            %(pharmacy_key)s,
            %(adjustment_type)s,
            %(adjustment_reason)s,
            %(performed_by)s,
            %(quantity_adjusted)s,
            %(cost_impact)s,
            %(batch_number_affected)s,
            %(adjustment_timestamp)s,
            %(approval_timestamp)s,
            %(approved_by)s
        )
    """
    
    try:
        print(f"\nInserting {len(adjustments)} adjustments into database...")
        execute_batch(cur, insert_query, adjustments, page_size=100)
        conn.commit()
        print(f"Successfully inserted {len(adjustments)} stock adjustments!")
        
        # Statistics
        cur.execute("""
            SELECT 
                COUNT(*) as total_adjustments,
                SUM(CASE WHEN cost_impact < 0 THEN cost_impact ELSE 0 END) as total_losses,
                SUM(CASE WHEN cost_impact > 0 THEN cost_impact ELSE 0 END) as total_gains,
                SUM(cost_impact) as net_impact
            FROM dwh.fact_stock_adjustments
        """)
        stats = cur.fetchone()
        
        print(f"\nAdjustment Statistics:")
        print(f"  Total Adjustments: {stats[0]:,}")
        print(f"  Total Losses: R {abs(stats[1]):,.2f}")
        print(f"  Total Gains: R {stats[2]:,.2f}")
        print(f"  Net Impact: R {stats[3]:,.2f}")
        
        # Adjustment type breakdown
        cur.execute("""
            SELECT 
                adjustment_type,
                COUNT(*) as count,
                SUM(cost_impact) as total_impact
            FROM dwh.fact_stock_adjustments
            GROUP BY adjustment_type
            ORDER BY count DESC
        """)
        print(f"\nAdjustment Type Distribution:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,} adjustments (R {row[2]:,.2f})")
        
        # Top medications by adjustment frequency
        cur.execute("""
            SELECT 
                m.medication_name,
                COUNT(*) as adjustment_count,
                SUM(f.cost_impact) as total_cost_impact
            FROM dwh.fact_stock_adjustments f
            JOIN dwh.dim_medication m ON f.medication_key = m.medication_key
            GROUP BY m.medication_name
            ORDER BY adjustment_count DESC
            LIMIT 5
        """)
        print(f"\nTop 5 Medications by Adjustment Frequency:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,} adjustments (R {row[2]:,.2f})")
        
    except Exception as e:
        conn.rollback()
        print(f"Error inserting adjustments: {e}")
        raise
    finally:
        cur.close()
        conn.close()


def main():
    print("=" * 70)
    print("PHARMAFLOW ANALYTICS - STOCK ADJUSTMENT GENERATOR")
    print("=" * 70)
    
    medications, pharmacies = get_reference_data()
    adjustments = generate_adjustments(medications, pharmacies, num_adjustments=200)
    insert_adjustments(adjustments)
    
    print("\n" + "=" * 70)
    print("STOCK ADJUSTMENT GENERATION COMPLETE!")
    print("=" * 70)


if __name__ == "__main__":
    main()
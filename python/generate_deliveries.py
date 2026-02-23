"""
Generate supplier delivery data
Creates historical delivery records from suppliers to pharmacies
"""

import os
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_batch
import random
from dotenv import load_dotenv

load_dotenv()

random.seed(300)

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
    """Fetch suppliers, medications, and pharmacies"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    print("Fetching reference data...")
    
    # Get suppliers
    cur.execute("""
        SELECT 
            supplier_key,
            supplier_name,
            average_delivery_lead_time_days,
            on_time_delivery_rate,
            delivery_days
        FROM dwh.dim_supplier
        WHERE is_active = TRUE
    """)
    suppliers = [
        {
            'key': r[0], 'name': r[1], 'lead_time': r[2],
            'on_time_rate': float(r[3]) if r[3] else 95.0,
            'delivery_days': r[4]
        }
        for r in cur.fetchall()
    ]
    
    # Get medications with pricing
    cur.execute("""
        SELECT 
            m.medication_key,
            m.medication_name,
            m.unit_cost_price,
            m.minimum_order_quantity,
            m.typical_shelf_life_days,
            c.movement_class
        FROM dwh.dim_medication m
        JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
        WHERE m.is_active = TRUE AND m.is_current = TRUE
    """)
    medications = [
        {
            'key': r[0], 'name': r[1], 'cost': float(r[2]),
            'min_order': r[3], 'shelf_life': r[4], 'movement': r[5]
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
    
    print(f"  Loaded {len(suppliers)} suppliers")
    print(f"  Loaded {len(medications)} medications")
    print(f"  Loaded {len(pharmacies)} pharmacies")
    
    return suppliers, medications, pharmacies


def generate_batch_number():
    """Generate realistic batch number"""
    return f"BATCH{random.randint(100000, 999999)}"


def calculate_order_quantity(medication):
    """Calculate order quantity based on medication characteristics"""
    min_qty = medication['min_order']
    
    if medication['movement'] == 'Fast_Mover':
        base_qty = random.randint(100, 500)
    elif medication['movement'] == 'Medium_Mover':
        base_qty = random.randint(50, 200)
    else:  # Slow_Mover
        base_qty = random.randint(min_qty, 100)
    
    # Round to multiples of minimum order quantity
    return max(min_qty, (base_qty // min_qty) * min_qty)


def generate_deliveries(suppliers, medications, pharmacies, num_deliveries=500):
    """Generate delivery records"""
    
    deliveries = []
    delivery_counter = 1
    
    # Generate deliveries over past 90 days
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=90)
    
    print(f"\nGenerating {num_deliveries} supplier deliveries...")
    print(f"Date range: {start_date} to {end_date}")
    
    for i in range(num_deliveries):
        # Random order date in the past 90 days
        days_ago = random.randint(0, 90)
        ordered_date = end_date - timedelta(days=days_ago)
        
        # Select supplier
        supplier = random.choice(suppliers)
        
        # Select medication
        medication = random.choice(medications)
        
        # Select pharmacy
        pharmacy = random.choice(pharmacies)
        
        # Order quantity
        quantity_ordered = calculate_order_quantity(medication)
        
        # Expected delivery date (based on supplier lead time)
        lead_time = supplier['lead_time']
        expected_delivery = ordered_date + timedelta(days=lead_time)
        
        # Actual delivery date (may be early/late based on supplier performance)
        on_time_prob = supplier['on_time_rate'] / 100.0
        
        if random.random() < on_time_prob:
            # On time or early
            variance = random.randint(-1, 1)
        else:
            # Late
            variance = random.randint(1, 5)
        
        actual_delivery_date = expected_delivery + timedelta(days=variance)
        
        # Ensure delivery date doesn't exceed today
        if actual_delivery_date > end_date:
            actual_delivery_date = end_date
        
        # Delivery lead time
        delivery_lead_time = (actual_delivery_date - ordered_date).days
        
        # Is on time?
        is_on_time = actual_delivery_date <= expected_delivery
        
        # Quantity delivered (usually matches ordered, but sometimes variance)
        delivery_accuracy = random.random()
        
        if delivery_accuracy > 0.95:
            # Perfect delivery
            quantity_delivered = quantity_ordered
            quantity_damaged = 0
            quantity_rejected = 0
        elif delivery_accuracy > 0.85:
            # Minor shortage
            quantity_delivered = quantity_ordered - random.randint(1, int(quantity_ordered * 0.05))
            quantity_damaged = 0
            quantity_rejected = 0
        elif delivery_accuracy > 0.80:
            # Some damage
            quantity_damaged = random.randint(1, int(quantity_ordered * 0.05))
            quantity_delivered = quantity_ordered - quantity_damaged
            quantity_rejected = 0
        else:
            # Significant issues
            quantity_damaged = random.randint(1, int(quantity_ordered * 0.10))
            quantity_rejected = random.randint(0, int(quantity_ordered * 0.05))
            quantity_delivered = quantity_ordered - quantity_damaged - quantity_rejected
        
        # Ensure delivered quantity is not negative
        quantity_delivered = max(0, quantity_delivered)
        
        # Delivery status
        if quantity_delivered == 0:
            delivery_status = 'Rejected'
        elif quantity_delivered == quantity_ordered:
            delivery_status = 'Complete'
        else:
            delivery_status = 'Partial'
        
        # Batch number
        batch_number = generate_batch_number()
        
        # Expiry date (based on shelf life)
        expiry_date = actual_delivery_date + timedelta(days=medication['shelf_life'])
        
        # Unit cost (may have slight variation)
        unit_cost = medication['cost'] * random.uniform(0.95, 1.05)
        total_cost = round(unit_cost * quantity_delivered, 2)
        
        # Cost variance (difference from expected)
        expected_cost = medication['cost'] * quantity_ordered
        actual_cost = total_cost
        variance_cost = round(actual_cost - expected_cost, 2)
        
        # Quality issue flag
        quality_issue = quantity_damaged > 0 or quantity_rejected > 0
        
        # Timestamps
        ordered_timestamp = datetime.combine(
            ordered_date,
            datetime.min.time().replace(hour=random.randint(8, 16))
        )
        
        delivery_timestamp = datetime.combine(
            actual_delivery_date,
            datetime.min.time().replace(hour=random.randint(8, 18))
        )
        
        # Received by (pharmacist names)
        pharmacists = [
            'Sarah Nkosi', 'John Maseko', 'David Chen', 'Precious Dlamini',
            'Michael van Wyk', 'Lerato Mahlangu', 'Zanele Sithole'
        ]
        
        delivery = {
            'delivery_number': f'DEL-{delivery_counter:06d}',
            'purchase_order_number': f'PO-{delivery_counter:06d}',
            'delivery_date_key': get_date_key(actual_delivery_date),
            'ordered_date_key': get_date_key(ordered_date),
            'supplier_key': supplier['key'],
            'medication_key': medication['key'],
            'pharmacy_key': pharmacy['key'],
            'batch_number': batch_number,
            'delivery_status': delivery_status,
            'quantity_ordered': quantity_ordered,
            'quantity_delivered': quantity_delivered,
            'quantity_damaged': quantity_damaged,
            'quantity_rejected': quantity_rejected,
            'unit_cost': round(unit_cost, 2),
            'total_cost': total_cost,
            'expiry_date': expiry_date,
            'shelf_life_days_at_delivery': (expiry_date - actual_delivery_date).days,
            'delivery_lead_time_days': delivery_lead_time,
            'variance_cost': variance_cost,
            'is_on_time': is_on_time,
            'quality_issue_flag': quality_issue,
            'ordered_timestamp': ordered_timestamp,
            'expected_delivery_date': expected_delivery,
            'actual_delivery_timestamp': delivery_timestamp,
            'received_by': random.choice(pharmacists)
        }
        
        deliveries.append(delivery)
        delivery_counter += 1
        
        if (i + 1) % 100 == 0:
            print(f"  Generated {i + 1}/{num_deliveries} deliveries...")
    
    return deliveries


def insert_deliveries(deliveries):
    """Insert deliveries into database"""
    
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    insert_query = """
        INSERT INTO dwh.fact_supplier_deliveries (
            delivery_number, purchase_order_number,
            delivery_date_key, ordered_date_key,
            supplier_key, medication_key, pharmacy_key,
            batch_number, delivery_status,
            quantity_ordered, quantity_delivered, quantity_damaged, quantity_rejected,
            unit_cost, total_cost, expiry_date,
            shelf_life_days_at_delivery, delivery_lead_time_days, variance_cost,
            is_on_time, quality_issue_flag,
            ordered_timestamp, expected_delivery_date, actual_delivery_timestamp,
            received_by
        ) VALUES (
            %(delivery_number)s, %(purchase_order_number)s,
            %(delivery_date_key)s, %(ordered_date_key)s,
            %(supplier_key)s, %(medication_key)s, %(pharmacy_key)s,
            %(batch_number)s, %(delivery_status)s,
            %(quantity_ordered)s, %(quantity_delivered)s, %(quantity_damaged)s, %(quantity_rejected)s,
            %(unit_cost)s, %(total_cost)s, %(expiry_date)s,
            %(shelf_life_days_at_delivery)s, %(delivery_lead_time_days)s, %(variance_cost)s,
            %(is_on_time)s, %(quality_issue_flag)s,
            %(ordered_timestamp)s, %(expected_delivery_date)s, %(actual_delivery_timestamp)s,
            %(received_by)s
        )
    """
    
    try:
        print(f"\nInserting {len(deliveries)} deliveries into database...")
        execute_batch(cur, insert_query, deliveries, page_size=100)
        conn.commit()
        print(f"Successfully inserted {len(deliveries)} deliveries!")
        
        # Statistics
        cur.execute("""
            SELECT 
                COUNT(*) as total_deliveries,
                SUM(total_cost) as total_procurement_cost,
                AVG(delivery_lead_time_days) as avg_lead_time,
                COUNT(CASE WHEN is_on_time = TRUE THEN 1 END) * 100.0 / COUNT(*) as on_time_pct,
                COUNT(CASE WHEN quality_issue_flag = TRUE THEN 1 END) as quality_issues
            FROM dwh.fact_supplier_deliveries
        """)
        stats = cur.fetchone()
        
        print(f"\nDelivery Statistics:")
        print(f"  Total Deliveries: {stats[0]:,}")
        print(f"  Total Procurement Cost: R {stats[1]:,.2f}")
        print(f"  Average Lead Time: {stats[2]:.1f} days")
        print(f"  On-Time Delivery Rate: {stats[3]:.1f}%")
        print(f"  Quality Issues: {stats[4]:,}")
        
        # Delivery status breakdown
        cur.execute("""
            SELECT delivery_status, COUNT(*) as count
            FROM dwh.fact_supplier_deliveries
            GROUP BY delivery_status
            ORDER BY count DESC
        """)
        print(f"\nDelivery Status Distribution:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,}")
        
        # Top suppliers by volume
        cur.execute("""
            SELECT 
                s.supplier_name,
                COUNT(*) as delivery_count,
                SUM(f.total_cost) as total_value
            FROM dwh.fact_supplier_deliveries f
            JOIN dwh.dim_supplier s ON f.supplier_key = s.supplier_key
            GROUP BY s.supplier_name
            ORDER BY total_value DESC
        """)
        print(f"\nSupplier Performance:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,} deliveries (R {row[2]:,.2f})")
        
    except Exception as e:
        conn.rollback()
        print(f"Error inserting deliveries: {e}")
        raise
    finally:
        cur.close()
        conn.close()


def main():
    print("=" * 70)
    print("PHARMAFLOW ANALYTICS - SUPPLIER DELIVERY GENERATOR")
    print("=" * 70)
    
    suppliers, medications, pharmacies = get_reference_data()
    deliveries = generate_deliveries(suppliers, medications, pharmacies, num_deliveries=500)
    insert_deliveries(deliveries)
    
    print("\n" + "=" * 70)
    print("SUPPLIER DELIVERY GENERATION COMPLETE!")
    print("=" * 70)


if __name__ == "__main__":
    main()
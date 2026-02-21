"""
Generate inventory snapshot data
Creates daily snapshots of stock levels for past 30 days
"""

import os
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_batch
import random
from dotenv import load_dotenv

load_dotenv()

random.seed(200)

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
    
    # Get medications with category info
    cur.execute("""
        SELECT 
            m.medication_key,
            m.unit_cost_price,
            m.unit_retail_price,
            m.is_seasonal,
            m.seasonal_peak_months,
            c.clinical_category,
            c.movement_class
        FROM dwh.dim_medication m
        JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
        WHERE m.is_active = TRUE AND m.is_current = TRUE
    """)
    medications = [
        {
            'key': r[0], 'cost': float(r[1]), 'retail': float(r[2]),
            'seasonal': r[3], 'peak_months': r[4],
            'category': r[5], 'movement': r[6]
        }
        for r in cur.fetchall()
    ]
    
    # Get pharmacies
    cur.execute("""
        SELECT pharmacy_key, location_name, demographic_profile
        FROM dwh.dim_pharmacy
        WHERE is_active = TRUE
    """)
    pharmacies = [
        {'key': r[0], 'name': r[1], 'demographic': r[2]}
        for r in cur.fetchall()
    ]
    
    cur.close()
    conn.close()
    
    print(f"  Loaded {len(medications)} medications")
    print(f"  Loaded {len(pharmacies)} pharmacies")
    
    return medications, pharmacies


def calculate_base_stock(medication, pharmacy):
    """Calculate base stock level based on medication and pharmacy characteristics"""
    
    # Base stock by movement class
    if medication['movement'] == 'Fast_Mover':
        base_stock = random.randint(100, 300)
    elif medication['movement'] == 'Medium_Mover':
        base_stock = random.randint(40, 120)
    else:  # Slow_Mover
        base_stock = random.randint(10, 50)
    
    # Adjust for pharmacy demographic (affluent areas stock more)
    if pharmacy['demographic'] == 'Affluent':
        base_stock = int(base_stock * 1.3)
    elif pharmacy['demographic'] == 'Township':
        base_stock = int(base_stock * 0.8)
    elif pharmacy['demographic'] == 'CBD':
        base_stock = int(base_stock * 1.1)
    
    # Chronic medications have higher stock
    if medication['category'] == 'Chronic':
        base_stock = int(base_stock * 1.5)
    
    return base_stock


def calculate_reorder_point(base_stock):
    """Calculate reorder point (typically 20-30% of base stock)"""
    return int(base_stock * random.uniform(0.20, 0.30))


def generate_inventory_snapshots(medications, pharmacies, days=30):
    """Generate daily inventory snapshots"""
    
    snapshots = []
    
    # Generate for past 30 days
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=days-1)
    
    print(f"\nGenerating inventory snapshots...")
    print(f"Date range: {start_date} to {end_date}")
    print(f"Total snapshots: {len(medications)} medications × {len(pharmacies)} pharmacies × {days} days = {len(medications) * len(pharmacies) * days:,}")
    
    # Initialize stock levels for each medication-pharmacy combination
    stock_levels = {}
    for med in medications:
        for pharm in pharmacies:
            key = (med['key'], pharm['key'])
            base_stock = calculate_base_stock(med, pharm)
            reorder_point = calculate_reorder_point(base_stock)
            max_stock = int(base_stock * 1.5)
            
            # Start with random stock between 50-100% of base
            initial_stock = random.randint(int(base_stock * 0.5), base_stock)
            
            stock_levels[key] = {
                'quantity': initial_stock,
                'base_stock': base_stock,
                'reorder_point': reorder_point,
                'max_stock': max_stock,
                'days_since_delivery': random.randint(1, 10)
            }
    
    counter = 0
    
    # Generate snapshots for each day
    for day_offset in range(days):
        current_date = start_date + timedelta(days=day_offset)
        current_month = current_date.month
        
        for med in medications:
            for pharm in pharmacies:
                key = (med['key'], pharm['key'])
                stock = stock_levels[key]
                
                # Daily consumption (random between 1-10% of base stock)
                daily_consumption = random.randint(
                    int(stock['base_stock'] * 0.01),
                    int(stock['base_stock'] * 0.10)
                )
                
                # Seasonal boost for seasonal medications
                if med['seasonal'] and med['peak_months']:
                    peak_months = [int(m) for m in med['peak_months'].split(',')]
                    if current_month in peak_months:
                        daily_consumption = int(daily_consumption * 1.5)
                
                # Apply daily consumption
                stock['quantity'] = max(0, stock['quantity'] - daily_consumption)
                stock['days_since_delivery'] += 1
                
                # Restock if below reorder point and it's been a few days
                if stock['quantity'] <= stock['reorder_point'] and stock['days_since_delivery'] >= 3:
                    restock_quantity = stock['max_stock'] - stock['quantity']
                    stock['quantity'] += restock_quantity
                    stock['days_since_delivery'] = 0
                
                # Randomly restock fast movers even if not at reorder point
                if med['movement'] == 'Fast_Mover' and random.random() < 0.05:
                    if stock['quantity'] < stock['max_stock']:
                        top_up = stock['max_stock'] - stock['quantity']
                        stock['quantity'] += top_up
                        stock['days_since_delivery'] = 0
                
                # Calculate allocated quantity (pending prescriptions)
                quantity_allocated = random.randint(0, min(10, stock['quantity']))
                quantity_available = stock['quantity'] - quantity_allocated
                
                # Quantity on order (if below reorder point)
                quantity_on_order = 0
                if quantity_available <= stock['reorder_point']:
                    quantity_on_order = stock['max_stock'] - stock['quantity']
                
                # Stock value calculations
                stock_value_cost = stock['quantity'] * med['cost']
                stock_value_retail = stock['quantity'] * med['retail']
                
                # Days until stockout (rough estimate)
                if daily_consumption > 0 and quantity_available > 0:
                    days_until_stockout = int(quantity_available / daily_consumption)
                else:
                    days_until_stockout = None
                
                # Stock turnover rate (annual)
                stock_turnover = round(random.uniform(4.0, 12.0), 2)
                
                # Near expiry (random, small chance)
                quantity_near_expiry = random.randint(0, int(stock['quantity'] * 0.05)) if random.random() < 0.1 else 0
                
                # Expired today (very rare)
                quantity_expired_today = random.randint(1, 5) if random.random() < 0.02 else 0
                
                # Stock status
                if quantity_available <= 0:
                    stock_status = 'OUT_OF_STOCK'
                elif quantity_available <= stock['reorder_point']:
                    stock_status = 'LOW_STOCK'
                elif stock['quantity'] > stock['max_stock']:
                    stock_status = 'OVERSTOCKED'
                elif quantity_near_expiry > int(stock['quantity'] * 0.2):
                    stock_status = 'NEAR_EXPIRY'
                else:
                    stock_status = 'OK'
                
                # Overstocked flag
                is_overstocked = stock['quantity'] > stock['max_stock']
                
                # Minimum days until expiry (random)
                min_days_expiry = random.randint(30, 365) if stock['quantity'] > 0 else None
                
                # Batch count
                batch_count = random.randint(1, 4) if stock['quantity'] > 0 else 0
                
                # Last stock count date (within past week)
                last_count_days_ago = random.randint(0, 7)
                last_stock_count = current_date - timedelta(days=last_count_days_ago)
                
                snapshot = {
                    'snapshot_date_key': get_date_key(current_date),
                    'medication_key': med['key'],
                    'pharmacy_key': pharm['key'],
                    'quantity_on_hand': stock['quantity'],
                    'quantity_allocated': quantity_allocated,
                    'quantity_on_order': quantity_on_order,
                    'reorder_point': stock['reorder_point'],
                    'maximum_stock_level': stock['max_stock'],
                    'quantity_expired_today': quantity_expired_today,
                    'quantity_near_expiry': quantity_near_expiry,
                    'stock_value_at_cost': round(stock_value_cost, 2),
                    'stock_value_at_retail': round(stock_value_retail, 2),
                    'days_until_stockout': days_until_stockout,
                    'stock_turnover_rate': stock_turnover,
                    'is_overstocked': is_overstocked,
                    'stock_status_code': stock_status,
                    'min_days_until_expiry': min_days_expiry,
                    'batch_count': batch_count,
                    'snapshot_timestamp': datetime.combine(current_date, datetime.min.time().replace(hour=23, minute=59)),
                    'last_stock_count_date': last_stock_count
                }
                
                snapshots.append(snapshot)
                counter += 1
                
                if counter % 1000 == 0:
                    print(f"  Generated {counter:,} snapshots...")
    
    return snapshots


def insert_snapshots(snapshots):
    """Insert snapshots into database"""
    
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    insert_query = """
        INSERT INTO dwh.fact_inventory_snapshots (
            snapshot_date_key, medication_key, pharmacy_key,
            quantity_on_hand, quantity_allocated, quantity_on_order,
            reorder_point, maximum_stock_level,
            quantity_expired_today, quantity_near_expiry,
            stock_value_at_cost, stock_value_at_retail,
            days_until_stockout, stock_turnover_rate,
            is_overstocked, stock_status_code,
            min_days_until_expiry, batch_count,
            snapshot_timestamp, last_stock_count_date
        ) VALUES (
            %(snapshot_date_key)s, %(medication_key)s, %(pharmacy_key)s,
            %(quantity_on_hand)s, %(quantity_allocated)s, %(quantity_on_order)s,
            %(reorder_point)s, %(maximum_stock_level)s,
            %(quantity_expired_today)s, %(quantity_near_expiry)s,
            %(stock_value_at_cost)s, %(stock_value_at_retail)s,
            %(days_until_stockout)s, %(stock_turnover_rate)s,
            %(is_overstocked)s, %(stock_status_code)s,
            %(min_days_until_expiry)s, %(batch_count)s,
            %(snapshot_timestamp)s, %(last_stock_count_date)s
        )
        ON CONFLICT (snapshot_date_key, medication_key, pharmacy_key) DO NOTHING
    """
    
    try:
        print(f"\nInserting {len(snapshots):,} snapshots into database...")
        execute_batch(cur, insert_query, snapshots, page_size=1000)
        conn.commit()
        print(f"Successfully inserted {len(snapshots):,} inventory snapshots!")
        
        # Statistics
        cur.execute("""
            SELECT 
                COUNT(*) as total_snapshots,
                SUM(stock_value_at_retail) as total_inventory_value,
                COUNT(CASE WHEN stock_status_code = 'LOW_STOCK' THEN 1 END) as low_stock_count,
                COUNT(CASE WHEN stock_status_code = 'OUT_OF_STOCK' THEN 1 END) as out_of_stock_count
            FROM dwh.fact_inventory_snapshots
        """)
        stats = cur.fetchone()
        
        print(f"\nInventory Statistics:")
        print(f"  Total Snapshots: {stats[0]:,}")
        print(f"  Total Inventory Value: R {stats[1]:,.2f}")
        print(f"  Low Stock Items: {stats[2]:,}")
        print(f"  Out of Stock Items: {stats[3]:,}")
        
        # Top 5 medications by stock value
        cur.execute("""
            SELECT 
                m.medication_name,
                SUM(f.quantity_on_hand) as total_units,
                SUM(f.stock_value_at_retail) as total_value
            FROM dwh.fact_inventory_snapshots f
            JOIN dwh.dim_medication m ON f.medication_key = m.medication_key
            WHERE f.snapshot_date_key = (SELECT MAX(snapshot_date_key) FROM dwh.fact_inventory_snapshots)
            GROUP BY m.medication_name
            ORDER BY total_value DESC
            LIMIT 5
        """)
        
        print(f"\nTop 5 Medications by Stock Value (Latest Snapshot):")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]:,} units (R {row[2]:,.2f})")
        
    except Exception as e:
        conn.rollback()
        print(f"Error inserting snapshots: {e}")
        raise
    finally:
        cur.close()
        conn.close()


def main():
    print("=" * 70)
    print("PHARMAFLOW ANALYTICS - INVENTORY SNAPSHOT GENERATOR")
    print("=" * 70)
    
    medications, pharmacies = get_reference_data()
    snapshots = generate_inventory_snapshots(medications, pharmacies, days=30)
    insert_snapshots(snapshots)
    
    print("\n" + "=" * 70)
    print("INVENTORY SNAPSHOT GENERATION COMPLETE!")
    print("=" * 70)


if __name__ == "__main__":
    main()
"""
Supplier Delivery Event Producer
Simulates real-time supplier delivery arrival events at pharmacy locations.

Usage:
    python kafka/producers/delivery_producer.py
    python kafka/producers/delivery_producer.py --count 10
"""

import sys
import json
import random
import argparse
import logging
import time
from datetime import datetime, date, timedelta
from pathlib import Path

from kafka import KafkaProducer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, PRODUCER_CONFIG, SIMULATION

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

PHARMACY_IDS  = SIMULATION['pharmacy_ids']
SUPPLIER_IDS  = ['SUP001', 'SUP002', 'SUP003', 'SUP004']
MEDICATION_IDS = [f'MED{str(i).zfill(3)}' for i in range(1, 61)]
DELIVERY_STATUSES = ['Complete', 'Complete', 'Partial', 'Partial', 'Pending']


def generate_delivery_event() -> dict:
    pharmacy_id    = random.choice(PHARMACY_IDS)
    supplier_id    = random.choice(SUPPLIER_IDS)
    medication_id  = random.choice(MEDICATION_IDS)
    ordered_qty    = random.randint(50, 500)
    received_qty   = int(ordered_qty * random.uniform(0.7, 1.0))
    unit_cost      = round(random.uniform(10.0, 400.0), 2)
    lead_days      = random.randint(1, 7)
    order_date     = date.today() - timedelta(days=lead_days)
    is_on_time     = lead_days <= 3

    return {
        'event_type':              'delivery_received',
        'event_timestamp':         datetime.now().isoformat(),
        'delivery_number':         f"DEL-{supplier_id}-{datetime.now().strftime('%Y%m%d%H%M%S')}-{random.randint(100,999)}",
        'pharmacy_id':             pharmacy_id,
        'supplier_id':             supplier_id,
        'medication_id':           medication_id,
        'ordered_quantity':        ordered_qty,
        'received_quantity':       received_qty,
        'unit_cost_price':         unit_cost,
        'total_cost':              round(received_qty * unit_cost, 2),
        'order_date':              order_date.isoformat(),
        'expected_delivery_date':  (order_date + timedelta(days=3)).isoformat(),
        'actual_delivery_date':    date.today().isoformat(),
        'lead_time_days':          lead_days,
        'is_on_time':              is_on_time,
        'delivery_status':         random.choice(DELIVERY_STATUSES),
        'quality_issue_flag':      random.random() < 0.05,
        'expiry_date':             (date.today() + timedelta(days=random.randint(180, 730))).isoformat(),
        'shelf_life_days_at_delivery': random.randint(180, 730),
    }


def run_producer(count: int = None, rate_per_minute: int = None):
    if rate_per_minute is None:
        rate_per_minute = SIMULATION['deliveries_per_minute']
    delay = 60.0 / rate_per_minute

    producer = KafkaProducer(
        bootstrap_servers=PRODUCER_CONFIG['bootstrap_servers'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        acks=PRODUCER_CONFIG['acks'],
        retries=PRODUCER_CONFIG['retries'],
    )

    topic = TOPICS['deliveries']
    sent = errors = 0

    logger.info(f"Delivery producer starting | topic={topic} | rate={rate_per_minute}/min")

    try:
        while True:
            event = generate_delivery_event()
            try:
                producer.send(
                    topic,
                    key=event['supplier_id'].encode('utf-8'),
                    value=event,
                ).get(timeout=5)
                sent += 1
                logger.info(f"[{sent}] Delivery: {event['delivery_number']} | {event['supplier_id']} → {event['pharmacy_id']} | qty={event['received_quantity']}")
            except Exception as e:
                logger.error(f"Send failed: {e}")
                errors += 1

            if count and sent >= count:
                break
            time.sleep(delay)

    except KeyboardInterrupt:
        logger.info("Stopped.")
    finally:
        producer.flush()
        producer.close()
        logger.info(f"Done. Sent={sent} Errors={errors}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--count', type=int, default=None)
    parser.add_argument('--rate',  type=int, default=None)
    args = parser.parse_args()
    run_producer(count=args.count, rate_per_minute=args.rate)
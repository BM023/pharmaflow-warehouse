"""
Inventory Update Producer
Simulates real-time stock level change events (dispensing reduces stock,
deliveries increase it) and publishes to pharmaflow.inventory topic.

Usage:
    python kafka/producers/inventory_producer.py
    python kafka/producers/inventory_producer.py --count 30
"""

import sys
import json
import random
import argparse
import logging
import time
from datetime import datetime
from pathlib import Path

from kafka import KafkaProducer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, PRODUCER_CONFIG, SIMULATION

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

PHARMACY_IDS   = SIMULATION['pharmacy_ids']
MEDICATION_IDS = [f'MED{str(i).zfill(3)}' for i in range(1, 61)]
STATUS_CODES   = ['OK', 'OK', 'OK', 'LOW', 'NEAR_EXPIRY', 'OVERSTOCKED']


def generate_inventory_event() -> dict:
    pharmacy_id   = random.choice(PHARMACY_IDS)
    medication_id = random.choice(MEDICATION_IDS)
    qty_on_hand   = random.randint(0, 500)
    reorder_point = random.randint(20, 80)
    max_stock     = random.randint(200, 600)
    cost_price    = round(random.uniform(10.0, 400.0), 2)
    retail_price  = round(cost_price * random.uniform(1.6, 2.2), 2)

    if qty_on_hand == 0:
        status = 'OUT'
    elif qty_on_hand <= reorder_point:
        status = 'LOW'
    else:
        status = random.choice(['OK', 'OK', 'OK', 'NEAR_EXPIRY', 'OVERSTOCKED'])

    return {
        'event_type':           'inventory_snapshot',
        'event_timestamp':      datetime.now().isoformat(),
        'snapshot_timestamp':   datetime.now().isoformat(),
        'pharmacy_id':          pharmacy_id,
        'medication_id':        medication_id,
        'quantity_on_hand':     qty_on_hand,
        'quantity_allocated':   random.randint(0, min(qty_on_hand, 50)),
        'reorder_point':        reorder_point,
        'maximum_stock_level':  max_stock,
        'stock_value_at_cost':  round(qty_on_hand * cost_price, 2),
        'stock_value_at_retail': round(qty_on_hand * retail_price, 2),
        'stock_status_code':    status,
        'min_days_until_expiry': random.randint(1, 730),
    }


def run_producer(count: int = None, rate_per_minute: int = None):
    if rate_per_minute is None:
        rate_per_minute = SIMULATION['inventory_updates_per_minute']
    delay = 60.0 / rate_per_minute

    producer = KafkaProducer(
        bootstrap_servers=PRODUCER_CONFIG['bootstrap_servers'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        acks=PRODUCER_CONFIG['acks'],
        retries=PRODUCER_CONFIG['retries'],
    )

    topic = TOPICS['inventory']
    sent = errors = 0

    logger.info(f"Inventory producer starting | topic={topic} | rate={rate_per_minute}/min")

    try:
        while True:
            event = generate_inventory_event()
            try:
                producer.send(
                    topic,
                    key=f"{event['pharmacy_id']}_{event['medication_id']}".encode('utf-8'),
                    value=event,
                ).get(timeout=5)
                sent += 1
                logger.info(f"[{sent}] {event['pharmacy_id']} | {event['medication_id']} | qty={event['quantity_on_hand']} | status={event['stock_status_code']}")
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
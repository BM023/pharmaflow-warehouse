"""
kafka/producers/prescription_producer.py
PharmaFlow Analytics — Prescription Event Producer

Simulates real-time prescription dispensing events across 5 pharmacy
locations and publishes them to the pharmaflow.prescriptions Kafka topic.

Usage:
    python kafka/producers/prescription_producer.py              # run indefinitely
    python kafka/producers/prescription_producer.py --count 50  # send 50 messages
    python kafka/producers/prescription_producer.py --rate 5    # 5 messages/minute
"""

import sys
import json
import random
import argparse
import logging
import time
from datetime import datetime, date
from pathlib import Path

from kafka import KafkaProducer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, PRODUCER_CONFIG, SIMULATION

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Sample reference data (mirrors warehouse dimensions)
# ---------------------------------------------------------------------------
PHARMACY_IDS    = SIMULATION['pharmacy_ids']
MEDICATION_IDS  = [f'MED{str(i).zfill(3)}' for i in range(1, 61)]
DOCTOR_IDS      = [f'DR{str(i).zfill(3)}' for i in range(1, 31)]
INSURANCE_IDS   = ['INS001', 'INS002', 'INS003', 'INS004', 'INS005', None]
PHARMACISTS     = ['Thandi Mokoena', 'Sipho Dlamini', 'Priya Naidoo',
                   'Johan van der Berg', 'Naledi Sithole']
RX_TYPES        = ['New', 'New', 'New', 'Refill', 'Refill', 'Emergency']
PAYMENT_METHODS = ['Cash', 'Cash', 'Medical_Aid', 'Medical_Aid', 'Both']


def generate_prescription_event() -> dict:
    """Generate a single realistic prescription dispensing event."""
    pharmacy_id   = random.choice(PHARMACY_IDS)
    medication_id = random.choice(MEDICATION_IDS)
    doctor_id     = random.choice(DOCTOR_IDS)
    insurance_id  = random.choice(INSURANCE_IDS)
    payment       = 'Medical_Aid' if insurance_id else 'Cash'
    quantity      = random.randint(14, 90)
    unit_price    = round(random.uniform(15.0, 850.0), 2)
    total         = round(quantity * unit_price * random.uniform(0.8, 1.0), 2)
    copay         = round(total * random.uniform(0.1, 0.3), 2) if insurance_id else total
    coverage      = round(total - copay, 2) if insurance_id else 0.0

    rx_number = (
        f"RX-{pharmacy_id}-"
        f"{datetime.now().strftime('%Y%m%d%H%M%S')}-"
        f"{random.randint(1000, 9999)}"
    )

    return {
        'event_type':                'prescription_dispensed',
        'event_timestamp':           datetime.now().isoformat(),
        'prescription_number':       rx_number,
        'prescription_date':         date.today().isoformat(),
        'pharmacy_id':               pharmacy_id,
        'patient_id':                f'PAT{str(random.randint(1, 500)).zfill(4)}',
        'medication_id':             medication_id,
        'doctor_id':                 doctor_id,
        'insurance_id':              insurance_id,
        'prescription_type':         random.choice(RX_TYPES),
        'payment_method':            payment,
        'dispensing_pharmacist_name': random.choice(PHARMACISTS),
        'quantity_dispensed':        quantity,
        'unit_price':                unit_price,
        'total_amount':              total,
        'cost_price':                round(unit_price * 0.55, 2),
        'insurance_coverage_amount': coverage,
        'patient_copay':             copay,
        'discount_amount':           0.0,
        'days_supply':               quantity,
        'refills_remaining':         random.randint(0, 5),
        'dispensing_timestamp':      datetime.now().isoformat(),
    }


def run_producer(count: int = None, rate_per_minute: int = None):
    """
    Publish prescription events to Kafka.

    Args:
        count:           total messages to send (None = run forever)
        rate_per_minute: messages per minute (None = use config default)
    """
    if rate_per_minute is None:
        rate_per_minute = SIMULATION['prescriptions_per_minute']

    delay = 60.0 / rate_per_minute

    producer = KafkaProducer(
        bootstrap_servers=PRODUCER_CONFIG['bootstrap_servers'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        acks=PRODUCER_CONFIG['acks'],
        retries=PRODUCER_CONFIG['retries'],
    )

    topic   = TOPICS['prescriptions']
    sent    = 0
    errors  = 0

    logger.info(f"Prescription producer starting")
    logger.info(f"Topic  : {topic}")
    logger.info(f"Rate   : {rate_per_minute}/min ({delay:.1f}s between messages)")
    logger.info(f"Count  : {'unlimited' if count is None else count}")

    try:
        while True:
            event = generate_prescription_event()
            try:
                future = producer.send(
                    topic,
                    key=event['pharmacy_id'].encode('utf-8'),
                    value=event,
                )
                future.get(timeout=5)
                sent += 1
                logger.info(
                    f"[{sent}] Sent: {event['prescription_number']} | "
                    f"pharmacy={event['pharmacy_id']} | "
                    f"med={event['medication_id']} | "
                    f"R{event['total_amount']:.2f}"
                )
            except Exception as e:
                logger.error(f"Failed to send: {e}")
                errors += 1

            if count and sent >= count:
                logger.info(f"Reached target count ({count}). Stopping.")
                break

            time.sleep(delay)

    except KeyboardInterrupt:
        logger.info("Producer stopped by user.")
    finally:
        producer.flush()
        producer.close()
        logger.info(f"Done. Sent: {sent} | Errors: {errors}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='PharmaFlow Prescription Producer')
    parser.add_argument('--count', type=int, default=None, help='Number of messages to send')
    parser.add_argument('--rate',  type=int, default=None, help='Messages per minute')
    args = parser.parse_args()
    run_producer(count=args.count, rate_per_minute=args.rate)
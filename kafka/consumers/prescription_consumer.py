"""
kafka/consumers/prescription_consumer.py
PharmaFlow Analytics — Prescription Event Consumer

Reads prescription events from pharmaflow.prescriptions topic and
accumulates them into a daily CSV file at:
    raw_data/YYYY-MM-DD/prescriptions_YYYY-MM-DD.csv

The file is flushed every FLUSH_INTERVAL_SECONDS so the file monitor
and Airflow FileSensor can detect it and trigger the ETL pipeline.

Usage:
    python kafka/consumers/prescription_consumer.py
"""

import sys
import csv
import json
import logging
import os
import time
from datetime import datetime, date
from pathlib import Path

from kafka import KafkaConsumer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, CONSUMER_CONFIG, RAW_DATA_DIR

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

FLUSH_INTERVAL_SECONDS = 30
GROUP_ID = 'pharmaflow-prescription-consumer'

CSV_COLUMNS = [
    'prescription_number', 'prescription_date', 'pharmacy_id', 'patient_id',
    'medication_id', 'doctor_id', 'insurance_id', 'prescription_type',
    'payment_method', 'dispensing_pharmacist_name', 'quantity_dispensed',
    'unit_price', 'total_amount', 'cost_price', 'insurance_coverage_amount',
    'patient_copay', 'discount_amount', 'days_supply', 'refills_remaining',
    'dispensing_timestamp',
]


def get_output_path(target_date: date = None) -> Path:
    if target_date is None:
        target_date = date.today()
    date_str = target_date.strftime('%Y-%m-%d')
    folder = Path(RAW_DATA_DIR) / date_str
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f'prescriptions_{date_str}.csv'


def write_batch(records: list, output_path: Path):
    """Append a batch of records to the daily CSV file."""
    file_exists = output_path.exists()
    with open(output_path, 'a', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS, extrasaction='ignore')
        if not file_exists:
            writer.writeheader()
        writer.writerows(records)
    logger.info(f"Flushed {len(records)} records to {output_path}")


def run_consumer():
    consumer = KafkaConsumer(
        TOPICS['prescriptions'],
        bootstrap_servers=CONSUMER_CONFIG['bootstrap_servers'],
        group_id=GROUP_ID,
        value_deserializer=lambda v: json.loads(v.decode('utf-8')),
        auto_offset_reset=CONSUMER_CONFIG['auto_offset_reset'],
        enable_auto_commit=CONSUMER_CONFIG['enable_auto_commit'],
        consumer_timeout_ms=FLUSH_INTERVAL_SECONDS * 1000,
    )

    logger.info(f"Prescription consumer started | topic={TOPICS['prescriptions']}")
    logger.info(f"Writing to: {RAW_DATA_DIR}/YYYY-MM-DD/prescriptions_YYYY-MM-DD.csv")

    buffer   = []
    consumed = 0
    flushed  = 0

    try:
        while True:
            try:
                for message in consumer:
                    event = message.value
                    buffer.append(event)
                    consumed += 1

                    if consumed % 10 == 0:
                        logger.info(f"Consumed {consumed} messages (buffer: {len(buffer)})")

            except Exception:
                pass  # consumer_timeout_ms hit — time to flush

            if buffer:
                output_path = get_output_path()
                write_batch(buffer, output_path)
                flushed += len(buffer)
                buffer = []
                logger.info(f"Total flushed: {flushed} | Output: {output_path}")

    except KeyboardInterrupt:
        logger.info("Consumer stopped.")
        if buffer:
            write_batch(buffer, get_output_path())
    finally:
        consumer.close()
        logger.info(f"Consumer closed. Total consumed: {consumed}")


if __name__ == '__main__':
    run_consumer()
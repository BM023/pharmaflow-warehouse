"""
Patient Registration Consumer
Reads patient registration events and appends to:
    raw_data/YYYY-MM-DD/new_patients.csv

Usage:
    python kafka/consumers/patient_consumer.py
"""

import sys
import csv
import json
import logging
from datetime import date
from pathlib import Path

from kafka import KafkaConsumer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, CONSUMER_CONFIG, RAW_DATA_DIR

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

FLUSH_INTERVAL_SECONDS = 30
GROUP_ID = 'pharmaflow-patient-consumer'

CSV_COLUMNS = [
    'patient_id', 'title', 'first_name', 'last_name', 'date_of_birth',
    'gender', 'phone_number', 'email', 'address_line1', 'suburb',
    'city', 'province', 'postal_code', 'registration_date',
    'is_chronic_patient', 'has_medical_aid', 'preferred_contact_method',
]


def get_output_path(target_date: date = None) -> Path:
    if target_date is None:
        target_date = date.today()
    date_str = target_date.strftime('%Y-%m-%d')
    folder = Path(RAW_DATA_DIR) / date_str
    folder.mkdir(parents=True, exist_ok=True)
    return folder / 'new_patients.csv'


def write_batch(records: list, output_path: Path):
    file_exists = output_path.exists()
    with open(output_path, 'a', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS, extrasaction='ignore')
        if not file_exists:
            writer.writeheader()
        writer.writerows(records)
    logger.info(f"Flushed {len(records)} patient records to {output_path}")


def run_consumer():
    consumer = KafkaConsumer(
        TOPICS['patients'],
        bootstrap_servers=CONSUMER_CONFIG['bootstrap_servers'],
        group_id=GROUP_ID,
        value_deserializer=lambda v: json.loads(v.decode('utf-8')),
        auto_offset_reset=CONSUMER_CONFIG['auto_offset_reset'],
        enable_auto_commit=CONSUMER_CONFIG['enable_auto_commit'],
        consumer_timeout_ms=FLUSH_INTERVAL_SECONDS * 1000,
    )

    logger.info(f"Patient consumer started | topic={TOPICS['patients']}")

    buffer = []
    consumed = 0

    try:
        while True:
            try:
                for message in consumer:
                    buffer.append(message.value)
                    consumed += 1
                    logger.info(f"[{consumed}] Patient: {message.value.get('patient_id')} | {message.value.get('first_name')} {message.value.get('last_name')}")
            except Exception:
                pass

            if buffer:
                write_batch(buffer, get_output_path())
                buffer = []

    except KeyboardInterrupt:
        logger.info("Stopped.")
        if buffer:
            write_batch(buffer, get_output_path())
    finally:
        consumer.close()
        logger.info(f"Total consumed: {consumed}")


if __name__ == '__main__':
    run_consumer()


# =============================================================================
# kafka/consumers/delivery_consumer.py
# =============================================================================

"""
Delivery event consumer — writes to raw_data/YYYY-MM-DD/deliveries_YYYY-MM-DD.csv
"""

import sys
import csv
import json
import logging
from datetime import date
from pathlib import Path

from kafka import KafkaConsumer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, CONSUMER_CONFIG, RAW_DATA_DIR

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

GROUP_ID = 'pharmaflow-delivery-consumer'

DELIVERY_COLUMNS = [
    'delivery_number', 'pharmacy_id', 'supplier_id', 'medication_id',
    'ordered_quantity', 'received_quantity', 'unit_cost_price', 'total_cost',
    'order_date', 'expected_delivery_date', 'actual_delivery_date',
    'lead_time_days', 'is_on_time', 'delivery_status', 'quality_issue_flag',
    'expiry_date', 'shelf_life_days_at_delivery',
]


def get_delivery_output_path(target_date: date = None) -> Path:
    if target_date is None:
        target_date = date.today()
    date_str = target_date.strftime('%Y-%m-%d')
    folder = Path(RAW_DATA_DIR) / date_str
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f'deliveries_{date_str}.csv'


def run_delivery_consumer():
    consumer = KafkaConsumer(
        TOPICS['deliveries'],
        bootstrap_servers=CONSUMER_CONFIG['bootstrap_servers'],
        group_id=GROUP_ID,
        value_deserializer=lambda v: json.loads(v.decode('utf-8')),
        auto_offset_reset=CONSUMER_CONFIG['auto_offset_reset'],
        enable_auto_commit=CONSUMER_CONFIG['enable_auto_commit'],
        consumer_timeout_ms=30000,
    )

    logger.info(f"Delivery consumer started | topic={TOPICS['deliveries']}")

    buffer = []
    consumed = 0

    try:
        while True:
            try:
                for message in consumer:
                    buffer.append(message.value)
                    consumed += 1
                    logger.info(f"[{consumed}] Delivery: {message.value.get('delivery_number')}")
            except Exception:
                pass

            if buffer:
                output_path = get_delivery_output_path()
                file_exists = output_path.exists()
                with open(output_path, 'a', newline='') as f:
                    writer = csv.DictWriter(f, fieldnames=DELIVERY_COLUMNS, extrasaction='ignore')
                    if not file_exists:
                        writer.writeheader()
                    writer.writerows(buffer)
                logger.info(f"Flushed {len(buffer)} delivery records to {output_path}")
                buffer = []

    except KeyboardInterrupt:
        logger.info("Stopped.")
    finally:
        consumer.close()


if __name__ == '__main__':
    run_delivery_consumer()
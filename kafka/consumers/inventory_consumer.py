"""
Inventory Event Consumer
Reads inventory snapshot events and writes to:
    raw_data/YYYY-MM-DD/inventory_snapshot_YYYY-MM-DD.xlsx

Accumulates events throughout the day and flushes to Excel every
FLUSH_INTERVAL_SECONDS seconds.

Usage:
    python kafka/consumers/inventory_consumer.py
"""

import sys
import json
import logging
import time
from datetime import datetime, date
from pathlib import Path

import pandas as pd
from kafka import KafkaConsumer

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, CONSUMER_CONFIG, RAW_DATA_DIR

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

FLUSH_INTERVAL_SECONDS = 30
GROUP_ID = 'pharmaflow-inventory-consumer'

COLUMNS = [
    'pharmacy_id', 'medication_id', 'quantity_on_hand', 'quantity_allocated',
    'reorder_point', 'maximum_stock_level', 'stock_value_at_cost',
    'stock_value_at_retail', 'stock_status_code', 'min_days_until_expiry',
    'snapshot_timestamp',
]


def get_output_path(target_date: date = None) -> Path:
    if target_date is None:
        target_date = date.today()
    date_str = target_date.strftime('%Y-%m-%d')
    folder = Path(RAW_DATA_DIR) / date_str
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f'inventory_snapshot_{date_str}.xlsx'


def write_batch(records: list, output_path: Path):
    """Append records to Excel file, creating or updating the Inventory sheet."""
    new_df = pd.DataFrame(records, columns=COLUMNS)

    if output_path.exists():
        existing_df = pd.read_excel(output_path, sheet_name='Inventory')
        combined_df = pd.concat([existing_df, new_df], ignore_index=True)
        # Keep latest snapshot per pharmacy+medication combination
        combined_df = combined_df.drop_duplicates(
            subset=['pharmacy_id', 'medication_id'], keep='last'
        )
    else:
        combined_df = new_df

    with pd.ExcelWriter(output_path, engine='openpyxl') as writer:
        combined_df.to_excel(writer, sheet_name='Inventory', index=False)

    logger.info(f"Flushed {len(records)} records to {output_path} ({len(combined_df)} total rows)")


def run_consumer():
    consumer = KafkaConsumer(
        TOPICS['inventory'],
        bootstrap_servers=CONSUMER_CONFIG['bootstrap_servers'],
        group_id=GROUP_ID,
        value_deserializer=lambda v: json.loads(v.decode('utf-8')),
        auto_offset_reset=CONSUMER_CONFIG['auto_offset_reset'],
        enable_auto_commit=CONSUMER_CONFIG['enable_auto_commit'],
        consumer_timeout_ms=FLUSH_INTERVAL_SECONDS * 1000,
    )

    logger.info(f"Inventory consumer started | topic={TOPICS['inventory']}")

    buffer = []
    consumed = flushed = 0

    try:
        while True:
            try:
                for message in consumer:
                    buffer.append(message.value)
                    consumed += 1
            except Exception:
                pass

            if buffer:
                write_batch(buffer, get_output_path())
                flushed += len(buffer)
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
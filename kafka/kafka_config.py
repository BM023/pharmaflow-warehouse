"""
kafka/kafka_config.py
PharmaFlow Analytics — Kafka Configuration

Shared configuration for all producers and consumers.
"""

import os
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Broker config
# ---------------------------------------------------------------------------
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')

# ---------------------------------------------------------------------------
# Topic definitions
# ---------------------------------------------------------------------------
TOPICS = {
    'prescriptions': 'pharmaflow.prescriptions',
    'inventory':     'pharmaflow.inventory',
    'patients':      'pharmaflow.patients',
    'deliveries':    'pharmaflow.deliveries',
}

# Number of partitions per topic (one per pharmacy location)
TOPIC_PARTITIONS = 5
TOPIC_REPLICATION = 1   # single broker for local dev

# ---------------------------------------------------------------------------
# Producer defaults
# ---------------------------------------------------------------------------
PRODUCER_CONFIG = {
    'bootstrap_servers': KAFKA_BOOTSTRAP_SERVERS,
    'value_serializer':  None,   # set per producer
    'acks':              'all',  # wait for all replicas
    'retries':           3,
    'retry_backoff_ms':  500,
}

# ---------------------------------------------------------------------------
# Consumer defaults
# ---------------------------------------------------------------------------
CONSUMER_CONFIG = {
    'bootstrap_servers':  KAFKA_BOOTSTRAP_SERVERS,
    'value_deserializer': None,  # set per consumer
    'auto_offset_reset':  'earliest',
    'enable_auto_commit': True,
    'auto_commit_interval_ms': 1000,
}

# ---------------------------------------------------------------------------
# Raw data output dir (consumers write here)
# ---------------------------------------------------------------------------
RAW_DATA_DIR = os.getenv('RAW_DATA_DIR', 'raw_data')

# ---------------------------------------------------------------------------
# Simulation settings
# ---------------------------------------------------------------------------
SIMULATION = {
    'prescriptions_per_minute': 10,   # realistic busy pharmacy rate
    'inventory_updates_per_minute': 3,
    'patients_per_minute': 1,
    'deliveries_per_minute': 1,
    'pharmacy_ids': ['PH001', 'PH002', 'PH003', 'PH004', 'PH005'],
}
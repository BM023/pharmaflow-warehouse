"""
New Patient Registration Producer
Simulates real-time patient registration events at pharmacy counters.

Usage:
    python kafka/producers/patient_producer.py
    python kafka/producers/patient_producer.py --count 10
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
from faker import Faker

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))
from kafka_config import TOPICS, PRODUCER_CONFIG, SIMULATION

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

fake = Faker('en_ZA')

PHARMACY_IDS = SIMULATION['pharmacy_ids']
TITLES       = ['Mr', 'Mrs', 'Ms', 'Dr', 'Prof']
GENDERS      = ['Male', 'Female']
PROVINCES    = ['Gauteng', 'Gauteng', 'Gauteng', 'Western Cape', 'KwaZulu-Natal']
SUBURBS      = ['Sandton', 'Randburg', 'Soweto', 'Fourways', 'Midrand',
                'Rosebank', 'Parktown', 'Braamfontein', 'Melville', 'Norwood']


def generate_patient_event() -> dict:
    gender    = random.choice(GENDERS)
    dob       = date.today() - timedelta(days=random.randint(365*18, 365*80))
    has_aid   = random.random() < 0.38
    is_chronic = random.random() < 0.30
    patient_id = f"PAT{str(random.randint(5001, 9999)).zfill(4)}"

    return {
        'event_type':               'patient_registration',
        'event_timestamp':          datetime.now().isoformat(),
        'patient_id':               patient_id,
        'title':                    random.choice(TITLES),
        'first_name':               fake.first_name_male() if gender == 'Male' else fake.first_name_female(),
        'last_name':                fake.last_name(),
        'date_of_birth':            dob.isoformat(),
        'gender':                   gender,
        'phone_number':             f'+27 {random.randint(10,99)} {random.randint(100,999)} {random.randint(1000,9999)}',
        'email':                    fake.email(),
        'address_line1':            fake.street_address(),
        'suburb':                   random.choice(SUBURBS),
        'city':                     'Johannesburg',
        'province':                 random.choice(PROVINCES),
        'postal_code':              str(random.randint(1000, 9999)),
        'registration_date':        date.today().isoformat(),
        'is_chronic_patient':       is_chronic,
        'has_medical_aid':          has_aid,
        'preferred_contact_method': random.choice(['Phone', 'Email', 'SMS']),
        'primary_pharmacy_id':      random.choice(PHARMACY_IDS),
    }


def run_producer(count: int = None, rate_per_minute: int = None):
    if rate_per_minute is None:
        rate_per_minute = SIMULATION['patients_per_minute']
    delay = 60.0 / rate_per_minute

    producer = KafkaProducer(
        bootstrap_servers=PRODUCER_CONFIG['bootstrap_servers'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        acks=PRODUCER_CONFIG['acks'],
        retries=PRODUCER_CONFIG['retries'],
    )

    topic = TOPICS['patients']
    sent = errors = 0

    logger.info(f"Patient producer starting | topic={topic} | rate={rate_per_minute}/min")

    try:
        while True:
            event = generate_patient_event()
            try:
                producer.send(
                    topic,
                    key=event['patient_id'].encode('utf-8'),
                    value=event,
                ).get(timeout=5)
                sent += 1
                logger.info(f"[{sent}] Registered: {event['patient_id']} | {event['first_name']} {event['last_name']} | {event['primary_pharmacy_id']}")
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
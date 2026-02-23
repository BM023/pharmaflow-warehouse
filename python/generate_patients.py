"""
Generate realistic patient data using Faker library
Inserts 500 patients into dim_patient table
"""

import os
from faker import Faker
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_batch
import random
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize Faker with US locale
fake = Faker('en_US')
Faker.seed(42)  # For reproducibility
random.seed(42)

# Database connection parameters
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5433'),
    'database': os.getenv('DB_NAME', 'pharmaflow_warehouse'),
    'user': os.getenv('DB_USER', 'pharmaflow'),
    'password': os.getenv('DB_PASSWORD', 'pharmaflow2024')
}

# South African suburbs by pharmacy location demographic
SUBURBS = {
    'Affluent': ['Sandton', 'Hyde Park', 'Morningside', 'Bryanston', 'Rosebank', 'Parktown'],
    'Township': ['Orlando East', 'Soweto', 'Diepsloot', 'Alexandra', 'Tembisa'],
    'CBD': ['Johannesburg CBD', 'Braamfontein', 'Newtown', 'Hillbrow'],
    'Upper_Middle': ['Randburg', 'Fourways', 'Rosebank', 'Parkview', 'Melville'],
    'Middle_Income': ['Midrand', 'Benoni', 'Roodepoort', 'Krugersdorp', 'Boksburg']
}

# Medical aid distribution (realistic for SA)
MEDICAL_AID_DISTRIBUTION = {
    True: 0.35,   # 35% have medical aid
    False: 0.65   # 65% are cash patients
}

# Chronic patient distribution
CHRONIC_PATIENT_DISTRIBUTION = {
    True: 0.25,   # 25% are chronic patients
    False: 0.75
}

PATIENT_TYPES = ['New', 'Regular', 'Occasional']

CONTACT_METHODS = ['Phone', 'Email', 'SMS', 'WhatsApp']

TITLES = {
    'Male': ['Mr', 'Dr', 'Prof'],
    'Female': ['Ms', 'Mrs', 'Miss', 'Dr', 'Prof']
}


def get_pharmacy_distribution():
    """Get pharmacy keys and their demographic profiles"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    cur.execute("""
        SELECT pharmacy_key, demographic_profile, location_name
        FROM dwh.dim_pharmacy
        WHERE is_active = TRUE
    """)
    
    pharmacies = cur.fetchall()
    cur.close()
    conn.close()
    
    return pharmacies


def generate_sa_id_number(date_of_birth, gender):
    """Generate realistic South African ID number format (YYMMDD GSSS CAZ)"""
    # Format: YYMMDD GSSS CAZ
    # YY = Year, MM = Month, DD = Day
    # G = Gender (0-4 female, 5-9 male)
    # SSS = Sequence number
    # C = Citizenship (0 = SA citizen, 1 = permanent resident)
    # A = Usually 8
    # Z = Checksum
    
    yy = date_of_birth.strftime('%y')
    mm = date_of_birth.strftime('%m')
    dd = date_of_birth.strftime('%d')
    
    gender_digit = random.randint(5, 9) if gender == 'Male' else random.randint(0, 4)
    sequence = f"{random.randint(0, 999):03d}"
    citizenship = '0'  # SA citizen
    a_digit = '8'
    
    id_number = f"{yy}{mm}{dd}{gender_digit}{sequence}{citizenship}{a_digit}"
    
    # Simple checksum (not actual Luhn algorithm for simplicity)
    checksum = str(sum(int(d) for d in id_number) % 10)
    
    return id_number + checksum


def generate_patient_data(num_patients=500):
    """Generate patient data"""
    
    pharmacies = get_pharmacy_distribution()
    patients = []
    
    print(f"Generating {num_patients} patient records...")
    
    for i in range(num_patients):
        # Assign to pharmacy based on distribution
        pharmacy = random.choice(pharmacies)
        pharmacy_key = pharmacy[0]
        demographic_profile = pharmacy[1]
        
        # Gender distribution
        gender = random.choice(['Male', 'Female'])
        
        # Generate age with realistic distribution
        age_distribution = random.choices(
            ['child', 'teen', 'young_adult', 'adult', 'middle_age', 'senior'],
            weights=[0.08, 0.07, 0.20, 0.25, 0.25, 0.15],
            k=1
        )[0]
        
        if age_distribution == 'child':
            age = random.randint(0, 12)
        elif age_distribution == 'teen':
            age = random.randint(13, 18)
        elif age_distribution == 'young_adult':
            age = random.randint(19, 35)
        elif age_distribution == 'adult':
            age = random.randint(36, 50)
        elif age_distribution == 'middle_age':
            age = random.randint(51, 65)
        else:  # senior
            age = random.randint(66, 90)
        
        date_of_birth = datetime.now().date() - timedelta(days=age*365 + random.randint(0, 364))
        
        # Generate patient ID (SA ID number format)
        patient_id = generate_sa_id_number(date_of_birth, gender, sequence_override=i % 1000)
        
        # Name generation
        if gender == 'Male':
            first_name = fake.first_name_male()
        else:
            first_name = fake.first_name_female()
        
        last_name = fake.last_name()
        title = random.choice(TITLES[gender])
        
        # Assign suburb based on pharmacy demographic
        suburb = random.choice(SUBURBS[demographic_profile])
        
        # Medical aid - higher in affluent areas
        has_medical_aid_prob = 0.70 if demographic_profile == 'Affluent' else \
                               0.50 if demographic_profile == 'Upper_Middle' else \
                               0.30 if demographic_profile == 'Middle_Income' else \
                               0.15 if demographic_profile == 'CBD' else 0.10
        
        has_medical_aid = random.random() < has_medical_aid_prob
        
        # Chronic patient - more likely in older patients
        chronic_prob = 0.05 if age < 18 else \
                      0.15 if age < 40 else \
                      0.35 if age < 60 else 0.50
        
        is_chronic_patient = random.random() < chronic_prob
        
        # Patient type based on history
        if is_chronic_patient:
            patient_type = 'Regular'
        else:
            patient_type = random.choices(
                PATIENT_TYPES,
                weights=[0.20, 0.50, 0.30],
                k=1
            )[0]
        
        # Registration date (random within last 5 years)
        days_ago = random.randint(1, 1825)  # Up to 5 years
        registration_date = datetime.now().date() - timedelta(days=days_ago)
        
        # Contact information
        phone_number = f'+27 {random.randint(10,99)} {random.randint(100,999)} {random.randint(1000,9999)}' if random.random() > 0.05 else None
        email = fake.email() if random.random() > 0.20 and age >= 18 else None
        
        patient = {
            'patient_id': patient_id,
            'title': title,
            'first_name': first_name,
            'last_name': last_name,
            'date_of_birth': date_of_birth,
            'gender': gender,
            'phone_number': phone_number,
            'email': email,
            'address_line1': fake.street_address(),
            'address_line2': None if random.random() > 0.3 else fake.secondary_address(),
            'suburb': suburb,
            'city': 'Johannesburg',
            'province': 'Gauteng',
            'postal_code': f'{random.randint(1000, 9999)}',
            'primary_pharmacy_key': pharmacy_key,
            'patient_type': patient_type,
            'registration_date': registration_date,
            'is_chronic_patient': is_chronic_patient,
            'has_medical_aid': has_medical_aid,
            'preferred_contact_method': random.choice(CONTACT_METHODS),
            'is_active': True
        }
        
        patients.append(patient)
        
        if (i + 1) % 100 == 0:
            print(f"  Generated {i + 1}/{num_patients} patients...")
    
    return patients


def insert_patients(patients):
    """Insert patients into database"""
    
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    insert_query = """
        INSERT INTO dwh.dim_patient (
            patient_id, title, first_name, last_name, date_of_birth, gender,
            phone_number, email, address_line1, address_line2, suburb, city, province, postal_code,
            primary_pharmacy_key, patient_type, registration_date,
            is_chronic_patient, has_medical_aid, preferred_contact_method, is_active
        ) VALUES (
            %(patient_id)s, %(title)s, %(first_name)s, %(last_name)s, %(date_of_birth)s, %(gender)s,
            %(phone_number)s, %(email)s, %(address_line1)s, %(address_line2)s, %(suburb)s, 
            %(city)s, %(province)s, %(postal_code)s,
            %(primary_pharmacy_key)s, %(patient_type)s, %(registration_date)s,
            %(is_chronic_patient)s, %(has_medical_aid)s, %(preferred_contact_method)s, %(is_active)s
        )
    """
    
    try:
        print(f"\nInserting {len(patients)} patients into database...")
        execute_batch(cur, insert_query, patients, page_size=100)
        conn.commit()
        print(f"✓ Successfully inserted {len(patients)} patients!")
        
        # Verify insertion
        cur.execute("SELECT COUNT(*) FROM dwh.dim_patient")
        count = cur.fetchone()[0]
        print(f"✓ Total patients in database: {count}")
        
        # Show distribution
        cur.execute("""
            SELECT 
                age_group,
                COUNT(*) as patient_count,
                ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as percentage
            FROM dwh.dim_patient
            WHERE is_current = TRUE
            GROUP BY age_group
            ORDER BY 
                CASE age_group
                    WHEN '0-12' THEN 1
                    WHEN '13-18' THEN 2
                    WHEN '19-35' THEN 3
                    WHEN '36-50' THEN 4
                    WHEN '51-65' THEN 5
                    WHEN '65+' THEN 6
                END
        """)
        
        print("\nAge Group Distribution:")
        print("Age Group | Count | Percentage")
        print("-" * 35)
        for row in cur.fetchall():
            print(f"{row[0]:9} | {row[1]:5} | {row[2]:5}%")
        
        # Show chronic vs non-chronic
        cur.execute("""
            SELECT 
                CASE WHEN is_chronic_patient THEN 'Chronic' ELSE 'Non-Chronic' END as patient_category,
                COUNT(*) as count
            FROM dwh.dim_patient
            WHERE is_current = TRUE
            GROUP BY is_chronic_patient
        """)
        
        print("\nChronic Patient Distribution:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]}")
        
        # Show medical aid distribution
        cur.execute("""
            SELECT 
                CASE WHEN has_medical_aid THEN 'Has Medical Aid' ELSE 'Cash Patient' END as payment_type,
                COUNT(*) as count
            FROM dwh.dim_patient
            WHERE is_current = TRUE
            GROUP BY has_medical_aid
        """)
        
        print("\nPayment Type Distribution:")
        for row in cur.fetchall():
            print(f"  {row[0]}: {row[1]}")
        
    except Exception as e:
        conn.rollback()
        print(f"✗ Error inserting patients: {e}")
        raise
    finally:
        cur.close()
        conn.close()

def generate_sa_id_number(date_of_birth, gender, sequence_override=None):
    yy = date_of_birth.strftime('%y')
    mm = date_of_birth.strftime('%m')
    dd = date_of_birth.strftime('%d')
    gender_digit = random.randint(5, 9) if gender == 'Male' else random.randint(0, 4)
    sequence = f"{sequence_override:03d}" if sequence_override is not None else f"{random.randint(0, 999):03d}"
    citizenship = '0'
    a_digit = '8'
    id_number = f"{yy}{mm}{dd}{gender_digit}{sequence}{citizenship}{a_digit}"
    checksum = str(sum(int(d) for d in id_number) % 10)
    return id_number + checksum

def main():
    """Main execution function"""
    print("=" * 60)
    print("PHARMAFLOW ANALYTICS - PATIENT DATA GENERATOR")
    print("=" * 60)
    
    # Generate patient data
    patients = generate_patient_data(num_patients=500)
    
    # Insert into database
    insert_patients(patients)
    
    print("\n" + "=" * 60)
    print("PATIENT DATA GENERATION COMPLETE!")
    print("=" * 60)


if __name__ == "__main__":
    main()
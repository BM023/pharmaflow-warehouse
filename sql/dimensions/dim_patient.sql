CREATE TABLE dwh.dim_patient (
    patient_key SERIAL PRIMARY KEY,
    patient_id VARCHAR(20) NOT NULL UNIQUE,
    
    -- Personal information
    title VARCHAR(10),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    age_group VARCHAR(20),
    gender VARCHAR(30),
    
    -- Contact information
    phone_number VARCHAR(20),
    email VARCHAR(100),
    address_line1 VARCHAR(200),
    address_line2 VARCHAR(200),
    suburb VARCHAR(100),
    city VARCHAR(100),
    province VARCHAR(50),
    postal_code VARCHAR(10),
    
    -- Patient profile
    primary_pharmacy_key INTEGER REFERENCES dwh.dim_pharmacy(pharmacy_key),
    patient_type VARCHAR(30) DEFAULT 'New',
    registration_date DATE NOT NULL,
    is_chronic_patient BOOLEAN DEFAULT FALSE,
    has_medical_aid BOOLEAN DEFAULT FALSE,
    preferred_contact_method VARCHAR(20),
    
    -- SCD Type 2 fields
    effective_date DATE DEFAULT CURRENT_DATE,
    end_date DATE,
    is_current BOOLEAN DEFAULT TRUE,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Function to calculate age group
CREATE OR REPLACE FUNCTION calculate_age_group(dob DATE) 
RETURNS VARCHAR(20) AS $$
BEGIN
    RETURN CASE 
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 0 AND 12 THEN '0-12'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 13 AND 18 THEN '13-18'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 19 AND 35 THEN '19-35'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 36 AND 50 THEN '36-50'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 51 AND 65 THEN '51-65'
        ELSE '65+'
    END;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-populate age_group
CREATE OR REPLACE FUNCTION update_patient_age_group()
RETURNS TRIGGER AS $$
BEGIN
    NEW.age_group := calculate_age_group(NEW.date_of_birth);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_patient_age_group
BEFORE INSERT OR UPDATE ON dwh.dim_patient
FOR EACH ROW
EXECUTE FUNCTION update_patient_age_group();

-- Create indexes for dim_patient
CREATE INDEX idx_patient_age_group ON dwh.dim_patient(age_group);
CREATE INDEX idx_patient_chronic ON dwh.dim_patient(is_chronic_patient);
CREATE INDEX idx_patient_active ON dwh.dim_patient(is_active);
CREATE INDEX idx_patient_current ON dwh.dim_patient(is_current);
CREATE INDEX idx_patient_pharmacy ON dwh.dim_patient(primary_pharmacy_key);
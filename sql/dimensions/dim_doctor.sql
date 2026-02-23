CREATE TABLE dwh.dim_doctor (
    doctor_key SERIAL PRIMARY KEY,
    doctor_id VARCHAR(20) NOT NULL UNIQUE,
    hpcsa_registration_number VARCHAR(30) UNIQUE,
    
    -- Personal information
    title VARCHAR(10) DEFAULT 'Dr',
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    
    -- Professional information
    specialty VARCHAR(100),
    sub_specialty VARCHAR(100),
    practice_name VARCHAR(200),
    practice_type VARCHAR(50),
    years_in_practice INTEGER,
    
    -- Contact information
    phone_number VARCHAR(20),
    email VARCHAR(100),
    practice_address VARCHAR(300),
    city VARCHAR(100),
    province VARCHAR(50),
    
    -- Practice patterns (updated periodically)
    average_prescriptions_per_month INTEGER,
    most_prescribed_category VARCHAR(100),
    prescribing_style VARCHAR(30),
    prefers_generic_percentage DECIMAL(5, 2),
    
    -- Relationships
    hospital_affiliations TEXT,
    is_referring_doctor BOOLEAN DEFAULT FALSE,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    registration_date DATE,
    last_prescription_date DATE,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for dim_doctor
CREATE INDEX idx_doctor_specialty ON dwh.dim_doctor(specialty);
CREATE INDEX idx_doctor_active ON dwh.dim_doctor(is_active);
CREATE INDEX idx_doctor_city ON dwh.dim_doctor(city);
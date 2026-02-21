CREATE TABLE dwh.fact_prescription_transactions (
    prescription_transaction_key BIGSERIAL PRIMARY KEY,
    prescription_number VARCHAR(30) NOT NULL UNIQUE,
    
    -- Foreign keys to dimensions
    transaction_date_key INTEGER NOT NULL REFERENCES dwh.dim_date(date_key),
    patient_key INTEGER NOT NULL REFERENCES dwh.dim_patient(patient_key),
    medication_key INTEGER NOT NULL REFERENCES dwh.dim_medication(medication_key),
    doctor_key INTEGER NOT NULL REFERENCES dwh.dim_doctor(doctor_key),
    pharmacy_key INTEGER NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    insurance_key INTEGER REFERENCES dwh.dim_insurance(insurance_key),
    
    -- Degenerate dimensions
    prescription_type VARCHAR(20) NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    dispensing_pharmacist_name VARCHAR(100),
    
    -- Measures
    quantity_dispensed INTEGER NOT NULL CHECK (quantity_dispensed > 0),
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    total_amount DECIMAL(12, 2) NOT NULL CHECK (total_amount >= 0),
    cost_price DECIMAL(10, 2) NOT NULL CHECK (cost_price >= 0),
    insurance_coverage_amount DECIMAL(12, 2) DEFAULT 0.00,
    patient_copay DECIMAL(10, 2) DEFAULT 0.00,
    discount_amount DECIMAL(10, 2) DEFAULT 0.00,
    profit_margin DECIMAL(12, 2) GENERATED ALWAYS AS (total_amount - (cost_price * quantity_dispensed)) STORED,
    days_supply INTEGER CHECK (days_supply > 0),
    refills_remaining SMALLINT DEFAULT 0,
    
    -- Timestamps
    prescription_date DATE NOT NULL,
    dispensing_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT chk_payment_adds_up CHECK (
        total_amount = insurance_coverage_amount + patient_copay + discount_amount
    )
);

-- Create indexes for fact_prescription_transactions
CREATE INDEX idx_fact_rx_date ON dwh.fact_prescription_transactions(transaction_date_key);
CREATE INDEX idx_fact_rx_patient ON dwh.fact_prescription_transactions(patient_key);
CREATE INDEX idx_fact_rx_medication ON dwh.fact_prescription_transactions(medication_key);
CREATE INDEX idx_fact_rx_doctor ON dwh.fact_prescription_transactions(doctor_key);
CREATE INDEX idx_fact_rx_pharmacy ON dwh.fact_prescription_transactions(pharmacy_key);
CREATE INDEX idx_fact_rx_insurance ON dwh.fact_prescription_transactions(insurance_key);
CREATE INDEX idx_fact_rx_type ON dwh.fact_prescription_transactions(prescription_type);
CREATE INDEX idx_fact_rx_timestamp ON dwh.fact_prescription_transactions(dispensing_timestamp);
CREATE TABLE dwh.dim_insurance (
    insurance_key SERIAL PRIMARY KEY,
    insurance_id VARCHAR(20) NOT NULL UNIQUE,
    scheme_code VARCHAR(30) UNIQUE,
    
    -- Provider information
    provider_name VARCHAR(100) NOT NULL,
    scheme_name VARCHAR(200),
    plan_type VARCHAR(50),
    network_type VARCHAR(30),
    
    -- Coverage details
    default_coverage_percentage DECIMAL(5, 2) DEFAULT 80.00,
    annual_limit DECIMAL(12, 2),
    chronic_benefit_available BOOLEAN DEFAULT TRUE,
    chronic_coverage_percentage DECIMAL(5, 2) DEFAULT 100.00,
    default_copay_amount DECIMAL(8, 2),
    dispensing_fee_covered BOOLEAN DEFAULT TRUE,
    
    -- Formulary
    has_formulary_restrictions BOOLEAN DEFAULT FALSE,
    requires_generic_substitution BOOLEAN DEFAULT FALSE,
    requires_pre_authorization BOOLEAN DEFAULT FALSE,
    
    -- Financial
    average_reimbursement_time_days INTEGER,
    payment_reliability_rating VARCHAR(20),
    invoice_submission_method VARCHAR(30),
    
    -- Contact information
    claims_contact_number VARCHAR(20),
    authorization_contact_number VARCHAR(20),
    claims_email VARCHAR(100),
    portal_url VARCHAR(200),
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    contract_start_date DATE,
    contract_end_date DATE,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for dim_insurance
CREATE INDEX idx_insurance_provider ON dwh.dim_insurance(provider_name);
CREATE INDEX idx_insurance_active ON dwh.dim_insurance(is_active);
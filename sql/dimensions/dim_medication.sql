CREATE TABLE dim_medication (
    medication_key SERIAL PRIMARY KEY,
    medication_id VARCHAR(30) NOT NULL,
    barcode VARCHAR(50),
    
    medication_name VARCHAR(200) NOT NULL,
    generic_name VARCHAR(200),
    scientific_name VARCHAR(200),
    manufacturer VARCHAR(100),
    distributor VARCHAR(100),
    
    dosage_form VARCHAR(30) NOT NULL,
    strength VARCHAR(50),
    pack_size INTEGER,
    unit_of_measure VARCHAR(20),
    
    category_key INTEGER REFERENCES dim_medication_category(category_key),
    therapeutic_class VARCHAR(100),
    schedule_classification VARCHAR(10),
    requires_prescription BOOLEAN DEFAULT TRUE,
    is_controlled_substance BOOLEAN DEFAULT FALSE,
    is_generic BOOLEAN DEFAULT FALSE,
    
    unit_cost_price DECIMAL(10, 2) NOT NULL,
    unit_retail_price DECIMAL(10, 2) NOT NULL,
    markup_percentage DECIMAL(5, 2) GENERATED ALWAYS AS (
        ((unit_retail_price - unit_cost_price) / NULLIF(unit_cost_price, 0)) * 100
    ) STORED,
    
    typical_shelf_life_days INTEGER,
    minimum_order_quantity INTEGER DEFAULT 1,
    reorder_lead_time_days INTEGER DEFAULT 3,
    storage_requirements VARCHAR(50) DEFAULT 'Room Temperature',
    is_fragile BOOLEAN DEFAULT FALSE,
    is_high_value BOOLEAN DEFAULT FALSE,
    
    common_side_effects TEXT,
    contraindications TEXT,
    drug_interactions_warning BOOLEAN DEFAULT FALSE,
    
    is_seasonal BOOLEAN DEFAULT FALSE,
    seasonal_peak_months VARCHAR(50),
    average_monthly_demand INTEGER,
    
    effective_date DATE DEFAULT CURRENT_DATE,
    end_date DATE,
    is_current BOOLEAN DEFAULT TRUE,
    version_number INTEGER DEFAULT 1,
    change_reason VARCHAR(100),
    
    is_active BOOLEAN DEFAULT TRUE,
    discontinuation_date DATE,
    replacement_medication_key INTEGER REFERENCES dim_medication(medication_key),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_scd_dates CHECK (end_date IS NULL OR end_date >= effective_date)
);

CREATE INDEX idx_medication_id ON dim_medication(medication_id);
CREATE INDEX idx_medication_name ON dim_medication(medication_name);
CREATE INDEX idx_medication_category ON dim_medication(category_key);
CREATE INDEX idx_medication_current ON dim_medication(is_current);
CREATE INDEX idx_medication_active ON dim_medication(is_active);
CREATE INDEX idx_medication_seasonal ON dim_medication(is_seasonal);
CREATE INDEX idx_medication_therapeutic ON dim_medication(therapeutic_class);
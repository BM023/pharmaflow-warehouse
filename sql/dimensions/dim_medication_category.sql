CREATE TABLE dwh.dim_medication_category (
    category_key SERIAL PRIMARY KEY,
    
    -- Clinical classification
    clinical_category VARCHAR(30) NOT NULL,
    clinical_category_description TEXT,
    
    -- Demand classification
    movement_class VARCHAR(20) NOT NULL,
    movement_threshold_units_per_month INTEGER,
    turnover_rate_category VARCHAR(20),
    
    -- Value classification (ABC)
    value_class CHAR(1) NOT NULL CHECK (value_class IN ('A', 'B', 'C')),
    value_class_description TEXT,
    
    -- Operational classification
    is_critical_stock BOOLEAN DEFAULT FALSE,
    criticality_reason VARCHAR(100),
    requires_cold_chain BOOLEAN DEFAULT FALSE,
    requires_special_handling BOOLEAN DEFAULT FALSE,
    security_level VARCHAR(30) DEFAULT 'Standard',
    
    -- Inventory management
    default_reorder_point_formula VARCHAR(200),
    default_safety_stock_days INTEGER,
    review_frequency VARCHAR(20),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT uq_category_combination UNIQUE (clinical_category, movement_class, value_class)
);

-- Create indexes for dim_medication_category
CREATE INDEX idx_category_clinical ON dwh.dim_medication_category(clinical_category);
CREATE INDEX idx_category_movement ON dwh.dim_medication_category(movement_class);
CREATE INDEX idx_category_value ON dwh.dim_medication_category(value_class);
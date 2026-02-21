CREATE TABLE dwh.fact_stock_adjustments (
    adjustment_key BIGSERIAL PRIMARY KEY,
    adjustment_reference_number VARCHAR(30) NOT NULL UNIQUE,
    
    -- Foreign keys
    adjustment_date_key INTEGER NOT NULL REFERENCES dwh.dim_date(date_key),
    medication_key INTEGER NOT NULL REFERENCES dwh.dim_medication(medication_key),
    pharmacy_key INTEGER NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    
    -- Degenerate dimensions
    adjustment_type VARCHAR(50) NOT NULL,
    adjustment_reason TEXT,
    performed_by VARCHAR(100),
    
    -- Measures
    quantity_adjusted INTEGER NOT NULL,
    cost_impact DECIMAL(12, 2) NOT NULL,
    batch_number_affected VARCHAR(50),
    
    -- Timestamps
    adjustment_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approval_timestamp TIMESTAMP,
    approved_by VARCHAR(100),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fact_adj_date ON fact_stock_adjustments(adjustment_date_key);
CREATE INDEX idx_fact_adj_medication ON fact_stock_adjustments(medication_key);
CREATE INDEX idx_fact_adj_pharmacy ON fact_stock_adjustments(pharmacy_key);
CREATE INDEX idx_fact_adj_type ON fact_stock_adjustments(adjustment_type);




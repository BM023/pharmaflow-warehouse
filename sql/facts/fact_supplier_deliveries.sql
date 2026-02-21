CREATE TABLE dwh.fact_supplier_deliveries (
    delivery_key BIGSERIAL PRIMARY KEY,
    delivery_number VARCHAR(30) NOT NULL UNIQUE,
    purchase_order_number VARCHAR(30),
    
    -- Foreign keys
    delivery_date_key INTEGER NOT NULL REFERENCES dwh.dim_date(date_key),
    ordered_date_key INTEGER NOT NULL REFERENCES dwh.dim_date(date_key),
    supplier_key INTEGER NOT NULL REFERENCES dwh.dim_supplier(supplier_key),
    medication_key INTEGER NOT NULL REFERENCES dwh.dim_medication(medication_key),
    pharmacy_key INTEGER NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    
    -- Degenerate dimensions
    batch_number VARCHAR(50),
    delivery_status VARCHAR(30),
    
    -- Measures
    quantity_ordered INTEGER NOT NULL,
    quantity_delivered INTEGER NOT NULL,
    quantity_damaged INTEGER DEFAULT 0,
    quantity_rejected INTEGER DEFAULT 0,
    unit_cost DECIMAL(10, 2) NOT NULL,
    total_cost DECIMAL(12, 2) NOT NULL,
    expiry_date DATE NOT NULL,
    delivery_lead_time_days INTEGER,
    variance_cost DECIMAL(12, 2),
    
    -- Computed columns
    variance_quantity INTEGER GENERATED ALWAYS AS (quantity_delivered - quantity_ordered) STORED,
    is_complete BOOLEAN GENERATED ALWAYS AS (quantity_delivered >= quantity_ordered) STORED,
    
    -- Quality metrics
    is_on_time BOOLEAN,
    quality_issue_flag BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    ordered_timestamp TIMESTAMP NOT NULL,
    expected_delivery_date DATE,
    actual_delivery_timestamp TIMESTAMP NOT NULL,
    received_by VARCHAR(100),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_fact_del_delivery_date ON fact_supplier_deliveries(delivery_date_key);
CREATE INDEX idx_fact_del_ordered_date ON fact_supplier_deliveries(ordered_date_key);
CREATE INDEX idx_fact_del_supplier ON fact_supplier_deliveries(supplier_key);
CREATE INDEX idx_fact_del_medication ON fact_supplier_deliveries(medication_key);
CREATE INDEX idx_fact_del_pharmacy ON fact_supplier_deliveries(pharmacy_key);
CREATE INDEX idx_fact_del_status ON fact_supplier_deliveries(delivery_status);
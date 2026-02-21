CREATE TABLE dwh.fact_inventory_snapshots (
    inventory_snapshot_key BIGSERIAL PRIMARY KEY,
    
    -- Foreign keys
    snapshot_date_key INTEGER NOT NULL REFERENCES dwh.dim_date(date_key),
    medication_key INTEGER NOT NULL REFERENCES dwh.dim_medication(medication_key),
    pharmacy_key INTEGER NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    
    -- Measures
    quantity_on_hand INTEGER NOT NULL DEFAULT 0,
    quantity_allocated INTEGER DEFAULT 0,
    quantity_on_order INTEGER DEFAULT 0,
    reorder_point INTEGER NOT NULL,
    maximum_stock_level INTEGER,
    quantity_expired_today INTEGER DEFAULT 0,
    quantity_near_expiry INTEGER DEFAULT 0,
    stock_value_at_cost DECIMAL(12, 2) NOT NULL,
    stock_value_at_retail DECIMAL(12, 2) NOT NULL,
    days_until_stockout INTEGER,
    stock_turnover_rate DECIMAL(8, 2),
    
    -- Computed columns
    quantity_available INTEGER GENERATED ALWAYS AS (quantity_on_hand - quantity_allocated) STORED,
    is_out_of_stock BOOLEAN GENERATED ALWAYS AS ((quantity_on_hand - quantity_allocated) <= 0) STORED,
    is_below_reorder_point BOOLEAN GENERATED ALWAYS AS ((quantity_on_hand - quantity_allocated) <= reorder_point) STORED,
    
    -- Other indicators
    is_overstocked BOOLEAN,
    stock_status_code VARCHAR(20),
    
    -- Semi-additive measures
    min_days_until_expiry INTEGER,
    batch_count INTEGER DEFAULT 0,
    
    -- Timestamps
    snapshot_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_stock_count_date DATE,
    
    -- Unique constraint
    CONSTRAINT uq_snapshot_daily UNIQUE (snapshot_date_key, medication_key, pharmacy_key)
);

-- Create indexes for fact_inventory_snapshots
CREATE INDEX idx_fact_inv_date ON dwh.fact_inventory_snapshots(snapshot_date_key);
CREATE INDEX idx_fact_inv_medication ON dwh.fact_inventory_snapshots(medication_key);
CREATE INDEX idx_fact_inv_pharmacy ON dwh.fact_inventory_snapshots(pharmacy_key);
CREATE INDEX idx_fact_inv_status ON dwh.fact_inventory_snapshots(stock_status_code);
CREATE INDEX idx_fact_inv_low_stock ON dwh.fact_inventory_snapshots(is_below_reorder_point) WHERE is_below_reorder_point = TRUE;
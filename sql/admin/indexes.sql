-- =============================================================================
-- sql/admin/indexes.sql
-- PharmaFlow Analytics — Index Audit & Optimisation
--
-- Adds indexes optimised for the most common analytical query patterns:
--   1. Time-series queries (by date range)
--   2. Dimension slice queries (by pharmacy, medication, doctor)
--   3. Payment/type analysis queries
--   4. SCD Type 2 lookups (is_current filters)
--   5. Pipeline monitoring queries
--
-- All indexes use IF NOT EXISTS — safe to re-run.
-- =============================================================================

SET search_path TO dwh, public;

\echo '=================================================='
\echo ' PharmaFlow — Index Optimisation'
\echo '=================================================='

-- ---------------------------------------------------------------------------
-- fact_prescription_transactions
-- Most queried fact table — needs indexes for every common slice dimension
-- ---------------------------------------------------------------------------
\echo '[1] fact_prescription_transactions indexes...'

-- Date range queries (most common analytical pattern)
CREATE INDEX IF NOT EXISTS idx_rx_date_key
    ON dwh.fact_prescription_transactions(transaction_date_key);

-- Revenue by pharmacy
CREATE INDEX IF NOT EXISTS idx_rx_pharmacy
    ON dwh.fact_prescription_transactions(pharmacy_key);

-- Top medications by volume
CREATE INDEX IF NOT EXISTS idx_rx_medication
    ON dwh.fact_prescription_transactions(medication_key);

-- Patient history lookups
CREATE INDEX IF NOT EXISTS idx_rx_patient
    ON dwh.fact_prescription_transactions(patient_key);

-- Doctor prescribing patterns
CREATE INDEX IF NOT EXISTS idx_rx_doctor
    ON dwh.fact_prescription_transactions(doctor_key);

-- Payment method analysis
CREATE INDEX IF NOT EXISTS idx_rx_payment_method
    ON dwh.fact_prescription_transactions(payment_method);

-- Prescription type distribution
CREATE INDEX IF NOT EXISTS idx_rx_type
    ON dwh.fact_prescription_transactions(prescription_type);

-- Composite: date + pharmacy (most common dashboard query)
CREATE INDEX IF NOT EXISTS idx_rx_date_pharmacy
    ON dwh.fact_prescription_transactions(transaction_date_key, pharmacy_key);

-- Composite: date + medication (trend analysis)
CREATE INDEX IF NOT EXISTS idx_rx_date_medication
    ON dwh.fact_prescription_transactions(transaction_date_key, medication_key);

-- Revenue range queries
CREATE INDEX IF NOT EXISTS idx_rx_total_amount
    ON dwh.fact_prescription_transactions(total_amount);

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- fact_inventory_snapshots
-- ---------------------------------------------------------------------------
\echo '[2] fact_inventory_snapshots indexes...'

CREATE INDEX IF NOT EXISTS idx_inv_date_key
    ON dwh.fact_inventory_snapshots(snapshot_date_key);

CREATE INDEX IF NOT EXISTS idx_inv_pharmacy
    ON dwh.fact_inventory_snapshots(pharmacy_key);

CREATE INDEX IF NOT EXISTS idx_inv_medication
    ON dwh.fact_inventory_snapshots(medication_key);

-- Stock status filtering (most common inventory query)
CREATE INDEX IF NOT EXISTS idx_inv_status
    ON dwh.fact_inventory_snapshots(stock_status_code);

-- Composite: latest snapshot per location (dashboard query)
CREATE INDEX IF NOT EXISTS idx_inv_date_pharmacy_med
    ON dwh.fact_inventory_snapshots(snapshot_date_key DESC, pharmacy_key, medication_key);

-- Low stock alerts
CREATE INDEX IF NOT EXISTS idx_inv_low_stock
    ON dwh.fact_inventory_snapshots(stock_status_code, pharmacy_key)
    WHERE stock_status_code IN ('OUT', 'LOW');

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- fact_supplier_deliveries
-- ---------------------------------------------------------------------------
\echo '[3] fact_supplier_deliveries indexes...'

CREATE INDEX IF NOT EXISTS idx_del_date_key
    ON dwh.fact_supplier_deliveries(delivery_date_key);

CREATE INDEX IF NOT EXISTS idx_del_supplier
    ON dwh.fact_supplier_deliveries(supplier_key);

CREATE INDEX IF NOT EXISTS idx_del_pharmacy
    ON dwh.fact_supplier_deliveries(pharmacy_key);

CREATE INDEX IF NOT EXISTS idx_del_medication
    ON dwh.fact_supplier_deliveries(medication_key);

-- On-time delivery analysis
CREATE INDEX IF NOT EXISTS idx_del_on_time
    ON dwh.fact_supplier_deliveries(is_on_time, supplier_key);

-- Quality issue filtering
CREATE INDEX IF NOT EXISTS idx_del_quality
    ON dwh.fact_supplier_deliveries(quality_issue_flag)
    WHERE quality_issue_flag = TRUE;

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- fact_stock_adjustments
-- ---------------------------------------------------------------------------
\echo '[4] fact_stock_adjustments indexes...'

CREATE INDEX IF NOT EXISTS idx_adj_date_key
    ON dwh.fact_stock_adjustments(adjustment_date_key);

CREATE INDEX IF NOT EXISTS idx_adj_type
    ON dwh.fact_stock_adjustments(adjustment_type);

CREATE INDEX IF NOT EXISTS idx_adj_pharmacy
    ON dwh.fact_stock_adjustments(pharmacy_key);

-- Loss analysis (negative cost impact)
CREATE INDEX IF NOT EXISTS idx_adj_cost_impact
    ON dwh.fact_stock_adjustments(cost_impact)
    WHERE cost_impact < 0;

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- Dimension table indexes (SCD Type 2 + lookup optimisation)
-- ---------------------------------------------------------------------------
\echo '[5] Dimension table indexes...'

-- dim_patient: SCD Type 2 lookups
CREATE INDEX IF NOT EXISTS idx_patient_current
    ON dwh.dim_patient(is_current)
    WHERE is_current = TRUE;

CREATE INDEX IF NOT EXISTS idx_patient_id_current
    ON dwh.dim_patient(patient_id, is_current);

CREATE INDEX IF NOT EXISTS idx_patient_chronic
    ON dwh.dim_patient(is_chronic_patient)
    WHERE is_chronic_patient = TRUE;

CREATE INDEX IF NOT EXISTS idx_patient_medical_aid
    ON dwh.dim_patient(has_medical_aid);

-- dim_medication: active medication lookups
CREATE INDEX IF NOT EXISTS idx_med_current
    ON dwh.dim_medication(is_current, is_active)
    WHERE is_current = TRUE AND is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_med_category
    ON dwh.dim_medication(category_key);

CREATE INDEX IF NOT EXISTS idx_med_therapeutic
    ON dwh.dim_medication(therapeutic_class);

-- dim_date: calendar hierarchy queries
CREATE INDEX IF NOT EXISTS idx_date_month_year
    ON dwh.dim_date(year_number, month_number);

CREATE INDEX IF NOT EXISTS idx_date_is_weekend
    ON dwh.dim_date(is_weekend);

-- pipeline_runs monitoring queries
CREATE INDEX IF NOT EXISTS idx_pipeline_run_date
    ON dwh.pipeline_runs(run_date DESC)
    WHERE EXISTS (SELECT 1 FROM information_schema.tables
                  WHERE table_schema = 'dwh' AND table_name = 'pipeline_runs');

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- Index inventory report
-- ---------------------------------------------------------------------------
\echo ''
\echo 'Current index summary:'

SELECT
    t.tablename,
    COUNT(i.indexname)                          AS index_count,
    pg_size_pretty(pg_relation_size('dwh.' || t.tablename)) AS table_size,
    pg_size_pretty(
        pg_total_relation_size('dwh.' || t.tablename) -
        pg_relation_size('dwh.' || t.tablename)
    )                                           AS index_size
FROM pg_tables t
LEFT JOIN pg_indexes i
    ON i.tablename = t.tablename AND i.schemaname = 'dwh'
WHERE t.schemaname = 'dwh'
GROUP BY t.tablename
ORDER BY pg_total_relation_size('dwh.' || t.tablename) DESC;

\echo ''
\echo 'Index optimisation complete.'
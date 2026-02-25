-- =============================================================================
-- sql/monitoring/pipeline_metrics.sql
-- PharmaFlow Analytics — Pipeline Metrics Views
--
-- Creates views consumed by the Streamlit dashboard's Pipeline Health tab.
-- All views are designed to be fast (no full table scans on fact tables).
--
-- Run once: docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse < sql/monitoring/pipeline_metrics.sql
-- =============================================================================

SET search_path TO dwh, public;

\echo '=================================================='
\echo ' PharmaFlow — Pipeline Metrics Views'
\echo '=================================================='

-- ---------------------------------------------------------------------------
-- View 1: Pipeline run summary (for dashboard KPI cards)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_pipeline_summary AS
SELECT
    COUNT(*)                                            AS total_runs,
    COUNT(CASE WHEN status = 'success' THEN 1 END)      AS successful_runs,
    COUNT(CASE WHEN status = 'failed'  THEN 1 END)      AS failed_runs,
    COUNT(CASE WHEN status = 'partial' THEN 1 END)      AS partial_runs,
    ROUND(
        COUNT(CASE WHEN status = 'success' THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1
    )                                                   AS success_rate_pct,
    SUM(rows_loaded)                                    AS total_rows_loaded,
    AVG(duration_seconds)                               AS avg_duration_seconds,
    MAX(run_date)                                       AS last_run_date,
    MAX(started_at)                                     AS last_run_timestamp
FROM dwh.pipeline_runs;

-- ---------------------------------------------------------------------------
-- View 2: Daily pipeline runs (for trend chart)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_pipeline_daily AS
SELECT
    run_date,
    COUNT(*)                                            AS run_count,
    SUM(rows_loaded)                                    AS rows_loaded,
    SUM(rows_skipped)                                   AS rows_skipped,
    SUM(rows_failed)                                    AS rows_failed,
    AVG(duration_seconds)                               AS avg_duration_s,
    MAX(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)  AS had_failure
FROM dwh.pipeline_runs
GROUP BY run_date
ORDER BY run_date DESC;

-- ---------------------------------------------------------------------------
-- View 3: Warehouse growth over time (for dashboard chart)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_warehouse_growth AS
SELECT
    d.full_date                                         AS snapshot_date,
    COUNT(f.prescription_transaction_key)               AS prescriptions_on_day,
    SUM(COUNT(f.prescription_transaction_key)) OVER (
        ORDER BY d.full_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                   AS cumulative_prescriptions,
    SUM(f.total_amount)                                 AS daily_revenue,
    SUM(SUM(f.total_amount)) OVER (
        ORDER BY d.full_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                   AS cumulative_revenue
FROM dwh.dim_date d
LEFT JOIN dwh.fact_prescription_transactions f
    ON d.date_key = f.transaction_date_key
WHERE d.full_date BETWEEN
    (SELECT MIN(prescription_date) FROM dwh.fact_prescription_transactions)
    AND CURRENT_DATE
GROUP BY d.full_date
ORDER BY d.full_date;

-- ---------------------------------------------------------------------------
-- View 4: Business KPIs (for dashboard summary cards)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_business_kpis AS
SELECT
    -- Revenue
    SUM(total_amount)                                   AS total_revenue,
    SUM(profit_margin)                                  AS total_profit,
    ROUND(AVG(total_amount), 2)                         AS avg_transaction_value,
    -- Volume
    COUNT(*)                                            AS total_prescriptions,
    COUNT(DISTINCT patient_key)                         AS unique_patients,
    SUM(quantity_dispensed)                             AS total_units_dispensed,
    -- Payment mix
    COUNT(CASE WHEN payment_method = 'Medical_Aid' THEN 1 END) AS medical_aid_count,
    COUNT(CASE WHEN payment_method = 'Cash'        THEN 1 END) AS cash_count,
    ROUND(
        COUNT(CASE WHEN payment_method = 'Medical_Aid' THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1
    )                                                   AS medical_aid_pct,
    -- Date range
    MIN(prescription_date)                              AS data_from,
    MAX(prescription_date)                              AS data_to
FROM dwh.fact_prescription_transactions;

-- ---------------------------------------------------------------------------
-- View 5: Revenue by pharmacy (for bar chart)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_revenue_by_pharmacy AS
SELECT
    ph.location_name,
    ph.demographic_profile,
    COUNT(f.prescription_transaction_key)               AS prescription_count,
    SUM(f.total_amount)                                 AS total_revenue,
    SUM(f.profit_margin)                                AS total_profit,
    ROUND(AVG(f.total_amount), 2)                       AS avg_transaction,
    ROUND(
        SUM(f.profit_margin) * 100.0
        / NULLIF(SUM(f.total_amount), 0), 1
    )                                                   AS profit_margin_pct
FROM dwh.fact_prescription_transactions f
JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
GROUP BY ph.location_name, ph.demographic_profile
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- View 6: Top medications (for leaderboard)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_top_medications AS
SELECT
    m.medication_name,
    m.therapeutic_class,
    c.clinical_category,
    c.movement_class,
    COUNT(f.prescription_transaction_key)               AS prescription_count,
    SUM(f.quantity_dispensed)                           AS total_units,
    SUM(f.total_amount)                                 AS total_revenue,
    ROUND(AVG(f.total_amount), 2)                       AS avg_revenue_per_rx
FROM dwh.fact_prescription_transactions f
JOIN dwh.dim_medication m          ON f.medication_key = m.medication_key
JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
GROUP BY m.medication_name, m.therapeutic_class, c.clinical_category, c.movement_class
ORDER BY prescription_count DESC;

-- ---------------------------------------------------------------------------
-- View 7: Stock alerts (for inventory monitoring panel)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_stock_alerts AS
SELECT
    ph.location_name,
    m.medication_name,
    m.therapeutic_class,
    f.stock_status_code,
    f.quantity_on_hand,
    f.reorder_point,
    f.stock_value_at_retail,
    CASE
        WHEN f.stock_status_code = 'OUT'  THEN 1
        WHEN f.stock_status_code = 'LOW'  THEN 2
        WHEN f.stock_status_code = 'NEAR_EXPIRY' THEN 3
        ELSE 4
    END                                                 AS urgency_rank
FROM dwh.fact_inventory_snapshots f
JOIN dwh.dim_pharmacy ph   ON f.pharmacy_key   = ph.pharmacy_key
JOIN dwh.dim_medication m  ON f.medication_key = m.medication_key
WHERE f.snapshot_date_key = (
    SELECT MAX(snapshot_date_key) FROM dwh.fact_inventory_snapshots
)
AND f.stock_status_code IN ('OUT', 'LOW', 'NEAR_EXPIRY')
ORDER BY urgency_rank, ph.location_name, m.medication_name;

\echo '  Views created:'
\echo '    v_pipeline_summary, v_pipeline_daily, v_warehouse_growth'
\echo '    v_business_kpis, v_revenue_by_pharmacy, v_top_medications, v_stock_alerts'

-- Show quick check
\echo ''
\echo 'Business KPIs snapshot:'
SELECT
    total_prescriptions,
    total_revenue,
    total_profit,
    unique_patients,
    medical_aid_pct
FROM dwh.v_business_kpis;

\echo ''
\echo 'Pipeline metrics setup complete.'
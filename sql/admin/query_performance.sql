-- =============================================================================
-- Query Performance Analysis
--
-- Runs EXPLAIN ANALYZE on the most common dashboard and analytical queries.
-- Use this to:
--   1. Verify indexes are being used (look for "Index Scan" not "Seq Scan")
--   2. Identify slow queries before they become a problem
--   3. Document baseline performance for the project portfolio
--
-- Run: docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse < sql/admin/query_performance.sql
-- =============================================================================

SET search_path TO dwh, public;

-- Collect statistics first for accurate estimates
ANALYZE dwh.fact_prescription_transactions;
ANALYZE dwh.fact_inventory_snapshots;
ANALYZE dwh.fact_supplier_deliveries;
ANALYZE dwh.fact_stock_adjustments;

\echo '=================================================='
\echo ' PharmaFlow — Query Performance Analysis'
\echo '=================================================='

-- ---------------------------------------------------------------------------
-- Query 1: Monthly revenue by pharmacy (dashboard query)
-- ---------------------------------------------------------------------------
\echo ''
\echo '[Q1] Monthly revenue by pharmacy...'

EXPLAIN ANALYZE
SELECT
    ph.location_name,
    d.year_number,
    d.month_number,
    d.month_name,
    COUNT(*)                    AS prescription_count,
    SUM(f.total_amount)         AS total_revenue,
    SUM(f.profit_margin)        AS total_profit,
    AVG(f.total_amount)         AS avg_transaction_value
FROM dwh.fact_prescription_transactions f
JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
JOIN dwh.dim_date d      ON f.transaction_date_key = d.date_key
WHERE d.year_number = 2025
GROUP BY ph.location_name, d.year_number, d.month_number, d.month_name
ORDER BY d.year_number, d.month_number, total_revenue DESC;

-- ---------------------------------------------------------------------------
-- Query 2: Top 10 medications by prescription volume (last 30 days)
-- ---------------------------------------------------------------------------
\echo ''
\echo '[Q2] Top 10 medications by volume (last 30 days)...'

EXPLAIN ANALYZE
SELECT
    m.medication_name,
    m.therapeutic_class,
    c.clinical_category,
    COUNT(*)                    AS prescription_count,
    SUM(f.quantity_dispensed)   AS total_units_dispensed,
    SUM(f.total_amount)         AS total_revenue
FROM dwh.fact_prescription_transactions f
JOIN dwh.dim_medication m          ON f.medication_key = m.medication_key
JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
JOIN dwh.dim_date d                ON f.transaction_date_key = d.date_key
WHERE d.full_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY m.medication_name, m.therapeutic_class, c.clinical_category
ORDER BY prescription_count DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- Query 3: Current stock status across all pharmacies
-- ---------------------------------------------------------------------------
\echo ''
\echo '[Q3] Current stock status across all pharmacies...'

EXPLAIN ANALYZE
SELECT
    ph.location_name,
    f.stock_status_code,
    COUNT(*)                        AS medication_count,
    SUM(f.stock_value_at_retail)    AS total_stock_value
FROM dwh.fact_inventory_snapshots f
JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
WHERE f.snapshot_date_key = (
    SELECT MAX(snapshot_date_key) FROM dwh.fact_inventory_snapshots
)
GROUP BY ph.location_name, f.stock_status_code
ORDER BY ph.location_name, f.stock_status_code;

-- ---------------------------------------------------------------------------
-- Query 4: Medical aid vs cash payment split by pharmacy
-- ---------------------------------------------------------------------------
\echo ''
\echo '[Q4] Payment method analysis by pharmacy...'

EXPLAIN ANALYZE
SELECT
    ph.location_name,
    f.payment_method,
    COUNT(*)                AS transaction_count,
    SUM(f.total_amount)     AS total_revenue,
    AVG(f.patient_copay)    AS avg_patient_copay
FROM dwh.fact_prescription_transactions f
JOIN dwh.dim_pharmacy ph ON f.pharmacy_key = ph.pharmacy_key
GROUP BY ph.location_name, f.payment_method
ORDER BY ph.location_name, transaction_count DESC;

-- ---------------------------------------------------------------------------
-- Query 5: Patient chronic vs non-chronic prescription patterns
-- ---------------------------------------------------------------------------
\echo ''
\echo '[Q5] Chronic vs non-chronic patient patterns...'

EXPLAIN ANALYZE
SELECT
    p.is_chronic_patient,
    p.age_group,
    COUNT(DISTINCT f.patient_key)   AS unique_patients,
    COUNT(*)                        AS total_prescriptions,
    AVG(f.quantity_dispensed)       AS avg_quantity,
    AVG(f.total_amount)             AS avg_spend
FROM dwh.fact_prescription_transactions f
JOIN dwh.dim_patient p ON f.patient_key = p.patient_key
WHERE p.is_current = TRUE
GROUP BY p.is_chronic_patient, p.age_group
ORDER BY p.is_chronic_patient DESC, p.age_group;

-- ---------------------------------------------------------------------------
-- Index usage report — confirms which indexes are being used
-- ---------------------------------------------------------------------------
\echo ''
\echo 'Index usage report (scans > 0 means index is being used):'

SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan        AS times_used,
    idx_tup_read    AS tuples_read,
    idx_tup_fetch   AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'dwh'
ORDER BY idx_scan DESC, tablename, indexname;

-- ---------------------------------------------------------------------------
-- Table bloat / dead tuple check
-- ---------------------------------------------------------------------------
\echo ''
\echo 'Table health (dead tuples indicate need for VACUUM):'

SELECT
    schemaname,
    relname                         AS tablename,
    n_live_tup                      AS live_rows,
    n_dead_tup                      AS dead_rows,
    CASE
        WHEN n_live_tup > 0
        THEN ROUND(n_dead_tup * 100.0 / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END                             AS dead_row_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
ORDER BY n_dead_tup DESC;

\echo ''
\echo 'Performance analysis complete.'
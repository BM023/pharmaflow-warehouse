-- =============================================================================
-- sql/monitoring/db_health.sql
-- PharmaFlow Analytics — Database Health Monitoring
--
-- Comprehensive health check covering:
--   1. Table sizes and growth
--   2. Index usage statistics
--   3. Query performance (slow query detection)
--   4. Connection statistics
--   5. Vacuum and autovacuum status
--   6. Pipeline run history
--
-- Run: docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse < sql/monitoring/db_health.sql
-- =============================================================================

SET search_path TO dwh, public;

\echo '=================================================='
\echo ' PharmaFlow — Database Health Check'
\echo ' Run at:' :current_timestamp
\echo '=================================================='

-- ---------------------------------------------------------------------------
-- 1. Table sizes and row counts
-- ---------------------------------------------------------------------------
\echo ''
\echo '[1] Table Sizes and Row Counts'
\echo '-------------------------------------------'

SELECT
    t.tablename,
    pg_size_pretty(pg_relation_size('dwh.' || t.tablename))             AS table_size,
    pg_size_pretty(pg_total_relation_size('dwh.' || t.tablename))       AS total_size_with_indexes,
    pg_size_pretty(
        pg_total_relation_size('dwh.' || t.tablename) -
        pg_relation_size('dwh.' || t.tablename)
    )                                                                    AS index_size,
    COALESCE(s.n_live_tup, 0)                                           AS live_rows,
    COALESCE(s.n_dead_tup, 0)                                           AS dead_rows
FROM pg_tables t
LEFT JOIN pg_stat_user_tables s ON s.relname = t.tablename AND s.schemaname = 'dwh'
WHERE t.schemaname = 'dwh'
ORDER BY pg_total_relation_size('dwh.' || t.tablename) DESC;

-- ---------------------------------------------------------------------------
-- 2. Index usage — unused indexes waste write performance
-- ---------------------------------------------------------------------------
\echo ''
\echo '[2] Index Usage (sorted by usage — review unused indexes)'
\echo '-------------------------------------------'

SELECT
    tablename,
    indexname,
    idx_scan                                    AS times_scanned,
    idx_tup_read                                AS rows_read,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    CASE
        WHEN idx_scan = 0 THEN '⚠ UNUSED'
        WHEN idx_scan < 10 THEN 'LOW USE'
        ELSE 'ACTIVE'
    END                                         AS usage_status
FROM pg_stat_user_indexes
WHERE schemaname = 'dwh'
ORDER BY idx_scan DESC, tablename;

-- ---------------------------------------------------------------------------
-- 3. Vacuum status — dead tuples slow queries
-- ---------------------------------------------------------------------------
\echo ''
\echo '[3] Vacuum Status'
\echo '-------------------------------------------'

SELECT
    relname                                     AS table_name,
    n_live_tup                                  AS live_rows,
    n_dead_tup                                  AS dead_rows,
    CASE
        WHEN n_live_tup + n_dead_tup > 0
        THEN ROUND(n_dead_tup * 100.0 / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END                                         AS dead_row_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    CASE
        WHEN n_dead_tup > 1000 THEN '⚠ VACUUM RECOMMENDED'
        ELSE 'OK'
    END                                         AS vacuum_status
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
ORDER BY n_dead_tup DESC;

-- ---------------------------------------------------------------------------
-- 4. Warehouse row count summary
-- ---------------------------------------------------------------------------
\echo ''
\echo '[4] Warehouse Row Count Summary'
\echo '-------------------------------------------'

SELECT table_name, row_count FROM (
    SELECT 'dim_date'                           AS table_name, COUNT(*) AS row_count FROM dwh.dim_date
    UNION ALL SELECT 'dim_patient',              COUNT(*) FROM dwh.dim_patient WHERE is_current = TRUE
    UNION ALL SELECT 'dim_medication',           COUNT(*) FROM dwh.dim_medication WHERE is_current = TRUE
    UNION ALL SELECT 'dim_pharmacy',             COUNT(*) FROM dwh.dim_pharmacy
    UNION ALL SELECT 'dim_doctor',               COUNT(*) FROM dwh.dim_doctor
    UNION ALL SELECT 'dim_insurance',            COUNT(*) FROM dwh.dim_insurance
    UNION ALL SELECT 'dim_supplier',             COUNT(*) FROM dwh.dim_supplier
    UNION ALL SELECT 'dim_medication_category',  COUNT(*) FROM dwh.dim_medication_category
    UNION ALL SELECT 'fact_prescription_transactions', COUNT(*) FROM dwh.fact_prescription_transactions
    UNION ALL SELECT 'fact_inventory_snapshots', COUNT(*) FROM dwh.fact_inventory_snapshots
    UNION ALL SELECT 'fact_supplier_deliveries', COUNT(*) FROM dwh.fact_supplier_deliveries
    UNION ALL SELECT 'fact_stock_adjustments',   COUNT(*) FROM dwh.fact_stock_adjustments
) t ORDER BY
    CASE table_name
        WHEN 'fact_prescription_transactions' THEN 1
        WHEN 'fact_inventory_snapshots'       THEN 2
        WHEN 'fact_supplier_deliveries'       THEN 3
        WHEN 'fact_stock_adjustments'         THEN 4
        ELSE 5
    END;

-- ---------------------------------------------------------------------------
-- 5. Pipeline run history
-- ---------------------------------------------------------------------------
\echo ''
\echo '[5] Pipeline Run History (last 10 runs)'
\echo '-------------------------------------------'

SELECT
    run_id,
    run_date,
    stage,
    rows_loaded,
    rows_skipped,
    rows_failed,
    status,
    duration_seconds        AS duration_s,
    started_at::TIME        AS started_at
FROM dwh.pipeline_runs
ORDER BY started_at DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- 6. Data quality summary (last 7 days)
-- ---------------------------------------------------------------------------
\echo ''
\echo '[6] Data Quality Summary (last 7 days)'
\echo '-------------------------------------------'

SELECT
    run_date,
    dataset,
    total_checks,
    total_rows_checked,
    total_rows_failed,
    overall_failure_rate_pct  AS failure_pct,
    critical_issues,
    warnings
FROM dwh.v_data_quality_summary
WHERE run_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY run_date DESC, dataset;

-- ---------------------------------------------------------------------------
-- 7. Overall warehouse health score
-- ---------------------------------------------------------------------------
\echo ''
\echo '[7] Warehouse Health Score'
\echo '-------------------------------------------'

WITH health_checks AS (
    SELECT
        -- Check 1: All fact tables have data
        (SELECT COUNT(*) FROM dwh.fact_prescription_transactions) > 0  AS has_prescriptions,
        (SELECT COUNT(*) FROM dwh.fact_inventory_snapshots) > 0        AS has_inventory,
        -- Check 2: Dimensions populated
        (SELECT COUNT(*) FROM dwh.dim_patient WHERE is_current = TRUE) > 0  AS has_patients,
        (SELECT COUNT(*) FROM dwh.dim_medication WHERE is_current = TRUE) > 0 AS has_medications,
        -- Check 3: Recent data (last 7 days)
        (SELECT MAX(full_date) FROM dwh.dim_date
         JOIN dwh.fact_prescription_transactions f
         ON dim_date.date_key = f.transaction_date_key
        ) >= CURRENT_DATE - INTERVAL '7 days'  AS has_recent_data,
        -- Check 4: Pipeline has run recently
        EXISTS (
            SELECT 1 FROM dwh.pipeline_runs
            WHERE run_date >= CURRENT_DATE - INTERVAL '7 days'
            AND status = 'success'
        )  AS pipeline_healthy
)
SELECT
    CASE WHEN has_prescriptions THEN '✓' ELSE '✗' END  AS prescriptions_loaded,
    CASE WHEN has_inventory     THEN '✓' ELSE '✗' END  AS inventory_loaded,
    CASE WHEN has_patients      THEN '✓' ELSE '✗' END  AS patients_loaded,
    CASE WHEN has_medications   THEN '✓' ELSE '✗' END  AS medications_loaded,
    CASE WHEN has_recent_data   THEN '✓' ELSE '✗' END  AS recent_data_present,
    CASE WHEN pipeline_healthy  THEN '✓' ELSE '✗' END  AS pipeline_ran_recently,
    (
        (CASE WHEN has_prescriptions THEN 1 ELSE 0 END) +
        (CASE WHEN has_inventory     THEN 1 ELSE 0 END) +
        (CASE WHEN has_patients      THEN 1 ELSE 0 END) +
        (CASE WHEN has_medications   THEN 1 ELSE 0 END) +
        (CASE WHEN has_recent_data   THEN 1 ELSE 0 END) +
        (CASE WHEN pipeline_healthy  THEN 1 ELSE 0 END)
    ) * 100 / 6                                        AS health_score_pct
FROM health_checks;

\echo ''
\echo 'Health check complete.'
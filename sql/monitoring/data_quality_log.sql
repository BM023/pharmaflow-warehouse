-- =============================================================================
-- sql/monitoring/data_quality_log.sql
-- PharmaFlow Analytics — Data Quality Monitoring
--
-- Creates a data_quality_log table to track quality issues detected
-- during each ETL run, and views for dashboard consumption.
--
-- Run once: docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse < sql/monitoring/data_quality_log.sql
-- =============================================================================

SET search_path TO dwh, public;

\echo '=================================================='
\echo ' PharmaFlow — Data Quality Monitoring Setup'
\echo '=================================================='

-- ---------------------------------------------------------------------------
-- Data quality log table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dwh.data_quality_log (
    log_id              BIGSERIAL     PRIMARY KEY,
    run_date            DATE          NOT NULL,
    pipeline_run_id     BIGINT,       -- FK to pipeline_runs if available
    dataset             VARCHAR(50)   NOT NULL,  -- prescriptions/inventory/patients
    source_file         VARCHAR(255),
    check_name          VARCHAR(100)  NOT NULL,
    check_category      VARCHAR(50)   NOT NULL,  -- completeness/validity/consistency/timeliness
    rows_checked        INTEGER       DEFAULT 0,
    rows_passed         INTEGER       DEFAULT 0,
    rows_failed         INTEGER       DEFAULT 0,
    failure_rate_pct    DECIMAL(5,2)
        GENERATED ALWAYS AS (
            CASE WHEN rows_checked > 0
                 THEN ROUND(rows_failed * 100.0 / rows_checked, 2)
                 ELSE 0
            END
        ) STORED,
    severity            VARCHAR(20)   DEFAULT 'WARNING',  -- INFO / WARNING / CRITICAL
    details             TEXT,
    logged_at           TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_dq_run_date
    ON dwh.data_quality_log(run_date DESC);

CREATE INDEX IF NOT EXISTS idx_dq_dataset
    ON dwh.data_quality_log(dataset);

CREATE INDEX IF NOT EXISTS idx_dq_severity
    ON dwh.data_quality_log(severity)
    WHERE severity IN ('WARNING', 'CRITICAL');

\echo '  data_quality_log table created.'

-- ---------------------------------------------------------------------------
-- Seed with quality issues detected from existing data
-- (reflects issues the transform module fixed)
-- ---------------------------------------------------------------------------
INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'prescriptions',
    'prescriptions_2026-02-21.csv',
    'duplicate_prescription_numbers',
    'consistency',
    105, 100, 5,
    'WARNING',
    '5% duplicate prescription records detected and removed during transform'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'duplicate_prescription_numbers' AND run_date = CURRENT_DATE
);

INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'prescriptions',
    'prescriptions_2026-02-21.csv',
    'currency_format_errors',
    'validity',
    105, 102, 3,
    'INFO',
    '3% of total_amount values had R prefix — stripped during transform'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'currency_format_errors' AND run_date = CURRENT_DATE
);

INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'prescriptions',
    'prescriptions_2026-02-21.csv',
    'outlier_quantities',
    'validity',
    105, 103, 2,
    'WARNING',
    '2% of quantity_dispensed values were outliers (0, negative, or >365) — removed'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'outlier_quantities' AND run_date = CURRENT_DATE
);

INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'inventory',
    'inventory_snapshot_2026-02-21.xlsx',
    'negative_quantities',
    'validity',
    300, 294, 6,
    'WARNING',
    '2% of quantity_on_hand values were negative — corrected to 0'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'negative_quantities' AND run_date = CURRENT_DATE
);

INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'inventory',
    'inventory_snapshot_2026-02-21.xlsx',
    'pharmacy_id_typos',
    'validity',
    300, 291, 9,
    'INFO',
    '3% of pharmacy_id values had trailing X typo — corrected'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'pharmacy_id_typos' AND run_date = CURRENT_DATE
);

INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'patients',
    'new_patients.csv',
    'invalid_email_format',
    'validity',
    7, 6, 1,
    'INFO',
    'Invalid email format (AT instead of @) detected and corrected'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'invalid_email_format' AND run_date = CURRENT_DATE
);

INSERT INTO dwh.data_quality_log (
    run_date, dataset, source_file, check_name, check_category,
    rows_checked, rows_passed, rows_failed, severity, details
)
SELECT
    CURRENT_DATE,
    'medications',
    'medication_catalog.json',
    'missing_required_fields',
    'completeness',
    63, 60, 3,
    'WARNING',
    '3 medication records missing medication_id or medication_name — skipped'
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.data_quality_log
    WHERE check_name = 'missing_required_fields' AND run_date = CURRENT_DATE
);

\echo '  Seed data quality records inserted.'

-- ---------------------------------------------------------------------------
-- View: daily quality summary for dashboard
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_data_quality_summary AS
SELECT
    run_date,
    dataset,
    COUNT(*)                                    AS total_checks,
    SUM(rows_checked)                           AS total_rows_checked,
    SUM(rows_failed)                            AS total_rows_failed,
    ROUND(SUM(rows_failed) * 100.0 /
          NULLIF(SUM(rows_checked), 0), 2)      AS overall_failure_rate_pct,
    COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) AS critical_issues,
    COUNT(CASE WHEN severity = 'WARNING'  THEN 1 END) AS warnings,
    COUNT(CASE WHEN severity = 'INFO'     THEN 1 END) AS info_items
FROM dwh.data_quality_log
GROUP BY run_date, dataset
ORDER BY run_date DESC, dataset;

-- ---------------------------------------------------------------------------
-- View: quality trend over time (for dashboard chart)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_quality_trend AS
SELECT
    run_date,
    SUM(rows_checked)                           AS total_rows_checked,
    SUM(rows_passed)                            AS total_rows_passed,
    SUM(rows_failed)                            AS total_rows_failed,
    ROUND(SUM(rows_passed) * 100.0 /
          NULLIF(SUM(rows_checked), 0), 2)      AS pass_rate_pct,
    COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) AS critical_count
FROM dwh.data_quality_log
GROUP BY run_date
ORDER BY run_date DESC;

\echo '  Views created: v_data_quality_summary, v_quality_trend'

-- Show current quality summary
\echo ''
\echo 'Current data quality summary:'
SELECT * FROM dwh.v_data_quality_summary;

\echo ''
\echo 'Data quality monitoring setup complete.'
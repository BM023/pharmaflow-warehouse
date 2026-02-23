-- =============================================================================
-- sql/admin/partitioning.sql
-- PharmaFlow Analytics — Table Partitioning
--
-- Partitions fact_prescription_transactions by year using PostgreSQL
-- declarative partitioning (RANGE on transaction_date_key).
--
-- Strategy:
--   - Create new partitioned table
--   - Copy data from existing table
--   - Swap tables
--   - Create partitions for 2024-2027
--
-- WHY: As prescription volume grows (millions of rows/year), partitioning
-- allows PostgreSQL to scan only the relevant year partition for date-range
-- queries, dramatically reducing query time and enabling faster vacuuming.
--
-- Run: docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse < sql/admin/partitioning.sql
-- =============================================================================

SET search_path TO dwh, public;

\echo '=================================================='
\echo ' PharmaFlow — Table Partitioning'
\echo '=================================================='
\echo ''
\echo 'IMPORTANT: This script migrates fact_prescription_transactions'
\echo 'to a partitioned table. Existing data is preserved.'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 1: Create the new partitioned table
-- ---------------------------------------------------------------------------
\echo '[1] Creating partitioned table...'

CREATE TABLE IF NOT EXISTS dwh.fact_prescription_transactions_partitioned (
    prescription_key            BIGSERIAL,
    prescription_number         VARCHAR(30)    NOT NULL,
    transaction_date_key        INTEGER        NOT NULL,
    patient_key                 INTEGER        NOT NULL,
    medication_key              INTEGER        NOT NULL,
    doctor_key                  INTEGER        NOT NULL,
    pharmacy_key                INTEGER        NOT NULL,
    insurance_key               INTEGER,
    prescription_type           VARCHAR(20),
    payment_method              VARCHAR(20),
    dispensing_pharmacist_name  VARCHAR(100),
    quantity_dispensed          INTEGER        NOT NULL,
    unit_price                  DECIMAL(10,2)  NOT NULL,
    total_amount                DECIMAL(12,2)  NOT NULL,
    cost_price                  DECIMAL(10,2),
    profit_margin               DECIMAL(12,2)
        GENERATED ALWAYS AS (total_amount - COALESCE(cost_price * quantity_dispensed, 0)) STORED,
    insurance_coverage_amount   DECIMAL(12,2)  DEFAULT 0,
    patient_copay               DECIMAL(12,2)  DEFAULT 0,
    discount_amount             DECIMAL(12,2)  DEFAULT 0,
    days_supply                 INTEGER,
    refills_remaining           INTEGER,
    prescription_date           DATE,
    dispensing_timestamp        TIMESTAMP,
    created_at                  TIMESTAMP      DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (transaction_date_key);

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- Step 2: Create year partitions (2024-2027)
-- ---------------------------------------------------------------------------
\echo '[2] Creating year partitions...'

-- 2024
CREATE TABLE IF NOT EXISTS dwh.fact_rx_2024
    PARTITION OF dwh.fact_prescription_transactions_partitioned
    FOR VALUES FROM (20240101) TO (20250101);

-- 2025
CREATE TABLE IF NOT EXISTS dwh.fact_rx_2025
    PARTITION OF dwh.fact_prescription_transactions_partitioned
    FOR VALUES FROM (20250101) TO (20260101);

-- 2026
CREATE TABLE IF NOT EXISTS dwh.fact_rx_2026
    PARTITION OF dwh.fact_prescription_transactions_partitioned
    FOR VALUES FROM (20260101) TO (20270101);

-- 2027 (future)
CREATE TABLE IF NOT EXISTS dwh.fact_rx_2027
    PARTITION OF dwh.fact_prescription_transactions_partitioned
    FOR VALUES FROM (20270101) TO (20280101);

\echo '   Partitions created: 2024, 2025, 2026, 2027'

-- ---------------------------------------------------------------------------
-- Step 3: Add indexes to partitioned table
-- ---------------------------------------------------------------------------
\echo '[3] Adding indexes to partitioned table...'

CREATE INDEX IF NOT EXISTS idx_rx_part_date
    ON dwh.fact_prescription_transactions_partitioned(transaction_date_key);

CREATE INDEX IF NOT EXISTS idx_rx_part_pharmacy
    ON dwh.fact_prescription_transactions_partitioned(pharmacy_key);

CREATE INDEX IF NOT EXISTS idx_rx_part_medication
    ON dwh.fact_prescription_transactions_partitioned(medication_key);

CREATE INDEX IF NOT EXISTS idx_rx_part_patient
    ON dwh.fact_prescription_transactions_partitioned(patient_key);

CREATE INDEX IF NOT EXISTS idx_rx_part_payment
    ON dwh.fact_prescription_transactions_partitioned(payment_method);

\echo '   Done.'

-- ---------------------------------------------------------------------------
-- Step 4: Copy data from existing table
-- ---------------------------------------------------------------------------
\echo '[4] Migrating existing data...'

INSERT INTO dwh.fact_prescription_transactions_partitioned (
    prescription_number, transaction_date_key, patient_key, medication_key,
    doctor_key, pharmacy_key, insurance_key, prescription_type, payment_method,
    dispensing_pharmacist_name, quantity_dispensed, unit_price, total_amount,
    cost_price, insurance_coverage_amount, patient_copay, discount_amount,
    days_supply, refills_remaining, prescription_date, dispensing_timestamp,
    created_at
)
SELECT
    prescription_number, transaction_date_key, patient_key, medication_key,
    doctor_key, pharmacy_key, insurance_key, prescription_type, payment_method,
    dispensing_pharmacist_name, quantity_dispensed, unit_price, total_amount,
    cost_price, insurance_coverage_amount, patient_copay, discount_amount,
    days_supply, refills_remaining, prescription_date, dispensing_timestamp,
    created_at
FROM dwh.fact_prescription_transactions
ON CONFLICT DO NOTHING;

\echo '   Data migrated.'

-- ---------------------------------------------------------------------------
-- Step 5: Verify row counts match
-- ---------------------------------------------------------------------------
\echo '[5] Verifying row counts...'

SELECT
    'Original table'       AS source,
    COUNT(*)               AS row_count
FROM dwh.fact_prescription_transactions
UNION ALL
SELECT
    'Partitioned table',
    COUNT(*)
FROM dwh.fact_prescription_transactions_partitioned
UNION ALL
SELECT
    '  → 2024 partition',
    COUNT(*)
FROM dwh.fact_rx_2024
UNION ALL
SELECT
    '  → 2025 partition',
    COUNT(*)
FROM dwh.fact_rx_2025
UNION ALL
SELECT
    '  → 2026 partition',
    COUNT(*)
FROM dwh.fact_rx_2026;

-- ---------------------------------------------------------------------------
-- Step 6: Partition size report
-- ---------------------------------------------------------------------------
\echo ''
\echo 'Partition size report:'

SELECT
    child.relname                               AS partition_name,
    pg_size_pretty(pg_relation_size(child.oid)) AS partition_size,
    pg_stat_user_tables.n_live_tup              AS row_estimate
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
LEFT JOIN pg_stat_user_tables ON pg_stat_user_tables.relname = child.relname
WHERE parent.relname = 'fact_prescription_transactions_partitioned'
ORDER BY child.relname;

\echo ''
\echo 'Partitioning complete.'
\echo ''
\echo 'NOTE: The original fact_prescription_transactions table is preserved.'
\echo 'To swap to the partitioned version, update your ETL load.py to'
\echo 'insert into fact_prescription_transactions_partitioned instead.'
\echo 'When ready: ALTER TABLE dwh.fact_prescription_transactions RENAME TO fact_rx_unpartitioned_backup;'
\echo '            ALTER TABLE dwh.fact_prescription_transactions_partitioned RENAME TO fact_prescription_transactions;'
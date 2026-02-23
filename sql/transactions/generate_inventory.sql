-- =============================================================================
-- generate_inventory.sql
-- Generates fact_inventory_snapshots records.
-- Grain: one row per medication per pharmacy per day.
--
-- For production volume use: python python/generate_inventory.py
--
-- This script covers 2025-08-01 to 2026-02-20:
--   60 medications × 5 pharmacies × ~205 days ≈ 61,500 rows
--   (respects the uq_snapshot_daily unique constraint)
-- =============================================================================
SET search_path TO dwh, public;

\echo 'Generating inventory snapshots...'

DO $$
DECLARE
    v_start_date    DATE    := '2025-08-01';
    v_end_date      DATE    := '2026-02-20';
    v_date          DATE;
    v_date_key      INTEGER;
    v_med_key       INTEGER;
    v_pharm_key     INTEGER;
    v_cost_price    DECIMAL(10,2);
    v_retail_price  DECIMAL(10,2);
    v_is_seasonal   BOOLEAN;
    v_peak_months   VARCHAR(50);
    v_is_peak       BOOLEAN;
    v_month         INTEGER;
    v_on_hand       INTEGER;
    v_allocated     INTEGER;
    v_on_order      INTEGER;
    v_reorder_pt    INTEGER;
    v_max_stock     INTEGER;
    v_expired_today INTEGER;
    v_near_expiry   INTEGER;
    v_status_code   VARCHAR(20);
    v_is_over       BOOLEAN;
    v_days_out      INTEGER;
    v_turnover      DECIMAL(8,2);
    v_generated     INTEGER := 0;
BEGIN
    v_date := v_start_date;
    WHILE v_date <= v_end_date LOOP

        SELECT date_key INTO v_date_key
        FROM   dwh.dim_date WHERE full_date = v_date;

        IF v_date_key IS NOT NULL THEN
            v_month := EXTRACT(MONTH FROM v_date)::INTEGER;

            FOR v_pharm_key IN
                SELECT pharmacy_key FROM dwh.dim_pharmacy WHERE is_active = TRUE
            LOOP
                FOR v_med_key, v_cost_price, v_retail_price, v_is_seasonal, v_peak_months IN
                    SELECT medication_key, unit_cost_price, unit_retail_price,
                           is_seasonal, seasonal_peak_months
                    FROM   dwh.dim_medication
                    WHERE  is_active = TRUE AND is_current = TRUE
                LOOP
                    -- Skip if already loaded (idempotent)
                    IF EXISTS (
                        SELECT 1 FROM dwh.fact_inventory_snapshots
                        WHERE  snapshot_date_key = v_date_key
                          AND  medication_key    = v_med_key
                          AND  pharmacy_key      = v_pharm_key
                    ) THEN CONTINUE; END IF;

                    -- Is this a seasonal peak month?
                    v_is_peak := v_is_seasonal AND
                                 v_peak_months IS NOT NULL AND
                                 v_peak_months LIKE '%' || v_month::TEXT || '%';

                    -- Base stock levels depend on medication type
                    v_max_stock  := CASE WHEN v_is_peak THEN (RANDOM()*300+200)::INTEGER
                                         ELSE (RANDOM()*200+50)::INTEGER END;
                    v_reorder_pt := (v_max_stock * 0.25)::INTEGER;

                    -- Simulate realistic on-hand: mostly OK, some low, occasional out
                    v_on_hand := CASE
                        WHEN RANDOM() < 0.05 THEN 0                                          -- 5% out of stock
                        WHEN RANDOM() < 0.12 THEN (v_reorder_pt * RANDOM())::INTEGER          -- 7% below reorder
                        ELSE (v_reorder_pt + RANDOM() * (v_max_stock - v_reorder_pt))::INTEGER
                    END;

                    -- Overstock (5% chance, usually right after delivery)
                    IF RANDOM() < 0.05 THEN
                        v_on_hand := (v_max_stock * 1.2)::INTEGER;
                    END IF;

                    v_allocated     := CASE WHEN v_on_hand > 5 THEN (RANDOM() * 5)::INTEGER ELSE 0 END;
                    v_on_order      := CASE WHEN v_on_hand <= v_reorder_pt THEN
                                               (v_max_stock - v_on_hand)
                                           ELSE 0 END;
                    v_expired_today := CASE WHEN RANDOM() < 0.02 THEN (RANDOM() * 3)::INTEGER ELSE 0 END;
                    v_near_expiry   := CASE WHEN RANDOM() < 0.10 THEN (RANDOM() * 20 + 1)::INTEGER ELSE 0 END;

                    -- Stock status
                    v_is_over := v_on_hand > v_max_stock;
                    v_status_code := CASE
                        WHEN (v_on_hand - v_allocated) <= 0               THEN 'OUT'
                        WHEN v_near_expiry > 0                             THEN 'NEAR_EXPIRY'
                        WHEN v_is_over                                     THEN 'OVERSTOCKED'
                        WHEN (v_on_hand - v_allocated) <= v_reorder_pt    THEN 'LOW'
                        ELSE 'OK'
                    END;

                    -- Days until stockout (rough estimate)
                    v_days_out := CASE
                        WHEN v_on_hand <= 0 THEN 0
                        ELSE LEAST((v_on_hand - v_allocated) / GREATEST((v_max_stock / 30), 1), 999)
                    END;

                    -- Turnover rate (annualised)
                    v_turnover := ROUND((12.0 / GREATEST(v_max_stock / GREATEST((v_max_stock * 0.6)::INTEGER, 1), 1)) * 12, 2);

                    BEGIN
                        INSERT INTO dwh.fact_inventory_snapshots (
                            snapshot_date_key, medication_key, pharmacy_key,
                            quantity_on_hand, quantity_allocated, quantity_on_order,
                            reorder_point, maximum_stock_level,
                            quantity_expired_today, quantity_near_expiry,
                            stock_value_at_cost, stock_value_at_retail,
                            days_until_stockout, stock_turnover_rate,
                            is_overstocked, stock_status_code,
                            min_days_until_expiry, batch_count,
                            snapshot_timestamp
                        ) VALUES (
                            v_date_key, v_med_key, v_pharm_key,
                            v_on_hand, v_allocated, v_on_order,
                            v_reorder_pt, v_max_stock,
                            v_expired_today, v_near_expiry,
                            ROUND(v_on_hand * v_cost_price, 2),
                            ROUND(v_on_hand * v_retail_price, 2),
                            v_days_out, v_turnover,
                            v_is_over, v_status_code,
                            CASE WHEN RANDOM() < 0.1 THEN (RANDOM() * 90 + 1)::INTEGER ELSE NULL END,
                            (RANDOM() * 4 + 1)::INTEGER,
                            v_date::TIMESTAMP + INTERVAL '7 hours' + (RANDOM() * INTERVAL '1 hour')
                        );
                        v_generated := v_generated + 1;
                    EXCEPTION WHEN unique_violation THEN
                        NULL;
                    END;

                END LOOP; -- medication
            END LOOP; -- pharmacy
        END IF;

        v_date := v_date + INTERVAL '1 day';
    END LOOP;

    RAISE NOTICE 'Generated % inventory snapshot rows.', v_generated;
END $$;

-- Verification
SELECT
    stock_status_code,
    COUNT(*)                                    AS snapshot_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM dwh.fact_inventory_snapshots
GROUP BY stock_status_code
ORDER BY snapshot_count DESC;

SELECT
    MIN(snapshot_timestamp)::DATE AS earliest,
    MAX(snapshot_timestamp)::DATE AS latest,
    COUNT(DISTINCT snapshot_date_key) AS days_covered,
    COUNT(*) AS total_rows
FROM dwh.fact_inventory_snapshots;
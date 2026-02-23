-- =============================================================================
-- generate_deliveries.sql
-- Generates fact_supplier_deliveries AND fact_stock_adjustments records.
--
-- For production volume use:
--   python python/generate_deliveries.py
--   python python/generate_adjustments.py
--
-- Deliveries : ~500 rows (4 suppliers × 5 pharmacies × ~25 deliveries each)
-- Adjustments: ~200 rows (realistic disposal, damage, count corrections)
-- =============================================================================
SET search_path TO dwh, public;

\echo 'Generating supplier deliveries...'

DO $$
DECLARE
    v_start_date        DATE    := '2025-08-01';
    v_end_date          DATE    := '2026-02-20';
    v_target_rows       INTEGER := 500;
    v_generated         INTEGER := 0;
    v_date              DATE;
    v_ordered_date      DATE;
    v_delivery_date_key INTEGER;
    v_ordered_date_key  INTEGER;
    v_sup_key           INTEGER;
    v_med_key           INTEGER;
    v_pharm_key         INTEGER;
    v_unit_cost         DECIMAL(10,2);
    v_qty_ordered       INTEGER;
    v_qty_delivered     INTEGER;
    v_qty_damaged       INTEGER;
    v_qty_rejected      INTEGER;
    v_total_cost        DECIMAL(12,2);
    v_expiry_date       DATE;
    v_lead_time         INTEGER;
    v_status            VARCHAR(30);
    v_is_on_time        BOOLEAN;
    v_quality_issue     BOOLEAN;
    v_expected_date     DATE;
    v_del_num           VARCHAR(30);
    v_po_num            VARCHAR(30);
    v_batch             VARCHAR(50);
    v_seq               INTEGER := 1;
    v_date_range        INTEGER;
    v_receivers         TEXT[]  := ARRAY[
        'T. Ndlovu','S. Mokoena','N. Khumalo','L. Mahlangu','Z. Sithole'
    ];
    v_sup_lead          INTEGER;
BEGIN
    v_date_range := v_end_date - v_start_date;

    WHILE v_generated < v_target_rows LOOP

        -- Delivery date
        v_date := v_start_date + (RANDOM() * v_date_range)::INTEGER;
        SELECT date_key INTO v_delivery_date_key
        FROM   dwh.dim_date WHERE full_date = v_date;
        IF v_delivery_date_key IS NULL THEN CONTINUE; END IF;

        -- Supplier (with lead time)
        SELECT supplier_key, COALESCE(average_delivery_lead_time_days, 3)
        INTO   v_sup_key, v_sup_lead
        FROM   dwh.dim_supplier WHERE is_active = TRUE ORDER BY RANDOM() LIMIT 1;

        -- Ordered date = delivery date minus lead time (+ small jitter)
        v_lead_time   := v_sup_lead + (RANDOM() * 2 - 1)::INTEGER;
        v_ordered_date := v_date - (v_sup_lead + (RANDOM() * 3)::INTEGER);
        SELECT date_key INTO v_ordered_date_key
        FROM   dwh.dim_date WHERE full_date = v_ordered_date;
        IF v_ordered_date_key IS NULL THEN CONTINUE; END IF;

        -- Medication
        SELECT medication_key, unit_cost_price
        INTO   v_med_key, v_unit_cost
        FROM   dwh.dim_medication
        WHERE  is_active = TRUE AND is_current = TRUE ORDER BY RANDOM() LIMIT 1;
        IF v_med_key IS NULL THEN CONTINUE; END IF;

        -- Pharmacy
        SELECT pharmacy_key INTO v_pharm_key
        FROM   dwh.dim_pharmacy WHERE is_active = TRUE ORDER BY RANDOM() LIMIT 1;

        -- Quantities
        v_qty_ordered   := (RANDOM() * 150 + 20)::INTEGER;
        v_qty_damaged   := CASE WHEN RANDOM() < 0.05 THEN (RANDOM() * 5)::INTEGER ELSE 0 END;
        v_qty_rejected  := CASE WHEN RANDOM() < 0.03 THEN (RANDOM() * 3)::INTEGER ELSE 0 END;
        v_qty_delivered := CASE
            WHEN RANDOM() < 0.92 THEN v_qty_ordered                                        -- complete
            ELSE (v_qty_ordered * (0.7 + RANDOM() * 0.25))::INTEGER                        -- partial
        END;
        v_total_cost    := ROUND(v_qty_delivered * v_unit_cost * (1 - RANDOM() * 0.05), 2);

        -- Expiry date: 6 months to 3 years from delivery
        v_expiry_date := v_date + ((180 + RANDOM() * 900)::INTEGER || ' days')::INTERVAL;

        -- Delivery status
        v_status := CASE
            WHEN v_qty_rejected > 0                THEN 'Rejected'
            WHEN v_qty_damaged  > 0                THEN 'Damaged'
            WHEN v_qty_delivered < v_qty_ordered   THEN 'Partial'
            ELSE                                        'Complete'
        END;

        -- On-time check (expected delivery date)
        v_expected_date := v_ordered_date + v_sup_lead;
        v_is_on_time    := v_date <= v_expected_date;
        v_quality_issue := v_qty_damaged > 0 OR v_qty_rejected > 0;

        v_del_num := 'DEL-' || TO_CHAR(v_date, 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 4, '0');
        v_po_num  := 'PO-'  || TO_CHAR(v_ordered_date, 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 4, '0');
        v_batch   := 'BATCH-' || UPPER(SUBSTRING(MD5(v_seq::TEXT), 1, 8));
        v_seq     := v_seq + 1;

        BEGIN
            INSERT INTO dwh.fact_supplier_deliveries (
                delivery_number, purchase_order_number,
                delivery_date_key, ordered_date_key,
                supplier_key, medication_key, pharmacy_key,
                batch_number, delivery_status,
                quantity_ordered, quantity_delivered, quantity_damaged, quantity_rejected,
                unit_cost, total_cost, expiry_date,
                delivery_lead_time_days, variance_cost,
                is_on_time, quality_issue_flag,
                ordered_timestamp, expected_delivery_date, actual_delivery_timestamp,
                received_by
            ) VALUES (
                v_del_num, v_po_num,
                v_delivery_date_key, v_ordered_date_key,
                v_sup_key, v_med_key, v_pharm_key,
                v_batch, v_status,
                v_qty_ordered, v_qty_delivered, v_qty_damaged, v_qty_rejected,
                v_unit_cost, v_total_cost, v_expiry_date,
                v_lead_time,
                ROUND((v_qty_delivered - v_qty_ordered) * v_unit_cost, 2),
                v_is_on_time, v_quality_issue,
                v_ordered_date::TIMESTAMP + INTERVAL '9 hours',
                v_expected_date,
                v_date::TIMESTAMP + INTERVAL '10 hours' + (RANDOM() * INTERVAL '6 hours'),
                v_receivers[CEIL(RANDOM() * ARRAY_LENGTH(v_receivers, 1))::INTEGER]
            );
            v_generated := v_generated + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;

    END LOOP;
    RAISE NOTICE 'Generated % delivery records.', v_generated;
END $$;

-- ============================================================================
-- Stock Adjustments
-- ============================================================================
\echo 'Generating stock adjustments...'

DO $$
DECLARE
    v_start_date      DATE    := '2025-08-01';
    v_end_date        DATE    := '2026-02-20';
    v_target_rows     INTEGER := 200;
    v_generated       INTEGER := 0;
    v_date            DATE;
    v_date_key        INTEGER;
    v_med_key         INTEGER;
    v_pharm_key       INTEGER;
    v_cost_price      DECIMAL(10,2);
    v_adj_type        VARCHAR(50);
    v_qty             INTEGER;
    v_cost_impact     DECIMAL(12,2);
    v_ref_num         VARCHAR(30);
    v_batch           VARCHAR(50);
    v_seq             INTEGER := 1;
    v_date_range      INTEGER;
    v_adj_types       TEXT[]  := ARRAY[
        'Expired_Disposal','Damaged','Theft','Count_Correction',
        'Return_to_Supplier','Transfer_In','Transfer_Out'
    ];
    v_reasons         TEXT[]  := ARRAY[
        'Exceeded expiry date — disposed per SOP',
        'Damaged in handling — written off',
        'Missing stock — reported to management',
        'Physical count variance corrected',
        'Returned to supplier — damaged on delivery',
        'Stock transferred in from Sandton branch',
        'Stock transferred out to Soweto branch'
    ];
    v_staff           TEXT[]  := ARRAY[
        'T. Ndlovu','S. Mokoena','N. Khumalo','L. Mahlangu','Z. Sithole',
        'B. Mthembu','A. Dlamini'
    ];
    v_approvers       TEXT[]  := ARRAY[
        'Dr. S. Nkosi','Dr. J. Maseko','Dr. D. Chen','Dr. P. Dlamini','Dr. M. van Wyk'
    ];
    v_type_idx        INTEGER;
BEGIN
    v_date_range := v_end_date - v_start_date;

    WHILE v_generated < v_target_rows LOOP

        v_date := v_start_date + (RANDOM() * v_date_range)::INTEGER;
        SELECT date_key INTO v_date_key
        FROM   dwh.dim_date WHERE full_date = v_date;
        IF v_date_key IS NULL THEN CONTINUE; END IF;

        SELECT medication_key, unit_cost_price
        INTO   v_med_key, v_cost_price
        FROM   dwh.dim_medication
        WHERE  is_active = TRUE AND is_current = TRUE ORDER BY RANDOM() LIMIT 1;
        IF v_med_key IS NULL THEN CONTINUE; END IF;

        SELECT pharmacy_key INTO v_pharm_key
        FROM   dwh.dim_pharmacy WHERE is_active = TRUE ORDER BY RANDOM() LIMIT 1;

        -- Weighted adjustment type: expiry & count corrections most common
        v_type_idx := CASE
            WHEN RANDOM() < 0.35 THEN 1  -- Expired_Disposal (most common)
            WHEN RANDOM() < 0.55 THEN 2  -- Damaged
            WHEN RANDOM() < 0.60 THEN 3  -- Theft
            WHEN RANDOM() < 0.75 THEN 4  -- Count_Correction
            WHEN RANDOM() < 0.82 THEN 5  -- Return_to_Supplier
            WHEN RANDOM() < 0.91 THEN 6  -- Transfer_In
            ELSE 7                        -- Transfer_Out
        END;
        v_adj_type := v_adj_types[v_type_idx];

        -- Quantity: negative for removals, positive for transfers in / corrections
        v_qty := CASE
            WHEN v_adj_type IN ('Transfer_In','Count_Correction') AND RANDOM() > 0.5
                THEN (RANDOM() * 20 + 1)::INTEGER
            ELSE -1 * (RANDOM() * 30 + 1)::INTEGER
        END;

        v_cost_impact := ROUND(ABS(v_qty) * v_cost_price, 2);
        IF v_qty > 0 THEN v_cost_impact := -v_cost_impact; END IF;  -- negative impact = gain

        v_batch   := 'BATCH-' || UPPER(SUBSTRING(MD5(v_seq::TEXT), 1, 8));
        v_ref_num := 'ADJ-' || TO_CHAR(v_date,'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 4, '0');
        v_seq     := v_seq + 1;

        BEGIN
            INSERT INTO dwh.fact_stock_adjustments (
                adjustment_reference_number,
                adjustment_date_key, medication_key, pharmacy_key,
                adjustment_type, adjustment_reason, performed_by,
                quantity_adjusted, cost_impact, batch_number_affected,
                adjustment_timestamp, approval_timestamp, approved_by
            ) VALUES (
                v_ref_num,
                v_date_key, v_med_key, v_pharm_key,
                v_adj_type, v_reasons[v_type_idx],
                v_staff[CEIL(RANDOM() * ARRAY_LENGTH(v_staff, 1))::INTEGER],
                v_qty, v_cost_impact, v_batch,
                v_date::TIMESTAMP + INTERVAL '8 hours' + (RANDOM() * INTERVAL '9 hours'),
                v_date::TIMESTAMP + INTERVAL '17 hours' + (RANDOM() * INTERVAL '2 hours'),
                v_approvers[CEIL(RANDOM() * ARRAY_LENGTH(v_approvers, 1))::INTEGER]
            );
            v_generated := v_generated + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;

    END LOOP;
    RAISE NOTICE 'Generated % stock adjustment records.', v_generated;
END $$;

-- Verification — deliveries
SELECT
    delivery_status,
    COUNT(*)                    AS count,
    ROUND(AVG(total_cost), 2)   AS avg_cost,
    SUM(quantity_damaged)       AS total_damaged
FROM dwh.fact_supplier_deliveries
GROUP BY delivery_status ORDER BY count DESC;

-- Verification — adjustments
SELECT
    adjustment_type,
    COUNT(*)                        AS count,
    SUM(ABS(quantity_adjusted))     AS total_units,
    ROUND(SUM(ABS(cost_impact)), 2) AS total_cost_impact
FROM dwh.fact_stock_adjustments
GROUP BY adjustment_type ORDER BY count DESC;
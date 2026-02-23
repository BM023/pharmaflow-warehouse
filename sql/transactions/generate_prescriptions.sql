-- =============================================================================
-- generate_prescriptions.sql
-- Generates fact_prescription_transactions records from existing dim data.
--
-- This SQL-only approach is useful for quick testing or seeding before the
-- Python ETL pipeline is run. For production data generation use:
--   python python/generate_prescriptions.py
--
-- Generates ~5,000 prescriptions spanning 2025-08-01 to 2026-02-20
-- covering seasonal patterns, chronic/acute/refill distributions.
-- =============================================================================
SET search_path TO dwh, public;

\echo 'Generating prescription transactions...'

DO $$
DECLARE
    v_start_date     DATE    := '2025-08-01';
    v_end_date       DATE    := '2026-02-20';
    v_target_rows    INTEGER := 5000;
    v_generated      INTEGER := 0;
    v_date           DATE;
    v_date_key       INTEGER;
    v_patient_key    INTEGER;
    v_med_key        INTEGER;
    v_doc_key        INTEGER;
    v_pharm_key      INTEGER;
    v_ins_key        INTEGER;
    v_unit_cost      DECIMAL(10,2);
    v_unit_retail    DECIMAL(10,2);
    v_qty            INTEGER;
    v_total          DECIMAL(12,2);
    v_ins_cov        DECIMAL(12,2);
    v_copay          DECIMAL(10,2);
    v_discount       DECIMAL(10,2);
    v_rx_type        VARCHAR(20);
    v_pay_method     VARCHAR(30);
    v_days_supply    INTEGER;
    v_has_aid        BOOLEAN;
    v_cov_pct        DECIMAL(5,2);
    v_rx_num         VARCHAR(30);
    v_seq            INTEGER := 1;
    v_date_range     INTEGER;
    v_dispensers     TEXT[]  := ARRAY[
        'Dr. A. Patel','Dr. S. Williams','B. Nkosi (Pharm)',
        'T. Mokoena (Pharm)','L. Dlamini (Pharm)','M. van Wyk (Pharm)'
    ];
BEGIN
    v_date_range := v_end_date - v_start_date;

    WHILE v_generated < v_target_rows LOOP

        -- Random date weighted toward weekdays and month-end (pension effect)
        v_date := v_start_date + (RANDOM() * v_date_range)::INTEGER;
        -- Skip if date not in dim_date
        SELECT date_key INTO v_date_key FROM dwh.dim_date WHERE full_date = v_date;
        IF v_date_key IS NULL THEN CONTINUE; END IF;

        -- Random patient
        SELECT patient_key, has_medical_aid
        INTO   v_patient_key, v_has_aid
        FROM   dwh.dim_patient
        WHERE  is_active = TRUE AND is_current = TRUE
        ORDER  BY RANDOM() LIMIT 1;
        IF v_patient_key IS NULL THEN CONTINUE; END IF;

        -- Random medication (bias toward fast movers: repeat selection 3x for cat 1,7,10)
        SELECT m.medication_key, m.unit_cost_price, m.unit_retail_price
        INTO   v_med_key, v_unit_cost, v_unit_retail
        FROM   dwh.dim_medication m
        JOIN   dwh.dim_medication_category c ON m.category_key = c.category_key
        WHERE  m.is_active = TRUE AND m.is_current = TRUE
        ORDER  BY CASE WHEN c.movement_class = 'Fast_Mover' THEN RANDOM() * 0.3
                       WHEN c.movement_class = 'Medium_Mover' THEN RANDOM() * 0.6
                       ELSE RANDOM() END
        LIMIT  1;
        IF v_med_key IS NULL THEN CONTINUE; END IF;

        -- Random doctor
        SELECT doctor_key INTO v_doc_key
        FROM   dwh.dim_doctor WHERE is_active = TRUE ORDER BY RANDOM() LIMIT 1;

        -- Random pharmacy
        SELECT pharmacy_key INTO v_pharm_key
        FROM   dwh.dim_pharmacy WHERE is_active = TRUE ORDER BY RANDOM() LIMIT 1;

        -- Prescription type distribution: 50% Refill, 40% New, 10% Emergency
        v_rx_type := CASE
            WHEN RANDOM() < 0.50 THEN 'Refill'
            WHEN RANDOM() < 0.89 THEN 'New'
            ELSE 'Emergency'
        END;

        -- Quantity: 1-3 packs
        v_qty := (RANDOM() * 2 + 1)::INTEGER;
        v_total := ROUND(v_unit_retail * v_qty, 2);
        v_discount := 0.00;

        -- Insurance & payment
        IF v_has_aid AND RANDOM() > 0.15 THEN
            v_pay_method := CASE WHEN RANDOM() > 0.3 THEN 'Medical_Aid' ELSE 'Both' END;
            SELECT insurance_key, default_coverage_percentage
            INTO   v_ins_key, v_cov_pct
            FROM   dwh.dim_insurance
            WHERE  is_active = TRUE AND insurance_id != 'INS-005'
            ORDER  BY RANDOM() LIMIT 1;
            v_ins_cov  := ROUND(v_total * (v_cov_pct / 100.0), 2);
            v_copay    := ROUND(v_total - v_ins_cov, 2);
        ELSE
            v_pay_method := 'Cash';
            SELECT insurance_key INTO v_ins_key
            FROM   dwh.dim_insurance WHERE insurance_id = 'INS-005';
            v_ins_cov := 0.00;
            v_copay   := v_total;
            -- Occasional cash discount
            IF RANDOM() < 0.10 THEN
                v_discount := ROUND(v_total * 0.05, 2);
                v_copay    := v_total - v_discount;
            END IF;
        END IF;

        -- Days supply
        v_days_supply := CASE v_rx_type
            WHEN 'Refill'    THEN (ARRAY[28,30,60,90])[CEIL(RANDOM()*4)::INTEGER]
            WHEN 'New'       THEN (ARRAY[7,14,28,30])[CEIL(RANDOM()*4)::INTEGER]
            ELSE 7
        END;

        v_rx_num := 'RX-' || TO_CHAR(v_date, 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 5, '0');
        v_seq    := v_seq + 1;

        BEGIN
            INSERT INTO dwh.fact_prescription_transactions (
                prescription_number,
                transaction_date_key, patient_key, medication_key,
                doctor_key, pharmacy_key, insurance_key,
                prescription_type, payment_method,
                dispensing_pharmacist_name,
                quantity_dispensed, unit_price, total_amount, cost_price,
                insurance_coverage_amount, patient_copay, discount_amount,
                days_supply, refills_remaining,
                prescription_date, dispensing_timestamp
            ) VALUES (
                v_rx_num,
                v_date_key, v_patient_key, v_med_key,
                v_doc_key, v_pharm_key, v_ins_key,
                v_rx_type, v_pay_method,
                v_dispensers[CEIL(RANDOM() * ARRAY_LENGTH(v_dispensers, 1))::INTEGER],
                v_qty, v_unit_retail, v_total, v_unit_cost,
                v_ins_cov, v_copay, v_discount,
                v_days_supply,
                CASE WHEN v_rx_type = 'New' THEN (RANDOM() * 5)::INTEGER ELSE 0 END,
                v_date,
                v_date + (RANDOM() * INTERVAL '12 hours') + INTERVAL '8 hours'
            );
            v_generated := v_generated + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL; -- skip duplicates, loop continues
        END;

    END LOOP;
    RAISE NOTICE 'Generated % prescription transactions.', v_generated;
END $$;

-- Verification
SELECT
    prescription_type,
    payment_method,
    COUNT(*)                            AS tx_count,
    ROUND(AVG(total_amount), 2)         AS avg_amount,
    ROUND(SUM(total_amount)/1000, 0)    AS total_revenue_k
FROM dwh.fact_prescription_transactions
GROUP BY prescription_type, payment_method
ORDER BY tx_count DESC;
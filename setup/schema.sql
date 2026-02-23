-- =============================================================================
-- PharmaFlow Analytics - Master Warehouse Schema
-- Run this ONCE to build the complete warehouse from scratch.
--
-- Usage:
--   docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse \
--     < setup/schema.sql
--
-- Execution order (respects all FK dependencies):
--   0. Schema
--   1. dim_date (no deps)
--   2. dim_medication_category (no deps — must precede dim_medication)
--   3. dim_pharmacy (no deps — must precede dim_patient)
--   4. dim_doctor, dim_insurance, dim_supplier (no deps)
--   5. dim_medication (FK → dim_medication_category)
--   6. dim_patient (FK → dim_pharmacy)
--   7. Functions & Triggers
--   8. Fact tables (FK → all dims)
--   9. Sample data (\i files)
-- =============================================================================

\echo ''
\echo '================================================='
\echo ' PharmaFlow Analytics - Warehouse Setup'
\echo '================================================='

-- ---------------------------------------------------------------------------
-- STEP 0: Schema
-- ---------------------------------------------------------------------------
\echo '[0] Creating schema...'
CREATE SCHEMA IF NOT EXISTS dwh;
SET search_path TO dwh, public;

-- ---------------------------------------------------------------------------
-- STEP 1: dim_date
-- ---------------------------------------------------------------------------
\echo '[1] dim_date...'

CREATE TABLE IF NOT EXISTS dwh.dim_date (
    date_key              INTEGER      PRIMARY KEY,
    full_date             DATE         NOT NULL UNIQUE,
    day_of_month          SMALLINT     NOT NULL,
    day_of_week           SMALLINT     NOT NULL,
    day_name              VARCHAR(10)  NOT NULL,
    day_name_short        VARCHAR(3)   NOT NULL,
    week_of_month         SMALLINT     NOT NULL,
    week_of_year          SMALLINT     NOT NULL,
    month                 SMALLINT     NOT NULL,
    month_name            VARCHAR(10)  NOT NULL,
    month_name_short      VARCHAR(3)   NOT NULL,
    quarter               SMALLINT     NOT NULL,
    quarter_name          VARCHAR(2)   NOT NULL,
    year                  SMALLINT     NOT NULL,
    year_month            INTEGER      NOT NULL,
    year_quarter          VARCHAR(10)  NOT NULL,
    is_weekend            BOOLEAN      NOT NULL DEFAULT FALSE,
    is_public_holiday     BOOLEAN      NOT NULL DEFAULT FALSE,
    holiday_name          VARCHAR(50),
    is_month_start        BOOLEAN      NOT NULL DEFAULT FALSE,
    is_month_end          BOOLEAN      NOT NULL DEFAULT FALSE,
    is_quarter_start      BOOLEAN      NOT NULL DEFAULT FALSE,
    is_quarter_end        BOOLEAN      NOT NULL DEFAULT FALSE,
    is_year_start         BOOLEAN      NOT NULL DEFAULT FALSE,
    is_year_end           BOOLEAN      NOT NULL DEFAULT FALSE,
    season                VARCHAR(10)  NOT NULL,
    is_flu_season         BOOLEAN      NOT NULL DEFAULT FALSE,
    is_allergy_season     BOOLEAN      NOT NULL DEFAULT FALSE,
    is_school_holiday     BOOLEAN      NOT NULL DEFAULT FALSE,
    fiscal_year           SMALLINT     NOT NULL,
    fiscal_quarter        VARCHAR(10)  NOT NULL,
    created_at            TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_date_full_date  ON dwh.dim_date(full_date);
CREATE INDEX IF NOT EXISTS idx_date_year_month ON dwh.dim_date(year_month);
CREATE INDEX IF NOT EXISTS idx_date_year       ON dwh.dim_date(year);
CREATE INDEX IF NOT EXISTS idx_date_season     ON dwh.dim_date(season);

DO $$
DECLARE
    d     DATE    := '2020-01-01';
    end_d DATE    := '2030-12-31';
    dk    INTEGER;
    dow   INTEGER;
    m     INTEGER;
    y     INTEGER;
    sv    VARCHAR(10);
    fy    SMALLINT;
BEGIN
    WHILE d <= end_d LOOP
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_date WHERE full_date = d) THEN
            dk  := EXTRACT(YEAR FROM d)::INTEGER * 10000
                 + EXTRACT(MONTH FROM d)::INTEGER * 100
                 + EXTRACT(DAY FROM d)::INTEGER;
            dow := EXTRACT(DOW FROM d)::INTEGER;
            m   := EXTRACT(MONTH FROM d)::INTEGER;
            y   := EXTRACT(YEAR FROM d)::INTEGER;
            sv  := CASE WHEN m IN (12,1,2) THEN 'Summer'
                        WHEN m IN (3,4,5)  THEN 'Autumn'
                        WHEN m IN (6,7,8)  THEN 'Winter'
                        ELSE 'Spring' END;
            fy  := CASE WHEN m >= 4 THEN y ELSE y - 1 END;

            INSERT INTO dwh.dim_date VALUES (
                dk, d,
                EXTRACT(DAY FROM d)::SMALLINT,
                CASE dow WHEN 0 THEN 7 ELSE dow END::SMALLINT,
                TRIM(TO_CHAR(d,'Day')), TRIM(TO_CHAR(d,'Dy')),
                CEIL(EXTRACT(DAY FROM d)/7.0)::SMALLINT,
                EXTRACT(WEEK FROM d)::SMALLINT,
                m::SMALLINT,
                TRIM(TO_CHAR(d,'Month')), TRIM(TO_CHAR(d,'Mon')),
                EXTRACT(QUARTER FROM d)::SMALLINT,
                'Q'||EXTRACT(QUARTER FROM d)::TEXT,
                y::SMALLINT,
                (y*100+m)::INTEGER,
                y::TEXT||'Q'||EXTRACT(QUARTER FROM d)::TEXT,
                dow IN (0,6),
                FALSE, -- is_public_holiday (update via load_sa_holidays.sql)
                NULL,
                EXTRACT(DAY FROM d) = 1,
                d = (DATE_TRUNC('MONTH',d) + INTERVAL '1 MONTH - 1 day')::DATE,
                (m IN (1,4,7,10) AND EXTRACT(DAY FROM d) = 1),
                (m IN (3,6,9,12) AND d = (DATE_TRUNC('MONTH',d)+INTERVAL '1 MONTH - 1 day')::DATE),
                (m=1  AND EXTRACT(DAY FROM d) = 1),
                (m=12 AND EXTRACT(DAY FROM d) = 31),
                sv,
                m BETWEEN 5 AND 9,
                m BETWEEN 8 AND 11,
                FALSE,
                fy,
                'FY'||fy::TEXT||'Q'||CASE WHEN m IN(4,5,6) THEN '1'
                                           WHEN m IN(7,8,9) THEN '2'
                                           WHEN m IN(10,11,12) THEN '3'
                                           ELSE '4' END,
                CURRENT_TIMESTAMP
            );
        END IF;
        d := d + INTERVAL '1 day';
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- STEP 2: dim_medication_category  (no deps — must precede dim_medication)
-- ---------------------------------------------------------------------------
\echo '[2] dim_medication_category...'

CREATE TABLE IF NOT EXISTS dwh.dim_medication_category (
    category_key                        SERIAL       PRIMARY KEY,
    clinical_category                   VARCHAR(30)  NOT NULL,
    clinical_category_description       TEXT,
    movement_class                      VARCHAR(20)  NOT NULL,
    movement_threshold_units_per_month  INTEGER,
    turnover_rate_category              VARCHAR(20),
    value_class                         CHAR(1)      NOT NULL CHECK (value_class IN ('A','B','C')),
    value_class_description             TEXT,
    is_critical_stock                   BOOLEAN      DEFAULT FALSE,
    criticality_reason                  VARCHAR(100),
    requires_cold_chain                 BOOLEAN      DEFAULT FALSE,
    requires_special_handling           BOOLEAN      DEFAULT FALSE,
    security_level                      VARCHAR(30)  DEFAULT 'Standard',
    default_reorder_point_formula       VARCHAR(200),
    default_safety_stock_days           INTEGER,
    review_frequency                    VARCHAR(20),
    created_at                          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at                          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_category_combination UNIQUE (clinical_category, movement_class, value_class)
);

CREATE INDEX IF NOT EXISTS idx_category_clinical ON dwh.dim_medication_category(clinical_category);
CREATE INDEX IF NOT EXISTS idx_category_movement ON dwh.dim_medication_category(movement_class);
CREATE INDEX IF NOT EXISTS idx_category_value    ON dwh.dim_medication_category(value_class);

-- ---------------------------------------------------------------------------
-- STEP 3: dim_pharmacy  (no deps — must precede dim_patient)
-- ---------------------------------------------------------------------------
\echo '[3] dim_pharmacy...'

CREATE TABLE IF NOT EXISTS dwh.dim_pharmacy (
    pharmacy_key                  SERIAL         PRIMARY KEY,
    pharmacy_id                   VARCHAR(20)    NOT NULL UNIQUE,
    license_number                VARCHAR(30)    NOT NULL UNIQUE,
    location_name                 VARCHAR(100)   NOT NULL,
    store_code                    VARCHAR(10)    NOT NULL UNIQUE,
    address_line1                 VARCHAR(200),
    address_line2                 VARCHAR(200),
    suburb                        VARCHAR(100),
    city                          VARCHAR(100)   NOT NULL,
    province                      VARCHAR(50)    NOT NULL,
    postal_code                   VARCHAR(10),
    gps_latitude                  DECIMAL(10,8),
    gps_longitude                 DECIMAL(11,8),
    demographic_profile           VARCHAR(30),
    catchment_area_population     INTEGER,
    competition_level             VARCHAR(20),
    foot_traffic_level            VARCHAR(20),
    parking_availability          VARCHAR(30),
    square_meters                 DECIMAL(8,2),
    number_of_dispensing_stations SMALLINT,
    has_drive_through             BOOLEAN        DEFAULT FALSE,
    has_clinic_on_site            BOOLEAN        DEFAULT FALSE,
    has_cold_storage              BOOLEAN        DEFAULT TRUE,
    manager_name                  VARCHAR(100),
    pharmacist_in_charge          VARCHAR(100),
    phone_number                  VARCHAR(20),
    email                         VARCHAR(100),
    operating_hours               VARCHAR(200),
    is_24_hours                   BOOLEAN        DEFAULT FALSE,
    monthly_average_revenue       DECIMAL(12,2),
    monthly_average_transactions  INTEGER,
    customer_satisfaction_rating  DECIMAL(2,1),
    inventory_turnover_rate       DECIMAL(5,2),
    opening_date                  DATE           NOT NULL,
    last_audit_date               DATE,
    license_expiry_date           DATE,
    is_active                     BOOLEAN        DEFAULT TRUE,
    status                        VARCHAR(30)    DEFAULT 'Open',
    created_at                    TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP      DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_pharmacy_city        ON dwh.dim_pharmacy(city);
CREATE INDEX IF NOT EXISTS idx_pharmacy_demographic ON dwh.dim_pharmacy(demographic_profile);
CREATE INDEX IF NOT EXISTS idx_pharmacy_active      ON dwh.dim_pharmacy(is_active);
CREATE INDEX IF NOT EXISTS idx_pharmacy_code        ON dwh.dim_pharmacy(store_code);

-- ---------------------------------------------------------------------------
-- STEP 4: dim_doctor, dim_insurance, dim_supplier  (no deps)
-- ---------------------------------------------------------------------------
\echo '[4] dim_doctor, dim_insurance, dim_supplier...'

CREATE TABLE IF NOT EXISTS dwh.dim_doctor (
    doctor_key                        SERIAL       PRIMARY KEY,
    doctor_id                         VARCHAR(20)  NOT NULL UNIQUE,
    hpcsa_registration_number         VARCHAR(30)  UNIQUE,
    title                             VARCHAR(10)  DEFAULT 'Dr',
    first_name                        VARCHAR(100) NOT NULL,
    last_name                         VARCHAR(100) NOT NULL,
    specialty                         VARCHAR(100),
    sub_specialty                     VARCHAR(100),
    practice_name                     VARCHAR(200),
    practice_type                     VARCHAR(50),
    years_in_practice                 INTEGER,
    phone_number                      VARCHAR(20),
    email                             VARCHAR(100),
    practice_address                  VARCHAR(300),
    city                              VARCHAR(100),
    province                          VARCHAR(50),
    average_prescriptions_per_month   INTEGER,
    most_prescribed_category          VARCHAR(100),
    prescribing_style                 VARCHAR(30),
    prefers_generic_percentage        DECIMAL(5,2),
    hospital_affiliations             TEXT,
    is_referring_doctor               BOOLEAN      DEFAULT FALSE,
    is_active                         BOOLEAN      DEFAULT TRUE,
    registration_date                 DATE,
    last_prescription_date            DATE,
    created_at                        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at                        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_doctor_specialty ON dwh.dim_doctor(specialty);
CREATE INDEX IF NOT EXISTS idx_doctor_active    ON dwh.dim_doctor(is_active);
CREATE INDEX IF NOT EXISTS idx_doctor_city      ON dwh.dim_doctor(city);

CREATE TABLE IF NOT EXISTS dwh.dim_insurance (
    insurance_key                   SERIAL        PRIMARY KEY,
    insurance_id                    VARCHAR(20)   NOT NULL UNIQUE,
    scheme_code                     VARCHAR(30)   UNIQUE,
    provider_name                   VARCHAR(100)  NOT NULL,
    scheme_name                     VARCHAR(200),
    plan_type                       VARCHAR(50),
    network_type                    VARCHAR(30),
    default_coverage_percentage     DECIMAL(5,2)  DEFAULT 80.00,
    annual_limit                    DECIMAL(12,2),
    chronic_benefit_available       BOOLEAN       DEFAULT TRUE,
    chronic_coverage_percentage     DECIMAL(5,2)  DEFAULT 100.00,
    default_copay_amount            DECIMAL(8,2),
    dispensing_fee_covered          BOOLEAN       DEFAULT TRUE,
    has_formulary_restrictions      BOOLEAN       DEFAULT FALSE,
    requires_generic_substitution   BOOLEAN       DEFAULT FALSE,
    requires_pre_authorization      BOOLEAN       DEFAULT FALSE,
    average_reimbursement_time_days INTEGER,
    payment_reliability_rating      VARCHAR(20),
    invoice_submission_method       VARCHAR(30),
    claims_contact_number           VARCHAR(20),
    authorization_contact_number    VARCHAR(20),
    claims_email                    VARCHAR(100),
    portal_url                      VARCHAR(200),
    is_active                       BOOLEAN       DEFAULT TRUE,
    contract_start_date             DATE,
    contract_end_date               DATE,
    created_at                      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_insurance_provider ON dwh.dim_insurance(provider_name);
CREATE INDEX IF NOT EXISTS idx_insurance_active   ON dwh.dim_insurance(is_active);

CREATE TABLE IF NOT EXISTS dwh.dim_supplier (
    supplier_key                      SERIAL        PRIMARY KEY,
    supplier_id                       VARCHAR(20)   NOT NULL UNIQUE,
    supplier_code                     VARCHAR(10)   UNIQUE,
    supplier_name                     VARCHAR(200)  NOT NULL,
    trading_name                      VARCHAR(200),
    company_registration_number       VARCHAR(30),
    vat_number                        VARCHAR(30),
    supplier_type                     VARCHAR(50),
    primary_contact_name              VARCHAR(100),
    phone_number                      VARCHAR(20),
    mobile_number                     VARCHAR(20),
    email                             VARCHAR(100),
    website                           VARCHAR(200),
    address_line1                     VARCHAR(200),
    address_line2                     VARCHAR(200),
    city                              VARCHAR(100),
    province                          VARCHAR(50),
    postal_code                       VARCHAR(10),
    payment_terms                     VARCHAR(30)   DEFAULT '30_Days',
    credit_limit                      DECIMAL(12,2),
    discount_percentage               DECIMAL(5,2)  DEFAULT 0.00,
    minimum_order_value               DECIMAL(10,2),
    delivery_fee                      DECIMAL(8,2),
    free_delivery_threshold           DECIMAL(10,2),
    average_delivery_lead_time_days   INTEGER,
    on_time_delivery_rate             DECIMAL(5,2),
    order_accuracy_rate               DECIMAL(5,2),
    quality_issue_rate                DECIMAL(5,2),
    reliability_rating                VARCHAR(20),
    total_annual_spend                DECIMAL(14,2),
    delivery_days                     VARCHAR(50),
    delivery_cutoff_time              TIME,
    delivery_area_coverage            VARCHAR(100),
    cold_chain_capable                BOOLEAN       DEFAULT FALSE,
    emergency_delivery_available      BOOLEAN       DEFAULT FALSE,
    is_active                         BOOLEAN       DEFAULT TRUE,
    is_preferred_supplier             BOOLEAN       DEFAULT FALSE,
    contract_start_date               DATE,
    contract_end_date                 DATE,
    last_order_date                   DATE,
    created_at                        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_supplier_name      ON dwh.dim_supplier(supplier_name);
CREATE INDEX IF NOT EXISTS idx_supplier_active    ON dwh.dim_supplier(is_active);
CREATE INDEX IF NOT EXISTS idx_supplier_preferred ON dwh.dim_supplier(is_preferred_supplier);

-- ---------------------------------------------------------------------------
-- STEP 5: dim_medication  (FK → dim_medication_category)
-- ---------------------------------------------------------------------------
\echo '[5] dim_medication...'

CREATE TABLE IF NOT EXISTS dwh.dim_medication (
    medication_key                SERIAL        PRIMARY KEY,
    medication_id                 VARCHAR(30)   NOT NULL,
    barcode                       VARCHAR(50),
    medication_name               VARCHAR(200)  NOT NULL,
    generic_name                  VARCHAR(200),
    scientific_name               VARCHAR(200),
    manufacturer                  VARCHAR(100),
    distributor                   VARCHAR(100),
    dosage_form                   VARCHAR(30)   NOT NULL,
    strength                      VARCHAR(50),
    pack_size                     INTEGER,
    unit_of_measure               VARCHAR(20),
    category_key                  INTEGER       REFERENCES dwh.dim_medication_category(category_key),
    therapeutic_class             VARCHAR(100),
    schedule_classification       VARCHAR(10),
    requires_prescription         BOOLEAN       DEFAULT TRUE,
    is_controlled_substance       BOOLEAN       DEFAULT FALSE,
    is_generic                    BOOLEAN       DEFAULT FALSE,
    unit_cost_price               DECIMAL(10,2) NOT NULL,
    unit_retail_price             DECIMAL(10,2) NOT NULL,
    markup_percentage             DECIMAL(5,2)  GENERATED ALWAYS AS (
                                      ROUND(((unit_retail_price - unit_cost_price)
                                             / NULLIF(unit_cost_price,0)) * 100, 2)
                                  ) STORED,
    typical_shelf_life_days       INTEGER,
    minimum_order_quantity        INTEGER       DEFAULT 1,
    reorder_lead_time_days        INTEGER       DEFAULT 3,
    storage_requirements          VARCHAR(50)   DEFAULT 'Room Temperature',
    is_fragile                    BOOLEAN       DEFAULT FALSE,
    is_high_value                 BOOLEAN       DEFAULT FALSE,
    common_side_effects           TEXT,
    contraindications             TEXT,
    drug_interactions_warning     BOOLEAN       DEFAULT FALSE,
    is_seasonal                   BOOLEAN       DEFAULT FALSE,
    seasonal_peak_months          VARCHAR(50),
    average_monthly_demand        INTEGER,
    effective_date                DATE          DEFAULT CURRENT_DATE,
    end_date                      DATE,
    is_current                    BOOLEAN       DEFAULT TRUE,
    version_number                INTEGER       DEFAULT 1,
    change_reason                 VARCHAR(100),
    is_active                     BOOLEAN       DEFAULT TRUE,
    discontinuation_date          DATE,
    replacement_medication_key    INTEGER       REFERENCES dwh.dim_medication(medication_key),
    created_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_scd_dates CHECK (end_date IS NULL OR end_date >= effective_date)
);

CREATE INDEX IF NOT EXISTS idx_medication_id          ON dwh.dim_medication(medication_id);
CREATE INDEX IF NOT EXISTS idx_medication_name        ON dwh.dim_medication(medication_name);
CREATE INDEX IF NOT EXISTS idx_medication_category    ON dwh.dim_medication(category_key);
CREATE INDEX IF NOT EXISTS idx_medication_current     ON dwh.dim_medication(is_current);
CREATE INDEX IF NOT EXISTS idx_medication_active      ON dwh.dim_medication(is_active);
CREATE INDEX IF NOT EXISTS idx_medication_seasonal    ON dwh.dim_medication(is_seasonal);
CREATE INDEX IF NOT EXISTS idx_medication_therapeutic ON dwh.dim_medication(therapeutic_class);

-- ---------------------------------------------------------------------------
-- STEP 6: dim_patient  (FK → dim_pharmacy)
-- ---------------------------------------------------------------------------
\echo '[6] dim_patient...'

CREATE TABLE IF NOT EXISTS dwh.dim_patient (
    patient_key               SERIAL        PRIMARY KEY,
    patient_id                VARCHAR(20)   NOT NULL UNIQUE,
    title                     VARCHAR(10),
    first_name                VARCHAR(100)  NOT NULL,
    last_name                 VARCHAR(100)  NOT NULL,
    date_of_birth             DATE          NOT NULL,
    age_group                 VARCHAR(20),
    gender                    VARCHAR(30),
    phone_number              VARCHAR(20),
    email                     VARCHAR(100),
    address_line1             VARCHAR(200),
    address_line2             VARCHAR(200),
    suburb                    VARCHAR(100),
    city                      VARCHAR(100),
    province                  VARCHAR(50),
    postal_code               VARCHAR(10),
    primary_pharmacy_key      INTEGER       REFERENCES dwh.dim_pharmacy(pharmacy_key),
    patient_type              VARCHAR(30)   DEFAULT 'New',
    registration_date         DATE          NOT NULL,
    is_chronic_patient        BOOLEAN       DEFAULT FALSE,
    has_medical_aid           BOOLEAN       DEFAULT FALSE,
    preferred_contact_method  VARCHAR(20),
    effective_date            DATE          DEFAULT CURRENT_DATE,
    end_date                  DATE,
    is_current                BOOLEAN       DEFAULT TRUE,
    is_active                 BOOLEAN       DEFAULT TRUE,
    created_at                TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_patient_age_group ON dwh.dim_patient(age_group);
CREATE INDEX IF NOT EXISTS idx_patient_chronic   ON dwh.dim_patient(is_chronic_patient);
CREATE INDEX IF NOT EXISTS idx_patient_active    ON dwh.dim_patient(is_active);
CREATE INDEX IF NOT EXISTS idx_patient_current   ON dwh.dim_patient(is_current);
CREATE INDEX IF NOT EXISTS idx_patient_pharmacy  ON dwh.dim_patient(primary_pharmacy_key);

-- ---------------------------------------------------------------------------
-- STEP 7: Functions & Triggers
-- ---------------------------------------------------------------------------
\echo '[7] Functions and triggers...'

CREATE OR REPLACE FUNCTION dwh.calculate_age_group(dob DATE)
RETURNS VARCHAR(20) AS $$
BEGIN
    RETURN CASE
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 0  AND 12 THEN '0-12'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 13 AND 18 THEN '13-18'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 19 AND 35 THEN '19-35'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 36 AND 50 THEN '36-50'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob)) BETWEEN 51 AND 65 THEN '51-65'
        ELSE '65+'
    END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dwh.update_patient_age_group()
RETURNS TRIGGER AS $$
BEGIN
    NEW.age_group := dwh.calculate_age_group(NEW.date_of_birth);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_patient_age_group ON dwh.dim_patient;
CREATE TRIGGER trg_patient_age_group
    BEFORE INSERT OR UPDATE ON dwh.dim_patient
    FOR EACH ROW EXECUTE FUNCTION dwh.update_patient_age_group();

-- SCD Type 2: process a medication price change
CREATE OR REPLACE FUNCTION dwh.process_medication_price_change(
    p_medication_id    VARCHAR,
    p_new_cost_price   DECIMAL,
    p_new_retail_price DECIMAL,
    p_change_reason    VARCHAR DEFAULT 'Price Change'
)
RETURNS INTEGER AS $$
DECLARE v_new_key INTEGER;
BEGIN
    UPDATE dwh.dim_medication
    SET    is_current = FALSE,
           end_date   = CURRENT_DATE - INTERVAL '1 day',
           updated_at = CURRENT_TIMESTAMP
    WHERE  medication_id = p_medication_id AND is_current = TRUE;

    INSERT INTO dwh.dim_medication (
        medication_id, barcode, medication_name, generic_name, scientific_name,
        manufacturer, distributor, dosage_form, strength, pack_size, unit_of_measure,
        category_key, therapeutic_class, schedule_classification,
        requires_prescription, is_controlled_substance, is_generic,
        unit_cost_price, unit_retail_price,
        typical_shelf_life_days, minimum_order_quantity, reorder_lead_time_days,
        storage_requirements, is_fragile, is_high_value,
        is_seasonal, seasonal_peak_months,
        effective_date, end_date, is_current, version_number, change_reason, is_active
    )
    SELECT
        medication_id, barcode, medication_name, generic_name, scientific_name,
        manufacturer, distributor, dosage_form, strength, pack_size, unit_of_measure,
        category_key, therapeutic_class, schedule_classification,
        requires_prescription, is_controlled_substance, is_generic,
        p_new_cost_price, p_new_retail_price,
        typical_shelf_life_days, minimum_order_quantity, reorder_lead_time_days,
        storage_requirements, is_fragile, is_high_value,
        is_seasonal, seasonal_peak_months,
        CURRENT_DATE, NULL, TRUE, version_number + 1, p_change_reason, is_active
    FROM dwh.dim_medication
    WHERE medication_id = p_medication_id
    ORDER BY version_number DESC LIMIT 1
    RETURNING medication_key INTO v_new_key;

    RETURN v_new_key;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- STEP 8: Fact Tables
-- ---------------------------------------------------------------------------
\echo '[8] Fact tables...'

CREATE TABLE IF NOT EXISTS dwh.fact_prescription_transactions (
    prescription_transaction_key  BIGSERIAL     PRIMARY KEY,
    prescription_number           VARCHAR(30)   NOT NULL UNIQUE,
    transaction_date_key          INTEGER       NOT NULL REFERENCES dwh.dim_date(date_key),
    patient_key                   INTEGER       NOT NULL REFERENCES dwh.dim_patient(patient_key),
    medication_key                INTEGER       NOT NULL REFERENCES dwh.dim_medication(medication_key),
    doctor_key                    INTEGER       NOT NULL REFERENCES dwh.dim_doctor(doctor_key),
    pharmacy_key                  INTEGER       NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    insurance_key                 INTEGER       REFERENCES dwh.dim_insurance(insurance_key),
    prescription_type             VARCHAR(20)   NOT NULL,
    payment_method                VARCHAR(30)   NOT NULL,
    dispensing_pharmacist_name    VARCHAR(100),
    quantity_dispensed            INTEGER       NOT NULL CHECK (quantity_dispensed > 0),
    unit_price                    DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    total_amount                  DECIMAL(12,2) NOT NULL CHECK (total_amount >= 0),
    cost_price                    DECIMAL(10,2) NOT NULL CHECK (cost_price >= 0),
    insurance_coverage_amount     DECIMAL(12,2) DEFAULT 0.00,
    patient_copay                 DECIMAL(10,2) DEFAULT 0.00,
    discount_amount               DECIMAL(10,2) DEFAULT 0.00,
    profit_margin                 DECIMAL(12,2) GENERATED ALWAYS AS
                                      (total_amount - (cost_price * quantity_dispensed)) STORED,
    days_supply                   INTEGER       CHECK (days_supply > 0),
    refills_remaining             SMALLINT      DEFAULT 0,
    prescription_date             DATE          NOT NULL,
    dispensing_timestamp          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_prescription_type CHECK (prescription_type IN ('New','Refill','Emergency')),
    CONSTRAINT chk_payment_method    CHECK (payment_method    IN ('Cash','Medical_Aid','Both'))
);

CREATE INDEX IF NOT EXISTS idx_fact_rx_date       ON dwh.fact_prescription_transactions(transaction_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_rx_patient    ON dwh.fact_prescription_transactions(patient_key);
CREATE INDEX IF NOT EXISTS idx_fact_rx_medication ON dwh.fact_prescription_transactions(medication_key);
CREATE INDEX IF NOT EXISTS idx_fact_rx_doctor     ON dwh.fact_prescription_transactions(doctor_key);
CREATE INDEX IF NOT EXISTS idx_fact_rx_pharmacy   ON dwh.fact_prescription_transactions(pharmacy_key);
CREATE INDEX IF NOT EXISTS idx_fact_rx_insurance  ON dwh.fact_prescription_transactions(insurance_key);
CREATE INDEX IF NOT EXISTS idx_fact_rx_type       ON dwh.fact_prescription_transactions(prescription_type);
CREATE INDEX IF NOT EXISTS idx_fact_rx_timestamp  ON dwh.fact_prescription_transactions(dispensing_timestamp);

CREATE TABLE IF NOT EXISTS dwh.fact_inventory_snapshots (
    inventory_snapshot_key    BIGSERIAL     PRIMARY KEY,
    snapshot_date_key         INTEGER       NOT NULL REFERENCES dwh.dim_date(date_key),
    medication_key            INTEGER       NOT NULL REFERENCES dwh.dim_medication(medication_key),
    pharmacy_key              INTEGER       NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    quantity_on_hand          INTEGER       NOT NULL DEFAULT 0,
    quantity_allocated        INTEGER       DEFAULT 0,
    quantity_on_order         INTEGER       DEFAULT 0,
    reorder_point             INTEGER       NOT NULL,
    maximum_stock_level       INTEGER,
    quantity_expired_today    INTEGER       DEFAULT 0,
    quantity_near_expiry      INTEGER       DEFAULT 0,
    stock_value_at_cost       DECIMAL(12,2) NOT NULL,
    stock_value_at_retail     DECIMAL(12,2) NOT NULL,
    days_until_stockout       INTEGER,
    stock_turnover_rate       DECIMAL(8,2),
    quantity_available        INTEGER       GENERATED ALWAYS AS (quantity_on_hand - quantity_allocated) STORED,
    is_out_of_stock           BOOLEAN       GENERATED ALWAYS AS ((quantity_on_hand - quantity_allocated) <= 0) STORED,
    is_below_reorder_point    BOOLEAN       GENERATED ALWAYS AS ((quantity_on_hand - quantity_allocated) <= reorder_point) STORED,
    is_overstocked            BOOLEAN,
    stock_status_code         VARCHAR(20),
    min_days_until_expiry     INTEGER,
    batch_count               INTEGER       DEFAULT 0,
    snapshot_timestamp        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_stock_count_date     DATE,
    CONSTRAINT uq_snapshot_daily UNIQUE (snapshot_date_key, medication_key, pharmacy_key)
);

CREATE INDEX IF NOT EXISTS idx_fact_inv_date       ON dwh.fact_inventory_snapshots(snapshot_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_inv_medication ON dwh.fact_inventory_snapshots(medication_key);
CREATE INDEX IF NOT EXISTS idx_fact_inv_pharmacy   ON dwh.fact_inventory_snapshots(pharmacy_key);
CREATE INDEX IF NOT EXISTS idx_fact_inv_status     ON dwh.fact_inventory_snapshots(stock_status_code);
CREATE INDEX IF NOT EXISTS idx_fact_inv_low_stock  ON dwh.fact_inventory_snapshots(is_below_reorder_point)
    WHERE is_below_reorder_point = TRUE;

CREATE TABLE IF NOT EXISTS dwh.fact_supplier_deliveries (
    delivery_key                  BIGSERIAL     PRIMARY KEY,
    delivery_number               VARCHAR(30)   NOT NULL UNIQUE,
    purchase_order_number         VARCHAR(30),
    delivery_date_key             INTEGER       NOT NULL REFERENCES dwh.dim_date(date_key),
    ordered_date_key              INTEGER       NOT NULL REFERENCES dwh.dim_date(date_key),
    supplier_key                  INTEGER       NOT NULL REFERENCES dwh.dim_supplier(supplier_key),
    medication_key                INTEGER       NOT NULL REFERENCES dwh.dim_medication(medication_key),
    pharmacy_key                  INTEGER       NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    batch_number                  VARCHAR(50),
    delivery_status               VARCHAR(30),
    quantity_ordered              INTEGER       NOT NULL,
    quantity_delivered            INTEGER       NOT NULL,
    quantity_damaged              INTEGER       DEFAULT 0,
    quantity_rejected             INTEGER       DEFAULT 0,
    unit_cost                     DECIMAL(10,2) NOT NULL,
    total_cost                    DECIMAL(12,2) NOT NULL,
    expiry_date                   DATE          NOT NULL,
    delivery_lead_time_days       INTEGER,
    variance_cost                 DECIMAL(12,2),
    variance_quantity             INTEGER       GENERATED ALWAYS AS (quantity_delivered - quantity_ordered) STORED,
    shelf_life_days_at_delivery   INTEGER,   -- populated by ETL: expiry_date - actual_delivery_date
    is_complete                   BOOLEAN       GENERATED ALWAYS AS (quantity_delivered >= quantity_ordered) STORED,
    is_on_time                    BOOLEAN,
    quality_issue_flag            BOOLEAN       DEFAULT FALSE,
    ordered_timestamp             TIMESTAMP     NOT NULL,
    expected_delivery_date        DATE,
    actual_delivery_timestamp     TIMESTAMP     NOT NULL,
    received_by                   VARCHAR(100),
    created_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_fact_del_delivery_date ON dwh.fact_supplier_deliveries(delivery_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_del_ordered_date  ON dwh.fact_supplier_deliveries(ordered_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_del_supplier      ON dwh.fact_supplier_deliveries(supplier_key);
CREATE INDEX IF NOT EXISTS idx_fact_del_medication    ON dwh.fact_supplier_deliveries(medication_key);
CREATE INDEX IF NOT EXISTS idx_fact_del_pharmacy      ON dwh.fact_supplier_deliveries(pharmacy_key);
CREATE INDEX IF NOT EXISTS idx_fact_del_status        ON dwh.fact_supplier_deliveries(delivery_status);

CREATE TABLE IF NOT EXISTS dwh.fact_stock_adjustments (
    adjustment_key                BIGSERIAL     PRIMARY KEY,
    adjustment_reference_number   VARCHAR(30)   NOT NULL UNIQUE,
    adjustment_date_key           INTEGER       NOT NULL REFERENCES dwh.dim_date(date_key),
    medication_key                INTEGER       NOT NULL REFERENCES dwh.dim_medication(medication_key),
    pharmacy_key                  INTEGER       NOT NULL REFERENCES dwh.dim_pharmacy(pharmacy_key),
    adjustment_type               VARCHAR(50)   NOT NULL,
    adjustment_reason             TEXT,
    performed_by                  VARCHAR(100),
    quantity_adjusted             INTEGER       NOT NULL,
    cost_impact                   DECIMAL(12,2) NOT NULL,
    batch_number_affected         VARCHAR(50),
    adjustment_timestamp          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approval_timestamp            TIMESTAMP,
    approved_by                   VARCHAR(100),
    created_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_adjustment_type CHECK (
        adjustment_type IN (
            'Expired_Disposal','Damaged','Theft','Count_Correction',
            'Return_to_Supplier','Transfer_In','Transfer_Out'
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_fact_adj_date       ON dwh.fact_stock_adjustments(adjustment_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_adj_medication ON dwh.fact_stock_adjustments(medication_key);
CREATE INDEX IF NOT EXISTS idx_fact_adj_pharmacy   ON dwh.fact_stock_adjustments(pharmacy_key);
CREATE INDEX IF NOT EXISTS idx_fact_adj_type       ON dwh.fact_stock_adjustments(adjustment_type);

-- ---------------------------------------------------------------------------
-- STEP 9: Load static dimension data
-- ---------------------------------------------------------------------------
\echo '[9] Loading static dimension data...'

\i sql/sample_data/load_medication_categories.sql
\i sql/sample_data/load_pharmacy.sql
\i sql/sample_data/load_doctors.sql
\i sql/sample_data/load_insurance.sql
\i sql/sample_data/load_suppliers.sql
\i sql/sample_data/load_medications.sql

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
\echo ''
\echo 'Row counts:'
SELECT table_name, row_count FROM (
    SELECT 'dim_date'                AS table_name, COUNT(*) AS row_count FROM dwh.dim_date
    UNION ALL SELECT 'dim_medication_category',     COUNT(*) FROM dwh.dim_medication_category
    UNION ALL SELECT 'dim_pharmacy',                COUNT(*) FROM dwh.dim_pharmacy
    UNION ALL SELECT 'dim_doctor',                  COUNT(*) FROM dwh.dim_doctor
    UNION ALL SELECT 'dim_insurance',               COUNT(*) FROM dwh.dim_insurance
    UNION ALL SELECT 'dim_supplier',                COUNT(*) FROM dwh.dim_supplier
    UNION ALL SELECT 'dim_medication',              COUNT(*) FROM dwh.dim_medication
    UNION ALL SELECT 'dim_patient',                 COUNT(*) FROM dwh.dim_patient
) t ORDER BY table_name;

\echo ''
\echo '================================================='
\echo ' Setup complete. Next steps:'
\echo '   python python/generate_patients.py'
\echo '   python python/generate_prescriptions.py'
\echo '   python python/generate_inventory.py'
\echo '   python python/generate_deliveries.py'
\echo '   python python/generate_adjustments.py'
\echo '   ./scripts/run_pipeline.sh'
\echo '================================================='
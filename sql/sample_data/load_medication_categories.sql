-- =============================================================================
-- Load Medication Category Sample Data
-- 12 categories covering all medications in load_medications.sql
-- MUST run before load_medications.sql
-- =============================================================================
SET search_path TO dwh, public;

INSERT INTO dwh.dim_medication_category (
    clinical_category, clinical_category_description,
    movement_class, movement_threshold_units_per_month, turnover_rate_category,
    value_class, value_class_description,
    is_critical_stock, criticality_reason,
    requires_cold_chain, requires_special_handling, security_level,
    default_reorder_point_formula, default_safety_stock_days, review_frequency
) VALUES

-- cat 1: Chronic - Fast Mover (A) — diabetes, cardiovascular, respiratory
(
    'Chronic', 'Long-term medications taken daily by patients with ongoing conditions',
    'Fast_Mover', 200, 'Very_High',
    'A', 'Top 20% SKUs — 80% of revenue. Zero-tolerance for stockouts.',
    TRUE, 'Life-saving',
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 14, 'Daily'
),

-- cat 2: Chronic - Medium Mover (A)
(
    'Chronic', 'Long-term medications with moderate monthly demand',
    'Medium_Mover', 80, 'High',
    'A', 'Top 20% SKUs — 80% of revenue.',
    TRUE, 'Life-saving',
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 10, 'Weekly'
),

-- cat 3: Chronic - Slow Mover (B) — specialist medications
(
    'Chronic', 'Long-term specialist medications with low monthly demand',
    'Slow_Mover', 20, 'Medium',
    'B', 'Next 30% SKUs — 15% of revenue.',
    TRUE, 'No_Substitute',
    FALSE, TRUE, 'High_Value',
    'avg_daily_usage * lead_time_days * 1.5', 21, 'Weekly'
),

-- cat 4: Seasonal - Fast Mover (A) — flu & cold season
(
    'Seasonal', 'Medications with peak demand during flu/allergy season (May-November)',
    'Fast_Mover', 300, 'Very_High',
    'A', 'Top 20% SKUs — driven by seasonal spikes.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days * seasonal_multiplier', 21, 'Weekly'
),

-- cat 5: Seasonal - Medium Mover (B)
(
    'Seasonal', 'Seasonal medications with moderate demand peaks',
    'Medium_Mover', 100, 'High',
    'B', 'Next 30% SKUs — 15% of revenue.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 14, 'Weekly'
),

-- cat 6: Seasonal - Slow Mover (C)
(
    'Seasonal', 'Seasonal medications that are slow-moving outside peak periods',
    'Slow_Mover', 30, 'Low',
    'C', 'Bottom 50% SKUs — 5% of revenue.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_monthly_demand / 4', 7, 'Monthly'
),

-- cat 7: Regular - Fast Mover (A) — OTC painkillers, antacids, vitamins
(
    'Regular', 'Everyday OTC medications bought routinely regardless of season',
    'Fast_Mover', 400, 'Very_High',
    'A', 'Top 20% SKUs — 80% of revenue.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 7, 'Weekly'
),

-- cat 8: Regular - Medium Mover (B)
(
    'Regular', 'Regularly purchased medications with moderate demand',
    'Medium_Mover', 100, 'High',
    'B', 'Next 30% SKUs — 15% of revenue.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 10, 'Weekly'
),

-- cat 9: Regular - Slow Mover (C)
(
    'Regular', 'Regularly available but slow-selling OTC products',
    'Slow_Mover', 25, 'Low',
    'C', 'Bottom 50% SKUs — 5% of revenue.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_monthly_demand / 3', 7, 'Monthly'
),

-- cat 10: Acute - Fast Mover (A) — antibiotics, acute scripts
(
    'Acute', 'Short-course medications for acute illnesses, high prescription turnover',
    'Fast_Mover', 250, 'High',
    'A', 'Top 20% SKUs — high script volume.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 10, 'Weekly'
),

-- cat 11: Acute - Medium Mover (B)
(
    'Acute', 'Acute medications with moderate prescription volumes',
    'Medium_Mover', 80, 'Medium',
    'B', 'Next 30% SKUs — 15% of revenue.',
    FALSE, NULL,
    FALSE, FALSE, 'Standard',
    'avg_daily_usage * lead_time_days + safety_stock', 14, 'Weekly'
),

-- cat 12: Controlled Substances (C/B) — S5/S6 schedule, strict handling
(
    'Regular', 'Schedule 5/6 controlled substances requiring special dispensing procedures',
    'Slow_Mover', 15, 'Low',
    'B', 'High-value items requiring strict stock control.',
    TRUE, 'Controlled_Substance',
    FALSE, TRUE, 'Controlled_Substance',
    'strict_manual_count * 2', 30, 'Daily'
);

-- Verify
SELECT category_key, clinical_category, movement_class, value_class
FROM dwh.dim_medication_category
ORDER BY category_key;
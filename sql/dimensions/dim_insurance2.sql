---DELETE THIS FILE

INSERT INTO dim_insurance (
    insurance_id, scheme_code, provider_name, scheme_name,
    plan_type, network_type,
    default_coverage_percentage, annual_limit,
    chronic_benefit_available, chronic_coverage_percentage,
    default_copay_amount, dispensing_fee_covered,
    has_formulary_restrictions, requires_generic_substitution,
    requires_pre_authorization,
    average_reimbursement_time_days, payment_reliability_rating,
    invoice_submission_method,
    claims_contact_number, claims_email,
    is_active, contract_start_date
) VALUES
(
    'INS-001', 'DISC-EXEC', 'Discovery Health', 'Executive Plan',
    'Comprehensive', 'Open',
    100.00, 500000.00,
    TRUE, 100.00, 0.00, TRUE,
    FALSE, FALSE, FALSE,
    7, 'Excellent', 'EDI',
    '0860 99 88 77', 'claims@discovery.co.za',
    TRUE, '2020-01-01'
),
(
    'INS-002', 'DISC-SAVER', 'Discovery Health', 'Classic Saver',
    'Savings_Plan', 'Restricted',
    70.00, 100000.00,
    TRUE, 80.00, 50.00, FALSE,
    TRUE, TRUE, TRUE,
    10, 'Good', 'Portal',
    '0860 99 88 77', 'claims@discovery.co.za',
    TRUE, '2020-01-01'
),
(
    'INS-003', 'MOM-INCENT', 'Momentum Health', 'Incentive Option',
    'Comprehensive', 'Open',
    90.00, 400000.00,
    TRUE, 100.00, 20.00, TRUE,
    FALSE, FALSE, FALSE,
    8, 'Excellent', 'EDI',
    '0860 11 77 89', 'claims@momentum.co.za',
    TRUE, '2020-03-01'
),
(
    'INS-004', 'BON-STAN', 'Bonitas', 'BonComprehensive',
    'Comprehensive', 'Closed',
    85.00, 300000.00,
    TRUE, 100.00, 30.00, TRUE,
    TRUE, FALSE, TRUE,
    12, 'Good', 'Email',
    '0860 002 108', 'claims@bonitas.co.za',
    TRUE, '2020-06-01'
),
(
    'INS-005', 'CASH', 'Cash Patient', 'No Medical Aid',
    'Hospital_Plan', 'Open',
    0.00, 0.00,
    FALSE, 0.00, 0.00, FALSE,
    FALSE, FALSE, FALSE,
    0, 'N/A', 'N/A',
    'N/A', 'N/A',
    TRUE, '2020-01-01'
),
(
    'INS-006', 'MEDSH-NET', 'Medshield', 'NetCare Network',
    'Network_Option', 'Restricted',
    75.00, 200000.00,
    TRUE, 90.00, 40.00, TRUE,
    TRUE, TRUE, FALSE,
    14, 'Fair', 'Portal',
    '0860 002 677', 'claims@medshield.co.za',
    TRUE, '2021-01-01'
);
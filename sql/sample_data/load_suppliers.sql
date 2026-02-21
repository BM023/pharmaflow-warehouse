-- ============================================================================
-- Load Supplier Sample Data
-- 4 South African pharmaceutical suppliers
-- ============================================================================

SET search_path TO dwh, public;

-- Insert 4 pharmaceutical suppliers
INSERT INTO dwh.dim_supplier (
    supplier_id, supplier_code, supplier_name, trading_name,
    company_registration_number, vat_number, supplier_type,
    primary_contact_name, phone_number, email, website,
    address_line1, city, province, postal_code,
    payment_terms, credit_limit, discount_percentage,
    minimum_order_value, delivery_fee, free_delivery_threshold,
    average_delivery_lead_time_days, on_time_delivery_rate,
    order_accuracy_rate, reliability_rating,
    delivery_days, delivery_cutoff_time, delivery_area_coverage,
    cold_chain_capable, emergency_delivery_available,
    is_active, is_preferred_supplier,
    contract_start_date, contract_end_date
) VALUES
(
    'SUP-001', 'ASP', 'Aspen Pharmacare', 'Aspen SA',
    '1985/123456/07', '4123456789', 'Manufacturer',
    'John Pietersen', '+27 11 239 6100', 'orders@aspenpharma.co.za', 'www.aspenpharma.com',
    '1 Melrose Boulevard', 'Johannesburg', 'Gauteng', '2196',
    '30_Days', 500000.00, 5.00,
    5000.00, 150.00, 20000.00,
    2, 95.50, 98.20, 'Excellent',
    'Mon_Wed_Fri', '14:00:00', 'National',
    TRUE, TRUE,
    TRUE, TRUE,
    '2020-01-01', '2027-12-31'
),
(
    'SUP-002', 'ADC', 'Adcock Ingram', 'Adcock Ingram Healthcare',
    '1949/034567/06', '4234567890', 'Manufacturer',
    'Sarah Naidoo', '+27 11 635 0143', 'sales@adcock.co.za', 'www.adcock.co.za',
    '1 New Road', 'Midrand', 'Gauteng', '1685',
    '60_Days', 400000.00, 3.50,
    3000.00, 100.00, 15000.00,
    3, 92.00, 96.50, 'Good',
    'Tue_Thu', '15:00:00', 'Gauteng',
    TRUE, FALSE,
    TRUE, TRUE,
    '2020-06-01', '2027-05-31'
),
(
    'SUP-003', 'UNP', 'UniPharm Distributors', 'UniPharm',
    '2005/067890/07', '4345678901', 'Distributor',
    'Mohamed Ahmed', '+27 11 555 1234', 'info@unipharm.co.za', 'www.unipharm.co.za',
    '45 Main Reef Road', 'Johannesburg', 'Gauteng', '2001',
    '30_Days', 300000.00, 4.00,
    2000.00, 80.00, 10000.00,
    1, 97.80, 99.10, 'Excellent',
    'Mon_Tue_Wed_Thu_Fri', '16:00:00', 'Gauteng',
    FALSE, TRUE,
    TRUE, TRUE,
    '2021-01-15', '2028-01-14'
),
(
    'SUP-004', 'IMP', 'Imperial Health Sciences', 'Imperial',
    '1998/012345/06', '4456789012', 'Wholesaler',
    'Thandi Dlamini', '+27 11 739 8000', 'orders@ih.co.za', 'www.imperialhealth.co.za',
    'Box 1009, Bedfordview', 'Johannesburg', 'Gauteng', '2008',
    '45_Days', 600000.00, 6.00,
    8000.00, 200.00, 25000.00,
    2, 94.30, 97.80, 'Excellent',
    'Daily', '12:00:00', 'National',
    TRUE, TRUE,
    TRUE, TRUE,
    '2019-03-01', '2026-02-28'
);

-- Verify
SELECT COUNT(*) as supplier_count FROM dwh.dim_supplier;
SELECT supplier_code, supplier_name, reliability_rating FROM dwh.dim_supplier;
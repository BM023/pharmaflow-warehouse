-- =============================================================================
-- Load Pharmacy Data
-- 5 PharmaFlow locations across Johannesburg
-- NOTE: The CREATE TABLE is in schema.sql. This file inserts data only.
-- =============================================================================
SET search_path TO dwh, public;

INSERT INTO dwh.dim_pharmacy (
    pharmacy_id, license_number, location_name, store_code,
    address_line1, suburb, city, province, postal_code,
    gps_latitude, gps_longitude,
    demographic_profile, catchment_area_population, competition_level,
    foot_traffic_level, parking_availability,
    square_meters, number_of_dispensing_stations,
    has_drive_through, has_clinic_on_site,
    manager_name, pharmacist_in_charge, phone_number, email,
    operating_hours, monthly_average_revenue, monthly_average_transactions,
    customer_satisfaction_rating, inventory_turnover_rate,
    opening_date, license_expiry_date
) VALUES
(
    'PF-001', 'LIC-2020-001', 'PharmaFlow Sandton', 'SAND',
    '123 Rivonia Road', 'Sandton', 'Johannesburg', 'Gauteng', '2196',
    -26.1076, 28.0567,
    'Affluent', 250000, 'High', 'Very_High', 'Ample',
    450.00, 4, TRUE, TRUE,
    'Thandi Ndlovu', 'Dr. Sarah Nkosi', '+27 11 234 5678',
    'sandton@pharmaflow.co.za',
    'Mon-Fri: 7AM-9PM, Sat-Sun: 8AM-6PM', 850000.00, 3500,
    4.5, 8.2,
    '2020-03-15', '2027-03-14'
),
(
    'PF-002', 'LIC-2020-002', 'PharmaFlow Soweto', 'SOWT',
    '45 Koma Road', 'Orlando East', 'Johannesburg', 'Gauteng', '1804',
    -26.2419, 27.8661,
    'Township', 450000, 'Medium', 'High', 'Limited',
    320.00, 3, FALSE, TRUE,
    'Sipho Mokoena', 'Dr. John Maseko', '+27 11 987 6543',
    'soweto@pharmaflow.co.za',
    'Mon-Sat: 8AM-6PM, Sun: 9AM-2PM', 420000.00, 4200,
    4.2, 9.5,
    '2020-06-01', '2027-05-31'
),
(
    'PF-003', 'LIC-2021-003', 'PharmaFlow CBD', 'CBD',
    '78 Commissioner Street', 'Johannesburg CBD', 'Johannesburg', 'Gauteng', '2001',
    -26.2041, 28.0473,
    'CBD', 180000, 'Very_High', 'Very_High', 'Street_Only',
    280.00, 3, FALSE, FALSE,
    'Nomsa Khumalo', 'Dr. David Chen', '+27 11 456 7890',
    'cbd@pharmaflow.co.za',
    'Mon-Fri: 7AM-7PM, Sat: 8AM-3PM', 520000.00, 2800,
    3.9, 10.1,
    '2021-01-10', '2028-01-09'
),
(
    'PF-004', 'LIC-2021-004', 'PharmaFlow Rosebank', 'ROSE',
    'The Mall of Rosebank, Shop 45', 'Rosebank', 'Johannesburg', 'Gauteng', '2196',
    -26.1482, 28.0425,
    'Upper_Middle', 320000, 'High', 'High', 'Ample',
    380.00, 3, FALSE, FALSE,
    'Lerato Mahlangu', 'Dr. Precious Dlamini', '+27 11 789 0123',
    'rosebank@pharmaflow.co.za',
    'Mon-Sun: 9AM-8PM', 680000.00, 3100,
    4.4, 7.8,
    '2021-08-20', '2028-08-19'
),
(
    'PF-005', 'LIC-2022-005', 'PharmaFlow Midrand', 'MIDR',
    '200 Old Pretoria Road', 'Midrand', 'Johannesburg', 'Gauteng', '1685',
    -25.9953, 28.1289,
    'Middle_Income', 280000, 'Medium', 'Medium', 'Ample',
    350.00, 3, TRUE, FALSE,
    'Zanele Sithole', 'Dr. Michael van Wyk', '+27 11 345 6789',
    'midrand@pharmaflow.co.za',
    'Mon-Fri: 8AM-7PM, Sat: 8AM-5PM, Sun: 9AM-2PM', 480000.00, 2900,
    4.3, 8.7,
    '2022-02-14', '2029-02-13'
);

SELECT pharmacy_id, store_code, location_name, demographic_profile
FROM dwh.dim_pharmacy
ORDER BY pharmacy_key;
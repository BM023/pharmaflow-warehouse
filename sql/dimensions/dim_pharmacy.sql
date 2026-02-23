CREATE TABLE dwh.dim_pharmacy (
    pharmacy_key SERIAL PRIMARY KEY,
    pharmacy_id VARCHAR(20) NOT NULL UNIQUE,
    license_number VARCHAR(30) NOT NULL UNIQUE,
    
    -- Location details
    location_name VARCHAR(100) NOT NULL,
    store_code VARCHAR(10) NOT NULL UNIQUE,
    address_line1 VARCHAR(200),
    address_line2 VARCHAR(200),
    suburb VARCHAR(100),
    city VARCHAR(100) NOT NULL,
    province VARCHAR(50) NOT NULL,
    postal_code VARCHAR(10),
    gps_latitude DECIMAL(10, 8),
    gps_longitude DECIMAL(11, 8),
    
    -- Demographics & market
    demographic_profile VARCHAR(30),
    catchment_area_population INTEGER,
    competition_level VARCHAR(20),
    foot_traffic_level VARCHAR(20),
    parking_availability VARCHAR(30),
    
    -- Facility information
    square_meters DECIMAL(8, 2),
    number_of_dispensing_stations SMALLINT,
    has_drive_through BOOLEAN DEFAULT FALSE,
    has_clinic_on_site BOOLEAN DEFAULT FALSE,
    has_cold_storage BOOLEAN DEFAULT TRUE,
    
    -- Operational details
    manager_name VARCHAR(100),
    pharmacist_in_charge VARCHAR(100),
    phone_number VARCHAR(20),
    email VARCHAR(100),
    operating_hours VARCHAR(200),
    is_24_hours BOOLEAN DEFAULT FALSE,
    
    -- Business metrics
    monthly_average_revenue DECIMAL(12, 2),
    monthly_average_transactions INTEGER,
    customer_satisfaction_rating DECIMAL(2, 1),
    inventory_turnover_rate DECIMAL(5, 2),
    
    -- Dates
    opening_date DATE NOT NULL,
    last_audit_date DATE,
    license_expiry_date DATE,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    status VARCHAR(30) DEFAULT 'Open',
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for dim_pharmacy
CREATE INDEX idx_pharmacy_city ON dwh.dim_pharmacy(city);
CREATE INDEX idx_pharmacy_demographic ON dwh.dim_pharmacy(demographic_profile);
CREATE INDEX idx_pharmacy_active ON dwh.dim_pharmacy(is_active);
CREATE INDEX idx_pharmacy_code ON dwh.dim_pharmacy(store_code);

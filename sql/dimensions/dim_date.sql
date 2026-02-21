CREATE TABLE dwh.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    
    -- Day attributes
    day_of_month SMALLINT NOT NULL,
    day_of_week SMALLINT NOT NULL,
    day_name VARCHAR(10) NOT NULL,
    day_name_short VARCHAR(3) NOT NULL,
    
    -- Week attributes
    week_of_month SMALLINT NOT NULL,
    week_of_year SMALLINT NOT NULL,
    
    -- Month attributes
    month SMALLINT NOT NULL,
    month_name VARCHAR(10) NOT NULL,
    month_name_short VARCHAR(3) NOT NULL,
    
    -- Quarter attributes
    quarter SMALLINT NOT NULL,
    quarter_name VARCHAR(2) NOT NULL,
    
    -- Year attributes
    year SMALLINT NOT NULL,
    year_month INTEGER NOT NULL,
    year_quarter VARCHAR(10) NOT NULL,
    
    -- Business calendar
    is_weekend BOOLEAN NOT NULL DEFAULT FALSE,
    is_public_holiday BOOLEAN NOT NULL DEFAULT FALSE,
    holiday_name VARCHAR(50),
    is_month_start BOOLEAN NOT NULL DEFAULT FALSE,
    is_month_end BOOLEAN NOT NULL DEFAULT FALSE,
    is_quarter_start BOOLEAN NOT NULL DEFAULT FALSE,
    is_quarter_end BOOLEAN NOT NULL DEFAULT FALSE,
    is_year_start BOOLEAN NOT NULL DEFAULT FALSE,
    is_year_end BOOLEAN NOT NULL DEFAULT FALSE,
    
    -- South African specific
    season VARCHAR(10) NOT NULL,
    is_flu_season BOOLEAN NOT NULL DEFAULT FALSE,
    is_allergy_season BOOLEAN NOT NULL DEFAULT FALSE,
    is_school_holiday BOOLEAN NOT NULL DEFAULT FALSE,
    fiscal_year SMALLINT NOT NULL,
    fiscal_quarter VARCHAR(10) NOT NULL,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for dim_date
CREATE INDEX idx_date_full_date ON dwh.dim_date(full_date);
CREATE INDEX idx_date_year_month ON dwh.dim_date(year_month);
CREATE INDEX idx_date_year ON dwh.dim_date(year);
CREATE INDEX idx_date_season ON dwh.dim_date(season);

-- Populate dim_date with 10 years of data (2020-2030)
DO $$
DECLARE
    start_date DATE := '2020-01-01';
    end_date DATE := '2030-12-31';
    current_date_iter DATE;
    date_key_val INTEGER;
    dow INTEGER;
    month_val INTEGER;
    year_val INTEGER;
    season_val VARCHAR(10);
    fiscal_year_val SMALLINT;
BEGIN
    current_date_iter := start_date;
    
    WHILE current_date_iter <= end_date LOOP
        date_key_val := EXTRACT(YEAR FROM current_date_iter) * 10000 
                      + EXTRACT(MONTH FROM current_date_iter) * 100 
                      + EXTRACT(DAY FROM current_date_iter);
        
        dow := EXTRACT(DOW FROM current_date_iter);
        month_val := EXTRACT(MONTH FROM current_date_iter);
        year_val := EXTRACT(YEAR FROM current_date_iter);
        
        season_val := CASE 
            WHEN month_val IN (12, 1, 2) THEN 'Summer'
            WHEN month_val IN (3, 4, 5) THEN 'Autumn'
            WHEN month_val IN (6, 7, 8) THEN 'Winter'
            WHEN month_val IN (9, 10, 11) THEN 'Spring'
        END;
        
        fiscal_year_val := CASE 
            WHEN month_val >= 4 THEN year_val
            ELSE year_val - 1
        END;
        
        INSERT INTO dwh.dim_date (
            date_key, full_date,
            day_of_month, day_of_week, day_name, day_name_short,
            week_of_month, week_of_year,
            month, month_name, month_name_short,
            quarter, quarter_name,
            year, year_month, year_quarter,
            is_weekend, is_month_start, is_month_end,
            is_quarter_start, is_quarter_end,
            is_year_start, is_year_end,
            season, is_flu_season, is_allergy_season,
            fiscal_year, fiscal_quarter
        ) VALUES (
            date_key_val,
            current_date_iter,
            EXTRACT(DAY FROM current_date_iter),
            CASE dow WHEN 0 THEN 7 ELSE dow END,
            TRIM(TO_CHAR(current_date_iter, 'Day')),
            TRIM(TO_CHAR(current_date_iter, 'Dy')),
            CEIL(EXTRACT(DAY FROM current_date_iter) / 7.0),
            EXTRACT(WEEK FROM current_date_iter),
            month_val,
            TRIM(TO_CHAR(current_date_iter, 'Month')),
            TRIM(TO_CHAR(current_date_iter, 'Mon')),
            EXTRACT(QUARTER FROM current_date_iter),
            'Q' || EXTRACT(QUARTER FROM current_date_iter),
            year_val,
            year_val * 100 + month_val,
            year_val || 'Q' || EXTRACT(QUARTER FROM current_date_iter),
            dow IN (0, 6),
            EXTRACT(DAY FROM current_date_iter) = 1,
            current_date_iter = (DATE_TRUNC('MONTH', current_date_iter) + INTERVAL '1 MONTH - 1 day')::DATE,
            (month_val IN (1, 4, 7, 10) AND EXTRACT(DAY FROM current_date_iter) = 1),
            (month_val IN (3, 6, 9, 12) AND current_date_iter = (DATE_TRUNC('MONTH', current_date_iter) + INTERVAL '1 MONTH - 1 day')::DATE),
            month_val = 1 AND EXTRACT(DAY FROM current_date_iter) = 1,
            month_val = 12 AND EXTRACT(DAY FROM current_date_iter) = 31,
            season_val,
            month_val BETWEEN 5 AND 9,
            month_val BETWEEN 8 AND 11,
            fiscal_year_val,
            'FY' || fiscal_year_val || 'Q' || CASE 
                WHEN month_val IN (4,5,6) THEN 1
                WHEN month_val IN (7,8,9) THEN 2
                WHEN month_val IN (10,11,12) THEN 3
                ELSE 4
            END
        );
        
        current_date_iter := current_date_iter + INTERVAL '1 day';
    END LOOP;
END $$;
# PharmaFlow Analytics 

**Pharmaceutical Data Pipeline & Warehouse**

A complete ETL data pipeline and warehouse solution for pharmacy inventory and prescription tracking.

## Project Overview

PharmaFlow Analytics simulates a mid-sized pharmacy chain with 5 locations across Johannesburg. The project demonstrates end-to-end data engineering skills including warehouse design, ETL pipelines, automation, and data quality management.

## Business Domain

**Company:** PharmaFlow Analytics  
**Locations:** 5 pharmacies serving diverse demographics (Sandton, Soweto, CBD, Rosebank, Midrand)  
**Core Operations:**
- Prescription dispensing and tracking
- Multi-location inventory management
- Supplier delivery monitoring
- Insurance claims processing
- Stock level optimization

## Technical Architecture

### Data Warehouse (Star Schema)
- **8 Dimension Tables:** Date, Patient, Medication, Doctor, Pharmacy, Insurance, Supplier, Category
- **4 Fact Tables:** Prescription Transactions, Inventory Snapshots, Supplier Deliveries, Stock Adjustments
- **Database:** PostgreSQL 15 (Docker containerized)
- **Records:** 15,000+ transactions across 6 months

### ETL Pipeline
- **Shell Scripts:** File monitoring, validation, staging
- **Python:** Data extraction, transformation, loading
- **Orchestration:** Apache Airflow (planned)
- **Data Sources:** CSV, JSON, Excel files with intentional quality issues

## Features

- **SCD Type 2:** Historical price tracking for medications
- **Data Quality Handling:** Duplicates, missing values, format errors, outliers
- **Seasonal Analysis:** Flu season and allergy season patterns
- **Demographics:** Location-based inventory and sales patterns
- **Automation:** Scheduled daily processing with cron jobs

## Technology Stack

- **Database:** PostgreSQL 15
- **Languages:** Python 3.13, Bash/Shell
- **Python Libraries:** pandas, psycopg2, Faker, openpyxl
- **Containerization:** Docker
- **Version Control:** Git/GitHub
- **Orchestration:** Apache Airflow (in progress)

## Project Structure
```
pharmaflow_warehouse/
├── sql/
│   ├── transactions/
│   │   ├── generate_deliveries.sql
│   │   ├── generate_inventory.sql
│   │   └── export_perscriptions.sql
│   ├── dimensions/
│   │   ├── dim_date.sql
│   │   ├── dim_doctor.sql
│   │   ├── dim_insurance.sql
│   │   ├── dim_supplier.sql
│   │   ├── dim_medication.sql
│   │   ├── dim_medication_category.sql
│   │   ├── dim_patient.sql
│   │   └── dim_pharmacy.sql
│   ├── facts/
│   │   ├── fact_prescription_transactions.sql
│   │   ├── fact_inventory_snapshots.sql
│   │   ├── fact_supplier_deliveries.sql
│   │   └── fact_stock_adjustments.sql
│   └── sample_data/
│       ├── load_doctors.sql
│       ├── load_medications.sql
│       ├── load_insurance.sql
│       ├── load_patients.sql
│       └── load_suppliers.sql
├── python/
│   ├── generate_patients.py
│   ├── generate_prescriptions.py
│   ├── generate_inventory.py
│   ├── generate_deliveries.py
│   ├── generate_adjustments.py
│   └── export_sample_files.py
├── scripts/
│   ├── monitor_files.sh
│   ├── process_file.sh
│   ├── cleanup_logs.sh
│   ├── steup_cron.sh
│   └── run_pipeline.sh
├── setup/
│   └── schema.sql
├── raw_data/
├── staging/
├── processed/
├── archive/
├── logs/
├── docker/
│   └──  docker-compose.yml
├── venv/ 
├── .venv/ 
├── .env
├── requirements.txt
├── README.md
└── .gitignore
```

## Setup Instructions

### Prerequisites
- Docker Desktop
- Python 3.13+
- Git

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/YOUR_USERNAME/pharmaflow-warehouse.git
cd pharmaflow-warehouse
```

2. **Set up PostgreSQL with Docker**
```bash
docker run --name pharmaflow-db \
  -e POSTGRES_PASSWORD=pharmaflow2024 \
  -e POSTGRES_USER=pharmaflow \
  -e POSTGRES_DB=pharmaflow_warehouse \
  -p 5433:5432 \
  -v pharmaflow-data:/var/lib/postgresql/data \
  -d postgres:15
```

3. **Create virtual environment**
```bash
python3 -m venv venv
source venv/bin/activate  # On Mac/Linux
pip install -r requirements.txt
```

4. **Set up environment variables**
```bash
cp .env.example .env
# Edit .env with your database credentials
```

5. **Build data warehouse**
```bash
docker exec -i pharmaflow-db psql -U pharmaflow -d pharmaflow_warehouse < sql/00_master/complete_warehouse.sql
```

6. **Load sample data**
```bash
python python/generate_patients.py
python python/generate_prescriptions.py
python python/generate_inventory.py
python python/generate_deliveries.py
python python/generate_adjustments.py
```

7. **Generate source files for ETL**
```bash
python python/export_sample_files.py
```

8. **Run ETL pipeline**
```bash
./scripts/run_pipeline.sh
```

## Data Warehouse Schema

### Dimension Tables
- `dim_date` - Calendar dimension (4,018 dates)
- `dim_patient` - Customer information (500 patients)
- `dim_medication` - Product catalog with SCD Type 2 (60 medications)
- `dim_doctor` - Prescriber information (30 doctors)
- `dim_pharmacy` - Store locations (5 pharmacies)
- `dim_insurance` - Medical aid schemes (6 schemes)
- `dim_supplier` - Pharmaceutical suppliers (4 suppliers)
- `dim_medication_category` - Stock classifications (12 categories)

### Fact Tables
- `fact_prescription_transactions` - Prescription fills (5,000+ records)
- `fact_inventory_snapshots` - Daily stock levels (9,000 records)
- `fact_supplier_deliveries` - Procurement data (500 deliveries)
- `fact_stock_adjustments` - Inventory corrections (200 adjustments)

## Key Analyses Supported

- Prescription trends by location, medication, and time
- Inventory turnover and stockout analysis
- Seasonal demand patterns (flu season, allergy season)
- Supplier performance metrics
- Patient demographics and chronic medication adherence
- Revenue and profit margin analysis
- Insurance reimbursement tracking

## Author

Boikanyo Maswi  
Data Engineering Portfolio Project  
February 2026

## License

This project is for educational and portfolio purposes.





```
pharmaflow_warehouse/
├── sql/
│   ├── transactions/
│   │   ├── generate_deliveries.sql  (EMPTY)
│   │   ├── generate_inventory.sql  (EMPTY)
│   │   └── export_perscriptions.sql  (EMPTY)
│   │
│   ├── dimensions/
│   │   ├── dim_date.sql
│   │   ├── dim_doctor.sql
│   │   ├── dim_insurance.sql
│   │   ├── dim_supplier.sql
│   │   ├── dim_medication.sql
│   │   ├── dim_medication_category.sql
│   │   ├── dim_patient.sql
│   │   └── dim_pharmacy.sql
│   │
│   ├── facts/
│   │   ├── fact_prescription_transactions.sql
│   │   ├── fact_inventory_snapshots.sql
│   │   ├── fact_supplier_deliveries.sql
│   │   └── fact_stock_adjustments.sql
│   │
│   └── sample_data/
│       ├── load_doctors.sql
│       ├── load_medications.sql
│       ├── load_insurance.sql
│       ├── load_patients.sql
│       └── load_suppliers.sql
│
├── python/
│   ├── generate_patients.py
│   ├── generate_prescriptions.py
│   ├── generate_inventory.py
│   ├── generate_deliveries.py
│   ├── generate_adjustments.py
│   ├── export_sample_files.py
│   └── etl/
│       ├── __init__.py
│       ├── extract.py 
│       ├── transform.py
│       └── load.py
│
├── scripts/
│   ├── monitor_files.sh   (EMPTY)
│   ├── process_file.sh  (EMPTY)
│   ├── cleanup_logs.sh  (EMPTY)
│   ├── steup_cron.sh  (EMPTY)
│   └── run_pipeline.sh  (EMPTY)
│
├── setup/
│   └── schema.sql
│
├── raw_data/  (NOT VISIBLE IN REPO)
│   ├── 2026-02-20
│   │   ├── inventory_snapshot_2026-02-20.xlsx
│   │   ├── medication_catalog.json
│   │   └── perscriptions_2026-02-20.csv
│   │
│   └── 2026-02-21
│       ├── inventory_snapshot_2026-02-21.xlsx
│       ├── medication_catalog.json
│       ├── perscriptions_2026-02-21.csv
│       ├── new_patients.csv
│       └── README.md
│
├── staging/
├── processed/
├── archive/
├── logs/
├── docker-compose.yml
├── .venv/
├── venv/
├── .env
├── requirements.txt
├── README.md
└── .gitignore
```
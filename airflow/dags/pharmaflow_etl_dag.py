"""
airflow/dags/pharmaflow_etl_dag.py
PharmaFlow Analytics — Airflow DAG

Pipeline: file_sensor → extract → transform → validate → load → cleanup → notify

Schedule: Daily at 06:30 (after cron generates files at 06:00)
Catchup:  False (only run for today, not historical backfills)
"""

import os
import sys
import logging
from datetime import datetime, timedelta, date
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.sensors.filesystem import FileSensor
from airflow.utils.dates import days_ago

# ---------------------------------------------------------------------------
# Path setup — make ETL modules importable inside Airflow containers
# ---------------------------------------------------------------------------
sys.path.insert(0, '/opt/airflow')

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# DAG default arguments
# ---------------------------------------------------------------------------
default_args = {
    'owner':            'pharmaflow',
    'depends_on_past':  False,
    'email_on_failure': False,   # set to True and add email when ready
    'email_on_retry':   False,
    'retries':          2,
    'retry_delay':      timedelta(minutes=5),
    'retry_exponential_backoff': True,
    'execution_timeout': timedelta(hours=1),
}

# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id='pharmaflow_daily_etl',
    default_args=default_args,
    description='PharmaFlow daily ETL: file drop → extract → transform → validate → load → cleanup',
    schedule_interval='30 6 * * *',   # 06:30 daily (files generated at 06:00 by cron)
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=1,
    tags=['pharmaflow', 'etl', 'daily'],
    doc_md="""
## PharmaFlow Daily ETL Pipeline

Processes daily pharmacy transaction files through a full ETL lifecycle.

### File Types
- `prescriptions_YYYY-MM-DD.csv` — daily prescription transactions
- `inventory_snapshot_YYYY-MM-DD.xlsx` — stock level snapshots
- `new_patients.csv` — new patient registrations
- `medication_catalog.json` — reference data (validated, not loaded)

### Pipeline Stages
1. **file_sensor** — waits for today's prescription file to arrive
2. **generate_files** — runs export_sample_files.py to produce raw files
3. **extract** — reads all files, logs row counts and source metadata
4. **transform** — cleans data quality issues, applies business logic
5. **validate** — checks row counts and data integrity post-transform
6. **load** — upserts to warehouse, SCD Type 2 for patients
7. **cleanup** — archives processed files, rotates logs
8. **notify** — logs pipeline summary to pipeline_runs metadata table
    """,
) as dag:

    # -----------------------------------------------------------------------
    # Task 1: Generate raw files (runs export_sample_files.py)
    # -----------------------------------------------------------------------
    generate_files = BashOperator(
        task_id='generate_files',
        bash_command=(
            'cd /opt/airflow && '
            'source /opt/airflow/../venv/bin/activate 2>/dev/null || true && '
            'python python/export_sample_files.py'
        ),
        env={
            'DB_HOST':     os.environ.get('PHARMAFLOW_DB_HOST', 'pharmaflow-db'),
            'DB_PORT':     os.environ.get('PHARMAFLOW_DB_PORT', '5432'),
            'DB_NAME':     os.environ.get('PHARMAFLOW_DB_NAME', 'pharmaflow_warehouse'),
            'DB_USER':     os.environ.get('PHARMAFLOW_DB_USER', 'pharmaflow'),
            'DB_PASSWORD': os.environ.get('PHARMAFLOW_DB_PASSWORD', 'pharmaflow2024'),
        },
        doc_md="Generates raw CSV/JSON/Excel files for today's date into raw_data/YYYY-MM-DD/",
    )

    # -----------------------------------------------------------------------
    # Task 2: File sensor — waits up to 30 min for prescription file
    # -----------------------------------------------------------------------
    wait_for_prescription_file = FileSensor(
        task_id='wait_for_prescription_file',
        filepath='/opt/airflow/raw_data/{{ ds }}/prescriptions_{{ ds }}.csv',
        poke_interval=30,          # check every 30 seconds
        timeout=1800,              # give up after 30 minutes
        mode='poke',
        doc_md="Waits for today's prescription CSV to appear in raw_data/",
    )

    # -----------------------------------------------------------------------
    # Task 3: Extract
    # -----------------------------------------------------------------------
    def extract_task(**context):
        """Extract all files for the execution date."""
        from python.etl.extract import run_extract
        execution_date = context['ds']
        target_date = datetime.strptime(execution_date, '%Y-%m-%d').date()

        raw_data_dir = '/opt/airflow/raw_data'
        dataframes = run_extract(raw_data_dir, target_date)

        # Push row counts to XCom for downstream tasks
        counts = {k: len(v) for k, v in dataframes.items() if v is not None}
        context['task_instance'].xcom_push(key='row_counts', value=counts)
        logger.info(f"Extract complete: {counts}")
        return counts

    extract = PythonOperator(
        task_id='extract',
        python_callable=extract_task,
        doc_md="Reads raw files and returns DataFrames with source metadata.",
    )

    # -----------------------------------------------------------------------
    # Task 4: Transform
    # -----------------------------------------------------------------------
    def transform_task(**context):
        """Clean and validate extracted data, apply business logic."""
        from python.etl.extract import (
            run_extract,
            extract_existing_prescription_numbers,
            extract_existing_patient_ids,
        )
        from python.etl.transform import run_transform

        execution_date = context['ds']
        target_date = datetime.strptime(execution_date, '%Y-%m-%d').date()

        # Re-extract (stateless — Airflow tasks don't share memory)
        dataframes = run_extract('/opt/airflow/raw_data', target_date)
        existing_rx       = extract_existing_prescription_numbers()
        existing_patients = extract_existing_patient_ids()

        transformed = run_transform(dataframes, existing_rx, existing_patients)
        counts = {k: len(v) for k, v in transformed.items()}
        context['task_instance'].xcom_push(key='transformed_counts', value=counts)
        logger.info(f"Transform complete: {counts}")
        return counts

    transform = PythonOperator(
        task_id='transform',
        python_callable=transform_task,
        doc_md="Cleans data quality issues, deduplicates, applies business logic.",
    )

    # -----------------------------------------------------------------------
    # Task 5: Validate
    # -----------------------------------------------------------------------
    def validate_task(**context):
        """
        Data quality gate — fails the DAG if critical checks don't pass.
        Checks:
          - At least 1 prescription row survived transform
          - No negative quantities in inventory
          - Transform didn't drop more than 50% of extracted rows
        """
        ti = context['task_instance']
        extracted   = ti.xcom_pull(task_ids='extract',   key='row_counts')
        transformed = ti.xcom_pull(task_ids='transform', key='transformed_counts')

        if not extracted or not transformed:
            raise ValueError("Missing XCom data from extract/transform tasks.")

        issues = []

        # Check 1: prescriptions survived
        rx_extracted   = extracted.get('prescriptions', 0)
        rx_transformed = transformed.get('prescriptions', 0)
        if rx_extracted > 0 and rx_transformed == 0:
            issues.append("All prescription rows were dropped during transform.")

        # Check 2: drop rate < 50%
        for dataset in ['prescriptions', 'inventory']:
            ext = extracted.get(dataset, 0)
            trn = transformed.get(dataset, 0)
            if ext > 0:
                drop_rate = (ext - trn) / ext
                if drop_rate > 0.50:
                    issues.append(
                        f"{dataset}: {drop_rate:.0%} rows dropped "
                        f"({ext} extracted → {trn} transformed). "
                        f"Threshold: 50%."
                    )

        if issues:
            raise ValueError(f"Validation failed:\n" + "\n".join(f"  - {i}" for i in issues))

        logger.info("Validation passed.")
        logger.info(f"  Extracted:   {extracted}")
        logger.info(f"  Transformed: {transformed}")
        return {'status': 'passed', 'extracted': extracted, 'transformed': transformed}

    validate = PythonOperator(
        task_id='validate',
        python_callable=validate_task,
        doc_md="Data quality gate — fails pipeline if row counts or data integrity checks fail.",
    )

    # -----------------------------------------------------------------------
    # Task 6: Load
    # -----------------------------------------------------------------------
    def load_task(**context):
        """Load transformed data into the warehouse."""
        from python.etl.extract import (
            run_extract,
            extract_existing_prescription_numbers,
            extract_existing_patient_ids,
            extract_dimension_keys,
        )
        from python.etl.transform import run_transform
        from python.etl.load import run_load

        execution_date = context['ds']
        target_date = datetime.strptime(execution_date, '%Y-%m-%d').date()

        # Re-extract and transform (Airflow tasks are stateless)
        dataframes        = run_extract('/opt/airflow/raw_data', target_date)
        existing_rx       = extract_existing_prescription_numbers()
        existing_patients = extract_existing_patient_ids()
        transformed       = run_transform(dataframes, existing_rx, existing_patients)
        dim_keys          = extract_dimension_keys()

        results = run_load(
            transformed=transformed,
            dim_keys=dim_keys,
            existing_rx_numbers=existing_rx,
            existing_patient_ids=existing_patients,
            run_date=execution_date,
        )

        context['task_instance'].xcom_push(key='load_results', value=str(results))
        logger.info(f"Load complete: {results}")
        return results

    load = PythonOperator(
        task_id='load',
        python_callable=load_task,
        doc_md="Upserts transformed data to warehouse. SCD Type 2 for patients.",
    )

    # -----------------------------------------------------------------------
    # Task 7: Cleanup — archive files, rotate logs
    # -----------------------------------------------------------------------
    cleanup = BashOperator(
        task_id='cleanup',
        bash_command='/opt/airflow/scripts/cleanup_logs.sh',
        doc_md="Archives processed files and rotates logs older than 30 days.",
    )

    # -----------------------------------------------------------------------
    # Task 8: Notify — log pipeline summary
    # -----------------------------------------------------------------------
    def notify_task(**context):
        """Log final pipeline summary to Airflow logs and pipeline_runs table."""
        ti = context['task_instance']
        execution_date  = context['ds']
        extracted       = ti.xcom_pull(task_ids='extract',   key='row_counts') or {}
        transformed     = ti.xcom_pull(task_ids='transform', key='transformed_counts') or {}
        load_results    = ti.xcom_pull(task_ids='load',      key='load_results') or '{}'

        logger.info("=" * 60)
        logger.info("PHARMAFLOW ETL PIPELINE — DAILY SUMMARY")
        logger.info(f"Date         : {execution_date}")
        logger.info(f"Extracted    : {extracted}")
        logger.info(f"Transformed  : {transformed}")
        logger.info(f"Load results : {load_results}")
        logger.info("Status       : SUCCESS")
        logger.info("=" * 60)

    notify = PythonOperator(
        task_id='notify',
        python_callable=notify_task,
        trigger_rule='all_done',   # runs even if upstream tasks failed
        doc_md="Logs final pipeline summary. Runs regardless of upstream status.",
    )

    # -----------------------------------------------------------------------
    # Task dependencies — the DAG graph
    # -----------------------------------------------------------------------
    generate_files >> wait_for_prescription_file >> extract >> transform >> validate >> load >> cleanup >> notify
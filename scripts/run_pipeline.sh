#!/usr/bin/env bash
# =============================================================================
# run_pipeline.sh
# PharmaFlow Analytics — Master Pipeline Orchestrator
#
# Runs the full ETL pipeline in correct dependency order:
#   1. Generate/export raw source files
#   2. Process each file (validate → stage → load → archive)
#   3. Log everything with timestamps and row counts
#
# Usage:
#   ./scripts/run_pipeline.sh              # full run
#   ./scripts/run_pipeline.sh --dry-run    # validate only, no DB writes
#   ./scripts/run_pipeline.sh --skip-gen   # skip file generation, process existing
#
# Scheduled via: setup_cron.sh (runs daily at 06:00)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RAW_DATA_DIR="${PROJECT_ROOT}/raw_data"
STAGING_DIR="${PROJECT_ROOT}/staging"
PROCESSED_DIR="${PROJECT_ROOT}/processed"
ARCHIVE_DIR="${PROJECT_ROOT}/archive"
LOG_DIR="${PROJECT_ROOT}/logs"
PYTHON_DIR="${PROJECT_ROOT}/python"

VENV_PYTHON="${PROJECT_ROOT}/venv/bin/python"
DATE_STR="$(date +%Y-%m-%d)"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="${LOG_DIR}/pipeline_${TIMESTAMP}.log"
PIPELINE_START=$(date +%s)

DRY_RUN=false
SKIP_GEN=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)   DRY_RUN=true  ;;
        --skip-gen)  SKIP_GEN=true ;;
    esac
done

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local message="$*"
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[${ts}] [${level}] ${message}"
    echo "${line}" | tee -a "${LOG_FILE}"
}

log_info()    { log "INFO " "$@"; }
log_success() { log "OK   " "$@"; }
log_warn()    { log "WARN " "$@"; }
log_error()   { log "ERROR" "$@"; }

separator() {
    echo "$(printf '=%.0s' {1..70})" | tee -a "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Setup — ensure all directories exist
# ---------------------------------------------------------------------------
setup_directories() {
    for dir in "${RAW_DATA_DIR}" "${STAGING_DIR}" "${PROCESSED_DIR}" \
               "${ARCHIVE_DIR}" "${LOG_DIR}"; do
        mkdir -p "${dir}"
    done
    log_info "Directory structure verified."
}

# ---------------------------------------------------------------------------
# Python runner with timing and error capture
# ---------------------------------------------------------------------------
run_python() {
    local label="$1"
    local script="$2"
    local step_start; step_start=$(date +%s)

    log_info "Starting: ${label}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${VENV_PYTHON} ${script}"
        return 0
    fi

    local tmp_out; tmp_out="$(mktemp)"

    if "${VENV_PYTHON}" "${script}" > "${tmp_out}" 2>&1; then
        local step_end; step_end=$(date +%s)
        local elapsed=$(( step_end - step_start ))
        # Append Python output to log, indented
        sed 's/^/    /' "${tmp_out}" >> "${LOG_FILE}"
        log_success "${label} completed in ${elapsed}s."
    else
        local exit_code=$?
        sed 's/^/    /' "${tmp_out}" >> "${LOG_FILE}"
        log_error "${label} FAILED (exit ${exit_code}). See log: ${LOG_FILE}"
        rm -f "${tmp_out}"
        return ${exit_code}
    fi

    rm -f "${tmp_out}"
}

# ---------------------------------------------------------------------------
# File processing — validate, stage, load, archive
# ---------------------------------------------------------------------------
process_raw_files() {
    local date_folder="${RAW_DATA_DIR}/${DATE_STR}"

    if [[ ! -d "${date_folder}" ]]; then
        log_warn "No raw_data folder found for ${DATE_STR}: ${date_folder}"
        return 0
    fi

    local file_count; file_count=$(find "${date_folder}" -type f | wc -l | tr -d ' ')
    log_info "Found ${file_count} file(s) in ${date_folder}"

    while IFS= read -r -d '' file; do
        "${SCRIPT_DIR}/process_file.sh" "${file}" 2>&1 | tee -a "${LOG_FILE}"
    done < <(find "${date_folder}" -type f \( -name "*.csv" -o -name "*.json" -o -name "*.xlsx" \) -print0)
}

# ---------------------------------------------------------------------------
# Pipeline steps
# ---------------------------------------------------------------------------
step_generate_files() {
    separator
    log_info "STEP 1/4 — Generating raw source files"
    separator
    run_python "Export sample files (prescriptions/inventory/patients)" \
               "${PYTHON_DIR}/export_sample_files.py"
}

step_generate_fact_data() {
    separator
    log_info "STEP 2/4 — Loading fact table data"
    separator

    run_python "Patients (dim_patient)"                              "${PYTHON_DIR}/generate_patients.py"       || true
    run_python "Prescription transactions (fact_prescription_transactions)" "${PYTHON_DIR}/generate_prescriptions.py"
    run_python "Inventory snapshots (fact_inventory_snapshots)"      "${PYTHON_DIR}/generate_inventory.py"
    run_python "Supplier deliveries (fact_supplier_deliveries)"      "${PYTHON_DIR}/generate_deliveries.py"
    run_python "Stock adjustments (fact_stock_adjustments)"          "${PYTHON_DIR}/generate_adjustments.py"
}

step_process_files() {
    separator
    log_info "STEP 3/4 — Processing raw files through staging pipeline"
    separator
    process_raw_files
}

step_cleanup() {
    separator
    log_info "STEP 4/4 — Running cleanup"
    separator
    "${SCRIPT_DIR}/cleanup_logs.sh" 2>&1 | tee -a "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Row count verification
# ---------------------------------------------------------------------------
verify_row_counts() {
    separator
    log_info "Verifying warehouse row counts..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Skipping DB verification."
        return 0
    fi

    local query="
SELECT table_name, row_count FROM (
    SELECT 'dim_patient'                  AS table_name, COUNT(*) AS row_count FROM dwh.dim_patient
    UNION ALL SELECT 'dim_medication',                   COUNT(*) FROM dwh.dim_medication WHERE is_current=TRUE
    UNION ALL SELECT 'fact_prescription_transactions',  COUNT(*) FROM dwh.fact_prescription_transactions
    UNION ALL SELECT 'fact_inventory_snapshots',        COUNT(*) FROM dwh.fact_inventory_snapshots
    UNION ALL SELECT 'fact_supplier_deliveries',        COUNT(*) FROM dwh.fact_supplier_deliveries
    UNION ALL SELECT 'fact_stock_adjustments',          COUNT(*) FROM dwh.fact_stock_adjustments
) t ORDER BY table_name;
"
    # Use .env values if available, otherwise defaults
    DB_HOST="${DB_HOST:-localhost}"
    DB_PORT="${DB_PORT:-5433}"
    DB_NAME="${DB_NAME:-pharmaflow_warehouse}"
    DB_USER="${DB_USER:-pharmaflow}"

    PGPASSWORD="${DB_PASSWORD:-pharmaflow2024}" \
    psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
         -c "${query}" 2>&1 | tee -a "${LOG_FILE}" || \
    log_warn "Could not connect to DB for verification (pipeline may still have succeeded)."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    mkdir -p "${LOG_DIR}"

    separator
    log_info "PHARMAFLOW ANALYTICS — PIPELINE START"
    log_info "Date     : ${DATE_STR}"
    log_info "Log file : ${LOG_FILE}"
    log_info "Dry run  : ${DRY_RUN}"
    log_info "Skip gen : ${SKIP_GEN}"
    separator

    setup_directories

    if [[ "${SKIP_GEN}" == "false" ]]; then
        step_generate_files
        step_generate_fact_data
    else
        log_info "Skipping data generation (--skip-gen flag set)."
    fi

    step_process_files
    step_cleanup
    verify_row_counts

    local pipeline_end; pipeline_end=$(date +%s)
    local total_elapsed=$(( pipeline_end - PIPELINE_START ))
    local minutes=$(( total_elapsed / 60 ))
    local seconds=$(( total_elapsed % 60 ))

    separator
    log_success "PIPELINE COMPLETE — Total time: ${minutes}m ${seconds}s"
    log_info "Log saved to: ${LOG_FILE}"
    separator
}

main "$@"
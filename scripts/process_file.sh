#!/usr/bin/env bash
# =============================================================================
# process_file.sh
# PharmaFlow Analytics — Single File Processor
#
# Lifecycle for one file:
#   raw_data/ → validate → staging/ → load → processed/ (success)
#                                           → archive/failed/ (failure)
#
# Usage:
#   ./scripts/process_file.sh /path/to/raw_data/2026-02-23/prescriptions_2026-02-23.csv
#
# Called by: monitor_files.sh (on file arrival) and run_pipeline.sh (batch)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STAGING_DIR="${PROJECT_ROOT}/staging"
PROCESSED_DIR="${PROJECT_ROOT}/processed"
ARCHIVE_DIR="${PROJECT_ROOT}/archive"
LOG_DIR="${PROJECT_ROOT}/logs"
VENV_PYTHON="${PROJECT_ROOT}/venv/bin/python"

# ---------------------------------------------------------------------------
# Validate argument
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <file_path>"
    exit 1
fi

SOURCE_FILE="$1"

if [[ ! -f "${SOURCE_FILE}" ]]; then
    echo "[ERROR] File not found: ${SOURCE_FILE}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Derived values
# ---------------------------------------------------------------------------
FILE_NAME="$(basename "${SOURCE_FILE}")"
FILE_EXT="${FILE_NAME##*.}"
FILE_SIZE="$(wc -c < "${SOURCE_FILE}" | tr -d ' ') bytes"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
DATE_STR="$(date +%Y-%m-%d)"
LOG_FILE="${LOG_DIR}/file_processor_${DATE_STR}.log"
STAGED_FILE=""   # set by stage_file(), used by main()

mkdir -p "${STAGING_DIR}" "${PROCESSED_DIR}" "${ARCHIVE_DIR}/failed" "${LOG_DIR}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[${ts}] [${level}] [${FILE_NAME}] $*"
    echo "${line}" | tee -a "${LOG_FILE}"
}

log_info()    { log "INFO " "$@"; }
log_success() { log "OK   " "$@"; }
log_warn()    { log "WARN " "$@"; }
log_error()   { log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Step 1: Validate
# ---------------------------------------------------------------------------
validate_file() {
    log_info "Validating — size: ${FILE_SIZE}, type: ${FILE_EXT}"

    # Must have a recognised extension
    case "${FILE_EXT}" in
        csv|json|xlsx) ;;
        *)
            log_error "Unsupported file type: .${FILE_EXT}"
            return 1
            ;;
    esac

    # Must not be empty
    local size_bytes; size_bytes="$(wc -c < "${SOURCE_FILE}" | tr -d ' ')"
    if [[ "${size_bytes}" -eq 0 ]]; then
        log_error "File is empty."
        return 1
    fi

    # CSV-specific: check it has at least a header + 1 data row
    if [[ "${FILE_EXT}" == "csv" ]]; then
        local line_count; line_count="$(wc -l < "${SOURCE_FILE}" | tr -d ' ')"
        if [[ "${line_count}" -lt 2 ]]; then
            log_error "CSV has fewer than 2 lines (header only or empty)."
            return 1
        fi
        log_info "CSV row count (including header): ${line_count}"
    fi

    # JSON-specific: check it's valid JSON
    if [[ "${FILE_EXT}" == "json" ]]; then
        if command -v python3 &>/dev/null; then
            if ! python3 -c "import json,sys; json.load(open('${SOURCE_FILE}'))" 2>/dev/null; then
                log_error "File is not valid JSON."
                return 1
            fi
            log_info "JSON structure validated."
        fi
    fi

    log_success "Validation passed."
    return 0
}

# ---------------------------------------------------------------------------
# Step 2: Move to staging
# ---------------------------------------------------------------------------
stage_file() {
    STAGED_FILE="${STAGING_DIR}/${TIMESTAMP}_${FILE_NAME}"
    cp "${SOURCE_FILE}" "${STAGED_FILE}"
    log_info "Staged to: ${STAGED_FILE}"
}

# ---------------------------------------------------------------------------
# Step 3: Detect file type and load
# ---------------------------------------------------------------------------
load_file() {
    local staged_file="$1"

    case "${FILE_NAME}" in
        prescriptions_*.csv)
            log_info "Prescription file validated and staged — data already loaded via generate_prescriptions.py."
            log_info "File contents available at: ${staged_file}"
            return 0
            ;;
        inventory_snapshot_*.xlsx)
            log_info "Inventory file validated and staged — data already loaded via generate_inventory.py."
            return 0
            ;;
        new_patients.csv)
            log_info "Patient file validated and staged — data already loaded via generate_patients.py."
            return 0
            ;;
        medication_catalog.json)
            log_info "Medication catalog — reference data, no load required."
            return 0
            ;;
        *)
            log_warn "No ETL mapping for file: ${FILE_NAME} — skipping load."
            return 0
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Step 4a: Archive to processed/ on success
# ---------------------------------------------------------------------------
archive_success() {
    local staged_file="$1"
    local dest_dir="${PROCESSED_DIR}/${DATE_STR}"
    mkdir -p "${dest_dir}"
    mv "${staged_file}" "${dest_dir}/${FILE_NAME}"
    log_success "Archived to: ${dest_dir}/${FILE_NAME}"
}

# ---------------------------------------------------------------------------
# Step 4b: Archive to archive/failed/ on failure
# ---------------------------------------------------------------------------
archive_failure() {
    local staged_file="$1"
    local reason="$2"
    local dest_dir="${ARCHIVE_DIR}/failed/${DATE_STR}"
    mkdir -p "${dest_dir}"

    # Move the file
    if [[ -f "${staged_file}" ]]; then
        mv "${staged_file}" "${dest_dir}/${FILE_NAME}"
    fi

    # Write a failure report alongside it
    cat > "${dest_dir}/${FILE_NAME}.failure_report.txt" <<EOF
File        : ${FILE_NAME}
Source      : ${SOURCE_FILE}
Failed at   : $(date '+%Y-%m-%d %H:%M:%S')
Reason      : ${reason}
Log file    : ${LOG_FILE}
EOF

    log_error "Moved to failed archive: ${dest_dir}/${FILE_NAME}"
    log_error "Failure report: ${dest_dir}/${FILE_NAME}.failure_report.txt"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local file_start; file_start=$(date +%s)
    log_info "Processing started — source: ${SOURCE_FILE}"

    # Step 1: Validate
    if ! validate_file; then
        archive_failure "" "Validation failed"
        exit 1
    fi

    # Step 2: Stage
    STAGED_FILE=""
    stage_file

    # Step 3: Load
    if ! load_file "${STAGED_FILE}"; then
        archive_failure "${STAGED_FILE}" "ETL load failed"
        exit 1
    fi

    # Step 4: Archive success
    archive_success "${STAGED_FILE}"

    local file_end; file_end=$(date +%s)
    local elapsed=$(( file_end - file_start ))
    log_success "Processing complete in ${elapsed}s."
}

main
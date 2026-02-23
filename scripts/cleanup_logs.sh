#!/usr/bin/env bash
# =============================================================================
# cleanup_logs.sh
# PharmaFlow Analytics — Log & Archive Maintenance
#
# Runs as the final step of run_pipeline.sh, and can be called standalone.
#
# What it does:
#   - Deletes log files older than 30 days
#   - Compresses processed/ archives older than 7 days into .tar.gz
#   - Removes compressed archives older than 90 days
#   - Prints a storage summary at the end
#
# Usage:
#   ./scripts/cleanup_logs.sh
#   ./scripts/cleanup_logs.sh --dry-run    # show what would be deleted, no action
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${PROJECT_ROOT}/logs"
PROCESSED_DIR="${PROJECT_ROOT}/processed"
ARCHIVE_DIR="${PROJECT_ROOT}/archive"

LOG_RETENTION_DAYS=30
COMPRESS_AFTER_DAYS=7
ARCHIVE_RETENTION_DAYS=90

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

DATE_STR="$(date +%Y-%m-%d)"
LOG_FILE="${LOG_DIR}/cleanup_${DATE_STR}.log"

mkdir -p "${LOG_DIR}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [${level}] $*" | tee -a "${LOG_FILE}"
}

log_info()    { log "INFO " "$@"; }
log_success() { log "OK   " "$@"; }
log_warn()    { log "WARN " "$@"; }

dry_run_prefix() {
    [[ "${DRY_RUN}" == "true" ]] && echo "[DRY RUN] " || echo ""
}

# ---------------------------------------------------------------------------
# Step 1: Delete old log files
# ---------------------------------------------------------------------------
cleanup_old_logs() {
    log_info "--- Cleaning logs older than ${LOG_RETENTION_DAYS} days ---"
    local count=0

    while IFS= read -r -d '' file; do
        log_info "$(dry_run_prefix)Deleting log: ${file}"
        [[ "${DRY_RUN}" == "false" ]] && rm -f "${file}"
        count=$(( count + 1 ))
    done < <(find "${LOG_DIR}" -maxdepth 1 -type f -name "*.log" \
                 -mtime "+${LOG_RETENTION_DAYS}" -print0 2>/dev/null)

    if [[ ${count} -eq 0 ]]; then
        log_info "No logs older than ${LOG_RETENTION_DAYS} days found."
    else
        log_success "$(dry_run_prefix)Removed ${count} old log file(s)."
    fi
}

# ---------------------------------------------------------------------------
# Step 2: Compress processed/ folders older than 7 days
# ---------------------------------------------------------------------------
compress_old_processed() {
    log_info "--- Compressing processed/ folders older than ${COMPRESS_AFTER_DAYS} days ---"
    local count=0

    while IFS= read -r -d '' dir; do
        local dir_name; dir_name="$(basename "${dir}")"
        local tar_path="${PROCESSED_DIR}/${dir_name}.tar.gz"

        if [[ -f "${tar_path}" ]]; then
            log_info "Already compressed: ${dir_name}.tar.gz — skipping."
            continue
        fi

        log_info "$(dry_run_prefix)Compressing: ${dir} → ${tar_path}"

        if [[ "${DRY_RUN}" == "false" ]]; then
            tar -czf "${tar_path}" -C "${PROCESSED_DIR}" "${dir_name}" && \
            rm -rf "${dir}"
        fi

        count=$(( count + 1 ))
    done < <(find "${PROCESSED_DIR}" -maxdepth 1 -mindepth 1 -type d \
                 -mtime "+${COMPRESS_AFTER_DAYS}" -print0 2>/dev/null)

    if [[ ${count} -eq 0 ]]; then
        log_info "No processed folders older than ${COMPRESS_AFTER_DAYS} days."
    else
        log_success "$(dry_run_prefix)Compressed ${count} folder(s)."
    fi
}

# ---------------------------------------------------------------------------
# Step 3: Delete old compressed archives
# ---------------------------------------------------------------------------
cleanup_old_archives() {
    log_info "--- Removing archives older than ${ARCHIVE_RETENTION_DAYS} days ---"
    local count=0

    while IFS= read -r -d '' file; do
        log_info "$(dry_run_prefix)Deleting archive: ${file}"
        [[ "${DRY_RUN}" == "false" ]] && rm -f "${file}"
        count=$(( count + 1 ))
    done < <(find "${PROCESSED_DIR}" -maxdepth 1 -type f -name "*.tar.gz" \
                 -mtime "+${ARCHIVE_RETENTION_DAYS}" -print0 2>/dev/null)

    # Also clean failed archives older than 90 days
    while IFS= read -r -d '' file; do
        log_info "$(dry_run_prefix)Deleting failed archive: ${file}"
        [[ "${DRY_RUN}" == "false" ]] && rm -f "${file}"
        count=$(( count + 1 ))
    done < <(find "${ARCHIVE_DIR}/failed" -type f \
                 -mtime "+${ARCHIVE_RETENTION_DAYS}" -print0 2>/dev/null)

    if [[ ${count} -eq 0 ]]; then
        log_info "No archives older than ${ARCHIVE_RETENTION_DAYS} days."
    else
        log_success "$(dry_run_prefix)Removed ${count} old archive(s)."
    fi
}

# ---------------------------------------------------------------------------
# Step 4: Storage summary
# ---------------------------------------------------------------------------
storage_summary() {
    log_info "--- Storage Summary ---"

    for dir in "${LOG_DIR}" "${PROCESSED_DIR}" "${ARCHIVE_DIR}"; do
        if [[ -d "${dir}" ]]; then
            local size; size="$(du -sh "${dir}" 2>/dev/null | cut -f1)"
            local file_count; file_count="$(find "${dir}" -type f | wc -l | tr -d ' ')"
            log_info "$(basename "${dir}")/  →  ${size}  (${file_count} files)"
        fi
    done

    # Log file counts by type
    local log_count; log_count="$(find "${LOG_DIR}" -name "*.log" | wc -l | tr -d ' ')"
    local gz_count;  gz_count="$(find "${PROCESSED_DIR}" -name "*.tar.gz" 2>/dev/null | wc -l | tr -d ' ')"
    log_info "Active log files: ${log_count} | Compressed archives: ${gz_count}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "=========================================="
    log_info "PharmaFlow Cleanup starting"
    [[ "${DRY_RUN}" == "true" ]] && log_warn "DRY RUN MODE — no files will be modified"
    log_info "=========================================="

    cleanup_old_logs
    compress_old_processed
    cleanup_old_archives
    storage_summary

    log_success "Cleanup complete."
}

main
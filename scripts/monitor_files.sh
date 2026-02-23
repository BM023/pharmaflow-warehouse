#!/usr/bin/env bash
# =============================================================================
# monitor_files.sh
# PharmaFlow Analytics — File Drop Monitor
#
# Watches raw_data/ for new files using polling (no fswatch/inotify required).
# When a new file is detected, calls process_file.sh on it.
#
# Usage:
#   ./scripts/monitor_files.sh              # watch indefinitely
#   ./scripts/monitor_files.sh --once       # scan once and exit (useful for cron)
#   ./scripts/monitor_files.sh --interval 60  # poll every 60 seconds (default: 30)
#
# To stop: Ctrl+C or kill the process
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RAW_DATA_DIR="${PROJECT_ROOT}/raw_data"
LOG_DIR="${PROJECT_ROOT}/logs"
SEEN_FILES_DB="${LOG_DIR}/.monitor_seen_files"   # tracks already-processed files

POLL_INTERVAL=30
RUN_ONCE=false
DATE_STR="$(date +%Y-%m-%d)"
LOG_FILE="${LOG_DIR}/monitor_${DATE_STR}.log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)          RUN_ONCE=true          ; shift ;;
        --interval)      POLL_INTERVAL="$2"     ; shift 2 ;;
        *)               shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}" "${RAW_DATA_DIR}"
touch "${SEEN_FILES_DB}"

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
log_error()   { log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Scan for new files
# ---------------------------------------------------------------------------
scan_and_process() {
    local new_file_count=0

    # Find all eligible files in raw_data/ (any depth)
    while IFS= read -r -d '' file; do
        local abs_path; abs_path="$(cd "$(dirname "${file}")" && pwd)/$(basename "${file}")"

        # Skip if already seen
        if grep -qF "${abs_path}" "${SEEN_FILES_DB}" 2>/dev/null; then
            continue
        fi

        # New file detected
        local file_name; file_name="$(basename "${abs_path}")"
        local file_size; file_size="$(wc -c < "${abs_path}" | tr -d ' ')"
        log_info "New file detected: ${file_name} (${file_size} bytes)"

        # Brief wait — ensures file is fully written before processing
        sleep 2

        # Process it
        if "${SCRIPT_DIR}/process_file.sh" "${abs_path}" 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "Processed: ${file_name}"
        else
            log_error "Failed to process: ${file_name}"
        fi

        # Mark as seen regardless of success (avoid retry loops)
        echo "${abs_path}" >> "${SEEN_FILES_DB}"
        new_file_count=$(( new_file_count + 1 ))

    done < <(find "${RAW_DATA_DIR}" -type f \
                \( -name "*.csv" -o -name "*.json" -o -name "*.xlsx" \) \
                -print0)

    if [[ ${new_file_count} -eq 0 && "${RUN_ONCE}" == "true" ]]; then
        log_info "No new files found."
    fi

    return ${new_file_count}
}

# ---------------------------------------------------------------------------
# Rotate seen-files DB daily (keep it from growing indefinitely)
# ---------------------------------------------------------------------------
rotate_seen_files() {
    local line_count; line_count="$(wc -l < "${SEEN_FILES_DB}" | tr -d ' ')"
    if [[ ${line_count} -gt 10000 ]]; then
        log_info "Rotating seen-files tracker (${line_count} entries)."
        # Keep last 5000 entries
        tail -5000 "${SEEN_FILES_DB}" > "${SEEN_FILES_DB}.tmp"
        mv "${SEEN_FILES_DB}.tmp" "${SEEN_FILES_DB}"
    fi
}

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
trap 'log_info "Monitor stopped (signal received)."; exit 0' SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log_info "=========================================="
log_info "PharmaFlow File Monitor starting"
log_info "Watching : ${RAW_DATA_DIR}"
log_info "Interval : ${POLL_INTERVAL}s"
log_info "Log file : ${LOG_FILE}"
log_info "=========================================="

if [[ "${RUN_ONCE}" == "true" ]]; then
    log_info "Running single scan (--once mode)..."
    scan_and_process
    log_info "Scan complete. Exiting."
    exit 0
fi

# Continuous polling loop
while true; do
    scan_and_process || true
    rotate_seen_files
    log_info "Sleeping ${POLL_INTERVAL}s before next scan..."
    sleep "${POLL_INTERVAL}"
done
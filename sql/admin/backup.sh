#!/usr/bin/env bash
# =============================================================================
# sql/admin/backup.sh
# PharmaFlow Analytics — Automated Database Backup
#
# Creates compressed pg_dump backups of the pharmaflow_warehouse database.
#
# Backup strategy:
#   - Daily full backup (schema + data) → backups/daily/
#   - Keeps last 7 daily backups
#   - Keeps last 4 weekly backups (Sunday snapshots)
#   - Keeps last 3 monthly backups (1st of month snapshots)
#
# Usage:
#   ./sql/admin/backup.sh                  # full backup
#   ./sql/admin/backup.sh --schema-only    # DDL only (no data)
#   ./sql/admin/backup.sh --verify         # verify last backup is readable
#   ./sql/admin/backup.sh --dry-run        # show what would happen
#
# Schedule: Add to crontab via setup_cron.sh or run manually.
# Recommended cron: 0 2 * * * (daily at 02:00, before pipeline at 06:00)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load env
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    set -a; source "${PROJECT_ROOT}/.env"; set +a
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5433}"
DB_NAME="${DB_NAME:-pharmaflow_warehouse}"
DB_USER="${DB_USER:-pharmaflow}"
PGPASSWORD="${DB_PASSWORD:-pharmaflow2024}"
export PGPASSWORD

BACKUP_DIR="${PROJECT_ROOT}/backups"
DAILY_DIR="${BACKUP_DIR}/daily"
WEEKLY_DIR="${BACKUP_DIR}/weekly"
MONTHLY_DIR="${BACKUP_DIR}/monthly"
LOG_DIR="${PROJECT_ROOT}/logs"

DAILY_RETENTION=7
WEEKLY_RETENTION=4
MONTHLY_RETENTION=3

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
DATE_STR="$(date +%Y-%m-%d)"
DAY_OF_WEEK="$(date +%u)"    # 7 = Sunday
DAY_OF_MONTH="$(date +%d)"   # 01 = first of month

LOG_FILE="${LOG_DIR}/backup_${DATE_STR}.log"

MODE="full"
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --schema-only) MODE="schema" ;;
        --verify)      MODE="verify" ;;
        --dry-run)     DRY_RUN=true  ;;
    esac
done

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

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
# Setup directories
# ---------------------------------------------------------------------------
setup_dirs() {
    for dir in "${DAILY_DIR}" "${WEEKLY_DIR}" "${MONTHLY_DIR}"; do
        mkdir -p "${dir}"
    done
}

# ---------------------------------------------------------------------------
# Create backup
# ---------------------------------------------------------------------------
create_backup() {
    local dest_dir="$1"
    local label="$2"
    local backup_file="${dest_dir}/pharmaflow_${label}_${TIMESTAMP}.sql.gz"

    log_info "Creating ${label} backup → ${backup_file}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would run: pg_dump | gzip > ${backup_file}"
        return 0
    fi

    local pg_dump_args=(
        -h "${DB_HOST}"
        -p "${DB_PORT}"
        -U "${DB_USER}"
        -d "${DB_NAME}"
        --no-password
        --verbose
        --format=plain
        --encoding=UTF8
    )

    if [[ "${MODE}" == "schema" ]]; then
        pg_dump_args+=(--schema-only)
    fi

    local start; start=$(date +%s)

    if pg_dump "${pg_dump_args[@]}" 2>>"${LOG_FILE}" | gzip > "${backup_file}"; then
        local end; end=$(date +%s)
        local elapsed=$(( end - start ))
        local size; size="$(du -sh "${backup_file}" | cut -f1)"
        log_success "Backup created: ${backup_file} (${size}, ${elapsed}s)"
        echo "${backup_file}"
    else
        log_error "pg_dump failed — check log: ${LOG_FILE}"
        rm -f "${backup_file}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Retention cleanup
# ---------------------------------------------------------------------------
cleanup_old_backups() {
    local dir="$1"
    local keep="$2"
    local label="$3"

    local count; count="$(find "${dir}" -name "*.sql.gz" | wc -l | tr -d ' ')"

    if [[ ${count} -le ${keep} ]]; then
        log_info "${label}: ${count} backups (retention: ${keep}) — nothing to remove."
        return 0
    fi

    local to_delete=$(( count - keep ))
    log_info "${label}: removing ${to_delete} old backup(s) (keeping ${keep})..."

    if [[ "${DRY_RUN}" == "false" ]]; then
        find "${dir}" -name "*.sql.gz" -printf '%T+ %p\n' | \
            sort | head -n "${to_delete}" | \
            awk '{print $2}' | \
            xargs rm -f
    else
        log_info "[DRY RUN] Would delete ${to_delete} file(s) from ${dir}"
    fi
}

# ---------------------------------------------------------------------------
# Verify backup is readable
# ---------------------------------------------------------------------------
verify_backup() {
    log_info "Verifying latest backup..."

    local latest; latest="$(find "${DAILY_DIR}" -name "*.sql.gz" -printf '%T+ %p\n' | \
                             sort -r | head -1 | awk '{print $2}')"

    if [[ -z "${latest}" ]]; then
        log_error "No backup found to verify."
        return 1
    fi

    log_info "Checking: ${latest}"

    if gunzip -t "${latest}" 2>>"${LOG_FILE}"; then
        local size; size="$(du -sh "${latest}" | cut -f1)"
        local line_count; line_count="$(zcat "${latest}" | wc -l | tr -d ' ')"
        log_success "Backup verified: ${latest}"
        log_info "  Size: ${size} | Lines: ${line_count:,}"
    else
        log_error "Backup verification FAILED: ${latest}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Backup summary
# ---------------------------------------------------------------------------
backup_summary() {
    log_info "--- Backup Storage Summary ---"

    for dir_label in "${DAILY_DIR}:daily" "${WEEKLY_DIR}:weekly" "${MONTHLY_DIR}:monthly"; do
        local dir="${dir_label%%:*}"
        local label="${dir_label##*:}"
        if [[ -d "${dir}" ]]; then
            local count; count="$(find "${dir}" -name "*.sql.gz" | wc -l | tr -d ' ')"
            local size; size="$(du -sh "${dir}" 2>/dev/null | cut -f1)"
            log_info "  ${label}/: ${count} backups, ${size} total"

            # Show most recent
            local latest; latest="$(find "${dir}" -name "*.sql.gz" -printf '%T+ %p\n' | \
                                    sort -r | head -1 | awk '{print $2}')"
            if [[ -n "${latest}" ]]; then
                local latest_size; latest_size="$(du -sh "${latest}" | cut -f1)"
                log_info "    Latest: $(basename "${latest}") (${latest_size})"
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "=========================================="
    log_info "PharmaFlow Database Backup"
    log_info "Mode     : ${MODE}"
    log_info "Dry run  : ${DRY_RUN}"
    log_info "Database : ${DB_NAME} @ ${DB_HOST}:${DB_PORT}"
    log_info "=========================================="

    if [[ "${MODE}" == "verify" ]]; then
        verify_backup
        return
    fi

    setup_dirs

    # Always create daily backup
    create_backup "${DAILY_DIR}" "daily"
    cleanup_old_backups "${DAILY_DIR}" "${DAILY_RETENTION}" "Daily backups"

    # Weekly backup on Sundays
    if [[ "${DAY_OF_WEEK}" == "7" ]]; then
        log_info "Sunday — creating weekly backup..."
        create_backup "${WEEKLY_DIR}" "weekly"
        cleanup_old_backups "${WEEKLY_DIR}" "${WEEKLY_RETENTION}" "Weekly backups"
    fi

    # Monthly backup on 1st of month
    if [[ "${DAY_OF_MONTH}" == "01" ]]; then
        log_info "1st of month — creating monthly backup..."
        create_backup "${MONTHLY_DIR}" "monthly"
        cleanup_old_backups "${MONTHLY_DIR}" "${MONTHLY_RETENTION}" "Monthly backups"
    fi

    backup_summary
    log_success "Backup complete."
}

main
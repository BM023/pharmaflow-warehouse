#!/usr/bin/env bash
# =============================================================================
# setup_cron.sh
# PharmaFlow Analytics — Cron Job Installer
#
# Installs a daily cron job that runs the full pipeline at 06:00.
# Safe to re-run — checks for existing entries before adding.
#
# Usage:
#   ./scripts/setup_cron.sh              # install cron job
#   ./scripts/setup_cron.sh --remove     # remove cron job
#   ./scripts/setup_cron.sh --status     # show current cron entries
#   ./scripts/setup_cron.sh --dry-run    # show what would be installed
#
# Cron schedule: 0 6 * * *  (daily at 06:00 AM local time)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${PROJECT_ROOT}/logs"
CRON_LOG="${LOG_DIR}/cron_pipeline.log"

# The unique marker lets us find/remove our entry reliably
CRON_MARKER="# pharmaflow-pipeline"

# Cron schedule: daily at 06:00
CRON_SCHEDULE="0 6 * * *"

# Full cron entry
CRON_ENTRY="${CRON_SCHEDULE} cd ${PROJECT_ROOT} && ${SCRIPT_DIR}/run_pipeline.sh >> ${CRON_LOG} 2>&1 ${CRON_MARKER}"

MODE="install"
[[ "${1:-}" == "--remove"  ]] && MODE="remove"
[[ "${1:-}" == "--status"  ]] && MODE="status"
[[ "${1:-}" == "--dry-run" ]] && MODE="dry-run"

mkdir -p "${LOG_DIR}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

current_crontab() {
    crontab -l 2>/dev/null || echo ""
}

entry_exists() {
    current_crontab | grep -qF "${CRON_MARKER}"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
install_cron() {
    if entry_exists; then
        log "Cron job already installed. Use --remove to uninstall first."
        log "Current entry:"
        current_crontab | grep -F "${CRON_MARKER}"
        return 0
    fi

    log "Installing cron job..."
    log "Entry: ${CRON_ENTRY}"

    # Append to existing crontab
    ( current_crontab; echo "${CRON_ENTRY}" ) | crontab -

    log "✓ Cron job installed successfully."
    log ""
    log "Schedule  : Daily at 06:00 AM"
    log "Command   : ${SCRIPT_DIR}/run_pipeline.sh"
    log "Cron log  : ${CRON_LOG}"
    log ""
    log "To verify: crontab -l"
    log "To remove: ./scripts/setup_cron.sh --remove"
}

remove_cron() {
    if ! entry_exists; then
        log "No PharmaFlow cron entry found — nothing to remove."
        return 0
    fi

    log "Removing cron job..."
    current_crontab | grep -vF "${CRON_MARKER}" | crontab -
    log "✓ Cron job removed."
}

show_status() {
    log "Current crontab:"
    echo "---"
    current_crontab | grep -F "${CRON_MARKER}" || echo "(no PharmaFlow entry found)"
    echo "---"

    log ""
    log "All cron jobs for current user:"
    echo "---"
    current_crontab || echo "(crontab is empty)"
    echo "---"

    if [[ -f "${CRON_LOG}" ]]; then
        log ""
        log "Last 20 lines of cron log (${CRON_LOG}):"
        echo "---"
        tail -20 "${CRON_LOG}"
        echo "---"
    else
        log "Cron log not yet created: ${CRON_LOG}"
    fi
}

dry_run() {
    log "[DRY RUN] Would install the following cron entry:"
    echo ""
    echo "  ${CRON_ENTRY}"
    echo ""
    log "[DRY RUN] Cron log would write to: ${CRON_LOG}"
    log "[DRY RUN] No changes made."
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight() {
    # Ensure run_pipeline.sh exists and is executable
    if [[ ! -f "${SCRIPT_DIR}/run_pipeline.sh" ]]; then
        echo "[ERROR] run_pipeline.sh not found at ${SCRIPT_DIR}/run_pipeline.sh"
        exit 1
    fi

    # Make all scripts executable
    chmod +x "${SCRIPT_DIR}"/*.sh
    log "All scripts marked executable."

    # Ensure crontab command is available
    if ! command -v crontab &>/dev/null; then
        echo "[ERROR] crontab command not available on this system."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "============================================"
echo " PharmaFlow Analytics — Cron Setup"
echo " Mode: ${MODE}"
echo "============================================"

case "${MODE}" in
    install)
        preflight
        install_cron
        ;;
    remove)
        remove_cron
        ;;
    status)
        show_status
        ;;
    dry-run)
        dry_run
        ;;
esac
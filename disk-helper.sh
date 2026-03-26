#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

FORCE_MODE="false"
DRY_RUN="false"
DOWNLOAD_AGE_DAYS=30

show_help() {
    cat <<'HELP'
Usage: disk-helper.sh [OPTIONS]

Options:
  --force       Auto-clean without prompting (large files/duplicates still interactive)
  --dry-run     Report what would be cleaned without deleting
  --days=N      Age threshold for old downloads (default: 30)
  -h, --help    Show help message
HELP
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --force)
                FORCE_MODE="true"
                ;;
            --dry-run)
                DRY_RUN="true"
                ;;
            --days=*)
                DOWNLOAD_AGE_DAYS="${1#*=}"
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help >&2
                exit 1
                ;;
        esac
        shift
    done
}

LOG_FILE="/tmp/disk-helper-$(date +%Y-%m-%d).log"
TOTAL_FREED=0

format_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

dir_size() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}'
    else
        echo 0
    fi
}

tool_installed() {
    command -v "$1" &>/dev/null
}

log_action() {
    local action="$1"
    local size="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $action — freed $size" >> "$LOG_FILE"
}

confirm() {
    local prompt="$1"
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 0
    fi
    printf "%s [y/N] " "$prompt"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

show_disk_usage() {
    echo ""
    echo "=== Disk Usage ==="
    df -h / | tail -1 | awk '{printf "  Filesystem: %s  Total: %s  Used: %s  Free: %s  (%s used)\n", $1, $2, $3, $4, $5}'
    echo ""
}

show_summary() {
    echo ""
    echo "=== Summary ==="
    echo "  Total space freed: $(format_size $TOTAL_FREED)"
    echo "  Log saved to: $LOG_FILE"
    echo ""
}

cleanup_trap() {
    echo ""
    echo "Interrupted! Showing partial results..."
    show_summary
    exit 130
}

main() {
    parse_args "$@"
    trap cleanup_trap INT
    echo "disk-helper v${VERSION}"
    show_disk_usage
    # cleanup categories will go here
    show_summary
}

# Guard: only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

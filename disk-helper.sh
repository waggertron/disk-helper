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

# Default paths (can be overridden in tests)
USER_CACHE_DIR="${USER_CACHE_DIR:-$HOME/Library/Caches}"

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

clean_user_caches() {
    local size_before
    size_before="$(dir_size "$USER_CACHE_DIR")"

    if [[ "$size_before" -eq 0 ]]; then
        echo "  User caches: nothing to clean"
        return
    fi

    echo "  User caches: $(format_size "$size_before")"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would clean user caches"
        return
    fi

    if confirm "  Clean user caches?"; then
        rm -rf "${USER_CACHE_DIR:?}"/*
        local size_after
        size_after="$(dir_size "$USER_CACHE_DIR")"
        local freed=$(( size_before - size_after ))
        TOTAL_FREED=$(( TOTAL_FREED + freed ))
        log_action "Cleaned user caches" "$(format_size $freed)"
        echo "  Freed: $(format_size $freed)"
    else
        echo "  Skipped user caches"
    fi
}

clean_system_caches() {
    echo ""
    echo "=== System Caches ==="
    clean_user_caches
    # System-level caches (/Library/Caches) require sudo — only attempt if not dry-run
    if [[ "$DRY_RUN" != "true" ]] && [[ -d "/Library/Caches" ]]; then
        local size
        size="$(sudo du -sk /Library/Caches 2>/dev/null | awk '{print $1 * 1024}' || echo 0)"
        if [[ "$size" -gt 0 ]]; then
            echo "  System caches: $(format_size "$size")"
            if confirm "  Clean system caches? (requires sudo)"; then
                sudo rm -rf /Library/Caches/* 2>/dev/null || true
                log_action "Cleaned system caches" "$(format_size "$size")"
                TOTAL_FREED=$(( TOTAL_FREED + size ))
                echo "  Freed: $(format_size "$size")"
            else
                echo "  Skipped system caches"
            fi
        fi
    fi
}

clean_homebrew() {
    echo ""
    echo "=== Homebrew ==="
    if ! tool_installed brew; then
        echo "  Homebrew: not installed, skipping"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would run: brew cleanup --prune=all"
        brew cleanup --dry-run 2>/dev/null | tail -5 || true
        return
    fi

    if confirm "  Run brew cleanup --prune=all?"; then
        local output
        output="$(brew cleanup --prune=all 2>&1)" || true
        log_action "Ran brew cleanup" "see log"
        echo "  Homebrew cleanup complete"
        echo "$output" | tail -3
    else
        echo "  Skipped Homebrew cleanup"
    fi
}

clean_npm() {
    echo ""
    echo "=== npm ==="
    if ! tool_installed npm; then
        echo "  npm: not installed, skipping"
        return
    fi

    local cache_dir
    cache_dir="$(npm config get cache 2>/dev/null || echo "")"
    local size=0
    if [[ -n "$cache_dir" ]] && [[ -d "$cache_dir" ]]; then
        size="$(dir_size "$cache_dir")"
    fi

    echo "  npm cache: $(format_size $size)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would run: npm cache clean --force"
        return
    fi

    if [[ "$size" -gt 0 ]] && confirm "  Clean npm cache?"; then
        npm cache clean --force 2>/dev/null || true
        TOTAL_FREED=$(( TOTAL_FREED + size ))
        log_action "Cleaned npm cache" "$(format_size $size)"
        echo "  Freed: $(format_size $size)"
    else
        echo "  Skipped npm cache"
    fi
}

clean_pip() {
    echo ""
    echo "=== pip ==="
    if ! tool_installed pip3 && ! tool_installed pip; then
        echo "  pip: not installed, skipping"
        return
    fi

    local pip_cmd="pip3"
    tool_installed pip3 || pip_cmd="pip"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would run: $pip_cmd cache purge"
        return
    fi

    if confirm "  Purge pip cache?"; then
        $pip_cmd cache purge 2>/dev/null || true
        log_action "Purged pip cache" "see log"
        echo "  pip cache purged"
    else
        echo "  Skipped pip cache"
    fi
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

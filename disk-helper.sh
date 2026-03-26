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
LARGE_FILE_SCAN_DIR="${LARGE_FILE_SCAN_DIR:-$HOME}"
LARGE_FILE_MIN_SIZE_KB="${LARGE_FILE_MIN_SIZE_KB:-524288}"  # 500MB in KB
USER_CACHE_DIR="${USER_CACHE_DIR:-$HOME/Library/Caches}"
XCODE_DERIVED_DATA="${XCODE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
XCODE_ARCHIVES="${XCODE_ARCHIVES:-$HOME/Library/Developer/Xcode/Archives}"
XCODE_DEVICE_SUPPORT="${XCODE_DEVICE_SUPPORT:-$HOME/Library/Developer/Xcode/iOS DeviceSupport}"

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
        local result
        result="$(du -sk "$path" 2>/dev/null | tail -1 | awk '{print $1 * 1024}')" || true
        echo "${result:-0}"
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

clean_xcode() {
    echo ""
    echo "=== Xcode ==="
    if ! tool_installed xcodebuild; then
        echo "  Xcode: not installed, skipping"
        return
    fi

    local total_freed=0

    # Derived Data
    local dd_size
    dd_size="$(dir_size "$XCODE_DERIVED_DATA")"
    if [[ "$dd_size" -gt 0 ]]; then
        echo "  DerivedData: $(format_size $dd_size)"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would clean DerivedData"
        elif confirm "  Clean DerivedData?"; then
            rm -rf "${XCODE_DERIVED_DATA:?}"/*
            total_freed=$(( total_freed + dd_size ))
            echo "  Freed: $(format_size $dd_size)"
        fi
    fi

    # Archives
    local arch_size
    arch_size="$(dir_size "$XCODE_ARCHIVES")"
    if [[ "$arch_size" -gt 0 ]]; then
        echo "  Archives: $(format_size $arch_size)"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would clean Archives"
        elif confirm "  Clean Archives?"; then
            rm -rf "${XCODE_ARCHIVES:?}"/*
            total_freed=$(( total_freed + arch_size ))
            echo "  Freed: $(format_size $arch_size)"
        fi
    fi

    # Device Support
    local ds_size
    ds_size="$(dir_size "$XCODE_DEVICE_SUPPORT")"
    if [[ "$ds_size" -gt 0 ]]; then
        echo "  Device Support: $(format_size $ds_size)"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] Would clean Device Support"
        elif confirm "  Clean Device Support files?"; then
            rm -rf "${XCODE_DEVICE_SUPPORT:?}"/*
            total_freed=$(( total_freed + ds_size ))
            echo "  Freed: $(format_size $ds_size)"
        fi
    fi

    if [[ "$total_freed" -gt 0 ]]; then
        TOTAL_FREED=$(( TOTAL_FREED + total_freed ))
        log_action "Cleaned Xcode" "$(format_size $total_freed)"
    fi
}

clean_docker() {
    echo ""
    echo "=== Docker ==="
    if ! tool_installed docker; then
        echo "  Docker: not installed, skipping"
        return
    fi

    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        echo "  Docker: daemon not running, skipping"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would run: docker system prune -f"
        docker system df 2>/dev/null || true
        return
    fi

    if confirm "  Run docker system prune (removes dangling images, stopped containers, unused networks)?"; then
        local output
        output="$(docker system prune -f 2>&1)" || true
        echo "$output" | tail -3
        log_action "Ran docker system prune" "see log"
        echo "  Docker cleanup complete"
    else
        echo "  Skipped Docker cleanup"
    fi
}

find_large_files() {
    echo ""
    echo "=== Large Files (>$(format_size $(( LARGE_FILE_MIN_SIZE_KB * 1024 )))) ==="

    # Scan common directories (not entire $HOME — too slow)
    local default_home="$HOME"
    local scan_dirs
    if [[ "$LARGE_FILE_SCAN_DIR" != "$default_home" ]]; then
        # Custom scan dir (e.g., tests) — scan it directly
        scan_dirs=("$LARGE_FILE_SCAN_DIR")
    else
        scan_dirs=("$LARGE_FILE_SCAN_DIR/Downloads" "$LARGE_FILE_SCAN_DIR/Documents" "$LARGE_FILE_SCAN_DIR/Desktop" "$LARGE_FILE_SCAN_DIR/Movies" "$LARGE_FILE_SCAN_DIR/Music" "$LARGE_FILE_SCAN_DIR/Pictures")
    fi
    local files=""
    for scan_dir in "${scan_dirs[@]}"; do
        [[ -d "$scan_dir" ]] || continue
        local found
        found="$(find "$scan_dir" -maxdepth 5 -type f -size +"${LARGE_FILE_MIN_SIZE_KB}k" 2>/dev/null | head -20 || true)"
        [[ -n "$found" ]] && files="${files}${files:+$'\n'}${found}"
    done

    if [[ -z "$files" ]]; then
        echo "  No files found above threshold"
        return
    fi

    echo "  Found large files:"
    while IFS= read -r file; do
        local size
        size="$(stat -f%z "$file" 2>/dev/null || echo 0)"
        printf "  %-60s %s\n" "$file" "$(format_size "$size")"
    done <<< "$files"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Review only — no deletions"
        return
    fi

    echo ""
    echo "  NOTE: Large files require individual confirmation (even in --force mode)."
    while IFS= read -r file; do
        local size
        size="$(stat -f%z "$file" 2>/dev/null || echo 0)"
        local old_force="$FORCE_MODE"
        FORCE_MODE="false"
        if confirm "  Delete $file ($(format_size "$size"))?"; then
            rm -f "$file"
            TOTAL_FREED=$(( TOTAL_FREED + size ))
            log_action "Deleted large file: $file" "$(format_size "$size")"
            echo "  Deleted."
        fi
        FORCE_MODE="$old_force"
    done <<< "$files"
}

DOWNLOADS_DIR="${DOWNLOADS_DIR:-$HOME/Downloads}"

clean_old_downloads() {
    echo ""
    echo "=== Old Downloads (>${DOWNLOAD_AGE_DAYS} days) ==="

    if [[ ! -d "$DOWNLOADS_DIR" ]]; then
        echo "  Downloads directory not found, skipping"
        return
    fi

    local files
    files="$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -mtime +"${DOWNLOAD_AGE_DAYS}" 2>/dev/null || true)"

    if [[ -z "$files" ]]; then
        echo "  No old files found in Downloads"
        return
    fi

    local total_size=0
    local file_count=0
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        local size
        size="$(stat -f%z "$file" 2>/dev/null || echo 0)"
        total_size=$(( total_size + size ))
        file_count=$(( file_count + 1 ))
    done <<< "$files"

    echo "  Found $file_count files older than ${DOWNLOAD_AGE_DAYS} days ($(format_size $total_size) total)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would remove $file_count files"
        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            echo "    $(basename "$file")"
        done <<< "$files"
        return
    fi

    if confirm "  Remove $file_count old files from Downloads?"; then
        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            rm -f "$file"
        done <<< "$files"
        TOTAL_FREED=$(( TOTAL_FREED + total_size ))
        log_action "Cleaned old downloads" "$(format_size $total_size)"
        echo "  Freed: $(format_size $total_size)"
    else
        echo "  Skipped old downloads cleanup"
    fi
}

TRASH_DIR="${TRASH_DIR:-$HOME/.Trash}"

clean_trash() {
    echo ""
    echo "=== Trash ==="

    local size
    size="$(dir_size "$TRASH_DIR")"

    if [[ "$size" -eq 0 ]]; then
        echo "  Trash is empty"
        return
    fi

    echo "  Trash: $(format_size $size)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would empty Trash"
        return
    fi

    if confirm "  Empty Trash?"; then
        rm -rf "${TRASH_DIR:?}"/* 2>/dev/null || true
        TOTAL_FREED=$(( TOTAL_FREED + size ))
        log_action "Emptied Trash" "$(format_size $size)"
        echo "  Freed: $(format_size $size)"
    else
        echo "  Skipped Trash"
    fi
}

DUPLICATE_SCAN_DIRS="${DUPLICATE_SCAN_DIRS:-$HOME/Downloads:$HOME/Documents:$HOME/Desktop}"

find_duplicates() {
    echo ""
    echo "=== Duplicate Files ==="

    # Split scan dirs by colon
    local IFS=':'
    local dirs=()
    read -ra dirs <<< "$DUPLICATE_SCAN_DIRS"
    unset IFS

    local tmp_sizes
    tmp_sizes="$(mktemp)"
    local tmp_hashes
    tmp_hashes="$(mktemp)"
    trap "rm -f '$tmp_sizes' '$tmp_hashes'" RETURN

    # Pass 1: collect file sizes
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r file; do
            local size
            size="$(stat -f%z "$file" 2>/dev/null || echo 0)"
            [[ "$size" -gt 0 ]] || continue
            echo "$size $file" >> "$tmp_sizes"
        done < <(find "$dir" -type f -maxdepth 3 2>/dev/null)
    done

    if [[ ! -s "$tmp_sizes" ]]; then
        echo "  No duplicates found"
        return
    fi

    # Find sizes that appear more than once
    local dup_sizes
    dup_sizes="$(awk '{print $1}' "$tmp_sizes" | sort | uniq -d)"

    if [[ -z "$dup_sizes" ]]; then
        echo "  No duplicates found"
        return
    fi

    # Pass 2: for same-size files, compute checksums
    while IFS= read -r size; do
        [[ -n "$size" ]] || continue
        while IFS= read -r line; do
            local file="${line#* }"
            local hash
            hash="$(md5 -q "$file" 2>/dev/null || true)"
            [[ -n "$hash" ]] || continue
            echo "$hash $size $file" >> "$tmp_hashes"
        done < <(grep "^${size} " "$tmp_sizes")
    done <<< "$dup_sizes"

    # Find duplicate hashes
    local found_dupes=false
    local dup_hashes
    dup_hashes="$(awk '{print $1}' "$tmp_hashes" | sort | uniq -d)"

    if [[ -z "$dup_hashes" ]]; then
        echo "  No duplicates found"
        return
    fi

    while IFS= read -r hash; do
        [[ -n "$hash" ]] || continue
        found_dupes=true
        local size
        size="$(grep "^${hash} " "$tmp_hashes" | head -1 | awk '{print $2}')"
        echo "  Duplicate group ($(format_size "$size") each):"
        while IFS= read -r line; do
            local f="${line#* }"
            f="${f#* }"
            echo "    $f"
        done < <(grep "^${hash} " "$tmp_hashes")
        echo ""
    done <<< "$dup_hashes"

    if [[ "$found_dupes" == "false" ]]; then
        echo "  No duplicates found"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Review only — no deletions"
        return
    fi

    echo "  NOTE: Duplicate removal requires individual confirmation (even in --force mode)."
    echo "  Re-run with specific file paths to delete manually if desired."
}

main() {
    parse_args "$@"
    trap cleanup_trap INT

    echo "disk-helper v${VERSION}"
    [[ "$DRY_RUN" == "true" ]] && echo "[DRY RUN MODE]"

    show_disk_usage

    clean_system_caches
    clean_homebrew
    clean_npm
    clean_pip
    clean_xcode
    clean_docker
    find_large_files
    find_duplicates
    clean_old_downloads
    clean_trash

    show_summary
}

# Guard: only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

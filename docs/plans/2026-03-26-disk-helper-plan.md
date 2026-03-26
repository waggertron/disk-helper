# Disk Helper Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a comprehensive macOS disk cleanup bash script with interactive/force/dry-run modes.

**Architecture:** Single bash script (`disk-helper.sh`) with functions per cleanup category. Each function follows detect → measure → confirm → clean → report flow. A test suite using bats validates argument parsing, helper functions, and category logic using temp directories and mocked commands.

**Tech Stack:** Bash, bats-core (testing), macOS CLI tools (du, find, md5, osascript)

---

### Task 0: Project Setup

**Files:**
- Create: `disk-helper.sh`
- Create: `tests/test_helper.bash`

**Step 1: Install bats-core**

Run: `brew install bats-core`

**Step 2: Create executable script skeleton**

Create `disk-helper.sh` with shebang, `set -euo pipefail`, and a `main` function that just prints "disk-helper v0.1.0".

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

main() {
    echo "disk-helper v${VERSION}"
}

main "$@"
```

**Step 3: Create test helper**

Create `tests/test_helper.bash` that sets up a temp directory for each test and tears it down after.

```bash
setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}
```

**Step 4: Make script executable and verify**

Run: `chmod +x disk-helper.sh && ./disk-helper.sh`
Expected: `disk-helper v0.1.0`

**Step 5: Commit**

```bash
git add disk-helper.sh tests/test_helper.bash docs/
git commit -m "chore: project setup with script skeleton and test helper"
```

---

### Task 1: Argument Parsing & Help

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/args.bats`

**Step 1: Write the failing tests**

Create `tests/args.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "shows help with -h flag" {
    run ./disk-helper.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--force"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--days="* ]]
}

@test "shows help with --help flag" {
    run ./disk-helper.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "sets force mode with --force" {
    # We test by sourcing and checking the variable
    source ./disk-helper.sh --force </dev/null
    [ "$FORCE_MODE" = "true" ]
}

@test "sets dry run mode with --dry-run" {
    source ./disk-helper.sh --dry-run </dev/null
    [ "$DRY_RUN" = "true" ]
}

@test "sets custom days with --days=N" {
    source ./disk-helper.sh --days=60 </dev/null
    [ "$DOWNLOAD_AGE_DAYS" = "60" ]
}

@test "defaults days to 30" {
    source ./disk-helper.sh --dry-run </dev/null
    [ "$DOWNLOAD_AGE_DAYS" = "30" ]
}

@test "rejects unknown flags" {
    run ./disk-helper.sh --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/args.bats`
Expected: All FAIL

**Step 3: Implement argument parsing**

Update `disk-helper.sh` with `parse_args` function, `show_help` function, and global variables (`FORCE_MODE`, `DRY_RUN`, `DOWNLOAD_AGE_DAYS`). The `main` function calls `parse_args "$@"`. If sourced (for testing), skip calling `main` — use a guard:

```bash
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

main() {
    parse_args "$@"
    echo "disk-helper v${VERSION}"
}

# Guard: only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

Update the source-based tests to call `parse_args` directly instead of sourcing the whole script:

```bash
@test "sets force mode with --force" {
    source ./disk-helper.sh
    parse_args --force
    [ "$FORCE_MODE" = "true" ]
}
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/args.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/args.bats
git commit -m "feat: add argument parsing with --force, --dry-run, --days=N, --help"
```

---

### Task 2: Utility Functions (logging, size formatting, confirmation prompt)

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/utils.bats`

**Step 1: Write the failing tests**

Create `tests/utils.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
}

@test "format_size converts bytes to human readable" {
    result="$(format_size 1073741824)"
    [[ "$result" == *"1.0"*"G"* ]]
}

@test "format_size handles megabytes" {
    result="$(format_size 5242880)"
    [[ "$result" == *"5.0"*"M"* ]]
}

@test "format_size handles kilobytes" {
    result="$(format_size 2048)"
    [[ "$result" == *"2.0"*"K"* ]]
}

@test "format_size handles bytes" {
    result="$(format_size 500)"
    echo "$result"
    [[ "$result" == *"500"*"B"* ]]
}

@test "dir_size returns size in bytes for a directory" {
    mkdir -p "$TEST_TEMP_DIR/testdir"
    dd if=/dev/zero of="$TEST_TEMP_DIR/testdir/file1" bs=1024 count=100 2>/dev/null
    result="$(dir_size "$TEST_TEMP_DIR/testdir")"
    # Should be roughly 102400 bytes (100KB)
    [ "$result" -gt 90000 ]
}

@test "dir_size returns 0 for nonexistent directory" {
    result="$(dir_size "/nonexistent/path")"
    [ "$result" -eq 0 ]
}

@test "tool_installed returns 0 for existing command" {
    run tool_installed "ls"
    [ "$status" -eq 0 ]
}

@test "tool_installed returns 1 for missing command" {
    run tool_installed "definitely_not_a_real_command_xyz"
    [ "$status" -ne 0 ]
}

@test "log_action writes to log file" {
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
    log_action "Cleaned system caches" "50M"
    grep -q "Cleaned system caches" "$LOG_FILE"
    grep -q "50M" "$LOG_FILE"
}

@test "confirm returns 0 in force mode" {
    FORCE_MODE="true"
    run confirm "Delete stuff?"
    [ "$status" -eq 0 ]
}

@test "confirm returns 0 when user types y" {
    FORCE_MODE="false"
    run bash -c 'source ./disk-helper.sh; FORCE_MODE=false; echo y | confirm "Delete?"'
    [ "$status" -eq 0 ]
}

@test "confirm returns 1 when user types n" {
    FORCE_MODE="false"
    run bash -c 'source ./disk-helper.sh; FORCE_MODE=false; echo n | confirm "Delete?"'
    [ "$status" -ne 0 ]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/utils.bats`
Expected: All FAIL

**Step 3: Implement utility functions**

Add to `disk-helper.sh`:

```bash
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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/utils.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/utils.bats
git commit -m "feat: add utility functions — format_size, dir_size, tool_installed, log_action, confirm"
```

---

### Task 3: Disk Usage Report & Trap Handler

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/report.bats`

**Step 1: Write the failing tests**

Create `tests/report.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
}

@test "show_disk_usage outputs disk info" {
    run show_disk_usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk Usage"* ]]
    [[ "$output" == *"/"* ]]
}

@test "show_summary outputs total freed" {
    TOTAL_FREED=1073741824
    run show_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total space freed"* ]]
    [[ "$output" == *"1.0 GB"* ]]
}

@test "show_summary handles zero freed" {
    TOTAL_FREED=0
    run show_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total space freed"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/report.bats`
Expected: All FAIL

**Step 3: Implement report functions**

Add to `disk-helper.sh`:

```bash
show_disk_usage() {
    echo ""
    echo "=== Disk Usage ==="
    df -h / | tail -1 | awk '{printf "  Total: %s  Used: %s  Free: %s  (%s used)\n", $2, $3, $4, $5}'
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
```

Update `main` to call `show_disk_usage` at the start, set the trap, and call `show_summary` at the end:

```bash
main() {
    parse_args "$@"
    trap cleanup_trap INT
    echo "disk-helper v${VERSION}"
    show_disk_usage
    # cleanup categories will go here
    show_summary
}
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/report.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/report.bats
git commit -m "feat: add disk usage report, summary, and Ctrl+C trap handler"
```

---

### Task 4: System Caches Cleanup

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/clean_caches.bats`

**Step 1: Write the failing tests**

Create `tests/clean_caches.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    # Override cache paths for testing
    export USER_CACHE_DIR="$TEST_TEMP_DIR/user_caches"
    mkdir -p "$USER_CACHE_DIR/com.apple.something"
    dd if=/dev/zero of="$USER_CACHE_DIR/com.apple.something/cache.db" bs=1024 count=50 2>/dev/null
}

@test "clean_user_caches removes cache files" {
    FORCE_MODE="true"
    DRY_RUN="false"
    clean_user_caches
    [ ! -f "$USER_CACHE_DIR/com.apple.something/cache.db" ]
}

@test "clean_user_caches dry run does not delete" {
    DRY_RUN="true"
    FORCE_MODE="false"
    clean_user_caches
    [ -f "$USER_CACHE_DIR/com.apple.something/cache.db" ]
}

@test "clean_user_caches reports size" {
    FORCE_MODE="true"
    DRY_RUN="false"
    run clean_user_caches
    [[ "$output" == *"User caches"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/clean_caches.bats`
Expected: All FAIL

**Step 3: Implement system caches cleanup**

Add to `disk-helper.sh`:

```bash
# Default paths (can be overridden in tests)
USER_CACHE_DIR="${USER_CACHE_DIR:-$HOME/Library/Caches}"

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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/clean_caches.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/clean_caches.bats
git commit -m "feat: add system and user cache cleanup"
```

---

### Task 5: Homebrew, npm, pip Cleanup

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/clean_package_managers.bats`

**Step 1: Write the failing tests**

Create `tests/clean_package_managers.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    DRY_RUN="false"
    FORCE_MODE="true"
}

@test "clean_homebrew skips if brew not installed" {
    # Override tool_installed to return false
    tool_installed() { return 1; }
    run clean_homebrew
    [[ "$output" == *"not installed"* ]]
}

@test "clean_homebrew runs brew cleanup in dry-run" {
    DRY_RUN="true"
    # Only test if brew is actually installed
    if ! command -v brew &>/dev/null; then
        skip "brew not installed"
    fi
    run clean_homebrew
    [[ "$output" == *"Homebrew"* ]]
    [[ "$output" == *"dry-run"* ]]
}

@test "clean_npm skips if npm not installed" {
    tool_installed() { return 1; }
    run clean_npm
    [[ "$output" == *"not installed"* ]]
}

@test "clean_pip skips if pip not installed" {
    tool_installed() { return 1; }
    run clean_pip
    [[ "$output" == *"not installed"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/clean_package_managers.bats`
Expected: All FAIL

**Step 3: Implement package manager cleanup**

Add to `disk-helper.sh`:

```bash
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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/clean_package_managers.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/clean_package_managers.bats
git commit -m "feat: add homebrew, npm, and pip cache cleanup"
```

---

### Task 6: Xcode Cleanup

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/clean_xcode.bats`

**Step 1: Write the failing tests**

Create `tests/clean_xcode.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
    # Override Xcode paths for testing
    export XCODE_DERIVED_DATA="$TEST_TEMP_DIR/DerivedData"
    export XCODE_ARCHIVES="$TEST_TEMP_DIR/Archives"
    export XCODE_DEVICE_SUPPORT="$TEST_TEMP_DIR/DeviceSupport"
}

@test "clean_xcode skips if xcodebuild not installed" {
    tool_installed() { return 1; }
    run clean_xcode
    [[ "$output" == *"not installed"* ]]
}

@test "clean_xcode cleans derived data" {
    mkdir -p "$XCODE_DERIVED_DATA/SomeProject"
    dd if=/dev/zero of="$XCODE_DERIVED_DATA/SomeProject/build.o" bs=1024 count=100 2>/dev/null
    clean_xcode
    [ ! -d "$XCODE_DERIVED_DATA/SomeProject" ]
}

@test "clean_xcode dry run does not delete" {
    DRY_RUN="true"
    mkdir -p "$XCODE_DERIVED_DATA/SomeProject"
    dd if=/dev/zero of="$XCODE_DERIVED_DATA/SomeProject/build.o" bs=1024 count=100 2>/dev/null
    clean_xcode
    [ -d "$XCODE_DERIVED_DATA/SomeProject" ]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/clean_xcode.bats`
Expected: All FAIL

**Step 3: Implement Xcode cleanup**

Add to `disk-helper.sh`:

```bash
XCODE_DERIVED_DATA="${XCODE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
XCODE_ARCHIVES="${XCODE_ARCHIVES:-$HOME/Library/Developer/Xcode/Archives}"
XCODE_DEVICE_SUPPORT="${XCODE_DEVICE_SUPPORT:-$HOME/Library/Developer/Xcode/iOS DeviceSupport}"

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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/clean_xcode.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/clean_xcode.bats
git commit -m "feat: add Xcode DerivedData, Archives, and DeviceSupport cleanup"
```

---

### Task 7: Docker Cleanup

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/clean_docker.bats`

**Step 1: Write the failing tests**

Create `tests/clean_docker.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
}

@test "clean_docker skips if docker not installed" {
    tool_installed() { return 1; }
    run clean_docker
    [[ "$output" == *"not installed"* ]]
}

@test "clean_docker dry run does not prune" {
    DRY_RUN="true"
    # Mock docker as installed
    tool_installed() { [[ "$1" == "docker" ]] && return 0 || command -v "$1" &>/dev/null; }
    run clean_docker
    [[ "$output" == *"dry-run"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/clean_docker.bats`
Expected: All FAIL

**Step 3: Implement Docker cleanup**

Add to `disk-helper.sh`:

```bash
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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/clean_docker.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/clean_docker.bats
git commit -m "feat: add Docker system prune cleanup"
```

---

### Task 8: Large File Finder

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/large_files.bats`

**Step 1: Write the failing tests**

Create `tests/large_files.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    FORCE_MODE="false"
    DRY_RUN="false"
    export LARGE_FILE_SCAN_DIR="$TEST_TEMP_DIR"
    export LARGE_FILE_MIN_SIZE_KB=1  # 1KB for testing instead of 500MB
}

@test "find_large_files lists files above threshold" {
    dd if=/dev/zero of="$TEST_TEMP_DIR/bigfile.bin" bs=1024 count=5 2>/dev/null
    run find_large_files
    [[ "$output" == *"bigfile.bin"* ]]
}

@test "find_large_files shows nothing when no large files" {
    run find_large_files
    [[ "$output" == *"No files found"* ]] || [[ "$output" == *"Large Files"* ]]
}

@test "find_large_files dry run still lists files" {
    DRY_RUN="true"
    dd if=/dev/zero of="$TEST_TEMP_DIR/bigfile.bin" bs=1024 count=5 2>/dev/null
    run find_large_files
    [[ "$output" == *"bigfile.bin"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/large_files.bats`
Expected: All FAIL

**Step 3: Implement large file finder**

Add to `disk-helper.sh`:

```bash
LARGE_FILE_SCAN_DIR="${LARGE_FILE_SCAN_DIR:-$HOME}"
LARGE_FILE_MIN_SIZE_KB="${LARGE_FILE_MIN_SIZE_KB:-524288}"  # 500MB in KB

find_large_files() {
    echo ""
    echo "=== Large Files (>$(format_size $(( LARGE_FILE_MIN_SIZE_KB * 1024 )))) ==="

    local files
    files="$(find "$LARGE_FILE_SCAN_DIR" -type f -size +"${LARGE_FILE_MIN_SIZE_KB}k" \
        -not -path "*/Library/*" \
        -not -path "*/.Trash/*" \
        -not -path "*/.*" \
        2>/dev/null | head -20 || true)"

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
        # Always ask — never auto-delete large files
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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/large_files.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/large_files.bats
git commit -m "feat: add large file finder with always-interactive deletion"
```

---

### Task 9: Duplicate File Finder

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/duplicates.bats`

**Step 1: Write the failing tests**

Create `tests/duplicates.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    FORCE_MODE="false"
    DRY_RUN="false"
    export DUPLICATE_SCAN_DIRS="$TEST_TEMP_DIR"
}

@test "find_duplicates detects identical files" {
    echo "identical content" > "$TEST_TEMP_DIR/file1.txt"
    echo "identical content" > "$TEST_TEMP_DIR/file2.txt"
    run find_duplicates
    [[ "$output" == *"file1.txt"* ]]
    [[ "$output" == *"file2.txt"* ]]
}

@test "find_duplicates ignores unique files" {
    echo "unique content A" > "$TEST_TEMP_DIR/file1.txt"
    echo "unique content B" > "$TEST_TEMP_DIR/file2.txt"
    run find_duplicates
    [[ "$output" == *"No duplicates"* ]]
}

@test "find_duplicates dry run lists but does not delete" {
    DRY_RUN="true"
    echo "same" > "$TEST_TEMP_DIR/file1.txt"
    echo "same" > "$TEST_TEMP_DIR/file2.txt"
    find_duplicates
    [ -f "$TEST_TEMP_DIR/file1.txt" ]
    [ -f "$TEST_TEMP_DIR/file2.txt" ]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/duplicates.bats`
Expected: All FAIL

**Step 3: Implement duplicate file finder**

Add to `disk-helper.sh`:

```bash
DUPLICATE_SCAN_DIRS="${DUPLICATE_SCAN_DIRS:-$HOME/Downloads:$HOME/Documents:$HOME/Desktop}"

find_duplicates() {
    echo ""
    echo "=== Duplicate Files ==="

    local -A size_map
    local -A hash_map
    local -a duplicates

    # Split scan dirs by colon
    IFS=':' read -ra dirs <<< "$DUPLICATE_SCAN_DIRS"

    # Pass 1: group by size
    local -A files_by_size
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r file; do
            local size
            size="$(stat -f%z "$file" 2>/dev/null || echo 0)"
            [[ "$size" -gt 0 ]] || continue
            files_by_size["$size"]+="$file"$'\n'
        done < <(find "$dir" -type f -maxdepth 3 2>/dev/null)
    done

    # Pass 2: for same-size files, compare checksums
    local found_dupes=false
    local -A seen_hashes
    local dupe_groups=""

    for size in "${!files_by_size[@]}"; do
        local file_list="${files_by_size[$size]}"
        local count
        count="$(echo -n "$file_list" | grep -c '^' || true)"
        [[ "$count" -gt 1 ]] || continue

        # Hash each file
        local -A hash_to_files
        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            local hash
            hash="$(md5 -q "$file" 2>/dev/null || true)"
            [[ -n "$hash" ]] || continue
            hash_to_files["$hash"]+="$file"$'\n'
        done <<< "$file_list"

        for hash in "${!hash_to_files[@]}"; do
            local group="${hash_to_files[$hash]}"
            local gcount
            gcount="$(echo -n "$group" | grep -c '^' || true)"
            if [[ "$gcount" -gt 1 ]]; then
                found_dupes=true
                echo "  Duplicate group ($(format_size "$size") each):"
                while IFS= read -r f; do
                    [[ -n "$f" ]] || continue
                    echo "    $f"
                done <<< "$group"
                echo ""
            fi
        done
        unset hash_to_files
    done

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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/duplicates.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/duplicates.bats
git commit -m "feat: add duplicate file finder with checksum-based detection"
```

---

### Task 10: Old Downloads Cleanup

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/old_downloads.bats`

**Step 1: Write the failing tests**

Create `tests/old_downloads.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
    export DOWNLOADS_DIR="$TEST_TEMP_DIR/Downloads"
    mkdir -p "$DOWNLOADS_DIR"
    DOWNLOAD_AGE_DAYS=30
}

@test "clean_old_downloads removes old files" {
    touch -t 202501010000 "$DOWNLOADS_DIR/oldfile.zip"
    clean_old_downloads
    [ ! -f "$DOWNLOADS_DIR/oldfile.zip" ]
}

@test "clean_old_downloads keeps recent files" {
    touch "$DOWNLOADS_DIR/newfile.zip"
    clean_old_downloads
    [ -f "$DOWNLOADS_DIR/newfile.zip" ]
}

@test "clean_old_downloads dry run does not delete" {
    DRY_RUN="true"
    touch -t 202501010000 "$DOWNLOADS_DIR/oldfile.zip"
    clean_old_downloads
    [ -f "$DOWNLOADS_DIR/oldfile.zip" ]
}

@test "clean_old_downloads respects --days setting" {
    DOWNLOAD_AGE_DAYS=1
    # Create a file that's 2 days old
    touch -t "$(date -v-2d +%Y%m%d0000)" "$DOWNLOADS_DIR/oldish.zip"
    clean_old_downloads
    [ ! -f "$DOWNLOADS_DIR/oldish.zip" ]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/old_downloads.bats`
Expected: All FAIL

**Step 3: Implement old downloads cleanup**

Add to `disk-helper.sh`:

```bash
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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/old_downloads.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/old_downloads.bats
git commit -m "feat: add old downloads cleanup with configurable age threshold"
```

---

### Task 11: Empty Trash

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/trash.bats`

**Step 1: Write the failing tests**

Create `tests/trash.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
    export TRASH_DIR="$TEST_TEMP_DIR/.Trash"
    mkdir -p "$TRASH_DIR"
}

@test "clean_trash removes trash contents" {
    echo "junk" > "$TRASH_DIR/junkfile.txt"
    clean_trash
    [ ! -f "$TRASH_DIR/junkfile.txt" ]
}

@test "clean_trash dry run does not delete" {
    DRY_RUN="true"
    echo "junk" > "$TRASH_DIR/junkfile.txt"
    clean_trash
    [ -f "$TRASH_DIR/junkfile.txt" ]
}

@test "clean_trash handles empty trash" {
    run clean_trash
    [[ "$output" == *"empty"* ]] || [[ "$output" == *"Trash"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/trash.bats`
Expected: All FAIL

**Step 3: Implement trash cleanup**

Add to `disk-helper.sh`:

```bash
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
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/trash.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/trash.bats
git commit -m "feat: add Trash cleanup"
```

---

### Task 12: Wire Everything Into Main & Final Integration

**Files:**
- Modify: `disk-helper.sh`
- Create: `tests/integration.bats`

**Step 1: Write the failing tests**

Create `tests/integration.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "script runs with --dry-run without errors" {
    run ./disk-helper.sh --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk-helper"* ]]
    [[ "$output" == *"Disk Usage"* ]]
    [[ "$output" == *"Summary"* ]]
}

@test "script shows help" {
    run ./disk-helper.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "script rejects bad flags" {
    run ./disk-helper.sh --invalid
    [ "$status" -ne 0 ]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/integration.bats`
Expected: Some may fail if main isn't wired up

**Step 3: Wire up main function**

Update `main` in `disk-helper.sh`:

```bash
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
```

**Step 4: Run ALL tests**

Run: `bats tests/*.bats`
Expected: All PASS

**Step 5: Commit**

```bash
git add disk-helper.sh tests/integration.bats
git commit -m "feat: wire all cleanup categories into main and add integration tests"
```

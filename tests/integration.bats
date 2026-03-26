#!/usr/bin/env bats

load test_helper

@test "script runs with --dry-run without errors" {
    # Override paths to avoid permission errors on real system directories
    export USER_CACHE_DIR="$TEST_TEMP_DIR/caches"
    export XCODE_DERIVED_DATA="$TEST_TEMP_DIR/DerivedData"
    export XCODE_ARCHIVES="$TEST_TEMP_DIR/Archives"
    export XCODE_DEVICE_SUPPORT="$TEST_TEMP_DIR/DeviceSupport"
    export LARGE_FILE_SCAN_DIR="$TEST_TEMP_DIR"
    export LARGE_FILE_MIN_SIZE_KB=524288
    export DOWNLOADS_DIR="$TEST_TEMP_DIR/Downloads"
    export TRASH_DIR="$TEST_TEMP_DIR/Trash"
    export DUPLICATE_SCAN_DIRS="$TEST_TEMP_DIR/Downloads"
    mkdir -p "$USER_CACHE_DIR" "$DOWNLOADS_DIR" "$TRASH_DIR"

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

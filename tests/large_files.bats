#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export LARGE_FILE_SCAN_DIR="$TEST_TEMP_DIR"
    export LARGE_FILE_MIN_SIZE_KB=1  # 1KB for testing instead of 500MB
    source ./disk-helper.sh
    FORCE_MODE="false"
    DRY_RUN="false"
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

#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export DUPLICATE_SCAN_DIRS="$TEST_TEMP_DIR"
    source ./disk-helper.sh
    FORCE_MODE="false"
    DRY_RUN="false"
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

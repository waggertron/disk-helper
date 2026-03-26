#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    source ./disk-helper.sh
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
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

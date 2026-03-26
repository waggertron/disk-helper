#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
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

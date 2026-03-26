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
    source ./disk-helper.sh
    parse_args --force
    [ "$FORCE_MODE" = "true" ]
}

@test "sets dry run mode with --dry-run" {
    source ./disk-helper.sh
    parse_args --dry-run
    [ "$DRY_RUN" = "true" ]
}

@test "sets custom days with --days=N" {
    source ./disk-helper.sh
    parse_args --days=60
    [ "$DOWNLOAD_AGE_DAYS" = "60" ]
}

@test "defaults days to 30" {
    source ./disk-helper.sh
    parse_args --dry-run
    [ "$DOWNLOAD_AGE_DAYS" = "30" ]
}

@test "rejects unknown flags" {
    run ./disk-helper.sh --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

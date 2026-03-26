#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    source ./disk-helper.sh
    DRY_RUN="false"
    FORCE_MODE="true"
}

@test "clean_homebrew skips if brew not installed" {
    tool_installed() { return 1; }
    run clean_homebrew
    [[ "$output" == *"not installed"* ]]
}

@test "clean_homebrew runs brew cleanup in dry-run" {
    DRY_RUN="true"
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

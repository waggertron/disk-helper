#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
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
    # Mock docker as installed but don't actually run it
    tool_installed() { [[ "$1" == "docker" ]] && return 0 || command -v "$1" &>/dev/null; }
    # Mock docker info to succeed
    docker() {
        if [[ "$1" == "info" ]]; then return 0; fi
        if [[ "$1" == "system" && "$2" == "df" ]]; then echo "mock docker df output"; fi
    }
    run clean_docker
    [[ "$output" == *"dry-run"* ]]
}

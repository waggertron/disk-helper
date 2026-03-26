#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export USER_CACHE_DIR="$TEST_TEMP_DIR/user_caches"
    source ./disk-helper.sh
    mkdir -p "$USER_CACHE_DIR/com.apple.something"
    dd if=/dev/zero of="$USER_CACHE_DIR/com.apple.something/cache.db" bs=1024 count=50 2>/dev/null
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
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

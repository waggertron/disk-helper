#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export XCODE_DERIVED_DATA="$TEST_TEMP_DIR/DerivedData"
    export XCODE_ARCHIVES="$TEST_TEMP_DIR/Archives"
    export XCODE_DEVICE_SUPPORT="$TEST_TEMP_DIR/DeviceSupport"
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
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

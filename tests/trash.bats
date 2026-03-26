#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export TRASH_DIR="$TEST_TEMP_DIR/.Trash"
    mkdir -p "$TRASH_DIR"
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
}

@test "clean_trash removes trash contents" {
    echo "junk" > "$TRASH_DIR/junkfile.txt"
    clean_trash
    [ ! -f "$TRASH_DIR/junkfile.txt" ]
}

@test "clean_trash dry run does not delete" {
    DRY_RUN="true"
    echo "junk" > "$TRASH_DIR/junkfile.txt"
    clean_trash
    [ -f "$TRASH_DIR/junkfile.txt" ]
}

@test "clean_trash handles empty trash" {
    run clean_trash
    [[ "$output" == *"empty"* ]] || [[ "$output" == *"Trash"* ]]
}

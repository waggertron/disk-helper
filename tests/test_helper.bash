setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

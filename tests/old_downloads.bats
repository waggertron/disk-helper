#!/usr/bin/env bats

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export DOWNLOADS_DIR="$TEST_TEMP_DIR/Downloads"
    mkdir -p "$DOWNLOADS_DIR"
    source ./disk-helper.sh
    FORCE_MODE="true"
    DRY_RUN="false"
    DOWNLOAD_AGE_DAYS=30
}

@test "clean_old_downloads removes old files" {
    touch -t 202501010000 "$DOWNLOADS_DIR/oldfile.zip"
    clean_old_downloads
    [ ! -f "$DOWNLOADS_DIR/oldfile.zip" ]
}

@test "clean_old_downloads keeps recent files" {
    touch "$DOWNLOADS_DIR/newfile.zip"
    clean_old_downloads
    [ -f "$DOWNLOADS_DIR/newfile.zip" ]
}

@test "clean_old_downloads dry run does not delete" {
    DRY_RUN="true"
    touch -t 202501010000 "$DOWNLOADS_DIR/oldfile.zip"
    clean_old_downloads
    [ -f "$DOWNLOADS_DIR/oldfile.zip" ]
}

@test "clean_old_downloads respects --days setting" {
    DOWNLOAD_AGE_DAYS=1
    touch -t "$(date -v-2d +%Y%m%d0000)" "$DOWNLOADS_DIR/oldish.zip"
    clean_old_downloads
    [ ! -f "$DOWNLOADS_DIR/oldish.zip" ]
}

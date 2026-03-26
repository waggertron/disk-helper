#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

FORCE_MODE="false"
DRY_RUN="false"
DOWNLOAD_AGE_DAYS=30

show_help() {
    cat <<'HELP'
Usage: disk-helper.sh [OPTIONS]

Options:
  --force       Auto-clean without prompting (large files/duplicates still interactive)
  --dry-run     Report what would be cleaned without deleting
  --days=N      Age threshold for old downloads (default: 30)
  -h, --help    Show help message
HELP
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --force)
                FORCE_MODE="true"
                ;;
            --dry-run)
                DRY_RUN="true"
                ;;
            --days=*)
                DOWNLOAD_AGE_DAYS="${1#*=}"
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help >&2
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    echo "disk-helper v${VERSION}"
}

# Guard: only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

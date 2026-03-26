# Disk Helper — Design Document

## Overview

A single bash script (`disk-helper.sh`) that helps clean up disk space on macOS. It works through multiple cleanup categories, detects which tools are installed, and reports space reclaimed.

## Modes

- **Interactive (default)** — shows findings per category, asks y/n before deleting
- **`--force`** — auto-cleans without prompting (except large files and duplicates, which always require confirmation)
- **`--dry-run`** — reports what would be cleaned without deleting anything

## Cleanup Categories (in order)

1. **System caches** — `~/Library/Caches/*`, `/Library/Caches/*`
2. **Homebrew** — `brew cleanup --prune=all`
3. **npm** — `npm cache clean --force`
4. **pip** — `pip cache purge`
5. **Xcode** — DerivedData, archives, device support files
6. **Docker** — `docker system prune` (dangling images, stopped containers, unused networks)
7. **Large file finder** — scan home directory for files >500MB
8. **Duplicate file finder** — checksum-based scan of Downloads, Documents, Desktop
9. **Old downloads** — files in ~/Downloads older than 30 days (configurable via `--days=N`)
10. **Trash** — empty system Trash

## Per-Category Flow

For each category the script:
1. Detects if the tool is installed (via `command -v`), skips if not
2. Calculates the size of what can be cleaned
3. Shows the size to the user
4. In interactive mode: asks y/n before proceeding
5. In force mode: cleans automatically
6. Reports space freed

## Error Handling & Safety

- **Sudo** — prompts once upfront if system-level caches will be cleaned
- **Tool detection** — `command -v` to check for brew/npm/pip/docker/xcodebuild
- **Protected paths** — never touches anything outside known cache/temp locations
- **Large files & duplicates** — always interactive, even in `--force` mode
- **Logging** — writes summary to `/tmp/disk-helper-YYYY-MM-DD.log`
- **Ctrl+C** — trapped to show partial results and space reclaimed so far

## Duplicate File Finder

- Scans ~/Downloads, ~/Documents, ~/Desktop
- Groups files by size first (fast filter)
- Compares MD5 checksums (`md5 -q`) for same-size files only
- Presents duplicate groups with paths, user picks which to keep
- Always interactive regardless of mode

## CLI Interface

```
Usage: disk-helper.sh [OPTIONS]

Options:
  --force       Auto-clean without prompting (large files/duplicates still interactive)
  --dry-run     Report what would be cleaned without deleting
  --days=N      Age threshold for old downloads (default: 30)
  -h, --help    Show help message
```

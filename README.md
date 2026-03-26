# disk-helper

A comprehensive macOS disk cleanup tool. Single bash script, zero dependencies beyond what ships with macOS.

> **Platform:** macOS only. This script relies on macOS-specific paths (`~/Library/Caches`, `~/.Trash`, Xcode directories), macOS `stat` flags (`-f%z`), macOS `md5` command, and `df` output formatting. It will not work on Linux or Windows without modification.

## What it cleans

| Category | What it does |
|---|---|
| **System caches** | Clears `~/Library/Caches` and `/Library/Caches` (sudo) |
| **Homebrew** | Runs `brew cleanup --prune=all` to remove old formula versions |
| **npm** | Runs `npm cache clean --force` |
| **pip** | Runs `pip3 cache purge` (or `pip cache purge`) |
| **Xcode** | Removes DerivedData, Archives, and iOS Device Support files |
| **Docker** | Runs `docker system prune` (dangling images, stopped containers, unused networks) |
| **Large files** | Scans your home directory for files >500MB |
| **Duplicates** | Finds duplicate files in Downloads, Documents, and Desktop using MD5 checksums |
| **Old downloads** | Removes files in `~/Downloads` older than 30 days (configurable) |
| **Trash** | Empties the system Trash |

The script auto-detects which tools are installed and skips categories that don't apply. If you don't have Xcode, Docker, npm, etc., those sections are silently skipped.

## Installation

```bash
git clone https://github.com/waggertron/disk-helper.git
cd disk-helper
chmod +x disk-helper.sh
```

### Optional: add a shell alias

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias disk-clean="/path/to/disk-helper/disk-helper.sh"
```

Then reload your shell (`source ~/.zshrc`) and use `disk-clean` from anywhere.

## Usage

```
./disk-helper.sh [OPTIONS]
```

### Options

| Flag | Description |
|---|---|
| `--dry-run` | Show what would be cleaned without deleting anything. **Start here.** |
| `--force` | Auto-clean without prompting for each category. Large files and duplicates still require individual confirmation for safety. |
| `--days=N` | Set the age threshold for old downloads (default: 30 days). |
| `-h`, `--help` | Show help message. |

### Examples

**See what's using space (safe, deletes nothing):**

```bash
./disk-helper.sh --dry-run
```

**Interactive cleanup (asks before each action):**

```bash
./disk-helper.sh
```

**Auto-clean everything except large files and duplicates:**

```bash
./disk-helper.sh --force
```

**Clean downloads older than 60 days:**

```bash
./disk-helper.sh --days=60
```

**Combine flags:**

```bash
./disk-helper.sh --force --days=14
```

## How it works

### Three modes

1. **Interactive (default)** -- The script shows the size of each category and asks `[y/N]` before cleaning. You approve or skip each one individually.

2. **Dry run (`--dry-run`)** -- Reports everything it would clean with sizes, but makes no changes. Use this first to see what's eating your disk.

3. **Force (`--force`)** -- Cleans all categories without prompting. Two exceptions for safety: **large files** and **duplicate files** always require individual confirmation, even in force mode. These are too risky to auto-delete.

### Safety features

- **Tool detection** -- Uses `command -v` to check if brew, npm, pip, docker, and xcodebuild exist before attempting cleanup. Missing tools are skipped silently.
- **Protected paths** -- All `rm -rf` calls use the `${VAR:?}` bash guard to prevent accidental deletion if a path variable is empty.
- **Large files are always interactive** -- Even with `--force`, each large file requires individual confirmation before deletion.
- **Duplicates are never auto-deleted** -- The duplicate finder reports what it finds but does not auto-delete. Review the output and remove files manually.
- **Ctrl+C handling** -- If you interrupt the script mid-run, it shows a summary of space freed so far before exiting.
- **Logging** -- Every action is logged to `/tmp/disk-helper-YYYY-MM-DD.log` so you can review what was cleaned after the fact.

### What requires sudo

Only the system-level cache cleanup (`/Library/Caches`) requires `sudo`. The script will prompt for your password if it needs it. Everything else runs as your normal user.

## Running tests

The test suite uses [bats-core](https://github.com/bats-core/bats-core).

```bash
# Install bats
brew install bats-core

# Run all tests
bats tests/*.bats
```

There are 50 tests covering argument parsing, utility functions, and each cleanup category. Tests use temporary directories and mock commands to avoid touching your real filesystem.

## Requirements

- **macOS** (tested on macOS Sequoia, should work on Monterey+)
- **Bash** (ships with macOS)
- **bats-core** (only needed to run tests)

Optional tools that enable additional cleanup categories:
- [Homebrew](https://brew.sh)
- Node.js / npm
- Python / pip
- Xcode
- Docker

## Project structure

```
disk-helper/
  disk-helper.sh          # The script (single file, ~590 lines)
  tests/
    test_helper.bash      # Shared test setup/teardown
    args.bats             # Argument parsing tests
    utils.bats            # Utility function tests
    report.bats           # Disk report/summary tests
    clean_caches.bats     # System cache tests
    clean_package_managers.bats  # Homebrew/npm/pip tests
    clean_xcode.bats      # Xcode cleanup tests
    clean_docker.bats     # Docker cleanup tests
    large_files.bats      # Large file finder tests
    duplicates.bats       # Duplicate finder tests
    old_downloads.bats    # Old downloads tests
    trash.bats            # Trash cleanup tests
    integration.bats      # End-to-end integration tests
  docs/plans/             # Design and implementation docs
```

## License

MIT

# Recipe Synchronization Tool

This tool synchronizes cloud recipes from your development repository to the awesome-cloud-projects repository. It performs intelligent one-way syncing, comparing timestamps to only copy new or updated recipes.

## 📋 Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [Command-Line Options](#command-line-options)
- [Safety Features](#safety-features)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

### Purpose

The sync tool automatically copies recipes from your development repository to the production awesome-cloud-projects repository. It:

- **Source**: `/Users/mzazon/Dev/GitHub/recipes/{aws,azure,gcp}/`
- **Destination**: `/Users/mzazon/Dev/GitHub/awesome-cloud-projects/{aws,azure,gcp}/`

### Key Features

✅ **Smart Synchronization**: Only copies new or updated recipes  
✅ **Safe by Default**: Runs in dry-run mode unless explicitly requested  
✅ **Timestamp Comparison**: Compares modification times to detect changes  
✅ **Selective Syncing**: Sync specific providers (AWS, Azure, GCP)  
✅ **Backup Support**: Create backups before overwriting  
✅ **Detailed Reporting**: Comprehensive statistics and progress tracking  
✅ **Error Handling**: Robust error detection and reporting  

## Installation

### Prerequisites

- **Python 3.7+** (uses standard library only)
- **File System Access** to both source and destination repositories
- **Write Permissions** to destination directory

### Setup

The script is located in the `.publish/scripts/` directory and requires no additional installation:

```bash
# Navigate to the scripts directory
cd .publish/scripts

# Make the script executable (optional)
chmod +x sync_recipes.py
```

## Quick Start

### 1. Preview Changes (Recommended First Step)

```bash
# See what would be synced without making any changes
python3 sync_recipes.py --dry-run
```

### 2. Perform Actual Sync

```bash
# Perform the actual synchronization
python3 sync_recipes.py --live
```

### 3. Check Statistics Only

```bash
# Just show statistics without syncing
python3 sync_recipes.py --stats-only
```

## Usage Guide

### Basic Workflow

1. **Always start with dry-run** to see what will be changed
2. **Review the preview** to ensure expected recipes will be synced
3. **Run live sync** to perform actual copying
4. **Check the summary report** for confirmation

### Default Behavior

- **Dry-run mode**: Enabled by default for safety
- **All providers**: Syncs aws, azure, and gcp by default
- **Timestamp comparison**: Only copies newer files
- **No backup**: Overwrites without backup unless requested

## Command-Line Options

### Basic Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Preview changes without copying | `True` |
| `--live` | Perform actual sync (overrides dry-run) | `False` |
| `--stats-only` | Show statistics without syncing | `False` |

### Path Options

| Option | Description | Default |
|--------|-------------|---------|
| `--source` | Source repository path | `/Users/mzazon/Dev/GitHub/recipes` |
| `--dest` | Destination repository path | `/Users/mzazon/Dev/GitHub/awesome-cloud-projects` |

### Filtering Options

| Option | Description | Example |
|--------|-------------|---------|
| `--provider` | Comma-separated providers to sync | `--provider aws,azure` |

### Safety Options

| Option | Description | Use Case |
|--------|-------------|----------|
| `--force` | Force overwrite regardless of timestamps | When timestamps are unreliable |
| `--backup` | Create backup before overwriting | When you want to preserve existing versions |

### Output Options

| Option | Description | Use Case |
|--------|-------------|----------|
| `--verbose`, `-v` | Enable detailed logging | Debugging or detailed progress |
| `--quiet`, `-q` | Suppress all output except errors | Automated scripts |

## Safety Features

### 1. Dry-Run by Default

The script runs in **dry-run mode by default**. This means:
- No files are actually copied
- You see exactly what would happen
- You must explicitly use `--live` to perform actual sync

### 2. Timestamp Comparison

- Only copies recipes that are newer in source than destination
- Compares the latest modification time of any file in the recipe folder
- Skips recipes that are already up-to-date

### 3. Backup Option

```bash
# Create timestamped backups before overwriting
python3 sync_recipes.py --live --backup
```

Backups are created with format: `{recipe-name}.backup.{timestamp}`

### 4. Comprehensive Reporting

Every operation provides:
- Summary statistics (new, updated, skipped recipes)
- Detailed file counts and sizes
- Error reporting with specific folder names
- Timestamp information for troubleshooting

## Examples

### Basic Operations

```bash
# Preview all changes
python3 sync_recipes.py --dry-run

# Perform full sync
python3 sync_recipes.py --live

# Show statistics only
python3 sync_recipes.py --stats-only
```

### Provider-Specific Syncing

```bash
# Sync only AWS recipes
python3 sync_recipes.py --live --provider aws

# Sync AWS and Azure only
python3 sync_recipes.py --live --provider aws,azure

# Preview GCP recipes only
python3 sync_recipes.py --dry-run --provider gcp
```

### Advanced Options

```bash
# Sync with backups and verbose output
python3 sync_recipes.py --live --backup --verbose

# Force sync all recipes regardless of timestamps
python3 sync_recipes.py --live --force

# Quiet mode for automated scripts
python3 sync_recipes.py --live --quiet
```

### Custom Paths

```bash
# Use custom source/destination paths
python3 sync_recipes.py --live \
  --source /path/to/custom/recipes \
  --dest /path/to/custom/destination
```

## Sample Output

### Dry-Run Output

```
2024-08-31 14:30:00,123 - INFO - Starting DRY RUN sync for providers: aws, azure, gcp
2024-08-31 14:30:00,124 - INFO - Analyzing aws recipes...
2024-08-31 14:30:01,200 - INFO - Analyzing azure recipes...
2024-08-31 14:30:02,100 - INFO - Analyzing gcp recipes...

================================================================================
RECIPE SYNCHRONIZATION REPORT
================================================================================
Mode: DRY RUN (Preview Only)
Timestamp: 2024-08-31 14:30:02

SUMMARY:
  Total recipes analyzed: 850
  New recipes: 45
  Updated recipes: 12
  Up-to-date recipes: 793
  Total size to copy: 15.3 MB

NEW RECIPES (45):
  📁 aws/new-lambda-function (2.1 MB, 15 files)
  📁 aws/advanced-s3-lifecycle (1.8 MB, 12 files)
  📁 azure/cognitive-services-demo (3.2 MB, 20 files)
  ... and 42 more

UPDATED RECIPES (12):
  🔄 aws/existing-ecs-cluster (1.1 MB) - source is newer (source: 2024-08-31 10:15:30, dest: 2024-08-30 15:20:10)
  🔄 gcp/bigquery-analytics (2.3 MB) - source is newer (source: 2024-08-31 09:45:22, dest: 2024-08-29 14:30:45)
  ... and 10 more

================================================================================
To perform the actual sync, run the command without --dry-run
```

### Live Sync Output

```
2024-08-31 14:35:00,123 - INFO - Starting LIVE sync for providers: aws, azure, gcp
2024-08-31 14:35:00,124 - INFO - Performing live sync...
2024-08-31 14:35:00,125 - INFO - Copying new recipe: aws/new-lambda-function
2024-08-31 14:35:01,200 - INFO - Updating recipe: aws/existing-ecs-cluster (source is newer)

================================================================================
RECIPE SYNCHRONIZATION REPORT
================================================================================
Mode: LIVE SYNC
Timestamp: 2024-08-31 14:35:10

SUMMARY:
  Total recipes analyzed: 850
  New recipes: 45
  Updated recipes: 12
  Up-to-date recipes: 793
  Total size to copy: 15.3 MB
  Actual copies performed: 57
  Errors encountered: 0
  Total size copied: 15.3 MB

================================================================================
Sync completed!
```

## Troubleshooting

### Common Issues

#### 1. Permission Errors

```bash
❌ Error: Permission denied accessing /path/to/recipes
```

**Solution**: Ensure you have read access to source and write access to destination:

```bash
# Check permissions
ls -la /Users/mzazon/Dev/GitHub/recipes
ls -la /Users/mzazon/Dev/GitHub/awesome-cloud-projects

# Fix permissions if needed (be careful with this)
chmod -R u+rw /Users/mzazon/Dev/GitHub/awesome-cloud-projects
```

#### 2. Source Directory Not Found

```bash
❌ Error: Source base directory does not exist: /path/to/recipes
```

**Solution**: Verify the source path exists or use `--source` to specify correct path:

```bash
# Check if source exists
ls -la /Users/mzazon/Dev/GitHub/recipes

# Use custom source path
python3 sync_recipes.py --source /correct/path/to/recipes
```

#### 3. No Recipes Found

```bash
INFO - Total recipes analyzed: 0
```

**Solution**: Check that provider directories exist and contain recipe folders:

```bash
# Check provider directories
ls -la /Users/mzazon/Dev/GitHub/recipes/aws
ls -la /Users/mzazon/Dev/GitHub/recipes/azure
ls -la /Users/mzazon/Dev/GitHub/recipes/gcp
```

#### 4. Sync Errors During Copy

```bash
❌ aws/problematic-recipe
```

**Solution**: Run with `--verbose` to see detailed error information:

```bash
python3 sync_recipes.py --live --verbose
```

Common causes:
- File in use by another process
- Insufficient disk space
- Special characters in filenames
- Symbolic links or special file types

### Debugging Commands

```bash
# Show detailed information about what the script sees
python3 sync_recipes.py --dry-run --verbose

# Check specific provider
python3 sync_recipes.py --dry-run --provider aws --verbose

# Test with statistics only (safest for debugging)
python3 sync_recipes.py --stats-only --verbose
```

### Recovery

If a sync fails partway through:

1. **Check the error messages** in the output
2. **Run dry-run again** to see remaining work
3. **Fix the underlying issue** (permissions, disk space, etc.)
4. **Re-run the sync** - it will skip already-copied recipes

If you need to restore from backups:

```bash
# Backups are created with timestamp suffix
ls -la /Users/mzazon/Dev/GitHub/awesome-cloud-projects/aws/*.backup.*

# Restore manually if needed
mv problematic-recipe.backup.1693478400 problematic-recipe
```

## Integration

### With README Generation

After syncing recipes, regenerate the README:

```bash
# Sync recipes first
python3 sync_recipes.py --live

# Then regenerate README
python3 generate_readme.py
```

### Automation

For automated use in scripts:

```bash
#!/bin/bash
set -e

# Sync recipes quietly
python3 sync_recipes.py --live --quiet

# Generate new README
python3 generate_readme.py --quiet

echo "Sync and README generation completed successfully"
```

### Scheduling

To run periodically, add to crontab:

```bash
# Run every day at 9 AM
0 9 * * * cd /Users/mzazon/Dev/GitHub/awesome-cloud-projects/.publish/scripts && python3 sync_recipes.py --live --quiet
```

## Support

For issues or questions:

1. **Run with `--verbose`** to get detailed logging
2. **Check file permissions** on both source and destination
3. **Verify paths exist** and contain expected structure
4. **Test with `--dry-run`** to isolate issues
5. **Use `--stats-only`** for safe troubleshooting

---

*This tool is designed to safely synchronize your recipe repositories. Always test with dry-run mode first!*
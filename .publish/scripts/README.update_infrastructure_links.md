# Infrastructure Code Link Updater

This tool automatically updates the "Infrastructure Code" section in recipe markdown files by replacing placeholder text with actual links to the infrastructure code folders. It intelligently detects what infrastructure-as-code tools are available for each recipe and generates appropriate links with provider-specific descriptions.

## 📋 Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [Command-Line Options](#command-line-options)
- [Provider Mappings](#provider-mappings)
- [Safety Features](#safety-features)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

### Purpose

The script searches for recipes containing the placeholder text `*Infrastructure code will be generated after recipe approval.*` under the "## Infrastructure Code" heading and replaces it with dynamic links to actual infrastructure code directories.

**Target Text:**
```markdown
## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*
```

**Result:**
```markdown
## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [Terraform](code/terraform/) - Terraform configuration files
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
```

### Key Features

✅ **Smart Detection**: Only processes recipes with exact placeholder text  
✅ **Provider-Aware**: Different IaC tools for AWS, Azure, and GCP  
✅ **Safe by Default**: Runs in dry-run mode unless explicitly requested  
✅ **Idempotent**: Can be run multiple times safely  
✅ **Selective Processing**: Process specific providers or recipes  
✅ **Comprehensive Logging**: Detailed progress and error reporting  
✅ **README Priority**: Always shows code/README.md link first when available  

## Installation

### Prerequisites

- **Python 3.7+** (uses standard library only)
- **Read/Write Access** to recipe directories
- **Properly structured recipes** with code/ subdirectories

### Setup

The script is located in `.publish/scripts/` and requires no additional installation:

```bash
# Navigate to the scripts directory
cd .publish/scripts

# Make the script executable (optional)
chmod +x update_infrastructure_links.py
```

## Quick Start

### 1. Preview Changes (Recommended First Step)

```bash
# See what would be updated without making any changes
python3 update_infrastructure_links.py --dry-run
```

### 2. Update All Recipes

```bash
# Perform the actual updates
python3 update_infrastructure_links.py --live
```

### 3. Process Specific Provider

```bash
# Update only AWS recipes
python3 update_infrastructure_links.py --live --provider aws
```

## Usage Guide

### Basic Workflow

1. **Always start with dry-run** to preview what will be changed
2. **Review the output** to ensure expected recipes will be updated
3. **Run live update** to perform actual file modifications
4. **Check the summary report** for confirmation

### When the Script Runs

The script will:
- ✅ **Update recipes** containing the exact placeholder text
- ⏭️  **Skip recipes** with custom Infrastructure Code sections
- ⏭️  **Skip recipes** without code/ directories
- ❌ **Report errors** for inaccessible files or parsing issues

## Command-Line Options

### Basic Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Preview changes without modifying files | `True` |
| `--live` | Perform actual updates (overrides dry-run) | `False` |
| `--stats` | Show detailed statistics after processing | `False` |

### Path Options

| Option | Description | Default |
|--------|-------------|---------|
| `--root` | Repository root path | `/Users/mzazon/Dev/GitHub/awesome-cloud-projects` |

### Filtering Options

| Option | Description | Example |
|--------|-------------|---------|
| `--provider` | Comma-separated providers to process | `--provider aws,azure` |
| `--recipe` | Process specific recipe only | `--recipe aws/lambda-function` |

### Advanced Options

| Option | Description | Use Case |
|--------|-------------|----------|
| `--force` | Update files even without exact placeholder | When placeholder text has been modified |

### Output Options

| Option | Description | Use Case |
|--------|-------------|----------|
| `--verbose`, `-v` | Enable detailed logging | Debugging or detailed progress |
| `--quiet`, `-q` | Suppress all output except errors | Automated scripts |

## Provider Mappings

The script uses provider-specific mappings to generate appropriate infrastructure links:

### AWS Infrastructure Tools

| Directory/File | Display Name | Description |
|----------------|--------------|-------------|
| `README.md` | Infrastructure Code Overview | Detailed description of all infrastructure components |
| `cloudformation.yaml` | CloudFormation | AWS CloudFormation template |
| `cloudformation/` | CloudFormation | AWS CloudFormation templates |
| `cdk-typescript/` | AWS CDK (TypeScript) | AWS CDK TypeScript implementation |
| `cdk-python/` | AWS CDK (Python) | AWS CDK Python implementation |
| `cdk-java/` | AWS CDK (Java) | AWS CDK Java implementation |
| `cdk-csharp/` | AWS CDK (C#) | AWS CDK C# implementation |
| `terraform/` | Terraform | Terraform configuration files |
| `scripts/` | Bash CLI Scripts | Example bash scripts using AWS CLI commands to deploy infrastructure |

### Azure Infrastructure Tools

| Directory/File | Display Name | Description |
|----------------|--------------|-------------|
| `README.md` | Infrastructure Code Overview | Detailed description of all infrastructure components |
| `bicep/` | Bicep | Azure Bicep templates |
| `terraform/` | Terraform | Terraform configuration files |
| `arm-templates/` | ARM Templates | Azure Resource Manager templates |
| `arm/` | ARM Templates | Azure Resource Manager templates |
| `scripts/` | Bash CLI Scripts | Example bash scripts using Azure CLI commands to deploy infrastructure |

### GCP Infrastructure Tools

| Directory/File | Display Name | Description |
|----------------|--------------|-------------|
| `README.md` | Infrastructure Code Overview | Detailed description of all infrastructure components |
| `terraform/` | Terraform | Terraform configuration files |
| `infrastructure-manager/` | Infrastructure Manager | GCP Infrastructure Manager templates |
| `deployment-manager/` | Deployment Manager | GCP Deployment Manager templates |
| `scripts/` | Bash CLI Scripts | Example bash scripts using gcloud CLI commands to deploy infrastructure |

## Safety Features

### 1. Dry-Run by Default

The script runs in **dry-run mode by default**. This means:
- No files are actually modified
- You see exactly what would happen
- You must explicitly use `--live` to perform actual updates

### 2. Exact Text Matching

- Only processes recipes with the exact placeholder text
- Preserves custom Infrastructure Code sections
- Won't overwrite manually created content

### 3. Comprehensive Validation

- Checks for code/ directory existence
- Validates markdown structure
- Reports parsing errors clearly
- Maintains file integrity

### 4. Detailed Reporting

Every operation provides:
- Summary statistics (total, updated, skipped, errors)
- Detailed file-by-file results
- Clear error messages with file paths
- Processing time information

## Examples

### Basic Operations

```bash
# Preview all changes
python3 update_infrastructure_links.py --dry-run

# Update all recipes
python3 update_infrastructure_links.py --live

# Show statistics after processing
python3 update_infrastructure_links.py --live --stats
```

### Provider-Specific Processing

```bash
# Process only AWS recipes
python3 update_infrastructure_links.py --live --provider aws

# Process AWS and Azure only
python3 update_infrastructure_links.py --live --provider aws,azure

# Preview GCP recipes only
python3 update_infrastructure_links.py --dry-run --provider gcp
```

### Targeted Processing

```bash
# Process specific recipe
python3 update_infrastructure_links.py --live --recipe aws/my-lambda-function

# Process recipes matching pattern
python3 update_infrastructure_links.py --live --recipe lambda

# Update with verbose output
python3 update_infrastructure_links.py --live --verbose
```

### Advanced Options

```bash
# Force update even without exact placeholder (use carefully)
python3 update_infrastructure_links.py --live --force

# Quiet mode for scripts
python3 update_infrastructure_links.py --live --quiet

# Custom repository path
python3 update_infrastructure_links.py --live --root /path/to/custom/repo
```

## Sample Output

### Dry-Run Output

```
2024-08-31 15:30:00,123 - INFO - Starting DRY RUN processing for providers: aws, azure, gcp
2024-08-31 15:30:00,456 - INFO - Processing 850 recipe files...
2024-08-31 15:30:01,200 - INFO - 🔍 Would update: aws/lambda-api-gateway/lambda-api-gateway.md - Updated with 5 infrastructure items
2024-08-31 15:30:01,250 - INFO - 🔍 Would update: azure/app-service-deployment/app-service-deployment.md - Updated with 3 infrastructure items

================================================================================
INFRASTRUCTURE LINKS UPDATE REPORT
================================================================================
Mode: DRY RUN (Preview Only)
Timestamp: 2024-08-31 15:30:05

SUMMARY:
  Total recipes processed: 850
  Recipes with placeholder text: 456
  Recipes updated: 456
  Recipes skipped: 394
  Errors encountered: 0

UPDATED RECIPES (456):
  ✅ aws/lambda-api-gateway/lambda-api-gateway.md - Updated with 5 infrastructure items
  ✅ aws/s3-static-website/s3-static-website.md - Updated with 4 infrastructure items
  ✅ azure/app-service-deployment/app-service-deployment.md - Updated with 3 infrastructure items
  ... and 453 more

================================================================================
To perform the actual updates, run the command with --live
```

### Live Update Output

```
2024-08-31 15:35:00,123 - INFO - Starting LIVE processing for providers: aws, azure, gcp
2024-08-31 15:35:00,456 - INFO - Processing 850 recipe files...
2024-08-31 15:35:01,200 - INFO - ✅ Updated: aws/lambda-api-gateway/lambda-api-gateway.md - Updated with 5 infrastructure items
2024-08-31 15:35:01,250 - INFO - ✅ Updated: azure/app-service-deployment/app-service-deployment.md - Updated with 3 infrastructure items

================================================================================
INFRASTRUCTURE LINKS UPDATE REPORT
================================================================================
Mode: LIVE UPDATE
Timestamp: 2024-08-31 15:35:15

SUMMARY:
  Total recipes processed: 850
  Recipes with placeholder text: 456
  Recipes updated: 456
  Recipes skipped: 394
  Errors encountered: 0

================================================================================
Infrastructure links update completed!
```

## Before and After Examples

### AWS Recipe Example

**Before:**
```markdown
## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*
```

**After:**
```markdown
## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [Terraform](code/terraform/) - Terraform configuration files
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
```

### Azure Recipe Example

**Before:**
```markdown
## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*
```

**After:**
```markdown
## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Bicep](code/bicep/) - Azure Bicep templates
- [Terraform](code/terraform/) - Terraform configuration files
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using Azure CLI commands to deploy infrastructure
```

### GCP Recipe Example

**Before:**
```markdown
## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*
```

**After:**
```markdown
## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Terraform](code/terraform/) - Terraform configuration files
- [Infrastructure Manager](code/infrastructure-manager/) - GCP Infrastructure Manager templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using gcloud CLI commands to deploy infrastructure
```

## Troubleshooting

### Common Issues

#### 1. No Recipes Updated

```bash
SUMMARY:
  Total recipes processed: 850
  Recipes with placeholder text: 0
  Recipes updated: 0
```

**Possible Causes:**
- Recipes don't contain exact placeholder text
- Infrastructure Code sections have been manually edited
- No code/ directories exist

**Solutions:**
```bash
# Check specific recipe to see current content
python3 update_infrastructure_links.py --dry-run --recipe aws/my-recipe --verbose

# Use force mode if placeholder text was slightly modified (use carefully)
python3 update_infrastructure_links.py --live --force --recipe aws/my-recipe
```

#### 2. Permission Errors

```bash
❌ Error: aws/my-recipe/my-recipe.md - Error: [Errno 13] Permission denied
```

**Solution:**
```bash
# Check and fix file permissions
ls -la /path/to/recipe/file.md
chmod 644 /path/to/recipe/file.md
```

#### 3. No Code Directory Found

```bash
⏭️ Skipped: aws/my-recipe/my-recipe.md - No code directory or items found
```

**Solution:**
- Verify the recipe has a `code/` subdirectory
- Check that code/ directory contains infrastructure files

#### 4. Parsing Errors

```bash
❌ Error: aws/my-recipe/my-recipe.md - Error: No Infrastructure Code section found
```

**Solutions:**
- Ensure the recipe has a `## Infrastructure Code` section
- Check markdown formatting and spelling
- Verify file encoding is UTF-8

### Debugging Commands

```bash
# Show detailed processing information
python3 update_infrastructure_links.py --dry-run --verbose

# Process single recipe to isolate issues
python3 update_infrastructure_links.py --dry-run --recipe aws/problematic-recipe --verbose

# Check specific provider only
python3 update_infrastructure_links.py --dry-run --provider aws --verbose
```

### Validation Steps

1. **Check placeholder text exists**:
   ```bash
   grep -r "Infrastructure code will be generated after recipe approval" aws/*/
   ```

2. **Check Infrastructure Code sections**:
   ```bash
   grep -r "## Infrastructure Code" aws/*/ | head -5
   ```

3. **Verify code directories**:
   ```bash
   find aws/ -name "code" -type d | head -5
   ```

### Recovery

If updates go wrong:

1. **Use version control** to revert changes:
   ```bash
   git checkout -- aws/my-recipe/my-recipe.md
   ```

2. **Re-run with specific recipe** to fix individual files:
   ```bash
   python3 update_infrastructure_links.py --live --recipe aws/my-recipe
   ```

3. **Check git diff** before committing:
   ```bash
   git diff --name-only
   git diff aws/my-recipe/my-recipe.md
   ```

## Integration

### With README Generation

After updating infrastructure links, regenerate the main README:

```bash
# Update infrastructure links
python3 update_infrastructure_links.py --live

# Then regenerate README
python3 generate_readme.py
```

### Automation

For regular maintenance:

```bash
#!/bin/bash
set -e

echo "Updating infrastructure links..."
python3 update_infrastructure_links.py --live --quiet

echo "Regenerating README..."
python3 generate_readme.py --quiet

echo "Update completed successfully"
```

### Git Integration

```bash
# Update links and commit changes
python3 update_infrastructure_links.py --live
git add -A
git commit -m "Update infrastructure code links in recipes"
```

## Support

For issues or questions:

1. **Run with `--verbose`** to get detailed logging
2. **Test with single recipe** using `--recipe` to isolate problems
3. **Check file permissions** and directory structure
4. **Verify placeholder text** is exactly as expected
5. **Use `--dry-run`** first to preview all changes safely

---

*This tool safely updates infrastructure links across all recipe files. Always test with dry-run mode first!*
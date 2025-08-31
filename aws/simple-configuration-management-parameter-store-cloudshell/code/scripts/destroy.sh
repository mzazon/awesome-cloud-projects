#!/bin/bash

#
# Destroy Script for AWS Parameter Store Configuration Management
# 
# This script removes all infrastructure and configuration created by the
# "Simple Configuration Management with Parameter Store and CloudShell" recipe.
#
# Prerequisites:
# - AWS CLI installed and configured
# - IAM permissions for Systems Manager Parameter Store operations
# - Previous deployment using the deploy.sh script
#

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE=false
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_handler() {
    log "ERROR" "Destruction failed at line $1. Check $LOG_FILE for details."
    log "ERROR" "Some resources may not have been deleted. Review manually."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS Parameter Store configuration management infrastructure.

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    -d, --dry-run       Show what would be deleted without actually doing it
    -a, --app-name      Specify application name to delete (default: from deployment state)
    -p, --prefix        Specify parameter prefix to delete (overrides app-name)

EXAMPLES:
    $0                          # Interactive deletion using deployment state
    $0 --force                  # Delete without confirmation prompts
    $0 --dry-run                # Show deletion plan without executing
    $0 --app-name myapp         # Delete specific app parameters
    $0 --prefix /myapp          # Delete specific parameter prefix

SAFETY:
    This script will delete ALL parameters under the specified prefix.
    Use --dry-run first to preview what will be deleted.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -a|--app-name)
            CUSTOM_APP_NAME="$2"
            shift 2
            ;;
        -p|--prefix)
            CUSTOM_PREFIX="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
echo "Destruction started at $(date)" > "$LOG_FILE"
log "INFO" "Starting AWS Parameter Store configuration management destruction"

# Load deployment state
load_deployment_state() {
    local state_file="${SCRIPT_DIR}/deployment-state.json"
    
    if [[ -n "${CUSTOM_PREFIX:-}" ]]; then
        export PARAM_PREFIX="$CUSTOM_PREFIX"
        export APP_NAME=$(echo "$PARAM_PREFIX" | sed 's|^/||')
        log "INFO" "Using custom parameter prefix: $PARAM_PREFIX"
        return
    fi
    
    if [[ -n "${CUSTOM_APP_NAME:-}" ]]; then
        export APP_NAME="$CUSTOM_APP_NAME"
        export PARAM_PREFIX="/${APP_NAME}"
        log "INFO" "Using custom app name: $APP_NAME"
        return
    fi
    
    if [[ -f "$state_file" ]]; then
        log "INFO" "Loading deployment state from: $state_file"
        
        # Extract values from JSON state file
        export APP_NAME=$(grep -o '"app_name": "[^"]*"' "$state_file" | cut -d'"' -f4)
        export PARAM_PREFIX=$(grep -o '"param_prefix": "[^"]*"' "$state_file" | cut -d'"' -f4)
        export AWS_REGION=$(grep -o '"aws_region": "[^"]*"' "$state_file" | cut -d'"' -f4)
        
        log "INFO" "Loaded state:"
        log "INFO" "  - App Name: $APP_NAME"
        log "INFO" "  - Parameter Prefix: $PARAM_PREFIX"
        log "INFO" "  - AWS Region: $AWS_REGION"
    else
        log "ERROR" "No deployment state file found and no app name specified."
        log "ERROR" "Use --app-name or --prefix to specify what to delete."
        log "ERROR" "State file expected at: $state_file"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required permissions
    if ! aws ssm describe-parameters --max-items 1 &> /dev/null; then
        log "ERROR" "Insufficient permissions for Systems Manager Parameter Store operations."
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check passed"
}

# List parameters to be deleted
list_parameters_to_delete() {
    log "INFO" "Scanning for parameters to delete..."
    
    # Get list of parameters under the prefix
    local params=$(aws ssm describe-parameters \
        --parameter-filters "Key=Name,Option=BeginsWith,Values=${PARAM_PREFIX}" \
        --query 'Parameters[].Name' \
        --output text 2>/dev/null | wc -w)
    
    if [[ "$params" -eq 0 ]]; then
        log "WARN" "No parameters found with prefix: $PARAM_PREFIX"
        return 1
    fi
    
    log "INFO" "Found $params parameters to delete:"
    aws ssm describe-parameters \
        --parameter-filters "Key=Name,Option=BeginsWith,Values=${PARAM_PREFIX}" \
        --query 'Parameters[].[Name,Type,Description]' \
        --output table
    
    return 0
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log "WARN" "=============================================="
    log "WARN" "WARNING: DESTRUCTIVE OPERATION"
    log "WARN" "=============================================="
    log "WARN" "This will permanently delete ALL parameters"
    log "WARN" "under the prefix: $PARAM_PREFIX"
    log "WARN" ""
    log "WARN" "This action cannot be undone!"
    log "WARN" "=============================================="
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed deletion. Proceeding..."
}

# Delete parameters
delete_parameters() {
    log "INFO" "Deleting parameters..."
    
    # Get list of parameters to delete
    local param_names=$(aws ssm describe-parameters \
        --parameter-filters "Key=Name,Option=BeginsWith,Values=${PARAM_PREFIX}" \
        --query 'Parameters[].Name' \
        --output text 2>/dev/null)
    
    if [[ -z "$param_names" ]]; then
        log "INFO" "No parameters found to delete"
        return
    fi
    
    local deleted_count=0
    local failed_count=0
    
    for param_name in $param_names; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would delete parameter: $param_name"
            ((deleted_count++))
            continue
        fi
        
        if aws ssm delete-parameter --name "$param_name" &>> "$LOG_FILE"; then
            log "SUCCESS" "Deleted parameter: $param_name"
            ((deleted_count++))
        else
            log "ERROR" "Failed to delete parameter: $param_name"
            ((failed_count++))
        fi
        
        # Small delay to avoid rate limiting
        sleep 0.1
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Parameter deletion summary:"
        log "INFO" "  - Successfully deleted: $deleted_count"
        if [[ "$failed_count" -gt 0 ]]; then
            log "WARN" "  - Failed to delete: $failed_count"
        fi
    else
        log "INFO" "Would delete $deleted_count parameters"
    fi
}

# Delete configuration management script
delete_config_script() {
    local script_path="${SCRIPT_DIR}/config-manager.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$script_path" ]]; then
            log "INFO" "[DRY-RUN] Would delete configuration script: $script_path"
        fi
        return
    fi
    
    if [[ -f "$script_path" ]]; then
        rm -f "$script_path"
        log "SUCCESS" "Deleted configuration management script: $script_path"
    else
        log "INFO" "Configuration script not found (already deleted or not created)"
    fi
}

# Delete backup files
delete_backup_files() {
    if [[ "$DRY_RUN" == "true" ]]; then
        local backup_files=$(find "$SCRIPT_DIR" -name "config-backup-*.json" 2>/dev/null | wc -l)
        if [[ "$backup_files" -gt 0 ]]; then
            log "INFO" "[DRY-RUN] Would delete $backup_files backup files"
        fi
        return
    fi
    
    local deleted_backups=0
    for backup_file in "$SCRIPT_DIR"/config-backup-*.json; do
        if [[ -f "$backup_file" ]]; then
            rm -f "$backup_file"
            log "SUCCESS" "Deleted backup file: $(basename "$backup_file")"
            ((deleted_backups++))
        fi
    done
    
    if [[ "$deleted_backups" -eq 0 ]]; then
        log "INFO" "No backup files found to delete"
    else
        log "INFO" "Deleted $deleted_backups backup files"
    fi
}

# Delete deployment state
delete_deployment_state() {
    local state_file="${SCRIPT_DIR}/deployment-state.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$state_file" ]]; then
            log "INFO" "[DRY-RUN] Would delete deployment state file: $state_file"
        fi
        return
    fi
    
    if [[ -f "$state_file" ]]; then
        rm -f "$state_file"
        log "SUCCESS" "Deleted deployment state file: $state_file"
    else
        log "INFO" "Deployment state file not found (already deleted)"
    fi
}

# Validate cleanup
validate_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Skipping cleanup validation in dry-run mode"
        return
    fi
    
    log "INFO" "Validating cleanup..."
    
    # Check if any parameters still exist
    local remaining_params=$(aws ssm describe-parameters \
        --parameter-filters "Key=Name,Option=BeginsWith,Values=${PARAM_PREFIX}" \
        --query 'length(Parameters)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$remaining_params" -eq 0 ]]; then
        log "SUCCESS" "Cleanup validation passed: No parameters remaining"
    else
        log "WARN" "Cleanup validation warning: $remaining_params parameters still exist"
        log "WARN" "This may be expected if deletion failed for some parameters"
    fi
}

# Main destruction function
main() {
    log "INFO" "================================================"
    log "INFO" "AWS Parameter Store Configuration Management"
    log "INFO" "Destruction Script v1.0"
    log "INFO" "================================================"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY-RUN mode - no resources will be deleted"
    fi
    
    check_prerequisites
    load_deployment_state
    
    # List what will be deleted
    if ! list_parameters_to_delete; then
        log "INFO" "No parameters found to delete. Cleaning up local files only."
    else
        confirm_deletion
        delete_parameters
    fi
    
    # Clean up local files
    delete_config_script
    delete_backup_files
    delete_deployment_state
    
    validate_cleanup
    
    log "SUCCESS" "================================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "SUCCESS" "Dry-run completed successfully!"
        log "INFO" "No resources were actually deleted."
        log "INFO" "Run without --dry-run to perform actual deletion."
    else
        log "SUCCESS" "Destruction completed successfully!"
        log "INFO" "All resources have been removed."
    fi
    log "SUCCESS" "================================================"
    
    # Clean up log files if everything was successful and not in dry-run mode
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log "INFO" "Cleanup complete. Log file preserved at: $LOG_FILE"
        log "INFO" "You can safely delete the log file if no longer needed."
    fi
}

# Run main function
main "$@"
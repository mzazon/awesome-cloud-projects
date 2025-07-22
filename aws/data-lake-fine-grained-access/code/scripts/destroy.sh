#!/bin/bash

# Destroy script for AWS Lake Formation Fine-Grained Access Control
# This script removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

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
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Error handler
error_handler() {
    local line_number=$1
    log ERROR "Script failed at line $line_number"
    log ERROR "Check the log file: $LOG_FILE"
    log WARN "Some resources may not have been cleaned up. Review AWS console manually."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS Lake Formation Fine-Grained Access Control resources

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be destroyed without actually destroying
    -f, --force         Skip confirmation prompts (use with caution)
    -r, --region        AWS region (default: from deployment info or current AWS CLI region)
    --skip-prereq       Skip prerequisite checks
    --debug             Enable debug logging

ENVIRONMENT VARIABLES:
    AWS_REGION          AWS region resources are in
    FORCE               Skip confirmation (true/false)
    
EXAMPLES:
    $0                  # Destroy with confirmation prompts
    $0 --dry-run        # Show what would be destroyed
    $0 --force          # Destroy without confirmation (dangerous!)
    
WARNING: This will permanently delete all Lake Formation resources created by the deploy script.
EOF
}

# Prerequisites check
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    for tool in jq; do
        if ! command -v $tool &> /dev/null; then
            log ERROR "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    log INFO "Prerequisites check completed successfully"
}

# Load deployment information
load_deployment_info() {
    log INFO "Loading deployment information..."
    
    local deployment_file="${SCRIPT_DIR}/.deployment_info"
    
    if [ ! -f "$deployment_file" ]; then
        log WARN "Deployment info file not found: $deployment_file"
        log WARN "Will attempt to determine resource names from environment or defaults"
        
        # Fallback to environment variables or defaults
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export DATABASE_NAME=${DATABASE_NAME:-"sample_database"}
        export TABLE_NAME=${TABLE_NAME:-"customer_data"}
        
        # Try to find bucket from S3 list
        local bucket_list=$(aws s3 ls | grep "data-lake-fgac" | awk '{print $3}' | head -1)
        export DATA_LAKE_BUCKET=${DATA_LAKE_BUCKET:-$bucket_list}
        
        if [ -z "$DATA_LAKE_BUCKET" ]; then
            log ERROR "Could not determine S3 bucket name. Please set DATA_LAKE_BUCKET environment variable."
            exit 1
        fi
    else
        # Source the deployment info file
        source "$deployment_file"
        log INFO "Loaded deployment information from: $deployment_file"
    fi
    
    log INFO "Deployment variables:"
    log INFO "  AWS_REGION: ${AWS_REGION:-not set}"
    log INFO "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID:-not set}"
    log INFO "  DATA_LAKE_BUCKET: ${DATA_LAKE_BUCKET:-not set}"
    log INFO "  DATABASE_NAME: ${DATABASE_NAME:-not set}"
    log INFO "  TABLE_NAME: ${TABLE_NAME:-not set}"
    
    # Validate required variables
    if [ -z "${AWS_REGION:-}" ] || [ -z "${AWS_ACCOUNT_ID:-}" ] || [ -z "${DATA_LAKE_BUCKET:-}" ]; then
        log ERROR "Required deployment variables not found. Cannot proceed with cleanup."
        exit 1
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [ "$FORCE" = "true" ] || [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    echo
    log WARN "This will permanently delete the following resources:"
    log WARN "  - S3 Bucket: $DATA_LAKE_BUCKET (and all contents)"
    log WARN "  - Glue Database: $DATABASE_NAME"
    log WARN "  - Glue Table: $TABLE_NAME"
    log WARN "  - IAM Roles: DataAnalystRole, FinanceTeamRole, HRRole"
    log WARN "  - Lake Formation permissions and data filters"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log INFO "Destruction cancelled by user"
        exit 0
    fi
    
    log INFO "User confirmed destruction. Proceeding..."
}

# Remove Lake Formation permissions
remove_lake_formation_permissions() {
    log INFO "Removing Lake Formation permissions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would remove Lake Formation permissions from all roles"
        return 0
    fi
    
    # List of roles to clean up
    local roles=("DataAnalystRole" "FinanceTeamRole" "HRRole")
    
    for role in "${roles[@]}"; do
        local role_arn="arn:aws:iam::$AWS_ACCOUNT_ID:role/$role"
        
        # Try to revoke table permissions
        aws lakeformation revoke-permissions \
            --principal "DataLakePrincipalIdentifier=$role_arn" \
            --permissions "SELECT" \
            --resource '{
                "Table": {
                    "DatabaseName": "'$DATABASE_NAME'",
                    "Name": "'$TABLE_NAME'"
                }
            }' 2>/dev/null || log DEBUG "Failed to revoke table permissions for $role (may not exist)"
        
        # Try to revoke column permissions
        aws lakeformation revoke-permissions \
            --principal "DataLakePrincipalIdentifier=$role_arn" \
            --permissions "SELECT" \
            --resource '{
                "TableWithColumns": {
                    "DatabaseName": "'$DATABASE_NAME'",
                    "Name": "'$TABLE_NAME'",
                    "ColumnWildcard": {}
                }
            }' 2>/dev/null || log DEBUG "Failed to revoke column permissions for $role (may not exist)"
        
        log INFO "Attempted to revoke permissions for: $role"
    done
    
    log INFO "Lake Formation permissions removal completed"
}

# Remove data filters
remove_data_filters() {
    log INFO "Removing data filters..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would remove data filter: engineering-only-filter"
        return 0
    fi
    
    # Remove the engineering-only filter
    aws lakeformation delete-data-cells-filter \
        --table-catalog-id "$AWS_ACCOUNT_ID" \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" \
        --name "engineering-only-filter" 2>/dev/null || {
        log WARN "Failed to delete data filter 'engineering-only-filter' (may not exist)"
    }
    
    log INFO "Data filters removal completed"
}

# Remove Glue resources
remove_glue_resources() {
    log INFO "Removing Glue resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would remove Glue table: $TABLE_NAME"
        log INFO "[DRY RUN] Would remove Glue database: $DATABASE_NAME"
        return 0
    fi
    
    # Delete Glue table
    aws glue delete-table \
        --database-name "$DATABASE_NAME" \
        --name "$TABLE_NAME" 2>/dev/null || {
        log WARN "Failed to delete Glue table '$TABLE_NAME' (may not exist)"
    }
    
    # Wait a moment for table deletion to propagate
    sleep 2
    
    # Delete Glue database
    aws glue delete-database \
        --name "$DATABASE_NAME" 2>/dev/null || {
        log WARN "Failed to delete Glue database '$DATABASE_NAME' (may not exist)"
    }
    
    log INFO "Glue resources removal completed"
}

# Remove IAM roles
remove_iam_roles() {
    log INFO "Removing IAM roles..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would remove IAM roles: DataAnalystRole, FinanceTeamRole, HRRole"
        return 0
    fi
    
    local roles=("DataAnalystRole" "FinanceTeamRole" "HRRole")
    
    for role in "${roles[@]}"; do
        # First, detach any attached policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$role" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$attached_policies" ]; then
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy \
                    --role-name "$role" \
                    --policy-arn "$policy_arn" || {
                    log WARN "Failed to detach policy $policy_arn from role $role"
                }
            done
        fi
        
        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$role" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$inline_policies" ]; then
            for policy_name in $inline_policies; do
                aws iam delete-role-policy \
                    --role-name "$role" \
                    --policy-name "$policy_name" || {
                    log WARN "Failed to delete inline policy $policy_name from role $role"
                }
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$role" 2>/dev/null || {
            log WARN "Failed to delete IAM role '$role' (may not exist)"
        }
        
        log INFO "Attempted to delete IAM role: $role"
    done
    
    log INFO "IAM roles removal completed"
}

# Deregister S3 location and remove bucket
remove_s3_resources() {
    log INFO "Removing S3 resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would deregister S3 location: arn:aws:s3:::$DATA_LAKE_BUCKET"
        log INFO "[DRY RUN] Would delete S3 bucket: $DATA_LAKE_BUCKET (and all contents)"
        return 0
    fi
    
    # Deregister S3 location from Lake Formation
    aws lakeformation deregister-resource \
        --resource-arn "arn:aws:s3:::$DATA_LAKE_BUCKET" 2>/dev/null || {
        log WARN "Failed to deregister S3 location (may not be registered)"
    }
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$DATA_LAKE_BUCKET" &>/dev/null; then
        log WARN "S3 bucket '$DATA_LAKE_BUCKET' does not exist. Skipping deletion."
        return 0
    fi
    
    # Delete all objects and versions in the bucket
    log INFO "Deleting all objects in bucket: $DATA_LAKE_BUCKET"
    aws s3 rm "s3://$DATA_LAKE_BUCKET" --recursive || {
        log WARN "Failed to delete some objects in bucket $DATA_LAKE_BUCKET"
    }
    
    # Delete all object versions if versioning was enabled
    local versions=$(aws s3api list-object-versions \
        --bucket "$DATA_LAKE_BUCKET" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$versions" != "[]" ] && [ "$versions" != "" ]; then
        echo "$versions" | jq -r '.[] | "\(.Key) \(.VersionId)"' | while read -r key version_id; do
            aws s3api delete-object \
                --bucket "$DATA_LAKE_BUCKET" \
                --key "$key" \
                --version-id "$version_id" 2>/dev/null || {
                log DEBUG "Failed to delete version $version_id of object $key"
            }
        done
    fi
    
    # Delete delete markers
    local delete_markers=$(aws s3api list-object-versions \
        --bucket "$DATA_LAKE_BUCKET" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$delete_markers" != "[]" ] && [ "$delete_markers" != "" ]; then
        echo "$delete_markers" | jq -r '.[] | "\(.Key) \(.VersionId)"' | while read -r key version_id; do
            aws s3api delete-object \
                --bucket "$DATA_LAKE_BUCKET" \
                --key "$key" \
                --version-id "$version_id" 2>/dev/null || {
                log DEBUG "Failed to delete delete marker $version_id of object $key"
            }
        done
    fi
    
    # Delete the bucket
    aws s3 rb "s3://$DATA_LAKE_BUCKET" --force || {
        log ERROR "Failed to delete S3 bucket '$DATA_LAKE_BUCKET'"
        log ERROR "You may need to manually delete this bucket from the AWS Console"
    }
    
    log INFO "S3 resources removal completed"
}

# Clean up local files
cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove temporary directory if it exists
    local temp_dir_file="${SCRIPT_DIR}/.temp_dir"
    if [ -f "$temp_dir_file" ]; then
        local temp_dir=$(cat "$temp_dir_file" 2>/dev/null || echo "")
        if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
            rm -rf "$temp_dir" || log WARN "Failed to clean up temporary directory: $temp_dir"
        fi
        rm -f "$temp_dir_file"
    fi
    
    # Remove deployment info file
    local deployment_file="${SCRIPT_DIR}/.deployment_info"
    if [ -f "$deployment_file" ]; then
        rm -f "$deployment_file" || log WARN "Failed to remove deployment info file"
    fi
    
    log INFO "Local files cleanup completed"
}

# Validate cleanup
validate_cleanup() {
    log INFO "Validating cleanup..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would validate cleanup of all resources"
        return 0
    fi
    
    local cleanup_errors=0
    
    # Check if S3 bucket still exists
    if aws s3 ls "s3://$DATA_LAKE_BUCKET" &>/dev/null; then
        log ERROR "S3 bucket still exists: $DATA_LAKE_BUCKET"
        ((cleanup_errors++))
    fi
    
    # Check if Glue database still exists
    if aws glue get-database --name "$DATABASE_NAME" &>/dev/null; then
        log ERROR "Glue database still exists: $DATABASE_NAME"
        ((cleanup_errors++))
    fi
    
    # Check if IAM roles still exist
    for role in DataAnalystRole FinanceTeamRole HRRole; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            log ERROR "IAM role still exists: $role"
            ((cleanup_errors++))
        fi
    done
    
    if [ $cleanup_errors -eq 0 ]; then
        log INFO "All resources cleaned up successfully"
        return 0
    else
        log WARN "$cleanup_errors resources may not have been fully cleaned up"
        log WARN "Please check the AWS Console to verify complete cleanup"
        return 1
    fi
}

# Main destroy function
main() {
    log INFO "Starting Lake Formation Fine-Grained Access Control cleanup..."
    log INFO "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --skip-prereq)
                SKIP_PREREQ=true
                shift
                ;;
            --debug)
                set -x
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites unless skipped
    if [ "${SKIP_PREREQ:-false}" != "true" ]; then
        check_prerequisites
    fi
    
    # Load deployment information
    load_deployment_info
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN MODE - No resources will be destroyed"
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Execute cleanup steps in reverse order of creation
    remove_data_filters
    remove_lake_formation_permissions
    remove_iam_roles
    remove_glue_resources
    remove_s3_resources
    cleanup_local_files
    
    # Validate cleanup
    if [ "$DRY_RUN" != "true" ]; then
        validate_cleanup
    fi
    
    log INFO "Lake Formation Fine-Grained Access Control cleanup completed!"
    
    if [ "$DRY_RUN" != "true" ]; then
        log INFO ""
        log INFO "All Lake Formation resources have been cleaned up."
        log INFO "Please verify in the AWS Console that all resources are removed."
        log INFO ""
        log WARN "Note: Lake Formation settings may still retain some global configuration."
        log WARN "Review Lake Formation settings in the AWS Console if needed."
    fi
}

# Run main function
main "$@"
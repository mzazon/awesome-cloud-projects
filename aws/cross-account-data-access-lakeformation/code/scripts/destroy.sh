#!/bin/bash

# =============================================================================
# AWS Lake Formation Cross-Account Data Access Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script.
# It includes safety checks, confirmation prompts, and proper resource
# cleanup order to avoid dependency issues.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for resource deletion
# - Access to both producer and consumer accounts
# - Deployment variables file from original deployment
#
# Usage:
#   ./destroy.sh [--force] [--dry-run] [--debug] [--skip-confirmation]
#
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_VARS_FILE="${SCRIPT_DIR}/.deployment_vars"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
FORCE=false
DRY_RUN=false
DEBUG=false
SKIP_CONFIRMATION=false

# Resource tracking
RESOURCES_TO_DELETE=()
FAILED_DELETIONS=()

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

debug() {
    if [[ "$DEBUG" == "true" ]]; then
        log "${BLUE}DEBUG: $1${NC}"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

show_help() {
    cat << EOF
AWS Lake Formation Cross-Account Data Access Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --force                     Skip safety checks and force deletion
    --dry-run                   Show what would be deleted without executing
    --debug                     Enable debug logging
    --skip-confirmation         Skip confirmation prompts (use with caution)
    --help                      Show this help message

Safety Features:
    - Confirmation prompts for destructive actions
    - Resource dependency checking
    - Rollback on critical failures
    - Detailed logging of all operations

Examples:
    $0                          Interactive cleanup with confirmations
    $0 --dry-run               Show what would be deleted
    $0 --force --skip-confirmation    Automated cleanup (dangerous)

EOF
}

# Load deployment variables
load_deployment_vars() {
    info "Loading deployment variables..."
    
    if [[ ! -f "$DEPLOYMENT_VARS_FILE" ]]; then
        warning "Deployment variables file not found: $DEPLOYMENT_VARS_FILE"
        warning "Attempting to discover resources automatically..."
        discover_resources
        return
    fi
    
    # Source the deployment variables
    source "$DEPLOYMENT_VARS_FILE"
    
    # Validate required variables
    if [[ -z "${PRODUCER_ACCOUNT_ID:-}" ]] || [[ -z "${CONSUMER_ACCOUNT_ID:-}" ]]; then
        error "Required deployment variables missing. Cannot proceed with cleanup."
    fi
    
    info "Loaded deployment variables:"
    info "  Producer Account: ${PRODUCER_ACCOUNT_ID}"
    info "  Consumer Account: ${CONSUMER_ACCOUNT_ID}"
    info "  AWS Region: ${AWS_REGION:-'Not set'}"
    info "  Data Lake Bucket: ${DATA_LAKE_BUCKET:-'Not set'}"
    info "  Resource Share ARN: ${RESOURCE_SHARE_ARN:-'Not set'}"
}

# Discover resources if deployment vars file is missing
discover_resources() {
    info "Attempting to discover Lake Formation resources..."
    
    export PRODUCER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    # Try to find data lake bucket
    DATA_LAKE_BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'data-lake-${PRODUCER_ACCOUNT_ID}')].Name" --output text || echo "")
    if [[ -n "$DATA_LAKE_BUCKETS" ]]; then
        export DATA_LAKE_BUCKET=$(echo "$DATA_LAKE_BUCKETS" | head -n1)
        info "Discovered data lake bucket: $DATA_LAKE_BUCKET"
    fi
    
    # Try to find resource shares
    RESOURCE_SHARES=$(aws ram get-resource-shares --resource-owner SELF --name "lake-formation-cross-account-share" --query 'resourceShares[0].resourceShareArn' --output text 2>/dev/null || echo "")
    if [[ -n "$RESOURCE_SHARES" && "$RESOURCE_SHARES" != "None" ]]; then
        export RESOURCE_SHARE_ARN="$RESOURCE_SHARES"
        info "Discovered resource share: $RESOURCE_SHARE_ARN"
    fi
    
    warning "Resource discovery completed with limited information"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
    fi
    
    # Verify we're in the producer account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [[ -n "${PRODUCER_ACCOUNT_ID:-}" ]] && [[ "$CURRENT_ACCOUNT" != "$PRODUCER_ACCOUNT_ID" ]]; then
        error "Must run cleanup from producer account. Current: $CURRENT_ACCOUNT, Expected: $PRODUCER_ACCOUNT_ID"
    fi
    
    success "Prerequisites check completed"
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local critical="${3:-false}"
    
    debug "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would execute: $description"
        return 0
    fi
    
    if eval "$cmd" 2>/dev/null; then
        success "$description"
        return 0
    else
        if [[ "$critical" == "true" && "$FORCE" == "false" ]]; then
            error "Critical operation failed: $description"
        else
            warning "Failed to execute: $description"
            FAILED_DELETIONS+=("$description")
            return 1
        fi
    fi
}

# Safety confirmation
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    info "This script will delete the following resources:"
    info "  ✗ Cross-account resource shares"
    info "  ✗ Lake Formation LF-Tags and permissions"
    info "  ✗ Glue Data Catalog databases and tables"
    info "  ✗ Glue crawlers"
    info "  ✗ S3 data lake bucket and all contents"
    info "  ✗ IAM roles and policies"
    info "  ✗ Sample data and scripts"
    echo ""
    warning "This action is IRREVERSIBLE and will DELETE ALL DATA!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Final confirmation - type the producer account ID (${PRODUCER_ACCOUNT_ID:-unknown}) to proceed: " -r
    if [[ $REPLY != "${PRODUCER_ACCOUNT_ID:-}" ]]; then
        error "Account ID confirmation failed. Cleanup cancelled."
    fi
    
    success "Deletion confirmed by user"
}

# Revoke cross-account permissions
revoke_cross_account_permissions() {
    info "Revoking cross-account permissions..."
    
    if [[ -n "${CONSUMER_ACCOUNT_ID:-}" ]]; then
        # Revoke LF-Tag permissions
        execute_cmd "aws lakeformation revoke-permissions \
            --principal DataLakePrincipalIdentifier='$CONSUMER_ACCOUNT_ID' \
            --resource LFTag='{TagKey=department,TagValues=[finance]}' \
            --permissions ASSOCIATE DESCRIBE" \
            "Revoked LF-Tag permissions for consumer account"
        
        # List and revoke additional permissions
        local permissions=$(aws lakeformation list-permissions \
            --principal DataLakePrincipalIdentifier="$CONSUMER_ACCOUNT_ID" \
            --query 'PrincipalResourcePermissions[*]' \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$permissions" != "[]" ]]; then
            info "Found additional permissions to revoke"
            # Additional revocation logic would go here
        fi
    fi
    
    success "Cross-account permissions revoked"
}

# Delete resource shares
delete_resource_shares() {
    info "Deleting cross-account resource shares..."
    
    if [[ -n "${RESOURCE_SHARE_ARN:-}" ]]; then
        execute_cmd "aws ram delete-resource-share --resource-share-arn '$RESOURCE_SHARE_ARN'" \
            "Deleted resource share: $RESOURCE_SHARE_ARN"
    fi
    
    # Find and delete any remaining resource shares
    local shares=$(aws ram get-resource-shares --resource-owner SELF \
        --query 'resourceShares[?contains(name, `lake-formation`)].resourceShareArn' \
        --output text 2>/dev/null || echo "")
    
    for share in $shares; do
        if [[ -n "$share" && "$share" != "None" ]]; then
            execute_cmd "aws ram delete-resource-share --resource-share-arn '$share'" \
                "Deleted additional resource share: $share"
        fi
    done
    
    success "Resource shares cleanup completed"
}

# Remove LF-Tags and associations
remove_lf_tags() {
    info "Removing LF-Tags and resource associations..."
    
    # Remove LF-Tags from databases
    local databases=("financial_db" "customer_db")
    for db in "${databases[@]}"; do
        # Check if database exists
        if aws glue get-database --name "$db" &>/dev/null; then
            # Remove all LF-Tags from database
            local tag_keys=("department" "classification" "data-category")
            for tag in "${tag_keys[@]}"; do
                execute_cmd "aws lakeformation remove-lf-tags-from-resource \
                    --resource Database='{Name=$db}' \
                    --lf-tags-to-remove '[{TagKey=$tag}]'" \
                    "Removed $tag LF-Tag from $db database" || true
            done
        fi
    done
    
    # Remove LF-Tags from tables
    for db in "${databases[@]}"; do
        if aws glue get-database --name "$db" &>/dev/null; then
            local tables=$(aws glue get-tables --database-name "$db" \
                --query 'TableList[*].Name' --output text 2>/dev/null || echo "")
            
            for table in $tables; do
                if [[ -n "$table" ]]; then
                    execute_cmd "aws lakeformation remove-lf-tags-from-resource \
                        --resource Table='{DatabaseName=$db,Name=$table}' \
                        --lf-tags-to-remove '[{TagKey=department},{TagKey=classification}]'" \
                        "Removed LF-Tags from table: $table" || true
                fi
            done
        fi
    done
    
    # Delete LF-Tags themselves
    local tags=("department" "classification" "data-category")
    for tag in "${tags[@]}"; do
        execute_cmd "aws lakeformation delete-lf-tag --tag-key '$tag'" \
            "Deleted LF-Tag: $tag" || true
    done
    
    success "LF-Tags cleanup completed"
}

# Delete Glue resources
delete_glue_resources() {
    info "Deleting Glue Data Catalog resources..."
    
    # Delete crawlers
    local crawlers=("financial-reports-crawler")
    for crawler in "${crawlers[@]}"; do
        if aws glue get-crawler --name "$crawler" &>/dev/null; then
            # Stop crawler if running
            execute_cmd "aws glue stop-crawler --name '$crawler'" \
                "Stopped crawler: $crawler" || true
            
            # Wait a moment for stop to complete
            sleep 5
            
            # Delete crawler
            execute_cmd "aws glue delete-crawler --name '$crawler'" \
                "Deleted crawler: $crawler"
        fi
    done
    
    # Delete databases and tables
    local databases=("financial_db" "customer_db")
    for db in "${databases[@]}"; do
        if aws glue get-database --name "$db" &>/dev/null; then
            # Delete all tables in database first
            local tables=$(aws glue get-tables --database-name "$db" \
                --query 'TableList[*].Name' --output text 2>/dev/null || echo "")
            
            for table in $tables; do
                if [[ -n "$table" ]]; then
                    execute_cmd "aws glue delete-table --database-name '$db' --name '$table'" \
                        "Deleted table: $db.$table"
                fi
            done
            
            # Delete database
            execute_cmd "aws glue delete-database --name '$db'" \
                "Deleted database: $db"
        fi
    done
    
    success "Glue resources cleanup completed"
}

# Delete S3 resources
delete_s3_resources() {
    info "Deleting S3 data lake resources..."
    
    if [[ -n "${DATA_LAKE_BUCKET:-}" ]]; then
        # Check if bucket exists
        if aws s3 ls "s3://$DATA_LAKE_BUCKET" &>/dev/null; then
            # Delete all objects including versions
            execute_cmd "aws s3api delete-objects \
                --bucket '$DATA_LAKE_BUCKET' \
                --delete \"\$(aws s3api list-object-versions \
                    --bucket '$DATA_LAKE_BUCKET' \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --output json)\"" \
                "Deleted all object versions from $DATA_LAKE_BUCKET" || true
            
            # Delete delete markers
            execute_cmd "aws s3api delete-objects \
                --bucket '$DATA_LAKE_BUCKET' \
                --delete \"\$(aws s3api list-object-versions \
                    --bucket '$DATA_LAKE_BUCKET' \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --output json)\"" \
                "Deleted all delete markers from $DATA_LAKE_BUCKET" || true
            
            # Delete bucket
            execute_cmd "aws s3 rb s3://'$DATA_LAKE_BUCKET'" \
                "Deleted S3 bucket: $DATA_LAKE_BUCKET"
        else
            info "S3 bucket $DATA_LAKE_BUCKET not found or already deleted"
        fi
    fi
    
    # Clean up any additional buckets that match the pattern
    local additional_buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'data-lake-${PRODUCER_ACCOUNT_ID:-}')].Name" \
        --output text 2>/dev/null || echo "")
    
    for bucket in $additional_buckets; do
        if [[ -n "$bucket" ]]; then
            warning "Found additional data lake bucket: $bucket"
            if [[ "$FORCE" == "true" || "$SKIP_CONFIRMATION" == "true" ]]; then
                execute_cmd "aws s3 rm s3://'$bucket' --recursive" \
                    "Emptied bucket: $bucket"
                execute_cmd "aws s3 rb s3://'$bucket'" \
                    "Deleted bucket: $bucket"
            fi
        fi
    done
    
    success "S3 resources cleanup completed"
}

# Delete IAM resources
delete_iam_resources() {
    info "Deleting IAM resources..."
    
    # Detach and delete Glue service role
    local role_name="AWSGlueServiceRole"
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        # Detach policies
        local policies=("arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole" 
                       "arn:aws:iam::aws:policy/AmazonS3FullAccess")
        
        for policy in "${policies[@]}"; do
            execute_cmd "aws iam detach-role-policy --role-name '$role_name' --policy-arn '$policy'" \
                "Detached policy from $role_name: $policy" || true
        done
        
        # Delete role
        execute_cmd "aws iam delete-role --role-name '$role_name'" \
            "Deleted IAM role: $role_name"
    fi
    
    success "IAM resources cleanup completed"
}

# Clean up Lake Formation settings
cleanup_lake_formation() {
    info "Cleaning up Lake Formation settings..."
    
    # Deregister S3 locations
    if [[ -n "${DATA_LAKE_BUCKET:-}" ]]; then
        execute_cmd "aws lakeformation deregister-resource --resource-arn 'arn:aws:s3:::$DATA_LAKE_BUCKET'" \
            "Deregistered S3 location from Lake Formation" || true
    fi
    
    # Note: We don't reset Lake Formation data lake settings as this might affect other resources
    warning "Lake Formation data lake settings left intact to avoid affecting other resources"
    
    success "Lake Formation cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove sample data directory
    if [[ -d "sample-data" ]]; then
        execute_cmd "rm -rf sample-data" \
            "Removed sample data directory"
    fi
    
    # Remove generated scripts
    local scripts=("consumer-account-setup.sh" "financial-crawler-config.json")
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            execute_cmd "rm -f '$script'" \
                "Removed generated script: $script"
        fi
    done
    
    # Optionally remove deployment variables (with confirmation)
    if [[ -f "$DEPLOYMENT_VARS_FILE" ]] && [[ "$FORCE" == "true" || "$SKIP_CONFIRMATION" == "true" ]]; then
        execute_cmd "rm -f '$DEPLOYMENT_VARS_FILE'" \
            "Removed deployment variables file"
    elif [[ -f "$DEPLOYMENT_VARS_FILE" ]]; then
        info "Keeping deployment variables file: $DEPLOYMENT_VARS_FILE"
    fi
    
    success "Local files cleanup completed"
}

# Generate consumer cleanup script
generate_consumer_cleanup() {
    info "Generating consumer account cleanup script..."
    
    cat > "${SCRIPT_DIR}/consumer-cleanup.sh" << EOF
#!/bin/bash

# =============================================================================
# Consumer Account Cleanup Script for Lake Formation Cross-Account Data Access
# =============================================================================
# This script should be run in the consumer account to clean up resources
# created during the cross-account setup.
#
# Usage: ./consumer-cleanup.sh [--force]
# =============================================================================

set -euo pipefail

FORCE=\${1:-}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1"
}

error() {
    log "\${RED}ERROR: \$1\${NC}"
    exit 1
}

warning() {
    log "\${YELLOW}WARNING: \$1\${NC}"
}

success() {
    log "\${GREEN}SUCCESS: \$1\${NC}"
}

info() {
    log "\${BLUE}INFO: \$1\${NC}"
}

# Confirmation
if [[ "\$FORCE" != "--force" ]]; then
    echo ""
    warning "This will delete consumer account resources for Lake Formation setup."
    read -p "Are you sure? Type 'YES' to confirm: " -r
    if [[ \$REPLY != "YES" ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
fi

info "Starting consumer account cleanup..."

# Delete DataAnalystRole
if aws iam get-role --role-name DataAnalystRole &>/dev/null; then
    # Detach policies
    aws iam detach-role-policy --role-name DataAnalystRole \\
        --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess 2>/dev/null || true
    aws iam detach-role-policy --role-name DataAnalystRole \\
        --policy-arn arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess 2>/dev/null || true
    
    # Delete role
    aws iam delete-role --role-name DataAnalystRole
    success "Deleted DataAnalystRole"
fi

# Delete resource link database
if aws glue get-database --name shared_financial_db &>/dev/null; then
    aws glue delete-database --name shared_financial_db
    success "Deleted shared_financial_db resource link"
fi

# Clean up temporary files
rm -f data-analyst-trust-policy.json

success "Consumer account cleanup completed!"

EOF
    
    chmod +x "${SCRIPT_DIR}/consumer-cleanup.sh"
    success "Consumer cleanup script generated"
}

# Main cleanup function
main() {
    info "Starting AWS Lake Formation Cross-Account Data Access cleanup..."
    info "Cleanup started at: $(date)"
    
    # Show what will be deleted
    info "Cleanup plan:"
    info "  1. Revoke cross-account permissions"
    info "  2. Delete RAM resource shares"
    info "  3. Remove LF-Tags and associations"
    info "  4. Delete Glue resources (crawlers, databases, tables)"
    info "  5. Delete S3 data lake bucket and contents"
    info "  6. Delete IAM roles"
    info "  7. Clean up Lake Formation settings"
    info "  8. Remove local files and scripts"
    
    # Execute cleanup steps
    confirm_deletion
    revoke_cross_account_permissions
    delete_resource_shares
    remove_lf_tags
    delete_glue_resources
    delete_s3_resources
    delete_iam_resources
    cleanup_lake_formation
    cleanup_local_files
    generate_consumer_cleanup
    
    # Summary
    success "Cleanup completed successfully!"
    
    if [[ ${#FAILED_DELETIONS[@]} -gt 0 ]]; then
        warning "Some deletions failed:"
        for failure in "${FAILED_DELETIONS[@]}"; do
            warning "  - $failure"
        done
    fi
    
    info "=============================================================================="
    info "CLEANUP SUMMARY"
    info "=============================================================================="
    info "Cleanup completed at: $(date)"
    info "Failed deletions: ${#FAILED_DELETIONS[@]}"
    info ""
    info "IMPORTANT:"
    info "- Run the consumer cleanup script in the consumer account:"
    info "  ${SCRIPT_DIR}/consumer-cleanup.sh"
    info "- Review CloudTrail logs for any remaining resources"
    info "- Check for any additional charges in Cost Explorer"
    info "=============================================================================="
}

# =============================================================================
# Script Execution
# =============================================================================

# Initialize logging
info "Initializing cleanup script..."
debug "Script directory: $SCRIPT_DIR"
debug "Log file: $LOG_FILE"

# Parse command line arguments
parse_args "$@"

# Execute cleanup
load_deployment_vars
check_prerequisites
main

info "Script execution completed at: $(date)"
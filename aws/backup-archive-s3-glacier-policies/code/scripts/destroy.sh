#!/bin/bash

# Destroy script for Backup and Archive Strategies with S3 Glacier and Lifecycle Policies
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_DIR="${SCRIPT_DIR}/../config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Safety confirmation
confirm_destruction() {
    echo ""
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will permanently delete ALL resources created by the deployment."
    log_warning "This includes:"
    log_warning "  - S3 bucket and ALL objects (including archived data)"
    log_warning "  - IAM roles and policies"
    log_warning "  - CloudWatch alarms and log groups"
    log_warning "  - Glacier data retrieval policies"
    log_warning "  - All configuration files"
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set - skipping confirmation"
        return 0
    fi
    
    read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_DIR}/deployment.env" ]]; then
        log_error "Deployment configuration not found: ${CONFIG_DIR}/deployment.env"
        log_error "Please ensure the deployment script was run successfully."
        exit 1
    fi
    
    # Source the deployment environment variables
    set -a  # automatically export all variables
    source "${CONFIG_DIR}/deployment.env"
    set +a  # stop automatically exporting
    
    log_info "Loaded deployment configuration from: ${CONFIG_DIR}/deployment.env"
    log_info "Bucket to delete: $BACKUP_BUCKET_NAME"
    log_info "IAM Role to delete: $IAM_ROLE_NAME"
    log_info "CloudWatch Alarm to delete: $CLOUDWATCH_ALARM_NAME"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Verify we're in the correct AWS account
    local current_account_id
    current_account_id=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ "$current_account_id" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "AWS Account ID mismatch!"
        log_error "Current account: $current_account_id"
        log_error "Expected account: $AWS_ACCOUNT_ID"
        log_error "Please ensure you're authenticated to the correct AWS account."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Delete S3 bucket and all contents
delete_s3_bucket() {
    log_info "Deleting S3 bucket and all contents: $BACKUP_BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BACKUP_BUCKET_NAME" 2>/dev/null; then
        log_warning "Bucket $BACKUP_BUCKET_NAME does not exist or is not accessible"
        return 0
    fi
    
    # Calculate total objects for progress tracking
    local total_objects
    total_objects=$(aws s3api list-objects-v2 \
        --bucket "$BACKUP_BUCKET_NAME" \
        --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    local total_versions
    total_versions=$(aws s3api list-object-versions \
        --bucket "$BACKUP_BUCKET_NAME" \
        --query 'length(Versions)' --output text 2>/dev/null || echo "0")
    
    log_info "Found $total_objects objects and $total_versions versions to delete"
    
    # Check for objects in Glacier/Deep Archive that might incur early deletion fees
    local glacier_objects
    glacier_objects=$(aws s3api list-objects-v2 \
        --bucket "$BACKUP_BUCKET_NAME" \
        --query 'Contents[?StorageClass==`GLACIER` || StorageClass==`DEEP_ARCHIVE`]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$glacier_objects" && "$glacier_objects" != "None" ]]; then
        log_warning "Found objects in Glacier/Deep Archive storage classes"
        log_warning "Deleting these objects may incur early deletion charges"
        log_warning "Consider the cost implications before proceeding"
        
        if [[ "${FORCE_DESTROY:-}" != "true" ]]; then
            read -p "Continue with deletion? (y/N): " glacier_confirm
            if [[ "$glacier_confirm" != "y" && "$glacier_confirm" != "Y" ]]; then
                log_info "S3 bucket deletion cancelled by user."
                return 0
            fi
        fi
    fi
    
    # Remove all current objects
    if [[ "$total_objects" -gt 0 ]]; then
        log_info "Deleting current objects..."
        aws s3 rm "s3://$BACKUP_BUCKET_NAME" --recursive
    fi
    
    # Remove all object versions and delete markers
    if [[ "$total_versions" -gt 0 ]]; then
        log_info "Deleting object versions and delete markers..."
        
        # Get and delete all versions
        aws s3api list-object-versions \
            --bucket "$BACKUP_BUCKET_NAME" \
            --output json \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' | \
        jq -r '.[] | select(.Key != null) | "--key \(.Key) --version-id \(.VersionId)"' | \
        while read -r delete_args; do
            if [[ -n "$delete_args" ]]; then
                eval "aws s3api delete-object --bucket $BACKUP_BUCKET_NAME $delete_args" || true
            fi
        done
        
        # Get and delete all delete markers
        aws s3api list-object-versions \
            --bucket "$BACKUP_BUCKET_NAME" \
            --output json \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' | \
        jq -r '.[] | select(.Key != null) | "--key \(.Key) --version-id \(.VersionId)"' | \
        while read -r delete_args; do
            if [[ -n "$delete_args" ]]; then
                eval "aws s3api delete-object --bucket $BACKUP_BUCKET_NAME $delete_args" || true
            fi
        done
    fi
    
    # Remove bucket lifecycle configuration
    log_info "Removing bucket lifecycle configuration..."
    aws s3api delete-bucket-lifecycle --bucket "$BACKUP_BUCKET_NAME" 2>/dev/null || true
    
    # Wait a moment for deletions to propagate
    sleep 5
    
    # Delete the bucket
    log_info "Deleting bucket: $BACKUP_BUCKET_NAME"
    aws s3api delete-bucket --bucket "$BACKUP_BUCKET_NAME"
    
    log_success "S3 bucket deleted: $BACKUP_BUCKET_NAME"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME" --query 'MetricAlarms[0]' --output text &>/dev/null; then
        log_info "Deleting CloudWatch alarm: $CLOUDWATCH_ALARM_NAME"
        aws cloudwatch delete-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME"
        log_success "CloudWatch alarm deleted: $CLOUDWATCH_ALARM_NAME"
    else
        log_warning "CloudWatch alarm not found: $CLOUDWATCH_ALARM_NAME"
    fi
    
    # Delete log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/s3/lifecycle-transitions" --query 'logGroups[0]' --output text &>/dev/null; then
        log_info "Deleting log group: /aws/s3/lifecycle-transitions"
        aws logs delete-log-group --log-group-name /aws/s3/lifecycle-transitions
        log_success "Log group deleted: /aws/s3/lifecycle-transitions"
    else
        log_warning "Log group not found: /aws/s3/lifecycle-transitions"
    fi
}

# Delete IAM role
delete_iam_role() {
    log_info "Deleting IAM role: $IAM_ROLE_NAME"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log_warning "IAM role not found: $IAM_ROLE_NAME"
        return 0
    fi
    
    # List and detach all attached policies
    log_info "Detaching policies from IAM role..."
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies \
        --role-name "$IAM_ROLE_NAME" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text)
    
    if [[ -n "$attached_policies" ]]; then
        for policy_arn in $attached_policies; do
            log_info "Detaching policy: $policy_arn"
            aws iam detach-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-arn "$policy_arn"
        done
    fi
    
    # List and delete all inline policies
    local inline_policies
    inline_policies=$(aws iam list-role-policies \
        --role-name "$IAM_ROLE_NAME" \
        --query 'PolicyNames' \
        --output text)
    
    if [[ -n "$inline_policies" && "$inline_policies" != "None" ]]; then
        for policy_name in $inline_policies; do
            log_info "Deleting inline policy: $policy_name"
            aws iam delete-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-name "$policy_name"
        done
    fi
    
    # Delete the role
    aws iam delete-role --role-name "$IAM_ROLE_NAME"
    log_success "IAM role deleted: $IAM_ROLE_NAME"
}

# Reset Glacier data retrieval policy
reset_glacier_policy() {
    log_info "Resetting Glacier data retrieval policy to default..."
    
    # Create default (no restrictions) retrieval policy
    cat > "/tmp/default-retrieval-policy.json" << 'EOF'
{
  "Rules": []
}
EOF
    
    # Apply default retrieval policy
    aws glacier set-data-retrieval-policy \
        --account-id "$AWS_ACCOUNT_ID" \
        --policy file:///tmp/default-retrieval-policy.json
    
    # Clean up temporary file
    rm -f /tmp/default-retrieval-policy.json
    
    log_success "Glacier data retrieval policy reset to default"
}

# Clean up local configuration files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ -d "$CONFIG_DIR" ]]; then
        local files_to_remove=(
            "deployment.env"
            "lifecycle-policy.json"
            "glacier-trust-policy.json"
            "data-retrieval-policy.json"
            "backup-automation.sh"
            "compliance-report.sh"
        )
        
        for file in "${files_to_remove[@]}"; do
            if [[ -f "${CONFIG_DIR}/$file" ]]; then
                log_info "Removing: ${CONFIG_DIR}/$file"
                rm -f "${CONFIG_DIR}/$file"
            fi
        done
        
        # Remove sample data directory
        if [[ -d "${CONFIG_DIR}/sample-data" ]]; then
            log_info "Removing sample data directory"
            rm -rf "${CONFIG_DIR}/sample-data"
        fi
        
        # Remove config directory if empty
        if [[ -z "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ]]; then
            log_info "Removing empty config directory"
            rmdir "$CONFIG_DIR"
        fi
        
        log_success "Local configuration files cleaned up"
    else
        log_warning "Config directory not found: $CONFIG_DIR"
    fi
}

# Validate destruction
validate_destruction() {
    log_info "Validating resource destruction..."
    
    local validation_errors=0
    
    # Check if S3 bucket still exists
    if aws s3api head-bucket --bucket "$BACKUP_BUCKET_NAME" 2>/dev/null; then
        log_error "S3 bucket still exists: $BACKUP_BUCKET_NAME"
        ((validation_errors++))
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" 2>/dev/null; then
        log_error "IAM role still exists: $IAM_ROLE_NAME"
        ((validation_errors++))
    fi
    
    # Check if CloudWatch alarm still exists
    if aws cloudwatch describe-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q .; then
        log_error "CloudWatch alarm still exists: $CLOUDWATCH_ALARM_NAME"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All resources successfully destroyed"
    else
        log_error "Some resources may not have been properly destroyed ($validation_errors errors)"
        log_error "Please check AWS console and manually remove any remaining resources"
        return 1
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted by user"
    log_warning "Some resources may be partially deleted"
    log_warning "Please run the script again or manually check AWS console"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Main destruction function
main() {
    log_info "Starting destruction of Backup and Archive Strategies resources"
    log_info "Destruction log: $LOG_FILE"
    
    confirm_destruction
    load_deployment_config
    check_prerequisites
    
    # Start destruction process
    log_info "Beginning resource destruction..."
    
    # Delete resources in reverse order of creation
    delete_s3_bucket
    delete_cloudwatch_resources
    delete_iam_role
    reset_glacier_policy
    cleanup_local_files
    
    # Validate destruction
    validate_destruction
    
    # Display destruction summary
    echo ""
    log_success "=== DESTRUCTION COMPLETED SUCCESSFULLY ==="
    echo ""
    log_info "Destruction Summary:"
    log_info "  ✅ S3 bucket deleted: $BACKUP_BUCKET_NAME"
    log_info "  ✅ IAM role deleted: $IAM_ROLE_NAME"
    log_info "  ✅ CloudWatch alarm deleted: $CLOUDWATCH_ALARM_NAME"
    log_info "  ✅ Glacier retrieval policy reset"
    log_info "  ✅ Local configuration files cleaned"
    echo ""
    log_info "All resources have been successfully destroyed."
    log_warning "Note: Some Glacier storage charges may continue to appear on your bill"
    log_warning "for a short period due to AWS billing processing delays."
    echo ""
    
    # Cost savings information
    log_info "Cost Impact:"
    log_info "  - S3 storage charges: Stopped immediately"
    log_info "  - CloudWatch alarm charges: Stopped immediately"
    log_info "  - Glacier early deletion fees: May apply if objects were deleted before minimum duration"
    echo ""
}

# Run main function with all arguments
main "$@"
#!/bin/bash

# CloudFormation Nested Stacks Cleanup Script
# This script safely removes all nested stack infrastructure and associated resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message"
            fi
            ;;
    esac
}

# Help function
show_help() {
    cat << EOF
CloudFormation Nested Stacks Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s, --stack-name STACK          Root stack name to delete [required]
    -b, --bucket BUCKET             S3 bucket name for templates [auto-detected if not provided]
    -r, --region REGION             AWS region [default: current AWS CLI region]
    -f, --force                     Skip confirmation prompts (DANGEROUS!)
    -k, --keep-bucket               Keep S3 template bucket after cleanup
    -d, --dry-run                   Show what would be deleted without actually deleting
    -v, --verbose                   Enable verbose logging
    -h, --help                      Show this help message

EXAMPLES:
    $0 -s nested-infrastructure-abc123     # Delete specific stack with confirmation
    $0 -s my-stack -f                      # Delete without confirmation (dangerous)
    $0 -s my-stack -k                      # Delete stack but keep S3 bucket
    $0 -s my-stack -d                      # Dry run to see what would be deleted

WARNING:
    This script will permanently delete all infrastructure resources.
    Use with caution, especially in production environments.

EOF
}

# Default values
ROOT_STACK_NAME=""
TEMPLATE_BUCKET_NAME=""
AWS_REGION=""
FORCE=false
KEEP_BUCKET=false
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--stack-name)
            ROOT_STACK_NAME="$2"
            shift 2
            ;;
        -b|--bucket)
            TEMPLATE_BUCKET_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-bucket)
            KEEP_BUCKET=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            DEBUG=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ROOT_STACK_NAME" ]]; then
    log "ERROR" "Stack name is required. Use -s or --stack-name option."
    show_help
    exit 1
fi

log "INFO" "Starting CloudFormation nested stacks cleanup"
log "INFO" "Stack Name: $ROOT_STACK_NAME"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured or invalid. Please run 'aws configure'"
        exit 1
    fi
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log "ERROR" "AWS region not set. Please set it with 'aws configure' or use -r option"
            exit 1
        fi
    fi
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Check required permissions (basic check)
    log "DEBUG" "Checking CloudFormation permissions..."
    if ! aws cloudformation list-stacks --max-items 1 &> /dev/null; then
        log "ERROR" "Insufficient CloudFormation permissions"
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Check if stack exists
check_stack_exists() {
    log "INFO" "Checking if stack exists..."
    
    if ! aws cloudformation describe-stacks --stack-name "$ROOT_STACK_NAME" &> /dev/null; then
        log "ERROR" "Stack '$ROOT_STACK_NAME' does not exist or is not accessible"
        exit 1
    fi
    
    log "INFO" "Stack '$ROOT_STACK_NAME' found"
}

# Get stack information
get_stack_info() {
    log "INFO" "Gathering stack information..."
    
    # Get stack details
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'Stacks[0].StackStatus' --output text)
    
    STACK_CREATION_TIME=$(aws cloudformation describe-stacks \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'Stacks[0].CreationTime' --output text)
    
    log "INFO" "Stack Status: $STACK_STATUS"
    log "INFO" "Created: $STACK_CREATION_TIME"
    
    # Try to auto-detect template bucket if not provided
    if [[ -z "$TEMPLATE_BUCKET_NAME" ]]; then
        TEMPLATE_BUCKET_NAME=$(aws cloudformation describe-stacks \
            --stack-name "$ROOT_STACK_NAME" \
            --query 'Stacks[0].Parameters[?ParameterKey==`TemplateBucketName`].ParameterValue' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$TEMPLATE_BUCKET_NAME" && "$TEMPLATE_BUCKET_NAME" != "None" ]]; then
            log "INFO" "Auto-detected template bucket: $TEMPLATE_BUCKET_NAME"
        fi
    fi
    
    # Get nested stacks
    log "DEBUG" "Identifying nested stacks..."
    NESTED_STACKS=$(aws cloudformation list-stack-resources \
        --stack-name "$ROOT_STACK_NAME" \
        --resource-type AWS::CloudFormation::Stack \
        --query 'StackResourceSummaries[].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$NESTED_STACKS" ]]; then
        log "INFO" "Found nested stacks:"
        for stack in $NESTED_STACKS; do
            log "INFO" "  - $stack"
        done
    fi
}

# Display deletion plan
show_deletion_plan() {
    log "INFO" "=== DELETION PLAN ==="
    log "INFO" "The following resources will be PERMANENTLY DELETED:"
    log "INFO" ""
    log "INFO" "Root Stack: $ROOT_STACK_NAME"
    
    if [[ -n "$NESTED_STACKS" ]]; then
        log "INFO" "Nested Stacks:"
        for stack in $NESTED_STACKS; do
            log "INFO" "  - $stack"
        done
    fi
    
    # List stack resources
    log "INFO" ""
    log "INFO" "Key Resources to be deleted:"
    aws cloudformation describe-stack-resources \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'StackResources[?ResourceType==`AWS::CloudFormation::Stack`].{Type:ResourceType,LogicalId:LogicalResourceId,PhysicalId:PhysicalResourceId}' \
        --output table 2>/dev/null || log "WARN" "Could not list nested stack resources"
    
    if [[ -n "$TEMPLATE_BUCKET_NAME" && "$KEEP_BUCKET" == "false" ]]; then
        log "INFO" ""
        log "INFO" "S3 Template Bucket: $TEMPLATE_BUCKET_NAME (will be deleted)"
    elif [[ -n "$TEMPLATE_BUCKET_NAME" && "$KEEP_BUCKET" == "true" ]]; then
        log "INFO" ""
        log "INFO" "S3 Template Bucket: $TEMPLATE_BUCKET_NAME (will be preserved)"
    fi
    
    log "INFO" ""
    log "WARN" "⚠️  WARNING: This action cannot be undone!"
    log "WARN" "⚠️  All data and configurations will be permanently lost!"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log "WARN" "Force mode enabled - skipping confirmation"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Dry run mode - no resources will be deleted"
        return
    fi
    
    echo ""
    read -p "Are you sure you want to delete all these resources? Type 'DELETE' to confirm: " -r
    echo ""
    
    if [[ $REPLY != "DELETE" ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    log "WARN" "Deletion confirmed. Starting cleanup process..."
}

# Check for deletion protection
check_deletion_protection() {
    log "INFO" "Checking for deletion protection..."
    
    # Check if any nested stacks have termination protection
    if [[ -n "$NESTED_STACKS" ]]; then
        for stack in $NESTED_STACKS; do
            local protection=$(aws cloudformation describe-stacks \
                --stack-name "$stack" \
                --query 'Stacks[0].EnableTerminationProtection' \
                --output text 2>/dev/null || echo "false")
            
            if [[ "$protection" == "true" ]]; then
                log "WARN" "Stack '$stack' has termination protection enabled"
                
                if [[ "$DRY_RUN" == "false" ]]; then
                    if [[ "$FORCE" == "true" ]]; then
                        log "INFO" "Disabling termination protection for '$stack'"
                        aws cloudformation update-termination-protection \
                            --stack-name "$stack" \
                            --no-enable-termination-protection
                    else
                        log "ERROR" "Cannot delete stack with termination protection. Use --force to override."
                        exit 1
                    fi
                fi
            fi
        done
    fi
    
    # Check root stack termination protection
    local root_protection=$(aws cloudformation describe-stacks \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'Stacks[0].EnableTerminationProtection' \
        --output text 2>/dev/null || echo "false")
    
    if [[ "$root_protection" == "true" ]]; then
        log "WARN" "Root stack '$ROOT_STACK_NAME' has termination protection enabled"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            if [[ "$FORCE" == "true" ]]; then
                log "INFO" "Disabling termination protection for root stack"
                aws cloudformation update-termination-protection \
                    --stack-name "$ROOT_STACK_NAME" \
                    --no-enable-termination-protection
            else
                log "ERROR" "Cannot delete stack with termination protection. Use --force to override."
                exit 1
            fi
        fi
    fi
}

# Delete CloudFormation stacks
delete_stacks() {
    log "INFO" "Deleting CloudFormation stacks..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would delete stack: $ROOT_STACK_NAME"
        log "INFO" "[DRY-RUN] This would automatically delete all nested stacks"
        return
    fi
    
    # Delete the root stack (this will cascade to nested stacks)
    log "INFO" "Initiating deletion of root stack: $ROOT_STACK_NAME"
    aws cloudformation delete-stack --stack-name "$ROOT_STACK_NAME"
    
    log "INFO" "Waiting for stack deletion to complete (this may take 10-20 minutes)..."
    
    # Wait for deletion with timeout
    local timeout=1800  # 30 minutes
    local elapsed=0
    local check_interval=30
    
    while true; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$ROOT_STACK_NAME" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [[ "$status" == "DELETE_COMPLETE" ]] || [[ "$status" == "DELETE_COMPLETE" ]]; then
            log "INFO" "✅ Stack deletion completed successfully"
            break
        elif [[ "$status" == "DELETE_FAILED" ]]; then
            log "ERROR" "Stack deletion failed. Check AWS Console for details."
            
            # Show failed resources
            log "ERROR" "Failed resources:"
            aws cloudformation describe-stack-events \
                --stack-name "$ROOT_STACK_NAME" \
                --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
                --output table 2>/dev/null || true
            
            exit 1
        else
            log "INFO" "Stack status: $status (elapsed: ${elapsed}s)"
        fi
        
        if [[ $elapsed -ge $timeout ]]; then
            log "ERROR" "Timeout waiting for stack deletion"
            exit 1
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
}

# Clean up S3 template bucket
cleanup_template_bucket() {
    if [[ -z "$TEMPLATE_BUCKET_NAME" ]]; then
        log "INFO" "No template bucket specified, skipping bucket cleanup"
        return
    fi
    
    if [[ "$KEEP_BUCKET" == "true" ]]; then
        log "INFO" "Keeping template bucket as requested: $TEMPLATE_BUCKET_NAME"
        return
    fi
    
    log "INFO" "Cleaning up S3 template bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would delete S3 bucket: $TEMPLATE_BUCKET_NAME"
        log "INFO" "[DRY-RUN] Would delete all objects in bucket first"
        return
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$TEMPLATE_BUCKET_NAME" &> /dev/null; then
        log "INFO" "Template bucket '$TEMPLATE_BUCKET_NAME' does not exist or already deleted"
        return
    fi
    
    # Delete all objects in bucket (including versions)
    log "INFO" "Deleting all objects from bucket: $TEMPLATE_BUCKET_NAME"
    aws s3 rm "s3://$TEMPLATE_BUCKET_NAME" --recursive
    
    # Delete all object versions if versioning is enabled
    aws s3api list-object-versions \
        --bucket "$TEMPLATE_BUCKET_NAME" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | while read key version; do
        if [[ -n "$key" && -n "$version" ]]; then
            aws s3api delete-object \
                --bucket "$TEMPLATE_BUCKET_NAME" \
                --key "$key" \
                --version-id "$version" 2>/dev/null || true
        fi
    done
    
    # Delete all delete markers
    aws s3api list-object-versions \
        --bucket "$TEMPLATE_BUCKET_NAME" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | while read key version; do
        if [[ -n "$key" && -n "$version" ]]; then
            aws s3api delete-object \
                --bucket "$TEMPLATE_BUCKET_NAME" \
                --key "$key" \
                --version-id "$version" 2>/dev/null || true
        fi
    done
    
    # Delete the bucket
    log "INFO" "Deleting bucket: $TEMPLATE_BUCKET_NAME"
    aws s3 rb "s3://$TEMPLATE_BUCKET_NAME"
    
    log "INFO" "✅ Template bucket deleted successfully"
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local template_dir="$(dirname "$0")/../templates"
    local summary_file="$(dirname "$0")/../deployment-summary.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would clean up local files:"
        if [[ -d "$template_dir" ]]; then
            log "INFO" "[DRY-RUN]   - Template directory: $template_dir"
        fi
        if [[ -f "$summary_file" ]]; then
            log "INFO" "[DRY-RUN]   - Deployment summary: $summary_file"
        fi
        return
    fi
    
    # Remove template files
    if [[ -d "$template_dir" ]]; then
        log "INFO" "Removing template directory: $template_dir"
        rm -rf "$template_dir"
    fi
    
    # Remove deployment summary
    if [[ -f "$summary_file" ]]; then
        log "INFO" "Removing deployment summary: $summary_file"
        rm -f "$summary_file"
    fi
    
    log "INFO" "✅ Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would verify cleanup completion"
        return
    fi
    
    # Check if stack still exists
    if aws cloudformation describe-stacks --stack-name "$ROOT_STACK_NAME" &> /dev/null; then
        log "WARN" "Stack '$ROOT_STACK_NAME' still exists"
        return
    fi
    
    # Check if bucket still exists (if we tried to delete it)
    if [[ -n "$TEMPLATE_BUCKET_NAME" && "$KEEP_BUCKET" == "false" ]]; then
        if aws s3 ls "s3://$TEMPLATE_BUCKET_NAME" &> /dev/null; then
            log "WARN" "Template bucket '$TEMPLATE_BUCKET_NAME' still exists"
            return
        fi
    fi
    
    log "INFO" "✅ Cleanup verification completed successfully"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "INFO" "Generating cleanup summary..."
    
    local summary_file="$(dirname "$0")/../cleanup-summary.json"
    
    cat > "$summary_file" << EOF
{
  "cleanup": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "stackName": "$ROOT_STACK_NAME",
    "templateBucket": "$TEMPLATE_BUCKET_NAME",
    "bucketKept": $KEEP_BUCKET,
    "region": "$AWS_REGION",
    "accountId": "$AWS_ACCOUNT_ID",
    "dryRun": $DRY_RUN,
    "force": $FORCE
  }
}
EOF
    
    log "INFO" "Cleanup summary saved to: $summary_file"
}

# Main execution
main() {
    log "INFO" "=== CloudFormation Nested Stacks Cleanup Started ==="
    
    check_prerequisites
    check_stack_exists
    get_stack_info
    show_deletion_plan
    confirm_deletion
    check_deletion_protection
    delete_stacks
    cleanup_template_bucket
    cleanup_local_files
    verify_cleanup
    generate_cleanup_summary
    
    log "INFO" "=== Cleanup Completed Successfully ==="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "All resources have been permanently deleted"
        log "INFO" "Stack '$ROOT_STACK_NAME' has been removed"
        
        if [[ -n "$TEMPLATE_BUCKET_NAME" ]]; then
            if [[ "$KEEP_BUCKET" == "true" ]]; then
                log "INFO" "Template bucket '$TEMPLATE_BUCKET_NAME' was preserved"
            else
                log "INFO" "Template bucket '$TEMPLATE_BUCKET_NAME' was deleted"
            fi
        fi
    else
        log "INFO" "This was a dry run - no resources were actually deleted"
        log "INFO" "Remove the --dry-run flag to perform actual deletion"
    fi
}

# Error handling
trap 'log "ERROR" "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
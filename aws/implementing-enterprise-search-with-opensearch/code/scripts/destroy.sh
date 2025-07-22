#!/bin/bash

# Cleanup script for Implementing Enterprise Search with OpenSearch Service
# This script safely destroys all resources created by deploy.sh

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in DRY-RUN mode - no resources will be destroyed"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log "Force delete mode enabled - will attempt to delete resources even if errors occur"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            log "Auto-confirmation enabled - will not prompt for confirmation"
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force] [--yes]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force: Continue deletion even if some resources fail to delete"
            echo "  --yes: Skip confirmation prompts"
            exit 1
            ;;
    esac
done

# Load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ -f "deployment-config.env" ]]; then
        source deployment-config.env
        log "Configuration loaded from deployment-config.env"
    else
        warning "deployment-config.env not found. You may need to provide configuration manually."
        
        # Prompt for manual configuration if needed
        if [[ -z "${DOMAIN_NAME:-}" ]]; then
            read -p "Enter OpenSearch domain name: " DOMAIN_NAME
        fi
        if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
            read -p "Enter S3 bucket name: " S3_BUCKET_NAME
        fi
        if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
            read -p "Enter Lambda function name: " LAMBDA_FUNCTION_NAME
        fi
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            read -p "Enter random suffix used in resource names: " RANDOM_SUFFIX
        fi
        if [[ -z "${AWS_REGION:-}" ]]; then
            export AWS_REGION=$(aws configure get region)
        fi
        if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        fi
    fi
    
    log "Configuration:"
    log "  Domain Name: ${DOMAIN_NAME:-Not set}"
    log "  S3 Bucket: ${S3_BUCKET_NAME:-Not set}"
    log "  Lambda Function: ${LAMBDA_FUNCTION_NAME:-Not set}"
    log "  AWS Region: ${AWS_REGION:-Not set}"
    log "  Random Suffix: ${RANDOM_SUFFIX:-Not set}"
}

# Prerequisites validation
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo
    warning "This will permanently delete the following resources:"
    echo "  - OpenSearch domain: ${DOMAIN_NAME:-Unknown}"
    echo "  - S3 bucket: ${S3_BUCKET_NAME:-Unknown}"
    echo "  - Lambda function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
    echo "  - IAM roles and policies"
    echo "  - CloudWatch dashboards and alarms"
    echo "  - CloudWatch log groups"
    echo
    warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Delete OpenSearch domain
delete_opensearch_domain() {
    log "Deleting OpenSearch domain..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete OpenSearch domain: ${DOMAIN_NAME:-Unknown}"
        return 0
    fi
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        warning "Domain name not specified, skipping OpenSearch domain deletion"
        return 0
    fi
    
    # Check if domain exists
    if aws opensearch describe-domain --domain-name "$DOMAIN_NAME" &> /dev/null; then
        log "Initiating OpenSearch domain deletion (this may take 10-15 minutes)..."
        
        if aws opensearch delete-domain --domain-name "$DOMAIN_NAME"; then
            log "OpenSearch domain deletion initiated: $DOMAIN_NAME"
            
            # Wait for deletion to complete (optional, can be skipped to speed up script)
            log "Waiting for domain deletion to complete..."
            while aws opensearch describe-domain --domain-name "$DOMAIN_NAME" &> /dev/null; do
                log "Domain still exists, waiting 30 seconds..."
                sleep 30
            done
            success "OpenSearch domain deleted: $DOMAIN_NAME"
        else
            if [[ "$FORCE_DELETE" == "true" ]]; then
                warning "Failed to delete OpenSearch domain, continuing due to --force flag"
            else
                error "Failed to delete OpenSearch domain: $DOMAIN_NAME"
                exit 1
            fi
        fi
    else
        warning "OpenSearch domain not found or already deleted: $DOMAIN_NAME"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete Lambda function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
        return 0
    fi
    
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        warning "Lambda function name not specified, skipping deletion"
        return 0
    fi
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        if aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"; then
            success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        else
            if [[ "$FORCE_DELETE" == "true" ]]; then
                warning "Failed to delete Lambda function, continuing due to --force flag"
            else
                error "Failed to delete Lambda function: $LAMBDA_FUNCTION_NAME"
                exit 1
            fi
        fi
    else
        warning "Lambda function not found or already deleted: $LAMBDA_FUNCTION_NAME"
    fi
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete IAM roles"
        return 0
    fi
    
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        warning "Random suffix not specified, cannot determine IAM role names"
        return 0
    fi
    
    # Delete Lambda IAM role
    local lambda_role_name="LambdaOpenSearchRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "$lambda_role_name" &> /dev/null; then
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "$lambda_role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || warning "Failed to detach Lambda policy"
        
        # Delete role
        if aws iam delete-role --role-name "$lambda_role_name"; then
            success "Lambda IAM role deleted: $lambda_role_name"
        else
            warning "Failed to delete Lambda IAM role: $lambda_role_name"
        fi
    else
        warning "Lambda IAM role not found: $lambda_role_name"
    fi
    
    # Delete OpenSearch IAM role
    local opensearch_role_name="OpenSearchServiceRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "$opensearch_role_name" &> /dev/null; then
        if aws iam delete-role --role-name "$opensearch_role_name"; then
            success "OpenSearch IAM role deleted: $opensearch_role_name"
        else
            warning "Failed to delete OpenSearch IAM role: $opensearch_role_name"
        fi
    else
        warning "OpenSearch IAM role not found: $opensearch_role_name"
    fi
}

# Delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete S3 bucket: ${S3_BUCKET_NAME:-Unknown}"
        return 0
    fi
    
    if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
        warning "S3 bucket name not specified, skipping deletion"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log "Emptying S3 bucket contents..."
        if aws s3 rm s3://"$S3_BUCKET_NAME" --recursive; then
            log "S3 bucket contents removed"
        else
            warning "Failed to remove S3 bucket contents"
        fi
        
        log "Deleting S3 bucket..."
        if aws s3 rb s3://"$S3_BUCKET_NAME"; then
            success "S3 bucket deleted: $S3_BUCKET_NAME"
        else
            if [[ "$FORCE_DELETE" == "true" ]]; then
                warning "Failed to delete S3 bucket, continuing due to --force flag"
            else
                error "Failed to delete S3 bucket: $S3_BUCKET_NAME"
                exit 1
            fi
        fi
    else
        warning "S3 bucket not found or already deleted: $S3_BUCKET_NAME"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete CloudWatch dashboards, alarms, and log groups"
        return 0
    fi
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        warning "Domain name not specified, skipping CloudWatch resource deletion"
        return 0
    fi
    
    # Delete dashboard
    local dashboard_name="OpenSearch-${DOMAIN_NAME}-Dashboard"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &> /dev/null; then
        if aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"; then
            success "CloudWatch dashboard deleted: $dashboard_name"
        else
            warning "Failed to delete CloudWatch dashboard: $dashboard_name"
        fi
    else
        warning "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    # Delete alarm
    local alarm_name="OpenSearch-High-Search-Latency-${DOMAIN_NAME}"
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0]' --output text | grep -q "$alarm_name"; then
        if aws cloudwatch delete-alarms --alarm-names "$alarm_name"; then
            success "CloudWatch alarm deleted: $alarm_name"
        else
            warning "Failed to delete CloudWatch alarm: $alarm_name"
        fi
    else
        warning "CloudWatch alarm not found: $alarm_name"
    fi
    
    # Delete log groups
    local index_log_group="/aws/opensearch/domains/${DOMAIN_NAME}/index-slow-logs"
    local search_log_group="/aws/opensearch/domains/${DOMAIN_NAME}/search-slow-logs"
    
    for log_group in "$index_log_group" "$search_log_group"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0]' --output text | grep -q "$log_group"; then
            if aws logs delete-log-group --log-group-name "$log_group"; then
                success "CloudWatch log group deleted: $log_group"
            else
                warning "Failed to delete CloudWatch log group: $log_group"
            fi
        else
            warning "CloudWatch log group not found: $log_group"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would clean up local files"
        return 0
    fi
    
    # List of files to clean up
    local files_to_remove=(
        "deployment-config.env"
        "opensearch-trust-policy.json"
        "lambda-trust-policy.json"
        "domain-config.json"
        "product-mapping.json"
        "sample-products.json"
        "lambda-indexer.py"
        "lambda-indexer.zip"
        "cloudwatch-dashboard.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed local file: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Print deletion summary
print_summary() {
    log "Deletion Summary:"
    log "================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN MODE - No resources were actually deleted"
        log "The following resources would have been deleted:"
    else
        log "The following resources have been deleted:"
    fi
    
    log "- OpenSearch domain: ${DOMAIN_NAME:-Not specified}"
    log "- S3 bucket: ${S3_BUCKET_NAME:-Not specified}"
    log "- Lambda function: ${LAMBDA_FUNCTION_NAME:-Not specified}"
    log "- IAM roles and policies"
    log "- CloudWatch dashboards and alarms"
    log "- CloudWatch log groups"
    log "- Local configuration files"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        success "All resources have been successfully deleted!"
        log "You may want to verify in the AWS Console that all resources are gone."
    fi
}

# Main cleanup function
main() {
    log "Starting OpenSearch Service resource cleanup..."
    
    check_prerequisites
    load_configuration
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_resources
    delete_lambda_function
    delete_iam_roles
    delete_s3_bucket
    delete_opensearch_domain
    cleanup_local_files
    
    print_summary
    
    if [[ "$DRY_RUN" != "true" ]]; then
        success "Cleanup completed successfully!"
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"
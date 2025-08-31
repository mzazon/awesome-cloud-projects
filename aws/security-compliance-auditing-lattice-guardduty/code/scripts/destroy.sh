#!/bin/bash

# Security Compliance Auditing with VPC Lattice and GuardDuty - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/security-compliance-destroy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
FORCE=false
KEEP_GUARDDUTY=false
KEEP_S3_DATA=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
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

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check log file: $LOG_FILE"
    log_warning "Some resources may still exist and incur charges"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Security Compliance Auditing Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without removing resources
    -f, --force             Skip confirmation prompts (use with caution)
    --keep-guardduty        Keep GuardDuty detector enabled (if created by this script)
    --keep-s3-data          Keep S3 bucket data (delete bucket but preserve data in new bucket)
    --config-file FILE      Use specific deployment config file
    --debug                 Enable debug logging

EXAMPLES:
    $0                      # Interactive cleanup with prompts
    $0 --dry-run            # See what would be deleted
    $0 --force              # Delete everything without prompts
    $0 --keep-guardduty     # Keep GuardDuty enabled
    $0 --keep-s3-data       # Preserve compliance reports

SAFETY:
    - Always run with --dry-run first to review what will be deleted
    - Use --keep-guardduty if GuardDuty is used by other systems
    - Use --keep-s3-data to preserve compliance reports for auditing

EOF
}

# Parse command line arguments
CONFIG_FILE=""
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
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
        --keep-guardduty)
            KEEP_GUARDDUTY=true
            shift
            ;;
        --keep-s3-data)
            KEEP_S3_DATA=true
            shift
            ;;
        --config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    # Use specified config file or look for default
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Config file not found: $CONFIG_FILE"
            exit 1
        fi
        source "$CONFIG_FILE"
        log_info "Loaded config from: $CONFIG_FILE"
    elif [[ -f "$SCRIPT_DIR/.deployment-config" ]]; then
        source "$SCRIPT_DIR/.deployment-config"
        log_info "Loaded config from: $SCRIPT_DIR/.deployment-config"
    else
        log_error "No deployment configuration found!"
        log_error "Run this script from the same directory as deploy.sh or specify --config-file"
        exit 1
    fi
    
    # Validate required variables
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable not set: $var"
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
    log_info "Region: ${AWS_REGION}"
    log_info "Account: ${AWS_ACCOUNT_ID}"
}

# Check AWS CLI access
check_aws_access() {
    log_info "Checking AWS access..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "Current AWS account ($current_account) doesn't match deployment account ($AWS_ACCOUNT_ID)"
        exit 1
    fi
    
    log_success "AWS access verified"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete the following resources:"
    echo "  🗑️  S3 Bucket: ${BUCKET_NAME:-N/A}"
    echo "  🗑️  CloudWatch Log Group: ${LOG_GROUP_NAME:-N/A}"
    echo "  🗑️  Lambda Function: ${LAMBDA_FUNCTION_NAME:-N/A}"
    echo "  🗑️  IAM Role: ${IAM_ROLE_NAME:-N/A}"
    echo "  🗑️  SNS Topic: ${SNS_TOPIC_NAME:-N/A}"
    echo "  🗑️  CloudWatch Dashboard: SecurityComplianceDashboard"
    echo "  🗑️  VPC Lattice Service Network: ${SERVICE_NETWORK_ID:-N/A}"
    
    if [[ "$KEEP_GUARDDUTY" == "false" ]]; then
        echo "  🗑️  GuardDuty Detector: ${GUARDDUTY_DETECTOR_ID:-N/A}"
    else
        echo "  ⚠️   GuardDuty Detector: KEEPING (as requested)"
    fi
    
    if [[ "$KEEP_S3_DATA" == "true" ]]; then
        echo "  ⚠️   S3 Data: PRESERVING (will create backup bucket)"
    fi
    
    echo
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove VPC Lattice resources
remove_vpc_lattice() {
    log_info "Removing VPC Lattice resources..."
    
    if [[ -z "${SERVICE_NETWORK_ID:-}" ]]; then
        log_warning "No service network ID found, skipping VPC Lattice cleanup"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete VPC Lattice service network: $SERVICE_NETWORK_ID"
        return 0
    fi
    
    # Check if service network exists
    if ! aws vpc-lattice get-service-network --service-network-identifier "$SERVICE_NETWORK_ID" &> /dev/null; then
        log_warning "Service network not found: $SERVICE_NETWORK_ID"
        return 0
    fi
    
    # Delete access log subscription first
    local log_subscriptions=$(aws vpc-lattice list-access-log-subscriptions \
        --resource-identifier "$SERVICE_NETWORK_ID" \
        --query 'items[0].id' --output text 2>/dev/null || echo "None")
    
    if [[ "$log_subscriptions" != "None" && -n "$log_subscriptions" ]]; then
        log_info "Removing access log subscription..."
        aws vpc-lattice delete-access-log-subscription \
            --access-log-subscription-identifier "$log_subscriptions"
        log_success "Access log subscription removed"
    fi
    
    # Delete service network
    log_info "Deleting service network: $SERVICE_NETWORK_ID"
    aws vpc-lattice delete-service-network \
        --service-network-identifier "$SERVICE_NETWORK_ID"
    
    log_success "VPC Lattice service network deleted: $SERVICE_NETWORK_ID"
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete CloudWatch dashboard and log resources"
        return 0
    fi
    
    # Delete dashboard
    if aws cloudwatch describe-dashboards --dashboard-names SecurityComplianceDashboard &> /dev/null; then
        log_info "Deleting CloudWatch dashboard..."
        aws cloudwatch delete-dashboards --dashboard-names SecurityComplianceDashboard
        log_success "CloudWatch dashboard deleted"
    else
        log_warning "CloudWatch dashboard not found"
    fi
    
    # Delete log subscription filter
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        local filters=$(aws logs describe-subscription-filters \
            --log-group-name "$LOG_GROUP_NAME" \
            --query 'subscriptionFilters[?filterName==`SecurityComplianceFilter`].filterName' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$filters" ]]; then
            log_info "Deleting log subscription filter..."
            aws logs delete-subscription-filter \
                --log-group-name "$LOG_GROUP_NAME" \
                --filter-name "SecurityComplianceFilter"
            log_success "Log subscription filter deleted"
        fi
        
        # Delete log group
        if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[?logGroupName==`'$LOG_GROUP_NAME'`]' --output text | grep -q "$LOG_GROUP_NAME"; then
            log_info "Deleting log group: $LOG_GROUP_NAME"
            aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
            log_success "CloudWatch log group deleted"
        else
            log_warning "Log group not found: $LOG_GROUP_NAME"
        fi
    fi
}

# Remove Lambda function
remove_lambda_function() {
    log_info "Removing Lambda function..."
    
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_warning "No Lambda function name found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log_success "Lambda function deleted"
    else
        log_warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
}

# Remove IAM role
remove_iam_role() {
    log_info "Removing IAM role..."
    
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        log_warning "No IAM role name found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete IAM role: $IAM_ROLE_NAME"
        return 0
    fi
    
    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        # Delete attached policies first
        local policies=$(aws iam list-role-policies --role-name "$IAM_ROLE_NAME" --query 'PolicyNames' --output text)
        if [[ -n "$policies" && "$policies" != "None" ]]; then
            for policy in $policies; do
                log_info "Deleting inline policy: $policy"
                aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$policy"
            done
        fi
        
        # Delete attached managed policies
        local managed_policies=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
        if [[ -n "$managed_policies" && "$managed_policies" != "None" ]]; then
            for policy_arn in $managed_policies; do
                log_info "Detaching managed policy: $policy_arn"
                aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn "$policy_arn"
            done
        fi
        
        # Delete role
        log_info "Deleting IAM role: $IAM_ROLE_NAME"
        aws iam delete-role --role-name "$IAM_ROLE_NAME"
        log_success "IAM role deleted"
    else
        log_warning "IAM role not found: $IAM_ROLE_NAME"
    fi
}

# Remove SNS topic
remove_sns_topic() {
    log_info "Removing SNS topic..."
    
    if [[ -z "${SNS_TOPIC_ARN:-}" ]]; then
        log_warning "No SNS topic ARN found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete SNS topic: $SNS_TOPIC_ARN"
        return 0
    fi
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        log_info "Deleting SNS topic: $SNS_TOPIC_ARN"
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
        log_success "SNS topic deleted"
    else
        log_warning "SNS topic not found: $SNS_TOPIC_ARN"
    fi
}

# Remove S3 bucket
remove_s3_bucket() {
    log_info "Removing S3 bucket..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "No S3 bucket name found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$KEEP_S3_DATA" == "true" ]]; then
            log_info "[DRY-RUN] Would preserve S3 data and create backup bucket"
        else
            log_info "[DRY-RUN] Would delete S3 bucket: $BUCKET_NAME"
        fi
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log_warning "S3 bucket not found: $BUCKET_NAME"
        return 0
    fi
    
    if [[ "$KEEP_S3_DATA" == "true" ]]; then
        # Create backup bucket and move data
        local backup_bucket="${BUCKET_NAME}-backup-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating backup bucket: $backup_bucket"
        
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://$backup_bucket"
        else
            aws s3 mb "s3://$backup_bucket" --region "$AWS_REGION"
        fi
        
        # Copy data to backup bucket
        log_info "Copying data to backup bucket..."
        aws s3 sync "s3://$BUCKET_NAME" "s3://$backup_bucket"
        
        log_success "Data backed up to: s3://$backup_bucket"
    fi
    
    # Empty and delete bucket
    log_info "Emptying S3 bucket: $BUCKET_NAME"
    aws s3 rm "s3://$BUCKET_NAME" --recursive
    
    log_info "Deleting S3 bucket: $BUCKET_NAME"
    aws s3 rb "s3://$BUCKET_NAME"
    
    log_success "S3 bucket deleted"
}

# Remove GuardDuty detector
remove_guardduty() {
    if [[ "$KEEP_GUARDDUTY" == "true" ]]; then
        log_info "Keeping GuardDuty detector as requested"
        return 0
    fi
    
    log_info "Removing GuardDuty detector..."
    
    if [[ -z "${GUARDDUTY_DETECTOR_ID:-}" ]]; then
        log_warning "No GuardDuty detector ID found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete GuardDuty detector: $GUARDDUTY_DETECTOR_ID"
        return 0
    fi
    
    # Check if detector exists
    if aws guardduty get-detector --detector-id "$GUARDDUTY_DETECTOR_ID" &> /dev/null; then
        log_info "Disabling GuardDuty detector: $GUARDDUTY_DETECTOR_ID"
        aws guardduty delete-detector --detector-id "$GUARDDUTY_DETECTOR_ID"
        log_success "GuardDuty detector deleted"
    else
        log_warning "GuardDuty detector not found: $GUARDDUTY_DETECTOR_ID"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean up local configuration files"
        return 0
    fi
    
    # Remove deployment config
    if [[ -f "$SCRIPT_DIR/.deployment-config" ]]; then
        rm -f "$SCRIPT_DIR/.deployment-config"
        log_success "Removed deployment configuration file"
    fi
    
    # Remove any temporary files
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-security-policy.json
    rm -f /tmp/security_processor.py
    rm -f /tmp/security-processor.zip
    rm -f /tmp/dashboard-config.json
    
    log_success "Local files cleaned up"
}

# Verify resource deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]] && aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log_warning "S3 bucket still exists: $BUCKET_NAME"
        ((errors++))
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        ((errors++))
    fi
    
    # Check IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]] && aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log_warning "IAM role still exists: $IAM_ROLE_NAME"
        ((errors++))
    fi
    
    # Check SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        log_warning "SNS topic still exists: $SNS_TOPIC_ARN"
        ((errors++))
    fi
    
    # Check VPC Lattice service network
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]] && aws vpc-lattice get-service-network --service-network-identifier "$SERVICE_NETWORK_ID" &> /dev/null; then
        log_warning "VPC Lattice service network still exists: $SERVICE_NETWORK_ID"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources successfully deleted"
    else
        log_warning "$errors resources still exist - they may take time to delete or require manual cleanup"
    fi
}

# Print cleanup summary
print_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN COMPLETE ==="
        log_info "No resources were actually deleted"
        return 0
    fi
    
    log_success "=== Cleanup Complete ==="
    echo
    log_info "Deleted Resources:"
    echo "  ✅ S3 Bucket: ${BUCKET_NAME:-N/A}"
    echo "  ✅ CloudWatch Log Group: ${LOG_GROUP_NAME:-N/A}"
    echo "  ✅ Lambda Function: ${LAMBDA_FUNCTION_NAME:-N/A}"
    echo "  ✅ IAM Role: ${IAM_ROLE_NAME:-N/A}"
    echo "  ✅ SNS Topic: ${SNS_TOPIC_NAME:-N/A}"
    echo "  ✅ CloudWatch Dashboard: SecurityComplianceDashboard"
    echo "  ✅ VPC Lattice Service Network: ${SERVICE_NETWORK_ID:-N/A}"
    
    if [[ "$KEEP_GUARDDUTY" == "false" ]]; then
        echo "  ✅ GuardDuty Detector: ${GUARDDUTY_DETECTOR_ID:-N/A}"
    else
        echo "  ⚠️  GuardDuty Detector: KEPT (as requested)"
    fi
    
    if [[ "$KEEP_S3_DATA" == "true" ]]; then
        echo "  ⚠️  S3 Data: PRESERVED in backup bucket"
    fi
    
    echo
    log_info "Cost Impact:"
    echo "  💰 All billable resources have been removed"
    echo "  💰 No ongoing charges should occur"
    
    if [[ "$KEEP_GUARDDUTY" == "true" ]]; then
        echo "  ⚠️  GuardDuty charges will continue (as requested)"
    fi
    
    echo
    log_info "Cleanup log saved to: $LOG_FILE"
    
    if [[ "$KEEP_S3_DATA" == "true" ]]; then
        echo
        log_warning "Compliance reports preserved in backup bucket - remember to manage lifecycle policies"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Security Compliance Auditing cleanup..."
    log_info "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    load_deployment_config
    check_aws_access
    confirm_deletion
    
    remove_vpc_lattice
    remove_cloudwatch_resources
    remove_lambda_function
    remove_iam_role
    remove_sns_topic
    remove_s3_bucket
    remove_guardduty
    cleanup_local_files
    
    verify_deletion
    print_summary
}

# Run main function
main "$@"
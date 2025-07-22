#!/bin/bash

# =============================================================================
# AWS Backup Strategies with S3 and Glacier - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the backup strategies
# deployment, including S3 buckets, Lambda functions, IAM roles, EventBridge
# rules, CloudWatch resources, and SNS topics.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Validation
# =============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="/tmp/backup-strategy-destroy-$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/../deployment-info.json"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

# Function to handle script exit
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup failed with exit code $exit_code"
        log_warning "Some resources may still exist. Please check AWS console manually."
        log_info "Cleanup log saved to: $LOG_FILE"
    else
        log_success "Cleanup completed successfully!"
        log_info "All resources have been removed."
        log_info "Cleanup log saved to: $LOG_FILE"
    fi
}

trap cleanup_on_exit EXIT

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured."
        exit 1
    fi
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# =============================================================================
# Load Deployment Information
# =============================================================================

load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        log_error "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        log_error "Cannot determine which resources to clean up."
        log_info "If you have deployment information, you can set environment variables manually:"
        log_info "export AWS_REGION=your-region"
        log_info "export BACKUP_BUCKET_NAME=your-bucket-name"
        log_info "export BACKUP_FUNCTION_NAME=your-function-name"
        log_info "export BACKUP_ROLE_NAME=your-role-name"
        log_info "export BACKUP_TOPIC_NAME=your-topic-name"
        log_info "export RANDOM_SUFFIX=your-suffix"
        exit 1
    fi
    
    # Load variables from deployment info
    export AWS_REGION
    AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_INFO_FILE")
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_INFO_FILE")
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(jq -r '.random_suffix' "$DEPLOYMENT_INFO_FILE")
    export BACKUP_BUCKET_NAME
    BACKUP_BUCKET_NAME=$(jq -r '.resources.s3_bucket' "$DEPLOYMENT_INFO_FILE")
    export BACKUP_FUNCTION_NAME
    BACKUP_FUNCTION_NAME=$(jq -r '.resources.lambda_function' "$DEPLOYMENT_INFO_FILE")
    export BACKUP_ROLE_NAME
    BACKUP_ROLE_NAME=$(jq -r '.resources.iam_role' "$DEPLOYMENT_INFO_FILE")
    export BACKUP_TOPIC_NAME
    BACKUP_TOPIC_NAME=$(jq -r '.resources.sns_topic' "$DEPLOYMENT_INFO_FILE")
    export BACKUP_TOPIC_ARN
    BACKUP_TOPIC_ARN=$(jq -r '.resources.sns_topic_arn' "$DEPLOYMENT_INFO_FILE")
    
    log_info "Loaded deployment info:"
    log_info "AWS Region: $AWS_REGION"
    log_info "Bucket: $BACKUP_BUCKET_NAME"
    log_info "Function: $BACKUP_FUNCTION_NAME"
    log_info "Role: $BACKUP_ROLE_NAME"
    log_info "Topic: $BACKUP_TOPIC_NAME"
    log_info "Suffix: $RANDOM_SUFFIX"
    
    log_success "Deployment information loaded"
}

# =============================================================================
# Resource Removal Functions
# =============================================================================

remove_eventbridge_rules() {
    log_info "Removing EventBridge rules and targets..."
    
    local rules=("daily-backup-${RANDOM_SUFFIX}" "weekly-backup-${RANDOM_SUFFIX}")
    
    for rule in "${rules[@]}"; do
        if aws events describe-rule --name "$rule" &>/dev/null; then
            log_info "Removing targets for rule: $rule"
            # Remove targets first
            aws events remove-targets --rule "$rule" --ids "1" 2>/dev/null || true
            
            log_info "Removing rule: $rule"
            # Delete rule
            aws events delete-rule --name "$rule" 2>/dev/null || true
            
            log_success "Removed EventBridge rule: $rule"
        else
            log_warning "EventBridge rule not found: $rule"
        fi
    done
    
    log_success "EventBridge rules cleanup completed"
}

remove_lambda_function() {
    log_info "Removing Lambda function..."
    
    if aws lambda get-function --function-name "$BACKUP_FUNCTION_NAME" &>/dev/null; then
        # Remove Lambda permissions first
        aws lambda remove-permission \
            --function-name "$BACKUP_FUNCTION_NAME" \
            --statement-id daily-backup-permission 2>/dev/null || true
        
        aws lambda remove-permission \
            --function-name "$BACKUP_FUNCTION_NAME" \
            --statement-id weekly-backup-permission 2>/dev/null || true
        
        # Delete Lambda function
        aws lambda delete-function --function-name "$BACKUP_FUNCTION_NAME"
        
        log_success "Lambda function deleted: $BACKUP_FUNCTION_NAME"
    else
        log_warning "Lambda function not found: $BACKUP_FUNCTION_NAME"
    fi
    
    # Clean up local files
    rm -f /tmp/backup-function.py /tmp/backup-function.zip /tmp/response.json
    
    log_success "Lambda function cleanup completed"
}

remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms=("backup-failure-alarm-${RANDOM_SUFFIX}" "backup-duration-alarm-${RANDOM_SUFFIX}")
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "$alarm"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log_success "Deleted CloudWatch alarm: $alarm"
        else
            log_warning "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete dashboard
    local dashboard_name="backup-strategy-dashboard-${RANDOM_SUFFIX}"
    if aws cloudwatch list-dashboards --query "DashboardEntries[?DashboardName=='$dashboard_name']" --output text | grep -q "$dashboard_name"; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        log_success "Deleted CloudWatch dashboard: $dashboard_name"
    else
        log_warning "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    # Clean up local files
    rm -f /tmp/dashboard-body.json
    
    log_success "CloudWatch resources cleanup completed"
}

remove_cross_region_replication() {
    log_info "Checking for cross-region replication..."
    
    # Check if replication is configured
    if aws s3api get-bucket-replication --bucket "$BACKUP_BUCKET_NAME" &>/dev/null; then
        log_info "Removing cross-region replication configuration..."
        
        # Get DR bucket name from replication config
        local dr_bucket
        dr_bucket=$(aws s3api get-bucket-replication --bucket "$BACKUP_BUCKET_NAME" \
            --query 'ReplicationConfiguration.Rules[0].Destination.Bucket' --output text 2>/dev/null || echo "")
        
        if [ -n "$dr_bucket" ] && [ "$dr_bucket" != "None" ]; then
            dr_bucket=$(echo "$dr_bucket" | sed 's|arn:aws:s3:::|arn:aws:s3:::|')
            dr_bucket=$(basename "$dr_bucket")
            
            log_info "Found DR bucket: $dr_bucket"
            
            # Remove replication configuration
            aws s3api delete-bucket-replication --bucket "$BACKUP_BUCKET_NAME" 2>/dev/null || true
            
            # Delete DR bucket contents and bucket
            local dr_region
            dr_region=$(aws s3api get-bucket-location --bucket "$dr_bucket" \
                --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
            
            if [ "$dr_region" = "None" ]; then
                dr_region="us-east-1"
            fi
            
            log_info "Deleting DR bucket contents..."
            aws s3 rm "s3://$dr_bucket" --recursive 2>/dev/null || true
            
            log_info "Deleting DR bucket..."
            aws s3api delete-bucket --bucket "$dr_bucket" --region "$dr_region" 2>/dev/null || true
            
            # Delete replication role
            local replication_role="s3-replication-role-${RANDOM_SUFFIX}"
            if aws iam get-role --role-name "$replication_role" &>/dev/null; then
                aws iam delete-role-policy --role-name "$replication_role" --policy-name ReplicationPolicy 2>/dev/null || true
                aws iam delete-role --role-name "$replication_role" 2>/dev/null || true
                log_success "Deleted replication role: $replication_role"
            fi
            
            log_success "Cross-region replication removed"
        fi
    else
        log_info "No cross-region replication configured"
    fi
    
    # Clean up local files
    rm -f /tmp/replication-trust-policy.json /tmp/replication-policy.json /tmp/replication-config.json
}

remove_s3_bucket() {
    log_info "Removing S3 bucket and all contents..."
    
    if aws s3api head-bucket --bucket "$BACKUP_BUCKET_NAME" &>/dev/null; then
        # Remove cross-region replication first
        remove_cross_region_replication
        
        log_info "Deleting all object versions from bucket..."
        
        # Delete all object versions
        local versions
        versions=$(aws s3api list-object-versions --bucket "$BACKUP_BUCKET_NAME" \
            --output json --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null || echo "[]")
        
        if [ "$versions" != "[]" ] && [ "$versions" != "null" ]; then
            echo "$versions" | jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
            while IFS= read -r delete_args; do
                aws s3api delete-object --bucket "$BACKUP_BUCKET_NAME" $delete_args 2>/dev/null || true
            done
        fi
        
        # Delete delete markers
        local delete_markers
        delete_markers=$(aws s3api list-object-versions --bucket "$BACKUP_BUCKET_NAME" \
            --output json --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null || echo "[]")
        
        if [ "$delete_markers" != "[]" ] && [ "$delete_markers" != "null" ]; then
            echo "$delete_markers" | jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
            while IFS= read -r delete_args; do
                aws s3api delete-object --bucket "$BACKUP_BUCKET_NAME" $delete_args 2>/dev/null || true
            done
        fi
        
        # Remove any remaining objects using S3 CLI
        aws s3 rm "s3://$BACKUP_BUCKET_NAME" --recursive 2>/dev/null || true
        
        # Delete bucket
        aws s3api delete-bucket --bucket "$BACKUP_BUCKET_NAME"
        
        log_success "S3 bucket deleted: $BACKUP_BUCKET_NAME"
    else
        log_warning "S3 bucket not found: $BACKUP_BUCKET_NAME"
    fi
    
    # Clean up local files
    rm -f /tmp/lifecycle-policy.json
    rm -rf ~/backup-demo-data
    
    log_success "S3 bucket cleanup completed"
}

remove_iam_resources() {
    log_info "Removing IAM resources..."
    
    # Detach policies from role
    if aws iam get-role --role-name "$BACKUP_ROLE_NAME" &>/dev/null; then
        log_info "Detaching policies from role: $BACKUP_ROLE_NAME"
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name "$BACKUP_ROLE_NAME" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/BackupExecutionPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "$BACKUP_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        
        # Delete custom policy
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/BackupExecutionPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$BACKUP_ROLE_NAME"
        
        log_success "IAM role deleted: $BACKUP_ROLE_NAME"
    else
        log_warning "IAM role not found: $BACKUP_ROLE_NAME"
    fi
    
    # Clean up local files
    rm -f /tmp/trust-policy.json /tmp/backup-policy.json
    
    log_success "IAM resources cleanup completed"
}

remove_sns_topic() {
    log_info "Removing SNS topic..."
    
    if [ -n "$BACKUP_TOPIC_ARN" ] && [ "$BACKUP_TOPIC_ARN" != "null" ]; then
        # Delete SNS topic
        aws sns delete-topic --topic-arn "$BACKUP_TOPIC_ARN" 2>/dev/null || true
        
        log_success "SNS topic deleted: $BACKUP_TOPIC_ARN"
    else
        log_warning "SNS topic ARN not found or invalid"
    fi
    
    log_success "SNS topic cleanup completed"
}

remove_deployment_info() {
    log_info "Removing deployment information file..."
    
    if [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Deployment info file removed"
    else
        log_warning "Deployment info file not found"
    fi
}

# =============================================================================
# Confirmation and Safety Checks
# =============================================================================

confirm_destruction() {
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This will permanently delete the following resources:"
    echo
    log_warning "• S3 Bucket: $BACKUP_BUCKET_NAME (including ALL objects and versions)"
    log_warning "• Lambda Function: $BACKUP_FUNCTION_NAME"
    log_warning "• IAM Role: $BACKUP_ROLE_NAME"
    log_warning "• SNS Topic: $BACKUP_TOPIC_ARN"
    log_warning "• EventBridge Rules: daily-backup-${RANDOM_SUFFIX}, weekly-backup-${RANDOM_SUFFIX}"
    log_warning "• CloudWatch Alarms and Dashboard"
    log_warning "• Any cross-region replication configuration and DR bucket"
    echo
    log_warning "This action CANNOT be undone!"
    echo
    
    if [ "${FORCE_DESTROY:-}" = "true" ]; then
        log_warning "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo
    if [ "$REPLY" != "yes" ]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# =============================================================================
# Main Cleanup Flow
# =============================================================================

main() {
    log_info "Starting AWS Backup Strategies cleanup..."
    log_info "Log file: $LOG_FILE"
    
    # Execute cleanup steps
    check_prerequisites
    
    # Try to load deployment info, but allow manual override
    if [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        load_deployment_info
    else
        log_warning "Deployment info file not found. Checking for environment variables..."
        
        # Check if manual environment variables are set
        if [ -z "${BACKUP_BUCKET_NAME:-}" ] || [ -z "${RANDOM_SUFFIX:-}" ]; then
            log_error "No deployment info found and required environment variables not set."
            log_error "Please ensure you have either:"
            log_error "1. The deployment-info.json file from the original deployment"
            log_error "2. The following environment variables set:"
            log_error "   - AWS_REGION"
            log_error "   - BACKUP_BUCKET_NAME" 
            log_error "   - BACKUP_FUNCTION_NAME"
            log_error "   - BACKUP_ROLE_NAME"
            log_error "   - BACKUP_TOPIC_NAME or BACKUP_TOPIC_ARN"
            log_error "   - RANDOM_SUFFIX"
            exit 1
        fi
        
        # Set defaults for missing variables
        export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
        export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
        export BACKUP_FUNCTION_NAME="${BACKUP_FUNCTION_NAME:-backup-orchestrator-${RANDOM_SUFFIX}}"
        export BACKUP_ROLE_NAME="${BACKUP_ROLE_NAME:-backup-execution-role-${RANDOM_SUFFIX}}"
        export BACKUP_TOPIC_NAME="${BACKUP_TOPIC_NAME:-backup-notifications-${RANDOM_SUFFIX}}"
        export BACKUP_TOPIC_ARN="${BACKUP_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${BACKUP_TOPIC_NAME}}"
        
        log_info "Using environment variables for cleanup"
    fi
    
    confirm_destruction
    
    # Execute cleanup in reverse order of creation
    remove_eventbridge_rules
    remove_lambda_function
    remove_cloudwatch_resources
    remove_s3_bucket  # This also handles cross-region replication
    remove_iam_resources
    remove_sns_topic
    remove_deployment_info
    
    # Display final summary
    echo
    log_success "=== Cleanup Summary ==="
    log_success "All backup strategy resources have been successfully removed"
    log_info "Cleaned up resources:"
    log_info "• S3 bucket and all contents"
    log_info "• Lambda function and permissions"
    log_info "• IAM role and policies"
    log_info "• SNS topic and subscriptions"
    log_info "• EventBridge rules and targets"
    log_info "• CloudWatch alarms and dashboard"
    log_info "• Cross-region replication (if configured)"
    log_info "• Local temporary files"
    echo
    log_info "Cleanup log saved to: $LOG_FILE"
}

# Check if running in dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log_info "Running in dry-run mode - no resources will be deleted"
    log_info "Would execute the following cleanup steps:"
    log_info "1. Remove EventBridge rules and targets"
    log_info "2. Remove Lambda function and permissions"
    log_info "3. Remove CloudWatch alarms and dashboard"
    log_info "4. Remove S3 bucket and all contents (including versions)"
    log_info "5. Remove cross-region replication (if configured)"
    log_info "6. Remove IAM role and policies"
    log_info "7. Remove SNS topic"
    log_info "8. Remove deployment info file"
    exit 0
fi

# Check for force mode
if [ "${1:-}" = "--force" ]; then
    export FORCE_DESTROY="true"
    log_warning "Force mode enabled - will not prompt for confirmation"
fi

# Run main cleanup
main "$@"
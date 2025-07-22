#!/bin/bash

# AWS Sustainability Dashboards Cleanup Script
# Recipe: Carbon Footprint Analytics with QuickSight
# This script removes all infrastructure created by the deployment script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    REPO_ROOT="${SCRIPT_DIR}/../../../.."
fi

# Configuration
RESOURCE_FILE="${SCRIPT_DIR}/deployed_resources.txt"
CLEANUP_LOG="${SCRIPT_DIR}/cleanup.log"

# Initialize cleanup log
echo "=== AWS Sustainability Dashboards Cleanup Started at $(date) ===" > "${CLEANUP_LOG}"

log "Starting AWS Sustainability Dashboards cleanup..."

# Load deployed resources
load_resources() {
    log "Loading deployed resource information..."
    
    if [[ ! -f "${RESOURCE_FILE}" ]]; then
        error "Resource file not found: ${RESOURCE_FILE}"
        error "Cannot determine which resources to clean up."
        error "Please run with --manual-cleanup to specify resources manually."
        exit 1
    fi
    
    # Source the resource file
    source "${RESOURCE_FILE}"
    
    # Validate required variables
    if [[ -z "$AWS_REGION" || -z "$AWS_ACCOUNT_ID" || -z "$RANDOM_SUFFIX" ]]; then
        error "Missing required variables in resource file."
        error "Resource file may be corrupted or incomplete."
        exit 1
    fi
    
    log "Loaded resource configuration:"
    log "• AWS Region: ${AWS_REGION}"
    log "• AWS Account: ${AWS_ACCOUNT_ID}"
    log "• Resource Suffix: ${RANDOM_SUFFIX}"
    
    # Export variables for use in cleanup functions
    export AWS_REGION AWS_ACCOUNT_ID RANDOM_SUFFIX
    export BUCKET_NAME FUNCTION_NAME ROLE_NAME SNS_TOPIC_NAME EVENTBRIDGE_RULE_NAME
    
    success "Resource configuration loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    log "Checking cleanup prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Verify we're in the correct account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]]; then
        error "Current AWS account ($CURRENT_ACCOUNT) doesn't match deployment account ($AWS_ACCOUNT_ID)"
        error "Please configure credentials for the correct account."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Remove QuickSight resources (manual step notification)
cleanup_quicksight_resources() {
    log "QuickSight resource cleanup (manual steps required)..."
    
    warning "QuickSight resources must be deleted manually through the console:"
    echo
    echo "1. Navigate to QuickSight Console:"
    echo "   https://${AWS_REGION}.quicksight.aws.amazon.com/"
    echo
    echo "2. Delete any dashboards created for sustainability analytics"
    echo "3. Delete datasets that reference the S3 manifest"
    echo "4. Delete data sources pointing to the S3 bucket: ${BUCKET_NAME}"
    echo
    
    read -p "Have you completed the QuickSight cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Please complete QuickSight cleanup before proceeding with infrastructure removal."
        warning "Infrastructure cleanup will continue, but QuickSight resources may remain."
    fi
    
    echo "QUICKSIGHT_CLEANUP=manual" >> "${CLEANUP_LOG}"
}

# Remove CloudWatch alarms
cleanup_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    local alarms_to_delete=(
        "SustainabilityDataProcessingFailure-${RANDOM_SUFFIX}"
        "SustainabilityDataProcessingSuccess-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            log "Deleting CloudWatch alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            success "Deleted alarm: $alarm"
        else
            log "CloudWatch alarm not found (may already be deleted): $alarm"
        fi
    done
    
    echo "CLOUDWATCH_ALARMS_DELETED=true" >> "${CLEANUP_LOG}"
    success "CloudWatch alarms cleanup completed"
}

# Remove SNS topic and subscriptions
cleanup_sns_resources() {
    log "Removing SNS topic and subscriptions..."
    
    # Get SNS topic ARN
    local sns_topic_arn
    sns_topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn,\`${SNS_TOPIC_NAME}\`)].TopicArn" --output text 2>/dev/null || echo "")
    
    if [[ -n "$sns_topic_arn" && "$sns_topic_arn" != "None" ]]; then
        log "Found SNS topic: $sns_topic_arn"
        
        # List and delete subscriptions first
        local subscriptions
        subscriptions=$(aws sns list-subscriptions-by-topic --topic-arn "$sns_topic_arn" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" && "$subscriptions" != "None" ]]; then
            for subscription_arn in $subscriptions; do
                if [[ "$subscription_arn" != "PendingConfirmation" ]]; then
                    log "Deleting subscription: $subscription_arn"
                    aws sns unsubscribe --subscription-arn "$subscription_arn"
                fi
            done
        fi
        
        # Delete the topic
        log "Deleting SNS topic: $sns_topic_arn"
        aws sns delete-topic --topic-arn "$sns_topic_arn"
        success "Deleted SNS topic: ${SNS_TOPIC_NAME}"
    else
        log "SNS topic not found (may already be deleted): ${SNS_TOPIC_NAME}"
    fi
    
    echo "SNS_TOPIC_DELETED=true" >> "${CLEANUP_LOG}"
    success "SNS resources cleanup completed"
}

# Remove EventBridge rule and targets
cleanup_eventbridge_resources() {
    log "Removing EventBridge rule and targets..."
    
    # Check if rule exists
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        log "Found EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
        
        # Remove targets first
        local targets
        targets=$(aws events list-targets-by-rule --rule "${EVENTBRIDGE_RULE_NAME}" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
        
        if [[ -n "$targets" && "$targets" != "None" ]]; then
            log "Removing targets from EventBridge rule..."
            aws events remove-targets --rule "${EVENTBRIDGE_RULE_NAME}" --ids $targets
        fi
        
        # Delete the rule
        log "Deleting EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
        aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}"
        success "Deleted EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    else
        log "EventBridge rule not found (may already be deleted): ${EVENTBRIDGE_RULE_NAME}"
    fi
    
    echo "EVENTBRIDGE_RULE_DELETED=true" >> "${CLEANUP_LOG}"
    success "EventBridge resources cleanup completed"
}

# Remove Lambda function
cleanup_lambda_function() {
    log "Removing Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        log "Found Lambda function: ${FUNCTION_NAME}"
        
        # Remove any resource-based policies (EventBridge permissions)
        local policy_statements
        policy_statements=$(aws lambda get-policy --function-name "${FUNCTION_NAME}" --query 'Policy' --output text 2>/dev/null || echo "")
        
        if [[ -n "$policy_statements" && "$policy_statements" != "None" ]]; then
            # Try to remove EventBridge permission
            aws lambda remove-permission \
                --function-name "${FUNCTION_NAME}" \
                --statement-id "allow-eventbridge-${RANDOM_SUFFIX}" 2>/dev/null || true
        fi
        
        # Delete the function
        log "Deleting Lambda function: ${FUNCTION_NAME}"
        aws lambda delete-function --function-name "${FUNCTION_NAME}"
        success "Deleted Lambda function: ${FUNCTION_NAME}"
    else
        log "Lambda function not found (may already be deleted): ${FUNCTION_NAME}"
    fi
    
    echo "LAMBDA_FUNCTION_DELETED=true" >> "${CLEANUP_LOG}"
    success "Lambda function cleanup completed"
}

# Remove IAM resources
cleanup_iam_resources() {
    log "Removing IAM role and policies..."
    
    local role_name="${ROLE_NAME}"
    local policy_name="SustainabilityAnalyticsPolicy-${RANDOM_SUFFIX}"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        log "Found IAM role: $role_name"
        
        # Detach managed policies
        log "Detaching managed policies from role..."
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        
        # Detach custom policy
        log "Detaching custom policy from role..."
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" 2>/dev/null || true
        
        # Delete the role
        log "Deleting IAM role: $role_name"
        aws iam delete-role --role-name "$role_name"
        success "Deleted IAM role: $role_name"
    else
        log "IAM role not found (may already be deleted): $role_name"
    fi
    
    # Delete custom policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" &>/dev/null; then
        log "Deleting custom policy: $policy_name"
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
        success "Deleted IAM policy: $policy_name"
    else
        log "IAM policy not found (may already be deleted): $policy_name"
    fi
    
    echo "IAM_RESOURCES_DELETED=true" >> "${CLEANUP_LOG}"
    success "IAM resources cleanup completed"
}

# Empty and remove S3 bucket
cleanup_s3_bucket() {
    log "Removing S3 bucket and contents..."
    
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log "Found S3 bucket: ${BUCKET_NAME}"
        
        # Check if bucket has versioning enabled and handle versions
        local versioning_status
        versioning_status=$(aws s3api get-bucket-versioning --bucket "${BUCKET_NAME}" --query 'Status' --output text 2>/dev/null || echo "None")
        
        if [[ "$versioning_status" == "Enabled" ]]; then
            log "Bucket has versioning enabled, removing all versions..."
            
            # Remove all object versions and delete markers
            aws s3api list-object-versions --bucket "${BUCKET_NAME}" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json > versions.json 2>/dev/null || echo '{"Objects":[]}' > versions.json
            
            if [[ $(jq '.Objects | length' versions.json) -gt 0 ]]; then
                aws s3api delete-objects --bucket "${BUCKET_NAME}" --delete file://versions.json > /dev/null
            fi
            
            # Remove delete markers
            aws s3api list-object-versions --bucket "${BUCKET_NAME}" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json > delete-markers.json 2>/dev/null || echo '{"Objects":[]}' > delete-markers.json
            
            if [[ $(jq '.Objects | length' delete-markers.json) -gt 0 ]]; then
                aws s3api delete-objects --bucket "${BUCKET_NAME}" --delete file://delete-markers.json > /dev/null
            fi
            
            # Clean up temporary files
            rm -f versions.json delete-markers.json
        else
            # For non-versioned buckets, use simple deletion
            log "Removing all objects from bucket..."
            aws s3 rm s3://"${BUCKET_NAME}" --recursive
        fi
        
        # Remove bucket policy if it exists
        aws s3api delete-bucket-policy --bucket "${BUCKET_NAME}" 2>/dev/null || true
        
        # Delete the bucket
        log "Deleting S3 bucket: ${BUCKET_NAME}"
        aws s3 rb s3://"${BUCKET_NAME}"
        success "Deleted S3 bucket: ${BUCKET_NAME}"
    else
        log "S3 bucket not found (may already be deleted): ${BUCKET_NAME}"
    fi
    
    echo "S3_BUCKET_DELETED=true" >> "${CLEANUP_LOG}"
    success "S3 bucket cleanup completed"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary and configuration files..."
    
    local files_to_remove=(
        "trust-policy.json"
        "sustainability-policy.json" 
        "bucket-policy.json"
        "sustainability_processor.py"
        "function.zip"
        "sustainability-manifest.json"
        "response.json"
        "versions.json"
        "delete-markers.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Temporary files cleanup completed"
}

# Display cleanup summary
display_summary() {
    log "=== Cleanup Summary ==="
    echo
    success "AWS Sustainability Dashboards infrastructure cleanup completed!"
    echo
    echo "Resources removed:"
    echo "✅ CloudWatch Alarms"
    echo "✅ SNS Topic and Subscriptions"
    echo "✅ EventBridge Rule and Targets"
    echo "✅ Lambda Function"
    echo "✅ IAM Role and Policies"
    echo "✅ S3 Bucket and Contents"
    echo "✅ Temporary Files"
    echo
    warning "Manual cleanup required for:"
    echo "• QuickSight dashboards and data sources"
    echo "• Any manually created resources not tracked by the deployment script"
    echo
    echo "Cleanup log: ${CLEANUP_LOG}"
    
    # Archive or remove resource file
    if [[ -f "${RESOURCE_FILE}" ]]; then
        mv "${RESOURCE_FILE}" "${RESOURCE_FILE}.$(date +%Y%m%d_%H%M%S).bak"
        log "Resource file archived for reference"
    fi
    
    # Log final status
    echo "=== Cleanup completed successfully at $(date) ===" >> "${CLEANUP_LOG}"
}

# Manual cleanup mode
manual_cleanup() {
    log "Manual cleanup mode - please provide resource details"
    
    read -p "Enter AWS Region: " AWS_REGION
    read -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    read -p "Enter resource suffix: " RANDOM_SUFFIX
    
    # Set resource names
    export BUCKET_NAME="sustainability-analytics-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="sustainability-data-processor-${RANDOM_SUFFIX}"
    export ROLE_NAME="SustainabilityAnalyticsRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="sustainability-alerts-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="sustainability-data-collection-${RANDOM_SUFFIX}"
    
    warning "Manual cleanup mode enabled with provided resource names"
}

# Main cleanup function
main() {
    echo
    log "=== AWS Sustainability Dashboards Cleanup ==="
    echo
    
    # Check for manual cleanup mode
    if [[ "$1" == "--manual-cleanup" ]]; then
        manual_cleanup
    else
        load_resources
    fi
    
    # Check if running in dry-run mode
    if [[ "$1" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        warning "This is a dry run. No actual cleanup will occur."
        log "Resources that would be deleted:"
        log "• S3 Bucket: ${BUCKET_NAME}"
        log "• Lambda Function: ${FUNCTION_NAME}"
        log "• IAM Role: ${ROLE_NAME}"
        log "• SNS Topic: ${SNS_TOPIC_NAME}"
        log "• EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
        return 0
    fi
    
    # Confirm cleanup
    echo -e "${RED}WARNING: This will permanently delete AWS resources and data.${NC}"
    echo
    echo "Resources to be deleted:"
    echo "• S3 Bucket: ${BUCKET_NAME} (and ALL contents)"
    echo "• Lambda Function: ${FUNCTION_NAME}"
    echo "• IAM Role: ${ROLE_NAME}"
    echo "• SNS Topic: ${SNS_TOPIC_NAME}"
    echo "• EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "• CloudWatch Alarms and related resources"
    echo
    echo -e "${RED}This action cannot be undone.${NC}"
    echo
    read -p "Are you sure you want to delete all resources? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Second confirmation for safety
    echo -e "${RED}Final confirmation: Type 'DELETE' to proceed with resource deletion:${NC}"
    read -p "> " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled - confirmation not received"
        exit 0
    fi
    
    # Execute cleanup steps in reverse order of creation
    check_prerequisites
    cleanup_quicksight_resources
    cleanup_cloudwatch_alarms
    cleanup_sns_resources
    cleanup_eventbridge_resources
    cleanup_lambda_function
    cleanup_iam_resources
    cleanup_s3_bucket
    cleanup_temp_files
    display_summary
    
    success "Cleanup completed successfully!"
}

# Error handling
trap 'error "Cleanup failed at line $LINENO. Check ${CLEANUP_LOG} for details."; exit 1' ERR

# Help function
show_help() {
    echo "AWS Sustainability Dashboards Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help              Show this help message"
    echo "  --dry-run           Show what would be deleted without actually deleting"
    echo "  --manual-cleanup    Manual cleanup mode (for when resource file is missing)"
    echo
    echo "Examples:"
    echo "  $0                  # Normal cleanup using deployed_resources.txt"
    echo "  $0 --dry-run        # Preview cleanup without making changes"
    echo "  $0 --manual-cleanup # Manual cleanup when resource file is missing"
}

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Run main function
main "$@"
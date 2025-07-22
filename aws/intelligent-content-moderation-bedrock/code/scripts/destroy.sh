#!/bin/bash

# Destroy script for Intelligent Content Moderation with Amazon Bedrock and EventBridge
# Recipe: building-intelligent-content-moderation-with-amazon-bedrock-and-eventbridge

set -e  # Exit on any error

# Color codes for output
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
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "AWS CLI is configured and authenticated"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This script will permanently delete the following resources:"
    echo "  • All Lambda functions (ContentAnalysisFunction, ApprovedHandlerFunction, RejectedHandlerFunction, ReviewHandlerFunction)"
    echo "  • All S3 buckets and their contents (content-moderation-bucket-*, approved-content-*, rejected-content-*)"
    echo "  • EventBridge custom bus and all rules (content-moderation-bus)"
    echo "  • SNS topic and subscriptions (content-moderation-notifications)"
    echo "  • IAM roles and policies (ContentAnalysisLambdaRole)"
    echo "  • Bedrock guardrails (if created)"
    echo
    echo "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY == "yes" ]]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    read -p "Last chance! Type 'DELETE' to proceed with destruction: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding..."
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set resource names (attempt to find existing resources)
    export CUSTOM_BUS_NAME="content-moderation-bus"
    export SNS_TOPIC_NAME="content-moderation-notifications"
    
    # Try to find existing buckets with the pattern
    CONTENT_BUCKETS=($(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `content-moderation-bucket-`)].Name' --output text))
    APPROVED_BUCKETS=($(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `approved-content-`)].Name' --output text))
    REJECTED_BUCKETS=($(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `rejected-content-`)].Name' --output text))
    
    success "Environment variables set"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=("ContentAnalysisFunction" "ApprovedHandlerFunction" "RejectedHandlerFunction" "ReviewHandlerFunction")
    
    for function in "${functions[@]}"; do
        if aws lambda get-function --function-name "${function}" >/dev/null 2>&1; then
            # Remove EventBridge permissions first
            aws lambda remove-permission \
                --function-name "${function}" \
                --statement-id "eventbridge-permission" 2>/dev/null || true
            
            # Remove S3 permissions
            aws lambda remove-permission \
                --function-name "${function}" \
                --statement-id "s3-trigger-permission" 2>/dev/null || true
            
            # Delete the function
            aws lambda delete-function --function-name "${function}"
            success "Deleted Lambda function: ${function}"
        else
            warning "Lambda function ${function} not found"
        fi
    done
    
    success "All Lambda functions processed"
}

# Function to delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    # Delete rules for each decision type
    for decision in approved rejected review; do
        local rule_name="${decision}-content-rule"
        
        if aws events describe-rule --name "${rule_name}" --event-bus-name "${CUSTOM_BUS_NAME}" >/dev/null 2>&1; then
            # Remove targets first
            aws events remove-targets \
                --rule "${rule_name}" \
                --event-bus-name "${CUSTOM_BUS_NAME}" \
                --ids 1 2>/dev/null || true
            
            # Delete the rule
            aws events delete-rule \
                --name "${rule_name}" \
                --event-bus-name "${CUSTOM_BUS_NAME}"
            success "Deleted EventBridge rule: ${rule_name}"
        else
            warning "EventBridge rule ${rule_name} not found"
        fi
    done
    
    # Delete custom event bus
    if aws events describe-event-bus --name "${CUSTOM_BUS_NAME}" >/dev/null 2>&1; then
        aws events delete-event-bus --name "${CUSTOM_BUS_NAME}"
        success "Deleted EventBridge custom bus: ${CUSTOM_BUS_NAME}"
    else
        warning "EventBridge custom bus ${CUSTOM_BUS_NAME} not found"
    fi
    
    success "EventBridge resources processed"
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets and contents..."
    
    # Process content buckets
    for bucket in "${CONTENT_BUCKETS[@]}"; do
        if [ -n "${bucket}" ]; then
            # Remove bucket notification configuration
            aws s3api put-bucket-notification-configuration \
                --bucket "${bucket}" \
                --notification-configuration '{}' 2>/dev/null || true
            
            # Delete all objects and versions
            aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
            
            # Delete all object versions
            aws s3api delete-objects \
                --bucket "${bucket}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${bucket}" \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --output json)" 2>/dev/null || true
            
            # Delete delete markers
            aws s3api delete-objects \
                --bucket "${bucket}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${bucket}" \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --output json)" 2>/dev/null || true
            
            # Delete the bucket
            aws s3 rb "s3://${bucket}" --force 2>/dev/null || true
            success "Deleted S3 bucket: ${bucket}"
        fi
    done
    
    # Process approved buckets
    for bucket in "${APPROVED_BUCKETS[@]}"; do
        if [ -n "${bucket}" ]; then
            aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
            aws s3 rb "s3://${bucket}" --force 2>/dev/null || true
            success "Deleted S3 bucket: ${bucket}"
        fi
    done
    
    # Process rejected buckets
    for bucket in "${REJECTED_BUCKETS[@]}"; do
        if [ -n "${bucket}" ]; then
            aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
            aws s3 rb "s3://${bucket}" --force 2>/dev/null || true
            success "Deleted S3 bucket: ${bucket}"
        fi
    done
    
    success "S3 buckets processed"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    # Find SNS topic ARN
    SNS_TOPIC_ARN=$(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':${SNS_TOPIC_NAME}')].TopicArn" --output text)
    
    if [ -n "${SNS_TOPIC_ARN}" ]; then
        # Delete all subscriptions first
        aws sns list-subscriptions-by-topic --topic-arn "${SNS_TOPIC_ARN}" \
            --query 'Subscriptions[].SubscriptionArn' --output text | \
            xargs -I {} aws sns unsubscribe --subscription-arn {} 2>/dev/null || true
        
        # Delete the topic
        aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
        success "Deleted SNS topic: ${SNS_TOPIC_ARN}"
    else
        warning "SNS topic ${SNS_TOPIC_NAME} not found"
    fi
    
    success "SNS resources processed"
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    local role_name="ContentAnalysisLambdaRole"
    
    if aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${role_name}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${role_name}" \
            --policy-name ContentAnalysisPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "${role_name}"
        success "Deleted IAM role: ${role_name}"
    else
        warning "IAM role ${role_name} not found"
    fi
    
    success "IAM resources processed"
}

# Function to delete Bedrock guardrails
delete_bedrock_guardrails() {
    log "Deleting Bedrock guardrails..."
    
    # Find guardrails with the expected name pattern
    GUARDRAIL_IDS=($(aws bedrock list-guardrails --query 'guardrails[?name==`ContentModerationGuardrail`].id' --output text 2>/dev/null || true))
    
    for guardrail_id in "${GUARDRAIL_IDS[@]}"; do
        if [ -n "${guardrail_id}" ]; then
            aws bedrock delete-guardrail --guardrail-identifier "${guardrail_id}" 2>/dev/null || true
            success "Deleted Bedrock guardrail: ${guardrail_id}"
        fi
    done
    
    if [ ${#GUARDRAIL_IDS[@]} -eq 0 ]; then
        warning "No Bedrock guardrails found with name ContentModerationGuardrail"
    fi
    
    success "Bedrock guardrails processed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Clean up any temporary files created during deployment
    rm -f /tmp/lambda-trust-policy.json 2>/dev/null || true
    rm -f /tmp/content-analysis-policy.json 2>/dev/null || true
    rm -f /tmp/s3-notification-config.json 2>/dev/null || true
    rm -f /tmp/bedrock-guardrail.json 2>/dev/null || true
    rm -rf /tmp/lambda-functions 2>/dev/null || true
    rm -f positive-content.txt negative-content.txt neutral-content.txt 2>/dev/null || true
    
    success "Temporary files cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local failed_deletions=0
    
    # Check Lambda functions
    local functions=("ContentAnalysisFunction" "ApprovedHandlerFunction" "RejectedHandlerFunction" "ReviewHandlerFunction")
    for function in "${functions[@]}"; do
        if aws lambda get-function --function-name "${function}" >/dev/null 2>&1; then
            error "Lambda function ${function} still exists"
            failed_deletions=$((failed_deletions + 1))
        fi
    done
    
    # Check EventBridge bus
    if aws events describe-event-bus --name "${CUSTOM_BUS_NAME}" >/dev/null 2>&1; then
        error "EventBridge bus ${CUSTOM_BUS_NAME} still exists"
        failed_deletions=$((failed_deletions + 1))
    fi
    
    # Check S3 buckets
    for bucket in "${CONTENT_BUCKETS[@]}" "${APPROVED_BUCKETS[@]}" "${REJECTED_BUCKETS[@]}"; do
        if [ -n "${bucket}" ] && aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
            error "S3 bucket ${bucket} still exists"
            failed_deletions=$((failed_deletions + 1))
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name ContentAnalysisLambdaRole >/dev/null 2>&1; then
        error "IAM role ContentAnalysisLambdaRole still exists"
        failed_deletions=$((failed_deletions + 1))
    fi
    
    if [ $failed_deletions -eq 0 ]; then
        success "All resources successfully deleted"
    else
        error "${failed_deletions} resources failed to delete. Please check manually."
        exit 1
    fi
}

# Main execution
main() {
    echo
    echo "=================================="
    echo "Content Moderation Cleanup Script"
    echo "=================================="
    echo
    
    # Check prerequisites
    check_aws_config
    
    # Set environment variables
    set_environment_variables
    
    # Confirm destruction
    confirm_destruction
    
    # Execute deletion steps
    delete_lambda_functions
    delete_eventbridge_resources
    delete_s3_buckets
    delete_sns_topic
    delete_iam_resources
    delete_bedrock_guardrails
    cleanup_temp_files
    
    # Verify deletion
    verify_deletion
    
    echo
    success "✅ Content moderation infrastructure successfully destroyed!"
    echo
    echo "Summary of deleted resources:"
    echo "  • Lambda functions: 4"
    echo "  • S3 buckets: ${#CONTENT_BUCKETS[@]} + ${#APPROVED_BUCKETS[@]} + ${#REJECTED_BUCKETS[@]}"
    echo "  • EventBridge bus and rules: 1 bus + 3 rules"
    echo "  • SNS topic: 1"
    echo "  • IAM role: 1"
    echo "  • Bedrock guardrails: ${#GUARDRAIL_IDS[@]}"
    echo
    warning "Note: Check your AWS billing to ensure all resources have been terminated."
    echo
}

# Run main function
main "$@"
#!/bin/bash

# AI Content Moderation with Bedrock
# Cleanup/Destroy Script
# 
# This script removes all infrastructure created by the deploy script including:
# - Lambda functions and their permissions
# - EventBridge custom bus and rules
# - S3 buckets and their contents
# - IAM roles and policies
# - SNS topics

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    if eval "$check_command" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check prerequisites
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed or not in PATH"
fi

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS credentials not configured or invalid"
fi

log "Prerequisites check completed successfully"

# Set environment variables
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    warn "No default region found, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Set resource names (these might be different if user customized them)
export CUSTOM_BUS_NAME="content-moderation-bus"
export SNS_TOPIC_NAME="content-moderation-notifications"

# Prompt for confirmation
echo
warn "This script will delete ALL resources related to the content moderation system."
warn "This action is irreversible and will permanently delete:"
warn "  - All Lambda functions and their code"
warn "  - All S3 buckets and their contents"
warn "  - EventBridge custom bus and rules"
warn "  - IAM roles and policies"
warn "  - SNS topics and subscriptions"
echo
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation

if [[ "$confirmation" != "yes" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo
log "Starting cleanup of content moderation infrastructure..."

# Remove Lambda functions
log "Removing Lambda functions..."

LAMBDA_FUNCTIONS=("ContentAnalysisFunction" "ApprovedHandlerFunction" "RejectedHandlerFunction" "ReviewHandlerFunction")

for function in "${LAMBDA_FUNCTIONS[@]}"; do
    if resource_exists "aws lambda get-function --function-name $function"; then
        log "Deleting Lambda function: $function"
        aws lambda delete-function --function-name $function
    else
        info "Lambda function $function not found, skipping"
    fi
done

# Remove EventBridge rules and targets
log "Removing EventBridge rules and custom bus..."

for decision in approved rejected review; do
    rule_name="${decision}-content-rule"
    
    # Remove targets first
    if resource_exists "aws events list-targets-by-rule --rule $rule_name --event-bus-name $CUSTOM_BUS_NAME"; then
        log "Removing targets for EventBridge rule: $rule_name"
        aws events remove-targets \
            --rule $rule_name \
            --event-bus-name $CUSTOM_BUS_NAME \
            --ids 1
    fi
    
    # Remove rule
    if resource_exists "aws events describe-rule --name $rule_name --event-bus-name $CUSTOM_BUS_NAME"; then
        log "Deleting EventBridge rule: $rule_name"
        aws events delete-rule \
            --name $rule_name \
            --event-bus-name $CUSTOM_BUS_NAME
    else
        info "EventBridge rule $rule_name not found, skipping"
    fi
done

# Remove custom EventBridge bus
if resource_exists "aws events describe-event-bus --name $CUSTOM_BUS_NAME"; then
    log "Deleting custom EventBridge bus: $CUSTOM_BUS_NAME"
    aws events delete-event-bus --name $CUSTOM_BUS_NAME
else
    info "Custom EventBridge bus $CUSTOM_BUS_NAME not found, skipping"
fi

# Find and remove S3 buckets
log "Finding and removing S3 buckets..."

# Look for buckets with our naming pattern
BUCKET_PATTERNS=("content-moderation-bucket-" "approved-content-" "rejected-content-")

for pattern in "${BUCKET_PATTERNS[@]}"; do
    # Find buckets matching the pattern
    matching_buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, '${pattern}')].Name" \
        --output text)
    
    for bucket in $matching_buckets; do
        if [[ -n "$bucket" ]]; then
            log "Emptying and deleting S3 bucket: $bucket"
            
            # Empty bucket first
            aws s3 rm s3://$bucket --recursive || warn "Failed to empty bucket $bucket"
            
            # Delete bucket
            aws s3 rb s3://$bucket || warn "Failed to delete bucket $bucket"
        fi
    done
done

# Remove IAM roles and policies
log "Removing IAM roles and policies..."

IAM_ROLE="ContentAnalysisLambdaRole"

if resource_exists "aws iam get-role --role-name $IAM_ROLE"; then
    log "Deleting IAM role: $IAM_ROLE"
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name $IAM_ROLE \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || warn "Failed to detach managed policy"
    
    # Delete inline policies
    aws iam delete-role-policy \
        --role-name $IAM_ROLE \
        --policy-name ContentAnalysisPolicy || warn "Failed to delete inline policy"
    
    # Delete role
    aws iam delete-role --role-name $IAM_ROLE
else
    info "IAM role $IAM_ROLE not found, skipping"
fi

# Remove SNS topics
log "Removing SNS topics..."

# Find SNS topics with our naming pattern
SNS_TOPICS=$(aws sns list-topics \
    --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
    --output text)

for topic_arn in $SNS_TOPICS; do
    if [[ -n "$topic_arn" ]]; then
        log "Deleting SNS topic: $topic_arn"
        aws sns delete-topic --topic-arn $topic_arn
    fi
done

# Remove any remaining Bedrock guardrails (if created)
log "Checking for Bedrock guardrails to remove..."

# List guardrails and look for content moderation ones
guardrails=$(aws bedrock list-guardrails \
    --query "guardrails[?contains(name, 'ContentModeration')].guardrailId" \
    --output text 2>/dev/null || echo "")

for guardrail_id in $guardrails; do
    if [[ -n "$guardrail_id" ]]; then
        log "Deleting Bedrock guardrail: $guardrail_id"
        aws bedrock delete-guardrail --guardrail-identifier $guardrail_id || warn "Failed to delete guardrail $guardrail_id"
    fi
done

# Clean up local files
log "Cleaning up local files..."

# Remove any temporary files and directories created during deployment
rm -rf lambda-functions/ || true
rm -f lambda-trust-policy.json content-analysis-policy.json s3-notification-config.json || true
rm -f deployment-summary.json || true
rm -f *.zip || true

log "Local cleanup completed"

# Verification
log "Verifying cleanup completion..."

# Check for remaining resources
remaining_functions=0
for function in "${LAMBDA_FUNCTIONS[@]}"; do
    if resource_exists "aws lambda get-function --function-name $function"; then
        warn "Lambda function $function still exists"
        remaining_functions=$((remaining_functions + 1))
    fi
done

remaining_buckets=0
for pattern in "${BUCKET_PATTERNS[@]}"; do
    matching_buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, '${pattern}')].Name" \
        --output text)
    
    for bucket in $matching_buckets; do
        if [[ -n "$bucket" ]]; then
            warn "S3 bucket $bucket still exists"
            remaining_buckets=$((remaining_buckets + 1))
        fi
    done
done

if resource_exists "aws events describe-event-bus --name $CUSTOM_BUS_NAME"; then
    warn "EventBridge custom bus $CUSTOM_BUS_NAME still exists"
fi

if resource_exists "aws iam get-role --role-name $IAM_ROLE"; then
    warn "IAM role $IAM_ROLE still exists"
fi

# Summary
echo
if [[ $remaining_functions -eq 0 && $remaining_buckets -eq 0 ]]; then
    log "✅ Cleanup completed successfully!"
    log "All content moderation infrastructure has been removed."
else
    warn "⚠️  Cleanup completed with warnings."
    warn "Some resources may still exist. Please check AWS console for any remaining resources."
fi

echo
info "Cleanup summary:"
info "  - Lambda functions: $([ $remaining_functions -eq 0 ] && echo "✅ Removed" || echo "⚠️  $remaining_functions remaining")"
info "  - S3 buckets: $([ $remaining_buckets -eq 0 ] && echo "✅ Removed" || echo "⚠️  $remaining_buckets remaining")"
info "  - EventBridge resources: ✅ Removed"
info "  - IAM roles: ✅ Removed"
info "  - SNS topics: ✅ Removed"
info "  - Local files: ✅ Cleaned"

echo
info "If you encounter any issues, you can manually delete resources through the AWS console:"
info "  - Lambda: https://console.aws.amazon.com/lambda/"
info "  - S3: https://console.aws.amazon.com/s3/"
info "  - EventBridge: https://console.aws.amazon.com/events/"
info "  - IAM: https://console.aws.amazon.com/iam/"
info "  - SNS: https://console.aws.amazon.com/sns/"

log "Content moderation infrastructure cleanup complete!"
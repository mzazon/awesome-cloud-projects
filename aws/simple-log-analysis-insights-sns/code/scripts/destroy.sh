#!/bin/bash

# Destroy script for Simple Log Analysis with CloudWatch Insights and SNS
# This script removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Destroy script for Simple Log Analysis with CloudWatch Insights and SNS

Usage: $0 [OPTIONS]

Options:
    -f, --force            Skip confirmation prompts (use with caution)
    -k, --keep-logs        Keep CloudWatch log group and data
    -v, --verbose          Enable verbose logging
    -s, --state-file FILE  Custom deployment state file path
    -h, --help             Show this help message

Example:
    $0                     # Interactive cleanup with confirmations
    $0 --force             # Automatic cleanup without prompts
    $0 --keep-logs         # Cleanup but preserve log data

WARNING: This will permanently delete all resources created by the deployment.
Make sure you have backed up any important log data before proceeding.

EOF
}

# Default values
FORCE=false
KEEP_LOGS=false
VERBOSE=false
STATE_FILE=".deployment_state"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--state-file)
            STATE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

log "Starting cleanup of Simple Log Analysis with CloudWatch Insights and SNS"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Cannot proceed with cleanup."
    exit 1
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

# Load deployment state if available
if [[ -f "$STATE_FILE" ]]; then
    log "Loading deployment state from $STATE_FILE"
    source "$STATE_FILE"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log "Loaded state variables:"
        log "  AWS_REGION: ${AWS_REGION:-'not set'}"
        log "  LOG_GROUP_NAME: ${LOG_GROUP_NAME:-'not set'}"
        log "  SNS_TOPIC_NAME: ${SNS_TOPIC_NAME:-'not set'}"
        log "  LAMBDA_FUNCTION_NAME: ${LAMBDA_FUNCTION_NAME:-'not set'}"
        log "  IAM_ROLE_NAME: ${IAM_ROLE_NAME:-'not set'}"
        log "  EVENTBRIDGE_RULE_NAME: ${EVENTBRIDGE_RULE_NAME:-'not set'}"
    fi
else
    warning "Deployment state file not found at $STATE_FILE"
    warning "This might indicate the deployment was not completed or state file was moved."
    warning "You may need to manually clean up resources or provide resource names."
    
    if [[ "$FORCE" == "false" ]]; then
        read -p "Do you want to continue with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Try to guess resource names or ask for input
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
            warning "Using default region: $AWS_REGION"
        fi
    fi
    
    log "Manual cleanup mode - you may need to provide resource identifiers"
fi

# Set AWS region
export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-east-1"
    warning "No AWS region configured. Using us-east-1 as default."
fi

log "Using AWS Region: $AWS_REGION"

# Confirmation prompt unless --force is used
if [[ "$FORCE" == "false" ]]; then
    echo
    warning "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
    warning "This script will permanently delete the following AWS resources:"
    [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]] && warning "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && warning "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [[ -n "${IAM_ROLE_NAME:-}" ]] && warning "  - IAM Role: ${IAM_ROLE_NAME}"
    [[ -n "${SNS_TOPIC_ARN:-}" ]] && warning "  - SNS Topic: ${SNS_TOPIC_ARN}"
    [[ -n "${SNS_TOPIC_NAME:-}" ]] && warning "  - SNS Topic: ${SNS_TOPIC_NAME}"
    if [[ "$KEEP_LOGS" == "false" && -n "${LOG_GROUP_NAME:-}" ]]; then
        warning "  - CloudWatch Log Group: ${LOG_GROUP_NAME} (including all log data)"
    fi
    echo
    warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    echo
fi

log "Starting resource cleanup..."

# Keep track of cleanup status
CLEANUP_ERRORS=0

# Function to handle cleanup errors
handle_error() {
    local resource="$1"
    local error_msg="$2"
    error "Failed to delete $resource: $error_msg"
    ((CLEANUP_ERRORS++))
    if [[ "$VERBOSE" == "true" ]]; then
        error "Detailed error: $error_msg"
    fi
}

# Step 1: Remove EventBridge Rule and Targets
if [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]]; then
    log "Step 1: Removing EventBridge Rule..."
    
    # Remove targets first
    if aws events remove-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --ids "1" \
        --region "${AWS_REGION}" 2>/dev/null; then
        success "EventBridge targets removed"
    else
        handle_error "EventBridge targets" "Target removal failed or rule doesn't exist"
    fi
    
    # Delete the rule
    if aws events delete-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --region "${AWS_REGION}" 2>/dev/null; then
        success "EventBridge rule deleted: ${EVENTBRIDGE_RULE_NAME}"
    else
        handle_error "EventBridge rule" "Rule deletion failed or rule doesn't exist"
    fi
else
    warning "EventBridge rule name not found in state. Skipping..."
fi

# Step 2: Delete Lambda Function
if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
    log "Step 2: Deleting Lambda Function..."
    
    if aws lambda delete-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --region "${AWS_REGION}" 2>/dev/null; then
        success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        handle_error "Lambda function" "Function deletion failed or function doesn't exist"
    fi
else
    warning "Lambda function name not found in state. Skipping..."
fi

# Step 3: Delete IAM Role and Policies
if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
    log "Step 3: Deleting IAM Role and Policies..."
    
    # Delete inline policies
    if aws iam delete-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name LogAnalyzerPolicy 2>/dev/null; then
        success "Inline policy deleted"
    else
        handle_error "IAM inline policy" "Policy deletion failed or policy doesn't exist"
    fi
    
    # Detach managed policies
    if aws iam detach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null; then
        success "Managed policy detached"
    else
        handle_error "IAM managed policy" "Policy detachment failed or policy not attached"
    fi
    
    # Delete the role
    if aws iam delete-role \
        --role-name "${IAM_ROLE_NAME}" 2>/dev/null; then
        success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        handle_error "IAM role" "Role deletion failed or role doesn't exist"
    fi
else
    warning "IAM role name not found in state. Skipping..."
fi

# Step 4: Delete SNS Topic
if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
    log "Step 4: Deleting SNS Topic..."
    
    if aws sns delete-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --region "${AWS_REGION}" 2>/dev/null; then
        success "SNS topic deleted: ${SNS_TOPIC_ARN}"
    else
        handle_error "SNS topic" "Topic deletion failed or topic doesn't exist"
    fi
elif [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
    log "Step 4: Deleting SNS Topic by name..."
    
    # Get topic ARN first
    TOPIC_ARN=$(aws sns list-topics --region "${AWS_REGION}" --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text 2>/dev/null)
    
    if [[ -n "$TOPIC_ARN" ]]; then
        if aws sns delete-topic \
            --topic-arn "$TOPIC_ARN" \
            --region "${AWS_REGION}" 2>/dev/null; then
            success "SNS topic deleted: $TOPIC_ARN"
        else
            handle_error "SNS topic" "Topic deletion failed"
        fi
    else
        warning "SNS topic not found: ${SNS_TOPIC_NAME}"
    fi
else
    warning "SNS topic information not found in state. Skipping..."
fi

# Step 5: Delete CloudWatch Log Group (unless --keep-logs is specified)
if [[ "$KEEP_LOGS" == "false" && -n "${LOG_GROUP_NAME:-}" ]]; then
    log "Step 5: Deleting CloudWatch Log Group..."
    
    if aws logs delete-log-group \
        --log-group-name "${LOG_GROUP_NAME}" \
        --region "${AWS_REGION}" 2>/dev/null; then
        success "CloudWatch log group deleted: ${LOG_GROUP_NAME}"
    else
        handle_error "CloudWatch log group" "Log group deletion failed or log group doesn't exist"
    fi
elif [[ "$KEEP_LOGS" == "true" ]]; then
    log "Step 5: Keeping CloudWatch Log Group as requested..."
    warning "Log group preserved: ${LOG_GROUP_NAME:-'unknown'}"
else
    warning "Log group name not found in state. Skipping..."
fi

# Step 6: Clean up local files
log "Step 6: Cleaning up local files..."

LOCAL_FILES=(
    "lambda-trust-policy.json"
    "lambda-permissions-policy.json"
    "log_analyzer.py"
    "lambda-function.zip"
    "lambda-response.json"
    "test-response.json"
)

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        [[ "$VERBOSE" == "true" ]] && success "Removed local file: $file"
    fi
done

# Remove deployment state file if requested
if [[ "$FORCE" == "true" || "$CLEANUP_ERRORS" -eq 0 ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        success "Deployment state file removed: $STATE_FILE"
    fi
else
    warning "Keeping deployment state file due to cleanup errors"
fi

success "Local cleanup completed"

# Final summary
echo
log "=== CLEANUP SUMMARY ==="
if [[ "$CLEANUP_ERRORS" -eq 0 ]]; then
    success "🎉 All resources cleaned up successfully!"
    log "The following resources have been removed:"
    [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]] && log "  ✅ EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && log "  ✅ Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [[ -n "${IAM_ROLE_NAME:-}" ]] && log "  ✅ IAM Role: ${IAM_ROLE_NAME}"
    [[ -n "${SNS_TOPIC_ARN:-}${SNS_TOPIC_NAME:-}" ]] && log "  ✅ SNS Topic"
    if [[ "$KEEP_LOGS" == "false" && -n "${LOG_GROUP_NAME:-}" ]]; then
        log "  ✅ CloudWatch Log Group: ${LOG_GROUP_NAME}"
    elif [[ "$KEEP_LOGS" == "true" ]]; then
        log "  ⏭️  CloudWatch Log Group: ${LOG_GROUP_NAME:-'unknown'} (preserved)"
    fi
    log "  ✅ Local temporary files"
    echo
    log "No AWS resources remain from this deployment."
    if [[ "$KEEP_LOGS" == "true" ]]; then
        warning "Note: CloudWatch log group was preserved and may incur storage costs."
    fi
else
    warning "⚠️  Cleanup completed with $CLEANUP_ERRORS errors"
    error "Some resources may not have been properly deleted."
    error "Please check the AWS console to verify all resources are removed."
    echo
    log "You may need to manually delete remaining resources:"
    log "1. Check CloudWatch → Log groups"
    log "2. Check SNS → Topics"
    log "3. Check Lambda → Functions"
    log "4. Check IAM → Roles"
    log "5. Check EventBridge → Rules"
    echo
    exit 1
fi

echo
log "Thank you for using the Simple Log Analysis with CloudWatch Insights and SNS solution!"
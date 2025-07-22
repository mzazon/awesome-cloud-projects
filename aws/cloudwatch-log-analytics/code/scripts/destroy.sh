#!/bin/bash

# Destroy script for CloudWatch Log Analytics with Insights
# This script removes all resources created by the deployment script

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [[ "$DRY_RUN" == "true" ]]; then
    log "Running in dry-run mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        log "[DRY-RUN] Description: $description"
        return 0
    else
        log "Executing: $description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || true
        else
            eval "$cmd"
        fi
        return $?
    fi
}

# Banner
echo "=============================================="
echo "  Log Analytics Solutions Cleanup Script"
echo "=============================================="
echo

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
fi

success "Prerequisites check completed"

# Load deployment information
DEPLOYMENT_INFO_FILE="./deployment-info.json"
if [[ -f "$DEPLOYMENT_INFO_FILE" ]] && command -v jq &> /dev/null; then
    log "Loading deployment information from $DEPLOYMENT_INFO_FILE"
    
    AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_INFO_FILE")
    AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_INFO_FILE")
    LOG_GROUP_NAME=$(jq -r '.resources.log_group_name' "$DEPLOYMENT_INFO_FILE")
    SNS_TOPIC_NAME=$(jq -r '.resources.sns_topic_name' "$DEPLOYMENT_INFO_FILE")
    SNS_TOPIC_ARN=$(jq -r '.resources.sns_topic_arn' "$DEPLOYMENT_INFO_FILE")
    LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name' "$DEPLOYMENT_INFO_FILE")
    LAMBDA_ROLE_ARN=$(jq -r '.resources.lambda_role_arn' "$DEPLOYMENT_INFO_FILE")
    NOTIFICATION_EMAIL=$(jq -r '.resources.notification_email' "$DEPLOYMENT_INFO_FILE")
    
    log "Loaded deployment information:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Log Group: $LOG_GROUP_NAME"
    log "  SNS Topic: $SNS_TOPIC_NAME"
    log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "  Notification Email: $NOTIFICATION_EMAIL"
else
    warning "Deployment info file not found or jq not available. Using environment variables and defaults."
    
    # Fallback to environment variables or prompts
    AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    if [[ -z "$LOG_GROUP_NAME" ]]; then
        read -p "Enter the log group name to delete: " LOG_GROUP_NAME
    fi
    
    if [[ -z "$SNS_TOPIC_NAME" ]]; then
        read -p "Enter the SNS topic name to delete: " SNS_TOPIC_NAME
    fi
    
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
        read -p "Enter the Lambda function name to delete: " LAMBDA_FUNCTION_NAME
    fi
    
    # Construct ARNs
    if [[ -n "$SNS_TOPIC_NAME" ]]; then
        SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
    
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role"
    fi
fi

# Validation
if [[ -z "$LOG_GROUP_NAME" && -z "$SNS_TOPIC_NAME" && -z "$LAMBDA_FUNCTION_NAME" ]]; then
    error "No resources specified for deletion. Please provide resource names or ensure deployment-info.json exists."
fi

# Confirmation prompt
if [[ "$FORCE_DELETE" == "false" && "$DRY_RUN" == "false" ]]; then
    echo
    warning "This will permanently delete the following resources:"
    [[ -n "$LOG_GROUP_NAME" ]] && echo "  - CloudWatch Log Group: $LOG_GROUP_NAME"
    [[ -n "$SNS_TOPIC_NAME" ]] && echo "  - SNS Topic: $SNS_TOPIC_NAME"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "  - IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "  - CloudWatch Events Rule: ${LAMBDA_FUNCTION_NAME}-schedule"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "  - IAM Policy: ${LAMBDA_FUNCTION_NAME}-logs-policy"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Start cleanup process
log "Starting cleanup process..."

# Step 1: Remove CloudWatch Events rule and targets
if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    log "Step 1: Removing CloudWatch Events rule and targets..."
    
    # Remove targets first
    execute_command "aws events remove-targets \
        --rule '${LAMBDA_FUNCTION_NAME}-schedule' \
        --ids '1'" "Removing targets from CloudWatch Events rule" true
    
    # Remove the rule
    execute_command "aws events delete-rule \
        --name '${LAMBDA_FUNCTION_NAME}-schedule'" "Deleting CloudWatch Events rule" true
    
    success "CloudWatch Events rule and targets removed"
fi

# Step 2: Delete Lambda function
if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    log "Step 2: Deleting Lambda function..."
    
    # Remove Lambda permission first
    execute_command "aws lambda remove-permission \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --statement-id allow-eventbridge" "Removing Lambda permission for EventBridge" true
    
    # Delete the function
    execute_command "aws lambda delete-function \
        --function-name '$LAMBDA_FUNCTION_NAME'" "Deleting Lambda function" true
    
    success "Lambda function deleted"
fi

# Step 3: Remove IAM role and policies
if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    log "Step 3: Removing IAM role and policies..."
    
    # Detach managed policies
    execute_command "aws iam detach-role-policy \
        --role-name '${LAMBDA_FUNCTION_NAME}-role' \
        --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'" "Detaching Lambda basic execution policy" true
    
    execute_command "aws iam detach-role-policy \
        --role-name '${LAMBDA_FUNCTION_NAME}-role' \
        --policy-arn 'arn:aws:iam::aws:policy/AmazonSNSFullAccess'" "Detaching SNS full access policy" true
    
    # Detach custom policy
    execute_command "aws iam detach-role-policy \
        --role-name '${LAMBDA_FUNCTION_NAME}-role' \
        --policy-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-logs-policy'" "Detaching custom logs policy" true
    
    # Delete custom policy
    execute_command "aws iam delete-policy \
        --policy-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-logs-policy'" "Deleting custom logs policy" true
    
    # Delete IAM role
    execute_command "aws iam delete-role \
        --role-name '${LAMBDA_FUNCTION_NAME}-role'" "Deleting IAM role" true
    
    success "IAM role and policies removed"
fi

# Step 4: Delete SNS topic
if [[ -n "$SNS_TOPIC_ARN" ]]; then
    log "Step 4: Deleting SNS topic..."
    
    # List subscriptions before deletion (for logging)
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Current SNS subscriptions:"
        aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --query 'Subscriptions[*].[Protocol,Endpoint]' --output table 2>/dev/null || log "No subscriptions found or topic doesn't exist"
    fi
    
    # Delete the topic (this will also delete all subscriptions)
    execute_command "aws sns delete-topic --topic-arn '$SNS_TOPIC_ARN'" "Deleting SNS topic" true
    
    success "SNS topic deleted"
fi

# Step 5: Delete CloudWatch Log Group
if [[ -n "$LOG_GROUP_NAME" ]]; then
    log "Step 5: Deleting CloudWatch Log Group..."
    
    # Check if log group exists before deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
            log "Log group exists, proceeding with deletion"
        else
            warning "Log group $LOG_GROUP_NAME does not exist, skipping deletion"
        fi
    fi
    
    # Delete log group
    execute_command "aws logs delete-log-group \
        --log-group-name '$LOG_GROUP_NAME'" "Deleting CloudWatch Log Group" true
    
    success "CloudWatch Log Group deleted"
fi

# Step 6: Clean up local files
log "Step 6: Cleaning up local files..."

# Remove deployment info file
if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
    execute_command "rm -f '$DEPLOYMENT_INFO_FILE'" "Removing deployment info file" true
    success "Deployment info file removed"
fi

# Remove any temporary files that might have been left behind
execute_command "rm -f lambda_function.py lambda-function.zip response.json trust-policy.json logs-policy.json" "Removing temporary files" true

# Step 7: Verify cleanup
if [[ "$DRY_RUN" == "false" ]]; then
    log "Step 7: Verifying cleanup..."
    
    # Check if resources still exist
    resource_count=0
    
    # Check Lambda function
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            warning "Lambda function $LAMBDA_FUNCTION_NAME still exists"
            resource_count=$((resource_count + 1))
        fi
    fi
    
    # Check IAM role
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" &> /dev/null; then
            warning "IAM role ${LAMBDA_FUNCTION_NAME}-role still exists"
            resource_count=$((resource_count + 1))
        fi
    fi
    
    # Check SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
            warning "SNS topic $SNS_TOPIC_ARN still exists"
            resource_count=$((resource_count + 1))
        fi
    fi
    
    # Check CloudWatch Log Group
    if [[ -n "$LOG_GROUP_NAME" ]]; then
        if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
            warning "CloudWatch Log Group $LOG_GROUP_NAME still exists"
            resource_count=$((resource_count + 1))
        fi
    fi
    
    # Check CloudWatch Events rule
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        if aws events describe-rule --name "${LAMBDA_FUNCTION_NAME}-schedule" &> /dev/null; then
            warning "CloudWatch Events rule ${LAMBDA_FUNCTION_NAME}-schedule still exists"
            resource_count=$((resource_count + 1))
        fi
    fi
    
    if [[ $resource_count -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        warning "$resource_count resources may still exist. Please check manually."
    fi
fi

echo
echo "=============================================="
echo "         CLEANUP COMPLETED"
echo "=============================================="
echo

if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry-run completed. No resources were actually deleted."
    log "Run the script without --dry-run to perform the actual cleanup."
else
    success "Log Analytics Solution cleanup completed!"
    echo
    echo "Cleanup Summary:"
    echo "  🗑️  CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "  🗑️  SNS Topic: $SNS_TOPIC_NAME"
    echo "  🗑️  Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  🗑️  IAM Role and Policies: ${LAMBDA_FUNCTION_NAME}-role"
    echo "  🗑️  CloudWatch Events Rule: ${LAMBDA_FUNCTION_NAME}-schedule"
    echo "  🗑️  Local files: deployment-info.json and temporary files"
    echo
    echo "Notes:"
    echo "  - If you had confirmed the SNS email subscription, you may receive a final notification"
    echo "  - CloudWatch Logs data is permanently deleted and cannot be recovered"
    echo "  - IAM roles and policies may take a few minutes to fully propagate the deletion"
    echo
    success "All resources have been cleaned up successfully!"
fi

# Final recommendations
echo
log "Recommendations:"
echo "  1. Review your AWS bill to ensure no unexpected charges"
echo "  2. Check CloudWatch Logs for any other log groups that might be incurring charges"
echo "  3. Consider implementing automated cost monitoring for future deployments"
echo "  4. Keep deployment scripts and configurations in version control"
echo
log "Thank you for using the Log Analytics Solutions cleanup script!"
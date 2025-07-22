#!/bin/bash

# Event-Driven Microservices with EventBridge and Step Functions - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# ANSI color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Continuing with cleanup..."
}

# Set up error handling (don't exit on error for cleanup)
trap 'handle_error $LINENO' ERR

# Parse command line arguments
FORCE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Cleanup event-driven microservices architecture"
            echo ""
            echo "OPTIONS:"
            echo "  --force               Force cleanup even if some resources fail"
            echo "  --dry-run            Show what would be deleted without making changes"
            echo "  --yes                Skip confirmation prompts"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No actual changes will be made"
fi

log "Starting cleanup of Event-Driven Microservices architecture..."

# Check if deployment environment file exists
if [ -f .deployment_env ]; then
    log "Loading deployment environment variables..."
    source .deployment_env
    log_success "Environment variables loaded from .deployment_env"
else
    log_warning "No .deployment_env file found. You may need to set environment variables manually."
    
    # Try to get basic variables from AWS CLI
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Could not determine AWS Account ID. Please ensure AWS CLI is configured."
        exit 1
    fi
    
    # Prompt for resource identifiers if not found
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        echo "Please provide the random suffix used during deployment (6 characters):"
        read -r RANDOM_SUFFIX
        if [ -z "$RANDOM_SUFFIX" ]; then
            log_error "Random suffix is required for cleanup"
            exit 1
        fi
    fi
    
    # Set default values
    export PROJECT_NAME="${PROJECT_NAME:-microservices-demo}"
    export EVENTBUS_NAME="${PROJECT_NAME}-eventbus-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role-${RANDOM_SUFFIX}"
    export STEPFUNCTIONS_ROLE_NAME="${PROJECT_NAME}-stepfunctions-role-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="${PROJECT_NAME}-orders-${RANDOM_SUFFIX}"
fi

# Verification check
log "Verifying environment configuration..."
log "  AWS Region: ${AWS_REGION}"
log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
log "  Project Name: ${PROJECT_NAME:-Not Set}"
log "  Random Suffix: ${RANDOM_SUFFIX:-Not Set}"

# Safety confirmation
if [ "$SKIP_CONFIRMATION" = false ] && [ "$DRY_RUN" = false ]; then
    echo ""
    log_warning "This will DELETE all resources created by the deployment script!"
    echo "Resources to be deleted:"
    echo "  • EventBridge Bus: ${EVENTBUS_NAME:-Not Set}"
    echo "  • DynamoDB Table: ${DYNAMODB_TABLE_NAME:-Not Set}"
    echo "  • Lambda Functions: 4 microservices"
    echo "  • Step Functions State Machine"
    echo "  • IAM Roles: 2 execution roles"
    echo "  • EventBridge Rules and Targets"
    echo "  • CloudWatch Dashboard and Log Groups"
    echo ""
    echo "Are you sure you want to continue? (type 'yes' to confirm)"
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would delete all Event-Driven Microservices resources"
    exit 0
fi

# Track cleanup progress
CLEANUP_ERRORS=0

# Function to safely delete resources
safe_delete() {
    local resource_type="$1"
    local command="$2"
    local resource_name="$3"
    
    log "Deleting ${resource_type}: ${resource_name}"
    
    if eval "$command" > /dev/null 2>&1; then
        log_success "${resource_type} deleted successfully"
    else
        log_warning "Failed to delete ${resource_type}: ${resource_name}"
        ((CLEANUP_ERRORS++))
        if [ "$FORCE" = false ]; then
            log_error "Use --force to continue despite errors"
            return 1
        fi
    fi
}

# Step 1: Delete Step Functions state machine
if [ -n "${STATE_MACHINE_ARN:-}" ]; then
    safe_delete "Step Functions state machine" \
        "aws stepfunctions delete-state-machine --state-machine-arn ${STATE_MACHINE_ARN}" \
        "${STATE_MACHINE_ARN}"
else
    # Try to find state machine by name pattern
    STATE_MACHINE_NAME="${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX}"
    log "Searching for Step Functions state machine: ${STATE_MACHINE_NAME}"
    
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?contains(name, '${STATE_MACHINE_NAME}')].stateMachineArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
        safe_delete "Step Functions state machine" \
            "aws stepfunctions delete-state-machine --state-machine-arn ${STATE_MACHINE_ARN}" \
            "${STATE_MACHINE_ARN}"
    else
        log_warning "Step Functions state machine not found or already deleted"
    fi
fi

# Step 2: Remove EventBridge rules and targets
log "Removing EventBridge rules and targets..."

# Remove targets first, then rules
RULE_NAMES=(
    "${PROJECT_NAME}-order-created-rule-${RANDOM_SUFFIX}"
    "${PROJECT_NAME}-payment-events-rule-${RANDOM_SUFFIX}"
)

for rule_name in "${RULE_NAMES[@]}"; do
    log "Removing targets from rule: ${rule_name}"
    
    # Get rule targets
    targets=$(aws events list-targets-by-rule \
        --rule "$rule_name" \
        --event-bus-name "${EVENTBUS_NAME}" \
        --query 'Targets[].Id' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$targets" ] && [ "$targets" != "None" ]; then
        # Convert space-separated targets to comma-separated
        target_ids=$(echo "$targets" | tr ' ' ',')
        safe_delete "EventBridge rule targets" \
            "aws events remove-targets --rule ${rule_name} --event-bus-name ${EVENTBUS_NAME} --ids ${target_ids}" \
            "${rule_name}"
    fi
    
    # Delete the rule
    safe_delete "EventBridge rule" \
        "aws events delete-rule --name ${rule_name} --event-bus-name ${EVENTBUS_NAME}" \
        "${rule_name}"
done

# Step 3: Delete EventBridge custom bus
if [ -n "${EVENTBUS_NAME:-}" ]; then
    safe_delete "EventBridge custom bus" \
        "aws events delete-event-bus --name ${EVENTBUS_NAME}" \
        "${EVENTBUS_NAME}"
fi

# Step 4: Delete Lambda functions
log "Deleting Lambda functions..."

LAMBDA_FUNCTIONS=(
    "${PROJECT_NAME}-order-service-${RANDOM_SUFFIX}"
    "${PROJECT_NAME}-payment-service-${RANDOM_SUFFIX}"
    "${PROJECT_NAME}-inventory-service-${RANDOM_SUFFIX}"
    "${PROJECT_NAME}-notification-service-${RANDOM_SUFFIX}"
)

for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
    # Check if function exists
    if aws lambda get-function --function-name "$function_name" > /dev/null 2>&1; then
        safe_delete "Lambda function" \
            "aws lambda delete-function --function-name ${function_name}" \
            "${function_name}"
    else
        log_warning "Lambda function not found: ${function_name}"
    fi
done

# Step 5: Delete DynamoDB table
if [ -n "${DYNAMODB_TABLE_NAME:-}" ]; then
    # Check if table exists
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" > /dev/null 2>&1; then
        safe_delete "DynamoDB table" \
            "aws dynamodb delete-table --table-name ${DYNAMODB_TABLE_NAME}" \
            "${DYNAMODB_TABLE_NAME}"
        
        # Wait for table deletion to complete
        log "Waiting for DynamoDB table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE_NAME" 2>/dev/null || true
        log_success "DynamoDB table deletion completed"
    else
        log_warning "DynamoDB table not found: ${DYNAMODB_TABLE_NAME}"
    fi
fi

# Step 6: Delete CloudWatch resources
log "Deleting CloudWatch resources..."

# Delete CloudWatch dashboard
DASHBOARD_NAME="${PROJECT_NAME}-microservices-dashboard-${RANDOM_SUFFIX}"
safe_delete "CloudWatch dashboard" \
    "aws cloudwatch delete-dashboards --dashboard-names ${DASHBOARD_NAME}" \
    "${DASHBOARD_NAME}"

# Delete CloudWatch Log Group
LOG_GROUP_NAME="/aws/stepfunctions/${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX}"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0]' > /dev/null 2>&1; then
    safe_delete "CloudWatch Log Group" \
        "aws logs delete-log-group --log-group-name ${LOG_GROUP_NAME}" \
        "${LOG_GROUP_NAME}"
else
    log_warning "CloudWatch Log Group not found: ${LOG_GROUP_NAME}"
fi

# Delete Lambda Log Groups
log "Cleaning up Lambda Log Groups..."
for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
    lambda_log_group="/aws/lambda/${function_name}"
    if aws logs describe-log-groups --log-group-name-prefix "$lambda_log_group" --query 'logGroups[0]' > /dev/null 2>&1; then
        safe_delete "Lambda Log Group" \
            "aws logs delete-log-group --log-group-name ${lambda_log_group}" \
            "${lambda_log_group}"
    fi
done

# Step 7: Delete IAM roles
log "Deleting IAM roles..."

# Delete Lambda role
if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
    # Check if role exists
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" > /dev/null 2>&1; then
        log "Detaching policies from Lambda role..."
        
        # Detach managed policies
        LAMBDA_POLICIES=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/Amazon-EventBridge-FullAccess"
        )
        
        for policy_arn in "${LAMBDA_POLICIES[@]}"; do
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies if any
        inline_policies=$(aws iam list-role-policies \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$inline_policies" ] && [ "$inline_policies" != "None" ]; then
            for policy_name in $inline_policies; do
                aws iam delete-role-policy \
                    --role-name "$LAMBDA_ROLE_NAME" \
                    --policy-name "$policy_name" 2>/dev/null || true
            done
        fi
        
        safe_delete "Lambda IAM role" \
            "aws iam delete-role --role-name ${LAMBDA_ROLE_NAME}" \
            "${LAMBDA_ROLE_NAME}"
    else
        log_warning "Lambda IAM role not found: ${LAMBDA_ROLE_NAME}"
    fi
fi

# Delete Step Functions role
if [ -n "${STEPFUNCTIONS_ROLE_NAME:-}" ]; then
    # Check if role exists
    if aws iam get-role --role-name "$STEPFUNCTIONS_ROLE_NAME" > /dev/null 2>&1; then
        log "Detaching policies from Step Functions role..."
        
        # Detach managed policies
        STEPFUNCTIONS_POLICIES=(
            "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
            "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
        )
        
        for policy_arn in "${STEPFUNCTIONS_POLICIES[@]}"; do
            aws iam detach-role-policy \
                --role-name "$STEPFUNCTIONS_ROLE_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies if any
        inline_policies=$(aws iam list-role-policies \
            --role-name "$STEPFUNCTIONS_ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$inline_policies" ] && [ "$inline_policies" != "None" ]; then
            for policy_name in $inline_policies; do
                aws iam delete-role-policy \
                    --role-name "$STEPFUNCTIONS_ROLE_NAME" \
                    --policy-name "$policy_name" 2>/dev/null || true
            done
        fi
        
        safe_delete "Step Functions IAM role" \
            "aws iam delete-role --role-name ${STEPFUNCTIONS_ROLE_NAME}" \
            "${STEPFUNCTIONS_ROLE_NAME}"
    else
        log_warning "Step Functions IAM role not found: ${STEPFUNCTIONS_ROLE_NAME}"
    fi
fi

# Step 8: Clean up local files
log "Cleaning up local files..."

LOCAL_FILES=(
    ".deployment_env"
    "test-response.json"
    "test-response-1.json"
    "test-response-2.json"
    "test-response-3.json"
)

for file in "${LOCAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        log_success "Removed local file: $file"
    fi
done

# Step 9: Verification
log "Verifying resource cleanup..."

# Check if any resources still exist
REMAINING_RESOURCES=0

# Check EventBridge bus
if [ -n "${EVENTBUS_NAME:-}" ]; then
    if aws events describe-event-bus --name "$EVENTBUS_NAME" > /dev/null 2>&1; then
        log_warning "EventBridge bus still exists: $EVENTBUS_NAME"
        ((REMAINING_RESOURCES++))
    fi
fi

# Check DynamoDB table
if [ -n "${DYNAMODB_TABLE_NAME:-}" ]; then
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" > /dev/null 2>&1; then
        log_warning "DynamoDB table still exists: $DYNAMODB_TABLE_NAME"
        ((REMAINING_RESOURCES++))
    fi
fi

# Check Lambda functions
for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$function_name" > /dev/null 2>&1; then
        log_warning "Lambda function still exists: $function_name"
        ((REMAINING_RESOURCES++))
    fi
done

# Check IAM roles
if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" > /dev/null 2>&1; then
        log_warning "Lambda IAM role still exists: $LAMBDA_ROLE_NAME"
        ((REMAINING_RESOURCES++))
    fi
fi

if [ -n "${STEPFUNCTIONS_ROLE_NAME:-}" ]; then
    if aws iam get-role --role-name "$STEPFUNCTIONS_ROLE_NAME" > /dev/null 2>&1; then
        log_warning "Step Functions IAM role still exists: $STEPFUNCTIONS_ROLE_NAME"
        ((REMAINING_RESOURCES++))
    fi
fi

# Final summary
echo ""
echo "=============================================="
echo "CLEANUP SUMMARY"
echo "=============================================="

if [ $CLEANUP_ERRORS -eq 0 ] && [ $REMAINING_RESOURCES -eq 0 ]; then
    log_success "Cleanup completed successfully!"
    echo "All Event-Driven Microservices resources have been removed."
elif [ $CLEANUP_ERRORS -gt 0 ] || [ $REMAINING_RESOURCES -gt 0 ]; then
    log_warning "Cleanup completed with issues:"
    echo "  • Cleanup errors: $CLEANUP_ERRORS"
    echo "  • Remaining resources: $REMAINING_RESOURCES"
    echo ""
    if [ $CLEANUP_ERRORS -gt 0 ]; then
        echo "Some resources could not be deleted. This may be due to:"
        echo "  • Resource dependencies"
        echo "  • Insufficient permissions"
        echo "  • Resources already deleted"
        echo "  • Temporary AWS service issues"
    fi
    if [ $REMAINING_RESOURCES -gt 0 ]; then
        echo "Some resources may still exist. Check the AWS console to verify."
        echo "You may need to delete them manually or run this script again."
    fi
    echo ""
    echo "Consider using --force flag to continue despite errors."
else
    log_success "Cleanup completed!"
fi

echo ""
echo "Cleanup Summary:"
echo "  • Deleted Step Functions state machine"
echo "  • Removed EventBridge rules and targets"
echo "  • Deleted EventBridge custom bus"
echo "  • Deleted Lambda functions"
echo "  • Deleted DynamoDB table"
echo "  • Deleted CloudWatch dashboard and log groups"
echo "  • Deleted IAM roles"
echo "  • Cleaned up local files"
echo ""
echo "AWS Region: ${AWS_REGION}"
echo "Project: ${PROJECT_NAME:-Unknown}"
echo "=============================================="

# Exit with appropriate code
if [ $CLEANUP_ERRORS -gt 0 ] || [ $REMAINING_RESOURCES -gt 0 ]; then
    exit 1
else
    exit 0
fi
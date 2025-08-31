#!/bin/bash

# Canary Deployments with VPC Lattice and Lambda - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
STATE_FILE="${SCRIPT_DIR}/deployment-state.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log ERROR "$1"
    log ERROR "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm_destruction() {
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log INFO "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will permanently delete all canary deployment resources!${NC}"
    echo ""
    echo "Resources to be deleted:"
    if [[ -f "$STATE_FILE" ]]; then
        echo "- VPC Lattice Service Network and Service"
        echo "- Lambda Functions and Versions"
        echo "- Target Groups"
        echo "- IAM Roles and Policies"
        echo "- CloudWatch Alarms"
        echo "- SNS Topics"
    else
        echo "- All resources matching the canary deployment pattern"
    fi
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to load deployment state
load_deployment_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log WARN "Deployment state file not found: $STATE_FILE"
        log WARN "Will attempt to clean up resources by pattern matching"
        return 1
    fi
    
    log INFO "Loading deployment state from: $STATE_FILE"
    
    # Extract values from JSON state file
    export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$STATE_FILE" 2>/dev/null || echo "")
    export AWS_REGION=$(jq -r '.aws_region' "$STATE_FILE" 2>/dev/null || echo "")
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$STATE_FILE" 2>/dev/null || echo "")
    export SERVICE_NAME=$(jq -r '.service_name' "$STATE_FILE" 2>/dev/null || echo "")
    export FUNCTION_NAME=$(jq -r '.function_name' "$STATE_FILE" 2>/dev/null || echo "")
    export SERVICE_NETWORK_NAME=$(jq -r '.service_network_name' "$STATE_FILE" 2>/dev/null || echo "")
    export LAMBDA_ROLE_NAME=$(jq -r '.lambda_role_name' "$STATE_FILE" 2>/dev/null || echo "")
    export ROLLBACK_FUNCTION_NAME=$(jq -r '.rollback_function_name' "$STATE_FILE" 2>/dev/null || echo "")
    export LAMBDA_ROLE_ARN=$(jq -r '.lambda_role_arn' "$STATE_FILE" 2>/dev/null || echo "")
    export LAMBDA_VERSION_1=$(jq -r '.lambda_version_1' "$STATE_FILE" 2>/dev/null || echo "")
    export LAMBDA_VERSION_2=$(jq -r '.lambda_version_2' "$STATE_FILE" 2>/dev/null || echo "")
    export SERVICE_NETWORK_ID=$(jq -r '.service_network_id' "$STATE_FILE" 2>/dev/null || echo "")
    export PROD_TARGET_GROUP_ID=$(jq -r '.prod_target_group_id' "$STATE_FILE" 2>/dev/null || echo "")
    export CANARY_TARGET_GROUP_ID=$(jq -r '.canary_target_group_id' "$STATE_FILE" 2>/dev/null || echo "")
    export SERVICE_ID=$(jq -r '.service_id' "$STATE_FILE" 2>/dev/null || echo "")
    export LISTENER_ID=$(jq -r '.listener_id' "$STATE_FILE" 2>/dev/null || echo "")
    export ROLLBACK_TOPIC_ARN=$(jq -r '.rollback_topic_arn' "$STATE_FILE" 2>/dev/null || echo "")
    
    # Validate essential variables
    if [[ -z "$RANDOM_SUFFIX" || "$RANDOM_SUFFIX" == "null" ]]; then
        log ERROR "Failed to load deployment state - missing or invalid random suffix"
        return 1
    fi
    
    log INFO "✅ Deployment state loaded successfully (suffix: $RANDOM_SUFFIX)"
    return 0
}

# Function to validate prerequisites
validate_prerequisites() {
    log INFO "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' not found. Please install it and try again."
        fi
    done
    
    # Check AWS CLI authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS CLI is not configured or authentication failed. Please run 'aws configure' or set AWS credentials."
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region || echo "us-east-1")
    log INFO "✅ Authenticated to AWS Account: $account_id, Region: $region"
}

# Function to safely delete a resource with error handling
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local delete_command="$3"
    
    if [[ -z "$resource_id" || "$resource_id" == "null" ]]; then
        log WARN "Skipping $resource_type deletion - resource ID not available"
        return 0
    fi
    
    log INFO "Deleting $resource_type: $resource_id"
    
    if eval "$delete_command" >/dev/null 2>&1; then
        log INFO "✅ $resource_type deleted successfully"
    else
        log WARN "Failed to delete $resource_type: $resource_id (may not exist or already deleted)"
    fi
}

# Function to remove VPC Lattice resources
remove_vpc_lattice_resources() {
    log INFO "Removing VPC Lattice resources..."
    
    # Remove service network association first
    if [[ -n "${SERVICE_NETWORK_ID:-}" && -n "${SERVICE_ID:-}" ]]; then
        log INFO "Checking for service network associations..."
        local association_id=$(aws vpc-lattice list-service-network-service-associations \
            --service-network-identifier "$SERVICE_NETWORK_ID" \
            --query 'items[?serviceId==`'"$SERVICE_ID"'`].id' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$association_id" && "$association_id" != "null" ]]; then
            safe_delete "Service Network Association" "$association_id" \
                "aws vpc-lattice delete-service-network-service-association --service-network-service-association-identifier '$association_id'"
            
            # Wait for association to be deleted
            log INFO "Waiting for service network association to be deleted..."
            sleep 10
        fi
    fi
    
    # Delete VPC Lattice service
    safe_delete "VPC Lattice Service" "${SERVICE_ID:-}" \
        "aws vpc-lattice delete-service --service-identifier '$SERVICE_ID'"
    
    # Delete target groups
    safe_delete "Production Target Group" "${PROD_TARGET_GROUP_ID:-}" \
        "aws vpc-lattice delete-target-group --target-group-identifier '$PROD_TARGET_GROUP_ID'"
    
    safe_delete "Canary Target Group" "${CANARY_TARGET_GROUP_ID:-}" \
        "aws vpc-lattice delete-target-group --target-group-identifier '$CANARY_TARGET_GROUP_ID'"
    
    # Delete service network
    safe_delete "VPC Lattice Service Network" "${SERVICE_NETWORK_ID:-}" \
        "aws vpc-lattice delete-service-network --service-network-identifier '$SERVICE_NETWORK_ID'"
}

# Function to remove Lambda functions
remove_lambda_functions() {
    log INFO "Removing Lambda functions..."
    
    # Delete main Lambda function (this will delete all versions)
    safe_delete "Lambda Function" "${FUNCTION_NAME:-}" \
        "aws lambda delete-function --function-name '$FUNCTION_NAME'"
    
    # Delete rollback Lambda function
    safe_delete "Rollback Lambda Function" "${ROLLBACK_FUNCTION_NAME:-}" \
        "aws lambda delete-function --function-name '$ROLLBACK_FUNCTION_NAME'"
}

# Function to remove IAM resources
remove_iam_resources() {
    log INFO "Removing IAM resources..."
    
    if [[ -n "${LAMBDA_ROLE_NAME:-}" && "$LAMBDA_ROLE_NAME" != "null" ]]; then
        # Detach policies from role
        safe_delete "IAM Policy Attachment (Basic Execution)" "$LAMBDA_ROLE_NAME" \
            "aws iam detach-role-policy --role-name '$LAMBDA_ROLE_NAME' --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'"
        
        safe_delete "IAM Policy Attachment (VPC Lattice)" "$LAMBDA_ROLE_NAME" \
            "aws iam detach-role-policy --role-name '$LAMBDA_ROLE_NAME' --policy-arn 'arn:aws:iam::aws:policy/VPCLatticeServiceAccess'"
        
        # Delete IAM role
        safe_delete "IAM Role" "$LAMBDA_ROLE_NAME" \
            "aws iam delete-role --role-name '$LAMBDA_ROLE_NAME'"
    fi
}

# Function to remove CloudWatch resources
remove_cloudwatch_resources() {
    log INFO "Removing CloudWatch resources..."
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        # Delete CloudWatch alarms
        local error_alarm="canary-lambda-errors-${RANDOM_SUFFIX}"
        local duration_alarm="canary-lambda-duration-${RANDOM_SUFFIX}"
        
        safe_delete "CloudWatch Error Alarm" "$error_alarm" \
            "aws cloudwatch delete-alarms --alarm-names '$error_alarm'"
        
        safe_delete "CloudWatch Duration Alarm" "$duration_alarm" \
            "aws cloudwatch delete-alarms --alarm-names '$duration_alarm'"
    fi
}

# Function to remove SNS resources
remove_sns_resources() {
    log INFO "Removing SNS resources..."
    
    safe_delete "SNS Topic" "${ROLLBACK_TOPIC_ARN:-}" \
        "aws sns delete-topic --topic-arn '$ROLLBACK_TOPIC_ARN'"
}

# Function to cleanup by pattern matching (fallback method)
cleanup_by_pattern() {
    log INFO "Attempting cleanup by pattern matching..."
    
    local pattern_suffix=""
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        pattern_suffix="-${RANDOM_SUFFIX}"
    fi
    
    # Find and delete Lambda functions with canary pattern
    log INFO "Searching for Lambda functions with canary pattern..."
    local lambda_functions=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'canary-demo')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lambda_functions" ]]; then
        for func in $lambda_functions; do
            safe_delete "Lambda Function (pattern match)" "$func" \
                "aws lambda delete-function --function-name '$func'"
        done
    fi
    
    # Find and delete VPC Lattice service networks with canary pattern
    log INFO "Searching for VPC Lattice service networks with canary pattern..."
    local service_networks=$(aws vpc-lattice list-service-networks \
        --query "items[?contains(name, 'canary-demo')].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$service_networks" ]]; then
        for sn in $service_networks; do
            # First, delete any services associated with the network
            local services=$(aws vpc-lattice list-service-network-service-associations \
                --service-network-identifier "$sn" \
                --query "items[].serviceId" --output text 2>/dev/null || echo "")
            
            for service in $services; do
                safe_delete "VPC Lattice Service (pattern match)" "$service" \
                    "aws vpc-lattice delete-service --service-identifier '$service'"
            done
            
            safe_delete "VPC Lattice Service Network (pattern match)" "$sn" \
                "aws vpc-lattice delete-service-network --service-network-identifier '$sn'"
        done
    fi
    
    # Find and delete IAM roles with canary pattern
    log INFO "Searching for IAM roles with canary pattern..."
    local iam_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'lambda-canary-execution-role')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$iam_roles" ]]; then
        for role in $iam_roles; do
            # Detach policies first
            safe_delete "IAM Policy Attachment (pattern match)" "$role" \
                "aws iam detach-role-policy --role-name '$role' --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'"
            
            safe_delete "IAM Policy Attachment (pattern match)" "$role" \
                "aws iam detach-role-policy --role-name '$role' --policy-arn 'arn:aws:iam::aws:policy/VPCLatticeServiceAccess'"
            
            safe_delete "IAM Role (pattern match)" "$role" \
                "aws iam delete-role --role-name '$role'"
        done
    fi
    
    # Find and delete CloudWatch alarms with canary pattern
    log INFO "Searching for CloudWatch alarms with canary pattern..."
    local cw_alarms=$(aws cloudwatch describe-alarms \
        --query "MetricAlarms[?contains(AlarmName, 'canary-lambda')].AlarmName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$cw_alarms" ]]; then
        safe_delete "CloudWatch Alarms (pattern match)" "multiple" \
            "aws cloudwatch delete-alarms --alarm-names $cw_alarms"
    fi
    
    # Find and delete SNS topics with canary pattern
    log INFO "Searching for SNS topics with canary pattern..."
    local sns_topics=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'canary-rollback')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sns_topics" ]]; then
        for topic in $sns_topics; do
            safe_delete "SNS Topic (pattern match)" "$topic" \
                "aws sns delete-topic --topic-arn '$topic'"
        done
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log INFO "Cleaning up temporary files..."
    
    # Remove deployment state file
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log INFO "✅ Deployment state file removed"
    fi
    
    # Remove any temporary lambda zip files that might be left
    find /tmp -name "lambda-*.zip" -type f -mtime 0 -delete 2>/dev/null || true
    find /tmp -name "rollback-function.zip" -type f -mtime 0 -delete 2>/dev/null || true
    
    log INFO "✅ Temporary files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    log INFO "Cleanup completed successfully!"
    echo ""
    echo -e "${GREEN}=== CLEANUP SUMMARY ===${NC}"
    echo "All canary deployment resources have been removed:"
    echo "- VPC Lattice Service Network and Service"
    echo "- Lambda Functions and Versions"
    echo "- Target Groups"
    echo "- IAM Roles and Policies"
    echo "- CloudWatch Alarms"
    echo "- SNS Topics"
    echo "- Deployment state files"
    echo ""
    echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
    echo ""
}

# Main cleanup function
main() {
    log INFO "Starting canary deployment infrastructure cleanup..."
    echo "Log file: $LOG_FILE"
    
    confirm_destruction
    validate_prerequisites
    
    # Try to load deployment state, fallback to pattern matching if not available
    if load_deployment_state; then
        # Use specific resource IDs from state file
        remove_vpc_lattice_resources
        remove_lambda_functions
        remove_iam_resources
        remove_cloudwatch_resources
        remove_sns_resources
    else
        # Fallback to pattern-based cleanup
        log WARN "State file not found, attempting pattern-based cleanup"
        cleanup_by_pattern
    fi
    
    cleanup_temp_files
    display_summary
    
    log INFO "Cleanup completed successfully! Total time: ${SECONDS}s"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --force     Skip confirmation prompt"
        echo "  --help, -h  Show this help message"
        echo ""
        echo "This script removes all resources created by the canary deployment."
        echo "It will attempt to use the deployment state file for precise cleanup,"
        echo "or fall back to pattern matching if the state file is not available."
        exit 0
        ;;
    --force)
        export FORCE_DESTROY="true"
        ;;
esac

# Run main cleanup
main "$@"
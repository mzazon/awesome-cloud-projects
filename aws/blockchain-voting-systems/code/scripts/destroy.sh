#!/bin/bash

# Blockchain-Based Voting Systems - Cleanup Script
# This script safely removes all resources created by the voting system deployment
# with proper confirmation prompts and error handling

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLEANUP_LOG="${PROJECT_ROOT}/cleanup_$(date +%Y%m%d_%H%M%S).log"

# Check if running in auto-confirm mode
AUTO_CONFIRM=${AUTO_CONFIRM:-false}
DRY_RUN=${DRY_RUN:-false}

# Redirect all output to log file while still showing on screen
exec > >(tee -a "${CLEANUP_LOG}")
exec 2>&1

log "Starting Blockchain Voting System cleanup..."
log "Cleanup log: ${CLEANUP_LOG}"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        log "Auto-confirming: $action"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would ask for confirmation: $action"
        return 0
    fi
    
    echo -e "${YELLOW}Are you sure you want to $action? (y/N)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        warning "Skipping: $action"
        return 1
    fi
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f "${PROJECT_ROOT}/deployment_env.sh" ]]; then
        source "${PROJECT_ROOT}/deployment_env.sh"
        log "Loaded environment variables from deployment_env.sh"
    else
        warning "deployment_env.sh not found. Using default values or prompting for input."
        
        # Set default region if not set
        if [[ -z "${AWS_REGION:-}" ]]; then
            export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        fi
        
        # Get account ID
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
        
        # Try to find resources by common naming patterns
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            # Look for voting system buckets
            BUCKET_NAME=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `voting-system-data-`)].Name' --output text | head -1)
            export BUCKET_NAME
        fi
        
        if [[ -z "${LAMBDA_AUTH_FUNCTION:-}" ]]; then
            # Look for authentication functions
            LAMBDA_AUTH_FUNCTION=$(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `VoterAuthentication-`)].FunctionName' --output text | head -1)
            export LAMBDA_AUTH_FUNCTION
        fi
        
        if [[ -z "${LAMBDA_MONITOR_FUNCTION:-}" ]]; then
            # Look for monitoring functions
            LAMBDA_MONITOR_FUNCTION=$(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `VoteMonitoring-`)].FunctionName' --output text | head -1)
            export LAMBDA_MONITOR_FUNCTION
        fi
    fi
    
    log "Environment configuration:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "  Bucket Name: ${BUCKET_NAME:-'Not set'}"
    log "  Auth Function: ${LAMBDA_AUTH_FUNCTION:-'Not set'}"
    log "  Monitor Function: ${LAMBDA_MONITOR_FUNCTION:-'Not set'}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check completed"
}

# Function to remove CloudWatch monitoring resources
remove_monitoring_resources() {
    log "Removing CloudWatch monitoring resources..."
    
    if ! confirm_action "remove CloudWatch monitoring resources"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove CloudWatch resources"
        return 0
    fi
    
    # Remove CloudWatch alarms
    local alarms=("VotingSystem-Auth-Errors" "VotingSystem-Monitor-Errors")
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" &>/dev/null; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log "Deleted CloudWatch alarm: $alarm"
        else
            info "CloudWatch alarm $alarm not found"
        fi
    done
    
    # Remove CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name BlockchainVotingSystem &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names BlockchainVotingSystem
        log "Deleted CloudWatch dashboard: BlockchainVotingSystem"
    else
        info "CloudWatch dashboard BlockchainVotingSystem not found"
    fi
    
    log "✅ CloudWatch monitoring resources removed"
}

# Function to remove EventBridge and SNS resources
remove_event_resources() {
    log "Removing EventBridge and SNS resources..."
    
    if ! confirm_action "remove EventBridge and SNS resources"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove EventBridge and SNS resources"
        return 0
    fi
    
    # Remove EventBridge targets
    if aws events describe-rule --name VotingSystemEvents &>/dev/null; then
        # Remove targets first
        aws events remove-targets --rule VotingSystemEvents --ids "1" 2>/dev/null || true
        
        # Remove the rule
        aws events delete-rule --name VotingSystemEvents
        log "Deleted EventBridge rule: VotingSystemEvents"
    else
        info "EventBridge rule VotingSystemEvents not found"
    fi
    
    # Remove SNS topic
    if [[ -n "${VOTING_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "${VOTING_TOPIC_ARN}" &>/dev/null; then
            aws sns delete-topic --topic-arn "${VOTING_TOPIC_ARN}"
            log "Deleted SNS topic: ${VOTING_TOPIC_ARN}"
        else
            info "SNS topic ${VOTING_TOPIC_ARN} not found"
        fi
    else
        # Try to find and delete voting system SNS topics
        local topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `voting-system-notifications`)].TopicArn' --output text)
        if [[ -n "$topics" ]]; then
            for topic in $topics; do
                aws sns delete-topic --topic-arn "$topic"
                log "Deleted SNS topic: $topic"
            done
        else
            info "No voting system SNS topics found"
        fi
    fi
    
    log "✅ EventBridge and SNS resources removed"
}

# Function to remove Lambda functions and IAM resources
remove_lambda_and_iam() {
    log "Removing Lambda functions and IAM resources..."
    
    if ! confirm_action "remove Lambda functions and IAM roles"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove Lambda functions and IAM roles"
        return 0
    fi
    
    # Remove Lambda functions
    local functions=("${LAMBDA_AUTH_FUNCTION}" "${LAMBDA_MONITOR_FUNCTION}")
    for func in "${functions[@]}"; do
        if [[ -n "$func" ]] && aws lambda get-function --function-name "$func" &>/dev/null; then
            aws lambda delete-function --function-name "$func"
            log "Deleted Lambda function: $func"
        else
            info "Lambda function $func not found"
        fi
    done
    
    # Remove IAM roles
    local roles=("VoterAuthLambdaRole" "VoteMonitorLambdaRole")
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
        "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
    )
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            # Detach policies
            for policy in "${policies[@]}"; do
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
            done
            
            # Delete role
            aws iam delete-role --role-name "$role"
            log "Deleted IAM role: $role"
        else
            info "IAM role $role not found"
        fi
    done
    
    log "✅ Lambda functions and IAM resources removed"
}

# Function to remove blockchain node
remove_blockchain_node() {
    log "Removing blockchain node..."
    
    if ! confirm_action "remove blockchain node"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove blockchain node"
        return 0
    fi
    
    # Note: This is a placeholder since the actual blockchain node
    # creation was skipped in the deployment script
    if [[ -n "${NODE_ID:-}" && "$NODE_ID" != "demo-node-id" ]]; then
        if aws managedblockchain get-node --node-id "${NODE_ID}" &>/dev/null; then
            aws managedblockchain delete-node --node-id "${NODE_ID}"
            log "Deleted blockchain node: ${NODE_ID}"
        else
            info "Blockchain node ${NODE_ID} not found"
        fi
    else
        info "No blockchain node to remove (demo deployment)"
    fi
    
    log "✅ Blockchain node removal completed"
}

# Function to remove KMS key
remove_kms_key() {
    log "Removing KMS key..."
    
    if ! confirm_action "schedule KMS key deletion"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would schedule KMS key deletion"
        return 0
    fi
    
    if [[ -n "${KMS_KEY_ID:-}" ]]; then
        if aws kms describe-key --key-id "${KMS_KEY_ID}" &>/dev/null; then
            aws kms schedule-key-deletion --key-id "${KMS_KEY_ID}" --pending-window-in-days 7
            log "Scheduled KMS key deletion: ${KMS_KEY_ID}"
        else
            info "KMS key ${KMS_KEY_ID} not found"
        fi
    else
        info "No KMS key to remove"
    fi
    
    log "✅ KMS key removal completed"
}

# Function to remove DynamoDB tables
remove_dynamodb_tables() {
    log "Removing DynamoDB tables..."
    
    if ! confirm_action "remove DynamoDB tables"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove DynamoDB tables"
        return 0
    fi
    
    local tables=("VoterRegistry" "Elections")
    
    for table in "${tables[@]}"; do
        if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
            aws dynamodb delete-table --table-name "$table"
            log "Deleted DynamoDB table: $table"
            
            # Wait for table to be deleted
            log "Waiting for table $table to be deleted..."
            aws dynamodb wait table-not-exists --table-name "$table" || true
        else
            info "DynamoDB table $table not found"
        fi
    done
    
    log "✅ DynamoDB tables removed"
}

# Function to remove S3 bucket and contents
remove_s3_resources() {
    log "Removing S3 resources..."
    
    if ! confirm_action "remove S3 bucket and all its contents"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove S3 bucket and contents"
        return 0
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            # Remove all objects and versions
            log "Removing all objects from S3 bucket: ${BUCKET_NAME}"
            aws s3 rm "s3://${BUCKET_NAME}" --recursive
            
            # Remove versioned objects if versioning is enabled
            aws s3api delete-objects --bucket "${BUCKET_NAME}" --delete "$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" --output json | jq '.Versions[] | {Key:.Key, VersionId:.VersionId}' | jq -s '{"Objects": .}')" 2>/dev/null || true
            
            # Remove delete markers
            aws s3api delete-objects --bucket "${BUCKET_NAME}" --delete "$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" --output json | jq '.DeleteMarkers[] | {Key:.Key, VersionId:.VersionId}' | jq -s '{"Objects": .}')" 2>/dev/null || true
            
            # Delete bucket
            aws s3 rb "s3://${BUCKET_NAME}"
            log "Deleted S3 bucket: ${BUCKET_NAME}"
        else
            info "S3 bucket ${BUCKET_NAME} not found"
        fi
    else
        info "No S3 bucket to remove"
    fi
    
    log "✅ S3 resources removed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if ! confirm_action "remove local deployment files"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove local files"
        return 0
    fi
    
    # Remove deployment environment file
    if [[ -f "${PROJECT_ROOT}/deployment_env.sh" ]]; then
        rm -f "${PROJECT_ROOT}/deployment_env.sh"
        log "Removed deployment_env.sh"
    fi
    
    # Remove any temporary directories
    local temp_dirs=("${PROJECT_ROOT}/lambda_tmp" "${PROJECT_ROOT}/dapp" "${PROJECT_ROOT}/smart-contracts")
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log "Removed temporary directory: $dir"
        fi
    done
    
    # Remove any temporary files
    local temp_files=("${PROJECT_ROOT}/*.json" "${PROJECT_ROOT}/*.zip" "${PROJECT_ROOT}/*.log")
    for pattern in "${temp_files[@]}"; do
        if ls $pattern &>/dev/null; then
            rm -f $pattern
            log "Removed temporary files: $pattern"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would verify cleanup"
        return 0
    fi
    
    local cleanup_failed=false
    
    # Check S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
        error "❌ S3 bucket ${BUCKET_NAME} still exists"
        cleanup_failed=true
    else
        log "✅ S3 bucket verification passed"
    fi
    
    # Check DynamoDB tables
    local tables=("VoterRegistry" "Elections")
    for table in "${tables[@]}"; do
        if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
            error "❌ DynamoDB table $table still exists"
            cleanup_failed=true
        fi
    done
    
    if [[ "$cleanup_failed" == "false" ]]; then
        log "✅ DynamoDB tables verification passed"
    fi
    
    # Check Lambda functions
    local functions=("${LAMBDA_AUTH_FUNCTION}" "${LAMBDA_MONITOR_FUNCTION}")
    for func in "${functions[@]}"; do
        if [[ -n "$func" ]] && aws lambda get-function --function-name "$func" &>/dev/null; then
            error "❌ Lambda function $func still exists"
            cleanup_failed=true
        fi
    done
    
    if [[ "$cleanup_failed" == "false" ]]; then
        log "✅ Lambda functions verification passed"
    fi
    
    if [[ "$cleanup_failed" == "true" ]]; then
        error "Cleanup verification failed. Some resources may still exist."
        warning "Please check the AWS console and manually remove any remaining resources."
        return 1
    fi
    
    log "✅ Cleanup verification completed successfully"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    log "================"
    log "Removed Resources:"
    log "  - CloudWatch Dashboard: BlockchainVotingSystem"
    log "  - CloudWatch Alarms: VotingSystem-Auth-Errors, VotingSystem-Monitor-Errors"
    log "  - EventBridge Rule: VotingSystemEvents"
    log "  - SNS Topic: ${VOTING_TOPIC_ARN:-'voting-system-notifications'}"
    log "  - Lambda Functions: ${LAMBDA_AUTH_FUNCTION:-'VoterAuthentication'}, ${LAMBDA_MONITOR_FUNCTION:-'VoteMonitoring'}"
    log "  - IAM Roles: VoterAuthLambdaRole, VoteMonitorLambdaRole"
    log "  - DynamoDB Tables: VoterRegistry, Elections"
    log "  - S3 Bucket: ${BUCKET_NAME:-'voting-system-data'}"
    log "  - KMS Key: ${KMS_KEY_ID:-'Voting System Encryption Key'} (scheduled for deletion)"
    log ""
    log "Cleanup log saved to: ${CLEANUP_LOG}"
    log ""
    log "🎉 Blockchain voting system cleanup completed successfully!"
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    warning "Partial cleanup detected. Some resources may still exist."
    
    echo -e "${YELLOW}Do you want to continue with manual cleanup verification? (y/N)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "Please check the AWS console for any remaining resources:"
        log "  - S3 buckets starting with 'voting-system-data-'"
        log "  - Lambda functions starting with 'VoterAuthentication-' or 'VoteMonitoring-'"
        log "  - DynamoDB tables: VoterRegistry, Elections"
        log "  - IAM roles: VoterAuthLambdaRole, VoteMonitorLambdaRole"
        log "  - CloudWatch resources: BlockchainVotingSystem dashboard"
        log "  - EventBridge rules: VotingSystemEvents"
        log "  - SNS topics containing 'voting-system-notifications'"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -y, --yes          Auto-confirm all destructive actions"
    echo "  -d, --dry-run      Show what would be deleted without actually deleting"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  AUTO_CONFIRM       Set to 'true' to auto-confirm (same as -y)"
    echo "  DRY_RUN           Set to 'true' to run in dry-run mode (same as -d)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                 # Interactive cleanup with confirmations"
    echo "  $0 -y              # Auto-confirm all actions"
    echo "  $0 -d              # Dry-run mode (show what would be deleted)"
    echo "  AUTO_CONFIRM=true $0  # Auto-confirm via environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main cleanup function
main() {
    log "🧹 Starting Blockchain Voting System Cleanup"
    log "============================================="
    
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        warning "Auto-confirm mode enabled. All resources will be deleted without confirmation."
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "Dry-run mode enabled. No resources will actually be deleted."
    fi
    
    # Final confirmation for destructive action
    if [[ "$AUTO_CONFIRM" != "true" && "$DRY_RUN" != "true" ]]; then
        echo -e "${RED}WARNING: This will permanently delete all voting system resources!${NC}"
        echo -e "${RED}This action cannot be undone.${NC}"
        echo ""
        if ! confirm_action "proceed with complete cleanup"; then
            log "Cleanup cancelled by user."
            exit 0
        fi
    fi
    
    check_prerequisites
    load_environment
    
    # Cleanup in reverse order of creation
    remove_monitoring_resources
    remove_event_resources
    remove_lambda_and_iam
    remove_blockchain_node
    remove_kms_key
    remove_dynamodb_tables
    remove_s3_resources
    cleanup_local_files
    
    # Verify cleanup
    if ! verify_cleanup; then
        handle_partial_cleanup
    else
        display_cleanup_summary
    fi
    
    log "🎉 Cleanup completed successfully!"
    log "Total cleanup time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Run main function
main "$@"
#!/bin/bash

# Cross-Organization Data Sharing with Amazon Managed Blockchain - Cleanup Script
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for resource deletion with timeout
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local timeout="${3:-300}"  # Default 5 minutes
    local interval="${4:-15}"   # Default 15 seconds
    
    log_info "Waiting for $resource_name to be deleted (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! eval "$check_command" >/dev/null 2>&1; then
            log_success "$resource_name has been deleted"
            return 0
        fi
        
        log_info "Waiting for $resource_name deletion... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Timeout waiting for $resource_name deletion after ${timeout}s"
    return 1
}

# Confirmation prompt
confirm_deletion() {
    local resource_type="$1"
    local skip_prompt="${SKIP_CONFIRMATION:-false}"
    
    if [ "$skip_prompt" = "true" ]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete all $resource_type resources."
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    case "$confirmation" in
        yes|YES|y|Y)
            return 0
            ;;
        *)
            log_info "Operation cancelled by user."
            exit 0
            ;;
    esac
}

# Load environment variables from state file
load_environment() {
    log_info "Loading environment variables from deployment state..."
    
    if [ ! -f "deployment-state.env" ]; then
        log_error "deployment-state.env file not found!"
        log_error "This file is created during deployment and contains resource IDs."
        log_error "Without it, we cannot safely clean up resources."
        log_error ""
        log_info "You can manually delete resources using these patterns:"
        log_info "  - Managed Blockchain networks with 'cross-org-network-' prefix"
        log_info "  - S3 buckets with 'cross-org-data-' prefix"
        log_info "  - Lambda functions with 'CrossOrgDataValidator-' prefix"
        log_info "  - DynamoDB table: CrossOrgAuditTrail"
        log_info "  - EventBridge rule: CrossOrgDataSharingRule"
        log_info "  - SNS topic: cross-org-notifications"
        log_info "  - IAM role: CrossOrgDataSharingLambdaRole"
        log_info "  - IAM policy: CrossOrgDataSharingAccessPolicy"
        exit 1
    fi
    
    # Source the environment file
    set -a  # Automatically export all variables
    source deployment-state.env
    set +a
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "NETWORK_ID"
        "ORG_A_MEMBER_ID"
        "ORG_B_MEMBER_ID"
        "ORG_A_NODE_ID"
        "ORG_B_NODE_ID"
        "BUCKET_NAME"
        "LAMBDA_FUNCTION_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required variable $var is not set in deployment-state.env"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded successfully"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Network ID: ${NETWORK_ID}"
    log_info "S3 Bucket: ${BUCKET_NAME}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Verify we're in the correct AWS account
    local current_account_id
    current_account_id=$(aws sts get-caller-identity --query Account --output text)
    
    if [ "$current_account_id" != "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS account mismatch!"
        log_error "Expected: $AWS_ACCOUNT_ID"
        log_error "Current:  $current_account_id"
        log_error "Please configure the correct AWS credentials."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Remove CloudWatch monitoring resources
remove_cloudwatch_monitoring() {
    log_info "Removing CloudWatch monitoring resources..."
    
    # Delete CloudWatch alarms
    if aws cloudwatch describe-alarms --alarm-names "CrossOrg-Lambda-Errors" >/dev/null 2>&1; then
        aws cloudwatch delete-alarms --alarm-names "CrossOrg-Lambda-Errors"
        log_success "Deleted CloudWatch alarm: CrossOrg-Lambda-Errors"
    else
        log_warning "CloudWatch alarm CrossOrg-Lambda-Errors not found"
    fi
    
    # Delete dashboard
    if aws cloudwatch get-dashboard --dashboard-name CrossOrgDataSharing >/dev/null 2>&1; then
        aws cloudwatch delete-dashboards --dashboard-names CrossOrgDataSharing
        log_success "Deleted CloudWatch dashboard: CrossOrgDataSharing"
    else
        log_warning "CloudWatch dashboard CrossOrgDataSharing not found"
    fi
    
    log_success "CloudWatch monitoring resources removed"
}

# Remove EventBridge and SNS resources
remove_eventbridge_sns() {
    log_info "Removing EventBridge and SNS resources..."
    
    # Remove EventBridge targets first
    if aws events describe-rule --name CrossOrgDataSharingRule >/dev/null 2>&1; then
        aws events remove-targets --rule CrossOrgDataSharingRule --ids "1" >/dev/null 2>&1 || true
        log_success "Removed EventBridge rule targets"
        
        # Delete EventBridge rule
        aws events delete-rule --name CrossOrgDataSharingRule
        log_success "Deleted EventBridge rule: CrossOrgDataSharingRule"
    else
        log_warning "EventBridge rule CrossOrgDataSharingRule not found"
    fi
    
    # Delete SNS topic
    if [ -n "${TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" >/dev/null 2>&1; then
            aws sns delete-topic --topic-arn "${TOPIC_ARN}"
            log_success "Deleted SNS topic: ${TOPIC_ARN}"
        else
            log_warning "SNS topic ${TOPIC_ARN} not found"
        fi
    else
        # Try to delete by name if ARN not available
        local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:cross-org-notifications"
        if aws sns get-topic-attributes --topic-arn "$topic_arn" >/dev/null 2>&1; then
            aws sns delete-topic --topic-arn "$topic_arn"
            log_success "Deleted SNS topic: $topic_arn"
        else
            log_warning "SNS topic cross-org-notifications not found"
        fi
    fi
    
    log_success "EventBridge and SNS resources removed"
}

# Remove Lambda function and IAM resources
remove_lambda_iam() {
    log_info "Removing Lambda function and IAM resources..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
        log_success "Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
    else
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found"
    fi
    
    # Detach policies from IAM role
    local lambda_role="CrossOrgDataSharingLambdaRole"
    if aws iam get-role --role-name "$lambda_role" >/dev/null 2>&1; then
        log_info "Detaching policies from IAM role: $lambda_role"
        
        # List of policies to detach
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
            "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy --role-name "$lambda_role" --policy-arn "$policy" >/dev/null 2>&1 || true
        done
        
        # Delete IAM role
        aws iam delete-role --role-name "$lambda_role"
        log_success "Deleted IAM role: $lambda_role"
    else
        log_warning "IAM role $lambda_role not found"
    fi
    
    # Delete custom IAM policy
    local policy_name="CrossOrgDataSharingAccessPolicy"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
    
    if aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
        aws iam delete-policy --policy-arn "$policy_arn"
        log_success "Deleted IAM policy: $policy_name"
    else
        log_warning "IAM policy $policy_name not found"
    fi
    
    log_success "Lambda function and IAM resources removed"
}

# Remove blockchain network and members
remove_blockchain_network() {
    log_info "Removing blockchain network and members..."
    
    # Check if network exists
    if ! aws managedblockchain get-network --network-id "${NETWORK_ID}" >/dev/null 2>&1; then
        log_warning "Blockchain network ${NETWORK_ID} not found or already deleted"
        return 0
    fi
    
    # Delete peer nodes first
    log_info "Deleting peer nodes..."
    
    # Delete Organization A peer node
    if [ -n "${ORG_A_NODE_ID:-}" ] && [ -n "${ORG_A_MEMBER_ID:-}" ]; then
        if aws managedblockchain get-node \
           --network-id "${NETWORK_ID}" \
           --member-id "${ORG_A_MEMBER_ID}" \
           --node-id "${ORG_A_NODE_ID}" >/dev/null 2>&1; then
            
            aws managedblockchain delete-node \
                --network-id "${NETWORK_ID}" \
                --member-id "${ORG_A_MEMBER_ID}" \
                --node-id "${ORG_A_NODE_ID}"
            log_success "Initiated deletion of Organization A peer node: ${ORG_A_NODE_ID}"
        else
            log_warning "Organization A peer node ${ORG_A_NODE_ID} not found"
        fi
    fi
    
    # Delete Organization B peer node
    if [ -n "${ORG_B_NODE_ID:-}" ] && [ -n "${ORG_B_MEMBER_ID:-}" ]; then
        if aws managedblockchain get-node \
           --network-id "${NETWORK_ID}" \
           --member-id "${ORG_B_MEMBER_ID}" \
           --node-id "${ORG_B_NODE_ID}" >/dev/null 2>&1; then
            
            aws managedblockchain delete-node \
                --network-id "${NETWORK_ID}" \
                --member-id "${ORG_B_MEMBER_ID}" \
                --node-id "${ORG_B_NODE_ID}"
            log_success "Initiated deletion of Organization B peer node: ${ORG_B_NODE_ID}"
        else
            log_warning "Organization B peer node ${ORG_B_NODE_ID} not found"
        fi
    fi
    
    # Wait for node deletions
    log_info "Waiting for node deletions to complete..."
    sleep 60
    
    # Delete members
    log_info "Deleting network members..."
    
    # Delete Organization B member
    if [ -n "${ORG_B_MEMBER_ID:-}" ]; then
        if aws managedblockchain get-member \
           --network-id "${NETWORK_ID}" \
           --member-id "${ORG_B_MEMBER_ID}" >/dev/null 2>&1; then
            
            aws managedblockchain delete-member \
                --network-id "${NETWORK_ID}" \
                --member-id "${ORG_B_MEMBER_ID}"
            log_success "Initiated deletion of Organization B member: ${ORG_B_MEMBER_ID}"
        else
            log_warning "Organization B member ${ORG_B_MEMBER_ID} not found"
        fi
    fi
    
    # Delete Organization A member
    if [ -n "${ORG_A_MEMBER_ID:-}" ]; then
        if aws managedblockchain get-member \
           --network-id "${NETWORK_ID}" \
           --member-id "${ORG_A_MEMBER_ID}" >/dev/null 2>&1; then
            
            aws managedblockchain delete-member \
                --network-id "${NETWORK_ID}" \
                --member-id "${ORG_A_MEMBER_ID}"
            log_success "Initiated deletion of Organization A member: ${ORG_A_MEMBER_ID}"
        else
            log_warning "Organization A member ${ORG_A_MEMBER_ID} not found"
        fi
    fi
    
    # Wait for member deletions
    log_info "Waiting for member deletions to complete..."
    sleep 60
    
    # Delete network
    log_info "Deleting blockchain network..."
    if aws managedblockchain get-network --network-id "${NETWORK_ID}" >/dev/null 2>&1; then
        aws managedblockchain delete-network --network-id "${NETWORK_ID}"
        log_success "Initiated deletion of blockchain network: ${NETWORK_ID}"
        
        # Wait for network deletion
        wait_for_deletion \
            "aws managedblockchain get-network --network-id ${NETWORK_ID}" \
            "blockchain network ${NETWORK_ID}" \
            600 \
            30
    else
        log_warning "Blockchain network ${NETWORK_ID} not found"
    fi
    
    log_success "Blockchain network and members removed"
}

# Remove storage resources
remove_storage_resources() {
    log_info "Removing storage resources..."
    
    # Delete DynamoDB table
    if aws dynamodb describe-table --table-name CrossOrgAuditTrail >/dev/null 2>&1; then
        aws dynamodb delete-table --table-name CrossOrgAuditTrail >/dev/null
        log_success "Initiated deletion of DynamoDB table: CrossOrgAuditTrail"
        
        # Wait for table deletion
        wait_for_deletion \
            "aws dynamodb describe-table --table-name CrossOrgAuditTrail" \
            "DynamoDB table CrossOrgAuditTrail" \
            300 \
            15
    else
        log_warning "DynamoDB table CrossOrgAuditTrail not found"
    fi
    
    # Empty and delete S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_info "Emptying S3 bucket: ${BUCKET_NAME}"
        aws s3 rm "s3://${BUCKET_NAME}" --recursive >/dev/null 2>&1 || true
        
        log_info "Deleting S3 bucket: ${BUCKET_NAME}"
        aws s3 rb "s3://${BUCKET_NAME}" >/dev/null
        log_success "Deleted S3 bucket: ${BUCKET_NAME}"
    else
        log_warning "S3 bucket ${BUCKET_NAME} not found"
    fi
    
    log_success "Storage resources removed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-state.env"
        "lambda-function.zip"
        "lambda-function.js"
        "lambda-trust-policy.json"
        "cross-org-dashboard.json"
        "cross-org-access-policy.json"
        "cross-org-data-sharing-chaincode.tar.gz"
        "cross-org-client.js"
        "simulate-cross-org-operations.js"
        "compliance-monitor.js"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
    
    # Remove chaincode directory
    if [ -d "chaincode" ]; then
        rm -rf chaincode/
        log_success "Removed directory: chaincode/"
    fi
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local errors=0
    
    # Check if blockchain network still exists
    if aws managedblockchain get-network --network-id "${NETWORK_ID}" >/dev/null 2>&1; then
        log_warning "Blockchain network ${NETWORK_ID} still exists"
        ((errors++))
    fi
    
    # Check if Lambda function still exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
        ((errors++))
    fi
    
    # Check if S3 bucket still exists
    if aws s3 ls "s3://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "S3 bucket ${BUCKET_NAME} still exists"
        ((errors++))
    fi
    
    # Check if DynamoDB table still exists
    if aws dynamodb describe-table --table-name CrossOrgAuditTrail >/dev/null 2>&1; then
        log_warning "DynamoDB table CrossOrgAuditTrail still exists"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Cleanup verification completed successfully"
        log_success "All resources have been removed"
    else
        log_warning "Cleanup verification found $errors remaining resources"
        log_warning "Some resources may take additional time to delete"
        log_warning "You can re-run this script later to check again"
    fi
}

# Display cost savings information
display_cost_savings() {
    log_info ""
    log_success "Resource cleanup completed!"
    log_info ""
    log_info "Cost Savings Information:"
    log_info "  ✅ Managed Blockchain network charges stopped"
    log_info "  ✅ EC2 instances (blockchain nodes) terminated"
    log_info "  ✅ Lambda function compute charges stopped"
    log_info "  ✅ DynamoDB table storage charges stopped"
    log_info "  ✅ S3 bucket storage charges stopped"
    log_info "  ✅ CloudWatch dashboard and alarm charges stopped"
    log_info ""
    log_info "Estimated monthly savings: \$200-300"
    log_info ""
    log_warning "Note: Some charges may appear on your next bill for partial usage"
    log_warning "during the time resources were active."
}

# Handle script arguments
handle_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-confirmation)
                export SKIP_CONFIRMATION=true
                shift
                ;;
            --force)
                export SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                echo "Cross-Organization Data Sharing Cleanup Script"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-confirmation  Skip confirmation prompts (dangerous!)"
                echo "  --force             Same as --skip-confirmation"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "This script will remove all resources created by the deploy script."
                echo "It requires the deployment-state.env file to identify resources."
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    log_info "Starting Cross-Organization Data Sharing cleanup..."
    
    handle_arguments "$@"
    load_environment
    check_prerequisites
    
    # Show summary before proceeding
    log_info ""
    log_info "Resources to be deleted:"
    log_info "  - Blockchain Network: ${NETWORK_ID}"
    log_info "  - Organization A Member: ${ORG_A_MEMBER_ID}"
    log_info "  - Organization B Member: ${ORG_B_MEMBER_ID}"
    log_info "  - S3 Bucket: ${BUCKET_NAME}"
    log_info "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  - DynamoDB Table: CrossOrgAuditTrail"
    log_info "  - EventBridge Rule: CrossOrgDataSharingRule"
    log_info "  - SNS Topic: cross-org-notifications"
    log_info "  - IAM Role: CrossOrgDataSharingLambdaRole"
    log_info "  - CloudWatch Resources: Dashboard and Alarms"
    
    confirm_deletion "Cross-Organization Data Sharing"
    
    log_info ""
    log_info "Starting resource cleanup..."
    log_warning "This process may take 10-15 minutes to complete"
    
    # Remove resources in reverse order of creation
    remove_cloudwatch_monitoring
    remove_eventbridge_sns
    remove_lambda_iam
    remove_blockchain_network
    remove_storage_resources
    cleanup_local_files
    
    verify_cleanup
    display_cost_savings
    
    log_info ""
    log_success "Cross-Organization Data Sharing cleanup completed!"
}

# Run main function with all arguments
main "$@"
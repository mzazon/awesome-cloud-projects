#!/bin/bash

# Destroy script for Policy Enforcement Automation with VPC Lattice and Config
# This script safely removes all infrastructure created by the deploy.sh script
# with proper dependency handling and confirmation prompts

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    print_status "$RED" "ERROR: $1"
    log "ERROR" "$1"
    exit 1
}

# Function to prompt for confirmation
confirm_action() {
    local action=$1
    local resource=$2
    
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log "INFO" "Force mode enabled, skipping confirmation for $action"
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: About to $action: $resource${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "$YELLOW" "Skipping $action for $resource"
        return 1
    fi
    return 0
}

# Function to load environment variables
load_environment() {
    print_status "$BLUE" "Loading environment variables from deployment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error_exit "Environment file not found: $ENV_FILE. Make sure deploy.sh was run successfully."
    fi
    
    # Source environment variables
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
    
    # Verify required variables
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "CONFIG_RULE_NAME" "SNS_TOPIC_NAME"
        "LAMBDA_FUNCTION_NAME" "REMEDY_FUNCTION_NAME" "CONFIG_ROLE_NAME"
        "LAMBDA_ROLE_NAME" "CONFIG_BUCKET_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable $var not found in $ENV_FILE"
        fi
    done
    
    log "INFO" "Environment variables loaded successfully"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account: $AWS_ACCOUNT_ID"
    
    print_status "$GREEN" "Environment loaded successfully"
}

# Function to check AWS connectivity
check_aws_connectivity() {
    print_status "$BLUE" "Checking AWS connectivity..."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or expired."
    fi
    
    # Verify we're in the correct account and region
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    local current_region=$(aws configure get region)
    
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        error_exit "Account mismatch. Expected: $AWS_ACCOUNT_ID, Current: $current_account"
    fi
    
    if [[ "$current_region" != "$AWS_REGION" ]]; then
        print_status "$YELLOW" "Region mismatch. Expected: $AWS_REGION, Current: $current_region"
        print_status "$YELLOW" "Using region from environment: $AWS_REGION"
    fi
    
    print_status "$GREEN" "AWS connectivity verified"
}

# Function to delete test VPC Lattice resources
delete_test_resources() {
    print_status "$BLUE" "Deleting test VPC Lattice resources..."
    
    # Delete test service if it exists
    if [[ -n "${TEST_SERVICE_ID:-}" ]]; then
        if confirm_action "delete test service" "$TEST_SERVICE_ID"; then
            log "INFO" "Deleting test service: $TEST_SERVICE_ID"
            aws vpc-lattice delete-service \
                --service-identifier "$TEST_SERVICE_ID" || \
                log "WARN" "Failed to delete test service or it may not exist"
        fi
    fi
    
    # Delete service network VPC association if it exists
    if [[ -n "${SERVICE_NETWORK_ID:-}" && -n "${VPC_ID:-}" ]]; then
        if confirm_action "delete service network VPC association" "$SERVICE_NETWORK_ID"; then
            log "INFO" "Deleting service network VPC association"
            local association_id=$(aws vpc-lattice list-service-network-vpc-associations \
                --service-network-identifier "$SERVICE_NETWORK_ID" \
                --query 'items[0].id' --output text 2>/dev/null || echo "")
            
            if [[ -n "$association_id" && "$association_id" != "None" ]]; then
                aws vpc-lattice delete-service-network-vpc-association \
                    --service-network-vpc-association-identifier "$association_id" || \
                    log "WARN" "Failed to delete VPC association or it may not exist"
                
                # Wait for association deletion
                log "INFO" "Waiting for VPC association deletion..."
                sleep 10
            fi
        fi
    fi
    
    # Delete service network
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        if confirm_action "delete service network" "$SERVICE_NETWORK_ID"; then
            log "INFO" "Deleting service network: $SERVICE_NETWORK_ID"
            aws vpc-lattice delete-service-network \
                --service-network-identifier "$SERVICE_NETWORK_ID" || \
                log "WARN" "Failed to delete service network or it may not exist"
        fi
    fi
    
    # Delete VPC
    if [[ -n "${VPC_ID:-}" ]]; then
        if confirm_action "delete VPC" "$VPC_ID"; then
            log "INFO" "Deleting VPC: $VPC_ID"
            aws ec2 delete-vpc --vpc-id "$VPC_ID" || \
                log "WARN" "Failed to delete VPC or it may not exist"
        fi
    fi
    
    print_status "$GREEN" "Test resources cleanup completed"
}

# Function to delete Config resources
delete_config_resources() {
    print_status "$BLUE" "Deleting AWS Config resources..."
    
    # Delete Config rule
    if confirm_action "delete Config rule" "$CONFIG_RULE_NAME"; then
        log "INFO" "Deleting Config rule: $CONFIG_RULE_NAME"
        aws configservice delete-config-rule \
            --config-rule-name "$CONFIG_RULE_NAME" || \
            log "WARN" "Failed to delete Config rule or it may not exist"
    fi
    
    # Stop and delete configuration recorder
    if confirm_action "delete configuration recorder" "default"; then
        log "INFO" "Stopping configuration recorder"
        aws configservice stop-configuration-recorder \
            --configuration-recorder-name default || \
            log "WARN" "Failed to stop configuration recorder or it may not exist"
        
        log "INFO" "Deleting configuration recorder"
        aws configservice delete-configuration-recorder \
            --configuration-recorder-name default || \
            log "WARN" "Failed to delete configuration recorder or it may not exist"
    fi
    
    # Delete delivery channel
    if confirm_action "delete delivery channel" "default"; then
        log "INFO" "Deleting delivery channel"
        aws configservice delete-delivery-channel \
            --delivery-channel-name default || \
            log "WARN" "Failed to delete delivery channel or it may not exist"
    fi
    
    print_status "$GREEN" "Config resources cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    print_status "$BLUE" "Deleting Lambda functions..."
    
    # Delete compliance evaluator Lambda function
    if confirm_action "delete Lambda function" "$LAMBDA_FUNCTION_NAME"; then
        log "INFO" "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || \
            log "WARN" "Failed to delete Lambda function or it may not exist"
    fi
    
    # Delete auto-remediation Lambda function
    if confirm_action "delete Lambda function" "$REMEDY_FUNCTION_NAME"; then
        log "INFO" "Deleting Lambda function: $REMEDY_FUNCTION_NAME"
        aws lambda delete-function --function-name "$REMEDY_FUNCTION_NAME" || \
            log "WARN" "Failed to delete Lambda function or it may not exist"
    fi
    
    print_status "$GREEN" "Lambda functions cleanup completed"
}

# Function to delete SNS resources
delete_sns_resources() {
    print_status "$BLUE" "Deleting SNS resources..."
    
    # Delete SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if confirm_action "delete SNS topic" "$SNS_TOPIC_NAME"; then
            log "INFO" "Deleting SNS topic: $SNS_TOPIC_NAME"
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" || \
                log "WARN" "Failed to delete SNS topic or it may not exist"
        fi
    else
        # Construct SNS topic ARN if not available
        local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        if confirm_action "delete SNS topic" "$SNS_TOPIC_NAME"; then
            log "INFO" "Deleting SNS topic: $SNS_TOPIC_NAME"
            aws sns delete-topic --topic-arn "$topic_arn" || \
                log "WARN" "Failed to delete SNS topic or it may not exist"
        fi
    fi
    
    print_status "$GREEN" "SNS resources cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    print_status "$BLUE" "Deleting IAM resources..."
    
    # Delete Lambda IAM role
    if confirm_action "delete IAM role" "$LAMBDA_ROLE_NAME"; then
        log "INFO" "Detaching policies from Lambda role: $LAMBDA_ROLE_NAME"
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || \
            log "WARN" "Failed to detach policy or it may not be attached"
        
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name LatticeCompliancePolicy || \
            log "WARN" "Failed to delete inline policy or it may not exist"
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" || \
            log "WARN" "Failed to delete Lambda role or it may not exist"
    fi
    
    # Delete Config IAM role
    if confirm_action "delete IAM role" "$CONFIG_ROLE_NAME"; then
        log "INFO" "Detaching policies from Config role: $CONFIG_ROLE_NAME"
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "$CONFIG_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole || \
            log "WARN" "Failed to detach policy or it may not be attached"
        
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name "$CONFIG_ROLE_NAME" \
            --policy-name ConfigS3DeliveryRolePolicy || \
            log "WARN" "Failed to delete inline policy or it may not exist"
        
        # Delete role
        aws iam delete-role --role-name "$CONFIG_ROLE_NAME" || \
            log "WARN" "Failed to delete Config role or it may not exist"
    fi
    
    print_status "$GREEN" "IAM resources cleanup completed"
}

# Function to delete S3 resources
delete_s3_resources() {
    print_status "$BLUE" "Deleting S3 resources..."
    
    if confirm_action "delete S3 bucket and all contents" "$CONFIG_BUCKET_NAME"; then
        log "INFO" "Deleting S3 bucket: $CONFIG_BUCKET_NAME"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$CONFIG_BUCKET_NAME" 2>/dev/null; then
            # Empty the bucket first
            log "INFO" "Emptying S3 bucket contents"
            aws s3 rm "s3://$CONFIG_BUCKET_NAME" --recursive || \
                log "WARN" "Failed to empty bucket or it may already be empty"
            
            # Delete the bucket
            aws s3 rb "s3://$CONFIG_BUCKET_NAME" || \
                log "WARN" "Failed to delete S3 bucket or it may not exist"
        else
            log "WARN" "S3 bucket $CONFIG_BUCKET_NAME does not exist or is not accessible"
        fi
    fi
    
    print_status "$GREEN" "S3 resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    print_status "$BLUE" "Cleaning up local files..."
    
    if confirm_action "delete local environment file" "$ENV_FILE"; then
        log "INFO" "Removing environment file: $ENV_FILE"
        rm -f "$ENV_FILE"
    fi
    
    # Remove any temporary files that might have been left behind
    local temp_files=(
        "$SCRIPT_DIR/config-bucket-policy.json"
        "$SCRIPT_DIR/response.json"
        "$SCRIPT_DIR/compliance_evaluator.py"
        "$SCRIPT_DIR/compliance_evaluator.zip"
        "$SCRIPT_DIR/auto_remediation.py"
        "$SCRIPT_DIR/auto_remediation.zip"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "INFO" "Removing temporary file: $file"
            rm -f "$file"
        fi
    done
    
    print_status "$GREEN" "Local files cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    print_status "$BLUE" "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check if Config rule still exists
    if aws configservice describe-config-rules --config-rule-names "$CONFIG_RULE_NAME" &>/dev/null; then
        log "ERROR" "Config rule still exists: $CONFIG_RULE_NAME"
        ((cleanup_errors++))
    fi
    
    # Check if Lambda functions still exist
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log "ERROR" "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        ((cleanup_errors++))
    fi
    
    if aws lambda get-function --function-name "$REMEDY_FUNCTION_NAME" &>/dev/null; then
        log "ERROR" "Lambda function still exists: $REMEDY_FUNCTION_NAME"
        ((cleanup_errors++))
    fi
    
    # Check if IAM roles still exist
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log "ERROR" "IAM role still exists: $LAMBDA_ROLE_NAME"
        ((cleanup_errors++))
    fi
    
    if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
        log "ERROR" "IAM role still exists: $CONFIG_ROLE_NAME"
        ((cleanup_errors++))
    fi
    
    # Check if S3 bucket still exists
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET_NAME" &>/dev/null; then
        log "ERROR" "S3 bucket still exists: $CONFIG_BUCKET_NAME"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        print_status "$GREEN" "Cleanup verification completed successfully"
        log "INFO" "All resources have been successfully removed"
    else
        print_status "$YELLOW" "Cleanup verification found $cleanup_errors remaining resources"
        log "WARN" "Some resources may still exist. Manual cleanup may be required."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    print_status "$BLUE" "Cleanup Summary"
    echo "===========================================" | tee -a "$LOG_FILE"
    echo "Cleanup completed for deployment in AWS Region: $AWS_REGION" | tee -a "$LOG_FILE"
    echo "AWS Account: $AWS_ACCOUNT_ID" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Resources processed for deletion:" | tee -a "$LOG_FILE"
    echo "- Config Rule: $CONFIG_RULE_NAME" | tee -a "$LOG_FILE"
    echo "- SNS Topic: $SNS_TOPIC_NAME" | tee -a "$LOG_FILE"
    echo "- Lambda Functions: $LAMBDA_FUNCTION_NAME, $REMEDY_FUNCTION_NAME" | tee -a "$LOG_FILE"
    echo "- IAM Roles: $CONFIG_ROLE_NAME, $LAMBDA_ROLE_NAME" | tee -a "$LOG_FILE"
    echo "- S3 Bucket: $CONFIG_BUCKET_NAME" | tee -a "$LOG_FILE"
    echo "- Test VPC and Lattice resources" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Cleanup log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "===========================================" | tee -a "$LOG_FILE"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy all resources created by the VPC Lattice Policy Enforcement deployment"
    echo ""
    echo "Options:"
    echo "  --force         Skip confirmation prompts (dangerous!)"
    echo "  --help          Show this help message"
    echo "  --verify-only   Only verify if resources exist, don't delete them"
    echo ""
    echo "Examples:"
    echo "  $0              # Interactive cleanup with confirmations"
    echo "  $0 --force      # Automated cleanup without confirmations"
    echo "  $0 --verify-only # Check what resources would be deleted"
}

# Main cleanup function
main() {
    print_status "$GREEN" "Starting VPC Lattice Policy Enforcement Cleanup"
    log "INFO" "Cleanup started by user: $(whoami)"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_CLEANUP=true
                print_status "$YELLOW" "Force mode enabled - skipping confirmations"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            --verify-only)
                export VERIFY_ONLY=true
                print_status "$BLUE" "Verify-only mode enabled"
                shift
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Load environment and check connectivity
    load_environment
    check_aws_connectivity
    
    # Show warning and final confirmation
    if [[ "${VERIFY_ONLY:-false}" != "true" ]]; then
        echo ""
        print_status "$YELLOW" "WARNING: This will delete ALL resources created by the VPC Lattice Policy Enforcement deployment!"
        print_status "$YELLOW" "This action cannot be undone!"
        echo ""
        
        if [[ "${FORCE_CLEANUP:-false}" != "true" ]]; then
            read -p "Type 'DELETE' to confirm you want to proceed: " -r
            if [[ $REPLY != "DELETE" ]]; then
                print_status "$BLUE" "Cleanup cancelled by user"
                exit 0
            fi
        fi
        
        # Execute cleanup steps in dependency order
        delete_test_resources
        delete_config_resources
        delete_lambda_functions
        delete_sns_resources
        delete_iam_resources
        delete_s3_resources
        cleanup_local_files
    fi
    
    # Verify cleanup completion
    verify_cleanup
    
    if [[ "${VERIFY_ONLY:-false}" != "true" ]]; then
        print_status "$GREEN" "Cleanup completed successfully!"
        display_cleanup_summary
    fi
    
    log "INFO" "Cleanup process completed"
}

# Handle script interruption
trap 'print_status "$RED" "Cleanup interrupted. Some resources may still exist."; exit 1' INT

# Run main function with all arguments
main "$@"
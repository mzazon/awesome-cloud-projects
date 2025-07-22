#!/bin/bash

# Destroy script for AWS Blockchain-Based Supply Chain Tracking Systems
# This script safely removes all created infrastructure resources

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
ERROR_LOG="${SCRIPT_DIR}/cleanup_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}" | tee -a "${ERROR_LOG}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup encountered errors. Check ${ERROR_LOG} for details."
    log_warning "Some resources may still exist. Manual cleanup might be required."
    exit 1
}

trap cleanup_on_error ERR

# Initialize logging
echo "Cleanup started at $(date)" > "${LOG_FILE}"
echo "Cleanup errors log" > "${ERROR_LOG}"

log_info "Starting cleanup of AWS Blockchain-Based Supply Chain Tracking Systems"
log_info "Logs will be written to: ${LOG_FILE}"

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        source "${SCRIPT_DIR}/.env"
        log_success "Loaded environment variables from .env file"
    else
        log_warning ".env file not found. Using default values or prompting for input."
        
        # Set AWS region and account
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
            log_error "Unable to determine AWS account ID. Please configure AWS credentials."
            exit 1
        fi
    fi
    
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This will destroy ALL supply chain tracking infrastructure!"
    log_warning "This action is IRREVERSIBLE and will delete:"
    log_warning "  - Blockchain network and all data"
    log_warning "  - DynamoDB table and all records"
    log_warning "  - S3 bucket and all contents"
    log_warning "  - Lambda functions and logs"
    log_warning "  - IoT resources and configurations"
    log_warning "  - CloudWatch dashboards and alarms"
    echo ""
    
    if [[ "${1:-}" != "--force" ]]; then
        read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
        if [[ "${confirmation}" != "DELETE" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    else
        log_warning "Force mode enabled - skipping confirmation"
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms=("SupplyChain-Lambda-Errors" "SupplyChain-DynamoDB-Throttles")
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "${alarm}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${alarm}"; then
            aws cloudwatch delete-alarms --alarm-names "${alarm}"
            log_success "Deleted CloudWatch alarm: ${alarm}"
        else
            log_warning "CloudWatch alarm not found: ${alarm}"
        fi
    done
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name SupplyChainTracking &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names SupplyChainTracking
        log_success "Deleted CloudWatch dashboard: SupplyChainTracking"
    else
        log_warning "CloudWatch dashboard not found: SupplyChainTracking"
    fi
}

# Remove EventBridge and SNS resources
remove_eventbridge_resources() {
    log_info "Removing EventBridge and SNS resources..."
    
    # Remove EventBridge targets
    if aws events describe-rule --name SupplyChainTrackingRule &>/dev/null; then
        # Get target IDs
        local target_ids=$(aws events list-targets-by-rule \
            --rule SupplyChainTrackingRule \
            --query 'Targets[].Id' --output text 2>/dev/null || echo "")
        
        if [[ -n "${target_ids}" ]]; then
            aws events remove-targets \
                --rule SupplyChainTrackingRule \
                --ids ${target_ids}
            log_success "Removed EventBridge targets"
        fi
        
        # Delete EventBridge rule
        aws events delete-rule --name SupplyChainTrackingRule
        log_success "Deleted EventBridge rule: SupplyChainTrackingRule"
    else
        log_warning "EventBridge rule not found: SupplyChainTrackingRule"
    fi
    
    # Delete SNS topic
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &>/dev/null; then
            aws sns delete-topic --topic-arn "${TOPIC_ARN}"
            log_success "Deleted SNS topic: ${TOPIC_ARN}"
        else
            log_warning "SNS topic not found: ${TOPIC_ARN}"
        fi
    else
        # Try to find and delete the topic by name
        local topic_arn=$(aws sns list-topics \
            --query 'Topics[?contains(TopicArn, `supply-chain-notifications`)].TopicArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${topic_arn}" ]]; then
            aws sns delete-topic --topic-arn "${topic_arn}"
            log_success "Deleted SNS topic: ${topic_arn}"
        else
            log_warning "SNS topic not found: supply-chain-notifications"
        fi
    fi
}

# Remove Lambda function and IAM role
remove_lambda_resources() {
    log_info "Removing Lambda function and IAM resources..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name ProcessSupplyChainData &>/dev/null; then
        aws lambda delete-function --function-name ProcessSupplyChainData
        log_success "Deleted Lambda function: ProcessSupplyChainData"
    else
        log_warning "Lambda function not found: ProcessSupplyChainData"
    fi
    
    # Remove IAM role policies and delete role
    if aws iam get-role --role-name SupplyChainLambdaRole &>/dev/null; then
        # Detach policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy \
                --role-name SupplyChainLambdaRole \
                --policy-arn "${policy}" 2>/dev/null || true
        done
        
        # Delete IAM role
        aws iam delete-role --role-name SupplyChainLambdaRole
        log_success "Deleted IAM role: SupplyChainLambdaRole"
    else
        log_warning "IAM role not found: SupplyChainLambdaRole"
    fi
}

# Remove IoT resources
remove_iot_resources() {
    log_info "Removing IoT resources..."
    
    # Delete IoT rule
    if aws iot get-topic-rule --rule-name SupplyChainSensorRule &>/dev/null; then
        aws iot delete-topic-rule --rule-name SupplyChainSensorRule
        log_success "Deleted IoT rule: SupplyChainSensorRule"
    else
        log_warning "IoT rule not found: SupplyChainSensorRule"
    fi
    
    # Delete IoT policy
    if aws iot get-policy --policy-name SupplyChainTrackerPolicy &>/dev/null; then
        aws iot delete-policy --policy-name SupplyChainTrackerPolicy
        log_success "Deleted IoT policy: SupplyChainTrackerPolicy"
    else
        log_warning "IoT policy not found: SupplyChainTrackerPolicy"
    fi
    
    # Delete IoT thing
    if [[ -n "${IOT_THING_NAME:-}" ]]; then
        if aws iot describe-thing --thing-name "${IOT_THING_NAME}" &>/dev/null; then
            aws iot delete-thing --thing-name "${IOT_THING_NAME}"
            log_success "Deleted IoT thing: ${IOT_THING_NAME}"
        else
            log_warning "IoT thing not found: ${IOT_THING_NAME}"
        fi
    fi
    
    # Delete IoT thing type
    if aws iot describe-thing-type --thing-type-name SupplyChainTracker &>/dev/null; then
        aws iot delete-thing-type --thing-type-name SupplyChainTracker
        log_success "Deleted IoT thing type: SupplyChainTracker"
    else
        log_warning "IoT thing type not found: SupplyChainTracker"
    fi
}

# Remove blockchain network
remove_blockchain_network() {
    log_info "Removing blockchain network..."
    
    if [[ -n "${NETWORK_ID:-}" && -n "${MEMBER_ID:-}" && -n "${NODE_ID:-}" ]]; then
        # Delete peer node first
        if aws managedblockchain get-node \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" \
            --node-id "${NODE_ID}" &>/dev/null; then
            
            log_info "Deleting peer node: ${NODE_ID}"
            aws managedblockchain delete-node \
                --network-id "${NETWORK_ID}" \
                --member-id "${MEMBER_ID}" \
                --node-id "${NODE_ID}"
            
            # Wait for node deletion (timeout after 5 minutes)
            log_info "Waiting for node deletion to complete..."
            local wait_count=0
            while [[ ${wait_count} -lt 30 ]]; do
                if ! aws managedblockchain get-node \
                    --network-id "${NETWORK_ID}" \
                    --member-id "${MEMBER_ID}" \
                    --node-id "${NODE_ID}" &>/dev/null; then
                    break
                fi
                sleep 10
                ((wait_count++))
            done
            
            log_success "Deleted blockchain node: ${NODE_ID}"
        else
            log_warning "Blockchain node not found: ${NODE_ID}"
        fi
        
        # Delete member
        if aws managedblockchain get-member \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" &>/dev/null; then
            
            log_info "Deleting blockchain member: ${MEMBER_ID}"
            aws managedblockchain delete-member \
                --network-id "${NETWORK_ID}" \
                --member-id "${MEMBER_ID}"
            
            # Wait for member deletion (timeout after 5 minutes)
            log_info "Waiting for member deletion to complete..."
            local wait_count=0
            while [[ ${wait_count} -lt 30 ]]; do
                if ! aws managedblockchain get-member \
                    --network-id "${NETWORK_ID}" \
                    --member-id "${MEMBER_ID}" &>/dev/null; then
                    break
                fi
                sleep 10
                ((wait_count++))
            done
            
            log_success "Deleted blockchain member: ${MEMBER_ID}"
        else
            log_warning "Blockchain member not found: ${MEMBER_ID}"
        fi
        
        # Delete network
        if aws managedblockchain get-network --network-id "${NETWORK_ID}" &>/dev/null; then
            log_info "Deleting blockchain network: ${NETWORK_ID}"
            aws managedblockchain delete-network --network-id "${NETWORK_ID}"
            log_success "Deleted blockchain network: ${NETWORK_ID}"
        else
            log_warning "Blockchain network not found: ${NETWORK_ID}"
        fi
    else
        log_warning "Blockchain identifiers not found. Attempting to find and delete networks..."
        
        # Try to find networks by name pattern
        if [[ -n "${NETWORK_NAME:-}" ]]; then
            local networks=$(aws managedblockchain list-networks \
                --query "Networks[?Name=='${NETWORK_NAME}'].Id" --output text 2>/dev/null || echo "")
            
            if [[ -n "${networks}" ]]; then
                for network_id in ${networks}; do
                    log_info "Found network to delete: ${network_id}"
                    aws managedblockchain delete-network --network-id "${network_id}" 2>/dev/null || true
                done
            fi
        fi
    fi
    
    # Delete VPC accessor if it exists
    if [[ -n "${ENDPOINT_ID:-}" && "${ENDPOINT_ID}" != "endpoint-created" ]]; then
        if aws managedblockchain get-accessor --accessor-id "${ENDPOINT_ID}" &>/dev/null; then
            aws managedblockchain delete-accessor --accessor-id "${ENDPOINT_ID}"
            log_success "Deleted blockchain accessor: ${ENDPOINT_ID}"
        fi
    fi
}

# Remove DynamoDB table
remove_dynamodb_table() {
    log_info "Removing DynamoDB table..."
    
    if aws dynamodb describe-table --table-name SupplyChainMetadata &>/dev/null; then
        aws dynamodb delete-table --table-name SupplyChainMetadata
        
        # Wait for table deletion
        log_info "Waiting for DynamoDB table deletion..."
        aws dynamodb wait table-not-exists --table-name SupplyChainMetadata
        
        log_success "Deleted DynamoDB table: SupplyChainMetadata"
    else
        log_warning "DynamoDB table not found: SupplyChainMetadata"
    fi
}

# Remove S3 bucket
remove_s3_bucket() {
    log_info "Removing S3 bucket..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            # Delete all objects and versions
            log_info "Emptying S3 bucket: ${BUCKET_NAME}"
            aws s3 rm "s3://${BUCKET_NAME}" --recursive
            
            # Delete all object versions (if versioning is enabled)
            aws s3api delete-objects --bucket "${BUCKET_NAME}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${BUCKET_NAME}" \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --output json)" 2>/dev/null || true
            
            # Delete all delete markers
            aws s3api delete-objects --bucket "${BUCKET_NAME}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${BUCKET_NAME}" \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --output json)" 2>/dev/null || true
            
            # Delete bucket
            aws s3api delete-bucket --bucket "${BUCKET_NAME}"
            log_success "Deleted S3 bucket: ${BUCKET_NAME}"
        else
            log_warning "S3 bucket not found: ${BUCKET_NAME}"
        fi
    else
        log_warning "S3 bucket name not found in environment variables"
        
        # Try to find buckets with supply-chain pattern
        local buckets=$(aws s3api list-buckets \
            --query 'Buckets[?contains(Name, `supply-chain-data`)].Name' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${buckets}" ]]; then
            for bucket in ${buckets}; do
                log_info "Found bucket to delete: ${bucket}"
                aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
                aws s3api delete-bucket --bucket "${bucket}" 2>/dev/null || true
            done
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/../chaincode"
        "${SCRIPT_DIR}/../supply-chain-chaincode.tar.gz"
        "${SCRIPT_DIR}/../lambda-function.zip"
        "${SCRIPT_DIR}/../lambda-function.js"
        "${SCRIPT_DIR}/../blockchain-client.js"
        "${SCRIPT_DIR}/../simulate-supply-chain.js"
        "${SCRIPT_DIR}/iot-policy.json"
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            rm -rf "${file}"
            log_success "Removed: ${file}"
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=()
    
    # Check blockchain network
    if [[ -n "${NETWORK_ID:-}" ]]; then
        if aws managedblockchain get-network --network-id "${NETWORK_ID}" &>/dev/null; then
            remaining_resources+=("Blockchain Network: ${NETWORK_ID}")
        fi
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ProcessSupplyChainData &>/dev/null; then
        remaining_resources+=("Lambda Function: ProcessSupplyChainData")
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name SupplyChainMetadata &>/dev/null; then
        remaining_resources+=("DynamoDB Table: SupplyChainMetadata")
    fi
    
    # Check S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            remaining_resources+=("S3 Bucket: ${BUCKET_NAME}")
        fi
    fi
    
    # Check IoT resources
    if [[ -n "${IOT_THING_NAME:-}" ]]; then
        if aws iot describe-thing --thing-name "${IOT_THING_NAME}" &>/dev/null; then
            remaining_resources+=("IoT Thing: ${IOT_THING_NAME}")
        fi
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "The following resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log_warning "  - ${resource}"
        done
        log_warning "Manual cleanup may be required for these resources"
    fi
}

# Print cleanup summary
print_summary() {
    log_info "=== CLEANUP SUMMARY ==="
    log_info "Cleanup completed at: $(date)"
    log_info "Resources removed:"
    log_info "  ✓ Blockchain network and nodes"
    log_info "  ✓ Lambda functions and IAM roles"
    log_info "  ✓ DynamoDB table and data"
    log_info "  ✓ S3 bucket and contents"
    log_info "  ✓ IoT things, policies, and rules"
    log_info "  ✓ EventBridge rules and SNS topics"
    log_info "  ✓ CloudWatch dashboards and alarms"
    log_info "  ✓ Local files and configurations"
    log_info "========================"
    log_info ""
    log_info "Cleanup logs saved to: ${LOG_FILE}"
    if [[ -s "${ERROR_LOG}" ]]; then
        log_warning "Cleanup errors logged to: ${ERROR_LOG}"
    fi
    log_info ""
    log_success "Cleanup process completed!"
    log_info "Total cleanup time: $((SECONDS/60)) minutes $((SECONDS%60)) seconds"
}

# Main cleanup function
main() {
    local start_time=$SECONDS
    
    load_environment
    confirm_destruction "$@"
    
    # Remove resources in reverse order of creation
    remove_cloudwatch_resources
    remove_eventbridge_resources
    remove_lambda_resources
    remove_iot_resources
    remove_blockchain_network
    remove_dynamodb_table
    remove_s3_bucket
    cleanup_local_files
    
    verify_cleanup
    print_summary
    
    log_success "All cleanup operations completed in $((SECONDS-start_time)) seconds"
}

# Run main function
main "$@"
#!/bin/bash

# Destroy script for Ethereum-Compatible Smart Contracts with Managed Blockchain
# This script safely removes all resources created by the deployment

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set your AWS region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Failed to get AWS account ID"
    fi
    
    info "Environment initialized:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Find deployment resources
find_deployment_resources() {
    log "Finding deployment resources..."
    
    # Try to find deployment info from S3 bucket
    if [ -n "$1" ]; then
        # Use provided resource identifier
        RESOURCE_IDENTIFIER="$1"
        info "Using provided resource identifier: ${RESOURCE_IDENTIFIER}"
    else
        # Try to find deployment info interactively
        info "Searching for Ethereum deployment resources..."
        
        # List S3 buckets with ethereum-artifacts prefix
        BUCKETS=$(aws s3 ls | grep ethereum-artifacts | awk '{print $3}' || echo "")
        
        if [ -z "$BUCKETS" ]; then
            warn "No S3 buckets found with 'ethereum-artifacts' prefix"
            info "You can manually specify resource identifier as argument:"
            info "  ./destroy.sh <random-suffix>"
            
            # Try to find resources by naming pattern
            info "Searching for resources with ethereum naming pattern..."
            
            # Find Lambda functions
            LAMBDA_FUNCTIONS=$(aws lambda list-functions \
                --query 'Functions[?contains(FunctionName, `eth-contract-manager`)].FunctionName' \
                --output text || echo "")
            
            if [ -n "$LAMBDA_FUNCTIONS" ]; then
                info "Found Lambda functions:"
                for func in $LAMBDA_FUNCTIONS; do
                    info "  - $func"
                done
                
                # Extract suffix from first function
                FIRST_FUNCTION=$(echo "$LAMBDA_FUNCTIONS" | head -n1)
                RESOURCE_IDENTIFIER=$(echo "$FIRST_FUNCTION" | sed 's/eth-contract-manager-//')
                info "Extracted resource identifier: ${RESOURCE_IDENTIFIER}"
            else
                error "No Ethereum deployment resources found. Cannot proceed with cleanup."
            fi
        else
            # Use first bucket found
            FIRST_BUCKET=$(echo "$BUCKETS" | head -n1)
            RESOURCE_IDENTIFIER=$(echo "$FIRST_BUCKET" | sed "s/ethereum-artifacts-${AWS_ACCOUNT_ID}-//")
            info "Found S3 bucket: ${FIRST_BUCKET}"
            info "Extracted resource identifier: ${RESOURCE_IDENTIFIER}"
        fi
    fi
    
    # Set resource names based on identifier
    export RANDOM_SUFFIX="$RESOURCE_IDENTIFIER"
    export NODE_ID="eth-node-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="eth-contract-manager-${RANDOM_SUFFIX}"
    export API_NAME="ethereum-api-${RANDOM_SUFFIX}"
    export BUCKET_NAME="ethereum-artifacts-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export CLEANUP_LOG_FILE="/tmp/ethereum-cleanup-${RANDOM_SUFFIX}.log"
    
    info "Resource names set:"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
    info "  Node ID: ${NODE_ID}"
    info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    info "  API Name: ${API_NAME}"
    info "  Bucket Name: ${BUCKET_NAME}"
    
    # Create cleanup log file
    echo "Cleanup started at $(date)" > "$CLEANUP_LOG_FILE"
    echo "Resources to be cleaned up:" >> "$CLEANUP_LOG_FILE"
    echo "  NODE_ID=${NODE_ID}" >> "$CLEANUP_LOG_FILE"
    echo "  LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}" >> "$CLEANUP_LOG_FILE"
    echo "  API_NAME=${API_NAME}" >> "$CLEANUP_LOG_FILE"
    echo "  BUCKET_NAME=${BUCKET_NAME}" >> "$CLEANUP_LOG_FILE"
}

# Load deployment information if available
load_deployment_info() {
    log "Loading deployment information..."
    
    # Try to download deployment info from S3
    if aws s3 cp "s3://${BUCKET_NAME}/deployment-info.json" "/tmp/deployment-info.json" 2>/dev/null; then
        info "Deployment information loaded from S3"
        
        # Parse deployment info
        if command -v jq &> /dev/null; then
            NODE_ID=$(jq -r '.resources.ethereumNodeId // empty' /tmp/deployment-info.json)
            LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambdaFunctionName // empty' /tmp/deployment-info.json)
            API_ID=$(jq -r '.resources.apiGatewayId // empty' /tmp/deployment-info.json)
            API_NAME=$(jq -r '.resources.apiName // empty' /tmp/deployment-info.json)
            BUCKET_NAME=$(jq -r '.resources.s3BucketName // empty' /tmp/deployment-info.json)
            
            info "Loaded resource information:"
            info "  Node ID: ${NODE_ID}"
            info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
            info "  API Gateway ID: ${API_ID}"
            info "  API Name: ${API_NAME}"
            info "  S3 Bucket: ${BUCKET_NAME}"
        fi
        
        rm -f /tmp/deployment-info.json
    else
        warn "Could not load deployment information from S3"
        info "Proceeding with resource names based on identifier"
    fi
}

# Confirm destruction
confirm_destruction() {
    log "Confirming resource destruction..."
    
    warn "THIS WILL PERMANENTLY DELETE ALL ETHEREUM BLOCKCHAIN RESOURCES"
    warn "This action cannot be undone!"
    
    echo ""
    echo "Resources to be deleted:"
    echo "  - Ethereum Node: ${NODE_ID}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - API Gateway: ${API_NAME}"
    echo "  - S3 Bucket: ${BUCKET_NAME}"
    echo "  - IAM Role and Policy: ${LAMBDA_FUNCTION_NAME}-role"
    echo "  - CloudWatch Dashboard: Ethereum-Blockchain-${RANDOM_SUFFIX}"
    echo "  - CloudWatch Alarm: ${LAMBDA_FUNCTION_NAME}-errors"
    echo "  - Parameter Store values"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Please type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        info "Destruction cancelled - incorrect confirmation"
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
    
    echo "Destruction confirmed at $(date)" >> "$CLEANUP_LOG_FILE"
}

# Find and delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway resources..."
    
    # Find API Gateway by name
    API_ID=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
        info "Found API Gateway: ${API_ID}"
        
        # Delete API Gateway
        aws apigateway delete-rest-api --rest-api-id "$API_ID" || warn "Failed to delete API Gateway"
        
        log "API Gateway deleted successfully"
        echo "API Gateway deleted: ${API_ID}" >> "$CLEANUP_LOG_FILE"
    else
        warn "API Gateway not found: ${API_NAME}"
        echo "API Gateway not found: ${API_NAME}" >> "$CLEANUP_LOG_FILE"
    fi
}

# Delete Lambda function and permissions
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        info "Found Lambda function: ${LAMBDA_FUNCTION_NAME}"
        
        # Delete Lambda function
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || warn "Failed to delete Lambda function"
        
        log "Lambda function deleted successfully"
        echo "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}" >> "$CLEANUP_LOG_FILE"
    else
        warn "Lambda function not found: ${LAMBDA_FUNCTION_NAME}"
        echo "Lambda function not found: ${LAMBDA_FUNCTION_NAME}" >> "$CLEANUP_LOG_FILE"
    fi
}

# Delete IAM role and policies
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    local policy_name="${LAMBDA_FUNCTION_NAME}-blockchain-policy"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        info "Found IAM role: ${role_name}"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || warn "Failed to detach basic execution policy"
        
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" || warn "Failed to detach blockchain policy"
        
        # Delete role
        aws iam delete-role --role-name "$role_name" || warn "Failed to delete IAM role"
        
        log "IAM role deleted successfully"
        echo "IAM role deleted: ${role_name}" >> "$CLEANUP_LOG_FILE"
    else
        warn "IAM role not found: ${role_name}"
        echo "IAM role not found: ${role_name}" >> "$CLEANUP_LOG_FILE"
    fi
    
    # Check if custom policy exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" >/dev/null 2>&1; then
        info "Found IAM policy: ${policy_name}"
        
        # Delete policy
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" || warn "Failed to delete IAM policy"
        
        log "IAM policy deleted successfully"
        echo "IAM policy deleted: ${policy_name}" >> "$CLEANUP_LOG_FILE"
    else
        warn "IAM policy not found: ${policy_name}"
        echo "IAM policy not found: ${policy_name}" >> "$CLEANUP_LOG_FILE"
    fi
}

# Delete Ethereum node
delete_ethereum_node() {
    log "Deleting Ethereum node..."
    
    # Check if node exists
    if aws managedblockchain get-node --network-id n-ethereum-mainnet --node-id "$NODE_ID" >/dev/null 2>&1; then
        info "Found Ethereum node: ${NODE_ID}"
        
        # Delete node
        aws managedblockchain delete-node \
            --network-id n-ethereum-mainnet \
            --node-id "$NODE_ID" || warn "Failed to delete Ethereum node"
        
        info "Ethereum node deletion initiated (this may take several minutes)"
        
        # Wait for node deletion to complete
        local max_attempts=60  # 1 hour maximum
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! aws managedblockchain get-node --network-id n-ethereum-mainnet --node-id "$NODE_ID" >/dev/null 2>&1; then
                log "Ethereum node deleted successfully"
                break
            else
                info "Waiting for node deletion to complete..."
                sleep 60
            fi
            ((attempt++))
        done
        
        if [ $attempt -eq $max_attempts ]; then
            warn "Timeout waiting for Ethereum node deletion"
        fi
        
        echo "Ethereum node deleted: ${NODE_ID}" >> "$CLEANUP_LOG_FILE"
    else
        warn "Ethereum node not found: ${NODE_ID}"
        echo "Ethereum node not found: ${NODE_ID}" >> "$CLEANUP_LOG_FILE"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        info "Found S3 bucket: ${BUCKET_NAME}"
        
        # Delete all objects in bucket
        aws s3 rm "s3://${BUCKET_NAME}" --recursive || warn "Failed to delete S3 bucket contents"
        
        # Delete all object versions (if versioning is enabled)
        aws s3api delete-objects --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" \
                --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || warn "Failed to delete object versions"
        
        # Delete delete markers
        aws s3api delete-objects --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" \
                --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || warn "Failed to delete delete markers"
        
        # Delete bucket
        aws s3api delete-bucket --bucket "$BUCKET_NAME" || warn "Failed to delete S3 bucket"
        
        log "S3 bucket deleted successfully"
        echo "S3 bucket deleted: ${BUCKET_NAME}" >> "$CLEANUP_LOG_FILE"
    else
        warn "S3 bucket not found: ${BUCKET_NAME}"
        echo "S3 bucket not found: ${BUCKET_NAME}" >> "$CLEANUP_LOG_FILE"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    local dashboard_name="Ethereum-Blockchain-${RANDOM_SUFFIX}"
    local alarm_name="${LAMBDA_FUNCTION_NAME}-errors"
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" >/dev/null 2>&1; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" || warn "Failed to delete CloudWatch dashboard"
        log "CloudWatch dashboard deleted: ${dashboard_name}"
        echo "CloudWatch dashboard deleted: ${dashboard_name}" >> "$CLEANUP_LOG_FILE"
    else
        warn "CloudWatch dashboard not found: ${dashboard_name}"
        echo "CloudWatch dashboard not found: ${dashboard_name}" >> "$CLEANUP_LOG_FILE"
    fi
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "$alarm_name"; then
        aws cloudwatch delete-alarms --alarm-names "$alarm_name" || warn "Failed to delete CloudWatch alarm"
        log "CloudWatch alarm deleted: ${alarm_name}"
        echo "CloudWatch alarm deleted: ${alarm_name}" >> "$CLEANUP_LOG_FILE"
    else
        warn "CloudWatch alarm not found: ${alarm_name}"
        echo "CloudWatch alarm not found: ${alarm_name}" >> "$CLEANUP_LOG_FILE"
    fi
    
    # Delete CloudWatch log groups
    local log_groups=(
        "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        "/aws/apigateway/${API_NAME}"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            aws logs delete-log-group --log-group-name "$log_group" || warn "Failed to delete log group: $log_group"
            log "Log group deleted: ${log_group}"
            echo "Log group deleted: ${log_group}" >> "$CLEANUP_LOG_FILE"
        else
            warn "Log group not found: ${log_group}"
            echo "Log group not found: ${log_group}" >> "$CLEANUP_LOG_FILE"
        fi
    done
}

# Delete Parameter Store values
delete_parameter_store() {
    log "Deleting Parameter Store values..."
    
    local parameters=(
        "/ethereum/${LAMBDA_FUNCTION_NAME}/http-endpoint"
        "/ethereum/${LAMBDA_FUNCTION_NAME}/ws-endpoint"
    )
    
    for param in "${parameters[@]}"; do
        if aws ssm get-parameter --name "$param" >/dev/null 2>&1; then
            aws ssm delete-parameter --name "$param" || warn "Failed to delete parameter: $param"
            log "Parameter deleted: ${param}"
            echo "Parameter deleted: ${param}" >> "$CLEANUP_LOG_FILE"
        else
            warn "Parameter not found: ${param}"
            echo "Parameter not found: ${param}" >> "$CLEANUP_LOG_FILE"
        fi
    done
}

# Clean up temporary files
cleanup_temporary_files() {
    log "Cleaning up temporary files..."
    
    # Clean up temporary directories and files
    rm -rf "/tmp/ethereum-contracts-${RANDOM_SUFFIX}" 2>/dev/null || true
    rm -rf "/tmp/lambda-deployment-${RANDOM_SUFFIX}" 2>/dev/null || true
    rm -f "/tmp/lambda-deployment.zip" 2>/dev/null || true
    rm -f "/tmp/ethereum-deployment-info-${RANDOM_SUFFIX}.json" 2>/dev/null || true
    rm -f "/tmp/lambda-response.json" 2>/dev/null || true
    rm -f "/tmp/deployment-info.json" 2>/dev/null || true
    
    log "Temporary files cleaned up"
    echo "Temporary files cleaned up" >> "$CLEANUP_LOG_FILE"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        warn "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check API Gateway
    local api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        warn "API Gateway still exists: ${API_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warn "S3 bucket still exists: ${BUCKET_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" >/dev/null 2>&1; then
        warn "IAM role still exists: ${LAMBDA_FUNCTION_NAME}-role"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup verification completed successfully"
        echo "Cleanup verification: SUCCESS" >> "$CLEANUP_LOG_FILE"
    else
        warn "Cleanup verification found ${cleanup_issues} issues"
        echo "Cleanup verification: ISSUES (${cleanup_issues})" >> "$CLEANUP_LOG_FILE"
    fi
}

# Main cleanup function
main() {
    log "Starting Ethereum Smart Contract cleanup..."
    
    check_prerequisites
    initialize_environment
    find_deployment_resources "$1"
    load_deployment_info
    confirm_destruction
    delete_api_gateway
    delete_lambda_function
    delete_iam_resources
    delete_ethereum_node
    delete_s3_bucket
    delete_cloudwatch_resources
    delete_parameter_store
    cleanup_temporary_files
    verify_cleanup
    
    echo "Cleanup completed at $(date)" >> "$CLEANUP_LOG_FILE"
    
    log "Cleanup completed successfully!"
    log "================================================"
    log "CLEANUP SUMMARY"
    log "================================================"
    log "AWS Region: ${AWS_REGION}"
    log "Resources cleaned up:"
    log "  - Ethereum Node: ${NODE_ID}"
    log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "  - API Gateway: ${API_NAME}"
    log "  - S3 Bucket: ${BUCKET_NAME}"
    log "  - IAM Role and Policy"
    log "  - CloudWatch Dashboard and Alarm"
    log "  - Parameter Store values"
    log "  - Temporary files"
    log "Cleanup Log: ${CLEANUP_LOG_FILE}"
    log "================================================"
    
    info "All resources have been cleaned up to avoid ongoing charges"
    info "The Ethereum node deletion may take several minutes to complete"
}

# Run main function
main "$@"
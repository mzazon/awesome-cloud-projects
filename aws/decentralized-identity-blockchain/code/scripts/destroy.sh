#!/bin/bash

# Decentralized Identity Management with Blockchain - Cleanup Script
# This script removes all AWS resources created by the deployment script
# including Managed Blockchain network, QLDB ledger, Lambda functions, and supporting infrastructure.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not authenticated. Please run 'aws configure' or set AWS credentials."
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ ! -f ".env" ]]; then
        log_error ".env file not found. Cannot determine which resources to delete."
        log "This file should have been created by the deploy.sh script."
        exit 1
    fi
    
    # Source the environment file
    set -a  # Automatically export all variables
    source .env
    set +a  # Turn off automatic export
    
    log_success "Environment variables loaded from .env file"
    log "Region: ${AWS_REGION:-Not set}"
    log "Random Suffix: ${RANDOM_SUFFIX:-Not set}"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "=================================================="
    echo "DECENTRALIZED IDENTITY MANAGEMENT CLEANUP WARNING"
    echo "=================================================="
    echo
    echo "This script will DELETE the following resources:"
    echo
    echo "Blockchain Network: ${NETWORK_NAME:-Not set}"
    echo "QLDB Ledger: ${QLDB_LEDGER_NAME:-Not set}"
    echo "DynamoDB Table: ${DYNAMODB_TABLE_NAME:-Not set}"
    echo "S3 Bucket: ${S3_BUCKET_NAME:-Not set}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME:-Not set}"
    echo "API Gateway: ${API_NAME:-Not set}"
    echo "IAM Role: ${IAM_ROLE_NAME:-Not set}"
    echo "IAM Policy: ${IAM_POLICY_NAME:-Not set}"
    echo
    echo "⚠️  THIS ACTION CANNOT BE UNDONE ⚠️"
    echo
    
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete all these resources? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed deletion, proceeding with cleanup..."
}

# Function to remove API Gateway
remove_api_gateway() {
    log "Removing API Gateway..."
    
    if [[ -z "${API_ID:-}" ]]; then
        log_warning "API_ID not found, skipping API Gateway deletion"
        return 0
    fi
    
    # Check if API Gateway exists
    if aws apigateway get-rest-api --rest-api-id "${API_ID}" >/dev/null 2>&1; then
        aws apigateway delete-rest-api --rest-api-id "${API_ID}" || {
            log_warning "Failed to delete API Gateway ${API_ID}"
        }
        log_success "Deleted API Gateway: ${API_ID}"
    else
        log_warning "API Gateway ${API_ID} not found, may have been already deleted"
    fi
}

# Function to remove Lambda function
remove_lambda_function() {
    log "Removing Lambda function..."
    
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_warning "LAMBDA_FUNCTION_NAME not found, skipping Lambda deletion"
        return 0
    fi
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" || {
            log_warning "Failed to delete Lambda function ${LAMBDA_FUNCTION_NAME}"
        }
        log_success "Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
    else
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found, may have been already deleted"
    fi
    
    # Clean up deployment package
    if [[ -f "identity-lambda.zip" ]]; then
        rm -f identity-lambda.zip
        log "Cleaned up Lambda deployment package"
    fi
    
    # Clean up chaincode directory
    if [[ -d "chaincode" ]]; then
        rm -rf chaincode/
        log "Cleaned up chaincode directory"
    fi
}

# Function to remove blockchain network
remove_blockchain_network() {
    log "Removing AWS Managed Blockchain network..."
    
    if [[ -z "${NETWORK_ID:-}" ]] || [[ -z "${MEMBER_ID:-}" ]]; then
        log_warning "NETWORK_ID or MEMBER_ID not found, skipping blockchain deletion"
        return 0
    fi
    
    # Delete peer node first
    if [[ -n "${PEER_NODE_ID:-}" ]]; then
        log "Deleting peer node..."
        if aws managedblockchain get-node --network-id "${NETWORK_ID}" --member-id "${MEMBER_ID}" --node-id "${PEER_NODE_ID}" >/dev/null 2>&1; then
            aws managedblockchain delete-node \
                --network-id "${NETWORK_ID}" \
                --member-id "${MEMBER_ID}" \
                --node-id "${PEER_NODE_ID}" || {
                log_warning "Failed to delete peer node ${PEER_NODE_ID}"
            }
            
            # Wait for node deletion
            log "Waiting for peer node deletion..."
            local max_attempts=20
            local attempt=1
            while [[ $attempt -le $max_attempts ]]; do
                if ! aws managedblockchain get-node --network-id "${NETWORK_ID}" --member-id "${MEMBER_ID}" --node-id "${PEER_NODE_ID}" >/dev/null 2>&1; then
                    break
                fi
                log "Attempt $attempt: Waiting for peer node deletion..."
                sleep 30
                ((attempt++))
            done
            
            log_success "Deleted peer node: ${PEER_NODE_ID}"
        else
            log_warning "Peer node ${PEER_NODE_ID} not found, may have been already deleted"
        fi
    fi
    
    # Delete member
    log "Deleting blockchain member..."
    if aws managedblockchain get-member --network-id "${NETWORK_ID}" --member-id "${MEMBER_ID}" >/dev/null 2>&1; then
        aws managedblockchain delete-member \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" || {
            log_warning "Failed to delete member ${MEMBER_ID}"
        }
        
        # Wait for member deletion
        log "Waiting for member deletion..."
        local max_attempts=20
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if ! aws managedblockchain get-member --network-id "${NETWORK_ID}" --member-id "${MEMBER_ID}" >/dev/null 2>&1; then
                break
            fi
            log "Attempt $attempt: Waiting for member deletion..."
            sleep 30
            ((attempt++))
        done
        
        log_success "Deleted member: ${MEMBER_ID}"
    else
        log_warning "Member ${MEMBER_ID} not found, may have been already deleted"
    fi
    
    # Delete network
    log "Deleting blockchain network..."
    if aws managedblockchain get-network --network-id "${NETWORK_ID}" >/dev/null 2>&1; then
        aws managedblockchain delete-network --network-id "${NETWORK_ID}" || {
            log_warning "Failed to delete network ${NETWORK_ID}"
        }
        
        # Wait for network deletion
        log "Waiting for network deletion..."
        local max_attempts=20
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if ! aws managedblockchain get-network --network-id "${NETWORK_ID}" >/dev/null 2>&1; then
                break
            fi
            log "Attempt $attempt: Waiting for network deletion..."
            sleep 30
            ((attempt++))
        done
        
        log_success "Deleted blockchain network: ${NETWORK_ID}"
    else
        log_warning "Network ${NETWORK_ID} not found, may have been already deleted"
    fi
}

# Function to remove QLDB ledger
remove_qldb_ledger() {
    log "Removing QLDB ledger..."
    
    if [[ -z "${QLDB_LEDGER_NAME:-}" ]]; then
        log_warning "QLDB_LEDGER_NAME not found, skipping QLDB deletion"
        return 0
    fi
    
    # Check if QLDB ledger exists
    if aws qldb describe-ledger --name "${QLDB_LEDGER_NAME}" >/dev/null 2>&1; then
        aws qldb delete-ledger --name "${QLDB_LEDGER_NAME}" || {
            log_warning "Failed to delete QLDB ledger ${QLDB_LEDGER_NAME}"
        }
        
        # Wait for ledger deletion
        log "Waiting for QLDB ledger deletion..."
        local max_attempts=30
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if ! aws qldb describe-ledger --name "${QLDB_LEDGER_NAME}" >/dev/null 2>&1; then
                break
            fi
            log "Attempt $attempt: Waiting for QLDB ledger deletion..."
            sleep 10
            ((attempt++))
        done
        
        log_success "Deleted QLDB ledger: ${QLDB_LEDGER_NAME}"
    else
        log_warning "QLDB ledger ${QLDB_LEDGER_NAME} not found, may have been already deleted"
    fi
}

# Function to remove DynamoDB table
remove_dynamodb_table() {
    log "Removing DynamoDB table..."
    
    if [[ -z "${DYNAMODB_TABLE_NAME:-}" ]]; then
        log_warning "DYNAMODB_TABLE_NAME not found, skipping DynamoDB deletion"
        return 0
    fi
    
    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE_NAME}" >/dev/null 2>&1; then
        aws dynamodb delete-table --table-name "${DYNAMODB_TABLE_NAME}" || {
            log_warning "Failed to delete DynamoDB table ${DYNAMODB_TABLE_NAME}"
        }
        
        # Wait for table deletion
        log "Waiting for DynamoDB table deletion..."
        aws dynamodb wait table-not-exists --table-name "${DYNAMODB_TABLE_NAME}" || {
            log_warning "Timeout waiting for DynamoDB table deletion"
        }
        
        log_success "Deleted DynamoDB table: ${DYNAMODB_TABLE_NAME}"
    else
        log_warning "DynamoDB table ${DYNAMODB_TABLE_NAME} not found, may have been already deleted"
    fi
}

# Function to remove S3 bucket
remove_s3_bucket() {
    log "Removing S3 bucket and contents..."
    
    if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
        log_warning "S3_BUCKET_NAME not found, skipping S3 deletion"
        return 0
    fi
    
    # Check if S3 bucket exists
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        # Remove all objects from bucket
        log "Removing all objects from S3 bucket..."
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive || {
            log_warning "Failed to remove objects from S3 bucket ${S3_BUCKET_NAME}"
        }
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}" || {
            log_warning "Failed to delete S3 bucket ${S3_BUCKET_NAME}"
        }
        
        log_success "Deleted S3 bucket: ${S3_BUCKET_NAME}"
    else
        log_warning "S3 bucket ${S3_BUCKET_NAME} not found, may have been already deleted"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM roles and policies..."
    
    if [[ -z "${IAM_ROLE_NAME:-}" ]] || [[ -z "${IAM_POLICY_NAME:-}" ]]; then
        log_warning "IAM_ROLE_NAME or IAM_POLICY_NAME not found, skipping IAM deletion"
        return 0
    fi
    
    # Check if IAM role exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" >/dev/null 2>&1; then
        # Detach policies from role
        log "Detaching policies from IAM role..."
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || {
            log_warning "Failed to detach AWSLambdaBasicExecutionRole policy"
        }
        
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" || {
            log_warning "Failed to detach custom policy"
        }
        
        # Delete the role
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" || {
            log_warning "Failed to delete IAM role ${IAM_ROLE_NAME}"
        }
        
        log_success "Deleted IAM role: ${IAM_ROLE_NAME}"
    else
        log_warning "IAM role ${IAM_ROLE_NAME} not found, may have been already deleted"
    fi
    
    # Check if custom IAM policy exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" >/dev/null 2>&1; then
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" || {
            log_warning "Failed to delete IAM policy ${IAM_POLICY_NAME}"
        }
        
        log_success "Deleted IAM policy: ${IAM_POLICY_NAME}"
    else
        log_warning "IAM policy ${IAM_POLICY_NAME} not found, may have been already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "identity-lambda.js"
        "identity-lambda.zip"
        "response.json"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed file: $file"
        fi
    done
    
    # Remove chaincode directory if it exists
    if [[ -d "chaincode" ]]; then
        rm -rf chaincode/
        log "Removed chaincode directory"
    fi
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup completed!"
    echo
    echo "=================================================="
    echo "DECENTRALIZED IDENTITY MANAGEMENT CLEANUP SUMMARY"
    echo "=================================================="
    echo
    echo "The following resources have been removed:"
    echo
    echo "✅ API Gateway: ${API_NAME:-N/A}"
    echo "✅ Lambda Function: ${LAMBDA_FUNCTION_NAME:-N/A}"
    echo "✅ Blockchain Network: ${NETWORK_NAME:-N/A}"
    echo "✅ QLDB Ledger: ${QLDB_LEDGER_NAME:-N/A}"
    echo "✅ DynamoDB Table: ${DYNAMODB_TABLE_NAME:-N/A}"
    echo "✅ S3 Bucket: ${S3_BUCKET_NAME:-N/A}"
    echo "✅ IAM Role: ${IAM_ROLE_NAME:-N/A}"
    echo "✅ IAM Policy: ${IAM_POLICY_NAME:-N/A}"
    echo "✅ Local files and directories"
    echo
    echo "=================================================="
    echo
    echo "All resources have been successfully cleaned up."
    echo "You should no longer incur charges for these resources."
    echo
    echo "If you need to redeploy, run deploy.sh again."
    echo "=================================================="
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    log_warning "Some cleanup operations may have failed."
    echo
    echo "Common reasons for cleanup failures:"
    echo "1. Resources may have already been deleted"
    echo "2. Insufficient permissions for certain operations"
    echo "3. Resources may be in use by other services"
    echo "4. Network connectivity issues"
    echo
    echo "Please check the AWS Console to verify resource deletion."
    echo "You may need to manually delete any remaining resources."
}

# Main execution function
main() {
    log "Starting decentralized identity management cleanup..."
    
    # Check if dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    # Check prerequisites
    check_aws_auth
    
    # Load environment and confirm deletion
    load_environment
    confirm_deletion "$@"
    
    # Execute cleanup in reverse order of creation
    local cleanup_errors=0
    
    # API Gateway (created last, deleted first)
    remove_api_gateway || ((cleanup_errors++))
    
    # Lambda function
    remove_lambda_function || ((cleanup_errors++))
    
    # Blockchain network (nodes, members, network)
    remove_blockchain_network || ((cleanup_errors++))
    
    # QLDB ledger
    remove_qldb_ledger || ((cleanup_errors++))
    
    # DynamoDB table
    remove_dynamodb_table || ((cleanup_errors++))
    
    # S3 bucket
    remove_s3_bucket || ((cleanup_errors++))
    
    # IAM resources
    remove_iam_resources || ((cleanup_errors++))
    
    # Local files cleanup
    cleanup_local_files
    
    # Display results
    if [[ $cleanup_errors -eq 0 ]]; then
        display_cleanup_summary
    else
        handle_cleanup_errors
        log_warning "Cleanup completed with $cleanup_errors errors"
    fi
    
    log_success "Cleanup process finished!"
}

# Handle script termination
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Cleanup script encountered an error"
        log "Some resources may not have been deleted. Please check the AWS Console."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"
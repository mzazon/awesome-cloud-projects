#!/bin/bash

# Destroy script for Serverless Analytics with Athena Federated Query
# This script safely removes all resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "${LOG_FILE}"
}

# Function to prompt for confirmation
confirm_destruction() {
    if [[ "${1:-}" == "--force" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will destroy all resources created by the deployment script.${NC}"
    echo "This action cannot be undone. The following resources will be deleted:"
    echo "- S3 buckets and all their contents"
    echo "- RDS MySQL instance and all data"
    echo "- DynamoDB table and all data"
    echo "- VPC and all networking resources"
    echo "- Lambda connectors and CloudFormation stacks"
    echo "- Athena workgroup and data catalogs"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " response
    
    if [[ "$response" != "yes" ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
}

# Load environment variables
load_environment() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        error "Environment file not found: ${ENV_FILE}"
        error "Cannot proceed without environment variables from deployment."
        exit 1
    fi
    
    log "Loading environment variables..."
    source "${ENV_FILE}"
    
    # Verify required variables
    if [[ -z "${AWS_REGION:-}" ]] || [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        error "Missing required environment variables in ${ENV_FILE}"
        exit 1
    fi
    
    log "Environment loaded successfully"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account: ${AWS_ACCOUNT_ID}"
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
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    # Verify we're working with the correct AWS account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [[ "${CURRENT_ACCOUNT}" != "${AWS_ACCOUNT_ID}" ]]; then
        error "AWS account mismatch. Expected: ${AWS_ACCOUNT_ID}, Current: ${CURRENT_ACCOUNT}"
    fi
    
    log "Prerequisites check completed successfully"
}

# Remove Athena resources
remove_athena_resources() {
    log "Removing Athena resources..."
    
    # Drop federated view if it exists
    info "Dropping federated view..."
    aws athena start-query-execution \
        --query-string "DROP VIEW IF EXISTS default.order_analytics" \
        --work-group "federated-analytics" \
        --query 'QueryExecutionId' --output text &>/dev/null || true
    
    # Delete data catalogs
    info "Deleting data catalogs..."
    aws athena delete-data-catalog --name "mysql_catalog" 2>/dev/null || true
    aws athena delete-data-catalog --name "dynamodb_catalog" 2>/dev/null || true
    
    # Delete workgroup
    info "Deleting Athena workgroup..."
    aws athena delete-work-group --work-group "federated-analytics" 2>/dev/null || true
    
    log "Athena resources removed successfully"
}

# Remove Lambda functions and CloudFormation stacks
remove_lambda_connectors() {
    log "Removing Lambda connector functions..."
    
    # Delete MySQL connector stack
    info "Deleting MySQL connector stack..."
    aws cloudformation delete-stack --stack-name athena-mysql-connector 2>/dev/null || true
    
    # Delete DynamoDB connector stack
    info "Deleting DynamoDB connector stack..."
    aws cloudformation delete-stack --stack-name athena-dynamodb-connector 2>/dev/null || true
    
    # Wait for stack deletions to complete
    log "Waiting for connector stack deletions to complete..."
    
    # Wait for MySQL connector stack
    info "Waiting for MySQL connector stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name athena-mysql-connector 2>/dev/null || true
    
    # Wait for DynamoDB connector stack
    info "Waiting for DynamoDB connector stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name athena-dynamodb-connector 2>/dev/null || true
    
    log "Lambda connector functions removed successfully"
}

# Remove DynamoDB table
remove_dynamodb_table() {
    log "Removing DynamoDB table..."
    
    if [[ -n "${DYNAMO_TABLE_NAME:-}" ]]; then
        # Check if table exists
        if aws dynamodb describe-table --table-name "${DYNAMO_TABLE_NAME}" &>/dev/null; then
            info "Deleting DynamoDB table: ${DYNAMO_TABLE_NAME}"
            aws dynamodb delete-table --table-name "${DYNAMO_TABLE_NAME}"
            
            # Wait for table deletion
            log "Waiting for DynamoDB table deletion..."
            aws dynamodb wait table-not-exists --table-name "${DYNAMO_TABLE_NAME}"
            
            log "DynamoDB table deleted successfully"
        else
            log "DynamoDB table ${DYNAMO_TABLE_NAME} not found, skipping..."
        fi
    else
        warn "DynamoDB table name not found in environment"
    fi
}

# Remove RDS instance
remove_rds_instance() {
    log "Removing RDS instance..."
    
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        # Check if RDS instance exists
        if aws rds describe-db-instances --db-instance-identifier "${DB_INSTANCE_ID}" &>/dev/null; then
            info "Deleting RDS instance: ${DB_INSTANCE_ID}"
            aws rds delete-db-instance \
                --db-instance-identifier "${DB_INSTANCE_ID}" \
                --skip-final-snapshot \
                --delete-automated-backups
            
            # Wait for RDS instance deletion
            log "Waiting for RDS instance deletion (this may take several minutes)..."
            aws rds wait db-instance-deleted \
                --db-instance-identifier "${DB_INSTANCE_ID}"
            
            log "RDS instance deleted successfully"
        else
            log "RDS instance ${DB_INSTANCE_ID} not found, skipping..."
        fi
    else
        warn "RDS instance ID not found in environment"
    fi
    
    # Delete DB subnet group
    info "Deleting DB subnet group..."
    aws rds delete-db-subnet-group \
        --db-subnet-group-name athena-federated-subnet-group 2>/dev/null || true
    
    log "RDS resources removed successfully"
}

# Remove VPC and networking resources
remove_vpc_resources() {
    log "Removing VPC and networking resources..."
    
    if [[ -n "${VPC_ID:-}" ]]; then
        # Delete security group
        if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
            info "Deleting security group: ${SECURITY_GROUP_ID}"
            aws ec2 delete-security-group --group-id "${SECURITY_GROUP_ID}" 2>/dev/null || true
        fi
        
        # Delete subnets
        if [[ -n "${SUBNET_ID:-}" ]]; then
            info "Deleting subnet: ${SUBNET_ID}"
            aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" 2>/dev/null || true
        fi
        
        if [[ -n "${SUBNET_ID_2:-}" ]]; then
            info "Deleting subnet: ${SUBNET_ID_2}"
            aws ec2 delete-subnet --subnet-id "${SUBNET_ID_2}" 2>/dev/null || true
        fi
        
        # Delete VPC
        info "Deleting VPC: ${VPC_ID}"
        aws ec2 delete-vpc --vpc-id "${VPC_ID}" 2>/dev/null || true
        
        log "VPC resources removed successfully"
    else
        warn "VPC ID not found in environment"
    fi
}

# Remove S3 buckets
remove_s3_buckets() {
    log "Removing S3 buckets..."
    
    # Remove spill bucket
    if [[ -n "${SPILL_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${SPILL_BUCKET_NAME}" 2>/dev/null; then
            info "Deleting spill bucket: ${SPILL_BUCKET_NAME}"
            aws s3 rm "s3://${SPILL_BUCKET_NAME}" --recursive 2>/dev/null || true
            aws s3 rb "s3://${SPILL_BUCKET_NAME}" 2>/dev/null || true
            log "Spill bucket removed successfully"
        else
            log "Spill bucket ${SPILL_BUCKET_NAME} not found, skipping..."
        fi
    else
        warn "Spill bucket name not found in environment"
    fi
    
    # Remove results bucket
    if [[ -n "${RESULTS_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${RESULTS_BUCKET_NAME}" 2>/dev/null; then
            info "Deleting results bucket: ${RESULTS_BUCKET_NAME}"
            aws s3 rm "s3://${RESULTS_BUCKET_NAME}" --recursive 2>/dev/null || true
            aws s3 rb "s3://${RESULTS_BUCKET_NAME}" 2>/dev/null || true
            log "Results bucket removed successfully"
        else
            log "Results bucket ${RESULTS_BUCKET_NAME} not found, skipping..."
        fi
    else
        warn "Results bucket name not found in environment"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f "${SCRIPT_DIR}/init_db.sql" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/user_data.sh" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/.deploy_progress" 2>/dev/null || true
    
    log "Temporary files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check S3 buckets
    if [[ -n "${SPILL_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${SPILL_BUCKET_NAME}" 2>/dev/null; then
            warn "Spill bucket ${SPILL_BUCKET_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ -n "${RESULTS_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${RESULTS_BUCKET_NAME}" 2>/dev/null; then
            warn "Results bucket ${RESULTS_BUCKET_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check RDS instance
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        if aws rds describe-db-instances --db-instance-identifier "${DB_INSTANCE_ID}" &>/dev/null; then
            warn "RDS instance ${DB_INSTANCE_ID} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check DynamoDB table
    if [[ -n "${DYNAMO_TABLE_NAME:-}" ]]; then
        if aws dynamodb describe-table --table-name "${DYNAMO_TABLE_NAME}" &>/dev/null; then
            warn "DynamoDB table ${DYNAMO_TABLE_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check CloudFormation stacks
    if aws cloudformation describe-stacks --stack-name athena-mysql-connector &>/dev/null; then
        warn "CloudFormation stack athena-mysql-connector still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws cloudformation describe-stacks --stack-name athena-dynamodb-connector &>/dev/null; then
        warn "CloudFormation stack athena-dynamodb-connector still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "✅ All resources successfully cleaned up"
    else
        warn "⚠️  ${cleanup_issues} resources may still exist. Check AWS console manually."
    fi
}

# Main destruction function
main() {
    log "Starting Athena Federated Query resource destruction..."
    log "Log file: ${LOG_FILE}"
    
    # Initialize log file
    echo "Destruction started at $(date)" > "${LOG_FILE}"
    
    # Load environment and check prerequisites
    load_environment
    check_prerequisites
    
    # Confirm destruction
    confirm_destruction "$@"
    
    # Remove resources in reverse order of creation
    log "Removing resources in reverse order..."
    
    # Step 1: Remove Athena resources (no dependencies)
    remove_athena_resources
    
    # Step 2: Remove Lambda connectors (depends on Athena)
    remove_lambda_connectors
    
    # Step 3: Remove DynamoDB table (no dependencies)
    remove_dynamodb_table
    
    # Step 4: Remove RDS instance (depends on VPC)
    remove_rds_instance
    
    # Step 5: Remove VPC resources (depends on RDS)
    remove_vpc_resources
    
    # Step 6: Remove S3 buckets (no dependencies)
    remove_s3_buckets
    
    # Step 7: Clean up temporary files
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    # Final success message
    log "🎉 Resource destruction completed!"
    log ""
    log "Summary of removed resources:"
    log "- Athena workgroup and data catalogs"
    log "- Lambda connectors and CloudFormation stacks"
    log "- DynamoDB table: ${DYNAMO_TABLE_NAME:-N/A}"
    log "- RDS MySQL instance: ${DB_INSTANCE_ID:-N/A}"
    log "- VPC and networking resources"
    log "- S3 buckets: ${SPILL_BUCKET_NAME:-N/A}, ${RESULTS_BUCKET_NAME:-N/A}"
    log ""
    log "Destruction log saved to: ${LOG_FILE}"
    
    # Ask if user wants to remove environment file
    if [[ "${1:-}" != "--force" ]]; then
        read -p "Remove environment file (.env)? (y/N): " remove_env
        if [[ "$remove_env" == "y" || "$remove_env" == "Y" ]]; then
            rm -f "${ENV_FILE}"
            log "Environment file removed"
        fi
    fi
}

# Check if running in dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log "DRY RUN MODE - No resources will be destroyed"
    
    if [[ -f "${ENV_FILE}" ]]; then
        source "${ENV_FILE}"
        log "This would destroy the following resources:"
        log "- Athena workgroup: federated-analytics"
        log "- Data catalogs: mysql_catalog, dynamodb_catalog"
        log "- Lambda connectors: athena-mysql-connector, athena-dynamodb-connector"
        log "- DynamoDB table: ${DYNAMO_TABLE_NAME:-N/A}"
        log "- RDS instance: ${DB_INSTANCE_ID:-N/A}"
        log "- S3 buckets: ${SPILL_BUCKET_NAME:-N/A}, ${RESULTS_BUCKET_NAME:-N/A}"
        log "- VPC and networking resources"
    else
        log "No environment file found - no resources to destroy"
    fi
    
    log "Use './destroy.sh' to perform actual destruction"
    log "Use './destroy.sh --force' to skip confirmation prompts"
    exit 0
fi

# Run main function
main "$@"
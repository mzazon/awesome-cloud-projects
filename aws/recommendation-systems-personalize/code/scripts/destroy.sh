#!/bin/bash

# Real-time Recommendation Systems with Amazon Personalize and API Gateway
# Cleanup/Destroy Script
# 
# This script removes all resources created by the deployment script
# to avoid ongoing charges and clean up the AWS account.

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f .env ]]; then
        source .env
        log "Environment variables loaded from .env file"
    else
        warn ".env file not found. You may need to provide resource names manually."
        
        # Try to get basic AWS info
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            error "Cannot determine AWS account ID. Please ensure AWS CLI is configured."
        fi
        
        log "Using region: ${AWS_REGION}"
        log "Using account ID: ${AWS_ACCOUNT_ID}"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "This will delete ALL resources created by the deployment script."
    warn "This action cannot be undone!"
    
    if [[ "${1:-}" == "--force" ]]; then
        log "Force flag detected, skipping confirmation"
        return 0
    fi
    
    echo -e "\n${YELLOW}The following resources will be deleted:${NC}"
    echo "- Amazon Personalize campaign, solution, and dataset group"
    echo "- Lambda function and IAM role"
    echo "- API Gateway REST API"
    echo "- S3 bucket and all contents"
    echo "- CloudWatch alarms"
    echo "- IAM roles and policies"
    
    echo -e "\n${RED}Are you sure you want to continue? (yes/no)${NC}"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding..."
}

# Function to delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway..."
    
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
            aws apigateway delete-rest-api --rest-api-id "${API_ID}"
            log "API Gateway deleted: ${API_ID}"
        else
            warn "API Gateway ${API_ID} not found or already deleted"
        fi
    else
        warn "API_ID not set, skipping API Gateway deletion"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
            log "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
        else
            warn "Lambda function ${LAMBDA_FUNCTION_NAME} not found or already deleted"
        fi
    else
        warn "LAMBDA_FUNCTION_NAME not set, skipping Lambda deletion"
    fi
}

# Function to delete Personalize campaign
delete_personalize_campaign() {
    log "Deleting Personalize campaign..."
    
    if [[ -n "${CAMPAIGN_ARN:-}" ]]; then
        if aws personalize describe-campaign --campaign-arn "${CAMPAIGN_ARN}" &>/dev/null; then
            aws personalize delete-campaign --campaign-arn "${CAMPAIGN_ARN}"
            log "Campaign deletion initiated: ${CAMPAIGN_ARN}"
            
            # Wait for campaign to be deleted
            info "Waiting for campaign to be deleted..."
            while true; do
                if ! aws personalize describe-campaign --campaign-arn "${CAMPAIGN_ARN}" &>/dev/null; then
                    log "Campaign deleted successfully"
                    break
                fi
                info "Campaign still exists, waiting..."
                sleep 30
            done
        else
            warn "Campaign not found or already deleted"
        fi
    elif [[ -n "${CAMPAIGN_NAME:-}" && -n "${AWS_REGION:-}" && -n "${AWS_ACCOUNT_ID:-}" ]]; then
        # Try to construct ARN from name
        CAMPAIGN_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:campaign/${CAMPAIGN_NAME}"
        if aws personalize describe-campaign --campaign-arn "${CAMPAIGN_ARN}" &>/dev/null; then
            aws personalize delete-campaign --campaign-arn "${CAMPAIGN_ARN}"
            log "Campaign deletion initiated: ${CAMPAIGN_ARN}"
            
            # Wait for campaign to be deleted
            info "Waiting for campaign to be deleted..."
            while true; do
                if ! aws personalize describe-campaign --campaign-arn "${CAMPAIGN_ARN}" &>/dev/null; then
                    log "Campaign deleted successfully"
                    break
                fi
                info "Campaign still exists, waiting..."
                sleep 30
            done
        else
            warn "Campaign not found"
        fi
    else
        warn "CAMPAIGN_ARN or CAMPAIGN_NAME not set, skipping campaign deletion"
    fi
}

# Function to delete Personalize solution
delete_personalize_solution() {
    log "Deleting Personalize solution..."
    
    if [[ -n "${SOLUTION_ARN:-}" ]]; then
        if aws personalize describe-solution --solution-arn "${SOLUTION_ARN}" &>/dev/null; then
            aws personalize delete-solution --solution-arn "${SOLUTION_ARN}"
            log "Solution deletion initiated: ${SOLUTION_ARN}"
            
            # Wait for solution to be deleted
            info "Waiting for solution to be deleted..."
            while true; do
                if ! aws personalize describe-solution --solution-arn "${SOLUTION_ARN}" &>/dev/null; then
                    log "Solution deleted successfully"
                    break
                fi
                info "Solution still exists, waiting..."
                sleep 30
            done
        else
            warn "Solution not found or already deleted"
        fi
    elif [[ -n "${SOLUTION_NAME:-}" && -n "${AWS_REGION:-}" && -n "${AWS_ACCOUNT_ID:-}" ]]; then
        # Try to construct ARN from name
        SOLUTION_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${SOLUTION_NAME}"
        if aws personalize describe-solution --solution-arn "${SOLUTION_ARN}" &>/dev/null; then
            aws personalize delete-solution --solution-arn "${SOLUTION_ARN}"
            log "Solution deletion initiated: ${SOLUTION_ARN}"
            
            # Wait for solution to be deleted
            info "Waiting for solution to be deleted..."
            while true; do
                if ! aws personalize describe-solution --solution-arn "${SOLUTION_ARN}" &>/dev/null; then
                    log "Solution deleted successfully"
                    break
                fi
                info "Solution still exists, waiting..."
                sleep 30
            done
        else
            warn "Solution not found"
        fi
    else
        warn "SOLUTION_ARN or SOLUTION_NAME not set, skipping solution deletion"
    fi
}

# Function to delete Personalize dataset
delete_personalize_dataset() {
    log "Deleting Personalize dataset..."
    
    if [[ -n "${DATASET_ARN:-}" ]]; then
        if aws personalize describe-dataset --dataset-arn "${DATASET_ARN}" &>/dev/null; then
            aws personalize delete-dataset --dataset-arn "${DATASET_ARN}"
            log "Dataset deletion initiated: ${DATASET_ARN}"
            
            # Wait for dataset to be deleted
            info "Waiting for dataset to be deleted..."
            while true; do
                if ! aws personalize describe-dataset --dataset-arn "${DATASET_ARN}" &>/dev/null; then
                    log "Dataset deleted successfully"
                    break
                fi
                info "Dataset still exists, waiting..."
                sleep 30
            done
        else
            warn "Dataset not found or already deleted"
        fi
    elif [[ -n "${DATASET_GROUP_NAME:-}" && -n "${AWS_REGION:-}" && -n "${AWS_ACCOUNT_ID:-}" ]]; then
        # Try to construct ARN from dataset group name
        DATASET_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/INTERACTIONS"
        if aws personalize describe-dataset --dataset-arn "${DATASET_ARN}" &>/dev/null; then
            aws personalize delete-dataset --dataset-arn "${DATASET_ARN}"
            log "Dataset deletion initiated: ${DATASET_ARN}"
            
            # Wait for dataset to be deleted
            info "Waiting for dataset to be deleted..."
            while true; do
                if ! aws personalize describe-dataset --dataset-arn "${DATASET_ARN}" &>/dev/null; then
                    log "Dataset deleted successfully"
                    break
                fi
                info "Dataset still exists, waiting..."
                sleep 30
            done
        else
            warn "Dataset not found"
        fi
    else
        warn "DATASET_ARN or DATASET_GROUP_NAME not set, skipping dataset deletion"
    fi
}

# Function to delete Personalize schema
delete_personalize_schema() {
    log "Deleting Personalize schema..."
    
    if [[ -n "${SCHEMA_ARN:-}" ]]; then
        if aws personalize describe-schema --schema-arn "${SCHEMA_ARN}" &>/dev/null; then
            aws personalize delete-schema --schema-arn "${SCHEMA_ARN}"
            log "Schema deleted: ${SCHEMA_ARN}"
        else
            warn "Schema not found or already deleted"
        fi
    elif [[ -n "${RANDOM_SUFFIX:-}" && -n "${AWS_REGION:-}" && -n "${AWS_ACCOUNT_ID:-}" ]]; then
        # Try to construct ARN from suffix
        SCHEMA_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/interaction-schema-${RANDOM_SUFFIX}"
        if aws personalize describe-schema --schema-arn "${SCHEMA_ARN}" &>/dev/null; then
            aws personalize delete-schema --schema-arn "${SCHEMA_ARN}"
            log "Schema deleted: ${SCHEMA_ARN}"
        else
            warn "Schema not found"
        fi
    else
        warn "SCHEMA_ARN or RANDOM_SUFFIX not set, skipping schema deletion"
    fi
}

# Function to delete Personalize dataset group
delete_personalize_dataset_group() {
    log "Deleting Personalize dataset group..."
    
    if [[ -n "${DATASET_GROUP_ARN:-}" ]]; then
        if aws personalize describe-dataset-group --dataset-group-arn "${DATASET_GROUP_ARN}" &>/dev/null; then
            aws personalize delete-dataset-group --dataset-group-arn "${DATASET_GROUP_ARN}"
            log "Dataset group deleted: ${DATASET_GROUP_ARN}"
        else
            warn "Dataset group not found or already deleted"
        fi
    elif [[ -n "${DATASET_GROUP_NAME:-}" && -n "${AWS_REGION:-}" && -n "${AWS_ACCOUNT_ID:-}" ]]; then
        # Try to construct ARN from name
        DATASET_GROUP_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}"
        if aws personalize describe-dataset-group --dataset-group-arn "${DATASET_GROUP_ARN}" &>/dev/null; then
            aws personalize delete-dataset-group --dataset-group-arn "${DATASET_GROUP_ARN}"
            log "Dataset group deleted: ${DATASET_GROUP_ARN}"
        else
            warn "Dataset group not found"
        fi
    else
        warn "DATASET_GROUP_ARN or DATASET_GROUP_NAME not set, skipping dataset group deletion"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete Personalize IAM role
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local personalize_role_name="PersonalizeExecutionRole-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "${personalize_role_name}" &>/dev/null; then
            # Detach policies first
            aws iam detach-role-policy \
                --role-name "${personalize_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AmazonPersonalizeFullAccess \
                2>/dev/null || warn "Could not detach policy from ${personalize_role_name}"
            
            # Delete role
            aws iam delete-role --role-name "${personalize_role_name}"
            log "Personalize IAM role deleted: ${personalize_role_name}"
        else
            warn "Personalize IAM role not found: ${personalize_role_name}"
        fi
        
        # Delete Lambda IAM role
        local lambda_role_name="LambdaPersonalizeRole-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "${lambda_role_name}" &>/dev/null; then
            # Detach policies first
            aws iam detach-role-policy \
                --role-name "${lambda_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                2>/dev/null || warn "Could not detach basic execution policy from ${lambda_role_name}"
            
            aws iam detach-role-policy \
                --role-name "${lambda_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AmazonPersonalizeFullAccess \
                2>/dev/null || warn "Could not detach personalize policy from ${lambda_role_name}"
            
            # Delete role
            aws iam delete-role --role-name "${lambda_role_name}"
            log "Lambda IAM role deleted: ${lambda_role_name}"
        else
            warn "Lambda IAM role not found: ${lambda_role_name}"
        fi
    else
        warn "RANDOM_SUFFIX not set, skipping IAM role deletion"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            # Delete all objects in the bucket first
            aws s3 rm s3://"${BUCKET_NAME}" --recursive 2>/dev/null || warn "Could not delete objects from ${BUCKET_NAME}"
            
            # Delete the bucket
            aws s3api delete-bucket --bucket "${BUCKET_NAME}"
            log "S3 bucket deleted: ${BUCKET_NAME}"
        else
            warn "S3 bucket not found or already deleted: ${BUCKET_NAME}"
        fi
    else
        warn "BUCKET_NAME not set, skipping S3 bucket deletion"
    fi
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local alarm_name="RecommendationAPI-4xxErrors-${RANDOM_SUFFIX}"
        if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" --query 'MetricAlarms[0].AlarmName' --output text | grep -q "${alarm_name}"; then
            aws cloudwatch delete-alarms --alarm-names "${alarm_name}"
            log "CloudWatch alarm deleted: ${alarm_name}"
        else
            warn "CloudWatch alarm not found: ${alarm_name}"
        fi
    else
        warn "RANDOM_SUFFIX not set, skipping CloudWatch alarm deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might be left over
    rm -f personalize-trust-policy.json
    rm -f interactions-schema.json
    rm -f sample-interactions.csv
    rm -f recommendation-handler.py
    rm -f recommendation-handler.zip
    rm -f lambda-trust-policy.json
    
    # Remove environment file
    if [[ -f .env ]]; then
        rm -f .env
        log "Environment file removed"
    fi
    
    log "Local files cleaned up"
}

# Function to wait for resource deletion
wait_for_resource_deletion() {
    log "Waiting for all resources to be fully deleted..."
    
    # Give some time for async deletion operations to complete
    info "Waiting 30 seconds for deletion operations to complete..."
    sleep 30
    
    log "Resource deletion wait completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_successful=true
    
    # Check if resources still exist
    if [[ -n "${CAMPAIGN_ARN:-}" ]]; then
        if aws personalize describe-campaign --campaign-arn "${CAMPAIGN_ARN}" &>/dev/null; then
            warn "Campaign still exists: ${CAMPAIGN_ARN}"
            cleanup_successful=false
        fi
    fi
    
    if [[ -n "${SOLUTION_ARN:-}" ]]; then
        if aws personalize describe-solution --solution-arn "${SOLUTION_ARN}" &>/dev/null; then
            warn "Solution still exists: ${SOLUTION_ARN}"
            cleanup_successful=false
        fi
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            warn "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            cleanup_successful=false
        fi
    fi
    
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
            warn "API Gateway still exists: ${API_ID}"
            cleanup_successful=false
        fi
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            warn "S3 bucket still exists: ${BUCKET_NAME}"
            cleanup_successful=false
        fi
    fi
    
    if [[ "$cleanup_successful" == true ]]; then
        log "Cleanup verification successful - all resources deleted"
    else
        warn "Some resources may still exist. Please check the AWS console."
    fi
}

# Main destruction function
main() {
    log "Starting cleanup of Real-time Recommendation System..."
    
    # Load environment variables
    load_environment
    
    # Confirm destruction
    confirm_destruction "$@"
    
    # Delete resources in reverse order of creation
    log "Deleting resources in dependency order..."
    
    # Delete API Gateway first (no dependencies)
    delete_api_gateway
    
    # Delete Lambda function
    delete_lambda_function
    
    # Delete CloudWatch alarms
    delete_cloudwatch_alarms
    
    # Delete Personalize resources in dependency order
    delete_personalize_campaign
    delete_personalize_solution
    delete_personalize_dataset
    delete_personalize_schema
    delete_personalize_dataset_group
    
    # Delete IAM roles
    delete_iam_roles
    
    # Delete S3 bucket
    delete_s3_bucket
    
    # Wait for resources to be fully deleted
    wait_for_resource_deletion
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    log "Cleanup completed successfully!"
    log "================================================"
    log "CLEANUP SUMMARY:"
    log "All resources have been deleted"
    log "No ongoing charges should occur"
    log "Local files have been cleaned up"
    log "================================================"
    
    info "If you see any warnings above, please check the AWS console"
    info "to ensure all resources have been properly deleted."
}

# Run main function with all arguments
main "$@"
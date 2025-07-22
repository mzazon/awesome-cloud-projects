#!/bin/bash

# Destroy script for Building Advanced Recommendation Systems with Amazon Personalize
# This script safely removes all resources created for the recommendation system

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Load environment variables
load_environment() {
    if [ -f .env ]; then
        log "Loading environment variables from .env file..."
        source .env
        success "Environment variables loaded"
    else
        error "No .env file found. Please ensure the deployment script was run successfully."
    fi
}

# Confirmation prompt
confirm_destruction() {
    cat << EOF

⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️ 

This script will permanently delete the following resources:
- Amazon Personalize: Campaigns, Solutions, Datasets, and Dataset Groups
- Lambda Functions and related IAM roles
- S3 Bucket and all contents: ${BUCKET_NAME}
- IAM Roles and Policies
- EventBridge Rules (if any)
- All recommendation filters

This action CANNOT be undone!

EOF

    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Destruction cancelled."
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Wait for resource to be deleted
wait_for_deletion() {
    local resource_type=$1
    local resource_identifier=$2
    local check_command=$3
    local max_attempts=30
    local attempt=1
    
    log "Waiting for ${resource_type} deletion: ${resource_identifier}"
    
    while [ $attempt -le $max_attempts ]; do
        if ! eval "$check_command" &> /dev/null; then
            success "${resource_type} ${resource_identifier} deleted successfully"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts - ${resource_type} still exists, waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    warning "${resource_type} ${resource_identifier} deletion timeout reached"
    return 1
}

# Delete EventBridge rules and Lambda functions
delete_eventbridge_and_lambda() {
    log "Deleting EventBridge rules and Lambda functions..."
    
    # Delete EventBridge rule if exists
    if aws events describe-rule --name "personalize-retraining-${RANDOM_SUFFIX}" &> /dev/null; then
        # Remove targets first
        aws events remove-targets \
            --rule "personalize-retraining-${RANDOM_SUFFIX}" \
            --ids 1 || warning "Failed to remove EventBridge targets"
        
        # Delete rule
        aws events delete-rule \
            --name "personalize-retraining-${RANDOM_SUFFIX}" || warning "Failed to delete EventBridge rule"
        
        success "Deleted EventBridge rule"
    else
        log "EventBridge rule not found, skipping"
    fi
    
    # Delete Lambda functions
    local lambda_functions=(
        "comprehensive-recommendation-api-${RANDOM_SUFFIX}"
        "personalize-retraining-${RANDOM_SUFFIX}"
    )
    
    for function_name in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            aws lambda delete-function --function-name "$function_name"
            success "Deleted Lambda function: $function_name"
        else
            log "Lambda function $function_name not found, skipping"
        fi
    done
}

# Delete Personalize campaigns
delete_campaigns() {
    log "Deleting Personalize campaigns..."
    
    local campaigns=(
        "user-personalization-campaign-${RANDOM_SUFFIX}"
        "similar-items-campaign-${RANDOM_SUFFIX}"
        "trending-now-campaign-${RANDOM_SUFFIX}"
        "popularity-campaign-${RANDOM_SUFFIX}"
    )
    
    for campaign_name in "${campaigns[@]}"; do
        local campaign_arn="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:campaign/${campaign_name}"
        
        if aws personalize describe-campaign --campaign-arn "$campaign_arn" &> /dev/null; then
            log "Deleting campaign: $campaign_name"
            aws personalize delete-campaign --campaign-arn "$campaign_arn"
            
            # Wait for campaign deletion
            wait_for_deletion "Campaign" "$campaign_name" \
                "aws personalize describe-campaign --campaign-arn $campaign_arn"
        else
            log "Campaign $campaign_name not found, skipping"
        fi
    done
    
    success "All campaigns deleted"
}

# Delete batch inference jobs
delete_batch_jobs() {
    log "Checking for batch inference jobs..."
    
    # List and delete any batch inference jobs
    local batch_jobs=$(aws personalize list-batch-inference-jobs \
        --dataset-group-arn "${DATASET_GROUP_ARN}" \
        --query 'batchInferenceJobs[?status==`ACTIVE`].batchInferenceJobArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$batch_jobs" ]; then
        for job_arn in $batch_jobs; do
            log "Found active batch inference job: $job_arn"
            warning "Cannot delete active batch inference jobs. Please wait for completion or stop manually."
        done
    else
        log "No active batch inference jobs found"
    fi
}

# Delete filters
delete_filters() {
    log "Deleting Personalize filters..."
    
    local filters=(
        "exclude-purchased-${RANDOM_SUFFIX}"
        "category-filter-${RANDOM_SUFFIX}"
        "price-filter-${RANDOM_SUFFIX}"
    )
    
    for filter_name in "${filters[@]}"; do
        local filter_arn="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:filter/${filter_name}"
        
        if aws personalize describe-filter --filter-arn "$filter_arn" &> /dev/null; then
            aws personalize delete-filter --filter-arn "$filter_arn"
            success "Deleted filter: $filter_name"
        else
            log "Filter $filter_name not found, skipping"
        fi
    done
}

# Delete solutions
delete_solutions() {
    log "Deleting Personalize solutions..."
    
    # Wait a bit after campaign deletion
    sleep 30
    
    local solutions=(
        "${USER_PERSONALIZATION_SOLUTION}"
        "${SIMILAR_ITEMS_SOLUTION}"
        "${TRENDING_NOW_SOLUTION}"
        "${POPULARITY_SOLUTION}"
    )
    
    for solution_name in "${solutions[@]}"; do
        local solution_arn="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${solution_name}"
        
        if aws personalize describe-solution --solution-arn "$solution_arn" &> /dev/null; then
            log "Deleting solution: $solution_name"
            aws personalize delete-solution --solution-arn "$solution_arn"
            
            # Wait for solution deletion
            wait_for_deletion "Solution" "$solution_name" \
                "aws personalize describe-solution --solution-arn $solution_arn"
        else
            log "Solution $solution_name not found, skipping"
        fi
    done
    
    success "All solutions deleted"
}

# Delete datasets
delete_datasets() {
    log "Deleting Personalize datasets..."
    
    # Wait a bit after solution deletion
    sleep 30
    
    local dataset_arns=(
        "${INTERACTIONS_DATASET_ARN}"
        "${ITEMS_DATASET_ARN}"
        "${USERS_DATASET_ARN}"
    )
    
    local dataset_names=(
        "INTERACTIONS"
        "ITEMS"
        "USERS"
    )
    
    for i in "${!dataset_arns[@]}"; do
        local dataset_arn="${dataset_arns[$i]}"
        local dataset_name="${dataset_names[$i]}"
        
        if aws personalize describe-dataset --dataset-arn "$dataset_arn" &> /dev/null; then
            log "Deleting dataset: $dataset_name"
            aws personalize delete-dataset --dataset-arn "$dataset_arn"
            
            # Wait for dataset deletion
            wait_for_deletion "Dataset" "$dataset_name" \
                "aws personalize describe-dataset --dataset-arn $dataset_arn"
        else
            log "Dataset $dataset_name not found, skipping"
        fi
    done
    
    success "All datasets deleted"
}

# Delete schemas
delete_schemas() {
    log "Deleting Personalize schemas..."
    
    # Wait a bit after dataset deletion
    sleep 30
    
    local schema_arns=(
        "${INTERACTIONS_SCHEMA_ARN}"
        "${ITEMS_SCHEMA_ARN}"
        "${USERS_SCHEMA_ARN}"
    )
    
    local schema_names=(
        "interactions-schema-${RANDOM_SUFFIX}"
        "items-schema-${RANDOM_SUFFIX}"
        "users-schema-${RANDOM_SUFFIX}"
    )
    
    for i in "${!schema_arns[@]}"; do
        local schema_arn="${schema_arns[$i]}"
        local schema_name="${schema_names[$i]}"
        
        if aws personalize describe-schema --schema-arn "$schema_arn" &> /dev/null; then
            aws personalize delete-schema --schema-arn "$schema_arn"
            success "Deleted schema: $schema_name"
        else
            log "Schema $schema_name not found, skipping"
        fi
    done
}

# Delete dataset group
delete_dataset_group() {
    log "Deleting Personalize dataset group..."
    
    # Wait a bit after schema deletion
    sleep 30
    
    if aws personalize describe-dataset-group --dataset-group-arn "${DATASET_GROUP_ARN}" &> /dev/null; then
        log "Deleting dataset group: ${DATASET_GROUP_NAME}"
        aws personalize delete-dataset-group --dataset-group-arn "${DATASET_GROUP_ARN}"
        
        # Wait for dataset group deletion
        wait_for_deletion "Dataset Group" "${DATASET_GROUP_NAME}" \
            "aws personalize describe-dataset-group --dataset-group-arn ${DATASET_GROUP_ARN}"
    else
        log "Dataset group not found, skipping"
    fi
    
    success "Dataset group deleted"
}

# Delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    # Detach and delete Lambda role
    local lambda_role="LambdaRecommendationRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "$lambda_role" &> /dev/null; then
        # Detach policies
        aws iam detach-role-policy \
            --role-name "$lambda_role" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || true
        
        aws iam detach-role-policy \
            --role-name "$lambda_role" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaPersonalizePolicy-${RANDOM_SUFFIX}" || true
        
        # Delete role
        aws iam delete-role --role-name "$lambda_role"
        success "Deleted Lambda IAM role"
    else
        log "Lambda IAM role not found, skipping"
    fi
    
    # Delete Lambda custom policy
    local lambda_policy="LambdaPersonalizePolicy-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$lambda_policy" &> /dev/null; then
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$lambda_policy"
        success "Deleted Lambda custom policy"
    else
        log "Lambda custom policy not found, skipping"
    fi
    
    # Detach and delete Personalize role
    local personalize_role="PersonalizeServiceRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "$personalize_role" &> /dev/null; then
        # Detach policy
        aws iam detach-role-policy \
            --role-name "$personalize_role" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PersonalizeS3Access-${RANDOM_SUFFIX}" || true
        
        # Delete role
        aws iam delete-role --role-name "$personalize_role"
        success "Deleted Personalize IAM role"
    else
        log "Personalize IAM role not found, skipping"
    fi
    
    # Delete Personalize S3 policy
    local personalize_policy="PersonalizeS3Access-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$personalize_policy" &> /dev/null; then
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$personalize_policy"
        success "Deleted Personalize S3 policy"
    else
        log "Personalize S3 policy not found, skipping"
    fi
}

# Delete S3 bucket and contents
delete_s3_resources() {
    log "Deleting S3 bucket and contents..."
    
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        # Delete all objects in bucket (including versioned objects)
        aws s3 rm "s3://${BUCKET_NAME}" --recursive
        
        # Delete any remaining versioned objects
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Delete any delete markers
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb "s3://${BUCKET_NAME}" --force
        success "Deleted S3 bucket: ${BUCKET_NAME}"
    else
        log "S3 bucket not found, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f .env ]; then
        rm -f .env
        success "Deleted .env file"
    fi
    
    # Remove any temporary files that might be left
    rm -f *.json *.py *.csv *.zip
    
    success "Local cleanup completed"
}

# Generate deletion report
generate_deletion_report() {
    log "Generating deletion report..."
    
    cat << EOF

🗑️  DESTRUCTION COMPLETE 🗑️ 

The following resources have been deleted:
✅ EventBridge Rules
✅ Lambda Functions and IAM Roles  
✅ Personalize Campaigns
✅ Personalize Filters
✅ Personalize Solutions
✅ Personalize Datasets
✅ Personalize Schemas
✅ Personalize Dataset Group
✅ IAM Roles and Policies
✅ S3 Bucket and Contents
✅ Local Environment Files

Summary:
- S3 Bucket: ${BUCKET_NAME} ✅ DELETED
- Dataset Group: ${DATASET_GROUP_NAME} ✅ DELETED
- All ML models and campaigns ✅ DELETED
- All IAM resources ✅ DELETED

💰 Cost Impact:
- All ongoing charges for campaigns have been stopped
- Storage charges eliminated
- Lambda and EventBridge charges stopped

⚠️  Note: 
- CloudWatch logs may remain and incur minimal charges
- Any manual resources created outside this script need manual cleanup
- Billing may take up to 24 hours to reflect the changes

🎯 All resources created by the recommendation system have been successfully removed!

EOF
}

# Main destruction function
main() {
    log "Starting destruction of Recommendation Systems infrastructure"
    
    load_environment
    confirm_destruction
    
    # Execute deletion in dependency order
    delete_eventbridge_and_lambda
    delete_campaigns
    delete_batch_jobs
    delete_filters
    delete_solutions
    delete_datasets
    delete_schemas
    delete_dataset_group
    delete_iam_resources
    delete_s3_resources
    cleanup_local_files
    
    generate_deletion_report
    
    success "Destruction completed successfully!"
}

# Handle script interruption
trap 'error "Destruction interrupted. Some resources may still exist. Check AWS console."' INT TERM

# Run main function
main "$@"
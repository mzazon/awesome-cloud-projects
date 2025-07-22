#!/bin/bash

# Destroy script for Business Intelligence Dashboards with Amazon QuickSight
# This script safely removes all resources created by the deployment script

set -euo pipefail

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if deployment variables file exists
    if [[ ! -f ".deployment_vars" ]]; then
        warning "Deployment variables file not found. Some resources may need manual cleanup."
        echo "Expected file: .deployment_vars"
        echo "This file should have been created during deployment."
        echo ""
        read -p "Do you want to continue with manual resource identification? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        MANUAL_MODE=true
    else
        MANUAL_MODE=false
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment variables
load_deployment_vars() {
    if [[ "$MANUAL_MODE" == "false" ]]; then
        log "Loading deployment variables..."
        source .deployment_vars
        success "Deployment variables loaded"
        log "Will cleanup resources for suffix: ${RANDOM_SUFFIX}"
    else
        log "Manual mode: Setting up environment variables..."
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, defaulting to us-east-1"
        fi
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Prompt for resource suffix
        read -p "Enter the resource suffix (6-character identifier used during deployment): " RANDOM_SUFFIX
        if [[ -z "$RANDOM_SUFFIX" ]]; then
            error "Resource suffix is required for cleanup"
            exit 1
        fi
        
        # Set resource names based on suffix
        export S3_BUCKET_NAME="quicksight-data-${RANDOM_SUFFIX}"
        export IAM_ROLE_NAME="QuickSight-DataSource-Role-${RANDOM_SUFFIX}"
        export S3_DATA_SOURCE_ID="s3-sales-data-${RANDOM_SUFFIX}"
        export DATASET_ID="sales-dataset-${RANDOM_SUFFIX}"
        export ANALYSIS_ID="sales-analysis-${RANDOM_SUFFIX}"
        export DASHBOARD_ID="sales-dashboard-${RANDOM_SUFFIX}"
        
        success "Manual environment variables configured"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "=========================================="
    echo "   RESOURCE CLEANUP CONFIRMATION"
    echo "=========================================="
    echo ""
    warning "This will permanently delete the following resources:"
    echo ""
    echo "📊 QuickSight Resources:"
    echo "   Dashboard: ${DASHBOARD_ID:-'Unknown'}"
    echo "   Analysis: ${ANALYSIS_ID:-'Unknown'}"
    echo "   Dataset: ${DATASET_ID:-'Unknown'}"
    echo "   Data Source: ${S3_DATA_SOURCE_ID:-'Unknown'}"
    echo ""
    echo "🗂️  AWS Resources:"
    echo "   S3 Bucket: ${S3_BUCKET_NAME:-'Unknown'} (and all contents)"
    echo "   IAM Role: ${IAM_ROLE_NAME:-'Unknown'}"
    echo ""
    echo "🌍 Region: ${AWS_REGION}"
    echo "🔑 Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed with cleanup? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Double confirmation for safety
    read -p "Type 'DELETE' to confirm resource destruction: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log "Cleanup cancelled - confirmation not received"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to delete QuickSight resources
delete_quicksight_resources() {
    log "Deleting QuickSight resources..."
    
    # Delete dashboard
    if [[ -n "${DASHBOARD_ID:-}" ]]; then
        log "Deleting dashboard: ${DASHBOARD_ID}"
        if aws quicksight delete-dashboard \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --dashboard-id ${DASHBOARD_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            success "Dashboard deleted: ${DASHBOARD_ID}"
        else
            warning "Dashboard may not exist or already deleted: ${DASHBOARD_ID}"
        fi
    fi
    
    # Delete analysis
    if [[ -n "${ANALYSIS_ID:-}" ]]; then
        log "Deleting analysis: ${ANALYSIS_ID}"
        if aws quicksight delete-analysis \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --analysis-id ${ANALYSIS_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            success "Analysis deleted: ${ANALYSIS_ID}"
        else
            warning "Analysis may not exist or already deleted: ${ANALYSIS_ID}"
        fi
    fi
    
    # Delete dataset
    if [[ -n "${DATASET_ID:-}" ]]; then
        log "Deleting dataset: ${DATASET_ID}"
        if aws quicksight delete-data-set \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --data-set-id ${DATASET_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            success "Dataset deleted: ${DATASET_ID}"
        else
            warning "Dataset may not exist or already deleted: ${DATASET_ID}"
        fi
    fi
    
    # Delete data source
    if [[ -n "${S3_DATA_SOURCE_ID:-}" ]]; then
        log "Deleting data source: ${S3_DATA_SOURCE_ID}"
        if aws quicksight delete-data-source \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --data-source-id ${S3_DATA_SOURCE_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            success "Data source deleted: ${S3_DATA_SOURCE_ID}"
        else
            warning "Data source may not exist or already deleted: ${S3_DATA_SOURCE_ID}"
        fi
    fi
    
    success "QuickSight resources cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        # Check if role exists
        if aws iam get-role --role-name ${IAM_ROLE_NAME} &>/dev/null; then
            log "Detaching policies from IAM role: ${IAM_ROLE_NAME}"
            
            # List and detach all attached policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name ${IAM_ROLE_NAME} \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$attached_policies" ]]; then
                for policy in $attached_policies; do
                    log "Detaching policy: $policy"
                    aws iam detach-role-policy \
                        --role-name ${IAM_ROLE_NAME} \
                        --policy-arn $policy
                done
            fi
            
            # Delete the role
            log "Deleting IAM role: ${IAM_ROLE_NAME}"
            aws iam delete-role --role-name ${IAM_ROLE_NAME}
            success "IAM role deleted: ${IAM_ROLE_NAME}"
        else
            warning "IAM role not found or already deleted: ${IAM_ROLE_NAME}"
        fi
    fi
    
    success "IAM resources cleanup completed"
}

# Function to delete S3 resources
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if aws s3 ls s3://${S3_BUCKET_NAME} &>/dev/null; then
            log "Emptying S3 bucket: ${S3_BUCKET_NAME}"
            
            # Remove all objects and versions
            aws s3 rm s3://${S3_BUCKET_NAME} --recursive
            
            # Check for versioned objects and delete markers
            if aws s3api list-object-versions \
                --bucket ${S3_BUCKET_NAME} \
                --query 'Versions[0].Key' \
                --output text 2>/dev/null | grep -v "None" &>/dev/null; then
                
                log "Removing versioned objects..."
                aws s3api list-object-versions \
                    --bucket ${S3_BUCKET_NAME} \
                    --output json | \
                jq -r '.Versions[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
                while read -r key_version; do
                    if [[ -n "$key_version" ]]; then
                        aws s3api delete-object --bucket ${S3_BUCKET_NAME} $key_version
                    fi
                done
            fi
            
            # Check for delete markers
            if aws s3api list-object-versions \
                --bucket ${S3_BUCKET_NAME} \
                --query 'DeleteMarkers[0].Key' \
                --output text 2>/dev/null | grep -v "None" &>/dev/null; then
                
                log "Removing delete markers..."
                aws s3api list-object-versions \
                    --bucket ${S3_BUCKET_NAME} \
                    --output json | \
                jq -r '.DeleteMarkers[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
                while read -r key_version; do
                    if [[ -n "$key_version" ]]; then
                        aws s3api delete-object --bucket ${S3_BUCKET_NAME} $key_version
                    fi
                done
            fi
            
            # Delete the bucket
            log "Deleting S3 bucket: ${S3_BUCKET_NAME}"
            aws s3 rb s3://${S3_BUCKET_NAME}
            success "S3 bucket deleted: ${S3_BUCKET_NAME}"
        else
            warning "S3 bucket not found or already deleted: ${S3_BUCKET_NAME}"
        fi
    fi
    
    success "S3 resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "sales_data.csv"
        "quicksight-trust-policy.json"
        ".deployment_vars"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed local file: $file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=()
    
    # Check QuickSight dashboard
    if [[ -n "${DASHBOARD_ID:-}" ]]; then
        if aws quicksight describe-dashboard \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --dashboard-id ${DASHBOARD_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            cleanup_issues+=("Dashboard still exists: ${DASHBOARD_ID}")
        fi
    fi
    
    # Check QuickSight analysis
    if [[ -n "${ANALYSIS_ID:-}" ]]; then
        if aws quicksight describe-analysis \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --analysis-id ${ANALYSIS_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            cleanup_issues+=("Analysis still exists: ${ANALYSIS_ID}")
        fi
    fi
    
    # Check QuickSight dataset
    if [[ -n "${DATASET_ID:-}" ]]; then
        if aws quicksight describe-data-set \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --data-set-id ${DATASET_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            cleanup_issues+=("Dataset still exists: ${DATASET_ID}")
        fi
    fi
    
    # Check QuickSight data source
    if [[ -n "${S3_DATA_SOURCE_ID:-}" ]]; then
        if aws quicksight describe-data-source \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --data-source-id ${S3_DATA_SOURCE_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            cleanup_issues+=("Data source still exists: ${S3_DATA_SOURCE_ID}")
        fi
    fi
    
    # Check IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name ${IAM_ROLE_NAME} &>/dev/null; then
            cleanup_issues+=("IAM role still exists: ${IAM_ROLE_NAME}")
        fi
    fi
    
    # Check S3 bucket
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        if aws s3 ls s3://${S3_BUCKET_NAME} &>/dev/null; then
            cleanup_issues+=("S3 bucket still exists: ${S3_BUCKET_NAME}")
        fi
    fi
    
    # Report cleanup status
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        success "All resources have been successfully cleaned up"
    else
        warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            warning "  - $issue"
        done
        echo ""
        warning "You may need to manually clean up remaining resources or wait for eventual consistency"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "   CLEANUP SUMMARY"
    echo "=========================================="
    echo ""
    success "QuickSight Business Intelligence Dashboard cleanup completed!"
    echo ""
    echo "🗑️  Resources Removed:"
    echo "   ✅ QuickSight Dashboard: ${DASHBOARD_ID:-'N/A'}"
    echo "   ✅ QuickSight Analysis: ${ANALYSIS_ID:-'N/A'}"
    echo "   ✅ QuickSight Dataset: ${DATASET_ID:-'N/A'}"
    echo "   ✅ QuickSight Data Source: ${S3_DATA_SOURCE_ID:-'N/A'}"
    echo "   ✅ S3 Bucket: ${S3_BUCKET_NAME:-'N/A'}"
    echo "   ✅ IAM Role: ${IAM_ROLE_NAME:-'N/A'}"
    echo "   ✅ Local temporary files"
    echo ""
    echo "🌍 Region: ${AWS_REGION}"
    echo "🔑 Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "💰 Cost Impact:"
    echo "   All billable resources have been removed"
    echo "   No ongoing charges should occur from this deployment"
    echo ""
    echo "📝 Notes:"
    echo "   - QuickSight account remains active (requires manual cancellation if desired)"
    echo "   - Some resources may take a few minutes to fully disappear due to eventual consistency"
    echo "   - Check your AWS billing console to confirm no unexpected charges"
    echo ""
    echo "=========================================="
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    warning "Some cleanup operations encountered errors"
    echo ""
    echo "Manual cleanup may be required for:"
    echo "- QuickSight resources in the QuickSight console"
    echo "- IAM roles in the IAM console"
    echo "- S3 buckets in the S3 console"
    echo ""
    echo "Please check these services manually to ensure complete cleanup."
}

# Main execution
main() {
    log "Starting QuickSight Business Intelligence Dashboard cleanup..."
    
    check_prerequisites
    load_deployment_vars
    confirm_destruction
    
    # Perform cleanup with error handling
    set +e  # Continue on errors for cleanup
    
    delete_quicksight_resources
    delete_iam_resources
    delete_s3_resources
    cleanup_local_files
    
    set -e  # Re-enable error handling
    
    verify_cleanup
    display_summary
    
    success "Cleanup completed successfully!"
}

# Run main function
main "$@"
#!/bin/bash

# Privacy-Preserving Analytics with Clean Rooms - Cleanup Script
# This script removes all infrastructure created for privacy-preserving analytics

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Load environment variables from deployment
load_environment() {
    if [[ ! -f ".deployment_env" ]]; then
        error "Deployment environment file (.deployment_env) not found!"
        error "This file should have been created during deployment."
        error "You may need to clean up resources manually through the AWS Console."
        exit 1
    fi
    
    log "Loading deployment environment..."
    source .deployment_env
    
    # Verify required variables are set
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "CLEAN_ROOMS_NAME" "S3_BUCKET_ORG_A" "S3_BUCKET_ORG_B" "GLUE_DATABASE" "RESULTS_BUCKET")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            error "Required environment variable $var is not set!"
            exit 1
        fi
    done
    
    success "Environment loaded successfully"
}

# Confirm destructive action
confirm_destruction() {
    echo ""
    echo "=================================================="
    echo "WARNING: DESTRUCTIVE ACTION"
    echo "=================================================="
    echo "This script will permanently delete the following resources:"
    echo "- Clean Rooms Collaboration: ${CLEAN_ROOMS_NAME}"
    echo "- S3 Buckets and all data:"
    echo "  - ${S3_BUCKET_ORG_A}"
    echo "  - ${S3_BUCKET_ORG_B}"
    echo "  - ${RESULTS_BUCKET}"
    echo "- Glue Database: ${GLUE_DATABASE}"
    echo "- IAM Roles and Policies"
    echo "- QuickSight Resources"
    echo ""
    
    # Check for force flag
    if [[ "$1" == "--force" ]]; then
        warning "Force flag detected, skipping confirmation"
        return
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Confirmation received, proceeding with cleanup"
}

# Remove QuickSight resources
cleanup_quicksight() {
    log "Cleaning up QuickSight resources..."
    
    # Check if QuickSight is available
    if ! aws quicksight describe-account-settings --aws-account-id "${AWS_ACCOUNT_ID}" &>/dev/null; then
        warning "QuickSight not available or not configured, skipping cleanup"
        return
    fi
    
    # Delete QuickSight analysis if it exists
    if [[ -n "${QUICKSIGHT_ANALYSIS:-}" ]]; then
        aws quicksight delete-analysis \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --analysis-id "${QUICKSIGHT_ANALYSIS}" \
            --force-delete-without-recovery 2>/dev/null || warning "Failed to delete QuickSight analysis (may not exist)"
    fi
    
    # Delete QuickSight dataset if it exists
    local dataset_id="privacy-analytics-dataset-${CLEAN_ROOMS_NAME##*-}"
    aws quicksight delete-data-set \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id "${dataset_id}" 2>/dev/null || warning "Failed to delete QuickSight dataset (may not exist)"
    
    # Delete QuickSight data source if it exists
    local datasource_id="clean-rooms-results-${CLEAN_ROOMS_NAME##*-}"
    aws quicksight delete-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id "${datasource_id}" 2>/dev/null || warning "Failed to delete QuickSight data source (may not exist)"
    
    success "QuickSight resources cleanup completed"
}

# Remove Clean Rooms resources
cleanup_clean_rooms() {
    log "Cleaning up Clean Rooms resources..."
    
    # Get collaboration ID if available
    local collaboration_id="${COLLABORATION_ID:-}"
    
    if [[ -z "$collaboration_id" ]]; then
        # Try to find collaboration by name
        collaboration_id=$(aws cleanrooms list-collaborations \
            --query "collaborationList[?name=='${CLEAN_ROOMS_NAME}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "$collaboration_id" ]]; then
        warning "No Clean Rooms collaboration found to delete"
        return
    fi
    
    log "Found collaboration: ${collaboration_id}"
    
    # Delete configured table associations
    log "Deleting configured table associations..."
    
    # List and delete all associations for this collaboration
    local associations=$(aws cleanrooms list-configured-table-associations \
        --membership-identifier "${collaboration_id}" \
        --query "configuredTableAssociationSummaries[].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$associations" ]]; then
        for association_id in $associations; do
            aws cleanrooms delete-configured-table-association \
                --configured-table-association-identifier "${association_id}" \
                --membership-identifier "${collaboration_id}" 2>/dev/null || \
                warning "Failed to delete association ${association_id}"
        done
    fi
    
    # Wait for associations to be deleted
    sleep 10
    
    # Delete configured tables
    log "Deleting configured tables..."
    
    local configured_tables=$(aws cleanrooms list-configured-tables \
        --query "configuredTableSummaries[?contains(name, 'org-') || contains(name, 'customers')].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$configured_tables" ]]; then
        for table_id in $configured_tables; do
            aws cleanrooms delete-configured-table \
                --configured-table-identifier "${table_id}" 2>/dev/null || \
                warning "Failed to delete configured table ${table_id}"
        done
    fi
    
    # Wait for tables to be deleted
    sleep 10
    
    # Delete collaboration
    log "Deleting Clean Rooms collaboration..."
    aws cleanrooms delete-collaboration \
        --collaboration-identifier "${collaboration_id}" 2>/dev/null || \
        warning "Failed to delete collaboration"
    
    success "Clean Rooms resources cleanup completed"
}

# Remove Glue resources
cleanup_glue() {
    log "Cleaning up Glue resources..."
    
    # Delete crawlers
    local crawler_suffix="${CLEAN_ROOMS_NAME##*-}"
    local crawler_org_a="crawler-org-a-${crawler_suffix}"
    local crawler_org_b="crawler-org-b-${crawler_suffix}"
    
    for crawler in "$crawler_org_a" "$crawler_org_b"; do
        if aws glue get-crawler --name "$crawler" &>/dev/null; then
            # Stop crawler if running
            aws glue stop-crawler --name "$crawler" 2>/dev/null || true
            sleep 5
            
            # Delete crawler
            aws glue delete-crawler --name "$crawler" 2>/dev/null || \
                warning "Failed to delete crawler $crawler"
        else
            warning "Crawler $crawler not found"
        fi
    done
    
    # Delete Glue database and its tables
    if aws glue get-database --name "${GLUE_DATABASE}" &>/dev/null; then
        # First delete all tables in the database
        local tables=$(aws glue get-tables \
            --database-name "${GLUE_DATABASE}" \
            --query "TableList[].Name" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$tables" ]]; then
            for table in $tables; do
                aws glue delete-table \
                    --database-name "${GLUE_DATABASE}" \
                    --name "$table" 2>/dev/null || \
                    warning "Failed to delete table $table"
            done
        fi
        
        # Delete the database
        aws glue delete-database --name "${GLUE_DATABASE}" 2>/dev/null || \
            warning "Failed to delete Glue database"
    else
        warning "Glue database ${GLUE_DATABASE} not found"
    fi
    
    success "Glue resources cleanup completed"
}

# Remove IAM resources
cleanup_iam() {
    log "Cleaning up IAM resources..."
    
    # Detach and delete policies from Clean Rooms role
    if aws iam get-role --role-name CleanRoomsAnalyticsRole &>/dev/null; then
        log "Cleaning up CleanRoomsAnalyticsRole..."
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name CleanRoomsAnalyticsRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSCleanRoomsService 2>/dev/null || true
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name CleanRoomsAnalyticsRole \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access" 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name CleanRoomsAnalyticsRole 2>/dev/null || \
            warning "Failed to delete CleanRoomsAnalyticsRole"
    fi
    
    # Detach and delete policies from Glue role
    if aws iam get-role --role-name GlueCleanRoomsRole &>/dev/null; then
        log "Cleaning up GlueCleanRoomsRole..."
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name GlueCleanRoomsRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name GlueCleanRoomsRole \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access" 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name GlueCleanRoomsRole 2>/dev/null || \
            warning "Failed to delete GlueCleanRoomsRole"
    fi
    
    # Delete custom policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access" &>/dev/null; then
        log "Deleting custom policy CleanRoomsS3Access..."
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access" 2>/dev/null || \
            warning "Failed to delete CleanRoomsS3Access policy"
    fi
    
    success "IAM resources cleanup completed"
}

# Remove S3 resources
cleanup_s3() {
    log "Cleaning up S3 resources..."
    
    # Function to safely delete S3 bucket
    delete_s3_bucket() {
        local bucket=$1
        
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            log "Deleting S3 bucket: $bucket"
            
            # Delete all objects and versions in the bucket
            aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || warning "Failed to delete some objects in $bucket"
            
            # Delete all versions if versioning is enabled
            aws s3api delete-objects \
                --bucket "$bucket" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --output json 2>/dev/null || echo '{"Objects":[]}')" 2>/dev/null || true
            
            # Delete all delete markers
            aws s3api delete-objects \
                --bucket "$bucket" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --output json 2>/dev/null || echo '{"Objects":[]}')" 2>/dev/null || true
            
            # Delete the bucket
            aws s3 rb "s3://${bucket}" 2>/dev/null || warning "Failed to delete bucket $bucket"
        else
            warning "Bucket $bucket not found or not accessible"
        fi
    }
    
    # Delete all S3 buckets
    for bucket in "$S3_BUCKET_ORG_A" "$S3_BUCKET_ORG_B" "$RESULTS_BUCKET"; do
        delete_s3_bucket "$bucket"
    done
    
    success "S3 resources cleanup completed"
}

# Remove local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    rm -f customer_data_org_*.csv
    rm -f privacy_query.sql
    rm -f dp_config.json
    rm -f *-trust-policy.json
    rm -f *-policy.json
    
    # Remove deployment environment file
    rm -f .deployment_env
    
    success "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local errors=0
    
    # Check Clean Rooms collaboration
    local collaboration_exists=$(aws cleanrooms list-collaborations \
        --query "collaborationList[?name=='${CLEAN_ROOMS_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$collaboration_exists" ]]; then
        warning "Clean Rooms collaboration still exists: ${collaboration_exists}"
        errors=$((errors + 1))
    fi
    
    # Check S3 buckets
    for bucket in "$S3_BUCKET_ORG_A" "$S3_BUCKET_ORG_B" "$RESULTS_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            warning "S3 bucket still exists: $bucket"
            errors=$((errors + 1))
        fi
    done
    
    # Check Glue database
    if aws glue get-database --name "${GLUE_DATABASE}" &>/dev/null; then
        warning "Glue database still exists: ${GLUE_DATABASE}"
        errors=$((errors + 1))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name CleanRoomsAnalyticsRole &>/dev/null; then
        warning "IAM role still exists: CleanRoomsAnalyticsRole"
        errors=$((errors + 1))
    fi
    
    if aws iam get-role --role-name GlueCleanRoomsRole &>/dev/null; then
        warning "IAM role still exists: GlueCleanRoomsRole"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources have been successfully removed"
    else
        warning "Some resources may still exist. Please check the AWS Console for manual cleanup."
        warning "Total verification warnings: $errors"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        warning "Script interrupted or failed"
        warning "Some resources may not have been deleted"
        warning "Please check the AWS Console for manual cleanup"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main cleanup function
main() {
    log "Starting AWS Clean Rooms Privacy Analytics cleanup..."
    
    load_environment
    confirm_destruction "$@"
    
    # Cleanup in reverse order of creation
    cleanup_quicksight
    cleanup_clean_rooms
    cleanup_glue
    cleanup_iam
    cleanup_s3
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    success "🎉 Cleanup completed!"
    echo ""
    echo "=================================================="
    echo "CLEANUP SUMMARY"
    echo "=================================================="
    echo "The following resources have been removed:"
    echo "✅ Clean Rooms Collaboration: ${CLEAN_ROOMS_NAME}"
    echo "✅ S3 Buckets: ${S3_BUCKET_ORG_A}, ${S3_BUCKET_ORG_B}, ${RESULTS_BUCKET}"
    echo "✅ Glue Database: ${GLUE_DATABASE}"
    echo "✅ IAM Roles and Policies"
    echo "✅ QuickSight Resources"
    echo "✅ Local temporary files"
    echo ""
    echo "If you encounter any issues, please check the AWS Console"
    echo "for any remaining resources and delete them manually."
    echo "=================================================="
}

# Execute main function
main "$@"
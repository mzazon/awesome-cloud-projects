#!/bin/bash

# AWS Data Visualization Pipeline Cleanup Script
# Removes all resources created by the deployment script
# Based on recipe: Data Visualization Pipelines with QuickSight

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Default values
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false
PROJECT_NAME=""

# Help function
show_help() {
    cat << EOF
AWS Data Visualization Pipeline Cleanup Script

USAGE:
    ./destroy.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without making changes
    -f, --force             Force deletion without confirmation prompts
    -y, --yes               Skip all confirmation prompts (use with caution)
    -p, --project PROJECT   Specify project name to delete (required if deployment-info.txt not found)
    --region REGION         AWS region (default: current AWS CLI region)

EXAMPLES:
    ./destroy.sh                           # Interactive cleanup with confirmations
    ./destroy.sh --dry-run                 # Show what would be deleted
    ./destroy.sh --force --yes             # Force cleanup without prompts
    ./destroy.sh -p data-viz-pipeline-abc123 # Cleanup specific project

CAUTION:
    This script will permanently delete all resources created by the deployment script.
    Make sure you have backed up any important data before proceeding.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Try to load from deployment-info.txt first
    if [ -f "deployment-info.txt" ] && [ -z "$PROJECT_NAME" ]; then
        log "Found deployment-info.txt, extracting project information..."
        
        PROJECT_NAME=$(grep "Project Name:" deployment-info.txt | cut -d' ' -f3)
        AWS_REGION_FROM_FILE=$(grep "AWS Region:" deployment-info.txt | cut -d' ' -f3)
        AWS_ACCOUNT_ID_FROM_FILE=$(grep "AWS Account ID:" deployment-info.txt | cut -d' ' -f4)
        
        if [ -z "${AWS_REGION:-}" ]; then
            export AWS_REGION="$AWS_REGION_FROM_FILE"
        fi
        
        log "Loaded project: $PROJECT_NAME"
        log "Region: $AWS_REGION"
    elif [ -n "$PROJECT_NAME" ]; then
        log "Using provided project name: $PROJECT_NAME"
    else
        error "No deployment information found and no project name provided."
        error "Either ensure deployment-info.txt exists or provide project name with -p option."
        exit 1
    fi
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "No AWS region configured, using default: $AWS_REGION"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Derive resource names
    RANDOM_SUFFIX=$(echo "$PROJECT_NAME" | cut -d'-' -f4)
    export RAW_BUCKET="${PROJECT_NAME}-raw-data"
    export PROCESSED_BUCKET="${PROJECT_NAME}-processed-data"
    export ATHENA_RESULTS_BUCKET="${PROJECT_NAME}-athena-results"
    export GLUE_ROLE_NAME="GlueDataVizRole-${RANDOM_SUFFIX}"
    
    success "Deployment information loaded"
}

# Confirmation function
confirm_action() {
    local message="$1"
    
    if [ "$SKIP_CONFIRMATION" = true ] || [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local resource_name="$3"
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $resource_type deletion: $resource_name"
    
    while [ $attempt -lt $max_attempts ]; do
        if ! eval "$check_command" &> /dev/null; then
            success "$resource_type deleted: $resource_name"
            return 0
        fi
        
        log "Waiting for $resource_type deletion... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    warning "$resource_type may not have been fully deleted: $resource_name"
    return 1
}

# Delete Lambda function and S3 triggers
delete_lambda_resources() {
    log "Deleting Lambda function and S3 triggers..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would delete Lambda function: ${PROJECT_NAME}-automation"
        return 0
    fi
    
    # Remove S3 event notification first
    if aws s3api head-bucket --bucket "$RAW_BUCKET" &> /dev/null; then
        log "Removing S3 event notifications..."
        aws s3api put-bucket-notification-configuration \
            --bucket "$RAW_BUCKET" \
            --notification-configuration '{}' || warning "Failed to remove S3 notifications"
    fi
    
    # Delete Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-automation" &> /dev/null; then
        log "Deleting Lambda function: ${PROJECT_NAME}-automation"
        aws lambda delete-function --function-name "${PROJECT_NAME}-automation"
        success "Deleted Lambda function: ${PROJECT_NAME}-automation"
    else
        warning "Lambda function ${PROJECT_NAME}-automation not found"
    fi
    
    success "Lambda resources cleanup completed"
}

# Delete Athena workgroup
delete_athena_workgroup() {
    log "Deleting Athena workgroup..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would delete Athena workgroup: ${PROJECT_NAME}-workgroup"
        return 0
    fi
    
    if aws athena get-work-group --work-group "${PROJECT_NAME}-workgroup" &> /dev/null; then
        log "Deleting Athena workgroup: ${PROJECT_NAME}-workgroup"
        aws athena delete-work-group \
            --work-group "${PROJECT_NAME}-workgroup" \
            --recursive-delete-option
        success "Deleted Athena workgroup: ${PROJECT_NAME}-workgroup"
    else
        warning "Athena workgroup ${PROJECT_NAME}-workgroup not found"
    fi
    
    success "Athena resources cleanup completed"
}

# Delete Glue resources
delete_glue_resources() {
    log "Deleting Glue resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would delete Glue database and associated resources"
        return 0
    fi
    
    # Stop any running crawlers first
    for crawler in "${PROJECT_NAME}-raw-crawler" "${PROJECT_NAME}-processed-crawler"; do
        if aws glue get-crawler --name "$crawler" &> /dev/null; then
            local crawler_state=$(aws glue get-crawler --name "$crawler" --query 'Crawler.State' --output text)
            if [ "$crawler_state" = "RUNNING" ]; then
                log "Stopping crawler: $crawler"
                aws glue stop-crawler --name "$crawler" || warning "Failed to stop crawler: $crawler"
                wait_for_deletion "crawler" "aws glue get-crawler --name $crawler --query 'Crawler.State' --output text | grep -v READY" "$crawler"
            fi
        fi
    done
    
    # Stop any running ETL jobs
    if aws glue get-job --job-name "${PROJECT_NAME}-etl-job" &> /dev/null; then
        local running_jobs=$(aws glue get-job-runs --job-name "${PROJECT_NAME}-etl-job" --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text)
        if [ -n "$running_jobs" ]; then
            log "Stopping running ETL jobs..."
            for job_id in $running_jobs; do
                aws glue batch-stop-job-run --job-name "${PROJECT_NAME}-etl-job" --job-run-ids "$job_id" || warning "Failed to stop job run: $job_id"
            done
        fi
    fi
    
    # Delete ETL job
    if aws glue get-job --job-name "${PROJECT_NAME}-etl-job" &> /dev/null; then
        log "Deleting Glue ETL job: ${PROJECT_NAME}-etl-job"
        aws glue delete-job --job-name "${PROJECT_NAME}-etl-job"
        success "Deleted Glue ETL job: ${PROJECT_NAME}-etl-job"
    else
        warning "Glue ETL job ${PROJECT_NAME}-etl-job not found"
    fi
    
    # Delete crawlers
    for crawler in "${PROJECT_NAME}-raw-crawler" "${PROJECT_NAME}-processed-crawler"; do
        if aws glue get-crawler --name "$crawler" &> /dev/null; then
            log "Deleting Glue crawler: $crawler"
            aws glue delete-crawler --name "$crawler"
            success "Deleted Glue crawler: $crawler"
        else
            warning "Glue crawler $crawler not found"
        fi
    done
    
    # Delete database (this will also delete tables)
    if aws glue get-database --name "${PROJECT_NAME}-database" &> /dev/null; then
        log "Deleting Glue database: ${PROJECT_NAME}-database"
        aws glue delete-database --name "${PROJECT_NAME}-database"
        success "Deleted Glue database: ${PROJECT_NAME}-database"
    else
        warning "Glue database ${PROJECT_NAME}-database not found"
    fi
    
    success "Glue resources cleanup completed"
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would delete IAM role: $GLUE_ROLE_NAME"
        return 0
    fi
    
    if aws iam get-role --role-name "$GLUE_ROLE_NAME" &> /dev/null; then
        log "Deleting IAM role: $GLUE_ROLE_NAME"
        
        # Delete role policy
        aws iam delete-role-policy \
            --role-name "$GLUE_ROLE_NAME" \
            --policy-name S3AccessPolicy || warning "Failed to delete role policy"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$GLUE_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole || warning "Failed to detach managed policy"
        
        # Delete role
        aws iam delete-role --role-name "$GLUE_ROLE_NAME"
        success "Deleted IAM role: $GLUE_ROLE_NAME"
    else
        warning "IAM role $GLUE_ROLE_NAME not found"
    fi
    
    success "IAM roles cleanup completed"
}

# Delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would delete S3 buckets: $RAW_BUCKET, $PROCESSED_BUCKET, $ATHENA_RESULTS_BUCKET"
        return 0
    fi
    
    confirm_action "This will permanently delete all data in the S3 buckets. This action cannot be undone."
    
    for bucket in "$RAW_BUCKET" "$PROCESSED_BUCKET" "$ATHENA_RESULTS_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &> /dev/null; then
            log "Emptying and deleting S3 bucket: $bucket"
            
            # Delete all object versions and delete markers
            aws s3api list-object-versions --bucket "$bucket" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | while read key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" &> /dev/null || true
                fi
            done
            
            aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | while read key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" &> /dev/null || true
                fi
            done
            
            # Remove any remaining objects
            aws s3 rm "s3://$bucket" --recursive &> /dev/null || true
            
            # Delete bucket
            aws s3api delete-bucket --bucket "$bucket"
            success "Deleted S3 bucket: $bucket"
        else
            warning "S3 bucket $bucket not found"
        fi
    done
    
    success "S3 buckets cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would clean up local temporary files"
        return 0
    fi
    
    # Remove temporary files and directories that might exist
    local files_to_remove=(
        "sample-data"
        "glue-scripts"
        "lambda-automation"
        "athena-queries"
        "glue-trust-policy.json"
        "glue-s3-policy.json"
        "s3-notification.json"
        "automation-function.zip"
        "deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            log "Removing: $file"
            rm -rf "$file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Show resource summary
show_resource_summary() {
    log "Checking for remaining resources..."
    
    local remaining_resources=0
    
    # Check S3 buckets
    for bucket in "$RAW_BUCKET" "$PROCESSED_BUCKET" "$ATHENA_RESULTS_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &> /dev/null; then
            warning "S3 bucket still exists: $bucket"
            remaining_resources=$((remaining_resources + 1))
        fi
    done
    
    # Check Glue resources
    if aws glue get-database --name "${PROJECT_NAME}-database" &> /dev/null; then
        warning "Glue database still exists: ${PROJECT_NAME}-database"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$GLUE_ROLE_NAME" &> /dev/null; then
        warning "IAM role still exists: $GLUE_ROLE_NAME"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-automation" &> /dev/null; then
        warning "Lambda function still exists: ${PROJECT_NAME}-automation"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check Athena workgroup
    if aws athena get-work-group --work-group "${PROJECT_NAME}-workgroup" &> /dev/null; then
        warning "Athena workgroup still exists: ${PROJECT_NAME}-workgroup"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        success "All resources have been successfully deleted"
    else
        warning "$remaining_resources resources may still exist. Manual cleanup may be required."
    fi
    
    return $remaining_resources
}

# QuickSight cleanup reminder
quicksight_cleanup_reminder() {
    log "QuickSight cleanup reminder..."
    
    cat << EOF
${YELLOW}IMPORTANT: QuickSight Resources${NC}

The following QuickSight resources need to be manually deleted through the AWS Console:

1. Data Sources:
   - Navigate to QuickSight Console
   - Go to Data sources
   - Delete any data sources related to: ${PROJECT_NAME}-workgroup

2. Data Sets:
   - Navigate to QuickSight Console
   - Go to Data sets
   - Delete any datasets using the Athena data source

3. Dashboards and Analyses:
   - Navigate to QuickSight Console
   - Go to Dashboards and Analyses
   - Delete any items related to this project

${BLUE}Note:${NC} QuickSight resources cannot be deleted programmatically via CLI.

EOF
}

# Main cleanup function
main() {
    log "Starting AWS Data Visualization Pipeline cleanup..."
    
    # Show warning
    if [ "$DRY_RUN" = false ]; then
        warning "This will permanently delete all resources created by the deployment script."
        warning "Make sure you have backed up any important data before proceeding."
        echo
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    
    if [ "$DRY_RUN" = false ]; then
        confirm_action "Proceed with deleting all resources for project: $PROJECT_NAME?"
    fi
    
    delete_lambda_resources
    delete_athena_workgroup
    delete_glue_resources
    delete_iam_roles
    delete_s3_buckets
    cleanup_local_files
    
    if [ "$DRY_RUN" = true ]; then
        log "Dry run completed. No actual resources were deleted."
        exit 0
    fi
    
    # Wait a bit for eventual consistency
    log "Waiting for eventual consistency..."
    sleep 10
    
    # Show summary
    show_resource_summary
    local remaining=$?
    
    # Show QuickSight reminder
    quicksight_cleanup_reminder
    
    if [ $remaining -eq 0 ]; then
        success "🎉 AWS Data Visualization Pipeline cleanup completed successfully!"
    else
        warning "⚠️  Cleanup completed with warnings. Some resources may require manual deletion."
        exit 1
    fi
    
    cat << EOF

${GREEN}Cleanup Summary:${NC}
- All AWS resources have been deleted
- Local temporary files have been cleaned up
- QuickSight resources require manual cleanup (see above)

${BLUE}Cost Impact:${NC}
- S3 storage charges will stop accruing
- Glue and Athena charges will stop
- QuickSight charges will continue until manually cancelled

Thank you for using the AWS Data Visualization Pipeline!
EOF
}

# Run main function
main "$@"
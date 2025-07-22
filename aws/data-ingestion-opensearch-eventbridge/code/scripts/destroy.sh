#!/bin/bash

# Destroy script for Automated Data Ingestion Pipelines with OpenSearch and EventBridge
# This script safely removes all infrastructure components created by the deploy script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
}

# Function to confirm destructive actions
confirm_destroy() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete all resources created by the deployment script!"
    echo ""
    echo "The following resources will be deleted:"
    echo "  • S3 Bucket and all contents: ${BUCKET_NAME:-'(from .env file)'}"
    echo "  • OpenSearch Domain: ${OPENSEARCH_DOMAIN:-'(from .env file)'}"
    echo "  • OpenSearch Ingestion Pipeline: ${PIPELINE_NAME:-'(from .env file)'}"
    echo "  • EventBridge Scheduler schedules and group: ${SCHEDULE_GROUP_NAME:-'(from .env file)'}"
    echo "  • IAM roles and policies"
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to load environment variables
load_environment() {
    if [[ ! -f ".env" ]]; then
        error "Environment file .env not found. Cannot determine resources to delete."
        echo "Please ensure you're running this script from the same directory as deploy.sh"
        exit 1
    fi
    
    # Source the environment file
    set -a  # Export all variables
    source .env
    set +a  # Stop exporting
    
    log "Loaded environment configuration"
    log "Target AWS Region: ${AWS_REGION}"
    log "Target AWS Account: ${AWS_ACCOUNT_ID}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Verify we're in the correct account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]]; then
        error "Current AWS account ($CURRENT_ACCOUNT) doesn't match expected account ($AWS_ACCOUNT_ID)"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to delete EventBridge Scheduler resources
delete_scheduler_resources() {
    log "Deleting EventBridge Scheduler resources..."
    
    # Delete start schedule
    if aws scheduler get-schedule --name "start-ingestion-pipeline" --group-name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        aws scheduler delete-schedule \
            --name "start-ingestion-pipeline" \
            --group-name ${SCHEDULE_GROUP_NAME}
        success "Deleted start schedule"
    else
        warning "Start schedule not found or already deleted"
    fi
    
    # Delete stop schedule
    if aws scheduler get-schedule --name "stop-ingestion-pipeline" --group-name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        aws scheduler delete-schedule \
            --name "stop-ingestion-pipeline" \
            --group-name ${SCHEDULE_GROUP_NAME}
        success "Deleted stop schedule"
    else
        warning "Stop schedule not found or already deleted"
    fi
    
    # Wait a moment for schedules to be fully deleted
    sleep 5
    
    # Delete schedule group
    if aws scheduler get-schedule-group --name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        aws scheduler delete-schedule-group --name ${SCHEDULE_GROUP_NAME}
        success "Deleted schedule group: ${SCHEDULE_GROUP_NAME}"
    else
        warning "Schedule group not found or already deleted"
    fi
}

# Function to delete OpenSearch Ingestion pipeline
delete_ingestion_pipeline() {
    log "Deleting OpenSearch Ingestion pipeline..."
    
    if aws osis get-pipeline --pipeline-name ${PIPELINE_NAME} &>/dev/null; then
        # Get current pipeline status
        PIPELINE_STATUS=$(aws osis get-pipeline \
            --pipeline-name ${PIPELINE_NAME} \
            --query 'Pipeline.Status' --output text)
        
        # Stop pipeline if it's running
        if [[ "$PIPELINE_STATUS" == "ACTIVE" ]]; then
            log "Stopping pipeline before deletion..."
            aws osis stop-pipeline --pipeline-name ${PIPELINE_NAME}
            
            # Wait for pipeline to stop
            log "Waiting for pipeline to stop..."
            while true; do
                STATUS=$(aws osis get-pipeline \
                    --pipeline-name ${PIPELINE_NAME} \
                    --query 'Pipeline.Status' --output text 2>/dev/null || echo "DELETED")
                
                if [[ "$STATUS" == "STOPPED" ]]; then
                    break
                elif [[ "$STATUS" == "DELETED" ]]; then
                    warning "Pipeline was already deleted"
                    return 0
                fi
                
                sleep 10
            done
        fi
        
        # Delete the pipeline
        aws osis delete-pipeline --pipeline-name ${PIPELINE_NAME}
        success "OpenSearch Ingestion pipeline deletion initiated"
        
        # Wait for pipeline to be fully deleted
        log "Waiting for pipeline deletion to complete..."
        while aws osis get-pipeline --pipeline-name ${PIPELINE_NAME} &>/dev/null; do
            sleep 10
        done
        success "Pipeline fully deleted"
    else
        warning "Pipeline not found or already deleted"
    fi
}

# Function to delete OpenSearch domain
delete_opensearch_domain() {
    log "Deleting OpenSearch domain..."
    
    if aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null; then
        aws opensearch delete-domain --domain-name ${OPENSEARCH_DOMAIN}
        success "OpenSearch domain deletion initiated: ${OPENSEARCH_DOMAIN}"
        
        log "Note: OpenSearch domain deletion takes 10-15 minutes to complete"
        log "You can monitor progress with: aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN}"
    else
        warning "OpenSearch domain not found or already deleted"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        # Remove all objects and versions
        log "Removing all objects from bucket..."
        aws s3 rm s3://${BUCKET_NAME} --recursive
        
        # Remove any object versions (in case versioning was enabled)
        log "Removing object versions..."
        aws s3api list-object-versions \
            --bucket ${BUCKET_NAME} \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket ${BUCKET_NAME} \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
        
        # Remove delete markers
        aws s3api list-object-versions \
            --bucket ${BUCKET_NAME} \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket ${BUCKET_NAME} \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
        
        # Delete the bucket
        aws s3 rb s3://${BUCKET_NAME}
        success "S3 bucket deleted: ${BUCKET_NAME}"
    else
        warning "S3 bucket not found or already deleted"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete OpenSearch Ingestion IAM role
    if aws iam get-role --role-name ${PIPELINE_ROLE_NAME} &>/dev/null; then
        # Delete attached policies
        aws iam delete-role-policy \
            --role-name ${PIPELINE_ROLE_NAME} \
            --policy-name OpenSearchIngestionPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name ${PIPELINE_ROLE_NAME}
        success "Deleted IAM role: ${PIPELINE_ROLE_NAME}"
    else
        warning "Pipeline IAM role not found or already deleted"
    fi
    
    # Delete EventBridge Scheduler IAM role
    if aws iam get-role --role-name ${SCHEDULER_ROLE_NAME} &>/dev/null; then
        # Delete attached policies
        aws iam delete-role-policy \
            --role-name ${SCHEDULER_ROLE_NAME} \
            --policy-name SchedulerPipelinePolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name ${SCHEDULER_ROLE_NAME}
        success "Deleted IAM role: ${SCHEDULER_ROLE_NAME}"
    else
        warning "Scheduler IAM role not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".env" ]]; then
        rm -f .env
        success "Removed .env file"
    fi
    
    # Remove any temporary files that might still exist
    rm -f trust-policy.json permissions-policy.json domain-config.json
    rm -f pipeline-config.yaml scheduler-trust-policy.json scheduler-permissions-policy.json
    rm -f sample-logs.log sample-metrics.json
    
    success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        error "S3 bucket still exists: ${BUCKET_NAME}"
        ((errors++))
    else
        success "S3 bucket successfully deleted"
    fi
    
    # Check OpenSearch Ingestion pipeline
    if aws osis get-pipeline --pipeline-name ${PIPELINE_NAME} &>/dev/null; then
        error "OpenSearch Ingestion pipeline still exists: ${PIPELINE_NAME}"
        ((errors++))
    else
        success "OpenSearch Ingestion pipeline successfully deleted"
    fi
    
    # Check EventBridge schedule group
    if aws scheduler get-schedule-group --name ${SCHEDULE_GROUP_NAME} &>/dev/null; then
        error "Schedule group still exists: ${SCHEDULE_GROUP_NAME}"
        ((errors++))
    else
        success "Schedule group successfully deleted"
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name ${PIPELINE_ROLE_NAME} &>/dev/null; then
        error "Pipeline IAM role still exists: ${PIPELINE_ROLE_NAME}"
        ((errors++))
    else
        success "Pipeline IAM role successfully deleted"
    fi
    
    if aws iam get-role --role-name ${SCHEDULER_ROLE_NAME} &>/dev/null; then
        error "Scheduler IAM role still exists: ${SCHEDULER_ROLE_NAME}"
        ((errors++))
    else
        success "Scheduler IAM role successfully deleted"
    fi
    
    # OpenSearch domain check (may still be deleting)
    if aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null; then
        DOMAIN_STATUS=$(aws opensearch describe-domain \
            --domain-name ${OPENSEARCH_DOMAIN} \
            --query 'DomainStatus.Deleted' --output text 2>/dev/null || echo "false")
        
        if [[ "$DOMAIN_STATUS" == "true" ]]; then
            success "OpenSearch domain is marked for deletion"
        else
            warning "OpenSearch domain still exists (deletion in progress): ${OPENSEARCH_DOMAIN}"
        fi
    else
        success "OpenSearch domain successfully deleted"
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources successfully deleted"
    else
        warning "$errors resources may still exist - please check manually"
    fi
}

# Function to display destruction summary
display_summary() {
    echo ""
    echo "=================================="
    echo "🧹 DESTRUCTION COMPLETED"
    echo "=================================="
    echo ""
    echo "📋 Resources Destroyed:"
    echo "   ✅ S3 Bucket: ${BUCKET_NAME}"
    echo "   ✅ OpenSearch Ingestion Pipeline: ${PIPELINE_NAME}"
    echo "   ✅ EventBridge Scheduler resources: ${SCHEDULE_GROUP_NAME}"
    echo "   ✅ IAM Roles: ${PIPELINE_ROLE_NAME}, ${SCHEDULER_ROLE_NAME}"
    echo "   🕐 OpenSearch Domain: ${OPENSEARCH_DOMAIN} (deletion in progress)"
    echo ""
    echo "💡 Notes:"
    echo "   • OpenSearch domain deletion takes 10-15 minutes to complete"
    echo "   • You can verify deletion status in the AWS Console"
    echo "   • All local configuration files have been removed"
    echo ""
    echo "✨ Infrastructure cleanup completed successfully!"
    echo ""
}

# Main destruction function
main() {
    echo "🧹 Starting destruction of Automated Data Ingestion Pipelines"
    echo "============================================================="
    echo ""
    
    # Load configuration and confirm
    load_environment
    check_prerequisites
    confirm_destroy
    
    echo ""
    log "Beginning resource deletion process..."
    echo ""
    
    # Delete resources in reverse order of creation
    delete_scheduler_resources
    delete_ingestion_pipeline
    delete_opensearch_domain
    delete_s3_bucket
    delete_iam_resources
    cleanup_local_files
    verify_deletion
    display_summary
    
    success "Destruction process completed! 🎉"
}

# Error handling
handle_error() {
    error "An error occurred during destruction. Please check the output above."
    error "Some resources may still exist and require manual cleanup."
    exit 1
}

# Set error trap
trap handle_error ERR

# Run main function
main "$@"
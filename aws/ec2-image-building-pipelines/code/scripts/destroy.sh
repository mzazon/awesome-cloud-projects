#!/bin/bash

# EC2 Image Building Pipelines Cleanup Script
# This script removes all EC2 Image Builder pipeline infrastructure and associated resources

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    error "Cleanup failed. Check ${ERROR_LOG} for details."
    warn "Some resources may still exist. Review AWS console and clean up manually if needed."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove EC2 Image Builder pipeline and all associated resources.

OPTIONS:
    -h, --help              Show this help message
    -y, --yes               Skip confirmation prompts (auto-confirm)
    -r, --region REGION     AWS region (default: from deployment or current AWS CLI region)
    -f, --force             Force cleanup even if some resources fail to delete
    -k, --keep-amis         Keep created AMIs (only remove pipeline infrastructure)
    -d, --dry-run           Show what would be deleted without removing resources
    
EXAMPLES:
    $0                      # Interactive cleanup with confirmations
    $0 -y                   # Automatic cleanup without prompts
    $0 --keep-amis          # Remove pipeline but keep created AMIs
    $0 --dry-run            # Preview what would be deleted

REQUIREMENTS:
    - AWS CLI v2 configured with appropriate permissions
    - IAM permissions for EC2 Image Builder, EC2, IAM, S3, SNS
    - Deployment environment file (.deploy_env) from previous deployment

WARNING:
    This will permanently delete all EC2 Image Builder pipeline resources.
    Created AMIs will also be deleted unless --keep-amis is specified.

EOF
}

# Parse command line arguments
AUTO_CONFIRM=false
REGION=""
FORCE=false
KEEP_AMIS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-amis)
            KEEP_AMIS=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
log "Starting EC2 Image Builder pipeline cleanup"
log "Script version: 1.0"
log "Log file: $LOG_FILE"

# Load deployment environment
load_environment() {
    log "Loading deployment environment..."
    
    if [[ ! -f "${SCRIPT_DIR}/.deploy_env" ]]; then
        error "Deployment environment file not found: ${SCRIPT_DIR}/.deploy_env"
        error "This file is created during deployment and contains resource information."
        error "Without it, manual cleanup may be required."
        exit 1
    fi
    
    # Source the environment file
    source "${SCRIPT_DIR}/.deploy_env"
    
    # Override region if specified
    if [[ -n "$REGION" ]]; then
        AWS_REGION="$REGION"
    fi
    
    # Validate required variables
    if [[ -z "${AWS_REGION:-}" ]] || [[ -z "${PIPELINE_NAME:-}" ]]; then
        error "Invalid deployment environment file. Missing required variables."
        exit 1
    fi
    
    log "Loaded environment for region: $AWS_REGION"
    log "Pipeline name: $PIPELINE_NAME"
    log "S3 bucket: ${BUCKET_NAME:-Unknown}"
    
    success "Environment loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account information
    local aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    local aws_user_arn=$(aws sts get-caller-identity --query Arn --output text)
    log "AWS Account ID: $aws_account_id"
    log "AWS User/Role: $aws_user_arn"
    
    # Verify we can access the region
    if ! aws ec2 describe-regions --region "$AWS_REGION" &> /dev/null; then
        error "Cannot access AWS region: $AWS_REGION"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$AUTO_CONFIRM" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "WARNING: This will permanently delete the following resources:"
    warn "- EC2 Image Builder pipeline: $PIPELINE_NAME"
    warn "- Image recipes, components, and configurations"
    warn "- S3 bucket and contents: ${BUCKET_NAME:-Unknown}"
    warn "- IAM roles and policies: ImageBuilderInstanceRole-${ROLE_SUFFIX:-Unknown}"
    warn "- Security groups and SNS topics"
    
    if [[ "$KEEP_AMIS" == "false" ]]; then
        warn "- All created AMIs and snapshots"
    else
        log "- AMIs will be preserved (--keep-amis specified)"
    fi
    
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed"
}

# Stop and delete pipeline
delete_pipeline() {
    log "Deleting Image Builder pipeline..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete pipeline: $PIPELINE_NAME"
        return 0
    fi
    
    # Check if pipeline exists
    local pipeline_arn=""
    pipeline_arn=$(aws imagebuilder list-image-pipelines \
        --filters "name=name,values=${PIPELINE_NAME}" \
        --region "$AWS_REGION" \
        --query 'imagePipelineList[0].arn' --output text 2>/dev/null || echo "None")
    
    if [[ "$pipeline_arn" == "None" ]] || [[ -z "$pipeline_arn" ]]; then
        warn "Pipeline not found: $PIPELINE_NAME"
        return 0
    fi
    
    # Cancel any running builds
    log "Checking for running builds..."
    local running_builds=$(aws imagebuilder list-image-pipeline-images \
        --image-pipeline-arn "$pipeline_arn" \
        --region "$AWS_REGION" \
        --query 'images[?state.status==`BUILDING`].arn' --output text 2>/dev/null || echo "")
    
    if [[ -n "$running_builds" ]]; then
        warn "Found running builds. Attempting to cancel..."
        for build_arn in $running_builds; do
            aws imagebuilder cancel-image-creation \
                --image-build-version-arn "$build_arn" \
                --region "$AWS_REGION" &> /dev/null || warn "Failed to cancel build: $build_arn"
        done
        
        # Wait a moment for cancellation to take effect
        sleep 10
    fi
    
    # Delete the pipeline
    if aws imagebuilder delete-image-pipeline \
        --image-pipeline-arn "$pipeline_arn" \
        --region "$AWS_REGION" &> /dev/null; then
        success "Deleted pipeline: $PIPELINE_NAME"
    else
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to delete pipeline, continuing due to --force"
        else
            error "Failed to delete pipeline: $PIPELINE_NAME"
            return 1
        fi
    fi
}

# Delete created AMIs and snapshots
delete_amis() {
    if [[ "$KEEP_AMIS" == "true" ]]; then
        log "Skipping AMI deletion (--keep-amis specified)"
        return 0
    fi
    
    log "Deleting created AMIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would search for and delete AMIs created by pipeline"
        return 0
    fi
    
    # Find AMIs created by our pipeline
    local amis=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=tag:Recipe,Values=${RECIPE_NAME}" \
        --region "$AWS_REGION" \
        --query 'Images[].ImageId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$amis" ]]; then
        for ami_id in $amis; do
            log "Deleting AMI: $ami_id"
            
            # Get associated snapshots before deleting AMI
            local snapshots=$(aws ec2 describe-images \
                --image-ids "$ami_id" \
                --region "$AWS_REGION" \
                --query 'Images[0].BlockDeviceMappings[?Ebs].Ebs.SnapshotId' --output text 2>/dev/null || echo "")
            
            # Deregister AMI
            if aws ec2 deregister-image \
                --image-id "$ami_id" \
                --region "$AWS_REGION" &> /dev/null; then
                success "Deregistered AMI: $ami_id"
                
                # Delete associated snapshots
                for snapshot_id in $snapshots; do
                    if [[ -n "$snapshot_id" ]] && [[ "$snapshot_id" != "None" ]]; then
                        if aws ec2 delete-snapshot \
                            --snapshot-id "$snapshot_id" \
                            --region "$AWS_REGION" &> /dev/null; then
                            success "Deleted snapshot: $snapshot_id"
                        else
                            warn "Failed to delete snapshot: $snapshot_id"
                        fi
                    fi
                done
            else
                if [[ "$FORCE" == "true" ]]; then
                    warn "Failed to delete AMI: $ami_id, continuing due to --force"
                else
                    error "Failed to delete AMI: $ami_id"
                fi
            fi
        done
    else
        log "No AMIs found to delete"
    fi
}

# Delete Image Builder configurations
delete_configurations() {
    log "Deleting Image Builder configurations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete distribution config: ${DISTRIBUTION_NAME:-Unknown}"
        log "DRY RUN: Would delete infrastructure config: ${INFRASTRUCTURE_NAME:-Unknown}"
        log "DRY RUN: Would delete image recipe: ${RECIPE_NAME:-Unknown}"
        return 0
    fi
    
    # Delete distribution configuration
    if [[ -n "${DISTRIBUTION_NAME:-}" ]]; then
        local dist_arn=$(aws imagebuilder list-distribution-configurations \
            --filters "name=name,values=${DISTRIBUTION_NAME}" \
            --region "$AWS_REGION" \
            --query 'distributionConfigurationSummaryList[0].arn' --output text 2>/dev/null || echo "None")
        
        if [[ "$dist_arn" != "None" ]] && [[ -n "$dist_arn" ]]; then
            if aws imagebuilder delete-distribution-configuration \
                --distribution-configuration-arn "$dist_arn" \
                --region "$AWS_REGION" &> /dev/null; then
                success "Deleted distribution configuration"
            else
                warn "Failed to delete distribution configuration"
            fi
        fi
    fi
    
    # Delete infrastructure configuration
    if [[ -n "${INFRASTRUCTURE_NAME:-}" ]]; then
        local infra_arn=$(aws imagebuilder list-infrastructure-configurations \
            --filters "name=name,values=${INFRASTRUCTURE_NAME}" \
            --region "$AWS_REGION" \
            --query 'infrastructureConfigurationSummaryList[0].arn' --output text 2>/dev/null || echo "None")
        
        if [[ "$infra_arn" != "None" ]] && [[ -n "$infra_arn" ]]; then
            if aws imagebuilder delete-infrastructure-configuration \
                --infrastructure-configuration-arn "$infra_arn" \
                --region "$AWS_REGION" &> /dev/null; then
                success "Deleted infrastructure configuration"
            else
                warn "Failed to delete infrastructure configuration"
            fi
        fi
    fi
    
    # Delete image recipe
    if [[ -n "${RECIPE_NAME:-}" ]]; then
        local recipe_arn=$(aws imagebuilder list-image-recipes \
            --filters "name=name,values=${RECIPE_NAME}" \
            --region "$AWS_REGION" \
            --query 'imageRecipeSummaryList[0].arn' --output text 2>/dev/null || echo "None")
        
        if [[ "$recipe_arn" != "None" ]] && [[ -n "$recipe_arn" ]]; then
            if aws imagebuilder delete-image-recipe \
                --image-recipe-arn "$recipe_arn" \
                --region "$AWS_REGION" &> /dev/null; then
                success "Deleted image recipe"
            else
                warn "Failed to delete image recipe"
            fi
        fi
    fi
}

# Delete Image Builder components
delete_components() {
    log "Deleting Image Builder components..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete build component: ${COMPONENT_NAME:-Unknown}"
        log "DRY RUN: Would delete test component: ${COMPONENT_NAME:-Unknown}-test"
        return 0
    fi
    
    # Delete build component
    if [[ -n "${COMPONENT_NAME:-}" ]]; then
        local build_component_arn=$(aws imagebuilder list-components \
            --filters "name=name,values=${COMPONENT_NAME}" \
            --region "$AWS_REGION" \
            --query 'componentVersionList[0].arn' --output text 2>/dev/null || echo "None")
        
        if [[ "$build_component_arn" != "None" ]] && [[ -n "$build_component_arn" ]]; then
            if aws imagebuilder delete-component \
                --component-build-version-arn "$build_component_arn" \
                --region "$AWS_REGION" &> /dev/null; then
                success "Deleted build component"
            else
                warn "Failed to delete build component"
            fi
        fi
        
        # Delete test component
        local test_component_arn=$(aws imagebuilder list-components \
            --filters "name=name,values=${COMPONENT_NAME}-test" \
            --region "$AWS_REGION" \
            --query 'componentVersionList[0].arn' --output text 2>/dev/null || echo "None")
        
        if [[ "$test_component_arn" != "None" ]] && [[ -n "$test_component_arn" ]]; then
            if aws imagebuilder delete-component \
                --component-build-version-arn "$test_component_arn" \
                --region "$AWS_REGION" &> /dev/null; then
                success "Deleted test component"
            else
                warn "Failed to delete test component"
            fi
        fi
    fi
}

# Delete AWS resources (S3, SNS, Security Groups)
delete_aws_resources() {
    log "Deleting AWS resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete SNS topic: ${SNS_TOPIC_ARN:-Unknown}"
        log "DRY RUN: Would delete security group: ${SECURITY_GROUP_ID:-Unknown}"
        log "DRY RUN: Would delete S3 bucket: ${BUCKET_NAME:-Unknown}"
        return 0
    fi
    
    # Delete SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns delete-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --region "$AWS_REGION" &> /dev/null; then
            success "Deleted SNS topic"
        else
            warn "Failed to delete SNS topic"
        fi
    fi
    
    # Delete security group
    if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
        if aws ec2 delete-security-group \
            --group-id "$SECURITY_GROUP_ID" \
            --region "$AWS_REGION" &> /dev/null; then
            success "Deleted security group"
        else
            warn "Failed to delete security group"
        fi
    fi
    
    # Delete S3 bucket and contents
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Emptying S3 bucket: $BUCKET_NAME"
        if aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "$AWS_REGION" &> /dev/null; then
            log "Emptied S3 bucket contents"
        else
            warn "Failed to empty S3 bucket or bucket was already empty"
        fi
        
        if aws s3 rb "s3://${BUCKET_NAME}" --region "$AWS_REGION" &> /dev/null; then
            success "Deleted S3 bucket: $BUCKET_NAME"
        else
            warn "Failed to delete S3 bucket: $BUCKET_NAME"
        fi
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete IAM instance profile: ImageBuilderInstanceProfile-${ROLE_SUFFIX:-Unknown}"
        log "DRY RUN: Would delete IAM role: ImageBuilderInstanceRole-${ROLE_SUFFIX:-Unknown}"
        return 0
    fi
    
    if [[ -n "${ROLE_SUFFIX:-}" ]]; then
        local role_name="ImageBuilderInstanceRole-${ROLE_SUFFIX}"
        local profile_name="ImageBuilderInstanceProfile-${ROLE_SUFFIX}"
        
        # Remove role from instance profile
        if aws iam remove-role-from-instance-profile \
            --instance-profile-name "$profile_name" \
            --role-name "$role_name" &> /dev/null; then
            log "Removed role from instance profile"
        else
            warn "Failed to remove role from instance profile or association doesn't exist"
        fi
        
        # Delete instance profile
        if aws iam delete-instance-profile \
            --instance-profile-name "$profile_name" &> /dev/null; then
            success "Deleted instance profile: $profile_name"
        else
            warn "Failed to delete instance profile: $profile_name"
        fi
        
        # Detach policies from role
        log "Detaching policies from role..."
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder &> /dev/null || true
        
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore &> /dev/null || true
        
        # Delete IAM role
        if aws iam delete-role --role-name "$role_name" &> /dev/null; then
            success "Deleted IAM role: $role_name"
        else
            warn "Failed to delete IAM role: $role_name"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete local component files and environment"
        return 0
    fi
    
    # Remove component YAML files
    if [[ -f "${SCRIPT_DIR}/web-server-component.yaml" ]]; then
        rm -f "${SCRIPT_DIR}/web-server-component.yaml"
        log "Removed web-server-component.yaml"
    fi
    
    if [[ -f "${SCRIPT_DIR}/web-server-test.yaml" ]]; then
        rm -f "${SCRIPT_DIR}/web-server-test.yaml"
        log "Removed web-server-test.yaml"
    fi
    
    # Remove deployment environment file
    if [[ -f "${SCRIPT_DIR}/.deploy_env" ]]; then
        rm -f "${SCRIPT_DIR}/.deploy_env"
        log "Removed deployment environment file"
    fi
    
    success "Local cleanup completed"
}

# Display cleanup summary
show_summary() {
    log "Cleanup Summary"
    log "==============="
    log "Region: $AWS_REGION"
    log "Pipeline: $PIPELINE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN completed - no resources were deleted"
        log ""
        log "Resources that would be deleted:"
        log "- Image Builder pipeline and configurations"
        log "- S3 bucket and contents"
        log "- IAM roles and instance profiles"
        log "- Security groups and SNS topics"
        if [[ "$KEEP_AMIS" == "false" ]]; then
            log "- Created AMIs and snapshots"
        fi
    else
        log "Cleanup completed successfully"
        log ""
        log "Deleted resources:"
        log "- EC2 Image Builder pipeline: $PIPELINE_NAME"
        log "- Associated configurations and components"
        log "- S3 bucket: ${BUCKET_NAME:-Unknown}"
        log "- IAM resources with suffix: ${ROLE_SUFFIX:-Unknown}"
        log "- Local temporary files"
        
        if [[ "$KEEP_AMIS" == "true" ]]; then
            warn "AMIs were preserved and may incur storage costs"
            warn "Review EC2 console to manage AMI lifecycle"
        fi
        
        log ""
        log "All Image Builder pipeline resources have been removed."
        log "Check AWS console to verify cleanup if needed."
    fi
}

# Main execution
main() {
    log "Starting EC2 Image Builder cleanup"
    
    load_environment
    check_prerequisites
    confirm_cleanup
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN mode - showing what would be deleted"
    fi
    
    # Delete in reverse order of creation
    delete_amis
    delete_pipeline
    delete_configurations
    delete_components
    delete_aws_resources
    delete_iam_resources
    cleanup_local_files
    
    show_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "EC2 Image Builder cleanup completed successfully!"
    fi
}

# Run main function
main "$@"
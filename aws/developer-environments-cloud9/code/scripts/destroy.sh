#!/bin/bash

# AWS Cloud9 Developer Environments Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
handle_error() {
    error "An error occurred on line $1. Continuing cleanup..."
    # Don't exit on error during cleanup - try to clean up as much as possible
}

trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Cannot proceed with cleanup."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Try to load from state files
    if [ -f ".deployment_suffix" ]; then
        RANDOM_SUFFIX=$(cat .deployment_suffix)
        log "Loaded suffix from state file: ${RANDOM_SUFFIX}"
    else
        warning "No deployment suffix file found. Will attempt cleanup with user input."
        read -p "Enter the deployment suffix (6 characters): " RANDOM_SUFFIX
        if [ -z "$RANDOM_SUFFIX" ]; then
            error "No suffix provided. Cannot proceed with cleanup."
            exit 1
        fi
    fi
    
    # Set up environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    # Load environment ID if available
    if [ -f ".cloud9_environment_id" ]; then
        ENVIRONMENT_ID=$(cat .cloud9_environment_id)
        export ENVIRONMENT_ID
        log "Loaded Cloud9 environment ID: ${ENVIRONMENT_ID}"
    fi
    
    # Load repository name if available
    if [ -f ".codecommit_repo_name" ]; then
        REPO_NAME=$(cat .codecommit_repo_name)
        export REPO_NAME
        log "Loaded CodeCommit repository name: ${REPO_NAME}"
    fi
    
    # Load policy name if available
    if [ -f ".iam_policy_name" ]; then
        DEV_POLICY_NAME=$(cat .iam_policy_name)
        export DEV_POLICY_NAME
        log "Loaded IAM policy name: ${DEV_POLICY_NAME}"
    fi
    
    # Load dashboard name if available
    if [ -f ".cloudwatch_dashboard_name" ]; then
        DASHBOARD_NAME=$(cat .cloudwatch_dashboard_name)
        export DASHBOARD_NAME
        log "Loaded CloudWatch dashboard name: ${DASHBOARD_NAME}"
    fi
    
    # Set up resource names based on suffix
    export CLOUD9_ENV_NAME="dev-environment-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="Cloud9-${RANDOM_SUFFIX}-Role"
    
    if [ -z "${REPO_NAME:-}" ]; then
        export REPO_NAME="team-development-repo-${RANDOM_SUFFIX}"
    fi
    
    if [ -z "${DEV_POLICY_NAME:-}" ]; then
        export DEV_POLICY_NAME="Cloud9-Development-Policy-${RANDOM_SUFFIX}"
    fi
    
    if [ -z "${DASHBOARD_NAME:-}" ]; then
        export DASHBOARD_NAME="Cloud9-${RANDOM_SUFFIX}-Dashboard"
    fi
    
    success "Deployment state loaded"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    warning "This will permanently delete the following resources:"
    echo "  - Cloud9 Environment: ${CLOUD9_ENV_NAME}"
    echo "  - CodeCommit Repository: ${REPO_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo "  - IAM Policy: ${DEV_POLICY_NAME}"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  - Local project files and templates"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to delete Cloud9 environment
delete_cloud9_environment() {
    log "Deleting Cloud9 environment..."
    
    # If we have the environment ID from state file
    if [ -n "${ENVIRONMENT_ID:-}" ]; then
        if aws cloud9 describe-environments --environment-ids "${ENVIRONMENT_ID}" &> /dev/null; then
            aws cloud9 delete-environment --environment-id "${ENVIRONMENT_ID}" || true
            success "Cloud9 environment ${ENVIRONMENT_ID} deletion initiated"
            
            # Wait for deletion to complete
            log "Waiting for environment deletion to complete..."
            local max_attempts=24  # 12 minutes total
            local attempt=1
            
            while [ $attempt -le $max_attempts ]; do
                if ! aws cloud9 describe-environments --environment-ids "${ENVIRONMENT_ID}" &> /dev/null; then
                    success "Cloud9 environment deleted successfully"
                    break
                fi
                log "Environment still exists - waiting... (attempt $attempt/$max_attempts)"
                sleep 30
                ((attempt++))
            done
        else
            warning "Cloud9 environment ${ENVIRONMENT_ID} not found"
        fi
    else
        # Try to find environment by name
        log "Searching for Cloud9 environment by name: ${CLOUD9_ENV_NAME}"
        local env_id=$(aws cloud9 list-environments --query "environmentIds" --output text | tr '\t' '\n' | while read id; do
            if [ -n "$id" ]; then
                local env_name=$(aws cloud9 describe-environments --environment-ids "$id" --query 'environments[0].name' --output text 2>/dev/null || echo "")
                if [ "$env_name" = "$CLOUD9_ENV_NAME" ]; then
                    echo "$id"
                    break
                fi
            fi
        done)
        
        if [ -n "$env_id" ]; then
            aws cloud9 delete-environment --environment-id "$env_id" || true
            success "Cloud9 environment deletion initiated for: ${env_id}"
        else
            warning "Cloud9 environment not found: ${CLOUD9_ENV_NAME}"
        fi
    fi
}

# Function to delete CodeCommit repository
delete_codecommit_repository() {
    log "Deleting CodeCommit repository..."
    
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        aws codecommit delete-repository --repository-name "${REPO_NAME}" || true
        success "CodeCommit repository deleted: ${REPO_NAME}"
    else
        warning "CodeCommit repository not found: ${REPO_NAME}"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete custom IAM policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${DEV_POLICY_NAME}"
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        # First detach from any entities (if attached)
        local attached_roles=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null || echo "")
        if [ -n "$attached_roles" ]; then
            for role in $attached_roles; do
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" || true
                log "Detached policy from role: $role"
            done
        fi
        
        aws iam delete-policy --policy-arn "$policy_arn" || true
        success "IAM policy deleted: ${DEV_POLICY_NAME}"
    else
        warning "IAM policy not found: ${DEV_POLICY_NAME}"
    fi
    
    # Delete IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCloud9EnvironmentMember || true
        
        # Delete the role
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" || true
        success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        warning "IAM role not found: ${IAM_ROLE_NAME}"
    fi
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &> /dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "${DASHBOARD_NAME}" || true
        success "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
    else
        warning "CloudWatch dashboard not found: ${DASHBOARD_NAME}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove state files
    local files_to_remove=(
        ".cloud9_environment_id"
        ".deployment_suffix"
        ".codecommit_repo_name"
        ".iam_policy_name"
        ".cloudwatch_dashboard_name"
        "cloud9-setup.sh"
        "environment-config.sh"
        "cloud9-dev-policy.json"
        "dashboard-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed file: $file"
        fi
    done
    
    # Remove project templates directory
    if [ -d "project-templates" ]; then
        rm -rf "project-templates"
        log "Removed directory: project-templates"
    fi
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "The following resources have been removed:"
    echo "  ✓ Cloud9 Environment: ${CLOUD9_ENV_NAME}"
    echo "  ✓ CodeCommit Repository: ${REPO_NAME}"
    echo "  ✓ IAM Role: ${IAM_ROLE_NAME}"
    echo "  ✓ IAM Policy: ${DEV_POLICY_NAME}"
    echo "  ✓ CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  ✓ Local project files and state files"
    echo
    echo "Note: It may take a few minutes for all resources to be fully removed from AWS."
    echo "You can verify the cleanup by checking the AWS Console."
    echo
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    warning "Some resources may not have been deleted due to errors."
    echo "You may need to manually clean up the following resources in the AWS Console:"
    echo "  - Cloud9 Environment: ${CLOUD9_ENV_NAME}"
    echo "  - CodeCommit Repository: ${REPO_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo "  - IAM Policy: ${DEV_POLICY_NAME}"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo
}

# Main cleanup function
main() {
    log "Starting AWS Cloud9 Developer Environment cleanup..."
    
    check_prerequisites
    load_deployment_state
    confirm_deletion
    
    # Perform cleanup operations (continue on errors)
    delete_cloud9_environment || warning "Failed to delete Cloud9 environment"
    delete_codecommit_repository || warning "Failed to delete CodeCommit repository"
    delete_iam_resources || warning "Failed to delete IAM resources"
    delete_cloudwatch_dashboard || warning "Failed to delete CloudWatch dashboard"
    cleanup_local_files || warning "Failed to clean up local files"
    
    display_cleanup_summary
    success "Cleanup process completed!"
}

# Handle dry run mode
if [ "${1:-}" = "--dry-run" ]; then
    log "Running in dry-run mode - no resources will be deleted"
    check_prerequisites
    load_deployment_state
    
    echo
    echo "=== DRY RUN - RESOURCES THAT WOULD BE DELETED ==="
    echo "Cloud9 Environment: ${CLOUD9_ENV_NAME} (ID: ${ENVIRONMENT_ID:-unknown})"
    echo "CodeCommit Repository: ${REPO_NAME}"
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo "IAM Policy: ${DEV_POLICY_NAME}"
    echo "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "Local files and project templates"
    echo
    echo "To perform actual cleanup, run: ./destroy.sh"
    exit 0
fi

# Handle force mode (skip confirmation)
if [ "${1:-}" = "--force" ]; then
    log "Running in force mode - skipping confirmation prompts"
    check_prerequisites
    load_deployment_state
    
    # Perform cleanup operations
    delete_cloud9_environment || warning "Failed to delete Cloud9 environment"
    delete_codecommit_repository || warning "Failed to delete CodeCommit repository"
    delete_iam_resources || warning "Failed to delete IAM resources"
    delete_cloudwatch_dashboard || warning "Failed to delete CloudWatch dashboard"
    cleanup_local_files || warning "Failed to clean up local files"
    
    display_cleanup_summary
    success "Force cleanup completed!"
    exit 0
fi

# Show help
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "AWS Cloud9 Developer Environment Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmation prompts and delete all resources"
    echo "  --help, -h   Show this help message"
    echo
    echo "Examples:"
    echo "  $0                # Interactive cleanup with confirmation"
    echo "  $0 --dry-run      # Preview what would be deleted"
    echo "  $0 --force        # Delete everything without prompts"
    echo
    exit 0
fi

# Run main function
main "$@"
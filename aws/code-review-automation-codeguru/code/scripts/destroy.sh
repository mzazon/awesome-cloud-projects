#!/bin/bash

# AWS CodeGuru Code Review Automation - Cleanup Script
# This script removes all resources created by the CodeGuru automation deployment including:
# - CodeGuru Reviewer repository association
# - CodeGuru Profiler group
# - CodeCommit repository
# - IAM roles and policies
# - Local temporary files

set -e

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env" ]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Manual cleanup may be required."
        echo "Please provide the following information for cleanup:"
        
        read -p "AWS Region (default: us-east-1): " AWS_REGION
        AWS_REGION=${AWS_REGION:-us-east-1}
        
        read -p "Repository Name: " REPO_NAME
        read -p "Profiler Group Name: " PROFILER_GROUP_NAME
        read -p "IAM Role Name: " IAM_ROLE_NAME
        
        if [ -z "$REPO_NAME" ] || [ -z "$PROFILER_GROUP_NAME" ] || [ -z "$IAM_ROLE_NAME" ]; then
            error "Required information not provided. Cannot proceed with cleanup."
        fi
        
        export AWS_REGION REPO_NAME PROFILER_GROUP_NAME IAM_ROLE_NAME
    fi
    
    # Set account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
}

# Function to confirm deletion
confirm_deletion() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources will be deleted:"
    echo "- Repository: ${REPO_NAME}"
    echo "- Profiler Group: ${PROFILER_GROUP_NAME}"
    echo "- IAM Role: ${IAM_ROLE_NAME}"
    echo "- All associated CodeGuru associations and reviews"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to delete all resources? (type 'YES' to confirm): " CONFIRMATION
    
    if [ "$CONFIRMATION" != "YES" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to remove CodeGuru Reviewer association
remove_codeguru_association() {
    log "Removing CodeGuru Reviewer association..."
    
    # Find existing associations for the repository
    ASSOCIATIONS=$(aws codeguru-reviewer list-repository-associations \
        --query "RepositoryAssociationSummaries[?Repository.Name=='${REPO_NAME}'].AssociationArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ASSOCIATIONS" ]; then
        for association_arn in $ASSOCIATIONS; do
            log "Disassociating repository: $association_arn"
            
            aws codeguru-reviewer disassociate-repository \
                --association-arn "$association_arn" || warning "Failed to disassociate $association_arn"
            
            # Wait for disassociation to complete
            log "Waiting for disassociation to complete..."
            local max_attempts=20
            local attempt=1
            
            while [ $attempt -le $max_attempts ]; do
                local status=$(aws codeguru-reviewer describe-repository-association \
                    --association-arn "$association_arn" \
                    --query 'RepositoryAssociation.State' \
                    --output text 2>/dev/null || echo "Disassociated")
                
                if [ "$status" = "Disassociated" ] || [ "$status" = "Failed" ]; then
                    success "Repository disassociation completed"
                    break
                else
                    log "Disassociation status: $status (attempt $attempt/$max_attempts)"
                    sleep 10
                    ((attempt++))
                fi
            done
            
            if [ $attempt -gt $max_attempts ]; then
                warning "Disassociation timed out for $association_arn"
            fi
        done
    else
        warning "No CodeGuru Reviewer associations found for repository ${REPO_NAME}"
    fi
}

# Function to delete CodeGuru Profiler group
delete_profiler_group() {
    log "Deleting CodeGuru Profiler group..."
    
    # Check if profiler group exists
    if aws codeguru-profiler describe-profiling-group \
        --profiling-group-name ${PROFILER_GROUP_NAME} &> /dev/null; then
        
        aws codeguru-profiler delete-profiling-group \
            --profiling-group-name ${PROFILER_GROUP_NAME}
        
        success "Profiler group deleted: ${PROFILER_GROUP_NAME}"
    else
        warning "Profiler group ${PROFILER_GROUP_NAME} not found or already deleted"
    fi
}

# Function to delete CodeCommit repository
delete_codecommit_repo() {
    log "Deleting CodeCommit repository..."
    
    # Check if repository exists
    if aws codecommit get-repository --repository-name ${REPO_NAME} &> /dev/null; then
        
        # Confirm repository deletion
        warning "Deleting repository will permanently remove all code and history"
        read -p "Delete repository ${REPO_NAME}? (y/N): " DELETE_REPO
        
        if [[ "$DELETE_REPO" =~ ^[Yy]$ ]]; then
            aws codecommit delete-repository \
                --repository-name ${REPO_NAME}
            
            success "CodeCommit repository deleted: ${REPO_NAME}"
        else
            warning "Repository deletion skipped by user"
        fi
    else
        warning "Repository ${REPO_NAME} not found or already deleted"
    fi
}

# Function to clean up IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Check if IAM role exists
    if aws iam get-role --role-name ${IAM_ROLE_NAME} &> /dev/null; then
        
        # Detach managed policies
        log "Detaching policies from IAM role..."
        
        # List attached policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name ${IAM_ROLE_NAME} \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy_arn in $ATTACHED_POLICIES; do
                log "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name ${IAM_ROLE_NAME} \
                    --policy-arn "$policy_arn"
            done
        fi
        
        # List and delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name ${IAM_ROLE_NAME} \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$INLINE_POLICIES" ]; then
            for policy_name in $INLINE_POLICIES; do
                log "Deleting inline policy: $policy_name"
                aws iam delete-role-policy \
                    --role-name ${IAM_ROLE_NAME} \
                    --policy-name "$policy_name"
            done
        fi
        
        # Delete the IAM role
        aws iam delete-role \
            --role-name ${IAM_ROLE_NAME}
        
        success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        warning "IAM role ${IAM_ROLE_NAME} not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f .env
        success "Environment file removed"
    fi
    
    # Remove temporary repository directory if it exists
    if [ -n "$RANDOM_SUFFIX" ]; then
        local temp_dir="/tmp/codeguru-demo-${RANDOM_SUFFIX}"
        if [ -d "$temp_dir" ]; then
            rm -rf "$temp_dir"
            success "Temporary repository directory removed"
        fi
    fi
    
    # Remove any temporary JSON files
    rm -f trust-policy.json
    
    success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check repository
    if aws codecommit get-repository --repository-name ${REPO_NAME} &> /dev/null; then
        warning "Repository ${REPO_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check profiler group
    if aws codeguru-profiler describe-profiling-group \
        --profiling-group-name ${PROFILER_GROUP_NAME} &> /dev/null; then
        warning "Profiler group ${PROFILER_GROUP_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name ${IAM_ROLE_NAME} &> /dev/null; then
        warning "IAM role ${IAM_ROLE_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check CodeGuru associations
    REMAINING_ASSOCIATIONS=$(aws codeguru-reviewer list-repository-associations \
        --query "RepositoryAssociationSummaries[?Repository.Name=='${REPO_NAME}']" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_ASSOCIATIONS" ]; then
        warning "CodeGuru associations still exist for repository ${REPO_NAME}"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        warning "Some resources may still exist. Manual cleanup may be required."
        echo ""
        echo "Resources that may need manual cleanup:"
        echo "- CodeGuru code reviews (these cannot be deleted and will age out)"
        echo "- CloudWatch logs (if any were created)"
        echo "- Any custom IAM policies created outside this script"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been processed for deletion:"
    echo "✓ CodeGuru Reviewer associations"
    echo "✓ CodeGuru Profiler group: ${PROFILER_GROUP_NAME}"
    echo "✓ CodeCommit repository: ${REPO_NAME}"
    echo "✓ IAM role: ${IAM_ROLE_NAME}"
    echo "✓ Local temporary files"
    echo ""
    echo "Note: CodeGuru code reviews cannot be deleted and will age out automatically."
    echo "Any CloudWatch logs created during the demo may incur minimal charges."
    echo ""
    success "CodeGuru automation cleanup completed!"
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        warning "Cleanup script interrupted. Some resources may remain."
        echo "You can run this script again to complete the cleanup."
    fi
    exit $exit_code
}

# Set trap for script interruption
trap cleanup_on_exit EXIT

# Main cleanup function
main() {
    log "Starting AWS CodeGuru Code Review Automation cleanup..."
    
    check_prerequisites
    load_environment
    confirm_deletion
    remove_codeguru_association
    delete_profiler_group
    delete_codecommit_repo
    cleanup_iam_resources
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Help function
show_help() {
    echo "AWS CodeGuru Code Review Automation - Cleanup Script"
    echo ""
    echo "This script removes all resources created by the CodeGuru automation deployment."
    echo ""
    echo "Usage:"
    echo "  $0                    # Run interactive cleanup"
    echo "  $0 --help           # Show this help message"
    echo "  $0 --force          # Skip confirmation prompts (use with caution)"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI installed and configured"
    echo "  - Appropriate permissions to delete resources"
    echo "  - .env file from deployment (or manual input of resource names)"
    echo ""
    echo "Note: This script will permanently delete resources. Make sure you have"
    echo "      backed up any important code or configurations before running."
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --force)
        FORCE_CLEANUP=true
        ;;
    "")
        FORCE_CLEANUP=false
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

# Override confirmation function if force flag is set
if [ "$FORCE_CLEANUP" = true ]; then
    confirm_deletion() {
        warning "Force cleanup enabled - skipping confirmation"
        log "Proceeding with resource deletion..."
    }
fi

# Run main function
main "$@"
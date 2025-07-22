#!/bin/bash

# AWS Proton and CDK Infrastructure Automation Cleanup Script
# This script cleans up all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Global variables to track resources
ENVIRONMENT_NAME=""
ENV_TEMPLATE_NAME=""
SVC_TEMPLATE_NAME=""
PROTON_ROLE_NAME=""
PROJECT_NAME=""
AWS_ACCOUNT_ID=""
BUCKET_NAME=""

# Function to get user confirmation
confirm() {
    local prompt="$1"
    read -p "$prompt (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Function to detect existing resources
detect_resources() {
    log "Detecting existing resources..."
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to get AWS account ID. Please check your AWS credentials."
        exit 1
    fi
    
    # Try to find resources from environment variables or user input
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        log "Using PROJECT_NAME from environment: $PROJECT_NAME"
    else
        echo "Please provide the project name used during deployment:"
        read -p "Project name (proton-demo-XXXXXX): " PROJECT_NAME
        
        if [[ -z "$PROJECT_NAME" ]]; then
            error "Project name is required for cleanup"
            exit 1
        fi
    fi
    
    # Set derived names
    RANDOM_STRING=$(echo "$PROJECT_NAME" | sed 's/proton-demo-//')
    ENV_TEMPLATE_NAME="web-app-env-${RANDOM_STRING}"
    SVC_TEMPLATE_NAME="web-app-svc-${RANDOM_STRING}"
    PROTON_ROLE_NAME="ProtonServiceRole-${RANDOM_STRING}"
    ENVIRONMENT_NAME="dev-env-${RANDOM_STRING}"
    BUCKET_NAME="${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID}"
    
    log "Resource names detected:"
    log "  Environment Template: $ENV_TEMPLATE_NAME"
    log "  Service Template: $SVC_TEMPLATE_NAME"
    log "  Environment Name: $ENVIRONMENT_NAME"
    log "  Proton Role: $PROTON_ROLE_NAME"
    log "  S3 Bucket: $BUCKET_NAME"
    
    success "Resource detection completed"
}

# Function to list all resources to be deleted
list_resources() {
    log "Scanning for resources to delete..."
    
    echo ""
    echo "The following resources will be deleted:"
    echo ""
    
    # Check for environments
    if aws proton get-environment --name "$ENVIRONMENT_NAME" &> /dev/null; then
        echo "  ✓ Proton Environment: $ENVIRONMENT_NAME"
    else
        echo "  - Proton Environment: $ENVIRONMENT_NAME (not found)"
    fi
    
    # Check for environment templates
    if aws proton get-environment-template --name "$ENV_TEMPLATE_NAME" &> /dev/null; then
        echo "  ✓ Environment Template: $ENV_TEMPLATE_NAME"
        
        # List template versions
        local versions=$(aws proton list-environment-template-versions \
            --template-name "$ENV_TEMPLATE_NAME" \
            --query 'templateVersions[*].{Version:majorVersion+"."+minorVersion}' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$versions" ]]; then
            echo "    Template Versions: $versions"
        fi
    else
        echo "  - Environment Template: $ENV_TEMPLATE_NAME (not found)"
    fi
    
    # Check for service templates
    if aws proton get-service-template --name "$SVC_TEMPLATE_NAME" &> /dev/null; then
        echo "  ✓ Service Template: $SVC_TEMPLATE_NAME"
    else
        echo "  - Service Template: $SVC_TEMPLATE_NAME (not found)"
    fi
    
    # Check for IAM role
    if aws iam get-role --role-name "$PROTON_ROLE_NAME" &> /dev/null; then
        echo "  ✓ IAM Role: $PROTON_ROLE_NAME"
    else
        echo "  - IAM Role: $PROTON_ROLE_NAME (not found)"
    fi
    
    # Check for S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &> /dev/null; then
        echo "  ✓ S3 Bucket: $BUCKET_NAME"
    else
        echo "  - S3 Bucket: $BUCKET_NAME (not found)"
    fi
    
    # Check for local project directory
    if [[ -d "$PROJECT_NAME" ]]; then
        echo "  ✓ Local Directory: $PROJECT_NAME"
    else
        echo "  - Local Directory: $PROJECT_NAME (not found)"
    fi
    
    # Check for temporary files
    local temp_files=("proton-service-role-trust-policy.json" "environment-spec.yaml")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  ✓ Temporary File: $file"
        fi
    done
    
    echo ""
}

# Function to delete environments
delete_environments() {
    log "Deleting Proton environments..."
    
    # Check if environment exists
    if aws proton get-environment --name "$ENVIRONMENT_NAME" &> /dev/null; then
        local env_status=$(aws proton get-environment --name "$ENVIRONMENT_NAME" --query 'environment.deploymentStatus' --output text)
        
        if [[ "$env_status" == "DELETE_IN_PROGRESS" ]]; then
            warning "Environment deletion already in progress"
        else
            log "Deleting environment: $ENVIRONMENT_NAME"
            aws proton delete-environment --name "$ENVIRONMENT_NAME" || {
                error "Failed to delete environment. It may have dependent services."
                
                # List services in the environment
                local services=$(aws proton list-services --query 'services[?environmentName==`'$ENVIRONMENT_NAME'`].name' --output text 2>/dev/null || echo "")
                
                if [[ -n "$services" ]]; then
                    warning "Environment has dependent services: $services"
                    warning "Please delete services first, then re-run this script"
                    return 1
                fi
            }
            
            # Wait for environment deletion with timeout
            log "Waiting for environment deletion to complete..."
            local timeout=1800  # 30 minutes
            local elapsed=0
            local interval=30
            
            while [[ $elapsed -lt $timeout ]]; do
                if ! aws proton get-environment --name "$ENVIRONMENT_NAME" &> /dev/null; then
                    success "Environment deleted successfully"
                    break
                fi
                
                local status=$(aws proton get-environment --name "$ENVIRONMENT_NAME" --query 'environment.deploymentStatus' --output text 2>/dev/null || echo "DELETED")
                
                if [[ "$status" == "DELETE_FAILED" ]]; then
                    error "Environment deletion failed"
                    return 1
                elif [[ "$status" == "DELETED" || "$status" == "" ]]; then
                    success "Environment deleted successfully"
                    break
                else
                    log "Environment deletion status: $status (elapsed: ${elapsed}s)"
                    sleep $interval
                    elapsed=$((elapsed + interval))
                fi
            done
            
            if [[ $elapsed -ge $timeout ]]; then
                warning "Environment deletion timed out after ${timeout}s"
            fi
        fi
    else
        log "Environment $ENVIRONMENT_NAME not found, skipping deletion"
    fi
}

# Function to delete service templates
delete_service_templates() {
    log "Deleting service templates..."
    
    if aws proton get-service-template --name "$SVC_TEMPLATE_NAME" &> /dev/null; then
        # List and delete all template versions
        local versions=$(aws proton list-service-template-versions \
            --template-name "$SVC_TEMPLATE_NAME" \
            --query 'templateVersions[*].{Major:majorVersion,Minor:minorVersion}' \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$versions" != "[]" ]]; then
            log "Deleting service template versions..."
            echo "$versions" | jq -r '.[] | "\(.Major) \(.Minor)"' | while read -r major minor; do
                log "Deleting service template version $major.$minor"
                aws proton delete-service-template-version \
                    --template-name "$SVC_TEMPLATE_NAME" \
                    --major-version "$major" \
                    --minor-version "$minor" || warning "Failed to delete service template version $major.$minor"
            done
        fi
        
        # Delete the service template
        log "Deleting service template: $SVC_TEMPLATE_NAME"
        aws proton delete-service-template --name "$SVC_TEMPLATE_NAME" || warning "Failed to delete service template"
        
        success "Service template deleted"
    else
        log "Service template $SVC_TEMPLATE_NAME not found, skipping deletion"
    fi
}

# Function to delete environment templates
delete_environment_templates() {
    log "Deleting environment templates..."
    
    if aws proton get-environment-template --name "$ENV_TEMPLATE_NAME" &> /dev/null; then
        # List and delete all template versions
        local versions=$(aws proton list-environment-template-versions \
            --template-name "$ENV_TEMPLATE_NAME" \
            --query 'templateVersions[*].{Major:majorVersion,Minor:minorVersion}' \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$versions" != "[]" ]]; then
            log "Deleting environment template versions..."
            echo "$versions" | jq -r '.[] | "\(.Major) \(.Minor)"' | while read -r major minor; do
                log "Deleting environment template version $major.$minor"
                aws proton delete-environment-template-version \
                    --template-name "$ENV_TEMPLATE_NAME" \
                    --major-version "$major" \
                    --minor-version "$minor" || warning "Failed to delete environment template version $major.$minor"
            done
        fi
        
        # Delete the environment template
        log "Deleting environment template: $ENV_TEMPLATE_NAME"
        aws proton delete-environment-template --name "$ENV_TEMPLATE_NAME" || warning "Failed to delete environment template"
        
        success "Environment template deleted"
    else
        log "Environment template $ENV_TEMPLATE_NAME not found, skipping deletion"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &> /dev/null; then
        log "Emptying S3 bucket: $BUCKET_NAME"
        aws s3 rm "s3://$BUCKET_NAME" --recursive || warning "Failed to empty S3 bucket"
        
        log "Deleting S3 bucket: $BUCKET_NAME"
        aws s3 rb "s3://$BUCKET_NAME" || warning "Failed to delete S3 bucket"
        
        success "S3 bucket deleted"
    else
        log "S3 bucket $BUCKET_NAME not found, skipping deletion"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if aws iam get-role --role-name "$PROTON_ROLE_NAME" &> /dev/null; then
        # Detach all policies
        log "Detaching policies from role: $PROTON_ROLE_NAME"
        
        # List and detach managed policies
        local managed_policies=$(aws iam list-attached-role-policies \
            --role-name "$PROTON_ROLE_NAME" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$managed_policies" ]]; then
            for policy_arn in $managed_policies; do
                log "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name "$PROTON_ROLE_NAME" \
                    --policy-arn "$policy_arn" || warning "Failed to detach policy $policy_arn"
            done
        fi
        
        # List and delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$PROTON_ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$inline_policies" ]]; then
            for policy_name in $inline_policies; do
                log "Deleting inline policy: $policy_name"
                aws iam delete-role-policy \
                    --role-name "$PROTON_ROLE_NAME" \
                    --policy-name "$policy_name" || warning "Failed to delete inline policy $policy_name"
            done
        fi
        
        # Delete the role
        log "Deleting IAM role: $PROTON_ROLE_NAME"
        aws iam delete-role --role-name "$PROTON_ROLE_NAME" || warning "Failed to delete IAM role"
        
        success "IAM role deleted"
    else
        log "IAM role $PROTON_ROLE_NAME not found, skipping deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove project directory
    if [[ -d "$PROJECT_NAME" ]]; then
        log "Removing project directory: $PROJECT_NAME"
        rm -rf "$PROJECT_NAME" || warning "Failed to remove project directory"
        success "Project directory removed"
    fi
    
    # Remove temporary files
    local temp_files=("proton-service-role-trust-policy.json" "environment-spec.yaml")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing temporary file: $file"
            rm -f "$file" || warning "Failed to remove $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check environment
    if aws proton get-environment --name "$ENVIRONMENT_NAME" &> /dev/null; then
        warning "Environment still exists: $ENVIRONMENT_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check environment template
    if aws proton get-environment-template --name "$ENV_TEMPLATE_NAME" &> /dev/null; then
        warning "Environment template still exists: $ENV_TEMPLATE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check service template
    if aws proton get-service-template --name "$SVC_TEMPLATE_NAME" &> /dev/null; then
        warning "Service template still exists: $SVC_TEMPLATE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$PROTON_ROLE_NAME" &> /dev/null; then
        warning "IAM role still exists: $PROTON_ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &> /dev/null; then
        warning "S3 bucket still exists: $BUCKET_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check local directory
    if [[ -d "$PROJECT_NAME" ]]; then
        warning "Local directory still exists: $PROJECT_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources have been successfully cleaned up"
    else
        warning "Cleanup completed with $cleanup_issues issues. You may need to manually clean up some resources."
    fi
}

# Main cleanup function
main() {
    log "Starting AWS Proton and CDK Infrastructure Automation cleanup..."
    
    # Check AWS CLI is available
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Detect resources
    detect_resources
    
    # List resources to be deleted
    list_resources
    
    # Get user confirmation
    echo ""
    warning "This operation will permanently delete all the resources listed above."
    confirm "Are you sure you want to proceed with the cleanup?"
    
    # Perform cleanup in the correct order
    log "Starting cleanup process..."
    
    # Delete environments first (they depend on templates)
    delete_environments
    
    # Delete service templates
    delete_service_templates
    
    # Delete environment templates
    delete_environment_templates
    
    # Delete S3 bucket
    delete_s3_bucket
    
    # Delete IAM role
    delete_iam_role
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    success "Cleanup completed successfully!"
    log "All AWS Proton and CDK infrastructure automation resources have been removed."
}

# Handle script interruption
trap 'log "Cleanup interrupted by user"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--project-name PROJECT_NAME] [--force]"
            echo "  --project-name: Specify the project name to clean up"
            echo "  --force: Skip confirmation prompts"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Skip confirmation if force flag is set
if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
    confirm() {
        log "Force cleanup enabled, skipping confirmation"
        return 0
    }
fi

# Run main function
main "$@"
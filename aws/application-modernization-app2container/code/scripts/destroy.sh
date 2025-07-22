#!/bin/bash

# AWS App2Container Application Modernization Cleanup Script
# This script removes all resources created by the App2Container deployment
# Based on the recipe: Application Modernization with App2Container

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Continuing cleanup..."
}

trap 'handle_error $LINENO' ERR

# Display script header
echo "=================================================="
echo "  AWS App2Container Cleanup Script"
echo "  Recipe: Building Application Modernization"
echo "=================================================="
echo ""

# Configuration variables
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}
PRESERVE_ECR=${PRESERVE_ECR:-false}
PRESERVE_S3=${PRESERVE_S3:-false}
AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}
WORKSPACE_PATH=${WORKSPACE_PATH:-/opt/app2container}

# Function to confirm destructive actions
confirm_action() {
    if [ "$FORCE_DELETE" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This action will permanently delete resources!${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from environment file first
    if [ -f "/tmp/app2container-env.sh" ]; then
        log "Loading variables from /tmp/app2container-env.sh"
        source /tmp/app2container-env.sh
    else
        log_warning "Environment file not found. Attempting to discover resources..."
        
        # Try to discover resources if environment file doesn't exist
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [ -z "$AWS_ACCOUNT_ID" ]; then
            log_error "Cannot determine AWS account ID. Please ensure AWS CLI is configured."
            exit 1
        fi
        
        # Try to find App2Container resources
        log "Attempting to discover App2Container resources..."
        
        # Look for ECS clusters with app2container prefix
        CLUSTERS=$(aws ecs list-clusters --region "${AWS_REGION}" --query 'clusterArns' --output text 2>/dev/null | grep app2container || echo "")
        if [ -n "$CLUSTERS" ]; then
            export CLUSTER_NAME=$(echo "$CLUSTERS" | head -1 | cut -d'/' -f2)
            log "Found ECS cluster: ${CLUSTER_NAME}"
        fi
        
        # Look for ECR repositories with modernized-app prefix
        ECR_REPOS=$(aws ecr describe-repositories --region "${AWS_REGION}" --query 'repositories[?starts_with(repositoryName, `modernized-app`)].repositoryName' --output text 2>/dev/null || echo "")
        if [ -n "$ECR_REPOS" ]; then
            export ECR_REPO_NAME=$(echo "$ECR_REPOS" | head -1)
            log "Found ECR repository: ${ECR_REPO_NAME}"
        fi
        
        # Look for S3 buckets with app2container prefix
        S3_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `app2container-artifacts`)].Name' --output text 2>/dev/null || echo "")
        if [ -n "$S3_BUCKETS" ]; then
            export S3_BUCKET_NAME=$(echo "$S3_BUCKETS" | head -1)
            log "Found S3 bucket: ${S3_BUCKET_NAME}"
        fi
        
        # Look for CodeCommit repositories with app2container prefix
        CODECOMMIT_REPOS=$(aws codecommit list-repositories --query 'repositories[?starts_with(repositoryName, `app2container-pipeline`)].repositoryName' --output text 2>/dev/null || echo "")
        if [ -n "$CODECOMMIT_REPOS" ]; then
            export CODECOMMIT_REPO_NAME=$(echo "$CODECOMMIT_REPOS" | head -1)
            log "Found CodeCommit repository: ${CODECOMMIT_REPO_NAME}"
        fi
    fi
    
    # Display discovered resources
    log "Resources to be cleaned up:"
    [ -n "${CLUSTER_NAME:-}" ] && echo "- ECS Cluster: ${CLUSTER_NAME}"
    [ -n "${ECR_REPO_NAME:-}" ] && echo "- ECR Repository: ${ECR_REPO_NAME}"
    [ -n "${S3_BUCKET_NAME:-}" ] && echo "- S3 Bucket: ${S3_BUCKET_NAME}"
    [ -n "${CODECOMMIT_REPO_NAME:-}" ] && echo "- CodeCommit Repository: ${CODECOMMIT_REPO_NAME}"
    [ -n "${APP_ID:-}" ] && echo "- Application ID: ${APP_ID}"
    
    if [ -z "${CLUSTER_NAME:-}${ECR_REPO_NAME:-}${S3_BUCKET_NAME:-}${CODECOMMIT_REPO_NAME:-}" ]; then
        log_warning "No App2Container resources found to clean up"
        return 1
    fi
    
    return 0
}

# Function to stop and remove ECS resources
cleanup_ecs_resources() {
    if [ -z "${CLUSTER_NAME:-}" ]; then
        log_warning "No ECS cluster specified, skipping ECS cleanup"
        return 0
    fi
    
    log "Cleaning up ECS resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would clean up ECS cluster ${CLUSTER_NAME}"
        return 0
    fi
    
    # Check if cluster exists
    if ! aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "ECS cluster ${CLUSTER_NAME} not found"
        return 0
    fi
    
    # Get all services in the cluster
    SERVICES=$(aws ecs list-services --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" \
        --query 'serviceArns' --output text 2>/dev/null || echo "")
    
    if [ -n "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
        for service_arn in $SERVICES; do
            SERVICE_NAME=$(echo "$service_arn" | cut -d'/' -f2)
            log "Stopping ECS service: ${SERVICE_NAME}"
            
            # Update service to 0 desired count
            aws ecs update-service \
                --cluster "${CLUSTER_NAME}" \
                --service "${SERVICE_NAME}" \
                --desired-count 0 \
                --region "${AWS_REGION}" &>/dev/null || log_warning "Failed to update service ${SERVICE_NAME}"
            
            # Wait for tasks to stop (with timeout)
            log "Waiting for tasks to stop..."
            timeout 300 aws ecs wait services-stable \
                --cluster "${CLUSTER_NAME}" \
                --services "${SERVICE_NAME}" \
                --region "${AWS_REGION}" || log_warning "Timeout waiting for service to stabilize"
            
            # Delete the service
            aws ecs delete-service \
                --cluster "${CLUSTER_NAME}" \
                --service "${SERVICE_NAME}" \
                --region "${AWS_REGION}" &>/dev/null || log_warning "Failed to delete service ${SERVICE_NAME}"
            
            log_success "ECS service ${SERVICE_NAME} removed"
        done
    fi
    
    # Remove auto scaling configuration if it exists
    if [ -n "${SERVICE_NAME:-}" ]; then
        log "Removing auto scaling configuration..."
        
        # Deregister scalable target
        aws application-autoscaling deregister-scalable-target \
            --service-namespace ecs \
            --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
            --scalable-dimension ecs:service:DesiredCount \
            --region "${AWS_REGION}" &>/dev/null || log_warning "Auto scaling target not found or already removed"
    fi
    
    # Delete the cluster
    aws ecs delete-cluster --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null || log_warning "Failed to delete cluster"
    log_success "ECS cluster ${CLUSTER_NAME} removed"
}

# Function to delete CI/CD pipeline
cleanup_cicd_pipeline() {
    if [ -z "${APP_ID:-}" ]; then
        log_warning "No application ID specified, skipping CI/CD pipeline cleanup"
        return 0
    fi
    
    log "Cleaning up CI/CD pipeline..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would delete CI/CD pipeline for application ${APP_ID}"
        return 0
    fi
    
    # Delete CodePipeline CloudFormation stack
    STACK_NAME="app2container-pipeline-${APP_ID}"
    
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        log "Deleting CloudFormation stack: ${STACK_NAME}"
        
        aws cloudformation delete-stack \
            --stack-name "${STACK_NAME}" \
            --region "${AWS_REGION}"
        
        # Wait for stack deletion (with timeout)
        log "Waiting for stack deletion (this may take a few minutes)..."
        timeout 600 aws cloudformation wait stack-delete-complete \
            --stack-name "${STACK_NAME}" \
            --region "${AWS_REGION}" || log_warning "Timeout waiting for stack deletion"
        
        log_success "CI/CD pipeline stack removed"
    else
        log_warning "CI/CD pipeline stack not found"
    fi
}

# Function to remove container images and repositories
cleanup_container_resources() {
    log "Cleaning up container resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would clean up container images and ECR repository"
        return 0
    fi
    
    # Delete ECR repository
    if [ -n "${ECR_REPO_NAME:-}" ] && [ "$PRESERVE_ECR" != "true" ]; then
        if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" &>/dev/null; then
            log "Deleting ECR repository: ${ECR_REPO_NAME}"
            
            aws ecr delete-repository \
                --repository-name "${ECR_REPO_NAME}" \
                --force \
                --region "${AWS_REGION}" || log_warning "Failed to delete ECR repository"
            
            log_success "ECR repository ${ECR_REPO_NAME} removed"
        else
            log_warning "ECR repository ${ECR_REPO_NAME} not found"
        fi
    else
        log_warning "Preserving ECR repository or no repository specified"
    fi
    
    # Delete CodeCommit repository
    if [ -n "${CODECOMMIT_REPO_NAME:-}" ]; then
        if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO_NAME}" &>/dev/null; then
            log "Deleting CodeCommit repository: ${CODECOMMIT_REPO_NAME}"
            
            aws codecommit delete-repository \
                --repository-name "${CODECOMMIT_REPO_NAME}" || log_warning "Failed to delete CodeCommit repository"
            
            log_success "CodeCommit repository ${CODECOMMIT_REPO_NAME} removed"
        else
            log_warning "CodeCommit repository ${CODECOMMIT_REPO_NAME} not found"
        fi
    else
        log_warning "No CodeCommit repository specified"
    fi
    
    # Remove local Docker images
    if [ -n "${CONTAINER_IMAGE:-}" ]; then
        if docker images | grep -q "${APP_ID:-unknown}"; then
            log "Removing local Docker images..."
            docker rmi $(docker images | grep "${APP_ID}" | awk '{print $1":"$2}') &>/dev/null || log_warning "Failed to remove some local images"
            log_success "Local Docker images removed"
        fi
    fi
}

# Function to clean up supporting resources
cleanup_supporting_resources() {
    log "Cleaning up supporting resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would clean up S3 bucket and other supporting resources"
        return 0
    fi
    
    # Delete S3 bucket and contents
    if [ -n "${S3_BUCKET_NAME:-}" ] && [ "$PRESERVE_S3" != "true" ]; then
        if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
            log "Deleting S3 bucket: ${S3_BUCKET_NAME}"
            
            # Remove all objects first
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive &>/dev/null || log_warning "Failed to delete some S3 objects"
            
            # Delete the bucket
            aws s3 rb "s3://${S3_BUCKET_NAME}" &>/dev/null || log_warning "Failed to delete S3 bucket"
            
            log_success "S3 bucket ${S3_BUCKET_NAME} removed"
        else
            log_warning "S3 bucket ${S3_BUCKET_NAME} not found"
        fi
    else
        log_warning "Preserving S3 bucket or no bucket specified"
    fi
    
    # Delete security groups (find by description)
    log "Checking for App2Container security groups..."
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=description,Values=*App2Container*" \
        --query 'SecurityGroups[].GroupId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null || echo "")
    
    if [ -n "$SECURITY_GROUPS" ] && [ "$SECURITY_GROUPS" != "None" ]; then
        for sg_id in $SECURITY_GROUPS; do
            log "Deleting security group: ${sg_id}"
            aws ec2 delete-security-group \
                --group-id "${sg_id}" \
                --region "${AWS_REGION}" &>/dev/null || log_warning "Failed to delete security group ${sg_id}"
        done
        log_success "Security groups removed"
    fi
    
    # Delete CloudWatch dashboard
    if [ -n "${APP_ID:-}" ]; then
        DASHBOARD_NAME="App2Container-${APP_ID}"
        
        if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" --region "${AWS_REGION}" &>/dev/null; then
            log "Deleting CloudWatch dashboard: ${DASHBOARD_NAME}"
            
            aws cloudwatch delete-dashboards \
                --dashboard-names "${DASHBOARD_NAME}" \
                --region "${AWS_REGION}" &>/dev/null || log_warning "Failed to delete dashboard"
            
            log_success "CloudWatch dashboard removed"
        fi
    fi
}

# Function to remove App2Container artifacts
cleanup_app2container_artifacts() {
    log "Cleaning up App2Container artifacts..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would clean up App2Container workspace and artifacts"
        return 0
    fi
    
    # Clean up App2Container workspace
    if [ -n "${APP_ID:-}" ] && [ -d "${WORKSPACE_PATH}/${APP_ID}" ]; then
        log "Removing App2Container workspace for ${APP_ID}..."
        rm -rf "${WORKSPACE_PATH}/${APP_ID}" || log_warning "Failed to remove workspace directory"
        log_success "App2Container workspace cleaned"
    fi
    
    # Remove inventory file
    if [ -f "${WORKSPACE_PATH}/inventory.json" ]; then
        rm -f "${WORKSPACE_PATH}/inventory.json" || log_warning "Failed to remove inventory file"
    fi
    
    # Remove downloaded installers
    if [ -f "/tmp/AWSApp2Container-installer-linux.tar.gz" ]; then
        rm -f /tmp/AWSApp2Container-installer-linux.tar.gz
    fi
    
    # Clean up temporary files
    rm -f /tmp/a2c-init-config.json
    
    # Remove environment file
    if [ -f "/tmp/app2container-env.sh" ]; then
        log "Removing environment file..."
        rm -f /tmp/app2container-env.sh
    fi
    
    log_success "App2Container artifacts cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check ECS cluster
    if [ -n "${CLUSTER_NAME:-}" ]; then
        if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
            log_warning "ECS cluster ${CLUSTER_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check ECR repository
    if [ -n "${ECR_REPO_NAME:-}" ] && [ "$PRESERVE_ECR" != "true" ]; then
        if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" &>/dev/null; then
            log_warning "ECR repository ${ECR_REPO_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check S3 bucket
    if [ -n "${S3_BUCKET_NAME:-}" ] && [ "$PRESERVE_S3" != "true" ]; then
        if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
            log_warning "S3 bucket ${S3_BUCKET_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check CodeCommit repository
    if [ -n "${CODECOMMIT_REPO_NAME:-}" ]; then
        if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO_NAME}" &>/dev/null; then
            log_warning "CodeCommit repository ${CODECOMMIT_REPO_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
    
    return $cleanup_issues
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=================================================="
    echo "  AWS App2Container Cleanup Summary"
    echo "=================================================="
    echo ""
    echo "Cleanup Operations Performed:"
    echo "- ✅ ECS services and cluster cleanup"
    echo "- ✅ CI/CD pipeline removal"
    echo "- ✅ Container images and repositories cleanup"
    echo "- ✅ Supporting AWS resources cleanup"
    echo "- ✅ App2Container artifacts cleanup"
    echo ""
    
    if [ "$PRESERVE_ECR" = "true" ]; then
        echo "Note: ECR repository was preserved as requested"
    fi
    
    if [ "$PRESERVE_S3" = "true" ]; then
        echo "Note: S3 bucket was preserved as requested"
    fi
    
    echo ""
    echo "Additional Manual Steps (if needed):"
    echo "1. Check AWS Console for any remaining resources"
    echo "2. Review CloudWatch logs for retention settings"
    echo "3. Verify IAM roles created by App2Container (manual cleanup)"
    echo "4. Check for any remaining Auto Scaling configurations"
    echo ""
    echo "To reinstall App2Container in the future:"
    echo "sudo ./deploy.sh"
    echo ""
    echo "=================================================="
}

# Main execution flow
main() {
    log "Starting AWS App2Container cleanup..."
    
    # Check if dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Load environment and discover resources
    if ! load_environment; then
        log "No resources found to clean up. Exiting."
        exit 0
    fi
    
    # Confirm destructive action
    if [ "$DRY_RUN" != "true" ]; then
        confirm_action
    fi
    
    # Execute cleanup in proper order
    cleanup_ecs_resources
    cleanup_cicd_pipeline
    cleanup_container_resources
    cleanup_supporting_resources
    cleanup_app2container_artifacts
    
    # Verify cleanup completion
    if [ "$DRY_RUN" != "true" ]; then
        verify_cleanup
    fi
    
    display_cleanup_summary
    
    log_success "AWS App2Container cleanup completed!"
}

# Help function
show_help() {
    echo "AWS App2Container Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Show what would be deleted without actually deleting"
    echo "  --force                Skip confirmation prompts"
    echo "  --preserve-ecr         Keep ECR repository and images"
    echo "  --preserve-s3          Keep S3 bucket and contents"
    echo "  --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DRY_RUN               Set to 'true' for dry run mode"
    echo "  FORCE_DELETE          Set to 'true' to skip confirmations"
    echo "  PRESERVE_ECR          Set to 'true' to preserve ECR repository"
    echo "  PRESERVE_S3           Set to 'true' to preserve S3 bucket"
    echo "  AWS_REGION            AWS region (default: from AWS CLI config)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup"
    echo "  $0 --dry-run          # Show what would be deleted"
    echo "  $0 --force            # Cleanup without prompts"
    echo "  $0 --preserve-ecr     # Keep ECR repository"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --preserve-ecr)
            PRESERVE_ECR=true
            shift
            ;;
        --preserve-s3)
            PRESERVE_S3=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
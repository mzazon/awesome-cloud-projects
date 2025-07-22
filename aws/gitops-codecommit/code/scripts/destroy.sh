#!/bin/bash

# GitOps Workflows with AWS CodeCommit and CodeBuild - Cleanup Script
# This script safely removes all resources created by the deployment script
# including CodeCommit repository, CodeBuild project, ECR repository, and ECS resources

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/gitops-destroy-$(date +%Y%m%d-%H%M%S).log"
CONFIRMATION_REQUIRED=true
FORCE_DELETE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    log "${RED}Check log file: ${LOG_FILE}${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Show usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --repo-name REPO_NAME        Name of the CodeCommit repository
    --project-name PROJECT_NAME  Name of the CodeBuild project
    --cluster-name CLUSTER_NAME  Name of the ECS cluster
    --random-suffix SUFFIX       Random suffix used during deployment
    --aws-region REGION          AWS region (default: from AWS CLI config)
    --force                      Skip confirmation prompts
    --help                       Show this help message

Environment Variables:
    REPO_NAME                    Repository name
    PROJECT_NAME                 CodeBuild project name
    CLUSTER_NAME                 ECS cluster name
    RANDOM_SUFFIX                Random suffix
    AWS_REGION                   AWS region

Examples:
    $0 --repo-name gitops-demo-abc123 --project-name gitops-build-abc123
    $0 --force --random-suffix abc123
    RANDOM_SUFFIX=abc123 $0 --force
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --repo-name)
                REPO_NAME="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --random-suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            --aws-region)
                AWS_REGION="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                CONFIRMATION_REQUIRED=false
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set AWS region
    if [ -z "${AWS_REGION:-}" ]; then
        AWS_REGION=$(aws configure get region)
        if [ -z "${AWS_REGION}" ]; then
            AWS_REGION="us-east-1"
            warning "No default region found, using us-east-1"
        fi
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set resource names if not provided
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        REPO_NAME="${REPO_NAME:-gitops-demo-${RANDOM_SUFFIX}}"
        PROJECT_NAME="${PROJECT_NAME:-gitops-build-${RANDOM_SUFFIX}}"
        CLUSTER_NAME="${CLUSTER_NAME:-gitops-cluster-${RANDOM_SUFFIX}}"
    fi
    
    # Validate required variables
    if [ -z "${REPO_NAME:-}" ] || [ -z "${PROJECT_NAME:-}" ] || [ -z "${CLUSTER_NAME:-}" ]; then
        error_exit "Missing required parameters. Use --help for usage information."
    fi
    
    log "Environment variables:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  REPO_NAME: ${REPO_NAME}"
    log "  PROJECT_NAME: ${PROJECT_NAME}"
    log "  CLUSTER_NAME: ${CLUSTER_NAME}"
    log "  RANDOM_SUFFIX: ${RANDOM_SUFFIX:-N/A}"
    
    success "Environment initialization complete"
}

# Check if required tools are installed
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured properly."
    fi
    
    success "Prerequisites check passed"
}

# Confirm deletion with user
confirm_deletion() {
    if [ "$CONFIRMATION_REQUIRED" = true ]; then
        log "${YELLOW}WARNING: This will delete the following resources:${NC}"
        log "  - CodeCommit Repository: ${REPO_NAME}"
        log "  - CodeBuild Project: ${PROJECT_NAME}"
        log "  - ECR Repository: ${REPO_NAME}"
        log "  - ECS Cluster: ${CLUSTER_NAME}"
        log "  - IAM Role: CodeBuildGitOpsRole-${RANDOM_SUFFIX:-*}"
        log "  - CloudWatch Log Group: /ecs/gitops-app"
        log ""
        log "${RED}This action cannot be undone!${NC}"
        log ""
        
        read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
        if [ "$confirmation" != "yes" ]; then
            log "Operation cancelled by user."
            exit 0
        fi
    fi
    
    info "Proceeding with resource deletion..."
}

# Stop and delete running ECS services
cleanup_ecs_services() {
    info "Cleaning up ECS services..."
    
    # Check if cluster exists
    if ! aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
        warning "ECS cluster ${CLUSTER_NAME} not found, skipping service cleanup"
        return 0
    fi
    
    # List and stop services
    local services=$(aws ecs list-services --cluster "${CLUSTER_NAME}" --query 'serviceArns' --output text 2>/dev/null || echo "")
    
    if [ -n "$services" ] && [ "$services" != "None" ]; then
        info "Found ECS services, stopping them..."
        
        for service in $services; do
            local service_name=$(echo "$service" | cut -d'/' -f3)
            info "Stopping service: $service_name"
            
            # Update service to 0 desired count
            aws ecs update-service \
                --cluster "${CLUSTER_NAME}" \
                --service "$service_name" \
                --desired-count 0 \
                >> "${LOG_FILE}" 2>&1
            
            # Wait for service to scale down
            aws ecs wait services-stable \
                --cluster "${CLUSTER_NAME}" \
                --services "$service_name" \
                >> "${LOG_FILE}" 2>&1
            
            # Delete service
            aws ecs delete-service \
                --cluster "${CLUSTER_NAME}" \
                --service "$service_name" \
                >> "${LOG_FILE}" 2>&1
            
            success "Service $service_name deleted"
        done
    else
        info "No ECS services found in cluster"
    fi
}

# Delete CodeBuild project
delete_codebuild_project() {
    info "Deleting CodeBuild project..."
    
    # Check if project exists
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}" --query 'projects[0].name' --output text 2>/dev/null | grep -q "${PROJECT_NAME}"; then
        aws codebuild delete-project --name "${PROJECT_NAME}" >> "${LOG_FILE}" 2>&1
        success "CodeBuild project ${PROJECT_NAME} deleted"
    else
        warning "CodeBuild project ${PROJECT_NAME} not found"
    fi
}

# Delete ECR repository and all images
delete_ecr_repository() {
    info "Deleting ECR repository..."
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names "${REPO_NAME}" &> /dev/null; then
        # Delete all images first
        local images=$(aws ecr list-images --repository-name "${REPO_NAME}" --query 'imageIds[].imageTag' --output text 2>/dev/null || echo "")
        
        if [ -n "$images" ] && [ "$images" != "None" ]; then
            info "Deleting container images..."
            for tag in $images; do
                aws ecr batch-delete-image \
                    --repository-name "${REPO_NAME}" \
                    --image-ids imageTag="$tag" \
                    >> "${LOG_FILE}" 2>&1
            done
            success "Container images deleted"
        fi
        
        # Delete repository
        aws ecr delete-repository \
            --repository-name "${REPO_NAME}" \
            --force \
            >> "${LOG_FILE}" 2>&1
        
        success "ECR repository ${REPO_NAME} deleted"
    else
        warning "ECR repository ${REPO_NAME} not found"
    fi
}

# Delete ECS cluster
delete_ecs_cluster() {
    info "Deleting ECS cluster..."
    
    # Check if cluster exists
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
        # First ensure all services are cleaned up
        cleanup_ecs_services
        
        # Delete cluster
        aws ecs delete-cluster --cluster "${CLUSTER_NAME}" >> "${LOG_FILE}" 2>&1
        success "ECS cluster ${CLUSTER_NAME} deleted"
    else
        warning "ECS cluster ${CLUSTER_NAME} not found"
    fi
}

# Delete CloudWatch log groups
delete_cloudwatch_logs() {
    info "Deleting CloudWatch log groups..."
    
    # Delete ECS log group
    if aws logs describe-log-groups --log-group-name-prefix "/ecs/gitops-app" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "/ecs/gitops-app"; then
        aws logs delete-log-group --log-group-name "/ecs/gitops-app" >> "${LOG_FILE}" 2>&1
        success "CloudWatch log group /ecs/gitops-app deleted"
    else
        warning "CloudWatch log group /ecs/gitops-app not found"
    fi
    
    # Delete CodeBuild log groups
    local codebuild_log_groups=$(aws logs describe-log-groups --log-group-name-prefix "/aws/codebuild/${PROJECT_NAME}" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
    
    if [ -n "$codebuild_log_groups" ] && [ "$codebuild_log_groups" != "None" ]; then
        for log_group in $codebuild_log_groups; do
            aws logs delete-log-group --log-group-name "$log_group" >> "${LOG_FILE}" 2>&1
            success "CloudWatch log group $log_group deleted"
        done
    else
        info "No CodeBuild log groups found"
    fi
}

# Delete IAM roles
delete_iam_roles() {
    info "Deleting IAM roles..."
    
    # Delete CodeBuild role
    local codebuild_role_name="CodeBuildGitOpsRole-${RANDOM_SUFFIX:-*}"
    
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        codebuild_role_name="CodeBuildGitOpsRole-${RANDOM_SUFFIX}"
        
        if aws iam get-role --role-name "${codebuild_role_name}" &> /dev/null; then
            # Detach policies
            aws iam detach-role-policy \
                --role-name "${codebuild_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
                >> "${LOG_FILE}" 2>&1
            
            aws iam detach-role-policy \
                --role-name "${codebuild_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser \
                >> "${LOG_FILE}" 2>&1
            
            aws iam detach-role-policy \
                --role-name "${codebuild_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess \
                >> "${LOG_FILE}" 2>&1
            
            # Delete role
            aws iam delete-role --role-name "${codebuild_role_name}" >> "${LOG_FILE}" 2>&1
            success "IAM role ${codebuild_role_name} deleted"
        else
            warning "IAM role ${codebuild_role_name} not found"
        fi
    else
        warning "No random suffix provided, skipping IAM role cleanup"
        info "Please manually delete IAM roles with pattern: CodeBuildGitOpsRole-*"
    fi
    
    # Delete CodePipeline role if it exists
    local codepipeline_role_name="CodePipelineGitOpsRole-${RANDOM_SUFFIX:-*}"
    
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        codepipeline_role_name="CodePipelineGitOpsRole-${RANDOM_SUFFIX}"
        
        if aws iam get-role --role-name "${codepipeline_role_name}" &> /dev/null; then
            # Detach policies (if any were attached)
            aws iam detach-role-policy \
                --role-name "${codepipeline_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AWSCodeCommitReadOnly \
                >> "${LOG_FILE}" 2>&1 || true
            
            aws iam detach-role-policy \
                --role-name "${codepipeline_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess \
                >> "${LOG_FILE}" 2>&1 || true
            
            aws iam detach-role-policy \
                --role-name "${codepipeline_role_name}" \
                --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess \
                >> "${LOG_FILE}" 2>&1 || true
            
            # Delete role
            aws iam delete-role --role-name "${codepipeline_role_name}" >> "${LOG_FILE}" 2>&1
            success "IAM role ${codepipeline_role_name} deleted"
        else
            info "IAM role ${codepipeline_role_name} not found"
        fi
    fi
}

# Delete CodeCommit repository
delete_codecommit_repository() {
    info "Deleting CodeCommit repository..."
    
    # Check if repository exists
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        log "${RED}WARNING: This will permanently delete the repository and all its history!${NC}"
        
        if [ "$CONFIRMATION_REQUIRED" = true ]; then
            read -p "Are you sure you want to delete the repository ${REPO_NAME}? (type 'yes' to confirm): " repo_confirmation
            if [ "$repo_confirmation" != "yes" ]; then
                warning "Repository deletion cancelled by user"
                return 0
            fi
        fi
        
        aws codecommit delete-repository --repository-name "${REPO_NAME}" >> "${LOG_FILE}" 2>&1
        success "CodeCommit repository ${REPO_NAME} deleted"
    else
        warning "CodeCommit repository ${REPO_NAME} not found"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    rm -f /tmp/codebuild-trust-policy.json
    rm -f /tmp/codepipeline-trust-policy.json
    rm -rf /tmp/gitops-*
    
    success "Temporary files cleaned up"
}

# Generate cleanup summary
generate_summary() {
    info "Generating cleanup summary..."
    
    local summary_file="/tmp/gitops-cleanup-summary.txt"
    
    cat > "${summary_file}" << EOF
GitOps Workflow Cleanup Summary
===============================

Cleanup completed at: $(date)

Resources Removed:
- CodeCommit Repository: ${REPO_NAME}
- ECR Repository: ${REPO_NAME}
- CodeBuild Project: ${PROJECT_NAME}
- ECS Cluster: ${CLUSTER_NAME}
- CloudWatch Log Groups: /ecs/gitops-app, /aws/codebuild/${PROJECT_NAME}
- IAM Roles: CodeBuildGitOpsRole-${RANDOM_SUFFIX:-*}, CodePipelineGitOpsRole-${RANDOM_SUFFIX:-*}

Log File: ${LOG_FILE}

Note: If you had any running ECS services or tasks, they were stopped and deleted.
      All container images in the ECR repository were also removed.
EOF
    
    cat "${summary_file}"
    
    success "Cleanup summary saved to: ${summary_file}"
}

# Main cleanup function
main() {
    log "${GREEN}Starting GitOps Workflow Cleanup${NC}"
    log "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    check_prerequisites
    initialize_environment
    confirm_deletion
    
    # Clean up resources in reverse order of creation
    cleanup_ecs_services
    delete_ecs_cluster
    delete_codebuild_project
    delete_ecr_repository
    delete_cloudwatch_logs
    delete_iam_roles
    delete_codecommit_repository
    cleanup_temp_files
    
    generate_summary
    
    success "GitOps workflow cleanup completed successfully!"
    log "All resources have been removed."
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
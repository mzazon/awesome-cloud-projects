#!/bin/bash

# =============================================================================
# ECS Task Definitions with Environment Variable Management - Cleanup Script
# =============================================================================
# This script safely removes all infrastructure components created by the
# deployment script for the ECS environment variable management demonstration.
#
# Features:
# - Safe confirmation prompts for destructive actions
# - Proper dependency order for resource cleanup
# - Comprehensive validation of resource removal
# - Detailed logging of cleanup operations
# - State file management for tracking resources
#
# Author: AWS Recipes Team
# Version: 1.0
# =============================================================================

set -euo pipefail

# Enable debug mode if DEBUG environment variable is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# =============================================================================
# CONFIGURATION AND GLOBAL VARIABLES
# =============================================================================

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"
readonly TEMP_DIR="/tmp/ecs-envvar-destroy-$$"

# Configuration flags
FORCE_CLEANUP="${FORCE_CLEANUP:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

log_dry_run() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup script encountered an error"
    rm -rf "${TEMP_DIR}"
    exit 1
}

trap cleanup_on_error ERR

# Confirmation functions
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${FORCE_CLEANUP}" == "true" ]]; then
        return 0
    fi
    
    local prompt
    if [[ "${default}" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    echo -e "${YELLOW}[CONFIRM]${NC} ${message} ${prompt}"
    read -r response
    
    # Handle default responses
    if [[ -z "${response}" ]]; then
        response="${default}"
    fi
    
    case "${response,,}" in
        y|yes) return 0 ;;
        n|no) return 1 ;;
        *) 
            echo "Please answer yes or no."
            confirm_action "${message}" "${default}"
            ;;
    esac
}

# State management functions
load_deployment_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_error "No deployment state file found at ${STATE_FILE}"
        log_error "Unable to determine resources to clean up"
        echo ""
        echo "If you know the deployment details, you can create the state file manually:"
        echo "  AWS_REGION=your-region"
        echo "  AWS_ACCOUNT_ID=your-account-id"
        echo "  CLUSTER_NAME=your-cluster-name"
        echo "  # ... other resource names"
        echo ""
        echo "Or use --force-cleanup with manual resource specification"
        return 1
    fi
    
    log_info "Loading deployment state from ${STATE_FILE}"
    source "${STATE_FILE}"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "CLUSTER_NAME" "TASK_FAMILY" 
        "SERVICE_NAME" "S3_BUCKET" "EXEC_ROLE_NAME" "POLICY_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} not found in state file"
            return 1
        fi
    done
    
    log_success "Deployment state loaded successfully"
    log_info "  - AWS Region: ${AWS_REGION}"
    log_info "  - Cluster: ${CLUSTER_NAME}"
    log_info "  - Service: ${SERVICE_NAME}"
    log_info "  - S3 Bucket: ${S3_BUCKET}"
}

# Resource existence checks
check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "${resource_type}" in
        "cluster")
            aws ecs describe-clusters --clusters "${resource_name}" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"
            ;;
        "service")
            aws ecs describe-services --cluster "${CLUSTER_NAME}" --services "${resource_name}" --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"
            ;;
        "bucket")
            aws s3api head-bucket --bucket "${resource_name}" 2>/dev/null
            ;;
        "role")
            aws iam get-role --role-name "${resource_name}" &>/dev/null
            ;;
        "policy")
            aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${resource_name}" &>/dev/null
            ;;
        "task-definition")
            aws ecs describe-task-definition --task-definition "${resource_name}" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Prerequisites validation
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid"
        return 1
    fi
    
    # Check basic permissions
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log_error "Insufficient IAM permissions for cleanup operations"
        return 1
    fi
    
    log_success "Prerequisites check passed"
}

# =============================================================================
# RESOURCE CLEANUP FUNCTIONS
# =============================================================================

stop_ecs_service() {
    log_info "Stopping ECS service: ${SERVICE_NAME}"
    
    if ! check_resource_exists "service" "${SERVICE_NAME}"; then
        log_warning "ECS service ${SERVICE_NAME} not found or not active, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would stop ECS service ${SERVICE_NAME}"
        return 0
    fi
    
    # Update service to zero desired count
    log_info "Setting service desired count to 0..."
    aws ecs update-service \
        --cluster "${CLUSTER_NAME}" \
        --service "${SERVICE_NAME}" \
        --desired-count 0 \
        --output text &>> "${LOG_FILE}"
    
    # Wait for tasks to stop
    log_info "Waiting for tasks to stop..."
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local running_count=$(aws ecs describe-services \
            --cluster "${CLUSTER_NAME}" \
            --services "${SERVICE_NAME}" \
            --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
        
        if [[ "${running_count}" == "0" ]]; then
            log_success "All tasks stopped successfully"
            break
        fi
        
        log_info "Waiting for tasks to stop (attempt ${attempt}/${max_attempts})..."
        sleep 10
        ((attempt++))
    done
    
    # Delete the service
    log_info "Deleting ECS service..."
    aws ecs delete-service \
        --cluster "${CLUSTER_NAME}" \
        --service "${SERVICE_NAME}" \
        --output text &>> "${LOG_FILE}"
    
    log_success "ECS service stopped and deleted"
}

delete_task_definitions() {
    log_info "Deregistering ECS task definitions..."
    
    local task_families=("${TASK_FAMILY}" "${TASK_FAMILY}-envfiles")
    
    for family in "${task_families[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry_run "Would deregister task definition family: ${family}"
            continue
        fi
        
        # Get all revisions for the task family
        local revisions=$(aws ecs list-task-definitions \
            --family-prefix "${family}" \
            --status ACTIVE \
            --query 'taskDefinitionArns' \
            --output text 2>/dev/null || echo "")
        
        if [[ -z "${revisions}" ]]; then
            log_warning "No active task definitions found for family: ${family}"
            continue
        fi
        
        # Deregister each revision
        for revision in ${revisions}; do
            log_info "Deregistering task definition: ${revision}"
            aws ecs deregister-task-definition \
                --task-definition "${revision}" \
                --output text &>> "${LOG_FILE}"
        done
        
        log_success "Deregistered task definitions for family: ${family}"
    done
}

delete_ecs_cluster() {
    log_info "Deleting ECS cluster: ${CLUSTER_NAME}"
    
    if ! check_resource_exists "cluster" "${CLUSTER_NAME}"; then
        log_warning "ECS cluster ${CLUSTER_NAME} not found, skipping deletion"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would delete ECS cluster: ${CLUSTER_NAME}"
        return 0
    fi
    
    # Ensure no services are running
    local services=$(aws ecs list-services \
        --cluster "${CLUSTER_NAME}" \
        --query 'serviceArns' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${services}" ]] && [[ "${services}" != "None" ]]; then
        log_warning "Cluster still has active services. Attempting to delete anyway..."
    fi
    
    # Delete the cluster
    aws ecs delete-cluster \
        --cluster "${CLUSTER_NAME}" \
        --output text &>> "${LOG_FILE}"
    
    log_success "ECS cluster deleted successfully"
}

delete_ssm_parameters() {
    log_info "Deleting Systems Manager parameters..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would delete all parameters under /myapp/"
        return 0
    fi
    
    # Get all parameters under /myapp/
    local parameters=$(aws ssm get-parameters-by-path \
        --path "/myapp" \
        --recursive \
        --query 'Parameters[*].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "${parameters}" ]]; then
        log_warning "No Systems Manager parameters found under /myapp/"
        return 0
    fi
    
    # Delete parameters in batches (AWS limit is 10 per request)
    local param_array=($parameters)
    local batch_size=10
    local total_params=${#param_array[@]}
    local deleted_count=0
    
    for ((i=0; i<${total_params}; i+=batch_size)); do
        local batch=("${param_array[@]:i:batch_size}")
        
        if [[ ${#batch[@]} -gt 0 ]]; then
            log_info "Deleting parameter batch: ${batch[*]}"
            aws ssm delete-parameters \
                --names "${batch[@]}" \
                --output text &>> "${LOG_FILE}"
            
            deleted_count=$((deleted_count + ${#batch[@]}))
        fi
    done
    
    log_success "Deleted ${deleted_count} Systems Manager parameters"
}

delete_s3_bucket() {
    log_info "Deleting S3 bucket: ${S3_BUCKET}"
    
    if ! check_resource_exists "bucket" "${S3_BUCKET}"; then
        log_warning "S3 bucket ${S3_BUCKET} not found, skipping deletion"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would delete S3 bucket: ${S3_BUCKET} and all contents"
        return 0
    fi
    
    # Delete all objects and versions
    log_info "Deleting all objects and versions from bucket..."
    
    # Delete current versions
    aws s3 rm "s3://${S3_BUCKET}" --recursive --output text &>> "${LOG_FILE}" 2>&1 || true
    
    # Delete object versions and delete markers
    local versions=$(aws s3api list-object-versions \
        --bucket "${S3_BUCKET}" \
        --query 'Versions[*].[Key,VersionId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${versions}" ]]; then
        while IFS=$'\t' read -r key version_id; do
            if [[ -n "${key}" ]] && [[ -n "${version_id}" ]]; then
                aws s3api delete-object \
                    --bucket "${S3_BUCKET}" \
                    --key "${key}" \
                    --version-id "${version_id}" \
                    --output text &>> "${LOG_FILE}" 2>&1 || true
            fi
        done <<< "${versions}"
    fi
    
    # Delete delete markers
    local delete_markers=$(aws s3api list-object-versions \
        --bucket "${S3_BUCKET}" \
        --query 'DeleteMarkers[*].[Key,VersionId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${delete_markers}" ]]; then
        while IFS=$'\t' read -r key version_id; do
            if [[ -n "${key}" ]] && [[ -n "${version_id}" ]]; then
                aws s3api delete-object \
                    --bucket "${S3_BUCKET}" \
                    --key "${key}" \
                    --version-id "${version_id}" \
                    --output text &>> "${LOG_FILE}" 2>&1 || true
            fi
        done <<< "${delete_markers}"
    fi
    
    # Delete the bucket
    aws s3api delete-bucket \
        --bucket "${S3_BUCKET}" \
        --output text &>> "${LOG_FILE}"
    
    log_success "S3 bucket deleted successfully"
}

delete_iam_resources() {
    log_info "Deleting IAM roles and policies..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would delete IAM role: ${EXEC_ROLE_NAME}"
        log_dry_run "Would delete IAM policy: ${POLICY_NAME}"
        return 0
    fi
    
    # Detach and delete custom policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    if check_resource_exists "policy" "${POLICY_NAME}"; then
        log_info "Detaching custom policy from role..."
        aws iam detach-role-policy \
            --role-name "${EXEC_ROLE_NAME}" \
            --policy-arn "${policy_arn}" \
            --output text &>> "${LOG_FILE}" 2>&1 || true
        
        log_info "Deleting custom policy..."
        aws iam delete-policy \
            --policy-arn "${policy_arn}" \
            --output text &>> "${LOG_FILE}"
        
        log_success "Custom IAM policy deleted"
    else
        log_warning "Custom IAM policy ${POLICY_NAME} not found"
    fi
    
    # Detach AWS managed policies and delete role
    if check_resource_exists "role" "${EXEC_ROLE_NAME}"; then
        log_info "Detaching AWS managed policies..."
        aws iam detach-role-policy \
            --role-name "${EXEC_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
            --output text &>> "${LOG_FILE}" 2>&1 || true
        
        log_info "Deleting IAM role..."
        aws iam delete-role \
            --role-name "${EXEC_ROLE_NAME}" \
            --output text &>> "${LOG_FILE}"
        
        log_success "IAM role deleted successfully"
    else
        log_warning "IAM role ${EXEC_ROLE_NAME} not found"
    fi
}

delete_cloudwatch_logs() {
    log_info "Deleting CloudWatch log groups..."
    
    local log_groups=(
        "/ecs/${TASK_FAMILY}"
        "/ecs/${TASK_FAMILY}-envfiles"
    )
    
    for log_group in "${log_groups[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry_run "Would delete log group: ${log_group}"
            continue
        fi
        
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "${log_group}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${log_group}"; then
            log_info "Deleting log group: ${log_group}"
            aws logs delete-log-group \
                --log-group-name "${log_group}" \
                --output text &>> "${LOG_FILE}" 2>&1 || true
            log_success "Deleted log group: ${log_group}"
        else
            log_warning "Log group ${log_group} not found"
        fi
    done
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_cleanup() {
    log_info "Validating resource cleanup..."
    
    local cleanup_issues=0
    
    # Check ECS cluster
    if check_resource_exists "cluster" "${CLUSTER_NAME}"; then
        log_error "ECS cluster ${CLUSTER_NAME} still exists"
        ((cleanup_issues++))
    else
        log_success "ECS cluster cleanup validated"
    fi
    
    # Check S3 bucket
    if check_resource_exists "bucket" "${S3_BUCKET}"; then
        log_error "S3 bucket ${S3_BUCKET} still exists"
        ((cleanup_issues++))
    else
        log_success "S3 bucket cleanup validated"
    fi
    
    # Check IAM role
    if check_resource_exists "role" "${EXEC_ROLE_NAME}"; then
        log_error "IAM role ${EXEC_ROLE_NAME} still exists"
        ((cleanup_issues++))
    else
        log_success "IAM role cleanup validated"
    fi
    
    # Check Parameters
    local param_count=$(aws ssm get-parameters-by-path \
        --path "/myapp" \
        --recursive \
        --query 'length(Parameters)' --output text 2>/dev/null || echo "0")
    
    if [[ "${param_count}" -gt 0 ]]; then
        log_error "Found ${param_count} remaining Systems Manager parameters"
        ((cleanup_issues++))
    else
        log_success "Systems Manager parameters cleanup validated"
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "All cleanup validation checks passed"
        return 0
    else
        log_error "Cleanup validation failed with ${cleanup_issues} issues"
        return 1
    fi
}

display_cleanup_summary() {
    echo ""
    echo "======================================================================"
    echo "                    CLEANUP SUMMARY"
    echo "======================================================================"
    echo ""
    echo "The following resources have been removed:"
    echo ""
    echo "ECS Resources:"
    echo "  ✓ Service: ${SERVICE_NAME}"
    echo "  ✓ Cluster: ${CLUSTER_NAME}"
    echo "  ✓ Task Definitions: ${TASK_FAMILY}, ${TASK_FAMILY}-envfiles"
    echo ""
    echo "Configuration Resources:"
    echo "  ✓ S3 Bucket: ${S3_BUCKET}"
    echo "  ✓ Systems Manager Parameters: /myapp/*"
    echo "  ✓ IAM Role: ${EXEC_ROLE_NAME}"
    echo "  ✓ IAM Policy: ${POLICY_NAME}"
    echo ""
    echo "Monitoring Resources:"
    echo "  ✓ CloudWatch Log Groups: /ecs/${TASK_FAMILY}*"
    echo ""
    echo "Cleanup completed successfully!"
    echo "======================================================================"
}

# =============================================================================
# MAIN CLEANUP FLOW
# =============================================================================

main() {
    log_info "Starting ECS Environment Variable Management cleanup..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    echo ""
    
    # Initialize
    mkdir -p "${TEMP_DIR}"
    
    # Prerequisites and state loading
    check_prerequisites
    load_deployment_state
    
    # Display what will be cleaned up
    echo ""
    echo "======================================================================"
    echo "                    RESOURCES TO BE DELETED"
    echo "======================================================================"
    echo ""
    echo "ECS Resources:"
    echo "  - Service: ${SERVICE_NAME}"
    echo "  - Cluster: ${CLUSTER_NAME}" 
    echo "  - Task Definitions: ${TASK_FAMILY}, ${TASK_FAMILY}-envfiles"
    echo ""
    echo "Configuration Resources:"
    echo "  - S3 Bucket: ${S3_BUCKET} (and all contents)"
    echo "  - Systems Manager Parameters: /myapp/* (all parameters)"
    echo "  - IAM Role: ${EXEC_ROLE_NAME}"
    echo "  - IAM Policy: ${POLICY_NAME}"
    echo ""
    echo "Monitoring Resources:"
    echo "  - CloudWatch Log Groups: /ecs/${TASK_FAMILY}*"
    echo ""
    echo "======================================================================"
    echo ""
    
    # Confirmation
    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! confirm_action "Are you sure you want to delete all these resources?" "n"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        
        echo ""
        log_warning "This action cannot be undone!"
        if ! confirm_action "Proceed with resource deletion?" "n"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    echo ""
    log_info "Beginning resource cleanup..."
    
    # Cleanup in dependency order
    stop_ecs_service
    delete_task_definitions
    delete_ecs_cluster
    delete_ssm_parameters
    delete_s3_bucket
    delete_iam_resources
    delete_cloudwatch_logs
    
    # Validate cleanup (skip for dry run)
    if [[ "${DRY_RUN}" != "true" ]]; then
        validate_cleanup
        display_cleanup_summary
        
        # Remove state file
        if [[ -f "${STATE_FILE}" ]]; then
            rm -f "${STATE_FILE}"
            log_success "Deployment state file removed"
        fi
    else
        log_info "Dry run completed - no resources were deleted"
    fi
    
    # Cleanup temporary files
    rm -rf "${TEMP_DIR}"
    
    log_success "Cleanup completed successfully!"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP="true"
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force       Force cleanup without confirmations (dangerous!)"
            echo "  --yes         Skip confirmation prompts"
            echo "  --dry-run     Show what would be deleted without actually deleting"
            echo "  --help        Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  DEBUG=true    Enable debug output"
            echo ""
            echo "Safety Notes:"
            echo "  - This script will delete ALL resources created by the deployment"
            echo "  - Always run with --dry-run first to verify what will be deleted"
            echo "  - Ensure you have the correct AWS credentials configured"
            echo "  - Consider backing up any important data before running"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"
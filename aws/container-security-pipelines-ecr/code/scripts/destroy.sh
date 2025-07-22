#!/bin/bash

# =============================================================================
# Container Security Scanning Pipeline Cleanup Script
# =============================================================================
# This script removes all resources created by the container security scanning
# pipeline deployment, including ECR repositories, Lambda functions, 
# EventBridge rules, and associated IAM roles and policies.
# 
# Requirements:
# - AWS CLI v2 configured with appropriate permissions
# - Deployment state file from successful deployment
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="/tmp/container-security-destroy-$$"
readonly LOG_FILE="${TEMP_DIR}/cleanup.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Cleanup options
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -f, --force    Force cleanup even if state file is missing"
                echo "  -y, --yes      Skip confirmation prompts"
                echo "  -h, --help     Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check for deployment state file
    if [[ ! -f "${STATE_FILE}" ]] && [[ "${FORCE_CLEANUP}" != true ]]; then
        log_error "Deployment state file not found: ${STATE_FILE}"
        log_error "Use --force to attempt cleanup without state file"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to initialize cleanup environment
initialize_environment() {
    log_info "Initializing cleanup environment..."
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Initialize log file
    echo "Container Security Scanning Pipeline Cleanup Log" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    echo "========================================" >> "${LOG_FILE}"
    
    # Load deployment state if available
    if [[ -f "${STATE_FILE}" ]]; then
        source "${STATE_FILE}"
        log_info "Loaded deployment state from: ${STATE_FILE}"
    else
        log_warning "No state file found. Will attempt manual cleanup."
        # Set default values for manual cleanup
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # These will need to be discovered or provided manually
        export PROJECT_NAME="${PROJECT_NAME:-unknown}"
        export ECR_REPO_NAME="${ECR_REPO_NAME:-unknown}"
        export LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-unknown}"
        export SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-unknown}"
        export EVENTBRIDGE_RULE_NAME="${EVENTBRIDGE_RULE_NAME:-unknown}"
        export CONFIG_RULE_NAME="${CONFIG_RULE_NAME:-unknown}"
        export DASHBOARD_NAME="${DASHBOARD_NAME:-unknown}"
        export CODEBUILD_PROJECT_NAME="${CODEBUILD_PROJECT_NAME:-unknown}"
        export CODEBUILD_ROLE_NAME="${CODEBUILD_ROLE_NAME:-unknown}"
        export LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME:-unknown}"
    fi
    
    log_success "Environment initialized"
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "${SKIP_CONFIRMATION}" == true ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - ECR Repository: ${ECR_REPO_NAME}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "  - Config Rule: ${CONFIG_RULE_NAME}"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  - CodeBuild Project: ${CODEBUILD_PROJECT_NAME}"
    echo "  - IAM Roles and Policies"
    echo ""
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to remove CloudWatch dashboard
remove_cloudwatch_dashboard() {
    log_info "Removing CloudWatch dashboard..."
    
    if [[ "${DASHBOARD_NAME}" != "unknown" ]]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete dashboard ${DASHBOARD_NAME}"
        log_success "CloudWatch dashboard removed"
    else
        log_warning "Dashboard name unknown, attempting to find dashboards with project tag"
        # Try to find and delete dashboards with project tag
        local dashboards
        dashboards=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `ContainerSecurityDashboard`)].DashboardName' --output text)
        if [[ -n "${dashboards}" ]]; then
            for dashboard in ${dashboards}; do
                aws cloudwatch delete-dashboards --dashboard-names "${dashboard}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed dashboard: ${dashboard}"
            done
        fi
    fi
}

# Function to remove Config rule
remove_config_rule() {
    log_info "Removing Config rule..."
    
    if [[ "${CONFIG_RULE_NAME}" != "unknown" ]]; then
        aws configservice delete-config-rule \
            --config-rule-name "${CONFIG_RULE_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete Config rule ${CONFIG_RULE_NAME}"
        log_success "Config rule removed"
    else
        log_warning "Config rule name unknown, attempting to find rules with ECR scanning pattern"
        # Try to find Config rules related to ECR scanning
        local rules
        rules=$(aws configservice describe-config-rules --query 'ConfigRules[?contains(ConfigRuleName, `ecr-repository-scan-enabled`)].ConfigRuleName' --output text)
        if [[ -n "${rules}" ]]; then
            for rule in ${rules}; do
                aws configservice delete-config-rule --config-rule-name "${rule}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed Config rule: ${rule}"
            done
        fi
    fi
}

# Function to remove EventBridge rule
remove_eventbridge_rule() {
    log_info "Removing EventBridge rule..."
    
    if [[ "${EVENTBRIDGE_RULE_NAME}" != "unknown" ]]; then
        # Remove targets first
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to remove targets from rule ${EVENTBRIDGE_RULE_NAME}"
        
        # Delete rule
        aws events delete-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete EventBridge rule ${EVENTBRIDGE_RULE_NAME}"
        
        log_success "EventBridge rule removed"
    else
        log_warning "EventBridge rule name unknown, attempting to find rules with ECR scan pattern"
        # Try to find EventBridge rules related to ECR scanning
        local rules
        rules=$(aws events list-rules --query 'Rules[?contains(Name, `ECRScanCompleted`)].Name' --output text)
        if [[ -n "${rules}" ]]; then
            for rule in ${rules}; do
                aws events remove-targets --rule "${rule}" --ids "1" >> "${LOG_FILE}" 2>&1 || true
                aws events delete-rule --name "${rule}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed EventBridge rule: ${rule}"
            done
        fi
    fi
}

# Function to remove Lambda function
remove_lambda_function() {
    log_info "Removing Lambda function..."
    
    if [[ "${LAMBDA_FUNCTION_NAME}" != "unknown" ]]; then
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete Lambda function ${LAMBDA_FUNCTION_NAME}"
        log_success "Lambda function removed"
    else
        log_warning "Lambda function name unknown, attempting to find functions with SecurityScanProcessor pattern"
        # Try to find Lambda functions related to security scanning
        local functions
        functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `SecurityScanProcessor`)].FunctionName' --output text)
        if [[ -n "${functions}" ]]; then
            for func in ${functions}; do
                aws lambda delete-function --function-name "${func}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed Lambda function: ${func}"
            done
        fi
    fi
}

# Function to remove SNS topic
remove_sns_topic() {
    log_info "Removing SNS topic..."
    
    if [[ "${SNS_TOPIC_NAME}" != "unknown" ]]; then
        aws sns delete-topic \
            --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete SNS topic ${SNS_TOPIC_NAME}"
        log_success "SNS topic removed"
    else
        log_warning "SNS topic name unknown, attempting to find topics with security-alerts pattern"
        # Try to find SNS topics related to security alerts
        local topics
        topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `security-alerts`)].TopicArn' --output text)
        if [[ -n "${topics}" ]]; then
            for topic in ${topics}; do
                aws sns delete-topic --topic-arn "${topic}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed SNS topic: ${topic}"
            done
        fi
    fi
}

# Function to remove CodeBuild project
remove_codebuild_project() {
    log_info "Removing CodeBuild project..."
    
    if [[ "${CODEBUILD_PROJECT_NAME}" != "unknown" ]]; then
        aws codebuild delete-project \
            --name "${CODEBUILD_PROJECT_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete CodeBuild project ${CODEBUILD_PROJECT_NAME}"
        log_success "CodeBuild project removed"
    else
        log_warning "CodeBuild project name unknown, attempting to find projects with security-scan pattern"
        # Try to find CodeBuild projects related to security scanning
        local projects
        projects=$(aws codebuild list-projects --query 'projects[?contains(@, `security-scan`)]' --output text)
        if [[ -n "${projects}" ]]; then
            for project in ${projects}; do
                aws codebuild delete-project --name "${project}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed CodeBuild project: ${project}"
            done
        fi
    fi
}

# Function to remove ECR repository
remove_ecr_repository() {
    log_info "Removing ECR repository..."
    
    if [[ "${ECR_REPO_NAME}" != "unknown" ]]; then
        # Delete all images first
        local images
        images=$(aws ecr list-images --repository-name "${ECR_REPO_NAME}" --query 'imageIds' --output json 2>/dev/null || echo "[]")
        
        if [[ "${images}" != "[]" ]]; then
            aws ecr batch-delete-image \
                --repository-name "${ECR_REPO_NAME}" \
                --image-ids "${images}" \
                >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete images from ${ECR_REPO_NAME}"
        fi
        
        # Delete repository
        aws ecr delete-repository \
            --repository-name "${ECR_REPO_NAME}" \
            --force \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete ECR repository ${ECR_REPO_NAME}"
        
        log_success "ECR repository removed"
    else
        log_warning "ECR repository name unknown, attempting to find repositories with secure-app pattern"
        # Try to find ECR repositories related to security scanning
        local repositories
        repositories=$(aws ecr describe-repositories --query 'repositories[?contains(repositoryName, `secure-app`)].repositoryName' --output text)
        if [[ -n "${repositories}" ]]; then
            for repo in ${repositories}; do
                # Delete images first
                local images
                images=$(aws ecr list-images --repository-name "${repo}" --query 'imageIds' --output json 2>/dev/null || echo "[]")
                
                if [[ "${images}" != "[]" ]]; then
                    aws ecr batch-delete-image --repository-name "${repo}" --image-ids "${images}" >> "${LOG_FILE}" 2>&1 || true
                fi
                
                aws ecr delete-repository --repository-name "${repo}" --force >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed ECR repository: ${repo}"
            done
        fi
    fi
}

# Function to remove IAM roles and policies
remove_iam_roles() {
    log_info "Removing IAM roles and policies..."
    
    # Remove CodeBuild role
    if [[ "${CODEBUILD_ROLE_NAME}" != "unknown" ]]; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --policy-name "ECRSecurityScanningPolicy" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete CodeBuild role policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete CodeBuild role ${CODEBUILD_ROLE_NAME}"
        
        log_success "CodeBuild IAM role removed"
    else
        log_warning "CodeBuild role name unknown, attempting to find roles with ECRSecurityScanningRole pattern"
        # Try to find IAM roles related to ECR security scanning
        local roles
        roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `ECRSecurityScanningRole`)].RoleName' --output text)
        if [[ -n "${roles}" ]]; then
            for role in ${roles}; do
                # Delete inline policies
                local policies
                policies=$(aws iam list-role-policies --role-name "${role}" --query 'PolicyNames' --output text)
                for policy in ${policies}; do
                    aws iam delete-role-policy --role-name "${role}" --policy-name "${policy}" >> "${LOG_FILE}" 2>&1 || true
                done
                
                # Delete role
                aws iam delete-role --role-name "${role}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed IAM role: ${role}"
            done
        fi
    fi
    
    # Remove Lambda role
    if [[ "${LAMBDA_ROLE_NAME}" != "unknown" ]]; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-name "SecurityHubIntegrationPolicy" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete Lambda role policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete Lambda role ${LAMBDA_ROLE_NAME}"
        
        log_success "Lambda IAM role removed"
    else
        log_warning "Lambda role name unknown, attempting to find roles with SecurityScanLambdaRole pattern"
        # Try to find IAM roles related to security scan Lambda
        local roles
        roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `SecurityScanLambdaRole`)].RoleName' --output text)
        if [[ -n "${roles}" ]]; then
            for role in ${roles}; do
                # Delete inline policies
                local policies
                policies=$(aws iam list-role-policies --role-name "${role}" --query 'PolicyNames' --output text)
                for policy in ${policies}; do
                    aws iam delete-role-policy --role-name "${role}" --policy-name "${policy}" >> "${LOG_FILE}" 2>&1 || true
                done
                
                # Delete role
                aws iam delete-role --role-name "${role}" >> "${LOG_FILE}" 2>&1 || true
                log_success "Removed IAM role: ${role}"
            done
        fi
    fi
}

# Function to reset registry scanning configuration
reset_registry_scanning() {
    log_info "Resetting registry scanning configuration..."
    
    # Reset to basic scanning
    aws ecr put-registry-scanning-configuration \
        --scan-type BASIC \
        --rules '[]' \
        >> "${LOG_FILE}" 2>&1 || log_warning "Failed to reset registry scanning configuration"
    
    log_success "Registry scanning configuration reset"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary directory
    rm -rf "${TEMP_DIR}" || log_warning "Failed to remove temporary directory"
    
    # Remove state file
    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}" || log_warning "Failed to remove state file"
        log_success "Deployment state file removed"
    fi
    
    log_success "Temporary files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check if ECR repository still exists
    if [[ "${ECR_REPO_NAME}" != "unknown" ]]; then
        if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" &>/dev/null; then
            log_warning "ECR repository still exists: ${ECR_REPO_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if Lambda function still exists
    if [[ "${LAMBDA_FUNCTION_NAME}" != "unknown" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if EventBridge rule still exists
    if [[ "${EVENTBRIDGE_RULE_NAME}" != "unknown" ]]; then
        if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
            log_warning "EventBridge rule still exists: ${EVENTBRIDGE_RULE_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "Cleanup validation passed"
    else
        log_warning "Cleanup validation found ${cleanup_issues} issues"
    fi
}

# Function to print cleanup summary
print_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "========================================="
    echo "Removed Resources:"
    echo "  - ECR Repository: ${ECR_REPO_NAME}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "  - Config Rule: ${CONFIG_RULE_NAME}"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  - CodeBuild Project: ${CODEBUILD_PROJECT_NAME}"
    echo "  - IAM Roles and Policies"
    echo "========================================="
    echo ""
    echo "Cleanup completed at: $(date)"
    echo "Log file: ${LOG_FILE}"
    echo ""
    echo "Note: Registry scanning configuration has been reset to BASIC"
    echo "Manual verification recommended for complete cleanup"
}

# Main cleanup function
main() {
    log_info "Starting Container Security Scanning Pipeline cleanup..."
    
    # Execute cleanup steps
    parse_arguments "$@"
    check_prerequisites
    initialize_environment
    confirm_cleanup
    
    # Remove resources in reverse order of creation
    remove_cloudwatch_dashboard
    remove_config_rule
    remove_eventbridge_rule
    remove_lambda_function
    remove_sns_topic
    remove_codebuild_project
    remove_ecr_repository
    remove_iam_roles
    reset_registry_scanning
    cleanup_temp_files
    
    validate_cleanup
    print_cleanup_summary
    
    log_success "Container Security Scanning Pipeline cleanup completed!"
}

# Run main function
main "$@"
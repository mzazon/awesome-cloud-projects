#!/bin/bash

#########################################################################
# AWS Simple App Configuration with AppConfig and Lambda - Destroy Script
# 
# This script safely removes all infrastructure created by the Simple
# Application Configuration recipe deployment.
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate AWS permissions for resource deletion
# - jq installed for JSON processing
#
# Usage: ./destroy.sh [--force] [--dry-run] [--debug]
#########################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DRY_RUN=false
DEBUG=false
FORCE=false
DELETE_LOGS=false

#########################################################################
# Helper Functions
#########################################################################

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        log "${BLUE}[DEBUG]${NC} ${1}"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS Simple App Configuration with AppConfig and Lambda

OPTIONS:
    --force         Skip confirmation prompts
    --dry-run       Show what would be destroyed without making changes
    --debug         Enable debug logging
    --delete-logs   Also delete CloudWatch logs
    -h, --help      Show this help message

EXAMPLES:
    $0                      # Interactive destruction with confirmations
    $0 --force              # Automatic destruction without prompts
    $0 --dry-run            # Preview what would be destroyed
    $0 --debug              # Destroy with debug logging
EOF
}

confirm_destruction() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    cat << EOF

${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}

  🗑️  Lambda Function: ${LAMBDA_FUNCTION_NAME:-"(unknown)"}
  🗑️  AppConfig Application: ${APP_NAME:-"(unknown)"}
  🗑️  IAM Role: ${LAMBDA_ROLE_NAME:-"(unknown)"}
  🗑️  IAM Policy: ${APPCONFIG_POLICY_NAME:-"(unknown)"}
  🗑️  Deployment Strategy: ${DEPLOYMENT_STRATEGY_NAME:-"(unknown)"}

EOF

    if [[ "${DELETE_LOGS}" == "true" ]]; then
        echo -e "  🗑️  CloudWatch Logs: /aws/lambda/${LAMBDA_FUNCTION_NAME:-"(unknown)"}"
        echo ""
    fi

    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

#########################################################################
# Environment Loading
#########################################################################

load_environment() {
    log_info "Loading environment variables..."
    
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_warning "Environment file not found. Attempting to discover resources..."
        discover_resources
        return
    fi
    
    # Source environment variables
    set -a  # Automatically export all variables
    source "${ENV_FILE}"
    set +a
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "APP_NAME"
        "LAMBDA_FUNCTION_NAME"
        "LAMBDA_ROLE_NAME"
        "APPCONFIG_POLICY_NAME"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_warning "Missing environment variables: ${missing_vars[*]}"
        log_info "Attempting to discover resources..."
        discover_resources
    else
        log_success "Environment loaded successfully"
        debug "App Name: ${APP_NAME}"
        debug "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        debug "IAM Role: ${LAMBDA_ROLE_NAME}"
    fi
}

discover_resources() {
    log_info "Attempting to discover existing resources..."
    
    # Try to discover resources by tag or naming pattern
    local region
    region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_REGION="${region}"
    
    # Look for Lambda functions with our naming pattern
    local functions
    functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `config-demo-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        export LAMBDA_FUNCTION_NAME=$(echo "${functions}" | head -n1)
        log_info "Discovered Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Look for AppConfig applications with our naming pattern
    local apps
    apps=$(aws appconfig list-applications \
        --query 'Items[?contains(Name, `simple-config-app-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${apps}" ]]; then
        export APP_NAME=$(echo "${apps}" | head -n1)
        export APP_ID=$(aws appconfig list-applications \
            --query "Items[?Name=='${APP_NAME}'].Id" \
            --output text 2>/dev/null || echo "")
        log_info "Discovered AppConfig application: ${APP_NAME} (${APP_ID})"
    fi
    
    # Look for IAM roles with our naming pattern
    local roles
    roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `lambda-appconfig-role-`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${roles}" ]]; then
        export LAMBDA_ROLE_NAME=$(echo "${roles}" | head -n1)
        log_info "Discovered IAM role: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Try to extract suffix from discovered resources
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        local suffix="${LAMBDA_FUNCTION_NAME##*-}"
        export DEPLOYMENT_STRATEGY_NAME="immediate-deployment-${suffix}"
        export APPCONFIG_POLICY_NAME="AppConfigLambdaPolicy-${suffix}"
    fi
}

#########################################################################
# Resource Deletion Functions
#########################################################################

delete_lambda_function() {
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_warning "Lambda function name not found, skipping..."
        return 0
    fi
    
    log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found, skipping..."
        return 0
    fi
    
    # Delete Lambda function
    if aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null; then
        log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        log_error "Failed to delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 1
    fi
}

delete_cloudwatch_logs() {
    if [[ "${DELETE_LOGS}" != "true" ]] || [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        return 0
    fi
    
    local log_group="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    
    log_info "Deleting CloudWatch logs: ${log_group}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch log group: ${log_group}"
        return 0
    fi
    
    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "${log_group}" \
        --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${log_group}"; then
        debug "CloudWatch log group ${log_group} not found, skipping..."
        return 0
    fi
    
    # Delete log group
    if aws logs delete-log-group --log-group-name "${log_group}" 2>/dev/null; then
        log_success "CloudWatch log group deleted: ${log_group}"
    else
        log_warning "Failed to delete CloudWatch log group: ${log_group}"
    fi
}

delete_appconfig_resources() {
    if [[ -z "${APP_ID:-}" ]] && [[ -n "${APP_NAME:-}" ]]; then
        APP_ID=$(aws appconfig list-applications \
            --query "Items[?Name=='${APP_NAME}'].Id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${APP_ID:-}" ]]; then
        log_warning "AppConfig application ID not found, skipping AppConfig cleanup..."
        return 0
    fi
    
    log_info "Deleting AppConfig resources for application: ${APP_NAME} (${APP_ID})..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete AppConfig application: ${APP_NAME}"
        return 0
    fi
    
    # Check if application exists
    if ! aws appconfig get-application --application-id "${APP_ID}" &> /dev/null; then
        log_warning "AppConfig application ${APP_ID} not found, skipping..."
        return 0
    fi
    
    # Delete deployment strategy if it exists
    if [[ -n "${DEPLOYMENT_STRATEGY_ID:-}" ]] || [[ -n "${DEPLOYMENT_STRATEGY_NAME:-}" ]]; then
        local strategy_id="${DEPLOYMENT_STRATEGY_ID:-}"
        
        if [[ -z "${strategy_id}" ]] && [[ -n "${DEPLOYMENT_STRATEGY_NAME}" ]]; then
            strategy_id=$(aws appconfig list-deployment-strategies \
                --query "Items[?Name=='${DEPLOYMENT_STRATEGY_NAME}'].Id" \
                --output text 2>/dev/null || echo "")
        fi
        
        if [[ -n "${strategy_id}" ]] && aws appconfig get-deployment-strategy --deployment-strategy-id "${strategy_id}" &> /dev/null; then
            log_info "Deleting deployment strategy: ${strategy_id}..."
            if aws appconfig delete-deployment-strategy --deployment-strategy-id "${strategy_id}" 2>/dev/null; then
                log_success "Deployment strategy deleted: ${strategy_id}"
            else
                log_warning "Failed to delete deployment strategy: ${strategy_id}"
            fi
        fi
    fi
    
    # Get configuration profiles
    local config_profiles
    config_profiles=$(aws appconfig list-configuration-profiles \
        --application-id "${APP_ID}" \
        --query 'Items[].Id' --output text 2>/dev/null || echo "")
    
    # Delete configuration profiles
    for profile_id in ${config_profiles}; do
        log_info "Deleting configuration profile: ${profile_id}..."
        if aws appconfig delete-configuration-profile \
            --application-id "${APP_ID}" \
            --configuration-profile-id "${profile_id}" 2>/dev/null; then
            log_success "Configuration profile deleted: ${profile_id}"
        else
            log_warning "Failed to delete configuration profile: ${profile_id}"
        fi
    done
    
    # Get environments
    local environments
    environments=$(aws appconfig list-environments \
        --application-id "${APP_ID}" \
        --query 'Items[].Id' --output text 2>/dev/null || echo "")
    
    # Delete environments
    for env_id in ${environments}; do
        log_info "Deleting environment: ${env_id}..."
        if aws appconfig delete-environment \
            --application-id "${APP_ID}" \
            --environment-id "${env_id}" 2>/dev/null; then
            log_success "Environment deleted: ${env_id}"
        else
            log_warning "Failed to delete environment: ${env_id}"
        fi
    done
    
    # Delete application
    log_info "Deleting AppConfig application: ${APP_ID}..."
    if aws appconfig delete-application --application-id "${APP_ID}" 2>/dev/null; then
        log_success "AppConfig application deleted: ${APP_ID}"
    else
        log_error "Failed to delete AppConfig application: ${APP_ID}"
        return 1
    fi
}

delete_iam_resources() {
    if [[ -z "${LAMBDA_ROLE_NAME:-}" ]]; then
        log_warning "IAM role name not found, skipping IAM cleanup..."
        return 0
    fi
    
    log_info "Deleting IAM resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM role: ${LAMBDA_ROLE_NAME}"
        log_info "[DRY RUN] Would delete IAM policy: ${APPCONFIG_POLICY_NAME:-"(unknown)"}"
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        log_warning "IAM role ${LAMBDA_ROLE_NAME} not found, skipping IAM cleanup..."
        return 0
    fi
    
    local account_id="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
    
    # Detach policies from role
    log_info "Detaching policies from role: ${LAMBDA_ROLE_NAME}..."
    
    # Detach basic Lambda execution policy
    if aws iam detach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null; then
        debug "Detached AWSLambdaBasicExecutionRole"
    fi
    
    # Detach custom AppConfig policy
    if [[ -n "${APPCONFIG_POLICY_NAME:-}" ]] && [[ -n "${account_id}" ]]; then
        local policy_arn="arn:aws:iam::${account_id}:policy/${APPCONFIG_POLICY_NAME}"
        if aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn "${policy_arn}" 2>/dev/null; then
            debug "Detached ${APPCONFIG_POLICY_NAME}"
        fi
        
        # Delete custom policy
        log_info "Deleting IAM policy: ${APPCONFIG_POLICY_NAME}..."
        if aws iam delete-policy --policy-arn "${policy_arn}" 2>/dev/null; then
            log_success "IAM policy deleted: ${APPCONFIG_POLICY_NAME}"
        else
            log_warning "Failed to delete IAM policy: ${APPCONFIG_POLICY_NAME}"
        fi
    fi
    
    # Delete IAM role
    log_info "Deleting IAM role: ${LAMBDA_ROLE_NAME}..."
    if aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null; then
        log_success "IAM role deleted: ${LAMBDA_ROLE_NAME}"
    else
        log_error "Failed to delete IAM role: ${LAMBDA_ROLE_NAME}"
        return 1
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    local files_to_remove=(
        "${ENV_FILE}"
        "${SCRIPT_DIR}/trust-policy.json"
        "${SCRIPT_DIR}/appconfig-policy.json"
        "${SCRIPT_DIR}/config-data.json"
        "${SCRIPT_DIR}/updated-config.json"
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda-function.zip"
        "${SCRIPT_DIR}/response.json"
        "${SCRIPT_DIR}/updated-response.json"
    )
    
    local removed_count=0
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            ((removed_count++))
            debug "Removed: ${file}"
        fi
    done
    
    if [[ ${removed_count} -gt 0 ]]; then
        log_success "Cleaned up ${removed_count} local files"
    else
        debug "No local files to clean up"
    fi
}

#########################################################################
# Validation Functions
#########################################################################

validate_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

verify_deletion() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    local verification_errors=0
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
            log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((verification_errors++))
        else
            debug "Lambda function successfully deleted: ${LAMBDA_FUNCTION_NAME}"
        fi
    fi
    
    # Check AppConfig application
    if [[ -n "${APP_ID:-}" ]]; then
        if aws appconfig get-application --application-id "${APP_ID}" &> /dev/null; then
            log_warning "AppConfig application still exists: ${APP_ID}"
            ((verification_errors++))
        else
            debug "AppConfig application successfully deleted: ${APP_ID}"
        fi
    fi
    
    # Check IAM role
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
            log_warning "IAM role still exists: ${LAMBDA_ROLE_NAME}"
            ((verification_errors++))
        else
            debug "IAM role successfully deleted: ${LAMBDA_ROLE_NAME}"
        fi
    fi
    
    if [[ ${verification_errors} -eq 0 ]]; then
        log_success "Resource deletion verified successfully"
    else
        log_warning "Found ${verification_errors} resources that may not have been fully deleted"
    fi
}

#########################################################################
# Main Destruction Function
#########################################################################

destroy() {
    local start_time=$(date +%s)
    
    log_info "Starting destruction of Simple App Configuration resources..."
    log_info "Timestamp: $(date)"
    log_info "Log file: ${LOG_FILE}"
    
    # Load environment and confirm destruction
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_lambda_function
    delete_cloudwatch_logs
    delete_appconfig_resources
    delete_iam_resources
    cleanup_local_files
    verify_deletion
    
    # Calculate destruction time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Destruction completed successfully!"
    log_info "Total destruction time: ${duration} seconds"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        cat << EOF

┌─────────────────────────────────────────────────────────────────┐
│                    🧹 Cleanup Complete! 🧹                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ All Simple App Configuration resources have been removed.      │
│                                                                 │
│ Resources deleted:                                              │
│ ✅ Lambda Function                                              │
│ ✅ AppConfig Application & Components                           │
│ ✅ IAM Role & Policies                                          │
│ ✅ Local Configuration Files                                    │
EOF

        if [[ "${DELETE_LOGS}" == "true" ]]; then
            echo "│ ✅ CloudWatch Logs                                              │"
        fi

        cat << EOF
│                                                                 │
│ Your AWS account is now clean of recipe resources.             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

EOF
    fi
}

#########################################################################
# Script Entry Point
#########################################################################

main() {
    # Initialize log file
    echo "Destruction started at $(date)" > "${LOG_FILE}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                log_info "Force mode enabled - skipping confirmations"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                log_info "Dry run mode enabled"
                shift
                ;;
            --debug)
                DEBUG=true
                log_info "Debug mode enabled"
                shift
                ;;
            --delete-logs)
                DELETE_LOGS=true
                log_info "CloudWatch logs deletion enabled"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate prerequisites
    validate_prerequisites
    
    # Start destruction
    destroy
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
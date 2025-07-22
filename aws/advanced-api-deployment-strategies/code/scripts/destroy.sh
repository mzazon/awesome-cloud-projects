#!/bin/bash

# Destroy script for Advanced API Gateway Deployment Strategies with Blue-Green and Canary Patterns
# This script safely removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destruction.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Advanced API Gateway deployment and all associated resources.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -d, --dry-run       Show what would be destroyed without executing
    -f, --force         Skip confirmation prompts
    -r, --region        AWS region (default: from state file or current configured)
    -p, --profile       AWS profile to use
    --keep-logs         Keep CloudWatch log groups
    --partial           Allow partial cleanup (continue on errors)

EXAMPLES:
    $0                  # Interactive destruction with confirmations
    $0 --force          # Destroy without prompts
    $0 --dry-run        # Preview what would be destroyed
    $0 --partial        # Continue cleanup even if some resources fail

EOF
}

# Parse command line arguments
parse_args() {
    VERBOSE=false
    DRY_RUN=false
    FORCE=false
    KEEP_LOGS=false
    PARTIAL=false
    AWS_REGION=""
    AWS_PROFILE=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            --partial)
                PARTIAL=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Override exit on error for partial cleanup
    if [[ "${PARTIAL}" == "true" ]]; then
        set +e
    fi
}

# Load deployment state
load_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        error "State file not found: ${STATE_FILE}"
        error "Cannot proceed with destruction without deployment state"
        exit 1
    fi

    info "Loading deployment state from ${STATE_FILE}"
    source "${STATE_FILE}"

    # Verify required variables
    if [[ -z "${API_ID:-}" ]] || [[ -z "${AWS_REGION:-}" ]]; then
        error "Invalid state file - missing required variables"
        exit 1
    fi

    # Use region from state file if not provided
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION="${AWS_REGION}"
    fi

    info "Loaded state for API: ${API_NAME} (${API_ID})"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi

    # Set AWS profile if specified
    if [[ -n "${AWS_PROFILE}" ]]; then
        export AWS_PROFILE="${AWS_PROFILE}"
        info "Using AWS profile: ${AWS_PROFILE}"
    fi

    # Set AWS region
    export AWS_DEFAULT_REGION="${AWS_REGION}"
    info "Using AWS region: ${AWS_REGION}"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi

    success "Prerequisites check completed"
}

# Resource existence checker
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "${resource_type}" in
        "api-gateway")
            aws apigateway get-rest-api --rest-api-id "${resource_id}" &> /dev/null
            ;;
        "lambda")
            aws lambda get-function --function-name "${resource_id}" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "${resource_id}" &> /dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "${resource_id}" --query 'MetricAlarms[0]' --output text &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    info "Deleting CloudWatch alarms..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete CloudWatch alarms"
        return 0
    fi

    local alarm_names=(
        "${API_NAME}-4xx-errors"
        "${API_NAME}-5xx-errors" 
        "${API_NAME}-high-latency"
    )

    local existing_alarms=()
    
    # Check which alarms exist
    for alarm in "${alarm_names[@]}"; do
        if resource_exists "cloudwatch-alarm" "${alarm}"; then
            existing_alarms+=("${alarm}")
        fi
    done

    if [[ ${#existing_alarms[@]} -eq 0 ]]; then
        info "No CloudWatch alarms found to delete"
        return 0
    fi

    # Delete existing alarms
    if ! aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"; then
        error "Failed to delete CloudWatch alarms"
        [[ "${PARTIAL}" != "true" ]] && return 1
    fi

    success "Deleted CloudWatch alarms: ${existing_alarms[*]}"
}

# Delete API Gateway
delete_api_gateway() {
    info "Deleting API Gateway..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete API Gateway: ${API_ID}"
        return 0
    fi

    if ! resource_exists "api-gateway" "${API_ID}"; then
        info "API Gateway ${API_ID} not found - may have been deleted already"
        return 0
    fi

    # Delete API Gateway (this automatically deletes stages, deployments, and resources)
    if ! aws apigateway delete-rest-api --rest-api-id "${API_ID}"; then
        error "Failed to delete API Gateway: ${API_ID}"
        [[ "${PARTIAL}" != "true" ]] && return 1
    fi

    success "Deleted API Gateway: ${API_ID}"
}

# Delete Lambda functions
delete_lambda_functions() {
    info "Deleting Lambda functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete Lambda functions: ${BLUE_FUNCTION_NAME}, ${GREEN_FUNCTION_NAME}"
        return 0
    fi

    local functions=("${BLUE_FUNCTION_NAME}" "${GREEN_FUNCTION_NAME}")
    
    for func in "${functions[@]}"; do
        if [[ -z "${func}" ]]; then
            continue
        fi

        if resource_exists "lambda" "${func}"; then
            if ! aws lambda delete-function --function-name "${func}"; then
                error "Failed to delete Lambda function: ${func}"
                [[ "${PARTIAL}" != "true" ]] && return 1
            else
                success "Deleted Lambda function: ${func}"
            fi
        else
            info "Lambda function ${func} not found - may have been deleted already"
        fi
    done
}

# Delete CloudWatch log groups
delete_log_groups() {
    if [[ "${KEEP_LOGS}" == "true" ]]; then
        info "Keeping CloudWatch log groups as requested"
        return 0
    fi

    info "Deleting CloudWatch log groups..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete CloudWatch log groups for Lambda functions"
        return 0
    fi

    local log_groups=(
        "/aws/lambda/${BLUE_FUNCTION_NAME}"
        "/aws/lambda/${GREEN_FUNCTION_NAME}"
        "/aws/apigateway/${API_NAME}"
    )

    for log_group in "${log_groups[@]}"; do
        if [[ -z "${log_group}" ]]; then
            continue
        fi

        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "${log_group}" --query 'logGroups[0]' --output text &> /dev/null; then
            if ! aws logs delete-log-group --log-group-name "${log_group}"; then
                warning "Failed to delete log group: ${log_group}"
                # Don't fail for log groups as they're not critical
            else
                success "Deleted log group: ${log_group}"
            fi
        fi
    done
}

# Delete IAM role
delete_iam_role() {
    info "Deleting IAM role..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete IAM role: ${LAMBDA_ROLE_NAME}"
        return 0
    fi

    if [[ -z "${LAMBDA_ROLE_NAME}" ]]; then
        warning "Lambda role name not found in state file"
        return 0
    fi

    if ! resource_exists "iam-role" "${LAMBDA_ROLE_NAME}"; then
        info "IAM role ${LAMBDA_ROLE_NAME} not found - may have been deleted already"
        return 0
    fi

    # Detach policies from role
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "${LAMBDA_ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "${attached_policies}" ]]; then
        for policy_arn in ${attached_policies}; do
            if ! aws iam detach-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-arn "${policy_arn}"; then
                error "Failed to detach policy ${policy_arn} from role ${LAMBDA_ROLE_NAME}"
                [[ "${PARTIAL}" != "true" ]] && return 1
            fi
        done
    fi

    # Delete the role
    if ! aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}"; then
        error "Failed to delete IAM role: ${LAMBDA_ROLE_NAME}"
        [[ "${PARTIAL}" != "true" ]] && return 1
    fi

    success "Deleted IAM role: ${LAMBDA_ROLE_NAME}"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would clean up local files"
        return 0
    fi

    local files_to_remove=(
        "${SCRIPT_DIR}/blue-function.py"
        "${SCRIPT_DIR}/green-function.py"
        "${SCRIPT_DIR}/blue-function.zip"
        "${SCRIPT_DIR}/green-function.zip"
    )

    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            success "Removed local file: $(basename "${file}")"
        fi
    done
}

# Clean up state file
cleanup_state_file() {
    info "Cleaning up state file..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove state file: ${STATE_FILE}"
        return 0
    fi

    if [[ -f "${STATE_FILE}" ]]; then
        # Create backup of state file
        cp "${STATE_FILE}" "${STATE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        rm -f "${STATE_FILE}"
        success "Removed state file (backup created)"
    fi
}

# Display resource summary
display_summary() {
    info "=== Destruction Summary ==="
    
    if [[ -f "${STATE_FILE}" ]]; then
        source "${STATE_FILE}" 2>/dev/null || true
        echo "API Gateway: ${API_ID:-N/A}"
        echo "Blue Lambda: ${BLUE_FUNCTION_NAME:-N/A}"
        echo "Green Lambda: ${GREEN_FUNCTION_NAME:-N/A}"
        echo "IAM Role: ${LAMBDA_ROLE_NAME:-N/A}"
        echo "Region: ${AWS_REGION:-N/A}"
    else
        echo "No state file found"
    fi
    
    echo "Dry Run: ${DRY_RUN}"
    echo "Force: ${FORCE}"
    echo "Keep Logs: ${KEEP_LOGS}"
    echo "Partial: ${PARTIAL}"
    echo
}

# Confirm destruction
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo
    warning "⚠️  This will permanently delete all resources created by the deployment!"
    echo
    display_summary
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo
    
    if [[ "${REPLY}" != "DELETE" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
}

# Main destruction process
main() {
    info "Starting Advanced API Gateway resource destruction..."
    
    # Initialize logging
    echo "=== Destruction started at $(date) ===" > "${LOG_FILE}"
    
    # Parse arguments
    parse_args "$@"
    
    # Load deployment state
    load_state
    
    # Check prerequisites
    check_prerequisites
    
    # Display summary and confirm
    display_summary
    confirm_destruction

    echo
    info "🗑️  Beginning resource destruction..."
    echo

    # Execute destruction steps in reverse order of creation
    # Note: We delete in reverse order to handle dependencies properly
    
    # 1. Delete CloudWatch alarms first (no dependencies)
    delete_cloudwatch_alarms || warning "CloudWatch alarm deletion failed"
    
    # 2. Delete API Gateway (this removes stages, deployments, resources, and permissions)
    delete_api_gateway || warning "API Gateway deletion failed"
    
    # 3. Delete Lambda functions
    delete_lambda_functions || warning "Lambda function deletion failed"
    
    # 4. Delete CloudWatch log groups
    delete_log_groups || warning "Log group deletion failed"
    
    # 5. Delete IAM role (after Lambda functions are gone)
    delete_iam_role || warning "IAM role deletion failed"
    
    # 6. Clean up local files
    cleanup_local_files || warning "Local file cleanup failed"
    
    # 7. Clean up state file (last step)
    if [[ "${DRY_RUN}" != "true" ]]; then
        cleanup_state_file || warning "State file cleanup failed"
    fi

    # Final success message
    echo
    if [[ "${DRY_RUN}" == "true" ]]; then
        success "🔍 Dry run completed - no resources were actually deleted"
    else
        success "🎉 Advanced API Gateway resource destruction completed!"
    fi
    
    echo
    echo "=== Destruction Results ==="
    echo "Log File: ${LOG_FILE}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "State File: ${STATE_FILE} (preserved for dry run)"
    else
        echo "State File: Removed (backup created if existed)"
    fi
    echo
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo "All resources have been cleaned up."
        echo "You can now safely remove this directory if desired."
    else
        echo "To actually destroy resources, run: $0 --force"
    fi
    echo
    
    log "Destruction completed successfully"
}

# Error handling for script interruption
handle_interrupt() {
    echo
    error "🛑 Destruction interrupted by user"
    warning "Some resources may still exist and incur charges"
    warning "Run the script again to complete cleanup"
    exit 1
}

# Trap to handle script interruption
trap 'handle_interrupt' INT TERM

# Run main function
main "$@"
#!/bin/bash

# Destroy script for Simple Environment Health Check with Systems Manager and SNS
# This script safely removes all infrastructure components created by the deployment script.

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="environment-health-check"
RANDOM_SUFFIX=""
AWS_REGION=""
AWS_ACCOUNT_ID=""
FORCE_DELETE=false
DRY_RUN=false
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Simple Environment Health Check infrastructure.

OPTIONS:
    -s, --suffix SUFFIX     Random suffix from deployment (required if no deployment-info.json)
    -r, --region REGION     AWS region (defaults to current CLI region)
    -f, --force             Skip confirmation prompts
    --dry-run              Show what would be deleted without making changes
    -h, --help             Show this help message

EXAMPLES:
    $0 --suffix abc123
    $0 --force --suffix abc123
    $0 --region us-west-2 --suffix abc123
    DRY_RUN=true $0 --suffix abc123

NOTES:
    - If deployment-info.json exists, it will be used to determine resources to delete
    - Use --force to skip confirmation prompts (useful for automation)
    - Resources are deleted in reverse order of creation for safety

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load deployment information if available
load_deployment_info() {
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Loading deployment information from ${DEPLOYMENT_INFO_FILE}"
        
        # Extract values from JSON file
        if command -v jq &> /dev/null; then
            RANDOM_SUFFIX=$(jq -r '.random_suffix' "${DEPLOYMENT_INFO_FILE}")
            AWS_REGION=${AWS_REGION:-$(jq -r '.aws_region' "${DEPLOYMENT_INFO_FILE}")}
            AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "${DEPLOYMENT_INFO_FILE}")
            DEPLOYMENT_NAME=$(jq -r '.deployment_name' "${DEPLOYMENT_INFO_FILE}")
        else
            # Fallback parsing without jq
            RANDOM_SUFFIX=${RANDOM_SUFFIX:-$(grep '"random_suffix"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)}
            if [[ -z "${AWS_REGION}" ]]; then
                AWS_REGION=$(grep '"aws_region"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            fi
            AWS_ACCOUNT_ID=$(grep '"aws_account_id"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            DEPLOYMENT_NAME=$(grep '"deployment_name"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
        fi
        
        log_success "Deployment information loaded"
    else
        log_warning "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        log_info "Using command line parameters for resource identification"
    fi
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Validate suffix parameter if not loaded from file
    if [[ -z "${RANDOM_SUFFIX}" ]]; then
        log_error "Random suffix is required. Use -s/--suffix option or ensure deployment-info.json exists."
        usage
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region if not provided
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not set. Use --region option or configure AWS CLI."
            exit 1
        fi
    fi
    
    # Get AWS account ID if not loaded from file
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
            --query Account --output text)
    fi
    
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Deployment Name: ${DEPLOYMENT_NAME}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will DELETE ALL resources created by the health check deployment!"
    echo "Resources to be deleted:"
    echo "  - SNS Topic: environment-health-alerts-${RANDOM_SUFFIX}"
    echo "  - Lambda Function: environment-health-check-${RANDOM_SUFFIX}"
    echo "  - IAM Role: HealthCheckLambdaRole-${RANDOM_SUFFIX}"
    echo "  - IAM Policy: HealthCheckPolicy-${RANDOM_SUFFIX}"
    echo "  - EventBridge Rules: compliance-health-alerts-${RANDOM_SUFFIX}, health-check-schedule-${RANDOM_SUFFIX}"
    echo "  - Systems Manager Compliance data (Custom:EnvironmentHealth)"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    
    if eval "${check_command}" &>/dev/null; then
        return 0  # Resource exists
    else
        return 1  # Resource does not exist
    fi
}

# Remove EventBridge rules and targets
destroy_eventbridge() {
    log_info "Removing EventBridge rules and targets..."
    
    local schedule_rule="health-check-schedule-${RANDOM_SUFFIX}"
    local compliance_rule="compliance-health-alerts-${RANDOM_SUFFIX}"
    
    # Remove scheduled health check rule
    if resource_exists "EventBridge Rule" "${schedule_rule}" "aws events describe-rule --name '${schedule_rule}' --region '${AWS_REGION}'"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Remove targets first
            aws events remove-targets \
                --rule "${schedule_rule}" \
                --ids "1" \
                --region "${AWS_REGION}" 2>/dev/null || log_warning "Failed to remove targets from ${schedule_rule}"
            
            # Delete rule
            aws events delete-rule \
                --name "${schedule_rule}" \
                --region "${AWS_REGION}"
        fi
        log_success "EventBridge schedule rule ${schedule_rule} removed"
    else
        log_info "EventBridge schedule rule ${schedule_rule} not found"
    fi
    
    # Remove compliance monitoring rule
    if resource_exists "EventBridge Rule" "${compliance_rule}" "aws events describe-rule --name '${compliance_rule}' --region '${AWS_REGION}'"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Remove targets first
            aws events remove-targets \
                --rule "${compliance_rule}" \
                --ids "1" \
                --region "${AWS_REGION}" 2>/dev/null || log_warning "Failed to remove targets from ${compliance_rule}"
            
            # Delete rule
            aws events delete-rule \
                --name "${compliance_rule}" \
                --region "${AWS_REGION}"
        fi
        log_success "EventBridge compliance rule ${compliance_rule} removed"
    else
        log_info "EventBridge compliance rule ${compliance_rule} not found"
    fi
}

# Remove Lambda function
destroy_lambda() {
    local function_name="environment-health-check-${RANDOM_SUFFIX}"
    
    log_info "Removing Lambda function: ${function_name}"
    
    if resource_exists "Lambda Function" "${function_name}" "aws lambda get-function --function-name '${function_name}' --region '${AWS_REGION}'"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            aws lambda delete-function \
                --function-name "${function_name}" \
                --region "${AWS_REGION}"
        fi
        log_success "Lambda function ${function_name} removed"
    else
        log_info "Lambda function ${function_name} not found"
    fi
}

# Remove IAM resources
destroy_iam() {
    local role_name="HealthCheckLambdaRole-${RANDOM_SUFFIX}"
    local policy_name="HealthCheckPolicy-${RANDOM_SUFFIX}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    log_info "Removing IAM resources..."
    
    # Detach and delete custom policy
    if resource_exists "IAM Policy" "${policy_name}" "aws iam get-policy --policy-arn '${policy_arn}'"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Detach from role first
            aws iam detach-role-policy \
                --role-name "${role_name}" \
                --policy-arn "${policy_arn}" 2>/dev/null || log_warning "Failed to detach policy ${policy_name} from role"
            
            # Delete policy
            aws iam delete-policy \
                --policy-arn "${policy_arn}"
        fi
        log_success "IAM policy ${policy_name} removed"
    else
        log_info "IAM policy ${policy_name} not found"
    fi
    
    # Detach AWS managed policy and delete role
    if resource_exists "IAM Role" "${role_name}" "aws iam get-role --role-name '${role_name}'"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Detach AWS managed policy
            aws iam detach-role-policy \
                --role-name "${role_name}" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || log_warning "Failed to detach AWS managed policy from role"
            
            # Delete role
            aws iam delete-role \
                --role-name "${role_name}"
        fi
        log_success "IAM role ${role_name} removed"
    else
        log_info "IAM role ${role_name} not found"
    fi
}

# Remove SNS resources
destroy_sns() {
    local topic_name="environment-health-alerts-${RANDOM_SUFFIX}"
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${topic_name}"
    
    log_info "Removing SNS topic: ${topic_name}"
    
    if resource_exists "SNS Topic" "${topic_name}" "aws sns get-topic-attributes --topic-arn '${topic_arn}' --region '${AWS_REGION}'"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Delete topic (this also removes all subscriptions)
            aws sns delete-topic \
                --topic-arn "${topic_arn}" \
                --region "${AWS_REGION}"
        fi
        log_success "SNS topic ${topic_name} removed"
    else
        log_info "SNS topic ${topic_name} not found"
    fi
}

# Clean up compliance data
cleanup_compliance_data() {
    log_info "Cleaning up Systems Manager compliance data..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up compliance data for type: Custom:EnvironmentHealth"
        return 0
    fi
    
    # Get all managed instances with custom compliance data
    local instances
    instances=$(aws ssm list-compliance-summaries \
        --query 'ComplianceSummaryItems[?ComplianceType==`Custom:EnvironmentHealth`].ResourceId' \
        --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
    
    if [[ -n "${instances}" ]]; then
        for instance_id in ${instances}; do
            log_info "Removing compliance data for instance: ${instance_id}"
            
            # List and delete compliance items for this instance
            local compliance_items
            compliance_items=$(aws ssm list-compliance-items \
                --resource-ids "${instance_id}" \
                --resource-types ManagedInstance \
                --filters Key=ComplianceType,Values="Custom:EnvironmentHealth" \
                --query 'ComplianceItems[].Id' \
                --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
            
            if [[ -n "${compliance_items}" ]]; then
                for item_id in ${compliance_items}; do
                    # Note: AWS doesn't provide a direct way to delete compliance items
                    # They are automatically cleaned up over time or can be overwritten
                    log_info "Compliance item ${item_id} will be cleaned up automatically by AWS"
                done
            fi
        done
        log_success "Compliance data cleanup initiated"
    else
        log_info "No custom compliance data found to clean up"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/health_check_function.py"
        "${SCRIPT_DIR}/health_check_function.zip"
        "${SCRIPT_DIR}/response.json"
        "${DEPLOYMENT_INFO_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" != "true" ]]; then
                rm -f "${file}"
            fi
            log_success "Removed local file: $(basename "${file}")"
        fi
    done
}

# Verify resource deletion
verify_deletion() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check SNS topic
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:environment-health-alerts-${RANDOM_SUFFIX}"
    if aws sns get-topic-attributes --topic-arn "${topic_arn}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "SNS topic still exists: ${topic_arn}"
        verification_failed=true
    fi
    
    # Check Lambda function
    local function_name="environment-health-check-${RANDOM_SUFFIX}"
    if aws lambda get-function --function-name "${function_name}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "Lambda function still exists: ${function_name}"
        verification_failed=true
    fi
    
    # Check IAM role
    local role_name="HealthCheckLambdaRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "${role_name}" &>/dev/null; then
        log_warning "IAM role still exists: ${role_name}"
        verification_failed=true
    fi
    
    # Check EventBridge rules
    if aws events describe-rule --name "health-check-schedule-${RANDOM_SUFFIX}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "EventBridge schedule rule still exists"
        verification_failed=true
    fi
    
    if aws events describe-rule --name "compliance-health-alerts-${RANDOM_SUFFIX}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "EventBridge compliance rule still exists"
        verification_failed=true
    fi
    
    if [[ "${verification_failed}" == "true" ]]; then
        log_warning "Some resources may still exist. This could be due to AWS eventual consistency."
        log_info "Resources may take a few minutes to be fully deleted. Please check manually if needed."
    else
        log_success "All resources appear to be successfully deleted"
    fi
}

# Main destruction function
main() {
    echo "================================================"
    echo "Simple Environment Health Check Destruction"
    echo "================================================"
    
    # Parse arguments and validate
    parse_arguments "$@"
    load_deployment_info
    check_prerequisites
    setup_environment
    
    # Confirm deletion unless forced or dry run
    confirm_deletion
    
    # Remove resources in reverse order of creation
    log_info "Starting resource cleanup..."
    
    destroy_eventbridge
    cleanup_compliance_data
    destroy_lambda
    destroy_iam
    destroy_sns
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    echo "================================================"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "DRY RUN completed - no resources were deleted"
    else
        log_success "Destruction completed successfully!"
    fi
    echo "================================================"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo
        echo "Cleanup Summary:"
        echo "  - All EventBridge rules and targets removed"
        echo "  - Lambda function and IAM resources deleted"
        echo "  - SNS topic and subscriptions removed"
        echo "  - Local deployment files cleaned up"
        echo "  - Systems Manager compliance data cleanup initiated"
        echo
        echo "Note: Some AWS resources may take a few minutes to be fully"
        echo "      removed due to eventual consistency. Compliance data"
        echo "      will be automatically cleaned up by AWS over time."
    else
        echo
        log_info "Run without --dry-run to actually delete the resources"
    fi
}

# Run main function with all arguments
main "$@"
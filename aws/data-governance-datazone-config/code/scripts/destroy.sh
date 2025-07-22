#!/bin/bash

# Data Governance Pipelines with DataZone
# Cleanup/Destroy Script
# Recipe ID: 4e7b2c1a

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
ERROR_LOG="${SCRIPT_DIR}/cleanup_errors.log"
STATE_FILE="${SCRIPT_DIR}/deployment_state.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${ERROR_LOG}" | tee -a "${LOG_FILE}"
}

# Error handling (continue on error for cleanup)
handle_error() {
    local line_number=$1
    local error_code=$2
    log_warning "Non-fatal error occurred at line ${line_number}: exit code ${error_code}"
}

trap 'handle_error ${LINENO} $?' ERR

# Initialize logging
echo "Cleanup started at $(date)" > "${LOG_FILE}"
echo "Error log for cleanup at $(date)" > "${ERROR_LOG}"

log_info "Starting cleanup of Data Governance Pipeline with Amazon DataZone and AWS Config"

# Function to prompt for confirmation
confirm_destruction() {
    local resource_type="$1"
    local force="${2:-false}"
    
    if [[ "${force}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}WARNING: You are about to delete ${resource_type}${NC}"
    echo "This action cannot be undone."
    read -p "Do you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "User cancelled ${resource_type} deletion"
        return 1
    fi
    return 0
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_warning "No deployment state file found at ${STATE_FILE}"
        log_warning "Will attempt cleanup using AWS CLI discovery"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required to parse state file but not found"
        log_error "Please install jq or manually provide resource identifiers"
        exit 1
    fi
    
    # Load state variables
    export AWS_REGION=$(jq -r '.aws_region // empty' "${STATE_FILE}")
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' "${STATE_FILE}")
    export RANDOM_SUFFIX=$(jq -r '.random_suffix // empty' "${STATE_FILE}")
    export DATAZONE_DOMAIN_NAME=$(jq -r '.datazone_domain_name // empty' "${STATE_FILE}")
    export DATAZONE_DOMAIN_ID=$(jq -r '.datazone_domain_id // empty' "${STATE_FILE}")
    export DATAZONE_PROJECT_ID=$(jq -r '.datazone_project_id // empty' "${STATE_FILE}")
    export CONFIG_ROLE_NAME=$(jq -r '.config_role_name // empty' "${STATE_FILE}")
    export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name // empty' "${STATE_FILE}")
    export LAMBDA_ROLE_NAME=$(jq -r '.lambda_role_name // empty' "${STATE_FILE}")
    export EVENT_RULE_NAME=$(jq -r '.event_rule_name // empty' "${STATE_FILE}")
    export CONFIG_BUCKET=$(jq -r '.config_bucket // empty' "${STATE_FILE}")
    export GOVERNANCE_TOPIC_ARN=$(jq -r '.governance_topic_arn // empty' "${STATE_FILE}")
    
    log_success "Deployment state loaded successfully"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Resource Suffix: ${RANDOM_SUFFIX}"
    
    return 0
}

# Fallback resource discovery
discover_resources() {
    log_info "Attempting to discover resources..."
    
    # Get current AWS region and account
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        log_error "Unable to determine AWS account ID. Check AWS credentials."
        exit 1
    fi
    
    log_info "Discovered AWS Region: ${AWS_REGION}"
    log_info "Discovered AWS Account ID: ${AWS_ACCOUNT_ID}"
    
    # Attempt to find DataZone domains
    if command -v aws datazone &> /dev/null; then
        log_info "Searching for DataZone domains..."
        aws datazone list-domains --query 'items[?contains(name, `governance-domain`)]' \
            --output table 2>/dev/null || log_warning "Unable to list DataZone domains"
    fi
    
    # Find Lambda functions
    log_info "Searching for governance Lambda functions..."
    aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `data-governance-processor`)].{Name:FunctionName,Runtime:Runtime}' \
        --output table 2>/dev/null || log_warning "Unable to list Lambda functions"
}

# Remove DataZone resources
cleanup_datazone() {
    log_info "Cleaning up DataZone resources..."
    
    if [[ -z "${DATAZONE_DOMAIN_ID}" ]] && [[ -z "${DATAZONE_PROJECT_ID}" ]]; then
        log_warning "No DataZone identifiers found, skipping DataZone cleanup"
        return 0
    fi
    
    if ! confirm_destruction "DataZone domain and project" "${FORCE_CLEANUP:-false}"; then
        return 0
    fi
    
    # Delete DataZone project if exists
    if [[ -n "${DATAZONE_PROJECT_ID}" ]] && [[ -n "${DATAZONE_DOMAIN_ID}" ]]; then
        log_info "Deleting DataZone project: ${DATAZONE_PROJECT_ID}"
        if aws datazone delete-project \
            --domain-identifier "${DATAZONE_DOMAIN_ID}" \
            --identifier "${DATAZONE_PROJECT_ID}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
            log_success "DataZone project deletion initiated"
            sleep 30  # Wait for project deletion
        else
            log_warning "Failed to delete DataZone project or project doesn't exist"
        fi
    fi
    
    # Delete DataZone domain if exists
    if [[ -n "${DATAZONE_DOMAIN_ID}" ]]; then
        log_info "Deleting DataZone domain: ${DATAZONE_DOMAIN_ID}"
        if aws datazone delete-domain \
            --identifier "${DATAZONE_DOMAIN_ID}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
            log_success "DataZone domain deletion initiated"
            
            # Wait for domain deletion with timeout
            local max_attempts=30
            local attempt=1
            
            while [[ ${attempt} -le ${max_attempts} ]]; do
                if ! aws datazone get-domain \
                    --identifier "${DATAZONE_DOMAIN_ID}" &> /dev/null; then
                    log_success "DataZone domain deleted successfully"
                    break
                fi
                
                log_info "Waiting for domain deletion... (attempt ${attempt}/${max_attempts})"
                sleep 30
                ((attempt++))
            done
            
            if [[ ${attempt} -gt ${max_attempts} ]]; then
                log_warning "Timeout waiting for domain deletion, but deletion was initiated"
            fi
        else
            log_warning "Failed to delete DataZone domain or domain doesn't exist"
        fi
    fi
}

# Remove monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring and alerting resources..."
    
    # Delete CloudWatch alarms
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        local alarms=(
            "DataGovernanceErrors-${RANDOM_SUFFIX}"
            "DataGovernanceDuration-${RANDOM_SUFFIX}"
            "DataGovernanceCompliance-${RANDOM_SUFFIX}"
        )
        
        for alarm_name in "${alarms[@]}"; do
            if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" \
                --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${alarm_name}"; then
                log_info "Deleting CloudWatch alarm: ${alarm_name}"
                aws cloudwatch delete-alarms --alarm-names "${alarm_name}" \
                    >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
                log_success "Deleted CloudWatch alarm: ${alarm_name}"
            else
                log_warning "CloudWatch alarm ${alarm_name} not found"
            fi
        done
    fi
    
    # Delete SNS topic
    if [[ -n "${GOVERNANCE_TOPIC_ARN}" ]]; then
        log_info "Deleting SNS topic: ${GOVERNANCE_TOPIC_ARN}"
        if aws sns delete-topic --topic-arn "${GOVERNANCE_TOPIC_ARN}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
            log_success "SNS topic deleted: ${GOVERNANCE_TOPIC_ARN}"
        else
            log_warning "Failed to delete SNS topic or topic doesn't exist"
        fi
    fi
}

# Remove automation resources
cleanup_automation() {
    log_info "Cleaning up automation resources..."
    
    if [[ -z "${LAMBDA_FUNCTION_NAME}" ]] && [[ -z "${EVENT_RULE_NAME}" ]]; then
        log_warning "No automation resource identifiers found"
        return 0
    fi
    
    # Remove Lambda permission for EventBridge
    if [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        log_info "Removing EventBridge permission from Lambda function"
        aws lambda remove-permission \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --statement-id "governance-eventbridge-invoke" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Permission not found or already removed"
    fi
    
    # Delete EventBridge rule targets and rule
    if [[ -n "${EVENT_RULE_NAME}" ]]; then
        # Remove targets first
        log_info "Removing EventBridge rule targets"
        aws events remove-targets \
            --rule "${EVENT_RULE_NAME}" \
            --ids 1 \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Targets not found or already removed"
        
        # Delete the rule
        log_info "Deleting EventBridge rule: ${EVENT_RULE_NAME}"
        if aws events delete-rule --name "${EVENT_RULE_NAME}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
            log_success "EventBridge rule deleted: ${EVENT_RULE_NAME}"
        else
            log_warning "Failed to delete EventBridge rule or rule doesn't exist"
        fi
    fi
    
    # Delete Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
        if aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
            log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
        else
            log_warning "Failed to delete Lambda function or function doesn't exist"
        fi
    fi
}

# Remove AWS Config resources
cleanup_config() {
    log_info "Cleaning up AWS Config resources..."
    
    if ! confirm_destruction "AWS Config recorder and rules" "${FORCE_CLEANUP:-false}"; then
        return 0
    fi
    
    # Stop configuration recorder
    log_info "Stopping AWS Config configuration recorder"
    aws configservice stop-configuration-recorder \
        --configuration-recorder-name default \
        >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Configuration recorder not found or already stopped"
    
    # Delete Config rules
    local config_rules=(
        "s3-bucket-server-side-encryption-enabled"
        "rds-storage-encrypted"
        "s3-bucket-public-read-prohibited"
    )
    
    for rule_name in "${config_rules[@]}"; do
        log_info "Deleting Config rule: ${rule_name}"
        if aws configservice delete-config-rule \
            --config-rule-name "${rule_name}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
            log_success "Config rule deleted: ${rule_name}"
        else
            log_warning "Config rule ${rule_name} not found or already deleted"
        fi
    done
    
    # Delete delivery channel and recorder
    log_info "Deleting Config delivery channel"
    aws configservice delete-delivery-channel \
        --delivery-channel-name default \
        >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Delivery channel not found"
    
    log_info "Deleting Config configuration recorder"
    aws configservice delete-configuration-recorder \
        --configuration-recorder-name default \
        >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Configuration recorder not found"
    
    # Remove Config S3 bucket
    if [[ -n "${CONFIG_BUCKET}" ]]; then
        if aws s3api head-bucket --bucket "${CONFIG_BUCKET}" &> /dev/null; then
            log_info "Emptying and deleting Config S3 bucket: ${CONFIG_BUCKET}"
            
            # Empty bucket first
            if aws s3 rm "s3://${CONFIG_BUCKET}" --recursive \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
                log_success "Config bucket emptied: ${CONFIG_BUCKET}"
            else
                log_warning "Failed to empty Config bucket or bucket already empty"
            fi
            
            # Delete bucket
            if aws s3 rb "s3://${CONFIG_BUCKET}" \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
                log_success "Config bucket deleted: ${CONFIG_BUCKET}"
            else
                log_warning "Failed to delete Config bucket"
            fi
        else
            log_warning "Config bucket ${CONFIG_BUCKET} not found"
        fi
    fi
}

# Remove IAM roles
cleanup_iam_roles() {
    log_info "Cleaning up IAM roles..."
    
    # Remove Lambda role
    if [[ -n "${LAMBDA_ROLE_NAME}" ]]; then
        if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
            log_info "Removing Lambda role policies and deleting role: ${LAMBDA_ROLE_NAME}"
            
            # Remove inline policies
            aws iam delete-role-policy \
                --role-name "${LAMBDA_ROLE_NAME}" \
                --policy-name DataGovernancePolicy \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Inline policy not found"
            
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name "${LAMBDA_ROLE_NAME}" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Managed policy not attached"
            
            # Delete role
            if aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
                log_success "Lambda role deleted: ${LAMBDA_ROLE_NAME}"
            else
                log_warning "Failed to delete Lambda role"
            fi
        else
            log_warning "Lambda role ${LAMBDA_ROLE_NAME} not found"
        fi
    fi
    
    # Remove Config role
    if [[ -n "${CONFIG_ROLE_NAME}" ]]; then
        if aws iam get-role --role-name "${CONFIG_ROLE_NAME}" &> /dev/null; then
            log_info "Removing Config role policies and deleting role: ${CONFIG_ROLE_NAME}"
            
            # Detach managed policy
            aws iam detach-role-policy \
                --role-name "${CONFIG_ROLE_NAME}" \
                --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || log_warning "Managed policy not attached"
            
            # Delete role
            if aws iam delete-role --role-name "${CONFIG_ROLE_NAME}" \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}"; then
                log_success "Config role deleted: ${CONFIG_ROLE_NAME}"
            else
                log_warning "Failed to delete Config role"
            fi
        else
            log_warning "Config role ${CONFIG_ROLE_NAME} not found"
        fi
    fi
}

# Clean up temporary files
cleanup_files() {
    log_info "Cleaning up temporary files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/governance_function.py"
        "${SCRIPT_DIR}/governance_function.zip"
        "${SCRIPT_DIR}/deployment_state.tmp"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed temporary file: $(basename "${file}")"
        fi
    done
}

# Validation of cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local remaining_resources=0
    
    # Check if DataZone domain still exists
    if [[ -n "${DATAZONE_DOMAIN_ID}" ]]; then
        if aws datazone get-domain --identifier "${DATAZONE_DOMAIN_ID}" &> /dev/null; then
            log_warning "DataZone domain still exists: ${DATAZONE_DOMAIN_ID}"
            ((remaining_resources++))
        else
            log_success "DataZone domain successfully removed"
        fi
    fi
    
    # Check if Lambda function still exists
    if [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
            log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((remaining_resources++))
        else
            log_success "Lambda function successfully removed"
        fi
    fi
    
    # Check if Config recorder still exists
    if aws configservice describe-configuration-recorders \
        --configuration-recorder-names default &> /dev/null; then
        log_warning "Config recorder still exists"
        ((remaining_resources++))
    else
        log_success "Config recorder successfully removed"
    fi
    
    # Check if EventBridge rule still exists
    if [[ -n "${EVENT_RULE_NAME}" ]]; then
        if aws events describe-rule --name "${EVENT_RULE_NAME}" &> /dev/null; then
            log_warning "EventBridge rule still exists: ${EVENT_RULE_NAME}"
            ((remaining_resources++))
        else
            log_success "EventBridge rule successfully removed"
        fi
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
        return 0
    else
        log_warning "Cleanup completed but ${remaining_resources} resources may still exist"
        return 1
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "================================"
    echo "Cleanup process completed"
    echo "Check logs for detailed results:"
    echo "  - General log: ${LOG_FILE}"
    echo "  - Error log: ${ERROR_LOG}"
    
    if [[ -f "${STATE_FILE}" ]]; then
        echo "  - State file: ${STATE_FILE} (preserved)"
    fi
    
    echo ""
    echo "Manual verification recommended:"
    echo "  - Check AWS DataZone console for remaining domains"
    echo "  - Check AWS Config console for remaining recorders"
    echo "  - Check Lambda console for remaining functions"
    echo "  - Check EventBridge console for remaining rules"
    echo "  - Check S3 console for remaining Config buckets"
    echo "  - Check IAM console for remaining roles"
    echo "================================"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_CLEANUP="true"
                log_info "Force cleanup mode enabled - skipping confirmations"
                shift
                ;;
            --keep-state)
                export KEEP_STATE="true"
                log_info "State file will be preserved"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force       Skip confirmation prompts"
                echo "  --keep-state  Preserve deployment state file"
                echo "  --help, -h    Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main cleanup execution
main() {
    parse_arguments "$@"
    
    log_info "Starting cleanup process..."
    
    # Try to load state, fallback to discovery if needed
    if ! load_deployment_state; then
        discover_resources
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Perform cleanup in reverse order of creation
    cleanup_datazone
    cleanup_monitoring
    cleanup_automation
    cleanup_config
    cleanup_iam_roles
    cleanup_files
    
    # Validate cleanup
    if validate_cleanup; then
        log_success "Cleanup completed successfully!"
    else
        log_warning "Cleanup completed with some warnings. Manual verification recommended."
    fi
    
    # Remove state file if not preserving
    if [[ "${KEEP_STATE:-false}" == "false" ]] && [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        log_info "Deployment state file removed"
    fi
    
    print_cleanup_summary
}

# Run main function with all arguments
main "$@"
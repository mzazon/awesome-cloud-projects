#!/bin/bash

# Enterprise API Integration with AgentCore Gateway - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# with proper confirmation prompts and error handling

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ${*}${NC}" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ ${*}${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  ${*}${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ${*}${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_warning "Some resources may still exist and require manual cleanup."
    exit 1
}

trap cleanup_on_error ERR

# Show usage information
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Safely remove Enterprise API Integration with AgentCore Gateway infrastructure.

OPTIONS:
    -h, --help                 Show this help message
    -r, --region REGION        AWS region (default: current configured region)
    -p, --project-name NAME    Project name to destroy (required if multiple exist)
    --list-projects           List all projects found in the region
    --force                   Skip confirmation prompts (DANGEROUS)
    --dry-run                 Show what would be deleted without executing
    --skip-validation         Skip prerequisite validation
    --verbose                 Enable verbose output

EXAMPLES:
    ${SCRIPT_NAME}                                    # Interactive destruction
    ${SCRIPT_NAME} --project-name api-integration-xyz # Destroy specific project
    ${SCRIPT_NAME} --list-projects                    # List available projects
    ${SCRIPT_NAME} --dry-run                          # Preview destruction
    ${SCRIPT_NAME} --force                            # Skip confirmations (DANGEROUS)

SAFETY FEATURES:
    - Requires explicit confirmation before deleting resources
    - Shows detailed preview of resources to be deleted
    - Creates backup of resource information before deletion
    - Validates resource dependencies before removal
    - Provides rollback information for accidental deletions

EOF
}

# Default configuration
DRY_RUN=false
FORCE=false
SKIP_VALIDATION=false
VERBOSE=false
PROJECT_NAME=""
AWS_REGION=""
LIST_PROJECTS=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --list-projects)
                LIST_PROJECTS=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validation functions
check_prerequisites() {
    if [[ "${SKIP_VALIDATION}" == "true" ]]; then
        log_warning "Skipping prerequisite validation"
        return 0
    fi

    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi

    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log "Setting up cleanup environment..."

    # Set AWS region
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not set. Use --region or configure AWS CLI."
            exit 1
        fi
    fi
    export AWS_REGION

    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    log_success "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
}

# List available projects
list_projects() {
    log "Scanning for Enterprise API Integration projects..."
    
    local projects_found=()
    
    # Look for Lambda functions with our naming pattern
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `api-transformer-`) || contains(FunctionName, `data-validator-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    # Extract project suffixes from function names
    for func in ${lambda_functions}; do
        if [[ "$func" =~ api-transformer-(.+)$ ]] || [[ "$func" =~ data-validator-(.+)$ ]]; then
            local suffix="${BASH_REMATCH[1]}"
            local project_name="api-integration-${suffix}"
            if [[ ! " ${projects_found[*]} " =~ " ${project_name} " ]]; then
                projects_found+=("${project_name}")
            fi
        fi
    done
    
    # Look for Step Functions state machines
    local state_machines
    state_machines=$(aws stepfunctions list-state-machines \
        --query 'stateMachines[?contains(name, `api-orchestrator-`)].name' \
        --output text 2>/dev/null || echo "")
    
    for sm in ${state_machines}; do
        if [[ "$sm" =~ api-orchestrator-(.+)$ ]]; then
            local suffix="${BASH_REMATCH[1]}"
            local project_name="api-integration-${suffix}"
            if [[ ! " ${projects_found[*]} " =~ " ${project_name} " ]]; then
                projects_found+=("${project_name}")
            fi
        fi
    done
    
    # Look for API Gateways
    local api_gateways
    api_gateways=$(aws apigateway get-rest-apis \
        --query 'items[?contains(name, `enterprise-api-integration-`)].name' \
        --output text 2>/dev/null || echo "")
    
    for api in ${api_gateways}; do
        if [[ "$api" =~ enterprise-api-integration-(.+)$ ]]; then
            local suffix="${BASH_REMATCH[1]}"
            local project_name="api-integration-${suffix}"
            if [[ ! " ${projects_found[*]} " =~ " ${project_name} " ]]; then
                projects_found+=("${project_name}")
            fi
        fi
    done
    
    if [[ ${#projects_found[@]} -eq 0 ]]; then
        log_warning "No Enterprise API Integration projects found in region ${AWS_REGION}"
        exit 0
    fi
    
    log "Found ${#projects_found[@]} project(s):"
    for project in "${projects_found[@]}"; do
        log "  - ${project}"
        
        # Show resources for each project
        local suffix="${project##*-}"
        show_project_resources "${suffix}" "  "
    done
    
    echo "${projects_found[@]}"
}

# Show resources for a specific project
show_project_resources() {
    local suffix="$1"
    local indent="${2:-}"
    
    echo "${indent}Resources:"
    
    # Lambda functions
    local transformer_name="api-transformer-${suffix}"
    local validator_name="data-validator-${suffix}"
    
    if aws lambda get-function --function-name "${transformer_name}" &> /dev/null; then
        echo "${indent}  ✓ Lambda: ${transformer_name}"
    fi
    
    if aws lambda get-function --function-name "${validator_name}" &> /dev/null; then
        echo "${indent}  ✓ Lambda: ${validator_name}"
    fi
    
    # Step Functions
    local state_machine_name="api-orchestrator-${suffix}"
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${state_machine_name}" \
        &> /dev/null; then
        echo "${indent}  ✓ Step Functions: ${state_machine_name}"
    fi
    
    # API Gateway
    local api_name="enterprise-api-integration-${suffix}"
    local api_id
    api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${api_name}'].id" --output text 2>/dev/null || echo "")
    if [[ -n "${api_id}" && "${api_id}" != "None" ]]; then
        echo "${indent}  ✓ API Gateway: ${api_name} (${api_id})"
    fi
    
    # IAM Roles
    local roles=("lambda-execution-role-${suffix}" "stepfunctions-execution-role-${suffix}" "apigateway-stepfunctions-role-${suffix}")
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "${role}" &> /dev/null; then
            echo "${indent}  ✓ IAM Role: ${role}"
        fi
    done
}

# Auto-detect project if not specified
auto_detect_project() {
    if [[ -n "${PROJECT_NAME}" ]]; then
        return 0
    fi
    
    log "Auto-detecting project..."
    
    local projects
    projects=($(list_projects))
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        log_error "No projects found to destroy"
        exit 1
    elif [[ ${#projects[@]} -eq 1 ]]; then
        PROJECT_NAME="${projects[0]}"
        log "Auto-detected project: ${PROJECT_NAME}"
    else
        log_error "Multiple projects found. Please specify which to destroy:"
        for project in "${projects[@]}"; do
            log "  - ${project}"
        done
        log ""
        log "Use: ${SCRIPT_NAME} --project-name <PROJECT_NAME>"
        exit 1
    fi
}

# Validate project exists
validate_project() {
    local suffix="${PROJECT_NAME##*-}"
    
    log "Validating project: ${PROJECT_NAME}"
    
    # Check if any resources exist for this project
    local resources_found=false
    
    # Check Lambda functions
    local transformer_name="api-transformer-${suffix}"
    local validator_name="data-validator-${suffix}"
    
    if aws lambda get-function --function-name "${transformer_name}" &> /dev/null; then
        resources_found=true
    fi
    
    if aws lambda get-function --function-name "${validator_name}" &> /dev/null; then
        resources_found=true
    fi
    
    # Check Step Functions
    local state_machine_name="api-orchestrator-${suffix}"
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${state_machine_name}" \
        &> /dev/null; then
        resources_found=true
    fi
    
    # Check API Gateway
    local api_name="enterprise-api-integration-${suffix}"
    local api_id
    api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${api_name}'].id" --output text 2>/dev/null || echo "")
    if [[ -n "${api_id}" && "${api_id}" != "None" ]]; then
        resources_found=true
    fi
    
    if [[ "${resources_found}" == "false" ]]; then
        log_error "No resources found for project: ${PROJECT_NAME}"
        log "Run '${SCRIPT_NAME} --list-projects' to see available projects"
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Show destruction preview
show_destruction_preview() {
    local suffix="${PROJECT_NAME##*-}"
    
    log ""
    log "🔥 DESTRUCTION PREVIEW"
    log "====================="
    log "Project: ${PROJECT_NAME}"
    log "Region: ${AWS_REGION}"
    log "Account: ${AWS_ACCOUNT_ID}"
    log ""
    log "The following resources will be PERMANENTLY DELETED:"
    log ""
    
    show_project_resources "${suffix}"
    
    log ""
    log "⚠️  WARNING: This action cannot be undone!"
    log "⚠️  All data and configurations will be lost!"
    log ""
}

# Confirm destruction
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    show_destruction_preview
    
    echo -n "Type 'DELETE' to confirm destruction: "
    read -r confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo -n "Are you absolutely sure? Type '${PROJECT_NAME}' to confirm: "
    read -r project_confirmation
    
    if [[ "${project_confirmation}" != "${PROJECT_NAME}" ]]; then
        log "Destruction cancelled - project name did not match"
        exit 0
    fi
    
    log_warning "Destruction confirmed - proceeding with cleanup"
}

# Backup resource information
backup_resources() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would backup resource information"
        return 0
    fi
    
    log "Creating resource backup..."
    
    local backup_file="${SCRIPT_DIR}/resource_backup_${PROJECT_NAME}_$(date +%Y%m%d_%H%M%S).json"
    local suffix="${PROJECT_NAME##*-}"
    
    local backup_data='{
        "backup_timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "project_name": "'${PROJECT_NAME}'",
        "aws_region": "'${AWS_REGION}'",
        "aws_account_id": "'${AWS_ACCOUNT_ID}'",
        "resources": {}
    }'
    
    # Backup Lambda functions
    local transformer_name="api-transformer-${suffix}"
    local validator_name="data-validator-${suffix}"
    
    for func_name in "${transformer_name}" "${validator_name}"; do
        if aws lambda get-function --function-name "${func_name}" &> /dev/null; then
            local func_config
            func_config=$(aws lambda get-function --function-name "${func_name}" 2>/dev/null || echo '{}')
            backup_data=$(echo "${backup_data}" | jq --argjson config "${func_config}" \
                '.resources.lambda_functions."'${func_name}'" = $config')
        fi
    done
    
    # Backup Step Functions
    local state_machine_name="api-orchestrator-${suffix}"
    local state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${state_machine_name}"
    if aws stepfunctions describe-state-machine --state-machine-arn "${state_machine_arn}" &> /dev/null; then
        local sm_config
        sm_config=$(aws stepfunctions describe-state-machine --state-machine-arn "${state_machine_arn}" 2>/dev/null || echo '{}')
        backup_data=$(echo "${backup_data}" | jq --argjson config "${sm_config}" \
            '.resources.step_functions."'${state_machine_name}'" = $config')
    fi
    
    # Backup API Gateway
    local api_name="enterprise-api-integration-${suffix}"
    local api_id
    api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${api_name}'].id" --output text 2>/dev/null || echo "")
    if [[ -n "${api_id}" && "${api_id}" != "None" ]]; then
        local api_config
        api_config=$(aws apigateway get-rest-api --rest-api-id "${api_id}" 2>/dev/null || echo '{}')
        backup_data=$(echo "${backup_data}" | jq --argjson config "${api_config}" \
            '.resources.api_gateway."'${api_name}'" = $config')
    fi
    
    # Backup IAM Roles
    local roles=("lambda-execution-role-${suffix}" "stepfunctions-execution-role-${suffix}" "apigateway-stepfunctions-role-${suffix}")
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "${role}" &> /dev/null; then
            local role_config
            role_config=$(aws iam get-role --role-name "${role}" 2>/dev/null || echo '{}')
            backup_data=$(echo "${backup_data}" | jq --argjson config "${role_config}" \
                '.resources.iam_roles."'${role}'" = $config')
        fi
    done
    
    # Save backup
    echo "${backup_data}" | jq '.' > "${backup_file}"
    log_success "Resource backup created: ${backup_file}"
}

# Remove API Gateway
remove_api_gateway() {
    local suffix="${PROJECT_NAME##*-}"
    local api_name="enterprise-api-integration-${suffix}"
    
    log "Removing API Gateway..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove API Gateway ${api_name}"
        return 0
    fi
    
    local api_id
    api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${api_name}'].id" --output text 2>/dev/null || echo "")
    
    if [[ -n "${api_id}" && "${api_id}" != "None" ]]; then
        log "Deleting API Gateway: ${api_name} (${api_id})"
        
        if aws apigateway delete-rest-api --rest-api-id "${api_id}"; then
            log_success "API Gateway deleted successfully"
        else
            log_error "Failed to delete API Gateway"
        fi
    else
        log_warning "API Gateway ${api_name} not found"
    fi
}

# Remove Step Functions
remove_step_functions() {
    local suffix="${PROJECT_NAME##*-}"
    local state_machine_name="api-orchestrator-${suffix}"
    local state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${state_machine_name}"
    
    log "Removing Step Functions state machine..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove Step Functions state machine ${state_machine_name}"
        return 0
    fi
    
    if aws stepfunctions describe-state-machine --state-machine-arn "${state_machine_arn}" &> /dev/null; then
        log "Deleting Step Functions state machine: ${state_machine_name}"
        
        # First, stop any running executions
        local running_executions
        running_executions=$(aws stepfunctions list-executions \
            --state-machine-arn "${state_machine_arn}" \
            --status-filter RUNNING \
            --query 'executions[].executionArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "${running_executions}" ]]; then
            log_warning "Stopping running executions..."
            for execution_arn in ${running_executions}; do
                aws stepfunctions stop-execution --execution-arn "${execution_arn}" || true
                log "Stopped execution: ${execution_arn}"
            done
            
            # Wait a moment for executions to stop
            sleep 5
        fi
        
        if aws stepfunctions delete-state-machine --state-machine-arn "${state_machine_arn}"; then
            log_success "Step Functions state machine deleted successfully"
        else
            log_error "Failed to delete Step Functions state machine"
        fi
    else
        log_warning "Step Functions state machine ${state_machine_name} not found"
    fi
}

# Remove Lambda functions
remove_lambda_functions() {
    local suffix="${PROJECT_NAME##*-}"
    local transformer_name="api-transformer-${suffix}"
    local validator_name="data-validator-${suffix}"
    
    log "Removing Lambda functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove Lambda functions ${transformer_name} and ${validator_name}"
        return 0
    fi
    
    # Remove transformer function
    if aws lambda get-function --function-name "${transformer_name}" &> /dev/null; then
        log "Deleting Lambda function: ${transformer_name}"
        
        if aws lambda delete-function --function-name "${transformer_name}"; then
            log_success "Lambda function ${transformer_name} deleted successfully"
        else
            log_error "Failed to delete Lambda function ${transformer_name}"
        fi
    else
        log_warning "Lambda function ${transformer_name} not found"
    fi
    
    # Remove validator function
    if aws lambda get-function --function-name "${validator_name}" &> /dev/null; then
        log "Deleting Lambda function: ${validator_name}"
        
        if aws lambda delete-function --function-name "${validator_name}"; then
            log_success "Lambda function ${validator_name} deleted successfully"
        else
            log_error "Failed to delete Lambda function ${validator_name}"
        fi
    else
        log_warning "Lambda function ${validator_name} not found"
    fi
}

# Remove IAM roles
remove_iam_roles() {
    local suffix="${PROJECT_NAME##*-}"
    local roles=("lambda-execution-role-${suffix}" "stepfunctions-execution-role-${suffix}" "apigateway-stepfunctions-role-${suffix}")
    
    log "Removing IAM roles..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove IAM roles: ${roles[*]}"
        return 0
    fi
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "${role}" &> /dev/null; then
            log "Deleting IAM role: ${role}"
            
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${role}" \
                --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in ${attached_policies}; do
                log "Detaching policy: ${policy_arn}"
                aws iam detach-role-policy --role-name "${role}" --policy-arn "${policy_arn}" || true
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies \
                --role-name "${role}" \
                --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            for policy_name in ${inline_policies}; do
                log "Deleting inline policy: ${policy_name}"
                aws iam delete-role-policy --role-name "${role}" --policy-name "${policy_name}" || true
            done
            
            # Wait for policy detachment to propagate
            sleep 5
            
            # Delete the role
            if aws iam delete-role --role-name "${role}"; then
                log_success "IAM role ${role} deleted successfully"
            else
                log_error "Failed to delete IAM role ${role}"
            fi
        else
            log_warning "IAM role ${role} not found"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would clean up local files"
        return 0
    fi
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/enterprise-api-spec.json"
        "${SCRIPT_DIR}"/deployment_summary_*.json
        "${SCRIPT_DIR}"/resource_backup_*.json
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        # Handle glob patterns safely
        for file in ${file_pattern}; do
            if [[ -f "${file}" ]]; then
                log "Removing file: $(basename "${file}")"
                rm -f "${file}"
            fi
        done
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    local suffix="${PROJECT_NAME##*-}"
    
    log "Verifying cleanup completion..."
    
    local remaining_resources=()
    
    # Check Lambda functions
    local transformer_name="api-transformer-${suffix}"
    local validator_name="data-validator-${suffix}"
    
    if aws lambda get-function --function-name "${transformer_name}" &> /dev/null; then
        remaining_resources+=("Lambda: ${transformer_name}")
    fi
    
    if aws lambda get-function --function-name "${validator_name}" &> /dev/null; then
        remaining_resources+=("Lambda: ${validator_name}")
    fi
    
    # Check Step Functions
    local state_machine_name="api-orchestrator-${suffix}"
    local state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${state_machine_name}"
    if aws stepfunctions describe-state-machine --state-machine-arn "${state_machine_arn}" &> /dev/null; then
        remaining_resources+=("Step Functions: ${state_machine_name}")
    fi
    
    # Check API Gateway
    local api_name="enterprise-api-integration-${suffix}"
    local api_id
    api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${api_name}'].id" --output text 2>/dev/null || echo "")
    if [[ -n "${api_id}" && "${api_id}" != "None" ]]; then
        remaining_resources+=("API Gateway: ${api_name}")
    fi
    
    # Check IAM Roles
    local roles=("lambda-execution-role-${suffix}" "stepfunctions-execution-role-${suffix}" "apigateway-stepfunctions-role-${suffix}")
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "${role}" &> /dev/null; then
            remaining_resources+=("IAM Role: ${role}")
        fi
    done
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log_success "All resources have been successfully removed"
        return 0
    else
        log_warning "The following resources still exist and may need manual cleanup:"
        for resource in "${remaining_resources[@]}"; do
            log "  - ${resource}"
        done
        return 1
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log ""
    log "🧹 CLEANUP SUMMARY"
    log "=================="
    log "Project: ${PROJECT_NAME}"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Cleanup Time: $(date)"
    log ""
    
    if verify_cleanup; then
        log_success "✅ Cleanup completed successfully!"
        log ""
        log "All Enterprise API Integration resources have been removed."
        log "No ongoing costs should be incurred from this deployment."
    else
        log_warning "⚠️  Cleanup partially completed"
        log ""
        log "Some resources may still exist. Please check the verification output above."
        log "You may need to manually remove remaining resources through the AWS Console."
    fi
    
    log ""
    log "📁 FILES"
    log "Cleanup Log: ${LOG_FILE}"
    log ""
    log "💡 RECOVERY"
    log "If you accidentally deleted resources, check for backup files in:"
    log "${SCRIPT_DIR}/resource_backup_*.json"
    log ""
    log "To redeploy: ./deploy.sh"
}

# Main cleanup function
main() {
    log "Starting Enterprise API Integration cleanup..."
    log "Log file: ${LOG_FILE}"
    
    parse_arguments "$@"
    check_prerequisites
    setup_environment
    
    if [[ "${LIST_PROJECTS}" == "true" ]]; then
        list_projects
        exit 0
    fi
    
    auto_detect_project
    validate_project
    confirm_destruction
    backup_resources
    
    # Perform cleanup in reverse order of creation
    remove_api_gateway
    remove_step_functions
    remove_lambda_functions
    remove_iam_roles
    cleanup_local_files
    
    generate_cleanup_summary
    
    log_success "Cleanup process completed! 🎉"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
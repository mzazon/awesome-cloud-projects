#!/bin/bash

# CQRS and Event Sourcing with EventBridge and DynamoDB - Cleanup Script
# This script safely removes all resources created by the CQRS deployment

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/cqrs-destroy-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# =============================================================================
# Utility Functions
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy CQRS and Event Sourcing infrastructure

OPTIONS:
    -p, --project-name NAME    Specific project name to destroy
    -r, --region REGION        AWS region (uses current default if not specified)
    -f, --force               Skip confirmation prompts (dangerous!)
    -d, --dry-run             Show what would be destroyed without actually deleting
    -a, --all                 Destroy all CQRS projects found in the account
    -v, --verbose             Enable verbose logging
    -h, --help                Show this help message

EXAMPLES:
    $0                                    # Interactive mode - select project to destroy
    $0 --project-name cqrs-demo-abc123   # Destroy specific project
    $0 --all --force                     # Destroy all CQRS projects (DANGEROUS!)
    $0 --dry-run                         # Preview what would be destroyed

SAFETY NOTES:
- This script will DELETE all resources permanently
- Backups are NOT created automatically
- Use --dry-run first to verify what will be destroyed
- The --force flag skips all confirmation prompts

EOF
}

confirm_destruction() {
    local project_name=$1
    
    if [[ "${FORCE_MODE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    cat << EOF

${RED}WARNING: DESTRUCTIVE OPERATION${NC}

You are about to PERMANENTLY DELETE the following resources for project: ${project_name}

- DynamoDB Tables (including all data)
- Lambda Functions
- EventBridge Rules and Custom Bus
- IAM Roles and Policies
- Event Source Mappings

${RED}THIS CANNOT BE UNDONE!${NC}

EOF
    
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "This will delete ALL data. Type the project name '${project_name}' to confirm: " name_confirmation
    
    if [[ "${name_confirmation}" != "${project_name}" ]]; then
        log_error "Project name confirmation failed. Destruction cancelled."
        exit 1
    fi
    
    log_warning "Proceeding with resource destruction..."
}

wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        case ${resource_type} in
            "dynamodb-table")
                if ! aws dynamodb describe-table --table-name "${resource_name}" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' deleted"
                    return 0
                fi
                ;;
            "lambda-function")
                if ! aws lambda get-function --function-name "${resource_name}" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' deleted"
                    return 0
                fi
                ;;
            "iam-role")
                if ! aws iam get-role --role-name "${resource_name}" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' deleted"
                    return 0
                fi
                ;;
        esac
        
        log_info "Attempt ${attempt}/${max_attempts}: ${resource_type} still exists, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_warning "Timeout waiting for ${resource_type} '${resource_name}' deletion"
    return 1
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

discover_cqrs_projects() {
    log_info "Discovering CQRS projects in account..."
    
    local projects=()
    
    # Look for Lambda functions with our naming pattern
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `cqrs-demo`) || contains(FunctionName, `command-handler`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    # Extract project names from Lambda function names
    for func in ${lambda_functions}; do
        if [[ "${func}" =~ ^(.+)-(command-handler|stream-processor|user-projection|order-projection|query-handler)$ ]]; then
            local project_name="${BASH_REMATCH[1]}"
            if [[ ! " ${projects[*]} " =~ " ${project_name} " ]]; then
                projects+=("${project_name}")
            fi
        fi
    done
    
    # Look for DynamoDB tables with our naming pattern
    local dynamodb_tables
    dynamodb_tables=$(aws dynamodb list-tables \
        --query 'TableNames[?contains(@, `cqrs-demo`) || contains(@, `event-store`)]' \
        --output text 2>/dev/null || echo "")
    
    for table in ${dynamodb_tables}; do
        if [[ "${table}" =~ ^(.+)-(event-store|user-profiles|order-summaries)$ ]]; then
            local project_name="${BASH_REMATCH[1]}"
            if [[ ! " ${projects[*]} " =~ " ${project_name} " ]]; then
                projects+=("${project_name}")
            fi
        fi
    done
    
    # Look for EventBridge buses with our naming pattern
    local event_buses
    event_buses=$(aws events list-event-buses \
        --query 'EventBuses[?contains(Name, `cqrs-demo`) || contains(Name, `events`)].Name' \
        --output text 2>/dev/null || echo "")
    
    for bus in ${event_buses}; do
        if [[ "${bus}" =~ ^(.+)-events$ ]]; then
            local project_name="${BASH_REMATCH[1]}"
            if [[ ! " ${projects[*]} " =~ " ${project_name} " ]]; then
                projects+=("${project_name}")
            fi
        fi
    done
    
    printf '%s\n' "${projects[@]}" | sort -u
}

select_project_interactive() {
    local projects
    mapfile -t projects < <(discover_cqrs_projects)
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        log_error "No CQRS projects found in this account/region"
        exit 1
    fi
    
    echo "Found the following CQRS projects:"
    echo
    
    local i=1
    for project in "${projects[@]}"; do
        echo "  ${i}. ${project}"
        ((i++))
    done
    
    echo
    read -p "Select a project to destroy (1-${#projects[@]}): " selection
    
    if ! [[ "${selection}" =~ ^[0-9]+$ ]] || [[ ${selection} -lt 1 ]] || [[ ${selection} -gt ${#projects[@]} ]]; then
        log_error "Invalid selection: ${selection}"
        exit 1
    fi
    
    echo "${projects[$((selection-1))]}"
}

# =============================================================================
# Resource Destruction Functions
# =============================================================================

delete_lambda_functions() {
    local project_name=$1
    
    log_info "Deleting Lambda functions for project: ${project_name}"
    
    local functions=(
        "${project_name}-command-handler"
        "${project_name}-stream-processor"
        "${project_name}-user-projection"
        "${project_name}-order-projection"
        "${project_name}-query-handler"
    )
    
    for func in "${functions[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would delete Lambda function: ${func}"
            continue
        fi
        
        if aws lambda get-function --function-name "${func}" >/dev/null 2>&1; then
            log_info "Deleting Lambda function: ${func}"
            
            # Remove event source mappings first
            local mappings
            mappings=$(aws lambda list-event-source-mappings \
                --function-name "${func}" \
                --query 'EventSourceMappings[].UUID' \
                --output text 2>/dev/null || echo "")
            
            for mapping in ${mappings}; do
                log_info "Removing event source mapping: ${mapping}"
                aws lambda delete-event-source-mapping --uuid "${mapping}" >/dev/null 2>&1 || true
            done
            
            # Delete the function
            if aws lambda delete-function --function-name "${func}" >/dev/null 2>&1; then
                log_success "Deleted Lambda function: ${func}"
            else
                log_warning "Failed to delete Lambda function: ${func}"
            fi
        else
            log_info "Lambda function ${func} does not exist, skipping"
        fi
    done
}

delete_eventbridge_resources() {
    local project_name=$1
    
    log_info "Deleting EventBridge resources for project: ${project_name}"
    
    local event_bus_name="${project_name}-events"
    local rules=(
        "${project_name}-user-events"
        "${project_name}-order-events"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would delete EventBridge resources"
        return 0
    fi
    
    # Remove targets from rules first
    for rule in "${rules[@]}"; do
        if aws events describe-rule --name "${rule}" --event-bus-name "${event_bus_name}" >/dev/null 2>&1; then
            log_info "Removing targets from rule: ${rule}"
            
            local targets
            targets=$(aws events list-targets-by-rule \
                --rule "${rule}" \
                --event-bus-name "${event_bus_name}" \
                --query 'Targets[].Id' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${targets}" ]]; then
                aws events remove-targets \
                    --rule "${rule}" \
                    --event-bus-name "${event_bus_name}" \
                    --ids ${targets} >/dev/null 2>&1 || true
            fi
            
            # Delete the rule
            log_info "Deleting EventBridge rule: ${rule}"
            aws events delete-rule \
                --name "${rule}" \
                --event-bus-name "${event_bus_name}" >/dev/null 2>&1 || true
        fi
    done
    
    # Delete archive
    local archive_name="${event_bus_name}-archive"
    if aws events describe-archive --archive-name "${archive_name}" >/dev/null 2>&1; then
        log_info "Deleting EventBridge archive: ${archive_name}"
        aws events delete-archive --archive-name "${archive_name}" >/dev/null 2>&1 || true
        log_success "Deleted archive: ${archive_name}"
    fi
    
    # Delete custom event bus
    if aws events describe-event-bus --name "${event_bus_name}" >/dev/null 2>&1; then
        log_info "Deleting EventBridge bus: ${event_bus_name}"
        if aws events delete-event-bus --name "${event_bus_name}" >/dev/null 2>&1; then
            log_success "Deleted EventBridge bus: ${event_bus_name}"
        else
            log_warning "Failed to delete EventBridge bus: ${event_bus_name}"
        fi
    else
        log_info "EventBridge bus ${event_bus_name} does not exist, skipping"
    fi
}

delete_dynamodb_tables() {
    local project_name=$1
    
    log_info "Deleting DynamoDB tables for project: ${project_name}"
    
    local tables=(
        "${project_name}-event-store"
        "${project_name}-user-profiles"
        "${project_name}-order-summaries"
    )
    
    for table in "${tables[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would delete DynamoDB table: ${table}"
            continue
        fi
        
        if aws dynamodb describe-table --table-name "${table}" >/dev/null 2>&1; then
            log_info "Deleting DynamoDB table: ${table}"
            
            if aws dynamodb delete-table --table-name "${table}" >/dev/null 2>&1; then
                log_success "Initiated deletion of table: ${table}"
                
                # Wait for deletion in background for better performance
                (wait_for_deletion "dynamodb-table" "${table}" 60 &)
            else
                log_warning "Failed to delete DynamoDB table: ${table}"
            fi
        else
            log_info "DynamoDB table ${table} does not exist, skipping"
        fi
    done
    
    # Wait for all background deletion processes
    wait
}

delete_iam_roles() {
    local project_name=$1
    
    log_info "Deleting IAM roles for project: ${project_name}"
    
    local roles=(
        "${project_name}-command-role"
        "${project_name}-projection-role"
    )
    
    for role in "${roles[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would delete IAM role: ${role}"
            continue
        fi
        
        if aws iam get-role --role-name "${role}" >/dev/null 2>&1; then
            log_info "Deleting IAM role: ${role}"
            
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${role}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in ${attached_policies}; do
                log_info "Detaching policy ${policy_arn} from role ${role}"
                aws iam detach-role-policy \
                    --role-name "${role}" \
                    --policy-arn "${policy_arn}" >/dev/null 2>&1 || true
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies \
                --role-name "${role}" \
                --query 'PolicyNames' \
                --output text 2>/dev/null || echo "")
            
            for policy_name in ${inline_policies}; do
                log_info "Deleting inline policy ${policy_name} from role ${role}"
                aws iam delete-role-policy \
                    --role-name "${role}" \
                    --policy-name "${policy_name}" >/dev/null 2>&1 || true
            done
            
            # Delete the role
            if aws iam delete-role --role-name "${role}" >/dev/null 2>&1; then
                log_success "Deleted IAM role: ${role}"
            else
                log_warning "Failed to delete IAM role: ${role}"
            fi
        else
            log_info "IAM role ${role} does not exist, skipping"
        fi
    done
}

# =============================================================================
# Main Destruction Function
# =============================================================================

destroy_project() {
    local project_name=$1
    
    log_info "Starting destruction of CQRS project: ${project_name}"
    
    # Confirm destruction unless in force mode
    confirm_destruction "${project_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "=== DRY RUN MODE - NO RESOURCES WILL BE DELETED ==="
    fi
    
    # Delete resources in reverse order of creation to minimize dependencies
    delete_eventbridge_resources "${project_name}"
    delete_lambda_functions "${project_name}"
    delete_iam_roles "${project_name}"
    delete_dynamodb_tables "${project_name}"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_success "Project '${project_name}' destroyed successfully!"
        
        # Output destruction summary
        cat << EOF

=============================================================================
                        DESTRUCTION SUMMARY
=============================================================================
Project Name:           ${project_name}
AWS Region:             ${AWS_REGION}
AWS Account:            ${AWS_ACCOUNT_ID}

DELETED RESOURCES:
- Lambda Functions:     5 functions
- DynamoDB Tables:      3 tables (with all data)
- EventBridge Bus:      1 custom bus with archive
- EventBridge Rules:    2 rules with targets
- IAM Roles:            2 roles with policies

LOG FILE:               ${LOG_FILE}

NOTES:
- All data has been permanently deleted
- No backups were created
- Cost charges for these resources have stopped

=============================================================================
EOF
    else
        log_info "Dry run completed. No resources were actually deleted."
    fi
}

destroy_all_projects() {
    log_info "Destroying ALL CQRS projects in account..."
    
    local projects
    mapfile -t projects < <(discover_cqrs_projects)
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        log_info "No CQRS projects found to destroy"
        return 0
    fi
    
    log_warning "Found ${#projects[@]} projects to destroy:"
    for project in "${projects[@]}"; do
        log_warning "  - ${project}"
    done
    
    if [[ "${FORCE_MODE}" != "true" ]]; then
        echo
        read -p "Are you sure you want to destroy ALL ${#projects[@]} projects? (type 'DELETE ALL' to confirm): " confirmation
        
        if [[ "${confirmation}" != "DELETE ALL" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    for project in "${projects[@]}"; do
        log_info "Destroying project: ${project}"
        FORCE_MODE="true" destroy_project "${project}"
        echo
    done
    
    log_success "All CQRS projects destroyed successfully!"
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    # Parse command line arguments
    local project_name=""
    local region=""
    local force=false
    local dry_run=false
    local destroy_all=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-name)
                project_name="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -a|--all)
                destroy_all=true
                shift
                ;;
            -v|--verbose)
                verbose=true
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
    
    # Set global variables
    FORCE_MODE="${force}"
    DRY_RUN="${dry_run}"
    VERBOSE="${verbose}"
    
    # Enable verbose logging if requested
    if [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    # Set up AWS environment
    export AWS_REGION="${region:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_info "Starting CQRS and Event Sourcing cleanup script"
    log_info "Log file: ${LOG_FILE}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Main destruction logic
    if [[ "${destroy_all}" == "true" ]]; then
        destroy_all_projects
    elif [[ -n "${project_name}" ]]; then
        destroy_project "${project_name}"
    else
        # Interactive mode
        local selected_project
        selected_project=$(select_project_interactive)
        destroy_project "${selected_project}"
    fi
    
    log_success "Cleanup completed successfully!"
    exit 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
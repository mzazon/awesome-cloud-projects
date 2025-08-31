#!/bin/bash

#######################################################################
# Weather API Cloud Functions Cleanup Script
# 
# This script safely removes all resources created by the Weather API
# Cloud Functions deployment. It includes safety checks, confirmation
# prompts, and comprehensive logging.
#
# Prerequisites:
# - Google Cloud CLI (gcloud) installed and authenticated
# - Appropriate IAM permissions for resource deletion
#
# Usage: ./destroy.sh [OPTIONS]
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CODE_DIR="$(dirname "${SCRIPT_DIR}")"
readonly DEPLOYMENT_INFO_FILE="${CODE_DIR}/deployment-info.txt"
readonly LOG_FILE="/tmp/weather-api-destroy-$(date +%Y%m%d-%H%M%S).log"

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Script options
FORCE_DELETE=false
DRY_RUN=false
INTERACTIVE=true
DELETE_ALL=false

#######################################################################
# Utility Functions
#######################################################################

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

log_dry_run() {
    log "${MAGENTA}[DRY RUN]${NC} ${1}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Weather API Cloud Functions resources

OPTIONS:
    -f, --force         Skip confirmation prompts (use with caution)
    -d, --dry-run       Show what would be deleted without actually deleting
    -y, --yes           Answer yes to all prompts (implies --force)
    -a, --all           Delete all weather-api functions found in the project
    -h, --help          Show this help message

EXAMPLES:
    $0                  # Interactive deletion with confirmations
    $0 --dry-run        # Preview what would be deleted
    $0 --force          # Delete without confirmations
    $0 --all            # Delete all weather-api functions in the project

SAFETY FEATURES:
    - Interactive confirmation prompts by default
    - Dry-run mode to preview deletions
    - Comprehensive logging of all operations
    - Validation of resources before deletion
    - Rollback prevention for accidental executions

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                INTERACTIVE=false
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                FORCE_DELETE=true
                INTERACTIVE=false
                shift
                ;;
            -a|--all)
                DELETE_ALL=true
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
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Cleanup script failed with exit code ${exit_code}"
        log_info "Check log file: ${LOG_FILE}"
    fi
    exit ${exit_code}
}

confirm_action() {
    local message="${1}"
    local default="${2:-n}"
    
    if [[ "${INTERACTIVE}" == false ]] || [[ "${FORCE_DELETE}" == true ]]; then
        return 0
    fi
    
    local prompt
    if [[ "${default}" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    while true; do
        read -r -p "$(echo -e "${YELLOW}${message} ${prompt}:${NC} ")" response
        response=${response,,} # Convert to lowercase
        
        if [[ -z "${response}" ]]; then
            response="${default}"
        fi
        
        case "${response}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

#######################################################################
# Resource Discovery Functions
#######################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud >&/dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        return 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        return 1
    fi
    
    # Check if project is set
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "${current_project}" ]]; then
        log_error "No default project configured. Run: gcloud config set project PROJECT_ID"
        return 1
    fi
    
    log_success "Prerequisites check passed (Project: ${current_project})"
    return 0
}

load_deployment_info() {
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Loading deployment information from: ${DEPLOYMENT_INFO_FILE}"
        
        # Source the deployment info file to get variables
        # Use a subshell to avoid polluting current environment
        eval "$(grep -E '^[A-Z_]+=.*$' "${DEPLOYMENT_INFO_FILE}" 2>/dev/null || true)"
        
        if [[ -n "${FUNCTION_NAME:-}" ]]; then
            log_success "Loaded deployment info for function: ${FUNCTION_NAME}"
            return 0
        else
            log_warning "Deployment info file exists but contains no function name"
            return 1
        fi
    else
        log_warning "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        return 1
    fi
}

discover_weather_functions() {
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null)
    
    log_info "Discovering weather API functions in project: ${project_id}"
    
    # Get all functions with 'weather-api' in the name
    local functions_json
    functions_json=$(gcloud functions list \
        --filter="name:weather-api" \
        --format="json" 2>/dev/null || echo "[]")
    
    if [[ "${functions_json}" == "[]" ]] || [[ -z "${functions_json}" ]]; then
        log_warning "No weather API functions found in project"
        return 1
    fi
    
    # Parse function information
    local function_count
    function_count=$(echo "${functions_json}" | jq '. | length' 2>/dev/null || echo "0")
    
    if [[ "${function_count}" -eq 0 ]]; then
        log_warning "No weather API functions found"
        return 1
    fi
    
    log_success "Found ${function_count} weather API function(s)"
    
    # Display functions in a readable format
    echo "${functions_json}" | jq -r '.[] | "\(.name) (\(.buildConfig.source.storageSource.bucket // "gen2") in \(.location))"' 2>/dev/null || {
        # Fallback for simpler parsing
        echo "${functions_json}" | jq -r '.[] | "\(.name) in \(.location)"' 2>/dev/null
    }
    
    return 0
}

get_function_details() {
    local function_name="${1}"
    local region="${2:-}"
    
    log_info "Getting details for function: ${function_name}"
    
    # If region not provided, try to extract from function name or discover
    if [[ -z "${region}" ]]; then
        # Try to get region from gcloud functions list
        region=$(gcloud functions list \
            --filter="name:${function_name}" \
            --format="value(location)" \
            --limit=1 2>/dev/null | head -n1)
        
        if [[ -z "${region}" ]]; then
            log_error "Could not determine region for function: ${function_name}"
            return 1
        fi
    fi
    
    # Check if function exists
    if gcloud functions describe "${function_name}" --region="${region}" --gen2 >&/dev/null; then
        log_success "Function found: ${function_name} in ${region} (Gen 2)"
        echo "${region}"
        return 0
    elif gcloud functions describe "${function_name}" --region="${region}" >&/dev/null; then
        log_success "Function found: ${function_name} in ${region} (Gen 1)"
        echo "${region}"
        return 0
    else
        log_warning "Function not found: ${function_name} in ${region}"
        return 1
    fi
}

#######################################################################
# Deletion Functions
#######################################################################

delete_function() {
    local function_name="${1}"
    local region="${2}"
    local generation="${3:-gen2}"
    
    log_info "Preparing to delete function: ${function_name}"
    
    if [[ "${DRY_RUN}" == true ]]; then
        log_dry_run "Would delete Cloud Function: ${function_name} (${generation}) in ${region}"
        return 0
    fi
    
    # Confirm deletion
    if ! confirm_action "Delete Cloud Function '${function_name}' in region '${region}'?" "n"; then
        log_info "Skipping deletion of function: ${function_name}"
        return 0
    fi
    
    log_info "Deleting Cloud Function: ${function_name} (${generation}) in ${region}"
    
    # Delete function based on generation
    local delete_cmd
    if [[ "${generation}" == "gen2" ]]; then
        delete_cmd="gcloud functions delete ${function_name} --region=${region} --gen2 --quiet"
    else
        delete_cmd="gcloud functions delete ${function_name} --region=${region} --quiet"
    fi
    
    if eval "${delete_cmd}" 2>>"${LOG_FILE}"; then
        log_success "Successfully deleted function: ${function_name}"
        return 0
    else
        log_error "Failed to delete function: ${function_name}"
        log_info "Check if function exists and you have proper permissions"
        return 1
    fi
}

cleanup_deployment_artifacts() {
    log_info "Cleaning up deployment artifacts..."
    
    if [[ "${DRY_RUN}" == true ]]; then
        if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
            log_dry_run "Would remove deployment info file: ${DEPLOYMENT_INFO_FILE}"
        fi
        
        # Check for any temporary directories
        local temp_dirs
        temp_dirs=$(find /tmp -maxdepth 1 -name "weather-api-deploy-*" -type d 2>/dev/null || true)
        if [[ -n "${temp_dirs}" ]]; then
            log_dry_run "Would remove temporary directories: ${temp_dirs}"
        fi
        
        return 0
    fi
    
    # Remove deployment info file
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        if confirm_action "Remove deployment info file?" "y"; then
            rm -f "${DEPLOYMENT_INFO_FILE}"
            log_success "Removed deployment info file"
        fi
    fi
    
    # Clean up any temporary deployment directories
    local temp_dirs
    temp_dirs=$(find /tmp -maxdepth 1 -name "weather-api-deploy-*" -type d 2>/dev/null || true)
    if [[ -n "${temp_dirs}" ]]; then
        if confirm_action "Remove temporary deployment directories?" "y"; then
            echo "${temp_dirs}" | xargs rm -rf
            log_success "Removed temporary deployment directories"
        fi
    fi
    
    log_success "Deployment artifacts cleanup completed"
}

#######################################################################
# Main Deletion Logic
#######################################################################

delete_from_deployment_info() {
    log_info "Using deployment information for targeted deletion..."
    
    if [[ -z "${FUNCTION_NAME:-}" ]] || [[ -z "${REGION:-}" ]]; then
        log_error "Missing function name or region in deployment info"
        return 1
    fi
    
    # Get function generation
    local generation="gen2"
    if ! gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --gen2 >&/dev/null; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >&/dev/null; then
            generation="gen1"
        else
            log_error "Function not found: ${FUNCTION_NAME} in ${REGION}"
            return 1
        fi
    fi
    
    delete_function "${FUNCTION_NAME}" "${REGION}" "${generation}"
}

delete_all_weather_functions() {
    log_info "Deleting all weather API functions in the project..."
    
    local functions_json
    functions_json=$(gcloud functions list \
        --filter="name:weather-api" \
        --format="json" 2>/dev/null || echo "[]")
    
    if [[ "${functions_json}" == "[]" ]] || [[ -z "${functions_json}" ]]; then
        log_warning "No weather API functions found to delete"
        return 0
    fi
    
    # Parse and delete each function
    local function_count
    function_count=$(echo "${functions_json}" | jq '. | length' 2>/dev/null || echo "0")
    
    log_info "Found ${function_count} weather API function(s) to delete"
    
    # Show functions that will be deleted
    if [[ "${DRY_RUN}" == false ]] && [[ "${INTERACTIVE}" == true ]]; then
        log_info "Functions to be deleted:"
        echo "${functions_json}" | jq -r '.[] | "  - \(.name) in \(.location)"' 2>/dev/null || {
            echo "${functions_json}" | jq -r '.[] | "  - \(.name)"' 2>/dev/null
        }
        echo
    fi
    
    # Confirm bulk deletion
    if [[ "${DRY_RUN}" == false ]] && ! confirm_action "Delete all ${function_count} weather API functions?" "n"; then
        log_info "Bulk deletion cancelled"
        return 0
    fi
    
    # Delete each function
    local deleted_count=0
    local failed_count=0
    
    while IFS= read -r function_data; do
        local function_name region generation
        
        function_name=$(echo "${function_data}" | jq -r '.name' 2>/dev/null)
        region=$(echo "${function_data}" | jq -r '.location' 2>/dev/null)
        
        # Determine generation
        generation="gen2"
        if ! gcloud functions describe "${function_name}" --region="${region}" --gen2 >&/dev/null 2>&1; then
            generation="gen1"
        fi
        
        if delete_function "${function_name}" "${region}" "${generation}"; then
            ((deleted_count++))
        else
            ((failed_count++))
        fi
        
    done < <(echo "${functions_json}" | jq -c '.[]' 2>/dev/null || echo "")
    
    log_info "Deletion summary: ${deleted_count} successful, ${failed_count} failed"
    
    if [[ ${failed_count} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

interactive_deletion() {
    log_info "Starting interactive deletion process..."
    
    # First, try to use deployment info
    if load_deployment_info; then
        log_info "Found deployment information"
        
        if confirm_action "Delete function from deployment info (${FUNCTION_NAME:-unknown})?" "y"; then
            delete_from_deployment_info
        fi
    else
        log_info "No deployment info found, discovering functions..."
        
        if discover_weather_functions; then
            if confirm_action "Delete all discovered weather API functions?" "n"; then
                delete_all_weather_functions
            fi
        else
            log_warning "No weather API functions found to delete"
        fi
    fi
    
    # Always offer to clean up artifacts
    cleanup_deployment_artifacts
}

show_deletion_summary() {
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null)
    
    cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}🧹 WEATHER API CLEANUP COMPLETED! 🧹${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${BLUE}Cleanup Summary:${NC}
  Project:          ${YELLOW}${project_id}${NC}
  Log File:         ${YELLOW}${LOG_FILE}${NC}
  Operation:        ${YELLOW}$([ "${DRY_RUN}" == true ] && echo "DRY RUN" || echo "ACTUAL DELETION")${NC}

${BLUE}Verification Commands:${NC}
  # Check remaining functions
  ${YELLOW}gcloud functions list --filter="name:weather-api"${NC}
  
  # Check project resources
  ${YELLOW}gcloud projects get-iam-policy ${project_id}${NC}

${BLUE}Next Steps:${NC}
  1. Verify all intended resources have been removed
  2. Check your Google Cloud Console for any remaining resources
  3. Review billing to ensure no unexpected charges
  4. Consider disabling unused APIs if no longer needed

${BLUE}Re-deployment:${NC}
  To deploy again: ${YELLOW}./deploy.sh${NC}

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
    
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "This was a dry run. No resources were actually deleted."
        log_info "Run without --dry-run to perform actual deletion."
    fi
}

#######################################################################
# Main Function
#######################################################################

main() {
    # Set up exit trap
    trap cleanup_on_exit EXIT
    
    # Initialize logging
    log_info "Starting Weather API cleanup script..."
    log_info "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Log script configuration
    log_info "Script configuration:"
    log_info "  Force delete: ${FORCE_DELETE}"
    log_info "  Dry run: ${DRY_RUN}"
    log_info "  Interactive: ${INTERACTIVE}"
    log_info "  Delete all: ${DELETE_ALL}"
    
    # Prerequisites check
    check_prerequisites || exit 1
    
    # Main deletion logic
    if [[ "${DELETE_ALL}" == true ]]; then
        delete_all_weather_functions || exit 1
        cleanup_deployment_artifacts
    elif [[ "${DRY_RUN}" == true ]]; then
        log_info "=== DRY RUN MODE - NO RESOURCES WILL BE DELETED ==="
        if load_deployment_info; then
            delete_from_deployment_info || true
        else
            discover_weather_functions || true
            delete_all_weather_functions || true
        fi
        cleanup_deployment_artifacts
    else
        interactive_deletion
    fi
    
    # Show summary
    show_deletion_summary
    
    log_success "Weather API cleanup completed successfully!"
    
    # Remove exit trap since we succeeded
    trap - EXIT
}

#######################################################################
# Script Entry Point
#######################################################################

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
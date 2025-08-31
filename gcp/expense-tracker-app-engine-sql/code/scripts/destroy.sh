#!/bin/bash

# Personal Expense Tracker Cleanup Script
# Removes App Engine application and Cloud SQL resources
# Recipe: expense-tracker-app-engine-sql

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Default values
FORCE_DELETE=false
DRY_RUN=false
KEEP_PROJECT=true

# Help function
show_help() {
    cat << EOF
Personal Expense Tracker Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    GCP project ID (required)
    --instance-name INSTANCE       Cloud SQL instance name
    --force                        Skip confirmation prompts
    --delete-project              Delete the entire project (DESTRUCTIVE)
    --dry-run                     Show what would be deleted without executing
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --instance-name expense-db-abc123
    $0 --project-id my-project-123 --force
    $0 --project-id my-project-123 --delete-project --force
    $0 --project-id my-project-123 --dry-run

DESCRIPTION:
    This script removes resources created by the deploy.sh script:
    - App Engine application versions (keeps default service)
    - Cloud SQL instances
    - Application files (if present)
    
    WARNING: Data deletion is permanent and cannot be undone!

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Appropriate IAM permissions for resource deletion
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --instance-name)
                INSTANCE_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --delete-project)
                KEEP_PROJECT=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud CLI"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id or -p flag"
        show_help
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project '${PROJECT_ID}' not found or not accessible"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local can_fail="${3:-false}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${cmd}"
        log_info "[DRY RUN] Description: ${description}"
        return 0
    fi
    
    log_info "Executing: ${description}"
    if [[ "${can_fail}" == "true" ]]; then
        eval "${cmd}" || log_warning "Command failed but continuing: ${description}"
    else
        eval "${cmd}"
    fi
}

# Confirm destructive action
confirm_action() {
    local action="$1"
    local details="$2"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    log_warning "DESTRUCTIVE ACTION: ${action}"
    log_warning "Details: ${details}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo -n "Are you sure you want to continue? (yes/no): "
    
    read -r response
    if [[ "${response}" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Set project context
set_project_context() {
    log_info "Setting project context..."
    
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Set project context"
    
    log_success "Project context set to: ${PROJECT_ID}"
}

# Discover Cloud SQL instances
discover_instances() {
    log_info "Discovering Cloud SQL instances..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would discover Cloud SQL instances"
        DISCOVERED_INSTANCES=("expense-db-example")
        return 0
    fi
    
    # Get all Cloud SQL instances that match the pattern
    local instances
    instances=$(gcloud sql instances list --filter="name:expense-db-*" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        # Use provided instance name
        DISCOVERED_INSTANCES=("${INSTANCE_NAME}")
        log_info "Using provided instance name: ${INSTANCE_NAME}"
    elif [[ -n "${instances}" ]]; then
        # Use discovered instances
        DISCOVERED_INSTANCES=()
        while IFS= read -r instance; do
            DISCOVERED_INSTANCES+=("${instance}")
        done <<< "${instances}"
        log_info "Discovered instances: ${DISCOVERED_INSTANCES[*]}"
    else
        DISCOVERED_INSTANCES=()
        log_info "No Cloud SQL instances found matching pattern 'expense-db-*'"
    fi
    
    # Try to read from deployment info file
    if [[ -f "deployment-info.txt" ]] && [[ ${#DISCOVERED_INSTANCES[@]} -eq 0 ]]; then
        local info_instance
        info_instance=$(grep "Cloud SQL Instance:" deployment-info.txt | cut -d: -f2 | xargs 2>/dev/null || true)
        if [[ -n "${info_instance}" ]]; then
            DISCOVERED_INSTANCES=("${info_instance}")
            log_info "Found instance in deployment-info.txt: ${info_instance}"
        fi
    fi
}

# Remove App Engine versions
cleanup_app_engine() {
    log_info "Cleaning up App Engine versions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up App Engine versions"
        return 0
    fi
    
    # Check if App Engine app exists
    if ! gcloud app describe &>/dev/null; then
        log_info "No App Engine application found"
        return 0
    fi
    
    # Get all versions except the default serving version
    local versions
    versions=$(gcloud app versions list --service=default --format="value(id)" --filter="traffic_split=0" 2>/dev/null || true)
    
    if [[ -n "${versions}" ]]; then
        confirm_action "Delete App Engine versions" "Versions: ${versions}"
        
        while IFS= read -r version; do
            if [[ -n "${version}" ]]; then
                execute_cmd "gcloud app versions delete ${version} --service=default --quiet" "Delete version ${version}" "true"
            fi
        done <<< "${versions}"
        
        log_success "App Engine versions cleaned up"
    else
        log_info "No non-serving App Engine versions to clean up"
    fi
    
    # Note about App Engine service
    log_warning "App Engine default service cannot be deleted once created"
    log_info "The service will remain but no longer serve traffic after version cleanup"
}

# Remove Cloud SQL instances
cleanup_cloud_sql() {
    log_info "Cleaning up Cloud SQL instances..."
    
    if [[ ${#DISCOVERED_INSTANCES[@]} -eq 0 ]]; then
        log_info "No Cloud SQL instances to clean up"
        return 0
    fi
    
    for instance in "${DISCOVERED_INSTANCES[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cloud SQL instance: ${instance}"
            continue
        fi
        
        # Check if instance exists
        if ! gcloud sql instances describe "${instance}" &>/dev/null; then
            log_warning "Cloud SQL instance '${instance}' not found"
            continue
        fi
        
        confirm_action "Delete Cloud SQL instance" "Instance: ${instance} (ALL DATA WILL BE LOST)"
        
        execute_cmd "gcloud sql instances delete ${instance} --quiet" "Delete Cloud SQL instance ${instance}"
        
        log_success "Cloud SQL instance deleted: ${instance}"
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local application files..."
    
    local files_to_remove=(
        "expense-tracker-app"
        "deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            execute_cmd "rm -rf ${file}" "Remove ${file}"
            log_success "Removed: ${file}"
        else
            log_info "File not found: ${file}"
        fi
    done
}

# Delete entire project (optional)
delete_project() {
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        return 0
    fi
    
    log_info "Preparing to delete entire project..."
    
    confirm_action "Delete entire project" "Project: ${PROJECT_ID} (ALL PROJECT DATA WILL BE LOST)"
    
    execute_cmd "gcloud projects delete ${PROJECT_ID} --quiet" "Delete project ${PROJECT_ID}"
    
    log_success "Project deletion initiated: ${PROJECT_ID}"
    log_info "Project deletion may take several minutes to complete"
}

# Display cleanup summary
show_summary() {
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "App Engine: Versions cleaned up (service remains)"
    log_info "Cloud SQL Instances: ${#DISCOVERED_INSTANCES[@]} instances processed"
    log_info "Local Files: Application directory and info files removed"
    
    if [[ "${KEEP_PROJECT}" == "false" ]]; then
        log_info "Project: Deletion initiated"
    else
        log_info "Project: Preserved (resources cleaned up)"
    fi
    
    log_info "Cleanup Date: $(date)"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info ""
        log_warning "This was a dry run - no resources were actually deleted"
        log_info "Run without --dry-run to execute the actual cleanup"
    fi
}

# Verify cleanup
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    # Check App Engine versions
    local remaining_versions
    remaining_versions=$(gcloud app versions list --service=default --format="value(id)" --filter="traffic_split=0" 2>/dev/null | wc -l || echo "0")
    
    if [[ "${remaining_versions}" -eq 0 ]]; then
        log_success "App Engine versions successfully cleaned up"
    else
        log_warning "${remaining_versions} App Engine versions still exist"
    fi
    
    # Check Cloud SQL instances
    local remaining_instances=0
    for instance in "${DISCOVERED_INSTANCES[@]}"; do
        if gcloud sql instances describe "${instance}" &>/dev/null; then
            ((remaining_instances++))
        fi
    done
    
    if [[ "${remaining_instances}" -eq 0 ]]; then
        log_success "Cloud SQL instances successfully deleted"
    else
        log_warning "${remaining_instances} Cloud SQL instances still exist"
    fi
    
    log_success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log_info "Starting Personal Expense Tracker cleanup..."
    log_info "Timestamp: $(date)"
    
    parse_args "$@"
    check_prerequisites
    set_project_context
    discover_instances
    
    log_info "Cleanup Plan:"
    log_info "  - App Engine versions (non-serving)"
    log_info "  - Cloud SQL instances: ${#DISCOVERED_INSTANCES[@]} found"
    log_info "  - Local application files"
    if [[ "${KEEP_PROJECT}" == "false" ]]; then
        log_info "  - Entire project (DESTRUCTIVE)"
    fi
    
    echo ""
    
    cleanup_app_engine
    cleanup_cloud_sql
    cleanup_local_files
    delete_project
    verify_cleanup
    show_summary
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        log_success "Cleanup completed successfully!"
        log_info "All specified resources have been removed."
        
        if [[ "${KEEP_PROJECT}" == "true" ]]; then
            log_info "The project '${PROJECT_ID}' has been preserved."
            log_info "You can reuse it for future deployments."
        fi
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted by user"
    log_info "Partial cleanup may have occurred"
    log_info "Run the script again to complete cleanup"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Run main function with all arguments
main "$@"
#!/bin/bash

# Legacy Database Applications with Database Migration Service and Application Design Center - Cleanup Script
# This script removes all infrastructure created for the legacy database modernization solution
# Recipe: legacy-database-applications-database-migration-service-application-design-center

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="cleanup-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script options
PARTIAL_CLEANUP=false
FORCE_CLEANUP=false
DRY_RUN=false

# Logging functions
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup script for Legacy Database Applications modernization infrastructure.

OPTIONS:
    --partial-cleanup    Clean up only resources tracked in .created_resources file
    --force             Skip confirmation prompts (dangerous!)
    --dry-run           Show what would be deleted without actually deleting
    --help              Show this help message

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 --dry-run               # Preview cleanup actions
    $0 --force                 # Force cleanup without prompts
    $0 --partial-cleanup       # Clean up only tracked resources

WARNING: This script will permanently delete cloud resources and data.
Make sure you have backups of any important data before proceeding.

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --partial-cleanup)
                PARTIAL_CLEANUP=true
                shift
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
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

# Prerequisites validation
check_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        log_error "No project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Load created resources from tracking file
load_created_resources() {
    local resources_file="${SCRIPT_DIR}/.created_resources"
    if [[ -f "${resources_file}" ]]; then
        log_info "Loading tracked resources from ${resources_file}"
        mapfile -t CREATED_RESOURCES < "${resources_file}"
        log_info "Found ${#CREATED_RESOURCES[@]} tracked resources"
    else
        log_warning "No tracked resources file found. Will attempt to discover resources."
        CREATED_RESOURCES=()
    fi
}

# Discover resources if not tracked
discover_resources() {
    if [[ ${#CREATED_RESOURCES[@]} -eq 0 && "${PARTIAL_CLEANUP}" == "false" ]]; then
        log_info "Discovering legacy modernization resources..."
        
        local project_id=$(gcloud config get-value project)
        local region="${REGION:-us-central1}"
        
        # Discover Cloud SQL instances with legacy pattern
        while IFS= read -r instance; do
            if [[ "${instance}" =~ modernized-postgres-.* ]]; then
                CREATED_RESOURCES+=("cloudsql:${instance}:${region}")
                log_info "Discovered Cloud SQL instance: ${instance}"
            fi
        done < <(gcloud sql instances list --format="value(name)" 2>/dev/null || true)
        
        # Discover migration jobs
        while IFS= read -r job; do
            if [[ "${job}" =~ legacy-modernization-.* ]]; then
                CREATED_RESOURCES+=("migration-job:${job}:${region}")
                log_info "Discovered migration job: ${job}"
            fi
        done < <(gcloud datamigration migration-jobs list --region="${region}" --format="value(name)" 2>/dev/null || true)
        
        # Discover connection profiles
        while IFS= read -r profile; do
            if [[ "${profile}" =~ (sqlserver-source-.*|postgres-dest-.*) ]]; then
                CREATED_RESOURCES+=("connection-profile:${profile}:${region}")
                log_info "Discovered connection profile: ${profile}"
            fi
        done < <(gcloud datamigration connection-profiles list --region="${region}" --format="value(name)" 2>/dev/null || true)
        
        # Discover source repositories
        while IFS= read -r repo; do
            if [[ "${repo}" =~ legacy-app-modernization ]]; then
                CREATED_RESOURCES+=("source-repo:${repo}:")
                log_info "Discovered source repository: ${repo}"
            fi
        done < <(gcloud source repos list --format="value(name)" 2>/dev/null || true)
        
        log_info "Resource discovery completed. Found ${#CREATED_RESOURCES[@]} resources."
    fi
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "${FORCE_CLEANUP}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  DANGER: This will permanently delete the following resources:"
    echo
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ -n "${location}" ]]; then
            echo "  - ${type}: ${name} (${location})"
        else
            echo "  - ${type}: ${name}"
        fi
    done
    
    echo
    log_warning "This action cannot be undone. All data will be permanently lost."
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    if [[ "${REPLY}" != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation failed"
        exit 0
    fi
}

# Execute command with dry run support
execute_command() {
    local description="$1"
    shift
    local command=("$@")
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${command[*]}"
        log_info "[DRY RUN] Description: ${description}"
        return 0
    else
        log_info "Executing: ${description}"
        if "${command[@]}" --quiet 2>/dev/null; then
            log_success "${description} completed"
            return 0
        else
            log_warning "${description} failed or resource not found"
            return 1
        fi
    fi
}

# Delete migration jobs
delete_migration_jobs() {
    log_info "Cleaning up Database Migration Service jobs..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "migration-job" ]]; then
            # Stop migration job first if running
            execute_command "Stopping migration job ${name}" \
                gcloud datamigration migration-jobs stop "${name}" --region="${location}"
            
            # Wait a moment for the job to stop
            if [[ "${DRY_RUN}" == "false" ]]; then
                sleep 10
            fi
            
            # Delete migration job
            execute_command "Deleting migration job ${name}" \
                gcloud datamigration migration-jobs delete "${name}" --region="${location}"
        fi
    done
}

# Delete connection profiles
delete_connection_profiles() {
    log_info "Cleaning up Database Migration Service connection profiles..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "connection-profile" ]]; then
            execute_command "Deleting connection profile ${name}" \
                gcloud datamigration connection-profiles delete "${name}" --region="${location}"
        fi
    done
}

# Delete Cloud SQL instances
delete_cloud_sql_instances() {
    log_info "Cleaning up Cloud SQL instances..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "cloudsql" ]]; then
            # Remove deletion protection first
            execute_command "Removing deletion protection for ${name}" \
                gcloud sql instances patch "${name}" --no-deletion-protection
            
            # Delete the instance
            execute_command "Deleting Cloud SQL instance ${name}" \
                gcloud sql instances delete "${name}"
        fi
    done
}

# Delete Application Design Center resources
delete_application_design_center() {
    log_info "Cleaning up Application Design Center resources..."
    
    local region="${REGION:-us-central1}"
    
    # Delete projects
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "adc-project" ]]; then
            execute_command "Deleting Application Design Center project ${name}" \
                gcloud alpha application-design-center projects delete "${name}" \
                --workspace="legacy-modernization-workspace" --region="${region}"
        fi
    done
    
    # Delete workspaces
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "adc-workspace" ]]; then
            execute_command "Deleting Application Design Center workspace ${name}" \
                gcloud alpha application-design-center workspaces delete "${name}" --region="${region}"
        fi
    done
}

# Delete source repositories
delete_source_repositories() {
    log_info "Cleaning up Source Repositories..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "source-repo" ]]; then
            execute_command "Deleting source repository ${name}" \
                gcloud source repos delete "${name}"
        fi
    done
}

# Delete logging resources
delete_logging_resources() {
    log_info "Cleaning up logging resources..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ "${type}" == "log-sink" ]]; then
            execute_command "Deleting log sink ${name}" \
                gcloud logging sinks delete "${name}"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.created_resources"
        "${SCRIPT_DIR}/.env"
        "${SCRIPT_DIR}/deployment-summary.md"
        "${SCRIPT_DIR}/source-profile-config.yaml"
        "${SCRIPT_DIR}/migration-job-config.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove file: ${file}"
            else
                rm -f "${file}"
                log_success "Removed file: ${file}"
            fi
        fi
    done
    
    # Remove cloned repository directory
    local repo_dir="${SCRIPT_DIR}/legacy-app-modernization"
    if [[ -d "${repo_dir}" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would remove directory: ${repo_dir}"
        else
            rm -rf "${repo_dir}"
            log_success "Removed directory: ${repo_dir}"
        fi
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed. No actual resources were deleted."
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    local project_id=$(gcloud config get-value project)
    local region="${REGION:-us-central1}"
    local remaining_resources=0
    
    # Check for remaining Cloud SQL instances
    local sql_instances
    sql_instances=$(gcloud sql instances list --format="value(name)" --filter="name:modernized-postgres-*" 2>/dev/null | wc -l || echo "0")
    if [[ "${sql_instances}" -gt 0 ]]; then
        log_warning "Found ${sql_instances} remaining Cloud SQL instances"
        ((remaining_resources += sql_instances))
    fi
    
    # Check for remaining migration jobs
    local migration_jobs
    migration_jobs=$(gcloud datamigration migration-jobs list --region="${region}" --format="value(name)" --filter="name:legacy-modernization-*" 2>/dev/null | wc -l || echo "0")
    if [[ "${migration_jobs}" -gt 0 ]]; then
        log_warning "Found ${migration_jobs} remaining migration jobs"
        ((remaining_resources += migration_jobs))
    fi
    
    # Check for remaining source repositories
    local source_repos
    source_repos=$(gcloud source repos list --format="value(name)" --filter="name:legacy-app-modernization" 2>/dev/null | wc -l || echo "0")
    if [[ "${source_repos}" -gt 0 ]]; then
        log_warning "Found ${source_repos} remaining source repositories"
        ((remaining_resources += source_repos))
    fi
    
    if [[ "${remaining_resources}" -eq 0 ]]; then
        log_success "Cleanup verification completed - no remaining resources found"
    else
        log_warning "Cleanup verification found ${remaining_resources} remaining resources"
        log_warning "Some resources may need manual cleanup or have dependencies"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    local report_file="${SCRIPT_DIR}/cleanup-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "${report_file}" << EOF
# Legacy Database Applications Modernization - Cleanup Report

Date: $(date)
Script: $0
Options: $*

## Cleanup Summary

Total resources processed: ${#CREATED_RESOURCES[@]}
Cleanup mode: $(if [[ "${DRY_RUN}" == "true" ]]; then echo "DRY RUN"; elif [[ "${PARTIAL_CLEANUP}" == "true" ]]; then echo "PARTIAL"; else echo "FULL"; fi)

## Resources Processed

EOF
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name location <<< "${resource}"
        if [[ -n "${location}" ]]; then
            echo "- ${type}: ${name} (${location})" >> "${report_file}"
        else
            echo "- ${type}: ${name}" >> "${report_file}"
        fi
    done
    
    cat >> "${report_file}" << EOF

## Cleanup Log

For detailed cleanup log, see: ${LOG_FILE}

## Next Steps

$(if [[ "${DRY_RUN}" == "true" ]]; then
    echo "This was a dry run. To perform actual cleanup, run the script without --dry-run."
else
    echo "Cleanup completed. Verify that all resources have been removed from the Google Cloud Console."
fi)

EOF
    
    log_success "Cleanup report generated: ${report_file}"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Legacy Database Applications modernization infrastructure..."
    log_info "Cleanup log: ${LOG_FILE}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    check_prerequisites
    load_created_resources
    discover_resources
    
    if [[ ${#CREATED_RESOURCES[@]} -eq 0 ]]; then
        log_info "No resources found to clean up"
        exit 0
    fi
    
    confirm_cleanup
    
    # Delete resources in reverse dependency order
    delete_migration_jobs
    delete_connection_profiles
    delete_cloud_sql_instances
    delete_application_design_center
    delete_source_repositories
    delete_logging_resources
    cleanup_local_files
    
    verify_cleanup
    generate_cleanup_report
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed successfully!"
        log_info "To perform actual cleanup, run: $0 $(echo "$@" | sed 's/--dry-run//')"
    else
        log_success "Cleanup completed successfully!"
        log_info "All Legacy Database Applications modernization resources have been removed"
    fi
    
    echo
    log_success "🧹 Cleanup process finished!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main "$@"
fi
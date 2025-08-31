#!/bin/bash

# Conversational AI Training Data Generation - Cleanup Script
# This script safely removes all GCP resources created by the deployment script
# including Cloud Functions, Cloud Storage, monitoring, and optionally the project

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false
PRESERVE_PROJECT=false
PRESERVE_DATA=false

# Function to log messages with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $*" | tee -a "${ERROR_LOG}" >&2
}

# Function to print colored output
print_status() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to print section headers
print_header() {
    echo ""
    print_status "${BLUE}" "============================================"
    print_status "${BLUE}" "$*"
    print_status "${BLUE}" "============================================"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to ask for user confirmation
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "${SKIP_CONFIRMATION}" = "true" ]; then
        log "Auto-confirming: ${message}"
        return 0
    fi
    
    local prompt
    if [ "${default}" = "y" ]; then
        prompt="${message} [Y/n]: "
    else
        prompt="${message} [y/N]: "
    fi
    
    while true; do
        read -p "${prompt}" -r response
        
        if [ -z "${response}" ]; then
            response="${default}"
        fi
        
        case "${response,,}" in
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

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required CLI tools
    if ! command_exists gcloud; then
        missing_tools+=("gcloud CLI")
    fi
    
    if ! command_exists gsutil; then
        missing_tools+=("gsutil (Google Cloud Storage CLI)")
    fi
    
    # Report missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - ${tool}"
        done
        print_status "${RED}" "Please install missing tools and retry."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
        log_error "gcloud is not authenticated"
        print_status "${RED}" "Please run 'gcloud auth login' and retry."
        exit 1
    fi
    
    print_status "${GREEN}" "✅ All prerequisites satisfied"
}

# Function to detect existing resources
detect_resources() {
    print_header "Detecting Existing Resources"
    
    # Get current project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -z "${CURRENT_PROJECT}" ]; then
        log_error "No active GCP project found"
        print_status "${RED}" "Please set an active project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log "Current project: ${CURRENT_PROJECT}"
    
    # Find conversation generation resources
    log "Scanning for conversation generation resources..."
    
    # Find Cloud Functions
    FUNCTIONS=$(gcloud functions list --filter="name:conversation-generator OR name:data-processor" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Find Storage buckets
    BUCKETS=$(gsutil ls -p "${CURRENT_PROJECT}" 2>/dev/null | \
        grep -E "gs://training-data-[a-f0-9]{6}/" | \
        sed 's|gs://||; s|/$||' || echo "")
    
    # Find log metrics
    METRICS=$(gcloud logging metrics list --filter="name:conversation_generation" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Display findings
    log "Found resources:"
    
    if [ -n "${FUNCTIONS}" ]; then
        log "  Cloud Functions:"
        echo "${FUNCTIONS}" | while read -r func; do
            if [ -n "${func}" ]; then
                log "    - ${func}"
            fi
        done
    else
        log "  Cloud Functions: None found"
    fi
    
    if [ -n "${BUCKETS}" ]; then
        log "  Storage Buckets:"
        echo "${BUCKETS}" | while read -r bucket; do
            if [ -n "${bucket}" ]; then
                log "    - ${bucket}"
            fi
        done
    else
        log "  Storage Buckets: None found"
    fi
    
    if [ -n "${METRICS}" ]; then
        log "  Log Metrics:"
        echo "${METRICS}" | while read -r metric; do
            if [ -n "${metric}" ]; then
                log "    - ${metric}"
            fi
        done
    else
        log "  Log Metrics: None found"
    fi
    
    # Check if any resources were found
    if [ -z "${FUNCTIONS}" ] && [ -z "${BUCKETS}" ] && [ -z "${METRICS}" ]; then
        print_status "${YELLOW}" "⚠️ No conversation generation resources found in project ${CURRENT_PROJECT}"
        
        if ! confirm "Continue with cleanup anyway?"; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    print_status "${GREEN}" "✅ Resource detection complete"
}

# Function to backup data before cleanup
backup_data() {
    if [ "${PRESERVE_DATA}" = "false" ]; then
        return 0
    fi
    
    print_header "Backing Up Training Data"
    
    local backup_dir="${SCRIPT_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_dir}"
    
    log "Creating backup directory: ${backup_dir}"
    
    if [ -n "${BUCKETS}" ]; then
        echo "${BUCKETS}" | while read -r bucket; do
            if [ -n "${bucket}" ]; then
                log "Backing up bucket: ${bucket}"
                
                # Create bucket-specific backup directory
                local bucket_backup="${backup_dir}/${bucket}"
                mkdir -p "${bucket_backup}"
                
                # Download all bucket contents
                if ! gsutil -m cp -r "gs://${bucket}/*" "${bucket_backup}/" 2>/dev/null; then
                    log "⚠️ Some files in ${bucket} may not have been backed up"
                fi
                
                # Create bucket metadata file
                cat > "${bucket_backup}/metadata.json" << EOF
{
  "bucket_name": "${bucket}",
  "backup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "${CURRENT_PROJECT}",
  "backup_method": "gsutil"
}
EOF
            fi
        done
        
        log "✅ Data backup completed: ${backup_dir}"
        print_status "${GREEN}" "Training data backed up to: ${backup_dir}"
    else
        log "No storage buckets found for backup"
    fi
}

# Function to remove Cloud Functions
remove_functions() {
    print_header "Removing Cloud Functions"
    
    if [ -z "${FUNCTIONS}" ]; then
        log "No Cloud Functions to remove"
        return 0
    fi
    
    log "Removing Cloud Functions..."
    
    echo "${FUNCTIONS}" | while read -r func; do
        if [ -n "${func}" ]; then
            log "Deleting function: ${func}"
            
            if gcloud functions delete "${func}" --quiet 2>/dev/null; then
                log "✅ Deleted function: ${func}"
            else
                log_error "Failed to delete function: ${func}"
                if [ "${FORCE_CLEANUP}" = "false" ]; then
                    if ! confirm "Continue with cleanup despite function deletion failure?"; then
                        log "Cleanup cancelled by user"
                        exit 1
                    fi
                fi
            fi
        fi
    done
    
    print_status "${GREEN}" "✅ Cloud Functions cleanup complete"
}

# Function to remove Storage buckets
remove_storage() {
    print_header "Removing Cloud Storage Resources"
    
    if [ -z "${BUCKETS}" ]; then
        log "No Storage buckets to remove"
        return 0
    fi
    
    if [ "${PRESERVE_DATA}" = "true" ]; then
        log "Skipping Storage deletion (data preservation enabled)"
        return 0
    fi
    
    log "Removing Storage buckets..."
    
    echo "${BUCKETS}" | while read -r bucket; do
        if [ -n "${bucket}" ]; then
            log "Processing bucket: ${bucket}"
            
            # Check if bucket exists and has objects
            local object_count
            object_count=$(gsutil ls "gs://${bucket}/**" 2>/dev/null | wc -l || echo "0")
            
            if [ "${object_count}" -gt 0 ]; then
                if ! confirm "Bucket ${bucket} contains ${object_count} objects. Delete all objects and bucket?" "n"; then
                    log "Skipping bucket: ${bucket}"
                    continue
                fi
                
                log "Deleting all objects in bucket: ${bucket}"
                if ! gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null; then
                    log_error "Failed to delete objects in bucket: ${bucket}"
                    if [ "${FORCE_CLEANUP}" = "false" ]; then
                        if ! confirm "Continue with bucket deletion despite object deletion failure?"; then
                            continue
                        fi
                    fi
                fi
            fi
            
            log "Deleting bucket: ${bucket}"
            if gsutil rb "gs://${bucket}" 2>/dev/null; then
                log "✅ Deleted bucket: ${bucket}"
            else
                log_error "Failed to delete bucket: ${bucket}"
                if [ "${FORCE_CLEANUP}" = "false" ]; then
                    if ! confirm "Continue with cleanup despite bucket deletion failure?"; then
                        log "Cleanup cancelled by user"
                        exit 1
                    fi
                fi
            fi
        fi
    done
    
    print_status "${GREEN}" "✅ Storage cleanup complete"
}

# Function to remove monitoring resources
remove_monitoring() {
    print_header "Removing Monitoring Resources"
    
    if [ -z "${METRICS}" ]; then
        log "No log metrics to remove"
        return 0
    fi
    
    log "Removing log-based metrics..."
    
    echo "${METRICS}" | while read -r metric; do
        if [ -n "${metric}" ]; then
            log "Deleting metric: ${metric}"
            
            if gcloud logging metrics delete "${metric}" --quiet 2>/dev/null; then
                log "✅ Deleted metric: ${metric}"
            else
                log_error "Failed to delete metric: ${metric}"
                if [ "${FORCE_CLEANUP}" = "false" ]; then
                    if ! confirm "Continue with cleanup despite metric deletion failure?"; then
                        log "Cleanup cancelled by user"
                        exit 1
                    fi
                fi
            fi
        fi
    done
    
    print_status "${GREEN}" "✅ Monitoring cleanup complete"
}

# Function to remove the project (optional)
remove_project() {
    if [ "${PRESERVE_PROJECT}" = "true" ]; then
        log "Skipping project deletion (project preservation enabled)"
        return 0
    fi
    
    print_header "Project Cleanup Options"
    
    print_status "${YELLOW}" "⚠️ PROJECT DELETION WARNING"
    print_status "${YELLOW}" "Deleting the project will permanently remove:"
    print_status "${YELLOW}" "  - All resources in the project"
    print_status "${YELLOW}" "  - All data and configurations"
    print_status "${YELLOW}" "  - Billing history and usage data"
    print_status "${YELLOW}" "  - This action CANNOT be undone"
    
    if ! confirm "Do you want to DELETE the entire project '${CURRENT_PROJECT}'?" "n"; then
        log "Project deletion cancelled by user"
        return 0
    fi
    
    # Additional confirmation for project deletion
    print_status "${RED}" "FINAL CONFIRMATION REQUIRED"
    echo -n "Type the project ID '${CURRENT_PROJECT}' to confirm deletion: "
    read -r confirmation
    
    if [ "${confirmation}" != "${CURRENT_PROJECT}" ]; then
        log "Project deletion cancelled - confirmation failed"
        return 0
    fi
    
    log "Deleting project: ${CURRENT_PROJECT}"
    
    if gcloud projects delete "${CURRENT_PROJECT}" --quiet; then
        log "✅ Project deleted: ${CURRENT_PROJECT}"
        print_status "${GREEN}" "✅ Project '${CURRENT_PROJECT}' has been deleted"
    else
        log_error "Failed to delete project: ${CURRENT_PROJECT}"
        print_status "${RED}" "❌ Failed to delete project. You may need to delete it manually."
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    print_header "Verifying Cleanup Completion"
    
    local remaining_resources=()
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --filter="name:conversation-generator OR name:data-processor" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "${remaining_functions}" ]; then
        remaining_resources+=("Cloud Functions: $(echo "${remaining_functions}" | tr '\n' ' ')")
    fi
    
    # Check for remaining buckets (if not preserved)
    if [ "${PRESERVE_DATA}" = "false" ]; then
        local remaining_buckets
        remaining_buckets=$(gsutil ls -p "${CURRENT_PROJECT}" 2>/dev/null | \
            grep -E "gs://training-data-[a-f0-9]{6}/" | \
            sed 's|gs://||; s|/$||' || echo "")
        
        if [ -n "${remaining_buckets}" ]; then
            remaining_resources+=("Storage Buckets: $(echo "${remaining_buckets}" | tr '\n' ' ')")
        fi
    fi
    
    # Check for remaining metrics
    local remaining_metrics
    remaining_metrics=$(gcloud logging metrics list --filter="name:conversation_generation" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "${remaining_metrics}" ]; then
        remaining_resources+=("Log Metrics: $(echo "${remaining_metrics}" | tr '\n' ' ')")
    fi
    
    # Report results
    if [ ${#remaining_resources[@]} -eq 0 ]; then
        log "✅ All targeted resources have been successfully removed"
        print_status "${GREEN}" "✅ Cleanup verification successful"
    else
        log "⚠️ Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log "  - ${resource}"
        done
        print_status "${YELLOW}" "⚠️ Some resources may require manual cleanup"
    fi
}

# Function to display cleanup summary
show_summary() {
    print_header "Cleanup Summary"
    
    log "Cleanup operation completed!"
    log ""
    log "Actions performed:"
    
    if [ -n "${FUNCTIONS}" ]; then
        log "  ✅ Removed Cloud Functions"
    fi
    
    if [ -n "${BUCKETS}" ]; then
        if [ "${PRESERVE_DATA}" = "true" ]; then
            log "  📁 Preserved Storage buckets (data backup mode)"
        else
            log "  ✅ Removed Storage buckets"
        fi
    fi
    
    if [ -n "${METRICS}" ]; then
        log "  ✅ Removed monitoring metrics"
    fi
    
    if [ "${PRESERVE_PROJECT}" = "false" ]; then
        log "  ✅ Project deletion attempted"
    else
        log "  📁 Preserved project"
    fi
    
    log ""
    log "Cost impact:"
    log "  - Ongoing charges for Cloud Functions: Eliminated"
    log "  - Storage costs: $(if [ "${PRESERVE_DATA}" = "true" ]; then echo "Continuing (data preserved)"; else echo "Eliminated"; fi)"
    log "  - API usage charges: Eliminated"
    log ""
    
    if [ "${PRESERVE_DATA}" = "true" ]; then
        log "Data preservation:"
        log "  - Training data has been backed up locally"
        log "  - Storage buckets preserved for future use"
        log "  - Consider manual cleanup when data is no longer needed"
        log ""
    fi
    
    log "Next steps:"
    if [ "${PRESERVE_PROJECT}" = "true" ]; then
        log "  - Project '${CURRENT_PROJECT}' remains active"
        log "  - Monitor for any remaining charges in billing console"
        log "  - Consider deleting the project if no longer needed"
    else
        log "  - Project deletion may take several minutes to complete"
        log "  - Verify project deletion in GCP Console"
    fi
    
    print_status "${GREEN}" "🎉 Cleanup completed successfully!"
}

# Function to handle script errors
handle_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    print_status "${RED}" "❌ Cleanup failed. Check ${ERROR_LOG} for details."
    
    if [ "${FORCE_CLEANUP}" = "false" ]; then
        print_status "${YELLOW}" "💡 Try running with --force to continue cleanup despite errors"
    fi
    
    exit "${exit_code}"
}

# Function to handle script interruption
handle_interrupt() {
    log "Cleanup interrupted by user"
    print_status "${YELLOW}" "⚠️ Cleanup interrupted. Some resources may remain."
    print_status "${YELLOW}" "Re-run the script to continue cleanup."
    exit 130
}

# Main cleanup function
main() {
    # Set up error handling
    trap handle_error ERR
    trap handle_interrupt SIGINT SIGTERM
    
    # Initialize logging
    log "Starting Conversational AI Training Data Generation cleanup"
    log "Script version: 1.0"
    log "Timestamp: $(date)"
    log "Options: force=${FORCE_CLEANUP}, preserve_project=${PRESERVE_PROJECT}, preserve_data=${PRESERVE_DATA}"
    
    # Show initial warning
    print_status "${YELLOW}" "⚠️ This script will remove GCP resources and may incur final charges."
    print_status "${YELLOW}" "Make sure you have backed up any important data before proceeding."
    
    if ! confirm "Do you want to proceed with the cleanup?" "n"; then
        log "Cleanup cancelled by user"
        print_status "${BLUE}" "Cleanup cancelled. No resources were modified."
        exit 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    detect_resources
    backup_data
    remove_functions
    remove_storage
    remove_monitoring
    remove_project
    verify_cleanup
    show_summary
    
    log "Cleanup completed successfully at $(date)"
}

# Script usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove Conversational AI Training Data Generation infrastructure from GCP

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Force cleanup, continue despite errors
    -y, --yes               Skip confirmation prompts (auto-confirm)
    --preserve-project      Don't delete the GCP project
    --preserve-data         Backup and preserve training data
    --dry-run              Show what would be deleted without removing resources

EXAMPLES:
    $0                              # Interactive cleanup with confirmations
    $0 --force --yes                # Force cleanup without prompts
    $0 --preserve-project           # Clean up resources but keep project
    $0 --preserve-data              # Backup data before cleanup
    $0 --dry-run                    # Preview cleanup actions

SAFETY FEATURES:
    - Interactive confirmations for destructive actions
    - Data backup options before deletion
    - Resource verification before and after cleanup
    - Detailed logging of all operations
    - Project deletion requires double confirmation

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--force)
            FORCE_CLEANUP=true
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            ;;
        --preserve-project)
            PRESERVE_PROJECT=true
            ;;
        --preserve-data)
            PRESERVE_DATA=true
            ;;
        --dry-run)
            print_status "${BLUE}" "Dry run mode - would check for and remove:"
            print_status "${BLUE}" "  - Cloud Functions (conversation-generator-*, data-processor-*)"
            print_status "${BLUE}" "  - Storage buckets (training-data-*)"
            print_status "${BLUE}" "  - Log metrics (conversation_generation_*)"
            print_status "${BLUE}" "  - GCP project (with confirmation)"
            print_status "${BLUE}" ""
            print_status "${BLUE}" "Run without --dry-run to perform actual cleanup"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
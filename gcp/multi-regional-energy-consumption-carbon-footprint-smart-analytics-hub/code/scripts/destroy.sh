#!/bin/bash

# Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub - Cleanup Script
# This script safely removes all resources created by the carbon optimization system
# 
# Prerequisites:
# - Google Cloud SDK installed and authenticated
# - Access to the project with appropriate permissions
# - Resources were deployed using the companion deploy.sh script

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
DRY_RUN=false
VERBOSE=false
FORCE=false
SKIP_CONFIRMATIONS=false

# Resource identification patterns
DATASET_PATTERN="carbon_analytics_*"
EXCHANGE_PATTERN="energy-optimization-exchange-*"
FUNCTION_PATTERN="workload-optimizer-*"
SCHEDULER_PATTERN="carbon-optimizer-*"

# Function to log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log "INFO" "${message}"
}

# Function to print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub resources

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION            GCP region (default: us-central1)
    -d, --dry-run                  Show what would be deleted without executing
    -v, --verbose                  Enable verbose output
    -f, --force                    Delete resources without individual confirmations
    -y, --yes                      Skip all confirmation prompts (dangerous)
    -h, --help                    Show this help message

EXAMPLES:
    $0 -p my-project-id
    $0 --project-id my-project --region europe-west1
    $0 -p my-project --dry-run
    $0 -p my-project --force --yes

SAFETY FEATURES:
    • Resource identification by naming patterns
    • Confirmation prompts for destructive operations
    • Dry-run mode to preview deletions
    • Comprehensive logging of all operations
    • Graceful handling of missing resources

EOF
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    local resource_type="$2"
    
    if [[ "${SKIP_CONFIRMATIONS}" == "true" ]]; then
        return 0
    fi
    
    if [[ "${FORCE}" == "true" ]]; then
        log "WARN" "Force mode enabled - skipping confirmation for ${resource_type}"
        return 0
    fi
    
    print_status "${YELLOW}" "${message}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "${BLUE}" "Skipping ${resource_type} deletion"
        return 1
    fi
    return 0
}

# Function to validate prerequisites
validate_prerequisites() {
    print_status "${BLUE}" "🔍 Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_status "${RED}" "❌ Google Cloud SDK is not installed"
        log "ERROR" "gcloud command not found"
        exit 1
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        print_status "${RED}" "❌ Not authenticated with Google Cloud SDK"
        log "ERROR" "No active gcloud authentication found"
        exit 1
    fi

    # Validate project ID format
    if [[ ! "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        print_status "${RED}" "❌ Invalid project ID format: ${PROJECT_ID}"
        log "ERROR" "Project ID must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        print_status "${RED}" "❌ Project ${PROJECT_ID} does not exist or is not accessible"
        log "ERROR" "Project ${PROJECT_ID} not found"
        exit 1
    fi

    # Set project context
    gcloud config set project "${PROJECT_ID}" || {
        print_status "${RED}" "❌ Failed to set project context"
        exit 1
    }

    print_status "${GREEN}" "✅ Prerequisites validation completed"
}

# Function to discover resources
discover_resources() {
    print_status "${BLUE}" "🔍 Discovering carbon optimization resources..."

    # Discover BigQuery datasets
    local datasets
    datasets=$(bq ls --format=json | jq -r ".[].datasetReference.datasetId // empty" | grep -E "${DATASET_PATTERN}" || true)
    
    # Discover Analytics Hub exchanges
    local exchanges
    exchanges=$(bq ls --data_exchange --location="${REGION}" --format=json 2>/dev/null | jq -r ".[].name // empty" | grep -E "${EXCHANGE_PATTERN}" || true)
    
    # Discover Cloud Functions
    local functions
    functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" | grep -E "${FUNCTION_PATTERN}" || true)
    
    # Discover Cloud Scheduler jobs
    local schedulers
    schedulers=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" | grep -E "${SCHEDULER_PATTERN}" || true)

    # Display discovered resources
    if [[ "${VERBOSE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${BLUE}" "📋 Discovered resources:"
        
        if [[ -n "${datasets}" ]]; then
            echo "  BigQuery Datasets:"
            echo "${datasets}" | sed 's/^/    • /'
        fi
        
        if [[ -n "${exchanges}" ]]; then
            echo "  Analytics Hub Exchanges:"
            echo "${exchanges}" | sed 's/^/    • /'
        fi
        
        if [[ -n "${functions}" ]]; then
            echo "  Cloud Functions:"
            echo "${functions}" | sed 's/^/    • /'
        fi
        
        if [[ -n "${schedulers}" ]]; then
            echo "  Cloud Scheduler Jobs:"
            echo "${schedulers}" | sed 's/^/    • /'
        fi
    fi

    # Store discovered resources in global variables for cleanup functions
    DISCOVERED_DATASETS="${datasets}"
    DISCOVERED_EXCHANGES="${exchanges}"
    DISCOVERED_FUNCTIONS="${functions}"
    DISCOVERED_SCHEDULERS="${schedulers}"

    local total_resources=0
    [[ -n "${datasets}" ]] && total_resources=$((total_resources + $(echo "${datasets}" | wc -l)))
    [[ -n "${exchanges}" ]] && total_resources=$((total_resources + $(echo "${exchanges}" | wc -l)))
    [[ -n "${functions}" ]] && total_resources=$((total_resources + $(echo "${functions}" | wc -l)))
    [[ -n "${schedulers}" ]] && total_resources=$((total_resources + $(echo "${schedulers}" | wc -l)))

    print_status "${GREEN}" "✅ Resource discovery completed (${total_resources} resources found)"
}

# Function to remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    if [[ -z "${DISCOVERED_SCHEDULERS}" ]]; then
        print_status "${BLUE}" "ℹ️  No Cloud Scheduler jobs found matching pattern"
        return 0
    fi

    if ! confirm_action "⚠️  Delete Cloud Scheduler jobs?" "Cloud Scheduler jobs"; then
        return 0
    fi

    print_status "${BLUE}" "⏰ Removing Cloud Scheduler jobs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "${DISCOVERED_SCHEDULERS}" | while read -r job; do
            [[ -n "${job}" ]] && print_status "${YELLOW}" "[DRY RUN] Would delete scheduler job: ${job}"
        done
        return 0
    fi

    local failed_deletions=()
    echo "${DISCOVERED_SCHEDULERS}" | while read -r job; do
        if [[ -n "${job}" ]]; then
            print_status "${BLUE}" "🗑️  Deleting scheduler job: ${job}"
            if gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet; then
                log "INFO" "Successfully deleted scheduler job: ${job}"
            else
                log "ERROR" "Failed to delete scheduler job: ${job}"
                failed_deletions+=("${job}")
            fi
        fi
    done

    if [[ ${#failed_deletions[@]} -gt 0 ]]; then
        print_status "${YELLOW}" "⚠️  Some scheduler jobs failed to delete: ${failed_deletions[*]}"
    else
        print_status "${GREEN}" "✅ All Cloud Scheduler jobs removed successfully"
    fi
}

# Function to remove Cloud Functions
remove_cloud_functions() {
    if [[ -z "${DISCOVERED_FUNCTIONS}" ]]; then
        print_status "${BLUE}" "ℹ️  No Cloud Functions found matching pattern"
        return 0
    fi

    if ! confirm_action "⚠️  Delete Cloud Functions?" "Cloud Functions"; then
        return 0
    fi

    print_status "${BLUE}" "⚡ Removing Cloud Functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "${DISCOVERED_FUNCTIONS}" | while read -r function; do
            [[ -n "${function}" ]] && print_status "${YELLOW}" "[DRY RUN] Would delete function: ${function}"
        done
        return 0
    fi

    local failed_deletions=()
    echo "${DISCOVERED_FUNCTIONS}" | while read -r function; do
        if [[ -n "${function}" ]]; then
            print_status "${BLUE}" "🗑️  Deleting Cloud Function: ${function}"
            if gcloud functions delete "${function}" --region="${REGION}" --quiet; then
                log "INFO" "Successfully deleted Cloud Function: ${function}"
            else
                log "ERROR" "Failed to delete Cloud Function: ${function}"
                failed_deletions+=("${function}")
            fi
        fi
    done

    if [[ ${#failed_deletions[@]} -gt 0 ]]; then
        print_status "${YELLOW}" "⚠️  Some functions failed to delete: ${failed_deletions[*]}"
    else
        print_status "${GREEN}" "✅ All Cloud Functions removed successfully"
    fi
}

# Function to remove Analytics Hub resources
remove_analytics_hub() {
    if [[ -z "${DISCOVERED_EXCHANGES}" ]]; then
        print_status "${BLUE}" "ℹ️  No Analytics Hub exchanges found matching pattern"
        return 0
    fi

    if ! confirm_action "⚠️  Delete Analytics Hub exchanges and listings?" "Analytics Hub resources"; then
        return 0
    fi

    print_status "${BLUE}" "🔄 Removing Analytics Hub resources..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "${DISCOVERED_EXCHANGES}" | while read -r exchange; do
            [[ -n "${exchange}" ]] && print_status "${YELLOW}" "[DRY RUN] Would delete exchange: ${exchange}"
        done
        return 0
    fi

    local failed_deletions=()
    echo "${DISCOVERED_EXCHANGES}" | while read -r exchange; do
        if [[ -n "${exchange}" ]]; then
            print_status "${BLUE}" "🗑️  Deleting Analytics Hub exchange: ${exchange}"
            
            # First, try to delete any listings in the exchange
            local listings
            listings=$(bq ls --listing --data_exchange="${exchange}" --location="${REGION}" --format="value(name)" 2>/dev/null || true)
            
            if [[ -n "${listings}" ]]; then
                echo "${listings}" | while read -r listing; do
                    if [[ -n "${listing}" ]]; then
                        print_status "${BLUE}" "📝 Deleting listing: ${listing}"
                        bq rm --listing "${listing}" --quiet || log "WARN" "Failed to delete listing: ${listing}"
                    fi
                done
            fi
            
            # Delete the exchange
            if bq rm --data_exchange "${exchange}" --location="${REGION}" --quiet; then
                log "INFO" "Successfully deleted Analytics Hub exchange: ${exchange}"
            else
                log "ERROR" "Failed to delete Analytics Hub exchange: ${exchange}"
                failed_deletions+=("${exchange}")
            fi
        fi
    done

    if [[ ${#failed_deletions[@]} -gt 0 ]]; then
        print_status "${YELLOW}" "⚠️  Some Analytics Hub resources failed to delete: ${failed_deletions[*]}"
    else
        print_status "${GREEN}" "✅ All Analytics Hub resources removed successfully"
    fi
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    if [[ -z "${DISCOVERED_DATASETS}" ]]; then
        print_status "${BLUE}" "ℹ️  No BigQuery datasets found matching pattern"
        return 0
    fi

    if ! confirm_action "⚠️  Delete BigQuery datasets and all contained data?" "BigQuery datasets"; then
        return 0
    fi

    print_status "${BLUE}" "📊 Removing BigQuery resources..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "${DISCOVERED_DATASETS}" | while read -r dataset; do
            [[ -n "${dataset}" ]] && print_status "${YELLOW}" "[DRY RUN] Would delete dataset: ${dataset}"
        done
        return 0
    fi

    local failed_deletions=()
    echo "${DISCOVERED_DATASETS}" | while read -r dataset; do
        if [[ -n "${dataset}" ]]; then
            print_status "${BLUE}" "🗑️  Deleting BigQuery dataset: ${dataset}"
            
            # List tables and views for logging
            local tables
            tables=$(bq ls --format="value(tableId)" "${PROJECT_ID}:${dataset}" 2>/dev/null || true)
            
            if [[ -n "${tables}" ]] && [[ "${VERBOSE}" == "true" ]]; then
                echo "    Tables/Views to be deleted:"
                echo "${tables}" | sed 's/^/      • /'
            fi
            
            # Delete dataset recursively (includes all tables and views)
            if bq rm -r -f "${PROJECT_ID}:${dataset}"; then
                log "INFO" "Successfully deleted BigQuery dataset: ${dataset}"
            else
                log "ERROR" "Failed to delete BigQuery dataset: ${dataset}"
                failed_deletions+=("${dataset}")
            fi
        fi
    done

    if [[ ${#failed_deletions[@]} -gt 0 ]]; then
        print_status "${YELLOW}" "⚠️  Some BigQuery datasets failed to delete: ${failed_deletions[*]}"
    else
        print_status "${GREEN}" "✅ All BigQuery resources removed successfully"
    fi
}

# Function to clean up temporary files and logs
cleanup_temp_files() {
    print_status "${BLUE}" "🧹 Cleaning up temporary files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would clean up temporary files"
        return 0
    fi

    # Clean up any temporary directories that might have been created
    local temp_patterns=("carbon-optimizer-function" "workload-migration")
    
    for pattern in "${temp_patterns[@]}"; do
        if [[ -d "${pattern}" ]]; then
            print_status "${BLUE}" "🗂️  Removing temporary directory: ${pattern}"
            rm -rf "${pattern}"
        fi
    done

    # Clean up any temporary files
    local temp_files=("carbon-metric.json" "alert-policy.json")
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            print_status "${BLUE}" "📄 Removing temporary file: ${file}"
            rm -f "${file}"
        fi
    done

    print_status "${GREEN}" "✅ Temporary files cleaned up"
}

# Function to verify resource deletion
verify_cleanup() {
    print_status "${BLUE}" "🔍 Verifying resource cleanup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would verify resource deletion"
        return 0
    fi

    local remaining_resources=()

    # Check for remaining BigQuery datasets
    local datasets
    datasets=$(bq ls --format=json | jq -r ".[].datasetReference.datasetId // empty" | grep -E "${DATASET_PATTERN}" || true)
    [[ -n "${datasets}" ]] && remaining_resources+=("BigQuery datasets: ${datasets}")

    # Check for remaining Analytics Hub exchanges
    local exchanges
    exchanges=$(bq ls --data_exchange --location="${REGION}" --format=json 2>/dev/null | jq -r ".[].name // empty" | grep -E "${EXCHANGE_PATTERN}" || true)
    [[ -n "${exchanges}" ]] && remaining_resources+=("Analytics Hub exchanges: ${exchanges}")

    # Check for remaining Cloud Functions
    local functions
    functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" | grep -E "${FUNCTION_PATTERN}" || true)
    [[ -n "${functions}" ]] && remaining_resources+=("Cloud Functions: ${functions}")

    # Check for remaining Cloud Scheduler jobs
    local schedulers
    schedulers=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" | grep -E "${SCHEDULER_PATTERN}" || true)
    [[ -n "${schedulers}" ]] && remaining_resources+=("Cloud Scheduler jobs: ${schedulers}")

    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        print_status "${YELLOW}" "⚠️  Some resources remain:"
        for resource in "${remaining_resources[@]}"; do
            echo "    • ${resource}"
        done
        log "WARN" "Cleanup verification found remaining resources"
    else
        print_status "${GREEN}" "✅ All resources successfully removed"
        log "INFO" "Cleanup verification completed - no remaining resources found"
    fi
}

# Function to display cleanup summary
display_summary() {
    local end_time=$(date)
    
    print_status "${GREEN}" "🎉 Cleanup completed!"
    
    cat << EOF

📋 CLEANUP SUMMARY
==================
Project ID: ${PROJECT_ID}
Region: ${REGION}
Completed at: ${end_time}

🗑️  Resources Removed:
$(if [[ -n "${DISCOVERED_DATASETS}" ]]; then echo "  • BigQuery Datasets: $(echo "${DISCOVERED_DATASETS}" | wc -l)"; fi)
$(if [[ -n "${DISCOVERED_EXCHANGES}" ]]; then echo "  • Analytics Hub Exchanges: $(echo "${DISCOVERED_EXCHANGES}" | wc -l)"; fi)
$(if [[ -n "${DISCOVERED_FUNCTIONS}" ]]; then echo "  • Cloud Functions: $(echo "${DISCOVERED_FUNCTIONS}" | wc -l)"; fi)
$(if [[ -n "${DISCOVERED_SCHEDULERS}" ]]; then echo "  • Cloud Scheduler Jobs: $(echo "${DISCOVERED_SCHEDULERS}" | wc -l)"; fi)

💡 Post-Cleanup Actions:
  1. Review Cloud Billing console for any remaining charges
  2. Check Cloud Monitoring for any orphaned custom metrics
  3. Verify IAM roles and service accounts if custom ones were created
  4. Review Cloud Logging for any remaining log entries

📝 Log File: ${LOG_FILE}

⚠️  Important Notes:
  • Some billable resources may have minimal charges for partial usage
  • Custom metrics in Cloud Monitoring may persist beyond resource deletion
  • Review the log file for any warnings or errors during cleanup

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATIONS=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_status "${RED}" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        print_status "${RED}" "❌ Project ID is required"
        usage
        exit 1
    fi
}

# Function to show final warning
show_final_warning() {
    if [[ "${SKIP_CONFIRMATIONS}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    cat << EOF

⚠️  FINAL WARNING ⚠️
=====================

This action will PERMANENTLY DELETE all resources related to the
Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub
in project: ${PROJECT_ID}

This includes:
• All BigQuery datasets and their data
• Analytics Hub exchanges and listings  
• Cloud Functions and their source code
• Cloud Scheduler jobs and their configuration
• Any custom monitoring metrics

This action CANNOT BE UNDONE!

EOF

    read -p "Are you absolutely sure you want to continue? Type 'DELETE' to confirm: " -r
    if [[ "${REPLY}" != "DELETE" ]]; then
        print_status "${BLUE}" "Operation cancelled by user"
        exit 0
    fi
}

# Main execution function
main() {
    print_status "${BLUE}" "🧹 Starting Multi-Regional Carbon Footprint Analytics Hub cleanup..."
    log "INFO" "Cleanup started with arguments: $*"

    # Initialize log file
    echo "Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub - Cleanup Log" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    echo "Script version: 1.0" >> "${LOG_FILE}"
    echo "----------------------------------------" >> "${LOG_FILE}"

    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "🧪 Running in DRY RUN mode - no resources will be deleted"
    fi

    validate_prerequisites
    discover_resources
    show_final_warning
    
    # Remove resources in reverse order of creation (dependencies first)
    remove_scheduler_jobs
    remove_cloud_functions
    remove_analytics_hub
    remove_bigquery_resources
    cleanup_temp_files
    verify_cleanup
    
    display_summary
    
    log "INFO" "Cleanup completed successfully"
    print_status "${GREEN}" "✅ All cleanup steps completed successfully!"
}

# Trap for cleanup on script exit
trap 'log "INFO" "Cleanup script execution finished"' EXIT

# Execute main function with all arguments
main "$@"
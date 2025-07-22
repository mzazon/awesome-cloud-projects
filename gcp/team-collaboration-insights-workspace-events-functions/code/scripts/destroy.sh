#!/bin/bash

# =============================================================================
# Team Collaboration Insights with Workspace Events API and Cloud Functions
# Cleanup/Destroy Script for GCP
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment-config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
FORCE_DELETE=${FORCE_DELETE:-false}
KEEP_PROJECT=${KEEP_PROJECT:-false}

# =============================================================================
# Utility Functions
# =============================================================================

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

check_command() {
    if ! command -v "${1}" &> /dev/null; then
        log_error "Required command '${1}' not found. Please install it and try again."
        exit 1
    fi
}

confirm_action() {
    local prompt="${1}"
    local default="${2:-n}"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_info "Force delete enabled, proceeding with: ${prompt}"
        return 0
    fi
    
    local response
    read -p "${prompt} [y/N]: " response
    response=${response:-${default}}
    
    if [[ "${response,,}" =~ ^(yes|y)$ ]]; then
        return 0
    else
        return 1
    fi
}

load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
        log_info "Loaded configuration from ${CONFIG_FILE}"
        return 0
    else
        log_warning "No deployment configuration found at ${CONFIG_FILE}"
        return 1
    fi
}

# =============================================================================
# Resource Inventory and Validation
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."

    # Check required commands
    check_command "gcloud"
    check_command "curl"

    # Check gcloud authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1 &>/dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi

    log_success "Prerequisites check completed"
}

validate_project_access() {
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not set. Cannot proceed with cleanup."
        exit 1
    fi

    # Check if we can access the project
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Cannot access project ${PROJECT_ID}. Please check project ID and permissions."
        exit 1
    fi

    # Set the project as active
    gcloud config set project "${PROJECT_ID}" --quiet
    log_info "Set active project to: ${PROJECT_ID}"
}

inventory_resources() {
    log_info "Taking inventory of resources to be deleted..."

    local resources_found=false

    # Check Workspace Events subscriptions
    log_info "Checking for Workspace Events subscriptions..."
    local subscriptions
    subscriptions=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://workspaceevents.googleapis.com/v1/subscriptions" 2>/dev/null | \
        jq -r '.subscriptions[]?.name // empty' 2>/dev/null || echo "")
    
    if [[ -n "${subscriptions}" ]]; then
        log_info "Found Workspace Events subscriptions:"
        echo "${subscriptions}" | while read -r sub; do
            [[ -n "${sub}" ]] && log_info "  - ${sub}"
        done
        resources_found=true
    fi

    # Check Cloud Functions
    log_info "Checking for Cloud Functions..."
    local functions
    functions=$(gcloud functions list --format="value(name)" 2>/dev/null | grep -E "(process-workspace-events|collaboration-analytics)" || echo "")
    
    if [[ -n "${functions}" ]]; then
        log_info "Found Cloud Functions:"
        echo "${functions}" | while read -r func; do
            [[ -n "${func}" ]] && log_info "  - ${func}"
        done
        resources_found=true
    fi

    # Check Pub/Sub resources
    log_info "Checking for Pub/Sub resources..."
    if gcloud pubsub topics describe workspace-events-topic &>/dev/null; then
        log_info "Found Pub/Sub topic: workspace-events-topic"
        resources_found=true
    fi

    if gcloud pubsub subscriptions describe workspace-events-subscription &>/dev/null; then
        log_info "Found Pub/Sub subscription: workspace-events-subscription"
        resources_found=true
    fi

    # Check Firestore database
    log_info "Checking for Firestore database..."
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_info "Found Firestore database: (default)"
        resources_found=true
    fi

    # Check IAM service account
    log_info "Checking for IAM service account..."
    local sa_email="workspace-events-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_info "Found service account: ${sa_email}"
        resources_found=true
    fi

    if [[ "${resources_found}" == "false" ]]; then
        log_info "No resources found to clean up."
        exit 0
    fi

    echo
    log_warning "The following resources will be PERMANENTLY DELETED:"
    log_warning "- All Workspace Events subscriptions"
    log_warning "- Cloud Functions (process-workspace-events, collaboration-analytics)"
    log_warning "- Pub/Sub topic and subscription"
    log_warning "- Firestore database and ALL data"
    log_warning "- IAM service account and permissions"
    
    if [[ "${KEEP_PROJECT}" == "false" ]]; then
        log_warning "- Google Cloud Project: ${PROJECT_ID}"
    fi
    
    echo
}

# =============================================================================
# Workspace Events Cleanup
# =============================================================================

cleanup_workspace_events() {
    log_info "Cleaning up Google Workspace Events subscriptions..."

    # Get access token
    local access_token
    access_token=$(gcloud auth print-access-token 2>/dev/null)
    
    if [[ -z "${access_token}" ]]; then
        log_warning "Cannot get access token. Skipping Workspace Events cleanup."
        return 0
    fi

    # List and delete all subscriptions
    log_info "Retrieving Workspace Events subscriptions..."
    local subscriptions_response
    subscriptions_response=$(curl -s -H "Authorization: Bearer ${access_token}" \
        "https://workspaceevents.googleapis.com/v1/subscriptions" 2>/dev/null || echo '{}')

    # Parse subscription names
    local subscription_names
    subscription_names=$(echo "${subscriptions_response}" | jq -r '.subscriptions[]?.name // empty' 2>/dev/null || echo "")

    if [[ -n "${subscription_names}" ]]; then
        log_info "Deleting Workspace Events subscriptions..."
        
        echo "${subscription_names}" | while read -r subscription_name; do
            if [[ -n "${subscription_name}" ]]; then
                log_info "Deleting subscription: ${subscription_name}"
                
                local delete_response
                delete_response=$(curl -s -X DELETE \
                    -H "Authorization: Bearer ${access_token}" \
                    "https://workspaceevents.googleapis.com/v1/${subscription_name}" \
                    -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")
                
                if [[ "${delete_response}" =~ ^(200|204|404)$ ]]; then
                    log_success "✅ Deleted subscription: ${subscription_name}"
                else
                    log_warning "⚠️  Failed to delete subscription: ${subscription_name} (HTTP ${delete_response})"
                fi
            fi
        done
    else
        log_info "No Workspace Events subscriptions found to delete"
    fi

    log_success "Workspace Events cleanup completed"
}

# =============================================================================
# Cloud Functions Cleanup
# =============================================================================

cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."

    local functions_to_delete=(
        "process-workspace-events"
        "collaboration-analytics"
    )

    for func_name in "${functions_to_delete[@]}"; do
        log_info "Checking for function: ${func_name}"
        
        if gcloud functions describe "${func_name}" &>/dev/null; then
            log_info "Deleting Cloud Function: ${func_name}"
            
            if gcloud functions delete "${func_name}" --quiet 2>>"${LOG_FILE}"; then
                log_success "✅ Deleted function: ${func_name}"
            else
                log_error "❌ Failed to delete function: ${func_name}"
            fi
        else
            log_info "Function ${func_name} not found (already deleted or never created)"
        fi
    done

    log_success "Cloud Functions cleanup completed"
}

# =============================================================================
# Pub/Sub Cleanup
# =============================================================================

cleanup_pubsub() {
    log_info "Cleaning up Pub/Sub resources..."

    # Delete subscription first (has dependency on topic)
    if gcloud pubsub subscriptions describe workspace-events-subscription &>/dev/null; then
        log_info "Deleting Pub/Sub subscription: workspace-events-subscription"
        
        if gcloud pubsub subscriptions delete workspace-events-subscription --quiet 2>>"${LOG_FILE}"; then
            log_success "✅ Deleted subscription: workspace-events-subscription"
        else
            log_error "❌ Failed to delete subscription: workspace-events-subscription"
        fi
    else
        log_info "Pub/Sub subscription not found (already deleted or never created)"
    fi

    # Delete topic
    if gcloud pubsub topics describe workspace-events-topic &>/dev/null; then
        log_info "Deleting Pub/Sub topic: workspace-events-topic"
        
        if gcloud pubsub topics delete workspace-events-topic --quiet 2>>"${LOG_FILE}"; then
            log_success "✅ Deleted topic: workspace-events-topic"
        else
            log_error "❌ Failed to delete topic: workspace-events-topic"
        fi
    else
        log_info "Pub/Sub topic not found (already deleted or never created)"
    fi

    log_success "Pub/Sub cleanup completed"
}

# =============================================================================
# Firestore Cleanup
# =============================================================================

cleanup_firestore() {
    log_info "Cleaning up Firestore database..."

    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_warning "Firestore database contains ALL collaboration data and analytics"
        
        if confirm_action "Delete Firestore database and ALL data?"; then
            log_info "Deleting Firestore database..."
            
            # Note: Firestore database deletion is a complex operation
            # We'll delete collections instead for safety
            
            log_info "Deleting Firestore collections..."
            
            # Delete collaboration_events collection
            if gcloud firestore collection-group delete collaboration_events --quiet &>/dev/null; then
                log_success "✅ Deleted collection: collaboration_events"
            else
                log_warning "⚠️  Could not delete collection: collaboration_events"
            fi
            
            # Delete team_metrics collection  
            if gcloud firestore collection-group delete team_metrics --quiet &>/dev/null; then
                log_success "✅ Deleted collection: team_metrics"
            else
                log_warning "⚠️  Could not delete collection: team_metrics"
            fi
            
            log_info "For complete database deletion, use the Firebase Console"
            log_info "or run: gcloud firestore databases delete --database='(default)'"
        else
            log_info "Skipping Firestore database deletion"
        fi
    else
        log_info "Firestore database not found (already deleted or never created)"
    fi

    log_success "Firestore cleanup completed"
}

# =============================================================================
# IAM Cleanup
# =============================================================================

cleanup_iam() {
    log_info "Cleaning up IAM resources..."

    local sa_email="workspace-events-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_info "Deleting service account: ${sa_email}"
        
        # Remove IAM policy bindings first
        log_info "Removing IAM policy bindings..."
        
        local roles=(
            "roles/pubsub.publisher"
            "roles/datastore.user"
            "roles/cloudfunctions.invoker"
        )

        for role in "${roles[@]}"; do
            log_info "Removing role binding: ${role}"
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" \
                --quiet 2>>"${LOG_FILE}" || true
        done

        # Delete service account
        if gcloud iam service-accounts delete "${sa_email}" --quiet 2>>"${LOG_FILE}"; then
            log_success "✅ Deleted service account: ${sa_email}"
        else
            log_error "❌ Failed to delete service account: ${sa_email}"
        fi
    else
        log_info "Service account not found (already deleted or never created)"
    fi

    log_success "IAM cleanup completed"
}

# =============================================================================
# Project Cleanup
# =============================================================================

cleanup_project() {
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Keeping project as requested: ${PROJECT_ID}"
        return 0
    fi

    log_warning "This will PERMANENTLY DELETE the entire project: ${PROJECT_ID}"
    log_warning "This action cannot be undone!"
    
    if confirm_action "Delete the entire project ${PROJECT_ID}?"; then
        log_info "Deleting project: ${PROJECT_ID}"
        
        if gcloud projects delete "${PROJECT_ID}" --quiet 2>>"${LOG_FILE}"; then
            log_success "✅ Project deletion initiated: ${PROJECT_ID}"
            log_info "Project deletion is asynchronous and may take several minutes to complete"
        else
            log_error "❌ Failed to delete project: ${PROJECT_ID}"
            log_info "You may need to delete the project manually from the Google Cloud Console"
        fi
    else
        log_info "Skipping project deletion"
    fi
}

# =============================================================================
# Cleanup Verification
# =============================================================================

verify_cleanup() {
    log_info "Verifying cleanup completion..."

    local cleanup_issues=false

    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" 2>/dev/null | \
        grep -E "(process-workspace-events|collaboration-analytics)" || echo "")
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "⚠️  Some Cloud Functions still exist:"
        echo "${remaining_functions}" | while read -r func; do
            [[ -n "${func}" ]] && log_warning "  - ${func}"
        done
        cleanup_issues=true
    else
        log_success "✅ All Cloud Functions cleaned up"
    fi

    # Check Pub/Sub resources
    if gcloud pubsub topics describe workspace-events-topic &>/dev/null; then
        log_warning "⚠️  Pub/Sub topic still exists: workspace-events-topic"
        cleanup_issues=true
    else
        log_success "✅ Pub/Sub topic cleaned up"
    fi

    # Check IAM service account
    local sa_email="workspace-events-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_warning "⚠️  Service account still exists: ${sa_email}"
        cleanup_issues=true
    else
        log_success "✅ Service account cleaned up"
    fi

    if [[ "${cleanup_issues}" == "true" ]]; then
        log_warning "Some resources may still exist. Check the Google Cloud Console for manual cleanup."
        return 1
    else
        log_success "All resources successfully cleaned up"
        return 0
    fi
}

# =============================================================================
# Temporary Files Cleanup
# =============================================================================

cleanup_local_files() {
    log_info "Cleaning up local temporary files..."

    local files_to_remove=(
        "${SCRIPT_DIR}/workspace-analytics-function"
        "${SCRIPT_DIR}/analytics-dashboard"
        "${SCRIPT_DIR}/workspace-config"
        "${SCRIPT_DIR}/firestore.rules"
    )

    for file_path in "${files_to_remove[@]}"; do
        if [[ -e "${file_path}" ]]; then
            log_info "Removing: ${file_path}"
            rm -rf "${file_path}" 2>/dev/null || log_warning "Could not remove: ${file_path}"
        fi
    done

    # Ask about removing configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        if confirm_action "Remove deployment configuration file (${CONFIG_FILE})?"; then
            rm -f "${CONFIG_FILE}"
            log_success "✅ Removed configuration file"
        else
            log_info "Keeping configuration file for future reference"
        fi
    fi

    log_success "Local files cleanup completed"
}

# =============================================================================
# Main Cleanup Flow
# =============================================================================

show_usage() {
    cat << EOF
Usage: ${0} [OPTIONS]

Team Collaboration Insights cleanup script for Google Cloud Platform.

OPTIONS:
    -f, --force         Skip confirmation prompts (use with caution)
    -k, --keep-project  Keep the Google Cloud project (only delete resources)
    -h, --help          Show this help message

EXAMPLES:
    ${0}                    # Interactive cleanup with confirmations
    ${0} --force            # Automated cleanup without prompts
    ${0} --keep-project     # Clean up resources but keep the project
    ${0} -f -k              # Force cleanup but keep project

ENVIRONMENT VARIABLES:
    FORCE_DELETE=true       # Same as --force flag
    KEEP_PROJECT=true       # Same as --keep-project flag

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -k|--keep-project)
                KEEP_PROJECT=true
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

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Initialize log file
    echo "=== Team Collaboration Insights Cleanup - $(date) ===" > "${LOG_FILE}"
    
    log_info "Starting cleanup of Team Collaboration Insights infrastructure"
    log_info "Script directory: ${SCRIPT_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force delete mode enabled - skipping confirmations"
    fi
    
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Keep project mode enabled - project will not be deleted"
    fi

    # Load configuration and validate access
    if ! load_config; then
        log_error "No deployment configuration found. Cannot determine what to clean up."
        log_error "If resources exist, please specify PROJECT_ID manually:"
        log_error "export PROJECT_ID=your-project-id && ${0}"
        exit 1
    fi

    # Export variables for use in functions
    export PROJECT_ID REGION ZONE RANDOM_SUFFIX

    # Execute cleanup steps
    check_prerequisites
    validate_project_access
    inventory_resources

    # Confirm before proceeding with destructive operations
    echo
    log_warning "This script will permanently delete cloud resources!"
    if ! confirm_action "Proceed with cleanup?"; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi

    # Execute cleanup in dependency order
    log_info "Starting resource cleanup..."
    cleanup_workspace_events
    cleanup_cloud_functions
    cleanup_pubsub
    cleanup_firestore
    cleanup_iam
    
    # Optional project deletion
    if [[ "${KEEP_PROJECT}" == "false" ]]; then
        cleanup_project
    fi

    # Verify cleanup
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        verify_cleanup
    fi

    # Clean up local files
    cleanup_local_files

    # Final summary
    echo
    log_success "🎉 Cleanup completed!"
    echo
    log_info "=== Cleanup Summary ==="
    log_info "Project ID: ${PROJECT_ID}"
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Project Status: Preserved (resources deleted)"
    else
        log_info "Project Status: Deletion initiated"
    fi
    echo
    log_info "Cleanup log saved to: ${LOG_FILE}"
    
    if [[ "${KEEP_PROJECT}" == "false" ]]; then
        echo
        log_info "Note: Project deletion is asynchronous and may take several minutes."
        log_info "You can monitor the deletion status in the Google Cloud Console."
    fi
}

# =============================================================================
# Script Entry Point
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
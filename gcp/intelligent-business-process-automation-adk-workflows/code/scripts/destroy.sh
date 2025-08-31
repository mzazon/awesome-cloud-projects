#!/bin/bash

# Intelligent Business Process Automation with ADK and Workflows - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper confirmation and verification steps

set -euo pipefail

# Colors for output
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTROY_LOG="${SCRIPT_DIR}/destroy.log"
RESOURCE_TRACKER="${SCRIPT_DIR}/.deployed_resources"
DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.json"

# Initialize logging
exec 1> >(tee -a "$DESTROY_LOG")
exec 2> >(tee -a "$DESTROY_LOG" >&2)

log_info "Starting cleanup at $(date)"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment info file first
    if [[ -f "$DEPLOYMENT_INFO" ]]; then
        log_info "Found deployment info file, loading resource details..."
        
        # Extract values using basic parsing (avoiding jq dependency)
        export PROJECT_ID=$(grep '"project_id"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        export REGION=$(grep '"region"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        
        # Extract resource names
        export DB_INSTANCE=$(grep '"sql_instance"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        export WORKFLOW_NAME=$(grep '"workflow"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        export FUNCTION_APPROVAL=$(grep '"approval"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        export FUNCTION_NOTIFY=$(grep '"notification"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        export AGENT_APP=$(grep '"agent"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        
        log_success "Loaded deployment information from $DEPLOYMENT_INFO"
    elif [[ -f "$RESOURCE_TRACKER" ]]; then
        log_info "Found resource tracker file, loading resource details..."
        
        # Parse resource tracker file
        while IFS=':' read -r resource_type resource_name resource_location; do
            case "$resource_type" in
                "sql_instance")
                    export DB_INSTANCE="$resource_name"
                    export REGION="$resource_location"
                    ;;
                "workflow")
                    export WORKFLOW_NAME="$resource_name"
                    ;;
                "function")
                    case "$resource_name" in
                        *"approval"*)
                            export FUNCTION_APPROVAL="$resource_name"
                            ;;
                        *"notification"*|*"notify"*)
                            export FUNCTION_NOTIFY="$resource_name"
                            ;;
                        *"agent"*)
                            export AGENT_APP="$resource_name"
                            ;;
                    esac
                    ;;
            esac
        done < "$RESOURCE_TRACKER"
        
        log_success "Loaded deployment information from resource tracker"
    else
        log_warning "No deployment information found. Using environment variables or prompting for input."
        
        # Fallback to environment variables or prompt user
        if [[ -z "${PROJECT_ID:-}" ]]; then
            read -p "Enter GCP Project ID: " PROJECT_ID
            export PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="${REGION:-us-central1}"
            log_info "Using default region: $REGION"
        fi
    fi
    
    # Set gcloud defaults
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud config set project "$PROJECT_ID" 2>/dev/null || true
    fi
    if [[ -n "${REGION:-}" ]]; then
        gcloud config set compute/region "$REGION" 2>/dev/null || true
    fi
}

# Function to display resources to be deleted
display_resources() {
    log_info "Resources scheduled for deletion:"
    echo ""
    echo "==================== RESOURCES TO DELETE ===================="
    
    if [[ -n "${PROJECT_ID:-}" ]]; then
        echo "Project ID: $PROJECT_ID"
    fi
    
    if [[ -n "${REGION:-}" ]]; then
        echo "Region: $REGION"
    fi
    
    echo ""
    echo "Cloud Functions:"
    if [[ -n "${FUNCTION_APPROVAL:-}" ]]; then
        echo "  - Approval Function: $FUNCTION_APPROVAL"
    fi
    if [[ -n "${FUNCTION_NOTIFY:-}" ]]; then
        echo "  - Notification Function: $FUNCTION_NOTIFY"
    fi
    if [[ -n "${AGENT_APP:-}" ]]; then
        echo "  - AI Agent Function: $AGENT_APP"
    fi
    
    echo ""
    echo "Cloud Workflows:"
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        echo "  - Workflow: $WORKFLOW_NAME"
    fi
    
    echo ""
    echo "Cloud SQL:"
    if [[ -n "${DB_INSTANCE:-}" ]]; then
        echo "  - Database Instance: $DB_INSTANCE"
    fi
    
    echo "============================================================="
    echo ""
}

# Function to confirm deletion
confirm_deletion() {
    display_resources
    
    log_warning "This action will permanently delete all listed resources."
    log_warning "This action cannot be undone!"
    echo ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        log_info "Force flag detected, skipping confirmation"
        return 0
    fi
    
    # Require explicit confirmation
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion, proceeding with cleanup..."
}

# Function to delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=(
        "${FUNCTION_APPROVAL:-}"
        "${FUNCTION_NOTIFY:-}"
        "${AGENT_APP:-}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -z "$func" ]]; then
            continue
        fi
        
        log_info "Checking if function $func exists..."
        if gcloud functions describe "$func" --gen2 --region="$REGION" --quiet 2>/dev/null; then
            log_info "Deleting function: $func"
            if gcloud functions delete "$func" \
                --gen2 \
                --region="$REGION" \
                --quiet; then
                log_success "Deleted function: $func"
            else
                log_error "Failed to delete function: $func"
            fi
        else
            log_warning "Function $func not found, skipping"
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Workflows
delete_workflows() {
    log_info "Deleting Cloud Workflows..."
    
    if [[ -z "${WORKFLOW_NAME:-}" ]]; then
        log_warning "No workflow name provided, skipping workflow deletion"
        return 0
    fi
    
    log_info "Checking if workflow $WORKFLOW_NAME exists..."
    if gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_info "Deleting workflow: $WORKFLOW_NAME"
        if gcloud workflows delete "$WORKFLOW_NAME" \
            --location="$REGION" \
            --quiet; then
            log_success "Deleted workflow: $WORKFLOW_NAME"
        else
            log_error "Failed to delete workflow: $WORKFLOW_NAME"
        fi
    else
        log_warning "Workflow $WORKFLOW_NAME not found, skipping"
    fi
    
    log_success "Cloud Workflows cleanup completed"
}

# Function to delete Cloud SQL instance
delete_database() {
    log_info "Deleting Cloud SQL instance..."
    
    if [[ -z "${DB_INSTANCE:-}" ]]; then
        log_warning "No database instance name provided, skipping database deletion"
        return 0
    fi
    
    log_info "Checking if Cloud SQL instance $DB_INSTANCE exists..."
    if gcloud sql instances describe "$DB_INSTANCE" --quiet 2>/dev/null; then
        log_warning "Deleting Cloud SQL instance: $DB_INSTANCE"
        log_warning "This will permanently delete all data in the database!"
        
        # Additional confirmation for database deletion
        if [[ "${1:-}" != "--force" ]]; then
            read -p "Are you sure you want to delete the database instance? Type 'DELETE-DB' to confirm: " db_confirmation
            if [[ "$db_confirmation" != "DELETE-DB" ]]; then
                log_info "Database deletion cancelled by user"
                return 0
            fi
        fi
        
        log_info "Deleting Cloud SQL instance: $DB_INSTANCE"
        if gcloud sql instances delete "$DB_INSTANCE" --quiet; then
            log_success "Deleted Cloud SQL instance: $DB_INSTANCE"
        else
            log_error "Failed to delete Cloud SQL instance: $DB_INSTANCE"
        fi
    else
        log_warning "Cloud SQL instance $DB_INSTANCE not found, skipping"
    fi
    
    log_success "Cloud SQL cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local deletion_errors=0
    
    # Check functions
    local functions=(
        "${FUNCTION_APPROVAL:-}"
        "${FUNCTION_NOTIFY:-}"
        "${AGENT_APP:-}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -z "$func" ]]; then
            continue
        fi
        
        if gcloud functions describe "$func" --gen2 --region="$REGION" --quiet 2>/dev/null; then
            log_error "Function $func still exists after deletion attempt"
            deletion_errors=$((deletion_errors + 1))
        else
            log_success "Function $func successfully deleted"
        fi
    done
    
    # Check workflow
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        if gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" --quiet 2>/dev/null; then
            log_error "Workflow $WORKFLOW_NAME still exists after deletion attempt"
            deletion_errors=$((deletion_errors + 1))
        else
            log_success "Workflow $WORKFLOW_NAME successfully deleted"
        fi
    fi
    
    # Check Cloud SQL instance
    if [[ -n "${DB_INSTANCE:-}" ]]; then
        if gcloud sql instances describe "$DB_INSTANCE" --quiet 2>/dev/null; then
            log_error "Cloud SQL instance $DB_INSTANCE still exists after deletion attempt"
            deletion_errors=$((deletion_errors + 1))
        else
            log_success "Cloud SQL instance $DB_INSTANCE successfully deleted"
        fi
    fi
    
    if [[ $deletion_errors -eq 0 ]]; then
        log_success "All resources verified as deleted successfully"
    else
        log_error "Some resources failed to delete properly. Please check manually."
        return 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "$RESOURCE_TRACKER"
        "$DEPLOYMENT_INFO"
        "${SCRIPT_DIR}/schema.sql"
        "${SCRIPT_DIR}/business-process-workflow.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $file"
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
    
    # Clean up temporary directories
    local temp_dirs=(
        "${SCRIPT_DIR}/temp_functions"
    )
    
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Removing directory: $dir"
            rm -rf "$dir"
            log_success "Removed directory: $dir"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup completed successfully!"
    echo ""
    echo "==================== CLEANUP SUMMARY ===================="
    echo "Cleanup completed at: $(date)"
    echo ""
    echo "Resources removed:"
    echo "  ✅ Cloud Functions (3 functions)"
    echo "  ✅ Cloud Workflows (1 workflow)"
    echo "  ✅ Cloud SQL Instance (1 database)"
    echo "  ✅ Local configuration files"
    echo ""
    echo "Note: Some Google Cloud APIs remain enabled."
    echo "You can disable them manually if they're not needed:"
    echo "  - Vertex AI API"
    echo "  - Cloud Workflows API"
    echo "  - Cloud SQL Admin API"
    echo "  - Cloud Functions API"
    echo "  - Cloud Build API"
    echo ""
    echo "Cleanup log saved to: $DESTROY_LOG"
    echo "============================================================="
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted by user"
    log_info "Partial cleanup may have occurred"
    log_info "Check the cleanup log for details: $DESTROY_LOG"
    exit 130
}

# Function to disable APIs (optional)
disable_apis() {
    log_info "Optionally disabling Google Cloud APIs..."
    
    read -p "Do you want to disable the Google Cloud APIs that were enabled? (y/N): " disable_apis_choice
    
    if [[ "$disable_apis_choice" =~ ^[Yy]$ ]]; then
        local apis=(
            "aiplatform.googleapis.com"
            "workflows.googleapis.com"
            "sqladmin.googleapis.com"
            "cloudfunctions.googleapis.com"
            "cloudbuild.googleapis.com"
            "eventarc.googleapis.com"
            "artifactregistry.googleapis.com"
            "run.googleapis.com"
        )
        
        log_warning "Disabling APIs may affect other services in your project"
        read -p "Are you sure? (y/N): " confirm_disable
        
        if [[ "$confirm_disable" =~ ^[Yy]$ ]]; then
            for api in "${apis[@]}"; do
                log_info "Disabling API: $api"
                if gcloud services disable "$api" --quiet --force 2>/dev/null; then
                    log_success "Disabled API: $api"
                else
                    log_warning "Could not disable API: $api (may be in use by other resources)"
                fi
            done
        else
            log_info "API disabling cancelled by user"
        fi
    else
        log_info "Skipping API disabling"
    fi
}

# Main execution function
main() {
    local force_flag="${1:-}"
    
    log_info "Starting Intelligent Business Process Automation cleanup"
    
    # Set up interrupt handler
    trap cleanup_on_interrupt SIGINT SIGTERM
    
    check_prerequisites
    load_deployment_info
    confirm_deletion "$force_flag"
    
    # Perform deletion in reverse order of creation
    delete_workflows
    delete_functions
    delete_database "$force_flag"
    
    # Verify deletion
    if verify_deletion; then
        cleanup_local_files
        display_cleanup_summary
        
        # Optional API cleanup
        if [[ "$force_flag" != "--force" ]]; then
            disable_apis
        fi
    else
        log_error "Some resources may not have been deleted properly"
        log_error "Please check the Google Cloud Console and cleanup manually if needed"
        exit 1
    fi
    
    log_success "Cleanup completed successfully at $(date)"
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Check the log file: $DESTROY_LOG"' ERR

# Usage information
usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts and force deletion"
    echo "  --help     Show this help message"
    echo ""
    echo "This script will delete all resources created by the deployment script."
    echo "Use with caution as this action cannot be undone."
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --force)
        log_info "Force mode enabled"
        main "--force"
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown argument: $1"
        usage
        exit 1
        ;;
esac
#!/bin/bash

# Location-Based Service Recommendations Cleanup Script
# This script safely removes all resources created by the deployment script

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get user confirmation for destructive operations
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    if [[ "${SKIP_CONFIRMATIONS:-false}" == "true" ]]; then
        log_warning "Skipping confirmation due to SKIP_CONFIRMATIONS=true"
        return 0
    fi
    
    while true; do
        if [[ "$default" == "Y" ]]; then
            read -p "$message (Y/n): " -n 1 -r
            echo
            [[ $REPLY =~ ^[Nn]$ ]] && return 1
            [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]] && return 0
        else
            read -p "$message (y/N): " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] && return 0
            [[ $REPLY =~ ^[Nn]$ ]] || [[ -z $REPLY ]] && return 1
        fi
    done
}

# Detect project and resources automatically
detect_resources() {
    log_info "Detecting existing resources..."
    
    # Try to get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_warning "No project ID specified and no default project configured"
            read -p "Enter the project ID to clean up: " PROJECT_ID
            if [[ -z "${PROJECT_ID}" ]]; then
                error_exit "Project ID is required for cleanup"
            fi
        fi
    fi
    
    # Set default region if not specified
    export REGION="${REGION:-us-central1}"
    export SERVICE_NAME="${SERVICE_NAME:-location-recommender}"
    
    log_info "Using Project ID: ${PROJECT_ID}"
    log_info "Using Region: ${REGION}"
    
    # Verify project exists and we have access
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        error_exit "Cannot access project ${PROJECT_ID}. Please check your permissions."
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1
}

# Main cleanup function
main() {
    log_info "Starting Location-Based Service Recommendations cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Detect existing resources
    detect_resources
    
    # Show cleanup summary
    show_cleanup_summary
    
    # Confirm destructive operation
    if ! confirm_action "⚠️  This will DELETE all resources in project ${PROJECT_ID}. Continue?"; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Perform cleanup operations
    cleanup_cloud_run_service
    cleanup_firestore_database
    cleanup_service_accounts
    cleanup_api_keys
    cleanup_local_files
    
    # Optional: Delete entire project
    offer_project_deletion
    
    log_success "Cleanup completed successfully!"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Please run: gcloud auth login"
    fi
    
    log_success "Prerequisites check completed"
}

# Show what will be cleaned up
show_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources that will be deleted:"
    
    # Check for Cloud Run service
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        local service_url
        service_url=$(gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" --format="value(status.url)" 2>/dev/null || echo "N/A")
        echo "✓ Cloud Run Service: ${SERVICE_NAME} (${service_url})"
    else
        echo "- Cloud Run Service: ${SERVICE_NAME} (not found)"
    fi
    
    # Check for Firestore databases
    local firestore_databases
    firestore_databases=$(gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -v '(default)' || echo "")
    if [[ -n "${firestore_databases}" ]]; then
        echo "✓ Firestore Databases:"
        while IFS= read -r db; do
            [[ -n "$db" ]] && echo "  - $db"
        done <<< "$firestore_databases"
    else
        echo "- Firestore Databases: (none found)"
    fi
    
    # Check for service accounts
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email:location-ai-service@${PROJECT_ID}.iam.gserviceaccount.com" 2>/dev/null || echo "")
    if [[ -n "${service_accounts}" ]]; then
        echo "✓ Service Accounts:"
        while IFS= read -r sa; do
            [[ -n "$sa" ]] && echo "  - $sa"
        done <<< "$service_accounts"
    else
        echo "- Service Accounts: (none found)"
    fi
    
    # Check for API keys
    local api_keys
    api_keys=$(gcloud services api-keys list --format="value(displayName)" --filter="displayName:'Location Recommender API Key'" 2>/dev/null || echo "")
    if [[ -n "${api_keys}" ]]; then
        echo "✓ API Keys:"
        while IFS= read -r key; do
            [[ -n "$key" ]] && echo "  - $key"
        done <<< "$api_keys"
    else
        echo "- API Keys: (none found)"
    fi
    
    # Check for local files
    local local_files=()
    [[ -d "recommendation-service" ]] && local_files+=("recommendation-service/")
    [[ -f "firestore-indexes.yaml" ]] && local_files+=("firestore-indexes.yaml")
    [[ -f "vertex-ai-config.json" ]] && local_files+=("vertex-ai-config.json")
    [[ -f "test-integration.js" ]] && local_files+=("test-integration.js")
    
    if [[ ${#local_files[@]} -gt 0 ]]; then
        echo "✓ Local Files:"
        printf "  - %s\n" "${local_files[@]}"
    else
        echo "- Local Files: (none found)"
    fi
    
    echo ""
}

# Clean up Cloud Run service
cleanup_cloud_run_service() {
    log_info "Cleaning up Cloud Run service..."
    
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_info "Deleting Cloud Run service: ${SERVICE_NAME}"
        
        gcloud run services delete "${SERVICE_NAME}" \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete Cloud Run service"
        
        # Wait for deletion to complete
        local timeout=60
        local count=0
        while gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" >/dev/null 2>&1; do
            if [[ $count -ge $timeout ]]; then
                log_warning "Timeout waiting for Cloud Run service deletion"
                break
            fi
            sleep 2
            ((count+=2))
        done
        
        log_success "Cloud Run service deleted"
    else
        log_info "Cloud Run service ${SERVICE_NAME} not found, skipping"
    fi
}

# Clean up Firestore databases
cleanup_firestore_database() {
    log_info "Cleaning up Firestore databases..."
    
    # Get all non-default databases
    local databases
    databases=$(gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -v '(default)' || echo "")
    
    if [[ -n "${databases}" ]]; then
        while IFS= read -r database; do
            if [[ -n "$database" ]]; then
                log_info "Deleting Firestore database: $database"
                
                if confirm_action "Delete Firestore database '$database'?"; then
                    gcloud firestore databases delete "$database" \
                        --quiet || log_warning "Failed to delete Firestore database: $database"
                    log_success "Firestore database $database deleted"
                else
                    log_info "Skipping Firestore database: $database"
                fi
            fi
        done <<< "$databases"
    else
        log_info "No custom Firestore databases found, skipping"
    fi
}

# Clean up service accounts
cleanup_service_accounts() {
    log_info "Cleaning up service accounts..."
    
    local service_account_email="location-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${service_account_email}" >/dev/null 2>&1; then
        log_info "Deleting service account: ${service_account_email}"
        
        gcloud iam service-accounts delete "${service_account_email}" \
            --quiet || log_warning "Failed to delete service account"
        
        log_success "Service account deleted"
    else
        log_info "Service account not found, skipping"
    fi
}

# Clean up API keys
cleanup_api_keys() {
    log_info "Cleaning up API keys..."
    
    local api_key_name
    api_key_name=$(gcloud services api-keys list \
        --format="value(name)" \
        --filter="displayName:'Location Recommender API Key'" 2>/dev/null || echo "")
    
    if [[ -n "${api_key_name}" ]]; then
        log_info "Deleting API key: Location Recommender API Key"
        
        gcloud services api-keys delete "${api_key_name}" \
            --quiet || log_warning "Failed to delete API key"
        
        log_success "API key deleted"
    else
        log_info "API key not found, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_deleted=false
    
    if [[ -d "recommendation-service" ]]; then
        log_info "Removing recommendation-service directory"
        rm -rf recommendation-service
        files_deleted=true
    fi
    
    if [[ -f "firestore-indexes.yaml" ]]; then
        log_info "Removing firestore-indexes.yaml"
        rm -f firestore-indexes.yaml
        files_deleted=true
    fi
    
    if [[ -f "vertex-ai-config.json" ]]; then
        log_info "Removing vertex-ai-config.json"
        rm -f vertex-ai-config.json
        files_deleted=true
    fi
    
    if [[ -f "test-integration.js" ]]; then
        log_info "Removing test-integration.js"
        rm -f test-integration.js
        files_deleted=true
    fi
    
    # Clean up any temp files
    rm -f /tmp/health_response.json /tmp/recommendation_response.json
    
    if [[ "$files_deleted" == "true" ]]; then
        log_success "Local files cleaned up"
    else
        log_info "No local files to clean up"
    fi
}

# Offer to delete the entire project
offer_project_deletion() {
    log_info "Cleanup of individual resources completed"
    echo ""
    
    if confirm_action "🗑️  Delete the entire project '${PROJECT_ID}'? This will remove ALL resources and cannot be undone"; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        log_warning "This action cannot be undone!"
        
        if confirm_action "Are you absolutely sure you want to delete project '${PROJECT_ID}'?"; then
            gcloud projects delete "${PROJECT_ID}" --quiet || error_exit "Failed to delete project"
            
            log_success "Project ${PROJECT_ID} has been scheduled for deletion"
            log_info "Project deletion may take several minutes to complete"
            log_info "The project will be permanently deleted after 30 days"
        else
            log_info "Project deletion cancelled"
        fi
    else
        log_info "Keeping project ${PROJECT_ID}"
        log_info "Individual resources have been cleaned up"
    fi
}

# Display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --project-id PROJECT_ID    Specify the project ID to clean up"
    echo "  -r, --region REGION            Specify the region (default: us-central1)"
    echo "  -s, --service-name NAME        Specify the service name (default: location-recommender)"
    echo "  -y, --yes                      Skip all confirmation prompts"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID                     Google Cloud project ID"
    echo "  REGION                         Google Cloud region"
    echo "  SERVICE_NAME                   Cloud Run service name"
    echo "  SKIP_CONFIRMATIONS             Set to 'true' to skip all confirmations"
    echo ""
    echo "Examples:"
    echo "  $0                             # Interactive cleanup with prompts"
    echo "  $0 -p my-project -y            # Cleanup specific project without prompts"
    echo "  $0 --project-id my-project     # Cleanup specific project with prompts"
    echo "  SKIP_CONFIRMATIONS=true $0     # Skip all confirmations"
}

# Parse command line arguments
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
            -s|--service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -y|--yes)
                export SKIP_CONFIRMATIONS=true
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

# Parse arguments and run main function
parse_arguments "$@"
main
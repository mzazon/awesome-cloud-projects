#!/bin/bash

# Cleanup Multi-Container Applications with Cloud Run and Docker Compose
# This script removes all resources created by the deployment script
# including Cloud Run services, Cloud SQL instances, Secret Manager secrets, and Artifact Registry

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment variables
load_deployment_vars() {
    log_info "Loading deployment variables..."
    
    if [[ -f ".deployment_vars" ]]; then
        # Source the deployment variables
        source .deployment_vars
        log_success "Loaded deployment variables from .deployment_vars"
        log_info "Project ID: ${PROJECT_ID:-'Not set'}"
        log_info "Service Name: ${SERVICE_NAME:-'Not set'}"
        log_info "SQL Instance: ${SQL_INSTANCE_NAME:-'Not set'}"
        log_info "Repository: ${REPOSITORY_NAME:-'Not set'}"
    else
        log_warning "No .deployment_vars file found. You'll need to provide resource names manually."
        
        # Prompt for required variables if not found
        read -p "Enter Project ID: " PROJECT_ID
        read -p "Enter Region (default: us-central1): " REGION
        REGION=${REGION:-"us-central1"}
        read -p "Enter Service Name: " SERVICE_NAME
        read -p "Enter Repository Name: " REPOSITORY_NAME
        read -p "Enter SQL Instance Name: " SQL_INSTANCE_NAME
        
        if [[ -z "${PROJECT_ID}" || -z "${SERVICE_NAME}" || -z "${REPOSITORY_NAME}" || -z "${SQL_INSTANCE_NAME}" ]]; then
            error_exit "All required variables must be provided"
        fi
    fi
    
    # Set gcloud project
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This will delete ALL resources created by the deployment script:"
    echo "  - Cloud Run service: ${SERVICE_NAME}"
    echo "  - Cloud SQL instance: ${SQL_INSTANCE_NAME} (including all data)"
    echo "  - Artifact Registry repository: ${REPOSITORY_NAME} (including all images)"
    echo "  - Secret Manager secrets: db-password, db-connection-string"
    echo "  - Local application code directory"
    echo ""
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        echo "  - Project: ${PROJECT_ID} (will be preserved)"
    else
        log_warning "Project ${PROJECT_ID} does not exist or is not accessible"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Delete Cloud Run service
delete_cloud_run_service() {
    log_info "Deleting Cloud Run service..."
    
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &> /dev/null; then
        log_info "Deleting Cloud Run service: ${SERVICE_NAME}"
        
        if gcloud run services delete "${SERVICE_NAME}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Cloud Run service deleted: ${SERVICE_NAME}"
        else
            log_warning "Failed to delete Cloud Run service (may not exist)"
        fi
    else
        log_warning "Cloud Run service ${SERVICE_NAME} not found"
    fi
}

# Delete Cloud SQL instance
delete_sql_instance() {
    log_info "Deleting Cloud SQL instance..."
    
    if gcloud sql instances describe "${SQL_INSTANCE_NAME}" &> /dev/null; then
        log_warning "Deleting Cloud SQL instance: ${SQL_INSTANCE_NAME}"
        log_warning "This will permanently delete all database data!"
        
        # Additional confirmation for database deletion
        read -p "Are you absolutely sure you want to delete the database? (DELETE/cancel): " db_confirmation
        
        if [[ "${db_confirmation}" == "DELETE" ]]; then
            if gcloud sql instances delete "${SQL_INSTANCE_NAME}" \
                --quiet; then
                log_success "Cloud SQL instance deleted: ${SQL_INSTANCE_NAME}"
                
                # Wait for deletion to complete
                log_info "Waiting for SQL instance deletion to complete..."
                local timeout=300
                local elapsed=0
                while [[ $elapsed -lt $timeout ]]; do
                    if ! gcloud sql instances describe "${SQL_INSTANCE_NAME}" &> /dev/null; then
                        break
                    fi
                    sleep 10
                    elapsed=$((elapsed + 10))
                    log_info "Still waiting for deletion... (${elapsed}s/${timeout}s)"
                done
                
                if [[ $elapsed -ge $timeout ]]; then
                    log_warning "Timeout waiting for SQL instance deletion, but it may still be in progress"
                fi
            else
                log_error "Failed to delete Cloud SQL instance"
            fi
        else
            log_info "Database deletion cancelled by user"
        fi
    else
        log_warning "Cloud SQL instance ${SQL_INSTANCE_NAME} not found"
    fi
}

# Delete Secret Manager secrets
delete_secrets() {
    log_info "Deleting Secret Manager secrets..."
    
    local secrets=("db-password" "db-connection-string")
    
    for secret in "${secrets[@]}"; do
        if gcloud secrets describe "${secret}" &> /dev/null; then
            log_info "Deleting secret: ${secret}"
            
            if gcloud secrets delete "${secret}" --quiet; then
                log_success "Secret deleted: ${secret}"
            else
                log_warning "Failed to delete secret: ${secret}"
            fi
        else
            log_warning "Secret ${secret} not found"
        fi
    done
}

# Delete Artifact Registry repository
delete_artifact_repository() {
    log_info "Deleting Artifact Registry repository..."
    
    if gcloud artifacts repositories describe "${REPOSITORY_NAME}" \
        --location="${REGION}" &> /dev/null; then
        log_info "Deleting Artifact Registry repository: ${REPOSITORY_NAME}"
        
        if gcloud artifacts repositories delete "${REPOSITORY_NAME}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Artifact Registry repository deleted: ${REPOSITORY_NAME}"
        else
            log_warning "Failed to delete Artifact Registry repository"
        fi
    else
        log_warning "Artifact Registry repository ${REPOSITORY_NAME} not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove application code directory
    if [[ -d "multicontainer-app" ]]; then
        log_info "Removing local application code directory..."
        rm -rf multicontainer-app
        log_success "Local application code directory removed"
    else
        log_warning "Local application code directory not found"
    fi
    
    # Remove service configuration file
    if [[ -f "service.yaml" ]]; then
        log_info "Removing service configuration file..."
        rm -f service.yaml
        log_success "Service configuration file removed"
    fi
    
    # Remove deployment variables file
    if [[ -f ".deployment_vars" ]]; then
        log_info "Removing deployment variables file..."
        rm -f .deployment_vars
        log_success "Deployment variables file removed"
    fi
    
    # Remove any Docker build cache (optional)
    if command -v docker &> /dev/null; then
        log_info "Cleaning up Docker build cache..."
        docker system prune -f &> /dev/null || log_warning "Failed to clean Docker cache"
        log_success "Docker build cache cleaned"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_successful=true
    
    # Check Cloud Run service
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &> /dev/null; then
        log_warning "Cloud Run service still exists: ${SERVICE_NAME}"
        cleanup_successful=false
    fi
    
    # Check Cloud SQL instance
    if gcloud sql instances describe "${SQL_INSTANCE_NAME}" &> /dev/null; then
        log_warning "Cloud SQL instance still exists: ${SQL_INSTANCE_NAME}"
        cleanup_successful=false
    fi
    
    # Check secrets
    for secret in "db-password" "db-connection-string"; do
        if gcloud secrets describe "${secret}" &> /dev/null; then
            log_warning "Secret still exists: ${secret}"
            cleanup_successful=false
        fi
    done
    
    # Check Artifact Registry repository
    if gcloud artifacts repositories describe "${REPOSITORY_NAME}" \
        --location="${REGION}" &> /dev/null; then
        log_warning "Artifact Registry repository still exists: ${REPOSITORY_NAME}"
        cleanup_successful=false
    fi
    
    if [[ "${cleanup_successful}" == "true" ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
}

# Display remaining resources
display_remaining_resources() {
    log_info "Checking for any remaining project resources..."
    
    echo ""
    echo "=== Cloud Run Services ==="
    gcloud run services list --region="${REGION}" 2>/dev/null || echo "No Cloud Run services found or error occurred"
    
    echo ""
    echo "=== Cloud SQL Instances ==="
    gcloud sql instances list 2>/dev/null || echo "No Cloud SQL instances found or error occurred"
    
    echo ""
    echo "=== Secret Manager Secrets ==="
    gcloud secrets list --limit=10 2>/dev/null || echo "No secrets found or error occurred"
    
    echo ""
    echo "=== Artifact Registry Repositories ==="
    gcloud artifacts repositories list --location="${REGION}" 2>/dev/null || echo "No repositories found or error occurred"
    
    echo ""
    log_info "If you created a dedicated project for this recipe, you can delete the entire project with:"
    echo "  gcloud projects delete ${PROJECT_ID}"
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may still exist. Run the script again to complete cleanup."
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Main cleanup function
main() {
    log_info "Starting multi-container Cloud Run resource cleanup..."
    
    check_prerequisites
    load_deployment_vars
    confirm_destruction
    
    # Perform cleanup operations
    delete_cloud_run_service
    delete_sql_instance
    delete_secrets
    delete_artifact_repository
    cleanup_local_files
    
    # Verification
    verify_cleanup
    display_remaining_resources
    
    log_success "Cleanup process completed!"
    log_info "Thank you for using the multi-container Cloud Run recipe"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
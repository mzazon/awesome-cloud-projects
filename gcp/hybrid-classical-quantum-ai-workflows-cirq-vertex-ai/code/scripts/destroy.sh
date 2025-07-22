#!/bin/bash

# =============================================================================
# Cleanup Script for Hybrid Classical-Quantum AI Workflows
# Recipe: hybrid-classical-quantum-ai-workflows-cirq-vertex-ai
# =============================================================================

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

# Error handling for non-critical failures
soft_error() {
    log_warning "$1"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [ ! -f ".deployment_state" ]; then
        log_warning "No deployment state file found. Using environment variables if available."
        return 1
    fi
    
    # Source the deployment state
    source .deployment_state
    
    log_info "Loaded deployment state for project: ${PROJECT_ID}"
    return 0
}

# Interactive confirmation
confirm_destruction() {
    log_warning "=================================================="
    log_warning "WARNING: This will destroy ALL resources created by the deployment!"
    log_warning "Project ID: ${PROJECT_ID:-Not Set}"
    log_warning "Storage Bucket: gs://${BUCKET_NAME:-Not Set}"
    log_warning "Cloud Function: ${FUNCTION_NAME:-Not Set}"
    log_warning "Vertex AI Workbench: ${WORKBENCH_INSTANCE:-Not Set}"
    log_warning "=================================================="
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set project context
set_project_context() {
    if [ -n "${PROJECT_ID:-}" ]; then
        log_info "Setting project context to: ${PROJECT_ID}"
        gcloud config set project ${PROJECT_ID} || soft_error "Failed to set project context"
        
        if [ -n "${REGION:-}" ]; then
            gcloud config set compute/region ${REGION} || soft_error "Failed to set region"
        fi
        
        if [ -n "${ZONE:-}" ]; then
            gcloud config set compute/zone ${ZONE} || soft_error "Failed to set zone"
        fi
    else
        log_warning "PROJECT_ID not found. Using current gcloud project."
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            log_error "No project ID available. Cannot proceed with cleanup."
            exit 1
        fi
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if [ -n "${FUNCTION_NAME:-}" ] && [ -n "${REGION:-}" ]; then
        # Check if function exists
        if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &>/dev/null; then
            log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
            gcloud functions delete ${FUNCTION_NAME} \
                --region=${REGION} \
                --quiet || soft_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            
            log_success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            log_warning "Cloud Function not found: ${FUNCTION_NAME}"
        fi
    else
        log_warning "Cloud Function name or region not specified, skipping..."
    fi
}

# Delete Vertex AI Workbench instance
delete_vertex_workbench() {
    log_info "Deleting Vertex AI Workbench instance..."
    
    if [ -n "${WORKBENCH_INSTANCE:-}" ] && [ -n "${ZONE:-}" ]; then
        # Check if instance exists
        if gcloud notebooks instances describe ${WORKBENCH_INSTANCE} --location=${ZONE} &>/dev/null; then
            log_info "Deleting Vertex AI Workbench instance: ${WORKBENCH_INSTANCE}"
            gcloud notebooks instances delete ${WORKBENCH_INSTANCE} \
                --location=${ZONE} \
                --quiet || soft_error "Failed to delete Vertex AI Workbench instance: ${WORKBENCH_INSTANCE}"
            
            # Wait for deletion to complete
            log_info "Waiting for Vertex AI Workbench instance deletion..."
            local max_attempts=20
            local attempt=1
            
            while [ $attempt -le $max_attempts ]; do
                if ! gcloud notebooks instances describe ${WORKBENCH_INSTANCE} --location=${ZONE} &>/dev/null; then
                    log_success "Vertex AI Workbench instance deleted: ${WORKBENCH_INSTANCE}"
                    break
                fi
                
                log_info "Waiting for deletion... (attempt $attempt/$max_attempts)"
                sleep 30
                ((attempt++))
            done
            
            if [ $attempt -gt $max_attempts ]; then
                soft_error "Timeout waiting for Vertex AI Workbench instance deletion"
            fi
        else
            log_warning "Vertex AI Workbench instance not found: ${WORKBENCH_INSTANCE}"
        fi
    else
        log_warning "Workbench instance name or zone not specified, skipping..."
    fi
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        # Check if bucket exists
        if gsutil ls gs://${BUCKET_NAME} &>/dev/null; then
            log_info "Deleting all objects in bucket: gs://${BUCKET_NAME}"
            
            # Remove all objects (including versions)
            gsutil -m rm -r gs://${BUCKET_NAME}/** || soft_error "Failed to delete bucket objects"
            
            # Delete the bucket
            log_info "Deleting bucket: gs://${BUCKET_NAME}"
            gsutil rb gs://${BUCKET_NAME} || soft_error "Failed to delete bucket: gs://${BUCKET_NAME}"
            
            log_success "Storage bucket deleted: gs://${BUCKET_NAME}"
        else
            log_warning "Storage bucket not found: gs://${BUCKET_NAME}"
        fi
    else
        log_warning "Bucket name not specified, skipping..."
    fi
}

# Delete IAM service accounts (if any were created)
delete_service_accounts() {
    log_info "Checking for service accounts to delete..."
    
    # List service accounts that match our naming pattern
    local service_accounts=$(gcloud iam service-accounts list \
        --filter="email~quantum-.*@${PROJECT_ID}.iam.gserviceaccount.com" \
        --format="value(email)" 2>/dev/null || echo "")
    
    if [ -n "$service_accounts" ]; then
        log_info "Found service accounts to delete:"
        echo "$service_accounts"
        
        while IFS= read -r account; do
            if [ -n "$account" ]; then
                log_info "Deleting service account: $account"
                gcloud iam service-accounts delete "$account" \
                    --quiet || soft_error "Failed to delete service account: $account"
            fi
        done <<< "$service_accounts"
        
        log_success "Service accounts cleanup completed"
    else
        log_info "No matching service accounts found"
    fi
}

# Clean up compute resources
cleanup_compute_resources() {
    log_info "Cleaning up any remaining compute resources..."
    
    # Delete any VM instances that might have been created
    local instances=$(gcloud compute instances list \
        --filter="name~quantum-.*" \
        --format="value(name,zone)" 2>/dev/null || echo "")
    
    if [ -n "$instances" ]; then
        log_info "Found compute instances to delete:"
        echo "$instances"
        
        while IFS=$'\t' read -r name zone; do
            if [ -n "$name" ] && [ -n "$zone" ]; then
                log_info "Deleting compute instance: $name in $zone"
                gcloud compute instances delete "$name" \
                    --zone="$zone" \
                    --quiet || soft_error "Failed to delete instance: $name"
            fi
        done <<< "$instances"
        
        log_success "Compute instances cleanup completed"
    else
        log_info "No matching compute instances found"
    fi
}

# Clean up Cloud Build resources
cleanup_cloud_build() {
    log_info "Cleaning up Cloud Build resources..."
    
    # Cancel any running builds
    local running_builds=$(gcloud builds list \
        --filter="status=WORKING" \
        --format="value(id)" \
        --limit=10 2>/dev/null || echo "")
    
    if [ -n "$running_builds" ]; then
        log_info "Cancelling running builds..."
        while IFS= read -r build_id; do
            if [ -n "$build_id" ]; then
                log_info "Cancelling build: $build_id"
                gcloud builds cancel "$build_id" || soft_error "Failed to cancel build: $build_id"
            fi
        done <<< "$running_builds"
    fi
    
    log_info "Cloud Build cleanup completed"
}

# Disable APIs (optional)
disable_apis() {
    log_info "Checking if APIs should be disabled..."
    
    read -p "Do you want to disable the APIs that were enabled? (y/N): " disable_choice
    
    if [[ $disable_choice =~ ^[Yy]$ ]]; then
        log_info "Disabling APIs..."
        
        local apis=(
            "cloudfunctions.googleapis.com"
            "aiplatform.googleapis.com"
            "notebooks.googleapis.com"
            "cloudbuild.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            gcloud services disable ${api} --force || soft_error "Failed to disable ${api}"
        done
        
        log_success "APIs disabled"
    else
        log_info "Keeping APIs enabled"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [ -f ".deployment_state" ]; then
        rm -f .deployment_state
        log_success "Removed deployment state file"
    fi
    
    # Remove any temporary Python files
    local temp_files=(
        "setup_quantum_env.py"
        "classical_risk_model.py"
        "quantum_portfolio_optimizer.py"
        "portfolio_monitor.py"
        "performance_analytics.py"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed temporary file: $file"
        fi
    done
    
    # Remove any temporary directories
    if [ -d "quantum-orchestrator" ]; then
        rm -rf quantum-orchestrator
        log_info "Removed temporary directory: quantum-orchestrator"
    fi
    
    log_success "Local cleanup completed"
}

# Delete entire project (optional)
delete_project() {
    log_info "Checking if entire project should be deleted..."
    
    read -p "Do you want to delete the entire project '${PROJECT_ID}'? This cannot be undone! (y/N): " delete_choice
    
    if [[ $delete_choice =~ ^[Yy]$ ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        log_warning "This action cannot be undone!"
        
        read -p "Type 'DELETE PROJECT' to confirm: " final_confirmation
        
        if [ "$final_confirmation" = "DELETE PROJECT" ]; then
            log_info "Deleting project: ${PROJECT_ID}"
            gcloud projects delete ${PROJECT_ID} --quiet || soft_error "Failed to delete project: ${PROJECT_ID}"
            
            log_success "Project deletion initiated: ${PROJECT_ID}"
            log_info "Note: Project deletion may take several minutes to complete"
            log_info "Billing will stop once deletion is finalized"
        else
            log_info "Project deletion cancelled"
        fi
    else
        log_info "Keeping project: ${PROJECT_ID}"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "=================================================="
    log_success "Cleanup Summary"
    log_info "=================================================="
    
    if [ -n "${PROJECT_ID:-}" ]; then
        log_info "Project ID: ${PROJECT_ID}"
    fi
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        log_info "Storage Bucket: gs://${BUCKET_NAME} - DELETED"
    fi
    
    if [ -n "${FUNCTION_NAME:-}" ]; then
        log_info "Cloud Function: ${FUNCTION_NAME} - DELETED"
    fi
    
    if [ -n "${WORKBENCH_INSTANCE:-}" ]; then
        log_info "Vertex AI Workbench: ${WORKBENCH_INSTANCE} - DELETED"
    fi
    
    log_info "Local files and directories - CLEANED"
    log_info "=================================================="
    log_success "Cleanup completed successfully!"
    
    log_info ""
    log_info "If you deleted the entire project, it may take several minutes"
    log_info "for the deletion to be fully processed by Google Cloud."
    log_info ""
    log_info "You can verify resource deletion in the Google Cloud Console:"
    log_info "https://console.cloud.google.com/"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Hybrid Classical-Quantum AI Workflows..."
    log_info "=================================================="
    
    # Load deployment state
    load_deployment_state || log_warning "Proceeding without deployment state file"
    
    # Check prerequisites
    check_prerequisites
    
    # Set project context
    set_project_context
    
    # Confirm destruction
    confirm_destruction
    
    # Execute cleanup steps
    delete_cloud_function
    delete_vertex_workbench
    cleanup_cloud_build
    delete_storage_bucket
    delete_service_accounts
    cleanup_compute_resources
    disable_apis
    cleanup_local_files
    
    # Optional: Delete entire project
    delete_project
    
    # Generate summary
    generate_cleanup_summary
}

# Handle script termination
cleanup_on_exit() {
    log_info "Cleanup script terminated"
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"
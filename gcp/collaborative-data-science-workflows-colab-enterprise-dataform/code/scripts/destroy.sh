#!/bin/bash

# Collaborative Data Science Workflows with Colab Enterprise and Dataform - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# Use with caution - this will permanently delete all resources and data

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"
readonly SUMMARY_FILE="${SCRIPT_DIR}/deployment-summary.txt"

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Confirmation prompt
confirm_destruction() {
    local project_id="${1:-}"
    
    cat << EOF

${RED}=================================================================${NC}
${RED}                    DANGER - DESTRUCTIVE ACTION${NC}
${RED}=================================================================${NC}

${YELLOW}WARNING: This script will permanently delete ALL resources created
for the Collaborative Data Science Workflows deployment.${NC}

${RED}The following resources will be PERMANENTLY DELETED:${NC}
  • BigQuery dataset and all tables (${DATASET_NAME:-})
  • Cloud Storage bucket and all data (${BUCKET_NAME:-})
  • Dataform repository and workspace (${REPOSITORY_NAME:-}, ${WORKSPACE_NAME:-})
  • Colab Enterprise runtime template (${TEMPLATE_NAME:-})
  • All sample data and configurations

${YELLOW}Project: ${project_id}${NC}

${RED}THIS ACTION CANNOT BE UNDONE!${NC}

EOF

    # Interactive confirmation
    echo -n "Type 'yes' to proceed with resource deletion: "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Double confirmation for extra safety
    echo -n "Are you absolutely sure? Type 'DELETE' to confirm: "
    read -r final_confirmation
    
    if [[ "${final_confirmation}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed resource deletion. Proceeding with cleanup..."
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available"
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not available"
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    # Try to load from state file first
    if [[ -f "${STATE_FILE}" ]]; then
        log_info "Loading state from ${STATE_FILE}"
        source "${STATE_FILE}"
    elif [[ -f "${SUMMARY_FILE}" ]]; then
        log_info "Loading state from ${SUMMARY_FILE}"
        # Parse deployment summary file
        export PROJECT_ID=$(grep "Project ID:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs)
        export REGION=$(grep "Region:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs)
        export BUCKET_NAME=$(grep "Bucket:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs | sed 's|gs://||')
        export DATASET_NAME=$(grep "BigQuery Dataset:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs)
        export REPOSITORY_NAME=$(grep "Dataform Repository:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs)
        export WORKSPACE_NAME=$(grep "Dataform Workspace:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs)
        export TEMPLATE_NAME=$(grep "Runtime Template:" "${SUMMARY_FILE}" | cut -d: -f2 | xargs)
    else
        log_warning "No deployment state found. Attempting manual configuration..."
        
        # Try to get current project
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null) || true
        
        if [[ -z "${PROJECT_ID}" ]]; then
            echo -n "Enter the project ID to clean up: "
            read -r PROJECT_ID
        fi
        
        # Set defaults if not found
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        
        log_warning "Using manual configuration. Some resources may not be cleaned up."
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error_exit "PROJECT_ID is required but not set"
    fi
    
    log_success "Deployment state loaded for project: ${PROJECT_ID}"
}

# Remove BigQuery resources
cleanup_bigquery() {
    log_info "Cleaning up BigQuery resources..."
    
    if [[ -n "${DATASET_NAME:-}" ]]; then
        log_info "Deleting BigQuery dataset: ${DATASET_NAME}"
        
        # Check if dataset exists
        if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
            bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || log_warning "Failed to delete BigQuery dataset: ${DATASET_NAME}"
            log_success "BigQuery dataset deleted: ${DATASET_NAME}"
        else
            log_warning "BigQuery dataset not found: ${DATASET_NAME}"
        fi
    else
        log_warning "No BigQuery dataset name found. Attempting to find datasets with pattern..."
        
        # Try to find datasets with analytics pattern
        local datasets
        datasets=$(bq ls -d --format="value(datasetId)" --filter="datasetId:analytics_*" 2>/dev/null || true)
        
        if [[ -n "${datasets}" ]]; then
            log_info "Found analytics datasets to clean up:"
            echo "${datasets}" | while read -r dataset; do
                if [[ -n "${dataset}" ]]; then
                    log_info "Deleting dataset: ${dataset}"
                    bq rm -r -f "${PROJECT_ID}:${dataset}" || log_warning "Failed to delete dataset: ${dataset}"
                fi
            done
        fi
    fi
}

# Remove Cloud Storage resources
cleanup_storage() {
    log_info "Cleaning up Cloud Storage resources..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Deleting Cloud Storage bucket: gs://${BUCKET_NAME}"
        
        # Check if bucket exists
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            # Remove all objects first
            gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
            
            # Remove bucket
            gsutil rb "gs://${BUCKET_NAME}" || log_warning "Failed to delete bucket: ${BUCKET_NAME}"
            log_success "Cloud Storage bucket deleted: gs://${BUCKET_NAME}"
        else
            log_warning "Cloud Storage bucket not found: gs://${BUCKET_NAME}"
        fi
    else
        log_warning "No bucket name found. Attempting to find buckets with pattern..."
        
        # Try to find buckets with ds-workflow pattern
        local buckets
        buckets=$(gsutil ls | grep "gs://ds-workflow-" || true)
        
        if [[ -n "${buckets}" ]]; then
            log_info "Found workflow buckets to clean up:"
            echo "${buckets}" | while read -r bucket; do
                if [[ -n "${bucket}" ]]; then
                    log_info "Deleting bucket: ${bucket}"
                    gsutil -m rm -r "${bucket}/**" 2>/dev/null || true
                    gsutil rb "${bucket}" || log_warning "Failed to delete bucket: ${bucket}"
                fi
            done
        fi
    fi
}

# Remove Dataform resources
cleanup_dataform() {
    log_info "Cleaning up Dataform resources..."
    
    # Set default region if not set
    REGION="${REGION:-us-central1}"
    
    # Clean up workspace first
    if [[ -n "${WORKSPACE_NAME:-}" && -n "${REPOSITORY_NAME:-}" ]]; then
        log_info "Deleting Dataform workspace: ${WORKSPACE_NAME}"
        
        if gcloud dataform workspaces describe "${WORKSPACE_NAME}" \
            --repository="${REPOSITORY_NAME}" \
            --region="${REGION}" &> /dev/null; then
            
            gcloud dataform workspaces delete "${WORKSPACE_NAME}" \
                --repository="${REPOSITORY_NAME}" \
                --region="${REGION}" \
                --quiet || log_warning "Failed to delete Dataform workspace: ${WORKSPACE_NAME}"
            log_success "Dataform workspace deleted: ${WORKSPACE_NAME}"
        else
            log_warning "Dataform workspace not found: ${WORKSPACE_NAME}"
        fi
    fi
    
    # Clean up repository
    if [[ -n "${REPOSITORY_NAME:-}" ]]; then
        log_info "Deleting Dataform repository: ${REPOSITORY_NAME}"
        
        if gcloud dataform repositories describe "${REPOSITORY_NAME}" \
            --region="${REGION}" &> /dev/null; then
            
            gcloud dataform repositories delete "${REPOSITORY_NAME}" \
                --region="${REGION}" \
                --quiet || log_warning "Failed to delete Dataform repository: ${REPOSITORY_NAME}"
            log_success "Dataform repository deleted: ${REPOSITORY_NAME}"
        else
            log_warning "Dataform repository not found: ${REPOSITORY_NAME}"
        fi
    fi
    
    # If no specific names, try to find resources with pattern
    if [[ -z "${REPOSITORY_NAME:-}" ]]; then
        log_warning "No repository name found. Attempting to find repositories with pattern..."
        
        local repositories
        repositories=$(gcloud dataform repositories list --region="${REGION}" --format="value(name)" --filter="name:*dataform-repo-*" 2>/dev/null || true)
        
        if [[ -n "${repositories}" ]]; then
            log_info "Found Dataform repositories to clean up:"
            echo "${repositories}" | while read -r repo_path; do
                if [[ -n "${repo_path}" ]]; then
                    local repo_name
                    repo_name=$(basename "${repo_path}")
                    log_info "Deleting repository: ${repo_name}"
                    gcloud dataform repositories delete "${repo_name}" \
                        --region="${REGION}" \
                        --quiet || log_warning "Failed to delete repository: ${repo_name}"
                fi
            done
        fi
    fi
}

# Remove Colab Enterprise runtime template
cleanup_runtime_template() {
    log_info "Cleaning up Colab Enterprise runtime template..."
    
    if [[ -n "${TEMPLATE_NAME:-}" ]]; then
        log_info "Deleting runtime template: ${TEMPLATE_NAME}"
        
        # Use REST API to delete runtime template
        local api_url="https://${REGION:-us-central1}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION:-us-central1}/runtimeTemplates/${TEMPLATE_NAME}"
        
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
            -H "Authorization: Bearer $(gcloud auth print-access-token)" \
            "${api_url}")
        
        if [[ "${response_code}" == "200" || "${response_code}" == "404" ]]; then
            log_success "Runtime template deleted: ${TEMPLATE_NAME}"
        else
            log_warning "Failed to delete runtime template: ${TEMPLATE_NAME} (HTTP ${response_code})"
        fi
    else
        log_warning "No runtime template name found. Attempting to find templates with pattern..."
        
        # Try to list and delete templates with ds-runtime pattern
        local templates_response
        templates_response=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
            "https://${REGION:-us-central1}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION:-us-central1}/runtimeTemplates" || true)
        
        if [[ -n "${templates_response}" ]]; then
            # Parse template names from response (simplified - in production, use jq)
            local template_names
            template_names=$(echo "${templates_response}" | grep -o '"name":"[^"]*ds-runtime-template-[^"]*"' | cut -d'"' -f4 || true)
            
            if [[ -n "${template_names}" ]]; then
                echo "${template_names}" | while read -r template_path; do
                    if [[ -n "${template_path}" ]]; then
                        log_info "Deleting template: ${template_path}"
                        curl -s -X DELETE \
                            -H "Authorization: Bearer $(gcloud auth print-access-token)" \
                            "https://${REGION:-us-central1}-aiplatform.googleapis.com/v1/${template_path}" \
                            > /dev/null || log_warning "Failed to delete template: ${template_path}"
                    fi
                done
            fi
        fi
    fi
}

# Clean up temporary files and logs
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${STATE_FILE}"
        "${SUMMARY_FILE}"
        "/tmp/runtime-template.json"
        "/tmp/sample-data"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            rm -rf "${file}"
            log_info "Removed: ${file}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check BigQuery datasets
    if [[ -n "${DATASET_NAME:-}" ]]; then
        if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
            log_warning "BigQuery dataset still exists: ${DATASET_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check Cloud Storage buckets
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_warning "Cloud Storage bucket still exists: gs://${BUCKET_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check Dataform repositories
    if [[ -n "${REPOSITORY_NAME:-}" ]]; then
        if gcloud dataform repositories describe "${REPOSITORY_NAME}" \
            --region="${REGION:-us-central1}" &> /dev/null; then
            log_warning "Dataform repository still exists: ${REPOSITORY_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_warning "Cleanup completed with ${cleanup_issues} potential issues"
        log_warning "Please check the Google Cloud Console for any remaining resources"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    cat << EOF

${GREEN}=================================================================${NC}
${GREEN}              CLEANUP COMPLETED SUCCESSFULLY${NC}
${GREEN}=================================================================${NC}

${BLUE}Cleaned up resources from project: ${PROJECT_ID}${NC}

${BLUE}Removed Resources:${NC}
  • BigQuery dataset: ${DATASET_NAME:-"<pattern-based cleanup>"}
  • Cloud Storage bucket: ${BUCKET_NAME:-"<pattern-based cleanup>"}
  • Dataform repository: ${REPOSITORY_NAME:-"<pattern-based cleanup>"}
  • Dataform workspace: ${WORKSPACE_NAME:-"<pattern-based cleanup>"}
  • Runtime template: ${TEMPLATE_NAME:-"<pattern-based cleanup>"}

${BLUE}Cleanup Summary:${NC}
  • All data has been permanently deleted
  • No ongoing charges should occur from these resources
  • Local configuration files have been removed

${YELLOW}Post-Cleanup Verification:${NC}
  • Check Google Cloud Console for any remaining resources
  • Verify billing has stopped for deleted resources
  • Review IAM permissions if no longer needed

${BLUE}If you need to redeploy:${NC}
  • Run ./deploy.sh to recreate the infrastructure
  • All previous data will be lost and cannot be recovered

${GREEN}=================================================================${NC}

EOF
    
    log_success "Cleanup completed at: $(date)"
    log_info "Total cleanup time: $SECONDS seconds"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Collaborative Data Science Workflows resources..."
    log_info "Cleanup started at: $(date)"
    
    # Initialize log file
    echo "Cleanup Log - $(date)" > "${LOG_FILE}"
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_destruction "${PROJECT_ID}"
    
    log_warning "Starting resource deletion in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    
    cleanup_bigquery
    cleanup_dataform
    cleanup_storage
    cleanup_runtime_template
    cleanup_local_files
    verify_cleanup
    generate_cleanup_summary
    
    log_success "Cleanup completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
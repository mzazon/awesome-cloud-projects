#!/bin/bash

# Sustainability Compliance Automation with Carbon Footprint and Functions
# Cleanup/Destroy Script for GCP
# 
# This script safely removes all infrastructure created by the deployment script
# including Cloud Functions, BigQuery datasets, Cloud Scheduler jobs, and associated resources.

set -euo pipefail

# Color codes for output formatting
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

# Progress tracking
STEP_COUNT=0
TOTAL_STEPS=6

step() {
    STEP_COUNT=$((STEP_COUNT + 1))
    log_info "Step ${STEP_COUNT}/${TOTAL_STEPS}: $1"
}

# User confirmation
confirm_destruction() {
    echo "================================================================"
    echo "    Sustainability Compliance Automation Cleanup Script"
    echo "================================================================"
    echo ""
    log_warning "This script will permanently delete the following resources:"
    echo ""
    echo "🗑️  RESOURCES TO BE DELETED:"
    echo "   • All Cloud Functions (process-carbon-data, generate-esg-report, carbon-alerts)"
    echo "   • BigQuery dataset and all tables (${DATASET_NAME:-carbon_footprint_*})"
    echo "   • Carbon Footprint data transfer configuration"
    echo "   • All Cloud Scheduler jobs (3 jobs)"
    echo "   • Cloud Storage bucket for ESG reports"
    echo "   • Local function source directories"
    echo ""
    echo "⚠️  WARNING: This action cannot be undone!"
    echo "   All stored sustainability data and reports will be permanently lost."
    echo ""
    
    read -p "Are you sure you want to proceed? (Type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Starting cleanup process..."
    echo ""
}

# Environment detection
detect_environment() {
    step "Detecting existing deployment configuration"
    
    # Try to detect current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "No active Google Cloud project found"
        log_info "Please set your project with: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Try to detect region
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    log_info "Detected project: ${PROJECT_ID}"
    log_info "Using region: ${REGION}"
    
    # Look for existing resources to determine naming patterns
    log_info "Scanning for existing sustainability resources..."
    
    # Find existing datasets
    local datasets
    datasets=$(bq ls --format="value(datasetId)" "${PROJECT_ID}" 2>/dev/null | grep "carbon_footprint" || true)
    
    if [[ -n "${datasets}" ]]; then
        log_info "Found carbon footprint datasets: ${datasets}"
        # Use the first dataset found
        DATASET_NAME=$(echo "${datasets}" | head -1)
    fi
    
    # Find existing functions
    local functions
    functions=$(gcloud functions list --format="value(name)" --filter="name:process-carbon-data OR name:generate-esg-report OR name:carbon-alerts" 2>/dev/null || true)
    
    if [[ -n "${functions}" ]]; then
        log_info "Found sustainability functions: ${functions}"
    fi
    
    log_success "Environment detection completed"
}

# Cloud Scheduler cleanup
cleanup_scheduler() {
    step "Removing Cloud Scheduler jobs"
    
    local scheduler_jobs=("process-carbon-data" "generate-esg-reports" "carbon-alerts-check")
    
    for job in "${scheduler_jobs[@]}"; do
        if gcloud scheduler jobs describe "${job}" --location="${REGION}" &>/dev/null; then
            log_info "Deleting Cloud Scheduler job: ${job}"
            gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet 2>/dev/null || {
                log_warning "Failed to delete scheduler job: ${job} (may not exist)"
            }
        else
            log_info "Scheduler job ${job} not found (may already be deleted)"
        fi
    done
    
    log_success "Cloud Scheduler jobs cleanup completed"
}

# Cloud Functions cleanup
cleanup_functions() {
    step "Removing Cloud Functions"
    
    # Get all functions that match our naming patterns
    local functions
    functions=$(gcloud functions list --format="value(name)" --filter="name~process-carbon-data OR name~generate-esg-report OR name~carbon-alerts" 2>/dev/null || true)
    
    if [[ -n "${functions}" ]]; then
        while IFS= read -r function_name; do
            if [[ -n "${function_name}" ]]; then
                log_info "Deleting Cloud Function: ${function_name}"
                gcloud functions delete "${function_name}" --region="${REGION}" --quiet 2>/dev/null || {
                    log_warning "Failed to delete function: ${function_name} (may not exist in this region)"
                }
            fi
        done <<< "${functions}"
    else
        log_info "No sustainability Cloud Functions found"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# BigQuery cleanup
cleanup_bigquery() {
    step "Removing BigQuery resources"
    
    # Find and delete carbon footprint datasets
    local datasets
    datasets=$(bq ls --format="value(datasetId)" "${PROJECT_ID}" 2>/dev/null | grep "carbon_footprint" || true)
    
    if [[ -n "${datasets}" ]]; then
        while IFS= read -r dataset; do
            if [[ -n "${dataset}" ]]; then
                log_info "Deleting BigQuery dataset: ${dataset}"
                
                # Delete data transfer configurations first
                log_info "Checking for data transfer configurations..."
                local transfer_configs
                transfer_configs=$(bq ls --transfer_config --format="value(name)" 2>/dev/null | grep "Carbon Footprint Export" || true)
                
                if [[ -n "${transfer_configs}" ]]; then
                    while IFS= read -r config_id; do
                        if [[ -n "${config_id}" ]]; then
                            log_info "Deleting data transfer configuration: ${config_id}"
                            bq rm --transfer_config "${config_id}" 2>/dev/null || {
                                log_warning "Failed to delete transfer config: ${config_id}"
                            }
                        fi
                    done <<< "${transfer_configs}"
                fi
                
                # Delete the dataset and all its tables
                bq rm -r -f "${PROJECT_ID}:${dataset}" 2>/dev/null || {
                    log_warning "Failed to delete dataset: ${dataset} (may not exist)"
                }
            fi
        done <<< "${datasets}"
    else
        log_info "No carbon footprint datasets found"
    fi
    
    log_success "BigQuery resources cleanup completed"
}

# Cloud Storage cleanup
cleanup_storage() {
    step "Removing Cloud Storage buckets"
    
    # Find ESG reports buckets
    local buckets
    buckets=$(gsutil ls | grep "esg-reports-" || true)
    
    if [[ -n "${buckets}" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                log_info "Deleting Cloud Storage bucket: ${bucket}"
                gsutil -m rm -r "${bucket}" 2>/dev/null || {
                    log_warning "Failed to delete bucket: ${bucket} (may not exist or be empty)"
                }
            fi
        done <<< "${buckets}"
    else
        log_info "No ESG reports buckets found"
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Local files cleanup
cleanup_local_files() {
    step "Cleaning up local files and directories"
    
    local directories=("carbon-processing-function" "esg-report-function" "carbon-alert-function")
    local files=("carbon_export_config.json")
    
    # Remove function directories
    for dir in "${directories[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_info "Removing local directory: ${dir}"
            rm -rf "${dir}"
        fi
    done
    
    # Remove configuration files
    for file in "${files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing local file: ${file}"
            rm -f "${file}"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" --filter="name~process-carbon-data OR name~generate-esg-report OR name~carbon-alerts" 2>/dev/null || true)
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some functions may still exist: ${remaining_functions}"
    else
        log_success "All sustainability functions removed"
    fi
    
    # Check for remaining datasets
    local remaining_datasets
    remaining_datasets=$(bq ls --format="value(datasetId)" "${PROJECT_ID}" 2>/dev/null | grep "carbon_footprint" || true)
    
    if [[ -n "${remaining_datasets}" ]]; then
        log_warning "Some datasets may still exist: ${remaining_datasets}"
    else
        log_success "All carbon footprint datasets removed"
    fi
    
    # Check for remaining scheduler jobs
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list --format="value(name)" --filter="name~process-carbon-data OR name~generate-esg-reports OR name~carbon-alerts-check" 2>/dev/null || true)
    
    if [[ -n "${remaining_jobs}" ]]; then
        log_warning "Some scheduler jobs may still exist: ${remaining_jobs}"
    else
        log_success "All sustainability scheduler jobs removed"
    fi
    
    log_success "Cleanup verification completed"
}

# Main cleanup function
main() {
    confirm_destruction
    detect_environment
    cleanup_scheduler
    cleanup_functions
    cleanup_bigquery
    cleanup_storage
    cleanup_local_files
    verify_cleanup
    
    echo ""
    echo "================================================================"
    echo "               CLEANUP COMPLETED SUCCESSFULLY"
    echo "================================================================"
    echo ""
    log_success "All sustainability compliance automation resources have been removed!"
    echo ""
    echo "🗑️  RESOURCES REMOVED:"
    echo "   ✅ Cloud Functions (process-carbon-data, generate-esg-report, carbon-alerts)"
    echo "   ✅ BigQuery datasets and tables"
    echo "   ✅ Carbon Footprint data transfer configurations"
    echo "   ✅ Cloud Scheduler jobs (3 jobs)"
    echo "   ✅ Cloud Storage buckets (ESG reports)"
    echo "   ✅ Local function source directories"
    echo ""
    echo "💰 COST IMPACT:"
    echo "   • No ongoing charges will be incurred for the deleted resources"
    echo "   • Any previously generated BigQuery data has been permanently deleted"
    echo "   • Stored ESG reports in Cloud Storage have been removed"
    echo ""
    echo "📝 IMPORTANT NOTES:"
    echo "   • Carbon Footprint data transfer configurations may take a few minutes to fully delete"
    echo "   • If you had other resources sharing similar names, verify they weren't accidentally deleted"
    echo "   • API enablement is preserved in case you have other workloads using these services"
    echo ""
    echo "🔄 TO REDEPLOY:"
    echo "   Run './deploy.sh' to recreate the sustainability compliance automation infrastructure"
    echo ""
    echo "================================================================"
}

# Execute main function
main "$@"
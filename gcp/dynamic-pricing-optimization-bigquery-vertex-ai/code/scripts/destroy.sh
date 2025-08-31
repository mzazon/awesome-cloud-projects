#!/bin/bash

# Dynamic Pricing Optimization Cleanup Script
# This script safely removes all resources created by the deployment script
# including BigQuery datasets, Cloud Functions, Cloud Scheduler jobs, and GCP project

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="pricing-opt"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY-RUN mode. No actual resources will be deleted."
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        log_info "[DRY-RUN] Purpose: $description"
    else
        log_info "Executing: $description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed (ignored): $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil not found. Please install Google Cloud SDK with gsutil."
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI not found. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Try to detect existing project from gcloud config
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    # Set environment variables with fallbacks
    export PROJECT_ID="${PROJECT_ID:-$CURRENT_PROJECT}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export DATASET_NAME="${DATASET_NAME:-pricing_optimization}"
    export MODEL_NAME="${MODEL_NAME:-pricing_model}"
    
    # If PROJECT_ID is still empty, try to find pricing optimization projects
    if [[ -z "$PROJECT_ID" ]]; then
        log_info "No PROJECT_ID specified. Searching for pricing optimization projects..."
        
        # List projects that match our naming pattern
        local matching_projects
        matching_projects=$(gcloud projects list --filter="projectId:${PROJECT_PREFIX}-*" --format="value(projectId)" 2>/dev/null || echo "")
        
        if [[ -n "$matching_projects" ]]; then
            log_info "Found potential pricing optimization projects:"
            echo "$matching_projects"
            
            if [[ "$FORCE" != "true" ]]; then
                echo ""
                read -p "Enter the PROJECT_ID to clean up (or press Ctrl+C to abort): " PROJECT_ID
            else
                # In force mode, use the first matching project
                PROJECT_ID=$(echo "$matching_projects" | head -n1)
                log_warning "Force mode: Using project $PROJECT_ID"
            fi
        else
            log_error "No PROJECT_ID specified and no matching projects found."
            log_error "Please specify PROJECT_ID environment variable or use --project-id flag."
            exit 1
        fi
    fi
    
    # Try to detect bucket and function names if not provided
    if [[ -z "${BUCKET_NAME:-}" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_info "Detecting Cloud Storage buckets..."
        BUCKET_NAME=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "pricing-data-" | head -n1 | sed 's|gs://||' | sed 's|/||' || echo "")
    fi
    
    if [[ -z "${FUNCTION_NAME:-}" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_info "Detecting Cloud Functions..."
        FUNCTION_NAME=$(gcloud functions list --filter="name:pricing-optimizer-*" --format="value(name)" 2>/dev/null | head -n1 || echo "")
    fi
    
    # Set current project context
    if [[ "$DRY_RUN" != "true" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set compute/zone "$ZONE"
    fi
    
    log_info "Environment variables configured:"
    log_info "  PROJECT_ID: $PROJECT_ID"
    log_info "  REGION: $REGION"
    log_info "  ZONE: $ZONE"
    log_info "  BUCKET_NAME: ${BUCKET_NAME:-'<auto-detect>'}"
    log_info "  FUNCTION_NAME: ${FUNCTION_NAME:-'<auto-detect>'}"
}

# Function to confirm destructive action
confirm_cleanup() {
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Force mode enabled. Skipping confirmation."
        return
    fi
    
    log_warning "This script will DELETE the following resources:"
    echo "  - GCP Project: $PROJECT_ID"
    echo "  - All BigQuery datasets and models"
    echo "  - All Cloud Functions"
    echo "  - All Cloud Scheduler jobs"
    echo "  - All Cloud Storage buckets"
    echo "  - All Vertex AI training jobs"
    echo "  - All monitoring dashboards"
    echo ""
    log_warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup..."
}

# Function to remove Cloud Scheduler jobs
cleanup_scheduler() {
    log_info "Cleaning up Cloud Scheduler jobs..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # List and delete all pricing optimization scheduler jobs
        local scheduler_jobs
        scheduler_jobs=$(gcloud scheduler jobs list --location="$REGION" --filter="name:pricing-optimization-*" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$scheduler_jobs" ]]; then
            while IFS= read -r job_name; do
                if [[ -n "$job_name" ]]; then
                    execute_cmd "gcloud scheduler jobs delete '$job_name' --location='$REGION' --quiet" \
                               "Deleting scheduler job: $job_name" true
                fi
            done <<< "$scheduler_jobs"
        else
            log_info "No Cloud Scheduler jobs found"
        fi
    else
        execute_cmd "gcloud scheduler jobs delete pricing-optimization-* --location=${REGION} --quiet" \
                   "Deleting all pricing optimization scheduler jobs" true
    fi
    
    log_success "Cloud Scheduler cleanup completed"
}

# Function to remove Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Auto-detect function name if not provided
        if [[ -z "${FUNCTION_NAME:-}" ]]; then
            local functions
            functions=$(gcloud functions list --filter="name:pricing-optimizer-*" --format="value(name)" 2>/dev/null || echo "")
            
            if [[ -n "$functions" ]]; then
                while IFS= read -r func_name; do
                    if [[ -n "$func_name" ]]; then
                        execute_cmd "gcloud functions delete '$func_name' --region='$REGION' --quiet" \
                                   "Deleting Cloud Function: $func_name" true
                    fi
                done <<< "$functions"
            else
                log_info "No Cloud Functions found"
            fi
        else
            execute_cmd "gcloud functions delete '$FUNCTION_NAME' --region='$REGION' --quiet" \
                       "Deleting Cloud Function: $FUNCTION_NAME" true
        fi
    else
        execute_cmd "gcloud functions delete ${FUNCTION_NAME:-'pricing-optimizer-*'} --region=${REGION} --quiet" \
                   "Deleting Cloud Function" true
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to remove Vertex AI resources
cleanup_vertex_ai() {
    log_info "Cleaning up Vertex AI resources..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Cancel and delete custom training jobs
        local training_jobs
        training_jobs=$(gcloud ai custom-jobs list --region="$REGION" --filter="displayName:pricing-optimization-training*" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$training_jobs" ]]; then
            while IFS= read -r job_name; do
                if [[ -n "$job_name" ]]; then
                    # Cancel running jobs first
                    execute_cmd "gcloud ai custom-jobs cancel '$job_name' --region='$REGION' --quiet" \
                               "Cancelling training job: $job_name" true
                fi
            done <<< "$training_jobs"
            
            log_info "Waiting for training jobs to be cancelled..."
            sleep 10
        else
            log_info "No Vertex AI training jobs found"
        fi
        
        # Delete any models or endpoints (if created)
        local models
        models=$(gcloud ai models list --region="$REGION" --filter="displayName:pricing*" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$models" ]]; then
            while IFS= read -r model_name; do
                if [[ -n "$model_name" ]]; then
                    execute_cmd "gcloud ai models delete '$model_name' --region='$REGION' --quiet" \
                               "Deleting AI model: $model_name" true
                fi
            done <<< "$models"
        fi
    else
        execute_cmd "gcloud ai custom-jobs cancel pricing-optimization-training* --region=${REGION} --quiet" \
                   "Cancelling Vertex AI training jobs" true
    fi
    
    log_success "Vertex AI cleanup completed"
}

# Function to remove BigQuery resources
cleanup_bigquery() {
    log_info "Cleaning up BigQuery resources..."
    
    # Delete BigQuery dataset and all tables/models
    execute_cmd "bq rm -r -f '${PROJECT_ID}:${DATASET_NAME}'" \
               "Deleting BigQuery dataset and all contents" true
    
    log_success "BigQuery cleanup completed"
}

# Function to remove Cloud Storage buckets
cleanup_storage() {
    log_info "Cleaning up Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Auto-detect bucket name if not provided
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            local buckets
            buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "pricing-data-" || echo "")
            
            if [[ -n "$buckets" ]]; then
                while IFS= read -r bucket_url; do
                    if [[ -n "$bucket_url" ]]; then
                        execute_cmd "gsutil -m rm -r '$bucket_url'" \
                                   "Deleting Cloud Storage bucket: $bucket_url" true
                    fi
                done <<< "$buckets"
            else
                log_info "No Cloud Storage buckets found"
            fi
        else
            execute_cmd "gsutil -m rm -r 'gs://${BUCKET_NAME}'" \
                       "Deleting Cloud Storage bucket: gs://${BUCKET_NAME}" true
        fi
    else
        execute_cmd "gsutil -m rm -r gs://${BUCKET_NAME:-'pricing-data-*'}" \
                   "Deleting Cloud Storage bucket" true
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Function to remove monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # List and delete dashboards related to pricing optimization
        local dashboards
        dashboards=$(gcloud monitoring dashboards list --filter="displayName:'Dynamic Pricing Optimization Dashboard'" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$dashboards" ]]; then
            while IFS= read -r dashboard_name; do
                if [[ -n "$dashboard_name" ]]; then
                    execute_cmd "gcloud monitoring dashboards delete '$dashboard_name' --quiet" \
                               "Deleting monitoring dashboard: $dashboard_name" true
                fi
            done <<< "$dashboards"
        else
            log_info "No monitoring dashboards found"
        fi
    else
        execute_cmd "gcloud monitoring dashboards delete pricing-optimization-dashboard --quiet" \
                   "Deleting monitoring dashboard" true
    fi
    
    log_success "Monitoring cleanup completed"
}

# Function to remove entire project
cleanup_project() {
    log_info "Cleaning up GCP project..."
    
    # Confirm project deletion
    if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_warning "This will DELETE the entire GCP project: $PROJECT_ID"
        log_warning "All resources in this project will be permanently lost!"
        echo ""
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Aborting project deletion."
            log_info "Individual resources have been cleaned up, but project remains."
            return
        fi
    fi
    
    execute_cmd "gcloud projects delete '$PROJECT_ID' --quiet" \
               "Deleting GCP project"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Project deletion initiated. It may take several minutes to complete."
        log_info "Note: Billing may continue for a few minutes after deletion."
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping validation in dry-run mode"
        return
    fi
    
    local cleanup_errors=0
    
    # Check if BigQuery dataset still exists
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_warning "BigQuery dataset still exists"
        ((cleanup_errors++))
    fi
    
    # Check if Cloud Functions still exist
    local remaining_functions
    remaining_functions=$(gcloud functions list --filter="name:pricing-optimizer-*" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Some Cloud Functions still exist: $remaining_functions"
        ((cleanup_errors++))
    fi
    
    # Check if Cloud Storage buckets still exist
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "pricing-data-" || echo "")
    if [[ -n "$remaining_buckets" ]]; then
        log_warning "Some Cloud Storage buckets still exist: $remaining_buckets"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "Cleanup validation completed successfully"
    else
        log_warning "Cleanup validation found $cleanup_errors potential issues"
        log_warning "Some resources may take time to be fully deleted"
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log_info "=== Cleanup Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources cleaned up:"
    echo "  ✅ Cloud Scheduler jobs"
    echo "  ✅ Cloud Functions"
    echo "  ✅ Vertex AI training jobs"
    echo "  ✅ BigQuery datasets and models"
    echo "  ✅ Cloud Storage buckets"
    echo "  ✅ Monitoring dashboards"
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "  ✅ GCP Project (deletion in progress)"
    fi
    echo ""
    echo "Cleanup completed successfully!"
    echo ""
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        echo "Note: The GCP project '$PROJECT_ID' was preserved."
        echo "To delete the entire project, run: gcloud projects delete $PROJECT_ID"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Dynamic Pricing Optimization cleanup..."
    log_info "================================================"
    
    check_prerequisites
    setup_environment
    confirm_cleanup
    
    # Cleanup resources in reverse order of creation
    cleanup_scheduler
    cleanup_cloud_functions
    cleanup_vertex_ai
    cleanup_bigquery
    cleanup_storage
    cleanup_monitoring
    
    # Optionally delete the entire project
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        cleanup_project
    fi
    
    validate_cleanup
    
    log_success "Cleanup completed successfully!"
    show_cleanup_summary
}

# Handle command line arguments
DELETE_PROJECT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Run in dry-run mode (no resources deleted)"
            echo "  --force                Skip confirmation prompts"
            echo "  --project-id ID        Specify GCP project ID to clean up"
            echo "  --region REGION        Specify GCP region (default: us-central1)"
            echo "  --delete-project       Delete the entire GCP project"
            echo "  --bucket-name NAME     Specify Cloud Storage bucket name"
            echo "  --function-name NAME   Specify Cloud Function name"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID            GCP project ID to clean up"
            echo "  REGION               GCP region (default: us-central1)"
            echo "  BUCKET_NAME          Cloud Storage bucket name"
            echo "  FUNCTION_NAME        Cloud Function name"
            echo "  DRY_RUN              Set to 'true' for dry-run mode"
            echo "  FORCE                Set to 'true' to skip confirmations"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
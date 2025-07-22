#!/bin/bash

# Edge-to-Cloud MLOps Pipelines Cleanup Script
# Recipe: Edge-to-Cloud MLOps Pipelines with Distributed Cloud Edge and Vertex AI Pipelines
# Provider: Google Cloud Platform

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Script interrupted. Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}/temp_resources.txt" 2>/dev/null || true
}

# Set up signal handling
trap cleanup EXIT INT TERM

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Edge-to-Cloud MLOps Pipelines infrastructure on Google Cloud Platform.

Options:
    -p, --project-id PROJECT_ID    GCP Project ID (required if .env file not found)
    -r, --region REGION           GCP Region (optional, will use from .env if available)
    -f, --force                   Skip confirmation prompts
    -k, --keep-project           Keep the project and only delete resources
    -d, --dry-run                Show what would be destroyed without executing
    -v, --verbose                Enable verbose logging
    -h, --help                   Show this help message

Examples:
    $0                           # Destroy using .env file settings
    $0 -p my-mlops-project       # Destroy specific project
    $0 --force                   # Skip confirmation prompts
    $0 --dry-run                 # Preview destruction
    $0 --keep-project            # Delete resources but keep project

WARNING: This will permanently delete all resources created by the deployment script.

EOF
}

# Default values
FORCE=false
KEEP_PROJECT=false
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
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
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Load environment variables from .env file if it exists
load_environment() {
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading environment variables from .env file..."
        source "${SCRIPT_DIR}/.env"
        log_info "Loaded environment for project: ${PROJECT_ID:-unknown}"
    else
        log_warning ".env file not found. Using command line parameters..."
        if [[ -z "${PROJECT_ID:-}" ]]; then
            log_error "PROJECT_ID must be provided via command line or .env file"
            exit 1
        fi
    fi
    
    # Set defaults for optional variables
    REGION=${REGION:-"us-central1"}
    ZONE=${ZONE:-"us-central1-a"}
}

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_info "Using authenticated account: $active_account"
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} not found or not accessible."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirmation prompt function
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will permanently delete the following resources:${NC}"
    echo "  - GKE Cluster: ${CLUSTER_NAME:-edge-simulation-cluster}"
    echo "  - Cloud Storage Buckets: ${MLOPS_BUCKET:-unknown}, ${EDGE_MODELS_BUCKET:-unknown}"
    echo "  - Cloud Functions: edge-model-updater"
    echo "  - Vertex AI Experiments and Models"
    echo "  - Cloud Monitoring Dashboards and Alerts"
    echo "  - Service Accounts and IAM bindings"
    
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        echo -e "${RED}  - Project: ${PROJECT_ID}${NC}"
    fi
    
    echo ""
    read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_warning "User confirmed destruction. Proceeding..."
}

# Configure gcloud function
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure gcloud with project: $PROJECT_ID"
        return 0
    fi
    
    gcloud config set project "${PROJECT_ID}"
    
    if [[ -n "${REGION:-}" ]]; then
        gcloud config set compute/region "${REGION}"
    fi
    
    if [[ -n "${ZONE:-}" ]]; then
        gcloud config set compute/zone "${ZONE}"
    fi
    
    log_success "gcloud configuration completed"
}

# Delete Kubernetes resources function
delete_kubernetes_resources() {
    log_info "Deleting Kubernetes resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Kubernetes deployments and services"
        return 0
    fi
    
    # Check if cluster exists and get credentials
    if gcloud container clusters describe "${CLUSTER_NAME:-edge-simulation-cluster}" \
        --region="${REGION}" &>/dev/null; then
        
        log_info "Getting cluster credentials..."
        gcloud container clusters get-credentials "${CLUSTER_NAME:-edge-simulation-cluster}" \
            --region="${REGION}" --quiet
        
        # Delete namespace (this will delete all resources in the namespace)
        log_info "Deleting edge-inference namespace and all resources..."
        if kubectl delete namespace edge-inference --timeout=300s --ignore-not-found; then
            log_success "Deleted edge-inference namespace"
        else
            log_warning "Failed to delete namespace or namespace not found"
        fi
        
        # Wait for namespace deletion
        log_info "Waiting for namespace deletion to complete..."
        while kubectl get namespace edge-inference &>/dev/null; do
            log_info "Waiting for namespace deletion..."
            sleep 10
        done
        
    else
        log_warning "GKE cluster not found, skipping Kubernetes resource deletion"
    fi
    
    log_success "Kubernetes resources cleanup completed"
}

# Delete GKE cluster function
delete_gke_cluster() {
    log_info "Deleting GKE cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete GKE cluster: ${CLUSTER_NAME:-edge-simulation-cluster}"
        return 0
    fi
    
    # Check if cluster exists
    if gcloud container clusters describe "${CLUSTER_NAME:-edge-simulation-cluster}" \
        --region="${REGION}" &>/dev/null; then
        
        log_info "Deleting GKE cluster: ${CLUSTER_NAME:-edge-simulation-cluster}"
        if gcloud container clusters delete "${CLUSTER_NAME:-edge-simulation-cluster}" \
            --region="${REGION}" \
            --quiet; then
            log_success "GKE cluster deleted"
        else
            log_error "Failed to delete GKE cluster"
        fi
    else
        log_warning "GKE cluster not found, skipping"
    fi
    
    log_success "GKE cluster cleanup completed"
}

# Delete Cloud Functions function
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: edge-model-updater"
        return 0
    fi
    
    # Delete edge-model-updater function
    log_info "Deleting edge-model-updater Cloud Function..."
    if gcloud functions delete edge-model-updater \
        --region="${REGION}" \
        --quiet 2>/dev/null; then
        log_success "Cloud Function deleted"
    else
        log_warning "Cloud Function not found or failed to delete"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Delete monitoring resources function
delete_monitoring_resources() {
    log_info "Deleting Cloud Monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete monitoring dashboards and alert policies"
        return 0
    fi
    
    # Delete monitoring dashboards
    log_info "Deleting monitoring dashboards..."
    local dashboard_ids
    dashboard_ids=$(gcloud monitoring dashboards list \
        --filter="displayName:Edge MLOps" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$dashboard_ids" ]]; then
        echo "$dashboard_ids" | while read -r dashboard_id; do
            if [[ -n "$dashboard_id" ]]; then
                log_info "Deleting dashboard: $dashboard_id"
                gcloud monitoring dashboards delete "$dashboard_id" --quiet 2>/dev/null || true
            fi
        done
        log_success "Monitoring dashboards deleted"
    else
        log_warning "No monitoring dashboards found"
    fi
    
    # Delete alert policies
    log_info "Deleting alert policies..."
    local policy_ids
    policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName:Edge*" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$policy_ids" ]]; then
        echo "$policy_ids" | while read -r policy_id; do
            if [[ -n "$policy_id" ]]; then
                log_info "Deleting alert policy: $policy_id"
                gcloud alpha monitoring policies delete "$policy_id" --quiet 2>/dev/null || true
            fi
        done
        log_success "Alert policies deleted"
    else
        log_warning "No alert policies found"
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Delete Vertex AI resources function
delete_vertex_ai_resources() {
    log_info "Deleting Vertex AI resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Vertex AI experiments and models"
        return 0
    fi
    
    # Delete experiments
    log_info "Deleting Vertex AI experiments..."
    if gcloud ai experiments delete edge-mlops-experiment \
        --region="${REGION}" \
        --quiet 2>/dev/null; then
        log_success "Vertex AI experiment deleted"
    else
        log_warning "Vertex AI experiment not found or failed to delete"
    fi
    
    # Delete models (Note: This requires additional permission and may not always work)
    log_info "Attempting to delete Vertex AI models..."
    local model_ids
    model_ids=$(gcloud ai models list \
        --region="${REGION}" \
        --filter="displayName:edge-inference-model" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$model_ids" ]]; then
        echo "$model_ids" | while read -r model_id; do
            if [[ -n "$model_id" ]]; then
                log_info "Deleting model: $model_id"
                gcloud ai models delete "$model_id" \
                    --region="${REGION}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete model $model_id"
            fi
        done
    else
        log_warning "No Vertex AI models found"
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Delete storage buckets function
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete buckets: ${MLOPS_BUCKET:-unknown}, ${EDGE_MODELS_BUCKET:-unknown}"
        return 0
    fi
    
    # Delete MLOps bucket
    if [[ -n "${MLOPS_BUCKET:-}" ]]; then
        log_info "Deleting MLOps bucket: $MLOPS_BUCKET"
        if gsutil ls "gs://${MLOPS_BUCKET}" &>/dev/null; then
            if gsutil -m rm -r "gs://${MLOPS_BUCKET}"; then
                log_success "MLOps bucket deleted"
            else
                log_error "Failed to delete MLOps bucket"
            fi
        else
            log_warning "MLOps bucket not found"
        fi
    fi
    
    # Delete edge models bucket
    if [[ -n "${EDGE_MODELS_BUCKET:-}" ]]; then
        log_info "Deleting edge models bucket: $EDGE_MODELS_BUCKET"
        if gsutil ls "gs://${EDGE_MODELS_BUCKET}" &>/dev/null; then
            if gsutil -m rm -r "gs://${EDGE_MODELS_BUCKET}"; then
                log_success "Edge models bucket deleted"
            else
                log_error "Failed to delete edge models bucket"
            fi
        else
            log_warning "Edge models bucket not found"
        fi
    fi
    
    log_success "Storage buckets cleanup completed"
}

# Delete service accounts function
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete service account: mlops-pipeline-sa"
        return 0
    fi
    
    # Delete service account
    log_info "Deleting mlops-pipeline-sa service account..."
    if gcloud iam service-accounts delete \
        "mlops-pipeline-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet 2>/dev/null; then
        log_success "Service account deleted"
    else
        log_warning "Service account not found or failed to delete"
    fi
    
    log_success "Service accounts cleanup completed"
}

# Delete project function
delete_project() {
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log_info "Keeping project as requested"
        return 0
    fi
    
    log_info "Deleting project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    # Final confirmation for project deletion
    if [[ "$FORCE" != "true" ]]; then
        echo ""
        echo -e "${RED}FINAL WARNING: About to delete project ${PROJECT_ID}${NC}"
        echo "This action is IRREVERSIBLE and will delete ALL resources in the project."
        echo ""
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_info "Project deletion cancelled by user."
            return 0
        fi
    fi
    
    log_warning "Deleting project: $PROJECT_ID"
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log_success "Project deleted successfully"
    else
        log_error "Failed to delete project"
    fi
}

# Clean up local files function
clean_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local deployment files"
        return 0
    fi
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/.env"
        "${SCRIPT_DIR}/training_pipeline.py"
        "${SCRIPT_DIR}/edge-inference-service.yaml"
        "${SCRIPT_DIR}/telemetry-collector.yaml"
        "${SCRIPT_DIR}/mlops-dashboard.json"
        "${SCRIPT_DIR}/edge-alert-policy.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    # Remove directories
    if [[ -d "${SCRIPT_DIR}/edge-model-updater" ]]; then
        log_info "Removing directory: ${SCRIPT_DIR}/edge-model-updater"
        rm -rf "${SCRIPT_DIR}/edge-model-updater"
    fi
    
    log_success "Local files cleanup completed"
}

# Resource inventory function
show_resource_inventory() {
    log_info "Creating resource inventory..."
    
    echo ""
    echo "=== RESOURCE INVENTORY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE:-unknown}"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # GKE Clusters
        echo "GKE Clusters:"
        gcloud container clusters list --filter="name:edge-simulation-cluster" 2>/dev/null || echo "  None found"
        
        # Cloud Storage Buckets
        echo ""
        echo "Cloud Storage Buckets:"
        gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(mlops-artifacts|edge-models)" || echo "  None found"
        
        # Cloud Functions
        echo ""
        echo "Cloud Functions:"
        gcloud functions list --filter="name:edge-model-updater" 2>/dev/null || echo "  None found"
        
        # Vertex AI Experiments
        echo ""
        echo "Vertex AI Experiments:"
        gcloud ai experiments list --region="${REGION}" --filter="displayName:Edge*" 2>/dev/null || echo "  None found"
        
        # Service Accounts
        echo ""
        echo "Service Accounts:"
        gcloud iam service-accounts list --filter="email:mlops-pipeline-sa@${PROJECT_ID}.iam.gserviceaccount.com" 2>/dev/null || echo "  None found"
    fi
    
    echo "=========================="
    echo ""
}

# Main destruction function
main() {
    log_info "Starting Edge-to-Cloud MLOps Pipelines cleanup..."
    
    # Load environment and check prerequisites
    load_environment
    check_prerequisites
    configure_gcloud
    
    # Show what will be destroyed
    show_resource_inventory
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be deleted"
    fi
    
    # Get user confirmation
    confirm_destruction
    
    # Execute cleanup steps in reverse order of creation
    delete_kubernetes_resources
    delete_gke_cluster
    delete_cloud_functions
    delete_monitoring_resources
    delete_vertex_ai_resources
    delete_storage_buckets
    delete_service_accounts
    delete_project
    clean_local_files
    
    # Final success message
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed. No resources were actually deleted."
    else
        log_success "Edge-to-Cloud MLOps Pipelines cleanup completed successfully!"
        
        if [[ "$KEEP_PROJECT" == "true" ]]; then
            log_info "Project ${PROJECT_ID} was preserved as requested."
            log_info "You may need to manually review and clean up any remaining resources."
        else
            log_info "Project ${PROJECT_ID} has been deleted."
        fi
    fi
    
    log_info "Cleanup logs saved to: ${LOG_FILE}"
    
    if [[ -f "${ERROR_LOG}" ]] && [[ -s "${ERROR_LOG}" ]]; then
        log_warning "Some errors occurred during cleanup. Check ${ERROR_LOG} for details."
    fi
}

# Run main function
main "$@"
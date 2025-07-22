#!/bin/bash

# Enterprise ML Model Lifecycle Management with AI Hypercomputer and Vertex AI Training
# Cleanup/Destroy Script for GCP Infrastructure
# Version: 1.0
# Description: Safely removes all ML lifecycle management infrastructure from GCP

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/deployment_env.sh"
LOG_FILE="/tmp/ml-cleanup-$(date +%Y%m%d-%H%M%S).log"
FORCE_DELETE=false
DRY_RUN=false

# Create log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "Starting Enterprise ML Model Lifecycle Management cleanup"
log "Log file: $LOG_FILE"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            warning "Force delete mode enabled - will not prompt for confirmation"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --help)
            echo "Usage: $0 [--force] [--dry-run] [--help]"
            echo "  --force    Skip confirmation prompts"
            echo "  --dry-run  Show what would be deleted without actually deleting"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load environment variables
load_environment() {
    log "Loading deployment environment..."
    
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        success "Environment loaded from $ENV_FILE"
    else
        warning "Environment file not found: $ENV_FILE"
        
        # Try to get environment from user input
        if [[ "$FORCE_DELETE" == "false" ]]; then
            read -p "Enter PROJECT_ID: " PROJECT_ID
            read -p "Enter REGION [us-central1]: " REGION
            REGION=${REGION:-us-central1}
            read -p "Enter ZONE [us-central1-a]: " ZONE
            ZONE=${ZONE:-us-central1-a}
            
            export PROJECT_ID REGION ZONE
        else
            error "Environment file not found and running in force mode"
        fi
    fi
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "PROJECT_ID is required"
    fi
    
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Zone: $ZONE"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project $PROJECT_ID does not exist or is not accessible"
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    success "Prerequisites check passed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete all ML lifecycle management resources in project: $PROJECT_ID"
    warning "This action cannot be undone!"
    
    echo -e "\nResources to be deleted:"
    echo "- All Vertex AI training jobs, experiments, and models"
    echo "- AI Hypercomputer infrastructure (TPUs and GPUs)"
    echo "- Cloud Workstations cluster and instances"
    echo "- Cloud Storage buckets and all data"
    echo "- BigQuery datasets and tables"
    echo "- Artifact Registry repositories"
    echo "- Monitoring dashboards and alerts"
    
    echo -e "\nType 'DELETE' to confirm deletion of all resources:"
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Stop active training jobs
stop_training_jobs() {
    log "Stopping active training jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would stop all active training jobs"
        return
    fi
    
    # List and cancel active training jobs
    local jobs
    jobs=$(gcloud ai custom-jobs list \
        --region="$REGION" \
        --filter="state:JOB_STATE_RUNNING OR state:JOB_STATE_PENDING" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$jobs" ]]; then
        while IFS= read -r job; do
            if [[ -n "$job" ]]; then
                log "Cancelling training job: $job"
                gcloud ai custom-jobs cancel "$job" --region="$REGION" --quiet || true
            fi
        done <<< "$jobs"
        
        # Wait for jobs to stop
        sleep 30
        success "Active training jobs stopped"
    else
        log "No active training jobs found"
    fi
}

# Remove AI Hypercomputer infrastructure
remove_ai_hypercomputer() {
    log "Removing AI Hypercomputer infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove TPU and GPU instances"
        return
    fi
    
    # Delete TPU instances
    local tpu_instances
    tpu_instances=$(gcloud compute tpus tpu-vm list \
        --zone="$ZONE" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$tpu_instances" ]]; then
        while IFS= read -r tpu; do
            if [[ -n "$tpu" ]]; then
                log "Deleting TPU instance: $tpu"
                gcloud compute tpus tpu-vm delete "$tpu" \
                    --zone="$ZONE" \
                    --quiet || true
            fi
        done <<< "$tpu_instances"
        success "TPU instances removed"
    else
        log "No TPU instances found"
    fi
    
    # Delete GPU instances
    local gpu_instances
    gpu_instances=$(gcloud compute instances list \
        --filter="zone:$ZONE AND machineType:a3-highgpu-8g" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$gpu_instances" ]]; then
        while IFS= read -r gpu; do
            if [[ -n "$gpu" ]]; then
                log "Deleting GPU instance: $gpu"
                gcloud compute instances delete "$gpu" \
                    --zone="$ZONE" \
                    --quiet || true
            fi
        done <<< "$gpu_instances"
        success "GPU instances removed"
    else
        log "No GPU instances found"
    fi
}

# Remove Vertex AI resources
remove_vertex_ai() {
    log "Removing Vertex AI resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove Vertex AI models, endpoints, and experiments"
        return
    fi
    
    # Delete endpoints first
    local endpoints
    endpoints=$(gcloud ai endpoints list \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$endpoints" ]]; then
        while IFS= read -r endpoint; do
            if [[ -n "$endpoint" ]]; then
                log "Deleting endpoint: $endpoint"
                gcloud ai endpoints delete "$endpoint" \
                    --region="$REGION" \
                    --quiet || true
            fi
        done <<< "$endpoints"
        success "Vertex AI endpoints removed"
    else
        log "No Vertex AI endpoints found"
    fi
    
    # Delete models
    local models
    models=$(gcloud ai models list \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$models" ]]; then
        while IFS= read -r model; do
            if [[ -n "$model" ]]; then
                log "Deleting model: $model"
                gcloud ai models delete "$model" \
                    --region="$REGION" \
                    --quiet || true
            fi
        done <<< "$models"
        success "Vertex AI models removed"
    else
        log "No Vertex AI models found"
    fi
    
    # Delete experiments (using Python since gcloud doesn't support this directly)
    log "Removing Vertex AI experiments..."
    python3 << 'EOF' || true
import os
from google.cloud import aiplatform

try:
    project_id = os.environ['PROJECT_ID']
    region = os.environ['REGION']
    
    aiplatform.init(project=project_id, location=region)
    
    experiments = aiplatform.Experiment.list()
    for experiment in experiments:
        try:
            experiment.delete()
            print(f"Deleted experiment: {experiment.display_name}")
        except Exception as e:
            print(f"Error deleting experiment {experiment.display_name}: {e}")
            
except Exception as e:
    print(f"Error connecting to Vertex AI: {e}")
EOF
    
    success "Vertex AI resources cleanup completed"
}

# Remove Cloud Workstations
remove_workstations() {
    log "Removing Cloud Workstations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove workstation instances, configs, and clusters"
        return
    fi
    
    # Delete workstation instances
    local workstation_instances
    workstation_instances=$(gcloud workstations list \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$workstation_instances" ]]; then
        while IFS= read -r workstation; do
            if [[ -n "$workstation" ]]; then
                # Extract cluster and config from workstation name
                local cluster_name config_name
                cluster_name=$(gcloud workstations describe "$workstation" \
                    --region="$REGION" \
                    --format="value(cluster)" 2>/dev/null | sed 's|.*/||' || true)
                config_name=$(gcloud workstations describe "$workstation" \
                    --region="$REGION" \
                    --format="value(config)" 2>/dev/null | sed 's|.*/||' || true)
                
                if [[ -n "$cluster_name" && -n "$config_name" ]]; then
                    log "Deleting workstation: $workstation"
                    gcloud workstations delete "$workstation" \
                        --cluster="$cluster_name" \
                        --config="$config_name" \
                        --region="$REGION" \
                        --quiet || true
                fi
            fi
        done <<< "$workstation_instances"
    fi
    
    # Delete workstation configurations
    local configs
    configs=$(gcloud workstations configs list \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$configs" ]]; then
        while IFS= read -r config; do
            if [[ -n "$config" ]]; then
                local cluster_name
                cluster_name=$(gcloud workstations configs describe "$config" \
                    --region="$REGION" \
                    --format="value(cluster)" 2>/dev/null | sed 's|.*/||' || true)
                
                if [[ -n "$cluster_name" ]]; then
                    log "Deleting workstation config: $config"
                    gcloud workstations configs delete "$config" \
                        --cluster="$cluster_name" \
                        --region="$REGION" \
                        --quiet || true
                fi
            fi
        done <<< "$configs"
    fi
    
    # Delete workstation clusters
    local clusters
    clusters=$(gcloud workstations clusters list \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$clusters" ]]; then
        while IFS= read -r cluster; do
            if [[ -n "$cluster" ]]; then
                log "Deleting workstation cluster: $cluster"
                gcloud workstations clusters delete "$cluster" \
                    --region="$REGION" \
                    --quiet || true
            fi
        done <<< "$clusters"
        success "Cloud Workstations removed"
    else
        log "No Cloud Workstations found"
    fi
}

# Remove Cloud Storage resources
remove_storage() {
    log "Removing Cloud Storage resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove all Cloud Storage buckets and data"
        return
    fi
    
    # List and delete buckets
    local buckets
    buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "^gs://.*-${PROJECT_ID}-" || true)
    
    if [[ -n "$buckets" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "$bucket" ]]; then
                log "Deleting bucket: $bucket"
                gsutil -m rm -r "$bucket" || true
            fi
        done <<< "$buckets"
        success "Cloud Storage buckets removed"
    else
        log "No project-specific Cloud Storage buckets found"
    fi
    
    # Also try to delete bucket if we have the name
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Attempting to delete bucket: gs://$BUCKET_NAME"
        gsutil -m rm -r "gs://$BUCKET_NAME" 2>/dev/null || true
    fi
}

# Remove BigQuery resources
remove_bigquery() {
    log "Removing BigQuery resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove BigQuery datasets and tables"
        return
    fi
    
    # List and delete datasets
    local datasets
    datasets=$(bq ls --project_id="$PROJECT_ID" --format=json 2>/dev/null | \
        python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for dataset in data:
        if 'ml_experiments' in dataset['datasetReference']['datasetId']:
            print(dataset['datasetReference']['datasetId'])
except:
    pass
" || true)
    
    if [[ -n "$datasets" ]]; then
        while IFS= read -r dataset; do
            if [[ -n "$dataset" ]]; then
                log "Deleting BigQuery dataset: $dataset"
                bq rm -r -f "${PROJECT_ID}:${dataset}" || true
            fi
        done <<< "$datasets"
        success "BigQuery datasets removed"
    else
        log "No ML-related BigQuery datasets found"
    fi
    
    # Also try to delete dataset if we have the name
    if [[ -n "${DATASET_NAME:-}" ]]; then
        log "Attempting to delete dataset: $DATASET_NAME"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null || true
    fi
}

# Remove Artifact Registry resources
remove_artifact_registry() {
    log "Removing Artifact Registry resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove Artifact Registry repositories"
        return
    fi
    
    # List and delete repositories
    local repositories
    repositories=$(gcloud artifacts repositories list \
        --location="$REGION" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$repositories" ]]; then
        while IFS= read -r repo; do
            if [[ -n "$repo" ]]; then
                log "Deleting Artifact Registry repository: $repo"
                gcloud artifacts repositories delete "$repo" \
                    --location="$REGION" \
                    --quiet || true
            fi
        done <<< "$repositories"
        success "Artifact Registry repositories removed"
    else
        log "No Artifact Registry repositories found"
    fi
}

# Remove monitoring resources
remove_monitoring() {
    log "Removing monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove monitoring dashboards and alerts"
        return
    fi
    
    # List and delete dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$dashboards" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "$dashboard" ]] && [[ "$dashboard" == *"Enterprise ML"* ]]; then
                log "Deleting monitoring dashboard: $dashboard"
                gcloud monitoring dashboards delete "$dashboard" \
                    --quiet || true
            fi
        done <<< "$dashboards"
        success "Monitoring dashboards removed"
    else
        log "No monitoring dashboards found"
    fi
    
    # List and delete alert policies
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy; do
            if [[ -n "$policy" ]] && [[ "$policy" == *"ML"* ]]; then
                log "Deleting alert policy: $policy"
                gcloud alpha monitoring policies delete "$policy" \
                    --quiet || true
            fi
        done <<< "$policies"
        success "Alert policies removed"
    else
        log "No alert policies found"
    fi
}

# Remove IAM resources
remove_iam_resources() {
    log "Removing custom IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove custom service accounts and roles"
        return
    fi
    
    # List and delete custom service accounts
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list \
        --format="value(email)" \
        --filter="email~ml-.*@${PROJECT_ID}.iam.gserviceaccount.com" 2>/dev/null || true)
    
    if [[ -n "$service_accounts" ]]; then
        while IFS= read -r sa; do
            if [[ -n "$sa" ]]; then
                log "Deleting service account: $sa"
                gcloud iam service-accounts delete "$sa" \
                    --quiet || true
            fi
        done <<< "$service_accounts"
        success "Custom service accounts removed"
    else
        log "No custom service accounts found"
    fi
}

# Cleanup environment file
cleanup_environment() {
    log "Cleaning up environment file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would remove environment file"
        return
    fi
    
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        success "Environment file removed: $ENV_FILE"
    fi
}

# Final project cleanup prompt
final_project_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would prompt for project deletion"
        return
    fi
    
    if [[ "$FORCE_DELETE" == "false" ]]; then
        warning "Do you want to delete the entire project? This will remove ALL resources in the project."
        echo "Type 'DELETE-PROJECT' to confirm project deletion, or press Enter to skip:"
        read -r project_confirmation
        
        if [[ "$project_confirmation" == "DELETE-PROJECT" ]]; then
            log "Deleting project: $PROJECT_ID"
            gcloud projects delete "$PROJECT_ID" --quiet || true
            success "Project deletion initiated"
        else
            log "Project deletion skipped"
        fi
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would verify cleanup"
        return
    fi
    
    local cleanup_issues=false
    
    # Check for remaining compute instances
    local instances
    instances=$(gcloud compute instances list \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$instances" ]]; then
        warning "Some compute instances may still exist:"
        echo "$instances"
        cleanup_issues=true
    fi
    
    # Check for remaining Cloud Storage buckets
    local buckets
    buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | head -5 || true)
    
    if [[ -n "$buckets" ]]; then
        warning "Some Cloud Storage buckets may still exist:"
        echo "$buckets"
        cleanup_issues=true
    fi
    
    # Check for remaining BigQuery datasets
    local datasets
    datasets=$(bq ls --project_id="$PROJECT_ID" --format=json 2>/dev/null | \
        python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for dataset in data:
        print(dataset['datasetReference']['datasetId'])
except:
    pass
" | head -5 || true)
    
    if [[ -n "$datasets" ]]; then
        warning "Some BigQuery datasets may still exist:"
        echo "$datasets"
        cleanup_issues=true
    fi
    
    if [[ "$cleanup_issues" == "true" ]]; then
        warning "Some resources may still exist. Check the Google Cloud Console for remaining resources."
    else
        success "Cleanup verification passed"
    fi
}

# Main cleanup function
main() {
    log "Starting Enterprise ML Model Lifecycle Management cleanup"
    
    # Load environment
    load_environment
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm deletion
    confirm_deletion
    
    # Stop active training jobs
    stop_training_jobs
    
    # Remove resources in dependency order
    remove_vertex_ai
    remove_ai_hypercomputer
    remove_workstations
    remove_storage
    remove_bigquery
    remove_artifact_registry
    remove_monitoring
    remove_iam_resources
    
    # Cleanup environment file
    cleanup_environment
    
    # Final project cleanup
    final_project_cleanup
    
    # Verify cleanup
    verify_cleanup
    
    # Final success message
    success "Enterprise ML Model Lifecycle Management cleanup completed!"
    
    log "Cleanup Summary:"
    log "- Project ID: $PROJECT_ID"
    log "- Cleanup log: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "This was a dry run - no resources were actually deleted"
    else
        log "All ML lifecycle management resources have been removed"
        warning "Check the Google Cloud Console to verify no unexpected resources remain"
        warning "Monitor your billing to ensure no ongoing charges"
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted. Check log file: $LOG_FILE"' INT TERM

# Run main function
main "$@"
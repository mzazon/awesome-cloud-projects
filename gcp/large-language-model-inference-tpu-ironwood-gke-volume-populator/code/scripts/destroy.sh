#!/bin/bash
set -euo pipefail

# Large Language Model Inference with TPU Ironwood and GKE Volume Populator - Cleanup Script
# This script safely removes all infrastructure created for the LLM inference deployment

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration variables - try to load from deployment if available
if [[ -f .deployment_vars ]]; then
    source .deployment_vars
    log "Loaded configuration from .deployment_vars"
fi

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER_NAME="${CLUSTER_NAME:-tpu-ironwood-cluster}"
BUCKET_NAME="${BUCKET_NAME:-}"
PARALLELSTORE_NAME="${PARALLELSTORE_NAME:-}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Display current configuration
display_config() {
    log "Cleanup Configuration:"
    echo "  Project ID: ${PROJECT_ID:-'Auto-detect from gcloud'}"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Bucket Name: ${BUCKET_NAME:-'Auto-detect'}"
    echo "  Parallelstore Name: ${PARALLELSTORE_NAME:-'Auto-detect'}"
    echo "  Service Account: ${SERVICE_ACCOUNT:-'Auto-detect'}"
    echo "  Force Delete: $FORCE_DELETE"
    echo "  Dry Run: $DRY_RUN"
    echo "  Skip Confirmation: $SKIP_CONFIRMATION"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud CLI with gsutil."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Get current project if not specified
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$PROJECT_ID" ]]; then
            error "No project ID specified and no default project configured."
            error "Use --project-id or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
        log "Using current project: $PROJECT_ID"
    fi
    
    success "Prerequisites check completed"
}

# Auto-detect resources if not specified
auto_detect_resources() {
    log "Auto-detecting resources for cleanup..."
    
    # Set gcloud project
    gcloud config set project "$PROJECT_ID" --quiet
    
    # Try to detect cluster and get credentials
    if [[ "$DRY_RUN" == "false" ]]; then
        if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &> /dev/null; then
            log "Found cluster: $CLUSTER_NAME"
            gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --quiet
        else
            warn "Cluster $CLUSTER_NAME not found in zone $ZONE"
        fi
    fi
    
    # Auto-detect bucket if not specified
    if [[ -z "$BUCKET_NAME" ]]; then
        local buckets=$(gsutil ls -p "$PROJECT_ID" | grep "llm-models-" | head -1 | sed 's|gs://||' | sed 's|/||')
        if [[ -n "$buckets" ]]; then
            BUCKET_NAME="$buckets"
            log "Auto-detected bucket: $BUCKET_NAME"
        fi
    fi
    
    # Auto-detect Parallelstore instance if not specified
    if [[ -z "$PARALLELSTORE_NAME" ]]; then
        local instances=$(gcloud parallelstore instances list --location="$ZONE" \
            --format="value(name)" --filter="name:model-storage-*" 2>/dev/null | head -1)
        if [[ -n "$instances" ]]; then
            PARALLELSTORE_NAME=$(basename "$instances")
            log "Auto-detected Parallelstore: $PARALLELSTORE_NAME"
        fi
    fi
    
    # Auto-detect service account if not specified
    if [[ -z "$SERVICE_ACCOUNT" ]]; then
        local sa=$(gcloud iam service-accounts list \
            --format="value(email)" --filter="email:tpu-inference-sa-*" 2>/dev/null | head -1)
        if [[ -n "$sa" ]]; then
            SERVICE_ACCOUNT=$(echo "$sa" | sed "s/@${PROJECT_ID}.iam.gserviceaccount.com//")
            log "Auto-detected service account: $SERVICE_ACCOUNT"
        fi
    fi
    
    success "Resource auto-detection completed"
}

# List resources to be deleted
list_resources() {
    log "Resources that will be deleted:"
    echo "================================"
    
    # Kubernetes resources
    if kubectl get deployment tpu-ironwood-inference &> /dev/null; then
        echo "✓ Kubernetes Deployment: tpu-ironwood-inference"
    fi
    
    if kubectl get service tpu-inference-service &> /dev/null; then
        echo "✓ Kubernetes Service: tpu-inference-service"
    fi
    
    if kubectl get pvc model-storage-pvc &> /dev/null; then
        echo "✓ Kubernetes PVC: model-storage-pvc"
    fi
    
    if kubectl get gcpdatasource llm-model-source &> /dev/null; then
        echo "✓ GCP Data Source: llm-model-source"
    fi
    
    if kubectl get storageclass parallelstore-csi-volume-populator &> /dev/null; then
        echo "✓ Storage Class: parallelstore-csi-volume-populator"
    fi
    
    if kubectl get serviceaccount tpu-inference-pod &> /dev/null; then
        echo "✓ Kubernetes Service Account: tpu-inference-pod"
    fi
    
    # GKE Cluster
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &> /dev/null; then
        echo "✓ GKE Cluster: $CLUSTER_NAME"
    fi
    
    # Parallelstore
    if [[ -n "$PARALLELSTORE_NAME" ]]; then
        if gcloud parallelstore instances describe "$PARALLELSTORE_NAME" --location="$ZONE" &> /dev/null; then
            echo "✓ Parallelstore Instance: $PARALLELSTORE_NAME"
        fi
    fi
    
    # Cloud Storage
    if [[ -n "$BUCKET_NAME" ]]; then
        if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
            echo "✓ Cloud Storage Bucket: gs://$BUCKET_NAME"
        fi
    fi
    
    # Service Account
    if [[ -n "$SERVICE_ACCOUNT" ]]; then
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
            echo "✓ Service Account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
        fi
    fi
    
    echo ""
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    warn "This operation will permanently delete all listed resources."
    warn "This action cannot be undone."
    echo ""
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warn "Force delete mode enabled - proceeding without additional confirmation"
        return
    fi
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warn "Final confirmation: This will delete billable resources."
    read -p "Continue with deletion? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove Kubernetes resources
remove_kubernetes_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Kubernetes resources"
        return
    fi
    
    log "Removing Kubernetes resources..."
    
    # Remove deployment
    if kubectl get deployment tpu-ironwood-inference &> /dev/null; then
        log "Deleting deployment: tpu-ironwood-inference"
        if kubectl delete deployment tpu-ironwood-inference --timeout=300s; then
            success "Deleted deployment"
        else
            warn "Failed to delete deployment (may not exist)"
        fi
    fi
    
    # Remove service
    if kubectl get service tpu-inference-service &> /dev/null; then
        log "Deleting service: tpu-inference-service"
        if kubectl delete service tpu-inference-service --timeout=300s; then
            success "Deleted service"
        else
            warn "Failed to delete service (may not exist)"
        fi
    fi
    
    # Remove PVC
    if kubectl get pvc model-storage-pvc &> /dev/null; then
        log "Deleting PVC: model-storage-pvc"
        if kubectl delete pvc model-storage-pvc --timeout=300s; then
            success "Deleted PVC"
        else
            warn "Failed to delete PVC (may not exist)"
        fi
    fi
    
    # Remove GCP Data Source
    if kubectl get gcpdatasource llm-model-source &> /dev/null; then
        log "Deleting GCP Data Source: llm-model-source"
        if kubectl delete gcpdatasource llm-model-source --timeout=60s; then
            success "Deleted GCP Data Source"
        else
            warn "Failed to delete GCP Data Source (may not exist)"
        fi
    fi
    
    # Remove Storage Class
    if kubectl get storageclass parallelstore-csi-volume-populator &> /dev/null; then
        log "Deleting Storage Class: parallelstore-csi-volume-populator"
        if kubectl delete storageclass parallelstore-csi-volume-populator; then
            success "Deleted Storage Class"
        else
            warn "Failed to delete Storage Class (may not exist)"
        fi
    fi
    
    # Remove Kubernetes service account
    if kubectl get serviceaccount tpu-inference-pod &> /dev/null; then
        log "Deleting Kubernetes service account: tpu-inference-pod"
        if kubectl delete serviceaccount tpu-inference-pod; then
            success "Deleted Kubernetes service account"
        else
            warn "Failed to delete Kubernetes service account (may not exist)"
        fi
    fi
    
    success "Kubernetes resources cleanup completed"
}

# Remove GKE cluster
remove_gke_cluster() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove GKE cluster: $CLUSTER_NAME"
        return
    fi
    
    log "Removing GKE cluster..."
    
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &> /dev/null; then
        log "Deleting GKE cluster: $CLUSTER_NAME"
        if gcloud container clusters delete "$CLUSTER_NAME" \
            --zone="$ZONE" \
            --quiet; then
            success "Deleted GKE cluster"
        else
            error "Failed to delete GKE cluster"
            exit 1
        fi
    else
        warn "GKE cluster $CLUSTER_NAME not found"
    fi
}

# Remove Parallelstore instance
remove_parallelstore() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Parallelstore instance: $PARALLELSTORE_NAME"
        return
    fi
    
    if [[ -z "$PARALLELSTORE_NAME" ]]; then
        warn "No Parallelstore instance name specified, skipping"
        return
    fi
    
    log "Removing Parallelstore instance..."
    
    if gcloud parallelstore instances describe "$PARALLELSTORE_NAME" --location="$ZONE" &> /dev/null; then
        log "Deleting Parallelstore instance: $PARALLELSTORE_NAME"
        if gcloud parallelstore instances delete "$PARALLELSTORE_NAME" \
            --location="$ZONE" \
            --quiet; then
            success "Deleted Parallelstore instance"
        else
            error "Failed to delete Parallelstore instance"
            exit 1
        fi
    else
        warn "Parallelstore instance $PARALLELSTORE_NAME not found"
    fi
}

# Remove Cloud Storage bucket
remove_storage_bucket() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Cloud Storage bucket: gs://$BUCKET_NAME"
        return
    fi
    
    if [[ -z "$BUCKET_NAME" ]]; then
        warn "No bucket name specified, skipping"
        return
    fi
    
    log "Removing Cloud Storage bucket..."
    
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log "Deleting bucket contents and bucket: gs://$BUCKET_NAME"
        
        # Check if bucket has contents
        local object_count=$(gsutil ls "gs://$BUCKET_NAME/**" 2>/dev/null | wc -l || echo "0")
        if [[ $object_count -gt 0 ]]; then
            log "Removing $object_count objects from bucket..."
            if gsutil -m rm -r "gs://$BUCKET_NAME/**"; then
                success "Removed bucket contents"
            else
                warn "Failed to remove some bucket contents"
            fi
        fi
        
        # Remove the bucket
        if gsutil rb "gs://$BUCKET_NAME"; then
            success "Deleted Cloud Storage bucket"
        else
            error "Failed to delete Cloud Storage bucket"
            exit 1
        fi
    else
        warn "Bucket gs://$BUCKET_NAME not found"
    fi
}

# Remove service account
remove_service_account() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove service account: $SERVICE_ACCOUNT"
        return
    fi
    
    if [[ -z "$SERVICE_ACCOUNT" ]]; then
        warn "No service account specified, skipping"
        return
    fi
    
    log "Removing service account..."
    
    local sa_email="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
        # Remove IAM policy bindings first
        log "Removing IAM policy bindings..."
        local roles=(
            "roles/tpu.admin"
            "roles/storage.objectViewer"
            "roles/parallelstore.admin"
            "roles/iam.workloadIdentityUser"
        )
        
        for role in "${roles[@]}"; do
            log "Removing role $role from service account..."
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa_email" \
                --role="$role" \
                --quiet 2>/dev/null || true
        done
        
        # Remove Workload Identity binding
        gcloud iam service-accounts remove-iam-policy-binding \
            --role="roles/iam.workloadIdentityUser" \
            --member="serviceAccount:${PROJECT_ID}.svc.id.goog[default/tpu-inference-pod]" \
            "$sa_email" \
            --quiet 2>/dev/null || true
        
        # Delete the service account
        log "Deleting service account: $sa_email"
        if gcloud iam service-accounts delete "$sa_email" --quiet; then
            success "Deleted service account"
        else
            error "Failed to delete service account"
            exit 1
        fi
    else
        warn "Service account $sa_email not found"
    fi
}

# Clean up monitoring resources
remove_monitoring_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove monitoring dashboards"
        return
    fi
    
    log "Removing monitoring dashboards..."
    
    # List and remove dashboards related to TPU Ironwood
    local dashboards=$(gcloud alpha monitoring dashboards list \
        --filter="displayName:'TPU Ironwood LLM Inference Dashboard'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        echo "$dashboards" | while read -r dashboard; do
            if [[ -n "$dashboard" ]]; then
                log "Deleting dashboard: $dashboard"
                gcloud alpha monitoring dashboards delete "$dashboard" --quiet || true
            fi
        done
        success "Removed monitoring dashboards"
    else
        warn "No monitoring dashboards found"
    fi
}

# Clean up local files
cleanup_local_files() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up local files"
        return
    fi
    
    log "Cleaning up local files..."
    
    # Remove deployment variables file
    if [[ -f .deployment_vars ]]; then
        rm -f .deployment_vars
        success "Removed .deployment_vars"
    fi
    
    # Remove any temporary dashboard config files
    if [[ -f dashboard_config.json ]]; then
        rm -f dashboard_config.json
        success "Removed dashboard_config.json"
    fi
    
    success "Local files cleanup completed"
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "All resources have been successfully removed."
        echo "You may want to verify in the Google Cloud Console:"
        echo "- GKE clusters: https://console.cloud.google.com/kubernetes/list"
        echo "- Storage buckets: https://console.cloud.google.com/storage"
        echo "- Parallelstore: https://console.cloud.google.com/parallelstore"
        echo "- Service accounts: https://console.cloud.google.com/iam-admin/serviceaccounts"
    else
        echo ""
        echo "Dry run completed. No resources were actually deleted."
    fi
    
    success "Cleanup completed successfully!"
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining Kubernetes resources
    if kubectl get deployment tpu-ironwood-inference &> /dev/null; then
        warn "Deployment still exists: tpu-ironwood-inference"
        ((cleanup_issues++))
    fi
    
    # Check for remaining cluster
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &> /dev/null; then
        warn "Cluster still exists: $CLUSTER_NAME"
        ((cleanup_issues++))
    fi
    
    # Check for remaining bucket
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        warn "Bucket still exists: gs://$BUCKET_NAME"
        ((cleanup_issues++))
    fi
    
    # Check for remaining Parallelstore
    if [[ -n "$PARALLELSTORE_NAME" ]] && gcloud parallelstore instances describe "$PARALLELSTORE_NAME" --location="$ZONE" &> /dev/null; then
        warn "Parallelstore still exists: $PARALLELSTORE_NAME"
        ((cleanup_issues++))
    fi
    
    # Check for remaining service account
    if [[ -n "$SERVICE_ACCOUNT" ]] && gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        warn "Service account still exists: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed"
    else
        warn "Cleanup verification found $cleanup_issues remaining resources"
        warn "Some resources may take additional time to be fully deleted"
    fi
}

# Main execution
main() {
    log "Starting TPU Ironwood LLM Inference cleanup..."
    
    display_config
    check_prerequisites
    auto_detect_resources
    list_resources
    confirm_deletion
    
    # Execute cleanup in reverse order of creation
    remove_monitoring_resources
    remove_kubernetes_resources
    remove_gke_cluster
    remove_parallelstore
    remove_storage_bucket
    remove_service_account
    cleanup_local_files
    
    verify_cleanup
    display_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
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
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --parallelstore-name)
            PARALLELSTORE_NAME="$2"
            shift 2
            ;;
        --service-account)
            SERVICE_ACCOUNT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run                    Show what would be deleted without making changes"
            echo "  --force                      Skip additional confirmation prompts"
            echo "  --skip-confirmation          Skip all confirmation prompts (dangerous!)"
            echo "  --project-id ID              Google Cloud project ID"
            echo "  --region REGION              Google Cloud region (default: us-central1)"
            echo "  --zone ZONE                  Google Cloud zone (default: us-central1-a)"
            echo "  --cluster-name NAME          GKE cluster name (default: tpu-ironwood-cluster)"
            echo "  --bucket-name NAME           Cloud Storage bucket name"
            echo "  --parallelstore-name NAME    Parallelstore instance name"
            echo "  --service-account NAME       Service account name (without @project.iam...)"
            echo "  --help                       Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  PROJECT_ID                   Google Cloud project ID"
            echo "  REGION                       Google Cloud region"
            echo "  ZONE                         Google Cloud zone"
            echo "  FORCE_DELETE                 Set to 'true' to skip confirmations"
            echo "  DRY_RUN                      Set to 'true' for dry run mode"
            echo "  SKIP_CONFIRMATION            Set to 'true' to skip all confirmations"
            echo ""
            echo "Note: The script will attempt to auto-detect resources if not specified."
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"
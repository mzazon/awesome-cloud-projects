#!/bin/bash

# Software Supply Chain Security with Binary Authorization and Cloud Build
# Cleanup/Destroy Script for GCP Recipe
# 
# This script safely removes all resources created by the deployment script:
# - Kubernetes deployments and services
# - GKE cluster
# - Binary Authorization policies and attestors
# - Cloud KMS resources
# - Artifact Registry repository
# - Local files and configurations

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Command: $2"
    log_error "Exit code: $3"
    log_warning "Continuing with cleanup of remaining resources..."
}

# Set up error trap that continues cleanup
trap 'handle_error $LINENO "$BASH_COMMAND" $?' ERR

# Configuration variables (can be overridden via environment)
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER_NAME="${CLUSTER_NAME:-secure-cluster}"
REPO_NAME="${REPO_NAME:-secure-images}"

# Resource names (try to detect from environment or use defaults)
KEYRING_NAME="${KEYRING_NAME:-}"
KEY_NAME="${KEY_NAME:-}"
ATTESTOR_NAME="${ATTESTOR_NAME:-}"

# Control flags
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. Will skip Kubernetes resource cleanup."
    fi
    
    # Check if project ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set. Please set it via environment variable or configure gcloud."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to configure environment
configure_environment() {
    log "Configuring environment for cleanup..."
    
    # Set project, region, and zone
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment configured for project: $PROJECT_ID"
}

# Function to discover resource names
discover_resources() {
    log "Discovering existing resources..."
    
    # Try to find resources if not provided
    if [[ -z "$KEYRING_NAME" ]]; then
        local found_keyring=$(gcloud kms keyrings list --location="$REGION" --filter="name~binauthz-keyring" --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -n "$found_keyring" ]]; then
            KEYRING_NAME=$(basename "$found_keyring")
            log "Found keyring: $KEYRING_NAME"
        fi
    fi
    
    if [[ -z "$ATTESTOR_NAME" ]]; then
        local found_attestor=$(gcloud container binauthz attestors list --filter="name~build-attestor" --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -n "$found_attestor" ]]; then
            ATTESTOR_NAME=$(basename "$found_attestor")
            log "Found attestor: $ATTESTOR_NAME"
        fi
    fi
    
    if [[ -z "$KEY_NAME" && -n "$KEYRING_NAME" ]]; then
        local found_key=$(gcloud kms keys list --location="$REGION" --keyring="$KEYRING_NAME" --filter="name~attestor-key" --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -n "$found_key" ]]; then
            KEY_NAME=$(basename "$found_key")
            log "Found key: $KEY_NAME"
        fi
    fi
    
    log_success "Resource discovery completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will permanently delete the following resources:"
    echo "  - Project: $PROJECT_ID"
    echo "  - Region: $REGION"
    echo "  - Zone: $ZONE"
    echo "  - GKE Cluster: $CLUSTER_NAME"
    echo "  - Artifact Registry: $REPO_NAME"
    echo "  - KMS Keyring: ${KEYRING_NAME:-"(auto-discover)"}"
    echo "  - KMS Key: ${KEY_NAME:-"(auto-discover)"}"
    echo "  - Attestor: ${ATTESTOR_NAME:-"(auto-discover)"}"
    echo "  - All Kubernetes resources"
    echo "  - All local files and configurations"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would prompt for confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed with deletion? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_success "Deletion confirmed by user"
}

# Function to cleanup Kubernetes resources
cleanup_kubernetes_resources() {
    log "Cleaning up Kubernetes resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would cleanup Kubernetes resources"
        return 0
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not available, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Try to get cluster credentials
    if ! gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --quiet 2>/dev/null; then
        log_warning "Could not get cluster credentials, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Delete application deployment and service
    if kubectl get deployment secure-app --quiet 2>/dev/null; then
        log "Deleting secure-app deployment..."
        kubectl delete deployment secure-app --timeout=60s || log_warning "Failed to delete deployment"
    fi
    
    if kubectl get service secure-app-service --quiet 2>/dev/null; then
        log "Deleting secure-app service..."
        kubectl delete service secure-app-service --timeout=60s || log_warning "Failed to delete service"
    fi
    
    # Delete any test deployments
    if kubectl get deployment test-unauthorized --quiet 2>/dev/null; then
        log "Deleting test-unauthorized deployment..."
        kubectl delete deployment test-unauthorized --timeout=60s || log_warning "Failed to delete test deployment"
    fi
    
    # Clean up any remaining resources
    log "Cleaning up any remaining application resources..."
    kubectl delete all -l app=secure-app --timeout=60s || log_warning "Failed to delete remaining resources"
    
    log_success "Kubernetes resources cleaned up"
}

# Function to delete GKE cluster
delete_gke_cluster() {
    log "Deleting GKE cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would delete GKE cluster"
        return 0
    fi
    
    # Check if cluster exists
    if ! gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --quiet 2>/dev/null; then
        log_warning "GKE cluster $CLUSTER_NAME does not exist in $ZONE"
        return 0
    fi
    
    log "Deleting GKE cluster: $CLUSTER_NAME"
    gcloud container clusters delete "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --quiet \
        --async || log_warning "Failed to delete GKE cluster"
    
    log_success "GKE cluster deletion initiated (async)"
}

# Function to reset Binary Authorization policy
reset_binauthz_policy() {
    log "Resetting Binary Authorization policy to default..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would reset Binary Authorization policy"
        return 0
    fi
    
    # Create default policy
    cat > /tmp/default-binauthz-policy.yaml <<EOF
defaultAdmissionRule:
  evaluationMode: ALWAYS_ALLOW
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF
    
    # Apply default policy
    gcloud container binauthz policy import /tmp/default-binauthz-policy.yaml --quiet || log_warning "Failed to reset Binary Authorization policy"
    
    # Clean up temporary file
    rm -f /tmp/default-binauthz-policy.yaml
    
    log_success "Binary Authorization policy reset to default"
}

# Function to delete Binary Authorization attestor
delete_attestor() {
    log "Deleting Binary Authorization attestor..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would delete Binary Authorization attestor"
        return 0
    fi
    
    if [[ -z "$ATTESTOR_NAME" ]]; then
        log_warning "No attestor name provided, skipping attestor deletion"
        return 0
    fi
    
    # Check if attestor exists
    if ! gcloud container binauthz attestors describe "$ATTESTOR_NAME" --quiet 2>/dev/null; then
        log_warning "Attestor $ATTESTOR_NAME does not exist"
        return 0
    fi
    
    log "Deleting attestor: $ATTESTOR_NAME"
    gcloud container binauthz attestors delete "$ATTESTOR_NAME" --quiet || log_warning "Failed to delete attestor"
    
    log_success "Binary Authorization attestor deleted"
}

# Function to delete KMS resources
delete_kms_resources() {
    log "Managing KMS resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would manage KMS resources"
        return 0
    fi
    
    if [[ -z "$KEYRING_NAME" || -z "$KEY_NAME" ]]; then
        log_warning "KMS resource names not provided, skipping KMS cleanup"
        return 0
    fi
    
    # Check if key exists
    if ! gcloud kms keys describe "$KEY_NAME" --keyring="$KEYRING_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_warning "KMS key $KEY_NAME does not exist in keyring $KEYRING_NAME"
        return 0
    fi
    
    # Disable key versions (cannot delete immediately due to retention policy)
    log "Disabling KMS key versions..."
    local key_versions=$(gcloud kms keys versions list --key="$KEY_NAME" --keyring="$KEYRING_NAME" --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$key_versions" ]]; then
        while IFS= read -r version; do
            local version_number=$(basename "$version")
            log "Disabling key version: $version_number"
            gcloud kms keys versions destroy "$version_number" \
                --key="$KEY_NAME" \
                --keyring="$KEYRING_NAME" \
                --location="$REGION" \
                --quiet || log_warning "Failed to disable key version $version_number"
        done <<< "$key_versions"
    fi
    
    log_success "KMS key versions disabled (will be deleted after retention period)"
    log_warning "Note: KMS keys have a mandatory retention period before permanent deletion"
}

# Function to delete Artifact Registry repository
delete_artifact_registry() {
    log "Deleting Artifact Registry repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would delete Artifact Registry repository"
        return 0
    fi
    
    # Check if repository exists
    if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_warning "Artifact Registry repository $REPO_NAME does not exist in $REGION"
        return 0
    fi
    
    log "Deleting Artifact Registry repository: $REPO_NAME"
    gcloud artifacts repositories delete "$REPO_NAME" \
        --location="$REGION" \
        --quiet || log_warning "Failed to delete Artifact Registry repository"
    
    log_success "Artifact Registry repository deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would cleanup local files"
        return 0
    fi
    
    local files_to_remove=(
        "secure-app"
        "deployment.yaml"
        "image_url.txt"
        "binauthz-policy.yaml"
        "/tmp/binauthz-policy.yaml"
        "/tmp/default-binauthz-policy.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            log "Removing: $file"
            rm -rf "$file" || log_warning "Failed to remove $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would verify cleanup"
        return 0
    fi
    
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check GKE cluster
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --quiet 2>/dev/null; then
        log_warning "⚠️  GKE cluster $CLUSTER_NAME still exists (may be deleting asynchronously)"
    else
        log_success "✅ GKE cluster $CLUSTER_NAME removed"
    fi
    
    # Check Artifact Registry
    if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_warning "⚠️  Artifact Registry repository $REPO_NAME still exists"
        ((cleanup_issues++))
    else
        log_success "✅ Artifact Registry repository $REPO_NAME removed"
    fi
    
    # Check attestor
    if [[ -n "$ATTESTOR_NAME" ]]; then
        if gcloud container binauthz attestors describe "$ATTESTOR_NAME" --quiet 2>/dev/null; then
            log_warning "⚠️  Attestor $ATTESTOR_NAME still exists"
            ((cleanup_issues++))
        else
            log_success "✅ Attestor $ATTESTOR_NAME removed"
        fi
    fi
    
    # Check KMS resources
    if [[ -n "$KEYRING_NAME" && -n "$KEY_NAME" ]]; then
        if gcloud kms keys describe "$KEY_NAME" --keyring="$KEYRING_NAME" --location="$REGION" --quiet 2>/dev/null; then
            log_warning "⚠️  KMS key $KEY_NAME still exists (disabled, will be deleted after retention period)"
        else
            log_success "✅ KMS key $KEY_NAME removed"
        fi
    fi
    
    # Check local files
    local remaining_files=()
    if [[ -d "secure-app" ]]; then remaining_files+=("secure-app"); fi
    if [[ -f "deployment.yaml" ]]; then remaining_files+=("deployment.yaml"); fi
    if [[ -f "image_url.txt" ]]; then remaining_files+=("image_url.txt"); fi
    
    if [[ ${#remaining_files[@]} -gt 0 ]]; then
        log_warning "⚠️  Some local files still exist: ${remaining_files[*]}"
        ((cleanup_issues++))
    else
        log_success "✅ Local files cleaned up"
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "✅ All resources successfully cleaned up"
    else
        log_warning "⚠️  $cleanup_issues issues found during cleanup verification"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Repository Name: $REPO_NAME"
    echo "Key Ring: ${KEYRING_NAME:-"(not found)"}"
    echo "Key Name: ${KEY_NAME:-"(not found)"}"
    echo "Attestor Name: ${ATTESTOR_NAME:-"(not found)"}"
    echo "===================="
    echo ""
    log_success "🎉 Cleanup completed!"
    echo ""
    echo "Important notes:"
    echo "• GKE cluster deletion is asynchronous and may take several minutes"
    echo "• KMS keys are disabled but have a mandatory retention period"
    echo "• Binary Authorization policy has been reset to default"
    echo "• All local files and configurations have been removed"
    echo ""
    echo "To verify all resources are cleaned up, you can:"
    echo "1. Check the GCP Console for any remaining resources"
    echo "2. Review your billing to ensure no ongoing charges"
    echo "3. Run 'gcloud container clusters list' to confirm cluster deletion"
}

# Function to handle script interruption
handle_interrupt() {
    log_warning "Script interrupted by user"
    log_warning "Cleanup may be incomplete. Please run the script again or manually verify resources."
    exit 130
}

# Set up interrupt handling
trap handle_interrupt SIGINT SIGTERM

# Main cleanup function
main() {
    echo "🧹 Starting Software Supply Chain Security Cleanup"
    echo "=================================================="
    
    # Parse command line arguments
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
            --yes)
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
            --repo-name)
                REPO_NAME="$2"
                shift 2
                ;;
            --keyring-name)
                KEYRING_NAME="$2"
                shift 2
                ;;
            --key-name)
                KEY_NAME="$2"
                shift 2
                ;;
            --attestor-name)
                ATTESTOR_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --dry-run              Show what would be done without executing"
                echo "  --force                Skip safety checks and force deletion"
                echo "  --yes                  Skip confirmation prompts"
                echo "  --project-id ID        Override project ID"
                echo "  --region REGION        Override region (default: us-central1)"
                echo "  --zone ZONE            Override zone (default: us-central1-a)"
                echo "  --cluster-name NAME    Override cluster name"
                echo "  --repo-name NAME       Override repository name"
                echo "  --keyring-name NAME    Override keyring name"
                echo "  --key-name NAME        Override key name"
                echo "  --attestor-name NAME   Override attestor name"
                echo "  --help                 Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    configure_environment
    discover_resources
    confirm_deletion
    cleanup_kubernetes_resources
    delete_gke_cluster
    reset_binauthz_policy
    delete_attestor
    delete_kms_resources
    delete_artifact_registry
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    echo ""
    log_success "🎉 Software Supply Chain Security cleanup completed!"
    echo ""
    echo "If you need to redeploy the solution, run: ./deploy.sh"
}

# Run main function
main "$@"
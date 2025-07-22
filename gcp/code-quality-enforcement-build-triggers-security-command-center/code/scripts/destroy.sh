#!/bin/bash

# Code Quality Enforcement with Cloud Build Triggers and Security Command Center - Cleanup Script
# This script removes all resources created by the deployment script including GKE cluster,
# Binary Authorization policies, Cloud Build triggers, and Security Command Center sources.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${ROOT_DIR}/cleanup.log"
readonly STATE_FILE="${ROOT_DIR}/.deployment_state"
readonly SCC_SOURCE_FILE="${ROOT_DIR}/.scc_source"

# Default values (will be overridden by state file if it exists)
PROJECT_ID=""
REGION=""
ZONE=""
CLUSTER_NAME=""
REPO_NAME=""
TRIGGER_NAME=""
ATTESTOR_NAME=""
SERVICE_ACCOUNT=""
SCC_SOURCE=""

# Function to load deployment state
load_deployment_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log_info "Loading deployment state from $STATE_FILE"
        # shellcheck source=/dev/null
        source "$STATE_FILE"
        log_success "Deployment state loaded"
    else
        log_warning "No deployment state file found at $STATE_FILE"
        log_warning "Some cleanup operations may not work without deployment state"
        
        # Try to get basic info from gcloud if possible
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID found. Please set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Load SCC source if available
    if [[ -f "$SCC_SOURCE_FILE" ]]; then
        SCC_SOURCE=$(cat "$SCC_SOURCE_FILE")
    fi
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - Project: $PROJECT_ID"
    echo "  - GKE Cluster: $CLUSTER_NAME (if exists)"
    echo "  - Repository: $REPO_NAME (if exists)"
    echo "  - Build Trigger: $TRIGGER_NAME (if exists)"
    echo "  - Attestor: $ATTESTOR_NAME (if exists)"
    echo "  - Service Account: $SERVICE_ACCOUNT (if exists)"
    echo "  - KMS keys and keyrings"
    echo "  - Security Command Center sources"
    echo
    
    # Check for --force flag
    if [[ "${1:-}" == "--force" ]]; then
        log_info "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. Kubernetes resource cleanup may be limited."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to remove Kubernetes resources
remove_kubernetes_resources() {
    log_info "Removing Kubernetes resources..."
    
    # Check if kubectl is available and cluster exists
    if command -v kubectl &> /dev/null && [[ -n "$CLUSTER_NAME" ]] && [[ -n "$ZONE" ]]; then
        # Try to get cluster credentials
        if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" 2>/dev/null; then
            # Remove deployment if k8s-deployment.yaml exists
            if [[ -f "$ROOT_DIR/k8s-deployment.yaml" ]]; then
                kubectl delete -f "$ROOT_DIR/k8s-deployment.yaml" 2>&1 | tee -a "$LOG_FILE" || true
                rm -f "$ROOT_DIR/k8s-deployment.yaml"
                log_success "Kubernetes deployment removed"
            else
                log_warning "k8s-deployment.yaml not found"
            fi
        else
            log_warning "Could not connect to cluster $CLUSTER_NAME"
        fi
    else
        log_warning "Skipping Kubernetes cleanup - kubectl not available or cluster info missing"
    fi
}

# Function to delete GKE cluster
delete_gke_cluster() {
    log_info "Deleting GKE cluster..."
    
    if [[ -n "$CLUSTER_NAME" ]] && [[ -n "$ZONE" ]]; then
        # Check if cluster exists
        if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &>/dev/null; then
            gcloud container clusters delete "$CLUSTER_NAME" \
                --zone="$ZONE" \
                --quiet 2>&1 | tee -a "$LOG_FILE"
            log_success "GKE cluster deleted: $CLUSTER_NAME"
        else
            log_warning "GKE cluster $CLUSTER_NAME not found or already deleted"
        fi
    else
        log_warning "Cluster name or zone not specified, skipping GKE cleanup"
    fi
}

# Function to remove Binary Authorization resources
remove_binary_authorization() {
    log_info "Removing Binary Authorization resources..."
    
    # Reset Binary Authorization policy to default
    log_info "Resetting Binary Authorization policy to default..."
    gcloud container binauthz policy import /dev/stdin << 'EOF' 2>&1 | tee -a "$LOG_FILE" || true
defaultAdmissionRule:
  evaluationMode: ALWAYS_ALLOW
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
globalPolicyEvaluationMode: ENABLE
EOF
    
    # Delete attestor if it exists
    if [[ -n "$ATTESTOR_NAME" ]]; then
        if gcloud container binauthz attestors describe "$ATTESTOR_NAME" &>/dev/null; then
            gcloud container binauthz attestors delete "$ATTESTOR_NAME" --quiet 2>&1 | tee -a "$LOG_FILE"
            log_success "Attestor deleted: $ATTESTOR_NAME"
        else
            log_warning "Attestor $ATTESTOR_NAME not found or already deleted"
        fi
    fi
    
    # Delete KMS resources
    log_info "Removing KMS resources..."
    
    # Destroy key version first
    if gcloud kms keys versions list --key=attestor-key --keyring=binauthz-ring --location=global --format="value(name)" 2>/dev/null | head -1 | grep -q .; then
        local key_version
        key_version=$(gcloud kms keys versions list --key=attestor-key --keyring=binauthz-ring --location=global --format="value(name)" | head -1)
        if [[ -n "$key_version" ]]; then
            gcloud kms keys versions destroy "$key_version" --quiet 2>&1 | tee -a "$LOG_FILE" || true
        fi
    fi
    
    # Schedule key for destruction
    if gcloud kms keys describe attestor-key --keyring=binauthz-ring --location=global &>/dev/null; then
        gcloud kms keys destroy attestor-key \
            --keyring=binauthz-ring \
            --location=global \
            --quiet 2>&1 | tee -a "$LOG_FILE" || true
        log_success "KMS key scheduled for destruction"
    else
        log_warning "KMS key not found or already deleted"
    fi
    
    log_success "Binary Authorization resources removed"
}

# Function to clean up Cloud Build resources
cleanup_cloud_build() {
    log_info "Cleaning up Cloud Build resources..."
    
    # Delete Cloud Build trigger
    if [[ -n "$TRIGGER_NAME" ]]; then
        if gcloud builds triggers describe "$TRIGGER_NAME" &>/dev/null; then
            gcloud builds triggers delete "$TRIGGER_NAME" --quiet 2>&1 | tee -a "$LOG_FILE"
            log_success "Cloud Build trigger deleted: $TRIGGER_NAME"
        else
            log_warning "Build trigger $TRIGGER_NAME not found or already deleted"
        fi
    fi
    
    # Delete Cloud Source Repository
    if [[ -n "$REPO_NAME" ]]; then
        if gcloud source repos describe "$REPO_NAME" &>/dev/null; then
            gcloud source repos delete "$REPO_NAME" --quiet 2>&1 | tee -a "$LOG_FILE"
            log_success "Cloud Source Repository deleted: $REPO_NAME"
        else
            log_warning "Repository $REPO_NAME not found or already deleted"
        fi
    fi
    
    log_success "Cloud Build resources cleaned up"
}

# Function to remove service account
remove_service_account() {
    log_info "Removing service account..."
    
    if [[ -n "$SERVICE_ACCOUNT" ]] && [[ -n "$PROJECT_ID" ]]; then
        local sa_email="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if gcloud iam service-accounts describe "$sa_email" &>/dev/null; then
            # Remove IAM policy bindings first
            local roles=(
                "roles/cloudbuild.builds.builder"
                "roles/binaryauthorization.attestorsEditor"
                "roles/containeranalysis.notes.editor"
                "roles/securitycenter.findingsEditor"
            )
            
            for role in "${roles[@]}"; do
                gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                    --member="serviceAccount:${sa_email}" \
                    --role="$role" 2>&1 | tee -a "$LOG_FILE" || true
            done
            
            # Delete service account
            gcloud iam service-accounts delete "$sa_email" --quiet 2>&1 | tee -a "$LOG_FILE"
            log_success "Service account deleted: $sa_email"
        else
            log_warning "Service account $sa_email not found or already deleted"
        fi
    else
        log_warning "Service account name or project ID not specified"
    fi
}

# Function to remove Security Command Center resources
remove_security_command_center() {
    log_info "Removing Security Command Center resources..."
    
    if [[ -n "$SCC_SOURCE" ]]; then
        if gcloud scc sources describe "$SCC_SOURCE" &>/dev/null; then
            gcloud scc sources delete "$SCC_SOURCE" --quiet 2>&1 | tee -a "$LOG_FILE"
            log_success "Security Command Center source deleted: $SCC_SOURCE"
        else
            log_warning "SCC source $SCC_SOURCE not found or already deleted"
        fi
    else
        log_warning "No SCC source found to delete"
    fi
}

# Function to clean up container images
cleanup_container_images() {
    log_info "Cleaning up container images..."
    
    # List and delete images from Google Container Registry
    local images
    images=$(gcloud container images list --repository="gcr.io/$PROJECT_ID" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$images" ]]; then
        echo "$images" | while read -r image; do
            if [[ "$image" == *"secure-app"* ]]; then
                log_info "Deleting image: $image"
                gcloud container images delete "$image" --force-delete-tags --quiet 2>&1 | tee -a "$LOG_FILE" || true
            fi
        done
        log_success "Container images cleaned up"
    else
        log_info "No container images found to clean up"
    fi
}

# Function to remove local files
remove_local_files() {
    log_info "Removing local files..."
    
    local files_to_remove=(
        "$STATE_FILE"
        "$SCC_SOURCE_FILE"
        "$ROOT_DIR/k8s-deployment.yaml"
        "$ROOT_DIR/deployment.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $(basename "$file")"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "The following resources have been removed:"
    echo "  ✓ Kubernetes deployments and services"
    echo "  ✓ GKE cluster: $CLUSTER_NAME"
    echo "  ✓ Binary Authorization policies and attestors"
    echo "  ✓ KMS keys (scheduled for destruction)"
    echo "  ✓ Cloud Build trigger: $TRIGGER_NAME"
    echo "  ✓ Cloud Source Repository: $REPO_NAME"
    echo "  ✓ Service account: $SERVICE_ACCOUNT"
    echo "  ✓ Security Command Center sources"
    echo "  ✓ Container images"
    echo "  ✓ Local state files"
    echo
    echo "=== IMPORTANT NOTES ==="
    echo "• KMS keys are scheduled for destruction (30-day recovery period)"
    echo "• Some logs may remain in Cloud Logging"
    echo "• Verify cleanup in Google Cloud Console"
    echo
    echo "Project: $PROJECT_ID"
    echo "Cleanup log: $LOG_FILE"
    echo
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    local exit_code=$?
    log_error "An error occurred during cleanup (exit code: $exit_code)"
    log_warning "Some resources may not have been fully cleaned up"
    log_info "Check the cleanup log for details: $LOG_FILE"
    log_info "You may need to manually remove remaining resources"
    exit $exit_code
}

trap handle_cleanup_error ERR

# Main cleanup function
main() {
    local force_flag="${1:-}"
    
    log_info "Starting Code Quality Enforcement Pipeline cleanup..."
    echo "Cleanup log: $LOG_FILE"
    
    # Execute cleanup steps
    load_deployment_state
    confirm_destruction "$force_flag"
    check_prerequisites
    
    # Remove resources in reverse order of creation
    remove_kubernetes_resources
    delete_gke_cluster
    remove_binary_authorization
    cleanup_cloud_build
    remove_service_account
    remove_security_command_center
    cleanup_container_images
    remove_local_files
    
    display_cleanup_summary
    
    log_success "Code Quality Enforcement Pipeline cleanup completed!"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [--force]"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompts and force cleanup"
    echo "  --help     Show this help message"
    echo
    echo "This script removes all resources created by the deploy.sh script."
    echo "It will prompt for confirmation before proceeding unless --force is used."
}

# Check if help is requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
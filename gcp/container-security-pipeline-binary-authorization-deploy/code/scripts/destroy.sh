#!/bin/bash

# Container Security Pipeline with Binary Authorization and Cloud Deploy - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
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
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be deleted"
fi

# Force cleanup mode (skip confirmations)
FORCE=false
if [[ "${1:-}" == "--force" ]] || [[ "${2:-}" == "--force" ]]; then
    FORCE=true
    warning "Force mode enabled - skipping confirmation prompts"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warning "Command failed but continuing: $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
    fi
    
    success "Prerequisites check passed"
}

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ -f "deployment-state.json" ]]; then
        export PROJECT_ID=$(cat deployment-state.json | grep -o '"project_id": "[^"]*' | cut -d'"' -f4)
        export REGION=$(cat deployment-state.json | grep -o '"region": "[^"]*' | cut -d'"' -f4)
        export ZONE=$(cat deployment-state.json | grep -o '"zone": "[^"]*' | cut -d'"' -f4)
        export RANDOM_SUFFIX=$(cat deployment-state.json | grep -o '"random_suffix": "[^"]*' | cut -d'"' -f4)
        export REPO_URL=$(cat deployment-state.json | grep -o '"repo_url": "[^"]*' | cut -d'"' -f4)
        export ATTESTOR_NAME=$(cat deployment-state.json | grep -o '"attestor_name": "[^"]*' | cut -d'"' -f4)
        export NOTE_ID=$(cat deployment-state.json | grep -o '"note_id": "[^"]*' | cut -d'"' -f4)
        export STAGING_CLUSTER=$(cat deployment-state.json | grep -o '"staging_cluster": "[^"]*' | cut -d'"' -f4)
        export PROD_CLUSTER=$(cat deployment-state.json | grep -o '"prod_cluster": "[^"]*' | cut -d'"' -f4)
        
        log "Loaded deployment state:"
        log "  PROJECT_ID: $PROJECT_ID"
        log "  REGION: $REGION"
        log "  ZONE: $ZONE"
        log "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
        log "  ATTESTOR_NAME: $ATTESTOR_NAME"
        log "  NOTE_ID: $NOTE_ID"
        log "  STAGING_CLUSTER: $STAGING_CLUSTER"
        log "  PROD_CLUSTER: $PROD_CLUSTER"
        
        success "Deployment state loaded successfully"
    else
        warning "deployment-state.json not found. You'll need to provide environment variables manually."
        
        # Fallback to environment variables or user input
        if [[ -z "${PROJECT_ID:-}" ]]; then
            read -p "Enter PROJECT_ID: " PROJECT_ID
        fi
        if [[ -z "${REGION:-}" ]]; then
            export REGION="us-central1"
        fi
        if [[ -z "${ZONE:-}" ]]; then
            export ZONE="us-central1-a"
        fi
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            read -p "Enter RANDOM_SUFFIX (from deployment): " RANDOM_SUFFIX
        fi
        
        export REPO_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/secure-apps-repo"
        export ATTESTOR_NAME="build-attestor-${RANDOM_SUFFIX}"
        export NOTE_ID="build-note-${RANDOM_SUFFIX}"
        export STAGING_CLUSTER="staging-cluster-${RANDOM_SUFFIX}"
        export PROD_CLUSTER="prod-cluster-${RANDOM_SUFFIX}"
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log "Force mode enabled, skipping confirmation"
        return
    fi
    
    warning "This will permanently delete the following resources:"
    warning "  - Project: $PROJECT_ID"
    warning "  - GKE Clusters: $STAGING_CLUSTER, $PROD_CLUSTER"
    warning "  - Artifact Registry repository: secure-apps-repo"
    warning "  - Binary Authorization attestor: $ATTESTOR_NAME"
    warning "  - Cloud Deploy pipeline: secure-app-pipeline"
    warning "  - All associated data and configurations"
    
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Confirmation received, proceeding with cleanup"
}

# Set project context
set_project_context() {
    log "Setting project context..."
    
    execute_cmd "gcloud config set project $PROJECT_ID" "Setting project context"
    execute_cmd "gcloud config set compute/region $REGION" "Setting region"
    execute_cmd "gcloud config set compute/zone $ZONE" "Setting zone"
    
    success "Project context set"
}

# Remove Cloud Deploy resources
remove_cloud_deploy() {
    log "Removing Cloud Deploy resources..."
    
    # Delete Cloud Deploy pipeline
    execute_cmd "gcloud deploy delivery-pipelines delete secure-app-pipeline \
        --region=$REGION \
        --quiet" "Deleting Cloud Deploy pipeline" "true"
    
    # Delete Cloud Deploy targets
    execute_cmd "gcloud deploy targets delete staging \
        --region=$REGION \
        --quiet" "Deleting staging target" "true"
    
    execute_cmd "gcloud deploy targets delete production \
        --region=$REGION \
        --quiet" "Deleting production target" "true"
    
    success "Cloud Deploy resources removed"
}

# Remove GKE clusters
remove_gke_clusters() {
    log "Removing GKE clusters..."
    
    # Delete staging cluster
    execute_cmd "gcloud container clusters delete $STAGING_CLUSTER \
        --zone=$ZONE \
        --quiet" "Deleting staging cluster" "true"
    
    # Delete production cluster
    execute_cmd "gcloud container clusters delete $PROD_CLUSTER \
        --zone=$ZONE \
        --quiet" "Deleting production cluster" "true"
    
    success "GKE clusters removed"
}

# Remove Binary Authorization resources
remove_binary_authorization() {
    log "Removing Binary Authorization resources..."
    
    # Delete Binary Authorization attestor
    execute_cmd "gcloud container binauthz attestors delete $ATTESTOR_NAME \
        --quiet" "Deleting Binary Authorization attestor" "true"
    
    # Reset Binary Authorization policy to default
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > default-policy.yaml <<EOF
defaultAdmissionRule:
  enforcementMode: ALWAYS_ALLOW
EOF
        execute_cmd "gcloud container binauthz policy import default-policy.yaml" "Resetting Binary Authorization policy" "true"
        rm -f default-policy.yaml
    fi
    
    # Delete attestation note
    execute_cmd "curl -X DELETE \
        -H 'Authorization: Bearer \$(gcloud auth print-access-token)' \
        'https://containeranalysis.googleapis.com/v1beta1/projects/${PROJECT_ID}/notes/${NOTE_ID}'" "Deleting attestation note" "true"
    
    success "Binary Authorization resources removed"
}

# Remove Artifact Registry resources
remove_artifact_registry() {
    log "Removing Artifact Registry resources..."
    
    # Delete Artifact Registry repository
    execute_cmd "gcloud artifacts repositories delete secure-apps-repo \
        --location=$REGION \
        --quiet" "Deleting Artifact Registry repository" "true"
    
    success "Artifact Registry resources removed"
}

# Remove Cloud Build resources
remove_cloud_build() {
    log "Removing Cloud Build resources..."
    
    # Note: Cloud Build doesn't have persistent resources to clean up
    # Built images are stored in Artifact Registry which is cleaned up separately
    
    success "Cloud Build resources removed"
}

# Clean up GPG keys
cleanup_gpg_keys() {
    log "Cleaning up GPG keys..."
    
    # Remove GPG keys
    execute_cmd "gpg --batch --yes --delete-secret-keys 'Build Attestor <build@${PROJECT_ID}.example.com>'" "Deleting GPG secret key" "true"
    execute_cmd "gpg --batch --yes --delete-keys 'Build Attestor <build@${PROJECT_ID}.example.com>'" "Deleting GPG public key" "true"
    
    success "GPG keys cleaned up"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove local files and directories
    local files_to_remove=(
        "sample-app"
        "k8s-manifests"
        "binauthz-policy.yaml"
        "clouddeploy.yaml"
        "note.json"
        "attestor-key.pub"
        "deployment-state.json"
        "default-policy.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            execute_cmd "rm -rf $file" "Removing $file" "true"
        fi
    done
    
    success "Local files cleaned up"
}

# Remove IAM bindings (if any were created)
remove_iam_bindings() {
    log "Removing IAM bindings..."
    
    # Note: In this recipe, we don't create specific IAM bindings
    # This is a placeholder for future enhancements
    
    success "IAM bindings removed"
}

# Disable APIs (optional)
disable_apis() {
    log "Disabling APIs..."
    
    # Only disable APIs if specifically requested
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        local apis=(
            "container.googleapis.com"
            "cloudbuild.googleapis.com"
            "artifactregistry.googleapis.com"
            "binaryauthorization.googleapis.com"
            "clouddeploy.googleapis.com"
            "containeranalysis.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            execute_cmd "gcloud services disable $api --force" "Disabling $api" "true"
        done
    else
        log "Skipping API disable (set DISABLE_APIS=true to disable)"
    fi
    
    success "APIs handling completed"
}

# Delete project (optional)
delete_project() {
    log "Checking if project should be deleted..."
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        warning "Deleting entire project: $PROJECT_ID"
        execute_cmd "gcloud projects delete $PROJECT_ID --quiet" "Deleting project"
        success "Project deleted"
    else
        log "Skipping project deletion (set DELETE_PROJECT=true to delete entire project)"
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry-run mode - skipping verification"
        return
    fi
    
    # Check if major resources are gone
    local cleanup_status=0
    
    # Check GKE clusters
    if gcloud container clusters list --zone=$ZONE --filter="name~$STAGING_CLUSTER OR name~$PROD_CLUSTER" --format="value(name)" | grep -q .; then
        warning "Some GKE clusters may still exist"
        cleanup_status=1
    fi
    
    # Check Artifact Registry
    if gcloud artifacts repositories list --location=$REGION --filter="name~secure-apps-repo" --format="value(name)" | grep -q .; then
        warning "Artifact Registry repository may still exist"
        cleanup_status=1
    fi
    
    # Check Binary Authorization attestor
    if gcloud container binauthz attestors list --filter="name~$ATTESTOR_NAME" --format="value(name)" | grep -q .; then
        warning "Binary Authorization attestor may still exist"
        cleanup_status=1
    fi
    
    # Check Cloud Deploy pipeline
    if gcloud deploy delivery-pipelines list --region=$REGION --filter="name~secure-app-pipeline" --format="value(name)" | grep -q .; then
        warning "Cloud Deploy pipeline may still exist"
        cleanup_status=1
    fi
    
    if [[ $cleanup_status -eq 0 ]]; then
        success "Cleanup verification passed - all major resources removed"
    else
        warning "Some resources may still exist. You may need to manually remove them."
    fi
}

# Main cleanup function
main() {
    log "Starting Container Security Pipeline cleanup..."
    
    check_prerequisites
    load_deployment_state
    confirm_destruction
    set_project_context
    
    # Remove resources in reverse order of creation
    remove_cloud_deploy
    remove_gke_clusters
    remove_binary_authorization
    remove_artifact_registry
    remove_cloud_build
    cleanup_gpg_keys
    remove_iam_bindings
    disable_apis
    cleanup_local_files
    delete_project
    
    verify_cleanup
    
    success "Container Security Pipeline cleanup completed successfully!"
    
    log "Cleanup summary:"
    log "  - Cloud Deploy pipeline removed"
    log "  - GKE clusters deleted"
    log "  - Binary Authorization resources removed"
    log "  - Artifact Registry repository deleted"
    log "  - GPG keys cleaned up"
    log "  - Local files removed"
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log "  - Project deleted"
    else
        log "  - Project retained (set DELETE_PROJECT=true to delete)"
    fi
    
    log "Cleanup completed successfully!"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmation prompts"
    echo ""
    echo "Environment variables:"
    echo "  DELETE_PROJECT=true   Delete the entire project"
    echo "  DISABLE_APIS=true     Disable the enabled APIs"
    echo ""
    echo "Examples:"
    echo "  $0                    Interactive cleanup"
    echo "  $0 --dry-run         Show what would be deleted"
    echo "  $0 --force           Skip confirmations"
    echo "  DELETE_PROJECT=true $0 --force  Delete everything including project"
}

# Handle help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"
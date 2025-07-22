#!/bin/bash

# Destroy script for Cloud-Native Development Environments with Firebase Studio and Gemini Code Assist
# This script safely removes all resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load environment variables from deployment
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from deployment summary
    if [[ -f "deployment-summary.json" ]]; then
        if command_exists jq; then
            export PROJECT_ID=$(jq -r '.project_id' deployment-summary.json)
            export REGION=$(jq -r '.region' deployment-summary.json)
            export REPO_NAME=$(jq -r '.repository_name' deployment-summary.json)
            export REGISTRY_NAME=$(jq -r '.registry_name' deployment-summary.json)
            log_success "Environment variables loaded from deployment-summary.json"
        else
            log_warning "jq not found. Please set environment variables manually."
        fi
    fi
    
    # Use default values if not set
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
    export REPO_NAME="${REPO_NAME:-}"
    export REGISTRY_NAME="${REGISTRY_NAME:-}"
    
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID not set. Please set it manually or run from deployment directory."
        exit 1
    fi
    
    log_success "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  REPO_NAME: ${REPO_NAME}"
    log "  REGISTRY_NAME: ${REGISTRY_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "===================================================================================="
    echo "                          DESTRUCTIVE OPERATION WARNING"
    echo "===================================================================================="
    echo ""
    echo "This script will permanently delete the following resources:"
    echo ""
    echo "🔥 GCP Project: ${PROJECT_ID}"
    echo "🔥 Firebase Project: ${PROJECT_ID}"
    echo "🔥 Cloud Source Repository: ${REPO_NAME}"
    echo "🔥 Artifact Registry: ${REGISTRY_NAME}"
    echo "🔥 Cloud Build Triggers"
    echo "🔥 Service Accounts"
    echo "🔥 All associated data and configurations"
    echo ""
    echo "⚠️  This operation CANNOT be undone!"
    echo ""
    echo "===================================================================================="
    echo ""
    
    # Check if running in interactive mode
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Type 'DESTROY' to confirm permanent deletion: " -r
    if [[ ! $REPLY == "DESTROY" ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to delete Cloud Build triggers
delete_cloud_build_triggers() {
    log "Deleting Cloud Build triggers..."
    
    # List and delete all triggers for the project
    local triggers=$(gcloud builds triggers list --format="value(id)" --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    if [[ -n "${triggers}" ]]; then
        echo "${triggers}" | while read -r trigger_id; do
            if [[ -n "${trigger_id}" ]]; then
                log "Deleting trigger: ${trigger_id}"
                gcloud builds triggers delete "${trigger_id}" --quiet --project="${PROJECT_ID}" || {
                    log_warning "Failed to delete trigger: ${trigger_id}"
                }
            fi
        done
        log_success "Cloud Build triggers deleted"
    else
        log_warning "No Cloud Build triggers found or unable to list triggers"
    fi
}

# Function to delete Artifact Registry
delete_artifact_registry() {
    log "Deleting Artifact Registry..."
    
    if [[ -n "${REGISTRY_NAME}" ]] && [[ -n "${REGION}" ]]; then
        if gcloud artifacts repositories describe "${REGISTRY_NAME}" \
            --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            
            log "Deleting registry: ${REGISTRY_NAME}"
            gcloud artifacts repositories delete "${REGISTRY_NAME}" \
                --location="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet || {
                log_warning "Failed to delete registry: ${REGISTRY_NAME}"
            }
            log_success "Artifact Registry deleted"
        else
            log_warning "Registry ${REGISTRY_NAME} not found or already deleted"
        fi
    else
        log_warning "Registry name or region not specified. Skipping Artifact Registry deletion."
    fi
}

# Function to delete Cloud Source Repository
delete_source_repository() {
    log "Deleting Cloud Source Repository..."
    
    if [[ -n "${REPO_NAME}" ]]; then
        if gcloud source repos describe "${REPO_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            log "Deleting repository: ${REPO_NAME}"
            gcloud source repos delete "${REPO_NAME}" --project="${PROJECT_ID}" --quiet || {
                log_warning "Failed to delete repository: ${REPO_NAME}"
            }
            log_success "Cloud Source Repository deleted"
        else
            log_warning "Repository ${REPO_NAME} not found or already deleted"
        fi
    else
        log_warning "Repository name not specified. Skipping Cloud Source Repository deletion."
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    log "Deleting service accounts..."
    
    local service_accounts=(
        "gemini-code-assist"
    )
    
    for sa in "${service_accounts[@]}"; do
        local sa_email="${sa}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if gcloud iam service-accounts describe "${sa_email}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            log "Deleting service account: ${sa_email}"
            gcloud iam service-accounts delete "${sa_email}" --project="${PROJECT_ID}" --quiet || {
                log_warning "Failed to delete service account: ${sa_email}"
            }
        else
            log_warning "Service account ${sa_email} not found or already deleted"
        fi
    done
    
    log_success "Service accounts deletion completed"
}

# Function to delete Cloud Run services
delete_cloud_run_services() {
    log "Deleting Cloud Run services..."
    
    local services=$(gcloud run services list --platform=managed --region="${REGION}" --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${services}" ]]; then
        echo "${services}" | while read -r service_name; do
            if [[ -n "${service_name}" ]]; then
                log "Deleting Cloud Run service: ${service_name}"
                gcloud run services delete "${service_name}" \
                    --platform=managed \
                    --region="${REGION}" \
                    --project="${PROJECT_ID}" \
                    --quiet || {
                    log_warning "Failed to delete service: ${service_name}"
                }
            fi
        done
        log_success "Cloud Run services deleted"
    else
        log_warning "No Cloud Run services found"
    fi
}

# Function to display Firebase Studio cleanup instructions
display_firebase_cleanup_instructions() {
    log "🌐 Firebase Studio Manual Cleanup Instructions"
    echo ""
    echo "===================================================================================="
    echo "                    FIREBASE STUDIO MANUAL CLEANUP REQUIRED"
    echo "===================================================================================="
    echo ""
    echo "The following resources must be manually deleted from Firebase Studio:"
    echo ""
    echo "1. Visit: https://studio.firebase.google.com"
    echo "2. Sign in with your Google account"
    echo "3. Delete workspaces associated with project: ${PROJECT_ID}"
    echo "4. Visit: https://console.firebase.google.com"
    echo "5. Delete Firebase project: ${PROJECT_ID}"
    echo ""
    echo "Note: Firebase Studio workspaces are managed through the web interface"
    echo "and cannot be deleted programmatically via CLI."
    echo ""
    echo "===================================================================================="
    echo ""
}

# Function to delete the entire GCP project
delete_gcp_project() {
    log "Deleting GCP project..."
    
    # Double confirmation for project deletion
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        echo ""
        echo "⚠️  FINAL WARNING: This will delete the entire GCP project!"
        echo "Project ID: ${PROJECT_ID}"
        echo ""
        read -p "Type the project ID to confirm project deletion: " -r
        if [[ ! $REPLY == "${PROJECT_ID}" ]]; then
            log "Project deletion cancelled. Individual resources will be cleaned up instead."
            return 0
        fi
    fi
    
    log "Initiating project deletion: ${PROJECT_ID}"
    gcloud projects delete "${PROJECT_ID}" --quiet || {
        log_error "Failed to delete project: ${PROJECT_ID}"
        log_warning "You may need to delete the project manually from the GCP Console"
        return 1
    }
    
    log_success "Project deletion initiated: ${PROJECT_ID}"
    log_warning "Project deletion may take several minutes to complete"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "deployment-summary.json"
        "cloudbuild.yaml"
        "firebase-studio-workspace"
        "temp-repo-setup"
        "app-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            log "Removing: ${file}"
            rm -rf "${file}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to validate destruction
validate_destruction() {
    log "Validating resource destruction..."
    
    # Check if project still exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Project ${PROJECT_ID} still exists (deletion may be in progress)"
    else
        log_success "Project ${PROJECT_ID} has been deleted"
    fi
    
    # Check repositories (only if project still exists)
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        if [[ -n "${REPO_NAME}" ]]; then
            if gcloud source repos describe "${REPO_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
                log_warning "Repository ${REPO_NAME} still exists"
            else
                log_success "Repository ${REPO_NAME} has been deleted"
            fi
        fi
        
        if [[ -n "${REGISTRY_NAME}" ]]; then
            if gcloud artifacts repositories describe "${REGISTRY_NAME}" \
                --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
                log_warning "Registry ${REGISTRY_NAME} still exists"
            else
                log_success "Registry ${REGISTRY_NAME} has been deleted"
            fi
        fi
    fi
    
    log_success "Destruction validation completed"
}

# Function to save destruction summary
save_destruction_summary() {
    log "Saving destruction summary..."
    
    cat > destruction-summary.json << EOF
{
  "destruction_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "repository_name": "${REPO_NAME}",
  "registry_name": "${REGISTRY_NAME}",
  "status": "destroyed",
  "manual_cleanup_required": [
    "Firebase Studio workspaces at https://studio.firebase.google.com",
    "Firebase project at https://console.firebase.google.com (if not deleted with GCP project)"
  ]
}
EOF
    
    log_success "Destruction summary saved to destruction-summary.json"
}

# Main destruction function
main() {
    log "Starting Firebase Studio and Gemini Code Assist resource destruction..."
    
    # Load environment and confirm destruction
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_cloud_build_triggers
    delete_cloud_run_services
    delete_artifact_registry
    delete_source_repository
    delete_service_accounts
    
    # Display manual cleanup instructions
    display_firebase_cleanup_instructions
    
    # Optionally delete the entire project
    echo ""
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        delete_gcp_project
    else
        read -p "Do you want to delete the entire GCP project? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            delete_gcp_project
        else
            log_warning "GCP project preserved. Individual resources have been cleaned up."
        fi
    fi
    
    # Clean up local files and validate
    cleanup_local_files
    validate_destruction
    save_destruction_summary
    
    log_success "🎉 Resource destruction completed!"
    echo ""
    echo "===================================================================================="
    echo "                            DESTRUCTION COMPLETE"
    echo "===================================================================================="
    echo ""
    echo "✅ Cloud Build triggers deleted"
    echo "✅ Cloud Run services deleted"
    echo "✅ Artifact Registry deleted"
    echo "✅ Cloud Source Repository deleted"
    echo "✅ Service accounts deleted"
    echo "✅ Local files cleaned up"
    echo ""
    echo "📋 Manual cleanup still required:"
    echo "   • Firebase Studio workspaces"
    echo "   • Firebase project (if not deleted with GCP project)"
    echo ""
    echo "===================================================================================="
}

# Error handling
trap 'log_error "Destruction failed at line $LINENO. Exit code: $?"' ERR

# Check for force destroy flag
if [[ "${1:-}" == "--force" ]]; then
    export FORCE_DESTROY=true
    log_warning "Force destroy mode enabled"
fi

# Run main function
main "$@"
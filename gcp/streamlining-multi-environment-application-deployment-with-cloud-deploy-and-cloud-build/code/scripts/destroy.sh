#!/bin/bash

# =============================================================================
# Multi-Environment Application Deployment with Cloud Deploy and Cloud Build
# Destroy Script
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" "$ERROR_LOG"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
}

log_step() {
    local step="$1"
    shift
    local message="$*"
    echo -e "\n${BLUE}=== Step $step: $message ===${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    log "ERROR" "Cleanup failed. Check logs at: $LOG_FILE and $ERROR_LOG"
    log "ERROR" "Some resources may still exist and incur charges"
    log "ERROR" "Please check the GCP console and clean up manually if needed"
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_step "0" "Checking Prerequisites"
    
    # Check if required tools are installed
    local required_tools=("gcloud" "kubectl" "gsutil")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        log "ERROR" "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log "ERROR" "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "INFO" "All prerequisites are met"
}

# =============================================================================
# Environment Setup
# =============================================================================

load_environment() {
    log_step "1" "Loading Environment Variables"
    
    # Load environment variables from .env file if it exists
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Loading environment variables from $ENV_FILE"
        # shellcheck source=/dev/null
        source "$ENV_FILE"
    else
        log "WARN" "Environment file $ENV_FILE not found"
        log "INFO" "Using default or user-provided environment variables"
        
        # Set default values if not provided
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
        
        # If no project ID is set, try to get it from gcloud
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            if [[ -z "$PROJECT_ID" ]]; then
                log "ERROR" "PROJECT_ID not found. Please set it manually or run deploy.sh first"
                exit 1
            fi
        fi
        
        # If no random suffix, we'll need to prompt for resource names
        if [[ -z "$RANDOM_SUFFIX" ]]; then
            log "WARN" "RANDOM_SUFFIX not found. Using default resource names"
            RANDOM_SUFFIX="default"
        fi
        
        # Set resource names
        export CLUSTER_DEV="${CLUSTER_DEV:-dev-cluster-${RANDOM_SUFFIX}}"
        export CLUSTER_STAGE="${CLUSTER_STAGE:-staging-cluster-${RANDOM_SUFFIX}}"
        export CLUSTER_PROD="${CLUSTER_PROD:-prod-cluster-${RANDOM_SUFFIX}}"
        export REPO_NAME="${REPO_NAME:-app-repo-${RANDOM_SUFFIX}}"
        export PIPELINE_NAME="${PIPELINE_NAME:-app-pipeline-${RANDOM_SUFFIX}}"
        export BUCKET_NAME="${BUCKET_NAME:-deploy-artifacts-${PROJECT_ID}-${RANDOM_SUFFIX}}"
    fi
    
    log "INFO" "Environment variables loaded:"
    log "INFO" "  PROJECT_ID: $PROJECT_ID"
    log "INFO" "  REGION: $REGION"
    log "INFO" "  ZONE: $ZONE"
    log "INFO" "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
}

# =============================================================================
# Confirmation Prompt
# =============================================================================

confirm_destruction() {
    log_step "2" "Confirming Resource Destruction"
    
    echo -e "\n${YELLOW}WARNING: This script will destroy the following resources:${NC}"
    echo -e "  - Cloud Deploy pipeline: $PIPELINE_NAME"
    echo -e "  - GKE clusters: $CLUSTER_DEV, $CLUSTER_STAGE, $CLUSTER_PROD"
    echo -e "  - Artifact Registry repository: $REPO_NAME"
    echo -e "  - Cloud Storage bucket: $BUCKET_NAME"
    echo -e "  - All associated data and configurations"
    echo -e "\n${RED}This action cannot be undone!${NC}"
    
    # Skip confirmation if running in non-interactive mode
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log "INFO" "Skipping confirmation (FORCE_DESTROY=true)"
        return 0
    fi
    
    echo -e "\n${YELLOW}Are you sure you want to continue? (yes/no):${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Destruction cancelled by user"
        exit 0
    fi
    
    log "INFO" "Destruction confirmed by user"
}

# =============================================================================
# GCP Project Configuration
# =============================================================================

configure_gcp_project() {
    log_step "3" "Configuring GCP Project"
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log "INFO" "Project configured: $PROJECT_ID"
}

# =============================================================================
# Cloud Deploy Resources Cleanup
# =============================================================================

delete_cloud_deploy_resources() {
    log_step "4" "Deleting Cloud Deploy Resources"
    
    # Check if pipeline exists
    if gcloud deploy delivery-pipelines describe "$PIPELINE_NAME" --region="$REGION" &>/dev/null; then
        log "INFO" "Deleting Cloud Deploy pipeline: $PIPELINE_NAME"
        
        # Delete any pending releases first
        log "INFO" "Checking for pending releases..."
        local releases
        releases=$(gcloud deploy releases list \
            --delivery-pipeline="$PIPELINE_NAME" \
            --region="$REGION" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$releases" ]]; then
            log "INFO" "Found releases to clean up"
            while IFS= read -r release; do
                if [[ -n "$release" ]]; then
                    log "INFO" "Deleting release: $release"
                    gcloud deploy releases delete "$release" \
                        --delivery-pipeline="$PIPELINE_NAME" \
                        --region="$REGION" \
                        --quiet || log "WARN" "Failed to delete release: $release"
                fi
            done <<< "$releases"
        fi
        
        # Delete the pipeline
        gcloud deploy delivery-pipelines delete "$PIPELINE_NAME" \
            --region="$REGION" \
            --quiet
        
        log "INFO" "Cloud Deploy pipeline deleted successfully"
    else
        log "WARN" "Cloud Deploy pipeline $PIPELINE_NAME not found"
    fi
}

# =============================================================================
# GKE Clusters Cleanup
# =============================================================================

delete_gke_clusters() {
    log_step "5" "Deleting GKE Clusters"
    
    # Function to delete a GKE cluster
    delete_cluster() {
        local cluster_name="$1"
        
        if gcloud container clusters describe "$cluster_name" --zone="$ZONE" &>/dev/null; then
            log "INFO" "Deleting GKE cluster: $cluster_name"
            
            # Delete any lingering workloads first
            log "INFO" "Cleaning up workloads in cluster: $cluster_name"
            gcloud container clusters get-credentials "$cluster_name" --zone="$ZONE" --quiet || true
            
            # Delete deployments and services
            kubectl delete deployments --all --timeout=60s || log "WARN" "Failed to delete deployments in $cluster_name"
            kubectl delete services --all --timeout=60s || log "WARN" "Failed to delete services in $cluster_name"
            
            # Delete the cluster
            gcloud container clusters delete "$cluster_name" \
                --zone="$ZONE" \
                --quiet
            
            log "INFO" "GKE cluster $cluster_name deleted successfully"
        else
            log "WARN" "GKE cluster $cluster_name not found"
        fi
    }
    
    # Delete all clusters
    delete_cluster "$CLUSTER_DEV"
    delete_cluster "$CLUSTER_STAGE"
    delete_cluster "$CLUSTER_PROD"
    
    log "INFO" "All GKE clusters deleted"
}

# =============================================================================
# Artifact Registry Cleanup
# =============================================================================

delete_artifact_registry() {
    log_step "6" "Deleting Artifact Registry Repository"
    
    # Check if repository exists
    if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" &>/dev/null; then
        log "INFO" "Deleting Artifact Registry repository: $REPO_NAME"
        
        # Delete all images in the repository first
        log "INFO" "Checking for images in repository..."
        local images
        images=$(gcloud artifacts docker images list \
            --repository="$REPO_NAME" \
            --location="$REGION" \
            --format="value(package)" 2>/dev/null || echo "")
        
        if [[ -n "$images" ]]; then
            log "INFO" "Found images to delete"
            while IFS= read -r image; do
                if [[ -n "$image" ]]; then
                    log "INFO" "Deleting image: $image"
                    gcloud artifacts docker images delete "$image" \
                        --quiet || log "WARN" "Failed to delete image: $image"
                fi
            done <<< "$images"
        fi
        
        # Delete the repository
        gcloud artifacts repositories delete "$REPO_NAME" \
            --location="$REGION" \
            --quiet
        
        log "INFO" "Artifact Registry repository deleted successfully"
    else
        log "WARN" "Artifact Registry repository $REPO_NAME not found"
    fi
}

# =============================================================================
# Cloud Storage Cleanup
# =============================================================================

delete_cloud_storage() {
    log_step "7" "Deleting Cloud Storage Bucket"
    
    # Check if bucket exists
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        log "INFO" "Deleting Cloud Storage bucket: $BUCKET_NAME"
        
        # Remove all objects and versions
        log "INFO" "Removing all objects from bucket..."
        gsutil -m rm -r "gs://$BUCKET_NAME/**" || log "WARN" "Failed to remove some objects"
        
        # Remove the bucket
        gsutil rb "gs://$BUCKET_NAME"
        
        log "INFO" "Cloud Storage bucket deleted successfully"
    else
        log "WARN" "Cloud Storage bucket $BUCKET_NAME not found"
    fi
}

# =============================================================================
# Application Source Cleanup
# =============================================================================

cleanup_application_source() {
    log_step "8" "Cleaning Up Application Source"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    if [[ -d "$app_dir" ]]; then
        log "INFO" "Removing application source directory: $app_dir"
        rm -rf "$app_dir"
        log "INFO" "Application source directory removed"
    else
        log "WARN" "Application source directory not found: $app_dir"
    fi
}

# =============================================================================
# Local Environment Cleanup
# =============================================================================

cleanup_local_environment() {
    log_step "9" "Cleaning Up Local Environment"
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Removing environment file: $ENV_FILE"
        rm -f "$ENV_FILE"
    fi
    
    # Remove kubectl contexts
    log "INFO" "Cleaning up kubectl contexts..."
    kubectl config delete-context "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_DEV}" || log "WARN" "Failed to remove dev context"
    kubectl config delete-context "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_STAGE}" || log "WARN" "Failed to remove staging context"
    kubectl config delete-context "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_PROD}" || log "WARN" "Failed to remove prod context"
    
    # Remove cluster credentials
    log "INFO" "Cleaning up cluster credentials..."
    kubectl config delete-cluster "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_DEV}" || log "WARN" "Failed to remove dev cluster"
    kubectl config delete-cluster "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_STAGE}" || log "WARN" "Failed to remove staging cluster"
    kubectl config delete-cluster "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_PROD}" || log "WARN" "Failed to remove prod cluster"
    
    # Remove service account entries
    kubectl config delete-user "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_DEV}" || log "WARN" "Failed to remove dev user"
    kubectl config delete-user "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_STAGE}" || log "WARN" "Failed to remove staging user"
    kubectl config delete-user "gke_${PROJECT_ID}_${ZONE}_${CLUSTER_PROD}" || log "WARN" "Failed to remove prod user"
    
    log "INFO" "Local environment cleanup completed"
}

# =============================================================================
# Cloud Build Cleanup
# =============================================================================

cleanup_cloud_build() {
    log_step "10" "Cleaning Up Cloud Build Resources"
    
    # List and delete any build triggers that might have been created
    log "INFO" "Checking for Cloud Build triggers..."
    local triggers
    triggers=$(gcloud builds triggers list \
        --filter="name:*${PIPELINE_NAME}*" \
        --format="value(id)" 2>/dev/null || echo "")
    
    if [[ -n "$triggers" ]]; then
        log "INFO" "Found Cloud Build triggers to delete"
        while IFS= read -r trigger; do
            if [[ -n "$trigger" ]]; then
                log "INFO" "Deleting trigger: $trigger"
                gcloud builds triggers delete "$trigger" --quiet || log "WARN" "Failed to delete trigger: $trigger"
            fi
        done <<< "$triggers"
    fi
    
    # Clean up any build history (builds will be automatically cleaned up by GCP)
    log "INFO" "Build history will be automatically cleaned up by GCP"
}

# =============================================================================
# Final Validation
# =============================================================================

validate_cleanup() {
    log_step "11" "Validating Cleanup"
    
    local cleanup_issues=()
    
    # Check if Cloud Deploy pipeline still exists
    if gcloud deploy delivery-pipelines describe "$PIPELINE_NAME" --region="$REGION" &>/dev/null; then
        cleanup_issues+=("Cloud Deploy pipeline still exists")
    fi
    
    # Check if any GKE clusters still exist
    local remaining_clusters
    remaining_clusters=$(gcloud container clusters list \
        --filter="name:($CLUSTER_DEV OR $CLUSTER_STAGE OR $CLUSTER_PROD)" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_clusters" ]]; then
        cleanup_issues+=("GKE clusters still exist: $remaining_clusters")
    fi
    
    # Check if Artifact Registry repository still exists
    if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" &>/dev/null; then
        cleanup_issues+=("Artifact Registry repository still exists")
    fi
    
    # Check if Cloud Storage bucket still exists
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        cleanup_issues+=("Cloud Storage bucket still exists")
    fi
    
    # Report cleanup status
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log "INFO" "All resources have been successfully cleaned up"
    else
        log "WARN" "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            log "WARN" "  - $issue"
        done
        log "WARN" "Please check the GCP console and clean up manually if needed"
    fi
}

# =============================================================================
# Usage Information
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -f, --force         Skip confirmation prompts
    -h, --help          Show this help message
    --debug             Enable debug logging

Environment Variables:
    PROJECT_ID          GCP project ID
    REGION              GCP region (default: us-central1)
    ZONE                GCP zone (default: us-central1-a)
    FORCE_DESTROY       Skip confirmation (same as --force)

Examples:
    $0                  # Interactive cleanup
    $0 --force          # Skip confirmation
    $0 --debug          # Enable debug logging

EOF
}

# =============================================================================
# Argument Processing
# =============================================================================

process_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                export FORCE_DESTROY="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log "INFO" "Starting Multi-Environment Application Cleanup"
    log "INFO" "Script started at: $(date)"
    
    # Initialize log files
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    # Process command line arguments
    process_arguments "$@"
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    configure_gcp_project
    delete_cloud_deploy_resources
    delete_gke_clusters
    delete_artifact_registry
    delete_cloud_storage
    cleanup_application_source
    cleanup_local_environment
    cleanup_cloud_build
    validate_cleanup
    
    log "INFO" "Cleanup completed successfully!"
    log "INFO" "Cleanup logs saved to: $LOG_FILE"
    
    # Display completion message
    echo -e "\n${GREEN}=== Cleanup Complete ===${NC}"
    echo -e "${GREEN}All resources have been successfully removed!${NC}"
    echo -e "\n${BLUE}What was cleaned up:${NC}"
    echo -e "  ✓ Cloud Deploy pipeline and releases"
    echo -e "  ✓ GKE clusters (dev, staging, production)"
    echo -e "  ✓ Artifact Registry repository and images"
    echo -e "  ✓ Cloud Storage bucket and contents"
    echo -e "  ✓ Application source code"
    echo -e "  ✓ Local environment configuration"
    echo -e "  ✓ kubectl contexts and credentials"
    echo -e "\n${GREEN}No further charges should be incurred for these resources.${NC}"
    echo -e "${BLUE}Please verify in the GCP console that all resources are removed.${NC}"
}

# Execute main function with all arguments
main "$@"
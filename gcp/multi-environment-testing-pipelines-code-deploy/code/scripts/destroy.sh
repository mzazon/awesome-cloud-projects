#!/bin/bash

# Multi-Environment Testing Pipelines with Cloud Code and Cloud Deploy - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to check if user is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "No active Google Cloud authentication found."
        echo "Please run: gcloud auth login"
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check required commands
    check_command "gcloud"
    check_command "kubectl"
    
    # Check authentication
    check_auth
    
    # Verify project is set
    if ! PROJECT_ID=$(gcloud config get-value project 2>/dev/null) || [ -z "$PROJECT_ID" ]; then
        error "No Google Cloud project configured."
        echo "Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# Function to confirm destructive action
confirm_destruction() {
    if [ "$FORCE" = false ]; then
        echo ""
        warning "This will delete ALL resources created by the multi-environment testing pipeline deployment."
        echo "This includes:"
        echo "- All GKE clusters (dev, staging, prod)"
        echo "- Cloud Deploy pipelines and targets"
        echo "- Artifact Registry repositories"
        echo "- Cloud Monitoring dashboards"
        echo "- Local application configuration files"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Function to discover resources by prefix
discover_resources() {
    log "Discovering resources to clean up..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    # If cluster prefix is provided, use it. Otherwise, discover all pipeline resources
    if [ -n "${CLUSTER_PREFIX:-}" ]; then
        log "Using provided cluster prefix: ${CLUSTER_PREFIX}"
    else
        # Try to discover pipeline resources
        PIPELINE_CLUSTERS=$(gcloud container clusters list --format="value(name)" --filter="name~pipeline-" 2>/dev/null || true)
        if [ -n "$PIPELINE_CLUSTERS" ]; then
            # Extract the first prefix found
            FIRST_CLUSTER=$(echo "$PIPELINE_CLUSTERS" | head -n 1)
            CLUSTER_PREFIX=$(echo "$FIRST_CLUSTER" | sed 's/-dev$//' | sed 's/-staging$//' | sed 's/-prod$//')
            log "Discovered cluster prefix: ${CLUSTER_PREFIX}"
        else
            error "No pipeline resources found and no cluster prefix provided."
            echo "Usage: $0 [--cluster-prefix CLUSTER_PREFIX]"
            exit 1
        fi
    fi
    
    success "Resource discovery completed"
}

# Function to delete Cloud Deploy resources
delete_cloud_deploy_resources() {
    log "Deleting Cloud Deploy resources..."
    
    # List and delete releases first
    log "Checking for Cloud Deploy releases..."
    RELEASES=$(gcloud deploy releases list \
        --delivery-pipeline="${CLUSTER_PREFIX}-pipeline" \
        --region="${REGION}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$RELEASES" ]; then
        log "Found releases to delete..."
        while IFS= read -r release; do
            if [ -n "$release" ]; then
                log "Deleting release: $release"
                gcloud deploy releases delete "$release" \
                    --delivery-pipeline="${CLUSTER_PREFIX}-pipeline" \
                    --region="${REGION}" \
                    --quiet 2>/dev/null || warning "Failed to delete release: $release"
            fi
        done <<< "$RELEASES"
    fi
    
    # Delete the delivery pipeline
    log "Deleting Cloud Deploy pipeline..."
    if gcloud deploy delivery-pipelines describe "${CLUSTER_PREFIX}-pipeline" \
        --region="${REGION}" &>/dev/null; then
        if gcloud deploy delivery-pipelines delete "${CLUSTER_PREFIX}-pipeline" \
            --region="${REGION}" \
            --quiet; then
            success "Cloud Deploy pipeline deleted"
        else
            error "Failed to delete Cloud Deploy pipeline"
        fi
    else
        warning "Cloud Deploy pipeline ${CLUSTER_PREFIX}-pipeline not found"
    fi
    
    # Delete individual targets
    log "Deleting Cloud Deploy targets..."
    for target in dev staging prod; do
        if gcloud deploy targets describe "$target" --region="${REGION}" &>/dev/null; then
            if gcloud deploy targets delete "$target" --region="${REGION}" --quiet; then
                success "Target $target deleted"
            else
                warning "Failed to delete target: $target"
            fi
        else
            log "Target $target not found (already deleted or doesn't exist)"
        fi
    done
    
    success "Cloud Deploy resources cleanup completed"
}

# Function to delete GKE clusters
delete_gke_clusters() {
    log "Deleting GKE clusters..."
    
    # Delete clusters in parallel for faster cleanup
    local cluster_pids=()
    
    for env in dev staging prod; do
        cluster_name="${CLUSTER_PREFIX}-${env}"
        if gcloud container clusters describe "$cluster_name" --zone="${ZONE}" &>/dev/null; then
            log "Deleting $env cluster: $cluster_name"
            (
                if gcloud container clusters delete "$cluster_name" \
                    --zone="${ZONE}" \
                    --quiet; then
                    success "$env cluster deleted: $cluster_name"
                else
                    error "Failed to delete $env cluster: $cluster_name"
                fi
            ) &
            cluster_pids+=($!)
        else
            warning "$env cluster not found: $cluster_name"
        fi
    done
    
    # Wait for all cluster deletions to complete
    if [ ${#cluster_pids[@]} -gt 0 ]; then
        log "Waiting for cluster deletions to complete..."
        for pid in "${cluster_pids[@]}"; do
            wait "$pid"
        done
    fi
    
    success "GKE clusters cleanup completed"
}

# Function to delete Artifact Registry repositories
delete_artifact_registry() {
    log "Deleting Artifact Registry repositories..."
    
    repo_name="${CLUSTER_PREFIX}-repo"
    if gcloud artifacts repositories describe "$repo_name" \
        --location="${REGION}" &>/dev/null; then
        if gcloud artifacts repositories delete "$repo_name" \
            --location="${REGION}" \
            --quiet; then
            success "Artifact Registry repository deleted: $repo_name"
        else
            error "Failed to delete Artifact Registry repository: $repo_name"
        fi
    else
        warning "Artifact Registry repository not found: $repo_name"
    fi
    
    success "Artifact Registry cleanup completed"
}

# Function to delete Cloud Build resources
delete_cloud_build_resources() {
    log "Deleting Cloud Build resources..."
    
    # Cloud Build builds and logs are automatically retained for auditing
    # We don't delete them as they provide valuable history
    log "Cloud Build builds and logs are retained for auditing purposes"
    
    # Cancel any running builds for this pipeline
    log "Checking for running builds..."
    RUNNING_BUILDS=$(gcloud builds list \
        --filter="status=WORKING AND substitutions.REPO_NAME~'${CLUSTER_PREFIX}'" \
        --format="value(id)" 2>/dev/null || true)
    
    if [ -n "$RUNNING_BUILDS" ]; then
        log "Cancelling running builds..."
        while IFS= read -r build_id; do
            if [ -n "$build_id" ]; then
                log "Cancelling build: $build_id"
                gcloud builds cancel "$build_id" --quiet 2>/dev/null || warning "Failed to cancel build: $build_id"
            fi
        done <<< "$RUNNING_BUILDS"
    else
        log "No running builds found"
    fi
    
    success "Cloud Build resources cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting Cloud Monitoring resources..."
    
    # Find and delete monitoring dashboards
    DASHBOARD_ID=$(gcloud monitoring dashboards list \
        --filter="displayName:'${CLUSTER_PREFIX} Pipeline Dashboard'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$DASHBOARD_ID" ]; then
        log "Deleting monitoring dashboard: $DASHBOARD_ID"
        if gcloud monitoring dashboards delete "$DASHBOARD_ID" --quiet; then
            success "Monitoring dashboard deleted"
        else
            warning "Failed to delete monitoring dashboard"
        fi
    else
        log "No monitoring dashboard found for ${CLUSTER_PREFIX}"
    fi
    
    success "Monitoring resources cleanup completed"
}

# Function to delete local application files
delete_local_files() {
    log "Cleaning up local application files..."
    
    app_dir="${CLUSTER_PREFIX}-app"
    if [ -d "$app_dir" ]; then
        log "Removing local application directory: $app_dir"
        if rm -rf "$app_dir"; then
            success "Local application files deleted"
        else
            error "Failed to delete local application files"
        fi
    else
        log "Local application directory not found: $app_dir"
    fi
    
    # Clean up any remaining configuration files
    for file in "monitoring-dashboard.json" "${CLUSTER_PREFIX}-*.yaml" "${CLUSTER_PREFIX}-*.json"; do
        if [ -f "$file" ]; then
            log "Removing configuration file: $file"
            rm -f "$file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check GKE clusters
    for env in dev staging prod; do
        cluster_name="${CLUSTER_PREFIX}-${env}"
        if gcloud container clusters describe "$cluster_name" --zone="${ZONE}" &>/dev/null; then
            cleanup_issues+=("GKE cluster still exists: $cluster_name")
        fi
    done
    
    # Check Cloud Deploy pipeline
    if gcloud deploy delivery-pipelines describe "${CLUSTER_PREFIX}-pipeline" \
        --region="${REGION}" &>/dev/null; then
        cleanup_issues+=("Cloud Deploy pipeline still exists: ${CLUSTER_PREFIX}-pipeline")
    fi
    
    # Check Artifact Registry
    repo_name="${CLUSTER_PREFIX}-repo"
    if gcloud artifacts repositories describe "$repo_name" \
        --location="${REGION}" &>/dev/null; then
        cleanup_issues+=("Artifact Registry repository still exists: $repo_name")
    fi
    
    # Check monitoring dashboard
    DASHBOARD_ID=$(gcloud monitoring dashboards list \
        --filter="displayName:'${CLUSTER_PREFIX} Pipeline Dashboard'" \
        --format="value(name)" 2>/dev/null || true)
    if [ -n "$DASHBOARD_ID" ]; then
        cleanup_issues+=("Monitoring dashboard still exists: $DASHBOARD_ID")
    fi
    
    # Report results
    if [ ${#cleanup_issues[@]} -eq 0 ]; then
        success "All resources successfully cleaned up"
    else
        warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            echo "  - $issue"
        done
        echo ""
        echo "These resources may need manual cleanup or may take additional time to be fully deleted."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Resource Prefix: ${CLUSTER_PREFIX}"
    echo ""
    echo "Cleaned up resources:"
    echo "- Cloud Deploy pipeline and targets"
    echo "- GKE clusters (dev, staging, prod)"
    echo "- Artifact Registry repository"
    echo "- Cloud Monitoring dashboard"
    echo "- Local application configuration files"
    echo ""
    echo "Retained resources:"
    echo "- Cloud Build logs and history (for auditing)"
    echo "- Google Cloud APIs (still enabled)"
    echo ""
    success "Multi-environment testing pipeline cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting multi-environment testing pipeline cleanup..."
    
    validate_prerequisites
    discover_resources
    confirm_destruction
    delete_cloud_deploy_resources
    delete_gke_clusters
    delete_artifact_registry
    delete_cloud_build_resources
    delete_monitoring_resources
    delete_local_files
    verify_cleanup
    display_cleanup_summary
}

# Script options
FORCE=false
CLUSTER_PREFIX=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --cluster-prefix)
            CLUSTER_PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            log "DRY RUN MODE - No resources will be deleted"
            log "Would delete resources with prefix: ${CLUSTER_PREFIX:-"<auto-discovered>"}"
            log "- Cloud Deploy pipeline and targets"
            log "- GKE clusters (dev, staging, prod)"
            log "- Artifact Registry repository"
            log "- Cloud Monitoring dashboard"
            log "- Local application configuration files"
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force                       Skip confirmation prompts"
            echo "  --cluster-prefix PREFIX       Specify the cluster prefix to clean up"
            echo "  --dry-run                     Show what would be deleted without actually deleting"
            echo "  --help                        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Auto-discover and delete pipeline resources"
            echo "  $0 --cluster-prefix pipeline-abc123  # Delete specific pipeline resources"
            echo "  $0 --force                           # Skip confirmation prompts"
            echo "  $0 --dry-run                         # Preview what would be deleted"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"
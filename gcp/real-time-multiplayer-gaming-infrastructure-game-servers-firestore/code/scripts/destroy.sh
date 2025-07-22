#!/bin/bash

# Real-Time Multiplayer Gaming Infrastructure Cleanup Script
# This script safely removes all resources created by the deployment script.

set -euo pipefail

# Configuration and Logging
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment-config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "${BLUE}INFO${NC}" "$@"; }
warn() { log "${YELLOW}WARN${NC}" "$@"; }
error() { log "${RED}ERROR${NC}" "$@"; }
success() { log "${GREEN}SUCCESS${NC}" "$@"; }

# Error handling for partial cleanup
handle_error() {
    local exit_code=$?
    error "Error occurred during cleanup (exit code: ${exit_code})"
    warn "Some resources may still exist. Please check manually if needed."
    return 0  # Don't exit on cleanup errors
}

trap handle_error ERR

# Load configuration
load_configuration() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        info "Loading configuration from ${CONFIG_FILE}"
        source "${CONFIG_FILE}"
    else
        warn "Configuration file not found. Using default values."
        warn "Some resources may not be cleaned up properly."
        
        # Set default values for cleanup
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export CLUSTER_NAME="${CLUSTER_NAME:-game-cluster}"
        export CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-}"
        export FIRESTORE_DATABASE="${FIRESTORE_DATABASE:-}"
    fi
    
    # Verify we have essential configuration
    if [[ -z "${PROJECT_ID}" ]]; then
        error "PROJECT_ID is not set. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    info "Configuration loaded for project: ${PROJECT_ID}"
}

# Confirmation prompt
confirm_destruction() {
    local force_cleanup="${1:-false}"
    
    if [[ "${force_cleanup}" != "true" ]]; then
        warn "⚠️  This will PERMANENTLY DELETE all gaming infrastructure resources!"
        warn "   - GKE Cluster: ${CLUSTER_NAME}"
        warn "   - Firestore Database: ${FIRESTORE_DATABASE}"
        warn "   - Cloud Run Service: ${CLOUD_RUN_SERVICE}"
        warn "   - Load Balancer and associated resources"
        warn "   - All game server fleets and configurations"
        echo ""
        
        read -r -p "Are you absolutely sure you want to continue? (type 'DELETE' to confirm): " confirmation
        
        if [[ "${confirmation}" != "DELETE" ]]; then
            info "Cleanup cancelled by user."
            exit 0
        fi
    fi
    
    info "Proceeding with resource cleanup..."
}

# Remove load balancer resources
remove_load_balancer() {
    info "Removing load balancer resources..."
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe game-forwarding-rule --global &>/dev/null; then
        info "Deleting global forwarding rule..."
        gcloud compute forwarding-rules delete game-forwarding-rule \
            --global \
            --quiet || warn "Failed to delete forwarding rule"
    fi
    
    # Delete HTTP proxy
    if gcloud compute target-http-proxies describe game-proxy --global &>/dev/null; then
        info "Deleting HTTP proxy..."
        gcloud compute target-http-proxies delete game-proxy \
            --global \
            --quiet || warn "Failed to delete HTTP proxy"
    fi
    
    # Delete URL map
    if gcloud compute url-maps describe game-loadbalancer --global &>/dev/null; then
        info "Deleting URL map..."
        gcloud compute url-maps delete game-loadbalancer \
            --global \
            --quiet || warn "Failed to delete URL map"
    fi
    
    # Delete backend service
    if gcloud compute backend-services describe game-backend --global &>/dev/null; then
        info "Deleting backend service..."
        gcloud compute backend-services delete game-backend \
            --global \
            --quiet || warn "Failed to delete backend service"
    fi
    
    success "Load balancer resources cleanup completed"
}

# Remove Cloud Run service
remove_cloud_run_service() {
    info "Removing Cloud Run service..."
    
    if [[ -n "${CLOUD_RUN_SERVICE}" ]]; then
        # Delete Cloud Run service
        if gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" &>/dev/null; then
            info "Deleting Cloud Run service: ${CLOUD_RUN_SERVICE}"
            gcloud run services delete "${CLOUD_RUN_SERVICE}" \
                --platform managed \
                --region "${REGION}" \
                --quiet || warn "Failed to delete Cloud Run service"
        fi
        
        # Delete container image
        if gcloud container images describe "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" &>/dev/null; then
            info "Deleting container image..."
            gcloud container images delete "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" \
                --quiet || warn "Failed to delete container image"
        fi
    else
        warn "Cloud Run service name not found in configuration"
    fi
    
    success "Cloud Run service cleanup completed"
}

# Remove Firestore database
remove_firestore_database() {
    info "Removing Firestore database..."
    
    if [[ -n "${FIRESTORE_DATABASE}" ]]; then
        if gcloud firestore databases describe --database="${FIRESTORE_DATABASE}" &>/dev/null; then
            info "Deleting Firestore database: ${FIRESTORE_DATABASE}"
            gcloud firestore databases delete "${FIRESTORE_DATABASE}" \
                --quiet || warn "Failed to delete Firestore database"
        fi
    else
        warn "Firestore database name not found in configuration"
    fi
    
    success "Firestore database cleanup completed"
}

# Remove game server resources
remove_game_server_resources() {
    info "Removing game server resources..."
    
    # Try to connect to cluster first
    if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${ZONE}" &>/dev/null; then
        # Get cluster credentials
        gcloud container clusters get-credentials "${CLUSTER_NAME}" \
            --zone="${ZONE}" --quiet || warn "Failed to get cluster credentials"
        
        # Delete game server fleet
        if kubectl get fleet simple-game-server-fleet &>/dev/null; then
            info "Deleting game server fleet..."
            kubectl delete fleet simple-game-server-fleet --timeout=60s || warn "Failed to delete game server fleet"
        fi
        
        # Uninstall Agones if installed
        if helm list -n agones-system | grep -q agones; then
            info "Uninstalling Agones..."
            helm uninstall agones --namespace agones-system --timeout=300s || warn "Failed to uninstall Agones"
        fi
        
        # Delete agones-system namespace
        if kubectl get namespace agones-system &>/dev/null; then
            info "Deleting agones-system namespace..."
            kubectl delete namespace agones-system --timeout=60s || warn "Failed to delete agones-system namespace"
        fi
    else
        warn "Cluster not found or not accessible. Skipping game server cleanup."
    fi
    
    success "Game server resources cleanup completed"
}

# Remove GKE cluster
remove_gke_cluster() {
    info "Removing GKE cluster..."
    
    if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${ZONE}" &>/dev/null; then
        info "Deleting GKE cluster: ${CLUSTER_NAME}"
        
        # Delete cluster with timeout
        timeout 600 gcloud container clusters delete "${CLUSTER_NAME}" \
            --zone="${ZONE}" \
            --quiet || warn "Failed to delete GKE cluster or operation timed out"
    else
        warn "GKE cluster ${CLUSTER_NAME} not found"
    fi
    
    success "GKE cluster cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/matchmaking-service"
        "${SCRIPT_DIR}/gameserver-fleet.yaml"
        "${SCRIPT_DIR}/sync-config.js"
        "${SCRIPT_DIR}/firestore.rules"
        "${SCRIPT_DIR}/game-schema.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            info "Removing ${file}"
            rm -rf "${file}" || warn "Failed to remove ${file}"
        fi
    done
    
    success "Local files cleanup completed"
}

# Remove configuration file
cleanup_configuration() {
    local keep_config="${1:-false}"
    
    if [[ "${keep_config}" != "true" && -f "${CONFIG_FILE}" ]]; then
        info "Removing configuration file..."
        rm -f "${CONFIG_FILE}" || warn "Failed to remove configuration file"
    elif [[ "${keep_config}" == "true" ]]; then
        info "Keeping configuration file for reference"
    fi
}

# Check for remaining resources
check_remaining_resources() {
    info "Checking for any remaining resources..."
    
    local remaining_resources=()
    
    # Check for GKE clusters
    if gcloud container clusters list --filter="name:${CLUSTER_NAME}" --format="value(name)" | grep -q .; then
        remaining_resources+=("GKE cluster: ${CLUSTER_NAME}")
    fi
    
    # Check for Cloud Run services
    if gcloud run services list --filter="metadata.name:${CLOUD_RUN_SERVICE}" --format="value(metadata.name)" | grep -q .; then
        remaining_resources+=("Cloud Run service: ${CLOUD_RUN_SERVICE}")
    fi
    
    # Check for load balancer resources
    if gcloud compute forwarding-rules list --global --filter="name:game-forwarding-rule" --format="value(name)" | grep -q .; then
        remaining_resources+=("Load balancer resources")
    fi
    
    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        warn "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            warn "  - ${resource}"
        done
        warn "Please check manually and remove if necessary."
    else
        success "No remaining resources detected"
    fi
}

# Validate cleanup prerequisites
validate_cleanup_prerequisites() {
    info "Validating cleanup prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI is not installed."
        exit 1
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        warn "kubectl is not installed. GKE cleanup may be limited."
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        warn "helm is not installed. Agones cleanup may be limited."
    fi
    
    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Cleanup prerequisites validated"
}

# Show cleanup summary
show_cleanup_summary() {
    info ""
    success "🧹 Gaming infrastructure cleanup completed!"
    info ""
    info "📋 Cleanup Summary:"
    info "  ✅ Load balancer resources removed"
    info "  ✅ Cloud Run service removed"
    info "  ✅ Firestore database removed"
    info "  ✅ Game server resources removed"
    info "  ✅ GKE cluster removed"
    info "  ✅ Local files cleaned up"
    info ""
    info "💡 Notes:"
    info "  - Some Google Cloud billing may continue for a short period"
    info "  - Container Registry images may need manual cleanup"
    info "  - Check the Google Cloud Console for any missed resources"
    info ""
    info "📄 Cleanup log saved to: ${LOG_FILE}"
}

# Main cleanup function
main() {
    local force_cleanup="false"
    local keep_config="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force_cleanup="true"
                shift
                ;;
            --keep-config|-k)
                keep_config="true"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -f, --force        Skip confirmation prompt"
                echo "  -k, --keep-config  Keep configuration file after cleanup"
                echo "  -h, --help         Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                 Interactive cleanup with confirmation"
                echo "  $0 --force         Automatic cleanup without confirmation"
                echo "  $0 --keep-config   Cleanup but keep configuration file"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    info "Starting Real-Time Multiplayer Gaming Infrastructure cleanup..."
    info "Cleanup log: ${LOG_FILE}"
    
    validate_cleanup_prerequisites
    load_configuration
    confirm_destruction "${force_cleanup}"
    
    # Cleanup in reverse order of creation
    remove_load_balancer
    remove_cloud_run_service
    remove_firestore_database
    remove_game_server_resources
    remove_gke_cluster
    cleanup_local_files
    check_remaining_resources
    cleanup_configuration "${keep_config}"
    
    show_cleanup_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
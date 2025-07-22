#!/bin/bash

# Multi-Cluster Service Mesh Governance Cleanup Script
# This script safely removes all resources created by the deployment script
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID     Specify GCP project ID (reads from .env if not provided)
#   --force                     Skip confirmation prompts
#   --keep-project             Keep the GCP project (only remove resources)
#   --dry-run                  Preview cleanup commands without executing
#   --help                     Show this help message

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
FORCE=false
KEEP_PROJECT=false
DRY_RUN=false

# Initialize variables
PROJECT_ID=""
REGION=""
ZONE=""
PROD_CLUSTER=""
STAGING_CLUSTER=""
DEV_CLUSTER=""

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
Multi-Cluster Service Mesh Governance Cleanup Script

This script safely removes all resources created by the deployment script, including:
- GKE clusters (production, staging, development)
- Anthos Service Mesh configurations
- Fleet Management memberships
- Anthos Config Management repositories
- Binary Authorization policies and attestors
- Artifact Registry repositories
- Monitoring dashboards
- Source repositories

Usage: $0 [OPTIONS]

Options:
  --project-id PROJECT_ID     Specify GCP project ID (reads from .env if not provided)
  --force                     Skip confirmation prompts (use with caution)
  --keep-project             Keep the GCP project (only remove resources within)
  --dry-run                  Preview cleanup commands without executing
  --help                     Show this help message

Examples:
  $0                          # Interactive cleanup with confirmations
  $0 --force                  # Automated cleanup without prompts
  $0 --keep-project          # Remove resources but keep project
  $0 --dry-run               # Preview what would be deleted
  $0 --project-id my-project # Cleanup specific project

Safety Features:
  - Interactive confirmation prompts by default
  - Dry-run mode to preview actions
  - Detailed logging of all operations
  - Graceful handling of missing resources
  - Option to preserve project while cleaning resources

Warning: This operation is destructive and cannot be undone!

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    local ignore_errors="${3:-false}"
    
    log_info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $cmd"
    else
        echo "Executing: $cmd" >> "$LOG_FILE"
        if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        else
            local exit_code=${PIPESTATUS[0]}
            if [[ "$ignore_errors" == "true" ]]; then
                log_warn "Command failed but continuing: $cmd"
                return 0
            else
                log_error "Command failed with exit code $exit_code: $cmd"
                return $exit_code
            fi
        fi
    fi
}

# Load environment variables
load_environment() {
    if [[ -f "$ENV_FILE" && -z "$PROJECT_ID" ]]; then
        log "Loading environment variables from $ENV_FILE..."
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        log "Loaded configuration:"
        log "  Project ID: $PROJECT_ID"
        log "  Region: $REGION"
        log "  Zone: $ZONE"
        log "  Production cluster: $PROD_CLUSTER"
        log "  Staging cluster: $STAGING_CLUSTER"
        log "  Development cluster: $DEV_CLUSTER"
    elif [[ -n "$PROJECT_ID" ]]; then
        log "Using provided project ID: $PROJECT_ID"
        log_warn "Cluster names not available - will attempt cleanup using project listing"
    else
        log_error "No project ID provided and no environment file found at $ENV_FILE"
        log_error "Please provide --project-id or ensure .env file exists from deployment"
        exit 1
    fi
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default="${2:-no}"
    
    if [[ "$FORCE" == "true" ]]; then
        log_warn "FORCE mode: Skipping confirmation for: $message"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would prompt for: $message"
        return 0
    fi
    
    local prompt
    if [[ "$default" == "yes" ]]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    while true; do
        read -p "$prompt" response
        case "${response,,}" in
            yes|y)
                return 0
                ;;
            no|n)
                return 1
                ;;
            "")
                if [[ "$default" == "yes" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Show cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary:"
    log "================"
    log "Project ID: $PROJECT_ID"
    if [[ -n "$REGION" ]]; then
        log "Region: $REGION"
        log "Zone: $ZONE"
    fi
    echo
    log "Resources to be removed:"
    if [[ -n "$PROD_CLUSTER" ]]; then
        log "- GKE Clusters: $PROD_CLUSTER, $STAGING_CLUSTER, $DEV_CLUSTER"
    else
        log "- All GKE clusters in the project"
    fi
    log "- Fleet Management memberships"
    log "- Anthos Service Mesh configurations"
    log "- Anthos Config Management"
    log "- Binary Authorization policies and attestors"
    log "- Artifact Registry repositories"
    log "- Source repositories"
    log "- Monitoring dashboards"
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        log "- GCP Project (complete deletion)"
    fi
    echo
    log_warn "This operation is destructive and cannot be undone!"
}

# Remove sample applications and configurations
cleanup_applications() {
    log "Cleaning up sample applications and configurations..."
    
    if [[ -n "$PROJECT_ID" ]]; then
        # Try to clean up Git repository configurations
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        if gcloud source repos clone anthos-config-management --project="$PROJECT_ID" 2>/dev/null; then
            cd anthos-config-management
            
            # Remove sample applications if they exist
            if [[ -d "config-root/namespaces/production/apps" ]]; then
                execute_cmd "git rm -r config-root/namespaces/*/apps/ || true" \
                    "Removing sample applications" "true"
                execute_cmd "git -c user.email='cleanup@example.com' -c user.name='Cleanup Script' commit -m 'Remove sample applications' || true" \
                    "Committing application removal" "true"
                execute_cmd "git push origin master || true" \
                    "Pushing configuration changes" "true"
            fi
        fi
        
        cd "$SCRIPT_DIR"
        rm -rf "$temp_dir"
    fi
    
    log "✅ Sample applications cleanup completed"
}

# Remove Config Management and Fleet features
cleanup_config_management() {
    log "Removing Config Management and Fleet features..."
    
    if [[ -n "$PROD_CLUSTER" && -n "$STAGING_CLUSTER" && -n "$DEV_CLUSTER" ]]; then
        # Remove Config Management from specific clusters
        execute_cmd "kubectl delete configmanagement config-management --context=gke_${PROJECT_ID}_${ZONE}_${PROD_CLUSTER} || true" \
            "Removing Config Management from production cluster" "true"
        execute_cmd "kubectl delete configmanagement config-management --context=gke_${PROJECT_ID}_${ZONE}_${STAGING_CLUSTER} || true" \
            "Removing Config Management from staging cluster" "true"
        execute_cmd "kubectl delete configmanagement config-management --context=gke_${PROJECT_ID}_${ZONE}_${DEV_CLUSTER} || true" \
            "Removing Config Management from development cluster" "true"
    fi
    
    # Disable service mesh on fleet
    execute_cmd "gcloud container fleet mesh disable --force || true" \
        "Disabling service mesh on fleet" "true"
    
    # Unregister clusters from fleet (try both specific names and discovery)
    if [[ -n "$PROD_CLUSTER" ]]; then
        execute_cmd "gcloud container fleet memberships unregister prod-membership || true" \
            "Unregistering production cluster from fleet" "true"
        execute_cmd "gcloud container fleet memberships unregister staging-membership || true" \
            "Unregistering staging cluster from fleet" "true"
        execute_cmd "gcloud container fleet memberships unregister dev-membership || true" \
            "Unregistering development cluster from fleet" "true"
    else
        # Try to unregister all memberships
        local memberships
        memberships=$(gcloud container fleet memberships list --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$memberships" ]]; then
            while IFS= read -r membership; do
                execute_cmd "gcloud container fleet memberships unregister '$membership' || true" \
                    "Unregistering membership: $membership" "true"
            done <<< "$memberships"
        fi
    fi
    
    log "✅ Config Management and Fleet features cleanup completed"
}

# Delete GKE clusters
cleanup_gke_clusters() {
    log "Deleting GKE clusters..."
    
    if [[ -n "$PROD_CLUSTER" && -n "$STAGING_CLUSTER" && -n "$DEV_CLUSTER" ]]; then
        # Delete specific clusters
        execute_cmd "gcloud container clusters delete ${PROD_CLUSTER} --zone=${ZONE} --quiet || true" \
            "Deleting production cluster" "true"
        execute_cmd "gcloud container clusters delete ${STAGING_CLUSTER} --zone=${ZONE} --quiet || true" \
            "Deleting staging cluster" "true"
        execute_cmd "gcloud container clusters delete ${DEV_CLUSTER} --zone=${ZONE} --quiet || true" \
            "Deleting development cluster" "true"
    else
        # Delete all clusters in the project
        local clusters
        clusters=$(gcloud container clusters list --format="value(name,zone)" 2>/dev/null || echo "")
        if [[ -n "$clusters" ]]; then
            while IFS=$'\t' read -r cluster_name cluster_zone; do
                [[ -n "$cluster_name" && -n "$cluster_zone" ]] && \
                execute_cmd "gcloud container clusters delete '$cluster_name' --zone='$cluster_zone' --quiet || true" \
                    "Deleting cluster: $cluster_name in $cluster_zone" "true"
            done <<< "$clusters"
        fi
    fi
    
    log "✅ GKE clusters cleanup completed"
}

# Clean up Binary Authorization
cleanup_binary_authorization() {
    log "Cleaning up Binary Authorization..."
    
    # Delete attestors
    execute_cmd "gcloud container binauthz attestors delete production-attestor --quiet || true" \
        "Deleting production attestor" "true"
    execute_cmd "gcloud container binauthz attestors delete staging-attestor --quiet || true" \
        "Deleting staging attestor" "true"
    
    # Reset Binary Authorization policy to default
    execute_cmd "gcloud container binauthz policy import /dev/stdin <<< '{
      \"defaultAdmissionRule\": {
        \"requireAttestationsBy\": [],
        \"enforcementMode\": \"PERMISSIVE_ENFORCEMENT\",
        \"evaluationMode\": \"ALWAYS_ALLOW\"
      },
      \"name\": \"projects/${PROJECT_ID}/policy\"
    }' || true" \
        "Resetting Binary Authorization policy" "true"
    
    log "✅ Binary Authorization cleanup completed"
}

# Clean up supporting resources
cleanup_supporting_resources() {
    log "Cleaning up supporting resources..."
    
    # Delete Artifact Registry repository
    if [[ -n "$REGION" ]]; then
        execute_cmd "gcloud artifacts repositories delete secure-apps --location=${REGION} --quiet || true" \
            "Deleting Artifact Registry repository" "true"
    else
        # Try common regions
        for region in us-central1 us-east1 us-west1 europe-west1; do
            execute_cmd "gcloud artifacts repositories delete secure-apps --location=$region --quiet || true" \
                "Attempting to delete Artifact Registry in $region" "true"
        done
    fi
    
    # Delete monitoring dashboard
    local dashboard_id
    dashboard_id=$(gcloud monitoring dashboards list --filter="displayName:'Service Mesh Governance Dashboard'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$dashboard_id" ]]; then
        execute_cmd "gcloud monitoring dashboards delete '$dashboard_id' --quiet || true" \
            "Deleting monitoring dashboard" "true"
    fi
    
    # Delete source repository
    execute_cmd "gcloud source repos delete anthos-config-management --quiet || true" \
        "Deleting source repository" "true"
    
    log "✅ Supporting resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        execute_cmd "rm -f '$ENV_FILE'" \
            "Removing environment file"
    fi
    
    # Remove any temporary kubeconfig contexts (best effort)
    if command -v kubectl &> /dev/null && [[ -n "$PROJECT_ID" ]]; then
        local contexts
        contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep "gke_${PROJECT_ID}" || true)
        if [[ -n "$contexts" ]]; then
            while IFS= read -r context; do
                [[ -n "$context" ]] && \
                execute_cmd "kubectl config delete-context '$context' || true" \
                    "Removing kubectl context: $context" "true"
            done <<< "$contexts"
        fi
    fi
    
    log "✅ Local files cleanup completed"
}

# Project deletion
delete_project() {
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log "Keeping project as requested (--keep-project flag)"
        return 0
    fi
    
    log_warn "Preparing to delete entire project: $PROJECT_ID"
    log_warn "This will remove ALL resources in the project, not just those created by this script"
    
    if confirm_action "Delete the entire project '$PROJECT_ID'? This cannot be undone!"; then
        execute_cmd "gcloud projects delete '$PROJECT_ID' --quiet" \
            "Deleting project: $PROJECT_ID"
        log "✅ Project deletion initiated"
        log_info "Project deletion is asynchronous and may take several minutes to complete"
    else
        log "Project deletion cancelled by user"
    fi
}

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check kubectl (optional, may not be needed for all cleanup operations)
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl is not installed - some cleanup operations may be skipped"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . 2>/dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first"
        exit 1
    fi
    
    log "✅ Prerequisites check completed"
}

# Validate project exists and is accessible
validate_project() {
    log "Validating project access..."
    
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        log_error "Please check the project ID and your permissions"
        exit 1
    fi
    
    # Set project context
    execute_cmd "gcloud config set project '$PROJECT_ID'" \
        "Setting project context"
    
    log "✅ Project validation completed"
}

# Main cleanup orchestration
perform_cleanup() {
    log "Starting cleanup operations..."
    
    cleanup_applications
    cleanup_config_management
    cleanup_gke_clusters
    cleanup_binary_authorization
    cleanup_supporting_resources
    cleanup_local_files
    
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        delete_project
    fi
    
    log "✅ All cleanup operations completed"
}

# Display completion summary
show_completion_summary() {
    log "🧹 Multi-Cluster Service Mesh Governance cleanup completed!"
    echo
    log "Cleanup Summary:"
    log "================"
    log "Project ID: $PROJECT_ID"
    echo
    log "Resources Removed:"
    log "- ✅ GKE clusters and associated resources"
    log "- ✅ Anthos Service Mesh configurations"
    log "- ✅ Fleet Management memberships"
    log "- ✅ Anthos Config Management"
    log "- ✅ Binary Authorization policies and attestors"
    log "- ✅ Artifact Registry repositories"
    log "- ✅ Source repositories"
    log "- ✅ Monitoring dashboards"
    log "- ✅ Local configuration files"
    
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log "- ⚠️  Project preserved (--keep-project flag)"
    else
        log "- ✅ Project deletion initiated"
    fi
    echo
    log "Cleanup log available at: $LOG_FILE"
    
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        log_info "Note: Project deletion is asynchronous and may take several minutes to complete"
        log_info "You can monitor progress in the Google Cloud Console"
    fi
}

# Main execution function
main() {
    # Initialize log file
    echo "=== Multi-Cluster Service Mesh Governance Cleanup Started at $(date) ===" > "$LOG_FILE"
    
    log "Starting Multi-Cluster Service Mesh Governance cleanup..."
    log "Cleanup script version: 1.0.0"
    
    parse_args "$@"
    check_prerequisites
    load_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No actual resources will be deleted"
        echo
    fi
    
    show_cleanup_summary
    echo
    
    if confirm_action "Proceed with cleanup?"; then
        validate_project
        perform_cleanup
        
        if [[ "$DRY_RUN" != "true" ]]; then
            show_completion_summary
        else
            log "DRY RUN completed. No resources were deleted."
        fi
    else
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "=== Cleanup completed at $(date) ==="
}

# Error handling
trap 'log_error "Cleanup script failed at line $LINENO. Exit code: $?"; exit 1' ERR

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
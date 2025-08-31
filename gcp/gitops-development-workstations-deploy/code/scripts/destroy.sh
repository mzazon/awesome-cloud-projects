#!/bin/bash

# GitOps Development Workflows with Cloud Workstations and Deploy - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $*"
    echo -e "$message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
handle_error() {
    local line_number=$1
    log_error "Script failed at line $line_number. Some resources may not have been cleaned up."
    log_error "You may need to manually delete remaining resources through the Cloud Console."
    exit 1
}

trap 'handle_error ${LINENO}' ERR

# Help function
show_help() {
    cat << EOF
GitOps Development Workflows Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without making changes
    -f, --force             Skip confirmation prompts
    -p, --project-id        Project ID to clean up (required)
    -r, --region            Region where resources were created (default: us-central1)
    --workstation-only      Delete only workstation components
    --pipeline-only         Delete only CI/CD pipeline components
    --keep-project          Don't delete the project, only resources within it

EXAMPLES:
    $0 --project-id my-project              # Interactive cleanup
    $0 --project-id my-project --force      # Cleanup without prompts
    $0 --project-id my-project --dry-run    # Preview what would be deleted
    $0 --project-id my-project --workstation-only  # Delete only workstations

ENVIRONMENT VARIABLES:
    PROJECT_ID          Google Cloud project ID (required if not set via flag)
    REGION              Google Cloud region (default: us-central1)
    DRY_RUN            Set to 'true' for dry run mode
    FORCE              Set to 'true' to skip confirmation prompts

WARNING:
    This script will permanently delete Google Cloud resources.
    Make sure you have backups of any important data before proceeding.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --workstation-only)
                WORKSTATION_ONLY=true
                shift
                ;;
            --pipeline-only)
                PIPELINE_ONLY=true
                shift
                ;;
            --keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud >/dev/null 2>&1; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate project ID is provided
    if [ -z "${PROJECT_ID:-}" ]; then
        log_error "PROJECT_ID is required. Use --project-id flag or set PROJECT_ID environment variable."
        exit 1
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize environment variables
init_environment() {
    log_info "Initializing environment variables..."
    
    # Set default values
    REGION=${REGION:-"us-central1"}
    WORKSTATION_ONLY=${WORKSTATION_ONLY:-false}
    PIPELINE_ONLY=${PIPELINE_ONLY:-false}
    KEEP_PROJECT=${KEEP_PROJECT:-false}
    
    # Set gcloud project
    gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE: No actual resources will be deleted"
    fi
}

# Execute command with dry run support
execute_command() {
    local cmd="$*"
    log_info "Executing: $cmd"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    # Add --quiet flag to most gcloud commands to suppress prompts
    if [[ "$cmd" == gcloud* ]] && [[ "$cmd" != *"--quiet"* ]] && [[ "$cmd" != *"list"* ]] && [[ "$cmd" != *"describe"* ]]; then
        cmd="$cmd --quiet"
    fi
    
    if ! eval "$cmd"; then
        log_warning "Command failed (continuing cleanup): $cmd"
        return 1
    fi
}

# Confirm deletion with user
confirm_deletion() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete Google Cloud resources in project: $PROJECT_ID"
    log_warning "This action cannot be undone."
    echo ""
    
    if [ "$WORKSTATION_ONLY" = true ]; then
        echo "Resources to be deleted: Cloud Workstations only"
    elif [ "$PIPELINE_ONLY" = true ]; then
        echo "Resources to be deleted: CI/CD Pipeline components only"
    else
        echo "Resources to be deleted:"
        echo "- GKE Clusters (staging and production)"
        echo "- Cloud Workstations"
        echo "- Cloud Source Repositories"
        echo "- Artifact Registry repositories"
        echo "- Cloud Deploy pipelines"
        echo "- Cloud Build triggers"
        echo "- Local temporary files"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# List resources to be deleted
list_resources() {
    log_info "Scanning for resources to delete..."
    
    if [ "$WORKSTATION_ONLY" != true ]; then
        # List GKE clusters
        log_info "GKE clusters in project:"
        gcloud container clusters list --format="table(name,location,status)" 2>/dev/null || log_warning "No GKE clusters found or permission denied"
        
        # List Cloud Deploy pipelines
        log_info "Cloud Deploy pipelines in region $REGION:"
        gcloud deploy delivery-pipelines list --region="$REGION" --format="table(name,description)" 2>/dev/null || log_warning "No Cloud Deploy pipelines found"
        
        # List Artifact Registry repositories
        log_info "Artifact Registry repositories in region $REGION:"
        gcloud artifacts repositories list --location="$REGION" --format="table(name,format,description)" 2>/dev/null || log_warning "No Artifact Registry repositories found"
        
        # List Source repositories
        log_info "Cloud Source repositories:"
        gcloud source repos list --format="table(name,url)" 2>/dev/null || log_warning "No Source repositories found"
        
        # List Cloud Build triggers
        log_info "Cloud Build triggers:"
        gcloud builds triggers list --format="table(name,description,createTime)" 2>/dev/null || log_warning "No Build triggers found"
    fi
    
    if [ "$PIPELINE_ONLY" != true ]; then
        # List Cloud Workstations
        log_info "Cloud Workstation clusters in region $REGION:"
        gcloud workstations clusters list --region="$REGION" --format="table(name,network)" 2>/dev/null || log_warning "No Workstation clusters found"
    fi
}

# Delete Cloud Deploy resources
delete_cloud_deploy() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Cloud Deploy deletion (workstation-only mode)"
        return 0
    fi
    
    log_info "Deleting Cloud Deploy resources..."
    
    # List and delete delivery pipelines
    local pipelines
    pipelines=$(gcloud deploy delivery-pipelines list --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$pipelines" ]; then
        while IFS= read -r pipeline; do
            if [ -n "$pipeline" ]; then
                log_info "Deleting delivery pipeline: $pipeline"
                execute_command "gcloud deploy delivery-pipelines delete $pipeline --region=$REGION"
            fi
        done <<< "$pipelines"
    else
        log_warning "No Cloud Deploy pipelines found to delete"
    fi
    
    log_success "Cloud Deploy resources cleanup completed"
}

# Delete GKE clusters
delete_gke_clusters() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping GKE cluster deletion (workstation-only mode)"
        return 0
    fi
    
    log_info "Deleting GKE clusters..."
    
    # List and delete all GKE clusters in the project
    local clusters
    clusters=$(gcloud container clusters list --format="value(name,zone)" 2>/dev/null || echo "")
    
    if [ -n "$clusters" ]; then
        while IFS=$'\t' read -r cluster_name cluster_zone; do
            if [ -n "$cluster_name" ] && [ -n "$cluster_zone" ]; then
                log_info "Deleting GKE cluster: $cluster_name in $cluster_zone"
                execute_command "gcloud container clusters delete $cluster_name --zone=$cluster_zone"
            fi
        done <<< "$clusters"
    else
        log_warning "No GKE clusters found to delete"
    fi
    
    log_success "GKE clusters deletion completed"
}

# Delete Cloud Workstations
delete_workstations() {
    if [ "$PIPELINE_ONLY" = true ]; then
        log_warning "Skipping Cloud Workstations deletion (pipeline-only mode)"
        return 0
    fi
    
    log_info "Deleting Cloud Workstations..."
    
    # List and delete workstation instances
    local workstation_configs
    workstation_configs=$(gcloud workstations clusters list --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$workstation_configs" ]; then
        while IFS= read -r cluster_name; do
            if [ -n "$cluster_name" ]; then
                log_info "Processing workstation cluster: $cluster_name"
                
                # Get configurations for this cluster
                local configs
                configs=$(gcloud workstations configs list --cluster="$cluster_name" --cluster-region="$REGION" --format="value(name)" 2>/dev/null || echo "")
                
                if [ -n "$configs" ]; then
                    while IFS= read -r config_name; do
                        if [ -n "$config_name" ]; then
                            log_info "Processing workstation config: $config_name"
                            
                            # Get workstation instances for this config
                            local instances
                            instances=$(gcloud workstations list --config="$config_name" --cluster="$cluster_name" --cluster-region="$REGION" --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
                            
                            if [ -n "$instances" ]; then
                                while IFS= read -r instance_name; do
                                    if [ -n "$instance_name" ]; then
                                        log_info "Deleting workstation instance: $instance_name"
                                        execute_command "gcloud workstations delete $instance_name --config=$config_name --cluster=$cluster_name --cluster-region=$REGION --region=$REGION"
                                    fi
                                done <<< "$instances"
                            fi
                            
                            # Delete the configuration
                            log_info "Deleting workstation configuration: $config_name"
                            execute_command "gcloud workstations configs delete $config_name --cluster=$cluster_name --cluster-region=$REGION"
                        fi
                    done <<< "$configs"
                fi
                
                # Delete the cluster
                log_info "Deleting workstation cluster: $cluster_name"
                execute_command "gcloud workstations clusters delete $cluster_name --region=$REGION"
            fi
        done <<< "$workstation_configs"
    else
        log_warning "No Cloud Workstation clusters found to delete"
    fi
    
    log_success "Cloud Workstations deletion completed"
}

# Delete Cloud Build triggers
delete_build_triggers() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Cloud Build triggers deletion (workstation-only mode)"
        return 0
    fi
    
    log_info "Deleting Cloud Build triggers..."
    
    # List and delete all build triggers
    local trigger_ids
    trigger_ids=$(gcloud builds triggers list --format="value(id)" 2>/dev/null || echo "")
    
    if [ -n "$trigger_ids" ]; then
        while IFS= read -r trigger_id; do
            if [ -n "$trigger_id" ]; then
                log_info "Deleting build trigger: $trigger_id"
                execute_command "gcloud builds triggers delete $trigger_id"
            fi
        done <<< "$trigger_ids"
    else
        log_warning "No Cloud Build triggers found to delete"
    fi
    
    log_success "Cloud Build triggers deletion completed"
}

# Delete Artifact Registry repositories
delete_artifact_registry() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Artifact Registry deletion (workstation-only mode)"
        return 0
    fi
    
    log_info "Deleting Artifact Registry repositories..."
    
    # List and delete repositories
    local repositories
    repositories=$(gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$repositories" ]; then
        while IFS= read -r repo_name; do
            if [ -n "$repo_name" ]; then
                # Extract just the repository name from the full path
                local short_name
                short_name=$(basename "$repo_name")
                log_info "Deleting Artifact Registry repository: $short_name"
                execute_command "gcloud artifacts repositories delete $short_name --location=$REGION"
            fi
        done <<< "$repositories"
    else
        log_warning "No Artifact Registry repositories found to delete"
    fi
    
    log_success "Artifact Registry repositories deletion completed"
}

# Delete Source repositories
delete_source_repos() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Source repositories deletion (workstation-only mode)"
        return 0
    fi
    
    log_info "Deleting Cloud Source repositories..."
    
    # List and delete repositories
    local repositories
    repositories=$(gcloud source repos list --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$repositories" ]; then
        while IFS= read -r repo_name; do
            if [ -n "$repo_name" ]; then
                log_info "Deleting Source repository: $repo_name"
                execute_command "gcloud source repos delete $repo_name"
            fi
        done <<< "$repositories"
    else
        log_warning "No Source repositories found to delete"
    fi
    
    log_success "Source repositories deletion completed"
}

# Clean up local files
cleanup_local_files() {
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    log_info "Cleaning up local files..."
    
    # Clean up common local directories and files created by the deployment script
    local cleanup_paths=(
        ~/kubernetes-engine-samples
        ~/cloudbuild-ci.yaml
        ~/clouddeploy.yaml
        ~/k8s
    )
    
    # Also clean up environment repo directories (pattern matching)
    if [ -d ~ ]; then
        local env_repos
        env_repos=$(find ~ -maxdepth 1 -type d -name "*-env-*-local" 2>/dev/null || echo "")
        if [ -n "$env_repos" ]; then
            while IFS= read -r repo_dir; do
                if [ -n "$repo_dir" ]; then
                    cleanup_paths+=("$repo_dir")
                fi
            done <<< "$env_repos"
        fi
    fi
    
    for path in "${cleanup_paths[@]}"; do
        if [ -e "$path" ]; then
            log_info "Removing: $path"
            rm -rf "$path"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Verify deletion
verify_deletion() {
    if [ "$DRY_RUN" = true ]; then
        log_warning "Skipping verification in dry run mode"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    local remaining_resources=false
    
    if [ "$WORKSTATION_ONLY" != true ]; then
        # Check for remaining GKE clusters
        if gcloud container clusters list --format="value(name)" 2>/dev/null | grep -q .; then
            log_warning "Some GKE clusters may still exist"
            remaining_resources=true
        fi
        
        # Check for remaining Cloud Deploy pipelines
        if gcloud deploy delivery-pipelines list --region="$REGION" --format="value(name)" 2>/dev/null | grep -q .; then
            log_warning "Some Cloud Deploy pipelines may still exist"
            remaining_resources=true
        fi
        
        # Check for remaining Artifact Registry repositories
        if gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null | grep -q .; then
            log_warning "Some Artifact Registry repositories may still exist"
            remaining_resources=true
        fi
        
        # Check for remaining Source repositories
        if gcloud source repos list --format="value(name)" 2>/dev/null | grep -q .; then
            log_warning "Some Source repositories may still exist"
            remaining_resources=true
        fi
        
        # Check for remaining Build triggers
        if gcloud builds triggers list --format="value(name)" 2>/dev/null | grep -q .; then
            log_warning "Some Build triggers may still exist"
            remaining_resources=true
        fi
    fi
    
    if [ "$PIPELINE_ONLY" != true ]; then
        # Check for remaining Workstation clusters
        if gcloud workstations clusters list --region="$REGION" --format="value(name)" 2>/dev/null | grep -q .; then
            log_warning "Some Workstation clusters may still exist"
            remaining_resources=true
        fi
    fi
    
    if [ "$remaining_resources" = true ]; then
        log_warning "Some resources may still exist. Check the Google Cloud Console for manual cleanup."
    else
        log_success "All targeted resources appear to have been deleted successfully"
    fi
}

# Generate cleanup summary
generate_summary() {
    log_info "Generating cleanup summary..."
    
    cat << EOF

========================================
CLEANUP SUMMARY
========================================

Project ID: $PROJECT_ID
Region: $REGION
Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "CLEANUP")

Resources Targeted for Deletion:
EOF

    if [ "$WORKSTATION_ONLY" = true ]; then
        echo "- Cloud Workstations (workstation-only mode)"
    elif [ "$PIPELINE_ONLY" = true ]; then
        echo "- CI/CD Pipeline components (pipeline-only mode)"
    else
        cat << EOF
- GKE Clusters (all in project)
- Cloud Workstations (all in region)
- Cloud Source Repositories (all in project)
- Artifact Registry repositories (all in region)
- Cloud Deploy pipelines (all in region)
- Cloud Build triggers (all in project)
- Local temporary files
EOF
    fi

    if [ "$DRY_RUN" = true ]; then
        cat << EOF

Next Steps:
- Run the script without --dry-run to actually delete the resources
- Use --force flag to skip confirmation prompts
EOF
    else
        cat << EOF

Cleanup Status: $([ "$?" -eq 0 ] && echo "COMPLETED" || echo "COMPLETED WITH WARNINGS")

Next Steps:
- Check the Google Cloud Console to verify all resources are deleted
- Review any remaining resources that may require manual deletion
- Consider deleting the project if it's no longer needed (use gcloud projects delete $PROJECT_ID)
EOF
    fi

    cat << EOF

Note: Some resources may take a few minutes to be fully deleted.
Check the Google Cloud Console if you need to verify complete removal.

========================================
EOF
}

# Main function
main() {
    log_info "Starting GitOps Development Workflows cleanup..."
    log_info "Log file: $LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    init_environment
    list_resources
    confirm_deletion
    
    # Execute cleanup in proper order (reverse of creation)
    delete_build_triggers
    delete_cloud_deploy
    delete_gke_clusters
    delete_workstations
    delete_artifact_registry
    delete_source_repos
    cleanup_local_files
    
    verify_deletion
    generate_summary
    
    if [ "$DRY_RUN" = true ]; then
        log_success "Dry run completed successfully. Review the planned deletions above."
    else
        log_success "GitOps Development Workflows cleanup completed!"
        log_warning "Remember to check the Google Cloud Console for any remaining resources."
    fi
}

# Run main function with all arguments
main "$@"
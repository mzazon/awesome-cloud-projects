#!/bin/bash
#
# destroy.sh - Cleanup Development Lifecycle Automation with Cloud Composer and Datastream
#
# This script removes all resources created by the deploy.sh script including:
# - Cloud Composer 3 environment
# - Datastream and connection profiles
# - Cloud SQL database instance
# - Artifact Registry repository
# - Cloud Workflows
# - Cloud Storage bucket and contents
# - Binary Authorization policies and attestors
#
# Usage: ./destroy.sh [--force] [--keep-project] [--dry-run]
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy-$(date +%Y%m%d-%H%M%S).log"

# Parse command line arguments
FORCE_CLEANUP=false
KEEP_PROJECT=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_CLEANUP=true
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
        --help|-h)
            echo "Usage: $0 [--force] [--keep-project] [--dry-run] [--help]"
            echo "  --force         Skip confirmation prompts and force cleanup"
            echo "  --keep-project  Don't delete the entire project (only remove resources)"
            echo "  --dry-run       Show what would be deleted without removing resources"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Global variables
PROJECT_ID=""
REGION=""
COMPOSER_ENV_NAME=""
DATASTREAM_NAME=""
BUCKET_NAME=""
ARTIFACT_REPO=""
DB_INSTANCE=""

# Logging function
log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
handle_error() {
    local exit_code=$?
    error "Cleanup failed with exit code $exit_code"
    error "Check log file: $LOG_FILE"
    error "Some resources may not have been deleted. Please check manually."
    exit $exit_code
}

trap handle_error ERR

# Utility functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    success "Authenticated as: $active_account"
    
    # Check for gsutil
    if ! command_exists gsutil; then
        error "gsutil is required but not installed"
        exit 1
    fi
    
    success "Prerequisites checked"
}

detect_resources() {
    info "Detecting deployed resources..."
    
    # Try to get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "No active GCP project found. Please set project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Try to get region from gcloud config
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    info "Detected project: $PROJECT_ID"
    info "Using region: $REGION"
    
    # Check for deployment info file
    local deployment_info="${SCRIPT_DIR}/deployment-info.txt"
    if [[ -f "$deployment_info" ]]; then
        info "Found deployment info file, extracting resource details..."
        
        # Extract resource names from deployment info
        COMPOSER_ENV_NAME=$(grep "Cloud Composer Environment:" "$deployment_info" | cut -d: -f2 | xargs || echo "intelligent-devops")
        BUCKET_NAME=$(grep "Storage Bucket:" "$deployment_info" | cut -d/ -f3 || echo "")
        DB_INSTANCE=$(grep "Database Instance:" "$deployment_info" | cut -d: -f2 | xargs || echo "")
        DATASTREAM_NAME=$(grep "Datastream:" "$deployment_info" | cut -d: -f2 | xargs || echo "schema-changes-stream")
        
        # Extract artifact repo from the line
        local artifact_line
        artifact_line=$(grep "Artifact Registry:" "$deployment_info" | cut -d: -f2- || echo "")
        if [[ -n "$artifact_line" ]]; then
            ARTIFACT_REPO=$(echo "$artifact_line" | sed 's|.*/'$PROJECT_ID'/||' | xargs)
        fi
    else
        warn "No deployment info file found. Using default resource names."
        COMPOSER_ENV_NAME="intelligent-devops"
        DATASTREAM_NAME="schema-changes-stream"
    fi
    
    info "Resource detection completed"
}

list_resources_to_delete() {
    info "Resources that will be deleted:"
    echo
    
    # List Cloud Composer environments
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would check for Cloud Composer environments"
    else
        local composer_envs
        composer_envs=$(gcloud composer environments list --locations="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
        if [[ -n "$composer_envs" ]]; then
            warn "Cloud Composer Environments (in $REGION):"
            echo "$composer_envs" | while read -r env; do
                if [[ -n "$env" ]]; then
                    echo "  - $env"
                fi
            done
        fi
    fi
    
    # List Datastream resources
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would check for Datastream resources"
    else
        local streams
        streams=$(gcloud datastream streams list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
        if [[ -n "$streams" ]]; then
            warn "Datastream Streams (in $REGION):"
            echo "$streams" | while read -r stream; do
                if [[ -n "$stream" ]]; then
                    echo "  - $(basename "$stream")"
                fi
            done
        fi
    fi
    
    # List Cloud SQL instances
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would check for Cloud SQL instances"
    else
        local sql_instances
        sql_instances=$(gcloud sql instances list --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
        if [[ -n "$sql_instances" ]]; then
            warn "Cloud SQL Instances:"
            echo "$sql_instances" | while read -r instance; do
                if [[ -n "$instance" ]]; then
                    echo "  - $instance"
                fi
            done
        fi
    fi
    
    # List Artifact Registry repositories
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would check for Artifact Registry repositories"
    else
        local repositories
        repositories=$(gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
        if [[ -n "$repositories" ]]; then
            warn "Artifact Registry Repositories (in $REGION):"
            echo "$repositories" | while read -r repo; do
                if [[ -n "$repo" ]]; then
                    echo "  - $(basename "$repo")"
                fi
            done
        fi
    fi
    
    # List Cloud Workflows
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would check for Cloud Workflows"
    else
        local workflows
        workflows=$(gcloud workflows list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
        if [[ -n "$workflows" ]]; then
            warn "Cloud Workflows (in $REGION):"
            echo "$workflows" | while read -r workflow; do
                if [[ -n "$workflow" ]]; then
                    echo "  - $(basename "$workflow")"
                fi
            done
        fi
    fi
    
    # List Cloud Storage buckets
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would check for Cloud Storage buckets"
    else
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "devops-automation" || echo "")
        if [[ -n "$buckets" ]]; then
            warn "Cloud Storage Buckets:"
            echo "$buckets" | while read -r bucket; do
                if [[ -n "$bucket" ]]; then
                    echo "  - $bucket"
                fi
            done
        fi
    fi
    
    echo
}

confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == true ]]; then
        warn "Force cleanup enabled - skipping confirmation"
        return 0
    fi
    
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete all resources created by the deployment."
    warn "This action cannot be undone!"
    echo
    
    if [[ "$KEEP_PROJECT" == false ]]; then
        warn "🚨 THE ENTIRE PROJECT WILL BE DELETED 🚨"
        warn "Project: $PROJECT_ID"
        echo
    fi
    
    warn "Estimated time for cleanup: 10-20 minutes"
    warn "Long-running operations (like Composer deletion) may take time to complete."
    echo
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to continue: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    warn "Starting cleanup in 5 seconds... Press Ctrl+C to abort"
    sleep 5
}

delete_composer_environment() {
    info "Deleting Cloud Composer environment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete Composer environment: $COMPOSER_ENV_NAME"
        return 0
    fi
    
    # Find and delete all Composer environments in the region
    local composer_envs
    composer_envs=$(gcloud composer environments list --locations="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$composer_envs" ]]; then
        echo "$composer_envs" | while read -r env; do
            if [[ -n "$env" ]]; then
                env_name=$(basename "$env")
                info "Deleting Composer environment: $env_name"
                
                # Delete environment (this may take 10-15 minutes)
                if gcloud composer environments delete "$env_name" \
                    --location="$REGION" \
                    --quiet; then
                    success "Composer environment deletion initiated: $env_name"
                else
                    warn "Failed to delete Composer environment: $env_name"
                fi
            fi
        done
    else
        info "No Cloud Composer environments found"
    fi
}

delete_datastream_resources() {
    info "Deleting Datastream resources..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete Datastream resources"
        return 0
    fi
    
    # Delete streams
    local streams
    streams=$(gcloud datastream streams list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$streams" ]]; then
        echo "$streams" | while read -r stream; do
            if [[ -n "$stream" ]]; then
                stream_name=$(basename "$stream")
                info "Deleting Datastream: $stream_name"
                
                if gcloud datastream streams delete "$stream_name" \
                    --location="$REGION" \
                    --quiet; then
                    success "Datastream deleted: $stream_name"
                else
                    warn "Failed to delete Datastream: $stream_name"
                fi
            fi
        done
    fi
    
    # Wait a bit for streams to be deleted before deleting connection profiles
    sleep 10
    
    # Delete connection profiles
    local profiles
    profiles=$(gcloud datastream connection-profiles list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$profiles" ]]; then
        echo "$profiles" | while read -r profile; do
            if [[ -n "$profile" ]]; then
                profile_name=$(basename "$profile")
                info "Deleting connection profile: $profile_name"
                
                if gcloud datastream connection-profiles delete "$profile_name" \
                    --location="$REGION" \
                    --quiet; then
                    success "Connection profile deleted: $profile_name"
                else
                    warn "Failed to delete connection profile: $profile_name"
                fi
            fi
        done
    fi
}

delete_database_instances() {
    info "Deleting Cloud SQL database instances..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete database instances"
        return 0
    fi
    
    # Get all SQL instances
    local sql_instances
    sql_instances=$(gcloud sql instances list --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$sql_instances" ]]; then
        echo "$sql_instances" | while read -r instance; do
            if [[ -n "$instance" ]]; then
                # Only delete instances that match our naming pattern or specific instance
                if [[ "$instance" == *"dev-database"* ]] || [[ "$instance" == "$DB_INSTANCE" ]]; then
                    info "Deleting SQL instance: $instance"
                    
                    if gcloud sql instances delete "$instance" --quiet; then
                        success "SQL instance deleted: $instance"
                    else
                        warn "Failed to delete SQL instance: $instance"
                    fi
                fi
            fi
        done
    else
        info "No Cloud SQL instances found"
    fi
}

delete_artifact_registry() {
    info "Deleting Artifact Registry repositories..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete Artifact Registry repositories"
        return 0
    fi
    
    # Get all repositories in the region
    local repositories
    repositories=$(gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$repositories" ]]; then
        echo "$repositories" | while read -r repo; do
            if [[ -n "$repo" ]]; then
                repo_name=$(basename "$repo")
                
                # Only delete repositories that match our naming pattern
                if [[ "$repo_name" == *"secure-containers"* ]] || [[ "$repo_name" == "$ARTIFACT_REPO" ]]; then
                    info "Deleting Artifact Registry repository: $repo_name"
                    
                    if gcloud artifacts repositories delete "$repo_name" \
                        --location="$REGION" \
                        --quiet; then
                        success "Artifact Registry repository deleted: $repo_name"
                    else
                        warn "Failed to delete Artifact Registry repository: $repo_name"
                    fi
                fi
            fi
        done
    else
        info "No Artifact Registry repositories found"
    fi
}

delete_workflows() {
    info "Deleting Cloud Workflows..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete Cloud Workflows"
        return 0
    fi
    
    # Get all workflows in the region
    local workflows
    workflows=$(gcloud workflows list --location="$REGION" --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$workflows" ]]; then
        echo "$workflows" | while read -r workflow; do
            if [[ -n "$workflow" ]]; then
                workflow_name=$(basename "$workflow")
                
                # Delete workflows that match our naming pattern
                if [[ "$workflow_name" == *"intelligent-deployment"* ]] || [[ "$workflow_name" == *"devops"* ]]; then
                    info "Deleting workflow: $workflow_name"
                    
                    if gcloud workflows delete "$workflow_name" \
                        --location="$REGION" \
                        --quiet; then
                        success "Workflow deleted: $workflow_name"
                    else
                        warn "Failed to delete workflow: $workflow_name"
                    fi
                fi
            fi
        done
    else
        info "No Cloud Workflows found"
    fi
}

delete_security_policies() {
    info "Cleaning up Binary Authorization policies..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete Binary Authorization policies"
        return 0
    fi
    
    # Reset Binary Authorization policy to default
    if gcloud container binauthz policy import /dev/stdin <<< '{}' 2>/dev/null; then
        success "Binary Authorization policy reset to default"
    else
        warn "Failed to reset Binary Authorization policy"
    fi
    
    # Delete attestors
    local attestors
    attestors=$(gcloud container binauthz attestors list --format="value(name)" 2>/dev/null | grep -v "^$" || echo "")
    
    if [[ -n "$attestors" ]]; then
        echo "$attestors" | while read -r attestor; do
            if [[ -n "$attestor" ]]; then
                attestor_name=$(basename "$attestor")
                
                if [[ "$attestor_name" == *"security-scan"* ]] || [[ "$attestor_name" == *"devops"* ]]; then
                    info "Deleting attestor: $attestor_name"
                    
                    if gcloud container binauthz attestors delete "$attestor_name" --quiet; then
                        success "Attestor deleted: $attestor_name"
                    else
                        warn "Failed to delete attestor: $attestor_name"
                    fi
                fi
            fi
        done
    fi
}

delete_storage_buckets() {
    info "Deleting Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete storage buckets"
        return 0
    fi
    
    # Get all buckets for the project
    local buckets
    buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "devops-automation" || echo "")
    
    if [[ -n "$buckets" ]]; then
        echo "$buckets" | while read -r bucket; do
            if [[ -n "$bucket" ]]; then
                info "Deleting storage bucket: $bucket"
                
                # Remove all objects first, then the bucket
                if gsutil -m rm -r "$bucket" 2>/dev/null; then
                    success "Storage bucket deleted: $bucket"
                else
                    warn "Failed to delete storage bucket: $bucket"
                fi
            fi
        done
    else
        info "No matching storage buckets found"
    fi
    
    # Also delete specific bucket if we know its name
    if [[ -n "$BUCKET_NAME" ]]; then
        local specific_bucket="gs://$BUCKET_NAME"
        if gsutil ls "$specific_bucket" >/dev/null 2>&1; then
            info "Deleting specific bucket: $specific_bucket"
            if gsutil -m rm -r "$specific_bucket" 2>/dev/null; then
                success "Specific bucket deleted: $specific_bucket"
            else
                warn "Failed to delete specific bucket: $specific_bucket"
            fi
        fi
    fi
}

clean_local_files() {
    info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would clean up local files"
        return 0
    fi
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/intelligent_cicd_dag.py"
        "${SCRIPT_DIR}/monitoring_dag.py"
        "${SCRIPT_DIR}/compliance-workflow.yaml"
        "${SCRIPT_DIR}/security-policy.yaml"
        "${SCRIPT_DIR}/db-config.txt"
        "${SCRIPT_DIR}/deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed local file: $(basename "$file")"
        fi
    done
}

delete_project() {
    if [[ "$KEEP_PROJECT" == true ]]; then
        info "Skipping project deletion (--keep-project specified)"
        return 0
    fi
    
    info "Deleting entire project..."
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    warn "Deleting project: $PROJECT_ID"
    warn "This will permanently delete ALL resources in the project!"
    
    if [[ "$FORCE_CLEANUP" == false ]]; then
        read -p "Type the project ID '$PROJECT_ID' to confirm project deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            warn "Project deletion cancelled - confirmation did not match"
            return 0
        fi
    fi
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        success "Project deletion initiated: $PROJECT_ID"
        info "Project deletion may take several minutes to complete"
    else
        error "Failed to delete project: $PROJECT_ID"
        exit 1
    fi
}

wait_for_operations() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    info "Waiting for long-running operations to complete..."
    info "This may take 10-15 minutes for Cloud Composer environment deletion"
    
    # We don't wait for all operations to complete as some may take very long
    # The user can check the console for operation status
    
    success "Cleanup operations initiated. Check GCP Console for completion status."
}

generate_cleanup_report() {
    info "Generating cleanup report..."
    
    local report_file="${SCRIPT_DIR}/cleanup-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
Development Lifecycle Automation Cleanup Report
=============================================

Cleanup Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION
Script Mode: $(if [[ "$DRY_RUN" == true ]]; then echo "DRY-RUN"; else echo "EXECUTION"; fi)

Operations Performed:
- Cloud Composer Environment: $(if [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deletion initiated"; fi)
- Datastream Resources: $(if [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deleted"; fi)
- Cloud SQL Instances: $(if [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deleted"; fi)
- Artifact Registry: $(if [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deleted"; fi)
- Cloud Workflows: $(if [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deleted"; fi)
- Security Policies: $(if [[ "$DRY_RUN" == true ]]; then echo "Would reset"; else echo "Reset"; fi)
- Storage Buckets: $(if [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deleted"; fi)
- Local Files: $(if [[ "$DRY_RUN" == true ]]; then echo "Would clean"; else echo "Cleaned"; fi)
- Project: $(if [[ "$KEEP_PROJECT" == true ]]; then echo "Preserved"; elif [[ "$DRY_RUN" == true ]]; then echo "Would delete"; else echo "Deletion initiated"; fi)

Log File: $LOG_FILE

Notes:
- Cloud Composer environment deletion may take 10-15 minutes to complete
- Project deletion (if initiated) may take several minutes
- Check GCP Console for final operation status
- Some operations may have failed - check the log file for details

Post-Cleanup Actions:
- Verify all resources are deleted in GCP Console
- Check billing to confirm charges have stopped
- Remove any remaining local files manually if needed
EOF

    success "Cleanup report generated: $report_file"
}

main() {
    info "Starting Development Lifecycle Automation cleanup..."
    info "Log file: $LOG_FILE"
    
    # Cleanup operations
    check_prerequisites
    detect_resources
    list_resources_to_delete
    confirm_cleanup
    
    info "Beginning resource cleanup..."
    
    # Delete resources in proper order (reverse of creation)
    delete_composer_environment
    delete_datastream_resources
    delete_database_instances
    delete_artifact_registry
    delete_workflows
    delete_security_policies
    delete_storage_buckets
    clean_local_files
    
    # Delete project if requested
    if [[ "$KEEP_PROJECT" == false ]]; then
        delete_project
    fi
    
    wait_for_operations
    generate_cleanup_report
    
    success "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == true ]]; then
        info "This was a dry run - no resources were actually deleted"
        info "Run without --dry-run to perform actual cleanup"
    else
        success "All cleanup operations have been initiated"
        warn "Some operations may still be running - check GCP Console for final status"
        
        if [[ "$KEEP_PROJECT" == false ]]; then
            warn "Project deletion initiated - this may take several minutes"
        fi
    fi
}

# Make script executable and run main function
chmod +x "$0"
main "$@"
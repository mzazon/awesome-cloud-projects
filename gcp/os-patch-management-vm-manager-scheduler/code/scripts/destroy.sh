#!/bin/bash

#########################################################################
# GCP OS Patch Management with VM Manager and Cloud Scheduler
# Cleanup/Destroy Script
#
# This script safely removes all resources created by the deployment
# script, including VM instances, Cloud Functions, Storage buckets,
# and monitoring resources.
#
# Author: Generated from Recipe b7e4f8c2
# Version: 1.0
#########################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.deploy_config"

# Variables
DRY_RUN=false
FORCE=false
KEEP_PROJECT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run      Show what would be deleted without actually deleting"
            echo "  --force        Skip confirmation prompts"
            echo "  --keep-project Don't delete the GCP project"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "Loading configuration from $CONFIG_FILE"
    else
        error "Configuration file not found: $CONFIG_FILE"
        error "Please ensure the deployment was completed successfully."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project $PROJECT_ID does not exist or is not accessible."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    success "Prerequisites check completed"
}

# Display cleanup summary
show_cleanup_summary() {
    log "Cleanup Configuration Summary:"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "VM Count: $VM_COUNT"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Function Name: $FUNCTION_NAME"
    echo "Scheduler Job: $SCHEDULER_JOB_NAME"
    echo "Keep Project: $KEEP_PROJECT"
    echo "Dry Run: $DRY_RUN"
    echo "Force: $FORCE"
    echo "=================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE: No resources will be actually deleted"
        echo ""
    fi
    
    if [[ "$FORCE" == "false" ]]; then
        echo "The following resources will be deleted:"
        echo "- VM instances (patch-test-vm-1 to patch-test-vm-$VM_COUNT)"
        echo "- Cloud Function ($FUNCTION_NAME)"
        echo "- Cloud Scheduler job ($SCHEDULER_JOB_NAME)"
        echo "- Cloud Storage bucket ($BUCKET_NAME)"
        echo "- Monitoring dashboard and alert policies"
        echo "- Local configuration files"
        if [[ "$KEEP_PROJECT" == "false" ]]; then
            echo "- GCP Project ($PROJECT_ID)"
        fi
        echo ""
        
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user."
            exit 0
        fi
    fi
}

# Execute command with dry run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would execute: $cmd"
        log "[DRY RUN] $description"
    else
        log "Executing: $description"
        if eval "$cmd"; then
            success "$description completed"
        else
            warning "$description failed (this may be expected if resource doesn't exist)"
        fi
    fi
}

# Delete Cloud Scheduler job
delete_scheduler_job() {
    log "Deleting Cloud Scheduler job..."
    
    if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$REGION" &> /dev/null; then
        execute_cmd "gcloud scheduler jobs delete '$SCHEDULER_JOB_NAME' --location='$REGION' --quiet" \
                   "Delete Cloud Scheduler job: $SCHEDULER_JOB_NAME"
    else
        warning "Cloud Scheduler job $SCHEDULER_JOB_NAME not found"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        execute_cmd "gcloud functions delete '$FUNCTION_NAME' --region='$REGION' --quiet" \
                   "Delete Cloud Function: $FUNCTION_NAME"
    else
        warning "Cloud Function $FUNCTION_NAME not found"
    fi
}

# Delete VM instances
delete_vm_instances() {
    log "Deleting VM instances..."
    
    for ((i=1; i<=VM_COUNT; i++)); do
        local vm_name="patch-test-vm-${i}"
        
        if gcloud compute instances describe "$vm_name" --zone="$ZONE" &> /dev/null; then
            execute_cmd "gcloud compute instances delete '$vm_name' --zone='$ZONE' --quiet" \
                       "Delete VM instance: $vm_name"
        else
            warning "VM instance $vm_name not found"
        fi
    done
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        execute_cmd "gsutil -m rm -r 'gs://$BUCKET_NAME'" \
                   "Delete Cloud Storage bucket: $BUCKET_NAME"
    else
        warning "Cloud Storage bucket $BUCKET_NAME not found"
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete monitoring dashboard
    local dashboard_id
    dashboard_id=$(gcloud monitoring dashboards list \
        --filter="displayName:'VM Patch Management Dashboard'" \
        --format="value(name)" 2>/dev/null | head -n1)
    
    if [[ -n "$dashboard_id" ]]; then
        execute_cmd "gcloud monitoring dashboards delete '$dashboard_id' --quiet" \
                   "Delete monitoring dashboard"
    else
        warning "Monitoring dashboard not found"
    fi
    
    # Delete alert policies
    local policy_id
    policy_id=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Patch Deployment Failure Alert'" \
        --format="value(name)" 2>/dev/null | head -n1)
    
    if [[ -n "$policy_id" ]]; then
        execute_cmd "gcloud alpha monitoring policies delete '$policy_id' --quiet" \
                   "Delete alert policy"
    else
        warning "Alert policy not found"
    fi
}

# Delete local files
delete_local_files() {
    log "Deleting local files..."
    
    local files_to_delete=(
        "$CONFIG_FILE"
        "${SCRIPT_DIR}/pre-patch-backup.sh"
        "${SCRIPT_DIR}/post-patch-validation.sh"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/alert-policy.yaml"
        "${SCRIPT_DIR}/../patch-function"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -e "$file" ]]; then
            execute_cmd "rm -rf '$file'" "Delete local file/directory: $file"
        else
            warning "Local file/directory not found: $file"
        fi
    done
}

# Delete GCP project
delete_project() {
    if [[ "$KEEP_PROJECT" == "false" ]]; then
        log "Deleting GCP project..."
        
        if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[DRY RUN] Would delete project: $PROJECT_ID"
            else
                warning "About to delete project: $PROJECT_ID"
                warning "This action cannot be undone!"
                
                if [[ "$FORCE" == "false" ]]; then
                    read -p "Type the project ID to confirm deletion: " -r
                    if [[ "$REPLY" != "$PROJECT_ID" ]]; then
                        error "Project ID mismatch. Skipping project deletion."
                        return 1
                    fi
                fi
                
                execute_cmd "gcloud projects delete '$PROJECT_ID' --quiet" \
                           "Delete GCP project: $PROJECT_ID"
            fi
        else
            warning "Project $PROJECT_ID not found"
        fi
    else
        log "Keeping GCP project as requested"
    fi
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run completed. No resources were actually deleted."
        return 0
    fi
    
    log "Verifying cleanup..."
    
    # Check if resources still exist
    local remaining_resources=()
    
    # Check VM instances
    for ((i=1; i<=VM_COUNT; i++)); do
        local vm_name="patch-test-vm-${i}"
        if gcloud compute instances describe "$vm_name" --zone="$ZONE" &> /dev/null; then
            remaining_resources+=("VM instance: $vm_name")
        fi
    done
    
    # Check Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        remaining_resources+=("Cloud Function: $FUNCTION_NAME")
    fi
    
    # Check Cloud Scheduler job
    if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$REGION" &> /dev/null; then
        remaining_resources+=("Cloud Scheduler job: $SCHEDULER_JOB_NAME")
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        remaining_resources+=("Cloud Storage bucket: $BUCKET_NAME")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            echo "  - $resource"
        done
    fi
}

# Main cleanup function
main() {
    log "Starting GCP OS Patch Management cleanup..."
    
    # Run cleanup steps
    load_config
    check_prerequisites
    show_cleanup_summary
    
    # Delete resources in reverse order of creation
    delete_monitoring_resources
    delete_scheduler_job
    delete_cloud_function
    delete_storage_bucket
    delete_vm_instances
    delete_local_files
    delete_project
    
    verify_cleanup
    
    # Display completion summary
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry run completed successfully!"
        echo ""
        echo "=== Dry Run Summary ==="
        echo "No resources were actually deleted."
        echo "Run without --dry-run to perform actual cleanup."
    else
        success "Cleanup completed successfully!"
        echo ""
        echo "=== Cleanup Summary ==="
        echo "All resources have been removed from project: $PROJECT_ID"
        if [[ "$KEEP_PROJECT" == "false" ]]; then
            echo "Project deletion initiated (may take a few minutes to complete)"
        else
            echo "Project preserved as requested"
        fi
        echo "Local configuration files have been removed"
    fi
    echo ""
    
    success "Cleanup process completed!"
}

# Run main function
main "$@"
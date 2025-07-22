#!/bin/bash

# Destroy script for Secure Remote Development Access with Cloud Identity-Aware Proxy and Cloud Code
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Error handler
error_handler() {
    local line_no=$1
    log_error "Script failed at line $line_no"
    log_error "Some resources may not have been cleaned up"
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/deployment-state.env"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy secure remote development environment created by deploy.sh.

OPTIONS:
    -p, --project-id PROJECT_ID    Specify project ID to destroy (optional if state file exists)
    -f, --force                   Skip confirmation prompts
    -k, --keep-project            Keep the project, only delete resources within it
    -h, --help                    Show this help message
    --dry-run                     Show what would be destroyed without executing

EXAMPLES:
    $0                           # Destroy using saved deployment state
    $0 -p my-project-123         # Destroy specific project
    $0 -f                        # Force destroy without confirmation
    $0 --dry-run                 # Preview what would be destroyed

SAFETY FEATURES:
    - Confirmation prompts before destructive actions
    - Graceful handling of missing resources
    - Detailed logging of all operations
    - Option to preserve project while cleaning resources

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -k|--keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        # Source the deployment state file
        # shellcheck source=/dev/null
        source "$DEPLOYMENT_STATE_FILE"
        
        log_success "Deployment state loaded from file"
        log_info "Project ID: $PROJECT_ID"
        log_info "Region: $REGION"
        log_info "Zone: $ZONE"
        log_info "Deployment date: $DEPLOYMENT_DATE"
    elif [[ -z "$PROJECT_ID" ]]; then
        log_error "No deployment state file found and no project ID provided"
        log_error "Use -p PROJECT_ID to specify the project to destroy"
        exit 1
    else
        log_warning "No deployment state file found, using provided project ID: $PROJECT_ID"
        # Set defaults for missing variables
        REGION=${REGION:-"us-central1"}
        ZONE=${ZONE:-"us-central1-a"}
    fi
    
    # Ensure project ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID not found in state file or provided via command line"
        exit 1
    fi
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID does not exist or is not accessible"
        log_warning "It may have already been deleted"
        return
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    log_success "Prerequisites check passed"
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete the following resources:"
    log_warning "- Project: $PROJECT_ID"
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log_warning "  (Project will be preserved, only resources deleted)"
    fi
    log_warning "- All Compute Engine instances and disks"
    log_warning "- All Artifact Registry repositories and images"
    log_warning "- All firewall rules created by deployment"
    log_warning "- All IAM policy bindings"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be actually destroyed"
        return
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_info "Destruction confirmed, proceeding..."
}

# List resources to be destroyed
list_resources() {
    log_info "Discovering resources to destroy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would discover and list resources in project: $PROJECT_ID"
        return
    fi
    
    # List Compute Engine instances
    log_info "Compute Engine instances:"
    if gcloud compute instances list --filter="tags.items:dev-environment" --format="table(name,zone,status)" --quiet; then
        : # Command succeeded
    else
        log_info "  No Compute Engine instances found"
    fi
    
    # List Artifact Registry repositories
    log_info "Artifact Registry repositories:"
    if gcloud artifacts repositories list --format="table(name,location,format)" --quiet; then
        : # Command succeeded
    else
        log_info "  No Artifact Registry repositories found"
    fi
    
    # List firewall rules
    log_info "Firewall rules:"
    if gcloud compute firewall-rules list --filter="name:allow-iap-ssh" --format="table(name,direction,priority)" --quiet; then
        : # Command succeeded
    else
        log_info "  No custom firewall rules found"
    fi
}

# Delete Compute Engine resources
delete_compute_resources() {
    log_info "Deleting Compute Engine resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Compute Engine instances and firewall rules"
        return
    fi
    
    # Delete VM instance if it exists
    if [[ -n "$VM_NAME" ]]; then
        if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
            log_info "Deleting VM instance: $VM_NAME"
            gcloud compute instances delete "$VM_NAME" \
                --zone="$ZONE" \
                --quiet
            log_success "VM instance deleted: $VM_NAME"
        else
            log_info "VM instance not found: $VM_NAME"
        fi
    else
        # Try to find and delete dev environment VMs
        log_info "Searching for development environment VMs..."
        VM_LIST=$(gcloud compute instances list \
            --filter="tags.items:dev-environment" \
            --format="value(name,zone)" \
            --quiet 2>/dev/null || true)
        
        if [[ -n "$VM_LIST" ]]; then
            while IFS=$'\t' read -r vm_name vm_zone; do
                if [[ -n "$vm_name" && -n "$vm_zone" ]]; then
                    log_info "Deleting VM: $vm_name in zone $vm_zone"
                    gcloud compute instances delete "$vm_name" \
                        --zone="$vm_zone" \
                        --quiet
                fi
            done <<< "$VM_LIST"
        else
            log_info "No development environment VMs found"
        fi
    fi
    
    # Delete firewall rule
    if gcloud compute firewall-rules describe allow-iap-ssh &>/dev/null; then
        log_info "Deleting firewall rule: allow-iap-ssh"
        gcloud compute firewall-rules delete allow-iap-ssh --quiet
        log_success "Firewall rule deleted: allow-iap-ssh"
    else
        log_info "Firewall rule not found: allow-iap-ssh"
    fi
}

# Delete Artifact Registry resources
delete_artifact_registry() {
    log_info "Deleting Artifact Registry resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Artifact Registry repositories and images"
        return
    fi
    
    # Delete specific repository if known
    if [[ -n "$REPO_NAME" && -n "$REGION" ]]; then
        if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" &>/dev/null; then
            log_info "Deleting Artifact Registry repository: $REPO_NAME"
            gcloud artifacts repositories delete "$REPO_NAME" \
                --location="$REGION" \
                --quiet
            log_success "Artifact Registry repository deleted: $REPO_NAME"
        else
            log_info "Artifact Registry repository not found: $REPO_NAME"
        fi
    else
        # Find and delete all repositories in the project
        log_info "Searching for Artifact Registry repositories..."
        REPO_LIST=$(gcloud artifacts repositories list \
            --format="value(name,location)" \
            --quiet 2>/dev/null || true)
        
        if [[ -n "$REPO_LIST" ]]; then
            while IFS=$'\t' read -r repo_name repo_location; do
                if [[ -n "$repo_name" && -n "$repo_location" ]]; then
                    # Extract repository name from full path
                    repo_short_name=$(basename "$repo_name")
                    log_info "Deleting repository: $repo_short_name in location $repo_location"
                    gcloud artifacts repositories delete "$repo_short_name" \
                        --location="$repo_location" \
                        --quiet
                fi
            done <<< "$REPO_LIST"
        else
            log_info "No Artifact Registry repositories found"
        fi
    fi
}

# Remove IAM policy bindings
remove_iam_policies() {
    log_info "Removing IAM policy bindings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove IAM policy bindings"
        return
    fi
    
    # Get current user email
    USER_EMAIL=$(gcloud config get-value account 2>/dev/null || echo "")
    
    if [[ -n "$USER_EMAIL" ]]; then
        # Remove project-level IAM bindings
        log_info "Removing project-level IAM bindings for $USER_EMAIL"
        
        # List of roles that may have been granted
        ROLES_TO_REMOVE=(
            "roles/compute.instanceAdmin"
            "roles/artifactregistry.writer"
            "roles/iap.tunnelResourceAccessor"
        )
        
        for role in "${ROLES_TO_REMOVE[@]}"; do
            if gcloud projects get-iam-policy "$PROJECT_ID" \
                --flatten="bindings[].members" \
                --filter="bindings.role:$role AND bindings.members:user:$USER_EMAIL" \
                --format="value(bindings.role)" | grep -q "$role"; then
                
                log_info "Removing role binding: $role"
                gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                    --member="user:$USER_EMAIL" \
                    --role="$role" \
                    --quiet 2>/dev/null || log_warning "Failed to remove role: $role"
            fi
        done
    else
        log_warning "Could not determine user email for IAM cleanup"
    fi
    
    log_success "IAM policy cleanup completed"
}

# Disable APIs
disable_apis() {
    log_info "Disabling APIs to prevent further charges..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would disable APIs"
        return
    fi
    
    # APIs that were enabled during deployment
    APIS_TO_DISABLE=(
        "iap.googleapis.com"
        "compute.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${APIS_TO_DISABLE[@]}"; do
        if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            log_info "Disabling API: $api"
            gcloud services disable "$api" --quiet 2>/dev/null || log_warning "Failed to disable API: $api"
        fi
    done
    
    log_success "APIs disabled"
}

# Delete OAuth and IAP configuration
cleanup_iap_oauth() {
    log_info "Cleaning up IAP and OAuth configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up OAuth brands and IAP configuration"
        return
    fi
    
    # Note: OAuth brands cannot be deleted via CLI
    log_warning "OAuth brands cannot be deleted programmatically"
    log_warning "Manual cleanup required:"
    log_warning "1. Go to: https://console.cloud.google.com/apis/credentials?project=$PROJECT_ID"
    log_warning "2. Remove any OAuth 2.0 client IDs if no longer needed"
    log_warning "3. OAuth consent screen will remain (shared across projects)"
    
    log_success "IAP cleanup guidance provided"
}

# Remove local configuration files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return
    fi
    
    # Remove VS Code configuration if it exists
    if [[ -d ".vscode" ]]; then
        log_info "Removing VS Code configuration directory"
        rm -rf .vscode
    fi
    
    # Remove audit policy file if it exists
    if [[ -f "audit-policy.yaml" ]]; then
        log_info "Removing audit policy file"
        rm -f audit-policy.yaml
    fi
    
    # Remove deployment state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_info "Removing deployment state file"
        rm -f "$DEPLOYMENT_STATE_FILE"
    fi
    
    log_success "Local files cleaned up"
}

# Delete the entire project
delete_project() {
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log_info "Keeping project as requested: $PROJECT_ID"
        return
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return
    fi
    
    # Final confirmation for project deletion
    if [[ "$FORCE" != "true" ]]; then
        echo ""
        log_warning "⚠️  FINAL WARNING: About to delete entire project ⚠️"
        log_warning "Project: $PROJECT_ID"
        log_warning "This action cannot be undone!"
        echo ""
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed"
            log_error "Expected: $PROJECT_ID"
            log_error "Received: $project_confirmation"
            exit 1
        fi
    fi
    
    # Delete the project
    gcloud projects delete "$PROJECT_ID" --quiet
    
    log_success "Project deletion initiated: $PROJECT_ID"
    log_info "Project deletion may take several minutes to complete"
}

# Main destruction function
main() {
    log_info "Starting secure remote development environment destruction..."
    log_info "Script: $0"
    log_info "Working directory: $(pwd)"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Load deployment state
    load_deployment_state
    
    # Check prerequisites
    check_prerequisites
    
    # Show what will be destroyed
    list_resources
    
    # Confirm destruction
    confirm_destruction
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be actually destroyed"
    fi
    
    # Execute destruction steps in reverse order of creation
    log_info "Beginning resource destruction..."
    
    # Remove local files first (safest)
    cleanup_local_files
    
    # Remove cloud resources
    remove_iam_policies
    delete_compute_resources
    delete_artifact_registry
    cleanup_iap_oauth
    
    # Disable APIs if keeping project
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        disable_apis
    fi
    
    # Delete project (if requested)
    delete_project
    
    # Display completion message
    log_success "Destruction completed successfully!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        if [[ "$KEEP_PROJECT" == "true" ]]; then
            log_info "Project preserved: $PROJECT_ID"
            log_info "All resources within the project have been deleted"
        else
            log_info "Project deleted: $PROJECT_ID"
            log_info "All resources have been permanently removed"
        fi
        echo ""
        log_info "Destruction summary:"
        log_info "- Compute Engine instances: Deleted"
        log_info "- Artifact Registry repositories: Deleted"
        log_info "- Firewall rules: Deleted"
        log_info "- IAM policy bindings: Removed"
        log_info "- Local configuration files: Removed"
        
        if [[ "$KEEP_PROJECT" != "true" ]]; then
            log_info "- Project: Deleted"
        fi
        
        echo ""
        log_warning "Manual cleanup required:"
        log_warning "- OAuth consent screen configuration (if no longer needed)"
        log_warning "- Any custom OAuth clients in Cloud Console"
    fi
}

# Execute main function with all arguments
main "$@"
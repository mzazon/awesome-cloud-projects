#!/bin/bash

# Application Debugging Workflows with Cloud Debugger and Cloud Workstations - Destroy Script
# This script removes all resources created by the deployment script including:
# - Cloud Workstations cluster and configuration
# - Artifact Registry repository and images
# - Sample Cloud Run application
# - Monitoring and logging configuration

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

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_info "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log_info "Force delete mode enabled - skipping confirmation prompts"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd"; then
        log_success "$description completed"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "$description failed, but continuing..."
            return 0
        else
            log_error "$description failed"
            return 1
        fi
    fi
}

# Function to load deployment state
load_deployment_state() {
    local state_file=".deployment_state"
    
    if [[ -f "$state_file" ]]; then
        log_info "Loading deployment state from $state_file"
        source "$state_file"
        log_success "Deployment state loaded"
    else
        log_warning "No deployment state file found. Using environment variables or defaults."
        
        # Set default values if not provided
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
        export WORKSTATION_CLUSTER="${WORKSTATION_CLUSTER:-}"
        export WORKSTATION_CONFIG="${WORKSTATION_CONFIG:-}"
        export REPOSITORY_NAME="${REPOSITORY_NAME:-}"
        export SERVICE_NAME="${SERVICE_NAME:-}"
        export WORKSTATION_NAME="${WORKSTATION_NAME:-}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "PROJECT_ID not found in environment or state file"
            exit 1
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will delete the following resources:"
    echo "- Project: ${PROJECT_ID}"
    echo "- Region: ${REGION}"
    echo "- Workstation Cluster: ${WORKSTATION_CLUSTER}"
    echo "- Workstation Config: ${WORKSTATION_CONFIG}"
    echo "- Workstation Instance: ${WORKSTATION_NAME}"
    echo "- Artifact Registry: ${REPOSITORY_NAME}"
    echo "- Sample App Service: ${SERVICE_NAME}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Set gcloud defaults
    if [[ -n "$PROJECT_ID" ]]; then
        execute_command "gcloud config set project ${PROJECT_ID}" "Setting default project"
    fi
    
    if [[ -n "$REGION" ]]; then
        execute_command "gcloud config set compute/region ${REGION}" "Setting default region"
    fi
    
    if [[ -n "$ZONE" ]]; then
        execute_command "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to wait for workstation to stop
wait_for_workstation_stopped() {
    local max_attempts=20
    local attempt=0
    
    log_info "Waiting for workstation to stop..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would check workstation state"
            break
        fi
        
        local state=$(gcloud workstations describe ${WORKSTATION_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER} \
            --config=${WORKSTATION_CONFIG} \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "STOPPED" ]] || [[ "$state" == "UNKNOWN" ]]; then
            log_success "Workstation stopped or not found"
            break
        fi
        
        log_info "Workstation state: $state (attempt $((attempt + 1))/$max_attempts)"
        sleep 15
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts && "$DRY_RUN" == "false" ]]; then
        log_warning "Timeout waiting for workstation to stop, proceeding with deletion"
    fi
}

# Function to wait for cluster to be deleted
wait_for_cluster_deletion() {
    local max_attempts=30
    local attempt=0
    
    log_info "Waiting for cluster deletion to complete..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would check cluster deletion state"
            break
        fi
        
        if ! gcloud workstations clusters describe ${WORKSTATION_CLUSTER} \
            --location=${REGION} &>/dev/null; then
            log_success "Cluster deletion completed"
            break
        fi
        
        log_info "Cluster still exists (attempt $((attempt + 1))/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts && "$DRY_RUN" == "false" ]]; then
        log_warning "Timeout waiting for cluster deletion, but proceeding"
    fi
}

# Function to delete workstation instance
delete_workstation_instance() {
    log_info "Deleting workstation instance..."
    
    if [[ -n "$WORKSTATION_NAME" ]]; then
        # Stop workstation first
        execute_command "gcloud workstations stop ${WORKSTATION_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER} \
            --config=${WORKSTATION_CONFIG} \
            --quiet" \
            "Stopping workstation instance" true
        
        # Wait for workstation to stop
        wait_for_workstation_stopped
        
        # Delete workstation instance
        execute_command "gcloud workstations delete ${WORKSTATION_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER} \
            --config=${WORKSTATION_CONFIG} \
            --quiet" \
            "Deleting workstation instance" true
        
        log_success "Workstation instance deletion initiated"
    else
        log_warning "No workstation instance name found, skipping"
    fi
}

# Function to delete workstation configuration
delete_workstation_config() {
    log_info "Deleting workstation configuration..."
    
    if [[ -n "$WORKSTATION_CONFIG" ]] && [[ -n "$WORKSTATION_CLUSTER" ]]; then
        execute_command "gcloud workstations configs delete ${WORKSTATION_CONFIG} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER} \
            --quiet" \
            "Deleting workstation configuration" true
        
        log_success "Workstation configuration deletion initiated"
    else
        log_warning "No workstation configuration or cluster name found, skipping"
    fi
}

# Function to delete workstation cluster
delete_workstation_cluster() {
    log_info "Deleting workstation cluster..."
    
    if [[ -n "$WORKSTATION_CLUSTER" ]]; then
        execute_command "gcloud workstations clusters delete ${WORKSTATION_CLUSTER} \
            --location=${REGION} \
            --quiet" \
            "Deleting workstation cluster" true
        
        # Wait for cluster deletion to complete
        wait_for_cluster_deletion
        
        log_success "Workstation cluster deletion initiated"
    else
        log_warning "No workstation cluster name found, skipping"
    fi
}

# Function to delete sample application
delete_sample_app() {
    log_info "Deleting sample application..."
    
    if [[ -n "$SERVICE_NAME" ]]; then
        execute_command "gcloud run services delete ${SERVICE_NAME} \
            --region=${REGION} \
            --quiet" \
            "Deleting Cloud Run service" true
        
        # Delete container image from Container Registry
        execute_command "gcloud container images delete gcr.io/${PROJECT_ID}/${SERVICE_NAME} \
            --quiet" \
            "Deleting container image from Container Registry" true
        
        log_success "Sample application deleted"
    else
        log_warning "No service name found, skipping"
    fi
}

# Function to delete Artifact Registry repository
delete_artifact_registry() {
    log_info "Deleting Artifact Registry repository..."
    
    if [[ -n "$REPOSITORY_NAME" ]]; then
        execute_command "gcloud artifacts repositories delete ${REPOSITORY_NAME} \
            --location=${REGION} \
            --quiet" \
            "Deleting Artifact Registry repository" true
        
        log_success "Artifact Registry repository deleted"
    else
        log_warning "No repository name found, skipping"
    fi
}

# Function to delete monitoring and logging resources
delete_monitoring_logging() {
    log_info "Deleting monitoring and logging resources..."
    
    # Delete logging sink
    execute_command "gcloud logging sinks delete workstation-debug-sink \
        --quiet" \
        "Deleting Cloud Logging sink" true
    
    # Delete Pub/Sub topic
    execute_command "gcloud pubsub topics delete debug-activities \
        --quiet" \
        "Deleting Pub/Sub topic" true
    
    log_success "Monitoring and logging resources deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        ".deployment_state"
        "debug-dashboard.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would remove: $file"
            else
                rm -f "$file"
                log_success "Removed: $file"
            fi
        fi
    done
    
    # Clean up temporary directories if they exist
    if [[ "$DRY_RUN" == "false" ]]; then
        local temp_dirs=(
            "/tmp/workstation_state.txt"
            "/tmp/cluster_state.txt"
        )
        
        for temp_file in "${temp_dirs[@]}"; do
            if [[ -f "$temp_file" ]]; then
                rm -f "$temp_file"
                log_success "Removed temp file: $temp_file"
            fi
        done
    fi
    
    log_success "Local cleanup completed"
}

# Function to clear environment variables
clear_environment() {
    log_info "Clearing environment variables..."
    
    local vars_to_unset=(
        "PROJECT_ID"
        "REGION"
        "ZONE"
        "RANDOM_SUFFIX"
        "WORKSTATION_CLUSTER"
        "WORKSTATION_CONFIG"
        "REPOSITORY_NAME"
        "SERVICE_NAME"
        "WORKSTATION_NAME"
        "IMAGE_URI"
        "SERVICE_URL"
        "WORKSTATION_URL"
    )
    
    for var in "${vars_to_unset[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would unset: $var"
        else
            unset "$var"
        fi
    done
    
    log_success "Environment variables cleared"
}

# Function to display destruction summary
display_summary() {
    log_success "Destruction completed successfully!"
    echo ""
    echo "=== Resources Removed ==="
    echo "- Workstation Instance: ${WORKSTATION_NAME:-N/A}"
    echo "- Workstation Config: ${WORKSTATION_CONFIG:-N/A}"
    echo "- Workstation Cluster: ${WORKSTATION_CLUSTER:-N/A}"
    echo "- Artifact Registry: ${REPOSITORY_NAME:-N/A}"
    echo "- Sample App Service: ${SERVICE_NAME:-N/A}"
    echo "- Monitoring and Logging resources"
    echo "- Local state files"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "All debugging workflow resources have been removed."
        echo "Note: It may take a few minutes for all resources to be fully deleted."
        echo ""
        echo "To verify deletion, check the Google Cloud Console or run:"
        echo "  gcloud workstations clusters list --location=${REGION}"
        echo "  gcloud run services list --region=${REGION}"
        echo "  gcloud artifacts repositories list --location=${REGION}"
    else
        echo "This was a dry-run. No resources were actually deleted."
        echo "To perform the actual deletion, run this script without --dry-run"
    fi
}

# Function to handle script interruption
handle_interruption() {
    log_warning "Script interrupted. Some resources may still exist."
    log_info "You can re-run this script to continue cleanup."
    exit 1
}

# Main destruction function
main() {
    log_info "Starting Application Debugging Workflows cleanup..."
    
    # Trap interruption signals
    trap handle_interruption INT TERM
    
    # Trap errors (but don't exit immediately for cleanup scripts)
    trap 'log_error "An error occurred during cleanup. Some resources may still exist."' ERR
    
    load_deployment_state
    confirm_deletion
    check_prerequisites
    
    # Delete resources in reverse order of creation
    delete_workstation_instance
    delete_workstation_config
    delete_workstation_cluster
    delete_sample_app
    delete_artifact_registry
    delete_monitoring_logging
    cleanup_local_files
    clear_environment
    
    display_summary
    
    log_success "Cleanup script completed!"
}

# Run main function
main "$@"
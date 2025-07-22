#!/bin/bash

# =============================================================================
# GCP Serverless GPU Computing Pipelines Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script:
# - Cloud Run services (GPU and CPU)
# - Cloud Workflows pipelines
# - Eventarc triggers
# - Cloud Storage buckets and data
# - Service accounts and IAM bindings
# - Container images
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_REGION="us-central1"
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false
KEEP_IMAGES=false

# =============================================================================
# Helper Functions
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup GCP Serverless GPU Computing Pipeline resources

OPTIONS:
    -r, --region REGION     GCP region for cleanup (default: ${DEFAULT_REGION})
    -p, --project PROJECT   GCP project ID (default: current gcloud project)
    -s, --service-prefix PREFIX  Service prefix to identify resources
    -n, --dry-run           Show what would be deleted without making changes
    -y, --yes               Skip confirmation prompts
    -f, --force             Force deletion even if errors occur
    -k, --keep-images       Keep container images (don't delete from GCR)
    -h, --help              Show this help message

EXAMPLES:
    $0                                          # Interactive cleanup
    $0 --service-prefix ml-pipeline-abc123      # Cleanup specific deployment
    $0 --dry-run                               # Preview what would be deleted
    $0 --yes --force                           # Force cleanup without prompts
    $0 --region europe-west1 --project my-project  # Cleanup in specific region/project

SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Resource validation before deletion
    - Dry-run mode for preview
    - Detailed logging of all actions
    - Graceful handling of missing resources

EOF
}

confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_info "Auto-confirming: $message"
        return 0
    fi
    
    local response
    read -p "$message [y/N]: " response
    response=${response:-$default_response}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

find_resources_by_prefix() {
    local resource_type="$1"
    local prefix="$2"
    
    log_info "Searching for $resource_type resources with prefix: $prefix"
    
    case "$resource_type" in
        "cloud-run")
            gcloud run services list --region="$REGION" --format="value(metadata.name)" --filter="metadata.name:$prefix" 2>/dev/null || true
            ;;
        "workflows")
            gcloud workflows list --location="$REGION" --format="value(name)" --filter="name:$prefix" 2>/dev/null || true
            ;;
        "eventarc")
            gcloud eventarc triggers list --location="$REGION" --format="value(name)" --filter="name:$prefix" 2>/dev/null || true
            ;;
        "storage")
            gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "gs://$prefix" | sed 's|gs://||' | sed 's|/$||' || true
            ;;
        "service-accounts")
            gcloud iam service-accounts list --format="value(email)" --filter="email:$prefix" 2>/dev/null || true
            ;;
        "container-images")
            gcloud container images list --repository="gcr.io/$PROJECT_ID" --format="value(name)" --filter="name:$prefix" 2>/dev/null || true
            ;;
    esac
}

list_all_resources() {
    local prefix="$1"
    
    log_info "=== Resource Discovery ==="
    log_info "Searching for resources with prefix: $prefix"
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    echo
    
    # Find Cloud Run services
    local cloud_run_services
    cloud_run_services=$(find_resources_by_prefix "cloud-run" "$prefix")
    if [[ -n "$cloud_run_services" ]]; then
        log_info "Cloud Run Services found:"
        echo "$cloud_run_services" | while read -r service; do
            echo "  • $service"
        done
    else
        log_info "No Cloud Run services found"
    fi
    
    # Find Workflows
    local workflows
    workflows=$(find_resources_by_prefix "workflows" "$prefix")
    if [[ -n "$workflows" ]]; then
        log_info "Cloud Workflows found:"
        echo "$workflows" | while read -r workflow; do
            echo "  • $workflow"
        done
    else
        log_info "No Cloud Workflows found"
    fi
    
    # Find Eventarc triggers
    local eventarc_triggers
    eventarc_triggers=$(find_resources_by_prefix "eventarc" "$prefix")
    if [[ -n "$eventarc_triggers" ]]; then
        log_info "Eventarc Triggers found:"
        echo "$eventarc_triggers" | while read -r trigger; do
            echo "  • $trigger"
        done
    else
        log_info "No Eventarc triggers found"
    fi
    
    # Find Storage buckets
    local storage_buckets
    storage_buckets=$(find_resources_by_prefix "storage" "$prefix")
    if [[ -n "$storage_buckets" ]]; then
        log_info "Cloud Storage Buckets found:"
        echo "$storage_buckets" | while read -r bucket; do
            echo "  • $bucket"
        done
    else
        log_info "No Cloud Storage buckets found"
    fi
    
    # Find Service accounts
    local service_accounts
    service_accounts=$(find_resources_by_prefix "service-accounts" "$prefix")
    if [[ -n "$service_accounts" ]]; then
        log_info "Service Accounts found:"
        echo "$service_accounts" | while read -r account; do
            echo "  • $account"
        done
    else
        log_info "No Service Accounts found"
    fi
    
    # Find Container images
    if [[ "$KEEP_IMAGES" == "false" ]]; then
        local container_images
        container_images=$(find_resources_by_prefix "container-images" "$prefix")
        if [[ -n "$container_images" ]]; then
            log_info "Container Images found:"
            echo "$container_images" | while read -r image; do
                echo "  • $image"
            done
        else
            log_info "No Container Images found"
        fi
    else
        log_info "Container Images will be preserved (--keep-images flag)"
    fi
    
    echo
}

delete_cloud_run_services() {
    local prefix="$1"
    
    log_info "Deleting Cloud Run services..."
    
    local services
    services=$(find_resources_by_prefix "cloud-run" "$prefix")
    
    if [[ -z "$services" ]]; then
        log_info "No Cloud Run services found to delete"
        return 0
    fi
    
    echo "$services" | while read -r service; do
        if [[ -n "$service" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Cloud Run service: $service"
                continue
            fi
            
            log_info "Deleting Cloud Run service: $service"
            if gcloud run services delete "$service" \
                --region="$REGION" \
                --quiet; then
                log_success "Deleted Cloud Run service: $service"
            else
                log_error "Failed to delete Cloud Run service: $service"
                if [[ "$FORCE_DELETE" == "false" ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

delete_workflows() {
    local prefix="$1"
    
    log_info "Deleting Cloud Workflows..."
    
    local workflows
    workflows=$(find_resources_by_prefix "workflows" "$prefix")
    
    if [[ -z "$workflows" ]]; then
        log_info "No Cloud Workflows found to delete"
        return 0
    fi
    
    echo "$workflows" | while read -r workflow; do
        if [[ -n "$workflow" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Cloud Workflow: $workflow"
                continue
            fi
            
            log_info "Deleting Cloud Workflow: $workflow"
            if gcloud workflows delete "$workflow" \
                --location="$REGION" \
                --quiet; then
                log_success "Deleted Cloud Workflow: $workflow"
            else
                log_error "Failed to delete Cloud Workflow: $workflow"
                if [[ "$FORCE_DELETE" == "false" ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

delete_eventarc_triggers() {
    local prefix="$1"
    
    log_info "Deleting Eventarc triggers..."
    
    local triggers
    triggers=$(find_resources_by_prefix "eventarc" "$prefix")
    
    if [[ -z "$triggers" ]]; then
        log_info "No Eventarc triggers found to delete"
        return 0
    fi
    
    echo "$triggers" | while read -r trigger; do
        if [[ -n "$trigger" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Eventarc trigger: $trigger"
                continue
            fi
            
            log_info "Deleting Eventarc trigger: $trigger"
            if gcloud eventarc triggers delete "$trigger" \
                --location="$REGION" \
                --quiet; then
                log_success "Deleted Eventarc trigger: $trigger"
            else
                log_error "Failed to delete Eventarc trigger: $trigger"
                if [[ "$FORCE_DELETE" == "false" ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

delete_storage_buckets() {
    local prefix="$1"
    
    log_info "Deleting Cloud Storage buckets..."
    
    local buckets
    buckets=$(find_resources_by_prefix "storage" "$prefix")
    
    if [[ -z "$buckets" ]]; then
        log_info "No Cloud Storage buckets found to delete"
        return 0
    fi
    
    echo "$buckets" | while read -r bucket; do
        if [[ -n "$bucket" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Cloud Storage bucket: gs://$bucket"
                continue
            fi
            
            log_info "Deleting Cloud Storage bucket: gs://$bucket"
            
            # Check if bucket has versioning enabled
            local versioning_enabled
            versioning_enabled=$(gsutil versioning get "gs://$bucket" 2>/dev/null | grep -c "Enabled" || echo "0")
            
            if [[ "$versioning_enabled" -gt 0 ]]; then
                log_info "Bucket has versioning enabled, removing all versions..."
                if ! gsutil -m rm -r "gs://$bucket/**" 2>/dev/null; then
                    log_warning "Failed to remove some objects from bucket: gs://$bucket"
                fi
            fi
            
            # Force remove all objects and the bucket
            if gsutil -m rm -r "gs://$bucket" 2>/dev/null; then
                log_success "Deleted Cloud Storage bucket: gs://$bucket"
            else
                log_error "Failed to delete Cloud Storage bucket: gs://$bucket"
                if [[ "$FORCE_DELETE" == "false" ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

delete_service_accounts() {
    local prefix="$1"
    
    log_info "Deleting service accounts..."
    
    local service_accounts
    service_accounts=$(find_resources_by_prefix "service-accounts" "$prefix")
    
    if [[ -z "$service_accounts" ]]; then
        log_info "No service accounts found to delete"
        return 0
    fi
    
    echo "$service_accounts" | while read -r account; do
        if [[ -n "$account" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete service account: $account"
                continue
            fi
            
            log_info "Deleting service account: $account"
            
            # Remove IAM policy bindings first
            local roles=(
                "roles/workflows.invoker"
                "roles/eventarc.eventReceiver"
                "roles/run.invoker"
            )
            
            for role in "${roles[@]}"; do
                if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                    --member "serviceAccount:$account" \
                    --role "$role" \
                    --quiet 2>/dev/null; then
                    log_info "Removed IAM binding: $role from $account"
                fi
            done
            
            # Delete service account
            if gcloud iam service-accounts delete "$account" \
                --quiet; then
                log_success "Deleted service account: $account"
            else
                log_error "Failed to delete service account: $account"
                if [[ "$FORCE_DELETE" == "false" ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

delete_container_images() {
    local prefix="$1"
    
    if [[ "$KEEP_IMAGES" == "true" ]]; then
        log_info "Skipping container image deletion (--keep-images flag)"
        return 0
    fi
    
    log_info "Deleting container images..."
    
    local images
    images=$(find_resources_by_prefix "container-images" "$prefix")
    
    if [[ -z "$images" ]]; then
        log_info "No container images found to delete"
        return 0
    fi
    
    echo "$images" | while read -r image; do
        if [[ -n "$image" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete container image: $image"
                continue
            fi
            
            log_info "Deleting container image: $image"
            if gcloud container images delete "$image" \
                --force-delete-tags \
                --quiet; then
                log_success "Deleted container image: $image"
            else
                log_error "Failed to delete container image: $image"
                if [[ "$FORCE_DELETE" == "false" ]]; then
                    exit 1
                fi
            fi
        fi
    done
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${PROJECT_ROOT}/workflow-definition.yaml"
        "${PROJECT_ROOT}/*.txt"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            if ls $file_pattern 2>/dev/null; then
                log_info "[DRY RUN] Would remove local files: $file_pattern"
            fi
            continue
        fi
        
        if ls $file_pattern 2>/dev/null; then
            log_info "Removing local files: $file_pattern"
            rm -f $file_pattern
        fi
    done
    
    log_success "Local files cleaned up"
}

verify_cleanup() {
    local prefix="$1"
    
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining resources
    local resource_types=("cloud-run" "workflows" "eventarc" "storage" "service-accounts")
    if [[ "$KEEP_IMAGES" == "false" ]]; then
        resource_types+=("container-images")
    fi
    
    for resource_type in "${resource_types[@]}"; do
        local resources
        resources=$(find_resources_by_prefix "$resource_type" "$prefix")
        if [[ -n "$resources" ]]; then
            log_warning "Remaining $resource_type resources:"
            echo "$resources" | while read -r resource; do
                echo "  • $resource"
            done
            remaining_resources=$((remaining_resources + 1))
        fi
    done
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
        return 0
    else
        log_warning "$remaining_resources resource type(s) still have remaining resources"
        return 1
    fi
}

display_cleanup_summary() {
    local prefix="$1"
    local start_time="$2"
    local end_time="$3"
    local duration=$((end_time - start_time))
    
    log_success "=== Cleanup Summary ==="
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Service Prefix: ${prefix}"
    echo "Cleanup Duration: ${duration} seconds"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually deleted"
    else
        echo "Cleanup Operations Completed:"
        echo "  • Cloud Run services deleted"
        echo "  • Cloud Workflows deleted"
        echo "  • Eventarc triggers deleted"
        echo "  • Cloud Storage buckets deleted"
        echo "  • Service accounts deleted"
        if [[ "$KEEP_IMAGES" == "false" ]]; then
            echo "  • Container images deleted"
        else
            echo "  • Container images preserved"
        fi
        echo "  • Local files cleaned up"
    fi
    echo
    
    if verify_cleanup "$prefix"; then
        log_success "Cleanup completed successfully!"
    else
        log_warning "Cleanup completed with some remaining resources"
        log_info "You may need to manually clean up remaining resources"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local start_time
    start_time=$(date +%s)
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -s|--service-prefix)
                SERVICE_PREFIX="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -k|--keep-images)
                KEEP_IMAGES=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    REGION="${REGION:-$DEFAULT_REGION}"
    PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

    # Validate inputs
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID not set. Use --project or set default project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi

    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet

    log_info "Starting cleanup of GCP Serverless GPU Computing Pipeline"
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    # If no service prefix provided, try to find resources
    if [[ -z "$SERVICE_PREFIX" ]]; then
        log_info "No service prefix provided. Searching for ml-pipeline resources..."
        
        # Look for Cloud Run services starting with ml-pipeline
        local found_services
        found_services=$(gcloud run services list --region="$REGION" --format="value(metadata.name)" --filter="metadata.name:ml-pipeline" 2>/dev/null || true)
        
        if [[ -n "$found_services" ]]; then
            log_info "Found ml-pipeline services. Attempting to extract prefix..."
            # Extract prefix from first service name
            SERVICE_PREFIX=$(echo "$found_services" | head -n1 | sed 's/-gpu-inference$//' | sed 's/-preprocess$//' | sed 's/-postprocess$//')
            log_info "Using detected service prefix: $SERVICE_PREFIX"
        else
            log_error "No service prefix provided and no ml-pipeline services found"
            log_error "Use --service-prefix to specify the prefix (e.g., ml-pipeline-abc123)"
            exit 1
        fi
    fi
    
    # List all resources that will be deleted
    list_all_resources "$SERVICE_PREFIX"
    
    # Confirmation prompt
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! confirm_action "Are you sure you want to delete all these resources?"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        echo
    fi
    
    # Execute cleanup steps in reverse order of creation
    delete_eventarc_triggers "$SERVICE_PREFIX"
    delete_workflows "$SERVICE_PREFIX"
    delete_cloud_run_services "$SERVICE_PREFIX"
    delete_service_accounts "$SERVICE_PREFIX"
    delete_storage_buckets "$SERVICE_PREFIX"
    delete_container_images "$SERVICE_PREFIX"
    cleanup_local_files
    
    # Display summary
    local end_time
    end_time=$(date +%s)
    display_cleanup_summary "$SERVICE_PREFIX" "$start_time" "$end_time"
}

# Error handling
trap 'log_error "Cleanup failed. Check the logs above for details."' ERR

# Run main function
main "$@"
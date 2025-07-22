#!/bin/bash

# Multi-Modal AI Content Generation with Lyria and Vertex AI - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/gcp-content-ai-destroy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load deployment state
load_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_info "Loading deployment state from $DEPLOYMENT_STATE_FILE"
        # Source the state file to load variables
        set -a  # automatically export all variables
        source "$DEPLOYMENT_STATE_FILE"
        set +a
        
        log_info "Loaded deployment configuration:"
        log_info "  PROJECT_ID: ${PROJECT_ID:-not set}"
        log_info "  REGION: ${REGION:-not set}"
        log_info "  BUCKET_NAME: ${BUCKET_NAME:-not set}"
        log_info "  SERVICE_ACCOUNT_NAME: ${SERVICE_ACCOUNT_NAME:-not set}"
    else
        log_warning "No deployment state file found at $DEPLOYMENT_STATE_FILE"
        log_warning "Cleanup will attempt to use environment variables or prompt for values"
    fi
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking cleanup prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables for cleanup
setup_cleanup_environment() {
    log_info "Setting up cleanup environment..."
    
    # Use values from deployment state or prompt user
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo -n "Enter PROJECT_ID to cleanup: "
        read -r PROJECT_ID
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
        log_info "Using default REGION: $REGION"
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" 2>/dev/null || {
        log_error "Failed to set project $PROJECT_ID. Please verify project exists and you have access."
        exit 1
    }
    gcloud config set compute/region "$REGION" 2>/dev/null
    
    log_info "Cleanup environment configured for project: $PROJECT_ID"
}

# Confirm destructive operation
confirm_destruction() {
    echo
    log_warning "==============================================="
    log_warning "DESTRUCTIVE OPERATION WARNING"
    log_warning "==============================================="
    log_warning "This script will permanently delete:"
    log_warning "  - All Cloud Functions"
    log_warning "  - All Cloud Run services"
    log_warning "  - Storage bucket and ALL its contents"
    log_warning "  - Service accounts and IAM bindings"
    log_warning "  - Monitoring metrics and policies"
    log_warning "  - All generated content and logs"
    log_warning "==============================================="
    echo
    
    # Skip confirmation if --force flag is provided
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "Force flag detected, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? Type 'yes' to continue: "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo -n "Enter the project ID '$PROJECT_ID' to confirm: "
    read -r project_confirmation
    
    if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
        log_error "Project ID confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    log_info "Destruction confirmed. Proceeding with cleanup..."
}

# Remove Cloud Functions
cleanup_functions() {
    log_info "Removing Cloud Functions..."
    
    local functions=("music-generation" "video-generation" "quality-assessment")
    
    for func in "${functions[@]}"; do
        log_info "Deleting function: $func"
        
        if gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
            gcloud functions delete "$func" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete function $func"
            log_success "Deleted function: $func"
        else
            log_info "Function $func not found or already deleted"
        fi
    done
    
    # Clean up local function code
    if [[ -d "${SCRIPT_DIR}/../functions" ]]; then
        rm -rf "${SCRIPT_DIR}/../functions"
        log_success "Removed local function code"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Remove Cloud Run services
cleanup_cloud_run() {
    log_info "Removing Cloud Run services..."
    
    local services=("content-orchestrator")
    
    for service in "${services[@]}"; do
        log_info "Deleting Cloud Run service: $service"
        
        if gcloud run services describe "$service" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
            gcloud run services delete "$service" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete Cloud Run service $service"
            log_success "Deleted Cloud Run service: $service"
        else
            log_info "Cloud Run service $service not found or already deleted"
        fi
    done
    
    # Clean up local service code
    if [[ -d "${SCRIPT_DIR}/../services" ]]; then
        rm -rf "${SCRIPT_DIR}/../services"
        log_success "Removed local service code"
    fi
    
    log_success "Cloud Run services cleanup completed"
}

# Remove monitoring configuration
cleanup_monitoring() {
    log_info "Removing monitoring configuration..."
    
    # Delete custom metrics
    local metrics=("content_generation_requests")
    
    for metric in "${metrics[@]}"; do
        log_info "Deleting custom metric: $metric"
        
        if gcloud logging metrics describe "$metric" --project="$PROJECT_ID" >/dev/null 2>&1; then
            gcloud logging metrics delete "$metric" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete metric $metric"
            log_success "Deleted metric: $metric"
        else
            log_info "Metric $metric not found or already deleted"
        fi
    done
    
    # Delete alerting policies (if any exist)
    log_info "Cleaning up alerting policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Content Generation'" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || true)
    
    if [[ -n "$policies" ]]; then
        echo "$policies" | while read -r policy; do
            if [[ -n "$policy" ]]; then
                gcloud alpha monitoring policies delete "$policy" \
                    --project="$PROJECT_ID" \
                    --quiet || log_warning "Failed to delete alerting policy $policy"
                log_success "Deleted alerting policy: $policy"
            fi
        done
    else
        log_info "No alerting policies found to delete"
    fi
    
    # Clean up local monitoring files
    rm -f "${SCRIPT_DIR}/alerting-policy.yaml"
    
    log_success "Monitoring configuration cleanup completed"
}

# Remove storage buckets and contents
cleanup_storage() {
    log_info "Removing storage infrastructure..."
    
    # If BUCKET_NAME is not set, try to find it
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "BUCKET_NAME not set, searching for content generation buckets..."
        
        # Try to find buckets with content generation pattern
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "content-generation-[a-f0-9]{6}" || true)
        
        if [[ -n "$buckets" ]]; then
            log_info "Found potential content generation buckets:"
            echo "$buckets"
            
            echo "$buckets" | while read -r bucket; do
                if [[ -n "$bucket" ]]; then
                    cleanup_bucket "$bucket"
                fi
            done
        else
            log_info "No content generation buckets found to cleanup"
        fi
    else
        cleanup_bucket "gs://$BUCKET_NAME"
    fi
    
    log_success "Storage cleanup completed"
}

# Helper function to cleanup a specific bucket
cleanup_bucket() {
    local bucket_url="$1"
    local bucket_name
    bucket_name=$(echo "$bucket_url" | sed 's|gs://||')
    
    log_info "Cleaning up bucket: $bucket_url"
    
    # Check if bucket exists
    if gsutil ls "$bucket_url" >/dev/null 2>&1; then
        # Remove all objects from bucket (including versions)
        log_info "Removing all objects from $bucket_url..."
        gsutil -m rm -r "${bucket_url}/**" 2>/dev/null || log_info "Bucket was already empty"
        
        # Remove versioned objects
        gsutil -m rm -a "${bucket_url}/**" 2>/dev/null || log_info "No versioned objects to remove"
        
        # Delete the bucket itself
        gsutil rb "$bucket_url" || log_warning "Failed to delete bucket $bucket_url"
        log_success "Deleted bucket: $bucket_url"
    else
        log_info "Bucket $bucket_url not found or already deleted"
    fi
}

# Remove service accounts and IAM policies
cleanup_iam() {
    log_info "Removing service accounts and IAM configuration..."
    
    # If SERVICE_ACCOUNT_NAME is not set, try to find it
    if [[ -z "${SERVICE_ACCOUNT_NAME:-}" ]]; then
        log_info "SERVICE_ACCOUNT_NAME not set, searching for content AI service accounts..."
        
        # Try to find service accounts with content AI pattern
        local service_accounts
        service_accounts=$(gcloud iam service-accounts list \
            --filter="displayName:'Content AI Generation Service'" \
            --format="value(email)" \
            --project="$PROJECT_ID" 2>/dev/null || true)
        
        if [[ -n "$service_accounts" ]]; then
            echo "$service_accounts" | while read -r sa_email; do
                if [[ -n "$sa_email" ]]; then
                    cleanup_service_account "$sa_email"
                fi
            done
        else
            log_info "No content AI service accounts found to cleanup"
        fi
    else
        cleanup_service_account "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    fi
    
    # Clean up local key files
    rm -f "${SCRIPT_DIR}/content-ai-key.json"
    
    log_success "IAM cleanup completed"
}

# Helper function to cleanup a specific service account
cleanup_service_account() {
    local sa_email="$1"
    
    log_info "Cleaning up service account: $sa_email"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$sa_email" --project="$PROJECT_ID" >/dev/null 2>&1; then
        # Remove IAM policy bindings
        local roles=(
            "roles/aiplatform.user"
            "roles/storage.objectAdmin"
            "roles/cloudfunctions.invoker"
            "roles/run.invoker"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding: $role for $sa_email"
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa_email" \
                --role="$role" \
                --quiet 2>/dev/null || log_info "Binding may not exist or already removed"
        done
        
        # Delete service account
        gcloud iam service-accounts delete "$sa_email" \
            --project="$PROJECT_ID" \
            --quiet || log_warning "Failed to delete service account $sa_email"
        log_success "Deleted service account: $sa_email"
    else
        log_info "Service account $sa_email not found or already deleted"
    fi
}

# Clean up local files and state
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log_success "Removed deployment state file"
    fi
    
    # Remove any temporary files
    rm -f "${SCRIPT_DIR}/alerting-policy.yaml"
    
    # Remove generated code directories if they exist and are empty
    for dir in "${SCRIPT_DIR}/../functions" "${SCRIPT_DIR}/../services"; do
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir")" ]]; then
            rmdir "$dir" 2>/dev/null || true
        fi
    done
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --filter="name:(music-generation OR video-generation OR quality-assessment)" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null | wc -l)
    
    if [[ "$remaining_functions" -gt 0 ]]; then
        log_warning "Some Cloud Functions may still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining Cloud Run services
    local remaining_services
    remaining_services=$(gcloud run services list \
        --filter="metadata.name:content-orchestrator" \
        --format="value(metadata.name)" \
        --project="$PROJECT_ID" 2>/dev/null | wc -l)
    
    if [[ "$remaining_services" -gt 0 ]]; then
        log_warning "Some Cloud Run services may still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining buckets (if BUCKET_NAME was set)
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
            log_warning "Storage bucket gs://$BUCKET_NAME still exists"
            ((cleanup_issues++))
        fi
    fi
    
    # Check for remaining service accounts (if SERVICE_ACCOUNT_NAME was set)
    if [[ -n "${SERVICE_ACCOUNT_NAME:-}" ]]; then
        if gcloud iam service-accounts describe \
            "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --project="$PROJECT_ID" >/dev/null 2>&1; then
            log_warning "Service account still exists"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ "$cleanup_issues" -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources appear to be removed"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_warning "Some resources may require manual removal"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Cleanup log: $LOG_FILE"
    echo
    echo "=== RESOURCES REMOVED ==="
    echo "- Cloud Functions (music-generation, video-generation, quality-assessment)"
    echo "- Cloud Run services (content-orchestrator)"
    echo "- Storage buckets and all contents"
    echo "- Service accounts and IAM bindings"
    echo "- Monitoring metrics and alerting policies"
    echo "- Local deployment state and generated code"
    echo
    echo "=== IMPORTANT NOTES ==="
    echo "- Some API enablements remain (they don't incur costs)"
    echo "- The GCP project itself was not deleted"
    echo "- Check the cleanup log for any warnings or errors"
    echo "- You may need to manually remove any remaining resources"
    echo
    log_success "Multi-Modal AI Content Generation Platform cleanup completed!"
}

# Main cleanup flow
main() {
    log_info "Starting Multi-Modal AI Content Generation Platform cleanup..."
    log_info "Cleanup log: $LOG_FILE"
    
    load_deployment_state
    check_prerequisites
    setup_cleanup_environment
    confirm_destruction
    
    # Cleanup in reverse order of creation
    cleanup_cloud_run
    cleanup_functions
    cleanup_monitoring
    cleanup_iam
    cleanup_storage
    cleanup_local_files
    
    verify_cleanup
    show_cleanup_summary
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --force)
            FORCE_DESTROY="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --project-id PROJECT_ID     GCP project ID to cleanup"
            echo "  --force                     Skip confirmation prompts"
            echo "  --help                      Show this help message"
            echo
            echo "This script will remove all resources created by the deployment script."
            echo "It reads deployment state from .deployment_state file if available."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"
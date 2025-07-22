#!/bin/bash

# Video Content Moderation Cleanup Script
# Safely removes all resources created by the video moderation deployment

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
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

# Global variables for resource tracking
RESOURCES_FOUND=()
RESOURCES_DELETED=()
RESOURCES_FAILED=()

# Safety confirmation function
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This script will permanently delete the following resources:"
    echo
    echo "📁 Project:              ${PROJECT_ID}"
    echo "🌍 Region:               ${REGION}"
    echo "🪣 Storage Bucket:        gs://${BUCKET_NAME:-<auto-detect>}"
    echo "⚡ Cloud Function:        ${FUNCTION_NAME:-<auto-detect>}"
    echo "📡 Pub/Sub Topic:         ${PUBSUB_TOPIC:-<auto-detect>}"
    echo "⏰ Scheduler Job:         ${SCHEDULER_JOB:-<auto-detect>}"
    echo "👤 Service Account:       video-moderation-scheduler"
    echo "🔐 IAM Policy Bindings:   Multiple roles and bindings"
    echo
    echo "⚠️  ALL DATA IN THE STORAGE BUCKET WILL BE PERMANENTLY LOST!"
    echo "⚠️  THIS ACTION CANNOT BE UNDONE!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Final confirmation - Type 'DELETE' to proceed: " final_confirm
    if [[ "${final_confirm}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup in 5 seconds..."
    sleep 5
}

# Prerequisites checking function
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Resource discovery function
discover_resources() {
    log_info "Discovering video moderation resources..."
    
    # Try to get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "PROJECT_ID not set and cannot determine current project"
            exit 1
        fi
        log_info "Using current project: ${PROJECT_ID}"
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        log_info "Using region: ${REGION}"
    fi
    
    # Discover Cloud Scheduler jobs (look for video moderation pattern)
    log_info "Discovering Cloud Scheduler jobs..."
    local scheduler_jobs
    scheduler_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name~moderation" 2>/dev/null || echo "")
    
    if [[ -n "${scheduler_jobs}" ]]; then
        while IFS= read -r job; do
            if [[ -n "${job}" ]]; then
                RESOURCES_FOUND+=("scheduler:${job}")
                log_info "Found scheduler job: ${job}"
            fi
        done <<< "${scheduler_jobs}"
    fi
    
    # Discover Cloud Functions (look for video moderation pattern)
    log_info "Discovering Cloud Functions..."
    local functions
    functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~moderator" 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        while IFS= read -r func; do
            if [[ -n "${func}" ]]; then
                RESOURCES_FOUND+=("function:${func}")
                log_info "Found function: ${func}"
            fi
        done <<< "${functions}"
    fi
    
    # Discover Pub/Sub topics (look for video moderation pattern)
    log_info "Discovering Pub/Sub topics..."
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~moderation" 2>/dev/null || echo "")
    
    if [[ -n "${topics}" ]]; then
        while IFS= read -r topic; do
            if [[ -n "${topic}" ]]; then
                # Extract topic name from full path
                local topic_name
                topic_name=$(basename "${topic}")
                RESOURCES_FOUND+=("pubsub:${topic_name}")
                log_info "Found Pub/Sub topic: ${topic_name}"
                
                # Look for subscriptions
                local subscriptions
                subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" --filter="topicId:${topic_name}" 2>/dev/null || echo "")
                if [[ -n "${subscriptions}" ]]; then
                    while IFS= read -r sub; do
                        if [[ -n "${sub}" ]]; then
                            local sub_name
                            sub_name=$(basename "${sub}")
                            RESOURCES_FOUND+=("subscription:${sub_name}")
                            log_info "Found Pub/Sub subscription: ${sub_name}"
                        fi
                    done <<< "${subscriptions}"
                fi
            fi
        done <<< "${topics}"
    fi
    
    # Discover Storage buckets (look for video moderation pattern)
    log_info "Discovering Cloud Storage buckets..."
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://.*moderation" | sed 's|gs://||' | sed 's|/||' || echo "")
    
    if [[ -n "${buckets}" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                RESOURCES_FOUND+=("bucket:${bucket}")
                log_info "Found storage bucket: ${bucket}"
            fi
        done <<< "${buckets}"
    fi
    
    # Discover service accounts (look for video moderation pattern)
    log_info "Discovering service accounts..."
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email~moderation" 2>/dev/null || echo "")
    
    if [[ -n "${service_accounts}" ]]; then
        while IFS= read -r sa; do
            if [[ -n "${sa}" ]]; then
                RESOURCES_FOUND+=("serviceaccount:${sa}")
                log_info "Found service account: ${sa}"
            fi
        done <<< "${service_accounts}"
    fi
    
    # Use provided resource names if discovery didn't find anything and they're provided
    if [[ ${#RESOURCES_FOUND[@]} -eq 0 ]]; then
        log_warning "No resources discovered automatically. Checking provided resource names..."
        
        if [[ -n "${SCHEDULER_JOB:-}" ]]; then
            if gcloud scheduler jobs describe "${SCHEDULER_JOB}" --location="${REGION}" &>/dev/null; then
                RESOURCES_FOUND+=("scheduler:${SCHEDULER_JOB}")
                log_info "Found scheduler job from variable: ${SCHEDULER_JOB}"
            fi
        fi
        
        if [[ -n "${FUNCTION_NAME:-}" ]]; then
            if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
                RESOURCES_FOUND+=("function:${FUNCTION_NAME}")
                log_info "Found function from variable: ${FUNCTION_NAME}"
            fi
        fi
        
        if [[ -n "${PUBSUB_TOPIC:-}" ]]; then
            if gcloud pubsub topics describe "${PUBSUB_TOPIC}" &>/dev/null; then
                RESOURCES_FOUND+=("pubsub:${PUBSUB_TOPIC}")
                log_info "Found Pub/Sub topic from variable: ${PUBSUB_TOPIC}"
            fi
        fi
        
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
                RESOURCES_FOUND+=("bucket:${BUCKET_NAME}")
                log_info "Found bucket from variable: ${BUCKET_NAME}"
            fi
        fi
    fi
    
    if [[ ${#RESOURCES_FOUND[@]} -eq 0 ]]; then
        log_warning "No video moderation resources found to delete"
        exit 0
    fi
    
    log_success "Resource discovery completed. Found ${#RESOURCES_FOUND[@]} resources"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    for resource in "${RESOURCES_FOUND[@]}"; do
        if [[ "${resource}" == scheduler:* ]]; then
            local job_name="${resource#scheduler:}"
            
            log_info "Deleting scheduler job: ${job_name}"
            
            if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet 2>/dev/null; then
                RESOURCES_DELETED+=("${resource}")
                log_success "✓ Deleted scheduler job: ${job_name}"
            else
                RESOURCES_FAILED+=("${resource}")
                log_error "✗ Failed to delete scheduler job: ${job_name}"
            fi
        fi
    done
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    for resource in "${RESOURCES_FOUND[@]}"; do
        if [[ "${resource}" == function:* ]]; then
            local function_name="${resource#function:}"
            
            log_info "Deleting function: ${function_name}"
            
            if gcloud functions delete "${function_name}" --region="${REGION}" --quiet 2>/dev/null; then
                RESOURCES_DELETED+=("${resource}")
                log_success "✓ Deleted function: ${function_name}"
            else
                RESOURCES_FAILED+=("${resource}")
                log_error "✗ Failed to delete function: ${function_name}"
            fi
        fi
    done
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    for resource in "${RESOURCES_FOUND[@]}"; do
        if [[ "${resource}" == subscription:* ]]; then
            local sub_name="${resource#subscription:}"
            
            log_info "Deleting Pub/Sub subscription: ${sub_name}"
            
            if gcloud pubsub subscriptions delete "${sub_name}" --quiet 2>/dev/null; then
                RESOURCES_DELETED+=("${resource}")
                log_success "✓ Deleted subscription: ${sub_name}"
            else
                RESOURCES_FAILED+=("${resource}")
                log_error "✗ Failed to delete subscription: ${sub_name}"
            fi
        fi
    done
    
    # Then delete topics
    for resource in "${RESOURCES_FOUND[@]}"; do
        if [[ "${resource}" == pubsub:* ]]; then
            local topic_name="${resource#pubsub:}"
            
            log_info "Deleting Pub/Sub topic: ${topic_name}"
            
            if gcloud pubsub topics delete "${topic_name}" --quiet 2>/dev/null; then
                RESOURCES_DELETED+=("${resource}")
                log_success "✓ Deleted topic: ${topic_name}"
            else
                RESOURCES_FAILED+=("${resource}")
                log_error "✗ Failed to delete topic: ${topic_name}"
            fi
        fi
    done
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    for resource in "${RESOURCES_FOUND[@]}"; do
        if [[ "${resource}" == bucket:* ]]; then
            local bucket_name="${resource#bucket:}"
            
            log_info "Deleting storage bucket and all contents: ${bucket_name}"
            log_warning "⚠️  All data in gs://${bucket_name} will be permanently lost!"
            
            # First, try to remove all objects in the bucket
            if gsutil -m rm -r "gs://${bucket_name}" 2>/dev/null; then
                RESOURCES_DELETED+=("${resource}")
                log_success "✓ Deleted bucket and contents: ${bucket_name}"
            else
                # If recursive delete failed, try to delete the bucket anyway
                if gsutil rb "gs://${bucket_name}" 2>/dev/null; then
                    RESOURCES_DELETED+=("${resource}")
                    log_success "✓ Deleted empty bucket: ${bucket_name}"
                else
                    RESOURCES_FAILED+=("${resource}")
                    log_error "✗ Failed to delete bucket: ${bucket_name}"
                fi
            fi
        fi
    done
}

# Function to delete service accounts
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    for resource in "${RESOURCES_FOUND[@]}"; do
        if [[ "${resource}" == serviceaccount:* ]]; then
            local sa_email="${resource#serviceaccount:}"
            
            log_info "Deleting service account: ${sa_email}"
            
            if gcloud iam service-accounts delete "${sa_email}" --quiet 2>/dev/null; then
                RESOURCES_DELETED+=("${resource}")
                log_success "✓ Deleted service account: ${sa_email}"
            else
                RESOURCES_FAILED+=("${resource}")
                log_error "✗ Failed to delete service account: ${sa_email}"
            fi
        fi
    done
}

# Function to clean up IAM policy bindings
cleanup_iam_bindings() {
    log_info "Cleaning up IAM policy bindings..."
    
    # List of roles that might have been assigned
    local roles=(
        "roles/pubsub.publisher"
        "roles/cloudscheduler.jobRunner"
        "roles/videointelligence.editor"
        "roles/storage.objectAdmin"
        "roles/logging.logWriter"
    )
    
    # Try to remove IAM bindings for the scheduler service account
    local sa_email="video-moderation-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
    for role in "${roles[@]}"; do
        log_info "Removing IAM binding: ${sa_email} -> ${role}"
        if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}" --quiet 2>/dev/null; then
            log_success "✓ Removed binding: ${role}"
        else
            log_warning "⚠ Could not remove binding: ${role} (may not exist)"
        fi
    done
    
    # Try to remove IAM bindings for the default App Engine service account
    local app_sa="${PROJECT_ID}@appspot.gserviceaccount.com"
    local app_roles=("roles/videointelligence.editor" "roles/storage.objectAdmin" "roles/logging.logWriter")
    
    for role in "${app_roles[@]}"; do
        log_info "Removing IAM binding: ${app_sa} -> ${role}"
        if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${app_sa}" \
            --role="${role}" --quiet 2>/dev/null; then
            log_success "✓ Removed binding: ${role}"
        else
            log_warning "⚠ Could not remove binding: ${role} (may not exist or have other uses)"
        fi
    done
    
    log_success "IAM cleanup completed"
}

# Function to clean up environment variables
cleanup_environment() {
    log_info "Cleaning up environment variables..."
    
    # List of environment variables to unset
    local env_vars=(
        "PROJECT_ID"
        "REGION"
        "ZONE"
        "BUCKET_NAME"
        "FUNCTION_NAME"
        "SCHEDULER_JOB"
        "PUBSUB_TOPIC"
    )
    
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "${var}"
            log_info "Cleared environment variable: ${var}"
        fi
    done
    
    log_success "Environment variables cleared"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                           CLEANUP SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if [[ ${#RESOURCES_DELETED[@]} -gt 0 ]]; then
        log_success "✅ Successfully deleted resources (${#RESOURCES_DELETED[@]}):"
        for resource in "${RESOURCES_DELETED[@]}"; do
            echo "   ✓ ${resource}"
        done
        echo
    fi
    
    if [[ ${#RESOURCES_FAILED[@]} -gt 0 ]]; then
        log_error "❌ Failed to delete resources (${#RESOURCES_FAILED[@]}):"
        for resource in "${RESOURCES_FAILED[@]}"; do
            echo "   ✗ ${resource}"
        done
        echo
        log_warning "Please manually review and delete any remaining resources"
    fi
    
    if [[ ${#RESOURCES_FAILED[@]} -eq 0 ]]; then
        log_success "🎉 All video content moderation resources have been successfully removed!"
    else
        log_warning "⚠️  Cleanup completed with some failures. Please review the failed resources above."
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Main cleanup function
main() {
    echo
    log_info "Starting Video Content Moderation Resource Cleanup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    confirm_destruction
    
    log_info "Starting resource deletion (in safe order)..."
    
    # Delete resources in reverse order of dependencies
    delete_scheduler_jobs
    delete_cloud_functions
    delete_pubsub_resources
    delete_storage_buckets
    delete_service_accounts
    cleanup_iam_bindings
    cleanup_environment
    
    display_cleanup_summary
    
    if [[ ${#RESOURCES_FAILED[@]} -eq 0 ]]; then
        log_success "Cleanup completed successfully! 🧹"
        exit 0
    else
        log_warning "Cleanup completed with some failures. Review the summary above."
        exit 1
    fi
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# Session Management with Cloud Memorystore and Firebase Auth - Cleanup Script
# This script safely removes all resources created by the deploy.sh script,
# including Cloud Functions, Redis instances, secrets, and scheduled jobs.

set -euo pipefail

# Color codes for output formatting
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm_destruction() {
    local resource_type="$1"
    local resource_name="$2"
    local force="${3:-false}"
    
    if [ "$force" = "true" ]; then
        return 0
    fi
    
    echo ""
    log_warning "About to delete ${resource_type}: ${resource_name}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping deletion of ${resource_type}: ${resource_name}"
        return 1
    fi
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project >/dev/null 2>&1; then
        log_error "No project set. Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to discover existing resources
discover_resources() {
    log_info "Discovering existing session management resources..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    
    # Try to load from deployment info file if it exists
    if [ -f "deployment-info.txt" ]; then
        log_info "Found deployment-info.txt, loading resource information..."
        
        # Extract resource names from deployment info
        export REDIS_INSTANCE_NAME=$(grep "Redis Instance:" deployment-info.txt | cut -d' ' -f3 || echo "session-store")
        export FUNCTION_NAME=$(grep "Session Function:" deployment-info.txt | cut -d' ' -f3 || echo "")
        export CLEANUP_FUNCTION_NAME=$(grep "Cleanup Function:" deployment-info.txt | cut -d' ' -f3 || echo "")
        export SECRET_NAME=$(grep "Secret:" deployment-info.txt | cut -d' ' -f2 || echo "")
        export SCHEDULER_JOB_NAME=$(grep "Scheduler Job:" deployment-info.txt | cut -d' ' -f3 || echo "")
    else
        log_warning "No deployment-info.txt found. Will attempt to discover resources automatically."
        
        # Default values
        export REDIS_INSTANCE_NAME="session-store"
        export FUNCTION_NAME=""
        export CLEANUP_FUNCTION_NAME=""
        export SECRET_NAME=""
        export SCHEDULER_JOB_NAME=""
    fi
    
    # Discover Cloud Functions with session-manager prefix
    log_info "Discovering Cloud Functions..."
    local session_functions=$(gcloud functions list --regions="${REGION}" \
        --filter="name~'session-manager-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    local cleanup_functions=$(gcloud functions list --regions="${REGION}" \
        --filter="name~'session-cleanup-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$session_functions" ] && [ -z "$FUNCTION_NAME" ]; then
        export FUNCTION_NAME=$(echo "$session_functions" | head -n1)
        log_info "Discovered session function: ${FUNCTION_NAME}"
    fi
    
    if [ -n "$cleanup_functions" ] && [ -z "$CLEANUP_FUNCTION_NAME" ]; then
        export CLEANUP_FUNCTION_NAME=$(echo "$cleanup_functions" | head -n1)
        log_info "Discovered cleanup function: ${CLEANUP_FUNCTION_NAME}"
    fi
    
    # Discover secrets with redis-connection prefix
    log_info "Discovering secrets..."
    local secrets=$(gcloud secrets list \
        --filter="name~'redis-connection-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$secrets" ] && [ -z "$SECRET_NAME" ]; then
        export SECRET_NAME=$(echo "$secrets" | head -n1)
        log_info "Discovered secret: ${SECRET_NAME}"
    fi
    
    # Discover scheduler jobs
    log_info "Discovering scheduler jobs..."
    local scheduler_jobs=$(gcloud scheduler jobs list --location="${REGION}" \
        --filter="name~'session-cleanup-job-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$scheduler_jobs" ] && [ -z "$SCHEDULER_JOB_NAME" ]; then
        export SCHEDULER_JOB_NAME=$(echo "$scheduler_jobs" | head -n1 | sed 's|.*/||')
        log_info "Discovered scheduler job: ${SCHEDULER_JOB_NAME}"
    fi
    
    log_success "Resource discovery completed"
}

# Function to display cleanup plan
display_cleanup_plan() {
    echo ""
    echo "=== CLEANUP PLAN ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources to be deleted:"
    
    if [ -n "${SCHEDULER_JOB_NAME}" ]; then
        echo "  ✓ Scheduler Job: ${SCHEDULER_JOB_NAME}"
    fi
    
    if [ -n "${CLEANUP_FUNCTION_NAME}" ]; then
        echo "  ✓ Cleanup Function: ${CLEANUP_FUNCTION_NAME}"
    fi
    
    if [ -n "${FUNCTION_NAME}" ]; then
        echo "  ✓ Session Function: ${FUNCTION_NAME}"
    fi
    
    if [ -n "${SECRET_NAME}" ]; then
        echo "  ✓ Secret: ${SECRET_NAME}"
    fi
    
    if [ -n "${REDIS_INSTANCE_NAME}" ]; then
        echo "  ✓ Redis Instance: ${REDIS_INSTANCE_NAME}"
    fi
    
    echo "  ✓ Monitoring policies (if any)"
    echo "  ✓ Local files"
    echo ""
}

# Function to remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    if [ -z "${SCHEDULER_JOB_NAME}" ]; then
        log_info "No scheduler jobs to remove"
        return 0
    fi
    
    log_info "Removing Cloud Scheduler jobs..."
    
    if confirm_destruction "Scheduler Job" "${SCHEDULER_JOB_NAME}" "${FORCE:-false}"; then
        if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" \
            --location="${REGION}" >/dev/null 2>&1; then
            
            if gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" \
                --location="${REGION}" \
                --quiet; then
                log_success "Deleted scheduler job: ${SCHEDULER_JOB_NAME}"
            else
                log_error "Failed to delete scheduler job: ${SCHEDULER_JOB_NAME}"
            fi
        else
            log_warning "Scheduler job ${SCHEDULER_JOB_NAME} not found"
        fi
    fi
}

# Function to remove Cloud Functions
remove_cloud_functions() {
    log_info "Removing Cloud Functions..."
    
    # Remove cleanup function
    if [ -n "${CLEANUP_FUNCTION_NAME}" ]; then
        if confirm_destruction "Cleanup Function" "${CLEANUP_FUNCTION_NAME}" "${FORCE:-false}"; then
            if gcloud functions describe "${CLEANUP_FUNCTION_NAME}" \
                --region="${REGION}" >/dev/null 2>&1; then
                
                if gcloud functions delete "${CLEANUP_FUNCTION_NAME}" \
                    --region="${REGION}" \
                    --quiet; then
                    log_success "Deleted cleanup function: ${CLEANUP_FUNCTION_NAME}"
                else
                    log_error "Failed to delete cleanup function: ${CLEANUP_FUNCTION_NAME}"
                fi
            else
                log_warning "Cleanup function ${CLEANUP_FUNCTION_NAME} not found"
            fi
        fi
    fi
    
    # Remove session management function
    if [ -n "${FUNCTION_NAME}" ]; then
        if confirm_destruction "Session Function" "${FUNCTION_NAME}" "${FORCE:-false}"; then
            if gcloud functions describe "${FUNCTION_NAME}" \
                --region="${REGION}" >/dev/null 2>&1; then
                
                if gcloud functions delete "${FUNCTION_NAME}" \
                    --region="${REGION}" \
                    --quiet; then
                    log_success "Deleted session function: ${FUNCTION_NAME}"
                else
                    log_error "Failed to delete session function: ${FUNCTION_NAME}"
                fi
            else
                log_warning "Session function ${FUNCTION_NAME} not found"
            fi
        fi
    fi
    
    if [ -z "${FUNCTION_NAME}" ] && [ -z "${CLEANUP_FUNCTION_NAME}" ]; then
        log_info "No Cloud Functions to remove"
    fi
}

# Function to remove secrets
remove_secrets() {
    if [ -z "${SECRET_NAME}" ]; then
        log_info "No secrets to remove"
        return 0
    fi
    
    log_info "Removing Secret Manager secrets..."
    
    if confirm_destruction "Secret" "${SECRET_NAME}" "${FORCE:-false}"; then
        if gcloud secrets describe "${SECRET_NAME}" >/dev/null 2>&1; then
            if gcloud secrets delete "${SECRET_NAME}" --quiet; then
                log_success "Deleted secret: ${SECRET_NAME}"
            else
                log_error "Failed to delete secret: ${SECRET_NAME}"
            fi
        else
            log_warning "Secret ${SECRET_NAME} not found"
        fi
    fi
}

# Function to remove Redis instance
remove_redis_instance() {
    if [ -z "${REDIS_INSTANCE_NAME}" ]; then
        log_info "No Redis instance to remove"
        return 0
    fi
    
    log_info "Removing Cloud Memorystore Redis instance..."
    log_warning "This will permanently delete all session data stored in Redis!"
    
    if confirm_destruction "Redis Instance" "${REDIS_INSTANCE_NAME}" "${FORCE:-false}"; then
        if gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
            --region="${REGION}" >/dev/null 2>&1; then
            
            log_info "Deleting Redis instance (this may take several minutes)..."
            if gcloud redis instances delete "${REDIS_INSTANCE_NAME}" \
                --region="${REGION}" \
                --quiet; then
                
                # Wait for deletion to complete
                log_info "Waiting for Redis instance deletion to complete..."
                local timeout=300  # 5 minutes timeout
                local elapsed=0
                
                while [ $elapsed -lt $timeout ]; do
                    if ! gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
                        --region="${REGION}" >/dev/null 2>&1; then
                        log_success "Redis instance deleted successfully"
                        break
                    fi
                    
                    log_info "Redis deletion in progress... (${elapsed}s elapsed)"
                    sleep 15
                    elapsed=$((elapsed + 15))
                done
                
                if [ $elapsed -ge $timeout ]; then
                    log_warning "Timeout waiting for Redis deletion, but deletion may still be in progress"
                fi
            else
                log_error "Failed to delete Redis instance: ${REDIS_INSTANCE_NAME}"
            fi
        else
            log_warning "Redis instance ${REDIS_INSTANCE_NAME} not found"
        fi
    fi
}

# Function to remove monitoring policies
remove_monitoring_policies() {
    log_info "Removing monitoring policies..."
    
    # Find and remove Redis memory alert policies
    local policies=$(gcloud alpha monitoring policies list \
        --filter="displayName~'Redis Memory Usage Alert'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            if confirm_destruction "Monitoring Policy" "$(basename "$policy")" "${FORCE:-false}"; then
                if gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null; then
                    log_success "Deleted monitoring policy: $(basename "$policy")"
                else
                    log_warning "Failed to delete monitoring policy: $(basename "$policy")"
                fi
            fi
        done
    else
        log_info "No monitoring policies found to remove"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "firebase-auth-config.json"
        "monitoring-config.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            if confirm_destruction "Local File" "$file" "${FORCE:-false}"; then
                rm -f "$file"
                log_success "Removed local file: $file"
            fi
        fi
    done
    
    # Remove any temporary function directories that might still exist
    if [ -d "session-function" ]; then
        if confirm_destruction "Directory" "session-function" "${FORCE:-false}"; then
            rm -rf "session-function"
            log_success "Removed directory: session-function"
        fi
    fi
    
    if [ -d "cleanup-function" ]; then
        if confirm_destruction "Directory" "cleanup-function" "${FORCE:-false}"; then
            rm -rf "cleanup-function"
            log_success "Removed directory: cleanup-function"
        fi
    fi
}

# Function to remove IAM policy bindings
cleanup_iam_bindings() {
    log_info "Cleaning up IAM policy bindings..."
    
    local function_sa="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    # Remove Secret Manager accessor role
    if gcloud projects get-iam-policy "${PROJECT_ID}" \
        --flatten="bindings[].members" \
        --filter="bindings.role:roles/secretmanager.secretAccessor AND bindings.members:serviceAccount:${function_sa}" \
        --format="value(bindings.role)" | grep -q "secretmanager.secretAccessor"; then
        
        if confirm_destruction "IAM Binding" "Secret Manager access for ${function_sa}" "${FORCE:-false}"; then
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${function_sa}" \
                --role="roles/secretmanager.secretAccessor" \
                --quiet; then
                log_success "Removed Secret Manager IAM binding"
            else
                log_warning "Failed to remove Secret Manager IAM binding"
            fi
        fi
    else
        log_info "No Secret Manager IAM bindings found to remove"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    log_success "Session management system cleanup completed!"
    echo ""
    echo "The following resources have been processed:"
    echo "  ✓ Cloud Scheduler jobs"
    echo "  ✓ Cloud Functions"
    echo "  ✓ Secret Manager secrets"
    echo "  ✓ Redis instance and session data"
    echo "  ✓ Monitoring policies"
    echo "  ✓ IAM policy bindings"
    echo "  ✓ Local files"
    echo ""
    
    log_info "Cleanup completed successfully!"
    log_info "Note: Some resources may take a few minutes to be fully removed from the console."
    echo ""
    
    # Check if Firebase project still exists
    echo "=== MANUAL CLEANUP REQUIRED ==="
    log_warning "Firebase Authentication settings remain active:"
    log_warning "If you no longer need Firebase Auth, manually disable it in:"
    log_warning "https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
    echo ""
    
    log_warning "Enabled APIs remain active to avoid disrupting other resources."
    log_warning "To disable APIs manually if not needed elsewhere:"
    log_warning "gcloud services disable redis.googleapis.com cloudfunctions.googleapis.com secretmanager.googleapis.com"
}

# Function to show help
show_help() {
    echo "Session Management Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force     Skip confirmation prompts and force deletion"
    echo "  -h, --help      Show this help message"
    echo "  --dry-run       Show what would be deleted without actually deleting"
    echo ""
    echo "Examples:"
    echo "  $0              Interactive cleanup with confirmations"
    echo "  $0 --force      Automatic cleanup without prompts"
    echo "  $0 --dry-run    Preview what would be deleted"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                export FORCE="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
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

# Main cleanup function
main() {
    echo "========================================"
    echo "Session Management System Cleanup"
    echo "========================================"
    echo ""
    
    parse_arguments "$@"
    
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        echo ""
    fi
    
    check_prerequisites
    discover_resources
    display_cleanup_plan
    
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "Dry run completed. No resources were deleted."
        exit 0
    fi
    
    if [ "${FORCE:-false}" != "true" ]; then
        echo ""
        log_warning "This will permanently delete all session management resources and data!"
        read -p "Are you sure you want to continue with cleanup? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    echo ""
    log_info "Starting cleanup process..."
    
    remove_scheduler_jobs
    remove_cloud_functions
    remove_secrets
    remove_redis_instance
    remove_monitoring_policies
    cleanup_iam_bindings
    cleanup_local_files
    display_cleanup_summary
}

# Run main function with all arguments
main "$@"
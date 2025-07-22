#!/bin/bash

# Destroy script for Secure Package Distribution Workflows with Artifact Registry and Secret Manager
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Function to confirm destruction
confirm_destruction() {
    echo -e "${RED}WARNING: This will permanently delete all resources created by the deployment script.${NC}"
    echo "This includes:"
    echo "- Artifact Registry repositories and all stored packages"
    echo "- Secret Manager secrets and their versions"
    echo "- Cloud Functions and their source code"
    echo "- Cloud Tasks queues and pending tasks"
    echo "- Cloud Scheduler jobs"
    echo "- IAM service accounts and policy bindings"
    echo "- Monitoring metrics and alerting policies"
    echo
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set to true, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f ".env" ]]; then
        log_info "Loading environment variables from .env file..."
        set -a  # Export all variables
        source .env
        set +a  # Stop exporting
        log_success "Environment variables loaded from .env file"
    else
        log_warning ".env file not found, attempting to derive from current gcloud config..."
        
        # Try to get from gcloud config
        export PROJECT_ID=$(gcloud config get-value project)
        export REGION=$(gcloud config get-value artifacts/location 2>/dev/null || echo "us-central1")
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID found. Please ensure gcloud is configured or .env file exists."
            exit 1
        fi
        
        log_warning "Some resources may not be cleaned up without the original .env file"
        log_warning "You may need to manually clean up resources with random suffixes"
    fi
    
    log_info "Using Project ID: ${PROJECT_ID}"
    log_info "Using Region: ${REGION}"
}

# Function to remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."
    
    if [[ -n "${SCHEDULER_JOB}" ]]; then
        # Remove specific scheduler jobs
        local jobs=(
            "${SCHEDULER_JOB}-nightly"
            "${SCHEDULER_JOB}-weekly-staging"
            "${SCHEDULER_JOB}-prod-manual"
        )
        
        for job in "${jobs[@]}"; do
            log_info "Removing scheduler job: ${job}"
            if gcloud scheduler jobs describe "${job}" --location="${REGION}" &>/dev/null; then
                gcloud scheduler jobs delete "${job}" \
                    --location="${REGION}" \
                    --quiet || log_warning "Failed to delete scheduler job: ${job}"
            else
                log_warning "Scheduler job not found: ${job}"
            fi
        done
    else
        log_warning "SCHEDULER_JOB variable not set, attempting to find and remove related jobs..."
        
        # List and remove jobs that might be related
        local job_list=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name:package-distribution" 2>/dev/null || true)
        
        if [[ -n "${job_list}" ]]; then
            echo "${job_list}" | while read -r job; do
                if [[ -n "${job}" ]]; then
                    log_info "Removing scheduler job: ${job}"
                    gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet || log_warning "Failed to delete job: ${job}"
                fi
            done
        else
            log_info "No scheduler jobs found to remove"
        fi
    fi
    
    log_success "Scheduler jobs removal completed"
}

# Function to remove Cloud Tasks queues
remove_task_queues() {
    log_info "Removing Cloud Tasks queues..."
    
    local queues=(
        "package-distribution-queue"
        "prod-distribution-queue"
    )
    
    for queue in "${queues[@]}"; do
        log_info "Removing task queue: ${queue}"
        if gcloud tasks queues describe "${queue}" --location="${REGION}" &>/dev/null; then
            gcloud tasks queues delete "${queue}" \
                --location="${REGION}" \
                --quiet || log_warning "Failed to delete task queue: ${queue}"
        else
            log_warning "Task queue not found: ${queue}"
        fi
    done
    
    log_success "Task queues removal completed"
}

# Function to remove Cloud Function
remove_cloud_function() {
    log_info "Removing Cloud Function..."
    
    if [[ -n "${FUNCTION_NAME}" ]]; then
        log_info "Removing Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            gcloud functions delete "${FUNCTION_NAME}" \
                --region="${REGION}" \
                --quiet || log_warning "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        else
            log_warning "Cloud Function not found: ${FUNCTION_NAME}"
        fi
    else
        log_warning "FUNCTION_NAME variable not set, attempting to find and remove related functions..."
        
        # List and remove functions that might be related
        local function_list=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name:package-distributor" 2>/dev/null || true)
        
        if [[ -n "${function_list}" ]]; then
            echo "${function_list}" | while read -r func; do
                if [[ -n "${func}" ]]; then
                    log_info "Removing Cloud Function: ${func}"
                    gcloud functions delete "${func}" --region="${REGION}" --quiet || log_warning "Failed to delete function: ${func}"
                fi
            done
        else
            log_info "No Cloud Functions found to remove"
        fi
    fi
    
    # Remove local function source directory
    if [[ -d "package-distributor-function" ]]; then
        log_info "Removing local function source directory..."
        rm -rf package-distributor-function
    fi
    
    log_success "Cloud Function removal completed"
}

# Function to remove Secret Manager secrets
remove_secrets() {
    log_info "Removing Secret Manager secrets..."
    
    if [[ -n "${SECRET_NAME}" && -n "${RANDOM_SUFFIX}" ]]; then
        # Remove specific secrets
        local secrets=(
            "${SECRET_NAME}-dev"
            "${SECRET_NAME}-staging"
            "${SECRET_NAME}-prod"
            "distribution-config-${RANDOM_SUFFIX}"
        )
        
        for secret in "${secrets[@]}"; do
            log_info "Removing secret: ${secret}"
            if gcloud secrets describe "${secret}" &>/dev/null; then
                gcloud secrets delete "${secret}" --quiet || log_warning "Failed to delete secret: ${secret}"
            else
                log_warning "Secret not found: ${secret}"
            fi
        done
    else
        log_warning "SECRET_NAME or RANDOM_SUFFIX not set, attempting to find and remove related secrets..."
        
        # List and remove secrets that might be related
        local secret_list=$(gcloud secrets list --format="value(name)" --filter="name:registry-credentials OR name:distribution-config" 2>/dev/null || true)
        
        if [[ -n "${secret_list}" ]]; then
            echo "${secret_list}" | while read -r secret; do
                if [[ -n "${secret}" ]]; then
                    log_info "Removing secret: ${secret}"
                    gcloud secrets delete "${secret}" --quiet || log_warning "Failed to delete secret: ${secret}"
                fi
            done
        else
            log_info "No secrets found to remove"
        fi
    fi
    
    log_success "Secret Manager secrets removal completed"
}

# Function to remove IAM service account
remove_service_account() {
    log_info "Removing IAM service account..."
    
    if [[ -n "${SERVICE_ACCOUNT_EMAIL}" ]]; then
        log_info "Removing service account: ${SERVICE_ACCOUNT_EMAIL}"
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" &>/dev/null; then
            # Remove IAM policy bindings first
            log_info "Removing IAM policy bindings..."
            local roles=(
                "roles/artifactregistry.reader"
                "roles/artifactregistry.writer"
                "roles/secretmanager.secretAccessor"
                "roles/cloudfunctions.invoker"
                "roles/cloudtasks.enqueuer"
            )
            
            for role in "${roles[@]}"; do
                log_info "Removing role binding: ${role}"
                gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
                    --role="${role}" \
                    --quiet || log_warning "Failed to remove role binding: ${role}"
            done
            
            # Delete the service account
            log_info "Deleting service account..."
            gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" --quiet || log_warning "Failed to delete service account"
        else
            log_warning "Service account not found: ${SERVICE_ACCOUNT_EMAIL}"
        fi
    else
        log_warning "SERVICE_ACCOUNT_EMAIL not set, attempting to find and remove related service accounts..."
        
        # List and remove service accounts that might be related
        local sa_list=$(gcloud iam service-accounts list --format="value(email)" --filter="email:package-distributor-sa" 2>/dev/null || true)
        
        if [[ -n "${sa_list}" ]]; then
            echo "${sa_list}" | while read -r sa; do
                if [[ -n "${sa}" ]]; then
                    log_info "Removing service account: ${sa}"
                    gcloud iam service-accounts delete "${sa}" --quiet || log_warning "Failed to delete service account: ${sa}"
                fi
            done
        else
            log_info "No service accounts found to remove"
        fi
    fi
    
    log_success "Service account removal completed"
}

# Function to remove Artifact Registry repositories
remove_artifact_registry() {
    log_info "Removing Artifact Registry repositories..."
    
    if [[ -n "${REPO_NAME}" ]]; then
        # Remove specific repositories
        local repos=(
            "${REPO_NAME}"
            "${REPO_NAME}-npm"
            "${REPO_NAME}-maven"
        )
        
        for repo in "${repos[@]}"; do
            log_info "Removing repository: ${repo}"
            if gcloud artifacts repositories describe "${repo}" --location="${REGION}" &>/dev/null; then
                gcloud artifacts repositories delete "${repo}" \
                    --location="${REGION}" \
                    --quiet || log_warning "Failed to delete repository: ${repo}"
            else
                log_warning "Repository not found: ${repo}"
            fi
        done
    else
        log_warning "REPO_NAME not set, attempting to find and remove related repositories..."
        
        # List and remove repositories that might be related
        local repo_list=$(gcloud artifacts repositories list --location="${REGION}" --format="value(name)" --filter="name:secure-packages" 2>/dev/null || true)
        
        if [[ -n "${repo_list}" ]]; then
            echo "${repo_list}" | while read -r repo; do
                if [[ -n "${repo}" ]]; then
                    local repo_name=$(basename "${repo}")
                    log_info "Removing repository: ${repo_name}"
                    gcloud artifacts repositories delete "${repo_name}" --location="${REGION}" --quiet || log_warning "Failed to delete repository: ${repo_name}"
                fi
            done
        else
            log_info "No repositories found to remove"
        fi
    fi
    
    log_success "Artifact Registry repositories removal completed"
}

# Function to remove monitoring resources
remove_monitoring() {
    log_info "Removing monitoring and alerting resources..."
    
    # Remove log-based metrics
    local metrics=(
        "package_distribution_failures"
        "package_distribution_success"
    )
    
    for metric in "${metrics[@]}"; do
        log_info "Removing log-based metric: ${metric}"
        if gcloud logging metrics describe "${metric}" &>/dev/null; then
            gcloud logging metrics delete "${metric}" --quiet || log_warning "Failed to delete metric: ${metric}"
        else
            log_warning "Metric not found: ${metric}"
        fi
    done
    
    # Remove alerting policies
    log_info "Removing alerting policies..."
    local policies=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:'Package Distribution Failures'" 2>/dev/null || true)
    
    if [[ -n "${policies}" ]]; then
        echo "${policies}" | while read -r policy; do
            if [[ -n "${policy}" ]]; then
                log_info "Removing alerting policy: ${policy}"
                gcloud alpha monitoring policies delete "${policy}" --quiet || log_warning "Failed to delete policy: ${policy}"
            fi
        done
    else
        log_info "No alerting policies found to remove"
    fi
    
    # Remove local alerting policy file
    if [[ -f "alerting-policy.json" ]]; then
        log_info "Removing local alerting policy file..."
        rm -f alerting-policy.json
    fi
    
    log_success "Monitoring resources removal completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".env" ]]; then
        log_info "Removing .env file..."
        rm -f .env
    fi
    
    # Remove any other temporary files
    local temp_files=(
        "alerting-policy.json"
        "package-distributor-function"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "${file}" ]]; then
            log_info "Removing: ${file}"
            rm -rf "${file}"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local warnings=0
    
    # Check for remaining repositories
    local remaining_repos=$(gcloud artifacts repositories list --location="${REGION}" --format="value(name)" --filter="name:secure-packages" 2>/dev/null || true)
    if [[ -n "${remaining_repos}" ]]; then
        log_warning "Some Artifact Registry repositories may still exist:"
        echo "${remaining_repos}"
        ((warnings++))
    fi
    
    # Check for remaining secrets
    local remaining_secrets=$(gcloud secrets list --format="value(name)" --filter="name:registry-credentials OR name:distribution-config" 2>/dev/null || true)
    if [[ -n "${remaining_secrets}" ]]; then
        log_warning "Some Secret Manager secrets may still exist:"
        echo "${remaining_secrets}"
        ((warnings++))
    fi
    
    # Check for remaining functions
    local remaining_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name:package-distributor" 2>/dev/null || true)
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some Cloud Functions may still exist:"
        echo "${remaining_functions}"
        ((warnings++))
    fi
    
    # Check for remaining service accounts
    local remaining_sas=$(gcloud iam service-accounts list --format="value(email)" --filter="email:package-distributor-sa" 2>/dev/null || true)
    if [[ -n "${remaining_sas}" ]]; then
        log_warning "Some service accounts may still exist:"
        echo "${remaining_sas}"
        ((warnings++))
    fi
    
    if [[ ${warnings} -eq 0 ]]; then
        log_success "All resources appear to have been cleaned up successfully"
    else
        log_warning "Some resources may still exist. Please check the Google Cloud Console for any remaining resources."
        log_warning "You may need to manually clean up resources that were created with different naming patterns."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "Resource cleanup completed!"
    echo
    echo "=== Cleanup Summary ==="
    echo "The following resources have been removed:"
    echo "✓ Cloud Scheduler jobs"
    echo "✓ Cloud Tasks queues"
    echo "✓ Cloud Functions"
    echo "✓ Secret Manager secrets"
    echo "✓ IAM service accounts and policy bindings"
    echo "✓ Artifact Registry repositories"
    echo "✓ Monitoring metrics and alerting policies"
    echo "✓ Local files and directories"
    echo
    echo "=== Important Notes ==="
    echo "• Some resources may take a few minutes to be fully deleted"
    echo "• Check the Google Cloud Console to verify all resources are removed"
    echo "• Billing will stop once all resources are successfully deleted"
    echo "• Any packages stored in Artifact Registry repositories have been permanently deleted"
    echo
    echo "If you need to redeploy the infrastructure, run: ./deploy.sh"
}

# Main execution
main() {
    log_info "Starting secure package distribution workflow cleanup..."
    
    confirm_destruction
    load_environment
    
    # Remove resources in reverse order of creation
    remove_scheduler_jobs
    remove_task_queues
    remove_cloud_function
    remove_monitoring
    remove_secrets
    remove_service_account
    remove_artifact_registry
    cleanup_local_files
    
    verify_cleanup
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "OPTIONS:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            echo
            echo "This script will remove all resources created by the deploy.sh script."
            echo "Make sure you have the .env file from the deployment in the same directory."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"
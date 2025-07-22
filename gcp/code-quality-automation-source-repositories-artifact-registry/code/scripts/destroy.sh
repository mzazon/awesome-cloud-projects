#!/bin/bash

# GCP Code Quality Automation Cleanup Script
# Recipe: Code Quality Automation with Cloud Source Repositories and Artifact Registry
# Description: Safely removes all resources created by the deployment script

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Default values
DEFAULT_REGION="us-central1"

# Parse command line arguments
FORCE_DELETE=false
DRY_RUN=false
DELETE_PROJECT=false
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --force-delete)
            FORCE_DELETE=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id ID         Target project ID (required if not set in gcloud)"
            echo "  --region REGION         GCP region (default: us-central1)"
            echo "  --force-delete          Force deletion without prompting for each resource"
            echo "  --delete-project        Delete the entire project (WARNING: irreversible)"
            echo "  --dry-run              Show what would be deleted without executing"
            echo "  --yes                  Skip all confirmation prompts"
            echo "  --help                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --project-id my-project --region us-central1"
            echo "  $0 --delete-project --yes"
            echo "  $0 --dry-run"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project if not specified
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error_exit "No project ID specified and no default project configured. Use --project-id or set default project."
        fi
    fi
    
    # Set defaults
    export REGION="${REGION:-$DEFAULT_REGION}"
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Force delete: ${FORCE_DELETE}"
    log_info "  Delete project: ${DELETE_PROJECT}"
    log_info "  Dry run: ${DRY_RUN}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login' first."
    fi
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error_exit "Project ${PROJECT_ID} does not exist or you don't have access to it."
    fi
    
    # Set the project context
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${PROJECT_ID}"
    fi
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local force_flag="$2"
    
    if [[ "${SKIP_CONFIRMATION}" == "true" || "${force_flag}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        return 1
    fi
    return 0
}

# Get list of build triggers
get_build_triggers() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "quality-pipeline-*"
        return
    fi
    
    gcloud builds triggers list \
        --filter="name~'quality-pipeline-'" \
        --format="value(name)" 2>/dev/null || echo ""
}

# Get list of artifact repositories
get_artifact_repositories() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "quality-artifacts-*"
        return
    fi
    
    gcloud artifacts repositories list \
        --location="${REGION}" \
        --filter="name~'quality-artifacts-'" \
        --format="value(name)" 2>/dev/null || echo ""
}

# Get list of source repositories
get_source_repositories() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "quality-demo-*"
        return
    fi
    
    gcloud source repos list \
        --filter="name~'quality-demo-'" \
        --format="value(name)" 2>/dev/null || echo ""
}

# Get list of storage buckets
get_storage_buckets() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "gs://code-quality-demo-*-build-artifacts"
        return
    fi
    
    gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "build-artifacts" || echo ""
}

# Get list of logging metrics
get_logging_metrics() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "code_quality_score"
        return
    fi
    
    gcloud logging metrics list \
        --filter="name~'code_quality_score'" \
        --format="value(name)" 2>/dev/null || echo ""
}

# Cancel running builds
cancel_running_builds() {
    log_info "Cancelling any running builds..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Get running builds
        RUNNING_BUILDS=$(gcloud builds list \
            --ongoing \
            --format="value(id)" 2>/dev/null || echo "")
        
        if [[ -n "${RUNNING_BUILDS}" ]]; then
            log_info "Found running builds, cancelling..."
            echo "${RUNNING_BUILDS}" | while read -r build_id; do
                if [[ -n "${build_id}" ]]; then
                    gcloud builds cancel "${build_id}" --quiet || true
                    log_info "Cancelled build: ${build_id}"
                fi
            done
        else
            log_info "No running builds found"
        fi
    fi
    
    log_success "Build cancellation completed"
}

# Delete build triggers
delete_build_triggers() {
    log_info "Deleting Cloud Build triggers..."
    
    local triggers
    triggers=$(get_build_triggers)
    
    if [[ -z "${triggers}" ]]; then
        log_info "No build triggers found to delete"
        return
    fi
    
    if confirm_action "This will delete the following build triggers: ${triggers}" "${FORCE_DELETE}"; then
        echo "${triggers}" | while read -r trigger; do
            if [[ -n "${trigger}" ]]; then
                log_info "Deleting build trigger: ${trigger}"
                if [[ "${DRY_RUN}" == "false" ]]; then
                    gcloud builds triggers delete "${trigger}" --quiet || log_warning "Failed to delete trigger: ${trigger}"
                fi
            fi
        done
        log_success "Build triggers deleted"
    else
        log_info "Skipping build trigger deletion"
    fi
}

# Delete artifact registry repositories
delete_artifact_repositories() {
    log_info "Deleting Artifact Registry repositories..."
    
    local repositories
    repositories=$(get_artifact_repositories)
    
    if [[ -z "${repositories}" ]]; then
        log_info "No artifact repositories found to delete"
        return
    fi
    
    if confirm_action "This will delete the following artifact repositories and ALL their contents: ${repositories}" "${FORCE_DELETE}"; then
        echo "${repositories}" | while read -r repo; do
            if [[ -n "${repo}" ]]; then
                # Extract just the repository name from the full path
                repo_name=$(basename "${repo}")
                log_info "Deleting artifact repository: ${repo_name}"
                if [[ "${DRY_RUN}" == "false" ]]; then
                    gcloud artifacts repositories delete "${repo_name}" \
                        --location="${REGION}" \
                        --quiet || log_warning "Failed to delete repository: ${repo_name}"
                fi
            fi
        done
        
        # Also try to delete the packages repository
        if [[ "${DRY_RUN}" == "false" ]]; then
            local package_repos
            package_repos=$(gcloud artifacts repositories list \
                --location="${REGION}" \
                --filter="name~'quality-artifacts-.*-packages'" \
                --format="value(name)" 2>/dev/null || echo "")
            
            echo "${package_repos}" | while read -r repo; do
                if [[ -n "${repo}" ]]; then
                    repo_name=$(basename "${repo}")
                    log_info "Deleting packages repository: ${repo_name}"
                    gcloud artifacts repositories delete "${repo_name}" \
                        --location="${REGION}" \
                        --quiet || log_warning "Failed to delete packages repository: ${repo_name}"
                fi
            done
        fi
        
        log_success "Artifact repositories deleted"
    else
        log_info "Skipping artifact repository deletion"
    fi
}

# Delete source repositories
delete_source_repositories() {
    log_info "Deleting Cloud Source repositories..."
    
    local repositories
    repositories=$(get_source_repositories)
    
    if [[ -z "${repositories}" ]]; then
        log_info "No source repositories found to delete"
        return
    fi
    
    if confirm_action "This will delete the following source repositories and ALL their contents: ${repositories}" "${FORCE_DELETE}"; then
        echo "${repositories}" | while read -r repo; do
            if [[ -n "${repo}" ]]; then
                log_info "Deleting source repository: ${repo}"
                if [[ "${DRY_RUN}" == "false" ]]; then
                    gcloud source repos delete "${repo}" --quiet || log_warning "Failed to delete repository: ${repo}"
                fi
            fi
        done
        log_success "Source repositories deleted"
    else
        log_info "Skipping source repository deletion"
    fi
}

# Delete storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    local buckets
    buckets=$(get_storage_buckets)
    
    if [[ -z "${buckets}" ]]; then
        log_info "No storage buckets found to delete"
        return
    fi
    
    if confirm_action "This will delete the following storage buckets and ALL their contents: ${buckets}" "${FORCE_DELETE}"; then
        echo "${buckets}" | while read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                log_info "Deleting storage bucket: ${bucket}"
                if [[ "${DRY_RUN}" == "false" ]]; then
                    gsutil -m rm -r "${bucket}" || log_warning "Failed to delete bucket: ${bucket}"
                fi
            fi
        done
        log_success "Storage buckets deleted"
    else
        log_info "Skipping storage bucket deletion"
    fi
}

# Delete logging metrics
delete_logging_metrics() {
    log_info "Deleting custom logging metrics..."
    
    local metrics
    metrics=$(get_logging_metrics)
    
    if [[ -z "${metrics}" ]]; then
        log_info "No custom logging metrics found to delete"
        return
    fi
    
    if confirm_action "This will delete the following logging metrics: ${metrics}" "${FORCE_DELETE}"; then
        echo "${metrics}" | while read -r metric; do
            if [[ -n "${metric}" ]]; then
                log_info "Deleting logging metric: ${metric}"
                if [[ "${DRY_RUN}" == "false" ]]; then
                    gcloud logging metrics delete "${metric}" --quiet || log_warning "Failed to delete metric: ${metric}"
                fi
            fi
        done
        log_success "Logging metrics deleted"
    else
        log_info "Skipping logging metrics deletion"
    fi
}

# Delete monitoring policies
delete_monitoring_policies() {
    log_info "Deleting monitoring alert policies..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Get monitoring policies related to code quality
        local policies
        policies=$(gcloud alpha monitoring policies list \
            --filter="displayName~'Code Quality'" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${policies}" ]]; then
            if confirm_action "This will delete monitoring alert policies related to code quality" "${FORCE_DELETE}"; then
                echo "${policies}" | while read -r policy; do
                    if [[ -n "${policy}" ]]; then
                        log_info "Deleting monitoring policy: ${policy}"
                        gcloud alpha monitoring policies delete "${policy}" --quiet || log_warning "Failed to delete policy: ${policy}"
                    fi
                done
                log_success "Monitoring policies deleted"
            else
                log_info "Skipping monitoring policy deletion"
            fi
        else
            log_info "No monitoring policies found to delete"
        fi
    else
        log_info "Would delete monitoring alert policies (dry run)"
    fi
}

# Delete the entire project
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return
    fi
    
    log_warning "PROJECT DELETION REQUESTED"
    log_warning "This will permanently delete the entire project: ${PROJECT_ID}"
    log_warning "This action is IRREVERSIBLE and will remove ALL resources in the project"
    
    if confirm_action "Are you absolutely sure you want to delete the entire project ${PROJECT_ID}?" false; then
        log_info "Deleting project: ${PROJECT_ID}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            gcloud projects delete "${PROJECT_ID}" --quiet
            log_success "Project deletion initiated. This may take several minutes to complete."
        else
            log_info "Would delete project: ${PROJECT_ID} (dry run)"
        fi
    else
        log_info "Project deletion cancelled"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log_success "🧹 Cleanup completed!"
    echo
    log_info "📋 Cleanup Summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    echo
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_info "✅ Project deletion initiated"
        log_warning "Note: Project deletion may take several minutes to complete"
    else
        log_info "✅ Build triggers removed"
        log_info "✅ Artifact repositories deleted"
        log_info "✅ Source repositories deleted"
        log_info "✅ Storage buckets deleted"
        log_info "✅ Logging metrics deleted"
        log_info "✅ Monitoring policies cleaned up"
        echo
        log_info "💡 Tips:"
        log_info "  - Verify all resources are deleted in the Cloud Console"
        log_info "  - Check for any remaining resources that may incur charges"
        log_info "  - Use --delete-project flag to remove the entire project"
    fi
    echo
    log_info "🔗 Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
}

# Main cleanup function
main() {
    log_info "🧹 Starting GCP Code Quality Automation cleanup..."
    echo
    
    # Check if this is a dry run
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "🔍 DRY RUN MODE - No resources will be deleted"
        echo
    fi
    
    # Warning about resource deletion
    if [[ "${DRY_RUN}" == "false" ]]; then
        log_warning "⚠️  WARNING: This script will delete cloud resources"
        log_warning "Make sure you have backed up any important data"
        echo
    fi
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        # If deleting entire project, skip individual resource deletion
        delete_project
    else
        # Delete individual resources
        cancel_running_builds
        delete_build_triggers
        delete_artifact_repositories
        delete_source_repositories
        delete_storage_buckets
        delete_logging_metrics
        delete_monitoring_policies
    fi
    
    # Display summary
    display_cleanup_summary
}

# Run main function
main "$@"
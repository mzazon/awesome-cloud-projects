#!/bin/bash

# Destruction script for Automated Code Refactoring with Gemini Code Assist and Source Repositories
# This script safely removes all resources created by the deployment script

set -euo pipefail

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

# Configuration variables
REQUIRED_PROJECT_ID=""
FORCE_DELETE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            REQUIRED_PROJECT_ID="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE=true
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
            echo "  --project-id ID  Project ID to clean up (required)"
            echo "  --force          Force deletion of all resources without individual confirmations"
            echo "  --dry-run        Show what would be deleted without making changes"
            echo "  --yes            Skip all confirmation prompts"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --project-id my-project-123"
            echo "  $0 --project-id my-project-123 --force --yes"
            echo "  $0 --project-id my-project-123 --dry-run"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${REQUIRED_PROJECT_ID}" ]]; then
    log_error "Project ID is required. Use --project-id <project-id>"
    exit 1
fi

export PROJECT_ID="${REQUIRED_PROJECT_ID}"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Prerequisites check completed"
}

# Discovery function to find resources
discover_resources() {
    log_info "Discovering resources in project ${PROJECT_ID}..."
    
    # Discover Source Repositories
    local repos
    repos=$(gcloud source repos list --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | grep -E "(refactor|automated)" || true)
    if [[ -n "${repos}" ]]; then
        DISCOVERED_REPOS=($repos)
        log_info "Found ${#DISCOVERED_REPOS[@]} source repositories: ${DISCOVERED_REPOS[*]}"
    else
        DISCOVERED_REPOS=()
        log_info "No source repositories found with refactor/automated naming pattern"
    fi
    
    # Discover Build Triggers
    local triggers
    triggers=$(gcloud builds triggers list --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | grep -E "(refactor|automated)" || true)
    if [[ -n "${triggers}" ]]; then
        DISCOVERED_TRIGGERS=($triggers)
        log_info "Found ${#DISCOVERED_TRIGGERS[@]} build triggers: ${DISCOVERED_TRIGGERS[*]}"
    else
        DISCOVERED_TRIGGERS=()
        log_info "No build triggers found with refactor/automated naming pattern"
    fi
    
    # Discover Service Accounts
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --project="${PROJECT_ID}" 2>/dev/null | grep -E "(refactor|automated)" || true)
    if [[ -n "${service_accounts}" ]]; then
        DISCOVERED_SERVICE_ACCOUNTS=($service_accounts)
        log_info "Found ${#DISCOVERED_SERVICE_ACCOUNTS[@]} service accounts: ${DISCOVERED_SERVICE_ACCOUNTS[*]}"
    else
        DISCOVERED_SERVICE_ACCOUNTS=()
        log_info "No service accounts found with refactor/automated naming pattern"
    fi
    
    # Discover ongoing builds
    local ongoing_builds
    ongoing_builds=$(gcloud builds list --ongoing --format="value(id)" --project="${PROJECT_ID}" 2>/dev/null || true)
    if [[ -n "${ongoing_builds}" ]]; then
        DISCOVERED_BUILDS=($ongoing_builds)
        log_info "Found ${#DISCOVERED_BUILDS[@]} ongoing builds: ${DISCOVERED_BUILDS[*]}"
    else
        DISCOVERED_BUILDS=()
        log_info "No ongoing builds found"
    fi
    
    log_success "Resource discovery completed"
}

# Confirmation function
confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will delete the following resources from project ${PROJECT_ID}:"
    echo ""
    
    if [[ ${#DISCOVERED_REPOS[@]} -gt 0 ]]; then
        echo "📁 Source Repositories (${#DISCOVERED_REPOS[@]}):"
        for repo in "${DISCOVERED_REPOS[@]}"; do
            echo "   - ${repo}"
        done
        echo ""
    fi
    
    if [[ ${#DISCOVERED_TRIGGERS[@]} -gt 0 ]]; then
        echo "🔧 Build Triggers (${#DISCOVERED_TRIGGERS[@]}):"
        for trigger in "${DISCOVERED_TRIGGERS[@]}"; do
            echo "   - ${trigger}"
        done
        echo ""
    fi
    
    if [[ ${#DISCOVERED_SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        echo "👤 Service Accounts (${#DISCOVERED_SERVICE_ACCOUNTS[@]}):"
        for sa in "${DISCOVERED_SERVICE_ACCOUNTS[@]}"; do
            echo "   - ${sa}"
        done
        echo ""
    fi
    
    if [[ ${#DISCOVERED_BUILDS[@]} -gt 0 ]]; then
        echo "🏗️  Ongoing Builds (${#DISCOVERED_BUILDS[@]}):"
        for build in "${DISCOVERED_BUILDS[@]}"; do
            echo "   - ${build}"
        done
        echo ""
    fi
    
    if [[ ${#DISCOVERED_REPOS[@]} -eq 0 && ${#DISCOVERED_TRIGGERS[@]} -eq 0 && ${#DISCOVERED_SERVICE_ACCOUNTS[@]} -eq 0 && ${#DISCOVERED_BUILDS[@]} -eq 0 ]]; then
        log_info "No resources found to delete."
        exit 0
    fi
    
    echo "⚠️  This action cannot be undone! ⚠️"
    echo ""
    
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Cancel ongoing builds
cancel_builds() {
    if [[ ${#DISCOVERED_BUILDS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Cancelling ongoing builds..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cancel ${#DISCOVERED_BUILDS[@]} builds"
        return
    fi
    
    for build_id in "${DISCOVERED_BUILDS[@]}"; do
        log_info "Cancelling build: ${build_id}"
        if gcloud builds cancel "${build_id}" --project="${PROJECT_ID}" --quiet 2>/dev/null; then
            log_success "✓ Cancelled build: ${build_id}"
        else
            log_warning "Failed to cancel build: ${build_id} (may have already completed)"
        fi
    done
    
    log_success "Build cancellation completed"
}

# Delete build triggers
delete_build_triggers() {
    if [[ ${#DISCOVERED_TRIGGERS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Deleting build triggers..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#DISCOVERED_TRIGGERS[@]} build triggers"
        return
    fi
    
    for trigger in "${DISCOVERED_TRIGGERS[@]}"; do
        log_info "Deleting build trigger: ${trigger}"
        
        if [[ "${FORCE_DELETE}" == "false" ]]; then
            read -p "Delete build trigger '${trigger}'? (y/N): " confirm
            if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
                log_info "Skipped: ${trigger}"
                continue
            fi
        fi
        
        if gcloud builds triggers delete "${trigger}" --project="${PROJECT_ID}" --quiet; then
            log_success "✓ Deleted build trigger: ${trigger}"
        else
            log_error "✗ Failed to delete build trigger: ${trigger}"
        fi
    done
    
    log_success "Build trigger deletion completed"
}

# Remove IAM policy bindings and delete service accounts
delete_service_accounts() {
    if [[ ${#DISCOVERED_SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Deleting service accounts and IAM bindings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#DISCOVERED_SERVICE_ACCOUNTS[@]} service accounts and their IAM bindings"
        return
    fi
    
    # IAM roles that might have been granted
    local roles=(
        "roles/source.writer"
        "roles/cloudaicompanion.user"
        "roles/cloudbuild.builds.editor"
    )
    
    for sa_email in "${DISCOVERED_SERVICE_ACCOUNTS[@]}"; do
        log_info "Processing service account: ${sa_email}"
        
        if [[ "${FORCE_DELETE}" == "false" ]]; then
            read -p "Delete service account '${sa_email}'? (y/N): " confirm
            if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
                log_info "Skipped: ${sa_email}"
                continue
            fi
        fi
        
        # Remove IAM policy bindings
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding: ${role} for ${sa_email}"
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" \
                --quiet 2>/dev/null; then
                log_success "✓ Removed IAM binding: ${role}"
            else
                log_warning "Could not remove IAM binding: ${role} (may not exist)"
            fi
        done
        
        # Delete service account
        log_info "Deleting service account: ${sa_email}"
        if gcloud iam service-accounts delete "${sa_email}" --project="${PROJECT_ID}" --quiet; then
            log_success "✓ Deleted service account: ${sa_email}"
        else
            log_error "✗ Failed to delete service account: ${sa_email}"
        fi
    done
    
    log_success "Service account deletion completed"
}

# Delete source repositories
delete_repositories() {
    if [[ ${#DISCOVERED_REPOS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Deleting source repositories..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#DISCOVERED_REPOS[@]} source repositories"
        return
    fi
    
    for repo in "${DISCOVERED_REPOS[@]}"; do
        log_info "Deleting source repository: ${repo}"
        
        if [[ "${FORCE_DELETE}" == "false" ]]; then
            read -p "Delete repository '${repo}' and ALL its code? (y/N): " confirm
            if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
                log_info "Skipped: ${repo}"
                continue
            fi
        fi
        
        if gcloud source repos delete "${repo}" --project="${PROJECT_ID}" --quiet; then
            log_success "✓ Deleted source repository: ${repo}"
        else
            log_error "✗ Failed to delete source repository: ${repo}"
        fi
    done
    
    log_success "Source repository deletion completed"
}

# Clean up local temporary files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local temporary files"
        return
    fi
    
    # Clean up any temporary directories that might contain cloned repos
    local temp_dirs
    temp_dirs=$(find /tmp -maxdepth 1 -type d -name "*refactor*" -o -name "*automated*" 2>/dev/null || true)
    
    if [[ -n "${temp_dirs}" ]]; then
        log_info "Found temporary directories to clean up"
        echo "${temp_dirs}" | while read -r temp_dir; do
            if [[ -d "${temp_dir}" ]]; then
                log_info "Removing temporary directory: ${temp_dir}"
                rm -rf "${temp_dir}"
                log_success "✓ Removed: ${temp_dir}"
            fi
        done
    fi
    
    log_success "Local cleanup completed"
}

# Optional: Disable APIs if no other resources depend on them
disable_apis_if_safe() {
    if [[ "${FORCE_DELETE}" == "false" ]]; then
        log_info "Skipping API disabling (use --force to disable APIs)"
        return
    fi
    
    log_info "Checking if APIs can be safely disabled..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would check if APIs can be safely disabled"
        return
    fi
    
    local apis_to_check=(
        "sourcerepo.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudaicompanion.googleapis.com"
    )
    
    for api in "${apis_to_check[@]}"; do
        # Check if there are other resources using this API
        case "${api}" in
            "sourcerepo.googleapis.com")
                local remaining_repos
                remaining_repos=$(gcloud source repos list --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | wc -l)
                if [[ "${remaining_repos}" -eq 0 ]]; then
                    log_info "Disabling ${api} (no remaining repositories)"
                    gcloud services disable "${api}" --project="${PROJECT_ID}" --quiet || log_warning "Failed to disable ${api}"
                else
                    log_info "Keeping ${api} enabled (${remaining_repos} repositories remain)"
                fi
                ;;
            "cloudbuild.googleapis.com")
                local remaining_triggers
                remaining_triggers=$(gcloud builds triggers list --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | wc -l)
                if [[ "${remaining_triggers}" -eq 0 ]]; then
                    log_info "Disabling ${api} (no remaining build triggers)"
                    gcloud services disable "${api}" --project="${PROJECT_ID}" --quiet || log_warning "Failed to disable ${api}"
                else
                    log_info "Keeping ${api} enabled (${remaining_triggers} build triggers remain)"
                fi
                ;;
            *)
                log_info "Skipping ${api} (manual review recommended)"
                ;;
        esac
    done
    
    log_success "API review completed"
}

# Generate cleanup summary
print_summary() {
    log_success "🎉 Cleanup completed successfully!"
    echo ""
    log_info "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Deleted Resources:"
    
    if [[ ${#DISCOVERED_BUILDS[@]} -gt 0 ]]; then
        echo "  - Cancelled ${#DISCOVERED_BUILDS[@]} ongoing builds"
    fi
    
    if [[ ${#DISCOVERED_TRIGGERS[@]} -gt 0 ]]; then
        echo "  - Deleted ${#DISCOVERED_TRIGGERS[@]} build triggers"
    fi
    
    if [[ ${#DISCOVERED_SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        echo "  - Deleted ${#DISCOVERED_SERVICE_ACCOUNTS[@]} service accounts and IAM bindings"
    fi
    
    if [[ ${#DISCOVERED_REPOS[@]} -gt 0 ]]; then
        echo "  - Deleted ${#DISCOVERED_REPOS[@]} source repositories"
    fi
    
    echo "  - Cleaned up local temporary files"
    echo ""
    
    if [[ "${FORCE_DELETE}" == "false" ]]; then
        log_info "💡 Tip: Use --force flag next time to skip individual confirmations"
    fi
    
    log_warning "Note: Project ${PROJECT_ID} still exists. To delete the entire project:"
    echo "  gcloud projects delete ${PROJECT_ID}"
}

# Main destruction function
main() {
    log_info "Starting cleanup of Automated Code Refactoring resources..."
    echo "Project: ${PROJECT_ID}"
    echo ""
    
    check_prerequisites
    discover_resources
    confirm_deletion
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Cleanup simulation completed"
        exit 0
    fi
    
    # Execute cleanup in safe order (dependencies first)
    cancel_builds
    delete_build_triggers
    delete_service_accounts
    delete_repositories
    cleanup_local_files
    disable_apis_if_safe
    
    print_summary
}

# Run main function
main "$@"
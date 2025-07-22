#!/bin/bash

# Code Review Automation with Firebase Studio and Cloud Source Repositories
# Cleanup Script for GCP
#
# This script removes all resources created by the deployment script:
# - Cloud Functions
# - Cloud Source Repositories
# - Configuration files
# - Generated artifacts

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Cleanup encountered an error. Check ${LOG_FILE} for details."
    error "Some resources may need manual cleanup."
    exit 1
}

trap cleanup_on_error ERR

# Display banner
show_banner() {
    echo -e "${RED}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Code Review Automation Cleanup               ║"
    echo "║                                                            ║"
    echo "║        ⚠️  This will delete all deployed resources  ⚠️        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --repository-name)
                REPOSITORY_NAME="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force                 Force cleanup without checking resource dependencies"
    echo "  --yes, -y              Skip confirmation prompts"
    echo "  --project PROJECT_ID   Specify the Google Cloud project ID"
    echo "  --region REGION        Specify the region (default: us-central1)"
    echo "  --function-name NAME   Specify the Cloud Function name to delete"
    echo "  --repository-name NAME Specify the repository name to delete"
    echo "  --help, -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --yes --force                     # Automated cleanup"
    echo "  $0 --project my-project --yes        # Cleanup specific project"
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active gcloud authentication found."
        error "Run: gcloud auth login"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Discover deployed resources
discover_resources() {
    info "Discovering deployed resources..."
    
    # Get current project if not specified
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            error "No Google Cloud project is set."
            error "Set a project with: gcloud config set project PROJECT_ID"
            error "Or use --project flag to specify project"
            exit 1
        fi
    fi
    
    # Set default values
    REGION="${REGION:-us-central1}"
    
    info "Project ID: ${PROJECT_ID}"
    info "Region: ${REGION}"
    
    # Discover Cloud Functions with code-review prefix
    local functions
    functions=$(gcloud functions list --regions="${REGION}" \
        --filter="name:code-review-trigger" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$functions" ]]; then
        DISCOVERED_FUNCTIONS=($functions)
        info "Discovered Cloud Functions: ${DISCOVERED_FUNCTIONS[*]}"
    else
        DISCOVERED_FUNCTIONS=()
        warn "No Cloud Functions found with code-review prefix"
    fi
    
    # Discover Source Repositories with intelligent-review prefix
    local repositories
    repositories=$(gcloud source repos list \
        --filter="name:intelligent-review-system" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$repositories" ]]; then
        DISCOVERED_REPOSITORIES=($repositories)
        info "Discovered Source Repositories: ${DISCOVERED_REPOSITORIES[*]}"
    else
        DISCOVERED_REPOSITORIES=()
        warn "No Source Repositories found with intelligent-review prefix"
    fi
    
    # Use command line arguments if provided
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        DISCOVERED_FUNCTIONS=("$FUNCTION_NAME")
    fi
    
    if [[ -n "${REPOSITORY_NAME:-}" ]]; then
        DISCOVERED_REPOSITORIES=("$REPOSITORY_NAME")
    fi
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo -e "\n${YELLOW}Resources to be deleted:${NC}"
    
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]]; then
        echo -e "${RED}Cloud Functions:${NC}"
        for func in "${DISCOVERED_FUNCTIONS[@]}"; do
            echo "  • $func"
        done
    fi
    
    if [[ ${#DISCOVERED_REPOSITORIES[@]} -gt 0 ]]; then
        echo -e "${RED}Source Repositories:${NC}"
        for repo in "${DISCOVERED_REPOSITORIES[@]}"; do
            echo "  • $repo"
        done
    fi
    
    echo -e "${RED}Local Files:${NC}"
    echo "  • Function source code"
    echo "  • Configuration files"
    echo "  • Generated scripts"
    
    echo ""
    echo -e "${YELLOW}⚠️  This action cannot be undone! ⚠️${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Delete Cloud Functions
delete_cloud_functions() {
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -eq 0 ]]; then
        info "No Cloud Functions to delete"
        return 0
    fi
    
    info "Deleting Cloud Functions..."
    
    for func in "${DISCOVERED_FUNCTIONS[@]}"; do
        info "Deleting Cloud Function: $func"
        
        if gcloud functions describe "$func" --region="${REGION}" &>/dev/null; then
            if gcloud functions delete "$func" \
                --region="${REGION}" \
                --quiet; then
                success "Deleted Cloud Function: $func"
            else
                if [[ "$FORCE_CLEANUP" == "true" ]]; then
                    warn "Failed to delete Cloud Function: $func (continuing due to --force)"
                else
                    error "Failed to delete Cloud Function: $func"
                    exit 1
                fi
            fi
        else
            warn "Cloud Function $func not found"
        fi
    done
}

# Delete Source Repositories
delete_source_repositories() {
    if [[ ${#DISCOVERED_REPOSITORIES[@]} -eq 0 ]]; then
        info "No Source Repositories to delete"
        return 0
    fi
    
    info "Deleting Source Repositories..."
    
    for repo in "${DISCOVERED_REPOSITORIES[@]}"; do
        info "Deleting Source Repository: $repo"
        
        if gcloud source repos describe "$repo" &>/dev/null; then
            # Additional confirmation for repository deletion
            if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
                echo -e "${YELLOW}⚠️  Repository '$repo' contains code that will be permanently lost!${NC}"
                read -p "Confirm deletion of repository '$repo' (type 'DELETE' to confirm): " repo_confirmation
                
                if [[ "$repo_confirmation" != "DELETE" ]]; then
                    warn "Skipping deletion of repository: $repo"
                    continue
                fi
            fi
            
            if gcloud source repos delete "$repo" --quiet; then
                success "Deleted Source Repository: $repo"
            else
                if [[ "$FORCE_CLEANUP" == "true" ]]; then
                    warn "Failed to delete Source Repository: $repo (continuing due to --force)"
                else
                    error "Failed to delete Source Repository: $repo"
                    exit 1
                fi
            fi
        else
            warn "Source Repository $repo not found"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local files_to_clean=(
        "${SCRIPT_DIR}/../function-source"
        "${SCRIPT_DIR}/../code-review-agent-config.json"
        "${SCRIPT_DIR}/../firebase-studio-agent.js"
        "${SCRIPT_DIR}/test-webhook.sh"
        "${SCRIPT_DIR}/validate-deployment.sh"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -e "$file" ]]; then
            info "Removing: $file"
            rm -rf "$file"
            success "Removed: $file"
        else
            warn "File not found: $file"
        fi
    done
    
    # Clean up temporary directories
    local temp_dirs=(
        "/tmp/code-review-repo-*"
    )
    
    for pattern in "${temp_dirs[@]}"; do
        for dir in $pattern; do
            if [[ -d "$dir" ]]; then
                info "Removing temporary directory: $dir"
                rm -rf "$dir"
                success "Removed: $dir"
            fi
        done
    done
}

# Verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Cloud Functions
    for func in "${DISCOVERED_FUNCTIONS[@]}"; do
        if gcloud functions describe "$func" --region="${REGION}" &>/dev/null; then
            error "Cloud Function still exists: $func"
            ((cleanup_issues++))
        fi
    done
    
    # Check Source Repositories
    for repo in "${DISCOVERED_REPOSITORIES[@]}"; do
        if gcloud source repos describe "$repo" &>/dev/null; then
            error "Source Repository still exists: $repo"
            ((cleanup_issues++))
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification completed successfully"
    else
        warn "Cleanup verification found $cleanup_issues remaining resources"
        warn "Manual cleanup may be required"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo -e "\n${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Cleanup Completed!                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}Cleanup Summary:${NC}"
    echo "• Project ID: ${PROJECT_ID}"
    echo "• Region: ${REGION}"
    echo "• Cloud Functions deleted: ${#DISCOVERED_FUNCTIONS[@]}"
    echo "• Source Repositories deleted: ${#DISCOVERED_REPOSITORIES[@]}"
    echo ""
    
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]]; then
        echo -e "${BLUE}Deleted Cloud Functions:${NC}"
        for func in "${DISCOVERED_FUNCTIONS[@]}"; do
            echo "  • $func"
        done
        echo ""
    fi
    
    if [[ ${#DISCOVERED_REPOSITORIES[@]} -gt 0 ]]; then
        echo -e "${BLUE}Deleted Source Repositories:${NC}"
        for repo in "${DISCOVERED_REPOSITORIES[@]}"; do
            echo "  • $repo"
        done
        echo ""
    fi
    
    echo -e "${BLUE}Additional Cleanup:${NC}"
    echo "• Local configuration files removed"
    echo "• Generated scripts removed"
    echo "• Function source code removed"
    echo "• Temporary directories cleaned"
    echo ""
    
    echo -e "${YELLOW}Post-Cleanup Notes:${NC}"
    echo "• APIs remain enabled (manual disable if needed)"
    echo "• IAM roles and permissions remain unchanged"
    echo "• Billing data is preserved for analysis"
    echo "• Cloud Build artifacts may remain in Cloud Storage"
    echo ""
    
    echo -e "${BLUE}Manual Cleanup (if needed):${NC}"
    echo "• Disable APIs: gcloud services disable [API_NAME]"
    echo "• Review IAM: gcloud iam service-accounts list"
    echo "• Check Storage: gcloud storage ls"
    echo "• Review Logs: gcloud logging sinks list"
    echo ""
    
    echo "Cleanup log saved to: ${LOG_FILE}"
}

# Check for remaining resources
check_remaining_resources() {
    info "Scanning for any remaining resources..."
    
    # Check for any Cloud Functions that might contain code-review in the name
    local remaining_functions
    remaining_functions=$(gcloud functions list --regions="${REGION}" \
        --filter="name~code-review" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_functions" ]]; then
        warn "Found additional Cloud Functions that may be related:"
        echo "$remaining_functions" | while read -r func; do
            echo "  • $func"
        done
        echo "Review these manually if they should be removed"
        echo ""
    fi
    
    # Check for any Source Repositories that might contain intelligent-review in the name
    local remaining_repos
    remaining_repos=$(gcloud source repos list \
        --filter="name~intelligent-review OR name~code-review" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_repos" ]]; then
        warn "Found additional Source Repositories that may be related:"
        echo "$remaining_repos" | while read -r repo; do
            echo "  • $repo"
        done
        echo "Review these manually if they should be removed"
        echo ""
    fi
}

# Main cleanup flow
main() {
    show_banner
    
    parse_arguments "$@"
    
    info "Starting cleanup at $(date)"
    info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    discover_resources
    confirm_cleanup
    
    delete_cloud_functions
    delete_source_repositories
    cleanup_local_files
    
    verify_cleanup
    check_remaining_resources
    show_cleanup_summary
    
    success "Code review automation system cleanup completed!"
}

# Execute main function
main "$@"
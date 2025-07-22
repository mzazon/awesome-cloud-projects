#!/bin/bash

#######################################################################
# Cleanup Script for Cloud-Based Development Workflows
# Recipe: Cloud Development Workflows with CloudShell
# 
# This script automates the cleanup of:
# - AWS CodeCommit repository
# - Local project files
# - Git configuration (optional)
# - Environment variables
#######################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/cleanup-cloudshell-codecommit-$(date +%Y%m%d-%H%M%S).log"
REPO_PREFIX="dev-workflow-demo"

# Default settings
FORCE_DELETE=false
CLEAN_GIT_CONFIG=false
PRESERVE_LOGS=false

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --repository-name NAME     Specify repository name to delete"
    echo "  --force                    Skip confirmation prompts"
    echo "  --clean-git-config         Remove Git global configuration"
    echo "  --preserve-logs            Keep log files after cleanup"
    echo "  --list-repositories        List repositories matching prefix"
    echo "  --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --force                           # Non-interactive cleanup"
    echo "  $0 --repository-name my-repo         # Clean specific repository"
    echo "  $0 --clean-git-config --force        # Full cleanup including Git config"
    echo "  $0 --list-repositories               # List matching repositories"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --repository-name)
                REPO_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --clean-git-config)
                CLEAN_GIT_CONFIG=true
                shift
                ;;
            --preserve-logs)
                PRESERVE_LOGS=true
                shift
                ;;
            --list-repositories)
                list_repositories
                exit 0
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# List repositories matching the prefix
list_repositories() {
    info "Listing repositories matching prefix '${REPO_PREFIX}'..."
    
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured."
    fi
    
    REPOS=$(aws codecommit list-repositories \
        --query "repositories[?starts_with(repositoryName, '${REPO_PREFIX}')].repositoryName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$REPOS" ]]; then
        info "No repositories found matching prefix '${REPO_PREFIX}'"
    else
        echo "Found repositories:"
        for repo in $REPOS; do
            echo "  - $repo"
        done
    fi
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured."
    fi
    
    success "Prerequisites validated"
}

# Get repository name interactively
get_repository_name() {
    if [[ -n "${REPO_NAME:-}" ]]; then
        info "Using specified repository name: ${REPO_NAME}"
        return
    fi
    
    info "Searching for repositories matching prefix '${REPO_PREFIX}'..."
    
    # Get list of repositories matching prefix
    REPOS=$(aws codecommit list-repositories \
        --query "repositories[?starts_with(repositoryName, '${REPO_PREFIX}')].repositoryName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$REPOS" ]]; then
        warning "No repositories found matching prefix '${REPO_PREFIX}'"
        if [[ "$FORCE_DELETE" == "false" ]]; then
            echo ""
            read -p "Enter repository name manually (or press Enter to skip): " REPO_NAME
            if [[ -z "$REPO_NAME" ]]; then
                info "No repository specified, skipping repository cleanup"
                return
            fi
        else
            info "No repository to clean up"
            return
        fi
    else
        # Convert to array
        REPO_ARRAY=($REPOS)
        
        if [[ ${#REPO_ARRAY[@]} -eq 1 ]]; then
            REPO_NAME="${REPO_ARRAY[0]}"
            info "Found single repository: ${REPO_NAME}"
        else
            if [[ "$FORCE_DELETE" == "true" ]]; then
                # In force mode, delete all matching repositories
                info "Force mode: will delete all matching repositories"
                for repo in "${REPO_ARRAY[@]}"; do
                    REPO_NAME="$repo"
                    delete_codecommit_repository
                    cleanup_local_files
                done
                return
            else
                echo ""
                echo "Multiple repositories found:"
                for i in "${!REPO_ARRAY[@]}"; do
                    echo "  $((i+1)). ${REPO_ARRAY[i]}"
                done
                echo "  $((${#REPO_ARRAY[@]}+1)). Delete all"
                echo "  $((${#REPO_ARRAY[@]}+2)). Skip repository cleanup"
                
                read -p "Select repository to delete (1-$((${#REPO_ARRAY[@]}+2))): " choice
                
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    if [[ $choice -ge 1 && $choice -le ${#REPO_ARRAY[@]} ]]; then
                        REPO_NAME="${REPO_ARRAY[$((choice-1))]}"
                    elif [[ $choice -eq $((${#REPO_ARRAY[@]}+1)) ]]; then
                        # Delete all repositories
                        for repo in "${REPO_ARRAY[@]}"; do
                            REPO_NAME="$repo"
                            delete_codecommit_repository
                            cleanup_local_files
                        done
                        return
                    elif [[ $choice -eq $((${#REPO_ARRAY[@]}+2)) ]]; then
                        info "Skipping repository cleanup"
                        return
                    else
                        error_exit "Invalid selection"
                    fi
                else
                    error_exit "Invalid input. Please enter a number."
                fi
            fi
        fi
    fi
    
    log "Selected repository: ${REPO_NAME}"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}WARNING: This will permanently delete the following:${NC}"
    echo "  - CodeCommit repository: ${REPO_NAME}"
    echo "  - Local project files: ~/projects/${REPO_NAME}"
    if [[ "$CLEAN_GIT_CONFIG" == "true" ]]; then
        echo "  - Git global configuration (user.name, user.email, credential helper)"
    fi
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed by user"
}

# Delete CodeCommit repository
delete_codecommit_repository() {
    if [[ -z "${REPO_NAME:-}" ]]; then
        info "No repository specified, skipping repository deletion"
        return
    fi
    
    info "Deleting CodeCommit repository: ${REPO_NAME}"
    
    # Check if repository exists
    if ! aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        warning "Repository ${REPO_NAME} does not exist or is already deleted"
        return
    fi
    
    # Delete the repository
    if aws codecommit delete-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        success "CodeCommit repository deleted: ${REPO_NAME}"
    else
        error_exit "Failed to delete CodeCommit repository: ${REPO_NAME}"
    fi
    
    # Wait a moment for deletion to propagate
    sleep 2
    
    # Verify deletion
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        warning "Repository may still be accessible (deletion propagating)"
    else
        success "Repository deletion confirmed"
    fi
}

# Clean up local files
cleanup_local_files() {
    if [[ -z "${REPO_NAME:-}" ]]; then
        info "No repository specified, skipping local file cleanup"
        return
    fi
    
    info "Cleaning up local files..."
    
    # Remove project directory
    PROJECT_DIR="${HOME}/projects/${REPO_NAME}"
    if [[ -d "$PROJECT_DIR" ]]; then
        rm -rf "$PROJECT_DIR" || error_exit "Failed to remove project directory"
        success "Removed project directory: ${PROJECT_DIR}"
    else
        info "Project directory does not exist: ${PROJECT_DIR}"
    fi
    
    # Remove empty projects directory if it exists and is empty
    if [[ -d "${HOME}/projects" ]]; then
        if [[ -z "$(ls -A "${HOME}/projects" 2>/dev/null)" ]]; then
            rmdir "${HOME}/projects" 2>/dev/null || true
            success "Removed empty projects directory"
        fi
    fi
    
    # Clean up test files
    TEST_FILES=(
        "${HOME}/test_persistence.txt"
        "${HOME}/.aws/cloudshell_test"
    )
    
    for file in "${TEST_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" && success "Removed test file: $file"
        fi
    done
}

# Clean Git configuration
clean_git_configuration() {
    if [[ "$CLEAN_GIT_CONFIG" != "true" ]]; then
        info "Skipping Git configuration cleanup (use --clean-git-config to enable)"
        return
    fi
    
    info "Cleaning Git global configuration..."
    
    # Store current values for logging
    CURRENT_USER=$(git config --global user.name 2>/dev/null || echo "not set")
    CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "not set")
    CURRENT_HELPER=$(git config --global credential.helper 2>/dev/null || echo "not set")
    
    log "Removing Git config - user.name: ${CURRENT_USER}"
    log "Removing Git config - user.email: ${CURRENT_EMAIL}"
    log "Removing Git config - credential.helper: ${CURRENT_HELPER}"
    
    # Remove Git configuration
    git config --global --unset user.name 2>/dev/null || true
    git config --global --unset user.email 2>/dev/null || true
    git config --global --unset credential.helper 2>/dev/null || true
    git config --global --unset credential.UseHttpPath 2>/dev/null || true
    
    success "Git global configuration cleaned"
}

# Clear environment variables
clear_environment_variables() {
    info "Clearing environment variables..."
    
    # List of variables to clear
    ENV_VARS=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "REPO_NAME"
        "REPO_URL"
        "DEFAULT_NAME"
        "DEBUG"
        "LOG_LEVEL"
        "LOG_FILE"
        "APP_NAME"
        "TIME_FORMAT"
    )
    
    for var in "${ENV_VARS[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
            log "Cleared environment variable: $var"
        fi
    done
    
    success "Environment variables cleared"
}

# Clean up log files
cleanup_logs() {
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        info "Preserving log files (--preserve-logs specified)"
        info "Current log file: ${LOG_FILE}"
        return
    fi
    
    info "Cleaning up log files..."
    
    # Find and remove old log files
    LOG_PATTERN="/tmp/*cloudshell-codecommit*.log"
    OLD_LOGS=$(find /tmp -name "*cloudshell-codecommit*.log" -type f 2>/dev/null || true)
    
    if [[ -n "$OLD_LOGS" ]]; then
        echo "$OLD_LOGS" | while read -r logfile; do
            if [[ "$logfile" != "$LOG_FILE" ]]; then
                rm -f "$logfile" && log "Removed old log file: $logfile"
            fi
        done
    fi
    
    success "Log cleanup completed"
}

# Validate cleanup
validate_cleanup() {
    info "Validating cleanup..."
    
    local validation_errors=0
    
    # Check repository deletion
    if [[ -n "${REPO_NAME:-}" ]]; then
        if aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
            warning "Repository ${REPO_NAME} still exists"
            ((validation_errors++))
        else
            success "Repository deletion confirmed"
        fi
    fi
    
    # Check local files
    if [[ -n "${REPO_NAME:-}" ]] && [[ -d "${HOME}/projects/${REPO_NAME}" ]]; then
        warning "Project directory still exists: ${HOME}/projects/${REPO_NAME}"
        ((validation_errors++))
    else
        success "Local files cleanup confirmed"
    fi
    
    # Check Git configuration if cleaned
    if [[ "$CLEAN_GIT_CONFIG" == "true" ]]; then
        if git config --global user.name &> /dev/null; then
            warning "Git user.name still configured"
            ((validation_errors++))
        fi
        if git config --global credential.helper &> /dev/null; then
            warning "Git credential helper still configured"
            ((validation_errors++))
        fi
        if [[ $validation_errors -eq 0 ]]; then
            success "Git configuration cleanup confirmed"
        fi
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        success "Cleanup validation completed successfully"
    else
        warning "Cleanup completed with ${validation_errors} validation warnings"
    fi
    
    log "Cleanup validation completed with ${validation_errors} issues"
}

# Main cleanup function
main() {
    echo -e "${BLUE}"
    echo "=============================================="
    echo "Cloud-Based Development Workflows Cleanup"
    echo "=============================================="
    echo -e "${NC}"
    
    log "Starting cleanup script"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run cleanup steps
    validate_prerequisites
    get_repository_name
    confirm_deletion
    delete_codecommit_repository
    cleanup_local_files
    clean_git_configuration
    clear_environment_variables
    validate_cleanup
    cleanup_logs
    
    echo -e "${GREEN}"
    echo "=============================================="
    echo "         CLEANUP COMPLETED SUCCESSFULLY"
    echo "=============================================="
    echo -e "${NC}"
    
    if [[ -n "${REPO_NAME:-}" ]]; then
        info "Deleted repository: ${REPO_NAME}"
    fi
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        info "Log file preserved: ${LOG_FILE}"
    fi
    
    echo ""
    echo "Cleanup Summary:"
    echo "✅ CodeCommit repository deleted"
    echo "✅ Local project files removed"
    if [[ "$CLEAN_GIT_CONFIG" == "true" ]]; then
        echo "✅ Git global configuration cleaned"
    else
        echo "ℹ️  Git configuration preserved (use --clean-git-config to clean)"
    fi
    echo "✅ Environment variables cleared"
    if [[ "$PRESERVE_LOGS" != "true" ]]; then
        echo "✅ Log files cleaned up"
    else
        echo "ℹ️  Log files preserved"
    fi
    
    log "Cleanup completed successfully"
}

# Execute main function with all arguments
main "$@"
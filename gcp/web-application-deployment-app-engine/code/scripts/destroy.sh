#!/bin/bash

# Cleanup script for GCP App Engine Web Application
# Recipe: Web Application Deployment with App Engine
# Version: 1.1
# Last Updated: 2025-01-12

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up resources created by the GCP App Engine deployment.

OPTIONS:
    -p, --project-id PROJECT_ID     Specify GCP project ID to clean up
    -f, --force                     Skip confirmation prompts
    -q, --quiet                     Suppress verbose output
    --delete-project                Delete the entire project (DESTRUCTIVE)
    --keep-project                  Keep project, only clean up App Engine resources
    -h, --help                      Show this help message
    --dry-run                       Show what would be done without executing

EXAMPLES:
    $0                                     # Interactive cleanup with prompts
    $0 --project-id my-project-123         # Clean up specific project
    $0 --force --delete-project            # Force delete entire project
    $0 --keep-project                      # Clean up App Engine only
    $0 --dry-run                          # Preview cleanup actions

NOTES:
    - App Engine applications cannot be deleted, only disabled
    - Use --delete-project to remove the entire project
    - Local application files are cleaned up by default

EOF
}

# Parse command line arguments
PROJECT_ID=""
FORCE=false
QUIET=false
DELETE_PROJECT=false
KEEP_PROJECT=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;
    esac
done

# Check for conflicting options
if [ "$DELETE_PROJECT" = true ] && [ "$KEEP_PROJECT" = true ]; then
    log_error "Cannot use --delete-project and --keep-project together"
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Determine project to clean up
determine_project() {
    log_info "Determining project to clean up..."
    
    # Try to get project from deployment info file
    if [ -z "$PROJECT_ID" ] && [ -f "deployment-info.txt" ]; then
        PROJECT_ID=$(grep "^PROJECT_ID=" deployment-info.txt 2>/dev/null | cut -d'=' -f2 || echo "")
        if [ -n "$PROJECT_ID" ]; then
            log_info "Found project ID in deployment-info.txt: $PROJECT_ID"
        fi
    fi
    
    # Try to get current project from gcloud config
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -n "$PROJECT_ID" ]; then
            log_info "Using current gcloud project: $PROJECT_ID"
        fi
    fi
    
    # If still no project ID, prompt user
    if [ -z "$PROJECT_ID" ] && [ "$FORCE" = false ]; then
        echo
        log_warning "No project ID specified or found in configuration"
        echo "Available projects:"
        gcloud projects list --format="table(projectId,name,projectNumber)" 2>/dev/null || true
        echo
        read -p "Enter the project ID to clean up: " PROJECT_ID
        
        if [ -z "$PROJECT_ID" ]; then
            log_error "No project ID provided"
            exit 1
        fi
    elif [ -z "$PROJECT_ID" ]; then
        log_error "No project ID specified and running in force mode"
        log_info "Use --project-id to specify the project to clean up"
        exit 1
    fi
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or is not accessible"
        exit 1
    fi
    
    export PROJECT_ID
    log_info "Will clean up project: $PROJECT_ID"
}

# Get user confirmation
get_confirmation() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo
    log_warning "This will clean up resources in project: $PROJECT_ID"
    
    if [ "$DELETE_PROJECT" = true ]; then
        log_warning "⚠️  DESTRUCTIVE ACTION: This will DELETE the entire project!"
        log_warning "⚠️  This action CANNOT be undone!"
        echo
        echo "Project details:"
        gcloud projects describe "$PROJECT_ID" --format="table(projectId,name,lifecycleState)" 2>/dev/null || true
    else
        log_info "This will:"
        log_info "  - Stop App Engine application versions"
        log_info "  - Clean up local application files"
        if [ "$KEEP_PROJECT" = false ]; then
            log_info "  - Suggest project deletion (manual step)"
        fi
    fi
    
    echo
    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Stop App Engine versions
cleanup_app_engine() {
    log_info "Cleaning up App Engine resources..."
    
    # Set the project
    gcloud config set project "$PROJECT_ID" --quiet
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would stop App Engine application versions"
        log_info "[DRY RUN] Would list and potentially delete non-serving versions"
        return 0
    fi
    
    # Check if App Engine is initialized
    if ! gcloud app describe --quiet &> /dev/null; then
        log_info "No App Engine application found in project $PROJECT_ID"
        return 0
    fi
    
    log_info "Found App Engine application"
    
    # List current versions
    log_info "Current App Engine versions:"
    gcloud app versions list --format="table(id,service,version,traffic_split)" || true
    
    # Get all versions for the default service
    local versions
    versions=$(gcloud app versions list --service=default --format="value(id)" 2>/dev/null || echo "")
    
    if [ -n "$versions" ]; then
        log_info "Stopping traffic to all versions..."
        
        # Stop serving traffic (this doesn't delete versions, just stops serving)
        for version in $versions; do
            log_info "Stopping version: $version"
            if ! gcloud app versions stop "$version" --service=default --quiet 2>/dev/null; then
                log_warning "Could not stop version $version (it may already be stopped)"
            fi
        done
        
        # Note: We don't delete versions here as the last version cannot be deleted
        # and deleting versions is usually not necessary for cost savings
        log_info "App Engine versions stopped (but not deleted)"
        
    else
        log_info "No App Engine versions found to clean up"
    fi
    
    log_success "App Engine cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local application files..."
    
    local files_to_clean=(
        "deployment-info.txt"
    )
    
    # Find webapp directories with random suffixes
    local webapp_dirs
    webapp_dirs=$(find . -maxdepth 1 -type d -name "webapp-*" 2>/dev/null || echo "")
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove deployment info file"
        if [ -n "$webapp_dirs" ]; then
            log_info "[DRY RUN] Would remove webapp directories: $webapp_dirs"
        fi
        return 0
    fi
    
    # Remove deployment info file
    for file in "${files_to_clean[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    # Remove webapp directories
    if [ -n "$webapp_dirs" ]; then
        for dir in $webapp_dirs; do
            if [ -d "$dir" ]; then
                log_info "Removing application directory: $dir"
                rm -rf "$dir"
                log_success "Removed: $dir"
            fi
        done
    else
        log_info "No webapp directories found to clean up"
    fi
    
    # Clean up any Python virtual environments
    if [ -d "venv" ]; then
        log_info "Removing Python virtual environment..."
        rm -rf venv
        log_success "Removed: venv"
    fi
    
    # Clean up Python cache files
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    
    log_success "Local file cleanup completed"
}

# Delete entire project
delete_project() {
    if [ "$DELETE_PROJECT" = false ]; then
        return 0
    fi
    
    log_info "Deleting entire project: $PROJECT_ID"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    # Final confirmation for project deletion
    if [ "$FORCE" = false ]; then
        echo
        log_warning "⚠️  FINAL CONFIRMATION REQUIRED ⚠️"
        log_warning "You are about to DELETE project: $PROJECT_ID"
        log_warning "This will permanently remove ALL resources in this project!"
        echo
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Deletion cancelled."
            exit 1
        fi
    fi
    
    log_info "Deleting project (this may take several minutes)..."
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project '$PROJECT_ID' has been deleted"
    else
        log_error "Failed to delete project '$PROJECT_ID'"
        log_info "You may need to delete it manually from the Cloud Console"
        return 1
    fi
}

# Provide manual cleanup instructions
provide_manual_instructions() {
    if [ "$DELETE_PROJECT" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo
    log_info "Manual cleanup options:"
    echo
    log_info "To delete the entire project (removes all resources and stops billing):"
    log_info "  gcloud projects delete $PROJECT_ID"
    echo
    log_info "To view the project in Cloud Console:"
    log_info "  https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    echo
    log_info "To check current App Engine quotas and usage:"
    log_info "  https://console.cloud.google.com/appengine/quotas?project=$PROJECT_ID"
    echo
    log_warning "Note: App Engine applications cannot be deleted, only disabled."
    log_warning "To completely stop billing, delete the entire project."
}

# Verify cleanup
verify_cleanup() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    # Check if project still exists (if we didn't delete it)
    if [ "$DELETE_PROJECT" = false ]; then
        if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log_info "Project still exists: $PROJECT_ID"
            
            # Check App Engine status
            if gcloud app describe --quiet &> /dev/null 2>&1; then
                local serving_versions
                serving_versions=$(gcloud app versions list --filter="traffic_split>0" --format="value(id)" 2>/dev/null | wc -l)
                if [ "$serving_versions" -eq 0 ]; then
                    log_success "No App Engine versions are currently serving traffic"
                else
                    log_warning "$serving_versions App Engine versions are still serving traffic"
                fi
            else
                log_info "No App Engine application found"
            fi
        else
            log_success "Project has been deleted: $PROJECT_ID"
        fi
    fi
    
    # Check local files
    local remaining_files=0
    [ -f "deployment-info.txt" ] && ((remaining_files++))
    [ -d "venv" ] && ((remaining_files++))
    
    # Count webapp directories
    local webapp_count
    webapp_count=$(find . -maxdepth 1 -type d -name "webapp-*" 2>/dev/null | wc -l)
    remaining_files=$((remaining_files + webapp_count))
    
    if [ "$remaining_files" -eq 0 ]; then
        log_success "All local files cleaned up"
    else
        log_warning "$remaining_files local files/directories may still exist"
    fi
    
    log_success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log_info "Starting GCP App Engine cleanup..."
    log_info "========================================"
    
    check_prerequisites
    determine_project
    get_confirmation
    cleanup_app_engine
    cleanup_local_files
    delete_project
    provide_manual_instructions
    verify_cleanup
    
    log_success "========================================"
    
    if [ "$DELETE_PROJECT" = true ] && [ "$DRY_RUN" = false ]; then
        log_success "Cleanup completed - project deleted!"
    elif [ "$DRY_RUN" = true ]; then
        log_info "Dry run completed - no actual changes made"
    else
        log_success "Cleanup completed!"
        log_info "App Engine resources have been stopped"
        log_info "Local files have been cleaned up"
        echo
        if [ "$KEEP_PROJECT" = false ]; then
            log_info "To completely remove all resources and stop billing:"
            log_info "  $0 --project-id $PROJECT_ID --delete-project"
        fi
    fi
}

# Handle interruption gracefully
trap 'log_warning "Cleanup interrupted by user"; exit 130' INT TERM

# Run main function
main "$@"
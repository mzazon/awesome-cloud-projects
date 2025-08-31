#!/bin/bash

# Random Quote API with Cloud Functions and Firestore - Cleanup Script
# This script removes all resources created by the deployment script
# Based on: random-quote-api-functions-firestore recipe

set -euo pipefail

# Color codes for output formatting
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
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-random-quote-api}"
DATABASE_ID="${DATABASE_ID:-quotes-db}"
FORCE="${FORCE:-false}"
DRY_RUN="${DRY_RUN:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-true}"

# Cleanup tracking
CLEANUP_ERRORS=0

# Error handling
handle_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        ((CLEANUP_ERRORS++))
        log_error "Operation failed with exit code $exit_code"
    fi
    return 0  # Don't exit on errors, continue cleanup
}

trap handle_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites satisfied"
}

# Auto-detect project if not provided
detect_project() {
    if [[ -z "$PROJECT_ID" ]]; then
        # Try to read from deployment info file
        if [[ -f "/tmp/quote-api-deployment-info.txt" ]]; then
            PROJECT_ID=$(grep "Project ID:" "/tmp/quote-api-deployment-info.txt" | cut -d' ' -f3)
            log_info "Auto-detected project from deployment info: $PROJECT_ID"
        else
            # Use current gcloud project
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
            if [[ -n "$PROJECT_ID" ]]; then
                log_info "Using current gcloud project: $PROJECT_ID"
            else
                log_error "No project ID specified and cannot auto-detect"
                log_error "Please specify PROJECT_ID or use --project-id option"
                exit 1
            fi
        fi
    fi
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible"
        exit 1
    fi
    
    log_info "Target project: $PROJECT_ID"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  • Project: $PROJECT_ID"
    echo "  • Cloud Function: $FUNCTION_NAME"
    echo "  • Firestore Database: $DATABASE_ID"
    echo "  • All associated data and configurations"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# List resources before deletion
list_resources() {
    log_info "Listing resources in project $PROJECT_ID..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would list and delete resources"
        return 0
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null || true
    
    # List Cloud Functions
    log_info "Cloud Functions:"
    if gcloud functions list --regions="$REGION" --filter="name:$FUNCTION_NAME" --format="table(name,status,trigger.httpsTrigger.url)" 2>/dev/null | grep -v "Listed 0 items"; then
        true  # Functions found
    else
        log_info "  No matching Cloud Functions found"
    fi
    
    # List Firestore databases
    log_info "Firestore Databases:"
    if gcloud firestore databases list --format="table(name,type,locationId)" 2>/dev/null | grep -v "Listed 0 items"; then
        true  # Databases found
    else
        log_info "  No Firestore databases found"
    fi
    
    echo
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet || handle_error
        
        log_success "Cloud Function deleted: $FUNCTION_NAME"
    else
        log_warning "Cloud Function $FUNCTION_NAME not found in region $REGION"
    fi
}

# Delete Firestore database
delete_firestore_database() {
    log_info "Deleting Firestore database: $DATABASE_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Firestore database: $DATABASE_ID"
        return 0
    fi
    
    # Check if database exists
    if gcloud firestore databases describe "$DATABASE_ID" &>/dev/null; then
        gcloud firestore databases delete "$DATABASE_ID" \
            --quiet || handle_error
        
        log_success "Firestore database deleted: $DATABASE_ID"
    else
        log_warning "Firestore database $DATABASE_ID not found"
    fi
}

# Delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        log_info "Skipping project deletion (DELETE_PROJECT=false)"
        return 0
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    # Additional confirmation for project deletion
    if [[ "$FORCE" != "true" ]]; then
        echo
        log_warning "You are about to delete the entire project: $PROJECT_ID"
        log_warning "This action cannot be undone!"
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed"
            log_info "Project deletion cancelled"
            return 1
        fi
    fi
    
    gcloud projects delete "$PROJECT_ID" \
        --quiet || handle_error
    
    log_success "Project deleted: $PROJECT_ID"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "/tmp/quote-api-deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove: $file"
            else
                rm -f "$file"
                log_info "Removed: $file"
            fi
        fi
    done
    
    # Clean up any temporary function directories
    if [[ "$DRY_RUN" != "true" ]]; then
        find /tmp -name "quote-function-*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    # Only verify if project still exists (if we didn't delete it)
    if [[ "$DELETE_PROJECT" != "true" ]] && gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null || true
        
        # Check for remaining functions
        local remaining_functions
        remaining_functions=$(gcloud functions list --regions="$REGION" --filter="name:$FUNCTION_NAME" --format="value(name)" 2>/dev/null | wc -l)
        
        if [[ "$remaining_functions" -gt 0 ]]; then
            log_warning "$remaining_functions Cloud Function(s) still exist"
            ((CLEANUP_ERRORS++))
        fi
        
        # Check for remaining databases
        if gcloud firestore databases describe "$DATABASE_ID" &>/dev/null; then
            log_warning "Firestore database $DATABASE_ID still exists"
            ((CLEANUP_ERRORS++))
        fi
    fi
    
    if [[ $CLEANUP_ERRORS -eq 0 ]]; then
        log_success "Cleanup verification passed"
    else
        log_warning "Cleanup completed with $CLEANUP_ERRORS warning(s)"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Random Quote API cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be deleted"
    fi
    
    check_prerequisites
    detect_project
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Database ID: $DATABASE_ID"
    log_info "  Delete Project: $DELETE_PROJECT"
    log_info "  Force Mode: $FORCE"
    
    confirm_destruction
    list_resources
    
    # Perform cleanup in reverse order of creation
    delete_cloud_function
    delete_firestore_database
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    fi
    
    cleanup_local_files
    verify_cleanup
    
    if [[ $CLEANUP_ERRORS -eq 0 ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_warning "Cleanup completed with $CLEANUP_ERRORS error(s)"
        log_info "You may need to manually verify and clean up remaining resources"
        exit 1
    fi
    
    log_info "All Random Quote API resources have been removed"
}

# Script usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Random Quote API resources created by the deployment script

OPTIONS:
    -p, --project-id       GCP Project ID (auto-detected if not specified)
    -r, --region           GCP region (default: us-central1)
    -f, --function-name    Cloud Function name (default: random-quote-api)
    -d, --database-id      Firestore database ID (default: quotes-db)
    --no-delete-project    Keep the project, only delete resources within it
    --force                Skip confirmation prompts
    --dry-run              Show what would be done without making changes
    -h, --help             Show this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID             Override project ID
    REGION                 Override region
    FUNCTION_NAME          Override function name
    DATABASE_ID            Override database ID
    DELETE_PROJECT         Set to 'false' to preserve project (default: true)
    FORCE                  Set to 'true' to skip confirmations
    DRY_RUN               Set to 'true' for dry run mode

EXAMPLES:
    $0                                          # Auto-detect and cleanup
    $0 --dry-run                               # Preview what would be deleted
    $0 -p my-project-12345                     # Specify project explicitly
    $0 --no-delete-project                     # Keep project, delete resources only
    $0 --force                                 # Skip all confirmation prompts
    PROJECT_ID=my-project $0 --force           # Use environment variable

SAFETY FEATURES:
    • Requires explicit confirmation before deletion
    • Lists resources before deletion
    • Supports dry-run mode to preview changes
    • Can preserve project while cleaning resources
    • Continues cleanup even if individual operations fail

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -f|--function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        -d|--database-id)
            DATABASE_ID="$2"
            shift 2
            ;;
        --no-delete-project)
            DELETE_PROJECT="false"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
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

# Run the main cleanup
main "$@"
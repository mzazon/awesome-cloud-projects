#!/bin/bash

# Tax Calculator API Cleanup Script
# Removes all Cloud Functions and Firestore resources
# Version: 1.0

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

# Configuration
DEFAULT_FUNCTION_NAME="tax-calculator"

# Script options
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
PROJECT_ID=""
REGION=""
FUNCTION_NAME="${DEFAULT_FUNCTION_NAME}"
DELETE_PROJECT=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Tax Calculator API resources (Cloud Functions and Firestore)

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP region (auto-detect if not specified)
    -f, --function-name NAME      Function name (default: ${DEFAULT_FUNCTION_NAME})
    -d, --dry-run                 Show what would be deleted without executing
    -F, --force                   Skip individual resource confirmations
    -y, --yes                     Skip all confirmations (dangerous!)
    --delete-project              Delete the entire project (destructive!)
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project-123               # Clean up with confirmations
    $0 --project-id my-project --force           # Clean up without individual confirmations
    $0 --project-id my-project --delete-project  # Delete entire project
    $0 --dry-run                                 # Preview what would be deleted

WARNING: This script will permanently delete resources and data!
EOF
}

# Parse command line arguments
parse_args() {
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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -F|--force)
                FORCE_DELETE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                FORCE_DELETE=true
                shift
                ;;
            --delete-project)
                DELETE_PROJECT=true
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
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate project ID is provided
    if [[ -z "$PROJECT_ID" ]]; then
        # Try to get from environment file
        if [[ -f "function-urls.env" ]]; then
            source function-urls.env
            log_info "Using PROJECT_ID from function-urls.env: $PROJECT_ID"
        else
            log_error "Project ID is required. Use --project-id or ensure function-urls.env exists"
            exit 1
        fi
    fi
    
    # Validate project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible"
        exit 1
    fi
    
    # Set project
    gcloud config set project "$PROJECT_ID"
    
    # Auto-detect region if not provided
    if [[ -z "$REGION" ]]; then
        if [[ -f "function-urls.env" ]]; then
            source function-urls.env
            if [[ -n "${REGION:-}" ]]; then
                log_info "Using REGION from function-urls.env: $REGION"
            fi
        fi
        
        # Try to detect from existing functions
        if [[ -z "$REGION" ]]; then
            REGION=$(gcloud functions list --filter="name:$FUNCTION_NAME" --format="value(region)" --limit=1 2>/dev/null || echo "")
            if [[ -n "$REGION" ]]; then
                log_info "Auto-detected region from existing function: $REGION"
            else
                REGION="us-central1"  # Default fallback
                log_warning "Could not detect region, using default: $REGION"
            fi
        fi
    fi
    
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log_success "Prerequisites check passed"
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Function Name: $FUNCTION_NAME"
}

# Confirmation prompts
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING:${NC} About to $action: $resource"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipped $action for $resource"
        return 1
    fi
    return 0
}

# List resources to be deleted
list_resources() {
    log_info "Scanning for resources to delete..."
    
    # Check for Cloud Functions
    local functions=$(gcloud functions list --filter="name:$FUNCTION_NAME OR name:${FUNCTION_NAME}-history" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$functions" ]]; then
        log_info "Found Cloud Functions:"
        echo "$functions" | while read -r func; do
            echo "  - $func"
        done
    else
        log_info "No Cloud Functions found matching pattern"
    fi
    
    # Check for Firestore database
    if gcloud firestore databases describe --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        log_info "Found Firestore database in region: $REGION"
    else
        log_info "No Firestore database found"
    fi
    
    # Check for local files
    local local_files=()
    [[ -d "tax-calculator-function" ]] && local_files+=("tax-calculator-function/")
    [[ -f "function-urls.env" ]] && local_files+=("function-urls.env")
    [[ -f "firestore.rules" ]] && local_files+=("firestore.rules")
    
    if [[ ${#local_files[@]} -gt 0 ]]; then
        log_info "Found local files to clean up:"
        printf '  - %s\n' "${local_files[@]}"
    else
        log_info "No local files to clean up"
    fi
}

# Delete Cloud Functions
delete_functions() {
    local functions_to_delete=("$FUNCTION_NAME" "${FUNCTION_NAME}-history")
    
    for func in "${functions_to_delete[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cloud Function: $func"
            continue
        fi
        
        # Check if function exists
        if gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
            if confirm_action "delete Cloud Function" "$func"; then
                log_info "Deleting Cloud Function: $func"
                if gcloud functions delete "$func" --region="$REGION" --project="$PROJECT_ID" --quiet; then
                    log_success "Deleted Cloud Function: $func"
                else
                    log_error "Failed to delete Cloud Function: $func"
                fi
            fi
        else
            log_info "Cloud Function $func not found (may already be deleted)"
        fi
    done
}

# Delete Firestore data
delete_firestore_data() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Firestore collections"
        return
    fi
    
    # Check if Firestore database exists
    if ! gcloud firestore databases describe --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        log_info "No Firestore database found to clean up"
        return
    fi
    
    if confirm_action "delete Firestore data" "tax_calculations collection"; then
        log_info "Deleting Firestore collections..."
        
        # Delete tax_calculations collection
        if gcloud firestore collections delete tax_calculations --project="$PROJECT_ID" --recursive --quiet 2>/dev/null; then
            log_success "Deleted tax_calculations collection"
        else
            log_warning "Failed to delete tax_calculations collection (may not exist)"
        fi
        
        # Note: We don't delete the entire Firestore database as it's harder to recreate
        log_info "Firestore database preserved (only collections deleted)"
    fi
}

# Delete local files
delete_local_files() {
    local files_to_delete=(
        "tax-calculator-function"
        "function-urls.env"
        "firestore.rules"
        "add_sample_data.py"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ -e "$file" ]]; then
                log_info "[DRY RUN] Would delete local file/directory: $file"
            fi
            continue
        fi
        
        if [[ -e "$file" ]]; then
            if confirm_action "delete local file/directory" "$file"; then
                log_info "Deleting local file/directory: $file"
                if rm -rf "$file"; then
                    log_success "Deleted: $file"
                else
                    log_error "Failed to delete: $file"
                fi
            fi
        fi
    done
}

# Delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete entire project: $PROJECT_ID"
        return
    fi
    
    log_warning "DANGER: About to delete the entire project: $PROJECT_ID"
    log_warning "This will permanently delete ALL resources in the project!"
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo -e "${RED}This action cannot be undone!${NC}"
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            log_error "Project ID did not match. Aborting project deletion."
            return 1
        fi
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deletion initiated: $PROJECT_ID"
        log_info "Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project: $PROJECT_ID"
    fi
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$DELETE_PROJECT" == "true" ]]; then
        return
    fi
    
    log_info "Verifying cleanup..."
    
    # Check functions are deleted
    local remaining_functions=$(gcloud functions list --filter="name:$FUNCTION_NAME OR name:${FUNCTION_NAME}-history" --format="value(name)" 2>/dev/null || echo "")
    if [[ -z "$remaining_functions" ]]; then
        log_success "All Cloud Functions removed"
    else
        log_warning "Some functions may still exist: $remaining_functions"
    fi
    
    # Check local files
    local remaining_files=()
    [[ -d "tax-calculator-function" ]] && remaining_files+=("tax-calculator-function/")
    [[ -f "function-urls.env" ]] && remaining_files+=("function-urls.env")
    [[ -f "firestore.rules" ]] && remaining_files+=("firestore.rules")
    
    if [[ ${#remaining_files[@]} -eq 0 ]]; then
        log_success "All local files cleaned up"
    else
        log_warning "Some local files remain: ${remaining_files[*]}"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Tax Calculator API cleanup..."
    
    parse_args "$@"
    check_prerequisites
    
    echo
    echo "=== Cleanup Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo "Delete Project: $DELETE_PROJECT"
    echo "Dry Run: $DRY_RUN"
    echo "Force Delete: $FORCE_DELETE"
    echo
    
    list_resources
    
    if [[ "$DRY_RUN" != "true" ]] && [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo
        log_warning "This will permanently delete the listed resources!"
        read -p "Continue with cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    echo
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    else
        delete_functions
        delete_firestore_data
        delete_local_files
        verify_cleanup
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Cleanup preview completed"
        echo
        echo "To run actual cleanup:"
        echo "  $0 --project-id $PROJECT_ID --region $REGION"
    elif [[ "$DELETE_PROJECT" == "true" ]]; then
        log_success "Project deletion initiated!"
        echo
        echo "=== Project Deletion Summary ==="
        echo "Project ID: $PROJECT_ID"
        echo "Status: Deletion in progress"
        echo "Note: Complete deletion may take several minutes"
    else
        log_success "Tax Calculator API cleanup completed!"
        echo
        echo "=== Cleanup Summary ==="
        echo "Project ID: $PROJECT_ID (preserved)"
        echo "Cloud Functions: Deleted"
        echo "Firestore Data: Deleted"
        echo "Local Files: Cleaned up"
        echo
        echo "The project and Firestore database have been preserved."
        echo "To delete the entire project, run: $0 --project-id $PROJECT_ID --delete-project"
    fi
}

# Error handler
error_handler() {
    log_error "Cleanup failed at line $1"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Run main function
main "$@"
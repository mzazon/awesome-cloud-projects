#!/bin/bash
#
# Weather Information API with Cloud Functions - Cleanup Script
# 
# This script removes all resources created by the Weather Information API
# deployment, including Cloud Functions, temporary files, and configurations.
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   --project-id <id>    Override default project ID
#   --region <region>    Override default region (default: us-central1)
#   --function-name <name> Override default function name (default: weather-api)
#   --force             Skip confirmation prompts
#   --dry-run           Show what would be deleted without executing
#   --help              Show this help message
#

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="weather-api"
DRY_RUN=false
FORCE=false

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Help function
show_help() {
    cat << EOF
Weather Information API with Cloud Functions - Cleanup Script

This script removes all resources created by the Weather Information API
deployment, including Cloud Functions, temporary files, and configurations.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --project-id <id>        Override default project ID
    --region <region>        Override default region (default: us-central1)
    --function-name <name>   Override default function name (default: weather-api)
    --force                 Skip confirmation prompts
    --dry-run               Show what would be deleted without executing
    --help                  Show this help message

EXAMPLES:
    # Interactive cleanup with prompts
    $0

    # Force cleanup without prompts
    $0 --force

    # Cleanup specific function in custom project
    $0 --project-id my-weather-project --function-name my-weather-api

    # Dry run to see what would be deleted
    $0 --dry-run

SAFETY FEATURES:
    - Confirmation prompts before destructive actions (unless --force)
    - Dry run mode to preview actions
    - Comprehensive logging of all operations
    - Graceful handling of already-deleted resources

For more information, visit: https://cloud.google.com/functions/docs
EOF
}

# Parse command line arguments
parse_args() {
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
            --function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
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
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Set default values and detect current configuration
setup_environment() {
    log_info "Setting up environment and detecting current configuration..."

    # Set defaults if not provided
    REGION=${REGION:-$DEFAULT_REGION}
    FUNCTION_NAME=${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}
    
    # Try to detect current project if not provided
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "$PROJECT_ID" ]]; then
            log_info "Using current gcloud project: $PROJECT_ID"
        else
            log_error "No project ID specified and no default project configured"
            log_error "Please specify --project-id or run: gcloud config set project PROJECT_ID"
            exit 1
        fi
    fi

    # Export environment variables
    export PROJECT_ID
    export REGION
    export FUNCTION_NAME

    log_success "Environment configured - Project: $PROJECT_ID, Region: $REGION, Function: $FUNCTION_NAME"
}

# Confirm destructive actions
confirm_deletion() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    log_warning "This action will permanently delete the following resources:"
    echo "   • Cloud Function: $FUNCTION_NAME (in $REGION)"
    echo "   • Any local temporary files"
    echo "   • Associated logs and metrics"
    echo
    
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
}

# Check if function exists
function_exists() {
    local function_name="$1"
    local region="$2"
    local project_id="$3"
    
    gcloud functions describe "$function_name" \
        --region="$region" \
        --project="$project_id" \
        --quiet >/dev/null 2>&1
}

# Delete Cloud Function
delete_function() {
    log_info "Checking for Cloud Function: $FUNCTION_NAME..."

    if [[ "$DRY_RUN" == "true" ]]; then
        if function_exists "$FUNCTION_NAME" "$REGION" "$PROJECT_ID"; then
            log_info "[DRY RUN] Would delete Cloud Function: $FUNCTION_NAME in $REGION"
        else
            log_info "[DRY RUN] Cloud Function $FUNCTION_NAME not found - nothing to delete"
        fi
        return 0
    fi

    # Check if function exists before attempting deletion
    if ! function_exists "$FUNCTION_NAME" "$REGION" "$PROJECT_ID"; then
        log_info "Cloud Function $FUNCTION_NAME not found in region $REGION"
        log_info "Function may have been already deleted or never created"
        return 0
    fi

    log_info "Deleting Cloud Function: $FUNCTION_NAME..."
    
    if gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet; then
        log_success "Cloud Function deleted successfully"
    else
        local exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            log_warning "Function may have been already deleted or not found"
        else
            log_error "Failed to delete Cloud Function (exit code: $exit_code)"
            return 1
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up:"
        # Look for weather-function directories
        local weather_dirs
        mapfile -t weather_dirs < <(find . -maxdepth 1 -type d -name "weather-function*" 2>/dev/null)
        if [[ ${#weather_dirs[@]} -gt 0 ]]; then
            for dir in "${weather_dirs[@]}"; do
                log_info "  - Directory: $dir"
            done
        else
            log_info "  - No weather-function directories found"
        fi
        log_info "  - Environment variables: PROJECT_ID, REGION, FUNCTION_NAME, FUNCTION_URL"
        return 0
    fi

    local cleanup_count=0

    # Remove any weather-function directories created during deployment
    local weather_dirs
    mapfile -t weather_dirs < <(find . -maxdepth 1 -type d -name "weather-function*" 2>/dev/null)
    
    for dir in "${weather_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Removing directory: $dir"
            rm -rf "$dir"
            ((cleanup_count++))
        fi
    done

    # Clean up environment variables
    unset PROJECT_ID REGION FUNCTION_NAME FUNCTION_URL 2>/dev/null || true

    if [[ $cleanup_count -gt 0 ]]; then
        log_success "Cleaned up $cleanup_count local directories and environment variables"
    else
        log_info "No local files found to clean up"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi

    log_info "Verifying cleanup completion..."

    # Check if function still exists
    if function_exists "$FUNCTION_NAME" "$REGION" "$PROJECT_ID"; then
        log_warning "Cloud Function $FUNCTION_NAME still exists - cleanup may be incomplete"
        return 1
    fi

    # Check for remaining local files
    local remaining_dirs
    mapfile -t remaining_dirs < <(find . -maxdepth 1 -type d -name "weather-function*" 2>/dev/null)
    
    if [[ ${#remaining_dirs[@]} -gt 0 ]]; then
        log_warning "Some local directories still exist:"
        for dir in "${remaining_dirs[@]}"; do
            log_warning "  - $dir"
        done
        return 1
    fi

    log_success "Cleanup verification completed - all resources removed"
    return 0
}

# Display cleanup summary
show_cleanup_summary() {
    echo
    echo "========================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN CLEANUP SUMMARY"
        echo "The following would be deleted:"
        echo "   • Cloud Function: $FUNCTION_NAME (if exists)"
        echo "   • Local weather-function directories"
        echo "   • Environment variables"
        echo
        echo "Run without --dry-run to perform actual cleanup."
    else
        log_success "CLEANUP COMPLETED"
        echo
        echo "📋 Cleanup Summary:"
        echo "   Project ID: $PROJECT_ID"
        echo "   Function: $FUNCTION_NAME (deleted)"
        echo "   Region: $REGION"
        echo "   Local files: Cleaned up"
        echo
        echo "💡 Notes:"
        echo "   • All function logs remain in Cloud Logging"
        echo "   • No ongoing costs from deleted resources"
        echo "   • Function URL is no longer accessible"
        echo
        echo "🔄 To redeploy, run: ./deploy.sh"
    fi
    echo "========================================"
}

# Handle script interruption
handle_interrupt() {
    echo
    log_warning "Script interrupted by user"
    log_info "Cleanup may be incomplete - you may need to run this script again"
    exit 130
}

# Main cleanup function
main() {
    # Set up interrupt handler
    trap handle_interrupt SIGINT SIGTERM

    echo "========================================"
    echo "Weather Information API Cleanup"
    echo "========================================"
    echo

    parse_args "$@"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
        echo
    fi

    check_prerequisites
    setup_environment
    confirm_deletion

    local cleanup_failed=false

    # Perform cleanup operations
    if ! delete_function; then
        cleanup_failed=true
        log_error "Function deletion failed"
    fi

    cleanup_local_files

    # Verify cleanup only if not in dry run mode and no failures
    if [[ "$DRY_RUN" == "false" && "$cleanup_failed" == "false" ]]; then
        if ! verify_cleanup; then
            log_warning "Cleanup verification found issues"
            cleanup_failed=true
        fi
    fi

    show_cleanup_summary

    # Exit with appropriate code
    if [[ "$cleanup_failed" == "true" ]]; then
        echo
        log_error "Cleanup completed with some errors"
        log_error "Please check the output above and run the script again if needed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
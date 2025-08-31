#!/bin/bash

# =============================================================================
# Weather API with Cloud Functions and Storage - Cleanup Script
# =============================================================================
# This script removes all resources created by the Weather API deployment
# Based on the recipe: Weather API with Cloud Functions and Storage
# =============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="weather-api"

# Global variables
PROJECT_ID=""
REGION=""
FUNCTION_NAME=""
BUCKET_NAME=""
DRY_RUN=false
FORCE=false
AUTO_DISCOVER=false

# =============================================================================
# Utility Functions
# =============================================================================

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

print_banner() {
    echo -e "${RED}"
    echo "============================================================================="
    echo "           Weather API with Cloud Functions and Storage"
    echo "                         Cleanup Script"
    echo "============================================================================="
    echo -e "${NC}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Weather API infrastructure from Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION             GCP Region (default: $DEFAULT_REGION)
    -f, --function-name NAME        Cloud Function name (default: $DEFAULT_FUNCTION_NAME)
    -b, --bucket-name NAME          Storage bucket name (required unless --auto-discover)
    -a, --auto-discover             Automatically discover resources to delete
    -d, --dry-run                   Show what would be deleted without executing
    --force                         Skip confirmation prompts
    -h, --help                      Show this help message

EXAMPLES:
    $0 --project-id my-weather-project --bucket-name weather-cache-123456-abc123
    $0 -p my-weather-project -b weather-cache-123456-abc123 --dry-run
    $0 --project-id my-project --auto-discover --force

NOTES:
    - Requires gcloud CLI to be installed and authenticated
    - Deletes Cloud Function, Storage bucket, and all cached data
    - Use --dry-run to preview what will be deleted
    - Use --auto-discover to find resources automatically (may be slower)
    - Deletion is irreversible - use with caution

EOF
}

# =============================================================================
# Prerequisites and Validation Functions
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n 1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil not found. Please install Google Cloud SDK with storage components."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

validate_project() {
    log_info "Validating project: $PROJECT_ID"

    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi

    # Set the project as active
    gcloud config set project "$PROJECT_ID"
    log_success "Project validated: $PROJECT_ID"
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

discover_resources() {
    log_info "Auto-discovering Weather API resources..."

    # Find Cloud Functions that match the pattern
    local discovered_functions
    discovered_functions=$(gcloud functions list \
        --filter="name:weather*" \
        --format="value(name)" 2>/dev/null || echo "")

    if [[ -n "$discovered_functions" ]]; then
        log_info "Discovered Cloud Functions:"
        echo "$discovered_functions" | while read -r func; do
            log_info "  - $func"
        done
        
        # Use the first discovered function if FUNCTION_NAME not specified
        if [[ -z "$FUNCTION_NAME" ]] || [[ "$FUNCTION_NAME" == "$DEFAULT_FUNCTION_NAME" ]]; then
            FUNCTION_NAME=$(echo "$discovered_functions" | head -n 1)
            log_info "Auto-selected function: $FUNCTION_NAME"
        fi
    fi

    # Find Storage buckets that match the pattern
    local discovered_buckets
    discovered_buckets=$(gsutil ls | grep -E "weather.*cache" || echo "")

    if [[ -n "$discovered_buckets" ]]; then
        log_info "Discovered Storage buckets:"
        echo "$discovered_buckets" | while read -r bucket; do
            log_info "  - $bucket"
        done
        
        # Use the first discovered bucket if BUCKET_NAME not specified
        if [[ -z "$BUCKET_NAME" ]]; then
            BUCKET_NAME=$(echo "$discovered_buckets" | head -n 1 | sed 's|gs://||' | sed 's|/||')
            log_info "Auto-selected bucket: $BUCKET_NAME"
        fi
    fi

    # Validate we found something to delete
    if [[ -z "$FUNCTION_NAME" ]] && [[ -z "$BUCKET_NAME" ]]; then
        log_warning "No Weather API resources discovered automatically"
        log_info "Try specifying resources manually or check if they exist in project: $PROJECT_ID"
        return 1
    fi

    log_success "Resource discovery completed"
}

check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local region="${3:-}"

    case "$resource_type" in
        "function")
            gcloud functions describe "$resource_name" --region="$region" &> /dev/null
            ;;
        "bucket")
            gsutil ls -b "gs://$resource_name" &> /dev/null
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# =============================================================================
# Cleanup Functions
# =============================================================================

delete_cloud_function() {
    if [[ -z "$FUNCTION_NAME" ]]; then
        log_info "No Cloud Function specified, skipping"
        return 0
    fi

    log_info "Checking for Cloud Function: $FUNCTION_NAME"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete function: $FUNCTION_NAME in region $REGION"
        return 0
    fi

    # Check if function exists
    if ! check_resource_exists "function" "$FUNCTION_NAME" "$REGION"; then
        log_warning "Cloud Function '$FUNCTION_NAME' not found in region '$REGION'"
        
        # Try to find it in other regions
        log_info "Searching for function in other regions..."
        local found_regions
        found_regions=$(gcloud functions list \
            --filter="name:$FUNCTION_NAME" \
            --format="value(name.segment(3))" 2>/dev/null || echo "")
        
        if [[ -n "$found_regions" ]]; then
            local found_region
            found_region=$(echo "$found_regions" | head -n 1)
            log_info "Found function in region: $found_region"
            
            if [[ "$FORCE" == "false" ]]; then
                read -p "Delete function from region $found_region instead? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Skipping function deletion"
                    return 0
                fi
            fi
            
            REGION="$found_region"
        else
            log_warning "Function not found in any region, skipping"
            return 0
        fi
    fi

    log_info "Deleting Cloud Function: $FUNCTION_NAME from region: $REGION"
    
    gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --quiet || {
        log_error "Failed to delete Cloud Function: $FUNCTION_NAME"
        return 1
    }

    log_success "Cloud Function deleted: $FUNCTION_NAME"
}

delete_storage_bucket() {
    if [[ -z "$BUCKET_NAME" ]]; then
        log_info "No Storage bucket specified, skipping"
        return 0
    fi

    log_info "Checking for Storage bucket: gs://$BUCKET_NAME"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete bucket: gs://$BUCKET_NAME and all contents"
        return 0
    fi

    # Check if bucket exists
    if ! check_resource_exists "bucket" "$BUCKET_NAME"; then
        log_warning "Storage bucket 'gs://$BUCKET_NAME' not found, skipping"
        return 0
    fi

    # Check bucket contents
    local object_count
    object_count=$(gsutil ls "gs://$BUCKET_NAME/**" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$object_count" -gt 0 ]]; then
        log_warning "Bucket contains $object_count objects"
        if [[ "$FORCE" == "false" ]]; then
            log_warning "All cached weather data will be permanently deleted"
            read -p "Continue with bucket deletion? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Skipping bucket deletion"
                return 0
            fi
        fi
    fi

    log_info "Deleting Storage bucket: gs://$BUCKET_NAME"
    
    # Delete all objects and the bucket
    gsutil -m rm -r "gs://$BUCKET_NAME" || {
        log_error "Failed to delete Storage bucket: gs://$BUCKET_NAME"
        return 1
    }

    log_success "Storage bucket deleted: gs://$BUCKET_NAME"
}

cleanup_local_files() {
    log_info "Cleaning up temporary files..."

    # Remove any temporary files that might have been created
    rm -f /tmp/lifecycle.json
    rm -f /tmp/function_test_response

    log_success "Local cleanup completed"
}

display_cleanup_summary() {
    echo -e "${GREEN}"
    echo "============================================================================="
    echo "                         CLEANUP COMPLETED"
    echo "============================================================================="
    echo -e "${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No resources were actually deleted${NC}"
        echo ""
    fi

    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo "Function: $FUNCTION_NAME (deleted)"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "Bucket: gs://$BUCKET_NAME (deleted)"
    fi
    
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "All Weather API resources have been removed"
        log_info "You can verify deletion by checking the Google Cloud Console"
        echo ""
        echo "Verification commands:"
        echo "  gcloud functions list --filter=\"name:$FUNCTION_NAME\""
        echo "  gsutil ls -b gs://$BUCKET_NAME"
    fi
}

# =============================================================================
# Main Execution Flow
# =============================================================================

parse_arguments() {
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
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -a|--auto-discover)
                AUTO_DISCOVER=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Set defaults for optional parameters
    REGION="${REGION:-$DEFAULT_REGION}"
    FUNCTION_NAME="${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}"

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or -p"
        show_usage
        exit 1
    fi

    # If auto-discover is not enabled and bucket name is not provided, warn user
    if [[ "$AUTO_DISCOVER" != "true" ]] && [[ -z "$BUCKET_NAME" ]]; then
        log_warning "Bucket name not specified and auto-discover disabled"
        log_info "Either provide --bucket-name or use --auto-discover"
        log_info "Continuing with only function cleanup..."
    fi
}

confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo -e "${RED}WARNING: This will permanently delete the following resources:${NC}"
    
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo "  - Cloud Function: $FUNCTION_NAME (region: $REGION)"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "  - Storage Bucket: gs://$BUCKET_NAME (and all contents)"
    fi
    
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Type 'DELETE' to confirm deletion: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    log_info "Deletion confirmed, proceeding..."
}

main() {
    print_banner

    # Parse command line arguments
    parse_arguments "$@"

    # Validate environment and inputs
    check_prerequisites
    validate_project

    # Auto-discover resources if requested
    if [[ "$AUTO_DISCOVER" == "true" ]]; then
        discover_resources || {
            log_error "Resource discovery failed"
            exit 1
        }
    fi

    # Show cleanup plan
    echo "Cleanup Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Function Name: ${FUNCTION_NAME:-"Not specified"}"
    echo "  Bucket Name: ${BUCKET_NAME:-"Not specified"}"
    echo "  Auto Discover: $AUTO_DISCOVER"
    echo "  Dry Run: $DRY_RUN"
    echo "  Force: $FORCE"
    echo ""

    # Confirm deletion unless in dry-run mode or force mode
    confirm_deletion

    # Execute cleanup steps
    log_info "Starting cleanup..."
    
    delete_cloud_function
    delete_storage_bucket
    cleanup_local_files
    
    display_cleanup_summary
    
    log_success "Weather API cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted! Some resources may not have been deleted."; exit 1' INT TERM

# Execute main function with all arguments
main "$@"
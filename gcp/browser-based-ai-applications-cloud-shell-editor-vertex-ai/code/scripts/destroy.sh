#!/bin/bash

#######################################
# Browser-Based AI Applications with Cloud Shell Editor and Vertex AI
# Cleanup Script for GCP
# 
# This script removes all infrastructure and resources created for the
# browser-based AI applications recipe
#######################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/ai-app-destroy-$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE=false
CONFIRM_DESTROY=true

#######################################
# Print colored output
#######################################
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

#######################################
# Display usage information
#######################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove browser-based AI application infrastructure from Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: us-central1)
    -s, --service-name NAME       Cloud Run service name (default: ai-chat-assistant)
    -d, --dry-run                 Show what would be deleted without executing
    -f, --force                   Force deletion without confirmation prompts
    --delete-project              Delete entire project (DESTRUCTIVE)
    -h, --help                    Display this help message

EXAMPLES:
    $0 --project-id my-ai-project
    $0 --project-id my-ai-project --region us-east1 --service-name my-ai-app
    $0 --project-id my-ai-project --dry-run
    $0 --project-id my-ai-project --delete-project --force

WARNINGS:
    - This script will permanently delete resources
    - Use --dry-run to preview what will be deleted
    - Use --delete-project with extreme caution

EOF
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    DELETE_PROJECT=false
    
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
            -s|--service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                CONFIRM_DESTROY=false
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
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    REGION="${REGION:-us-central1}"
    SERVICE_NAME="${SERVICE_NAME:-ai-chat-assistant}"

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        print_error "Project ID is required. Use --project-id option."
        usage
        exit 1
    fi

    export DELETE_PROJECT
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud CLI (gcloud) is not installed"
        print_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found"
        print_error "Run: gcloud auth login"
        exit 1
    fi

    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        print_error "Project '$PROJECT_ID' not found or not accessible"
        print_error "Verify project ID and permissions"
        exit 1
    fi

    print_success "Prerequisites check completed"
}

#######################################
# Set project context
#######################################
setup_environment() {
    print_status "Setting up environment..."

    # Set project as default
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"

    print_status "Environment configured:"
    print_status "  Project ID: $PROJECT_ID"
    print_status "  Region: $REGION"
    print_status "  Service Name: $SERVICE_NAME"
}

#######################################
# Get confirmation for destructive operations
#######################################
confirm_destruction() {
    if [[ "$CONFIRM_DESTROY" == "false" ]]; then
        return 0
    fi

    echo
    print_warning "WARNING: This will permanently delete the following resources:"
    print_warning "  - Cloud Run service: $SERVICE_NAME"
    print_warning "  - Container images in Container Registry"
    print_warning "  - Cloud Build history and artifacts"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        print_warning "  - ENTIRE PROJECT: $PROJECT_ID (IRREVERSIBLE)"
    fi
    
    echo
    print_warning "This action cannot be undone!"
    echo

    if [[ "$DELETE_PROJECT" == "true" ]]; then
        read -p "Type 'DELETE PROJECT' to confirm project deletion: " -r
        if [[ "$REPLY" != "DELETE PROJECT" ]]; then
            print_status "Project deletion cancelled"
            exit 0
        fi
    else
        read -p "Continue with resource deletion? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deletion cancelled by user"
            exit 0
        fi
    fi
}

#######################################
# List resources to be deleted
#######################################
list_resources() {
    print_status "Scanning for resources to delete..."

    # Check for Cloud Run services
    local services
    services=$(gcloud run services list \
        --region="$REGION" \
        --filter="metadata.name:$SERVICE_NAME" \
        --format="value(metadata.name)" 2>/dev/null || true)

    if [[ -n "$services" ]]; then
        print_status "Found Cloud Run services:"
        echo "$services" | while read -r service; do
            print_status "  - $service"
        done
    else
        print_status "No Cloud Run services found matching '$SERVICE_NAME'"
    fi

    # Check for container images
    local images
    images=$(gcloud container images list \
        --repository="gcr.io/$PROJECT_ID" \
        --filter="name:$SERVICE_NAME" \
        --format="value(name)" 2>/dev/null || true)

    if [[ -n "$images" ]]; then
        print_status "Found container images:"
        echo "$images" | while read -r image; do
            print_status "  - $image"
        done
    else
        print_status "No container images found for '$SERVICE_NAME'"
    fi

    # Check for Cloud Build history
    local builds
    builds=$(gcloud builds list \
        --filter="substitutions._SERVICE_NAME:$SERVICE_NAME" \
        --limit=5 \
        --format="value(id)" 2>/dev/null || true)

    if [[ -n "$builds" ]]; then
        print_status "Found recent Cloud Build history (will be preserved)"
        local build_count
        build_count=$(echo "$builds" | wc -l)
        print_status "  - $build_count recent builds found"
    fi
}

#######################################
# Delete Cloud Run service
#######################################
delete_cloud_run_service() {
    print_status "Deleting Cloud Run service..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would delete Cloud Run service: $SERVICE_NAME"
        return 0
    fi

    # Check if service exists
    if gcloud run services describe "$SERVICE_NAME" --region="$REGION" &>/dev/null; then
        print_status "Deleting Cloud Run service: $SERVICE_NAME"
        
        if gcloud run services delete "$SERVICE_NAME" \
            --region="$REGION" \
            --quiet; then
            print_success "Cloud Run service deleted: $SERVICE_NAME"
        else
            print_warning "Failed to delete Cloud Run service (may not exist)"
        fi
    else
        print_status "Cloud Run service not found: $SERVICE_NAME"
    fi
}

#######################################
# Delete container images
#######################################
delete_container_images() {
    print_status "Deleting container images..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would delete container images for: $SERVICE_NAME"
        return 0
    fi

    # List and delete all images for the service
    local images
    images=$(gcloud container images list \
        --repository="gcr.io/$PROJECT_ID" \
        --filter="name:$SERVICE_NAME" \
        --format="value(name)" 2>/dev/null || true)

    if [[ -n "$images" ]]; then
        echo "$images" | while read -r image; do
            print_status "Deleting container image: $image"
            
            # Delete image with all tags
            if gcloud container images delete "$image" \
                --force-delete-tags \
                --quiet; then
                print_success "Deleted container image: $image"
            else
                print_warning "Failed to delete container image: $image"
            fi
        done
    else
        print_status "No container images found for service: $SERVICE_NAME"
    fi
}

#######################################
# Clean up build artifacts
#######################################
cleanup_build_artifacts() {
    print_status "Cleaning up build artifacts..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would clean up build artifacts"
        return 0
    fi

    # Note: Cloud Build history is preserved for auditing
    # Individual builds cannot be deleted via CLI
    print_status "Cloud Build history preserved for auditing purposes"
    print_status "Build artifacts in Cloud Storage will be cleaned up automatically"
}

#######################################
# Delete entire project (if requested)
#######################################
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi

    print_status "Deleting entire project..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would delete entire project: $PROJECT_ID"
        return 0
    fi

    print_warning "Deleting project: $PROJECT_ID"
    print_warning "This action is IRREVERSIBLE and will delete ALL resources in the project!"
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        print_success "Project deletion initiated: $PROJECT_ID"
        print_status "Project deletion will complete in approximately 30 days"
        print_status "During this period, the project can be restored if needed"
    else
        print_error "Failed to delete project: $PROJECT_ID"
        exit 1
    fi
}

#######################################
# Verify cleanup completion
#######################################
verify_cleanup() {
    if [[ "$DELETE_PROJECT" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    print_status "Verifying cleanup completion..."

    # Check if Cloud Run service still exists
    if gcloud run services describe "$SERVICE_NAME" --region="$REGION" &>/dev/null; then
        print_warning "Cloud Run service still exists: $SERVICE_NAME"
    else
        print_success "Cloud Run service successfully removed"
    fi

    # Check for remaining container images
    local remaining_images
    remaining_images=$(gcloud container images list \
        --repository="gcr.io/$PROJECT_ID" \
        --filter="name:$SERVICE_NAME" \
        --format="value(name)" 2>/dev/null || true)

    if [[ -n "$remaining_images" ]]; then
        print_warning "Some container images may still exist"
    else
        print_success "Container images successfully removed"
    fi

    print_success "Cleanup verification completed"
}

#######################################
# Display cleanup summary
#######################################
display_summary() {
    print_status "Cleanup Summary"
    echo "================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Service Name: $SERVICE_NAME"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "Action: Project deletion initiated"
        echo "Timeline: 30 days until permanent deletion"
    else
        echo "Action: Service and container cleanup"
        echo "Status: Resources removed from project"
    fi
    
    echo ""
    echo "Notes:"
    echo "- Cloud Build history preserved for auditing"
    echo "- Project billing will stop for deleted resources"
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        echo "- APIs remain enabled for future use"
        echo "- Project structure preserved"
    fi
    echo "================================"
}

#######################################
# Cleanup function for error handling
#######################################
cleanup_on_error() {
    print_error "Cleanup process encountered an error"
    print_status "Some resources may not have been deleted"
    print_status "Check the log file for details: $LOG_FILE"
    exit 1
}

#######################################
# Main cleanup function
#######################################
main() {
    print_status "Starting AI application cleanup on Google Cloud Platform"
    print_status "Log file: $LOG_FILE"

    # Set up error handling
    trap cleanup_on_error ERR

    # Parse command line arguments
    parse_args "$@"

    # Execute cleanup steps
    check_prerequisites
    setup_environment
    list_resources
    confirm_destruction

    # Perform cleanup operations
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    else
        delete_cloud_run_service
        delete_container_images
        cleanup_build_artifacts
        verify_cleanup
    fi

    display_summary

    if [[ "$DRY_RUN" == "false" ]]; then
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            print_success "Project deletion initiated successfully!"
            print_status "Project $PROJECT_ID will be permanently deleted in 30 days"
        else
            print_success "AI application cleanup completed successfully!"
            print_status "All specified resources have been removed from $PROJECT_ID"
        fi
    else
        print_success "Dry run completed - no resources were deleted"
    fi
}

# Execute main function with all arguments
main "$@"
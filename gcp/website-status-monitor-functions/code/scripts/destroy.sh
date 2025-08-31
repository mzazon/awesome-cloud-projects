#!/bin/bash

# Website Status Monitor Cloud Function Cleanup Script
# This script removes all resources created by the deployment script
# Based on the GCP recipe: Website Status Monitor with Cloud Functions

set -euo pipefail

# Enable strict error handling
trap 'echo "❌ Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly FUNCTION_DIR="${SCRIPT_DIR}/../function"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Runtime variables
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-website-status-monitor}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print section headers
print_section() {
    local message=$1
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE} ${message}${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

# Function to load environment variables
load_environment() {
    if [ -f "$ENV_FILE" ]; then
        print_status "$BLUE" "Loading environment from: $ENV_FILE"
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        if [ -n "${FUNCTION_URL:-}" ]; then
            print_status "$GREEN" "✅ Found function URL in environment"
        fi
    else
        print_status "$YELLOW" "⚠️  No environment file found at: $ENV_FILE"
    fi
}

# Function to detect current configuration
detect_configuration() {
    print_section "Detecting Current Configuration"
    
    # Try to get current project if not set
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -n "$PROJECT_ID" ]; then
            print_status "$BLUE" "Using current gcloud project: $PROJECT_ID"
        else
            print_status "$RED" "❌ No project ID specified and no default project configured"
            print_status "$YELLOW" "   Please specify project with -p option or set PROJECT_ID environment variable"
            exit 1
        fi
    fi
    
    # Try to get current region if configured
    local current_region
    current_region=$(gcloud config get-value functions/region 2>/dev/null || echo "")
    if [ -n "$current_region" ]; then
        REGION="$current_region"
        print_status "$BLUE" "Using configured region: $REGION"
    fi
    
    print_status "$GREEN" "✅ Configuration detected successfully"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_status "$RED" "❌ gcloud CLI is not installed"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --format="value(account)" --filter="status=ACTIVE" | head -1 &> /dev/null; then
        print_status "$RED" "❌ Not authenticated with gcloud. Please run:"
        print_status "$YELLOW" "   gcloud auth login"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        print_status "$RED" "❌ Project '$PROJECT_ID' does not exist or is not accessible"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Prerequisites check completed"
}

# Function to list resources to be deleted
list_resources() {
    print_section "Identifying Resources to Delete"
    
    local resources_found=false
    
    # Check for Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        print_status "$YELLOW" "📁 Cloud Function: $FUNCTION_NAME (region: $REGION)"
        resources_found=true
    else
        print_status "$BLUE" "   No Cloud Function '$FUNCTION_NAME' found in region '$REGION'"
    fi
    
    # Check for local function source code
    if [ -d "$FUNCTION_DIR" ]; then
        print_status "$YELLOW" "📁 Local function source: $FUNCTION_DIR"
        resources_found=true
    else
        print_status "$BLUE" "   No local function source directory found"
    fi
    
    # Check for environment file
    if [ -f "$ENV_FILE" ]; then
        print_status "$YELLOW" "📁 Environment file: $ENV_FILE"
        resources_found=true
    else
        print_status "$BLUE" "   No environment file found"
    fi
    
    # Check for Cloud Build artifacts (functions create build artifacts)
    local build_count
    build_count=$(gcloud builds list --project="$PROJECT_ID" --filter="source.storageSource.bucket:gcf-sources-*" --limit=5 --format="value(id)" 2>/dev/null | wc -l)
    if [ "$build_count" -gt 0 ]; then
        print_status "$YELLOW" "📁 Cloud Build artifacts: ~$build_count recent builds (will be cleaned up automatically)"
    fi
    
    # Check if project should be deleted
    if [ "$DELETE_PROJECT" = "true" ]; then
        print_status "$RED" "🗑️  ENTIRE PROJECT: $PROJECT_ID (WARNING: This will delete ALL resources in the project)"
        resources_found=true
    fi
    
    if [ "$resources_found" = "false" ]; then
        print_status "$GREEN" "✅ No resources found to delete"
        return 1
    fi
    
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$FORCE" = "true" ]; then
        print_status "$YELLOW" "⚠️  Force mode enabled - skipping confirmation"
        return 0
    fi
    
    print_status "$RED" "⚠️  WARNING: This action cannot be undone!"
    echo
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        print_status "$RED" "🚨 PROJECT DELETION ENABLED - This will delete the ENTIRE project and ALL resources!"
        print_status "$RED" "   Project: $PROJECT_ID"
        echo
        read -p "Type 'DELETE PROJECT' to confirm project deletion: " -r
        if [ "$REPLY" != "DELETE PROJECT" ]; then
            print_status "$YELLOW" "Project deletion cancelled"
            exit 0
        fi
    else
        read -p "Proceed with resource cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "$YELLOW" "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Function to delete Cloud Function
delete_function() {
    print_section "Deleting Cloud Function"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Would delete function: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if function exists
    if ! gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        print_status "$BLUE" "Function '$FUNCTION_NAME' not found - skipping deletion"
        return 0
    fi
    
    print_status "$YELLOW" "Deleting Cloud Function '$FUNCTION_NAME'..."
    
    if gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet; then
        print_status "$GREEN" "✅ Cloud Function deleted successfully"
    else
        print_status "$RED" "❌ Failed to delete Cloud Function"
        return 1
    fi
    
    # Wait for function to be fully deleted
    print_status "$YELLOW" "Waiting for function deletion to complete..."
    local attempts=0
    while gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; do
        if [ $attempts -gt 30 ]; then
            print_status "$YELLOW" "⚠️  Function deletion is taking longer than expected"
            break
        fi
        sleep 2
        ((attempts++))
    done
    
    print_status "$GREEN" "✅ Function deletion completed"
}

# Function to clean up local files
cleanup_local_files() {
    print_section "Cleaning Up Local Files"
    
    local files_deleted=false
    
    # Remove function source directory
    if [ -d "$FUNCTION_DIR" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            print_status "$BLUE" "[DRY RUN] Would delete directory: $FUNCTION_DIR"
        else
            print_status "$YELLOW" "Removing function source directory..."
            rm -rf "$FUNCTION_DIR"
            print_status "$GREEN" "✅ Function source directory removed: $FUNCTION_DIR"
            files_deleted=true
        fi
    fi
    
    # Remove environment file
    if [ -f "$ENV_FILE" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            print_status "$BLUE" "[DRY RUN] Would delete file: $ENV_FILE"
        else
            print_status "$YELLOW" "Removing environment file..."
            rm -f "$ENV_FILE"
            print_status "$GREEN" "✅ Environment file removed: $ENV_FILE"
            files_deleted=true
        fi
    fi
    
    if [ "$files_deleted" = "false" ] && [ "$DRY_RUN" = "false" ]; then
        print_status "$BLUE" "No local files to clean up"
    fi
}

# Function to delete entire project
delete_project() {
    if [ "$DELETE_PROJECT" != "true" ]; then
        return 0
    fi
    
    print_section "Deleting Project"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    print_status "$RED" "🗑️  Deleting entire project: $PROJECT_ID"
    print_status "$YELLOW" "This will delete ALL resources in the project..."
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        print_status "$GREEN" "✅ Project deletion initiated: $PROJECT_ID"
        print_status "$BLUE" "   Note: Project deletion is asynchronous and may take several minutes"
    else
        print_status "$RED" "❌ Failed to delete project: $PROJECT_ID"
        return 1
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_section "Verifying Cleanup"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        print_status "$BLUE" "Project deletion initiated - verification skipped"
        return 0
    fi
    
    # Verify function is deleted
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        print_status "$YELLOW" "⚠️  Cloud Function still exists (deletion may still be in progress)"
    else
        print_status "$GREEN" "✅ Cloud Function successfully deleted"
    fi
    
    # Verify local files are removed
    if [ -d "$FUNCTION_DIR" ] || [ -f "$ENV_FILE" ]; then
        print_status "$YELLOW" "⚠️  Some local files still exist"
    else
        print_status "$GREEN" "✅ Local files successfully cleaned up"
    fi
}

# Function to display cleanup summary
display_summary() {
    print_section "Cleanup Summary"
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        print_status "$GREEN" "🗑️  Project deletion initiated successfully"
        print_status "$BLUE" "   Project: $PROJECT_ID"
        print_status "$YELLOW" "   Note: Complete project deletion may take several minutes"
    else
        print_status "$GREEN" "🧹 Website Status Monitor cleanup completed successfully!"
        echo
        print_status "$BLUE" "Resources cleaned up:"
        print_status "$NC" "  ✅ Cloud Function: $FUNCTION_NAME"
        print_status "$NC" "  ✅ Local function source code"
        print_status "$NC" "  ✅ Environment configuration"
        echo
        print_status "$BLUE" "Project retained: $PROJECT_ID"
        print_status "$YELLOW" "   Note: Project APIs remain enabled. Disable manually if not needed:"
        print_status "$NC" "   gcloud services disable cloudfunctions.googleapis.com --project=$PROJECT_ID"
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Cleanup simulation completed - no actual changes made"
    fi
}

# Function to show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Clean up Website Status Monitor Cloud Function resources"
    echo
    echo "Options:"
    echo "  -p, --project-id      Project ID to clean up"
    echo "  -r, --region          Function region (default: us-central1)"
    echo "  -f, --function-name   Function name (default: website-status-monitor)"
    echo "  -d, --dry-run         Simulate cleanup without making changes"
    echo "  --force               Skip confirmation prompts"
    echo "  --delete-project      Delete the entire project (DANGEROUS)"
    echo "  -h, --help            Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID            Override default project ID"
    echo "  REGION                Override default region"
    echo "  FUNCTION_NAME         Override default function name"
    echo "  DRY_RUN              Set to 'true' for dry run mode"
    echo "  FORCE                Set to 'true' to skip confirmations"
    echo "  DELETE_PROJECT       Set to 'true' to delete entire project"
    echo
    echo "Examples:"
    echo "  $0                              # Clean up with auto-detected settings"
    echo "  $0 -p my-project               # Clean up specific project"
    echo "  $0 --dry-run                   # Simulate cleanup"
    echo "  $0 --force                     # Skip confirmations"
    echo "  $0 --delete-project --force    # Delete entire project"
    echo
    echo "Safety Features:"
    echo "  • Confirmation prompts for destructive actions"
    echo "  • Dry run mode for testing"
    echo "  • Resource verification before deletion"
    echo "  • Graceful handling of missing resources"
}

# Main cleanup function
main() {
    print_section "Website Status Monitor - Resource Cleanup"
    print_status "$BLUE" "Starting cleanup process..."
    
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
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --delete-project)
                DELETE_PROJECT="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Load environment and detect configuration
    load_environment
    detect_configuration
    
    # Show configuration
    print_status "$BLUE" "Cleanup Configuration:"
    print_status "$NC" "  Project ID: $PROJECT_ID"
    print_status "$NC" "  Region: $REGION"
    print_status "$NC" "  Function Name: $FUNCTION_NAME"
    print_status "$NC" "  Dry Run: $DRY_RUN"
    print_status "$NC" "  Force Mode: $FORCE"
    print_status "$NC" "  Delete Project: $DELETE_PROJECT"
    echo
    
    # Execute cleanup steps
    check_prerequisites
    
    # List resources and confirm if any found
    if list_resources; then
        confirm_deletion
        delete_function
        cleanup_local_files
        delete_project
        verify_cleanup
        display_summary
    else
        print_status "$GREEN" "✨ Nothing to clean up - all resources already removed"
    fi
    
    print_status "$GREEN" "🚀 Cleanup completed successfully!"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
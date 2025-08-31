#!/bin/bash

# Contact Form with Cloud Functions and Gmail API - Cleanup Script
# This script safely removes all resources created by the deployment script
# while preserving important data and providing confirmation prompts.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_section() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

# Script metadata
SCRIPT_NAME="Contact Form Cloud Functions Cleanup"
SCRIPT_VERSION="1.0"
RECIPE_NAME="contact-form-functions-gmail"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="contact-form-handler"

# Configuration variables (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-$DEFAULT_REGION}"
FUNCTION_NAME="${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}"
FORCE="${FORCE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up resources created by the contact form deployment script.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (auto-detected if available)
    -r, --region REGION           Deployment region (default: $DEFAULT_REGION)
    -f, --function-name NAME      Cloud Function name (default: $DEFAULT_FUNCTION_NAME)
    --force                       Skip safety checks and force deletion
    --skip-confirmation           Skip interactive confirmation prompts
    -d, --dry-run                 Show what would be done without executing
    -h, --help                    Display this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                    Google Cloud Project ID
    REGION                        Deployment region
    FUNCTION_NAME                 Cloud Function name
    FORCE                         Set to 'true' to skip safety checks
    SKIP_CONFIRMATION             Set to 'true' to skip confirmation prompts
    DRY_RUN                       Set to 'true' for dry-run mode

EXAMPLES:
    $0                                           # Interactive cleanup with auto-detection
    $0 --project-id my-project --force           # Force cleanup without prompts
    $0 -p my-project -r us-east1 --dry-run      # Show what would be cleaned up
    SKIP_CONFIRMATION=true $0                    # Non-interactive cleanup

EOF
}

# Function to parse command line arguments
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
            --force)
                FORCE="true"
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -d|--dry-run)
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
}

# Function to auto-detect configuration from deployment files
auto_detect_config() {
    log_section "Auto-detecting Configuration"
    
    # Try to read from deployment.env if available
    if [[ -f "deployment.env" ]]; then
        log_info "Found deployment.env file, reading configuration..."
        source deployment.env
        
        # Extract function name from URL if FUNCTION_URL is available
        if [[ -n "${FUNCTION_URL:-}" && -z "$FUNCTION_NAME" ]]; then
            FUNCTION_NAME=$(echo "$FUNCTION_URL" | grep -o '/[^/]*$' | sed 's|/||')
            log_info "Detected function name from URL: $FUNCTION_NAME"
        fi
    fi
    
    # Auto-detect project ID from gcloud config if not set
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "$PROJECT_ID" ]]; then
            log_info "Auto-detected project ID: $PROJECT_ID"
        fi
    fi
    
    # Auto-detect region from gcloud config if not set
    if [[ "$REGION" == "$DEFAULT_REGION" ]]; then
        local detected_region
        detected_region=$(gcloud config get-value functions/region 2>/dev/null || echo "")
        if [[ -n "$detected_region" ]]; then
            REGION="$detected_region"
            log_info "Auto-detected region: $REGION"
        fi
    fi
    
    log_info "Configuration detected:"
    log_info "  Project ID: ${PROJECT_ID:-'Not set'}"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_section "Validating Prerequisites"
    
    # Check for required tools
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed or not in PATH"
        exit 1
    fi
    log_info "✓ gcloud CLI is available"
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    log_info "✓ Authenticated with gcloud"
    
    # Validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable"
        exit 1
    fi
    
    # Verify project exists and we have access
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Please check the project ID and your permissions."
        exit 1
    fi
    log_info "✓ Project '$PROJECT_ID' is accessible"
}

# Function to discover resources to be cleaned up
discover_resources() {
    log_section "Discovering Resources to Clean Up"
    
    local resources_found=()
    
    # Check if Cloud Function exists
    if gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" &>/dev/null; then
        resources_found+=("Cloud Function: $FUNCTION_NAME (region: $REGION)")
        log_info "✓ Found Cloud Function: $FUNCTION_NAME"
    else
        log_warning "Cloud Function '$FUNCTION_NAME' not found in region '$REGION'"
    fi
    
    # Check for local files
    local local_files=()
    [[ -f "deployment.env" ]] && local_files+=("deployment.env")
    [[ -f "contact-form.html" ]] && local_files+=("contact-form.html")
    [[ -f "token.pickle" ]] && local_files+=("token.pickle")
    [[ -d "contact-form-function" ]] && local_files+=("contact-form-function/ (directory)")
    
    if [[ ${#local_files[@]} -gt 0 ]]; then
        resources_found+=("Local files: ${local_files[*]}")
        log_info "✓ Found local files: ${local_files[*]}"
    fi
    
    # Display summary of resources to be cleaned up
    if [[ ${#resources_found[@]} -eq 0 ]]; then
        log_warning "No resources found to clean up"
        return 1
    fi
    
    log_info "\nResources that will be cleaned up:"
    for resource in "${resources_found[@]}"; do
        log_info "  - $resource"
    done
    
    return 0
}

# Function to get user confirmation
get_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$FORCE" == "true" ]]; then
        log_info "Skipping confirmation (automated mode)"
        return 0
    fi
    
    log_section "Confirmation Required"
    
    cat << EOF
${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}

1. Cloud Function: $FUNCTION_NAME (if it exists)
2. Local deployment files and directories
3. Generated HTML contact form

${RED}This action cannot be undone!${NC}

EOF
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_success "User confirmed cleanup operation"
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_section "Deleting Cloud Function"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if function exists before attempting deletion
    if ! gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" &>/dev/null; then
        log_warning "Cloud Function '$FUNCTION_NAME' does not exist or already deleted"
        return 0
    fi
    
    log_info "Deleting Cloud Function: $FUNCTION_NAME..."
    
    if gcloud functions delete "$FUNCTION_NAME" \
        --gen2 \
        --region="$REGION" \
        --quiet; then
        log_success "✓ Cloud Function deleted successfully"
    else
        log_error "Failed to delete Cloud Function"
        if [[ "$FORCE" != "true" ]]; then
            exit 1
        else
            log_warning "Continuing due to --force flag"
        fi
    fi
    
    # Wait for deletion to complete
    log_info "Waiting for deletion to complete..."
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if ! gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" &>/dev/null; then
            log_success "✓ Cloud Function deletion confirmed"
            break
        fi
        
        sleep 2
        ((attempts++))
        
        if [[ $attempts -eq $max_attempts ]]; then
            log_warning "Deletion verification timed out, but function may still be deleting"
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log_section "Cleaning Up Local Files"
    
    local files_to_remove=(
        "deployment.env"
        "contact-form.html"
        "token.pickle"
        "credentials.json"
        "generate_token.py"
    )
    
    local dirs_to_remove=(
        "contact-form-function"
    )
    
    # Remove individual files
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove file: $file"
            else
                rm -f "$file"
                log_success "✓ Removed file: $file"
            fi
        fi
    done
    
    # Remove directories
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove directory: $dir"
            else
                rm -rf "$dir"
                log_success "✓ Removed directory: $dir"
            fi
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to perform optional cleanup tasks
optional_cleanup() {
    log_section "Optional Cleanup Tasks"
    
    if [[ "$SKIP_CONFIRMATION" != "true" && "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        log_info "\nOptional cleanup tasks available:"
        log_info "1. Disable APIs that were enabled during deployment"
        log_info "2. Remove OAuth credentials from Downloads folder"
        
        read -p "Do you want to perform optional cleanup? (y/N): " optional_choice
        
        if [[ "$optional_choice" =~ ^[Yy]$ ]]; then
            # Ask about API cleanup
            read -p "Disable APIs (cloudfunctions, cloudbuild, gmail)? (y/N): " api_choice
            if [[ "$api_choice" =~ ^[Yy]$ ]]; then
                log_info "Disabling APIs..."
                local apis=(
                    "cloudfunctions.googleapis.com"
                    "cloudbuild.googleapis.com"
                    "gmail.googleapis.com"
                )
                
                for api in "${apis[@]}"; do
                    log_info "Disabling $api..."
                    gcloud services disable "$api" --quiet --force || log_warning "Failed to disable $api"
                done
                log_success "✓ APIs disabled"
            fi
            
            # Ask about credential cleanup
            read -p "Remove OAuth credentials from ~/Downloads/credentials.json? (y/N): " cred_choice
            if [[ "$cred_choice" =~ ^[Yy]$ ]]; then
                if [[ -f "$HOME/Downloads/credentials.json" ]]; then
                    rm -f "$HOME/Downloads/credentials.json"
                    log_success "✓ OAuth credentials removed"
                else
                    log_info "OAuth credentials file not found"
                fi
            fi
        fi
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would offer optional cleanup for:"
        log_info "  - Disabling APIs (cloudfunctions, cloudbuild, gmail)"
        log_info "  - Removing OAuth credentials file"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_section "Verifying Cleanup Completion"
    
    local verification_failed=false
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    # Verify Cloud Function deletion
    if gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" &>/dev/null; then
        log_error "✗ Cloud Function still exists"
        verification_failed=true
    else
        log_success "✓ Cloud Function successfully deleted"
    fi
    
    # Verify local file cleanup
    local remaining_files=()
    [[ -f "deployment.env" ]] && remaining_files+=("deployment.env")
    [[ -f "contact-form.html" ]] && remaining_files+=("contact-form.html")
    [[ -d "contact-form-function" ]] && remaining_files+=("contact-form-function/")
    
    if [[ ${#remaining_files[@]} -gt 0 ]]; then
        log_warning "Some local files still exist: ${remaining_files[*]}"
    else
        log_success "✓ All local files cleaned up"
    fi
    
    if [[ "$verification_failed" == "true" && "$FORCE" != "true" ]]; then
        log_error "Cleanup verification failed"
        exit 1
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    log_section "Cleanup Summary"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        cat << EOF
${CYAN}DRY RUN SUMMARY${NC}
The following cleanup actions would be performed:

1. Delete Cloud Function: $FUNCTION_NAME (if exists)
2. Remove local files:
   - deployment.env
   - contact-form.html
   - token.pickle
   - contact-form-function/ directory

3. Optional cleanup (if confirmed):
   - Disable APIs: cloudfunctions, cloudbuild, gmail
   - Remove OAuth credentials file

No actual changes would be made in dry-run mode.
EOF
        return 0
    fi
    
    cat << EOF
${GREEN}CLEANUP COMPLETED SUCCESSFULLY${NC}

🧹 Resources Cleaned Up:
   ✓ Cloud Function: $FUNCTION_NAME
   ✓ Local deployment files
   ✓ Generated HTML contact form
   ✓ Temporary authentication files

📋 What was preserved:
   - Your Google Cloud project (unchanged)
   - OAuth credentials in Google Cloud Console
   - Any emails sent through the contact form

💡 Next Steps:
   - Your contact form is now completely removed
   - OAuth credentials in Google Cloud Console can be deleted manually if no longer needed
   - Project APIs remain enabled unless specifically disabled

🔄 To redeploy:
   - Run the deploy.sh script again with the same parameters
   - OAuth setup will need to be repeated

EOF
}

# Main cleanup function
main() {
    log_section "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    auto_detect_config
    validate_prerequisites
    
    if ! discover_resources; then
        log_info "Nothing to clean up. Exiting."
        exit 0
    fi
    
    get_confirmation
    delete_cloud_function
    cleanup_local_files
    optional_cleanup
    verify_cleanup
    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Contact form cleanup completed successfully!"
    else
        log_info "Dry run completed. Use without --dry-run to perform actual cleanup."
    fi
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Execute main function with all arguments
main "$@"
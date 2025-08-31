#!/bin/bash

# Timezone Converter API with Cloud Functions - Cleanup Script
# This script removes all resources created by the timezone converter deployment

set -euo pipefail

# Colors for output
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

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="timezone-converter"

# Configuration variables (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-$DEFAULT_REGION}"
FUNCTION_NAME="${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove timezone converter API resources from Google Cloud Functions.

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required if not set in env)
    -r, --region REGION            Deployment region (default: $DEFAULT_REGION)
    -f, --function-name NAME       Function name (default: $DEFAULT_FUNCTION_NAME)
    -d, --delete-project           Delete entire GCP project (DANGEROUS)
    -F, --force                    Force deletion without detailed confirmations
    -y, --yes                      Skip all confirmation prompts
    -h, --help                     Display this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                     GCP Project ID
    REGION                         Deployment region
    FUNCTION_NAME                  Cloud Function name
    DELETE_PROJECT                 Set to 'true' to delete entire project
    FORCE_DELETE                   Set to 'true' to force deletion
    SKIP_CONFIRMATION             Set to 'true' to skip confirmations

EXAMPLES:
    # Delete function only
    $0 --project-id my-project-123

    # Delete function with custom name/region
    $0 --project-id my-project-123 --region europe-west1 --function-name my-function

    # Delete entire project (DANGEROUS)
    $0 --project-id my-project-123 --delete-project

    # Force delete without confirmations
    $0 --project-id my-project-123 --force --yes

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
            -d|--delete-project)
                DELETE_PROJECT="true"
                shift
                ;;
            -F|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION="true"
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

    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Validate PROJECT_ID
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is required. Set it via environment variable or --project-id flag."
        exit 1
    fi

    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access."
        exit 1
    fi

    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet

    log_success "Prerequisites check completed"
}

# Confirmation prompts
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi

    echo -e "${YELLOW}WARNING: You are about to $action the following resource:${NC}"
    echo -e "${YELLOW}$resource${NC}"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Check what resources exist
check_existing_resources() {
    log_info "Scanning for existing resources..."

    # Check if function exists
    local function_exists=false
    if gcloud functions describe "$FUNCTION_NAME" --gen2 --region "$REGION" &> /dev/null; then
        function_exists=true
        log_info "Found Cloud Function: $FUNCTION_NAME"
    else
        log_info "Cloud Function '$FUNCTION_NAME' not found in region '$REGION'"
    fi

    # Store function existence status
    echo "$function_exists" > /tmp/function_exists

    # Check project resources if deleting project
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_info "Scanning project resources for deletion..."
        
        # List all functions in project
        local all_functions
        all_functions=$(gcloud functions list --filter="name:*" --format="value(name)" 2>/dev/null || true)
        if [[ -n "$all_functions" ]]; then
            log_warning "Project contains the following Cloud Functions:"
            echo "$all_functions" | sed 's/^/  - /'
        fi

        # Check for other services
        local enabled_services
        enabled_services=$(gcloud services list --enabled --format="value(name)" --filter="name:(cloudfunctions.googleapis.com OR cloudbuild.googleapis.com)" 2>/dev/null || true)
        if [[ -n "$enabled_services" ]]; then
            log_info "Project has the following relevant APIs enabled:"
            echo "$enabled_services" | sed 's/^/  - /'
        fi
    fi

    log_success "Resource scan completed"
}

# Delete Cloud Function
delete_function() {
    local function_exists
    function_exists=$(cat /tmp/function_exists)

    if [[ "$function_exists" == "false" ]]; then
        log_info "Cloud Function '$FUNCTION_NAME' does not exist, skipping deletion"
        return 0
    fi

    if [[ "$FORCE_DELETE" != "true" ]]; then
        confirm_action "DELETE" "Cloud Function: $FUNCTION_NAME in $REGION"
    fi

    log_info "Deleting Cloud Function: $FUNCTION_NAME"

    # Delete function with retries
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Deletion attempt $((retry_count + 1))/$max_retries"
        
        if gcloud functions delete "$FUNCTION_NAME" \
            --gen2 \
            --region "$REGION" \
            --quiet; then
            
            log_success "Cloud Function deleted successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Deletion failed. Retrying in 10 seconds..."
                sleep 10
            else
                log_error "Function deletion failed after $max_retries attempts"
                return 1
            fi
        fi
    done

    # Verify deletion
    log_info "Verifying function deletion..."
    local wait_count=0
    local max_wait=30
    
    while [[ $wait_count -lt $max_wait ]]; do
        if ! gcloud functions describe "$FUNCTION_NAME" --gen2 --region "$REGION" &> /dev/null; then
            log_success "Function deletion verified"
            break
        fi
        
        log_info "Waiting for deletion to complete... ($((wait_count + 1))/$max_wait)"
        sleep 5
        wait_count=$((wait_count + 1))
    done

    if [[ $wait_count -eq $max_wait ]]; then
        log_warning "Function may still be in deletion process. Check manually if needed."
    fi
}

# Clean up IAM policies (if needed)
cleanup_iam_policies() {
    log_info "Checking for function-related IAM policies..."

    # Check if there are any custom IAM bindings for the function
    # In most cases, Cloud Functions handles this automatically
    local function_resource="projects/$PROJECT_ID/locations/$REGION/functions/$FUNCTION_NAME"
    
    # This is mainly informational since function deletion handles IAM cleanup
    log_info "IAM policies will be automatically cleaned up with function deletion"
}

# Disable APIs (optional, only if specifically requested)
disable_apis() {
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_info "APIs will be disabled when project is deleted"
        return 0
    fi

    # Only disable APIs if explicitly requested and no other functions exist
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" 2>/dev/null || true)
    
    if [[ -z "$remaining_functions" ]]; then
        log_info "No remaining Cloud Functions found"
        
        if [[ "$FORCE_DELETE" != "true" ]]; then
            echo -e "${YELLOW}Do you want to disable Cloud Functions APIs? This may affect other services.${NC}"
            read -p "Disable APIs? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Disabling Cloud Functions APIs..."
                gcloud services disable cloudfunctions.googleapis.com --quiet || {
                    log_warning "Failed to disable cloudfunctions.googleapis.com - may be used by other services"
                }
                gcloud services disable cloudbuild.googleapis.com --quiet || {
                    log_warning "Failed to disable cloudbuild.googleapis.com - may be used by other services"
                }
            fi
        fi
    else
        log_info "Other Cloud Functions exist, keeping APIs enabled"
    fi
}

# Delete entire project (DANGEROUS)
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi

    echo -e "${RED}===============================================${NC}"
    echo -e "${RED}           DANGER: PROJECT DELETION${NC}"
    echo -e "${RED}===============================================${NC}"
    echo -e "${RED}You are about to DELETE the entire project:${NC}"
    echo -e "${RED}Project ID: $PROJECT_ID${NC}"
    echo -e "${RED}This action is IRREVERSIBLE and will delete:${NC}"
    echo -e "${RED}- All Cloud Functions${NC}"
    echo -e "${RED}- All logs and monitoring data${NC}"
    echo -e "${RED}- All project configuration${NC}"
    echo -e "${RED}- All other resources in the project${NC}"
    echo -e "${RED}===============================================${NC}"

    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo
        echo -e "${YELLOW}Type the project ID to confirm deletion:${NC}"
        read -p "Project ID: " -r confirm_project_id
        
        if [[ "$confirm_project_id" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Aborting deletion."
            exit 1
        fi

        echo
        echo -e "${RED}This is your final warning. Are you absolutely sure?${NC}"
        read -p "Type 'DELETE' to confirm: " -r final_confirm
        
        if [[ "$final_confirm" != "DELETE" ]]; then
            log_info "Project deletion cancelled"
            exit 0
        fi
    fi

    log_info "Initiating project deletion: $PROJECT_ID"
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deletion initiated successfully"
        log_info "Note: Project deletion is asynchronous and may take several minutes to complete"
        log_info "You can monitor the deletion status in the Google Cloud Console"
    else
        log_error "Failed to delete project $PROJECT_ID"
        exit 1
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary status files
    rm -f /tmp/function_exists
    
    log_success "Temporary files cleaned up"
}

# Display deletion summary
display_summary() {
    local deletion_summary=""

    if [[ "$DELETE_PROJECT" == "true" ]]; then
        deletion_summary="Entire project '$PROJECT_ID' scheduled for deletion"
    else
        local function_exists
        function_exists=$(cat /tmp/function_exists 2>/dev/null || echo "false")
        
        if [[ "$function_exists" == "true" ]]; then
            deletion_summary="Cloud Function '$FUNCTION_NAME' deleted from region '$REGION'"
        else
            deletion_summary="No resources were deleted (function did not exist)"
        fi
    fi

    cat << EOF

${GREEN}================================${NC}
${GREEN}    CLEANUP SUMMARY${NC}
${GREEN}================================${NC}

${BLUE}Project ID:${NC}     $PROJECT_ID
${BLUE}Region:${NC}        $REGION
${BLUE}Function Name:${NC} $FUNCTION_NAME

${BLUE}Action Taken:${NC}   $deletion_summary

${GREEN}Verification Commands:${NC}

# Check if function still exists
gcloud functions describe $FUNCTION_NAME --gen2 --region $REGION

# List all functions in project
gcloud functions list

# Check project status (if project deleted)
gcloud projects describe $PROJECT_ID

${GREEN}================================${NC}

EOF
}

# Main cleanup function
main() {
    log_info "Starting Timezone Converter API cleanup..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Setup trap for cleanup
    trap cleanup_temp_files EXIT
    
    # Execute cleanup steps
    check_prerequisites
    check_existing_resources
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    else
        delete_function
        cleanup_iam_policies
        disable_apis
    fi
    
    # Display summary
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"
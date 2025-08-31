#!/bin/bash

##############################################################################
# Weather Dashboard with Cloud Functions and Storage - Cleanup Script
# 
# This script safely removes all resources created by the weather dashboard
# deployment, including:
# - Google Cloud Functions
# - Google Cloud Storage buckets and objects
# - Optionally the entire GCP project
# 
# Prerequisites:
# - Google Cloud SDK (gcloud) installed and authenticated
# - Access to the project where resources were deployed
##############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration (will be loaded from deployment state if available)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-weather-api}"
BUCKET_NAME="${BUCKET_NAME:-}"

##############################################################################
# Utility Functions
##############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all resources created by the weather dashboard deployment.

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (auto-detected if available)
    -r, --region REGION             GCP Region (default: us-central1)
    -f, --function-name NAME        Cloud Function name (default: weather-api)
    -b, --bucket-name NAME          Storage bucket name (auto-detected if available)
    --delete-project                Delete the entire GCP project (DANGEROUS!)
    --force                         Skip confirmation prompts
    --dry-run                       Show what would be deleted without actually deleting
    -h, --help                      Show this help message

EXAMPLES:
    $0                              # Remove resources using saved deployment state
    $0 --project-id "my-project"    # Remove resources from specific project
    $0 --delete-project --force     # Delete entire project without confirmation
    $0 --dry-run                    # Show what would be deleted

SAFETY FEATURES:
    • Loads configuration from deployment state file when available
    • Requires confirmation before deleting resources
    • Provides dry-run mode to preview deletions
    • Logs all operations for audit trail
    • Handles missing resources gracefully

EOF
}

load_deployment_state() {
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        log "INFO" "Loading deployment state from: $DEPLOYMENT_STATE_FILE"
        source "$DEPLOYMENT_STATE_FILE"
        
        log "INFO" "Loaded deployment configuration:"
        log "INFO" "  Project ID: $PROJECT_ID"
        log "INFO" "  Region: $REGION" 
        log "INFO" "  Function Name: $FUNCTION_NAME"
        log "INFO" "  Bucket Name: $BUCKET_NAME"
        log "INFO" "  Originally deployed: $DEPLOYMENT_TIME"
        log "INFO" "  Deployed by: $DEPLOYED_BY"
        
        return 0
    else
        log "WARN" "No deployment state file found at: $DEPLOYMENT_STATE_FILE"
        log "WARN" "You will need to specify resource names manually"
        return 1
    fi
}

validate_configuration() {
    log "INFO" "Validating configuration..."
    
    if [ -z "$PROJECT_ID" ]; then
        log "ERROR" "Project ID is required"
        log "INFO" "Specify with --project-id option or ensure deployment state file exists"
        exit 1
    fi
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "Google Cloud SDK (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log "ERROR" "Not authenticated with Google Cloud"
        log "INFO" "Run: gcloud auth login"
        exit 1
    fi
    
    # Set the project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    # Verify project exists and we have access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "ERROR" "Project $PROJECT_ID does not exist or you don't have access"
        exit 1
    fi
    
    local current_user=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
    log "INFO" "Authenticated as: $current_user"
    log "INFO" "Target project: $PROJECT_ID"
    
    log "INFO" "Configuration validation completed"
}

list_resources_to_delete() {
    log "INFO" "Scanning for resources to delete..."
    
    local resources_found=false
    
    # Check for Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log "INFO" "Found Cloud Function: $FUNCTION_NAME (region: $REGION)"
        resources_found=true
    else
        log "INFO" "Cloud Function $FUNCTION_NAME not found in region $REGION"
    fi
    
    # Check for Storage Bucket
    if [ -n "$BUCKET_NAME" ] && gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        local object_count=$(gsutil ls "gs://$BUCKET_NAME/**" 2>/dev/null | wc -l || echo "0")
        log "INFO" "Found Storage Bucket: $BUCKET_NAME ($object_count objects)"
        resources_found=true
    elif [ -n "$BUCKET_NAME" ]; then
        log "INFO" "Storage Bucket $BUCKET_NAME not found"
    fi
    
    # Check for local files
    local local_files=()
    [ -d "${PROJECT_ROOT}/function-source" ] && local_files+=("function-source/")
    [ -d "${PROJECT_ROOT}/website" ] && local_files+=("website/")
    [ -f "${PROJECT_ROOT}/function_url.txt" ] && local_files+=("function_url.txt")
    
    if [ ${#local_files[@]} -gt 0 ]; then
        log "INFO" "Found local files: ${local_files[*]}"
        resources_found=true
    fi
    
    if [ "$resources_found" = false ]; then
        log "WARN" "No resources found to delete"
        return 1
    fi
    
    return 0
}

confirm_deletion() {
    local delete_project="$1"
    local force="$2"
    
    if [ "$force" = true ]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}                            ⚠️  DELETION CONFIRMATION ⚠️                          ${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    if [ "$delete_project" = true ]; then
        echo -e "${RED}WARNING: You are about to DELETE THE ENTIRE PROJECT!${NC}"
        echo -e "${RED}This action is IRREVERSIBLE and will delete ALL resources in:${NC}"
        echo -e "  Project ID: ${RED}$PROJECT_ID${NC}"
        echo
        echo -e "${RED}This includes:${NC}"
        echo -e "  • All Cloud Functions, Storage buckets, and other GCP resources"
        echo -e "  • All data, configurations, and billing history"
        echo -e "  • All IAM policies and service accounts"
        echo
        echo -e "${RED}Type 'DELETE-PROJECT' to confirm project deletion:${NC}"
        read -r confirmation
        
        if [ "$confirmation" != "DELETE-PROJECT" ]; then
            log "INFO" "Project deletion cancelled"
            exit 0
        fi
    else
        echo "You are about to delete the following resources:"
        echo
        echo "  Project ID:     $PROJECT_ID"
        echo "  Region:         $REGION"
        echo "  Cloud Function: $FUNCTION_NAME"
        echo "  Storage Bucket: $BUCKET_NAME"
        echo "  Local files:    Generated code and website files"
        echo
        echo -e "${YELLOW}This action will permanently delete these resources and cannot be undone.${NC}"
        echo
        echo -n "Are you sure you want to continue? [y/N]: "
        read -r confirmation
        
        case "$confirmation" in
            [yY]|[yY][eE][sS])
                log "INFO" "User confirmed resource deletion"
                ;;
            *)
                log "INFO" "Deletion cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    echo
}

delete_cloud_function() {
    log "INFO" "Deleting Cloud Function: $FUNCTION_NAME"
    
    if ! gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log "INFO" "Cloud Function $FUNCTION_NAME not found, skipping"
        return 0
    fi
    
    if gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet; then
        log "INFO" "✅ Cloud Function $FUNCTION_NAME deleted successfully"
    else
        log "ERROR" "❌ Failed to delete Cloud Function $FUNCTION_NAME"
        return 1
    fi
}

delete_storage_bucket() {
    if [ -z "$BUCKET_NAME" ]; then
        log "INFO" "No bucket name specified, skipping storage cleanup"
        return 0
    fi
    
    log "INFO" "Deleting Storage Bucket: $BUCKET_NAME"
    
    if ! gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log "INFO" "Storage Bucket $BUCKET_NAME not found, skipping"
        return 0
    fi
    
    # Remove all objects first, then the bucket
    if gsutil -m rm -r "gs://$BUCKET_NAME" 2>/dev/null; then
        log "INFO" "✅ Storage Bucket $BUCKET_NAME and all contents deleted successfully"
    else
        log "ERROR" "❌ Failed to delete Storage Bucket $BUCKET_NAME"
        return 1
    fi
}

delete_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local deleted_count=0
    
    # Remove generated directories
    for dir in "function-source" "website"; do
        local dir_path="${PROJECT_ROOT}/$dir"
        if [ -d "$dir_path" ]; then
            rm -rf "$dir_path"
            log "INFO" "✅ Deleted directory: $dir/"
            ((deleted_count++))
        fi
    done
    
    # Remove generated files
    for file in "function_url.txt"; do
        local file_path="${PROJECT_ROOT}/$file"
        if [ -f "$file_path" ]; then
            rm -f "$file_path"
            log "INFO" "✅ Deleted file: $file"
            ((deleted_count++))
        fi
    done
    
    # Remove deployment state file
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log "INFO" "✅ Deleted deployment state file"
        ((deleted_count++))
    fi
    
    if [ $deleted_count -eq 0 ]; then
        log "INFO" "No local files found to delete"
    else
        log "INFO" "✅ Cleaned up $deleted_count local files/directories"
    fi
}

delete_project() {
    log "INFO" "Deleting entire project: $PROJECT_ID"
    
    log "WARN" "This will delete ALL resources in the project and cannot be undone!"
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log "INFO" "✅ Project $PROJECT_ID deletion initiated"
        log "INFO" "Note: Project deletion may take several minutes to complete"
    else
        log "ERROR" "❌ Failed to delete project $PROJECT_ID"
        return 1
    fi
}

show_cleanup_summary() {
    local delete_project="$1"
    
    if [ "$delete_project" = true ]; then
        cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}                         PROJECT DELETION INITIATED!                        ${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

🗑️  Project Cleanup Status:

✅ Project deletion initiated: $PROJECT_ID
✅ Local files cleaned up

⏳ Note: Complete project deletion may take 5-10 minutes.
   You can check status in the Google Cloud Console.

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
    else
        cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}                           CLEANUP COMPLETED!                               ${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

🗑️  Weather Dashboard Cleanup Status:

✅ Cloud Function deleted: $FUNCTION_NAME
✅ Storage Bucket deleted: $BUCKET_NAME  
✅ Local files cleaned up
✅ Deployment state cleared

💰 Cost Impact:
   • All billable resources have been removed
   • No ongoing charges will occur from this deployment
   • Final usage charges may appear in next billing cycle

📊 What was removed:
   • Google Cloud Function ($FUNCTION_NAME)
   • Google Cloud Storage bucket ($BUCKET_NAME)
   • All website files and function source code
   • Local deployment artifacts

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
    fi
}

##############################################################################
# Main Cleanup Logic
##############################################################################

main() {
    # Initialize logging
    echo "=== Weather Dashboard Cleanup Started at $(date) ===" >> "$LOG_FILE"
    
    # Parse command line arguments
    local dry_run=false
    local delete_project=false
    local force=false
    
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
            --delete-project)
                delete_project=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "INFO" "Starting Weather Dashboard cleanup..."
    
    # Load configuration from deployment state if available
    load_deployment_state || true
    
    # Override with command line arguments if provided
    log "INFO" "Final configuration:"
    log "INFO" "  Project ID: $PROJECT_ID"
    log "INFO" "  Region: $REGION"
    log "INFO" "  Function Name: $FUNCTION_NAME"
    log "INFO" "  Bucket Name: $BUCKET_NAME"
    log "INFO" "  Delete Project: $delete_project"
    log "INFO" "  Force Mode: $force"
    
    if [ "$dry_run" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be deleted"
        list_resources_to_delete
        log "INFO" "Dry run completed - no changes made"
        exit 0
    fi
    
    # Validate configuration and access
    validate_configuration
    
    # Check what resources exist
    if ! list_resources_to_delete && [ "$delete_project" = false ]; then
        log "INFO" "No resources found to delete, cleanup complete"
        exit 0
    fi
    
    # Get user confirmation
    confirm_deletion "$delete_project" "$force"
    
    # Execute cleanup based on mode
    if [ "$delete_project" = true ]; then
        # Delete entire project (includes all resources)
        delete_project
        delete_local_files
    else
        # Delete individual resources
        local failed_operations=0
        
        delete_cloud_function || ((failed_operations++))
        delete_storage_bucket || ((failed_operations++))
        delete_local_files || ((failed_operations++))
        
        if [ $failed_operations -gt 0 ]; then
            log "WARN" "$failed_operations operation(s) failed during cleanup"
            log "WARN" "Some resources may still exist and incur charges"
            log "INFO" "Check the Google Cloud Console to verify resource deletion"
        fi
    fi
    
    # Show completion summary  
    show_cleanup_summary "$delete_project"
    
    log "INFO" "Weather Dashboard cleanup completed!"
}

# Execute main function with all arguments
main "$@"
#!/bin/bash

# Progressive Web Apps with Amplify Hosting - Cleanup Script
# This script removes all AWS resources created for the PWA solution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to get Amplify app ID
get_amplify_app_id() {
    local app_id=""
    
    # Try to get app ID from file first
    if [ -f ".amplify_app_id" ]; then
        app_id=$(cat .amplify_app_id 2>/dev/null | tr -d '\n')
        info "Found app ID in .amplify_app_id file: ${app_id}"
    fi
    
    # If no file or empty, try environment variable
    if [ -z "$app_id" ] && [ -n "$AMPLIFY_APP_ID" ]; then
        app_id="$AMPLIFY_APP_ID"
        info "Using app ID from environment variable: ${app_id}"
    fi
    
    # If still no app ID, try to find by name pattern
    if [ -z "$app_id" ] && [ -n "$APP_NAME" ]; then
        info "Searching for Amplify apps with name pattern: ${APP_NAME}"
        app_id=$(aws amplify list-apps \
            --query "apps[?contains(name, '${APP_NAME}')].appId" \
            --output text 2>/dev/null | head -n 1)
        if [ -n "$app_id" ]; then
            info "Found app ID by name search: ${app_id}"
        fi
    fi
    
    # If still no app ID, list all apps and let user choose
    if [ -z "$app_id" ]; then
        warn "No app ID found. Listing all Amplify apps:"
        aws amplify list-apps \
            --query 'apps[*].{Name:name,AppId:appId,Domain:defaultDomain}' \
            --output table 2>/dev/null || echo "No apps found or access denied"
        
        read -p "Enter the App ID to delete (or press Enter to skip): " app_id
        
        if [ -z "$app_id" ]; then
            warn "No app ID provided. Skipping Amplify app deletion."
            return 1
        fi
    fi
    
    export AMPLIFY_APP_ID="$app_id"
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo "=========================================="
    echo -e "${RED}DESTRUCTIVE OPERATION WARNING${NC}"
    echo "=========================================="
    echo "This script will permanently delete:"
    echo "1. AWS Amplify application and all its resources"
    echo "2. Domain associations (if configured)"
    echo "3. All deployed content and build history"
    echo "4. Local project files (if requested)"
    echo ""
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    
    if [ -n "$AMPLIFY_APP_ID" ]; then
        # Get app details for confirmation
        APP_INFO=$(aws amplify get-app \
            --app-id "$AMPLIFY_APP_ID" \
            --query 'app.{Name:name,Domain:defaultDomain}' \
            --output json 2>/dev/null || echo '{"Name":"Unknown","Domain":"Unknown"}')
        
        APP_NAME_DISPLAY=$(echo "$APP_INFO" | grep -o '"Name":"[^"]*"' | cut -d'"' -f4)
        APP_DOMAIN_DISPLAY=$(echo "$APP_INFO" | grep -o '"Domain":"[^"]*"' | cut -d'"' -f4)
        
        echo "App to be deleted:"
        echo "  Name: ${APP_NAME_DISPLAY}"
        echo "  ID: ${AMPLIFY_APP_ID}"
        echo "  Domain: ${APP_DOMAIN_DISPLAY}"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (yes/NO): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete domain associations
delete_domain_associations() {
    if [ -z "$AMPLIFY_APP_ID" ]; then
        warn "No app ID available, skipping domain deletion"
        return
    fi
    
    log "Checking for domain associations..."
    
    # Get list of domain associations
    DOMAINS=$(aws amplify list-domain-associations \
        --app-id "$AMPLIFY_APP_ID" \
        --query 'domainAssociations[*].domainName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$DOMAINS" ] && [ "$DOMAINS" != "None" ]; then
        for domain in $DOMAINS; do
            log "Deleting domain association: ${domain}"
            
            aws amplify delete-domain-association \
                --app-id "$AMPLIFY_APP_ID" \
                --domain-name "$domain" \
                > /dev/null 2>&1 || warn "Failed to delete domain association: ${domain}"
            
            log "✅ Deleted domain association: ${domain}"
        done
    else
        info "No domain associations found"
    fi
}

# Function to stop active builds
stop_active_builds() {
    if [ -z "$AMPLIFY_APP_ID" ]; then
        warn "No app ID available, skipping build stop"
        return
    fi
    
    log "Checking for active builds..."
    
    # Get list of branches
    BRANCHES=$(aws amplify list-branches \
        --app-id "$AMPLIFY_APP_ID" \
        --query 'branches[*].branchName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$BRANCHES" ] && [ "$BRANCHES" != "None" ]; then
        for branch in $BRANCHES; do
            # Check for running jobs
            RUNNING_JOBS=$(aws amplify list-jobs \
                --app-id "$AMPLIFY_APP_ID" \
                --branch-name "$branch" \
                --max-results 5 \
                --query 'jobSummaries[?status==`RUNNING`].jobId' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$RUNNING_JOBS" ] && [ "$RUNNING_JOBS" != "None" ]; then
                for job_id in $RUNNING_JOBS; do
                    log "Stopping running build job: ${job_id}"
                    
                    aws amplify stop-job \
                        --app-id "$AMPLIFY_APP_ID" \
                        --branch-name "$branch" \
                        --job-id "$job_id" \
                        > /dev/null 2>&1 || warn "Failed to stop job: ${job_id}"
                    
                    log "✅ Stopped build job: ${job_id}"
                done
            fi
        done
    fi
    
    # Wait a moment for builds to stop
    if [ -n "$RUNNING_JOBS" ] && [ "$RUNNING_JOBS" != "None" ]; then
        info "Waiting for builds to stop..."
        sleep 10
    fi
}

# Function to delete Amplify branches
delete_branches() {
    if [ -z "$AMPLIFY_APP_ID" ]; then
        warn "No app ID available, skipping branch deletion"
        return
    fi
    
    log "Deleting Amplify branches..."
    
    # Get list of branches
    BRANCHES=$(aws amplify list-branches \
        --app-id "$AMPLIFY_APP_ID" \
        --query 'branches[*].branchName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$BRANCHES" ] && [ "$BRANCHES" != "None" ]; then
        for branch in $BRANCHES; do
            log "Deleting branch: ${branch}"
            
            aws amplify delete-branch \
                --app-id "$AMPLIFY_APP_ID" \
                --branch-name "$branch" \
                > /dev/null 2>&1 || warn "Failed to delete branch: ${branch}"
            
            log "✅ Deleted branch: ${branch}"
        done
    else
        info "No branches found"
    fi
}

# Function to delete Amplify app
delete_amplify_app() {
    if [ -z "$AMPLIFY_APP_ID" ]; then
        warn "No app ID available, skipping app deletion"
        return
    fi
    
    log "Deleting Amplify application: ${AMPLIFY_APP_ID}"
    
    # Delete the entire Amplify application
    aws amplify delete-app \
        --app-id "$AMPLIFY_APP_ID" \
        > /dev/null 2>&1 || error "Failed to delete Amplify application"
    
    log "✅ Deleted Amplify application: ${AMPLIFY_APP_ID}"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove state files
    local files_to_remove=(
        ".amplify_app_id"
        ".build_job_id"
        "custom_headers.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: ${file}"
        fi
    done
    
    # Ask if user wants to remove project directory
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        echo ""
        read -p "Do you want to remove the project directory ${PROJECT_DIR}? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR"
            log "✅ Removed project directory: ${PROJECT_DIR}"
        else
            info "Project directory preserved: ${PROJECT_DIR}"
        fi
    fi
    
    # Clean up environment variables
    unset AMPLIFY_APP_ID APP_NAME BUILD_JOB_ID DOMAIN_NAME FULL_DOMAIN PROJECT_DIR
    
    log "✅ Cleaned up local environment"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [ -n "$AMPLIFY_APP_ID" ]; then
        # Try to get app details (should fail if deleted)
        if aws amplify get-app --app-id "$AMPLIFY_APP_ID" > /dev/null 2>&1; then
            warn "Amplify app still exists: ${AMPLIFY_APP_ID}"
        else
            log "✅ Confirmed: Amplify app has been deleted"
        fi
    fi
    
    log "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}CLEANUP SUMMARY${NC}"
    echo "=========================================="
    echo "✅ Domain associations removed"
    echo "✅ Active builds stopped"
    echo "✅ Amplify branches deleted"
    echo "✅ Amplify application deleted"
    echo "✅ Local files cleaned up"
    echo ""
    echo "All AWS resources have been successfully removed."
    echo "No ongoing charges should occur from this deployment."
    echo ""
    
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        echo "Note: Project directory preserved at: ${PROJECT_DIR}"
        echo "You can manually remove it if no longer needed."
    fi
    
    echo "=========================================="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local exit_code=$?
    local line_number=$1
    
    error "Cleanup failed at line ${line_number} with exit code ${exit_code}"
    echo ""
    echo "Partial cleanup may have occurred. Please check the AWS Console"
    echo "to verify which resources still exist and remove them manually if needed."
    echo ""
    echo "Common manual cleanup steps:"
    echo "1. Check AWS Amplify Console for remaining apps"
    echo "2. Check Route 53 for DNS records (if custom domain was used)"
    echo "3. Check Certificate Manager for unused certificates"
    
    exit $exit_code
}

# Main cleanup function
main() {
    log "Starting Progressive Web App cleanup..."
    
    # Setup error handling
    trap 'handle_cleanup_error ${LINENO}' ERR
    
    check_prerequisites
    
    # Try to get app ID from various sources
    if ! get_amplify_app_id; then
        warn "Could not determine Amplify app ID"
        warn "If you have apps to delete, please use the AWS Console"
        exit 0
    fi
    
    confirm_deletion
    
    delete_domain_associations
    stop_active_builds
    delete_branches
    delete_amplify_app
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup process completed successfully!"
}

# Help function
show_help() {
    echo "Progressive Web App Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -a, --app-id APP_ID     Specify Amplify App ID to delete"
    echo "  -n, --app-name NAME     Search for app by name pattern"
    echo "  -f, --force             Skip confirmation prompts (use with caution)"
    echo "  --project-dir DIR       Specify project directory to clean up"
    echo ""
    echo "Environment Variables:"
    echo "  AMPLIFY_APP_ID         Amplify application ID"
    echo "  APP_NAME               Application name pattern for search"
    echo "  PROJECT_DIR            Project directory path"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 -a d1a2b3c4d5e6f                  # Delete specific app"
    echo "  $0 -n pwa-amplify                    # Search by name pattern"
    echo "  $0 --project-dir /path/to/project    # Specify project directory"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--app-id)
                AMPLIFY_APP_ID="$2"
                shift 2
                ;;
            -n|--app-name)
                APP_NAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            --project-dir)
                PROJECT_DIR="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    
    # Override confirmation if force flag is set
    if [ "$FORCE_CLEANUP" = true ]; then
        confirm_deletion() {
            warn "Force cleanup enabled - skipping confirmation"
        }
    fi
    
    main
fi
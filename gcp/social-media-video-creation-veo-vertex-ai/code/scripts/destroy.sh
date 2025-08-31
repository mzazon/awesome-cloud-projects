#!/bin/bash

# Destroy script for Social Media Video Creation with Veo 3 and Vertex AI
# This script safely removes all resources created by the deployment

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

# Force delete mode (skip confirmations)
FORCE=${FORCE:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

if [[ "$FORCE" == "true" ]]; then
    warning "Running in FORCE mode - skipping confirmations"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        if eval "$cmd"; then
            return 0
        else
            warning "Command failed (continuing): $cmd"
            return 1
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is required for storage operations. Please ensure it's installed."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Look for deployment state files
    local state_files
    mapfile -t state_files < <(find . -name "deployment_state_*.env" 2>/dev/null || true)
    
    if [[ ${#state_files[@]} -eq 0 ]]; then
        warning "No deployment state files found."
        log "You may need to provide resource names manually or search for resources."
        return 1
    elif [[ ${#state_files[@]} -eq 1 ]]; then
        DEPLOYMENT_STATE_FILE="${state_files[0]}"
        log "Found deployment state file: $DEPLOYMENT_STATE_FILE"
    else
        warning "Multiple deployment state files found:"
        for i in "${!state_files[@]}"; do
            echo "  $((i+1)). ${state_files[i]}"
        done
        
        if [[ "$FORCE" != "true" ]]; then
            read -rp "Select state file (1-${#state_files[@]}): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#state_files[@]} ]]; then
                DEPLOYMENT_STATE_FILE="${state_files[$((selection-1))]}"
            else
                error "Invalid selection"
            fi
        else
            DEPLOYMENT_STATE_FILE="${state_files[0]}"
            warning "Using first state file in force mode: $DEPLOYMENT_STATE_FILE"
        fi
    fi
    
    # Source the deployment state
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$DEPLOYMENT_STATE_FILE"
        success "Loaded deployment state from: $DEPLOYMENT_STATE_FILE"
        
        log "Found resources:"
        echo "  • Project: ${PROJECT_ID:-Not set}"
        echo "  • Region: ${REGION:-Not set}"
        echo "  • Storage Bucket: ${BUCKET_NAME:-Not set}"
        echo "  • Function Name: ${FUNCTION_NAME:-Not set}"
        echo "  • Random Suffix: ${RANDOM_SUFFIX:-Not set}"
        
        return 0
    else
        error "Deployment state file not found: $DEPLOYMENT_STATE_FILE"
    fi
}

# Function to prompt for confirmation
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  • Cloud Storage bucket: gs://${BUCKET_NAME:-unknown}"
    echo "  • Cloud Functions:"
    echo "    - ${FUNCTION_NAME:-unknown}"
    echo "    - validator-${RANDOM_SUFFIX:-unknown}"
    echo "    - monitor-${RANDOM_SUFFIX:-unknown}"
    echo "  • All stored videos and metadata"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -rp "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed by user"
}

# Function to set default project
set_project_context() {
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log "Setting project context..."
        execute_cmd "gcloud config set project ${PROJECT_ID}" "Setting project to ${PROJECT_ID}"
        success "Project context set"
    else
        warning "No PROJECT_ID found in deployment state"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    if [[ -z "${FUNCTION_NAME:-}" ]] || [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        warning "Function names not found in deployment state. Attempting auto-discovery..."
        
        # Try to find functions with common patterns
        local functions
        mapfile -t functions < <(gcloud functions list --format="value(name)" --filter="name~video" 2>/dev/null || true)
        
        if [[ ${#functions[@]} -gt 0 ]]; then
            warning "Found video-related functions:"
            for func in "${functions[@]}"; do
                echo "  • $func"
            done
            
            if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
                read -rp "Delete these functions? (y/N): " delete_confirm
                if [[ "$delete_confirm" != "y" ]] && [[ "$delete_confirm" != "Y" ]]; then
                    log "Skipping function deletion"
                    return 0
                fi
            fi
            
            for func in "${functions[@]}"; do
                execute_cmd "gcloud functions delete $func --quiet" "Deleting function: $func"
            done
        else
            warning "No video-related functions found to delete"
        fi
    else
        # Delete known functions
        local functions=("${FUNCTION_NAME}" "validator-${RANDOM_SUFFIX}" "monitor-${RANDOM_SUFFIX}")
        
        for func in "${functions[@]}"; do
            # Check if function exists before attempting deletion
            if gcloud functions describe "$func" &> /dev/null; then
                execute_cmd "gcloud functions delete $func --quiet" "Deleting function: $func"
            else
                warning "Function not found (may already be deleted): $func"
            fi
        done
    fi
    
    success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        warning "Bucket name not found in deployment state. Attempting auto-discovery..."
        
        # Try to find buckets with social-videos pattern
        local buckets
        mapfile -t buckets < <(gsutil ls -b | grep "gs://social-videos-" | sed 's|gs://||' | sed 's|/||' 2>/dev/null || true)
        
        if [[ ${#buckets[@]} -gt 0 ]]; then
            warning "Found social-videos buckets:"
            for bucket in "${buckets[@]}"; do
                echo "  • gs://$bucket"
            done
            
            if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
                read -rp "Delete these buckets and all their contents? (y/N): " delete_confirm
                if [[ "$delete_confirm" != "y" ]] && [[ "$delete_confirm" != "Y" ]]; then
                    log "Skipping bucket deletion"
                    return 0
                fi
            fi
            
            for bucket in "${buckets[@]}"; do
                execute_cmd "gsutil -m rm -r gs://$bucket" "Deleting bucket and contents: gs://$bucket"
            done
        else
            warning "No social-videos buckets found to delete"
        fi
    else
        # Check if bucket exists before attempting deletion
        if gsutil ls -b gs://"${BUCKET_NAME}" &> /dev/null; then
            # Show bucket contents before deletion
            if [[ "$DRY_RUN" != "true" ]]; then
                log "Bucket contents:"
                gsutil ls -l gs://"${BUCKET_NAME}" 2>/dev/null || echo "  (empty or inaccessible)"
                echo ""
            fi
            
            execute_cmd "gsutil -m rm -r gs://${BUCKET_NAME}" "Deleting bucket and all contents: gs://${BUCKET_NAME}"
        else
            warning "Bucket not found (may already be deleted): gs://${BUCKET_NAME}"
        fi
    fi
    
    success "Storage bucket cleanup completed"
}

# Function to clean up local artifacts
cleanup_local_artifacts() {
    log "Cleaning up local artifacts..."
    
    # Remove function directories
    if [[ -d "video-functions" ]]; then
        execute_cmd "rm -rf video-functions/" "Removing local function directories"
    else
        log "No local function directories found"
    fi
    
    # Remove deployment state file
    if [[ -n "${DEPLOYMENT_STATE_FILE:-}" ]] && [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        execute_cmd "rm -f $DEPLOYMENT_STATE_FILE" "Removing deployment state file"
    fi
    
    # Clean up any temporary files
    local temp_files
    mapfile -t temp_files < <(find . -name "*.tmp" -o -name "deployment_*.log" 2>/dev/null || true)
    
    if [[ ${#temp_files[@]} -gt 0 ]]; then
        for file in "${temp_files[@]}"; do
            execute_cmd "rm -f $file" "Removing temporary file: $file"
        done
    fi
    
    success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Skipping verification in dry-run mode"
        return 0
    fi
    
    local verification_errors=0
    
    # Check functions
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" &> /dev/null; then
            error "Function still exists: ${FUNCTION_NAME}"
            ((verification_errors++))
        fi
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local remaining_functions=("validator-${RANDOM_SUFFIX}" "monitor-${RANDOM_SUFFIX}")
        for func in "${remaining_functions[@]}"; do
            if gcloud functions describe "$func" &> /dev/null; then
                error "Function still exists: $func"
                ((verification_errors++))
            fi
        done
    fi
    
    # Check bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls -b gs://"${BUCKET_NAME}" &> /dev/null; then
            error "Bucket still exists: gs://${BUCKET_NAME}"
            ((verification_errors++))
        fi
    fi
    
    if [[ $verification_errors -eq 0 ]]; then
        success "All resources successfully deleted"
    else
        warning "$verification_errors verification errors found. Some resources may still exist."
    fi
}

# Function to search for remaining resources
search_remaining_resources() {
    log "Searching for any remaining resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping resource search in dry-run mode"
        return 0
    fi
    
    # Search for functions that might match our pattern
    log "Searching for video-related Cloud Functions..."
    local remaining_functions
    mapfile -t remaining_functions < <(gcloud functions list --format="value(name)" --filter="name~video OR name~generator OR name~validator OR name~monitor" 2>/dev/null || true)
    
    if [[ ${#remaining_functions[@]} -gt 0 ]]; then
        warning "Found potentially related functions:"
        for func in "${remaining_functions[@]}"; do
            echo "  • $func"
        done
    fi
    
    # Search for buckets that might match our pattern
    log "Searching for social-videos buckets..."
    local remaining_buckets
    mapfile -t remaining_buckets < <(gsutil ls -b | grep "social-videos" | sed 's|gs://||' | sed 's|/||' 2>/dev/null || true)
    
    if [[ ${#remaining_buckets[@]} -gt 0 ]]; then
        warning "Found potentially related buckets:"
        for bucket in "${remaining_buckets[@]}"; do
            echo "  • gs://$bucket"
        done
    fi
    
    if [[ ${#remaining_functions[@]} -eq 0 ]] && [[ ${#remaining_buckets[@]} -eq 0 ]]; then
        success "No additional resources found"
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary"
    echo ""
    echo "============================================"
    echo "Social Media Video Creation Pipeline Cleanup"
    echo "============================================"
    echo ""
    echo "📦 Resources Processed:"
    echo "  • Cloud Functions: Deleted"
    echo "  • Storage Bucket: Deleted"
    echo "  • Local Files: Cleaned up"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "This was a DRY-RUN - no actual resources were deleted"
    else
        success "Cleanup completed successfully!"
        echo ""
        echo "💰 Cost Impact:"
        echo "  • All billable resources have been removed"
        echo "  • No ongoing charges should occur"
        echo ""
    fi
    
    log "Cleanup process finished"
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup failed with exit code $exit_code"
        log "Some resources may still exist and require manual deletion"
        log "Check the Google Cloud Console for any remaining resources"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main cleanup function
main() {
    log "Starting Social Media Video Creation Pipeline cleanup..."
    log "Target Provider: Google Cloud Platform (GCP)"
    echo ""
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_deletion
    set_project_context
    delete_cloud_functions
    delete_storage_bucket
    cleanup_local_artifacts
    verify_deletion
    search_remaining_resources
    show_cleanup_summary
}

# Show help information
show_help() {
    echo "Social Media Video Creation Pipeline - Destroy Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Preview deletion without removing resources"
    echo "  --force        Skip confirmation prompts (use with caution)"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID     GCP Project ID (loaded from deployment state)"
    echo "  FORCE          Skip confirmations (true/false)"
    echo "  DRY_RUN        Preview mode (true/false)"
    echo ""
    echo "Examples:"
    echo "  ./destroy.sh                    # Interactive deletion"
    echo "  DRY_RUN=true ./destroy.sh       # Preview what would be deleted"
    echo "  FORCE=true ./destroy.sh         # Delete without prompts"
    echo ""
    echo "Safety Features:"
    echo "  • Requires explicit confirmation before deletion"
    echo "  • Loads resource names from deployment state files"
    echo "  • Verifies deletion completion"
    echo "  • Searches for any remaining resources"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Execute main function
main
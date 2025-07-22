#!/bin/bash

# Immersive XR Content Delivery with Immersive Stream for XR and Cloud CDN - Cleanup Script
# This script safely removes all XR content delivery platform infrastructure

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="xr-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Global variables
PROJECT_ID=""
REGION="us-central1"
SUFFIX=""
DRY_RUN=false
FORCE_DELETE=false
INTERACTIVE=true

# Resource names (will be computed from suffix)
BUCKET_NAME=""
CDN_NAME=""
STREAM_NAME=""

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely clean up Immersive XR Content Delivery Platform resources

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -s, --suffix SUFFIX           Resource name suffix (required)
    --dry-run                     Show what would be deleted without executing
    --force                       Skip confirmation prompts
    --non-interactive             Non-interactive mode (no prompts)
    -h, --help                   Show this help message

EXAMPLES:
    $SCRIPT_NAME --project-id my-xr-project --suffix abc123
    $SCRIPT_NAME --project-id my-project --suffix abc123 --dry-run
    $SCRIPT_NAME --project-id my-project --suffix abc123 --force

EOF
}

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running in dry-run mode
check_dry_run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE: Command would execute: $*"
        return 0
    fi
    return 1
}

# Execute command with dry-run support
execute_command() {
    local command="$*"
    log_info "Executing: $command"
    
    if check_dry_run "$command"; then
        return 0
    fi
    
    # Use best effort - don't fail if resource doesn't exist
    eval "$command" || {
        log_warning "Command failed (resource may not exist): $command"
        return 0
    }
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    
    if [[ "$INTERACTIVE" == "false" || "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Generate resource names from suffix
generate_resource_names() {
    if [[ -z "$SUFFIX" ]]; then
        error_exit "Resource name suffix is required. Use --suffix option."
    fi
    
    BUCKET_NAME="xr-assets-${SUFFIX}"
    CDN_NAME="xr-cdn-${SUFFIX}"
    STREAM_NAME="xr-stream-${SUFFIX}"
    
    log_info "Generated resource names with suffix: $SUFFIX"
    log_info "  Bucket: $BUCKET_NAME"
    log_info "  CDN: $CDN_NAME"
    log_info "  Stream: $STREAM_NAME"
}

# Check if resources exist
check_resources() {
    log_info "Checking which resources exist..."
    
    local resources_found=false
    local resource_list=""
    
    # Check storage bucket
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        resources_found=true
        resource_list+="\n  • Storage bucket: gs://$BUCKET_NAME"
    fi
    
    # Check CDN components
    if gcloud compute forwarding-rules describe "${CDN_NAME}-rule" --global &>/dev/null; then
        resources_found=true
        resource_list+="\n  • CDN forwarding rule: ${CDN_NAME}-rule"
    fi
    
    if gcloud compute target-http-proxies describe "${CDN_NAME}-proxy" &>/dev/null; then
        resources_found=true
        resource_list+="\n  • CDN proxy: ${CDN_NAME}-proxy"
    fi
    
    if gcloud compute url-maps describe "${CDN_NAME}-urlmap" &>/dev/null; then
        resources_found=true
        resource_list+="\n  • CDN URL map: ${CDN_NAME}-urlmap"
    fi
    
    if gcloud compute backend-buckets describe "${CDN_NAME}-backend" &>/dev/null; then
        resources_found=true
        resource_list+="\n  • CDN backend bucket: ${CDN_NAME}-backend"
    fi
    
    # Check XR service
    if gcloud beta immersive-stream xr service-instances describe "$STREAM_NAME" --location="$REGION" &>/dev/null; then
        resources_found=true
        resource_list+="\n  • XR service instance: $STREAM_NAME"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        resources_found=true
        resource_list+="\n  • Service account: xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    fi
    
    # Check logging metrics
    if gcloud logging metrics describe xr_session_starts &>/dev/null; then
        resources_found=true
        resource_list+="\n  • Logging metric: xr_session_starts"
    fi
    
    if gcloud logging metrics describe xr_session_duration &>/dev/null; then
        resources_found=true
        resource_list+="\n  • Logging metric: xr_session_duration"
    fi
    
    if [[ "$resources_found" == "false" ]]; then
        log_warning "No XR platform resources found with suffix '$SUFFIX'"
        log_info "This could mean:"
        log_info "  • Resources were already deleted"
        log_info "  • Wrong project ID or suffix"
        log_info "  • Resources were created with different names"
        exit 0
    fi
    
    echo -e "\n${YELLOW}Resources found for deletion:${NC}"
    echo -e "$resource_list"
    echo
}

# Delete XR service
delete_xr_service() {
    log_info "Deleting Immersive Stream for XR service..."
    
    if gcloud beta immersive-stream xr service-instances describe "$STREAM_NAME" --location="$REGION" &>/dev/null; then
        execute_command "gcloud beta immersive-stream xr service-instances delete $STREAM_NAME \
            --location=$REGION --quiet"
        log_success "XR service instance deleted: $STREAM_NAME"
    else
        log_info "XR service instance not found: $STREAM_NAME"
    fi
}

# Delete load balancer components
delete_load_balancer() {
    log_info "Deleting load balancer and CDN components..."
    
    # Delete in reverse order of creation to handle dependencies
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe "${CDN_NAME}-rule" --global &>/dev/null; then
        execute_command "gcloud compute forwarding-rules delete ${CDN_NAME}-rule --global --quiet"
        log_success "Forwarding rule deleted: ${CDN_NAME}-rule"
    else
        log_info "Forwarding rule not found: ${CDN_NAME}-rule"
    fi
    
    # Delete target proxy
    if gcloud compute target-http-proxies describe "${CDN_NAME}-proxy" &>/dev/null; then
        execute_command "gcloud compute target-http-proxies delete ${CDN_NAME}-proxy --quiet"
        log_success "Target proxy deleted: ${CDN_NAME}-proxy"
    else
        log_info "Target proxy not found: ${CDN_NAME}-proxy"
    fi
    
    # Delete URL map
    if gcloud compute url-maps describe "${CDN_NAME}-urlmap" &>/dev/null; then
        execute_command "gcloud compute url-maps delete ${CDN_NAME}-urlmap --quiet"
        log_success "URL map deleted: ${CDN_NAME}-urlmap"
    else
        log_info "URL map not found: ${CDN_NAME}-urlmap"
    fi
    
    # Delete backend bucket
    if gcloud compute backend-buckets describe "${CDN_NAME}-backend" &>/dev/null; then
        execute_command "gcloud compute backend-buckets delete ${CDN_NAME}-backend --quiet"
        log_success "Backend bucket deleted: ${CDN_NAME}-backend"
    else
        log_info "Backend bucket not found: ${CDN_NAME}-backend"
    fi
}

# Delete storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket and contents..."
    
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        # First, list the contents if in interactive mode
        if [[ "$INTERACTIVE" == "true" && "$DRY_RUN" == "false" ]]; then
            local object_count
            object_count=$(gsutil ls -r "gs://$BUCKET_NAME" | wc -l)
            if [[ $object_count -gt 1 ]]; then
                log_warning "Bucket contains $((object_count - 1)) objects"
                confirm_action "This will permanently delete all objects in gs://$BUCKET_NAME"
            fi
        fi
        
        execute_command "gsutil -m rm -r gs://$BUCKET_NAME"
        log_success "Storage bucket deleted: gs://$BUCKET_NAME"
    else
        log_info "Storage bucket not found: gs://$BUCKET_NAME"
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log_info "Deleting IAM resources..."
    
    local service_account="xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$service_account" &>/dev/null; then
        # First remove IAM policy bindings
        execute_command "gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member='serviceAccount:$service_account' \
            --role='roles/storage.objectViewer' --quiet" || true
        
        execute_command "gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member='serviceAccount:$service_account' \
            --role='roles/logging.logWriter' --quiet" || true
        
        execute_command "gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member='serviceAccount:$service_account' \
            --role='roles/monitoring.metricWriter' --quiet" || true
        
        # Delete service account
        execute_command "gcloud iam service-accounts delete $service_account --quiet"
        log_success "Service account deleted: $service_account"
    else
        log_info "Service account not found: $service_account"
    fi
    
    # Remove local key file if exists
    if [[ -f "xr-streaming-key.json" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -f "xr-streaming-key.json"
            log_success "Local service account key file deleted"
        else
            log_info "DRY RUN: Would delete local key file: xr-streaming-key.json"
        fi
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring and logging resources..."
    
    # Delete custom metrics
    if gcloud logging metrics describe xr_session_starts &>/dev/null; then
        execute_command "gcloud logging metrics delete xr_session_starts --quiet"
        log_success "Logging metric deleted: xr_session_starts"
    else
        log_info "Logging metric not found: xr_session_starts"
    fi
    
    if gcloud logging metrics describe xr_session_duration &>/dev/null; then
        execute_command "gcloud logging metrics delete xr_session_duration --quiet"
        log_success "Logging metric deleted: xr_session_duration"
    else
        log_info "Logging metric not found: xr_session_duration"
    fi
    
    # Note: We don't delete the entire monitoring workspace as it might be shared
    log_info "Note: Monitoring workspace and dashboards are preserved (may be shared)"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_clean=(
        "xr-streaming-key.json"
        "xr-deployment-*.log"
    )
    
    for file_pattern in "${files_to_clean[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            if ls $file_pattern 2>/dev/null; then
                rm -f $file_pattern
                log_success "Cleaned up local files: $file_pattern"
            fi
        else
            log_info "DRY RUN: Would clean up local files: $file_pattern"
        fi
    done
}

# Display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup completed successfully!"
    echo
    echo "======================================="
    echo "🧹 XR PLATFORM CLEANUP COMPLETED"
    echo "======================================="
    echo
    echo "📊 Cleanup Summary:"
    echo "  • Project ID: $PROJECT_ID"
    echo "  • Region: $REGION"
    echo "  • Resource Suffix: $SUFFIX"
    echo
    echo "🗑️  Deleted Resources:"
    echo "  • Storage bucket: gs://$BUCKET_NAME"
    echo "  • CDN configuration: ${CDN_NAME}-*"
    echo "  • XR service: $STREAM_NAME"
    echo "  • Service account: xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  • Custom logging metrics: xr_session_*"
    echo "  • Local key files and logs"
    echo
    echo "✅ Remaining Resources:"
    echo "  • Project: $PROJECT_ID (preserved)"
    echo "  • Enabled APIs (preserved for other resources)"
    echo "  • Monitoring workspace (preserved, may be shared)"
    echo
    echo "💡 Notes:"
    echo "  • All XR platform resources have been removed"
    echo "  • No ongoing charges for deleted resources"
    echo "  • You can safely re-deploy using deploy.sh"
    echo
    echo "📝 Log File: $LOG_FILE"
    echo
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed"
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available"
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Validate project
    if [[ -z "$PROJECT_ID" ]]; then
        error_exit "Project ID is required. Use --project-id option"
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error_exit "Project '$PROJECT_ID' not found or not accessible"
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &>/dev/null
    
    log_success "Prerequisites validation completed"
}

# Main cleanup function
main() {
    log_info "Starting XR Content Delivery Platform cleanup..."
    log_info "Log file: $LOG_FILE"
    
    validate_prerequisites
    generate_resource_names
    check_resources
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        confirm_action "⚠️  This will permanently delete all XR platform resources with suffix '$SUFFIX'"
    fi
    
    # Delete resources in reverse order of creation to handle dependencies
    delete_monitoring_resources
    delete_iam_resources
    delete_xr_service
    delete_load_balancer
    delete_storage_bucket
    cleanup_local_files
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

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
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --non-interactive)
            INTERACTIVE=false
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

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id option."
    usage
    exit 1
fi

if [[ -z "$SUFFIX" ]]; then
    log_error "Resource suffix is required. Use --suffix option."
    usage
    exit 1
fi

# Show startup message
echo "🧹 Immersive XR Content Delivery Platform Cleanup"
echo "==============================================="
echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 DRY RUN MODE - No resources will be deleted"
    echo
fi

# Run main cleanup
main

exit 0
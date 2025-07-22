#!/bin/bash

# Scalable Audio Content Distribution with Chirp 3 and Memorystore Valkey - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail

# Color codes for output
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

# Global variables
FORCE_DELETE=false
AUTO_APPROVE=false
STATE_FILE="deployment_state.json"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if jq is available (for state file parsing)
    if ! command -v jq &> /dev/null; then
        log_error "jq is not available. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log_info "Loading deployment state from $STATE_FILE"
        
        # Parse state file and export variables
        export PROJECT_ID=$(jq -r '.project_id' "$STATE_FILE" 2>/dev/null || echo "")
        export REGION=$(jq -r '.region' "$STATE_FILE" 2>/dev/null || echo "")
        export ZONE=$(jq -r '.zone' "$STATE_FILE" 2>/dev/null || echo "")
        export BUCKET_NAME=$(jq -r '.bucket_name' "$STATE_FILE" 2>/dev/null || echo "")
        export VALKEY_INSTANCE=$(jq -r '.valkey_instance' "$STATE_FILE" 2>/dev/null || echo "")
        export FUNCTION_NAME=$(jq -r '.function_name' "$STATE_FILE" 2>/dev/null || echo "")
        export CDN_IP_NAME=$(jq -r '.cdn_ip_name' "$STATE_FILE" 2>/dev/null || echo "")
        
        # Set gcloud defaults if project is available
        if [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "null" ]]; then
            gcloud config set project "$PROJECT_ID" --quiet
            if [[ -n "$REGION" && "$REGION" != "null" ]]; then
                gcloud config set compute/region "$REGION" --quiet
            fi
            if [[ -n "$ZONE" && "$ZONE" != "null" ]]; then
                gcloud config set compute/zone "$ZONE" --quiet
            fi
        fi
        
        log_success "Deployment state loaded successfully"
    else
        log_warning "Deployment state file not found. Using environment variables or prompting for values."
        
        # Use environment variables or current gcloud config
        export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
        export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")}"
        export ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")}"
        
        # If still no project, prompt user
        if [[ -z "$PROJECT_ID" ]]; then
            read -p "Enter Google Cloud Project ID: " PROJECT_ID
            gcloud config set project "$PROJECT_ID" --quiet
        fi
    fi
}

# Function to prompt for confirmation
confirm_destruction() {
    echo ""
    log_info "=== DESTRUCTION CONFIRMATION ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION:-us-central1}"
    log_info ""
    log_warning "This will DELETE the following resources:"
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "  • Cloud Storage bucket: ${BUCKET_NAME}"
    fi
    if [[ -n "${VALKEY_INSTANCE:-}" ]]; then
        log_info "  • Memorystore for Valkey instance: ${VALKEY_INSTANCE}"
    fi
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "  • Cloud Function: ${FUNCTION_NAME}"
    fi
    if [[ -n "${CDN_IP_NAME:-}" ]]; then
        log_info "  • CDN infrastructure and IP: ${CDN_IP_NAME}"
    fi
    
    log_info "  • Cloud Run service: audio-management-service"
    log_info "  • VPC network: audio-network"
    log_info "  • Service accounts and IAM bindings"
    log_info "  • Container images in Container Registry"
    log_info ""
    
    log_error "WARNING: This action is IRREVERSIBLE!"
    log_error "All data stored in these resources will be permanently lost."
    echo ""
    
    if [[ "$AUTO_APPROVE" != "true" && "$FORCE_DELETE" != "true" ]]; then
        read -p "Are you sure you want to delete all resources? Type 'DELETE' to confirm: " -r
        echo
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
        echo ""
        
        # Double confirmation for critical resources
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            log_warning "Final confirmation for Cloud Storage bucket deletion"
            read -p "This will permanently delete all audio files in bucket '${BUCKET_NAME}'. Type 'CONFIRM' to proceed: " -r
            echo
            if [[ "$REPLY" != "CONFIRM" ]]; then
                log_info "Bucket deletion cancelled by user"
                exit 0
            fi
        fi
    fi
}

# Function to discover resources automatically
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Try to find resources by common naming patterns if state file doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        log_info "Attempting to discover resources automatically..."
        
        # Find audio-related buckets
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "audio-content-" | head -1 || echo "")
            if [[ -n "$buckets" ]]; then
                BUCKET_NAME=$(basename "$buckets")
                log_info "Found bucket: $BUCKET_NAME"
            fi
        fi
        
        # Find Valkey instances
        if [[ -z "${VALKEY_INSTANCE:-}" ]]; then
            local instances=$(gcloud memcache instances list --region="$REGION" --format="value(name)" --filter="name~audio-cache-" 2>/dev/null | head -1 || echo "")
            if [[ -n "$instances" ]]; then
                VALKEY_INSTANCE=$(basename "$instances")
                log_info "Found Valkey instance: $VALKEY_INSTANCE"
            fi
        fi
        
        # Find Cloud Functions
        if [[ -z "${FUNCTION_NAME:-}" ]]; then
            local functions=$(gcloud functions list --region="$REGION" --format="value(name)" --filter="name~audio-processor-" 2>/dev/null | head -1 || echo "")
            if [[ -n "$functions" ]]; then
                FUNCTION_NAME=$(basename "$functions")
                log_info "Found Cloud Function: $FUNCTION_NAME"
            fi
        fi
        
        # Find CDN IP addresses
        if [[ -z "${CDN_IP_NAME:-}" ]]; then
            local addresses=$(gcloud compute addresses list --global --format="value(name)" --filter="name~audio-cdn-ip-" 2>/dev/null | head -1 || echo "")
            if [[ -n "$addresses" ]]; then
                CDN_IP_NAME="$addresses"
                log_info "Found CDN IP: $CDN_IP_NAME"
            fi
        fi
    fi
}

# Function to safely delete a resource with error handling
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="$3"
    
    log_info "Deleting $resource_type: $resource_name"
    
    if eval "$delete_command" 2>/dev/null; then
        log_success "$resource_type deleted successfully"
        return 0
    else
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log_warning "Failed to delete $resource_type (continuing due to --force)"
            return 0
        else
            log_error "Failed to delete $resource_type"
            return 1
        fi
    fi
}

# Function to delete Cloud Run services
delete_cloud_run_services() {
    log_info "Removing Cloud Run services..."
    
    # Delete audio management service
    if gcloud run services describe audio-management-service --platform managed --region "$REGION" &>/dev/null; then
        safe_delete "Cloud Run service" \
            "gcloud run services delete audio-management-service --platform managed --region '$REGION' --quiet" \
            "audio-management-service"
    else
        log_info "Cloud Run service audio-management-service not found or already deleted"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Removing Cloud Function: $FUNCTION_NAME"
        
        if gcloud functions describe "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
            safe_delete "Cloud Function" \
                "gcloud functions delete '$FUNCTION_NAME' --region '$REGION' --quiet" \
                "$FUNCTION_NAME"
        else
            log_info "Cloud Function $FUNCTION_NAME not found or already deleted"
        fi
    else
        log_info "No Cloud Function specified for deletion"
    fi
}

# Function to delete CDN infrastructure
delete_cdn_infrastructure() {
    log_info "Removing CDN infrastructure..."
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe audio-http-rule --global &>/dev/null; then
        safe_delete "CDN forwarding rule" \
            "gcloud compute forwarding-rules delete audio-http-rule --global --quiet" \
            "audio-http-rule"
    fi
    
    # Delete target HTTP proxy
    if gcloud compute target-http-proxies describe audio-http-proxy &>/dev/null; then
        safe_delete "CDN target HTTP proxy" \
            "gcloud compute target-http-proxies delete audio-http-proxy --quiet" \
            "audio-http-proxy"
    fi
    
    # Delete URL map
    if gcloud compute url-maps describe audio-cdn-map &>/dev/null; then
        safe_delete "CDN URL map" \
            "gcloud compute url-maps delete audio-cdn-map --quiet" \
            "audio-cdn-map"
    fi
    
    # Delete backend bucket
    if gcloud compute backend-buckets describe audio-backend &>/dev/null; then
        safe_delete "CDN backend bucket" \
            "gcloud compute backend-buckets delete audio-backend --quiet" \
            "audio-backend"
    fi
    
    # Delete global IP address
    if [[ -n "${CDN_IP_NAME:-}" ]] && gcloud compute addresses describe "$CDN_IP_NAME" --global &>/dev/null; then
        safe_delete "CDN global IP address" \
            "gcloud compute addresses delete '$CDN_IP_NAME' --global --quiet" \
            "$CDN_IP_NAME"
    fi
}

# Function to delete Memorystore instances
delete_memorystore_instances() {
    if [[ -n "${VALKEY_INSTANCE:-}" ]]; then
        log_info "Removing Memorystore for Valkey instance: $VALKEY_INSTANCE"
        
        if gcloud memcache instances describe "$VALKEY_INSTANCE" --region "$REGION" &>/dev/null; then
            log_info "Deleting Valkey instance (this may take several minutes)..."
            safe_delete "Memorystore for Valkey instance" \
                "gcloud memcache instances delete '$VALKEY_INSTANCE' --region '$REGION' --quiet" \
                "$VALKEY_INSTANCE"
            
            # Wait for deletion to complete
            log_info "Waiting for Valkey instance deletion to complete..."
            local max_attempts=20
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                if ! gcloud memcache instances describe "$VALKEY_INSTANCE" --region "$REGION" &>/dev/null; then
                    log_success "Valkey instance deletion confirmed"
                    break
                fi
                
                log_info "Attempt $attempt/$max_attempts: Waiting for deletion..."
                sleep 30
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                log_warning "Valkey instance deletion timeout - may still be in progress"
            fi
        else
            log_info "Valkey instance $VALKEY_INSTANCE not found or already deleted"
        fi
    else
        log_info "No Valkey instance specified for deletion"
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Removing Cloud Storage bucket: $BUCKET_NAME"
        
        # Check if bucket exists
        if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
            # Remove all objects first (including versioned objects)
            log_info "Removing all objects from bucket..."
            gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true
            
            # Remove the bucket
            safe_delete "Cloud Storage bucket" \
                "gsutil rb 'gs://$BUCKET_NAME'" \
                "$BUCKET_NAME"
        else
            log_info "Cloud Storage bucket $BUCKET_NAME not found or already deleted"
        fi
    else
        log_info "No Cloud Storage bucket specified for deletion"
    fi
}

# Function to delete VPC network
delete_vpc_network() {
    log_info "Removing VPC network and subnet..."
    
    # Delete subnet first
    if gcloud compute networks subnets describe audio-subnet --region "$REGION" &>/dev/null; then
        safe_delete "VPC subnet" \
            "gcloud compute networks subnets delete audio-subnet --region '$REGION' --quiet" \
            "audio-subnet"
    fi
    
    # Delete VPC network
    if gcloud compute networks describe audio-network &>/dev/null; then
        safe_delete "VPC network" \
            "gcloud compute networks delete audio-network --quiet" \
            "audio-network"
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    log_info "Removing service accounts..."
    
    # Delete TTS service account
    local service_account="tts-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$service_account" &>/dev/null; then
        safe_delete "TTS service account" \
            "gcloud iam service-accounts delete '$service_account' --quiet" \
            "tts-service-account"
    else
        log_info "Service account tts-service-account not found or already deleted"
    fi
}

# Function to delete container images
delete_container_images() {
    log_info "Removing container images..."
    
    # Delete audio management service image
    local image_name="gcr.io/${PROJECT_ID}/audio-management-service"
    if gcloud container images list --repository="gcr.io/${PROJECT_ID}" --filter="name~audio-management-service" --format="value(name)" | grep -q .; then
        log_info "Deleting container image: $image_name"
        # Delete all tags for the image
        local tags=$(gcloud container images list-tags "$image_name" --format="value(tags)" --filter="tags:*" 2>/dev/null || echo "")
        if [[ -n "$tags" ]]; then
            for tag in $tags; do
                safe_delete "Container image tag" \
                    "gcloud container images delete '${image_name}:${tag}' --quiet --force-delete-tags" \
                    "${image_name}:${tag}"
            done
        fi
    else
        log_info "Container image audio-management-service not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    # Remove function directories
    if [[ -d "audio-processor-function" ]]; then
        rm -rf audio-processor-function
        log_success "Removed audio-processor-function directory"
    fi
    
    if [[ -d "audio-management-service" ]]; then
        rm -rf audio-management-service
        log_success "Removed audio-management-service directory"
    fi
    
    # Remove temporary files
    local temp_files=("tts-key.json" "cors.json" "lifecycle.json" "test-response.json" "deployment_state.tmp")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed temporary file: $file"
        fi
    done
    
    # Remove state file last
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_success "Removed deployment state file"
    fi
}

# Function to display destruction summary
display_summary() {
    echo ""
    log_info "=== CLEANUP SUMMARY ==="
    log_success "Infrastructure cleanup completed!"
    echo ""
    log_info "The following resources have been removed:"
    log_info "  • Cloud Run services"
    log_info "  • Cloud Functions"
    log_info "  • CDN infrastructure and global IP"
    log_info "  • Memorystore for Valkey instance"
    log_info "  • Cloud Storage bucket and all contents"
    log_info "  • VPC network and subnet"
    log_info "  • Service accounts and IAM bindings"
    log_info "  • Container images"
    log_info "  • Local files and directories"
    echo ""
    log_warning "Note: Some resources may take additional time to be fully removed from your project."
    log_info "Check the Google Cloud Console to verify complete cleanup."
    echo ""
}

# Main cleanup function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting cleanup of Scalable Audio Content Distribution solution..."
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_state
    discover_resources
    confirm_destruction
    
    log_info "Beginning resource deletion..."
    echo ""
    
    # Delete resources in proper order (reverse of creation)
    delete_cloud_run_services
    delete_cloud_functions
    delete_cdn_infrastructure
    delete_memorystore_instances
    delete_storage_buckets
    delete_vpc_network
    delete_service_accounts
    delete_container_images
    cleanup_local_files
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    display_summary
    log_success "Cleanup completed successfully in ${duration} seconds!"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Cleanup script for Scalable Audio Content Distribution infrastructure"
    echo ""
    echo "Options:"
    echo "  --force           Continue cleanup even if individual resource deletions fail"
    echo "  --auto-approve    Skip confirmation prompts (use with caution!)"
    echo "  --project ID      Specify Google Cloud project ID"
    echo "  --region REGION   Specify deployment region"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive cleanup with confirmations"
    echo "  $0 --force                  # Cleanup with error tolerance"
    echo "  $0 --auto-approve --force   # Fully automated cleanup (dangerous!)"
    echo ""
    echo "Note: This script will attempt to load deployment state from 'deployment_state.json'"
    echo "      If the state file is not found, it will try to discover resources automatically."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main cleanup with error handling
set +e  # Disable exit on error for cleanup
main
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_success "All cleanup operations completed successfully"
else
    log_warning "Some cleanup operations may have failed. Check the output above for details."
fi

exit $exit_code
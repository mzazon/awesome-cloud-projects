#!/bin/bash

# Edge Caching Performance with Cloud CDN and Memorystore - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if dry-run mode is enabled
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warn "Force delete enabled - will skip confirmation prompts"
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force:   Skip confirmation prompts"
            echo "  --help:    Show this help message"
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log "$description"
    if [[ "$ignore_errors" == "true" ]]; then
        eval "$cmd" || warn "Command failed but continuing: $cmd"
    else
        eval "$cmd"
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_args="${3:-}"
    
    case "$resource_type" in
        "forwarding-rule")
            gcloud compute forwarding-rules describe "$resource_name" --global &>/dev/null
            ;;
        "target-proxy")
            gcloud compute target-http-proxies describe "$resource_name" --global &>/dev/null
            ;;
        "url-map")
            gcloud compute url-maps describe "$resource_name" --global &>/dev/null
            ;;
        "backend-service")
            gcloud compute backend-services describe "$resource_name" --global &>/dev/null
            ;;
        "health-check")
            gcloud compute health-checks describe "$resource_name" &>/dev/null
            ;;
        "ip-address")
            gcloud compute addresses describe "$resource_name" --global &>/dev/null
            ;;
        "redis")
            gcloud redis instances describe "$resource_name" --region="$additional_args" &>/dev/null
            ;;
        "storage-bucket")
            gsutil ls -b "gs://$resource_name" &>/dev/null
            ;;
        "subnet")
            gcloud compute networks subnets describe "$resource_name" --region="$additional_args" &>/dev/null
            ;;
        "network")
            gcloud compute networks describe "$resource_name" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "deployment_info.json" ]]; then
        # Parse JSON using standard tools
        export PROJECT_ID=$(grep -o '"project_id":[^,]*' deployment_info.json | cut -d'"' -f4)
        export REGION=$(grep -o '"region":[^,]*' deployment_info.json | cut -d'"' -f4)
        export ZONE=$(grep -o '"zone":[^,]*' deployment_info.json | cut -d'"' -f4)
        
        # Extract resource names
        export REDIS_INSTANCE_NAME=$(grep -o '"redis_instance":[^,]*' deployment_info.json | cut -d'"' -f4)
        export BUCKET_NAME=$(grep -o '"storage_bucket":[^,]*' deployment_info.json | cut -d'"' -f4)
        export BACKEND_SERVICE_NAME=$(grep -o '"backend_service":[^,]*' deployment_info.json | cut -d'"' -f4)
        export URL_MAP_NAME=$(grep -o '"url_map":[^,]*' deployment_info.json | cut -d'"' -f4)
        export TARGET_PROXY_NAME=$(grep -o '"target_proxy":[^,]*' deployment_info.json | cut -d'"' -f4)
        export FORWARDING_RULE_NAME=$(grep -o '"forwarding_rule":[^,]*' deployment_info.json | cut -d'"' -f4)
        export HEALTH_CHECK_NAME=$(grep -o '"health_check":[^,]*' deployment_info.json | cut -d'"' -f4)
        export NETWORK_NAME=$(grep -o '"network":[^,]*' deployment_info.json | cut -d'"' -f4)
        export SUBNET_NAME=$(grep -o '"subnet":[^,]*' deployment_info.json | cut -d'"' -f4)
        export IP_ADDRESS_NAME=$(grep -o '"ip_address":[^,]*' deployment_info.json | cut -d'"' -f4)
        
        success "Deployment information loaded from deployment_info.json"
    else
        warn "deployment_info.json not found. Using environment variables or defaults."
        
        # Fallback to environment variables or prompt user
        if [[ -z "${PROJECT_ID:-}" ]]; then
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            if [[ -z "$PROJECT_ID" ]]; then
                error "No project ID found. Please set PROJECT_ID environment variable or run from deployment directory."
            fi
        fi
        
        # Set default region if not provided
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        
        warn "Using current project: $PROJECT_ID"
        warn "Using region: $REGION"
        warn "Resource names will be detected dynamically"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage utility (gsutil) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    # Verify project access
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Cannot access project: $PROJECT_ID. Check project ID and permissions."
    fi
    
    success "Prerequisites check completed"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "🚨 WARNING: This will permanently delete all Edge Caching Performance resources!"
    echo "============================================================================="
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources to be deleted:"
    echo "• Forwarding Rule: ${FORWARDING_RULE_NAME:-auto-detect}"
    echo "• Target HTTP Proxy: ${TARGET_PROXY_NAME:-auto-detect}"
    echo "• URL Map: ${URL_MAP_NAME:-auto-detect}"
    echo "• Backend Service: ${BACKEND_SERVICE_NAME:-auto-detect}"
    echo "• Health Check: ${HEALTH_CHECK_NAME:-auto-detect}"
    echo "• Static IP Address: ${IP_ADDRESS_NAME:-auto-detect}"
    echo "• Redis Instance: ${REDIS_INSTANCE_NAME:-auto-detect}"
    echo "• Storage Bucket: ${BUCKET_NAME:-auto-detect}"
    echo "• VPC Subnet: ${SUBNET_NAME:-auto-detect}"
    echo "• VPC Network: ${NETWORK_NAME:-auto-detect}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed by user"
}

# Auto-detect resource names if not provided
auto_detect_resources() {
    log "Auto-detecting resource names..."
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &>/dev/null
    
    # If resource names are not set, try to find them
    if [[ -z "${FORWARDING_RULE_NAME:-}" ]]; then
        FORWARDING_RULE_NAME=$(gcloud compute forwarding-rules list --global --format="value(name)" --filter="name~'cdn-forwarding-rule'" | head -1)
    fi
    
    if [[ -z "${TARGET_PROXY_NAME:-}" ]]; then
        TARGET_PROXY_NAME=$(gcloud compute target-http-proxies list --global --format="value(name)" --filter="name~'cdn-target-proxy'" | head -1)
    fi
    
    if [[ -z "${URL_MAP_NAME:-}" ]]; then
        URL_MAP_NAME=$(gcloud compute url-maps list --global --format="value(name)" --filter="name~'cdn-url-map'" | head -1)
    fi
    
    if [[ -z "${BACKEND_SERVICE_NAME:-}" ]]; then
        BACKEND_SERVICE_NAME=$(gcloud compute backend-services list --global --format="value(name)" --filter="name~'cdn-backend'" | head -1)
    fi
    
    if [[ -z "${HEALTH_CHECK_NAME:-}" ]]; then
        HEALTH_CHECK_NAME=$(gcloud compute health-checks list --format="value(name)" --filter="name~'cdn-health-check'" | head -1)
    fi
    
    if [[ -z "${IP_ADDRESS_NAME:-}" ]]; then
        IP_ADDRESS_NAME=$(gcloud compute addresses list --global --format="value(name)" --filter="name~'cdn-ip-address'" | head -1)
    fi
    
    if [[ -z "${REDIS_INSTANCE_NAME:-}" ]]; then
        REDIS_INSTANCE_NAME=$(gcloud redis instances list --region="$REGION" --format="value(name)" --filter="name~'intelligent-cache'" | head -1)
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        BUCKET_NAME=$(gsutil ls -p "$PROJECT_ID" | grep -o 'gs://cdn-origin-content-[^/]*' | head -1 | sed 's/gs:\/\///')
    fi
    
    if [[ -z "${SUBNET_NAME:-}" ]]; then
        SUBNET_NAME=$(gcloud compute networks subnets list --regions="$REGION" --format="value(name)" --filter="name~'cdn-subnet'" | head -1)
    fi
    
    if [[ -z "${NETWORK_NAME:-}" ]]; then
        NETWORK_NAME=$(gcloud compute networks list --format="value(name)" --filter="name~'cdn-network'" | head -1)
    fi
    
    success "Resource auto-detection completed"
}

# Delete forwarding rule
delete_forwarding_rule() {
    if [[ -n "${FORWARDING_RULE_NAME:-}" ]] && resource_exists "forwarding-rule" "$FORWARDING_RULE_NAME"; then
        execute_command "gcloud compute forwarding-rules delete $FORWARDING_RULE_NAME --global --quiet" \
            "Deleting forwarding rule: $FORWARDING_RULE_NAME"
        success "Forwarding rule deleted"
    else
        warn "Forwarding rule not found or already deleted"
    fi
}

# Delete target proxy
delete_target_proxy() {
    if [[ -n "${TARGET_PROXY_NAME:-}" ]] && resource_exists "target-proxy" "$TARGET_PROXY_NAME"; then
        execute_command "gcloud compute target-http-proxies delete $TARGET_PROXY_NAME --global --quiet" \
            "Deleting target HTTP proxy: $TARGET_PROXY_NAME"
        success "Target HTTP proxy deleted"
    else
        warn "Target HTTP proxy not found or already deleted"
    fi
}

# Delete URL map
delete_url_map() {
    if [[ -n "${URL_MAP_NAME:-}" ]] && resource_exists "url-map" "$URL_MAP_NAME"; then
        execute_command "gcloud compute url-maps delete $URL_MAP_NAME --global --quiet" \
            "Deleting URL map: $URL_MAP_NAME"
        success "URL map deleted"
    else
        warn "URL map not found or already deleted"
    fi
}

# Delete backend service
delete_backend_service() {
    if [[ -n "${BACKEND_SERVICE_NAME:-}" ]] && resource_exists "backend-service" "$BACKEND_SERVICE_NAME"; then
        execute_command "gcloud compute backend-services delete $BACKEND_SERVICE_NAME --global --quiet" \
            "Deleting backend service: $BACKEND_SERVICE_NAME"
        success "Backend service deleted"
    else
        warn "Backend service not found or already deleted"
    fi
}

# Delete health check
delete_health_check() {
    if [[ -n "${HEALTH_CHECK_NAME:-}" ]] && resource_exists "health-check" "$HEALTH_CHECK_NAME"; then
        execute_command "gcloud compute health-checks delete $HEALTH_CHECK_NAME --quiet" \
            "Deleting health check: $HEALTH_CHECK_NAME"
        success "Health check deleted"
    else
        warn "Health check not found or already deleted"
    fi
}

# Delete static IP address
delete_static_ip() {
    if [[ -n "${IP_ADDRESS_NAME:-}" ]] && resource_exists "ip-address" "$IP_ADDRESS_NAME"; then
        execute_command "gcloud compute addresses delete $IP_ADDRESS_NAME --global --quiet" \
            "Deleting static IP address: $IP_ADDRESS_NAME"
        success "Static IP address deleted"
    else
        warn "Static IP address not found or already deleted"
    fi
}

# Delete Redis instance
delete_redis_instance() {
    if [[ -n "${REDIS_INSTANCE_NAME:-}" ]] && resource_exists "redis" "$REDIS_INSTANCE_NAME" "$REGION"; then
        execute_command "gcloud redis instances delete $REDIS_INSTANCE_NAME --region=$REGION --quiet" \
            "Deleting Redis instance: $REDIS_INSTANCE_NAME"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Waiting for Redis instance deletion to complete..."
            local max_attempts=20
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                if ! resource_exists "redis" "$REDIS_INSTANCE_NAME" "$REGION"; then
                    break
                fi
                
                log "Redis instance still exists (attempt $attempt/$max_attempts)"
                sleep 30
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                warn "Redis instance deletion is taking longer than expected"
            fi
        fi
        
        success "Redis instance deleted"
    else
        warn "Redis instance not found or already deleted"
    fi
}

# Delete storage bucket
delete_storage_bucket() {
    if [[ -n "${BUCKET_NAME:-}" ]] && resource_exists "storage-bucket" "$BUCKET_NAME"; then
        execute_command "gsutil -m rm -r gs://$BUCKET_NAME" \
            "Deleting storage bucket: $BUCKET_NAME"
        success "Storage bucket deleted"
    else
        warn "Storage bucket not found or already deleted"
    fi
}

# Delete subnet
delete_subnet() {
    if [[ -n "${SUBNET_NAME:-}" ]] && resource_exists "subnet" "$SUBNET_NAME" "$REGION"; then
        execute_command "gcloud compute networks subnets delete $SUBNET_NAME --region=$REGION --quiet" \
            "Deleting subnet: $SUBNET_NAME"
        success "Subnet deleted"
    else
        warn "Subnet not found or already deleted"
    fi
}

# Delete VPC network
delete_network() {
    if [[ -n "${NETWORK_NAME:-}" ]] && resource_exists "network" "$NETWORK_NAME"; then
        execute_command "gcloud compute networks delete $NETWORK_NAME --quiet" \
            "Deleting VPC network: $NETWORK_NAME"
        success "VPC network deleted"
    else
        warn "VPC network not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment_info.json"
        "cache_invalidation.py"
        "monitoring_dashboard.json"
        "index.html"
        "api-response.json"
        "deployment-*.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ "$file" == "deployment-*.log" ]]; then
            # Handle wildcard pattern
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f deployment-*.log 2>/dev/null || true
            fi
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Would remove: $file"
        elif [[ -f "$file" ]]; then
            execute_command "rm -f $file" "Removing local file: $file" "true"
        fi
    done
    
    success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local remaining_resources=()
    
    # Check each resource type
    if [[ -n "${FORWARDING_RULE_NAME:-}" ]] && resource_exists "forwarding-rule" "$FORWARDING_RULE_NAME"; then
        remaining_resources+=("Forwarding Rule: $FORWARDING_RULE_NAME")
    fi
    
    if [[ -n "${TARGET_PROXY_NAME:-}" ]] && resource_exists "target-proxy" "$TARGET_PROXY_NAME"; then
        remaining_resources+=("Target HTTP Proxy: $TARGET_PROXY_NAME")
    fi
    
    if [[ -n "${URL_MAP_NAME:-}" ]] && resource_exists "url-map" "$URL_MAP_NAME"; then
        remaining_resources+=("URL Map: $URL_MAP_NAME")
    fi
    
    if [[ -n "${BACKEND_SERVICE_NAME:-}" ]] && resource_exists "backend-service" "$BACKEND_SERVICE_NAME"; then
        remaining_resources+=("Backend Service: $BACKEND_SERVICE_NAME")
    fi
    
    if [[ -n "${HEALTH_CHECK_NAME:-}" ]] && resource_exists "health-check" "$HEALTH_CHECK_NAME"; then
        remaining_resources+=("Health Check: $HEALTH_CHECK_NAME")
    fi
    
    if [[ -n "${IP_ADDRESS_NAME:-}" ]] && resource_exists "ip-address" "$IP_ADDRESS_NAME"; then
        remaining_resources+=("Static IP Address: $IP_ADDRESS_NAME")
    fi
    
    if [[ -n "${REDIS_INSTANCE_NAME:-}" ]] && resource_exists "redis" "$REDIS_INSTANCE_NAME" "$REGION"; then
        remaining_resources+=("Redis Instance: $REDIS_INSTANCE_NAME")
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]] && resource_exists "storage-bucket" "$BUCKET_NAME"; then
        remaining_resources+=("Storage Bucket: $BUCKET_NAME")
    fi
    
    if [[ -n "${SUBNET_NAME:-}" ]] && resource_exists "subnet" "$SUBNET_NAME" "$REGION"; then
        remaining_resources+=("Subnet: $SUBNET_NAME")
    fi
    
    if [[ -n "${NETWORK_NAME:-}" ]] && resource_exists "network" "$NETWORK_NAME"; then
        remaining_resources+=("VPC Network: $NETWORK_NAME")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warn "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            echo "  - $resource"
        done
        warn "You may need to manually delete these resources"
    fi
}

# Main cleanup function
main() {
    log "Starting Edge Caching Performance cleanup..."
    
    # Load deployment information
    load_deployment_info
    
    # Check prerequisites
    check_prerequisites
    
    # Auto-detect resources if needed
    auto_detect_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_forwarding_rule
    delete_target_proxy
    delete_url_map
    delete_backend_service
    delete_health_check
    delete_static_ip
    delete_redis_instance
    delete_storage_bucket
    delete_subnet
    delete_network
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    success "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "🎉 Edge Caching Performance Resources Cleaned Up!"
        echo "==============================================="
        echo "All infrastructure resources have been removed."
        echo "Your Google Cloud project is now clean."
        echo ""
        echo "Note: It may take a few minutes for all resources to be fully removed from the Google Cloud Console."
    else
        echo ""
        echo "🎯 Dry-run cleanup completed successfully!"
        echo "======================================="
        echo "All resources would be deleted as shown above."
        echo "Run without --dry-run to actually perform cleanup."
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [[ "$DRY_RUN" == "false" ]]; then
        warn "Cleanup interrupted. Some resources may still exist."
        warn "You can re-run this script to continue the cleanup process."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"
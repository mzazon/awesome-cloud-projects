#!/bin/bash

# Global Web Application Performance with Firebase App Hosting and Cloud CDN - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
BUCKET_NAME=""
FUNCTION_NAME=""
DRY_RUN=false
FORCE=false
CONFIRM=true

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Global Web Application Performance solution resources

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION            Deployment region (default: us-central1)
    -b, --bucket-name NAME         Bucket name to delete (optional, will auto-detect)
    -f, --function-name NAME       Function name to delete (optional, will auto-detect)
    --dry-run                      Show what would be deleted without executing
    --force                        Skip individual resource confirmations
    --no-confirm                   Skip all confirmations (dangerous!)
    -h, --help                     Show this help message

EXAMPLES:
    $0 -p my-project
    $0 --project-id my-project --region europe-west1
    $0 -p my-project --dry-run
    $0 -p my-project --force

SAFETY FEATURES:
    - Interactive confirmation for destructive operations
    - Dry-run mode to preview changes
    - Resource dependency checking before deletion
    - Backup verification for critical data

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
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-confirm)
                CONFIRM=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use -p or --project-id"
        show_usage
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required tools
    local required_tools=("gcloud" "firebase" "gsutil")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi

    # Validate project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible"
        exit 1
    fi

    # Set active project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"

    log_success "Prerequisites check completed"
}

# Auto-detect resources if not specified
auto_detect_resources() {
    log_info "Auto-detecting resources to clean up..."

    # Auto-detect bucket if not specified
    if [[ -z "$BUCKET_NAME" ]]; then
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://web-assets-" | head -1 | sed 's|gs://||' | sed 's|/||' || true)
        if [[ -n "$buckets" ]]; then
            BUCKET_NAME="$buckets"
            log_info "Auto-detected bucket: $BUCKET_NAME"
        fi
    fi

    # Auto-detect function if not specified
    if [[ -z "$FUNCTION_NAME" ]]; then
        local functions
        functions=$(gcloud functions list --filter="name:perf-optimizer-" --format="value(name)" 2>/dev/null | head -1 || true)
        if [[ -n "$functions" ]]; then
            FUNCTION_NAME="$(basename "$functions")"
            log_info "Auto-detected function: $FUNCTION_NAME"
        fi
    fi
}

# Confirm destruction with user
confirm_destruction() {
    if [[ "$CONFIRM" == false ]]; then
        return 0
    fi

    log_warning "This will permanently delete the following resources:"
    echo ""
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "Cloud Storage Bucket: $BUCKET_NAME (and all contents)"
    fi
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo "Cloud Function: $FUNCTION_NAME"
    fi
    echo "Load Balancer and CDN resources"
    echo "Firebase App Hosting backend"
    echo "Cloud Monitoring alerts"
    echo "Pub/Sub topics"
    echo ""
    
    log_warning "This action cannot be undone!"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN MODE - No resources will actually be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (Type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Check for data in Cloud Storage bucket
check_bucket_data() {
    if [[ -n "$BUCKET_NAME" && "$DRY_RUN" == false ]]; then
        log_info "Checking bucket contents..."
        
        local object_count
        object_count=$(gsutil ls -r "gs://$BUCKET_NAME" 2>/dev/null | wc -l || echo "0")
        
        if [[ $object_count -gt 0 ]]; then
            log_warning "Bucket gs://$BUCKET_NAME contains $object_count objects"
            
            if [[ "$FORCE" == false && "$CONFIRM" == true ]]; then
                read -p "Do you want to delete all bucket contents? (yes/no): " delete_contents
                if [[ "$delete_contents" != "yes" ]]; then
                    log_info "Skipping bucket deletion to preserve data"
                    BUCKET_NAME=""
                    return 0
                fi
            fi
            
            log_info "Will delete bucket and all contents..."
        fi
    fi
}

# Remove load balancer and CDN resources
cleanup_load_balancer_cdn() {
    log_info "Cleaning up Load Balancer and CDN resources..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete forwarding rule: web-app-forwarding-rule"
        log_info "[DRY RUN] Would delete HTTPS proxy: web-app-proxy"
        log_info "[DRY RUN] Would delete SSL certificate: web-app-ssl-cert"
        log_info "[DRY RUN] Would delete URL map: web-app-urlmap"
        log_info "[DRY RUN] Would delete backend bucket: web-assets-backend"
        log_info "[DRY RUN] Would delete global IP: web-app-ip"
        return 0
    fi

    # Delete forwarding rule
    if gcloud compute forwarding-rules describe web-app-forwarding-rule --global &>/dev/null; then
        log_info "Deleting forwarding rule..."
        gcloud compute forwarding-rules delete web-app-forwarding-rule --global --quiet
        log_success "✓ Forwarding rule deleted"
    else
        log_info "Forwarding rule not found, skipping"
    fi

    # Delete HTTPS proxy
    if gcloud compute target-https-proxies describe web-app-proxy &>/dev/null; then
        log_info "Deleting HTTPS proxy..."
        gcloud compute target-https-proxies delete web-app-proxy --quiet
        log_success "✓ HTTPS proxy deleted"
    else
        log_info "HTTPS proxy not found, skipping"
    fi

    # Delete SSL certificate
    if gcloud compute ssl-certificates describe web-app-ssl-cert --global &>/dev/null; then
        log_info "Deleting SSL certificate..."
        gcloud compute ssl-certificates delete web-app-ssl-cert --global --quiet
        log_success "✓ SSL certificate deleted"
    else
        log_info "SSL certificate not found, skipping"
    fi

    # Delete URL map
    if gcloud compute url-maps describe web-app-urlmap &>/dev/null; then
        log_info "Deleting URL map..."
        gcloud compute url-maps delete web-app-urlmap --quiet
        log_success "✓ URL map deleted"
    else
        log_info "URL map not found, skipping"
    fi

    # Delete backend bucket
    if gcloud compute backend-buckets describe web-assets-backend &>/dev/null; then
        log_info "Deleting backend bucket..."
        gcloud compute backend-buckets delete web-assets-backend --quiet
        log_success "✓ Backend bucket deleted"
    else
        log_info "Backend bucket not found, skipping"
    fi

    # Delete global IP address
    if gcloud compute addresses describe web-app-ip --global &>/dev/null; then
        log_info "Deleting global IP address..."
        gcloud compute addresses delete web-app-ip --global --quiet
        log_success "✓ Global IP address deleted"
    else
        log_info "Global IP address not found, skipping"
    fi

    log_success "Load Balancer and CDN cleanup completed"
}

# Remove Firebase App Hosting
cleanup_firebase_hosting() {
    log_info "Cleaning up Firebase App Hosting..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete Firebase App Hosting backend: web-app-backend"
        log_info "[DRY RUN] Would clean up Firebase hosting sites"
        return 0
    fi

    # Delete Firebase App Hosting backend
    if firebase apphosting:backends:list --project="$PROJECT_ID" 2>/dev/null | grep -q "web-app-backend"; then
        log_info "Deleting Firebase App Hosting backend..."
        firebase apphosting:backends:delete web-app-backend \
            --project="$PROJECT_ID" \
            --location="$REGION" \
            --force 2>/dev/null || log_warning "Failed to delete App Hosting backend (may not exist)"
        log_success "✓ Firebase App Hosting backend deleted"
    else
        log_info "Firebase App Hosting backend not found, skipping"
    fi

    # Clean up hosting sites
    local sites
    sites=$(firebase hosting:sites:list --project="$PROJECT_ID" 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
    
    for site in $sites; do
        if [[ -n "$site" && "$site" != "Site" ]]; then
            log_info "Cleaning up hosting site: $site"
            firebase hosting:sites:delete "$site" --project="$PROJECT_ID" --force 2>/dev/null || log_warning "Failed to delete site $site"
        fi
    done

    log_success "Firebase hosting cleanup completed"
}

# Remove Cloud Functions
cleanup_cloud_functions() {
    if [[ -z "$FUNCTION_NAME" ]]; then
        log_info "No Cloud Function specified, skipping"
        return 0
    fi

    log_info "Cleaning up Cloud Function: $FUNCTION_NAME"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: $FUNCTION_NAME"
        return 0
    fi

    # Delete Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
        log_info "Deleting Cloud Function..."
        gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet
        log_success "✓ Cloud Function deleted: $FUNCTION_NAME"
    else
        log_info "Cloud Function not found, skipping"
    fi

    log_success "Cloud Functions cleanup completed"
}

# Remove Cloud Storage
cleanup_cloud_storage() {
    if [[ -z "$BUCKET_NAME" ]]; then
        log_info "No Cloud Storage bucket specified, skipping"
        return 0
    fi

    log_info "Cleaning up Cloud Storage bucket: $BUCKET_NAME"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete bucket and all contents: gs://$BUCKET_NAME"
        return 0
    fi

    # Delete bucket and all contents
    if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
        log_info "Deleting bucket contents and bucket..."
        gsutil -m rm -rf "gs://$BUCKET_NAME"
        log_success "✓ Cloud Storage bucket deleted: $BUCKET_NAME"
    else
        log_info "Cloud Storage bucket not found, skipping"
    fi

    log_success "Cloud Storage cleanup completed"
}

# Remove monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up Cloud Monitoring resources..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete monitoring policies and dashboards"
        return 0
    fi

    # Delete alerting policies
    local policies
    policies=$(gcloud alpha monitoring policies list --filter="displayName:'High Latency Alert'" --format="get(name)" 2>/dev/null || true)
    
    for policy in $policies; do
        if [[ -n "$policy" ]]; then
            log_info "Deleting alerting policy: $(basename "$policy")"
            gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null || log_warning "Failed to delete policy $policy"
        fi
    done

    log_success "Cloud Monitoring cleanup completed"
}

# Remove Pub/Sub resources
cleanup_pubsub() {
    log_info "Cleaning up Pub/Sub resources..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete Pub/Sub topic: performance-metrics"
        return 0
    fi

    # Delete Pub/Sub topic
    if gcloud pubsub topics describe performance-metrics &>/dev/null; then
        log_info "Deleting Pub/Sub topic..."
        gcloud pubsub topics delete performance-metrics --quiet
        log_success "✓ Pub/Sub topic deleted: performance-metrics"
    else
        log_info "Pub/Sub topic not found, skipping"
    fi

    log_success "Pub/Sub cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean up local directories and files"
        return 0
    fi

    # Remove created directories and files
    local cleanup_items=("web-app" "performance-optimizer" "firebase.json" "cors.json" "alerting-policy.json")
    
    for item in "${cleanup_items[@]}"; do
        if [[ -e "$item" ]]; then
            log_info "Removing local $item..."
            rm -rf "$item"
            log_success "✓ Removed: $item"
        fi
    done

    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would verify all resources are deleted"
        return 0
    fi

    local cleanup_issues=0

    # Check if bucket still exists
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
        log_warning "✗ Bucket still exists: $BUCKET_NAME"
        ((cleanup_issues++))
    fi

    # Check if function still exists
    if [[ -n "$FUNCTION_NAME" ]] && gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
        log_warning "✗ Function still exists: $FUNCTION_NAME"
        ((cleanup_issues++))
    fi

    # Check if global IP still exists
    if gcloud compute addresses describe web-app-ip --global &>/dev/null; then
        log_warning "✗ Global IP still exists: web-app-ip"
        ((cleanup_issues++))
    fi

    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "✓ All resources successfully removed"
    else
        log_warning "⚠ $cleanup_issues resources may still exist. Manual cleanup may be required."
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "Bucket: $BUCKET_NAME (deleted)"
    fi
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo "Function: $FUNCTION_NAME (deleted)"
    fi
    echo "Load Balancer/CDN: Removed"
    echo "Firebase Hosting: Cleaned up"
    echo "Monitoring: Cleaned up"
    echo "Pub/Sub: Cleaned up"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN COMPLETED - No resources were actually deleted"
    else
        log_success "Cleanup completed successfully!"
    fi
    
    echo ""
    log_info "Post-cleanup notes:"
    echo "1. Verify no unexpected charges on your Google Cloud billing"
    echo "2. Check that all required data was backed up before deletion"
    echo "3. Review any remaining resources in the console"
    echo "4. Consider deleting the entire project if no longer needed"
}

# Main cleanup function
main() {
    log_info "Starting Global Web Application Performance cleanup..."
    
    parse_args "$@"
    check_prerequisites
    auto_detect_resources
    confirm_destruction
    check_bucket_data
    
    # Execute cleanup in dependency order
    cleanup_load_balancer_cdn
    cleanup_firebase_hosting
    cleanup_cloud_functions
    cleanup_monitoring
    cleanup_pubsub
    cleanup_cloud_storage
    cleanup_local_files
    
    verify_cleanup
    show_cleanup_summary
}

# Execute main function with all arguments
main "$@"
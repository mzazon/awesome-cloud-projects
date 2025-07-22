#!/bin/bash

# Dynamic Resource Governance with Cloud Asset Inventory and Policy Simulator - Cleanup Script
# This script safely removes all governance infrastructure resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable debug mode if DEBUG=true
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY RUN mode - no actual resources will be deleted"
fi

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values - can be overridden by environment variables
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}
REGION=${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")}
ZONE=${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        log_error "No authenticated account found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set. Please set it as an environment variable or use --project flag"
        exit 1
    fi
    
    # Check if project exists and user has access
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
            log_error "Project $PROJECT_ID does not exist or you don't have access to it"
            exit 1
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    log_warning "This will delete ALL governance infrastructure resources in project: $PROJECT_ID"
    log_warning "This action cannot be undone!"
    echo ""
    echo "Resources that will be deleted:"
    echo "- Cloud Functions (asset analyzer, policy validator, compliance engine)"
    echo "- Cloud Asset Inventory feeds"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Service accounts and IAM bindings"
    echo "- Test resources (if any)"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

# Function to discover resources by pattern
discover_resources() {
    log_info "Discovering governance resources..."
    
    # Try to find resources by common patterns
    local discovered_resources=()
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Discover Cloud Functions
        local functions
        functions=$(gcloud functions list --regions="$REGION" --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*policy* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$functions" ]]; then
            log_info "Found Cloud Functions: $functions"
            discovered_resources+=("functions")
        fi
        
        # Discover Asset Inventory feeds
        local feeds
        feeds=$(gcloud asset feeds list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset*" 2>/dev/null || true)
        
        if [[ -n "$feeds" ]]; then
            log_info "Found Asset Inventory feeds: $feeds"
            discovered_resources+=("feeds")
        fi
        
        # Discover Pub/Sub topics
        local topics
        topics=$(gcloud pubsub topics list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$topics" ]]; then
            log_info "Found Pub/Sub topics: $topics"
            discovered_resources+=("topics")
        fi
        
        # Discover service accounts
        local service_accounts
        service_accounts=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" --filter="email:*governance* OR email:*asset*" 2>/dev/null || true)
        
        if [[ -n "$service_accounts" ]]; then
            log_info "Found service accounts: $service_accounts"
            discovered_resources+=("service_accounts")
        fi
        
        if [[ ${#discovered_resources[@]} -eq 0 ]]; then
            log_warning "No governance resources found. Resources may have been deleted already or use different naming patterns."
        fi
    else
        log_info "DRY RUN: Would discover governance resources"
    fi
}

# Function to delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Find and delete governance-related functions
        local functions
        functions=$(gcloud functions list --regions="$REGION" --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*policy* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$functions" ]]; then
            for func in $functions; do
                log_info "Deleting Cloud Function: $func"
                if gcloud functions delete "$func" --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                    log_success "Deleted Cloud Function: $func"
                else
                    log_warning "Failed to delete Cloud Function: $func (may not exist)"
                fi
            done
        else
            log_warning "No governance Cloud Functions found"
        fi
    else
        log_info "DRY RUN: Would delete Cloud Functions"
    fi
}

# Function to delete Asset Inventory feeds
delete_asset_feeds() {
    log_info "Deleting Asset Inventory feeds..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Find and delete governance-related feeds
        local feeds
        feeds=$(gcloud asset feeds list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset*" 2>/dev/null || true)
        
        if [[ -n "$feeds" ]]; then
            for feed in $feeds; do
                log_info "Deleting Asset Inventory feed: $feed"
                if gcloud asset feeds delete "$feed" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                    log_success "Deleted Asset Inventory feed: $feed"
                else
                    log_warning "Failed to delete Asset Inventory feed: $feed (may not exist)"
                fi
            done
        else
            log_warning "No governance Asset Inventory feeds found"
        fi
    else
        log_info "DRY RUN: Would delete Asset Inventory feeds"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Find and delete governance-related subscriptions first
        local subscriptions
        subscriptions=$(gcloud pubsub subscriptions list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$subscriptions" ]]; then
            for sub in $subscriptions; do
                local sub_name
                sub_name=$(basename "$sub")
                log_info "Deleting Pub/Sub subscription: $sub_name"
                if gcloud pubsub subscriptions delete "$sub_name" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                    log_success "Deleted Pub/Sub subscription: $sub_name"
                else
                    log_warning "Failed to delete Pub/Sub subscription: $sub_name (may not exist)"
                fi
            done
        fi
        
        # Find and delete governance-related topics
        local topics
        topics=$(gcloud pubsub topics list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$topics" ]]; then
            for topic in $topics; do
                local topic_name
                topic_name=$(basename "$topic")
                log_info "Deleting Pub/Sub topic: $topic_name"
                if gcloud pubsub topics delete "$topic_name" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                    log_success "Deleted Pub/Sub topic: $topic_name"
                else
                    log_warning "Failed to delete Pub/Sub topic: $topic_name (may not exist)"
                fi
            done
        else
            log_warning "No governance Pub/Sub topics found"
        fi
    else
        log_info "DRY RUN: Would delete Pub/Sub resources"
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Find and delete governance-related service accounts
        local service_accounts
        service_accounts=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" --filter="email:*governance* OR email:*asset*" 2>/dev/null || true)
        
        if [[ -n "$service_accounts" ]]; then
            for sa in $service_accounts; do
                log_info "Deleting service account: $sa"
                
                # First, remove IAM policy bindings
                local roles=(
                    "roles/cloudasset.viewer"
                    "roles/iam.securityReviewer"
                    "roles/monitoring.metricWriter"
                    "roles/logging.logWriter"
                    "roles/pubsub.publisher"
                    "roles/pubsub.subscriber"
                )
                
                for role in "${roles[@]}"; do
                    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                        --member="serviceAccount:$sa" \
                        --role="$role" \
                        --quiet 2>/dev/null || true
                done
                
                # Delete the service account
                if gcloud iam service-accounts delete "$sa" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                    log_success "Deleted service account: $sa"
                else
                    log_warning "Failed to delete service account: $sa (may not exist)"
                fi
            done
        else
            log_warning "No governance service accounts found"
        fi
    else
        log_info "DRY RUN: Would delete service accounts"
    fi
}

# Function to delete test resources
delete_test_resources() {
    log_info "Deleting test resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Find and delete test VMs
        local test_vms
        test_vms=$(gcloud compute instances list --project="$PROJECT_ID" --format="value(name)" --filter="labels.governance-test=true OR name:*governance*" 2>/dev/null || true)
        
        if [[ -n "$test_vms" ]]; then
            for vm in $test_vms; do
                # Get the zone for this VM
                local vm_zone
                vm_zone=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$vm" --format="value(zone)" 2>/dev/null | head -1)
                
                if [[ -n "$vm_zone" ]]; then
                    log_info "Deleting test VM: $vm in zone: $vm_zone"
                    if gcloud compute instances delete "$vm" --zone="$vm_zone" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                        log_success "Deleted test VM: $vm"
                    else
                        log_warning "Failed to delete test VM: $vm (may not exist)"
                    fi
                fi
            done
        else
            log_warning "No governance test VMs found"
        fi
        
        # Clean up any temporary files
        rm -f /tmp/governance-test-vm-* 2>/dev/null || true
    else
        log_info "DRY RUN: Would delete test resources"
    fi
}

# Function to clean up Cloud Build artifacts
cleanup_build_artifacts() {
    log_info "Cleaning up Cloud Build artifacts..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Clean up any Cloud Build artifacts related to governance functions
        local builds
        builds=$(gcloud builds list --project="$PROJECT_ID" --filter="source.storageSource.object:*governance*" --format="value(id)" --limit=10 2>/dev/null || true)
        
        if [[ -n "$builds" ]]; then
            log_info "Found Cloud Build artifacts to clean up"
            # Note: We don't delete build history for audit purposes
            # But we can clean up associated Cloud Storage objects
        fi
        
        # Clean up any staging buckets
        local staging_buckets
        staging_buckets=$(gsutil ls -p "$PROJECT_ID" gs://staging.*governance* 2>/dev/null || true)
        
        if [[ -n "$staging_buckets" ]]; then
            for bucket in $staging_buckets; do
                log_info "Cleaning up staging bucket: $bucket"
                gsutil -m rm -r "$bucket" 2>/dev/null || true
            done
        fi
    else
        log_info "DRY RUN: Would clean up Cloud Build artifacts"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local cleanup_issues=()
        
        # Check for remaining Cloud Functions
        local remaining_functions
        remaining_functions=$(gcloud functions list --regions="$REGION" --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*policy* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$remaining_functions" ]]; then
            cleanup_issues+=("Cloud Functions still exist: $remaining_functions")
        fi
        
        # Check for remaining Asset Inventory feeds
        local remaining_feeds
        remaining_feeds=$(gcloud asset feeds list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset*" 2>/dev/null || true)
        
        if [[ -n "$remaining_feeds" ]]; then
            cleanup_issues+=("Asset Inventory feeds still exist: $remaining_feeds")
        fi
        
        # Check for remaining Pub/Sub topics
        local remaining_topics
        remaining_topics=$(gcloud pubsub topics list --project="$PROJECT_ID" --format="value(name)" --filter="name:*governance* OR name:*asset* OR name:*compliance*" 2>/dev/null || true)
        
        if [[ -n "$remaining_topics" ]]; then
            cleanup_issues+=("Pub/Sub topics still exist: $remaining_topics")
        fi
        
        # Check for remaining service accounts
        local remaining_sas
        remaining_sas=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" --filter="email:*governance* OR email:*asset*" 2>/dev/null || true)
        
        if [[ -n "$remaining_sas" ]]; then
            cleanup_issues+=("Service accounts still exist: $remaining_sas")
        fi
        
        if [[ ${#cleanup_issues[@]} -gt 0 ]]; then
            log_warning "Cleanup validation found issues:"
            for issue in "${cleanup_issues[@]}"; do
                log_warning "  - $issue"
            done
            log_warning "You may need to manually clean up these resources"
        else
            log_success "Cleanup validation successful - no governance resources found"
        fi
    else
        log_info "DRY RUN: Would validate cleanup"
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Cleanup Actions Performed:"
    echo "- Deleted Cloud Functions (asset analyzer, policy validator, compliance engine)"
    echo "- Deleted Asset Inventory feeds"
    echo "- Deleted Pub/Sub topics and subscriptions"
    echo "- Deleted service accounts and removed IAM bindings"
    echo "- Deleted test resources"
    echo "- Cleaned up Cloud Build artifacts"
    echo ""
    echo "Note: Some resources may take a few minutes to be fully removed"
    echo "API usage and billing will stop once all resources are deleted"
}

# Main cleanup function
main() {
    log_info "Starting Dynamic Resource Governance cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
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
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --dry-run       Run in dry-run mode (no resources deleted)"
                echo "  --force         Skip confirmation prompts"
                echo "  --project ID    Specify project ID"
                echo "  --region NAME   Specify region"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    confirm_deletion
    delete_functions
    delete_asset_feeds
    delete_pubsub_resources
    delete_service_accounts
    delete_test_resources
    cleanup_build_artifacts
    validate_cleanup
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Execute main function
main "$@"
#!/bin/bash

# Infrastructure Change Monitoring with Cloud Asset Inventory and Pub/Sub - Destroy Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../.deployment_config"
PROJECT_ID=""
REGION=""
ZONE=""
TOPIC_NAME=""
SUBSCRIPTION_NAME=""
FUNCTION_NAME=""
DATASET_NAME=""
FEED_NAME=""
RANDOM_SUFFIX=""
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Deployment configuration file not found at $CONFIG_FILE"
        log_error "Please ensure you have deployed the solution first, or manually set environment variables"
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [[ -z "$PROJECT_ID" || -z "$TOPIC_NAME" || -z "$FUNCTION_NAME" || -z "$DATASET_NAME" || -z "$FEED_NAME" ]]; then
        log_error "Invalid or incomplete deployment configuration"
        exit 1
    fi
    
    log_success "Loaded deployment configuration"
    log_info "Project: $PROJECT_ID"
    log_info "Topic: $TOPIC_NAME"
    log_info "Function: $FUNCTION_NAME"
    log_info "Dataset: $DATASET_NAME"
    log_info "Feed: $FEED_NAME"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project matches configuration
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null)
    if [[ "$current_project" != "$PROJECT_ID" ]]; then
        log_warning "Current project ($current_project) differs from deployment config ($PROJECT_ID)"
        log_info "Setting project to $PROJECT_ID"
        gcloud config set project "$PROJECT_ID"
    fi
    
    # Check required tools
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to show destruction warning
show_destruction_warning() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return
    fi
    
    echo
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️"
    echo
    echo "This will permanently delete the following resources:"
    echo "• Asset Feed: $FEED_NAME"
    echo "• Cloud Function: $FUNCTION_NAME"
    echo "• Pub/Sub Topic: $TOPIC_NAME"
    echo "• Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    echo "• BigQuery Dataset: $DATASET_NAME (including all tables and data)"
    echo "• Alert Policies: Critical Infrastructure Changes"
    echo "• IAM bindings for the function service account"
    echo
    echo "💰 This will stop all billing for these resources."
    echo "📊 All audit data in BigQuery will be permanently lost."
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Function to remove Asset Inventory feed
remove_asset_feed() {
    log_info "Removing Cloud Asset Inventory feed..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Asset feed: $FEED_NAME"
        return
    fi
    
    # Check if feed exists
    if gcloud asset feeds list --project="$PROJECT_ID" --format="value(name)" | grep -q "$FEED_NAME"; then
        gcloud asset feeds delete "$FEED_NAME" --project="$PROJECT_ID" --quiet
        log_success "Deleted Asset feed: $FEED_NAME"
    else
        log_warning "Asset feed $FEED_NAME not found or already deleted"
    fi
}

# Function to remove Cloud Function
remove_cloud_function() {
    log_info "Removing Cloud Function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: $FUNCTION_NAME"
        return
    fi
    
    # Get function service account before deletion
    local function_sa=""
    if gcloud functions describe "$FUNCTION_NAME" --project="$PROJECT_ID" --region="$REGION" &>/dev/null; then
        function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format="value(serviceAccountEmail)" 2>/dev/null || echo "")
        
        # Delete the function
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet
        log_success "Deleted Cloud Function: $FUNCTION_NAME"
        
        # Remove IAM bindings if service account was found
        if [[ -n "$function_sa" ]]; then
            log_info "Removing IAM bindings for service account: $function_sa"
            
            # Remove BigQuery permissions (ignore errors if binding doesn't exist)
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$function_sa" \
                --role="roles/bigquery.dataEditor" \
                --quiet 2>/dev/null || log_warning "BigQuery IAM binding may not exist"
            
            # Remove Monitoring permissions (ignore errors if binding doesn't exist)
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$function_sa" \
                --role="roles/monitoring.metricWriter" \
                --quiet 2>/dev/null || log_warning "Monitoring IAM binding may not exist"
            
            log_success "Removed IAM bindings for function service account"
        fi
    else
        log_warning "Cloud Function $FUNCTION_NAME not found or already deleted"
    fi
}

# Function to remove Pub/Sub resources
remove_pubsub_resources() {
    log_info "Removing Pub/Sub resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Pub/Sub subscription: $SUBSCRIPTION_NAME"
        log_info "[DRY RUN] Would delete Pub/Sub topic: $TOPIC_NAME"
        return
    fi
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" &>/dev/null; then
        gcloud pubsub subscriptions delete "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" --quiet
        log_success "Deleted Pub/Sub subscription: $SUBSCRIPTION_NAME"
    else
        log_warning "Pub/Sub subscription $SUBSCRIPTION_NAME not found or already deleted"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        gcloud pubsub topics delete "$TOPIC_NAME" --project="$PROJECT_ID" --quiet
        log_success "Deleted Pub/Sub topic: $TOPIC_NAME"
    else
        log_warning "Pub/Sub topic $TOPIC_NAME not found or already deleted"
    fi
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    log_info "Removing BigQuery dataset and all tables..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete BigQuery dataset: $DATASET_NAME"
        return
    fi
    
    # Check if dataset exists
    if bq ls -d "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        # Show tables that will be deleted
        log_info "Tables in dataset $DATASET_NAME:"
        bq ls "$PROJECT_ID:$DATASET_NAME" || log_warning "Could not list tables"
        
        # Delete dataset and all tables
        bq rm -r -f "$PROJECT_ID:$DATASET_NAME"
        log_success "Deleted BigQuery dataset: $DATASET_NAME"
    else
        log_warning "BigQuery dataset $DATASET_NAME not found or already deleted"
    fi
}

# Function to remove alert policies
remove_alert_policies() {
    log_info "Removing Cloud Monitoring alert policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete alert policies matching: Critical Infrastructure Changes"
        return
    fi
    
    # List and delete alert policies with our pattern
    local policy_ids
    policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName~'Critical Infrastructure Changes.*$RANDOM_SUFFIX'" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$policy_ids" ]]; then
        while IFS= read -r policy_id; do
            if [[ -n "$policy_id" ]]; then
                gcloud alpha monitoring policies delete "$policy_id" --project="$PROJECT_ID" --quiet
                log_success "Deleted alert policy: $policy_id"
            fi
        done <<< "$policy_ids"
    else
        log_warning "No matching alert policies found or already deleted"
    fi
}

# Function to clean up deployment configuration
cleanup_deployment_config() {
    log_info "Cleaning up deployment configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete configuration file: $CONFIG_FILE"
        return
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Deleted deployment configuration file"
    else
        log_warning "Deployment configuration file not found"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local errors=0
    
    # Check Asset feed
    if gcloud asset feeds list --project="$PROJECT_ID" --format="value(name)" | grep -q "$FEED_NAME" 2>/dev/null; then
        log_error "Asset feed $FEED_NAME still exists"
        ((errors++))
    fi
    
    # Check Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --project="$PROJECT_ID" --region="$REGION" &>/dev/null; then
        log_error "Cloud Function $FUNCTION_NAME still exists"
        ((errors++))
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_error "Pub/Sub topic $TOPIC_NAME still exists"
        ((errors++))
    fi
    
    # Check BigQuery dataset
    if bq ls -d "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        log_error "BigQuery dataset $DATASET_NAME still exists"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources successfully removed"
    else
        log_error "Some resources may not have been fully cleaned up"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "🧹 Infrastructure Change Monitoring cleanup completed!"
    echo
    echo "===== CLEANUP SUMMARY ====="
    echo "Project ID: $PROJECT_ID"
    echo "Resources removed:"
    echo "  ✅ Asset Feed: $FEED_NAME"
    echo "  ✅ Cloud Function: $FUNCTION_NAME"
    echo "  ✅ Pub/Sub Topic: $TOPIC_NAME"
    echo "  ✅ Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    echo "  ✅ BigQuery Dataset: $DATASET_NAME"
    echo "  ✅ Alert Policies"
    echo "  ✅ IAM Bindings"
    echo "  ✅ Configuration File"
    echo
    echo "💰 All billing for these resources has been stopped."
    echo "📊 All audit data has been permanently deleted."
    echo
    echo "To redeploy the solution, run: ./deploy.sh"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --config-file FILE        Path to deployment configuration file"
    echo "  --force                   Skip all confirmations and proceed with deletion"
    echo "  --dry-run                 Show what would be deleted without actually deleting"
    echo "  --skip-confirmation       Skip the initial warning confirmation"
    echo "  --help                    Show this help message"
    echo
    echo "Environment Variables:"
    echo "  DRY_RUN                   Set to 'true' for dry run mode"
    echo "  FORCE                     Set to 'true' to skip confirmations"
    echo "  SKIP_CONFIRMATION         Set to 'true' to skip the initial warning"
    echo
    echo "Examples:"
    echo "  ./destroy.sh                           # Interactive destruction with confirmations"
    echo "  ./destroy.sh --force                   # Force destruction without confirmations"
    echo "  ./destroy.sh --dry-run                 # Show what would be deleted"
    echo "  FORCE=true ./destroy.sh                # Environment variable force mode"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --force)
            FORCE="true"
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help)
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

# Apply force mode if set via environment
if [[ "$FORCE" == "true" ]]; then
    SKIP_CONFIRMATION="true"
fi

# Main execution
main() {
    log_info "Starting Infrastructure Change Monitoring cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    load_deployment_config
    check_prerequisites
    show_destruction_warning
    
    # Remove resources in reverse order of creation
    remove_asset_feed
    remove_alert_policies
    remove_cloud_function
    remove_pubsub_resources
    remove_bigquery_resources
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cleanup_deployment_config
        verify_cleanup
        display_cleanup_summary
    else
        log_info "Dry run completed - no resources were deleted"
    fi
}

# Execute main function
main "$@"
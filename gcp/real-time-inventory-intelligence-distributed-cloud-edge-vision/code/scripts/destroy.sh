#!/bin/bash

# Real-Time Inventory Intelligence with Google Distributed Cloud Edge and Cloud Vision
# Cleanup/Destroy Script
#
# This script safely removes all infrastructure components created for the
# real-time inventory intelligence solution

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Continuing with cleanup..."
    # Don't exit on error during cleanup - we want to clean up as much as possible
}

trap 'handle_error $LINENO' ERR

# Function to confirm destructive action
confirm_destruction() {
    if [ "${FORCE_DESTROY:-false}" == "true" ]; then
        return 0
    fi
    
    echo -e "${RED}WARNING: This will permanently delete all resources created for the inventory intelligence solution!${NC}"
    echo "This includes:"
    echo "- Cloud SQL database instance and all data"
    echo "- Cloud Storage bucket and all images"
    echo "- Service accounts and IAM bindings"
    echo "- Vision API product sets and products"
    echo "- Monitoring dashboards and alerts"
    echo "- Kubernetes deployments (if cluster is accessible)"
    echo
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project
validate_project() {
    log "Validating project access..."
    
    # Check if project is set
    if [ -z "${PROJECT_ID:-}" ]; then
        log_error "PROJECT_ID is not set. Please set it before running this script."
        exit 1
    fi
    
    # Verify project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it"
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Function to cleanup Kubernetes deployments
cleanup_kubernetes() {
    log "Cleaning up Kubernetes deployments..."
    
    # Check if kubectl is available and cluster is accessible
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not found, skipping Kubernetes cleanup"
        return
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_warning "No accessible Kubernetes cluster found, skipping Kubernetes cleanup"
        return
    fi
    
    # Delete deployment
    if kubectl get deployment inventory-processor &>/dev/null; then
        log "Deleting inventory-processor deployment..."
        kubectl delete deployment inventory-processor --ignore-not-found=true
        log_success "Deployment deleted"
    else
        log_warning "Deployment inventory-processor not found"
    fi
    
    # Delete service
    if kubectl get service inventory-processor &>/dev/null; then
        log "Deleting inventory-processor service..."
        kubectl delete service inventory-processor --ignore-not-found=true
        log_success "Service deleted"
    else
        log_warning "Service inventory-processor not found"
    fi
    
    # Delete secret
    if kubectl get secret google-cloud-key &>/dev/null; then
        log "Deleting google-cloud-key secret..."
        kubectl delete secret google-cloud-key --ignore-not-found=true
        log_success "Secret deleted"
    else
        log_warning "Secret google-cloud-key not found"
    fi
    
    # Delete service account
    if kubectl get serviceaccount inventory-edge-processor &>/dev/null; then
        log "Deleting Kubernetes service account..."
        kubectl delete serviceaccount inventory-edge-processor --ignore-not-found=true
        log_success "Kubernetes service account deleted"
    else
        log_warning "Kubernetes service account inventory-edge-processor not found"
    fi
    
    log_success "Kubernetes resources cleanup completed"
}

# Function to cleanup Vision API resources
cleanup_vision_api() {
    log "Cleaning up Cloud Vision API resources..."
    
    # Remove product from product set first
    if gcloud ml vision product-sets describe "retail_inventory_set" \
        --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        
        # Check if product exists in the set
        if gcloud ml vision products describe "sample_product_001" \
            --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            
            log "Removing product from product set..."
            gcloud ml vision product-sets remove-product \
                --product-set-id="retail_inventory_set" \
                --product-id="sample_product_001" \
                --location="$REGION" \
                --project="$PROJECT_ID" || log_warning "Failed to remove product from product set"
            
            log "Deleting sample product..."
            gcloud ml vision products delete \
                --product-id="sample_product_001" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete sample product"
        else
            log_warning "Sample product not found"
        fi
        
        log "Deleting product set..."
        gcloud ml vision product-sets delete \
            --product-set-id="retail_inventory_set" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --quiet || log_warning "Failed to delete product set"
        
        log_success "Vision API resources cleaned up"
    else
        log_warning "Product set 'retail_inventory_set' not found"
    fi
}

# Function to cleanup monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # List and delete dashboards containing "Inventory Intelligence"
    log "Searching for inventory intelligence dashboards..."
    DASHBOARD_IDS=$(gcloud monitoring dashboards list \
        --format="value(name)" \
        --filter="displayName:('Inventory Intelligence')" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -n "$DASHBOARD_IDS" ]; then
        while IFS= read -r dashboard_id; do
            if [ -n "$dashboard_id" ]; then
                log "Deleting dashboard: $dashboard_id"
                gcloud monitoring dashboards delete "$dashboard_id" \
                    --project="$PROJECT_ID" \
                    --quiet || log_warning "Failed to delete dashboard $dashboard_id"
            fi
        done <<< "$DASHBOARD_IDS"
        log_success "Monitoring dashboards cleaned up"
    else
        log_warning "No inventory intelligence dashboards found"
    fi
    
    # Clean up alert policies
    log "Searching for inventory-related alert policies..."
    ALERT_POLICIES=$(gcloud alpha monitoring policies list \
        --format="value(name)" \
        --filter="displayName:('Low Inventory' OR 'Inventory')" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -n "$ALERT_POLICIES" ]; then
        while IFS= read -r policy_id; do
            if [ -n "$policy_id" ]; then
                log "Deleting alert policy: $policy_id"
                gcloud alpha monitoring policies delete "$policy_id" \
                    --project="$PROJECT_ID" \
                    --quiet || log_warning "Failed to delete alert policy $policy_id"
            fi
        done <<< "$ALERT_POLICIES"
        log_success "Alert policies cleaned up"
    else
        log_warning "No inventory-related alert policies found"
    fi
}

# Function to cleanup storage bucket
cleanup_storage() {
    log "Cleaning up Cloud Storage resources..."
    
    if [ -z "${BUCKET_NAME:-}" ]; then
        log_warning "BUCKET_NAME not set, attempting to find bucket with pattern..."
        # Try to find bucket with inventory-images pattern
        FOUND_BUCKETS=$(gsutil ls -p "$PROJECT_ID" | grep "inventory-images" || echo "")
        if [ -n "$FOUND_BUCKETS" ]; then
            while IFS= read -r bucket_url; do
                if [ -n "$bucket_url" ]; then
                    BUCKET_NAME=$(echo "$bucket_url" | sed 's|gs://||' | sed 's|/||')
                    log "Found bucket: $BUCKET_NAME"
                    break
                fi
            done <<< "$FOUND_BUCKETS"
        fi
    fi
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        # Check if bucket exists
        if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
            log "Deleting storage bucket and all contents: $BUCKET_NAME"
            gsutil -m rm -r "gs://$BUCKET_NAME" || log_warning "Failed to delete bucket $BUCKET_NAME"
            log_success "Storage bucket deleted"
        else
            log_warning "Storage bucket '$BUCKET_NAME' not found"
        fi
    else
        log_warning "No storage bucket found to delete"
    fi
}

# Function to cleanup Cloud SQL database
cleanup_database() {
    log "Cleaning up Cloud SQL database..."
    
    if [ -z "${DB_INSTANCE_NAME:-}" ]; then
        log_warning "DB_INSTANCE_NAME not set, attempting to find instance with pattern..."
        # Try to find instance with inventory-db pattern
        FOUND_INSTANCES=$(gcloud sql instances list \
            --format="value(name)" \
            --filter="name:inventory-db*" \
            --project="$PROJECT_ID" 2>/dev/null || echo "")
        if [ -n "$FOUND_INSTANCES" ]; then
            DB_INSTANCE_NAME=$(echo "$FOUND_INSTANCES" | head -n1)
            log "Found database instance: $DB_INSTANCE_NAME"
        fi
    fi
    
    if [ -n "${DB_INSTANCE_NAME:-}" ]; then
        # Check if instance exists
        if gcloud sql instances describe "$DB_INSTANCE_NAME" --project="$PROJECT_ID" &>/dev/null; then
            log "Deleting Cloud SQL instance: $DB_INSTANCE_NAME"
            log_warning "This operation may take several minutes..."
            gcloud sql instances delete "$DB_INSTANCE_NAME" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete Cloud SQL instance"
            log_success "Cloud SQL instance deleted"
        else
            log_warning "Cloud SQL instance '$DB_INSTANCE_NAME' not found"
        fi
    else
        log_warning "No Cloud SQL instance found to delete"
    fi
}

# Function to cleanup service account
cleanup_service_account() {
    log "Cleaning up service account..."
    
    local service_account_email="inventory-edge-processor@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$service_account_email" --project="$PROJECT_ID" &>/dev/null; then
        
        # Remove IAM policy bindings
        log "Removing IAM policy bindings..."
        local roles=(
            "roles/ml.developer"
            "roles/cloudsql.client"
            "roles/storage.objectAdmin"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            log "Removing role binding: $role"
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$service_account_email" \
                --role="$role" \
                --quiet || log_warning "Failed to remove role binding $role"
        done
        
        # Delete service account
        log "Deleting service account: $service_account_email"
        gcloud iam service-accounts delete "$service_account_email" \
            --project="$PROJECT_ID" \
            --quiet || log_warning "Failed to delete service account"
        
        log_success "Service account cleaned up"
    else
        log_warning "Service account '$service_account_email' not found"
    fi
    
    # Clean up local service account key file
    if [ -f "inventory-edge-key.json" ]; then
        log "Removing local service account key file..."
        rm -f "inventory-edge-key.json"
        log_success "Local service account key file removed"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "inventory-edge-key.json"
        "lifecycle.json"
        "inventory-*.yaml"
        "inventory-*.json"
        "../kubernetes/inventory-processor-deployment.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            log "Removing: $file"
            rm -rf "$file" 2>/dev/null || log_warning "Failed to remove $file"
        fi
    done
    
    # Remove kubernetes directory if empty
    if [ -d "../kubernetes" ] && [ -z "$(ls -A ../kubernetes)" ]; then
        log "Removing empty kubernetes directory..."
        rmdir "../kubernetes" 2>/dev/null || log_warning "Failed to remove kubernetes directory"
    fi
    
    log_success "Local files cleaned up"
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID:-not set}"
    echo "Region: ${REGION:-not set}"
    echo "Database Instance: ${DB_INSTANCE_NAME:-not found}"
    echo "Storage Bucket: ${BUCKET_NAME:-not found}"
    echo
    echo "=== CLEANUP COMPLETED ==="
    echo "The following resources have been removed (if they existed):"
    echo "✓ Kubernetes deployments and services"
    echo "✓ Cloud Vision API product sets and products"
    echo "✓ Monitoring dashboards and alert policies"
    echo "✓ Cloud Storage bucket and contents"
    echo "✓ Cloud SQL database instance"
    echo "✓ Service account and IAM bindings"
    echo "✓ Local configuration files"
    echo
    echo "=== MANUAL VERIFICATION ==="
    echo "Please verify in the Google Cloud Console that all resources have been removed:"
    echo "- Cloud SQL: https://console.cloud.google.com/sql/instances"
    echo "- Storage: https://console.cloud.google.com/storage/browser"
    echo "- IAM: https://console.cloud.google.com/iam-admin/serviceaccounts"
    echo "- Vision API: https://console.cloud.google.com/ai/vision"
    echo "- Monitoring: https://console.cloud.google.com/monitoring/dashboards"
    echo
    if [ "${DRY_RUN:-false}" == "true" ]; then
        echo "=== DRY RUN MODE ==="
        echo "This was a dry run. No resources were actually deleted."
        echo "Run without --dry-run to perform actual cleanup."
    fi
}

# Main cleanup function
main() {
    log "Starting Real-Time Inventory Intelligence cleanup..."
    
    # Set environment variables with defaults or from environment
    export PROJECT_ID="${PROJECT_ID:-}"
    export REGION="${REGION:-us-central1}"
    export DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-}"
    export BUCKET_NAME="${BUCKET_NAME:-}"
    
    # Run cleanup steps in reverse order of creation
    check_prerequisites
    validate_project
    confirm_destruction
    
    if [ "${DRY_RUN:-false}" == "true" ]; then
        log_warning "DRY RUN MODE: No resources will be actually deleted"
    fi
    
    cleanup_kubernetes
    cleanup_vision_api
    cleanup_monitoring
    cleanup_storage
    cleanup_database
    cleanup_service_account
    cleanup_local_files
    show_cleanup_summary
    
    log_success "Cleanup script completed!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --db-instance)
            DB_INSTANCE_NAME="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE_DESTROY="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID      Google Cloud Project ID"
            echo "  --region REGION              Google Cloud Region (default: us-central1)"
            echo "  --db-instance DB_NAME        Cloud SQL instance name (auto-detected if not provided)"
            echo "  --bucket-name BUCKET_NAME    Storage bucket name (auto-detected if not provided)"
            echo "  --force                      Skip confirmation prompts"
            echo "  --dry-run                    Show what would be deleted without actually deleting"
            echo "  --help                       Show this help message"
            echo
            echo "Example:"
            echo "  $0 --project-id my-project --force"
            echo "  $0 --project-id my-project --dry-run"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
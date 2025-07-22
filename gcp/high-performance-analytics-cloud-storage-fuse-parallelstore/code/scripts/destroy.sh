#!/bin/bash

# High-Performance Analytics with Cloud Storage FUSE and Parallelstore - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Default values
FORCE=false
DRY_RUN=false
KEEP_PROJECT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force         Skip confirmation prompts"
            echo "  --dry-run       Show what would be deleted without executing"
            echo "  --keep-project  Keep the GCP project, only delete resources within it"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

log "Starting High-Performance Analytics Infrastructure Cleanup"

# Check if deployment config exists
if [ ! -f ".deployment_config" ]; then
    log_error "Deployment configuration file (.deployment_config) not found."
    log_error "Cannot determine which resources to clean up."
    
    if [ "$FORCE" = false ]; then
        read -p "Do you want to proceed with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        
        # Manual cleanup mode
        log_warning "Entering manual cleanup mode. You'll need to provide resource names."
        
        read -p "Enter Project ID: " PROJECT_ID
        read -p "Enter Region (default: us-central1): " REGION
        REGION=${REGION:-us-central1}
        read -p "Enter Zone (default: us-central1-a): " ZONE
        ZONE=${ZONE:-us-central1-a}
        
        # Try to infer resource names (this is best effort)
        BUCKET_NAME=""
        CLUSTER_NAME=""
        PARALLELSTORE_NAME=""
        VM_NAME=""
    else
        log_error "Force mode requires deployment configuration. Exiting."
        exit 1
    fi
else
    # Load deployment configuration
    source .deployment_config
    
    log "Loaded deployment configuration:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    log "  Bucket: $BUCKET_NAME"
    log "  Cluster: $CLUSTER_NAME"
    log "  Parallelstore: $PARALLELSTORE_NAME"
    log "  VM: $VM_NAME"
fi

# Verify gcloud is configured for the correct project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    log_warning "Current gcloud project ($CURRENT_PROJECT) doesn't match deployment project ($PROJECT_ID)"
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        read -p "Set gcloud project to $PROJECT_ID? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gcloud config set project $PROJECT_ID
        else
            log_error "Cannot proceed without correct project configuration"
            exit 1
        fi
    fi
fi

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No resources will be deleted"
    log "Would delete the following resources:"
    [ -n "${CLUSTER_NAME:-}" ] && log "  - Dataproc cluster: $CLUSTER_NAME"
    [ -n "${VM_NAME:-}" ] && log "  - Compute Engine VM: $VM_NAME"
    [ -n "${PARALLELSTORE_NAME:-}" ] && log "  - Parallelstore instance: $PARALLELSTORE_NAME"
    [ -n "${BUCKET_NAME:-}" ] && log "  - Cloud Storage bucket: $BUCKET_NAME"
    log "  - BigQuery dataset: hpc_analytics"
    log "  - Monitoring policies and metrics"
    if [ "$KEEP_PROJECT" = false ]; then
        log "  - GCP Project: $PROJECT_ID"
    fi
    exit 0
fi

# Cost estimation
log_warning "COST SAVINGS:"
log_warning "  Parallelstore: ~\$1,200-2,400/month (\$40-80/day)"
log_warning "  Dataproc cluster: ~\$200-400/month (\$7-13/day)"
log_warning "  Compute Engine VM: ~\$100-200/month (\$3-7/day)"
log_warning "  Total monthly savings: \$1,520-3,050 (\$50-100/day)"

# Safety confirmation
if [ "$FORCE" = false ]; then
    log_warning "⚠️  WARNING: This will permanently delete all resources created by the deployment!"
    log_warning "⚠️  This action cannot be undone!"
    echo ""
    
    if [ "$KEEP_PROJECT" = false ]; then
        log_warning "⚠️  The entire GCP project '$PROJECT_ID' will be deleted!"
        log_warning "⚠️  All data and resources in this project will be lost!"
        echo ""
        
        read -p "Are you absolutely sure you want to DELETE the entire project? Type 'DELETE PROJECT' to confirm: " CONFIRMATION
        if [ "$CONFIRMATION" != "DELETE PROJECT" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    else
        read -p "Are you sure you want to delete all analytics resources? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
fi

log "Starting resource cleanup..."

# Set project context
if [ -n "${PROJECT_ID:-}" ]; then
    gcloud config set project $PROJECT_ID 2>/dev/null || log_warning "Could not set project $PROJECT_ID"
    gcloud config set compute/region ${REGION:-us-central1} 2>/dev/null || true
    gcloud config set compute/zone ${ZONE:-us-central1-a} 2>/dev/null || true
fi

# Function to safely delete resources with error handling
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    if [ -z "$resource_name" ]; then
        log_warning "Skipping $resource_type deletion - name not provided"
        return 0
    fi
    
    log "Deleting $resource_type: $resource_name"
    
    if eval "$delete_command" 2>/dev/null; then
        log_success "$resource_type deleted: $resource_name"
    else
        log_warning "Failed to delete $resource_type: $resource_name (may not exist or already deleted)"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local timeout="${3:-300}"  # 5 minutes default
    
    log "Waiting for $resource_name deletion to complete..."
    local elapsed=0
    
    while eval "$check_command" 2>/dev/null && [ $elapsed -lt $timeout ]; do
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            log "Still waiting for $resource_name deletion... (${elapsed}s elapsed)"
        fi
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_warning "Timeout waiting for $resource_name deletion to complete"
    else
        log_success "$resource_name deletion completed"
    fi
}

# If keeping project, delete resources individually
if [ "$KEEP_PROJECT" = true ]; then
    log "Deleting resources within project (keeping project)..."
    
    # Step 1: Delete Dataproc cluster (this should be first as it may have dependencies)
    if [ -n "${CLUSTER_NAME:-}" ]; then
        safe_delete "Dataproc cluster" "$CLUSTER_NAME" \
            "gcloud dataproc clusters delete $CLUSTER_NAME --zone=${ZONE:-us-central1-a} --quiet"
    else
        # Try to find and delete any Dataproc clusters
        log "Searching for Dataproc clusters to delete..."
        CLUSTERS=$(gcloud dataproc clusters list --format="value(clusterName)" --filter="zone:(${ZONE:-us-central1-a})" 2>/dev/null || echo "")
        for cluster in $CLUSTERS; do
            if [[ $cluster == *"dataproc-hpc"* ]] || [[ $cluster == *"hpc"* ]]; then
                safe_delete "Dataproc cluster" "$cluster" \
                    "gcloud dataproc clusters delete $cluster --zone=${ZONE:-us-central1-a} --quiet"
            fi
        done
    fi
    
    # Step 2: Delete Compute Engine VM
    if [ -n "${VM_NAME:-}" ]; then
        safe_delete "Compute Engine VM" "$VM_NAME" \
            "gcloud compute instances delete $VM_NAME --zone=${ZONE:-us-central1-a} --quiet"
    else
        # Try to find and delete analytics VMs
        log "Searching for analytics VMs to delete..."
        VMS=$(gcloud compute instances list --format="value(name)" --filter="zone:(${ZONE:-us-central1-a})" 2>/dev/null || echo "")
        for vm in $VMS; do
            if [[ $vm == *"analytics-vm"* ]]; then
                safe_delete "Compute Engine VM" "$vm" \
                    "gcloud compute instances delete $vm --zone=${ZONE:-us-central1-a} --quiet"
            fi
        done
    fi
    
    # Step 3: Delete Parallelstore instance (this takes time)
    if [ -n "${PARALLELSTORE_NAME:-}" ]; then
        safe_delete "Parallelstore instance" "$PARALLELSTORE_NAME" \
            "gcloud parallelstore instances delete $PARALLELSTORE_NAME --location=${ZONE:-us-central1-a} --quiet"
        
        # Wait for Parallelstore deletion to complete
        wait_for_deletion \
            "gcloud parallelstore instances describe $PARALLELSTORE_NAME --location=${ZONE:-us-central1-a}" \
            "$PARALLELSTORE_NAME" \
            600  # 10 minutes timeout
    else
        # Try to find and delete Parallelstore instances
        log "Searching for Parallelstore instances to delete..."
        STORES=$(gcloud parallelstore instances list --format="value(name)" 2>/dev/null || echo "")
        for store in $STORES; do
            if [[ $store == *"hpc-store"* ]] || [[ $store == *"parallelstore"* ]]; then
                store_name=$(basename "$store")
                store_location=$(echo "$store" | cut -d'/' -f4)
                safe_delete "Parallelstore instance" "$store_name" \
                    "gcloud parallelstore instances delete $store_name --location=$store_location --quiet"
            fi
        done
    fi
    
    # Step 4: Delete BigQuery dataset
    safe_delete "BigQuery dataset" "hpc_analytics" \
        "bq rm -r -f $PROJECT_ID:hpc_analytics"
    
    # Step 5: Delete Cloud Storage bucket
    if [ -n "${BUCKET_NAME:-}" ]; then
        safe_delete "Cloud Storage bucket" "$BUCKET_NAME" \
            "gcloud storage rm -r gs://$BUCKET_NAME"
    else
        # Try to find and delete analytics buckets
        log "Searching for analytics buckets to delete..."
        BUCKETS=$(gcloud storage ls 2>/dev/null | grep -E "(analytics-data|hpc)" || echo "")
        for bucket in $BUCKETS; do
            bucket_name=$(echo "$bucket" | sed 's|gs://||' | sed 's|/||')
            safe_delete "Cloud Storage bucket" "$bucket_name" \
                "gcloud storage rm -r gs://$bucket_name"
        done
    fi
    
    # Step 6: Delete monitoring policies and metrics
    log "Cleaning up monitoring policies and custom metrics..."
    
    # Delete monitoring policies
    POLICIES=$(gcloud monitoring policies list --format="value(name)" --filter="displayName:'Parallelstore Performance Alert'" 2>/dev/null || echo "")
    for policy in $POLICIES; do
        safe_delete "Monitoring policy" "$(basename $policy)" \
            "gcloud monitoring policies delete $policy --quiet"
    done
    
    # Delete custom metrics
    safe_delete "Custom metric" "parallelstore_throughput" \
        "gcloud logging metrics delete parallelstore_throughput --quiet"
    
    log_success "Resource cleanup completed within project $PROJECT_ID"
    
else
    # Delete entire project
    log "Deleting entire GCP project: $PROJECT_ID"
    
    if gcloud projects delete $PROJECT_ID --quiet 2>/dev/null; then
        log_success "Project deletion initiated: $PROJECT_ID"
        log "Note: Project deletion may take several minutes to complete"
        log "All resources within the project will be automatically deleted"
    else
        log_error "Failed to delete project: $PROJECT_ID"
        log_error "You may need to delete it manually from the GCP Console"
        exit 1
    fi
fi

# Clean up local files
log "Cleaning up local files..."

# Remove deployment configuration
if [ -f ".deployment_config" ]; then
    rm -f .deployment_config
    log_success "Removed deployment configuration file"
fi

# Remove any temporary files that might have been left behind
rm -f lifecycle.json vm_startup_script.sh analytics_pipeline.py external_table_def.json monitoring_policy.json
rm -rf sample_data/ 2>/dev/null || true

log_success "Local cleanup completed"

# Final summary
log ""
log_success "🎉 High-Performance Analytics Infrastructure Cleanup Complete!"
log ""

if [ "$KEEP_PROJECT" = true ]; then
    log "Cleanup Summary:"
    log "  ✅ Dataproc cluster deleted"
    log "  ✅ Compute Engine VM deleted"
    log "  ✅ Parallelstore instance deleted"
    log "  ✅ BigQuery dataset deleted"
    log "  ✅ Cloud Storage bucket deleted"
    log "  ✅ Monitoring policies deleted"
    log "  ✅ Local files cleaned up"
    log "  📁 Project preserved: $PROJECT_ID"
    log ""
    log "💰 Estimated monthly cost savings: \$1,520-3,050"
    log "💰 Estimated daily cost savings: \$50-100"
else
    log "Cleanup Summary:"
    log "  ✅ Entire project deleted: $PROJECT_ID"
    log "  ✅ All resources automatically removed"
    log "  ✅ Local files cleaned up"
    log ""
    log "💰 All costs eliminated immediately"
fi

log ""
log "Thank you for using the High-Performance Analytics recipe!"
log "For more cloud recipes, visit: https://github.com/googlecloudplatform/cloud-recipes"
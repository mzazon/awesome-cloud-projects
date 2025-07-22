#!/bin/bash
set -euo pipefail

# High-Performance Data Science Workflows with Cloud NetApp Volumes and Vertex AI Workbench
# Cleanup/Destroy Script for GCP Recipe
# This script removes all infrastructure created by the deployment script

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

# Error handling for non-critical operations
handle_error() {
    log_warning "Non-critical operation failed at line $1, continuing cleanup..."
}

trap 'handle_error $LINENO' ERR

# Load deployment state if available
STATE_FILE="${HOME}/.ml-netapp-deployment-state"
if [[ -f "$STATE_FILE" ]]; then
    log_info "Loading deployment state from $STATE_FILE"
    source "$STATE_FILE"
else
    log_warning "Deployment state file not found. Using environment variables or defaults."
fi

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
NETWORK_NAME="${NETWORK_NAME:-netapp-ml-network}"
STORAGE_POOL_NAME="${STORAGE_POOL_NAME:-}"
VOLUME_NAME="${VOLUME_NAME:-}"
WORKBENCH_NAME="${WORKBENCH_NAME:-}"
BUCKET_NAME="${BUCKET_NAME:-}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Display banner
cat << 'EOF'
============================================================
  High-Performance Data Science Workflows Cleanup
  GCP Recipe: NetApp Volumes + Vertex AI Workbench
============================================================
EOF

log_info "Starting cleanup with the following configuration:"
echo "  Project ID:      ${PROJECT_ID:-<not set>}"
echo "  Region:          ${REGION}"
echo "  Zone:            ${ZONE}"
echo "  Network:         ${NETWORK_NAME}"
echo "  Storage Pool:    ${STORAGE_POOL_NAME:-<not set>}"
echo "  Volume:          ${VOLUME_NAME:-<not set>}"
echo "  Workbench:       ${WORKBENCH_NAME:-<not set>}"
echo "  Bucket:          ${BUCKET_NAME:-<not set>}"
echo ""

# Dry run check
if [[ "${DRY_RUN}" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be deleted"
    exit 0
fi

# Prerequisites check
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
    exit 1
fi

# Check authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    log_error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
    exit 1
fi

log_success "Prerequisites check completed"

# Set gcloud configuration if PROJECT_ID is available
if [[ -n "$PROJECT_ID" ]]; then
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
else
    log_warning "PROJECT_ID not set. Using current gcloud project configuration."
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project ID found. Set PROJECT_ID or configure gcloud project."
        exit 1
    fi
fi

# Warning and confirmation
log_warning "This will DELETE ALL resources created by the deployment script!"
log_warning "This action is IRREVERSIBLE and will result in DATA LOSS!"

if [[ "${FORCE_DELETE}" != "true" ]]; then
    echo ""
    echo "Resources to be deleted:"
    [[ -n "$WORKBENCH_NAME" ]] && echo "  - Vertex AI Workbench: $WORKBENCH_NAME"
    [[ -n "$VOLUME_NAME" ]] && echo "  - NetApp Volume: $VOLUME_NAME"
    [[ -n "$STORAGE_POOL_NAME" ]] && echo "  - NetApp Storage Pool: $STORAGE_POOL_NAME"
    [[ -n "$BUCKET_NAME" ]] && echo "  - Cloud Storage Bucket: $BUCKET_NAME (with all contents)"
    echo "  - VPC Network: $NETWORK_NAME"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "This will delete ALL DATA in these resources. Type 'DELETE' to proceed: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
fi

log_info "Starting resource cleanup..."

# Function to check if resource exists and delete it
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    local check_command="$4"
    
    if [[ -z "$resource_name" ]]; then
        log_warning "No $resource_type name provided, skipping"
        return 0
    fi
    
    log_info "Checking $resource_type: $resource_name"
    
    # Check if resource exists
    if eval "$check_command" &>/dev/null; then
        log_info "Deleting $resource_type: $resource_name"
        if eval "$delete_command" &>/dev/null; then
            log_success "$resource_type deleted: $resource_name"
        else
            log_error "Failed to delete $resource_type: $resource_name"
            return 1
        fi
    else
        log_info "$resource_type not found: $resource_name"
    fi
}

# Step 1: Delete Vertex AI Workbench Instance
if [[ -n "$WORKBENCH_NAME" ]]; then
    log_info "Deleting Vertex AI Workbench instance..."
    
    # Check if instance exists and get its state
    if gcloud notebooks instances describe "$WORKBENCH_NAME" --location="$ZONE" --quiet &>/dev/null; then
        instance_state=$(gcloud notebooks instances describe "$WORKBENCH_NAME" \
            --location="$ZONE" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        log_info "Workbench instance state: $instance_state"
        
        # Stop instance if it's running
        if [[ "$instance_state" == "ACTIVE" ]]; then
            log_info "Stopping Workbench instance before deletion..."
            gcloud notebooks instances stop "$WORKBENCH_NAME" \
                --location="$ZONE" \
                --quiet || log_warning "Failed to stop Workbench instance"
            
            # Wait for instance to stop
            timeout=300  # 5 minutes
            elapsed=0
            while [[ $elapsed -lt $timeout ]]; do
                state=$(gcloud notebooks instances describe "$WORKBENCH_NAME" \
                    --location="$ZONE" \
                    --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
                
                if [[ "$state" != "ACTIVE" ]]; then
                    break
                fi
                
                sleep 10
                elapsed=$((elapsed + 10))
                log_info "Waiting for instance to stop... ($elapsed/${timeout}s)"
            done
        fi
        
        # Delete the instance
        gcloud notebooks instances delete "$WORKBENCH_NAME" \
            --location="$ZONE" \
            --quiet || log_error "Failed to delete Workbench instance"
        
        log_success "Vertex AI Workbench instance deletion initiated"
    else
        log_info "Workbench instance not found: $WORKBENCH_NAME"
    fi
else
    log_warning "No Workbench instance name provided, skipping"
fi

# Step 2: Delete Cloud Storage Bucket
if [[ -n "$BUCKET_NAME" ]]; then
    log_info "Deleting Cloud Storage bucket and all contents..."
    
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        # Remove all objects first, then delete bucket
        gsutil -m rm -r "gs://$BUCKET_NAME" || log_error "Failed to delete Cloud Storage bucket"
        log_success "Cloud Storage bucket deleted: $BUCKET_NAME"
    else
        log_info "Cloud Storage bucket not found: $BUCKET_NAME"
    fi
else
    log_warning "No bucket name provided, skipping"
fi

# Step 3: Delete NetApp Volume
if [[ -n "$VOLUME_NAME" ]]; then
    log_info "Deleting NetApp Volume..."
    
    if gcloud netapp volumes describe "$VOLUME_NAME" --location="$REGION" --quiet &>/dev/null; then
        gcloud netapp volumes delete "$VOLUME_NAME" \
            --location="$REGION" \
            --quiet || log_error "Failed to delete NetApp volume"
        
        # Wait for volume deletion to complete
        log_info "Waiting for volume deletion to complete..."
        timeout=300  # 5 minutes
        elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if ! gcloud netapp volumes describe "$VOLUME_NAME" --location="$REGION" --quiet &>/dev/null; then
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            log_info "Volume deletion in progress... ($elapsed/${timeout}s)"
        done
        
        log_success "NetApp volume deleted: $VOLUME_NAME"
    else
        log_info "NetApp volume not found: $VOLUME_NAME"
    fi
else
    log_warning "No volume name provided, skipping"
fi

# Step 4: Delete NetApp Storage Pool
if [[ -n "$STORAGE_POOL_NAME" ]]; then
    log_info "Deleting NetApp Storage Pool..."
    
    if gcloud netapp storage-pools describe "$STORAGE_POOL_NAME" --location="$REGION" --quiet &>/dev/null; then
        gcloud netapp storage-pools delete "$STORAGE_POOL_NAME" \
            --location="$REGION" \
            --quiet || log_error "Failed to delete NetApp storage pool"
        
        # Wait for storage pool deletion to complete
        log_info "Waiting for storage pool deletion to complete..."
        timeout=300  # 5 minutes
        elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if ! gcloud netapp storage-pools describe "$STORAGE_POOL_NAME" --location="$REGION" --quiet &>/dev/null; then
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            log_info "Storage pool deletion in progress... ($elapsed/${timeout}s)"
        done
        
        log_success "NetApp storage pool deleted: $STORAGE_POOL_NAME"
    else
        log_info "NetApp storage pool not found: $STORAGE_POOL_NAME"
    fi
else
    log_warning "No storage pool name provided, skipping"
fi

# Step 5: Delete VPC Network and Subnet
log_info "Deleting VPC network and subnet..."

# Delete subnet first
if gcloud compute networks subnets describe "$NETWORK_NAME-subnet" --region="$REGION" --quiet &>/dev/null; then
    gcloud compute networks subnets delete "$NETWORK_NAME-subnet" \
        --region="$REGION" \
        --quiet || log_error "Failed to delete subnet"
    log_success "Subnet deleted: $NETWORK_NAME-subnet"
else
    log_info "Subnet not found: $NETWORK_NAME-subnet"
fi

# Delete network
if gcloud compute networks describe "$NETWORK_NAME" --quiet &>/dev/null; then
    gcloud compute networks delete "$NETWORK_NAME" \
        --quiet || log_error "Failed to delete VPC network"
    log_success "VPC network deleted: $NETWORK_NAME"
else
    log_info "VPC network not found: $NETWORK_NAME"
fi

# Step 6: Clean up local state file
if [[ -f "$STATE_FILE" ]]; then
    log_info "Removing deployment state file..."
    rm "$STATE_FILE" || log_warning "Failed to remove state file"
    log_success "Deployment state file removed"
fi

# Step 7: Optional cleanup of environment variables
log_info "Cleaning up environment variables..."
unset PROJECT_ID REGION ZONE NETWORK_NAME STORAGE_POOL_NAME 2>/dev/null || true
unset VOLUME_NAME WORKBENCH_NAME BUCKET_NAME 2>/dev/null || true

# Display cleanup summary
cat << EOF

============================================================
              CLEANUP COMPLETED SUCCESSFULLY
============================================================

Deleted Resources:
  ✅ Vertex AI Workbench Instance
  ✅ Cloud NetApp Volume
  ✅ Cloud NetApp Storage Pool
  ✅ Cloud Storage Bucket (with all contents)
  ✅ VPC Network and Subnet
  ✅ Deployment state file

Notes:
  - All data stored in the NetApp volumes has been permanently deleted
  - All files in the Cloud Storage bucket have been permanently deleted
  - Any running notebooks or processes have been terminated
  - Network resources have been removed
  
  If you need to recreate this environment, run the deploy.sh script again.

============================================================
EOF

log_success "High-Performance Data Science Workflows cleanup completed successfully!"

# Final verification
log_info "Performing final verification..."

errors=0

# Check if any resources still exist
[[ -n "$WORKBENCH_NAME" ]] && gcloud notebooks instances describe "$WORKBENCH_NAME" --location="$ZONE" --quiet &>/dev/null && {
    log_warning "Workbench instance still exists: $WORKBENCH_NAME"
    ((errors++))
}

[[ -n "$VOLUME_NAME" ]] && gcloud netapp volumes describe "$VOLUME_NAME" --location="$REGION" --quiet &>/dev/null && {
    log_warning "NetApp volume still exists: $VOLUME_NAME"
    ((errors++))
}

[[ -n "$STORAGE_POOL_NAME" ]] && gcloud netapp storage-pools describe "$STORAGE_POOL_NAME" --location="$REGION" --quiet &>/dev/null && {
    log_warning "NetApp storage pool still exists: $STORAGE_POOL_NAME"
    ((errors++))
}

[[ -n "$BUCKET_NAME" ]] && gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null && {
    log_warning "Cloud Storage bucket still exists: $BUCKET_NAME"
    ((errors++))
}

gcloud compute networks describe "$NETWORK_NAME" --quiet &>/dev/null && {
    log_warning "VPC network still exists: $NETWORK_NAME"
    ((errors++))
}

if [[ $errors -eq 0 ]]; then
    log_success "All resources have been successfully deleted"
else
    log_warning "Some resources may still exist ($errors warnings). Check the Google Cloud Console."
fi
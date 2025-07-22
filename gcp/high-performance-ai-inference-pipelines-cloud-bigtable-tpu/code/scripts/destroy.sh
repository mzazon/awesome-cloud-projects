#!/bin/bash

# High-Performance AI Inference Pipeline Cleanup Script
# This script safely removes all resources created by the deployment script
# to prevent ongoing charges and clean up the GCP environment

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to safely delete resources with confirmation
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    log "Checking if $resource_type '$resource_name' exists..."
    if eval "$delete_command --dry-run" &>/dev/null || eval "echo 'Resource exists check'"; then
        log "Deleting $resource_type: $resource_name"
        if eval "$delete_command"; then
            success "$resource_type '$resource_name' deleted successfully"
        else
            warning "Failed to delete $resource_type '$resource_name' or it may not exist"
        fi
    else
        warning "$resource_type '$resource_name' does not exist or already deleted"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_attempts=20
    local attempt=0
    
    log "Waiting for $resource_name to be fully deleted..."
    while [ $attempt -lt $max_attempts ]; do
        if ! eval "$check_command" &>/dev/null; then
            success "$resource_name has been fully deleted"
            return 0
        fi
        sleep 15
        attempt=$((attempt + 1))
        log "Waiting for deletion... (attempt $attempt/$max_attempts)"
    done
    
    warning "$resource_name may still exist. Please check manually."
    return 1
}

# Banner
echo -e "${RED}"
echo "======================================================================"
echo "  High-Performance AI Inference Pipeline Cleanup"
echo "  ⚠️  WARNING: This will delete ALL resources created by deploy.sh ⚠️"
echo "======================================================================"
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error "No active gcloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

success "Prerequisites check passed"

# Environment configuration
log "Reading environment variables..."

# Try to get configuration from environment or use defaults
export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo 'us-central1')}"
export ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo 'us-central1-a')}"

# Set resource names (try environment variables first, then defaults)
export BIGTABLE_INSTANCE_ID="${BIGTABLE_INSTANCE_ID:-feature-store-bt}"
export TPU_ENDPOINT_NAME="${TPU_ENDPOINT_NAME:-high-perf-inference}"

# For resources with random suffixes, we'll need to search for them
if [ -z "${BUCKET_NAME:-}" ]; then
    # Try to find bucket with our pattern
    BUCKET_NAME=$(gsutil ls -p ${PROJECT_ID} | grep "gs://ai-inference-models-" | head -1 | sed 's|gs://||' | sed 's|/||')
fi

if [ -z "${REDIS_INSTANCE_ID:-}" ]; then
    # Try to find Redis instance with our pattern
    REDIS_INSTANCE_ID=$(gcloud redis instances list --region=${REGION} --format="value(name)" | grep "feature-cache-" | head -1 | sed 's|.*instances/||')
fi

# Display configuration
log "Cleanup configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Bigtable Instance: ${BIGTABLE_INSTANCE_ID}"
echo "  Storage Bucket: ${BUCKET_NAME:-<not found>}"
echo "  Redis Instance: ${REDIS_INSTANCE_ID:-<not found>}"
echo "  TPU Endpoint: ${TPU_ENDPOINT_NAME}"

# Final confirmation
echo
echo -e "${RED}⚠️  DANGER ZONE ⚠️${NC}"
echo "This operation will permanently delete all resources and cannot be undone."
echo "Make sure you have backed up any important data before proceeding."
echo
read -p "Are you absolutely sure you want to delete all resources? Type 'DELETE' to confirm: " -r
if [[ "$REPLY" != "DELETE" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo
read -p "Last chance! Type 'YES' to proceed with deletion: " -r
if [[ "$REPLY" != "YES" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

# Start cleanup process
log "Starting cleanup process..."

# 1. Delete Cloud Function
log "Step 1: Deleting Cloud Function..."
if gcloud functions describe inference-pipeline --region=${REGION} &> /dev/null; then
    gcloud functions delete inference-pipeline --region=${REGION} --quiet
    success "Cloud Function deleted"
else
    warning "Cloud Function 'inference-pipeline' not found"
fi

# 2. Delete Vertex AI endpoint and model
log "Step 2: Deleting Vertex AI resources..."

# Get endpoint ID
ENDPOINT_ID=$(gcloud ai endpoints list --region=${REGION} \
    --filter="displayName:${TPU_ENDPOINT_NAME}" \
    --format="value(name)" | head -1)

if [ -n "$ENDPOINT_ID" ]; then
    # Undeploy model from endpoint first
    log "Undeploying model from endpoint..."
    DEPLOYED_MODEL_ID=$(gcloud ai endpoints describe ${ENDPOINT_ID} \
        --region=${REGION} --format="value(deployedModels[0].id)" 2>/dev/null || echo "")
    
    if [ -n "$DEPLOYED_MODEL_ID" ]; then
        gcloud ai endpoints undeploy-model ${ENDPOINT_ID} \
            --region=${REGION} \
            --deployed-model-id=${DEPLOYED_MODEL_ID} \
            --quiet
        success "Model undeployed from endpoint"
        
        # Wait for undeployment to complete
        wait_for_deletion "gcloud ai endpoints describe ${ENDPOINT_ID} --region=${REGION} --format='value(deployedModels[0].id)' | grep -q ." "model deployment"
    fi
    
    # Delete endpoint
    log "Deleting Vertex AI endpoint..."
    gcloud ai endpoints delete ${ENDPOINT_ID} --region=${REGION} --quiet
    success "Vertex AI endpoint deleted"
else
    warning "Vertex AI endpoint '${TPU_ENDPOINT_NAME}' not found"
fi

# Delete model
log "Deleting Vertex AI model..."
MODEL_ID=$(gcloud ai models list --region=${REGION} \
    --filter="displayName:high-performance-recommendation-model" \
    --format="value(name)" | head -1)

if [ -n "$MODEL_ID" ]; then
    gcloud ai models delete ${MODEL_ID} --region=${REGION} --quiet
    success "Vertex AI model deleted"
else
    warning "Vertex AI model 'high-performance-recommendation-model' not found"
fi

# 3. Delete Redis instance
log "Step 3: Deleting Redis instance..."
if [ -n "$REDIS_INSTANCE_ID" ]; then
    if gcloud redis instances describe ${REDIS_INSTANCE_ID} --region=${REGION} &> /dev/null; then
        gcloud redis instances delete ${REDIS_INSTANCE_ID} --region=${REGION} --quiet
        success "Redis instance deletion initiated"
        
        # Wait for Redis deletion to complete
        wait_for_deletion "gcloud redis instances describe ${REDIS_INSTANCE_ID} --region=${REGION}" "Redis instance"
    else
        warning "Redis instance '${REDIS_INSTANCE_ID}' not found"
    fi
else
    warning "Redis instance ID not found"
fi

# 4. Delete Bigtable instance
log "Step 4: Deleting Bigtable instance..."
if gcloud bigtable instances describe ${BIGTABLE_INSTANCE_ID} &> /dev/null; then
    gcloud bigtable instances delete ${BIGTABLE_INSTANCE_ID} --quiet
    success "Bigtable instance deleted"
else
    warning "Bigtable instance '${BIGTABLE_INSTANCE_ID}' not found"
fi

# 5. Delete Cloud Storage bucket
log "Step 5: Deleting Cloud Storage bucket..."
if [ -n "$BUCKET_NAME" ]; then
    if gsutil ls gs://${BUCKET_NAME} &> /dev/null; then
        # Remove all objects first
        gsutil -m rm -r gs://${BUCKET_NAME}/* || true
        # Remove bucket
        gsutil rb gs://${BUCKET_NAME}
        success "Cloud Storage bucket deleted"
    else
        warning "Cloud Storage bucket 'gs://${BUCKET_NAME}' not found"
    fi
else
    warning "Cloud Storage bucket name not found"
fi

# 6. Delete monitoring resources
log "Step 6: Deleting monitoring resources..."

# Delete custom metrics
log "Deleting custom log-based metrics..."
gcloud logging metrics delete inference_latency --quiet || warning "Custom metric 'inference_latency' not found"
gcloud logging metrics delete cache_hit_ratio --quiet || warning "Custom metric 'cache_hit_ratio' not found"

success "Monitoring resources cleaned up"

# 7. Clean up any remaining resources
log "Step 7: Searching for any remaining resources..."

# Check for any remaining AI Platform resources
remaining_models=$(gcloud ai models list --region=${REGION} \
    --filter="displayName:high-performance-recommendation-model" \
    --format="value(name)" | wc -l)

remaining_endpoints=$(gcloud ai endpoints list --region=${REGION} \
    --filter="displayName:${TPU_ENDPOINT_NAME}" \
    --format="value(name)" | wc -l)

# Check for any remaining storage buckets
remaining_buckets=$(gsutil ls -p ${PROJECT_ID} | grep "gs://ai-inference-models-" | wc -l)

if [ "$remaining_models" -gt 0 ] || [ "$remaining_endpoints" -gt 0 ] || [ "$remaining_buckets" -gt 0 ]; then
    warning "Some resources may still exist:"
    if [ "$remaining_models" -gt 0 ]; then
        echo "  - Vertex AI models: $remaining_models"
    fi
    if [ "$remaining_endpoints" -gt 0 ]; then
        echo "  - Vertex AI endpoints: $remaining_endpoints"
    fi
    if [ "$remaining_buckets" -gt 0 ]; then
        echo "  - Storage buckets: $remaining_buckets"
    fi
    echo "Please check the Cloud Console for any remaining resources."
else
    success "No remaining resources detected"
fi

# Final summary
echo
echo -e "${GREEN}======================================================================"
echo "  Cleanup Summary"
echo "======================================================================${NC}"
echo "✅ Cloud Function: Deleted"
echo "✅ Vertex AI Endpoint: Deleted"
echo "✅ Vertex AI Model: Deleted"
echo "✅ Redis Instance: Deleted"
echo "✅ Bigtable Instance: Deleted"
echo "✅ Cloud Storage Bucket: Deleted"
echo "✅ Monitoring Resources: Cleaned up"
echo
echo -e "${YELLOW}Important Notes:${NC}"
echo "1. Some resources may take a few minutes to fully delete"
echo "2. Check your Cloud Console to verify all resources are removed"
echo "3. Monitor your billing to ensure no unexpected charges"
echo "4. Some logs may remain for up to 30 days"
echo
echo -e "${BLUE}Verification Commands:${NC}"
echo "• Check remaining functions: gcloud functions list --region=${REGION}"
echo "• Check remaining AI models: gcloud ai models list --region=${REGION}"
echo "• Check remaining endpoints: gcloud ai endpoints list --region=${REGION}"
echo "• Check remaining Bigtable: gcloud bigtable instances list"
echo "• Check remaining Redis: gcloud redis instances list --region=${REGION}"
echo "• Check remaining buckets: gsutil ls -p ${PROJECT_ID}"
echo
echo "======================================================================"

success "Cleanup completed successfully!"

# Optional: Display cost information
echo
echo -e "${YELLOW}💰 Cost Reminder:${NC}"
echo "Deleted resources should no longer incur charges. However, please:"
echo "1. Check your billing dashboard in the next few days"
echo "2. Look for any remaining charges from this project"
echo "3. Consider setting up billing alerts for future deployments"
echo
echo "For billing information, visit:"
echo "https://console.cloud.google.com/billing"
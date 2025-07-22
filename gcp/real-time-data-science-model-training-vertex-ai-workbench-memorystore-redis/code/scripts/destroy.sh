#!/bin/bash

# Real-Time Data Science Model Training with Vertex AI Workbench and Memorystore Redis
# Cleanup Script for GCP
# This script safely removes all resources created by the deployment script

set -euo pipefail

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

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Load configuration if available
if [[ -f "deployment_config.env" ]]; then
    log "Loading configuration from deployment_config.env..."
    source deployment_config.env
else
    warning "No deployment_config.env found. Using environment variables or prompting for input."
fi

# Configuration with fallbacks
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
REDIS_INSTANCE_NAME="${REDIS_INSTANCE_NAME:-}"
WORKBENCH_NAME="${WORKBENCH_NAME:-}"
BUCKET_NAME="${BUCKET_NAME:-}"
JOB_NAME="${JOB_NAME:-}"

# Banner
echo "============================================"
echo "Real-Time ML Training Infrastructure Cleanup"
echo "============================================"
echo ""

# Prerequisites check
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install it first."
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    error "gsutil is not installed. Please install it first."
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
fi

success "Prerequisites check passed"

# If no configuration found, prompt for project ID
if [[ -z "${PROJECT_ID}" ]]; then
    echo "Enter the project ID where resources were deployed:"
    read -r PROJECT_ID
    if [[ -z "${PROJECT_ID}" ]]; then
        error "Project ID is required"
    fi
fi

# Set project
gcloud config set project "${PROJECT_ID}"

# Display configuration
log "Cleanup Configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Redis Instance: ${REDIS_INSTANCE_NAME:-<auto-detect>}"
echo "  Workbench Instance: ${WORKBENCH_NAME:-<auto-detect>}"
echo "  Storage Bucket: ${BUCKET_NAME:-<auto-detect>}"
echo "  Batch Job: ${JOB_NAME:-<auto-detect>}"
echo ""

# Auto-detect resources if not specified
if [[ -z "${REDIS_INSTANCE_NAME}" ]] || [[ -z "${WORKBENCH_NAME}" ]] || [[ -z "${BUCKET_NAME}" ]]; then
    log "Auto-detecting resources..."
    
    # Find Redis instances
    if [[ -z "${REDIS_INSTANCE_NAME}" ]]; then
        REDIS_INSTANCES=$(gcloud redis instances list --region="${REGION}" --filter="displayName:('ML Feature Cache')" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "${REDIS_INSTANCES}" ]]; then
            REDIS_INSTANCE_NAME=$(echo "${REDIS_INSTANCES}" | head -n1 | cut -d'/' -f6)
            log "Found Redis instance: ${REDIS_INSTANCE_NAME}"
        fi
    fi
    
    # Find Workbench instances
    if [[ -z "${WORKBENCH_NAME}" ]]; then
        WORKBENCH_INSTANCES=$(gcloud workbench instances list --location="${ZONE}" --filter="labels.team:data-science" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "${WORKBENCH_INSTANCES}" ]]; then
            WORKBENCH_NAME=$(basename "${WORKBENCH_INSTANCES}" | head -n1)
            log "Found Workbench instance: ${WORKBENCH_NAME}"
        fi
    fi
    
    # Find storage buckets
    if [[ -z "${BUCKET_NAME}" ]]; then
        BUCKET_LIST=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "ml-training-bucket" | head -n1 || echo "")
        if [[ -n "${BUCKET_LIST}" ]]; then
            BUCKET_NAME=$(echo "${BUCKET_LIST}" | sed 's|gs://||' | sed 's|/||')
            log "Found storage bucket: ${BUCKET_NAME}"
        fi
    fi
    
    # Find batch jobs
    if [[ -z "${JOB_NAME}" ]]; then
        BATCH_JOBS=$(gcloud batch jobs list --location="${REGION}" --filter="name~'ml-training-job'" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "${BATCH_JOBS}" ]]; then
            JOB_NAME=$(basename "${BATCH_JOBS}" | head -n1)
            log "Found batch job: ${JOB_NAME}"
        fi
    fi
fi

# Show final detection results
log "Final resource list for cleanup:"
echo "  Redis Instance: ${REDIS_INSTANCE_NAME:-<none found>}"
echo "  Workbench Instance: ${WORKBENCH_NAME:-<none found>}"
echo "  Storage Bucket: ${BUCKET_NAME:-<none found>}"
echo "  Batch Job: ${JOB_NAME:-<none found>}"
echo ""

# Confirmation prompt
echo "⚠️  WARNING: This will permanently delete all resources listed above!"
echo "This action cannot be undone."
echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

# Start cleanup process
log "Starting cleanup process..."

# Keep track of cleanup success
CLEANUP_SUCCESS=true

# 1. Delete Cloud Batch job
if [[ -n "${JOB_NAME}" ]]; then
    log "Deleting Cloud Batch job: ${JOB_NAME}"
    if gcloud batch jobs describe "${JOB_NAME}" --location="${REGION}" --quiet 2>/dev/null; then
        if gcloud batch jobs delete "${JOB_NAME}" --location="${REGION}" --quiet; then
            success "Batch job deleted successfully"
        else
            error "Failed to delete batch job"
            CLEANUP_SUCCESS=false
        fi
    else
        warning "Batch job not found or already deleted"
    fi
else
    warning "No batch job specified for deletion"
fi

# 2. Delete Vertex AI Workbench instance
if [[ -n "${WORKBENCH_NAME}" ]]; then
    log "Deleting Vertex AI Workbench instance: ${WORKBENCH_NAME}"
    if gcloud workbench instances describe "${WORKBENCH_NAME}" --location="${ZONE}" --quiet 2>/dev/null; then
        if gcloud workbench instances delete "${WORKBENCH_NAME}" --location="${ZONE}" --quiet; then
            success "Workbench instance deleted successfully"
        else
            error "Failed to delete Workbench instance"
            CLEANUP_SUCCESS=false
        fi
    else
        warning "Workbench instance not found or already deleted"
    fi
else
    warning "No Workbench instance specified for deletion"
fi

# 3. Delete Memorystore Redis instance
if [[ -n "${REDIS_INSTANCE_NAME}" ]]; then
    log "Deleting Memorystore Redis instance: ${REDIS_INSTANCE_NAME}"
    if gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
        if gcloud redis instances delete "${REDIS_INSTANCE_NAME}" --region="${REGION}" --quiet; then
            success "Redis instance deleted successfully"
        else
            error "Failed to delete Redis instance"
            CLEANUP_SUCCESS=false
        fi
    else
        warning "Redis instance not found or already deleted"
    fi
else
    warning "No Redis instance specified for deletion"
fi

# 4. Delete Cloud Storage bucket and contents
if [[ -n "${BUCKET_NAME}" ]]; then
    log "Deleting Cloud Storage bucket: ${BUCKET_NAME}"
    if gsutil ls -b "gs://${BUCKET_NAME}" 2>/dev/null; then
        # First remove all objects
        log "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/*" 2>/dev/null || true; then
            log "Bucket objects removed"
        fi
        
        # Then remove the bucket
        if gsutil rb "gs://${BUCKET_NAME}"; then
            success "Storage bucket deleted successfully"
        else
            error "Failed to delete storage bucket"
            CLEANUP_SUCCESS=false
        fi
    else
        warning "Storage bucket not found or already deleted"
    fi
else
    warning "No storage bucket specified for deletion"
fi

# 5. Delete firewall rules
log "Deleting firewall rules..."
if gcloud compute firewall-rules describe allow-redis-access --quiet 2>/dev/null; then
    if gcloud compute firewall-rules delete allow-redis-access --quiet; then
        success "Firewall rule deleted successfully"
    else
        error "Failed to delete firewall rule"
        CLEANUP_SUCCESS=false
    fi
else
    warning "Firewall rule not found or already deleted"
fi

# 6. Delete monitoring dashboards
log "Deleting monitoring dashboards..."
DASHBOARDS=$(gcloud monitoring dashboards list --filter="displayName:('ML Training Pipeline Dashboard')" --format="value(name)" 2>/dev/null || echo "")
if [[ -n "${DASHBOARDS}" ]]; then
    for dashboard in ${DASHBOARDS}; do
        if gcloud monitoring dashboards delete "${dashboard}" --quiet; then
            success "Monitoring dashboard deleted: ${dashboard}"
        else
            warning "Failed to delete monitoring dashboard: ${dashboard}"
        fi
    done
else
    warning "No monitoring dashboards found"
fi

# 7. Clean up local files
log "Cleaning up local files..."
if [[ -f "deployment_config.env" ]]; then
    rm -f deployment_config.env
    success "Deployment configuration file removed"
fi

# Clean up any remaining temporary files
rm -f generate_dataset.py training_script.py batch_job.json 2>/dev/null || true
rm -f monitoring_dashboard.json ml_training_notebook.ipynb training_dataset.csv 2>/dev/null || true

success "Local files cleaned up"

# 8. Optional: Disable APIs (with confirmation)
echo ""
read -p "Do you want to disable the Google Cloud APIs that were enabled? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Disabling Google Cloud APIs..."
    
    # List of APIs to disable
    APIs=(
        "aiplatform.googleapis.com"
        "redis.googleapis.com"
        "batch.googleapis.com"
        "workbench.googleapis.com"
        "notebooks.googleapis.com"
    )
    
    for api in "${APIs[@]}"; do
        if gcloud services disable "${api}" --quiet 2>/dev/null; then
            success "Disabled API: ${api}"
        else
            warning "Failed to disable API: ${api} (may still be in use)"
        fi
    done
else
    log "Skipping API cleanup (APIs remain enabled)"
fi

# Final summary
echo ""
echo "============================================"
echo "Cleanup Summary"
echo "============================================"

if [[ "${CLEANUP_SUCCESS}" == "true" ]]; then
    success "✅ All resources have been successfully cleaned up!"
    echo ""
    echo "Resources removed:"
    echo "  ✅ Cloud Batch job: ${JOB_NAME:-<not found>}"
    echo "  ✅ Vertex AI Workbench: ${WORKBENCH_NAME:-<not found>}"
    echo "  ✅ Memorystore Redis: ${REDIS_INSTANCE_NAME:-<not found>}"
    echo "  ✅ Cloud Storage bucket: ${BUCKET_NAME:-<not found>}"
    echo "  ✅ Firewall rules: allow-redis-access"
    echo "  ✅ Monitoring dashboards"
    echo "  ✅ Local configuration files"
    echo ""
    echo "💰 Cost Impact: All billable resources have been removed"
    echo ""
    echo "⚠️  Note: Some logs and audit trails may remain in Cloud Logging"
    echo "    and can be cleaned up separately if needed."
else
    warning "⚠️  Cleanup completed with some errors"
    echo ""
    echo "Some resources may not have been deleted successfully."
    echo "Please check the Google Cloud Console to verify all resources"
    echo "have been removed and manually delete any remaining resources."
    echo ""
    echo "You can also re-run this script to attempt cleanup again."
fi

echo "============================================"

exit 0
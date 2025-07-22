#!/bin/bash

# Supply Chain Analytics with Cloud Bigtable and Cloud Dataproc - Cleanup Script
# This script safely destroys all resources created by the deployment script

set -euo pipefail

# Colors for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "Google Cloud SDK (gcloud) is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command_exists gsutil; then
        error "gsutil is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Try to get project ID from gcloud config if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error "PROJECT_ID is not set and cannot be determined from gcloud config"
            error "Please set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default values if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Resource names - these should match what was created
    export BIGTABLE_INSTANCE_ID="${BIGTABLE_INSTANCE_ID:-}"
    export DATAPROC_CLUSTER_NAME="${DATAPROC_CLUSTER_NAME:-}"
    export BUCKET_NAME="${BUCKET_NAME:-}"
    export TOPIC_NAME="${TOPIC_NAME:-}"
    export FUNCTION_NAME="${FUNCTION_NAME:-process-sensor-data}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-supply-chain-analytics-job}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    success "Environment configured for cleanup"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
}

# Function to discover resources if not specified
discover_resources() {
    log "Discovering resources to clean up..."
    
    # Discover Dataproc clusters if not specified
    if [[ -z "${DATAPROC_CLUSTER_NAME}" ]]; then
        log "Searching for Dataproc clusters with 'supply-analytics' prefix..."
        local clusters
        clusters=$(gcloud dataproc clusters list --region="${REGION}" \
            --filter="clusterName~supply-analytics.*" \
            --format="value(clusterName)" 2>/dev/null || echo "")
        
        if [[ -n "${clusters}" ]]; then
            DATAPROC_CLUSTER_NAME=$(echo "${clusters}" | head -n1)
            log "Found Dataproc cluster: ${DATAPROC_CLUSTER_NAME}"
        fi
    fi
    
    # Discover Bigtable instances if not specified
    if [[ -z "${BIGTABLE_INSTANCE_ID}" ]]; then
        log "Searching for Bigtable instances with 'supply-chain-bt' prefix..."
        local instances
        instances=$(gcloud bigtable instances list \
            --filter="name~.*supply-chain-bt.*" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${instances}" ]]; then
            BIGTABLE_INSTANCE_ID=$(basename "${instances}" | head -n1)
            log "Found Bigtable instance: ${BIGTABLE_INSTANCE_ID}"
        fi
    fi
    
    # Discover storage buckets if not specified
    if [[ -z "${BUCKET_NAME}" ]]; then
        log "Searching for storage buckets with 'supply-chain-data' prefix..."
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
            grep "supply-chain-data" | \
            sed 's|gs://||' | sed 's|/||' | head -n1 || echo "")
        
        if [[ -n "${buckets}" ]]; then
            BUCKET_NAME="${buckets}"
            log "Found storage bucket: ${BUCKET_NAME}"
        fi
    fi
    
    # Discover Pub/Sub topics if not specified
    if [[ -z "${TOPIC_NAME}" ]]; then
        log "Searching for Pub/Sub topics with 'sensor-data-topic' prefix..."
        local topics
        topics=$(gcloud pubsub topics list \
            --filter="name~.*sensor-data-topic.*" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${topics}" ]]; then
            TOPIC_NAME=$(basename "${topics}" | head -n1)
            log "Found Pub/Sub topic: ${TOPIC_NAME}"
        fi
    fi
    
    success "Resource discovery completed"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo
    echo "This script will DELETE the following resources:"
    echo
    
    if [[ -n "${DATAPROC_CLUSTER_NAME}" ]]; then
        echo "   🔥 Dataproc Cluster: ${DATAPROC_CLUSTER_NAME}"
    fi
    
    if [[ -n "${BIGTABLE_INSTANCE_ID}" ]]; then
        echo "   🔥 Bigtable Instance: ${BIGTABLE_INSTANCE_ID} (including all data)"
    fi
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        echo "   🔥 Storage Bucket: gs://${BUCKET_NAME} (including all data)"
    fi
    
    if [[ -n "${TOPIC_NAME}" ]]; then
        echo "   🔥 Pub/Sub Topic: ${TOPIC_NAME}"
    fi
    
    echo "   🔥 Cloud Function: ${FUNCTION_NAME}"
    echo "   🔥 Cloud Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "   🔥 Monitoring Dashboards"
    echo
    echo "   Project: ${PROJECT_ID}"
    echo "   Region: ${REGION}"
    echo
    warning "🚨 THIS ACTION CANNOT BE UNDONE! 🚨"
    echo
    
    # Allow bypass for automation
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        warning "Skipping confirmation due to SKIP_CONFIRMATION=true"
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to proceed: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log "Proceeding with resource cleanup..."
}

# Function to delete Cloud Scheduler job
delete_scheduler_job() {
    log "Deleting Cloud Scheduler job..."
    
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" \
            --location="${REGION}" \
            --quiet || {
            error "Failed to delete scheduler job: ${SCHEDULER_JOB_NAME}"
            return 1
        }
        success "Deleted scheduler job: ${SCHEDULER_JOB_NAME}"
    else
        warning "Scheduler job ${SCHEDULER_JOB_NAME} not found or already deleted"
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet || {
            error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            return 1
        }
        success "Deleted Cloud Function: ${FUNCTION_NAME}"
    else
        warning "Cloud Function ${FUNCTION_NAME} not found or already deleted"
    fi
}

# Function to delete Dataproc cluster
delete_dataproc_cluster() {
    if [[ -z "${DATAPROC_CLUSTER_NAME}" ]]; then
        warning "No Dataproc cluster name specified, skipping"
        return 0
    fi
    
    log "Deleting Dataproc cluster: ${DATAPROC_CLUSTER_NAME}"
    
    if gcloud dataproc clusters describe "${DATAPROC_CLUSTER_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        # Cancel any running jobs first
        log "Cancelling any running jobs on cluster..."
        local running_jobs
        running_jobs=$(gcloud dataproc jobs list \
            --cluster="${DATAPROC_CLUSTER_NAME}" \
            --region="${REGION}" \
            --filter="status.state=RUNNING" \
            --format="value(reference.jobId)" 2>/dev/null || echo "")
        
        if [[ -n "${running_jobs}" ]]; then
            echo "${running_jobs}" | while read -r job_id; do
                if [[ -n "${job_id}" ]]; then
                    log "Cancelling job: ${job_id}"
                    gcloud dataproc jobs cancel "${job_id}" \
                        --region="${REGION}" \
                        --quiet || warning "Failed to cancel job ${job_id}"
                fi
            done
        fi
        
        # Delete the cluster
        gcloud dataproc clusters delete "${DATAPROC_CLUSTER_NAME}" \
            --region="${REGION}" \
            --quiet || {
            error "Failed to delete Dataproc cluster: ${DATAPROC_CLUSTER_NAME}"
            return 1
        }
        success "Deleted Dataproc cluster: ${DATAPROC_CLUSTER_NAME}"
    else
        warning "Dataproc cluster ${DATAPROC_CLUSTER_NAME} not found or already deleted"
    fi
}

# Function to delete Bigtable instance
delete_bigtable_instance() {
    if [[ -z "${BIGTABLE_INSTANCE_ID}" ]]; then
        warning "No Bigtable instance ID specified, skipping"
        return 0
    fi
    
    log "Deleting Bigtable instance: ${BIGTABLE_INSTANCE_ID}"
    
    if gcloud bigtable instances describe "${BIGTABLE_INSTANCE_ID}" >/dev/null 2>&1; then
        gcloud bigtable instances delete "${BIGTABLE_INSTANCE_ID}" \
            --quiet || {
            error "Failed to delete Bigtable instance: ${BIGTABLE_INSTANCE_ID}"
            return 1
        }
        success "Deleted Bigtable instance: ${BIGTABLE_INSTANCE_ID}"
    else
        warning "Bigtable instance ${BIGTABLE_INSTANCE_ID} not found or already deleted"
    fi
}

# Function to delete Pub/Sub topic
delete_pubsub_topic() {
    if [[ -z "${TOPIC_NAME}" ]]; then
        warning "No Pub/Sub topic name specified, skipping"
        return 0
    fi
    
    log "Deleting Pub/Sub topic: ${TOPIC_NAME}"
    
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        gcloud pubsub topics delete "${TOPIC_NAME}" \
            --quiet || {
            error "Failed to delete Pub/Sub topic: ${TOPIC_NAME}"
            return 1
        }
        success "Deleted Pub/Sub topic: ${TOPIC_NAME}"
    else
        warning "Pub/Sub topic ${TOPIC_NAME} not found or already deleted"
    fi
}

# Function to delete storage bucket
delete_storage_bucket() {
    if [[ -z "${BUCKET_NAME}" ]]; then
        warning "No storage bucket name specified, skipping"
        return 0
    fi
    
    log "Deleting storage bucket: gs://${BUCKET_NAME}"
    
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        # First, delete all objects in the bucket
        log "Removing all objects from bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || {
            warning "No objects found in bucket or already deleted"
        }
        
        # Then delete the bucket itself
        gsutil rb "gs://${BUCKET_NAME}" || {
            error "Failed to delete storage bucket: gs://${BUCKET_NAME}"
            return 1
        }
        success "Deleted storage bucket: gs://${BUCKET_NAME}"
    else
        warning "Storage bucket gs://${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to delete monitoring dashboards
delete_monitoring_dashboards() {
    log "Deleting monitoring dashboards..."
    
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName~.*Supply Chain Analytics.*" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${dashboards}" ]]; then
        echo "${dashboards}" | while read -r dashboard; do
            if [[ -n "${dashboard}" ]]; then
                gcloud monitoring dashboards delete "${dashboard}" \
                    --quiet || warning "Failed to delete dashboard: ${dashboard}"
            fi
        done
        success "Deleted monitoring dashboards"
    else
        warning "No matching monitoring dashboards found"
    fi
}

# Function to clean up IAM roles and service accounts (if any were created)
cleanup_iam() {
    log "Checking for custom IAM resources..."
    
    # Look for custom service accounts that might have been created
    local custom_sa
    custom_sa=$(gcloud iam service-accounts list \
        --filter="displayName~.*supply.chain.*" \
        --format="value(email)" 2>/dev/null || echo "")
    
    if [[ -n "${custom_sa}" ]]; then
        echo "${custom_sa}" | while read -r sa_email; do
            if [[ -n "${sa_email}" ]]; then
                log "Found custom service account: ${sa_email}"
                read -p "Delete custom service account ${sa_email}? (y/N): " delete_sa
                if [[ "${delete_sa}" =~ ^[Yy]$ ]]; then
                    gcloud iam service-accounts delete "${sa_email}" --quiet || {
                        warning "Failed to delete service account: ${sa_email}"
                    }
                else
                    warning "Keeping service account: ${sa_email}"
                fi
            fi
        done
    else
        log "No custom service accounts found"
    fi
}

# Function to check for remaining resources
check_remaining_resources() {
    log "Checking for any remaining resources..."
    
    local found_resources=false
    
    # Check for remaining Dataproc clusters
    local remaining_clusters
    remaining_clusters=$(gcloud dataproc clusters list --region="${REGION}" \
        --filter="clusterName~.*supply.*" \
        --format="value(clusterName)" 2>/dev/null || echo "")
    
    if [[ -n "${remaining_clusters}" ]]; then
        warning "Remaining Dataproc clusters found:"
        echo "${remaining_clusters}" | while read -r cluster; do
            echo "   - ${cluster}"
        done
        found_resources=true
    fi
    
    # Check for remaining Bigtable instances
    local remaining_instances
    remaining_instances=$(gcloud bigtable instances list \
        --filter="name~.*supply.*" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${remaining_instances}" ]]; then
        warning "Remaining Bigtable instances found:"
        echo "${remaining_instances}" | while read -r instance; do
            echo "   - $(basename "${instance}")"
        done
        found_resources=true
    fi
    
    # Check for remaining storage buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
        grep "supply" || echo "")
    
    if [[ -n "${remaining_buckets}" ]]; then
        warning "Remaining storage buckets found:"
        echo "${remaining_buckets}" | while read -r bucket; do
            echo "   - ${bucket}"
        done
        found_resources=true
    fi
    
    if [[ "${found_resources}" == "false" ]]; then
        success "No remaining supply chain analytics resources found"
    else
        warning "Some resources may require manual cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    success "Supply Chain Analytics Platform Cleanup Complete!"
    echo
    echo "🗑️  Resources Deleted:"
    echo "   • Cloud Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "   • Cloud Function: ${FUNCTION_NAME}"
    
    if [[ -n "${DATAPROC_CLUSTER_NAME}" ]]; then
        echo "   • Dataproc Cluster: ${DATAPROC_CLUSTER_NAME}"
    fi
    
    if [[ -n "${BIGTABLE_INSTANCE_ID}" ]]; then
        echo "   • Bigtable Instance: ${BIGTABLE_INSTANCE_ID}"
    fi
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        echo "   • Storage Bucket: gs://${BUCKET_NAME}"
    fi
    
    if [[ -n "${TOPIC_NAME}" ]]; then
        echo "   • Pub/Sub Topic: ${TOPIC_NAME}"
    fi
    
    echo "   • Monitoring Dashboards"
    echo
    echo "💡 Tips:"
    echo "   • Check your billing dashboard to confirm charges have stopped"
    echo "   • Review the project for any remaining resources if needed"
    echo "   • Consider deleting the entire project if it was created specifically for this recipe"
    echo
    success "Cleanup completed successfully! 🧹"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    echo
    warning "Cleanup interrupted!"
    echo
    warning "Some resources may still exist. You can:"
    echo "1. Re-run this script to continue cleanup"
    echo "2. Manually delete resources via the Google Cloud Console"
    echo "3. Delete the entire project if it was created specifically for this recipe"
    echo
    exit 1
}

# Main cleanup function
main() {
    echo "🧹 Starting Supply Chain Analytics Platform Cleanup"
    echo "==============================================="
    
    check_prerequisites
    setup_environment
    discover_resources
    confirm_deletion
    
    # Delete resources in reverse order of dependencies
    delete_scheduler_job
    delete_cloud_function
    delete_dataproc_cluster
    delete_bigtable_instance
    delete_pubsub_topic
    delete_storage_bucket
    delete_monitoring_dashboards
    cleanup_iam
    check_remaining_resources
    display_cleanup_summary
    
    success "Cleanup completed successfully! 🎉"
}

# Handle script interruption
trap cleanup_on_interrupt INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirmation)
            export SKIP_CONFIRMATION=true
            shift
            ;;
        --project-id)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --bigtable-instance)
            export BIGTABLE_INSTANCE_ID="$2"
            shift 2
            ;;
        --dataproc-cluster)
            export DATAPROC_CLUSTER_NAME="$2"
            shift 2
            ;;
        --bucket-name)
            export BUCKET_NAME="$2"
            shift 2
            ;;
        --topic-name)
            export TOPIC_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Supply Chain Analytics Platform Cleanup Script"
            echo
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --skip-confirmation        Skip deletion confirmation prompt"
            echo "  --project-id PROJECT_ID    Google Cloud Project ID"
            echo "  --region REGION            Google Cloud Region (default: us-central1)"
            echo "  --bigtable-instance ID     Bigtable Instance ID to delete"
            echo "  --dataproc-cluster NAME    Dataproc Cluster name to delete"
            echo "  --bucket-name NAME         Storage bucket name to delete"
            echo "  --topic-name NAME          Pub/Sub topic name to delete"
            echo "  --help                     Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PROJECT_ID                 Google Cloud Project ID"
            echo "  REGION                     Google Cloud Region"
            echo "  BIGTABLE_INSTANCE_ID      Bigtable Instance ID"
            echo "  DATAPROC_CLUSTER_NAME     Dataproc Cluster name"
            echo "  BUCKET_NAME               Storage bucket name"
            echo "  TOPIC_NAME                Pub/Sub topic name"
            echo
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
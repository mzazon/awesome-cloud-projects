#!/bin/bash

# Destroy script for Code Review and Documentation Workflows with Google Workspace APIs and Cloud Run
# This script safely removes all infrastructure created by the deployment script

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Display banner
echo -e "${RED}"
echo "=================================================="
echo "  Code Review Workflow Cleanup Script"
echo "  GCP Recipe: workspace-apis-cloud-run"
echo "  WARNING: This will DELETE all resources!"
echo "=================================================="
echo -e "${NC}"

# Prerequisites validation
log_info "Validating prerequisites..."

# Check required tools
if ! command_exists gcloud; then
    error_exit "Google Cloud CLI (gcloud) is not installed or not in PATH"
fi

if ! command_exists gsutil; then
    error_exit "Google Cloud Storage utility (gsutil) is not installed or not in PATH"
fi

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
fi

log_success "Prerequisites validation completed"

# Configuration
log_info "Loading configuration..."

# Try to load from deployment info file if it exists
if [ -f "deployment-info.txt" ]; then
    log_info "Found deployment-info.txt, extracting configuration..."
    PROJECT_ID=$(grep "Project ID:" deployment-info.txt | cut -d' ' -f3 || echo "")
    REGION=$(grep "Region:" deployment-info.txt | cut -d' ' -f2 || echo "")
    SERVICE_NAME=$(grep "Service Name:" deployment-info.txt | cut -d' ' -f4 || echo "")
    TOPIC_NAME=$(grep "Topic Name:" deployment-info.txt | cut -d' ' -f4 || echo "")
    SUBSCRIPTION_NAME=$(grep "Subscription Name:" deployment-info.txt | cut -d' ' -f4 || echo "")
    BUCKET_NAME=$(grep "Bucket Name:" deployment-info.txt | cut -d' ' -f4 || echo "")
fi

# Use environment variables as fallback or if no deployment info
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
REGION="${REGION:-us-central1}"

# If we still don't have project ID, prompt user
if [ -z "${PROJECT_ID}" ]; then
    echo
    read -p "Enter the Google Cloud Project ID to clean up: " PROJECT_ID
    if [ -z "${PROJECT_ID}" ]; then
        error_exit "Project ID is required"
    fi
fi

# Set gcloud project
log_info "Setting project context..."
gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project ${PROJECT_ID}"

# Display configuration
log_info "Cleanup Configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
if [ -n "${SERVICE_NAME:-}" ]; then
    echo "  Service Name: ${SERVICE_NAME}"
fi
if [ -n "${TOPIC_NAME:-}" ]; then
    echo "  Topic Name: ${TOPIC_NAME}"
fi
if [ -n "${BUCKET_NAME:-}" ]; then
    echo "  Bucket Name: ${BUCKET_NAME}"
fi

# Safety confirmation
echo
echo -e "${RED}⚠️  WARNING: This will permanently delete all resources!${NC}"
echo -e "${YELLOW}This action cannot be undone.${NC}"
echo

if [ "${DESTROY_CONFIRM:-}" != "yes" ]; then
    read -p "Are you sure you want to delete all resources? Type 'yes' to confirm: " -r
    if [ "$REPLY" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
fi

echo
log_info "Starting resource cleanup..."

# Function to safely delete resources with error handling
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    
    log_info "Deleting ${resource_type}..."
    if eval "$delete_command" 2>/dev/null; then
        log_success "${resource_type} deleted successfully"
    else
        log_warning "Failed to delete ${resource_type} or it doesn't exist"
    fi
}

# Function to list and delete Cloud Run services with pattern matching
delete_cloud_run_services() {
    log_info "Finding and deleting Cloud Run services..."
    
    # Get list of services in the region
    services=$(gcloud run services list --region="${REGION}" --format="value(metadata.name)" 2>/dev/null || echo "")
    
    if [ -n "$services" ]; then
        # Delete specific services if we know their names
        if [ -n "${SERVICE_NAME:-}" ]; then
            safe_delete "Code Review Service (${SERVICE_NAME})" \
                "gcloud run services delete '${SERVICE_NAME}' --region='${REGION}' --quiet"
        fi
        
        # Find and delete services with common patterns
        for service in $services; do
            if echo "$service" | grep -qE "(code-review|docs-service|notification-service)"; then
                safe_delete "Cloud Run Service ($service)" \
                    "gcloud run services delete '$service' --region='${REGION}' --quiet"
            fi
        done
    else
        log_info "No Cloud Run services found in region ${REGION}"
    fi
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Finding and deleting Cloud Scheduler jobs..."
    
    # Get list of jobs in the region
    jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$jobs" ]; then
        for job in $jobs; do
            job_name=$(basename "$job")
            if echo "$job_name" | grep -qE "(weekly-doc-review|monthly-cleanup|maintenance-trigger)"; then
                safe_delete "Scheduler Job ($job_name)" \
                    "gcloud scheduler jobs delete '$job_name' --location='${REGION}' --quiet"
            fi
        done
    else
        log_info "No Cloud Scheduler jobs found in region ${REGION}"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Finding and deleting Pub/Sub resources..."
    
    # Delete specific subscription if we know its name
    if [ -n "${SUBSCRIPTION_NAME:-}" ]; then
        safe_delete "Pub/Sub Subscription (${SUBSCRIPTION_NAME})" \
            "gcloud pubsub subscriptions delete '${SUBSCRIPTION_NAME}' --quiet"
    fi
    
    # Find and delete subscriptions with common patterns
    subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null || echo "")
    for subscription in $subscriptions; do
        subscription_name=$(basename "$subscription")
        if echo "$subscription_name" | grep -qE "(code-processing|code-events)"; then
            safe_delete "Pub/Sub Subscription ($subscription_name)" \
                "gcloud pubsub subscriptions delete '$subscription_name' --quiet"
        fi
    done
    
    # Delete specific topic if we know its name
    if [ -n "${TOPIC_NAME:-}" ]; then
        safe_delete "Pub/Sub Topic (${TOPIC_NAME})" \
            "gcloud pubsub topics delete '${TOPIC_NAME}' --quiet"
    fi
    
    # Find and delete topics with common patterns
    topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null || echo "")
    for topic in $topics; do
        topic_name=$(basename "$topic")
        if echo "$topic_name" | grep -qE "(code-events|code-review)"; then
            safe_delete "Pub/Sub Topic ($topic_name)" \
                "gcloud pubsub topics delete '$topic_name' --quiet"
        fi
    done
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Finding and deleting Cloud Storage buckets..."
    
    # Delete specific bucket if we know its name
    if [ -n "${BUCKET_NAME:-}" ]; then
        if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
            log_info "Deleting bucket contents: gs://${BUCKET_NAME}"
            gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || log_warning "Failed to delete bucket gs://${BUCKET_NAME}"
            log_success "Storage bucket ${BUCKET_NAME} deleted"
        else
            log_info "Bucket gs://${BUCKET_NAME} not found or already deleted"
        fi
    fi
    
    # Find and delete buckets with common patterns
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(code-artifacts|code-review)" || echo "")
    for bucket in $buckets; do
        if [ -n "$bucket" ]; then
            log_info "Deleting bucket: $bucket"
            gsutil -m rm -r "$bucket" 2>/dev/null || log_warning "Failed to delete bucket $bucket"
        fi
    done
}

# Function to delete Secret Manager secrets
delete_secrets() {
    log_info "Finding and deleting Secret Manager secrets..."
    
    secrets=$(gcloud secrets list --format="value(name)" 2>/dev/null || echo "")
    for secret in $secrets; do
        if echo "$secret" | grep -qE "(workspace-credentials|code-review)"; then
            safe_delete "Secret ($secret)" \
                "gcloud secrets delete '$secret' --quiet"
        fi
    done
}

# Function to delete service accounts
delete_service_accounts() {
    log_info "Finding and deleting service accounts..."
    
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" 2>/dev/null || echo "")
    for sa in $service_accounts; do
        if echo "$sa" | grep -qE "(workspace-automation|code-review)"; then
            safe_delete "Service Account ($sa)" \
                "gcloud iam service-accounts delete '$sa' --quiet"
        fi
    done
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Finding and deleting monitoring resources..."
    
    # Delete dashboards with common patterns
    dashboards=$(gcloud monitoring dashboards list --format="value(name)" 2>/dev/null || echo "")
    for dashboard in $dashboards; do
        dashboard_id=$(basename "$dashboard")
        dashboard_info=$(gcloud monitoring dashboards describe "$dashboard_id" --format="value(displayName)" 2>/dev/null || echo "")
        if echo "$dashboard_info" | grep -qE "(Code Review|code-review)"; then
            safe_delete "Monitoring Dashboard ($dashboard_id)" \
                "gcloud monitoring dashboards delete '$dashboard_id' --quiet"
        fi
    done
    
    # Delete alert policies with common patterns
    policies=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null || echo "")
    for policy in $policies; do
        policy_id=$(basename "$policy")
        policy_info=$(gcloud alpha monitoring policies describe "$policy_id" --format="value(displayName)" 2>/dev/null || echo "")
        if echo "$policy_info" | grep -qE "(Code Review|code-review)"; then
            safe_delete "Alert Policy ($policy_id)" \
                "gcloud alpha monitoring policies delete '$policy_id' --quiet"
        fi
    done
}

# Execute cleanup in reverse order of creation
log_info "Step 1: Deleting Cloud Scheduler jobs..."
delete_scheduler_jobs

log_info "Step 2: Deleting Cloud Run services..."
delete_cloud_run_services

log_info "Step 3: Deleting monitoring resources..."
delete_monitoring_resources

log_info "Step 4: Deleting Pub/Sub resources..."
delete_pubsub_resources

log_info "Step 5: Deleting Cloud Storage buckets..."
delete_storage_buckets

log_info "Step 6: Deleting Secret Manager secrets..."
delete_secrets

log_info "Step 7: Deleting service accounts..."
delete_service_accounts

# Clean up local files
log_info "Step 8: Cleaning up local files..."
if [ -f "deployment-info.txt" ]; then
    if [ "${KEEP_DEPLOYMENT_INFO:-}" != "yes" ]; then
        rm -f deployment-info.txt
        log_success "Removed deployment-info.txt"
    else
        log_info "Keeping deployment-info.txt (KEEP_DEPLOYMENT_INFO=yes)"
    fi
fi

# Remove any temporary files that might have been left behind
rm -f lifecycle.json workspace-key.json test-payload.json
rm -f dashboard-config.json alert-policy.json
rm -rf code-review-service docs-service notification-service

log_success "Local files cleaned up"

# Verification
log_info "Step 9: Verification..."

# Check remaining resources
log_info "Checking for remaining resources..."

# Check Cloud Run services
remaining_services=$(gcloud run services list --region="${REGION}" --format="value(metadata.name)" 2>/dev/null | grep -E "(code-review|docs-service|notification-service)" || echo "")
if [ -n "$remaining_services" ]; then
    log_warning "Some Cloud Run services may still exist: $remaining_services"
else
    log_success "No matching Cloud Run services found"
fi

# Check Pub/Sub topics
remaining_topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(code-events|code-review)" || echo "")
if [ -n "$remaining_topics" ]; then
    log_warning "Some Pub/Sub topics may still exist: $remaining_topics"
else
    log_success "No matching Pub/Sub topics found"
fi

# Check storage buckets
remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(code-artifacts|code-review)" || echo "")
if [ -n "$remaining_buckets" ]; then
    log_warning "Some storage buckets may still exist: $remaining_buckets"
else
    log_success "No matching storage buckets found"
fi

# Final summary
echo
echo -e "${GREEN}=================================================="
echo "  Cleanup Completed!"
echo "==================================================${NC}"
echo
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo
echo "Resources cleaned up:"
echo "✅ Cloud Run services"
echo "✅ Cloud Scheduler jobs"
echo "✅ Pub/Sub topics and subscriptions"
echo "✅ Cloud Storage buckets"
echo "✅ Secret Manager secrets"
echo "✅ Service accounts"
echo "✅ Monitoring dashboards and alerts"
echo "✅ Local temporary files"
echo

if [ -n "$remaining_services" ] || [ -n "$remaining_topics" ] || [ -n "$remaining_buckets" ]; then
    echo -e "${YELLOW}⚠️  Some resources may still exist. Please review manually.${NC}"
    echo
    echo "To check remaining resources, run:"
    echo "  gcloud run services list --region=${REGION}"
    echo "  gcloud pubsub topics list"
    echo "  gsutil ls -p ${PROJECT_ID}"
    echo
else
    echo -e "${GREEN}✅ All resources have been successfully cleaned up!${NC}"
    echo
fi

echo "Optional: To delete the entire project, run:"
echo "  gcloud projects delete ${PROJECT_ID}"
echo
echo -e "${GREEN}Cleanup completed successfully!${NC}"
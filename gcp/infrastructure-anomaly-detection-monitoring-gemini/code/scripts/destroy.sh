#!/bin/bash

# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on any pipe failure

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project ID (try to get from current config if not set)
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            log_error "PROJECT_ID not set and cannot detect from gcloud config. Please set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    log_info "Using PROJECT_ID: $PROJECT_ID"
    log_info "Using REGION: $REGION"
    log_info "Using ZONE: $ZONE"
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Environment setup completed"
}

# Function to confirm cleanup
confirm_cleanup() {
    log_warning "This will delete ALL resources created by the Infrastructure Anomaly Detection deployment."
    log_warning "This action cannot be undone."
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with cleanup..."
}

# Function to discover resources with anomaly detection pattern
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Discover Cloud Functions
    FUNCTIONS=$(gcloud functions list --region="$REGION" --format="value(name)" --filter="name:anomaly-detector" 2>/dev/null || echo "")
    
    # Discover Pub/Sub topics
    TOPICS=$(gcloud pubsub topics list --format="value(name)" --filter="name:monitoring-events" 2>/dev/null || echo "")
    
    # Discover Pub/Sub subscriptions
    SUBSCRIPTIONS=$(gcloud pubsub subscriptions list --format="value(name)" --filter="name:anomaly-analysis" 2>/dev/null || echo "")
    
    # Discover VM instances
    INSTANCES=$(gcloud compute instances list --zones="$ZONE" --format="value(name)" --filter="name:test-instance" 2>/dev/null || echo "")
    
    # Discover alert policies
    ALERT_POLICIES=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:'AI-Powered CPU Anomaly Detection'" 2>/dev/null || echo "")
    
    # Discover custom metrics
    CUSTOM_METRICS=$(gcloud logging metrics list --format="value(name)" --filter="name:anomaly_score" 2>/dev/null || echo "")
    
    # Discover dashboards
    DASHBOARDS=$(gcloud monitoring dashboards list --format="value(name)" --filter="displayName:'AI-Powered Infrastructure Anomaly Detection'" 2>/dev/null || echo "")
    
    log_success "Resource discovery completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [ -n "$FUNCTIONS" ]; then
        log_info "Deleting Cloud Functions..."
        
        for function in $FUNCTIONS; do
            log_info "Deleting Cloud Function: $function"
            gcloud functions delete "$function" \
                --region="$REGION" \
                --quiet || log_warning "Failed to delete function: $function"
        done
        
        log_success "Cloud Functions cleanup completed"
    else
        log_info "No Cloud Functions found to delete"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    # Delete subscriptions first
    if [ -n "$SUBSCRIPTIONS" ]; then
        log_info "Deleting Pub/Sub subscriptions..."
        
        for subscription in $SUBSCRIPTIONS; do
            log_info "Deleting subscription: $subscription"
            gcloud pubsub subscriptions delete "$subscription" \
                --quiet || log_warning "Failed to delete subscription: $subscription"
        done
        
        log_success "Pub/Sub subscriptions cleanup completed"
    else
        log_info "No Pub/Sub subscriptions found to delete"
    fi
    
    # Delete topics
    if [ -n "$TOPICS" ]; then
        log_info "Deleting Pub/Sub topics..."
        
        for topic in $TOPICS; do
            log_info "Deleting topic: $topic"
            gcloud pubsub topics delete "$topic" \
                --quiet || log_warning "Failed to delete topic: $topic"
        done
        
        log_success "Pub/Sub topics cleanup completed"
    else
        log_info "No Pub/Sub topics found to delete"
    fi
}

# Function to delete VM instances
delete_vm_instances() {
    if [ -n "$INSTANCES" ]; then
        log_info "Deleting VM instances..."
        
        for instance in $INSTANCES; do
            log_info "Deleting VM instance: $instance"
            gcloud compute instances delete "$instance" \
                --zone="$ZONE" \
                --quiet || log_warning "Failed to delete instance: $instance"
        done
        
        log_success "VM instances cleanup completed"
    else
        log_info "No VM instances found to delete"
    fi
}

# Function to delete monitoring policies
delete_monitoring_policies() {
    if [ -n "$ALERT_POLICIES" ]; then
        log_info "Deleting monitoring alert policies..."
        
        for policy in $ALERT_POLICIES; do
            log_info "Deleting alert policy: $policy"
            gcloud alpha monitoring policies delete "$policy" \
                --quiet || log_warning "Failed to delete alert policy: $policy"
        done
        
        log_success "Monitoring policies cleanup completed"
    else
        log_info "No monitoring alert policies found to delete"
    fi
}

# Function to delete custom metrics
delete_custom_metrics() {
    if [ -n "$CUSTOM_METRICS" ]; then
        log_info "Deleting custom metrics..."
        
        for metric in $CUSTOM_METRICS; do
            log_info "Deleting custom metric: $metric"
            gcloud logging metrics delete "$metric" \
                --quiet || log_warning "Failed to delete custom metric: $metric"
        done
        
        log_success "Custom metrics cleanup completed"
    else
        log_info "No custom metrics found to delete"
    fi
}

# Function to delete dashboards
delete_dashboards() {
    if [ -n "$DASHBOARDS" ]; then
        log_info "Deleting monitoring dashboards..."
        
        for dashboard in $DASHBOARDS; do
            log_info "Deleting dashboard: $dashboard"
            gcloud monitoring dashboards delete "$dashboard" \
                --quiet || log_warning "Failed to delete dashboard: $dashboard"
        done
        
        log_success "Dashboards cleanup completed"
    else
        log_info "No dashboards found to delete"
    fi
}

# Function to clean up IAM permissions
cleanup_iam_permissions() {
    log_info "Cleaning up IAM permissions..."
    
    # Note: We don't remove IAM permissions as they might be used by other resources
    # In a production environment, you might want to audit and remove specific permissions
    
    log_info "IAM permissions cleanup skipped (manual review recommended)"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --region="$REGION" --format="value(name)" --filter="name:anomaly-detector" 2>/dev/null | wc -l)
    if [ "$remaining_functions" -gt 0 ]; then
        log_warning "$remaining_functions Cloud Functions still exist"
        remaining_resources=$((remaining_resources + remaining_functions))
    fi
    
    # Check for remaining Pub/Sub topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" --filter="name:monitoring-events" 2>/dev/null | wc -l)
    if [ "$remaining_topics" -gt 0 ]; then
        log_warning "$remaining_topics Pub/Sub topics still exist"
        remaining_resources=$((remaining_resources + remaining_topics))
    fi
    
    # Check for remaining VM instances
    local remaining_instances
    remaining_instances=$(gcloud compute instances list --zones="$ZONE" --format="value(name)" --filter="name:test-instance" 2>/dev/null | wc -l)
    if [ "$remaining_instances" -gt 0 ]; then
        log_warning "$remaining_instances VM instances still exist"
        remaining_resources=$((remaining_resources + remaining_instances))
    fi
    
    if [ "$remaining_resources" -eq 0 ]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "$remaining_resources resources may still exist - manual review recommended"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "=========================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "=========================="
    echo "Resources Processed:"
    echo "- Cloud Functions: ${FUNCTIONS:-"None found"}"
    echo "- Pub/Sub Topics: ${TOPICS:-"None found"}"
    echo "- Pub/Sub Subscriptions: ${SUBSCRIPTIONS:-"None found"}"
    echo "- VM Instances: ${INSTANCES:-"None found"}"
    echo "- Alert Policies: ${ALERT_POLICIES:-"None found"}"
    echo "- Custom Metrics: ${CUSTOM_METRICS:-"None found"}"
    echo "- Dashboards: ${DASHBOARDS:-"None found"}"
    echo "=========================="
    echo "Note: Some resources may take a few minutes to fully delete."
    echo "=========================="
    
    log_success "Infrastructure Anomaly Detection cleanup completed!"
}

# Function to handle cleanup with retry logic
safe_cleanup() {
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log_info "Cleanup attempt $((retry_count + 1))/$max_retries"
        
        # Delete resources in reverse order of creation
        delete_cloud_functions
        delete_pubsub_resources
        delete_vm_instances
        delete_monitoring_policies
        delete_custom_metrics
        delete_dashboards
        cleanup_iam_permissions
        
        # Check if cleanup was successful
        verify_cleanup
        
        if [ $? -eq 0 ]; then
            break
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warning "Retrying cleanup in 30 seconds..."
            sleep 30
        fi
    done
}

# Main execution
main() {
    log_info "Starting Infrastructure Anomaly Detection cleanup..."
    
    validate_prerequisites
    setup_environment
    confirm_cleanup
    discover_resources
    safe_cleanup
    display_cleanup_summary
    
    log_success "All cleanup steps completed!"
}

# Execute main function
main "$@"
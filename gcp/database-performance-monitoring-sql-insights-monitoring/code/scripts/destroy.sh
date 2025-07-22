#!/bin/bash

# Destroy script for Database Performance Monitoring with Cloud SQL Insights and Cloud Monitoring
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Some resources may still exist - check manually in the console"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo "=========================================================="
echo "Database Performance Monitoring Cleanup"
echo "Safely removing all created resources"
echo "=========================================================="

# Check prerequisites
log_info "Checking prerequisites..."

# Check if gcloud CLI is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    log_error "Not authenticated with Google Cloud"
    log_error "Please run: gcloud auth login"
    exit 1
fi

log_success "Prerequisites check completed"

# Function to prompt for project selection
select_project() {
    echo ""
    log_info "Available projects that may contain monitoring resources:"
    
    # List projects that match the naming pattern
    MATCHING_PROJECTS=$(gcloud projects list --filter="projectId:db-monitoring-*" --format="value(projectId)" 2>/dev/null || true)
    
    if [ -z "$MATCHING_PROJECTS" ]; then
        log_warning "No projects found matching 'db-monitoring-*' pattern"
        log_info "Please enter the project ID manually"
        read -p "Enter project ID to clean up: " PROJECT_ID
    else
        log_info "Found projects matching pattern:"
        echo "$MATCHING_PROJECTS" | nl
        echo ""
        read -p "Enter project ID to clean up (or select number): " selection
        
        # Check if it's a number
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            PROJECT_ID=$(echo "$MATCHING_PROJECTS" | sed -n "${selection}p")
            if [ -z "$PROJECT_ID" ]; then
                log_error "Invalid selection"
                exit 1
            fi
        else
            PROJECT_ID="$selection"
        fi
    fi
    
    export PROJECT_ID
    log_info "Selected project: $PROJECT_ID"
}

# Function to detect resources
detect_resources() {
    log_info "Detecting resources in project: $PROJECT_ID"
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    # Detect Cloud SQL instances
    SQL_INSTANCES=$(gcloud sql instances list --filter="name:performance-db-*" --format="value(name)" 2>/dev/null || true)
    
    # Detect Cloud Functions
    FUNCTIONS=$(gcloud functions list --filter="name:db-alert-handler-*" --format="value(name)" 2>/dev/null || true)
    
    # Detect Pub/Sub topics
    TOPICS=$(gcloud pubsub topics list --filter="name:db-alerts-*" --format="value(name)" 2>/dev/null || true)
    
    # Detect Storage buckets
    BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "db-reports-" | sed 's/gs:\/\///' | sed 's/\///' || true)
    
    # Detect monitoring dashboards
    DASHBOARDS=$(gcloud monitoring dashboards list --filter="displayName:'Cloud SQL Performance Monitoring Dashboard'" --format="value(name)" 2>/dev/null || true)
    
    # Detect alerting policies
    ALERT_POLICIES=$(gcloud alpha monitoring policies list --filter="displayName:('Cloud SQL High CPU Usage' OR 'Cloud SQL Slow Query Detection')" --format="value(name)" 2>/dev/null || true)
    
    # Detect notification channels
    NOTIFICATION_CHANNELS=$(gcloud alpha monitoring channels list --filter="displayName:'Database Alert Processing'" --format="value(name)" 2>/dev/null || true)
    
    # Display detected resources
    echo ""
    log_info "Detected resources to be removed:"
    
    if [ -n "$SQL_INSTANCES" ]; then
        echo "  Cloud SQL Instances:"
        echo "$SQL_INSTANCES" | sed 's/^/    - /'
    fi
    
    if [ -n "$FUNCTIONS" ]; then
        echo "  Cloud Functions:"
        echo "$FUNCTIONS" | sed 's/^/    - /' | sed 's|.*/||'
    fi
    
    if [ -n "$TOPICS" ]; then
        echo "  Pub/Sub Topics:"
        echo "$TOPICS" | sed 's/^/    - /' | sed 's|.*/||'
    fi
    
    if [ -n "$BUCKETS" ]; then
        echo "  Storage Buckets:"
        echo "$BUCKETS" | sed 's/^/    - /'
    fi
    
    if [ -n "$DASHBOARDS" ]; then
        echo "  Monitoring Dashboards:"
        echo "$DASHBOARDS" | sed 's/^/    - /' | sed 's|.*/||'
    fi
    
    if [ -n "$ALERT_POLICIES" ]; then
        echo "  Alert Policies:"
        echo "$ALERT_POLICIES" | sed 's/^/    - /' | sed 's|.*/||'
    fi
    
    if [ -n "$NOTIFICATION_CHANNELS" ]; then
        echo "  Notification Channels:"
        echo "$NOTIFICATION_CHANNELS" | sed 's/^/    - /' | sed 's|.*/||'
    fi
    
    if [ -z "$SQL_INSTANCES$FUNCTIONS$TOPICS$BUCKETS$DASHBOARDS$ALERT_POLICIES$NOTIFICATION_CHANNELS" ]; then
        log_warning "No monitoring resources detected in project $PROJECT_ID"
        log_info "The project may already be clean or resources were created with different names"
        exit 0
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    log_warning "WARNING: This will permanently delete all detected resources!"
    log_warning "This action cannot be undone."
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Do you also want to delete the entire project '$PROJECT_ID'? (y/N): " delete_project
    export DELETE_PROJECT="$delete_project"
}

# Function to remove notification channels
remove_notification_channels() {
    if [ -n "$NOTIFICATION_CHANNELS" ]; then
        log_info "Removing notification channels..."
        
        echo "$NOTIFICATION_CHANNELS" | while IFS= read -r channel; do
            if [ -n "$channel" ]; then
                log_info "Deleting notification channel: $(basename "$channel")"
                gcloud alpha monitoring channels delete "$channel" --quiet 2>/dev/null || log_warning "Failed to delete notification channel: $channel"
            fi
        done
        
        log_success "Notification channels removed"
    fi
}

# Function to remove alerting policies
remove_alert_policies() {
    if [ -n "$ALERT_POLICIES" ]; then
        log_info "Removing alerting policies..."
        
        echo "$ALERT_POLICIES" | while IFS= read -r policy; do
            if [ -n "$policy" ]; then
                log_info "Deleting alert policy: $(basename "$policy")"
                gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null || log_warning "Failed to delete alert policy: $policy"
            fi
        done
        
        log_success "Alert policies removed"
    fi
}

# Function to remove monitoring dashboards
remove_dashboards() {
    if [ -n "$DASHBOARDS" ]; then
        log_info "Removing monitoring dashboards..."
        
        echo "$DASHBOARDS" | while IFS= read -r dashboard; do
            if [ -n "$dashboard" ]; then
                log_info "Deleting dashboard: $(basename "$dashboard")"
                gcloud monitoring dashboards delete "$dashboard" --quiet 2>/dev/null || log_warning "Failed to delete dashboard: $dashboard"
            fi
        done
        
        log_success "Monitoring dashboards removed"
    fi
}

# Function to remove Cloud Functions
remove_functions() {
    if [ -n "$FUNCTIONS" ]; then
        log_info "Removing Cloud Functions..."
        
        # Extract region and function name from full resource name
        echo "$FUNCTIONS" | while IFS= read -r function_path; do
            if [ -n "$function_path" ]; then
                # Extract function name from path like projects/PROJECT/locations/REGION/functions/NAME
                function_name=$(basename "$function_path")
                log_info "Deleting Cloud Function: $function_name"
                gcloud functions delete "$function_name" --quiet 2>/dev/null || log_warning "Failed to delete function: $function_name"
            fi
        done
        
        log_success "Cloud Functions removed"
    fi
}

# Function to remove Pub/Sub topics
remove_topics() {
    if [ -n "$TOPICS" ]; then
        log_info "Removing Pub/Sub topics..."
        
        echo "$TOPICS" | while IFS= read -r topic; do
            if [ -n "$topic" ]; then
                topic_name=$(basename "$topic")
                log_info "Deleting Pub/Sub topic: $topic_name"
                gcloud pubsub topics delete "$topic_name" --quiet 2>/dev/null || log_warning "Failed to delete topic: $topic_name"
            fi
        done
        
        log_success "Pub/Sub topics removed"
    fi
}

# Function to remove Storage buckets
remove_storage_buckets() {
    if [ -n "$BUCKETS" ]; then
        log_info "Removing Cloud Storage buckets..."
        
        echo "$BUCKETS" | while IFS= read -r bucket; do
            if [ -n "$bucket" ]; then
                log_info "Deleting Storage bucket: $bucket"
                # Remove all objects first, then the bucket
                gsutil -m rm -r "gs://$bucket" 2>/dev/null || log_warning "Failed to delete bucket: $bucket"
            fi
        done
        
        log_success "Storage buckets removed"
    fi
}

# Function to remove Cloud SQL instances
remove_sql_instances() {
    if [ -n "$SQL_INSTANCES" ]; then
        log_info "Removing Cloud SQL instances..."
        log_warning "This may take several minutes..."
        
        echo "$SQL_INSTANCES" | while IFS= read -r instance; do
            if [ -n "$instance" ]; then
                log_info "Removing deletion protection from: $instance"
                gcloud sql instances patch "$instance" --no-deletion-protection --quiet 2>/dev/null || log_warning "Failed to remove deletion protection: $instance"
                
                log_info "Deleting Cloud SQL instance: $instance"
                gcloud sql instances delete "$instance" --quiet 2>/dev/null || log_warning "Failed to delete SQL instance: $instance"
            fi
        done
        
        log_success "Cloud SQL instances removal initiated"
    fi
}

# Function to remove entire project
remove_project() {
    if [[ "$DELETE_PROJECT" =~ ^[Yy]$ ]]; then
        log_warning "Deleting entire project: $PROJECT_ID"
        log_warning "This will remove ALL resources in the project, not just monitoring resources"
        
        read -p "Final confirmation - type 'DELETE PROJECT' to proceed: " final_confirm
        if [ "$final_confirm" = "DELETE PROJECT" ]; then
            log_info "Deleting project: $PROJECT_ID"
            gcloud projects delete "$PROJECT_ID" --quiet
            log_success "Project deletion initiated: $PROJECT_ID"
            log_info "Project deletion may take several minutes to complete"
        else
            log_info "Project deletion cancelled"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove temporary files that might have been created
    rm -f /tmp/deployment-info.txt 2>/dev/null || true
    rm -f /tmp/test_data.sql 2>/dev/null || true
    rm -f /tmp/dashboard-config.json 2>/dev/null || true
    rm -f /tmp/*alert-policy.json 2>/dev/null || true
    rm -rf /tmp/db-alert-function 2>/dev/null || true
    
    # Remove from home directory if it exists
    rm -f "$HOME/db-monitoring-deployment-info.txt" 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Function to display final status
show_cleanup_summary() {
    echo ""
    echo "=========================================================="
    log_success "Cleanup Process Completed"
    echo "=========================================================="
    echo ""
    
    if [[ "$DELETE_PROJECT" =~ ^[Yy]$ ]]; then
        log_info "Project deletion has been initiated: $PROJECT_ID"
        log_info "All resources will be automatically removed with the project"
    else
        log_info "The following resource types were processed:"
        log_info "  ✅ Notification channels"
        log_info "  ✅ Alert policies"
        log_info "  ✅ Monitoring dashboards"
        log_info "  ✅ Cloud Functions"
        log_info "  ✅ Pub/Sub topics"
        log_info "  ✅ Cloud Storage buckets"
        log_info "  ✅ Cloud SQL instances"
        log_info "  ✅ Local temporary files"
    fi
    
    echo ""
    log_warning "Please verify in the Google Cloud Console that all resources have been removed"
    log_warning "Some resources (especially Cloud SQL) may take additional time to complete deletion"
    
    if [[ ! "$DELETE_PROJECT" =~ ^[Yy]$ ]]; then
        echo ""
        log_info "Console URLs to verify cleanup:"
        log_info "  Cloud SQL: https://console.cloud.google.com/sql/instances?project=$PROJECT_ID"
        log_info "  Cloud Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
        log_info "  Monitoring: https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
        log_info "  Storage: https://console.cloud.google.com/storage/browser?project=$PROJECT_ID"
        log_info "  Pub/Sub: https://console.cloud.google.com/cloudpubsub/topic/list?project=$PROJECT_ID"
    fi
    
    echo ""
    log_success "Database Performance Monitoring cleanup completed successfully!"
}

# Main execution flow
main() {
    # Get project to clean up
    select_project
    
    # Detect existing resources
    detect_resources
    
    # Confirm deletion
    confirm_deletion
    
    echo ""
    log_info "Starting cleanup process..."
    
    # Remove resources in reverse order of dependencies
    remove_notification_channels
    remove_alert_policies
    remove_dashboards
    remove_functions
    remove_topics
    remove_storage_buckets
    remove_sql_instances
    
    # Remove project if requested
    remove_project
    
    # Clean up local files
    cleanup_local_files
    
    # Show summary
    show_cleanup_summary
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Cleanup interrupted by user"
    log_warning "Some resources may still exist - run the script again to complete cleanup"
    exit 1
}

trap cleanup_on_exit INT TERM

# Run main function
main

exit 0
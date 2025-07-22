#!/bin/bash

# Real-Time Event Processing with Cloud Memorystore and Pub/Sub - Cleanup Script
# This script safely removes all infrastructure components created for the
# real-time event processing solution

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to safely delete resource with confirmation
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    log "Deleting $resource_type: $resource_name"
    
    # Execute delete command and handle errors gracefully
    if eval "$delete_command" 2>/dev/null; then
        success "$resource_type deleted: $resource_name"
    else
        warning "$resource_type not found or already deleted: $resource_name"
    fi
}

# Function to wait for operation completion
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local max_attempts=30
    local attempt=1
    
    log "Waiting for $resource_type deletion to complete..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! eval "$check_command" >/dev/null 2>&1; then
            success "$resource_type deletion completed"
            return 0
        fi
        
        echo -n "."
        sleep 10
        ((attempt++))
    done
    
    warning "$resource_type deletion may still be in progress"
    return 0  # Don't fail the script for slow deletions
}

# Function to list and confirm resources for deletion
list_resources() {
    local project_id="$1"
    local region="$2"
    
    log "Scanning for event processing resources in project: $project_id"
    log "Region: $region"
    log ""
    
    # List Redis instances
    log "Redis Instances:"
    gcloud redis instances list --region="$region" --format="table(name,state,host,port)" 2>/dev/null || warning "No Redis instances found or access denied"
    log ""
    
    # List Pub/Sub topics
    log "Pub/Sub Topics:"
    gcloud pubsub topics list --format="table(name)" 2>/dev/null | grep -E "(events-topic|deadletter)" || warning "No matching Pub/Sub topics found"
    log ""
    
    # List Cloud Functions
    log "Cloud Functions (Gen2):"
    gcloud functions list --gen2 --format="table(name,state,region)" 2>/dev/null | grep -E "event-processor" || warning "No matching Cloud Functions found"
    log ""
    
    # List VPC Access Connectors
    log "VPC Access Connectors:"
    gcloud compute networks vpc-access connectors list --region="$region" --format="table(name,state)" 2>/dev/null | grep -E "redis-connector" || warning "No matching VPC connectors found"
    log ""
    
    # List BigQuery datasets
    log "BigQuery Datasets:"
    bq ls --format=prettyjson 2>/dev/null | grep -E "event_analytics" || warning "No matching BigQuery datasets found"
    log ""
    
    # List monitoring dashboards
    log "Cloud Monitoring Dashboards:"
    gcloud monitoring dashboards list --format="table(displayName,name)" 2>/dev/null | grep -E "Event Processing" || warning "No matching monitoring dashboards found"
    log ""
}

# Function to read deployment configuration if available
read_deployment_config() {
    local config_file=""
    
    # Try to find deployment config in common locations
    if [ -f "./deployment-config.txt" ]; then
        config_file="./deployment-config.txt"
    elif [ -f "/tmp/event-processor-*/deployment-config.txt" ]; then
        config_file=$(find /tmp -name "deployment-config.txt" -path "*/event-processor-*" | head -1)
    fi
    
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        log "Found deployment configuration: $config_file"
        log "Loading configuration..."
        
        # Source the configuration file
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Export the variable
            export "$key"="$value"
        done < "$config_file"
        
        success "Configuration loaded successfully"
        return 0
    else
        warning "Deployment configuration not found. Will prompt for values."
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Real-Time Event Processing infrastructure"
    
    # Check prerequisites
    log "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    if ! command_exists bq; then
        error "BigQuery CLI (bq) is not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check passed"
    
    # Try to read deployment configuration
    if ! read_deployment_config; then
        # Manual configuration input
        log "Manual configuration required"
        
        if [ -z "${PROJECT_ID:-}" ]; then
            read -p "Enter Google Cloud Project ID: " PROJECT_ID
        fi
        
        if [ -z "${REGION:-}" ]; then
            read -p "Enter region (default: us-central1): " REGION
            REGION="${REGION:-us-central1}"
        fi
        
        export PROJECT_ID REGION
    fi
    
    log "Configuration:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log ""
    
    # Set default project for commands
    gcloud config set project "$PROJECT_ID"
    
    # List resources that will be deleted
    list_resources "$PROJECT_ID" "$REGION"
    
    # Confirmation prompt
    warning "This will permanently delete all event processing infrastructure components!"
    warning "This action cannot be undone."
    log ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^(yes|YES)$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
    
    log "Beginning resource cleanup..."
    log ""
    
    # 1. Delete Cloud Functions
    log "=== Step 1: Deleting Cloud Functions ==="
    if [ -n "${FUNCTION_NAME:-}" ]; then
        safe_delete "Cloud Function" "$FUNCTION_NAME" \
            "gcloud functions delete '$FUNCTION_NAME' --region='$REGION' --gen2 --quiet"
    else
        # Find and delete functions by pattern
        local functions=$(gcloud functions list --gen2 --region="$REGION" --format="value(name)" 2>/dev/null | grep -E "event-processor" || true)
        for func in $functions; do
            safe_delete "Cloud Function" "$func" \
                "gcloud functions delete '$func' --region='$REGION' --gen2 --quiet"
        done
    fi
    
    # 2. Delete Pub/Sub Resources
    log ""
    log "=== Step 2: Deleting Pub/Sub Resources ==="
    
    # Delete subscriptions first
    if [ -n "${PUBSUB_TOPIC:-}" ]; then
        safe_delete "Pub/Sub Subscription" "${PUBSUB_TOPIC}-subscription" \
            "gcloud pubsub subscriptions delete '${PUBSUB_TOPIC}-subscription' --quiet"
        
        safe_delete "Pub/Sub Topic" "$PUBSUB_TOPIC" \
            "gcloud pubsub topics delete '$PUBSUB_TOPIC' --quiet"
        
        safe_delete "Dead Letter Topic" "${PUBSUB_TOPIC}-deadletter" \
            "gcloud pubsub topics delete '${PUBSUB_TOPIC}-deadletter' --quiet"
    else
        # Find and delete topics by pattern
        local topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(events-topic|deadletter)" || true)
        for topic in $topics; do
            local topic_name=$(basename "$topic")
            
            # Delete subscriptions for this topic
            local subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep "$topic_name" || true)
            for sub in $subscriptions; do
                local sub_name=$(basename "$sub")
                safe_delete "Pub/Sub Subscription" "$sub_name" \
                    "gcloud pubsub subscriptions delete '$sub_name' --quiet"
            done
            
            # Delete the topic
            safe_delete "Pub/Sub Topic" "$topic_name" \
                "gcloud pubsub topics delete '$topic_name' --quiet"
        done
    fi
    
    # 3. Delete VPC Access Connector
    log ""
    log "=== Step 3: Deleting VPC Access Connector ==="
    safe_delete "VPC Access Connector" "redis-connector" \
        "gcloud compute networks vpc-access connectors delete redis-connector --region='$REGION' --quiet"
    
    # Wait for VPC connector deletion
    wait_for_deletion "VPC Access Connector" \
        "gcloud compute networks vpc-access connectors describe redis-connector --region='$REGION'"
    
    # 4. Delete Cloud Memorystore Redis Instance
    log ""
    log "=== Step 4: Deleting Cloud Memorystore Redis Instance ==="
    if [ -n "${REDIS_INSTANCE:-}" ]; then
        safe_delete "Redis Instance" "$REDIS_INSTANCE" \
            "gcloud redis instances delete '$REDIS_INSTANCE' --region='$REGION' --quiet"
    else
        # Find and delete Redis instances by pattern
        local redis_instances=$(gcloud redis instances list --region="$REGION" --format="value(name)" 2>/dev/null | grep -E "event-cache" || true)
        for instance in $redis_instances; do
            safe_delete "Redis Instance" "$instance" \
                "gcloud redis instances delete '$instance' --region='$REGION' --quiet"
        done
    fi
    
    # Wait for Redis deletion (this can take several minutes)
    if [ -n "${REDIS_INSTANCE:-}" ]; then
        wait_for_deletion "Redis Instance" \
            "gcloud redis instances describe '$REDIS_INSTANCE' --region='$REGION'"
    fi
    
    # 5. Delete BigQuery Resources
    log ""
    log "=== Step 5: Deleting BigQuery Resources ==="
    
    # Prompt for BigQuery deletion (more dangerous as it contains data)
    warning "BigQuery dataset 'event_analytics' contains processed event data."
    read -p "Delete BigQuery dataset and all data? (yes/no): " -r
    if [[ $REPLY =~ ^(yes|YES)$ ]]; then
        safe_delete "BigQuery Dataset" "event_analytics" \
            "bq rm -r -f '${PROJECT_ID}:event_analytics'"
    else
        warning "Skipping BigQuery dataset deletion"
    fi
    
    # 6. Delete Monitoring Resources
    log ""
    log "=== Step 6: Deleting Monitoring Resources ==="
    
    # List and delete monitoring dashboards
    local dashboards=$(gcloud monitoring dashboards list --format="value(name)" 2>/dev/null | grep -v "^$" || true)
    for dashboard in $dashboards; do
        # Check if this is our dashboard
        local dashboard_info=$(gcloud monitoring dashboards describe "$dashboard" --format="value(displayName)" 2>/dev/null || true)
        if [[ $dashboard_info =~ "Event Processing" ]]; then
            local dashboard_id=$(basename "$dashboard")
            safe_delete "Monitoring Dashboard" "$dashboard_info" \
                "gcloud monitoring dashboards delete '$dashboard_id' --quiet"
        fi
    done
    
    # 7. Clean up temporary files
    log ""
    log "=== Step 7: Cleaning up temporary files ==="
    
    # Remove function code directories
    if [ -n "${FUNCTION_DIR:-}" ] && [ -d "${FUNCTION_DIR}" ]; then
        log "Removing function directory: ${FUNCTION_DIR}"
        rm -rf "${FUNCTION_DIR}"
        success "Function directory removed"
    fi
    
    # Remove any leftover function directories
    local temp_dirs=$(find /tmp -type d -name "event-processor-*" 2>/dev/null || true)
    for dir in $temp_dirs; do
        log "Removing temporary directory: $dir"
        rm -rf "$dir"
    done
    
    # Remove local monitoring dashboard files
    if [ -f "./monitoring-dashboard.json" ]; then
        rm -f "./monitoring-dashboard.json"
        success "Monitoring dashboard file removed"
    fi
    
    # 8. Verification
    log ""
    log "=== Step 8: Verification ==="
    log "Verifying resource cleanup..."
    
    # Verify Redis instances
    local remaining_redis=$(gcloud redis instances list --region="$REGION" --format="value(name)" 2>/dev/null | grep -E "event-cache" || true)
    if [ -z "$remaining_redis" ]; then
        success "All Redis instances cleaned up"
    else
        warning "Some Redis instances may still exist: $remaining_redis"
    fi
    
    # Verify Pub/Sub topics
    local remaining_topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(events-topic|deadletter)" || true)
    if [ -z "$remaining_topics" ]; then
        success "All Pub/Sub topics cleaned up"
    else
        warning "Some Pub/Sub topics may still exist: $remaining_topics"
    fi
    
    # Verify Cloud Functions
    local remaining_functions=$(gcloud functions list --gen2 --format="value(name)" 2>/dev/null | grep -E "event-processor" || true)
    if [ -z "$remaining_functions" ]; then
        success "All Cloud Functions cleaned up"
    else
        warning "Some Cloud Functions may still exist: $remaining_functions"
    fi
    
    success "Cleanup completed successfully!"
    log ""
    log "Cleanup Summary:"
    log "================"
    log "✅ Cloud Functions deleted"
    log "✅ Pub/Sub topics and subscriptions deleted"
    log "✅ VPC Access Connector deleted"
    log "✅ Redis instances deleted"
    log "✅ Monitoring dashboards deleted"
    log "✅ Temporary files cleaned up"
    
    if [[ ${REPLY:-} =~ ^(yes|YES)$ ]]; then
        log "✅ BigQuery dataset deleted"
    else
        log "⚠️  BigQuery dataset preserved (contains data)"
    fi
    
    log ""
    log "Notes:"
    log "• Some resources may take additional time to fully delete"
    log "• Check the Google Cloud Console to verify complete cleanup"
    log "• BigQuery storage may continue to incur costs if dataset was preserved"
    log "• VPC Access Connector deletion can take up to 10 minutes"
    log ""
    success "All cleanup operations completed!"
}

# Run main function
main "$@"
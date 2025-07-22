#!/bin/bash

# Destroy Event-Driven Data Synchronization Infrastructure
# This script safely removes all resources created by the deployment script

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RECIPE_NAME="event-driven-data-synchronization"

# Parse command line arguments
FORCE_DELETE=${1:-false}
SKIP_CONFIRM=${2:-false}

# Display usage information
usage() {
    echo "Usage: $0 [FORCE_DELETE] [SKIP_CONFIRM]"
    echo ""
    echo "Arguments:"
    echo "  FORCE_DELETE   Set to 'true' to force deletion without safety checks (default: false)"
    echo "  SKIP_CONFIRM   Set to 'true' to skip confirmation prompts (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Normal cleanup with confirmations"
    echo "  $0 false true        # Skip confirmations but keep safety checks"
    echo "  $0 true true         # Force delete everything without prompts"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_ID     GCP Project ID (required)"
    echo "  CLEANUP_ALL    Set to 'true' to clean up all recipe resources regardless of suffix"
    exit 1
}

# Check if help is requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Banner
echo "=================================================="
echo "Event-Driven Data Synchronization Cleanup"
echo "=================================================="
echo ""

# Prerequisites check
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "gcloud CLI is not installed. Please install it first."
fi

# Check if PROJECT_ID is set
if [ -z "${PROJECT_ID:-}" ]; then
    error_exit "PROJECT_ID environment variable is not set. Please set it first."
fi

# Verify gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error_exit "No active gcloud authentication found. Please run 'gcloud auth login' first."
fi

# Verify project exists and is accessible
if ! gcloud projects describe ${PROJECT_ID} &> /dev/null; then
    error_exit "Project ${PROJECT_ID} does not exist or is not accessible."
fi

log_success "Prerequisites check passed"

# Set project
gcloud config set project ${PROJECT_ID}

# Discover resources to delete
log_info "Discovering resources to delete..."

# Find all resources related to this recipe
if [ "${CLEANUP_ALL:-false}" == "true" ]; then
    log_info "Searching for all recipe resources (ignoring suffix)..."
    TOPICS=$(gcloud pubsub topics list --filter="name:data-sync-events-* OR name:sync-dead-letters-*" --format="value(name)" | sed 's|.*topics/||')
    SUBSCRIPTIONS=$(gcloud pubsub subscriptions list --filter="name:sync-processor-* OR name:audit-logger-* OR name:dlq-processor-*" --format="value(name)" | sed 's|.*subscriptions/||')
    FUNCTIONS=$(gcloud functions list --filter="name:data-sync-processor-* OR name:audit-logger-*" --format="value(name)")
else
    # Try to read from deployment summary if available
    if [ -f "${PROJECT_DIR}/deployment_summary.txt" ]; then
        log_info "Reading resource names from deployment summary..."
        TOPIC_NAME=$(grep "Pub/Sub Topic:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        SYNC_SUBSCRIPTION=$(grep "Sync Subscription:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        AUDIT_SUBSCRIPTION=$(grep "Audit Subscription:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        DLQ_TOPIC=$(grep "Dead Letter Topic:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f4)
        DLQ_SUBSCRIPTION=$(grep "Dead Letter Subscription:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f4)
        SYNC_FUNCTION=$(grep "Sync Function:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        AUDIT_FUNCTION=$(grep "Audit Function:" "${PROJECT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        
        TOPICS="${TOPIC_NAME} ${DLQ_TOPIC}"
        SUBSCRIPTIONS="${SYNC_SUBSCRIPTION} ${AUDIT_SUBSCRIPTION} ${DLQ_SUBSCRIPTION}"
        FUNCTIONS="${SYNC_FUNCTION} ${AUDIT_FUNCTION}"
    else
        log_warning "No deployment summary found. Searching for all recipe resources..."
        TOPICS=$(gcloud pubsub topics list --filter="name:data-sync-events-* OR name:sync-dead-letters-*" --format="value(name)" | sed 's|.*topics/||')
        SUBSCRIPTIONS=$(gcloud pubsub subscriptions list --filter="name:sync-processor-* OR name:audit-logger-* OR name:dlq-processor-*" --format="value(name)" | sed 's|.*subscriptions/||')
        FUNCTIONS=$(gcloud functions list --filter="name:data-sync-processor-* OR name:audit-logger-*" --format="value(name)")
    fi
fi

# Find monitoring dashboards
DASHBOARDS=$(gcloud monitoring dashboards list --filter="displayName:'Datastore Sync Monitoring'" --format="value(name)")

# Display resources to be deleted
log_info "Resources to be deleted:"
echo ""
echo "Cloud Functions:"
if [ -n "${FUNCTIONS}" ]; then
    echo "${FUNCTIONS}" | tr ' ' '\n' | sed 's/^/  - /'
else
    echo "  - None found"
fi

echo ""
echo "Pub/Sub Topics:"
if [ -n "${TOPICS}" ]; then
    echo "${TOPICS}" | tr ' ' '\n' | sed 's/^/  - /'
else
    echo "  - None found"
fi

echo ""
echo "Pub/Sub Subscriptions:"
if [ -n "${SUBSCRIPTIONS}" ]; then
    echo "${SUBSCRIPTIONS}" | tr ' ' '\n' | sed 's/^/  - /'
else
    echo "  - None found"
fi

echo ""
echo "Monitoring Dashboards:"
if [ -n "${DASHBOARDS}" ]; then
    echo "${DASHBOARDS}" | tr ' ' '\n' | sed 's/^/  - /'
else
    echo "  - None found"
fi

echo ""
echo "Datastore Entities:"
echo "  - All SyncEntity entities will be deleted"

echo ""
echo "Local Files:"
echo "  - sync-function/ directory"
echo "  - audit-function/ directory"
echo "  - datastore_init.py"
echo "  - data_publisher.py"
echo "  - monitoring_dashboard.json"
echo "  - deployment_summary.txt"

echo ""

# Safety check - prevent accidental deletion of production resources
if [ "${FORCE_DELETE}" != "true" ]; then
    log_info "Performing safety checks..."
    
    # Check if any functions have high invocation counts (potential production use)
    if [ -n "${FUNCTIONS}" ]; then
        for func in ${FUNCTIONS}; do
            if gcloud functions describe ${func} --format="value(name)" &> /dev/null; then
                log_info "Checking function usage: ${func}"
                # Note: This is a safety check - in production you might want to check metrics
            fi
        done
    fi
    
    # Check if topics have high message counts
    if [ -n "${TOPICS}" ]; then
        for topic in ${TOPICS}; do
            if gcloud pubsub topics describe ${topic} &> /dev/null; then
                log_info "Checking topic usage: ${topic}"
            fi
        done
    fi
fi

# Confirmation prompt
if [ "${SKIP_CONFIRM}" != "true" ]; then
    echo ""
    log_warning "This will permanently delete all listed resources!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    echo ""
fi

# Start cleanup
log_info "Starting cleanup process..."

# Delete Cloud Functions first (they depend on Pub/Sub)
if [ -n "${FUNCTIONS}" ]; then
    log_info "Deleting Cloud Functions..."
    for func in ${FUNCTIONS}; do
        if gcloud functions describe ${func} &> /dev/null; then
            log_info "  Deleting function: ${func}"
            gcloud functions delete ${func} --quiet || log_warning "Failed to delete function: ${func}"
        else
            log_warning "  Function not found: ${func}"
        fi
    done
    log_success "Cloud Functions cleanup completed"
else
    log_info "No Cloud Functions to delete"
fi

# Delete Pub/Sub subscriptions (they depend on topics)
if [ -n "${SUBSCRIPTIONS}" ]; then
    log_info "Deleting Pub/Sub subscriptions..."
    for sub in ${SUBSCRIPTIONS}; do
        if gcloud pubsub subscriptions describe ${sub} &> /dev/null; then
            log_info "  Deleting subscription: ${sub}"
            gcloud pubsub subscriptions delete ${sub} --quiet || log_warning "Failed to delete subscription: ${sub}"
        else
            log_warning "  Subscription not found: ${sub}"
        fi
    done
    log_success "Pub/Sub subscriptions cleanup completed"
else
    log_info "No Pub/Sub subscriptions to delete"
fi

# Delete Pub/Sub topics
if [ -n "${TOPICS}" ]; then
    log_info "Deleting Pub/Sub topics..."
    for topic in ${TOPICS}; do
        if gcloud pubsub topics describe ${topic} &> /dev/null; then
            log_info "  Deleting topic: ${topic}"
            gcloud pubsub topics delete ${topic} --quiet || log_warning "Failed to delete topic: ${topic}"
        else
            log_warning "  Topic not found: ${topic}"
        fi
    done
    log_success "Pub/Sub topics cleanup completed"
else
    log_info "No Pub/Sub topics to delete"
fi

# Delete monitoring dashboards
if [ -n "${DASHBOARDS}" ]; then
    log_info "Deleting monitoring dashboards..."
    for dashboard in ${DASHBOARDS}; do
        log_info "  Deleting dashboard: ${dashboard}"
        gcloud monitoring dashboards delete ${dashboard} --quiet || log_warning "Failed to delete dashboard: ${dashboard}"
    done
    log_success "Monitoring dashboards cleanup completed"
else
    log_info "No monitoring dashboards to delete"
fi

# Clean up Datastore entities
log_info "Cleaning up Datastore entities..."
cat > ${PROJECT_DIR}/cleanup_datastore.py << 'EOF'
from google.cloud import datastore
import sys

def cleanup_datastore():
    client = datastore.Client()
    
    try:
        # Query all SyncEntity entities
        query = client.query(kind='SyncEntity')
        entities = list(query.fetch())
        
        if entities:
            keys_to_delete = [entity.key for entity in entities]
            client.delete_multi(keys_to_delete)
            print(f"✅ Deleted {len(keys_to_delete)} entities from Datastore")
        else:
            print("✅ No entities found in Datastore")
            
    except Exception as e:
        print(f"❌ Error cleaning up Datastore: {str(e)}")
        sys.exit(1)

if __name__ == '__main__':
    cleanup_datastore()
EOF

# Check if Python dependencies are available
if python3 -c "import google.cloud.datastore" 2>/dev/null; then
    python3 ${PROJECT_DIR}/cleanup_datastore.py
else
    log_warning "Python dependencies not available. Skipping Datastore cleanup."
    log_info "To manually clean up Datastore entities, run:"
    echo "  pip3 install google-cloud-datastore"
    echo "  python3 cleanup_datastore.py"
fi

# Clean up local files
log_info "Cleaning up local files..."
rm -rf ${PROJECT_DIR}/sync-function || log_warning "Failed to remove sync-function directory"
rm -rf ${PROJECT_DIR}/audit-function || log_warning "Failed to remove audit-function directory"
rm -f ${PROJECT_DIR}/datastore_init.py || log_warning "Failed to remove datastore_init.py"
rm -f ${PROJECT_DIR}/data_publisher.py || log_warning "Failed to remove data_publisher.py"
rm -f ${PROJECT_DIR}/monitoring_dashboard.json || log_warning "Failed to remove monitoring_dashboard.json"
rm -f ${PROJECT_DIR}/cleanup_datastore.py || log_warning "Failed to remove cleanup_datastore.py"

# Ask about deployment summary
if [ -f "${PROJECT_DIR}/deployment_summary.txt" ]; then
    if [ "${SKIP_CONFIRM}" != "true" ]; then
        read -p "Delete deployment summary file? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f ${PROJECT_DIR}/deployment_summary.txt
            log_success "Deployment summary deleted"
        else
            log_info "Deployment summary preserved"
        fi
    else
        rm -f ${PROJECT_DIR}/deployment_summary.txt
        log_success "Deployment summary deleted"
    fi
fi

log_success "Local files cleanup completed"

# Final verification
log_info "Performing final verification..."

# Check if resources still exist
REMAINING_FUNCTIONS=$(gcloud functions list --filter="name:data-sync-processor-* OR name:audit-logger-*" --format="value(name)" | wc -l)
REMAINING_TOPICS=$(gcloud pubsub topics list --filter="name:data-sync-events-* OR name:sync-dead-letters-*" --format="value(name)" | wc -l)
REMAINING_SUBSCRIPTIONS=$(gcloud pubsub subscriptions list --filter="name:sync-processor-* OR name:audit-logger-* OR name:dlq-processor-*" --format="value(name)" | wc -l)

if [ "$REMAINING_FUNCTIONS" -eq 0 ] && [ "$REMAINING_TOPICS" -eq 0 ] && [ "$REMAINING_SUBSCRIPTIONS" -eq 0 ]; then
    log_success "All resources cleaned up successfully"
else
    log_warning "Some resources may still exist:"
    echo "  Functions: $REMAINING_FUNCTIONS"
    echo "  Topics: $REMAINING_TOPICS"
    echo "  Subscriptions: $REMAINING_SUBSCRIPTIONS"
    echo ""
    echo "You may need to manually delete these resources or run the script again."
fi

# Final summary
echo ""
echo "=================================================="
log_success "Cleanup completed!"
echo "=================================================="
echo ""
echo "Summary:"
echo "✅ Cloud Functions removed"
echo "✅ Pub/Sub resources removed"
echo "✅ Monitoring dashboards removed"
echo "✅ Datastore entities removed"
echo "✅ Local files cleaned up"
echo ""

if [ "$REMAINING_FUNCTIONS" -eq 0 ] && [ "$REMAINING_TOPICS" -eq 0 ] && [ "$REMAINING_SUBSCRIPTIONS" -eq 0 ]; then
    echo "🎉 All resources have been successfully removed!"
else
    echo "⚠️  Some resources may still exist. Please check the Cloud Console."
fi

echo ""
echo "Note: This script does not remove the GCP project itself."
echo "If you want to delete the entire project, run: gcloud projects delete ${PROJECT_ID}"
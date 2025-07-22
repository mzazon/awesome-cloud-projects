#!/bin/bash

# Deploy Event-Driven Data Synchronization with Cloud Datastore and Cloud Pub/Sub
# This script deploys the complete infrastructure for the event-driven data synchronization recipe

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

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up resources..."
    # Only clean up resources that were created in this session
    if [ ! -z "${TOPIC_NAME:-}" ]; then
        gcloud pubsub topics delete ${TOPIC_NAME} --quiet 2>/dev/null || true
    fi
    if [ ! -z "${SYNC_SUBSCRIPTION:-}" ]; then
        gcloud pubsub subscriptions delete ${SYNC_SUBSCRIPTION} --quiet 2>/dev/null || true
    fi
    if [ ! -z "${AUDIT_SUBSCRIPTION:-}" ]; then
        gcloud pubsub subscriptions delete ${AUDIT_SUBSCRIPTION} --quiet 2>/dev/null || true
    fi
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RECIPE_NAME="event-driven-data-synchronization"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Parse command line arguments
REGION=${1:-$DEFAULT_REGION}
ZONE=${2:-$DEFAULT_ZONE}
DRY_RUN=${3:-false}

# Display usage information
usage() {
    echo "Usage: $0 [REGION] [ZONE] [DRY_RUN]"
    echo ""
    echo "Arguments:"
    echo "  REGION     GCP region (default: $DEFAULT_REGION)"
    echo "  ZONE       GCP zone (default: $DEFAULT_ZONE)"
    echo "  DRY_RUN    Set to 'true' to preview changes without deploying (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 us-east1 us-east1-b              # Deploy to specific region/zone"
    echo "  $0 us-central1 us-central1-a true   # Dry run mode"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_ID     GCP Project ID (required)"
    echo "  SKIP_CONFIRM   Set to 'true' to skip confirmation prompts"
    exit 1
}

# Check if help is requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Banner
echo "=================================================="
echo "Event-Driven Data Synchronization Deployment"
echo "=================================================="
echo ""

# Prerequisites check
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "gcloud CLI is not installed. Please install it first."
fi

# Check if python3 is installed
if ! command -v python3 &> /dev/null; then
    error_exit "Python 3 is not installed. Please install it first."
fi

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    error_exit "pip3 is not installed. Please install it first."
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

# Set environment variables
export REGION=${REGION}
export ZONE=${ZONE}
export PROJECT_ID=${PROJECT_ID}

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3)
export RANDOM_SUFFIX=${RANDOM_SUFFIX}

# Set resource names
export TOPIC_NAME="data-sync-events-${RANDOM_SUFFIX}"
export SYNC_SUBSCRIPTION="sync-processor-${RANDOM_SUFFIX}"
export AUDIT_SUBSCRIPTION="audit-logger-${RANDOM_SUFFIX}"
export SYNC_FUNCTION="data-sync-processor-${RANDOM_SUFFIX}"
export AUDIT_FUNCTION="audit-logger-${RANDOM_SUFFIX}"
export DLQ_TOPIC="sync-dead-letters-${RANDOM_SUFFIX}"
export DLQ_SUBSCRIPTION="dlq-processor-${RANDOM_SUFFIX}"

# Display configuration
log_info "Deployment Configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Resource Suffix: ${RANDOM_SUFFIX}"
echo "  Dry Run: ${DRY_RUN}"
echo ""

# Confirmation prompt
if [ "${SKIP_CONFIRM:-false}" != "true" ] && [ "${DRY_RUN}" != "true" ]; then
    read -p "Do you want to continue with deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user."
        exit 0
    fi
fi

# Dry run mode
if [ "${DRY_RUN}" == "true" ]; then
    log_info "DRY RUN MODE - No resources will be created"
    log_info "The following resources would be created:"
    echo "  - Pub/Sub Topic: ${TOPIC_NAME}"
    echo "  - Pub/Sub Subscriptions: ${SYNC_SUBSCRIPTION}, ${AUDIT_SUBSCRIPTION}"
    echo "  - Cloud Functions: ${SYNC_FUNCTION}, ${AUDIT_FUNCTION}"
    echo "  - Dead Letter Queue: ${DLQ_TOPIC}, ${DLQ_SUBSCRIPTION}"
    echo "  - Monitoring Dashboard: Datastore Sync Monitoring"
    exit 0
fi

# Start deployment
log_info "Starting deployment..."

# Configure gcloud defaults
log_info "Configuring gcloud defaults..."
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs
log_info "Enabling required APIs..."
gcloud services enable datastore.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com

log_success "APIs enabled successfully"

# Create Pub/Sub topic
log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
gcloud pubsub topics create ${TOPIC_NAME}

# Create subscriptions
log_info "Creating Pub/Sub subscriptions..."
gcloud pubsub subscriptions create ${SYNC_SUBSCRIPTION} \
    --topic=${TOPIC_NAME} \
    --ack-deadline=60 \
    --message-retention-duration=7d

gcloud pubsub subscriptions create ${AUDIT_SUBSCRIPTION} \
    --topic=${TOPIC_NAME} \
    --ack-deadline=30 \
    --message-retention-duration=14d

log_success "Pub/Sub infrastructure created"

# Initialize Datastore
log_info "Initializing Datastore..."
cat > ${PROJECT_DIR}/datastore_init.py << 'EOF'
from google.cloud import datastore
import json
import sys

def initialize_datastore():
    client = datastore.Client()
    
    # Create initial entity with metadata
    key = client.key('SyncEntity', 'init-entity')
    entity = datastore.Entity(key=key)
    entity.update({
        'name': 'initialization',
        'status': 'active',
        'created_at': datastore.helpers.utcnow(),
        'version': 1,
        'sync_status': 'pending'
    })
    
    client.put(entity)
    print(f"✅ Datastore initialized with entity: {key.name}")

if __name__ == '__main__':
    initialize_datastore()
EOF

# Install Python dependencies
log_info "Installing Python dependencies..."
pip3 install google-cloud-datastore google-cloud-pubsub google-cloud-logging --quiet

# Initialize Datastore
python3 ${PROJECT_DIR}/datastore_init.py

log_success "Datastore initialized"

# Create sync function
log_info "Creating synchronization function..."
mkdir -p ${PROJECT_DIR}/sync-function
cd ${PROJECT_DIR}/sync-function

cat > main.py << 'EOF'
import base64
import json
import logging
from google.cloud import datastore
from google.cloud import pubsub_v1
import functions_framework

# Initialize clients
datastore_client = datastore.Client()
publisher = pubsub_v1.PublisherClient()

@functions_framework.cloud_event
def sync_processor(cloud_event):
    """Process data synchronization events with conflict resolution."""
    
    # Decode Pub/Sub message
    message_data = base64.b64decode(cloud_event.data["message"]["data"])
    event_data = json.loads(message_data.decode('utf-8'))
    
    logging.info(f"Processing sync event: {event_data}")
    
    try:
        # Extract event information
        entity_id = event_data.get('entity_id')
        operation = event_data.get('operation')  # create, update, delete
        data = event_data.get('data', {})
        timestamp = event_data.get('timestamp')
        
        # Implement conflict resolution logic
        if operation in ['create', 'update']:
            result = handle_data_operation(entity_id, operation, data, timestamp)
            
            # Publish success event for external systems
            if result['success']:
                publish_external_sync_event(entity_id, operation, result['data'])
                
        elif operation == 'delete':
            result = handle_delete_operation(entity_id, timestamp)
            
        logging.info(f"Sync operation completed: {result}")
        
    except Exception as e:
        logging.error(f"Sync processing failed: {str(e)}")
        # Implement dead letter queue handling
        raise

def handle_data_operation(entity_id, operation, data, timestamp):
    """Handle create/update operations with conflict resolution."""
    
    key = datastore_client.key('SyncEntity', entity_id)
    
    with datastore_client.transaction():
        # Get existing entity for conflict detection
        existing_entity = datastore_client.get(key)
        
        if existing_entity and operation == 'update':
            # Check for conflicts using timestamp
            existing_timestamp = existing_entity.get('last_modified')
            if existing_timestamp and existing_timestamp > timestamp:
                # Conflict detected - log and apply resolution strategy
                logging.warning(f"Conflict detected for entity {entity_id}")
                return resolve_conflict(existing_entity, data, timestamp)
        
        # Create or update entity
        entity = existing_entity or datastore.Entity(key=key)
        entity.update(data)
        entity['last_modified'] = timestamp
        entity['sync_status'] = 'synced'
        entity['version'] = entity.get('version', 0) + 1
        
        datastore_client.put(entity)
        
        return {
            'success': True,
            'data': dict(entity),
            'conflict_resolved': False
        }

def resolve_conflict(existing_entity, new_data, timestamp):
    """Implement conflict resolution strategy."""
    
    # Strategy: Merge non-conflicting fields, keep latest for conflicts
    resolved_data = dict(existing_entity)
    
    for key, value in new_data.items():
        if key not in resolved_data or key in ['description', 'metadata']:
            resolved_data[key] = value
    
    resolved_data['last_modified'] = max(existing_entity['last_modified'], timestamp)
    resolved_data['conflict_resolved'] = True
    resolved_data['version'] = existing_entity.get('version', 0) + 1
    
    datastore_client.put(datastore.Entity(existing_entity.key, **resolved_data))
    
    return {
        'success': True,
        'data': resolved_data,
        'conflict_resolved': True
    }

def handle_delete_operation(entity_id, timestamp):
    """Handle delete operations."""
    
    key = datastore_client.key('SyncEntity', entity_id)
    
    with datastore_client.transaction():
        entity = datastore_client.get(key)
        if entity:
            datastore_client.delete(key)
            
    return {'success': True, 'operation': 'delete'}

def publish_external_sync_event(entity_id, operation, data):
    """Publish events for external system synchronization."""
    
    topic_path = publisher.topic_path(
        datastore_client.project, 
        f"external-sync-{operation}"
    )
    
    message_data = json.dumps({
        'entity_id': entity_id,
        'operation': operation,
        'data': data,
        'source': 'datastore-sync'
    }).encode('utf-8')
    
    try:
        publisher.publish(topic_path, message_data)
        logging.info(f"Published external sync event for {entity_id}")
    except Exception as e:
        logging.warning(f"Failed to publish external sync: {str(e)}")
EOF

cat > requirements.txt << 'EOF'
google-cloud-datastore==2.19.0
google-cloud-pubsub==2.18.4
functions-framework==3.5.0
EOF

# Deploy sync function
log_info "Deploying synchronization function..."
gcloud functions deploy ${SYNC_FUNCTION} \
    --runtime python39 \
    --trigger-topic ${TOPIC_NAME} \
    --source . \
    --entry-point sync_processor \
    --memory 256MB \
    --timeout 60s \
    --max-instances 10

cd ${PROJECT_DIR}

# Create audit function
log_info "Creating audit logging function..."
mkdir -p ${PROJECT_DIR}/audit-function
cd ${PROJECT_DIR}/audit-function

cat > main.py << 'EOF'
import base64
import json
import logging
from google.cloud import logging as cloud_logging
from datetime import datetime
import functions_framework

# Initialize Cloud Logging client
logging_client = cloud_logging.Client()
audit_logger = logging_client.logger('datastore-sync-audit')

@functions_framework.cloud_event
def audit_logger_func(cloud_event):
    """Log all synchronization events for audit and compliance."""
    
    # Decode Pub/Sub message
    message_data = base64.b64decode(cloud_event.data["message"]["data"])
    event_data = json.loads(message_data.decode('utf-8'))
    
    # Create comprehensive audit log entry
    audit_entry = {
        'timestamp': datetime.utcnow().isoformat(),
        'event_type': 'data_synchronization',
        'entity_id': event_data.get('entity_id'),
        'operation': event_data.get('operation'),
        'source_system': event_data.get('source', 'unknown'),
        'message_id': cloud_event.data["message"]["messageId"],
        'data_snapshot': event_data.get('data', {}),
        'processing_metadata': {
            'function_name': 'audit_logger',
            'subscription': cloud_event.source,
            'delivery_attempt': cloud_event.data["message"].get("deliveryAttempt", 1)
        }
    }
    
    # Log to Cloud Logging with structured data
    audit_logger.log_struct(
        audit_entry,
        severity='INFO',
        labels={
            'component': 'datastore-sync',
            'operation': event_data.get('operation', 'unknown'),
            'entity_type': 'sync_entity'
        }
    )
    
    logging.info(f"Audit log created for entity: {event_data.get('entity_id')}")

    # Additional compliance logging for sensitive operations
    if event_data.get('operation') == 'delete':
        compliance_entry = {
            'compliance_event': 'data_deletion',
            'entity_id': event_data.get('entity_id'),
            'deletion_timestamp': datetime.utcnow().isoformat(),
            'retention_policy': 'applied',
            'regulatory_context': 'gdpr_compliance'
        }
        
        audit_logger.log_struct(
            compliance_entry,
            severity='NOTICE',
            labels={'compliance': 'data_deletion', 'regulation': 'gdpr'}
        )
EOF

cat > requirements.txt << 'EOF'
google-cloud-logging==3.8.0
functions-framework==3.5.0
EOF

# Deploy audit function
log_info "Deploying audit logging function..."
gcloud functions deploy ${AUDIT_FUNCTION} \
    --runtime python39 \
    --trigger-topic ${TOPIC_NAME} \
    --source . \
    --entry-point audit_logger_func \
    --memory 128MB \
    --timeout 30s \
    --max-instances 5

cd ${PROJECT_DIR}

log_success "Cloud Functions deployed successfully"

# Create dead letter queue
log_info "Setting up dead letter queue..."
gcloud pubsub topics create ${DLQ_TOPIC}
gcloud pubsub subscriptions create ${DLQ_SUBSCRIPTION} \
    --topic=${DLQ_TOPIC} \
    --ack-deadline=60 \
    --message-retention-duration=30d

# Update subscription with dead letter policy
gcloud pubsub subscriptions update ${SYNC_SUBSCRIPTION} \
    --dead-letter-topic=${DLQ_TOPIC} \
    --max-delivery-attempts=5

log_success "Dead letter queue configured"

# Create monitoring dashboard
log_info "Setting up monitoring dashboard..."
cat > ${PROJECT_DIR}/monitoring_dashboard.json << 'EOF'
{
  "displayName": "Datastore Sync Monitoring",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Pub/Sub Message Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"pubsub_topic\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Function Execution Count",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=${PROJECT_DIR}/monitoring_dashboard.json

log_success "Monitoring dashboard created"

# Create data publisher script
log_info "Creating data publisher utility..."
cat > ${PROJECT_DIR}/data_publisher.py << 'EOF'
#!/usr/bin/env python3

import json
import sys
from datetime import datetime
from google.cloud import pubsub_v1
from google.cloud import datastore
import argparse
import uuid

def publish_data_event(project_id, topic_name, entity_id, operation, data=None):
    """Publish data synchronization events to Pub/Sub topic."""
    
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    # Create event message
    event_data = {
        'entity_id': entity_id,
        'operation': operation,  # create, update, delete
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'data_publisher',
        'correlation_id': str(uuid.uuid4())
    }
    
    if data:
        event_data['data'] = data
    
    # Publish message to Pub/Sub
    message_data = json.dumps(event_data).encode('utf-8')
    
    try:
        future = publisher.publish(topic_path, message_data)
        message_id = future.result()
        
        print(f"✅ Published {operation} event for entity {entity_id}")
        print(f"   Message ID: {message_id}")
        print(f"   Correlation ID: {event_data['correlation_id']}")
        
        return message_id
        
    except Exception as e:
        print(f"❌ Failed to publish event: {str(e)}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Publish data sync events')
    parser.add_argument('--project', required=True, help='GCP Project ID')
    parser.add_argument('--topic', required=True, help='Pub/Sub topic name')
    parser.add_argument('--entity-id', required=True, help='Entity ID')
    parser.add_argument('--operation', required=True, 
                       choices=['create', 'update', 'delete'],
                       help='Operation type')
    parser.add_argument('--name', help='Entity name')
    parser.add_argument('--description', help='Entity description')
    parser.add_argument('--status', help='Entity status')
    
    args = parser.parse_args()
    
    # Prepare data payload for create/update operations
    data = None
    if args.operation in ['create', 'update']:
        data = {}
        if args.name:
            data['name'] = args.name
        if args.description:
            data['description'] = args.description
        if args.status:
            data['status'] = args.status
        
        # Add default values for demo
        if not data:
            data = {
                'name': f'Demo Entity {args.entity_id}',
                'description': f'Generated by data publisher for {args.operation}',
                'status': 'active',
                'category': 'demo'
            }
    
    # Publish the event
    publish_data_event(args.project, args.topic, args.entity_id, args.operation, data)

if __name__ == '__main__':
    main()
EOF

chmod +x ${PROJECT_DIR}/data_publisher.py

log_success "Data publisher utility created"

# Create deployment summary
log_info "Creating deployment summary..."
cat > ${PROJECT_DIR}/deployment_summary.txt << EOF
Event-Driven Data Synchronization Deployment Summary
===================================================

Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}
Resource Suffix: ${RANDOM_SUFFIX}

Resources Created:
------------------
Pub/Sub Topic: ${TOPIC_NAME}
Sync Subscription: ${SYNC_SUBSCRIPTION}
Audit Subscription: ${AUDIT_SUBSCRIPTION}
Dead Letter Topic: ${DLQ_TOPIC}
Dead Letter Subscription: ${DLQ_SUBSCRIPTION}
Sync Function: ${SYNC_FUNCTION}
Audit Function: ${AUDIT_FUNCTION}
Monitoring Dashboard: Datastore Sync Monitoring

Testing Commands:
----------------
# Test create operation
python3 data_publisher.py --project ${PROJECT_ID} --topic ${TOPIC_NAME} --entity-id test-001 --operation create --name "Test Entity" --status active

# Test update operation
python3 data_publisher.py --project ${PROJECT_ID} --topic ${TOPIC_NAME} --entity-id test-001 --operation update --description "Updated description"

# Test delete operation
python3 data_publisher.py --project ${PROJECT_ID} --topic ${TOPIC_NAME} --entity-id test-001 --operation delete

Monitoring URLs:
---------------
Cloud Functions: https://console.cloud.google.com/functions/list?project=${PROJECT_ID}
Pub/Sub Topics: https://console.cloud.google.com/cloudpubsub/topic/list?project=${PROJECT_ID}
Datastore: https://console.cloud.google.com/datastore/entities?project=${PROJECT_ID}
Cloud Logging: https://console.cloud.google.com/logs/query?project=${PROJECT_ID}

Cleanup Command:
---------------
./destroy.sh
EOF

log_success "Deployment summary created"

# Final verification
log_info "Performing final verification..."

# Check that resources were created
TOPICS_COUNT=$(gcloud pubsub topics list --filter="name:${TOPIC_NAME}" --format="value(name)" | wc -l)
SUBSCRIPTIONS_COUNT=$(gcloud pubsub subscriptions list --filter="name:${SYNC_SUBSCRIPTION} OR name:${AUDIT_SUBSCRIPTION}" --format="value(name)" | wc -l)
FUNCTIONS_COUNT=$(gcloud functions list --filter="name:${SYNC_FUNCTION} OR name:${AUDIT_FUNCTION}" --format="value(name)" | wc -l)

if [ "$TOPICS_COUNT" -eq 1 ] && [ "$SUBSCRIPTIONS_COUNT" -eq 2 ] && [ "$FUNCTIONS_COUNT" -eq 2 ]; then
    log_success "All resources verified successfully"
else
    log_warning "Some resources may not have been created properly"
    echo "Topics: $TOPICS_COUNT/1, Subscriptions: $SUBSCRIPTIONS_COUNT/2, Functions: $FUNCTIONS_COUNT/2"
fi

# Deployment complete
echo ""
echo "=================================================="
log_success "Deployment completed successfully!"
echo "=================================================="
echo ""
echo "Next Steps:"
echo "1. Test the system using the data_publisher.py script"
echo "2. Monitor function logs: gcloud functions logs read ${SYNC_FUNCTION}"
echo "3. Check Cloud Logging for audit events"
echo "4. View monitoring dashboard in Cloud Console"
echo ""
echo "For cleanup, run: ./destroy.sh"
echo ""
echo "Deployment summary saved to: deployment_summary.txt"
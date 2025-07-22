#!/bin/bash

# Real-Time Event Processing with Cloud Memorystore and Pub/Sub - Deployment Script
# This script deploys the complete infrastructure for real-time event processing
# using Google Cloud Memorystore for Redis, Pub/Sub, and Cloud Functions

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

# Function to wait for operation completion
wait_for_operation() {
    local operation_name="$1"
    local max_attempts=30
    local attempt=1
    
    log "Waiting for operation: $operation_name"
    
    while [ $attempt -le $max_attempts ]; do
        if gcloud operations describe "$operation_name" --format="value(done)" 2>/dev/null | grep -q "True"; then
            success "Operation completed: $operation_name"
            return 0
        fi
        
        echo -n "."
        sleep 10
        ((attempt++))
    done
    
    error "Operation timed out: $operation_name"
    return 1
}

# Function to check if Redis instance is ready
check_redis_ready() {
    local instance_name="$1"
    local region="$2"
    local max_attempts=30
    local attempt=1
    
    log "Checking Redis instance readiness: $instance_name"
    
    while [ $attempt -le $max_attempts ]; do
        local state=$(gcloud redis instances describe "$instance_name" \
            --region="$region" \
            --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$state" = "READY" ]; then
            success "Redis instance is ready: $instance_name"
            return 0
        elif [ "$state" = "CREATING" ]; then
            echo -n "."
            sleep 15
            ((attempt++))
        else
            error "Redis instance in unexpected state: $state"
            return 1
        fi
    done
    
    error "Redis instance creation timed out"
    return 1
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partially created resources..."
    
    # Note: This is a basic cleanup. For production, implement comprehensive cleanup
    if [ -n "${REDIS_INSTANCE:-}" ]; then
        gcloud redis instances delete "$REDIS_INSTANCE" --region="$REGION" --quiet 2>/dev/null || true
    fi
    
    if [ -n "${PUBSUB_TOPIC:-}" ]; then
        gcloud pubsub topics delete "$PUBSUB_TOPIC" --quiet 2>/dev/null || true
        gcloud pubsub topics delete "${PUBSUB_TOPIC}-deadletter" --quiet 2>/dev/null || true
    fi
    
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Main deployment function
main() {
    log "Starting deployment of Real-Time Event Processing infrastructure"
    
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
    
    # Set environment variables with defaults or prompts
    if [ -z "${PROJECT_ID:-}" ]; then
        read -p "Enter Google Cloud Project ID: " PROJECT_ID
    fi
    
    export PROJECT_ID
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    export REDIS_INSTANCE="event-cache-${RANDOM_SUFFIX}"
    export PUBSUB_TOPIC="events-topic-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="event-processor-${RANDOM_SUFFIX}"
    
    log "Configuration:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    log "  Redis Instance: $REDIS_INSTANCE"
    log "  Pub/Sub Topic: $PUBSUB_TOPIC"
    log "  Function Name: $FUNCTION_NAME"
    
    # Confirm deployment
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled"
        exit 0
    fi
    
    # Set default project and region
    log "Setting default project and region..."
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Enable required APIs
    log "Enabling required Google Cloud APIs..."
    local apis=(
        "redis.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "monitoring.googleapis.com"
        "compute.googleapis.com"
        "vpcaccess.googleapis.com"
        "bigquery.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        gcloud services enable "$api"
    done
    
    success "APIs enabled successfully"
    
    # Create Cloud Memorystore Redis Instance
    log "Creating Cloud Memorystore Redis instance..."
    gcloud redis instances create "$REDIS_INSTANCE" \
        --size=1 \
        --region="$REGION" \
        --redis-version=redis_6_x \
        --tier=BASIC \
        --network=default \
        --redis-config="maxmemory-policy=allkeys-lru"
    
    # Wait for Redis instance to be ready
    check_redis_ready "$REDIS_INSTANCE" "$REGION"
    
    # Get Redis connection details
    export REDIS_HOST=$(gcloud redis instances describe "$REDIS_INSTANCE" \
        --region="$REGION" \
        --format="value(host)")
    export REDIS_PORT=$(gcloud redis instances describe "$REDIS_INSTANCE" \
        --region="$REGION" \
        --format="value(port)")
    
    success "Redis instance created: $REDIS_INSTANCE ($REDIS_HOST:$REDIS_PORT)"
    
    # Create Pub/Sub resources
    log "Creating Pub/Sub topics and subscriptions..."
    
    # Create main topic
    gcloud pubsub topics create "$PUBSUB_TOPIC"
    
    # Create dead letter topic
    gcloud pubsub topics create "${PUBSUB_TOPIC}-deadletter"
    
    # Create subscription with dead letter policy
    gcloud pubsub subscriptions create "${PUBSUB_TOPIC}-subscription" \
        --topic="$PUBSUB_TOPIC" \
        --ack-deadline=60 \
        --message-retention-duration=7d
    
    # Update subscription with dead letter policy
    gcloud pubsub subscriptions update "${PUBSUB_TOPIC}-subscription" \
        --dead-letter-topic="${PUBSUB_TOPIC}-deadletter" \
        --max-delivery-attempts=5
    
    success "Pub/Sub resources created successfully"
    
    # Create VPC Access Connector for Redis connectivity
    log "Creating VPC Access Connector for Redis connectivity..."
    if ! gcloud compute networks vpc-access connectors describe redis-connector \
        --region="$REGION" >/dev/null 2>&1; then
        
        gcloud compute networks vpc-access connectors create redis-connector \
            --region="$REGION" \
            --subnet=default \
            --subnet-project="$PROJECT_ID" \
            --min-instances=2 \
            --max-instances=10 \
            --machine-type=e2-micro
        
        success "VPC Access Connector created"
    else
        warning "VPC Access Connector already exists"
    fi
    
    # Create function code directory
    FUNCTION_DIR="/tmp/event-processor-${RANDOM_SUFFIX}"
    mkdir -p "$FUNCTION_DIR"
    cd "$FUNCTION_DIR"
    
    log "Creating Cloud Function code..."
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "event-processor",
  "version": "1.0.0",
  "description": "Real-time event processor with Redis caching",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/pubsub": "^4.0.7",
    "@google-cloud/bigquery": "^7.3.0",
    "redis": "^4.6.13"
  }
}
EOF
    
    # Create the main function code
    cat > index.js << EOF
const redis = require('redis');
const {BigQuery} = require('@google-cloud/bigquery');

// Initialize Redis client
const redisClient = redis.createClient({
  socket: {
    host: '${REDIS_HOST}',
    port: ${REDIS_PORT}
  }
});

// Initialize BigQuery client for analytics
const bigquery = new BigQuery();
const dataset = bigquery.dataset('event_analytics');
const table = dataset.table('processed_events');

// Connect to Redis on function startup
redisClient.connect().catch(console.error);

/**
 * Processes incoming Pub/Sub events with Redis caching
 * @param {object} message Pub/Sub message
 * @param {object} context Cloud Functions context
 */
exports.processEvent = async (message, context) => {
  try {
    // Parse the event data
    const eventData = JSON.parse(
      Buffer.from(message.data, 'base64').toString()
    );
    
    console.log('Processing event:', eventData);
    
    // Generate cache key based on event type and user
    const cacheKey = \`event:\${eventData.type}:\${eventData.userId}\`;
    
    // Check Redis cache for existing data
    const cachedData = await redisClient.get(cacheKey);
    
    if (cachedData) {
      console.log('Cache hit for key:', cacheKey);
      // Update cached data with new event
      const existingData = JSON.parse(cachedData);
      existingData.eventCount += 1;
      existingData.lastEventTime = eventData.timestamp;
      existingData.events.push(eventData);
      
      // Keep only last 10 events to manage memory
      if (existingData.events.length > 10) {
        existingData.events = existingData.events.slice(-10);
      }
      
      // Update cache with 1 hour expiration
      await redisClient.setEx(cacheKey, 3600, JSON.stringify(existingData));
    } else {
      console.log('Cache miss for key:', cacheKey);
      // Create new cache entry
      const newData = {
        userId: eventData.userId,
        eventType: eventData.type,
        eventCount: 1,
        firstEventTime: eventData.timestamp,
        lastEventTime: eventData.timestamp,
        events: [eventData]
      };
      
      // Store in cache with 1 hour expiration
      await redisClient.setEx(cacheKey, 3600, JSON.stringify(newData));
    }
    
    // Store event in BigQuery for analytics
    const row = {
      event_id: eventData.id,
      user_id: eventData.userId,
      event_type: eventData.type,
      timestamp: eventData.timestamp,
      metadata: JSON.stringify(eventData.metadata || {})
    };
    
    await table.insert([row]);
    
    console.log('Event processed successfully:', eventData.id);
    
  } catch (error) {
    console.error('Error processing event:', error);
    throw error; // Trigger retry mechanism
  }
};
EOF
    
    success "Cloud Function code created"
    
    # Create BigQuery dataset and table
    log "Creating BigQuery dataset and table..."
    
    # Create dataset
    if ! bq show "${PROJECT_ID}:event_analytics" >/dev/null 2>&1; then
        bq mk --dataset \
            --location="$REGION" \
            --description="Event processing analytics dataset" \
            "${PROJECT_ID}:event_analytics"
        
        success "BigQuery dataset created"
    else
        warning "BigQuery dataset already exists"
    fi
    
    # Create table
    if ! bq show "${PROJECT_ID}:event_analytics.processed_events" >/dev/null 2>&1; then
        bq mk --table \
            --time_partitioning_field=timestamp \
            --time_partitioning_type=DAY \
            --clustering_fields=event_type,user_id \
            "${PROJECT_ID}:event_analytics.processed_events" \
            event_id:STRING,user_id:STRING,event_type:STRING,timestamp:TIMESTAMP,metadata:STRING
        
        success "BigQuery table created"
    else
        warning "BigQuery table already exists"
    fi
    
    # Deploy Cloud Function
    log "Deploying Cloud Function..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=nodejs20 \
        --source=. \
        --entry-point=processEvent \
        --trigger-topic="$PUBSUB_TOPIC" \
        --memory=512MB \
        --timeout=540s \
        --max-instances=100 \
        --vpc-connector="projects/${PROJECT_ID}/locations/${REGION}/connectors/redis-connector" \
        --set-env-vars="REDIS_HOST=${REDIS_HOST},REDIS_PORT=${REDIS_PORT}" \
        --region="$REGION"
    
    success "Cloud Function deployed successfully"
    
    # Create monitoring dashboard
    log "Creating monitoring dashboard..."
    cat > monitoring-dashboard.json << EOF
{
  "displayName": "Event Processing Dashboard - ${RANDOM_SUFFIX}",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Redis Operations/sec",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"redis.googleapis.com/stats/operations_per_second\"",
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
          "title": "Pub/Sub Messages/sec",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"pubsub_topic\" AND metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\"",
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
    
    # Create monitoring dashboard
    gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.json
    
    success "Monitoring dashboard created"
    
    # Save deployment configuration
    cat > deployment-config.txt << EOF
# Real-Time Event Processing Deployment Configuration
# Generated: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
REDIS_INSTANCE=${REDIS_INSTANCE}
REDIS_HOST=${REDIS_HOST}
REDIS_PORT=${REDIS_PORT}
PUBSUB_TOPIC=${PUBSUB_TOPIC}
FUNCTION_NAME=${FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
FUNCTION_DIR=${FUNCTION_DIR}
EOF
    
    # Test the deployment
    log "Testing the deployment..."
    
    # Publish a test event
    gcloud pubsub topics publish "$PUBSUB_TOPIC" \
        --message='{"id":"test-deployment","userId":"user123","type":"login","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","metadata":{"source":"deployment-test","ip":"127.0.0.1"}}'
    
    # Wait a moment for processing
    sleep 10
    
    # Check function logs
    log "Checking function execution..."
    gcloud functions logs read "$FUNCTION_NAME" \
        --limit=5 \
        --region="$REGION" \
        --format="value(textPayload)" | head -10
    
    success "Deployment completed successfully!"
    log ""
    log "Deployment Summary:"
    log "==================="
    log "Project ID: $PROJECT_ID"
    log "Redis Instance: $REDIS_INSTANCE ($REDIS_HOST:$REDIS_PORT)"
    log "Pub/Sub Topic: $PUBSUB_TOPIC"
    log "Cloud Function: $FUNCTION_NAME"
    log "BigQuery Dataset: event_analytics"
    log ""
    log "Next Steps:"
    log "1. Monitor the system through Cloud Monitoring dashboard"
    log "2. Test event processing by publishing to topic: $PUBSUB_TOPIC"
    log "3. Query processed events in BigQuery: ${PROJECT_ID}.event_analytics.processed_events"
    log "4. Use destroy.sh to clean up resources when done"
    log ""
    log "Configuration saved to: $FUNCTION_DIR/deployment-config.txt"
    
    # Cleanup function directory
    cd /
    # Keep the directory for potential debugging
    warning "Function code directory preserved at: $FUNCTION_DIR"
}

# Run main function
main "$@"
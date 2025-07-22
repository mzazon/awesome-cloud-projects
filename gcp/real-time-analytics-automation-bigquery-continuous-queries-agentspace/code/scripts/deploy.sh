#!/bin/bash

# Real-Time Analytics Automation with BigQuery Continuous Queries and Agentspace
# Deployment Script for GCP Recipe
# 
# This script automates the deployment of a real-time analytics system that combines
# BigQuery continuous queries, Agentspace AI agents, and Cloud Workflows for
# autonomous business process automation.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
}

# Function to check if project is set
check_project() {
    if [ -z "${PROJECT_ID:-}" ] || [ "${PROJECT_ID}" = "$(gcloud config get-value project 2>/dev/null || echo '')" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo '')
        if [ -z "${PROJECT_ID}" ]; then
            log_error "No project ID set. Please run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
}

# Function to enable APIs with retry logic
enable_apis() {
    local apis=(
        "bigquery.googleapis.com"
        "pubsub.googleapis.com" 
        "workflows.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )
    
    log_info "Enabling required Google Cloud APIs..."
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${PROJECT_ID}"; then
            log_success "Enabled ${api}"
        else
            log_warning "Failed to enable ${api}, may already be enabled"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    # Create raw events topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC_RAW}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Topic ${PUBSUB_TOPIC_RAW} already exists"
    else
        gcloud pubsub topics create "${PUBSUB_TOPIC_RAW}" --project="${PROJECT_ID}"
        log_success "Created topic: ${PUBSUB_TOPIC_RAW}"
    fi
    
    # Create insights topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC_INSIGHTS}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Topic ${PUBSUB_TOPIC_INSIGHTS} already exists"
    else
        gcloud pubsub topics create "${PUBSUB_TOPIC_INSIGHTS}" --project="${PROJECT_ID}"
        log_success "Created topic: ${PUBSUB_TOPIC_INSIGHTS}"
    fi
    
    # Create subscription for BigQuery continuous query consumption
    local subscription_name="${PUBSUB_TOPIC_RAW}-bq-sub"
    if gcloud pubsub subscriptions describe "${subscription_name}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Subscription ${subscription_name} already exists"
    else
        gcloud pubsub subscriptions create "${subscription_name}" \
            --topic="${PUBSUB_TOPIC_RAW}" \
            --project="${PROJECT_ID}"
        log_success "Created subscription: ${subscription_name}"
    fi
    
    # Create test subscription for insights topic
    local test_subscription="${PUBSUB_TOPIC_INSIGHTS}-test-sub"
    if gcloud pubsub subscriptions describe "${test_subscription}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Test subscription ${test_subscription} already exists"
    else
        gcloud pubsub subscriptions create "${test_subscription}" \
            --topic="${PUBSUB_TOPIC_INSIGHTS}" \
            --project="${PROJECT_ID}"
        log_success "Created test subscription: ${test_subscription}"
    fi
}

# Function to create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."
    
    # Create dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_warning "Dataset ${DATASET_NAME} already exists"
    else
        bq mk --dataset \
            --location="${REGION}" \
            --project_id="${PROJECT_ID}" \
            "${PROJECT_ID}:${DATASET_NAME}"
        log_success "Created dataset: ${DATASET_NAME}"
    fi
    
    # Create processed events table
    if bq ls "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" >/dev/null 2>&1; then
        log_warning "Table ${TABLE_NAME} already exists"
    else
        bq mk --table \
            --project_id="${PROJECT_ID}" \
            "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" \
            "event_id:STRING,timestamp:TIMESTAMP,user_id:STRING,event_type:STRING,value:FLOAT64,metadata:JSON"
        log_success "Created table: ${TABLE_NAME}"
    fi
    
    # Create insights table
    if bq ls "${PROJECT_ID}:${DATASET_NAME}.insights" >/dev/null 2>&1; then
        log_warning "Table insights already exists"
    else
        bq mk --table \
            --project_id="${PROJECT_ID}" \
            "${PROJECT_ID}:${DATASET_NAME}.insights" \
            "insight_id:STRING,generated_at:TIMESTAMP,insight_type:STRING,confidence:FLOAT64,recommendation:STRING,data_points:JSON"
        log_success "Created table: insights"
    fi
}

# Function to create continuous query
create_continuous_query() {
    log_info "Creating BigQuery continuous query..."
    
    # Create temporary directory for query files
    local temp_dir
    temp_dir=$(mktemp -d)
    local query_file="${temp_dir}/continuous_query.sql"
    
    # Generate continuous query SQL
    cat > "${query_file}" << EOF
EXPORT DATA
OPTIONS (
  uri = 'projects/${PROJECT_ID}/topics/${PUBSUB_TOPIC_INSIGHTS}',
  format = 'JSON',
  overwrite = false
) AS
WITH real_time_aggregates AS (
  SELECT
    GENERATE_UUID() as insight_id,
    CURRENT_TIMESTAMP() as generated_at,
    'anomaly_detection' as insight_type,
    user_id,
    event_type,
    AVG(value) OVER (
      PARTITION BY user_id, event_type 
      ORDER BY timestamp 
      ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) as moving_avg,
    value,
    CASE 
      WHEN ABS(value - AVG(value) OVER (
        PARTITION BY user_id, event_type 
        ORDER BY timestamp 
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
      )) > 2 * STDDEV(value) OVER (
        PARTITION BY user_id, event_type 
        ORDER BY timestamp 
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
      ) THEN 0.95
      ELSE 0.1
    END as confidence,
    metadata
  FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\`
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
)
SELECT
  insight_id,
  generated_at,
  insight_type,
  confidence,
  CONCAT('Potential anomaly detected for user ', user_id, 
         ' with event type ', event_type,
         '. Value: ', CAST(value AS STRING),
         ', Expected: ', CAST(moving_avg AS STRING)) as recommendation,
  TO_JSON(STRUCT(
    user_id,
    event_type,
    value,
    moving_avg,
    metadata
  )) as data_points
FROM real_time_aggregates
WHERE confidence > 0.8;
EOF
    
    # Check if continuous query job already exists
    local job_id="continuous-analytics-${RANDOM_SUFFIX}"
    if bq show -j "${job_id}" --project_id="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Continuous query job ${job_id} already exists"
    else
        # Start the continuous query job
        bq query \
            --use_legacy_sql=false \
            --job_timeout=0 \
            --continuous \
            --job_id="${job_id}" \
            --project_id="${PROJECT_ID}" \
            "$(cat ${query_file})"
        
        if [ $? -eq 0 ]; then
            log_success "Continuous query deployed with job ID: ${job_id}"
        else
            log_error "Failed to deploy continuous query"
            rm -rf "${temp_dir}"
            exit 1
        fi
    fi
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
}

# Function to create service account for Agentspace
create_service_account() {
    log_info "Creating service account for Agentspace integration..."
    
    local sa_name="agentspace-analytics"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account
    if gcloud iam service-accounts describe "${sa_email}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Service account ${sa_email} already exists"
    else
        gcloud iam service-accounts create "${sa_name}" \
            --display-name="Agentspace Analytics Service Account" \
            --project="${PROJECT_ID}"
        log_success "Created service account: ${sa_email}"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/pubsub.subscriber"
        "roles/bigquery.dataViewer"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}" \
            --quiet
        log_success "Granted ${role} to ${sa_email}"
    done
}

# Function to create Cloud Workflows
create_workflows() {
    log_info "Creating Cloud Workflows for business process automation..."
    
    # Create temporary directory for workflow files
    local temp_dir
    temp_dir=$(mktemp -d)
    local workflow_file="${temp_dir}/analytics_workflow.yaml"
    
    # Generate workflow definition
    cat > "${workflow_file}" << EOF
main:
  params: [input]
  steps:
    - extract_insight:
        assign:
          - insight_data: \${input.insight}
          - confidence: \${insight_data.confidence}
          - insight_type: \${insight_data.insight_type}
    
    - evaluate_confidence:
        switch:
          - condition: \${confidence > 0.9}
            next: high_priority_action
          - condition: \${confidence > 0.7}
            next: medium_priority_action
          - condition: true
            next: low_priority_action
    
    - high_priority_action:
        call: execute_immediate_response
        args:
          action_type: "immediate"
          insight: \${insight_data}
        next: log_action
    
    - medium_priority_action:
        call: execute_scheduled_response
        args:
          action_type: "scheduled"
          insight: \${insight_data}
        next: log_action
    
    - low_priority_action:
        call: execute_monitoring_response
        args:
          action_type: "monitoring"
          insight: \${insight_data}
        next: log_action
    
    - log_action:
        call: http.post
        args:
          url: "https://logging.googleapis.com/v2/entries:write"
          headers:
            Authorization: \${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
          body:
            entries:
              - logName: \${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/analytics-automation"}
                resource:
                  type: "workflow"
                jsonPayload:
                  insight_id: \${insight_data.insight_id}
                  action_taken: "processed"
                  confidence: \${confidence}
        result: log_result

execute_immediate_response:
  params: [action_type, insight]
  steps:
    - send_alert:
        call: http.post
        args:
          url: "https://pubsub.googleapis.com/v1/projects/${PROJECT_ID}/topics/alerts:publish"
          headers:
            Authorization: \${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
          body:
            messages:
              - data: \${base64.encode(json.encode(insight))}
                attributes:
                  priority: "high"
                  action_type: \${action_type}

execute_scheduled_response:
  params: [action_type, insight]
  steps:
    - schedule_review:
        call: sys.log
        args:
          data: \${"Scheduled review for insight: " + insight.insight_id}

execute_monitoring_response:
  params: [action_type, insight]
  steps:
    - add_to_monitoring:
        call: sys.log
        args:
          data: \${"Added to monitoring: " + insight.insight_id}
EOF
    
    # Deploy the workflow
    if gcloud workflows describe "${WORKFLOW_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Workflow ${WORKFLOW_NAME} already exists, updating..."
        gcloud workflows deploy "${WORKFLOW_NAME}" \
            --source="${workflow_file}" \
            --location="${REGION}" \
            --project="${PROJECT_ID}"
    else
        gcloud workflows deploy "${WORKFLOW_NAME}" \
            --source="${workflow_file}" \
            --location="${REGION}" \
            --project="${PROJECT_ID}"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Cloud Workflow deployed: ${WORKFLOW_NAME}"
    else
        log_error "Failed to deploy Cloud Workflow"
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
}

# Function to create data simulation script
create_simulation_script() {
    log_info "Creating data simulation script for testing..."
    
    local script_dir="$(dirname "$0")"
    local simulate_script="${script_dir}/simulate_data.py"
    
    if [ -f "${simulate_script}" ]; then
        log_warning "Data simulation script already exists"
        return 0
    fi
    
    cat > "${simulate_script}" << 'EOF'
#!/usr/bin/env python3
"""
Data simulation script for real-time analytics testing.
Generates realistic e-commerce event data with controlled anomalies.
"""

import json
import random
import time
import sys
from datetime import datetime

try:
    from google.cloud import pubsub_v1
except ImportError:
    print("Error: google-cloud-pubsub not installed. Run: pip install google-cloud-pubsub")
    sys.exit(1)

def generate_event():
    """Generate a realistic e-commerce event with occasional anomalies."""
    # Normal values vs anomalous values (5% chance of anomaly)
    if random.random() > 0.95:
        # Generate anomalous value
        value = random.normalvariate(300, 100)  # Much higher than normal
    else:
        # Generate normal value
        value = random.normalvariate(100, 15)
    
    return {
        "event_id": f"evt_{random.randint(100000, 999999)}",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "user_id": f"user_{random.randint(1, 1000)}",
        "event_type": random.choice(["purchase", "view", "click", "add_to_cart"]),
        "value": max(0, value),  # Ensure non-negative values
        "metadata": {
            "source": "web_app",
            "session_id": f"sess_{random.randint(10000, 99999)}",
            "user_agent": random.choice(["Chrome", "Firefox", "Safari", "Edge"]),
            "country": random.choice(["US", "CA", "UK", "DE", "FR"])
        }
    }

def publish_events(project_id, topic_name, num_events=100):
    """Publish events to Pub/Sub topic."""
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(project_id, topic_name)
        
        print(f"Publishing {num_events} events to {topic_path}")
        
        published_futures = []
        for i in range(num_events):
            event = generate_event()
            data = json.dumps(event).encode("utf-8")
            future = publisher.publish(topic_path, data)
            published_futures.append(future)
            
            if (i + 1) % 10 == 0:
                print(f"Published {i + 1}/{num_events} events")
            
            time.sleep(0.1)  # 10 events per second
        
        # Wait for all publishes to complete
        for future in published_futures:
            future.result()
        
        print(f"Successfully published all {num_events} events")
        
    except Exception as e:
        print(f"Error publishing events: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python simulate_data.py PROJECT_ID TOPIC_NAME [NUM_EVENTS]")
        print("Example: python simulate_data.py my-project raw-events-abc123 50")
        sys.exit(1)
    
    project_id = sys.argv[1]
    topic_name = sys.argv[2]
    num_events = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    
    publish_events(project_id, topic_name, num_events)
EOF
    
    chmod +x "${simulate_script}"
    log_success "Created data simulation script: ${simulate_script}"
}

# Function to install Python dependencies
install_python_deps() {
    log_info "Installing Python dependencies for data simulation..."
    
    if command_exists pip3; then
        pip3 install google-cloud-pubsub >/dev/null 2>&1
    elif command_exists pip; then
        pip install google-cloud-pubsub >/dev/null 2>&1
    else
        log_warning "pip not found. Please install google-cloud-pubsub manually: pip install google-cloud-pubsub"
        return 0
    fi
    
    log_success "Python dependencies installed"
}

# Function to wait for resources to be ready
wait_for_resources() {
    log_info "Waiting for resources to be fully ready..."
    
    # Wait for BigQuery dataset to be available
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
            log_success "BigQuery dataset is ready"
            break
        fi
        log_info "Waiting for BigQuery dataset... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_warning "BigQuery dataset readiness check timed out"
    fi
    
    # Additional wait for API propagation
    sleep 30
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_failed=false
    
    # Check Pub/Sub topics
    if ! gcloud pubsub topics describe "${PUBSUB_TOPIC_RAW}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Validation failed: Pub/Sub topic ${PUBSUB_TOPIC_RAW} not found"
        validation_failed=true
    fi
    
    if ! gcloud pubsub topics describe "${PUBSUB_TOPIC_INSIGHTS}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Validation failed: Pub/Sub topic ${PUBSUB_TOPIC_INSIGHTS} not found"
        validation_failed=true
    fi
    
    # Check BigQuery resources
    if ! bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_error "Validation failed: BigQuery dataset ${DATASET_NAME} not found"
        validation_failed=true
    fi
    
    # Check Cloud Workflow
    if ! gcloud workflows describe "${WORKFLOW_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Validation failed: Cloud Workflow ${WORKFLOW_NAME} not found"
        validation_failed=true
    fi
    
    # Check service account
    local sa_email="agentspace-analytics@${PROJECT_ID}.iam.gserviceaccount.com"
    if ! gcloud iam service-accounts describe "${sa_email}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Validation failed: Service account ${sa_email} not found"
        validation_failed=true
    fi
    
    if [ "$validation_failed" = true ]; then
        log_error "Deployment validation failed. Please check the errors above."
        exit 1
    else
        log_success "Deployment validation passed"
    fi
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "   DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Dataset: ${DATASET_NAME}"
    echo "Raw Events Topic: ${PUBSUB_TOPIC_RAW}"
    echo "Insights Topic: ${PUBSUB_TOPIC_INSIGHTS}"
    echo "Workflow: ${WORKFLOW_NAME}"
    echo "Continuous Query Job: continuous-analytics-${RANDOM_SUFFIX}"
    echo ""
    echo "=========================================="
    echo "   NEXT STEPS"
    echo "=========================================="
    echo ""
    echo "1. Test the pipeline with sample data:"
    echo "   ./simulate_data.py ${PROJECT_ID} ${PUBSUB_TOPIC_RAW} 50"
    echo ""
    echo "2. Monitor continuous query status:"
    echo "   bq show -j continuous-analytics-${RANDOM_SUFFIX}"
    echo ""
    echo "3. Check insights generation:"
    echo "   gcloud pubsub subscriptions pull ${PUBSUB_TOPIC_INSIGHTS}-test-sub --limit=5 --auto-ack"
    echo ""
    echo "4. View workflow executions:"
    echo "   gcloud workflows executions list --workflow=${WORKFLOW_NAME} --location=${REGION}"
    echo ""
    echo "For cleanup, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    echo "=========================================="
    echo "   Real-Time Analytics Automation"
    echo "   BigQuery + Agentspace + Workflows"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! command_exists bq; then
        log_error "bq CLI not found. Please install Google Cloud SDK with BigQuery component."
        exit 1
    fi
    
    check_gcloud_auth
    check_project
    
    # Set environment variables if not already set
    export REGION="${REGION:-us-central1}"
    export DATASET_NAME="${DATASET_NAME:-realtime_analytics}"
    export TABLE_NAME="${TABLE_NAME:-processed_events}"
    
    # Generate unique identifiers if not set
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    fi
    export PUBSUB_TOPIC_RAW="${PUBSUB_TOPIC_RAW:-raw-events-${RANDOM_SUFFIX}}"
    export PUBSUB_TOPIC_INSIGHTS="${PUBSUB_TOPIC_INSIGHTS:-insights-${RANDOM_SUFFIX}}"
    export WORKFLOW_NAME="${WORKFLOW_NAME:-analytics-automation-${RANDOM_SUFFIX}}"
    
    log_success "Prerequisites check passed"
    log_info "Using project: ${PROJECT_ID}"
    log_info "Using region: ${REGION}"
    log_info "Using random suffix: ${RANDOM_SUFFIX}"
    
    # Set default region
    gcloud config set compute/region "${REGION}" >/dev/null 2>&1
    
    # Deploy components
    enable_apis
    create_pubsub_resources
    create_bigquery_resources
    create_continuous_query
    create_service_account
    create_workflows
    create_simulation_script
    install_python_deps
    wait_for_resources
    validate_deployment
    
    log_success "Real-time analytics automation deployment completed successfully!"
    display_summary
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
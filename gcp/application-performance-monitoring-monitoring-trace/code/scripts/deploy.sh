#!/bin/bash

# Deploy script for Application Performance Monitoring with Cloud Monitoring and Cloud Trace
# Recipe: f4a8e3d2
# Last Updated: 2025-07-12

set -euo pipefail

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_LOG="${SCRIPT_DIR}/deploy.log"
RESOURCE_STATE="${SCRIPT_DIR}/.deploy_state"

# Default configuration (can be overridden by environment variables)
DEFAULT_PROJECT_ID="monitoring-demo-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Environment variables with defaults
export PROJECT_ID="${PROJECT_ID:-${DEFAULT_PROJECT_ID}}"
export REGION="${REGION:-${DEFAULT_REGION}}"
export ZONE="${ZONE:-${DEFAULT_ZONE}}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export INSTANCE_NAME="web-app-${RANDOM_SUFFIX}"
export PUBSUB_TOPIC="performance-alerts-${RANDOM_SUFFIX}"
export FUNCTION_NAME="performance-optimizer-${RANDOM_SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project creation or selection
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --name="Monitoring Demo" 2>>"${DEPLOY_LOG}"; then
            log_error "Failed to create project. Check if project ID is unique and valid."
            exit 1
        fi
        
        # Wait for project creation to complete
        sleep 10
        
        log_success "Project ${PROJECT_ID} created successfully"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" 2>>"${DEPLOY_LOG}"
    gcloud config set compute/region "${REGION}" 2>>"${DEPLOY_LOG}"
    gcloud config set compute/zone "${ZONE}" 2>>"${DEPLOY_LOG}"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Billing is not enabled for this project. Some services may not work."
        log_warning "Please enable billing at: https://console.cloud.google.com/billing"
    fi
    
    # Save project info to state file
    echo "PROJECT_ID=${PROJECT_ID}" > "${RESOURCE_STATE}"
    echo "REGION=${REGION}" >> "${RESOURCE_STATE}"
    echo "ZONE=${ZONE}" >> "${RESOURCE_STATE}"
    echo "INSTANCE_NAME=${INSTANCE_NAME}" >> "${RESOURCE_STATE}"
    echo "PUBSUB_TOPIC=${PUBSUB_TOPIC}" >> "${RESOURCE_STATE}"
    echo "FUNCTION_NAME=${FUNCTION_NAME}" >> "${RESOURCE_STATE}"
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "monitoring.googleapis.com"
        "cloudtrace.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if ! gcloud services enable "${api}" 2>>"${DEPLOY_LOG}"; then
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Pub/Sub infrastructure
create_pubsub() {
    log_info "Creating Pub/Sub infrastructure..."
    
    # Create Pub/Sub topic
    if ! gcloud pubsub topics create "${PUBSUB_TOPIC}" 2>>"${DEPLOY_LOG}"; then
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions create \
        "${PUBSUB_TOPIC}-subscription" \
        --topic="${PUBSUB_TOPIC}" 2>>"${DEPLOY_LOG}"; then
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    log_success "Pub/Sub infrastructure created"
}

# Function to deploy sample application
deploy_application() {
    log_info "Deploying sample application with monitoring instrumentation..."
    
    # Create startup script for the application
    local startup_script=$(cat << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y python3 python3-pip nginx

# Install monitoring libraries
pip3 install google-cloud-monitoring google-cloud-trace flask

# Create sample Flask application with monitoring
cat > /opt/app.py << 'APP_EOF'
from flask import Flask, request, jsonify
import time
import random
from google.cloud import monitoring_v3
from google.cloud import trace_v1
import os

app = Flask(__name__)

# Initialize monitoring client
monitoring_client = monitoring_v3.MetricServiceClient()
project_name = f"projects/{os.environ.get('GOOGLE_CLOUD_PROJECT')}"

@app.route('/api/data')
def get_data():
    # Simulate variable response time
    delay = random.uniform(0.1, 2.0)
    time.sleep(delay)
    
    # Create custom metric for response time
    series = monitoring_v3.TimeSeries()
    series.metric.type = "custom.googleapis.com/api/response_time"
    series.resource.type = "global"
    
    point = series.points.add()
    point.value.double_value = delay
    point.interval.end_time.seconds = int(time.time())
    
    try:
        monitoring_client.create_time_series(
            name=project_name, time_series=[series]
        )
    except Exception as e:
        print(f"Monitoring error: {e}")
    
    return jsonify({
        'data': 'Sample response',
        'response_time': delay,
        'timestamp': time.time()
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APP_EOF

# Start the application
cd /opt && python3 app.py &
EOF
)
    
    # Create Compute Engine instance
    if ! gcloud compute instances create "${INSTANCE_NAME}" \
        --machine-type=e2-medium \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --tags=web-server \
        --metadata=startup-script="${startup_script}" \
        --scopes=https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/trace.append \
        2>>"${DEPLOY_LOG}"; then
        log_error "Failed to create Compute Engine instance"
        exit 1
    fi
    
    # Create firewall rule
    if ! gcloud compute firewall-rules create allow-web-app \
        --allow tcp:5000 \
        --source-ranges 0.0.0.0/0 \
        --target-tags web-server 2>>"${DEPLOY_LOG}"; then
        log_error "Failed to create firewall rule"
        exit 1
    fi
    
    log_info "Waiting for instance to start and application to initialize..."
    sleep 60
    
    log_success "Sample application deployed"
}

# Function to create Cloud Function
deploy_cloud_function() {
    log_info "Deploying performance optimization Cloud Function..."
    
    # Create temporary directory for function code
    local function_dir="${SCRIPT_DIR}/temp_function"
    mkdir -p "${function_dir}"
    
    # Create function source code
    cat > "${function_dir}/main.py" << 'EOF'
import json
import base64
from google.cloud import monitoring_v3
from google.cloud import trace_v1
from google.cloud import logging
import functions_framework

# Initialize clients
monitoring_client = monitoring_v3.MetricServiceClient()
trace_client = trace_v1.TraceServiceClient()
logging_client = logging.Client()

@functions_framework.cloud_event
def performance_optimizer(cloud_event):
    """Process performance alerts and implement optimizations"""
    
    # Decode Pub/Sub message
    message_data = base64.b64decode(cloud_event.data["message"]["data"])
    alert_data = json.loads(message_data.decode())
    
    project_id = alert_data.get('incident', {}).get('project_id')
    
    if not project_id:
        print("No project ID found in alert data")
        return
    
    # Analyze performance metrics
    project_name = f"projects/{project_id}"
    
    # Query recent traces for bottleneck analysis
    try:
        traces = trace_client.list_traces(
            parent=project_name,
            page_size=10
        )
        
        slow_traces = []
        for trace in traces:
            for span in trace.spans:
                duration_ms = (span.end_time.seconds - span.start_time.seconds) * 1000
                if duration_ms > 1000:  # Spans over 1 second
                    slow_traces.append({
                        'trace_id': trace.trace_id,
                        'span_name': span.name,
                        'duration_ms': duration_ms
                    })
        
        # Log analysis results
        if slow_traces:
            log_entry = {
                'severity': 'WARNING',
                'message': f"Performance optimization triggered: {len(slow_traces)} slow traces detected",
                'slow_traces': slow_traces[:5]  # Limit output
            }
            print(json.dumps(log_entry))
            
            # Implement optimization logic here
            # Examples: cache warming, connection pooling, resource scaling
            
        else:
            print("No significant performance bottlenecks detected in recent traces")
            
    except Exception as e:
        print(f"Error analyzing traces: {e}")
    
    return "Performance analysis completed"
EOF
    
    cat > "${function_dir}/requirements.txt" << EOF
google-cloud-monitoring>=2.11.0
google-cloud-trace>=1.7.0
google-cloud-logging>=3.0.0
functions-framework>=3.0.0
EOF
    
    # Deploy the Cloud Function
    cd "${function_dir}"
    if ! gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-topic "${PUBSUB_TOPIC}" \
        --entry-point performance_optimizer \
        --memory 256MB \
        --timeout 60s \
        --source . 2>>"${DEPLOY_LOG}"; then
        log_error "Failed to deploy Cloud Function"
        cd "${SCRIPT_DIR}"
        rm -rf "${function_dir}"
        exit 1
    fi
    
    cd "${SCRIPT_DIR}"
    rm -rf "${function_dir}"
    
    log_success "Cloud Function deployed"
}

# Function to configure monitoring alerts
configure_monitoring() {
    log_info "Configuring Cloud Monitoring alert policies..."
    
    # Create alert policy configuration
    cat > "${SCRIPT_DIR}/alert-policy.json" << EOF
{
  "displayName": "High API Response Time Alert",
  "documentation": {
    "content": "API response time has exceeded acceptable thresholds",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "API Response Time Condition",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/api/response_time\" resource.type=\"global\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 1.5,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
EOF
    
    # Create the alert policy
    if ! gcloud alpha monitoring policies create --policy-from-file="${SCRIPT_DIR}/alert-policy.json" 2>>"${DEPLOY_LOG}"; then
        log_error "Failed to create alert policy"
        exit 1
    fi
    
    # Create Pub/Sub notification channel
    cat > "${SCRIPT_DIR}/notification-channel.json" << EOF
{
  "type": "pubsub",
  "displayName": "Performance Alert Channel",
  "description": "Pub/Sub channel for automated performance response",
  "labels": {
    "topic": "projects/${PROJECT_ID}/topics/${PUBSUB_TOPIC}"
  },
  "enabled": true
}
EOF
    
    # Create notification channel
    local channel_id
    if ! channel_id=$(gcloud alpha monitoring channels create \
        --channel-from-file="${SCRIPT_DIR}/notification-channel.json" \
        --format="value(name)" 2>>"${DEPLOY_LOG}"); then
        log_error "Failed to create notification channel"
        exit 1
    fi
    
    # Update alert policy with notification channel
    cat > "${SCRIPT_DIR}/updated-alert-policy.json" << EOF
{
  "displayName": "High API Response Time Alert",
  "documentation": {
    "content": "API response time has exceeded acceptable thresholds. Automated optimization triggered.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "API Response Time Condition",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/api/response_time\" resource.type=\"global\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 1.5,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ["${channel_id}"]
}
EOF
    
    # Get existing policy name and update it
    local policy_name
    if ! policy_name=$(gcloud alpha monitoring policies list \
        --filter="displayName='High API Response Time Alert'" \
        --format="value(name)" 2>>"${DEPLOY_LOG}"); then
        log_error "Failed to find alert policy"
        exit 1
    fi
    
    if ! gcloud alpha monitoring policies update "${policy_name}" \
        --policy-from-file="${SCRIPT_DIR}/updated-alert-policy.json" 2>>"${DEPLOY_LOG}"; then
        log_error "Failed to update alert policy with notification channel"
        exit 1
    fi
    
    # Save important IDs to state file
    echo "NOTIFICATION_CHANNEL_ID=${channel_id}" >> "${RESOURCE_STATE}"
    echo "ALERT_POLICY_NAME=${policy_name}" >> "${RESOURCE_STATE}"
    
    log_success "Monitoring alerts configured"
}

# Function to create monitoring dashboard
create_dashboard() {
    log_info "Creating custom monitoring dashboard..."
    
    cat > "${SCRIPT_DIR}/dashboard.json" << EOF
{
  "displayName": "Intelligent Performance Monitoring Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "API Response Time",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"custom.googleapis.com/api/response_time\" resource.type=\"global\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              },
              "plotType": "LINE"
            }],
            "yAxis": {
              "label": "Response Time (seconds)",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Function Executions",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"cloudfunctions.googleapis.com/function/executions\" resource.label.function_name=\"${FUNCTION_NAME}\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              },
              "plotType": "STACKED_BAR"
            }]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the dashboard
    local dashboard_id
    if ! dashboard_id=$(gcloud monitoring dashboards create \
        --config-from-file="${SCRIPT_DIR}/dashboard.json" \
        --format="value(name)" 2>>"${DEPLOY_LOG}"); then
        log_error "Failed to create dashboard"
        exit 1
    fi
    
    echo "DASHBOARD_ID=${dashboard_id}" >> "${RESOURCE_STATE}"
    
    log_success "Custom monitoring dashboard created"
}

# Function to generate test traffic
generate_test_traffic() {
    log_info "Generating test traffic to validate monitoring..."
    
    # Get application URL
    local instance_ip
    if ! instance_ip=$(gcloud compute instances describe "${INSTANCE_NAME}" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>>"${DEPLOY_LOG}"); then
        log_error "Failed to get instance IP"
        exit 1
    fi
    
    # Create traffic generation script
    cat > "${SCRIPT_DIR}/generate_traffic.sh" << 'EOF'
#!/bin/bash

APP_URL="http://$1:5000"

echo "Generating normal traffic..."
for i in {1..20}; do
    if curl -s "${APP_URL}/api/data" > /dev/null 2>&1; then
        echo -n "."
    else
        echo -n "x"
    fi
    sleep 2
done
echo

echo "Generating high-latency traffic to trigger alerts..."
for i in {1..10}; do
    # Multiple concurrent requests to increase load
    curl -s "${APP_URL}/api/data" &
    curl -s "${APP_URL}/api/data" &
    curl -s "${APP_URL}/api/data" &
    wait
    sleep 1
done

echo "Traffic generation completed"
EOF
    
    chmod +x "${SCRIPT_DIR}/generate_traffic.sh"
    
    log_info "Running traffic generation (this may take a few minutes)..."
    if "${SCRIPT_DIR}/generate_traffic.sh" "${instance_ip}"; then
        log_success "Test traffic generated successfully"
    else
        log_warning "Test traffic generation completed with some errors"
    fi
    
    echo "APPLICATION_URL=http://${instance_ip}:5000" >> "${RESOURCE_STATE}"
    
    log_info "Application URL: http://${instance_ip}:5000"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "=== Created Resources ==="
    echo "• Compute Instance: ${INSTANCE_NAME}"
    echo "• Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "• Cloud Function: ${FUNCTION_NAME}"
    echo "• Firewall Rule: allow-web-app"
    echo "• Alert Policy: High API Response Time Alert"
    echo "• Notification Channel: Performance Alert Channel"
    echo "• Dashboard: Intelligent Performance Monitoring Dashboard"
    echo
    echo "=== Access URLs ==="
    if [[ -f "${RESOURCE_STATE}" ]]; then
        source "${RESOURCE_STATE}"
        echo "• Application: ${APPLICATION_URL:-Not available}"
        echo "• Cloud Console: https://console.cloud.google.com/monitoring?project=${PROJECT_ID}"
        echo "• Monitoring Dashboard: https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"
    fi
    echo
    echo "=== Next Steps ==="
    echo "1. Monitor the application performance in Cloud Monitoring"
    echo "2. Review Cloud Trace data for request analysis"
    echo "3. Check Cloud Function logs for automated responses"
    echo "4. Generate additional traffic to test alert triggers"
    echo
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
    log_info "Deployment log saved to: ${DEPLOY_LOG}"
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Check ${DEPLOY_LOG} for details."
    log_info "Partial cleanup may be required. Run ./destroy.sh to remove any created resources."
    exit 1
}

# Main deployment function
main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    log_info "Starting deployment of Application Performance Monitoring solution..."
    log_info "Deployment log: ${DEPLOY_LOG}"
    
    # Clear previous log
    > "${DEPLOY_LOG}"
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_pubsub
    deploy_application
    deploy_cloud_function
    configure_monitoring
    create_dashboard
    generate_test_traffic
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/alert-policy.json"
    rm -f "${SCRIPT_DIR}/notification-channel.json"
    rm -f "${SCRIPT_DIR}/updated-alert-policy.json"
    rm -f "${SCRIPT_DIR}/dashboard.json"
    
    display_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
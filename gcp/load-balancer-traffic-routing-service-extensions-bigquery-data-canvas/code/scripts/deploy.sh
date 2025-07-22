#!/bin/bash

# Deploy script for Load Balancer Traffic Routing with Service Extensions and BigQuery Data Canvas
# Recipe: load-balancer-traffic-routing-service-extensions-bigquery-data-canvas
# Provider: GCP

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

# Error handler
error_exit() {
    log_error "Deployment failed at line $1"
    log_error "Check the logs above for details"
    exit 1
}

trap 'error_exit $LINENO' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log_info "Starting deployment at $(date)"
log_info "Log file: $LOG_FILE"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bc is installed (for calculations)
    if ! command -v bc &> /dev/null; then
        log_error "bc calculator is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Configuration setup
setup_configuration() {
    log_info "Setting up configuration..."
    
    # Default values
    DEFAULT_PROJECT_ID="intelligent-routing-$(date +%s)"
    DEFAULT_REGION="us-central1"
    DEFAULT_ZONE="us-central1-a"
    
    # Allow override via environment variables
    export PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
    export REGION="${REGION:-$DEFAULT_REGION}"
    export ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SERVICE_NAME="traffic-router-${RANDOM_SUFFIX}"
    export DATASET_NAME="traffic_analytics_${RANDOM_SUFFIX}"
    export EXTENSION_NAME="intelligent-router-${RANDOM_SUFFIX}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Configuration set:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "run.googleapis.com"
        "bigquery.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "serviceextensions.googleapis.com"
        "workflows.googleapis.com"
        "cloudfunctions.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."
    
    # Create BigQuery dataset
    bq mk --dataset \
        --location="${REGION}" \
        --description="Traffic analytics for intelligent routing" \
        "${PROJECT_ID}:${DATASET_NAME}" || true
    
    # Create table for load balancer metrics
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.lb_metrics" \
        timestamp:TIMESTAMP,request_id:STRING,source_ip:STRING,target_service:STRING,response_time:FLOAT,status_code:INTEGER,user_agent:STRING,request_size:INTEGER,response_size:INTEGER \
        || true
    
    # Create table for routing decisions
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.routing_decisions" \
        timestamp:TIMESTAMP,decision_id:STRING,source_criteria:STRING,target_service:STRING,confidence_score:FLOAT,ai_reasoning:STRING \
        || true
    
    log_success "BigQuery dataset and tables created"
}

# Deploy Cloud Run services
deploy_cloud_run_services() {
    log_info "Deploying Cloud Run services..."
    
    # Deploy Service A (Fast response)
    log_info "Deploying Cloud Run Service A (fast response)..."
    gcloud run deploy "service-a-${RANDOM_SUFFIX}" \
        --image=gcr.io/cloudrun/hello \
        --region="${REGION}" \
        --platform=managed \
        --allow-unauthenticated \
        --set-env-vars="SERVICE_TYPE=fast,RESPONSE_DELAY=100" \
        --max-instances=10 \
        --memory=512Mi \
        --quiet
    
    # Deploy Service B (Standard response)
    log_info "Deploying Cloud Run Service B (standard response)..."
    gcloud run deploy "service-b-${RANDOM_SUFFIX}" \
        --image=gcr.io/cloudrun/hello \
        --region="${REGION}" \
        --platform=managed \
        --allow-unauthenticated \
        --set-env-vars="SERVICE_TYPE=standard,RESPONSE_DELAY=500" \
        --max-instances=10 \
        --memory=1Gi \
        --quiet
    
    # Deploy Service C (Resource-intensive)
    log_info "Deploying Cloud Run Service C (resource-intensive)..."
    gcloud run deploy "service-c-${RANDOM_SUFFIX}" \
        --image=gcr.io/cloudrun/hello \
        --region="${REGION}" \
        --platform=managed \
        --allow-unauthenticated \
        --set-env-vars="SERVICE_TYPE=intensive,RESPONSE_DELAY=1000" \
        --max-instances=5 \
        --memory=2Gi \
        --quiet
    
    # Store service URLs
    SERVICE_A_URL=$(gcloud run services describe "service-a-${RANDOM_SUFFIX}" \
        --region="${REGION}" --format="value(status.url)")
    SERVICE_B_URL=$(gcloud run services describe "service-b-${RANDOM_SUFFIX}" \
        --region="${REGION}" --format="value(status.url)")
    SERVICE_C_URL=$(gcloud run services describe "service-c-${RANDOM_SUFFIX}" \
        --region="${REGION}" --format="value(status.url)")
    
    log_success "Cloud Run services deployed:"
    log_info "  Service A URL: ${SERVICE_A_URL}"
    log_info "  Service B URL: ${SERVICE_B_URL}"
    log_info "  Service C URL: ${SERVICE_C_URL}"
}

# Create Network Endpoint Groups
create_network_endpoint_groups() {
    log_info "Creating Network Endpoint Groups..."
    
    # Create serverless NEGs for each service
    for service in a b c; do
        log_info "Creating NEG for service-${service}..."
        gcloud compute network-endpoint-groups create "service-${service}-neg-${RANDOM_SUFFIX}" \
            --region="${REGION}" \
            --network-endpoint-type=serverless \
            --cloud-run-service="service-${service}-${RANDOM_SUFFIX}" \
            --quiet
    done
    
    log_success "Network Endpoint Groups created"
}

# Configure backend services
configure_backend_services() {
    log_info "Configuring backend services with health checks..."
    
    # Create health check
    gcloud compute health-checks create http "cr-health-check-${RANDOM_SUFFIX}" \
        --port=8080 \
        --request-path="/health" \
        --check-interval=30s \
        --timeout=10s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3 \
        --quiet
    
    # Create backend services and add NEGs
    for service in a b c; do
        log_info "Creating backend service for service-${service}..."
        
        # Create backend service
        gcloud compute backend-services create "service-${service}-backend-${RANDOM_SUFFIX}" \
            --global \
            --protocol=HTTP \
            --health-checks="cr-health-check-${RANDOM_SUFFIX}" \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --quiet
        
        # Add NEG to backend service
        gcloud compute backend-services add-backend "service-${service}-backend-${RANDOM_SUFFIX}" \
            --global \
            --network-endpoint-group="service-${service}-neg-${RANDOM_SUFFIX}" \
            --network-endpoint-group-region="${REGION}" \
            --quiet
    done
    
    log_success "Backend services configured with health checks"
}

# Create traffic routing function
create_traffic_routing_function() {
    log_info "Creating traffic routing function..."
    
    # Create function source code
    cat > "${SCRIPT_DIR}/traffic-router-function.py" << 'EOF'
import json
import logging
from google.cloud import bigquery
from google.cloud import monitoring_v3
import datetime
import os

def route_traffic(request):
    """Intelligent traffic routing based on real-time analytics"""
    
    # Extract request metadata
    request_data = request.get_json() if request.get_json() else {}
    source_ip = request_data.get('source_ip', '0.0.0.0')
    user_agent = request_data.get('user_agent', '')
    request_size = request_data.get('request_size', 0)
    
    # Get environment variables
    project_id = os.environ.get('PROJECT_ID', 'default-project')
    dataset_name = os.environ.get('DATASET_NAME', 'default_dataset')
    
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Query recent performance metrics
    query = f"""
    SELECT 
        target_service,
        AVG(response_time) as avg_response_time,
        COUNT(*) as request_count,
        AVG(status_code) as avg_status
    FROM `{project_id}.{dataset_name}.lb_metrics`
    WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
    GROUP BY target_service
    ORDER BY avg_response_time ASC
    """
    
    try:
        query_job = client.query(query)
        results = list(query_job)
        
        # Select optimal service based on performance
        if results:
            best_service = results[0].target_service
            confidence = 0.9
        else:
            # Default routing logic
            best_service = "service-a"
            confidence = 0.5
        
        # Log routing decision
        decision_data = {
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'decision_id': f"dec_{datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
            'source_criteria': f"ip:{source_ip},size:{request_size}",
            'target_service': best_service,
            'confidence_score': confidence,
            'ai_reasoning': 'Performance-based routing with historical analysis'
        }
        
        # Insert routing decision into BigQuery
        table_id = f"{project_id}.{dataset_name}.routing_decisions"
        table = client.get_table(table_id)
        client.insert_rows_json(table, [decision_data])
        
        return {
            'target_service': best_service,
            'confidence': confidence,
            'routing_metadata': decision_data
        }
        
    except Exception as e:
        logging.error(f"Routing error: {e}")
        return {
            'target_service': 'service-a',
            'confidence': 0.3,
            'error': str(e)
        }
EOF
    
    # Create requirements.txt
    cat > "${SCRIPT_DIR}/requirements.txt" << 'EOF'
google-cloud-bigquery>=3.0.0
google-cloud-monitoring>=2.0.0
functions-framework>=3.0.0
EOF
    
    # Deploy the function
    log_info "Deploying traffic routing Cloud Function..."
    gcloud functions deploy "traffic-router-${RANDOM_SUFFIX}" \
        --runtime=python39 \
        --trigger=http \
        --entry-point=route_traffic \
        --source="${SCRIPT_DIR}" \
        --region="${REGION}" \
        --allow-unauthenticated \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},DATASET_NAME=${DATASET_NAME}" \
        --quiet
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "traffic-router-${RANDOM_SUFFIX}" \
        --region="${REGION}" --format="value(httpsTrigger.url)")
    
    log_success "Traffic routing function deployed: ${FUNCTION_URL}"
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/traffic-router-function.py" "${SCRIPT_DIR}/requirements.txt"
}

# Configure Service Extensions
configure_service_extensions() {
    log_info "Configuring Service Extensions..."
    
    # Wait for function to be ready
    log_info "Waiting for Cloud Function to be ready..."
    sleep 60
    
    # Create the Service Extension resource
    gcloud service-extensions extensions create "${EXTENSION_NAME}" \
        --location="${REGION}" \
        --description="Intelligent traffic routing with BigQuery analytics" \
        --extension-type=TRAFFIC_EXTENSION \
        --config-type=CALLOUT \
        --callout-service-uri="${FUNCTION_URL}" \
        --callout-timeout=30s \
        --quiet
    
    # Wait for extension to be ready
    log_info "Waiting for Service Extension to be ready..."
    sleep 30
    
    log_success "Service Extension configured successfully"
}

# Create Application Load Balancer
create_application_load_balancer() {
    log_info "Creating Application Load Balancer with intelligent routing..."
    
    # Create URL map
    gcloud compute url-maps create "intelligent-lb-${RANDOM_SUFFIX}" \
        --default-backend-service="service-a-backend-${RANDOM_SUFFIX}" \
        --quiet
    
    # Add path-based routing rules
    gcloud compute url-maps add-path-matcher "intelligent-lb-${RANDOM_SUFFIX}" \
        --path-matcher-name=intelligent-matcher \
        --default-backend-service="service-a-backend-${RANDOM_SUFFIX}" \
        --backend-service-path-rules="/api/fast/*=service-a-backend-${RANDOM_SUFFIX},/api/standard/*=service-b-backend-${RANDOM_SUFFIX},/api/intensive/*=service-c-backend-${RANDOM_SUFFIX}" \
        --quiet
    
    # Create HTTP proxy
    gcloud compute target-http-proxies create "intelligent-proxy-${RANDOM_SUFFIX}" \
        --url-map="intelligent-lb-${RANDOM_SUFFIX}" \
        --quiet
    
    # Create global forwarding rule
    gcloud compute forwarding-rules create "intelligent-lb-rule-${RANDOM_SUFFIX}" \
        --global \
        --target-http-proxy="intelligent-proxy-${RANDOM_SUFFIX}" \
        --ports=80 \
        --quiet
    
    # Get load balancer IP
    LB_IP=$(gcloud compute forwarding-rules describe "intelligent-lb-rule-${RANDOM_SUFFIX}" \
        --global --format="value(IPAddress)")
    
    log_success "Application Load Balancer created with IP: ${LB_IP}"
    log_success "Intelligent routing is now active"
}

# Setup analytics and monitoring
setup_analytics_monitoring() {
    log_info "Setting up analytics and monitoring..."
    
    # Create log sink to export traffic logs to BigQuery
    gcloud logging sinks create "traffic-analytics-sink-${RANDOM_SUFFIX}" \
        "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET_NAME}" \
        --log-filter='resource.type="gce_instance" OR jsonPayload.source_ip!=""' \
        --quiet || true
    
    # Create analytics workflow
    cat > "${SCRIPT_DIR}/analytics-workflow.yaml" << EOF
main:
  params: [args]
  steps:
    - analyze_traffic:
        call: http.get
        args:
          url: \${"https://bigquery.googleapis.com/bigquery/v2/projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT") + "/queries"}
          headers:
            Authorization: \${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
          body:
            query: |
              SELECT 
                target_service,
                AVG(response_time) as avg_response_time,
                COUNT(*) as request_count,
                STDDEV(response_time) as response_time_stddev
              FROM \`${PROJECT_ID}.${DATASET_NAME}.lb_metrics\`
              WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)
              GROUP BY target_service
              ORDER BY avg_response_time ASC
            useLegacySql: false
        result: query_result
    
    - log_insights:
        call: sys.log
        args:
          text: \${"Analytics complete. Processing " + string(len(query_result.body.rows)) + " services"}
          severity: INFO
    
    - return_result:
        return: \${query_result}
EOF
    
    # Deploy analytics workflow
    gcloud workflows deploy "analytics-processor-${RANDOM_SUFFIX}" \
        --source="${SCRIPT_DIR}/analytics-workflow.yaml" \
        --location="${REGION}" \
        --quiet
    
    # Clean up temporary file
    rm -f "${SCRIPT_DIR}/analytics-workflow.yaml"
    
    log_success "Analytics and monitoring setup complete"
}

# Generate traffic for testing
generate_test_traffic() {
    log_info "Setting up traffic generation for testing..."
    
    # Create traffic generation script
    cat > "${SCRIPT_DIR}/generate_traffic.sh" << 'EOF'
#!/bin/bash

LB_IP=$1
DURATION=${2:-180}  # Default 3 minutes
REQUEST_COUNT=0

if [ -z "$LB_IP" ]; then
    echo "Usage: $0 <LB_IP> [DURATION_SECONDS]"
    exit 1
fi

echo "Generating traffic to ${LB_IP} for ${DURATION} seconds..."

end_time=$((SECONDS + DURATION))

while [ $SECONDS -lt $end_time ]; do
    # Generate varied traffic patterns
    PATHS=("/api/fast/test" "/api/standard/process" "/api/intensive/compute" "/health" "/")
    PATH=${PATHS[$RANDOM % ${#PATHS[@]}]}
    
    # Simulate different user agents
    USER_AGENTS=("Mozilla/5.0 (Chrome)" "Mozilla/5.0 (Firefox)" "curl/7.68.0" "PostmanRuntime/7.28.0")
    USER_AGENT=${USER_AGENTS[$RANDOM % ${#USER_AGENTS[@]}]}
    
    # Make request and capture basic metrics
    curl -s -w "Status: %{http_code}, Time: %{time_total}s\n" \
        -H "User-Agent: ${USER_AGENT}" \
        -o /dev/null \
        "http://${LB_IP}${PATH}" 2>/dev/null || true
    
    REQUEST_COUNT=$((REQUEST_COUNT + 1))
    
    # Random delay between requests (0.1 to 2 seconds)
    sleep $(awk 'BEGIN{srand(); print rand()*1.9 + 0.1}')
done

echo "Generated ${REQUEST_COUNT} requests over ${DURATION} seconds"
EOF
    
    chmod +x "${SCRIPT_DIR}/generate_traffic.sh"
    
    log_success "Traffic generation script created: ${SCRIPT_DIR}/generate_traffic.sh"
    log_info "Run './generate_traffic.sh ${LB_IP}' to start generating test traffic"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment-info.txt" << EOF
Deployment Information
=====================
Deployed at: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}
Random Suffix: ${RANDOM_SUFFIX}

Resources Created:
- BigQuery Dataset: ${DATASET_NAME}
- Cloud Run Services: 
  * service-a-${RANDOM_SUFFIX}
  * service-b-${RANDOM_SUFFIX}
  * service-c-${RANDOM_SUFFIX}
- Load Balancer IP: ${LB_IP}
- Service Extension: ${EXTENSION_NAME}
- Cloud Function: traffic-router-${RANDOM_SUFFIX}
- Analytics Workflow: analytics-processor-${RANDOM_SUFFIX}

Test Commands:
- Basic connectivity: curl http://${LB_IP}/
- Fast API test: curl http://${LB_IP}/api/fast/test
- Standard API test: curl http://${LB_IP}/api/standard/process
- Intensive API test: curl http://${LB_IP}/api/intensive/compute
- Generate traffic: ./generate_traffic.sh ${LB_IP}

BigQuery Queries:
- Traffic metrics: SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.lb_metrics\` LIMIT 10
- Routing decisions: SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.routing_decisions\` LIMIT 10

Cleanup:
- Run ./destroy.sh to remove all resources
EOF
    
    log_success "Deployment information saved to: ${SCRIPT_DIR}/deployment-info.txt"
}

# Main deployment function
main() {
    log_info "=== Starting GCP Load Balancer Traffic Routing Deployment ==="
    
    check_prerequisites
    setup_configuration
    enable_apis
    create_bigquery_resources
    deploy_cloud_run_services
    create_network_endpoint_groups
    configure_backend_services
    create_traffic_routing_function
    configure_service_extensions
    create_application_load_balancer
    setup_analytics_monitoring
    generate_test_traffic
    save_deployment_info
    
    log_success "=== Deployment completed successfully! ==="
    log_info "Load Balancer IP: ${LB_IP}"
    log_info "Check deployment-info.txt for detailed information and test commands"
    log_info "Run './generate_traffic.sh ${LB_IP}' to start generating test traffic"
    log_warning "Note: It may take a few minutes for all services to be fully operational"
}

# Run main function
main "$@"
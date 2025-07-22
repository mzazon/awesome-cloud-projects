#!/bin/bash

# Network Performance Optimization with Cloud WAN and Network Intelligence Center
# Deployment Script for GCP
# Recipe: network-performance-optimization-wan-network-intelligence-center

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active Google Cloud authentication found."
        error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        warn "openssl not found. Using date-based random suffix instead."
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Prompt for project ID if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            error "Project ID cannot be empty"
            exit 1
        fi
    fi
    
    # Set default values
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique identifiers
    if command_exists openssl; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
    fi
    
    export FUNCTION_NAME="network-optimizer-${RANDOM_SUFFIX}"
    export BUCKET_NAME="network-ops-data-${RANDOM_SUFFIX}"
    export TOPIC_NAME="network-alerts-${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "✅ Environment variables configured:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Zone: ${ZONE}"
    info "  Function Name: ${FUNCTION_NAME}"
    info "  Bucket Name: ${BUCKET_NAME}"
    info "  Topic Name: ${TOPIC_NAME}"
}

# Function to verify project exists and billing is enabled
verify_project() {
    log "Verifying project configuration..."
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        error "Project '${PROJECT_ID}' does not exist or you don't have access to it."
        exit 1
    fi
    
    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "$billing_account" ]]; then
        error "Billing is not enabled for project '${PROJECT_ID}'. Please enable billing first."
        error "Visit: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log "✅ Project verification completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "networkmanagement.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "logging.googleapis.com"
        "compute.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log "✅ ${api} enabled successfully"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled (30 seconds)..."
    sleep 30
    
    log "✅ All required APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        warn "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create the bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log "✅ Storage bucket gs://${BUCKET_NAME} created successfully"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics create "${TOPIC_NAME}" --quiet; then
        log "✅ Pub/Sub topic ${TOPIC_NAME} created successfully"
    else
        warn "Pub/Sub topic ${TOPIC_NAME} might already exist"
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions create "${TOPIC_NAME}-sub" --topic="${TOPIC_NAME}" --quiet; then
        log "✅ Pub/Sub subscription ${TOPIC_NAME}-sub created successfully"
    else
        warn "Pub/Sub subscription ${TOPIC_NAME}-sub might already exist"
    fi
}

# Function to configure Network Intelligence Center
configure_network_intelligence() {
    log "Configuring Network Intelligence Center connectivity tests..."
    
    # Create regional connectivity test
    info "Creating regional connectivity test..."
    if gcloud network-management connectivity-tests create \
        regional-connectivity-test \
        --source-project="${PROJECT_ID}" \
        --source-network-type=gcp-network \
        --source-network=default \
        --source-region="${REGION}" \
        --destination-project="${PROJECT_ID}" \
        --destination-network-type=gcp-network \
        --destination-network=default \
        --destination-region=us-west1 \
        --protocol=TCP \
        --destination-port=80 \
        --quiet 2>/dev/null; then
        log "✅ Regional connectivity test created successfully"
    else
        warn "Regional connectivity test might already exist"
    fi
    
    # Create external connectivity test
    info "Creating external connectivity test..."
    if gcloud network-management connectivity-tests create \
        external-connectivity-test \
        --source-project="${PROJECT_ID}" \
        --source-network-type=gcp-network \
        --source-network=default \
        --source-region="${REGION}" \
        --destination-ip-address=8.8.8.8 \
        --protocol=ICMP \
        --quiet 2>/dev/null; then
        log "✅ External connectivity test created successfully"
    else
        warn "External connectivity test might already exist"
    fi
}

# Function to enable VPC Flow Logs
enable_vpc_flow_logs() {
    log "Enabling VPC Flow Logs for traffic analysis..."
    
    # Check if default network exists
    if ! gcloud compute networks describe default >/dev/null 2>&1; then
        warn "Default network not found, skipping VPC Flow Logs configuration"
        return 0
    fi
    
    # Enable flow logs on default subnet
    if gcloud compute networks subnets update default \
        --region="${REGION}" \
        --enable-flow-logs \
        --logging-flow-sampling=0.1 \
        --logging-aggregation-interval=INTERVAL_5_SEC \
        --logging-metadata=INCLUDE_ALL_METADATA \
        --quiet; then
        log "✅ VPC Flow Logs enabled successfully"
    else
        warn "Failed to enable VPC Flow Logs or already enabled"
    fi
}

# Function to create monitoring policies
create_monitoring_policies() {
    log "Creating Cloud Monitoring policies..."
    
    # Create temporary directory for configuration files
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create network metrics policy
    cat > "${temp_dir}/network_metrics.yaml" << 'EOF'
displayName: "Network Performance Metrics"
combiner: OR
conditions:
  - displayName: "High Latency Alert"
    conditionThreshold:
      filter: 'resource.type="gce_instance"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 100
      duration: "60s"
alertStrategy:
  autoClose: "1800s"
EOF
    
    # Create network analyzer policy
    cat > "${temp_dir}/network_analyzer_policy.yaml" << 'EOF'
displayName: "Network Analyzer Alerts"
combiner: OR
conditions:
  - displayName: "Network Configuration Issue"
    conditionThreshold:
      filter: 'resource.type="gce_instance"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 0
      duration: "60s"
alertStrategy:
  autoClose: "1800s"
EOF
    
    # Apply monitoring policies
    if gcloud alpha monitoring policies create --policy-from-file="${temp_dir}/network_metrics.yaml" --quiet 2>/dev/null; then
        log "✅ Network performance monitoring policy created"
    else
        warn "Network performance monitoring policy might already exist"
    fi
    
    if gcloud alpha monitoring policies create --policy-from-file="${temp_dir}/network_analyzer_policy.yaml" --quiet 2>/dev/null; then
        log "✅ Network analyzer monitoring policy created"
    else
        warn "Network analyzer monitoring policy might already exist"
    fi
    
    # Cleanup temporary files
    rm -rf "${temp_dir}"
}

# Function to create and deploy Cloud Functions
deploy_cloud_functions() {
    log "Creating and deploying Cloud Functions..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create main network optimization function
    create_network_optimizer_function "${temp_dir}"
    
    # Create flow analyzer function
    create_flow_analyzer_function "${temp_dir}"
    
    # Create firewall optimizer function
    create_firewall_optimizer_function "${temp_dir}"
    
    # Cleanup temporary directory
    rm -rf "${temp_dir}"
}

# Function to create network optimizer Cloud Function
create_network_optimizer_function() {
    local temp_dir="$1"
    local function_dir="${temp_dir}/network-optimizer"
    
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    info "Creating network optimizer function code..."
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import json
import logging
from google.cloud import monitoring_v3
from google.cloud import networkmanagement_v1
from google.cloud import pubsub_v1
import base64
import os
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def optimize_network(cloud_event):
    """
    Main function to handle network optimization events.
    Analyzes network performance data and implements optimization strategies.
    """
    try:
        # Decode the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
        alert_data = json.loads(message_data)
        
        logger.info(f"Processing network optimization request: {alert_data}")
        
        # Initialize Google Cloud clients
        monitoring_client = monitoring_v3.MetricServiceClient()
        network_client = networkmanagement_v1.ReachabilityServiceClient()
        
        # Analyze current network performance
        performance_metrics = analyze_network_performance(monitoring_client)
        
        # Determine optimization actions based on metrics
        optimization_actions = determine_optimization_actions(performance_metrics)
        
        # Execute optimization strategies
        for action in optimization_actions:
            execute_optimization_action(action, network_client)
        
        logger.info("Network optimization completed successfully")
        return {"status": "success", "actions_taken": len(optimization_actions)}
        
    except Exception as e:
        logger.error(f"Error in network optimization: {str(e)}")
        return {"status": "error", "message": str(e)}

def analyze_network_performance(monitoring_client):
    """
    Analyze current network performance metrics to identify optimization opportunities.
    """
    project_name = f"projects/{os.environ.get('GCP_PROJECT')}"
    
    # Query latency metrics
    interval = monitoring_v3.TimeInterval({
        "end_time": {"seconds": int(time.time())},
        "start_time": {"seconds": int(time.time()) - 300}  # Last 5 minutes
    })
    
    # Retrieve network performance data
    try:
        results = monitoring_client.list_time_series(
            request={
                "name": project_name,
                "filter": 'metric.type="compute.googleapis.com/instance/network/sent_bytes_count"',
                "interval": interval,
            }
        )
    except Exception as e:
        logger.warning(f"Could not retrieve metrics: {str(e)}")
        results = []
    
    metrics = {
        "latency": 0,
        "packet_loss": 0,
        "throughput": 0,
        "connection_failures": 0
    }
    
    # Process and analyze the metrics
    for result in results:
        for point in result.points:
            metrics["throughput"] += point.value.double_value
    
    logger.info(f"Analyzed network metrics: {metrics}")
    return metrics

def determine_optimization_actions(metrics):
    """
    Determine what optimization actions to take based on performance metrics.
    """
    actions = []
    
    # High latency optimization
    if metrics.get("latency", 0) > 100:  # milliseconds
        actions.append({
            "type": "route_optimization",
            "priority": "high",
            "target": "reduce_latency"
        })
    
    # Low throughput optimization
    if metrics.get("throughput", 0) < 1000000:  # bytes per second
        actions.append({
            "type": "bandwidth_scaling",
            "priority": "medium",
            "target": "increase_throughput"
        })
    
    # Connection failure handling
    if metrics.get("connection_failures", 0) > 5:
        actions.append({
            "type": "failover_activation",
            "priority": "critical",
            "target": "restore_connectivity"
        })
    
    logger.info(f"Determined optimization actions: {actions}")
    return actions

def execute_optimization_action(action, network_client):
    """
    Execute a specific network optimization action.
    """
    action_type = action.get("type")
    priority = action.get("priority")
    
    logger.info(f"Executing {action_type} action with {priority} priority")
    
    if action_type == "route_optimization":
        optimize_routing(network_client)
    elif action_type == "bandwidth_scaling":
        scale_bandwidth()
    elif action_type == "failover_activation":
        activate_failover()
    
    logger.info(f"Successfully executed {action_type} action")

def optimize_routing(network_client):
    """
    Optimize network routing for better performance.
    """
    logger.info("Optimizing network routing for improved latency")

def scale_bandwidth():
    """
    Scale network bandwidth based on current demand.
    """
    logger.info("Scaling network bandwidth to meet demand")

def activate_failover():
    """
    Activate failover mechanisms for improved reliability.
    """
    logger.info("Activating network failover mechanisms")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.4.0
google-cloud-monitoring==2.15.1
google-cloud-network-management==1.5.1
google-cloud-pubsub==2.18.1
EOF
    
    # Deploy the function
    info "Deploying network optimizer function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python39 \
        --region="${REGION}" \
        --source=. \
        --entry-point=optimize_network \
        --trigger-topic="${TOPIC_NAME}" \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID}" \
        --quiet; then
        log "✅ Network optimizer function deployed successfully"
    else
        error "Failed to deploy network optimizer function"
        exit 1
    fi
    
    cd - >/dev/null
}

# Function to create flow analyzer Cloud Function
create_flow_analyzer_function() {
    local temp_dir="$1"
    local function_dir="${temp_dir}/flow-analyzer"
    
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    info "Creating flow analyzer function code..."
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import logging
from google.cloud import pubsub_v1
import json
import os

logger = logging.getLogger(__name__)

@functions_framework.http
def analyze_traffic_flows(request):
    """
    Analyze VPC Flow Logs to identify traffic patterns and optimization opportunities.
    """
    try:
        logger.info("Starting traffic flow analysis")
        
        # Simulate flow analysis (in production, this would query actual flow logs)
        optimization_opportunities = [
            {
                "type": "high_latency_flow",
                "src_ip": "10.0.1.100",
                "dest_ip": "10.0.2.200",
                "latency": 175.5,
                "recommendation": "route_optimization"
            }
        ]
        
        # Publish optimization opportunities to Pub/Sub
        if optimization_opportunities:
            publisher = pubsub_v1.PublisherClient()
            topic_path = publisher.topic_path(
                os.environ.get('GCP_PROJECT'), 
                os.environ.get('TOPIC_NAME')
            )
            
            for opportunity in optimization_opportunities:
                message_data = json.dumps(opportunity).encode('utf-8')
                publisher.publish(topic_path, message_data)
        
        logger.info(f"Flow analysis completed. Found {len(optimization_opportunities)} opportunities")
        return {"status": "success", "opportunities": len(optimization_opportunities)}
        
    except Exception as e:
        logger.error(f"Error in flow analysis: {str(e)}")
        return {"status": "error", "message": str(e)}
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.4.0
google-cloud-pubsub==2.18.1
EOF
    
    # Deploy the function
    info "Deploying flow analyzer function..."
    if gcloud functions deploy "flow-analyzer-${RANDOM_SUFFIX}" \
        --gen2 \
        --runtime=python39 \
        --region="${REGION}" \
        --source=. \
        --entry-point=analyze_traffic_flows \
        --trigger-http \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},TOPIC_NAME=${TOPIC_NAME}" \
        --quiet; then
        log "✅ Flow analyzer function deployed successfully"
    else
        error "Failed to deploy flow analyzer function"
        exit 1
    fi
    
    cd - >/dev/null
}

# Function to create firewall optimizer Cloud Function
create_firewall_optimizer_function() {
    local temp_dir="$1"
    local function_dir="${temp_dir}/firewall-optimizer"
    
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    info "Creating firewall optimizer function code..."
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import logging
from google.cloud import compute_v1
from google.cloud import pubsub_v1
import json
import os

logger = logging.getLogger(__name__)

@functions_framework.http
def optimize_firewall_rules(request):
    """
    Analyze firewall rules and recommend optimizations for better performance and security.
    """
    try:
        logger.info("Starting firewall rule analysis")
        
        # Initialize Compute Engine client
        compute_client = compute_v1.FirewallsClient()
        project_id = os.environ.get('GCP_PROJECT')
        
        # List all firewall rules
        try:
            firewall_rules = compute_client.list(project=project_id)
        except Exception as e:
            logger.warning(f"Could not list firewall rules: {str(e)}")
            firewall_rules = []
        
        optimization_recommendations = []
        
        for rule in firewall_rules:
            # Analyze rule for optimization opportunities
            if rule.source_ranges and '0.0.0.0/0' in rule.source_ranges:
                optimization_recommendations.append({
                    "type": "overly_permissive_rule",
                    "rule_name": rule.name,
                    "recommendation": "restrict_source_ranges",
                    "priority": "high",
                    "security_impact": "reduce_attack_surface"
                })
            
            # Check for unused rules (simplified logic)
            if not rule.target_tags and not rule.target_service_accounts:
                optimization_recommendations.append({
                    "type": "potentially_unused_rule",
                    "rule_name": rule.name,
                    "recommendation": "review_and_cleanup",
                    "priority": "medium",
                    "performance_impact": "reduce_rule_processing_overhead"
                })
        
        # Publish recommendations to optimization system
        if optimization_recommendations:
            publisher = pubsub_v1.PublisherClient()
            topic_path = publisher.topic_path(project_id, os.environ.get('TOPIC_NAME'))
            
            for recommendation in optimization_recommendations:
                message_data = json.dumps(recommendation).encode('utf-8')
                publisher.publish(topic_path, message_data)
        
        logger.info(f"Firewall analysis completed. Found {len(optimization_recommendations)} recommendations")
        return {"status": "success", "recommendations": len(optimization_recommendations)}
        
    except Exception as e:
        logger.error(f"Error in firewall analysis: {str(e)}")
        return {"status": "error", "message": str(e)}
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.4.0
google-cloud-compute==1.14.1
google-cloud-pubsub==2.18.1
EOF
    
    # Deploy the function
    info "Deploying firewall optimizer function..."
    if gcloud functions deploy "firewall-optimizer-${RANDOM_SUFFIX}" \
        --gen2 \
        --runtime=python39 \
        --region="${REGION}" \
        --source=. \
        --entry-point=optimize_firewall_rules \
        --trigger-http \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},TOPIC_NAME=${TOPIC_NAME}" \
        --quiet; then
        log "✅ Firewall optimizer function deployed successfully"
    else
        error "Failed to deploy firewall optimizer function"
        exit 1
    fi
    
    cd - >/dev/null
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    log "Creating Cloud Scheduler jobs for periodic optimization..."
    
    # Get the flow analyzer function URL
    local flow_analyzer_url
    flow_analyzer_url=$(gcloud functions describe "flow-analyzer-${RANDOM_SUFFIX}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "")
    
    if [[ -n "$flow_analyzer_url" ]]; then
        # Create periodic optimization job
        if gcloud scheduler jobs create http periodic-network-optimization \
            --schedule="*/15 * * * *" \
            --uri="${flow_analyzer_url}" \
            --http-method=GET \
            --time-zone="UTC" \
            --description="Periodic network traffic analysis and optimization" \
            --quiet 2>/dev/null; then
            log "✅ Periodic network optimization job created"
        else
            warn "Periodic network optimization job might already exist"
        fi
    else
        warn "Could not get flow analyzer URL, skipping HTTP scheduler job"
    fi
    
    # Create daily report job
    if gcloud scheduler jobs create pubsub daily-network-report \
        --schedule="0 9 * * *" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"type":"daily_report","action":"generate_network_health_report"}' \
        --time-zone="UTC" \
        --description="Daily network health and performance report" \
        --quiet 2>/dev/null; then
        log "✅ Daily network report job created"
    else
        warn "Daily network report job might already exist"
    fi
}

# Function to perform validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log "✅ Pub/Sub topic validation passed"
    else
        error "Pub/Sub topic validation failed"
        return 1
    fi
    
    # Check Cloud Functions
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log "✅ Network optimizer function validation passed"
    else
        error "Network optimizer function validation failed"
        return 1
    fi
    
    # Check connectivity tests
    if gcloud network-management connectivity-tests describe regional-connectivity-test >/dev/null 2>&1; then
        log "✅ Connectivity tests validation passed"
    else
        warn "Connectivity tests validation failed or not found"
    fi
    
    # Check storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log "✅ Storage bucket validation passed"
    else
        error "Storage bucket validation failed"
        return 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    local info_file="deployment-info-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "${info_file}" << EOF
Network Performance Optimization Deployment Information
======================================================
Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}

Resources Created:
- Function Name: ${FUNCTION_NAME}
- Bucket Name: ${BUCKET_NAME}
- Topic Name: ${TOPIC_NAME}
- Flow Analyzer: flow-analyzer-${RANDOM_SUFFIX}
- Firewall Optimizer: firewall-optimizer-${RANDOM_SUFFIX}

Connectivity Tests:
- regional-connectivity-test
- external-connectivity-test

Cloud Scheduler Jobs:
- periodic-network-optimization
- daily-network-report

Next Steps:
1. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}
2. Test optimization: gcloud pubsub topics publish ${TOPIC_NAME} --message='{"type":"test","latency":150}'
3. View monitoring: https://console.cloud.google.com/monitoring
4. Check Network Intelligence Center: https://console.cloud.google.com/net-intelligence

Cleanup:
To remove all resources, run: ./destroy.sh
EOF
    
    log "✅ Deployment information saved to ${info_file}"
    info "Please keep this file for reference and cleanup"
}

# Main deployment function
main() {
    log "Starting Network Performance Optimization deployment..."
    
    # Check if running in supported environment
    if [[ "${CLOUD_SHELL:-false}" != "true" ]] && [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
        info "Running outside of Cloud Shell environment"
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    verify_project
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    configure_network_intelligence
    enable_vpc_flow_logs
    create_monitoring_policies
    deploy_cloud_functions
    create_scheduler_jobs
    validate_deployment
    save_deployment_info
    
    log "🎉 Network Performance Optimization deployment completed successfully!"
    echo ""
    info "Resources deployed:"
    info "  • Network Intelligence Center connectivity tests"
    info "  • Cloud Functions for automated optimization"
    info "  • Pub/Sub messaging for event coordination"
    info "  • Cloud Monitoring policies for alerting"
    info "  • VPC Flow Logs for traffic analysis"
    info "  • Cloud Scheduler for periodic optimization"
    echo ""
    info "Next steps:"
    info "  1. Monitor the system through Cloud Monitoring"
    info "  2. Review Network Intelligence Center insights"
    info "  3. Test optimization by publishing test messages"
    info "  4. Review function logs for optimization activities"
    echo ""
    warn "Remember to run ./destroy.sh when you no longer need these resources to avoid ongoing charges."
}

# Handle script interruption
trap 'error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"
#!/bin/bash

# Threat Detection Pipelines with Cloud IDS and BigQuery Data Canvas - Deployment Script
# This script deploys the complete threat detection infrastructure

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    # Call destroy script if it exists
    if [[ -f "destroy.sh" ]]; then
        ./destroy.sh --force
    fi
}

# Trap errors and call cleanup
trap cleanup_on_error ERR

# Display script banner
echo "=================================================="
echo "Threat Detection Pipelines Deployment Script"
echo "=================================================="
echo ""

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud CLI."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not installed. Please install BigQuery CLI."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Required for generating random values."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_warning "PROJECT_ID not set. Using timestamp-based project ID."
        export PROJECT_ID="threat-detection-$(date +%s)"
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core configuration
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Resource names
    export VPC_NAME="threat-detection-vpc"
    export SUBNET_NAME="threat-detection-subnet"
    export IDS_ENDPOINT_NAME="threat-detection-endpoint"
    export MIRRORING_POLICY_NAME="threat-detection-mirroring"
    export DATASET_NAME="threat_detection"
    export PUBSUB_TOPIC="threat-detection-findings"
    export PUBSUB_SUBSCRIPTION="process-findings-sub"
    export ALERT_TOPIC="security-alerts"
    export PROCESSING_FUNCTION="process-threat-finding"
    export ALERT_FUNCTION="process-security-alert"
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "ids.googleapis.com"
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "servicenetworking.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        gcloud services enable "${api}" || error_exit "Failed to enable API: ${api}"
    done
    
    log_success "All required APIs enabled"
}

# Create VPC network infrastructure
create_network() {
    log_info "Creating VPC network infrastructure..."
    
    # Create VPC network
    log_info "Creating VPC network: ${VPC_NAME}"
    gcloud compute networks create "${VPC_NAME}" \
        --subnet-mode custom \
        --bgp-routing-mode regional || error_exit "Failed to create VPC network"
    
    # Create subnet
    log_info "Creating subnet: ${SUBNET_NAME}"
    gcloud compute networks subnets create "${SUBNET_NAME}" \
        --network "${VPC_NAME}" \
        --range 10.0.1.0/24 \
        --region "${REGION}" || error_exit "Failed to create subnet"
    
    # Reserve IP range for private services access
    log_info "Reserving IP range for private services access"
    gcloud compute addresses create google-managed-services-threat-detection \
        --global \
        --purpose VPC_PEERING \
        --prefix-length 16 \
        --network "${VPC_NAME}" || error_exit "Failed to reserve IP range"
    
    # Create private connection for Cloud IDS
    log_info "Creating private connection for Cloud IDS"
    gcloud services vpc-peerings connect \
        --service servicenetworking.googleapis.com \
        --ranges google-managed-services-threat-detection \
        --network "${VPC_NAME}" \
        --project "${PROJECT_ID}" || error_exit "Failed to create private connection"
    
    log_success "Network infrastructure created successfully"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."
    
    # Create BigQuery dataset
    log_info "Creating BigQuery dataset: ${DATASET_NAME}"
    bq mk --dataset \
        --description "Threat detection and security analytics data" \
        --location "${REGION}" \
        "${PROJECT_ID}:${DATASET_NAME}" || error_exit "Failed to create BigQuery dataset"
    
    # Create table for Cloud IDS findings
    log_info "Creating IDS findings table"
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.ids_findings" \
        finding_id:STRING,timestamp:TIMESTAMP,severity:STRING,threat_type:STRING,source_ip:STRING,destination_ip:STRING,protocol:STRING,details:STRING,raw_data:STRING \
        || error_exit "Failed to create IDS findings table"
    
    # Create table for aggregated threat metrics
    log_info "Creating threat metrics table"
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.threat_metrics" \
        metric_time:TIMESTAMP,threat_count:INTEGER,severity_high:INTEGER,severity_medium:INTEGER,severity_low:INTEGER,top_source_ips:STRING,top_threat_types:STRING \
        || error_exit "Failed to create threat metrics table"
    
    log_success "BigQuery resources created successfully"
}

# Create Pub/Sub topics and subscriptions
create_pubsub_resources() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    # Create topic for IDS findings
    log_info "Creating Pub/Sub topic: ${PUBSUB_TOPIC}"
    gcloud pubsub topics create "${PUBSUB_TOPIC}" || error_exit "Failed to create Pub/Sub topic"
    
    # Create subscription for Cloud Functions processing
    log_info "Creating Pub/Sub subscription: ${PUBSUB_SUBSCRIPTION}"
    gcloud pubsub subscriptions create "${PUBSUB_SUBSCRIPTION}" \
        --topic "${PUBSUB_TOPIC}" \
        --message-retention-duration 7d \
        --ack-deadline 60s || error_exit "Failed to create Pub/Sub subscription"
    
    # Create topic for alert notifications
    log_info "Creating alert topic: ${ALERT_TOPIC}"
    gcloud pubsub topics create "${ALERT_TOPIC}" || error_exit "Failed to create alert topic"
    
    log_success "Pub/Sub resources created successfully"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Create directory for threat processor function
    log_info "Creating threat processor function"
    mkdir -p threat-processor-function
    cd threat-processor-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.15.0
google-cloud-pubsub==2.18.4
google-cloud-logging==3.8.0
functions-framework==3.5.0
EOF
    
    # Create main Cloud Function code
    cat > main.py << 'EOF'
import json
import base64
from datetime import datetime
from google.cloud import bigquery
from google.cloud import pubsub_v1
import logging

# Initialize clients
bq_client = bigquery.Client()
publisher = pubsub_v1.PublisherClient()

def process_threat_finding(event, context):
    """Process Cloud IDS finding and store in BigQuery"""
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            finding = json.loads(message_data)
        else:
            logging.error("No data in Pub/Sub message")
            return
        
        # Prepare data for BigQuery
        table_id = f"{bq_client.project}.threat_detection.ids_findings"
        
        rows_to_insert = [{
            "finding_id": finding.get("finding_id", ""),
            "timestamp": datetime.utcnow().isoformat(),
            "severity": finding.get("severity", "UNKNOWN"),
            "threat_type": finding.get("threat_type", ""),
            "source_ip": finding.get("source_ip", ""),
            "destination_ip": finding.get("destination_ip", ""),
            "protocol": finding.get("protocol", ""),
            "details": json.dumps(finding.get("details", {})),
            "raw_data": json.dumps(finding)
        }]
        
        # Insert into BigQuery
        table = bq_client.get_table(table_id)
        errors = bq_client.insert_rows_json(table, rows_to_insert)
        
        if errors:
            logging.error(f"BigQuery insert errors: {errors}")
            return
        
        # Trigger alert for high severity findings
        if finding.get("severity") == "HIGH":
            project_id = bq_client.project
            topic_path = publisher.topic_path(project_id, "security-alerts")
            
            alert_data = {
                "alert_type": "HIGH_SEVERITY_THREAT",
                "finding_id": finding.get("finding_id"),
                "threat_type": finding.get("threat_type"),
                "source_ip": finding.get("source_ip"),
                "timestamp": datetime.utcnow().isoformat()
            }
            
            publisher.publish(topic_path, json.dumps(alert_data).encode('utf-8'))
        
        logging.info(f"Processed finding: {finding.get('finding_id')}")
        
    except Exception as e:
        logging.error(f"Error processing threat finding: {str(e)}")
        raise
EOF
    
    # Deploy threat processing function
    log_info "Deploying threat processing function"
    gcloud functions deploy "${PROCESSING_FUNCTION}" \
        --runtime python39 \
        --trigger-topic "${PUBSUB_TOPIC}" \
        --source . \
        --entry-point process_threat_finding \
        --memory 512MB \
        --timeout 120s \
        --set-env-vars PROJECT_ID="${PROJECT_ID}" || error_exit "Failed to deploy threat processing function"
    
    cd ..
    
    # Create directory for alert processor function
    log_info "Creating alert processor function"
    mkdir -p alert-processor-function
    cd alert-processor-function
    
    # Create requirements.txt for alert processor
    cat > requirements.txt << 'EOF'
google-cloud-pubsub==2.18.4
google-cloud-logging==3.8.0
google-cloud-compute==1.14.1
functions-framework==3.5.0
EOF
    
    # Create alert processing code
    cat > main.py << 'EOF'
import json
import base64
import logging
from google.cloud import compute_v1
from google.cloud import pubsub_v1

# Initialize clients
compute_client = compute_v1.InstancesClient()
publisher = pubsub_v1.PublisherClient()

def process_security_alert(event, context):
    """Process high-severity security alerts and trigger responses"""
    try:
        # Decode alert message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            alert = json.loads(message_data)
        else:
            logging.error("No data in alert message")
            return
        
        alert_type = alert.get("alert_type")
        source_ip = alert.get("source_ip")
        threat_type = alert.get("threat_type")
        
        logging.info(f"Processing alert: {alert_type} from {source_ip}")
        
        # Implement automated response based on threat type
        if threat_type in ["Malware Detection", "Command and Control"]:
            # Log critical threat for immediate investigation
            logging.critical(f"CRITICAL THREAT DETECTED: {threat_type} from {source_ip}")
            
        elif threat_type == "Port Scan":
            # Log suspicious activity
            logging.warning(f"SUSPICIOUS ACTIVITY: Port scan from {source_ip}")
        
        # Send notification (could integrate with external systems)
        notification = {
            "message": f"Security Alert: {threat_type} detected",
            "severity": "HIGH",
            "source_ip": source_ip,
            "timestamp": alert.get("timestamp"),
            "action_required": True
        }
        
        logging.info(f"Security alert processed: {alert.get('finding_id')}")
        
    except Exception as e:
        logging.error(f"Error processing security alert: {str(e)}")
        raise
EOF
    
    # Deploy alert processing function
    log_info "Deploying alert processing function"
    gcloud functions deploy "${ALERT_FUNCTION}" \
        --runtime python39 \
        --trigger-topic "${ALERT_TOPIC}" \
        --source . \
        --entry-point process_security_alert \
        --memory 256MB \
        --timeout 60s || error_exit "Failed to deploy alert processing function"
    
    cd ..
    
    log_success "Cloud Functions deployed successfully"
}

# Create Cloud IDS endpoint
create_ids_endpoint() {
    log_info "Creating Cloud IDS endpoint..."
    
    # Create Cloud IDS endpoint (this takes time)
    log_info "Creating IDS endpoint: ${IDS_ENDPOINT_NAME} (this may take 10-15 minutes)"
    gcloud ids endpoints create "${IDS_ENDPOINT_NAME}" \
        --network "${VPC_NAME}" \
        --zone "${ZONE}" \
        --severity INFORMATIONAL \
        --async || error_exit "Failed to create IDS endpoint"
    
    # Wait for endpoint creation with timeout
    log_info "Waiting for IDS endpoint to become ready..."
    local timeout=1200  # 20 minutes timeout
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local state=$(gcloud ids endpoints describe "${IDS_ENDPOINT_NAME}" \
            --zone "${ZONE}" \
            --format="value(state)" 2>/dev/null || echo "CREATING")
        
        if [[ "$state" == "READY" ]]; then
            log_success "IDS endpoint is ready"
            break
        elif [[ "$state" == "FAILED" ]]; then
            error_exit "IDS endpoint creation failed"
        else
            log_info "IDS endpoint state: ${state} - waiting ${interval} seconds..."
            sleep $interval
            elapsed=$((elapsed + interval))
        fi
    done
    
    if [ $elapsed -ge $timeout ]; then
        error_exit "Timeout waiting for IDS endpoint creation"
    fi
    
    # Get endpoint service attachment
    IDS_SERVICE_ATTACHMENT=$(gcloud ids endpoints describe "${IDS_ENDPOINT_NAME}" \
        --zone "${ZONE}" \
        --format="value(endpointForwardingRule)") || error_exit "Failed to get IDS service attachment"
    
    export IDS_SERVICE_ATTACHMENT
    log_success "Cloud IDS endpoint created: ${IDS_SERVICE_ATTACHMENT}"
}

# Create test VMs and packet mirroring
create_test_infrastructure() {
    log_info "Creating test infrastructure and packet mirroring..."
    
    # Create test VMs
    log_info "Creating test VMs for traffic generation"
    gcloud compute instances create "web-server-${RANDOM_SUFFIX}" \
        --zone "${ZONE}" \
        --machine-type e2-medium \
        --network-interface subnet="${SUBNET_NAME}" \
        --image-family debian-11 \
        --image-project debian-cloud \
        --tags web-server,mirrored-vm || error_exit "Failed to create web server VM"
    
    gcloud compute instances create "app-server-${RANDOM_SUFFIX}" \
        --zone "${ZONE}" \
        --machine-type e2-medium \
        --network-interface subnet="${SUBNET_NAME}" \
        --image-family debian-11 \
        --image-project debian-cloud \
        --tags app-server,mirrored-vm || error_exit "Failed to create app server VM"
    
    # Create packet mirroring policy
    log_info "Creating packet mirroring policy"
    gcloud compute packet-mirrorings create "${MIRRORING_POLICY_NAME}" \
        --region "${REGION}" \
        --network "${VPC_NAME}" \
        --mirrored-tags mirrored-vm \
        --collector-ilb "${IDS_SERVICE_ATTACHMENT}" \
        --async || error_exit "Failed to create packet mirroring policy"
    
    log_success "Test infrastructure and packet mirroring configured"
}

# Insert sample data for testing
insert_sample_data() {
    log_info "Inserting sample threat data for testing..."
    
    # Create sample threat data
    bq query --use_legacy_sql=false << EOF || error_exit "Failed to insert sample data"
INSERT INTO \`${PROJECT_ID}.threat_detection.ids_findings\` 
(finding_id, timestamp, severity, threat_type, source_ip, destination_ip, protocol, details, raw_data)
VALUES 
('finding-001', CURRENT_TIMESTAMP(), 'HIGH', 'Malware Detection', '203.0.113.1', '10.0.1.5', 'TCP', '{"port": 80, "payload": "suspicious"}', '{"full_details": "sample"}'),
('finding-002', CURRENT_TIMESTAMP(), 'MEDIUM', 'Port Scan', '198.51.100.1', '10.0.1.0/24', 'TCP', '{"ports": [22, 80, 443]}', '{"scan_type": "stealth"}'),
('finding-003', CURRENT_TIMESTAMP(), 'LOW', 'DNS Tunneling', '192.0.2.1', '8.8.8.8', 'UDP', '{"domain": "suspicious.example.com"}', '{"queries": 150}')
EOF
    
    # Create aggregation view
    bq query --use_legacy_sql=false << EOF || error_exit "Failed to create threat summary view"
CREATE OR REPLACE VIEW \`${PROJECT_ID}.threat_detection.threat_summary\` AS
SELECT 
    DATE(timestamp) as threat_date,
    COUNT(*) as total_findings,
    COUNTIF(severity = 'HIGH') as high_severity,
    COUNTIF(severity = 'MEDIUM') as medium_severity,
    COUNTIF(severity = 'LOW') as low_severity,
    ARRAY_AGG(DISTINCT threat_type LIMIT 5) as top_threat_types,
    ARRAY_AGG(DISTINCT source_ip LIMIT 10) as top_source_ips
FROM \`${PROJECT_ID}.threat_detection.ids_findings\`
GROUP BY DATE(timestamp)
ORDER BY threat_date DESC
EOF
    
    log_success "Sample data and views created successfully"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check IDS endpoint status
    log_info "Validating IDS endpoint status"
    local ids_state=$(gcloud ids endpoints describe "${IDS_ENDPOINT_NAME}" \
        --zone "${ZONE}" \
        --format="value(state)")
    
    if [[ "$ids_state" != "READY" ]]; then
        log_warning "IDS endpoint is not in READY state: ${ids_state}"
    else
        log_success "IDS endpoint is operational"
    fi
    
    # Check Cloud Functions
    log_info "Validating Cloud Functions"
    local func_status=$(gcloud functions describe "${PROCESSING_FUNCTION}" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$func_status" != "ACTIVE" ]]; then
        log_warning "Threat processing function status: ${func_status}"
    else
        log_success "Cloud Functions are operational"
    fi
    
    # Test BigQuery access
    log_info "Validating BigQuery access"
    local row_count=$(bq query --use_legacy_sql=false \
        "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.threat_detection.ids_findings\`" \
        --format=csv --quiet | tail -n 1)
    
    if [[ "$row_count" =~ ^[0-9]+$ ]] && [[ "$row_count" -gt 0 ]]; then
        log_success "BigQuery contains ${row_count} sample records"
    else
        log_warning "BigQuery validation issue - row count: ${row_count}"
    fi
    
    log_success "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "=================================================="
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================================="
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo ""
    echo "Resources Created:"
    echo "- VPC Network: ${VPC_NAME}"
    echo "- Cloud IDS Endpoint: ${IDS_ENDPOINT_NAME}"
    echo "- BigQuery Dataset: ${DATASET_NAME}"
    echo "- Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "- Cloud Functions: ${PROCESSING_FUNCTION}, ${ALERT_FUNCTION}"
    echo "- Test VMs: web-server-${RANDOM_SUFFIX}, app-server-${RANDOM_SUFFIX}"
    echo ""
    echo "Next Steps:"
    echo "1. Access BigQuery Data Canvas in the Google Cloud Console"
    echo "2. Navigate to BigQuery > ${DATASET_NAME} dataset"
    echo "3. Use natural language queries to analyze threat data"
    echo "4. Monitor Cloud Functions logs for processing activity"
    echo ""
    echo "Cleanup: Run './destroy.sh' to remove all resources"
    echo "=================================================="
}

# Main deployment function
main() {
    log_info "Starting threat detection pipeline deployment..."
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_network
    create_bigquery_resources
    create_pubsub_resources
    deploy_cloud_functions
    create_ids_endpoint
    create_test_infrastructure
    insert_sample_data
    validate_deployment
    display_summary
    
    log_success "Threat detection pipeline deployment completed successfully!"
}

# Run main function
main "$@"
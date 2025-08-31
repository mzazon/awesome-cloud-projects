#!/bin/bash

# Deploy Privilege Escalation Monitoring with PAM and Pub/Sub
# This script deploys a comprehensive privilege escalation monitoring system using
# Google Cloud services including PAM, Pub/Sub, Cloud Functions, and Cloud Monitoring

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
TEMP_DIR=""

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling and cleanup
cleanup() {
    local exit_code=$?
    log_info "Cleaning up temporary resources..."
    
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
        log_info "Temporary directory ${TEMP_DIR} removed"
    fi
    
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed with exit code ${exit_code}"
        log_error "Check the log file for details: ${LOG_FILE}"
        
        # Provide guidance on manual cleanup if needed
        if [[ -n "${TOPIC_NAME:-}" ]] || [[ -n "${FUNCTION_NAME:-}" ]]; then
            log_warning "You may need to manually clean up partially created resources:"
            [[ -n "${TOPIC_NAME:-}" ]] && echo "  - Pub/Sub topic: ${TOPIC_NAME}"
            [[ -n "${FUNCTION_NAME:-}" ]] && echo "  - Cloud Function: ${FUNCTION_NAME}"
            [[ -n "${SINK_NAME:-}" ]] && echo "  - Log sink: ${SINK_NAME}"
            [[ -n "${BUCKET_NAME:-}" ]] && echo "  - Storage bucket: ${BUCKET_NAME}"
        fi
    fi
    
    exit ${exit_code}
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        log_error "Install Google Cloud CLI with gsutil component"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed (required for random string generation)"
        exit 1
    fi
    
    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    # Get and validate project ID
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "No default project set in gcloud"
        log_error "Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Check if billing is enabled (basic check)
    if ! gcloud services list --enabled --filter="name:serviceusage.googleapis.com" --format="value(name)" | grep -q serviceusage; then
        log_warning "Unable to verify if billing is enabled"
        log_warning "Please ensure billing is enabled for project: ${PROJECT_ID}"
    fi
    
    log_success "Prerequisites check completed"
    return 0
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Export required environment variables
    export PROJECT_ID REGION ZONE
    export TOPIC_NAME SUBSCRIPTION_NAME FUNCTION_NAME SINK_NAME BUCKET_NAME
    
    # GCP configuration
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export TOPIC_NAME="privilege-escalation-alerts-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="privilege-monitor-sub-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="privilege-alert-processor-${RANDOM_SUFFIX}"
    export SINK_NAME="privilege-escalation-sink-${RANDOM_SUFFIX}"
    export BUCKET_NAME="privilege-audit-logs-${PROJECT_ID}-${RANDOM_SUFFIX}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set functions/region "${REGION}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Resource suffix: ${RANDOM_SUFFIX}"
    
    # Save environment to file for destroy script
    cat > "${SCRIPT_DIR}/.deploy_env" << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export TOPIC_NAME="${TOPIC_NAME}"
export SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export SINK_NAME="${SINK_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    return 0
}

# Enable required Google Cloud APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "logging.googleapis.com"
        "pubsub.googleapis.com" 
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "storage.googleapis.com"
        "privilegedaccessmanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 10
    
    log_success "All required APIs enabled successfully"
    return 0
}

# Create Pub/Sub topic and subscription
create_pubsub_resources() {
    log_info "Creating Pub/Sub resources..."
    
    # Create Pub/Sub topic
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
    if gcloud pubsub topics create "${TOPIC_NAME}" --quiet; then
        log_success "Pub/Sub topic created: ${TOPIC_NAME}"
    else
        log_error "Failed to create Pub/Sub topic"
        return 1
    fi
    
    # Create subscription with appropriate settings
    log_info "Creating Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    if gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=60 \
        --message-retention-duration=7d \
        --quiet; then
        log_success "Pub/Sub subscription created: ${SUBSCRIPTION_NAME}"
    else
        log_error "Failed to create Pub/Sub subscription"
        return 1
    fi
    
    return 0
}

# Configure log sink for privileged access events
create_log_sink() {
    log_info "Creating log sink for privileged access monitoring..."
    
    # Create log sink with comprehensive filter
    local log_filter='protoPayload.serviceName="iam.googleapis.com" OR
                     protoPayload.serviceName="cloudresourcemanager.googleapis.com" OR
                     protoPayload.serviceName="serviceusage.googleapis.com" OR
                     protoPayload.serviceName="privilegedaccessmanager.googleapis.com" OR
                     (protoPayload.methodName=~"setIamPolicy" OR
                      protoPayload.methodName=~"CreateRole" OR
                      protoPayload.methodName=~"UpdateRole" OR
                      protoPayload.methodName=~"CreateServiceAccount" OR
                      protoPayload.methodName=~"SetIamPolicy" OR
                      protoPayload.methodName=~"createGrant" OR
                      protoPayload.methodName=~"CreateGrant" OR
                      protoPayload.methodName=~"searchEntitlements")'
    
    if gcloud logging sinks create "${SINK_NAME}" \
        "pubsub.googleapis.com/projects/${PROJECT_ID}/topics/${TOPIC_NAME}" \
        --log-filter="${log_filter}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Log sink created: ${SINK_NAME}"
    else
        log_error "Failed to create log sink"
        return 1
    fi
    
    return 0
}

# Grant Pub/Sub publisher permissions to log sink
configure_sink_permissions() {
    log_info "Configuring log sink permissions..."
    
    # Get the sink's service account
    log_info "Retrieving sink service account..."
    local sink_service_account
    sink_service_account=$(gcloud logging sinks describe "${SINK_NAME}" \
        --format="value(writerIdentity)" 2>/dev/null)
    
    if [[ -z "${sink_service_account}" ]]; then
        log_error "Failed to retrieve sink service account"
        return 1
    fi
    
    log_info "Sink service account: ${sink_service_account}"
    
    # Grant Pub/Sub Publisher role to the sink service account
    log_info "Granting Pub/Sub Publisher role to sink service account..."
    if gcloud pubsub topics add-iam-policy-binding "${TOPIC_NAME}" \
        --member="${sink_service_account}" \
        --role="roles/pubsub.publisher" \
        --quiet; then
        log_success "Sink service account granted Pub/Sub Publisher permissions"
    else
        log_error "Failed to grant Pub/Sub Publisher permissions"
        return 1
    fi
    
    return 0
}

# Create Cloud Storage bucket for alert archive
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for alert archival..."
    
    # Create Cloud Storage bucket
    log_info "Creating bucket: ${BUCKET_NAME}"
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" 2>/dev/null; then
        log_success "Cloud Storage bucket created: ${BUCKET_NAME}"
    else
        log_error "Failed to create Cloud Storage bucket"
        return 1
    fi
    
    # Enable versioning for audit trail integrity
    log_info "Enabling versioning on bucket..."
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Bucket versioning enabled"
    else
        log_warning "Failed to enable bucket versioning"
    fi
    
    # Set lifecycle policy for cost optimization
    log_info "Setting lifecycle policy for cost optimization..."
    cat > "${TEMP_DIR}/lifecycle.json" << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
      "condition": {"age": 365}
    }
  ]
}
EOF
    
    if gsutil lifecycle set "${TEMP_DIR}/lifecycle.json" "gs://${BUCKET_NAME}"; then
        log_success "Lifecycle policy applied to bucket"
    else
        log_warning "Failed to apply lifecycle policy"
    fi
    
    return 0
}

# Deploy Cloud Function for alert processing
deploy_cloud_function() {
    log_info "Deploying Cloud Function for alert processing..."
    
    # Create function source directory
    local function_dir="${TEMP_DIR}/privilege-monitor-function"
    mkdir -p "${function_dir}"
    
    # Create main.py with alert processing logic
    cat > "${function_dir}/main.py" << 'EOF'
import json
import base64
import logging
import os
from datetime import datetime
from google.cloud import storage
from google.cloud import monitoring_v3

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_privilege_alert(event, context):
    """Process privilege escalation events from Pub/Sub"""
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        log_entry = json.loads(pubsub_message)
        
        # Extract audit log details
        proto_payload = log_entry.get('protoPayload', {})
        method_name = proto_payload.get('methodName', '')
        service_name = proto_payload.get('serviceName', '')
        principal_email = proto_payload.get('authenticationInfo', {}).get('principalEmail', 'Unknown')
        resource_name = proto_payload.get('resourceName', '')
        
        # Determine alert severity based on method and service
        severity = determine_severity(method_name, service_name, proto_payload)
        
        # Create alert object
        alert = {
            'timestamp': datetime.utcnow().isoformat(),
            'severity': severity,
            'principal': principal_email,
            'method': method_name,
            'service': service_name,
            'resource': resource_name,
            'raw_log': log_entry
        }
        
        # Log alert for monitoring
        logger.info(f"Privilege escalation detected: {severity} - {principal_email} - {method_name}")
        
        # Store alert in Cloud Storage
        store_alert(alert)
        
        # Send to Cloud Monitoring if high severity
        if severity in ['HIGH', 'CRITICAL']:
            send_monitoring_alert(alert)
            
        return 'Alert processed successfully'
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        raise

def determine_severity(method_name, service_name, proto_payload):
    """Determine alert severity based on the method, service, and context"""
    # Critical PAM operations
    critical_pam_methods = [
        'createGrant', 'CreateGrant', 'createEntitlement', 'CreateEntitlement'
    ]
    
    # High-risk IAM methods
    high_risk_methods = [
        'CreateRole', 'UpdateRole', 'DeleteRole',
        'CreateServiceAccount', 'SetIamPolicy'
    ]
    
    # Check for PAM-related activities
    if service_name == 'privilegedaccessmanager.googleapis.com':
        if any(method in method_name for method in critical_pam_methods):
            return 'CRITICAL'
        else:
            return 'HIGH'
    
    # Check for high-risk IAM operations
    if any(method in method_name for method in high_risk_methods):
        return 'HIGH'
    elif 'setIamPolicy' in method_name:
        return 'MEDIUM'
    else:
        return 'LOW'

def store_alert(alert):
    """Store alert in Cloud Storage for audit trail"""
    try:
        client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME', 'BUCKET_NAME_PLACEHOLDER')
        bucket = client.bucket(bucket_name)
        
        # Create filename with timestamp
        filename = f"alerts/{alert['timestamp'][:10]}/{alert['timestamp']}.json"
        blob = bucket.blob(filename)
        blob.upload_from_string(json.dumps(alert, indent=2))
        
    except Exception as e:
        logger.error(f"Failed to store alert: {str(e)}")

def send_monitoring_alert(alert):
    """Send high-severity alerts to Cloud Monitoring"""
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{os.environ.get('GCP_PROJECT', 'unknown')}"
        
        # Create custom metric for privilege escalation
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/privilege_escalation"
        series.resource.type = "global"
        
        point = series.points.add()
        point.value.int64_value = 1
        point.interval.end_time.seconds = int(datetime.utcnow().timestamp())
        
        client.create_time_series(name=project_name, time_series=[series])
        
    except Exception as e:
        logger.error(f"Failed to send monitoring alert: {str(e)}")
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.10.0
google-cloud-monitoring==2.16.0
EOF
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    if (cd "${function_dir}" && gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-topic "${TOPIC_NAME}" \
        --source . \
        --entry-point process_privilege_alert \
        --memory 256MB \
        --timeout 60s \
        --max-instances 10 \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME},GCP_PROJECT=${PROJECT_ID}" \
        --quiet); then
        log_success "Cloud Function deployed: ${FUNCTION_NAME}"
    else
        log_error "Failed to deploy Cloud Function"
        return 1
    fi
    
    return 0
}

# Create Cloud Monitoring alert policy
create_monitoring_alert() {
    log_info "Creating Cloud Monitoring alert policy..."
    
    # Create alert policy JSON
    cat > "${TEMP_DIR}/alert-policy.json" << 'EOF'
{
  "displayName": "Privilege Escalation Detection",
  "conditions": [
    {
      "displayName": "High privilege escalation rate",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/security/privilege_escalation\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 2,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [],
  "documentation": {
    "content": "Alert triggered when privilege escalation events exceed 2 per 5-minute window"
  }
}
EOF
    
    # Create the alert policy
    log_info "Creating monitoring alert policy..."
    if gcloud alpha monitoring policies create --policy-from-file="${TEMP_DIR}/alert-policy.json" --quiet; then
        log_success "Cloud Monitoring alert policy created"
    else
        log_warning "Failed to create monitoring alert policy (may need manual setup)"
    fi
    
    return 0
}

# Perform validation tests
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Pub/Sub resources
    log_info "Validating Pub/Sub resources..."
    if gcloud pubsub topics describe "${TOPIC_NAME}" --quiet >/dev/null 2>&1; then
        log_success "Pub/Sub topic validated: ${TOPIC_NAME}"
    else
        log_error "Pub/Sub topic validation failed"
        return 1
    fi
    
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" --quiet >/dev/null 2>&1; then
        log_success "Pub/Sub subscription validated: ${SUBSCRIPTION_NAME}"
    else
        log_error "Pub/Sub subscription validation failed"
        return 1
    fi
    
    # Check log sink
    log_info "Validating log sink..."
    if gcloud logging sinks describe "${SINK_NAME}" --quiet >/dev/null 2>&1; then
        log_success "Log sink validated: ${SINK_NAME}"
    else
        log_error "Log sink validation failed"
        return 1
    fi
    
    # Check Cloud Function
    log_info "Validating Cloud Function..."
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1; then
        log_success "Cloud Function validated: ${FUNCTION_NAME}"
    else
        log_error "Cloud Function validation failed"
        return 1
    fi
    
    # Check Storage bucket
    log_info "Validating Cloud Storage bucket..."
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_success "Cloud Storage bucket validated: ${BUCKET_NAME}"
    else
        log_error "Cloud Storage bucket validation failed"
        return 1
    fi
    
    log_success "All components validated successfully"
    return 0
}

# Generate test privilege escalation event
generate_test_event() {
    log_info "Generating test privilege escalation event..."
    
    local test_role_name="testPrivilegeRole${RANDOM_SUFFIX}"
    
    # Create test IAM role to trigger audit logs
    if gcloud iam roles create "${test_role_name}" \
        --project="${PROJECT_ID}" \
        --title="Test Privilege Role" \
        --description="Test role for privilege escalation monitoring" \
        --permissions="storage.objects.get" \
        --quiet; then
        log_success "Test IAM role created: ${test_role_name}"
        
        # Wait for log processing
        log_info "Waiting for log processing..."
        sleep 30
        
        # Check Cloud Function logs
        log_info "Checking Cloud Function logs..."
        gcloud functions logs read "${FUNCTION_NAME}" --limit=5 --region="${REGION}" || true
        
        # Clean up test role
        log_info "Cleaning up test role..."
        gcloud iam roles delete "${test_role_name}" --project="${PROJECT_ID}" --quiet || true
        
        log_success "Test event generated and cleanup completed"
    else
        log_warning "Failed to create test role - manual testing may be required"
    fi
    
    return 0
}

# Main deployment function
main() {
    log_info "Starting Privilege Escalation Monitoring deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    log_info "Using temporary directory: ${TEMP_DIR}"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_pubsub_resources
    create_log_sink
    configure_sink_permissions
    create_storage_bucket
    deploy_cloud_function
    create_monitoring_alert
    validate_deployment
    generate_test_event
    
    # Deployment completed successfully
    log_success "Privilege Escalation Monitoring deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Pub/Sub Topic: ${TOPIC_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Log Sink: ${SINK_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo
    echo "=== Next Steps ==="
    echo "1. Configure notification channels in Cloud Monitoring for alerts"
    echo "2. Review and customize alert policies as needed"
    echo "3. Monitor Cloud Function logs for alert processing"
    echo "4. Set up additional notification channels (email, Slack, etc.)"
    echo
    echo "=== Cost Optimization ==="
    echo "- Review Pub/Sub message retention settings"
    echo "- Monitor Cloud Function execution metrics"
    echo "- Consider adjusting storage lifecycle policies"
    echo
    echo "To destroy all resources: ./destroy.sh"
    echo "Environment saved to: ${SCRIPT_DIR}/.deploy_env"
}

# Run main function
main "$@"
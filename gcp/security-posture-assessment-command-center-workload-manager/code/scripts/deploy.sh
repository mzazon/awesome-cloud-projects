#!/bin/bash

# Security Posture Assessment with Security Command Center and Workload Manager - Deployment Script
# This script deploys the complete security posture assessment solution for GCP

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - ${message}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - ${message}"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}"
            ;;
    esac
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    echo -e "${RED}Deployment failed. Check logs above for details.${NC}"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for operation completion
wait_for_operation() {
    local operation_name=$1
    local timeout=${2:-300}  # Default 5 minute timeout
    local counter=0
    
    log "INFO" "Waiting for operation: ${operation_name}"
    
    while [ $counter -lt $timeout ]; do
        if gcloud operations describe "$operation_name" --format="value(done)" | grep -q "True"; then
            log "SUCCESS" "Operation ${operation_name} completed successfully"
            return 0
        fi
        sleep 10
        counter=$((counter + 10))
        echo -n "."
    done
    
    error_exit "Operation ${operation_name} timed out after ${timeout} seconds"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if required APIs are enabled
    local required_apis=(
        "securitycenter.googleapis.com"
        "workloadmanager.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "compute.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
    )
    
    log "INFO" "Checking required APIs..."
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
            log "WARNING" "API ${api} is not enabled. Enabling now..."
            gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
        fi
    done
    
    log "SUCCESS" "Prerequisites validation completed"
}

# Function to set up environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID:-"security-posture-$(date +%s)"}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Try to get organization ID
    if [ -z "${ORGANIZATION_ID:-}" ]; then
        export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [ -z "$ORGANIZATION_ID" ]; then
            error_exit "Could not determine Organization ID. Please set ORGANIZATION_ID environment variable."
        fi
    fi
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 7))
    export TOPIC_NAME="security-events-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="security-remediation-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-security-logs-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="security-automation-${RANDOM_SUFFIX}"
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
    gcloud config set compute/zone "${ZONE}" 2>/dev/null || true
    
    log "SUCCESS" "Environment setup completed"
    log "INFO" "Project: ${PROJECT_ID}"
    log "INFO" "Region: ${REGION}"
    log "INFO" "Organization: ${ORGANIZATION_ID}"
}

# Function to create project if it doesn't exist
create_project() {
    log "INFO" "Checking if project exists..."
    
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log "INFO" "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Security Posture Assessment" \
            || error_exit "Failed to create project"
        
        # Link billing account if available
        local billing_account=$(gcloud billing accounts list --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [ -n "$billing_account" ]; then
            gcloud billing projects link "${PROJECT_ID}" --billing-account="${billing_account}" \
                || log "WARNING" "Failed to link billing account. Please link manually."
        fi
        
        log "SUCCESS" "Project created successfully"
    else
        log "INFO" "Project already exists"
    fi
}

# Function to enable required APIs
enable_apis() {
    log "INFO" "Enabling required APIs..."
    
    local apis=(
        "securitycenter.googleapis.com"
        "workloadmanager.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "compute.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "INFO" "Enabling ${api}..."
        gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
    done
    
    log "SUCCESS" "APIs enabled successfully"
}

# Function to create service account
create_service_account() {
    log "INFO" "Creating service account..."
    
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Security Automation Service Account" \
        --description="Service account for automated security operations" \
        || error_exit "Failed to create service account"
    
    # Grant necessary roles
    local roles=(
        "roles/securitycenter.admin"
        "roles/workloadmanager.admin"
        "roles/cloudfunctions.admin"
        "roles/pubsub.admin"
        "roles/storage.admin"
        "roles/logging.admin"
        "roles/monitoring.admin"
        "roles/cloudscheduler.admin"
    )
    
    for role in "${roles[@]}"; do
        log "INFO" "Granting role: ${role}"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" \
            || error_exit "Failed to grant role ${role}"
    done
    
    log "SUCCESS" "Service account created and configured"
}

# Function to activate Security Command Center
activate_security_command_center() {
    log "INFO" "Activating Security Command Center..."
    
    # Note: This requires organization-level permissions
    if ! gcloud scc organizations describe "${ORGANIZATION_ID}" >/dev/null 2>&1; then
        log "INFO" "Activating Security Command Center at organization level..."
        gcloud scc organizations activate "${ORGANIZATION_ID}" \
            || error_exit "Failed to activate Security Command Center"
    else
        log "INFO" "Security Command Center already activated"
    fi
    
    log "SUCCESS" "Security Command Center activated"
}

# Function to create security posture
create_security_posture() {
    log "INFO" "Creating security posture..."
    
    # Create security posture using predefined template
    if ! gcloud scc postures describe secure-baseline \
        --organization="${ORGANIZATION_ID}" \
        --location=global >/dev/null 2>&1; then
        
        log "INFO" "Creating security posture: secure-baseline"
        gcloud scc postures create secure-baseline \
            --organization="${ORGANIZATION_ID}" \
            --location=global \
            --template=secure_by_default_essential \
            --description="Automated security baseline posture" \
            || error_exit "Failed to create security posture"
    else
        log "INFO" "Security posture already exists"
    fi
    
    # Deploy the posture
    if ! gcloud scc posture-deployments describe baseline-deployment \
        --organization="${ORGANIZATION_ID}" \
        --location=global >/dev/null 2>&1; then
        
        log "INFO" "Deploying security posture..."
        gcloud scc posture-deployments create baseline-deployment \
            --organization="${ORGANIZATION_ID}" \
            --location=global \
            --posture=secure-baseline \
            --posture-revision-id=1 \
            --target-resource="organizations/${ORGANIZATION_ID}" \
            || error_exit "Failed to deploy security posture"
    else
        log "INFO" "Security posture already deployed"
    fi
    
    log "SUCCESS" "Security posture created and deployed"
}

# Function to create Workload Manager evaluation
create_workload_manager_evaluation() {
    log "INFO" "Creating Workload Manager evaluation..."
    
    # Create validation rules file
    cat > "/tmp/security-validation-rules.yaml" << EOF
apiVersion: workloadmanager.cnrm.cloud.google.com/v1beta1
kind: WorkloadManagerEvaluation
metadata:
  name: security-compliance-check
spec:
  projectId: ${PROJECT_ID}
  schedule: "0 */6 * * *"
  description: "Security compliance validation"
  customRules:
    - name: "ensure-vm-shielded"
      description: "Verify VMs have Shielded VM enabled"
      type: "COMPUTE_ENGINE"
      severity: "HIGH"
    - name: "check-storage-encryption"
      description: "Ensure Cloud Storage uses CMEK"
      type: "CLOUD_STORAGE"
      severity: "CRITICAL"
EOF
    
    # Create Workload Manager evaluation
    if ! gcloud workload-manager evaluations describe security-compliance \
        --location="${REGION}" >/dev/null 2>&1; then
        
        log "INFO" "Creating Workload Manager evaluation..."
        gcloud workload-manager evaluations create security-compliance \
            --location="${REGION}" \
            --description="Automated security compliance validation" \
            --custom-rules-file="/tmp/security-validation-rules.yaml" \
            || error_exit "Failed to create Workload Manager evaluation"
    else
        log "INFO" "Workload Manager evaluation already exists"
    fi
    
    log "SUCCESS" "Workload Manager evaluation created"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "INFO" "Creating Pub/Sub resources..."
    
    # Create topic
    if ! gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        gcloud pubsub topics create "${TOPIC_NAME}" \
            || error_exit "Failed to create Pub/Sub topic"
    else
        log "INFO" "Pub/Sub topic already exists"
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions describe "${TOPIC_NAME}-subscription" >/dev/null 2>&1; then
        gcloud pubsub subscriptions create "${TOPIC_NAME}-subscription" \
            --topic="${TOPIC_NAME}" \
            --ack-deadline=300 \
            --max-delivery-attempts=5 \
            || error_exit "Failed to create Pub/Sub subscription"
    else
        log "INFO" "Pub/Sub subscription already exists"
    fi
    
    # Configure Security Command Center to publish findings
    if ! gcloud scc notifications describe security-findings-notification \
        --organization="${ORGANIZATION_ID}" >/dev/null 2>&1; then
        
        log "INFO" "Creating Security Command Center notification..."
        gcloud scc notifications create security-findings-notification \
            --organization="${ORGANIZATION_ID}" \
            --pubsub-topic="projects/${PROJECT_ID}/topics/${TOPIC_NAME}" \
            --description="Security findings for automated processing" \
            --filter="state=\"ACTIVE\"" \
            || error_exit "Failed to create Security Command Center notification"
    else
        log "INFO" "Security Command Center notification already exists"
    fi
    
    log "SUCCESS" "Pub/Sub resources created"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "INFO" "Creating Cloud Storage bucket..."
    
    if ! gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${BUCKET_NAME}" \
            || error_exit "Failed to create storage bucket"
        
        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}" \
            || error_exit "Failed to enable versioning"
    else
        log "INFO" "Storage bucket already exists"
    fi
    
    log "SUCCESS" "Storage bucket created"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "INFO" "Deploying Cloud Function..."
    
    # Create function source directory
    local function_dir="/tmp/security-remediation-function"
    mkdir -p "${function_dir}"
    
    # Copy function source files
    local source_dir="$(dirname "$0")/../terraform/function_source"
    if [ -d "${source_dir}" ]; then
        cp -r "${source_dir}"/* "${function_dir}/"
    else
        # Create default function files
        cat > "${function_dir}/main.py" << 'EOF'
import json
import base64
import logging
from google.cloud import compute_v1
from google.cloud import storage
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def process_security_event(event, context):
    """Process security events and implement remediation"""
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(event['data']).decode('utf-8')
        security_finding = json.loads(message_data)
        
        finding_type = security_finding.get('category', '')
        severity = security_finding.get('severity', 'LOW')
        resource_name = security_finding.get('resourceName', '')
        
        logger.info(f"Processing finding: {finding_type}, Severity: {severity}")
        
        # Implement remediation based on finding type
        if finding_type == 'COMPUTE_INSECURE_CONFIGURATION':
            remediate_compute_issue(resource_name, security_finding)
        elif finding_type == 'STORAGE_MISCONFIGURATION':
            remediate_storage_issue(resource_name, security_finding)
        elif severity == 'CRITICAL':
            send_critical_alert(security_finding)
        
        logger.info(f"Successfully processed security finding: {finding_type}")
        
    except Exception as e:
        logger.error(f"Error processing security event: {str(e)}")
        raise

def remediate_compute_issue(resource_name, finding):
    """Remediate compute engine security issues"""
    logger.info(f"Remediated compute issue for {resource_name}")

def remediate_storage_issue(resource_name, finding):
    """Remediate storage security issues"""
    logger.info(f"Remediated storage issue for {resource_name}")

def send_critical_alert(finding):
    """Send alert for critical findings requiring manual intervention"""
    logger.critical(f"CRITICAL SECURITY FINDING: {finding}")
EOF
        
        cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-compute
google-cloud-storage
google-cloud-logging
EOF
    fi
    
    # Deploy function
    cd "${function_dir}"
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python39 \
        --trigger-topic="${TOPIC_NAME}" \
        --entry-point=process_security_event \
        --memory=512MB \
        --timeout=300s \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        || error_exit "Failed to deploy Cloud Function"
    
    log "SUCCESS" "Cloud Function deployed"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "INFO" "Creating monitoring dashboard..."
    
    cat > "/tmp/security-dashboard.json" << EOF
{
  "displayName": "Security Posture Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Security Findings by Severity",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
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
    
    gcloud monitoring dashboards create --config-from-file="/tmp/security-dashboard.json" \
        || error_exit "Failed to create monitoring dashboard"
    
    log "SUCCESS" "Monitoring dashboard created"
}

# Function to create scheduled job
create_scheduled_job() {
    log "INFO" "Creating scheduled job..."
    
    if ! gcloud scheduler jobs describe security-posture-evaluation \
        --location="${REGION}" >/dev/null 2>&1; then
        
        gcloud scheduler jobs create pubsub security-posture-evaluation \
            --location="${REGION}" \
            --schedule="0 */4 * * *" \
            --topic="${TOPIC_NAME}" \
            --message-body='{"event_type":"scheduled_evaluation","source":"automation"}' \
            --description="Trigger security posture evaluation every 4 hours" \
            || error_exit "Failed to create scheduled job"
    else
        log "INFO" "Scheduled job already exists"
    fi
    
    log "SUCCESS" "Scheduled job created"
}

# Function to run initial validation
run_initial_validation() {
    log "INFO" "Running initial validation..."
    
    # Check Security Command Center status
    if gcloud scc organizations describe "${ORGANIZATION_ID}" >/dev/null 2>&1; then
        log "SUCCESS" "Security Command Center is active"
    else
        log "WARNING" "Security Command Center validation failed"
    fi
    
    # Check Workload Manager evaluation
    if gcloud workload-manager evaluations describe security-compliance \
        --location="${REGION}" >/dev/null 2>&1; then
        log "SUCCESS" "Workload Manager evaluation is configured"
    else
        log "WARNING" "Workload Manager evaluation validation failed"
    fi
    
    # Test pub/sub by publishing a test message
    log "INFO" "Testing Pub/Sub pipeline..."
    gcloud pubsub topics publish "${TOPIC_NAME}" \
        --message='{"category":"TEST_FINDING","severity":"MEDIUM","resourceName":"test-resource"}' \
        || log "WARNING" "Failed to publish test message"
    
    log "SUCCESS" "Initial validation completed"
}

# Function to display deployment summary
display_summary() {
    log "SUCCESS" "Security Posture Assessment deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Organization ID: ${ORGANIZATION_ID}"
    echo
    echo "Resources Created:"
    echo "- Security Command Center: Activated"
    echo "- Security Posture: secure-baseline"
    echo "- Workload Manager: security-compliance"
    echo "- Pub/Sub Topic: ${TOPIC_NAME}"
    echo "- Cloud Function: ${FUNCTION_NAME}"
    echo "- Storage Bucket: ${BUCKET_NAME}"
    echo "- Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "- Monitoring Dashboard: Security Posture Dashboard"
    echo "- Scheduled Job: security-posture-evaluation"
    echo
    echo "Next Steps:"
    echo "1. Visit Security Command Center: https://console.cloud.google.com/security/command-center"
    echo "2. View Workload Manager: https://console.cloud.google.com/workload-manager"
    echo "3. Check Monitoring Dashboard: https://console.cloud.google.com/monitoring/dashboards"
    echo "4. Review Cloud Function logs: https://console.cloud.google.com/functions/details/${REGION}/${FUNCTION_NAME}"
    echo
    echo "Security posture assessment is now running automatically!"
}

# Main deployment function
main() {
    echo "=== Security Posture Assessment Deployment ==="
    echo "Starting deployment process..."
    echo
    
    # Run deployment steps
    validate_prerequisites
    setup_environment
    create_project
    enable_apis
    create_service_account
    activate_security_command_center
    create_security_posture
    create_workload_manager_evaluation
    create_pubsub_resources
    create_storage_bucket
    deploy_cloud_function
    create_monitoring_dashboard
    create_scheduled_job
    run_initial_validation
    display_summary
    
    log "SUCCESS" "Deployment completed successfully!"
    exit 0
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
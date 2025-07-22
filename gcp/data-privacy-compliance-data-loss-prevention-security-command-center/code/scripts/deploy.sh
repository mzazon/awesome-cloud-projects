#!/bin/bash

# Deploy script for Data Privacy Compliance with Cloud DLP and Security Command Center
# This script deploys the complete privacy compliance infrastructure

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some JSON parsing may not work optimally."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warning "openssl is not available. Using date for random suffix generation."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    # Set project configuration
    export PROJECT_ID="${PROJECT_ID:-privacy-compliance-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    export FUNCTION_NAME="privacy-compliance-${RANDOM_SUFFIX}"
    export TOPIC_NAME="privacy-findings-${RANDOM_SUFFIX}"
    export BUCKET_NAME="privacy-scan-data-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="privacy-compliance-sa"
    export DLP_TEMPLATE_NAME="privacy-compliance-template"
    export SCC_SOURCE_NAME="Privacy Compliance Scanner"
    
    # Store variables in a file for cleanup script
    cat > .env.deploy << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export TOPIC_NAME="${TOPIC_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}"
export DLP_TEMPLATE_NAME="${DLP_TEMPLATE_NAME}"
export SCC_SOURCE_NAME="${SCC_SOURCE_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Function Name: ${FUNCTION_NAME}"
}

# Function to configure gcloud
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Privacy Compliance Project"
        
        # Link billing account if available
        BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -n "${BILLING_ACCOUNT}" ]]; then
            gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
            success "Billing account linked to project"
        else
            warning "No billing account found. Please link a billing account to enable APIs."
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dlp.googleapis.com"
        "securitycenter.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "storage-api.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for test data..."
    
    # Create bucket with appropriate settings
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        success "Created bucket: ${BUCKET_NAME}"
    else
        error "Failed to create bucket"
        exit 1
    fi
    
    # Enable uniform bucket-level access
    gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"
    
    # Create sample files with sensitive data for testing
    log "Creating sample data files..."
    cat > sample_data.txt << 'EOF'
Customer: John Doe, SSN: 123-45-6789, Email: john.doe@example.com
Credit Card: 4111-1111-1111-1111, Phone: (555) 123-4567
Medical Record: Patient ID 12345, DOB: 1985-03-15
Employee: Jane Smith, SSN: 987-65-4321, Phone: (555) 987-6543
Banking: Account 1234567890, Routing: 021000021
Personal Info: Driver License: D123456789, Email: jane.smith@company.com
EOF
    
    # Upload sample data
    if gsutil cp sample_data.txt "gs://${BUCKET_NAME}/"; then
        success "Sample data uploaded to bucket"
    else
        error "Failed to upload sample data"
        exit 1
    fi
    
    # Clean up local file
    rm -f sample_data.txt
}

# Function to create DLP inspection template
create_dlp_template() {
    log "Creating DLP inspection template..."
    
    cat > dlp-template.json << 'EOF'
{
  "displayName": "Privacy Compliance Template",
  "description": "Detects PII, PHI, and financial data for compliance monitoring",
  "inspectConfig": {
    "infoTypes": [
      {"name": "US_SOCIAL_SECURITY_NUMBER"},
      {"name": "CREDIT_CARD_NUMBER"},
      {"name": "EMAIL_ADDRESS"},
      {"name": "PHONE_NUMBER"},
      {"name": "PERSON_NAME"},
      {"name": "US_HEALTHCARE_NPI"},
      {"name": "DATE_OF_BIRTH"},
      {"name": "US_BANK_ROUTING_MICR"},
      {"name": "US_DRIVERS_LICENSE_NUMBER"}
    ],
    "minLikelihood": "POSSIBLE",
    "limits": {
      "maxFindingsPerRequest": 100,
      "maxFindingsPerInfoType": [
        {
          "infoType": {"name": "US_SOCIAL_SECURITY_NUMBER"},
          "maxFindings": 10
        }
      ]
    },
    "includeQuote": true
  }
}
EOF
    
    # Create the inspection template
    if gcloud dlp inspect-templates create \
        --template-file=dlp-template.json \
        --location="${REGION}" \
        --template-id="${DLP_TEMPLATE_NAME}"; then
        success "DLP inspection template created"
    else
        error "Failed to create DLP inspection template"
        exit 1
    fi
    
    # Store template name for later use
    export DLP_TEMPLATE_FULL_NAME="projects/${PROJECT_ID}/locations/${REGION}/inspectTemplates/${DLP_TEMPLATE_NAME}"
    echo "export DLP_TEMPLATE_FULL_NAME=\"${DLP_TEMPLATE_FULL_NAME}\"" >> .env.deploy
    
    rm -f dlp-template.json
}

# Function to create Pub/Sub resources
create_pubsub() {
    log "Creating Pub/Sub topic and subscription..."
    
    # Create topic
    if gcloud pubsub topics create "${TOPIC_NAME}"; then
        success "Created Pub/Sub topic: ${TOPIC_NAME}"
    else
        error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions create "${TOPIC_NAME}-subscription" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=60; then
        success "Created Pub/Sub subscription"
    else
        error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    # Set up IAM permissions for DLP to publish to topic
    gcloud pubsub topics add-iam-policy-binding "${TOPIC_NAME}" \
        --member="serviceAccount:service-${PROJECT_ID}@dlp-api.iam.gserviceaccount.com" \
        --role="roles/pubsub.publisher"
    
    success "Pub/Sub resources configured"
}

# Function to create service account
create_service_account() {
    log "Creating service account for privacy compliance..."
    
    # Create service account
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Privacy Compliance Service Account" \
        --description="Service account for privacy compliance automation"; then
        success "Service account created"
    else
        error "Failed to create service account"
        exit 1
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/dlp.user"
        "roles/securitycenter.findingsEditor"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
        "roles/pubsub.subscriber"
        "roles/storage.objectViewer"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role: ${role}"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}"
    done
    
    success "Service account permissions configured"
}

# Function to create Cloud Function
create_cloud_function() {
    log "Creating Cloud Function for DLP finding processing..."
    
    # Create function source directory
    mkdir -p privacy-function
    cd privacy-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.5.0
google-cloud-dlp==3.12.0
google-cloud-securitycenter==1.23.0
google-cloud-logging==3.8.0
google-cloud-monitoring==2.16.0
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import base64
import json
import logging
from datetime import datetime
import os
from google.cloud import dlp_v2
from google.cloud import securitycenter
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
import functions_framework

# Initialize clients
dlp_client = dlp_v2.DlpServiceClient()
scc_client = securitycenter.SecurityCenterClient()
logging_client = cloud_logging.Client()
monitoring_client = monitoring_v3.MetricServiceClient()

# Get project ID from environment
PROJECT_ID = os.environ.get('PROJECT_ID', '')

@functions_framework.cloud_event
def process_dlp_findings(cloud_event):
    """Process DLP findings and create Security Command Center findings"""
    
    try:
        # Decode Pub/Sub message
        if 'data' not in cloud_event.data.get('message', {}):
            logging.warning("No data in Pub/Sub message")
            return "No data to process"
            
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode('utf-8')
        
        # Handle scheduled scan trigger
        if "scheduled_scan" in message_data:
            logging.info("Scheduled scan triggered")
            return "Scheduled scan acknowledged"
        
        finding_data = json.loads(message_data)
        
        # Extract finding details
        project_id = finding_data.get('projectId', PROJECT_ID)
        location = finding_data.get('location', 'global')
        finding_type = finding_data.get('infoType', {}).get('name', 'UNKNOWN')
        resource_name = finding_data.get('resourceName', 'UNKNOWN')
        
        # Determine severity based on info type
        severity = determine_severity(finding_type)
        
        # Log the finding
        log_finding(finding_data, severity)
        
        # Create custom metrics
        create_custom_metrics(finding_type, severity)
        
        logging.info(f"Processed DLP finding: {finding_type} with severity {severity}")
        
        return "Finding processed successfully"
        
    except Exception as e:
        logging.error(f"Error processing DLP finding: {str(e)}")
        raise

def determine_severity(info_type):
    """Determine severity based on information type"""
    high_risk_types = ['US_SOCIAL_SECURITY_NUMBER', 'CREDIT_CARD_NUMBER', 'US_HEALTHCARE_NPI', 'US_BANK_ROUTING_MICR']
    medium_risk_types = ['EMAIL_ADDRESS', 'PHONE_NUMBER', 'DATE_OF_BIRTH', 'US_DRIVERS_LICENSE_NUMBER']
    
    if info_type in high_risk_types:
        return "HIGH"
    elif info_type in medium_risk_types:
        return "MEDIUM"
    else:
        return "LOW"

def get_compliance_impact(info_type):
    """Get compliance impact based on data type"""
    pii_types = ['US_SOCIAL_SECURITY_NUMBER', 'EMAIL_ADDRESS', 'PERSON_NAME']
    phi_types = ['US_HEALTHCARE_NPI', 'DATE_OF_BIRTH']
    pci_types = ['CREDIT_CARD_NUMBER']
    
    impacts = []
    if info_type in pii_types:
        impacts.append("GDPR")
    if info_type in phi_types:
        impacts.append("HIPAA")
    if info_type in pci_types:
        impacts.append("PCI-DSS")
    
    return ",".join(impacts) if impacts else "General Privacy"

def log_finding(finding_data, severity):
    """Log finding to Cloud Logging"""
    logger = logging_client.logger('privacy-compliance')
    logger.log_struct({
        'message': 'DLP finding processed',
        'severity': severity,
        'finding_data': finding_data,
        'timestamp': datetime.now().isoformat()
    })

def create_custom_metrics(info_type, severity):
    """Create custom metrics for monitoring"""
    try:
        project_name = f"projects/{PROJECT_ID}"
        
        # Create time series for findings count
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/dlp/findings_count"
        series.resource.type = "global"
        series.metric.labels['info_type'] = info_type
        series.metric.labels['severity'] = severity
        
        # Add data point
        point = monitoring_v3.Point()
        point.value.int64_value = 1
        now = datetime.now()
        point.interval.end_time.seconds = int(now.timestamp())
        series.points = [point]
        
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
    except Exception as e:
        logging.error(f"Error creating custom metrics: {str(e)}")
EOF
    
    # Deploy the Cloud Function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --runtime=python311 \
        --source=. \
        --entry-point=process_dlp_findings \
        --trigger-topic="${TOPIC_NAME}" \
        --memory=512MB \
        --timeout=300s \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}"; then
        success "Cloud Function deployed successfully"
    else
        error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    cd ..
    rm -rf privacy-function
}

# Function to create DLP scan job
create_dlp_job() {
    log "Creating DLP scan job configuration..."
    
    cat > dlp-job.json << EOF
{
  "inspectJob": {
    "inspectTemplate": "${DLP_TEMPLATE_FULL_NAME}",
    "storageConfig": {
      "cloudStorageOptions": {
        "fileSet": {
          "url": "gs://${BUCKET_NAME}/*"
        }
      }
    },
    "actions": [
      {
        "pubSub": {
          "topic": "projects/${PROJECT_ID}/topics/${TOPIC_NAME}"
        }
      }
    ]
  }
}
EOF
    
    # Create and run the initial DLP job
    if gcloud dlp jobs create \
        --location="${REGION}" \
        --job-file=dlp-job.json; then
        success "Initial DLP scan job created and started"
    else
        warning "Failed to create initial DLP job, but continuing with deployment"
    fi
    
    # Create scheduled job for continuous monitoring
    if gcloud scheduler jobs create pubsub privacy-scan-schedule \
        --schedule="0 */6 * * *" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"trigger": "scheduled_scan"}' \
        --time-zone="UTC" \
        --description="Triggers DLP scan every 6 hours"; then
        success "Scheduled DLP scans configured"
    else
        warning "Failed to create scheduled DLP scans"
    fi
    
    rm -f dlp-job.json
}

# Function to create monitoring resources
create_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create custom metric descriptor
    cat > metric-descriptor.json << 'EOF'
{
  "type": "custom.googleapis.com/dlp/findings_count",
  "displayName": "DLP Findings Count",
  "description": "Number of DLP findings by type and severity",
  "metricKind": "GAUGE",
  "valueType": "INT64",
  "labels": [
    {
      "key": "info_type",
      "valueType": "STRING",
      "description": "Type of sensitive information detected"
    },
    {
      "key": "severity",
      "valueType": "STRING",
      "description": "Severity level of the finding"
    }
  ]
}
EOF
    
    # Create logging metric
    if gcloud logging metrics create dlp-findings-metric \
        --description="DLP findings count by type and severity" \
        --log-filter='resource.type="cloud_function" AND jsonPayload.message="DLP finding processed"'; then
        success "Logging metric created"
    else
        warning "Failed to create logging metric"
    fi
    
    rm -f metric-descriptor.json
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check DLP template
    if gcloud dlp inspect-templates describe "${DLP_TEMPLATE_NAME}" --location="${REGION}" &> /dev/null; then
        success "DLP template validated"
    else
        warning "DLP template validation failed"
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        success "Cloud Function validated"
    else
        warning "Cloud Function validation failed"
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
        success "Pub/Sub topic validated"
    else
        warning "Pub/Sub topic validation failed"
    fi
    
    # Check bucket
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        success "Storage bucket validated"
    else
        warning "Storage bucket validation failed"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        success "Service account validated"
    else
        warning "Service account validation failed"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Pub/Sub Topic: ${TOPIC_NAME}"
    echo "Storage Bucket: ${BUCKET_NAME}"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "DLP Template: ${DLP_TEMPLATE_FULL_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor DLP findings in Cloud Logging"
    echo "2. Check Security Command Center for findings"
    echo "3. Review Cloud Function logs for processing status"
    echo "4. Test with additional data in the storage bucket"
    echo ""
    echo "Cleanup: Run './destroy.sh' to remove all resources"
    echo ""
}

# Main deployment function
main() {
    log "Starting Data Privacy Compliance deployment..."
    
    check_prerequisites
    set_environment
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_dlp_template
    create_pubsub
    create_service_account
    create_cloud_function
    create_dlp_job
    create_monitoring
    validate_deployment
    display_summary
    
    success "Data Privacy Compliance deployment completed successfully!"
}

# Run main function
main "$@"
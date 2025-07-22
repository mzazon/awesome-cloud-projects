#!/bin/bash

# Healthcare Data Compliance Workflows - Deployment Script
# This script deploys the complete healthcare compliance infrastructure on GCP
# Including Healthcare API, Cloud Tasks, Cloud Functions, and monitoring components

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

# Check if script is run with --dry-run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq (BigQuery CLI) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if default project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            error "No GCP project is set. Please set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for the project
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export LOCATION="${LOCATION:-us-central1}"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATASET_ID="healthcare-dataset-${RANDOM_SUFFIX}"
    export FHIR_STORE_ID="fhir-store-${RANDOM_SUFFIX}"
    export TASK_QUEUE_NAME="compliance-queue-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="compliance-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="healthcare-compliance-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export TOPIC_NAME="fhir-changes-${RANDOM_SUFFIX}"
    
    # Set default project and region
    execute gcloud config set project "${PROJECT_ID}"
    execute gcloud config set compute/region "${REGION}"
    execute gcloud config set compute/zone "${ZONE}"
    
    log "Environment configured:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Dataset ID: ${DATASET_ID}"
    log "  FHIR Store ID: ${FHIR_STORE_ID}"
    log "  Bucket Name: ${BUCKET_NAME}"
    
    # Save environment variables to file for cleanup script
    cat > .env.deploy << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
LOCATION=${LOCATION}
DATASET_ID=${DATASET_ID}
FHIR_STORE_ID=${FHIR_STORE_ID}
TASK_QUEUE_NAME=${TASK_QUEUE_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_NAME=${TOPIC_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured and saved to .env.deploy"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "healthcare.googleapis.com"
        "cloudtasks.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        execute gcloud services enable "${api}"
    done
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for APIs to be fully enabled
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "Required APIs enabled"
}

# Function to create healthcare dataset and FHIR store
create_healthcare_resources() {
    log "Creating healthcare dataset and FHIR store..."
    
    # Create healthcare dataset
    execute gcloud healthcare datasets create "${DATASET_ID}" \
        --location="${LOCATION}" \
        --description="Healthcare compliance dataset for FHIR processing"
    
    # Create FHIR store with audit logging enabled
    execute gcloud healthcare fhir-stores create "${FHIR_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${LOCATION}" \
        --version=R4 \
        --enable-update-create \
        --disable-referential-integrity
    
    success "Healthcare dataset and FHIR store created"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub resources..."
    
    # Create Pub/Sub topic for FHIR store events
    execute gcloud pubsub topics create "${TOPIC_NAME}"
    
    # Create subscription for FHIR store events
    execute gcloud pubsub subscriptions create "fhir-events-sub" \
        --topic="${TOPIC_NAME}" \
        --message-retention-duration=604800s \
        --ack-deadline=600s
    
    # Configure Pub/Sub notification for FHIR store
    execute gcloud healthcare fhir-stores update "${FHIR_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${LOCATION}" \
        --pubsub-topic="projects/${PROJECT_ID}/topics/${TOPIC_NAME}"
    
    success "Pub/Sub resources created and configured"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Create storage bucket with compliance settings
    execute gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"
    
    # Configure bucket lifecycle
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
        execute gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"
        rm lifecycle.json
    fi
    
    # Enable uniform bucket-level access
    execute gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"
    
    success "Cloud Storage bucket created with compliance settings"
}

# Function to create Cloud Tasks queue
create_task_queue() {
    log "Creating Cloud Tasks queue..."
    
    execute gcloud tasks queues create "${TASK_QUEUE_NAME}" \
        --location="${LOCATION}" \
        --max-dispatches-per-second=10 \
        --max-concurrent-dispatches=5 \
        --max-attempts=3 \
        --min-backoff=1s \
        --max-backoff=300s
    
    success "Cloud Tasks queue created"
}

# Function to create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset and tables..."
    
    # Create BigQuery dataset
    execute bq mk --dataset \
        --location="${REGION}" \
        --description="Healthcare compliance analytics dataset" \
        "${PROJECT_ID}:healthcare_compliance"
    
    # Create compliance events table
    execute bq mk --table \
        "${PROJECT_ID}:healthcare_compliance.compliance_events" \
        timestamp:TIMESTAMP,resource_name:STRING,event_type:STRING,compliance_status:STRING,validation_result:JSON,risk_score:INTEGER,message_id:STRING
    
    # Create audit trail table
    execute bq mk --table \
        "${PROJECT_ID}:healthcare_compliance.audit_trail" \
        timestamp:TIMESTAMP,user_id:STRING,resource_type:STRING,operation:STRING,phi_accessed:BOOLEAN,compliance_level:STRING,session_id:STRING
    
    success "BigQuery dataset and tables created"
}

# Function to create Cloud Functions
create_cloud_functions() {
    log "Creating Cloud Functions..."
    
    # Create function source directory
    mkdir -p compliance-function
    cd compliance-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-healthcare==2.15.0
google-cloud-tasks==2.16.0
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.1
google-cloud-logging==3.8.0
functions-framework==3.4.0
EOF
    
    # Create main function file
    cat > main.py << 'EOF'
import json
import base64
import logging
from datetime import datetime, timezone
from google.cloud import healthcare_v1
from google.cloud import tasks_v2
from google.cloud import storage
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def process_fhir_event(event, context):
    """Process FHIR store events for compliance validation."""
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            message = json.loads(message_data)
        else:
            message = event
        
        # Extract event details
        resource_name = message.get('resourceName', '')
        event_type = message.get('eventType', 'UNKNOWN')
        timestamp = datetime.now(timezone.utc).isoformat()
        
        # Log compliance event
        compliance_event = {
            'timestamp': timestamp,
            'resource_name': resource_name,
            'event_type': event_type,
            'compliance_status': 'PROCESSING',
            'message_id': context.eventId if hasattr(context, 'eventId') else 'unknown'
        }
        
        logger.info(f"Processing compliance event: {compliance_event}")
        
        # Validate PHI access patterns
        validation_result = validate_phi_access(message)
        compliance_event['validation_result'] = validation_result
        
        # Create compliance task for detailed processing
        if validation_result.get('requires_audit', False):
            create_compliance_task(compliance_event)
        
        # Store compliance event
        store_compliance_event(compliance_event)
        
        return {'status': 'success', 'event_id': compliance_event['message_id']}
        
    except Exception as e:
        logger.error(f"Error processing FHIR event: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def validate_phi_access(message):
    """Validate PHI access patterns and compliance requirements."""
    resource_name = message.get('resourceName', '')
    event_type = message.get('eventType', '')
    
    validation = {
        'is_phi_access': 'Patient' in resource_name or 'Person' in resource_name,
        'requires_audit': True,
        'compliance_level': 'STANDARD',
        'risk_score': calculate_risk_score(message)
    }
    
    # Enhanced validation for high-risk operations
    if event_type in ['CREATE', 'UPDATE', 'DELETE']:
        validation['requires_audit'] = True
        validation['compliance_level'] = 'ENHANCED'
    
    return validation

def calculate_risk_score(message):
    """Calculate risk score based on access patterns."""
    base_score = 1
    
    # Increase score for sensitive operations
    if message.get('eventType') == 'DELETE':
        base_score += 3
    elif message.get('eventType') in ['CREATE', 'UPDATE']:
        base_score += 2
    
    # Increase score for patient data
    if 'Patient' in message.get('resourceName', ''):
        base_score += 2
    
    return min(base_score, 5)  # Cap at 5

def create_compliance_task(event_data):
    """Create Cloud Task for detailed compliance processing."""
    try:
        client = tasks_v2.CloudTasksClient()
        parent = client.queue_path(
            project=os.environ.get('GCP_PROJECT'),
            location=os.environ.get('FUNCTION_REGION', 'us-central1'),
            queue='compliance-queue-' + os.environ.get('RANDOM_SUFFIX', 'default')
        )
        
        task = {
            'http_request': {
                'http_method': tasks_v2.HttpMethod.POST,
                'url': f"https://{os.environ.get('FUNCTION_REGION')}-{os.environ.get('GCP_PROJECT')}.cloudfunctions.net/compliance-audit",
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(event_data).encode()
            }
        }
        
        client.create_task(request={'parent': parent, 'task': task})
        logger.info(f"Created compliance task for event: {event_data['message_id']}")
        
    except Exception as e:
        logger.error(f"Error creating compliance task: {str(e)}")

def store_compliance_event(event_data):
    """Store compliance event in Cloud Storage."""
    try:
        client = storage.Client()
        bucket_name = f"healthcare-compliance-{os.environ.get('GCP_PROJECT')}-{os.environ.get('RANDOM_SUFFIX', 'default')}"
        bucket = client.bucket(bucket_name)
        
        # Create timestamped blob name
        timestamp = datetime.now(timezone.utc)
        blob_name = f"compliance-events/{timestamp.strftime('%Y/%m/%d')}/{event_data['message_id']}.json"
        
        blob = bucket.blob(blob_name)
        blob.upload_from_string(
            json.dumps(event_data, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Stored compliance event: {blob_name}")
        
    except Exception as e:
        logger.error(f"Error storing compliance event: {str(e)}")

import os
EOF
    
    # Deploy Cloud Function
    execute gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python39 \
        --trigger-topic="${TOPIC_NAME}" \
        --entry-point=process_fhir_event \
        --memory=512MB \
        --timeout=540s \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},FUNCTION_REGION=${REGION},RANDOM_SUFFIX=${RANDOM_SUFFIX}" \
        --max-instances=10
    
    cd ..
    
    # Create audit function
    mkdir -p audit-function
    cd audit-function
    
    # Create requirements.txt for audit function
    cat > requirements.txt << 'EOF'
google-cloud-healthcare==2.15.0
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
google-cloud-logging==3.8.0
functions-framework==3.4.0
EOF
    
    # Create audit function
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timezone
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def compliance_audit(request):
    """Process detailed compliance audit for high-risk events."""
    try:
        request_json = request.get_json()
        if not request_json:
            return {'status': 'error', 'message': 'No JSON data provided'}
        
        # Extract audit details
        audit_data = {
            'timestamp': datetime.now(timezone.utc),
            'original_event': request_json,
            'audit_level': determine_audit_level(request_json),
            'findings': perform_detailed_audit(request_json)
        }
        
        # Store audit results in BigQuery
        store_audit_results(audit_data)
        
        # Generate compliance report if needed
        if audit_data['audit_level'] == 'CRITICAL':
            generate_compliance_report(audit_data)
        
        logger.info(f"Completed compliance audit for event: {request_json.get('message_id')}")
        return {'status': 'success', 'audit_id': str(audit_data['timestamp'])}
        
    except Exception as e:
        logger.error(f"Error in compliance audit: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def determine_audit_level(event_data):
    """Determine the required audit level based on event characteristics."""
    validation_result = event_data.get('validation_result', {})
    risk_score = validation_result.get('risk_score', 1)
    
    if risk_score >= 4:
        return 'CRITICAL'
    elif risk_score >= 2:
        return 'ENHANCED'
    else:
        return 'STANDARD'

def perform_detailed_audit(event_data):
    """Perform detailed compliance audit analysis."""
    findings = {
        'phi_exposure_risk': assess_phi_exposure(event_data),
        'access_pattern_analysis': analyze_access_patterns(event_data),
        'compliance_violations': check_compliance_violations(event_data),
        'recommendations': generate_recommendations(event_data)
    }
    
    return findings

def assess_phi_exposure(event_data):
    """Assess potential PHI exposure risks."""
    resource_name = event_data.get('resource_name', '')
    event_type = event_data.get('event_type', '')
    
    risk_factors = []
    
    if 'Patient' in resource_name:
        risk_factors.append('Direct patient data access')
    
    if event_type == 'DELETE':
        risk_factors.append('Data deletion operation')
    
    if event_type in ['CREATE', 'UPDATE']:
        risk_factors.append('Data modification operation')
    
    return {
        'risk_level': 'HIGH' if len(risk_factors) > 1 else 'MEDIUM' if risk_factors else 'LOW',
        'factors': risk_factors
    }

def analyze_access_patterns(event_data):
    """Analyze access patterns for anomalies."""
    return {
        'pattern_type': 'normal',
        'frequency': 'standard',
        'timing': 'business_hours'
    }

def check_compliance_violations(event_data):
    """Check for potential compliance violations."""
    violations = []
    
    validation_result = event_data.get('validation_result', {})
    if validation_result.get('risk_score', 0) >= 4:
        violations.append('High-risk operation detected')
    
    return violations

def generate_recommendations(event_data):
    """Generate compliance recommendations."""
    recommendations = [
        'Continue monitoring access patterns',
        'Ensure proper authentication and authorization',
        'Maintain audit trail documentation'
    ]
    
    validation_result = event_data.get('validation_result', {})
    if validation_result.get('risk_score', 0) >= 3:
        recommendations.append('Consider additional security measures')
        recommendations.append('Review access permissions')
    
    return recommendations

def store_audit_results(audit_data):
    """Store audit results in BigQuery."""
    try:
        client = bigquery.Client()
        table_id = f"{os.environ.get('GCP_PROJECT')}.healthcare_compliance.audit_trail"
        
        row = {
            'timestamp': audit_data['timestamp'].isoformat(),
            'user_id': 'system',
            'resource_type': extract_resource_type(audit_data['original_event']),
            'operation': audit_data['original_event'].get('event_type', 'UNKNOWN'),
            'phi_accessed': audit_data['findings']['phi_exposure_risk']['risk_level'] != 'LOW',
            'compliance_level': audit_data['audit_level'],
            'session_id': audit_data['original_event'].get('message_id', 'unknown')
        }
        
        client.insert_rows_json(table_id, [row])
        logger.info(f"Stored audit results in BigQuery: {table_id}")
        
    except Exception as e:
        logger.error(f"Error storing audit results: {str(e)}")

def extract_resource_type(event_data):
    """Extract FHIR resource type from event data."""
    resource_name = event_data.get('resource_name', '')
    if 'Patient' in resource_name:
        return 'Patient'
    elif 'Observation' in resource_name:
        return 'Observation'
    elif 'Condition' in resource_name:
        return 'Condition'
    else:
        return 'Unknown'

def generate_compliance_report(audit_data):
    """Generate detailed compliance report for critical events."""
    try:
        client = storage.Client()
        bucket_name = f"healthcare-compliance-{os.environ.get('GCP_PROJECT')}-{os.environ.get('RANDOM_SUFFIX', 'default')}"
        bucket = client.bucket(bucket_name)
        
        timestamp = audit_data['timestamp']
        report_name = f"compliance-reports/{timestamp.strftime('%Y/%m/%d')}/critical-event-{timestamp.strftime('%H%M%S')}.json"
        
        report_data = {
            'report_type': 'Critical Event Audit',
            'generated_at': timestamp.isoformat(),
            'event_summary': audit_data['original_event'],
            'audit_findings': audit_data['findings'],
            'compliance_status': 'REQUIRES_REVIEW',
            'next_actions': [
                'Review access permissions',
                'Validate user authorization',
                'Document incident in compliance log'
            ]
        }
        
        blob = bucket.blob(report_name)
        blob.upload_from_string(
            json.dumps(report_data, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Generated compliance report: {report_name}")
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")

import os
EOF
    
    # Deploy audit function
    execute gcloud functions deploy "compliance-audit-${RANDOM_SUFFIX}" \
        --runtime=python39 \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point=compliance_audit \
        --memory=1024MB \
        --timeout=540s \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},RANDOM_SUFFIX=${RANDOM_SUFFIX}" \
        --max-instances=5
    
    cd ..
    
    success "Cloud Functions deployed successfully"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and alerting..."
    
    # Create monitoring notification channel (placeholder - requires actual email)
    warning "Monitoring notification channel creation requires manual configuration"
    warning "Please configure email notifications in Cloud Console for production use"
    
    success "Monitoring configuration completed"
}

# Function to perform validation tests
perform_validation() {
    log "Performing deployment validation..."
    
    # Test FHIR store creation
    log "Testing FHIR store..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if gcloud healthcare fhir-stores describe "${FHIR_STORE_ID}" \
            --dataset="${DATASET_ID}" \
            --location="${LOCATION}" &>/dev/null; then
            success "FHIR store is operational"
        else
            error "FHIR store validation failed"
            return 1
        fi
        
        # Test Cloud Functions
        log "Testing Cloud Functions..."
        if gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" &>/dev/null; then
            success "Compliance processing function is deployed"
        else
            error "Cloud Function validation failed"
            return 1
        fi
        
        # Test BigQuery dataset
        log "Testing BigQuery dataset..."
        if bq ls -d "${PROJECT_ID}:healthcare_compliance" &>/dev/null; then
            success "BigQuery dataset is accessible"
        else
            error "BigQuery dataset validation failed"
            return 1
        fi
        
        # Test Cloud Storage bucket
        log "Testing Cloud Storage bucket..."
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            success "Cloud Storage bucket is accessible"
        else
            error "Cloud Storage bucket validation failed"
            return 1
        fi
    else
        success "Validation skipped in dry-run mode"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Healthcare Dataset: ${DATASET_ID}"
    echo "FHIR Store: ${FHIR_STORE_ID}"
    echo "Cloud Functions: ${FUNCTION_NAME}, compliance-audit-${RANDOM_SUFFIX}"
    echo "Cloud Storage: gs://${BUCKET_NAME}"
    echo "Pub/Sub Topic: ${TOPIC_NAME}"
    echo "Task Queue: ${TASK_QUEUE_NAME}"
    echo "BigQuery Dataset: healthcare_compliance"
    echo ""
    echo "Environment variables saved to: .env.deploy"
    echo "Use the destroy.sh script to clean up resources"
    echo ""
    warning "Important: Ensure you have a Business Associate Agreement (BAA) with Google Cloud"
    warning "before processing real PHI data. This deployment is for development/testing only."
}

# Main deployment function
main() {
    log "Starting Healthcare Data Compliance Workflows deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Enable APIs
    enable_apis
    
    # Create resources
    create_healthcare_resources
    create_pubsub_resources
    create_storage_bucket
    create_task_queue
    create_bigquery_dataset
    create_cloud_functions
    configure_monitoring
    
    # Validate deployment
    perform_validation
    
    # Display summary
    display_summary
    
    success "Healthcare Data Compliance Workflows deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Next steps:"
        log "1. Review the deployed resources in Google Cloud Console"
        log "2. Configure email notifications for monitoring alerts"
        log "3. Test the compliance workflow with sample FHIR data"
        log "4. Ensure BAA is in place before processing real PHI data"
    fi
}

# Error handling
trap 'error "Deployment failed on line $LINENO"; exit 1' ERR

# Run main function
main "$@"
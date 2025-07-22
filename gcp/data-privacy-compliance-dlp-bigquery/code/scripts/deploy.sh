#!/bin/bash

# Data Privacy Compliance with Cloud DLP and BigQuery - Deployment Script
# This script deploys the complete data privacy compliance infrastructure
# including Cloud Storage, BigQuery, Cloud DLP, and Cloud Functions

set -e
set -o pipefail

# Configuration and constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
DEFAULT_PROJECT_PREFIX="privacy-compliance"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "BigQuery CLI (bq) is not installed. Please install it with: gcloud components install bq"
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install it with: gcloud components install gsutil"
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Please install curl."
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install openssl."
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        error_exit "python3 is not installed. Please install Python 3."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error_exit "No active gcloud authentication found. Please run: gcloud auth login"
    fi
    
    log "✅ All prerequisites met"
}

# Save deployment state
save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "${DEPLOYMENT_STATE_FILE}"
}

# Load deployment state
load_state() {
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        source "${DEPLOYMENT_STATE_FILE}"
    fi
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Load existing state if available
    load_state
    
    # Set or use existing PROJECT_ID
    if [[ -z "${PROJECT_ID}" ]]; then
        export PROJECT_ID="${DEFAULT_PROJECT_PREFIX}-$(date +%s)"
        save_state "PROJECT_ID" "${PROJECT_ID}"
    fi
    
    # Set region and zone
    export REGION="${REGION:-${DEFAULT_REGION}}"
    export ZONE="${ZONE:-${DEFAULT_ZONE}}"
    
    # Generate unique suffix for resources
    if [[ -z "${RANDOM_SUFFIX}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        save_state "RANDOM_SUFFIX" "${RANDOM_SUFFIX}"
    fi
    
    # Set resource names
    export BUCKET_NAME="dlp-compliance-data-${RANDOM_SUFFIX}"
    export DATASET_NAME="privacy_compliance"
    export FUNCTION_NAME="dlp-remediation-${RANDOM_SUFFIX}"
    
    # Save all configuration
    save_state "REGION" "${REGION}"
    save_state "ZONE" "${ZONE}"
    save_state "BUCKET_NAME" "${BUCKET_NAME}"
    save_state "DATASET_NAME" "${DATASET_NAME}"
    save_state "FUNCTION_NAME" "${FUNCTION_NAME}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    log_info "Dataset Name: ${DATASET_NAME}"
    log_info "Function Name: ${FUNCTION_NAME}"
}

# Create or verify project exists
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_warn "Project ${PROJECT_ID} does not exist. You may need to create it manually."
        log_warn "Run: gcloud projects create ${PROJECT_ID}"
        read -p "Continue with existing project? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Project setup cancelled"
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log "✅ Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dlp.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" 2>> "${LOG_FILE}"; then
            log_info "✅ ${api} enabled"
        else
            error_exit "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be ready
    log_info "Waiting for APIs to be ready..."
    sleep 30
    
    log "✅ All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for data sources..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warn "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return
    fi
    
    # Create bucket with appropriate location and access controls
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
        log_info "✅ Bucket gs://${BUCKET_NAME} created"
    else
        error_exit "Failed to create storage bucket"
    fi
    
    # Enable uniform bucket-level access for security
    if gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
        log_info "✅ Uniform bucket-level access enabled"
    else
        error_exit "Failed to enable uniform bucket-level access"
    fi
    
    # Set up lifecycle policy to manage data retention
    cat > "${SCRIPT_DIR}/lifecycle.json" << EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
EOF
    
    if gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
        log_info "✅ Lifecycle policy applied"
        rm -f "${SCRIPT_DIR}/lifecycle.json"
    else
        error_exit "Failed to set lifecycle policy"
    fi
    
    save_state "BUCKET_CREATED" "true"
    log "✅ Storage bucket created with security and retention policies"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log "Creating BigQuery dataset for compliance analytics..."
    
    # Create BigQuery dataset with appropriate location
    if bq mk --project_id="${PROJECT_ID}" --location="${REGION}" --description="Privacy compliance and DLP scan results" "${DATASET_NAME}" 2>> "${LOG_FILE}"; then
        log_info "✅ BigQuery dataset created"
    else
        # Check if dataset already exists
        if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
            log_warn "Dataset ${DATASET_NAME} already exists, skipping creation"
        else
            error_exit "Failed to create BigQuery dataset"
        fi
    fi
    
    # Create table for DLP scan results
    local scan_results_schema="scan_id:STRING,file_path:STRING,scan_timestamp:TIMESTAMP,info_type:STRING,likelihood:STRING,quote:STRING,byte_offset_start:INTEGER,byte_offset_end:INTEGER,finding_count:INTEGER,compliance_status:STRING"
    
    if bq mk --project_id="${PROJECT_ID}" --table "${DATASET_NAME}.dlp_scan_results" "${scan_results_schema}" 2>> "${LOG_FILE}"; then
        log_info "✅ DLP scan results table created"
    else
        # Check if table already exists
        if bq ls "${PROJECT_ID}:${DATASET_NAME}.dlp_scan_results" &> /dev/null; then
            log_warn "Table dlp_scan_results already exists, skipping creation"
        else
            error_exit "Failed to create dlp_scan_results table"
        fi
    fi
    
    # Create table for compliance summary metrics
    local summary_schema="date:DATE,total_files_scanned:INTEGER,files_with_pii:INTEGER,high_risk_findings:INTEGER,medium_risk_findings:INTEGER,low_risk_findings:INTEGER,compliance_score:FLOAT"
    
    if bq mk --project_id="${PROJECT_ID}" --table "${DATASET_NAME}.compliance_summary" "${summary_schema}" 2>> "${LOG_FILE}"; then
        log_info "✅ Compliance summary table created"
    else
        # Check if table already exists
        if bq ls "${PROJECT_ID}:${DATASET_NAME}.compliance_summary" &> /dev/null; then
            log_warn "Table compliance_summary already exists, skipping creation"
        else
            error_exit "Failed to create compliance_summary table"
        fi
    fi
    
    save_state "BIGQUERY_CREATED" "true"
    log "✅ BigQuery dataset and tables created for compliance analytics"
}

# Upload sample data for testing
upload_sample_data() {
    log "Uploading sample data with PII for testing..."
    
    # Create sample CSV file with PII data
    cat > "${SCRIPT_DIR}/sample_customer_data.csv" << EOF
customer_id,name,email,phone,ssn,credit_card,address
1001,John Smith,john.smith@email.com,555-123-4567,123-45-6789,4532-1234-5678-9012,123 Main St
1002,Jane Doe,jane.doe@email.com,555-987-6543,987-65-4321,5555-4444-3333-2222,456 Oak Ave
1003,Bob Johnson,bob.johnson@email.com,555-555-5555,555-55-5555,4111-1111-1111-1111,789 Pine Rd
EOF
    
    # Create sample document with mixed PII
    cat > "${SCRIPT_DIR}/privacy_policy.txt" << EOF
Customer Support Contact Information:
Email: support@company.com
Phone: 1-800-555-0123

For account inquiries, reference your account number: AC-123456789
Social Security verification: 123-45-6789
Payment card ending in: 1111
EOF
    
    # Upload sample files to Cloud Storage
    if gsutil cp "${SCRIPT_DIR}/sample_customer_data.csv" "gs://${BUCKET_NAME}/data/" 2>> "${LOG_FILE}"; then
        log_info "✅ Sample customer data uploaded"
    else
        error_exit "Failed to upload sample customer data"
    fi
    
    if gsutil cp "${SCRIPT_DIR}/privacy_policy.txt" "gs://${BUCKET_NAME}/documents/" 2>> "${LOG_FILE}"; then
        log_info "✅ Sample privacy policy uploaded"
    else
        error_exit "Failed to upload sample privacy policy"
    fi
    
    # Clean up local files
    rm -f "${SCRIPT_DIR}/sample_customer_data.csv" "${SCRIPT_DIR}/privacy_policy.txt"
    
    save_state "SAMPLE_DATA_UPLOADED" "true"
    log "✅ Sample data with PII uploaded for compliance testing"
}

# Create DLP inspection template
create_dlp_template() {
    log "Creating DLP inspection template for privacy compliance..."
    
    # Create DLP inspection template configuration
    cat > "${SCRIPT_DIR}/dlp_template.json" << EOF
{
  "displayName": "Privacy Compliance Scanner",
  "description": "Template for detecting PII and sensitive data for privacy compliance",
  "inspectConfig": {
    "infoTypes": [
      {"name": "EMAIL_ADDRESS"},
      {"name": "PHONE_NUMBER"},
      {"name": "US_SOCIAL_SECURITY_NUMBER"},
      {"name": "CREDIT_CARD_NUMBER"},
      {"name": "PERSON_NAME"},
      {"name": "US_DRIVERS_LICENSE_NUMBER"},
      {"name": "DATE_OF_BIRTH"},
      {"name": "IP_ADDRESS"}
    ],
    "minLikelihood": "POSSIBLE",
    "limits": {
      "maxFindingsPerRequest": 1000,
      "maxFindingsPerInfoType": [
        {
          "infoType": {"name": "EMAIL_ADDRESS"},
          "maxFindings": 100
        }
      ]
    }
  }
}
EOF
    
    # Create the DLP inspection template
    local template_response
    template_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @"${SCRIPT_DIR}/dlp_template.json" \
        "https://dlp.googleapis.com/v2/projects/${PROJECT_ID}/inspectTemplates" 2>> "${LOG_FILE}")
    
    if [[ $? -eq 0 ]] && [[ "${template_response}" != *"error"* ]]; then
        export TEMPLATE_NAME="projects/${PROJECT_ID}/inspectTemplates/privacy-compliance-scanner"
        save_state "TEMPLATE_NAME" "${TEMPLATE_NAME}"
        log_info "✅ DLP inspection template created"
    else
        log_warn "DLP template creation may have failed, but continuing..."
        log_info "Response: ${template_response}"
    fi
    
    rm -f "${SCRIPT_DIR}/dlp_template.json"
    
    save_state "DLP_TEMPLATE_CREATED" "true"
    log "✅ DLP inspection template created for privacy compliance"
}

# Create Pub/Sub topic
create_pubsub_topic() {
    log "Creating Pub/Sub topic for DLP notifications..."
    
    # Create Pub/Sub topic for DLP notifications
    if gcloud pubsub topics create dlp-notifications --quiet 2>> "${LOG_FILE}"; then
        log_info "✅ Pub/Sub topic created"
    else
        # Check if topic already exists
        if gcloud pubsub topics describe dlp-notifications &> /dev/null; then
            log_warn "Pub/Sub topic dlp-notifications already exists, skipping creation"
        else
            error_exit "Failed to create Pub/Sub topic"
        fi
    fi
    
    save_state "PUBSUB_TOPIC_CREATED" "true"
    log "✅ Pub/Sub topic for DLP notifications created"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function for automated remediation..."
    
    # Create function source directory
    local function_dir="${SCRIPT_DIR}/../dlp-function"
    mkdir -p "${function_dir}"
    
    # Create requirements.txt for Python dependencies
    cat > "${function_dir}/requirements.txt" << EOF
google-cloud-dlp==3.12.0
google-cloud-bigquery==3.11.4
google-cloud-storage==2.10.0
google-cloud-logging==3.8.0
EOF
    
    # Create main function code
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
from datetime import datetime
from google.cloud import dlp_v2
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import logging as cloud_logging

def process_dlp_results(event, context):
    """Process DLP scan results and perform automated remediation."""
    
    # Initialize clients
    dlp_client = dlp_v2.DlpServiceClient()
    bq_client = bigquery.Client()
    storage_client = storage.Client()
    logging_client = cloud_logging.Client()
    logger = logging_client.logger("dlp-remediation")
    
    try:
        # Parse the message from Pub/Sub
        message_data = json.loads(event['data'].decode('utf-8'))
        
        # Extract scan results
        scan_results = message_data.get('findings', [])
        file_path = message_data.get('file_path', '')
        
        # Process each finding
        for finding in scan_results:
            info_type = finding.get('infoType', {}).get('name', '')
            likelihood = finding.get('likelihood', '')
            quote = finding.get('quote', '')
            
            # Insert results into BigQuery
            table_id = f"{os.environ['PROJECT_ID']}.privacy_compliance.dlp_scan_results"
            rows_to_insert = [{
                'scan_id': context.eventId,
                'file_path': file_path,
                'scan_timestamp': datetime.utcnow().isoformat(),
                'info_type': info_type,
                'likelihood': likelihood,
                'quote': quote[:100],  # Truncate for privacy
                'byte_offset_start': finding.get('location', {}).get('byteRange', {}).get('start', 0),
                'byte_offset_end': finding.get('location', {}).get('byteRange', {}).get('end', 0),
                'finding_count': 1,
                'compliance_status': 'REQUIRES_REVIEW' if likelihood in ['LIKELY', 'VERY_LIKELY'] else 'APPROVED'
            }]
            
            errors = bq_client.insert_rows_json(table_id, rows_to_insert)
            if errors:
                logger.error(f"BigQuery insert errors: {errors}")
            
            # Implement remediation logic
            if likelihood in ['LIKELY', 'VERY_LIKELY']:
                # High-confidence PII detected - implement quarantine
                bucket_name = file_path.split('/')[2]  # Extract bucket from gs:// path
                blob_name = '/'.join(file_path.split('/')[3:])  # Extract object path
                
                bucket = storage_client.bucket(bucket_name)
                blob = bucket.blob(blob_name)
                
                # Add metadata tag for compliance tracking
                blob.metadata = blob.metadata or {}
                blob.metadata['compliance_status'] = 'HIGH_RISK_PII_DETECTED'
                blob.metadata['scan_timestamp'] = datetime.utcnow().isoformat()
                blob.patch()
                
                logger.warning(f"High-risk PII detected in {file_path}: {info_type}")
        
        return {'status': 'success', 'processed_findings': len(scan_results)}
        
    except Exception as e:
        logger.error(f"Error processing DLP results: {str(e)}")
        return {'status': 'error', 'message': str(e)}
EOF
    
    # Deploy the Cloud Function
    local current_dir=$(pwd)
    cd "${function_dir}"
    
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-topic dlp-notifications \
        --entry-point process_dlp_results \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID}" \
        --region="${REGION}" \
        --quiet 2>> "${LOG_FILE}"; then
        log_info "✅ Cloud Function deployed successfully"
    else
        cd "${current_dir}"
        error_exit "Failed to deploy Cloud Function"
    fi
    
    cd "${current_dir}"
    
    save_state "CLOUD_FUNCTION_DEPLOYED" "true"
    log "✅ Cloud Function deployed for automated DLP remediation"
}

# Create and run DLP job
create_dlp_job() {
    log "Creating DLP job to scan Cloud Storage..."
    
    # Create DLP job configuration for Cloud Storage scanning
    cat > "${SCRIPT_DIR}/dlp_job.json" << EOF
{
  "inspectJob": {
    "inspectConfig": {
      "infoTypes": [
        {"name": "EMAIL_ADDRESS"},
        {"name": "PHONE_NUMBER"},
        {"name": "US_SOCIAL_SECURITY_NUMBER"},
        {"name": "CREDIT_CARD_NUMBER"},
        {"name": "PERSON_NAME"}
      ],
      "minLikelihood": "POSSIBLE",
      "limits": {
        "maxFindingsPerRequest": 1000
      }
    },
    "storageConfig": {
      "cloudStorageOptions": {
        "fileSet": {
          "url": "gs://${BUCKET_NAME}/*"
        },
        "bytesLimitPerFile": "10485760",
        "fileTypes": ["CSV", "TEXT_FILE"]
      }
    },
    "actions": [
      {
        "publishToPubSub": {
          "topic": "projects/${PROJECT_ID}/topics/dlp-notifications"
        }
      },
      {
        "publishSummaryToCscc": {}
      }
    ]
  }
}
EOF
    
    # Create the DLP scan job
    local job_response
    job_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @"${SCRIPT_DIR}/dlp_job.json" \
        "https://dlp.googleapis.com/v2/projects/${PROJECT_ID}/dlpJobs" 2>> "${LOG_FILE}")
    
    if [[ $? -eq 0 ]] && [[ "${job_response}" != *"error"* ]]; then
        export DLP_JOB_NAME=$(echo "${job_response}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('name', ''))
except:
    pass
")
        if [[ -n "${DLP_JOB_NAME}" ]]; then
            save_state "DLP_JOB_NAME" "${DLP_JOB_NAME}"
            log_info "✅ DLP scan job created: ${DLP_JOB_NAME}"
        else
            log_warn "DLP job response did not contain job name"
        fi
    else
        log_warn "DLP job creation may have failed, continuing..."
        log_info "Response: ${job_response}"
    fi
    
    rm -f "${SCRIPT_DIR}/dlp_job.json"
    
    save_state "DLP_JOB_CREATED" "true"
    log "✅ DLP scan job created and scanning Cloud Storage for privacy-sensitive data"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    local verification_failed=false
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_info "✅ Cloud Storage bucket verified"
    else
        log_error "❌ Cloud Storage bucket verification failed"
        verification_failed=true
    fi
    
    # Check BigQuery dataset
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log_info "✅ BigQuery dataset verified"
    else
        log_error "❌ BigQuery dataset verification failed"
        verification_failed=true
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_info "✅ Cloud Function verified"
    else
        log_error "❌ Cloud Function verification failed"
        verification_failed=true
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe dlp-notifications &> /dev/null; then
        log_info "✅ Pub/Sub topic verified"
    else
        log_error "❌ Pub/Sub topic verification failed"
        verification_failed=true
    fi
    
    if [[ "${verification_failed}" == "true" ]]; then
        error_exit "Deployment verification failed"
    fi
    
    log "✅ All components verified successfully"
}

# Display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Cloud Storage Bucket: gs://${BUCKET_NAME}"
    log_info "BigQuery Dataset: ${PROJECT_ID}:${DATASET_NAME}"
    log_info "Cloud Function: ${FUNCTION_NAME}"
    log_info "Pub/Sub Topic: dlp-notifications"
    
    if [[ -n "${DLP_JOB_NAME}" ]]; then
        log_info "DLP Job: ${DLP_JOB_NAME}"
    fi
    
    log_info ""
    log_info "Next steps:"
    log_info "1. Monitor DLP job progress using the Google Cloud Console"
    log_info "2. Check BigQuery for scan results: bq query --use_legacy_sql=false \"SELECT * FROM \\\`${PROJECT_ID}.${DATASET_NAME}.dlp_scan_results\\\` LIMIT 10\""
    log_info "3. View Cloud Function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    log_info ""
    log_info "To clean up resources, run: ${SCRIPT_DIR}/destroy.sh"
}

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Deploy Data Privacy Compliance with Cloud DLP and BigQuery"
    echo ""
    echo "Options:"
    echo "  -p, --project PROJECT_ID    Google Cloud Project ID (default: auto-generated)"
    echo "  -r, --region REGION         Google Cloud Region (default: us-central1)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID                  Google Cloud Project ID"
    echo "  REGION                      Google Cloud Region"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main deployment function
main() {
    echo "🚀 Starting Data Privacy Compliance Deployment"
    echo "==============================================="
    echo ""
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_bigquery_resources
    upload_sample_data
    create_dlp_template
    create_pubsub_topic
    deploy_cloud_function
    create_dlp_job
    verify_deployment
    display_summary
    
    log ""
    log "🎉 Deployment completed successfully!"
    log "Check ${LOG_FILE} for detailed logs."
}

# Run main function with all arguments
main "$@"
#!/bin/bash

# Financial Compliance AML AI BigQuery - Deployment Script
# This script deploys the complete AML compliance monitoring solution on Google Cloud Platform

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found"
        echo "Please run: gcloud auth login"
        exit 1
    fi
}

# Function to check if APIs are enabled
check_api_enabled() {
    local api=$1
    if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        return 1
    fi
    return 0
}

# Function to wait for operation completion
wait_for_operation() {
    local operation_name=$1
    local operation_type=${2:-"operation"}
    
    log "Waiting for $operation_type to complete: $operation_name"
    
    local timeout=300  # 5 minutes timeout
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $timeout ]; do
        if gcloud compute operations describe "$operation_name" --zone="$ZONE" --format="value(status)" 2>/dev/null | grep -q "DONE"; then
            success "$operation_type completed successfully"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    error "$operation_type timed out after $timeout seconds"
    return 1
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed"
        echo "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log "Google Cloud CLI version: $gcloud_version"
    
    # Check if other required tools are available
    for tool in bq gsutil openssl; do
        if ! command_exists $tool; then
            error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check gcloud authentication
    check_gcloud_auth
    
    success "Prerequisites check completed"
}

# Configuration setup
setup_configuration() {
    log "Setting up configuration..."
    
    # Generate unique project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="aml-compliance-$(date +%s)"
        warning "PROJECT_ID not set, using generated ID: $PROJECT_ID"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export DATASET_NAME="aml_compliance_data"
    export TABLE_NAME="transactions"
    export MODEL_NAME="aml_detection_model"
    export BUCKET_NAME="aml-reports-${RANDOM_SUFFIX}"
    export TOPIC_NAME="aml-alerts"
    export FUNCTION_NAME="process-aml-alerts"
    export SCHEDULER_JOB="daily-compliance-report"
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "Configuration completed:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    log "  Bucket Name: $BUCKET_NAME"
    
    success "Configuration setup completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if check_api_enabled "$api"; then
            log "API already enabled: $api"
        else
            log "Enabling API: $api"
            if ! gcloud services enable "$api" --quiet; then
                error "Failed to enable API: $api"
                exit 1
            fi
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create BigQuery resources
create_bigquery_resources() {
    log "Creating BigQuery dataset and tables..."
    
    # Create BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        warning "BigQuery dataset already exists: ${DATASET_NAME}"
    else
        log "Creating BigQuery dataset: ${DATASET_NAME}"
        if ! bq mk --location="${REGION}" --dataset "${PROJECT_ID}:${DATASET_NAME}"; then
            error "Failed to create BigQuery dataset"
            exit 1
        fi
    fi
    
    # Create transaction table
    if bq ls "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" >/dev/null 2>&1; then
        warning "Transaction table already exists"
    else
        log "Creating transaction table: ${TABLE_NAME}"
        if ! bq mk --table "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" \
            transaction_id:STRING,timestamp:TIMESTAMP,account_id:STRING,\
amount:NUMERIC,currency:STRING,transaction_type:STRING,\
counterparty_id:STRING,country_code:STRING,risk_score:NUMERIC,\
is_suspicious:BOOLEAN; then
            error "Failed to create transaction table"
            exit 1
        fi
    fi
    
    # Create compliance alerts table
    if bq ls "${PROJECT_ID}:${DATASET_NAME}.compliance_alerts" >/dev/null 2>&1; then
        warning "Compliance alerts table already exists"
    else
        log "Creating compliance alerts table"
        if ! bq mk --table "${PROJECT_ID}:${DATASET_NAME}.compliance_alerts" \
            alert_id:STRING,transaction_id:STRING,risk_score:NUMERIC,\
alert_timestamp:TIMESTAMP,status:STRING,investigator:STRING,\
resolution:STRING,resolution_timestamp:TIMESTAMP; then
            error "Failed to create compliance alerts table"
            exit 1
        fi
    fi
    
    success "BigQuery resources created"
}

# Load sample data
load_sample_data() {
    log "Loading sample transaction data..."
    
    # Create sample transaction data file
    cat > sample_transactions.json << 'EOF'
{"transaction_id":"TXN001","timestamp":"2025-07-12 10:00:00","account_id":"ACC123","amount":"10000.00","currency":"USD","transaction_type":"WIRE","counterparty_id":"CTR456","country_code":"US","risk_score":"0.2","is_suspicious":"false"}
{"transaction_id":"TXN002","timestamp":"2025-07-12 10:15:00","account_id":"ACC124","amount":"50000.00","currency":"USD","transaction_type":"WIRE","counterparty_id":"CTR789","country_code":"XX","risk_score":"0.8","is_suspicious":"true"}
{"transaction_id":"TXN003","timestamp":"2025-07-12 10:30:00","account_id":"ACC125","amount":"5000.00","currency":"EUR","transaction_type":"ACH","counterparty_id":"CTR101","country_code":"DE","risk_score":"0.1","is_suspicious":"false"}
{"transaction_id":"TXN004","timestamp":"2025-07-12 10:45:00","account_id":"ACC123","amount":"75000.00","currency":"USD","transaction_type":"WIRE","counterparty_id":"CTR999","country_code":"XX","risk_score":"0.9","is_suspicious":"true"}
{"transaction_id":"TXN005","timestamp":"2025-07-12 11:00:00","account_id":"ACC126","amount":"25000.00","currency":"USD","transaction_type":"ACH","counterparty_id":"CTR200","country_code":"CA","risk_score":"0.3","is_suspicious":"false"}
{"transaction_id":"TXN006","timestamp":"2025-07-12 11:15:00","account_id":"ACC127","amount":"100000.00","currency":"USD","transaction_type":"WIRE","counterparty_id":"CTR888","country_code":"XX","risk_score":"0.95","is_suspicious":"true"}
EOF
    
    # Load sample data into BigQuery
    if ! bq load --source_format=NEWLINE_DELIMITED_JSON \
        "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" \
        sample_transactions.json; then
        error "Failed to load sample data"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f sample_transactions.json
    
    success "Sample transaction data loaded"
}

# Create BigQuery ML model
create_ml_model() {
    log "Creating BigQuery ML model for AML detection..."
    
    # Check if model already exists
    if bq ls "${PROJECT_ID}:${DATASET_NAME}.${MODEL_NAME}" >/dev/null 2>&1; then
        warning "ML model already exists, skipping creation"
        return 0
    fi
    
    # Create ML model
    local model_query="CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_NAME}.${MODEL_NAME}\`
OPTIONS(model_type='logistic_reg',
        input_label_cols=['is_suspicious']) AS
SELECT
  amount,
  risk_score,
  CASE 
    WHEN transaction_type = 'WIRE' THEN 1 
    ELSE 0 
  END AS is_wire_transfer,
  CASE 
    WHEN country_code = 'XX' THEN 1 
    ELSE 0 
  END AS is_high_risk_country,
  is_suspicious
FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\`"
    
    if ! bq query --use_legacy_sql=false "$model_query"; then
        error "Failed to create BigQuery ML model"
        exit 1
    fi
    
    success "BigQuery ML model created"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topic and subscription..."
    
    # Create topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        warning "Pub/Sub topic already exists: ${TOPIC_NAME}"
    else
        if ! gcloud pubsub topics create "${TOPIC_NAME}"; then
            error "Failed to create Pub/Sub topic"
            exit 1
        fi
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions describe "${TOPIC_NAME}-subscription" >/dev/null 2>&1; then
        warning "Pub/Sub subscription already exists"
    else
        if ! gcloud pubsub subscriptions create "${TOPIC_NAME}-subscription" \
            --topic="${TOPIC_NAME}"; then
            error "Failed to create Pub/Sub subscription"
            exit 1
        fi
    fi
    
    success "Pub/Sub resources created"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for compliance reports..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        warning "Cloud Storage bucket already exists: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create bucket
    if ! gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"; then
        error "Failed to create Cloud Storage bucket"
        exit 1
    fi
    
    # Enable versioning
    if ! gsutil versioning set on "gs://${BUCKET_NAME}"; then
        error "Failed to enable versioning on bucket"
        exit 1
    fi
    
    # Set IAM permissions
    if ! gsutil iam ch "serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com:objectAdmin" \
        "gs://${BUCKET_NAME}"; then
        warning "Failed to set IAM permissions on bucket"
    fi
    
    success "Cloud Storage bucket created"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log "Deploying Cloud Functions..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    
    # Deploy alert processing function
    log "Deploying alert processing function..."
    mkdir -p "${temp_dir}/aml-alert-function"
    cd "${temp_dir}/aml-alert-function"
    
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import bigquery
from google.cloud import monitoring_v3

def process_aml_alert(cloud_event):
    """Process AML alert from Pub/Sub"""
    try:
        # Decode the CloudEvent message
        import base64
        message_data = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
        alert_data = json.loads(message_data)
        
        logging.info(f"Processing AML alert: {alert_data}")
        
        # Initialize BigQuery client
        client = bigquery.Client()
        
        # Log alert to compliance table
        query = f"""
        INSERT INTO `{alert_data['project_id']}.{alert_data['dataset']}.compliance_alerts`
        (alert_id, transaction_id, risk_score, alert_timestamp, status)
        VALUES (
            GENERATE_UUID(),
            '{alert_data['transaction_id']}',
            {alert_data['risk_score']},
            CURRENT_TIMESTAMP(),
            'OPEN'
        )
        """
        
        job = client.query(query)
        job.result()
        
        logging.info(f"AML alert processed successfully: {alert_data['transaction_id']}")
        
        return "Alert processed"
        
    except Exception as e:
        logging.error(f"Error processing AML alert: {e}")
        raise
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.15.0
google-cloud-monitoring==2.18.0
functions-framework==3.5.0
EOF
    
    # Deploy the alert processing function
    if ! gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-topic "${TOPIC_NAME}" \
        --source . \
        --entry-point process_aml_alert \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars PROJECT_ID="${PROJECT_ID}" \
        --quiet; then
        error "Failed to deploy alert processing function"
        cd - > /dev/null
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    cd - > /dev/null
    
    # Deploy compliance reporting function
    log "Deploying compliance reporting function..."
    mkdir -p "${temp_dir}/compliance-report-function"
    cd "${temp_dir}/compliance-report-function"
    
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import storage

def generate_compliance_report(request):
    """Generate daily compliance report"""
    try:
        client = bigquery.Client()
        storage_client = storage.Client()
        
        # Get bucket name from environment
        bucket_name = os.environ.get('BUCKET_NAME')
        if not bucket_name:
            raise ValueError("BUCKET_NAME environment variable not set")
        
        # Generate report for previous day
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        
        # Query suspicious transactions
        query = f"""
        SELECT 
            transaction_id,
            timestamp,
            account_id,
            amount,
            currency,
            risk_score,
            country_code
        FROM `{client.project}.aml_compliance_data.transactions`
        WHERE DATE(timestamp) = '{yesterday}'
          AND is_suspicious = true
        ORDER BY risk_score DESC
        """
        
        results = client.query(query).to_dataframe()
        
        # Generate report content
        report_content = f"""
AML Compliance Report - {yesterday}

Total Suspicious Transactions: {len(results)}
High Risk Transactions (>0.8): {len(results[results['risk_score'] > 0.8]) if len(results) > 0 else 0}

Detailed Transactions:
{results.to_string(index=False) if len(results) > 0 else 'No suspicious transactions found'}

Generated: {datetime.now().isoformat()}
        """
        
        # Upload report to Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(f'compliance-reports/aml-report-{yesterday}.txt')
        blob.upload_from_string(report_content)
        
        print(f"Compliance report generated for {yesterday}")
        return f"Report generated for {yesterday}", 200
        
    except Exception as e:
        print(f"Error generating compliance report: {e}")
        return f"Error generating report: {str(e)}", 500
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.15.0
google-cloud-storage==2.12.0
pandas==2.1.4
functions-framework==3.5.0
EOF
    
    # Deploy the compliance reporting function
    if ! gcloud functions deploy compliance-report-generator \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --source . \
        --entry-point generate_compliance_report \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars PROJECT_ID="${PROJECT_ID}",BUCKET_NAME="${BUCKET_NAME}" \
        --quiet; then
        error "Failed to deploy compliance reporting function"
        cd - > /dev/null
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    cd - > /dev/null
    rm -rf "${temp_dir}"
    
    success "Cloud Functions deployed"
}

# Create Cloud Scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job..."
    
    # Check if job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB}" >/dev/null 2>&1; then
        warning "Scheduler job already exists: ${SCHEDULER_JOB}"
        return 0
    fi
    
    # Get the function URL
    local function_url=$(gcloud functions describe compliance-report-generator \
        --gen2 \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    # Create scheduler job
    if ! gcloud scheduler jobs create http "${SCHEDULER_JOB}" \
        --schedule="0 2 * * *" \
        --time-zone="America/New_York" \
        --uri="${function_url}" \
        --http-method=GET \
        --description="Daily AML compliance report generation"; then
        error "Failed to create Cloud Scheduler job"
        exit 1
    fi
    
    success "Cloud Scheduler job created"
}

# Test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test ML model predictions
    log "Testing ML model predictions..."
    local test_query="SELECT 
       'TEST001' as transaction_id,
       amount,
       risk_score,
       predicted_is_suspicious,
       predicted_is_suspicious_probs
     FROM ML.PREDICT(MODEL \`${PROJECT_ID}.${DATASET_NAME}.${MODEL_NAME}\`,
       (SELECT 
          'TEST001' as transaction_id,
          75000.0 as amount,
          0.85 as risk_score,
          1 as is_wire_transfer,
          1 as is_high_risk_country
       )
     )"
    
    if ! bq query --use_legacy_sql=false "$test_query" >/dev/null 2>&1; then
        warning "ML model prediction test failed"
    else
        success "ML model prediction test passed"
    fi
    
    # Test Pub/Sub alert processing
    log "Testing Pub/Sub alert processing..."
    local test_message='{"transaction_id":"TEST001","risk_score":0.9,"project_id":"'${PROJECT_ID}'","dataset":"'${DATASET_NAME}'"}'
    
    if ! echo "$test_message" | gcloud pubsub topics publish "${TOPIC_NAME}" --message=-; then
        warning "Pub/Sub alert test failed"
    else
        success "Pub/Sub alert test message sent"
        # Wait a moment for processing
        sleep 10
        
        # Check if alert was processed
        local alert_count=$(bq query --use_legacy_sql=false --format=csv \
            "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_NAME}.compliance_alerts\`" | tail -n 1)
        
        if [ "$alert_count" -gt 0 ]; then
            success "Alert processing test passed (${alert_count} alerts found)"
        else
            warning "Alert processing test may have failed (no alerts found)"
        fi
    fi
    
    success "Deployment testing completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Dataset: ${PROJECT_ID}:${DATASET_NAME}"
    echo "ML Model: ${PROJECT_ID}:${DATASET_NAME}.${MODEL_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Pub/Sub Topic: ${TOPIC_NAME}"
    echo "Alert Function: ${FUNCTION_NAME}"
    echo "Report Function: compliance-report-generator"
    echo "Scheduler Job: ${SCHEDULER_JOB}"
    echo ""
    echo "Next Steps:"
    echo "1. Access BigQuery console to view your dataset and ML model"
    echo "2. Monitor Cloud Functions logs for alert processing"
    echo "3. Check Cloud Storage bucket for generated compliance reports"
    echo "4. Review Cloud Scheduler for automated report generation"
    echo ""
    echo "Useful Commands:"
    echo "  View transactions: bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\` LIMIT 10'"
    echo "  Check alerts: bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.compliance_alerts\` ORDER BY alert_timestamp DESC LIMIT 10'"
    echo "  List reports: gsutil ls gs://${BUCKET_NAME}/compliance-reports/"
}

# Main deployment function
main() {
    log "Starting Financial Compliance AML AI BigQuery deployment..."
    
    # Trap to handle script interruption
    trap 'error "Deployment interrupted"; exit 1' INT TERM
    
    # Run deployment steps
    check_prerequisites
    setup_configuration
    enable_apis
    create_bigquery_resources
    load_sample_data
    create_ml_model
    create_pubsub_resources
    create_storage_bucket
    deploy_cloud_functions
    create_scheduler_job
    test_deployment
    print_summary
    
    success "Financial Compliance AML AI BigQuery deployment completed successfully!"
    log "Total deployment time: $SECONDS seconds"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
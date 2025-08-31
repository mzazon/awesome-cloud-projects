#!/bin/bash

# Automated Cost Analytics with Worker Pools and BigQuery - Deployment Script
# This script deploys the complete infrastructure for the cost analytics solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq CLI is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warning "openssl not found. Using date for random suffix generation."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-cost-analytics-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
    fi
    export RANDOM_SUFFIX
    
    # Set resource names
    export DATASET_NAME="cost_analytics_${RANDOM_SUFFIX}"
    export TOPIC_NAME="cost-processing-${RANDOM_SUFFIX}"
    export SERVICE_NAME="cost-worker-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="cost-processing-sub-${RANDOM_SUFFIX}"
    export SA_NAME="cost-worker-sa-${RANDOM_SUFFIX}"
    export JOB_NAME="daily-cost-analysis-${RANDOM_SUFFIX}"
    
    # Display configuration
    log "Deployment Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  Random Suffix: ${RANDOM_SUFFIX}"
    echo "  Dataset Name: ${DATASET_NAME}"
    echo "  Topic Name: ${TOPIC_NAME}"
    echo "  Service Name: ${SERVICE_NAME}"
    
    success "Environment variables configured"
}

# Function to configure GCP project
configure_project() {
    log "Configuring GCP project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
    gcloud config set compute/zone "${ZONE}" 2>/dev/null || true
    
    success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required GCP APIs..."
    
    local apis=(
        "cloudbilling.googleapis.com"
        "bigquery.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
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

# Function to create BigQuery dataset and tables
create_bigquery_resources() {
    log "Creating BigQuery resources..."
    
    # Create BigQuery dataset
    log "Creating BigQuery dataset: ${DATASET_NAME}"
    if bq mk --dataset \
        --description "Automated cost analytics dataset" \
        --location="${REGION}" \
        "${PROJECT_ID}:${DATASET_NAME}"; then
        success "BigQuery dataset created: ${DATASET_NAME}"
    else
        error "Failed to create BigQuery dataset"
        exit 1
    fi
    
    # Create cost analytics table with partitioning
    log "Creating cost analytics table..."
    if bq mk --table \
        --description "Daily cost analytics with project breakdown" \
        --time_partitioning_field=usage_date \
        --time_partitioning_type=DAY \
        "${PROJECT_ID}:${DATASET_NAME}.daily_costs" \
        usage_date:DATE,project_id:STRING,service:STRING,sku:STRING,cost:FLOAT,currency:STRING,labels:STRING; then
        success "Cost analytics table created"
    else
        error "Failed to create cost analytics table"
        exit 1
    fi
    
    # Create cost summary view
    log "Creating monthly cost summary view..."
    local monthly_view_sql="
        SELECT 
          FORMAT_DATE(\"%Y-%m\", usage_date) as month,
          project_id,
          service,
          SUM(cost) as total_cost,
          currency,
          COUNT(*) as usage_records
        FROM \`${PROJECT_ID}.${DATASET_NAME}.daily_costs\`
        WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
        GROUP BY month, project_id, service, currency
        ORDER BY month DESC, total_cost DESC
    "
    
    if bq mk --view \
        --description "Monthly cost summary by project and service" \
        --project_id "${PROJECT_ID}" \
        "${monthly_view_sql}" \
        "${PROJECT_ID}:${DATASET_NAME}.monthly_cost_summary"; then
        success "Monthly cost summary view created"
    else
        warning "Monthly cost summary view creation failed, continuing..."
    fi
    
    # Create cost trend analysis view
    log "Creating cost trend analysis view..."
    local trend_view_sql="
        WITH weekly_costs AS (
          SELECT 
            DATE_TRUNC(usage_date, WEEK) as week_start,
            project_id,
            service,
            SUM(cost) as weekly_cost
          FROM \`${PROJECT_ID}.${DATASET_NAME}.daily_costs\`
          GROUP BY week_start, project_id, service
        )
        SELECT 
          week_start,
          project_id,
          service,
          weekly_cost,
          LAG(weekly_cost) OVER (
            PARTITION BY project_id, service 
            ORDER BY week_start
          ) as previous_week_cost,
          ROUND(
            (weekly_cost - LAG(weekly_cost) OVER (
              PARTITION BY project_id, service 
              ORDER BY week_start
            )) / LAG(weekly_cost) OVER (
              PARTITION BY project_id, service 
              ORDER BY week_start
            ) * 100, 2
          ) as week_over_week_change_percent
        FROM weekly_costs
        ORDER BY week_start DESC, weekly_cost DESC
    "
    
    if bq mk --view \
        --description "Cost trend analysis with week-over-week comparison" \
        --project_id "${PROJECT_ID}" \
        "${trend_view_sql}" \
        "${PROJECT_ID}:${DATASET_NAME}.cost_trend_analysis"; then
        success "Cost trend analysis view created"
    else
        warning "Cost trend analysis view creation failed, continuing..."
    fi
    
    success "BigQuery resources created successfully"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub resources..."
    
    # Create Pub/Sub topic
    log "Creating Pub/Sub topic: ${TOPIC_NAME}"
    if gcloud pubsub topics create "${TOPIC_NAME}"; then
        success "Pub/Sub topic created: ${TOPIC_NAME}"
    else
        error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    success "Pub/Sub resources created successfully"
}

# Function to create service account and IAM permissions
create_service_account() {
    log "Creating service account and setting up IAM permissions..."
    
    # Create service account
    log "Creating service account: ${SA_NAME}"
    if gcloud iam service-accounts create "${SA_NAME}" \
        --description "Service account for cost analytics worker" \
        --display-name "Cost Analytics Worker"; then
        success "Service account created: ${SA_NAME}"
    else
        error "Failed to create service account"
        exit 1
    fi
    
    # Grant necessary permissions
    local sa_email="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log "Granting BigQuery permissions..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member "serviceAccount:${sa_email}" \
        --role "roles/bigquery.dataEditor"; then
        success "BigQuery permissions granted"
    else
        error "Failed to grant BigQuery permissions"
        exit 1
    fi
    
    log "Granting billing viewer permissions..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member "serviceAccount:${sa_email}" \
        --role "roles/billing.viewer"; then
        success "Billing viewer permissions granted"
    else
        error "Failed to grant billing viewer permissions"
        exit 1
    fi
    
    log "Granting Cloud Run invoker permissions..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member "serviceAccount:${sa_email}" \
        --role "roles/run.invoker"; then
        success "Cloud Run invoker permissions granted"
    else
        error "Failed to grant Cloud Run invoker permissions"
        exit 1
    fi
    
    success "Service account and IAM permissions configured"
}

# Function to build and deploy Cloud Run worker
deploy_cloud_run_worker() {
    log "Creating and deploying Cloud Run worker..."
    
    # Create temporary directory for worker code
    local temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    log "Creating worker application in ${temp_dir}..."
    
    # Create Python requirements file
    cat > requirements.txt << 'EOF'
google-cloud-billing==1.12.0
google-cloud-bigquery==3.15.0
google-cloud-pubsub==2.20.0
pandas==2.2.0
functions-framework==3.5.0
EOF
    
    # Create cost processing worker
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime, timedelta
from google.cloud import billing_v1
from google.cloud import bigquery
from google.cloud import pubsub_v1
import pandas as pd
import functions_framework

@functions_framework.cloud_event
def process_cost_data(cloud_event):
    """Process billing data and load into BigQuery"""
    
    # Initialize clients
    billing_client = billing_v1.CloudBillingClient()
    bq_client = bigquery.Client()
    
    # Get environment variables
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    dataset_name = os.environ.get('DATASET_NAME')
    billing_account = os.environ.get('BILLING_ACCOUNT', 'sample-billing-account')
    
    # Calculate date range (previous day)
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=1)
    
    try:
        # Retrieve billing data
        billing_data = get_billing_data(
            billing_client, billing_account, start_date, end_date
        )
        
        # Transform and load data
        if billing_data:
            load_to_bigquery(bq_client, project_id, dataset_name, billing_data)
            print(f"✅ Processed {len(billing_data)} cost records for {start_date}")
        else:
            print(f"No billing data found for {start_date}")
            
    except Exception as e:
        print(f"❌ Error processing cost data: {str(e)}")
        raise

def get_billing_data(client, billing_account, start_date, end_date):
    """Retrieve billing data from Cloud Billing API"""
    # This is a simplified example structure
    # In production, this would use actual billing API calls
    return [
        {
            'usage_date': start_date,
            'project_id': os.environ.get('GOOGLE_CLOUD_PROJECT', 'sample-project'),
            'service': 'Compute Engine',
            'sku': 'N1 Standard Instance',
            'cost': 12.45,
            'currency': 'USD',
            'labels': json.dumps({'environment': 'production'})
        },
        {
            'usage_date': start_date,
            'project_id': os.environ.get('GOOGLE_CLOUD_PROJECT', 'sample-project'),
            'service': 'BigQuery',
            'sku': 'Analysis',
            'cost': 5.23,
            'currency': 'USD',
            'labels': json.dumps({'department': 'analytics'})
        }
    ]

def load_to_bigquery(client, project_id, dataset_name, data):
    """Load processed data into BigQuery"""
    table_ref = f"{project_id}.{dataset_name}.daily_costs"
    
    # Convert to DataFrame and load
    df = pd.DataFrame(data)
    job_config = bigquery.LoadJobConfig(
        write_disposition="WRITE_APPEND",
        time_partitioning=bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY,
            field="usage_date"
        )
    )
    
    job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
    job.result()  # Wait for job completion
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD exec functions-framework --target=process_cost_data --port=8080
EOF
    
    # Deploy Cloud Run service
    log "Deploying Cloud Run service: ${SERVICE_NAME}"
    local sa_email="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --service-account="${sa_email}" \
        --set-env-vars="DATASET_NAME=${DATASET_NAME}" \
        --memory 1Gi \
        --cpu 1 \
        --min-instances 0 \
        --max-instances 10 \
        --concurrency 10 \
        --quiet; then
        success "Cloud Run worker deployed: ${SERVICE_NAME}"
    else
        error "Failed to deploy Cloud Run service"
        exit 1
    fi
    
    # Clean up temporary directory
    cd /
    rm -rf "${temp_dir}"
    
    success "Cloud Run worker deployment completed"
}

# Function to create Pub/Sub subscription
create_pubsub_subscription() {
    log "Creating Pub/Sub subscription..."
    
    # Get Cloud Run service URL
    local service_url
    service_url=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    if [[ -z "${service_url}" ]]; then
        error "Failed to get Cloud Run service URL"
        exit 1
    fi
    
    # Create Pub/Sub subscription for Cloud Run
    log "Creating subscription: ${SUBSCRIPTION_NAME}"
    if gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
        --topic "${TOPIC_NAME}" \
        --push-endpoint "${service_url}" \
        --ack-deadline 300 \
        --message-retention-duration 7d; then
        success "Pub/Sub subscription created: ${SUBSCRIPTION_NAME}"
    else
        error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    success "Pub/Sub integration configured"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job..."
    
    if gcloud scheduler jobs create pubsub "${JOB_NAME}" \
        --schedule "0 1 * * *" \
        --topic "${TOPIC_NAME}" \
        --message-body '{"trigger":"daily_cost_analysis","date":"auto"}' \
        --time-zone "America/New_York" \
        --description "Daily automated cost analytics processing"; then
        success "Cloud Scheduler job created: ${JOB_NAME}"
    else
        error "Failed to create Cloud Scheduler job"
        exit 1
    fi
    
    success "Automated scheduling configured"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Test Pub/Sub message publishing
    log "Testing Pub/Sub message publishing..."
    if gcloud pubsub topics publish "${TOPIC_NAME}" \
        --message '{"test":"deployment_validation","timestamp":"'$(date -Iseconds)'"}'; then
        success "Pub/Sub test message published"
    else
        warning "Pub/Sub test message failed"
    fi
    
    # Check Cloud Run service status
    log "Checking Cloud Run service status..."
    local service_status
    service_status=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format 'value(status.conditions[0].type)')
    
    if [[ "${service_status}" == "Ready" ]]; then
        success "Cloud Run service is ready"
    else
        warning "Cloud Run service status: ${service_status}"
    fi
    
    # Verify BigQuery resources
    log "Verifying BigQuery resources..."
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" > /dev/null 2>&1; then
        success "BigQuery dataset is accessible"
    else
        warning "BigQuery dataset verification failed"
    fi
    
    success "Validation tests completed"
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment Summary:"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Dataset: ${DATASET_NAME}"
    echo "Cloud Run Service: ${SERVICE_NAME}"
    echo "Pub/Sub Topic: ${TOPIC_NAME}"
    echo "Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
    echo "Service Account: ${SA_NAME}"
    echo "Scheduler Job: ${JOB_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Configure billing account access if needed"
    echo "2. Test the scheduled job: gcloud scheduler jobs run ${JOB_NAME}"
    echo "3. Monitor logs: gcloud logs read \"resource.type=cloud_run_revision\""
    echo "4. Query cost data: bq query \"SELECT * FROM \\\`${PROJECT_ID}.${DATASET_NAME}.daily_costs\\\` LIMIT 10\""
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    echo "============================================"
    echo "Automated Cost Analytics - Deployment Script"
    echo "============================================"
    echo ""
    
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_bigquery_resources
    create_pubsub_resources
    create_service_account
    deploy_cloud_run_worker
    create_pubsub_subscription
    create_scheduler_job
    run_validation
    show_deployment_summary
}

# Handle script interruption
trap 'error "Deployment interrupted!"; exit 1' INT TERM

# Run main function
main "$@"
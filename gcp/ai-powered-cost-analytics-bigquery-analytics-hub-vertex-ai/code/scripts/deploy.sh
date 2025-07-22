#!/bin/bash

# AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI - Deployment Script
# This script deploys the complete cost analytics infrastructure on Google Cloud Platform

set -euo pipefail

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if dry run mode is enabled
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY RUN mode - no actual resources will be created"
fi

# Function to execute commands (supports dry run)
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: $*"
    else
        eval "$@"
    fi
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Command '$1' is not installed. Please install it before running this script."
    fi
}

# Function to check if gcloud is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        error "No active gcloud authentication found. Please run 'gcloud auth login' first."
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check required commands
    check_command "gcloud"
    check_command "bq"
    check_command "gsutil"
    check_command "openssl"
    
    # Check gcloud authentication
    check_auth
    
    # Check if required environment variables are set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        # Generate project ID if not provided
        export PROJECT_ID="cost-analytics-$(date +%s)"
        warning "PROJECT_ID not set, generated: ${PROJECT_ID}"
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
        warning "REGION not set, using default: ${REGION}"
    fi
    
    success "Prerequisites validated"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigquery.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbilling.googleapis.com"
        "datacatalog.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        execute gcloud services enable "${api}" --project="${PROJECT_ID}"
    done
    
    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "APIs enabled successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Export core variables
    export ZONE="${ZONE:-${REGION}-a}"
    export DATASET_ID="${DATASET_ID:-cost_analytics}"
    export EXCHANGE_ID="${EXCHANGE_ID:-cost_data_exchange}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-cost-analytics-data-${RANDOM_SUFFIX}}"
    export MODEL_NAME="${MODEL_NAME:-cost-prediction-model-${RANDOM_SUFFIX}}"
    export ENDPOINT_NAME="${ENDPOINT_NAME:-cost-prediction-endpoint-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    execute gcloud config set project "${PROJECT_ID}"
    execute gcloud config set compute/region "${REGION}"
    execute gcloud config set compute/zone "${ZONE}"
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  DATASET_ID: ${DATASET_ID}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  MODEL_NAME: ${MODEL_NAME}"
    log "  ENDPOINT_NAME: ${ENDPOINT_NAME}"
    
    success "Environment setup complete"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for model artifacts..."
    
    execute gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"
    
    # Enable versioning for model artifacts
    execute gsutil versioning set on "gs://${BUCKET_NAME}"
    
    success "Cloud Storage bucket created: gs://${BUCKET_NAME}"
}

# Function to create BigQuery dataset and tables
create_bigquery_resources() {
    log "Creating BigQuery cost analytics dataset..."
    
    # Create the main analytics dataset
    execute bq mk --dataset \
        --location="${REGION}" \
        --description="Cost analytics and ML models" \
        "${PROJECT_ID}:${DATASET_ID}"
    
    # Create table for billing data with partitioning
    log "Creating partitioned billing data table..."
    execute bq mk --table \
        --time_partitioning_field=usage_start_time \
        --time_partitioning_type=DAY \
        --description="Daily cost and usage data" \
        "${PROJECT_ID}:${DATASET_ID}.billing_data" \
        "usage_start_time:TIMESTAMP,service_description:STRING,sku_description:STRING,project_id:STRING,cost:FLOAT64,currency:STRING,usage_amount:FLOAT64,usage_unit:STRING,location:STRING,labels:JSON"
    
    success "BigQuery dataset and billing table created"
}

# Function to set up Analytics Hub
setup_analytics_hub() {
    log "Setting up Analytics Hub data exchange..."
    
    # Create data exchange for cost analytics
    execute bq mk --data_exchange \
        --location="${REGION}" \
        --display_name="Cost Analytics Exchange" \
        --description="Shared cost data and optimization insights" \
        "${PROJECT_ID}:${EXCHANGE_ID}"
    
    # Create a listing for the billing dataset
    execute bq mk --listing \
        --data_exchange="${EXCHANGE_ID}" \
        --location="${REGION}" \
        --display_name="Billing Data Feed" \
        --description="Real-time billing and usage data" \
        --source_dataset="${PROJECT_ID}:${DATASET_ID}" \
        "${PROJECT_ID}:${EXCHANGE_ID}.billing_feed"
    
    success "Analytics Hub exchange and listing created"
}

# Function to load sample billing data
load_sample_data() {
    log "Loading sample billing data for training and testing..."
    
    execute bq query --use_legacy_sql=false "
    INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.billing_data\`
    (usage_start_time, service_description, sku_description, project_id, cost, currency, usage_amount, usage_unit, location, labels)
    WITH sample_data AS (
      SELECT
        TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL MOD(seq, 365) DAY) as usage_start_time,
        CASE MOD(seq, 4)
          WHEN 0 THEN 'Compute Engine'
          WHEN 1 THEN 'BigQuery'
          WHEN 2 THEN 'Cloud Storage'
          ELSE 'Cloud Functions'
        END as service_description,
        CASE MOD(seq, 4)
          WHEN 0 THEN 'N1 Standard Instance Core'
          WHEN 1 THEN 'Analysis'
          WHEN 2 THEN 'Standard Storage'
          ELSE 'Invocations'
        END as sku_description,
        CONCAT('project-', MOD(seq, 10)) as project_id,
        ROUND(RAND() * 1000 + 50, 2) as cost,
        'USD' as currency,
        ROUND(RAND() * 100, 2) as usage_amount,
        CASE MOD(seq, 4)
          WHEN 0 THEN 'hour'
          WHEN 1 THEN 'byte'
          WHEN 2 THEN 'byte-second'
          ELSE 'request'
        END as usage_unit,
        '${REGION}' as location,
        JSON '{\"team\": \"engineering\", \"environment\": \"production\"}' as labels
      FROM UNNEST(GENERATE_ARRAY(1, 1000)) as seq
    )
    SELECT * FROM sample_data"
    
    success "Sample billing data loaded for analysis"
}

# Function to create analytics views
create_analytics_views() {
    log "Creating analytics views for cost insights..."
    
    # Create daily cost summary view
    execute bq mk --view \
        --description="Daily cost aggregations by service and project" \
        --use_legacy_sql=false \
        "${PROJECT_ID}:${DATASET_ID}.daily_cost_summary" \
        "SELECT
          DATE(usage_start_time) as usage_date,
          service_description,
          project_id,
          location,
          SUM(cost) as total_cost,
          SUM(usage_amount) as total_usage,
          COUNT(*) as transaction_count,
          AVG(cost) as avg_cost_per_transaction
        FROM \`${PROJECT_ID}.${DATASET_ID}.billing_data\`
        GROUP BY usage_date, service_description, project_id, location
        ORDER BY usage_date DESC, total_cost DESC"
    
    # Create cost trend analysis view
    log "Creating cost trend analysis view..."
    execute bq mk --view \
        --description="7-day rolling cost trends with growth rates" \
        --use_legacy_sql=false \
        "${PROJECT_ID}:${DATASET_ID}.cost_trends" \
        "WITH daily_costs AS (
          SELECT
            DATE(usage_start_time) as usage_date,
            service_description,
            SUM(cost) as daily_cost
          FROM \`${PROJECT_ID}.${DATASET_ID}.billing_data\`
          GROUP BY usage_date, service_description
        )
        SELECT
          usage_date,
          service_description,
          daily_cost,
          AVG(daily_cost) OVER (
            PARTITION BY service_description 
            ORDER BY usage_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
          ) as seven_day_avg,
          LAG(daily_cost, 7) OVER (
            PARTITION BY service_description 
            ORDER BY usage_date
          ) as cost_7_days_ago,
          SAFE_DIVIDE(
            daily_cost - LAG(daily_cost, 7) OVER (
              PARTITION BY service_description 
              ORDER BY usage_date
            ),
            LAG(daily_cost, 7) OVER (
              PARTITION BY service_description 
              ORDER BY usage_date
            )
          ) * 100 as growth_rate_pct
        FROM daily_costs
        ORDER BY usage_date DESC, daily_cost DESC"
    
    success "Analytics views created for cost insights"
}

# Function to train machine learning model
train_ml_model() {
    log "Training BigQuery ML cost prediction model..."
    
    # Create and train the cost prediction model
    execute bq query --use_legacy_sql=false "
    CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.cost_prediction_bqml\`
    OPTIONS(
      model_type='LINEAR_REG',
      input_label_cols=['cost'],
      max_iterations=50
    ) AS
    SELECT
      EXTRACT(DAYOFWEEK FROM usage_start_time) as day_of_week,
      EXTRACT(HOUR FROM usage_start_time) as hour_of_day,
      service_description,
      project_id,
      usage_amount,
      LAG(cost, 1) OVER (
        PARTITION BY service_description, project_id 
        ORDER BY usage_start_time
      ) as previous_cost,
      LAG(cost, 7) OVER (
        PARTITION BY service_description, project_id 
        ORDER BY usage_start_time
      ) as cost_week_ago,
      cost
    FROM \`${PROJECT_ID}.${DATASET_ID}.billing_data\`
    WHERE usage_start_time < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)"
    
    # Export model for Vertex AI deployment
    log "Exporting model for Vertex AI deployment..."
    execute bq extract --destination_format=ML_TF_SAVED_MODEL \
        --destination_uri="gs://${BUCKET_NAME}/models/cost_prediction/*" \
        "${PROJECT_ID}:${DATASET_ID}.cost_prediction_bqml"
    
    success "BigQuery ML model trained and exported"
}

# Function to deploy model to Vertex AI
deploy_vertex_ai_model() {
    log "Deploying model to Vertex AI endpoint..."
    
    # Upload model to Vertex AI Model Registry
    log "Uploading model to Vertex AI Model Registry..."
    execute gcloud ai models upload \
        --region="${REGION}" \
        --display-name="${MODEL_NAME}" \
        --description="Cost prediction model for analytics" \
        --artifact-uri="gs://${BUCKET_NAME}/models/cost_prediction" \
        --container-image-uri="gcr.io/cloud-aiplatform/prediction/tf2-cpu.2-8:latest"
    
    # Get the model ID
    if [[ "$DRY_RUN" != "true" ]]; then
        MODEL_ID=$(gcloud ai models list \
            --region="${REGION}" \
            --filter="displayName:${MODEL_NAME}" \
            --format="value(name)" | cut -d'/' -f6)
        log "Model ID: ${MODEL_ID}"
    else
        MODEL_ID="model-id-placeholder"
    fi
    
    # Create prediction endpoint
    log "Creating prediction endpoint..."
    execute gcloud ai endpoints create \
        --region="${REGION}" \
        --display-name="${ENDPOINT_NAME}" \
        --description="Cost prediction endpoint for real-time inference"
    
    # Get the endpoint ID
    if [[ "$DRY_RUN" != "true" ]]; then
        ENDPOINT_ID=$(gcloud ai endpoints list \
            --region="${REGION}" \
            --filter="displayName:${ENDPOINT_NAME}" \
            --format="value(name)" | cut -d'/' -f6)
        log "Endpoint ID: ${ENDPOINT_ID}"
    else
        ENDPOINT_ID="endpoint-id-placeholder"
    fi
    
    # Deploy model to endpoint
    log "Deploying model to endpoint..."
    execute gcloud ai endpoints deploy-model "${ENDPOINT_ID}" \
        --region="${REGION}" \
        --model="${MODEL_ID}" \
        --display-name="${MODEL_NAME}-deployment" \
        --machine-type=n1-standard-2 \
        --min-replica-count=1 \
        --max-replica-count=3
    
    success "Model deployed to Vertex AI endpoint: ${ENDPOINT_ID}"
}

# Function to create anomaly detection system
create_anomaly_detection() {
    log "Creating cost anomaly detection system..."
    
    # Create anomaly detection model in BigQuery ML
    execute bq query --use_legacy_sql=false "
    CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.cost_anomaly_detection\`
    OPTIONS(
      model_type='KMEANS',
      num_clusters=3,
      standardize_features=true
    ) AS
    SELECT
      daily_cost,
      seven_day_avg,
      growth_rate_pct,
      service_description
    FROM \`${PROJECT_ID}.${DATASET_ID}.cost_trends\`
    WHERE growth_rate_pct IS NOT NULL"
    
    # Create anomaly detection view
    log "Creating anomaly detection view..."
    execute bq mk --view \
        --description="Cost anomalies with severity scores" \
        --use_legacy_sql=false \
        "${PROJECT_ID}:${DATASET_ID}.cost_anomalies" \
        "WITH anomaly_scores AS (
          SELECT
            usage_date,
            service_description,
            daily_cost,
            seven_day_avg,
            growth_rate_pct,
            ML.DISTANCE_TO_CENTROID(
              MODEL \`${PROJECT_ID}.${DATASET_ID}.cost_anomaly_detection\`,
              (SELECT AS STRUCT daily_cost, seven_day_avg, growth_rate_pct, service_description)
            ) as anomaly_score
          FROM \`${PROJECT_ID}.${DATASET_ID}.cost_trends\`
          WHERE growth_rate_pct IS NOT NULL
        )
        SELECT
          *,
          CASE
            WHEN anomaly_score > 2.0 THEN 'HIGH'
            WHEN anomaly_score > 1.0 THEN 'MEDIUM'
            ELSE 'LOW'
          END as severity
        FROM anomaly_scores
        WHERE anomaly_score > 0.5
        ORDER BY anomaly_score DESC, usage_date DESC"
    
    success "Cost anomaly detection system created"
}

# Function to set up monitoring and alerts
setup_monitoring() {
    log "Setting up Cloud Monitoring for cost alerts..."
    
    # Create alert policy configuration
    cat > /tmp/cost_alert_policy.json << EOF
{
  "displayName": "High Cost Anomaly Alert",
  "documentation": {
    "content": "Alert when cost anomalies exceed threshold",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "High Anomaly Score",
      "conditionThreshold": {
        "filter": "resource.type=\"bigquery_dataset\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 2.0,
        "duration": "300s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    # Create the alert policy
    execute gcloud alpha monitoring policies create \
        --policy-from-file=/tmp/cost_alert_policy.json
    
    # Create custom metric for cost trends
    execute bq query --use_legacy_sql=false "
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.monitoring_metrics\` AS
    SELECT
      CURRENT_TIMESTAMP() as timestamp,
      service_description,
      daily_cost,
      growth_rate_pct,
      CASE
        WHEN growth_rate_pct > 50 THEN 1
        ELSE 0
      END as high_growth_alert
    FROM \`${PROJECT_ID}.${DATASET_ID}.cost_trends\`
    WHERE usage_date = CURRENT_DATE() - 1"
    
    # Clean up temporary file
    rm -f /tmp/cost_alert_policy.json
    
    success "Cloud Monitoring alerts configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry run validation complete - no actual resources to validate"
        return
    fi
    
    # Check BigQuery resources
    log "Validating BigQuery resources..."
    if bq ls "${PROJECT_ID}:${DATASET_ID}" > /dev/null 2>&1; then
        success "BigQuery dataset accessible"
    else
        error "BigQuery dataset validation failed"
    fi
    
    # Check data loading
    log "Validating data loading..."
    local record_count
    record_count=$(bq query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_ID}.billing_data\`" | tail -n1)
    
    if [[ "$record_count" -gt 0 ]]; then
        success "Sample data loaded successfully: ${record_count} records"
    else
        warning "No data found in billing table"
    fi
    
    # Check Cloud Storage bucket
    log "Validating Cloud Storage bucket..."
    if gsutil ls "gs://${BUCKET_NAME}" > /dev/null 2>&1; then
        success "Cloud Storage bucket accessible"
    else
        error "Cloud Storage bucket validation failed"
    fi
    
    success "Deployment validation complete"
}

# Function to display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "BigQuery Dataset: ${PROJECT_ID}:${DATASET_ID}"
    log "Storage Bucket: gs://${BUCKET_NAME}"
    log "Model Name: ${MODEL_NAME}"
    log "Endpoint Name: ${ENDPOINT_NAME}"
    log ""
    log "Next Steps:"
    log "1. Verify BigQuery data: bq query --use_legacy_sql=false \"SELECT COUNT(*) FROM \\\`${PROJECT_ID}.${DATASET_ID}.billing_data\\\`\""
    log "2. Check Analytics Hub: bq ls --data_exchange --location=${REGION}"
    log "3. Test cost predictions using the Vertex AI endpoint"
    log "4. Monitor cost anomalies in the cost_anomalies view"
    log ""
    log "Cleanup: Run ./destroy.sh when you're done testing"
    
    success "AI-Powered Cost Analytics deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting AI-Powered Cost Analytics deployment..."
    log "=== AI-POWERED COST ANALYTICS DEPLOYMENT ==="
    
    validate_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_bigquery_resources
    setup_analytics_hub
    load_sample_data
    create_analytics_views
    train_ml_model
    deploy_vertex_ai_model
    create_anomaly_detection
    setup_monitoring
    validate_deployment
    display_summary
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created."' INT TERM

# Run main function
main "$@"
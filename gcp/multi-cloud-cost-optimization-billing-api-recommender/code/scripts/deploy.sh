#!/bin/bash

# Multi-Cloud Cost Optimization with Cloud Billing API and Cloud Recommender - Deployment Script
# This script deploys the complete cost optimization infrastructure on Google Cloud Platform

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="cost-optimization"
REGION="us-central1"
ZONE="us-central1-a"

# Functions directory relative to script location
FUNCTIONS_DIR="${SCRIPT_DIR}/../terraform/function_code"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install BigQuery CLI."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if functions source directory exists
    if [[ ! -d "$FUNCTIONS_DIR" ]]; then
        error "Functions source directory not found: $FUNCTIONS_DIR"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Prompt for confirmation
confirm_deployment() {
    echo -e "${BLUE}Multi-Cloud Cost Optimization Deployment${NC}"
    echo "This script will deploy:"
    echo "  - Google Cloud Project with billing linked"
    echo "  - BigQuery dataset and tables for cost analytics"
    echo "  - Cloud Storage bucket for reports and data"
    echo "  - Pub/Sub topics and subscriptions for event processing"
    echo "  - Cloud Functions for cost analysis and optimization"
    echo "  - Cloud Scheduler jobs for automated analysis"
    echo "  - Cloud Monitoring dashboard and alerting"
    echo ""
    echo "Estimated deployment time: 10-15 minutes"
    echo "Estimated monthly cost: $50-100 for moderate usage"
    echo ""
    
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Generate unique identifiers
generate_identifiers() {
    log "Generating unique identifiers..."
    
    TIMESTAMP=$(date +%s)
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    export PROJECT_ID="${PROJECT_PREFIX}-${TIMESTAMP}"
    export DATASET_NAME="cost_optimization_${RANDOM_SUFFIX}"
    export BUCKET_NAME="cost-optimization-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export TOPIC_NAME="cost-optimization-topic-${RANDOM_SUFFIX}"
    
    # Store identifiers for cleanup script
    cat > "${SCRIPT_DIR}/.deployment_config" << EOF
PROJECT_ID=${PROJECT_ID}
DATASET_NAME=${DATASET_NAME}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_NAME=${TOPIC_NAME}
REGION=${REGION}
ZONE=${ZONE}
EOF
    
    log "Generated project ID: ${PROJECT_ID}"
    log "Generated dataset name: ${DATASET_NAME}"
    log "Generated bucket name: ${BUCKET_NAME}"
}

# Get billing account
get_billing_account() {
    log "Getting available billing accounts..."
    
    BILLING_ACCOUNTS=$(gcloud billing accounts list --format="value(name)" --filter="open=true")
    
    if [[ -z "$BILLING_ACCOUNTS" ]]; then
        error "No active billing accounts found. Please ensure you have a billing account set up."
        exit 1
    fi
    
    # Use the first available billing account
    export BILLING_ACCOUNT_ID=$(echo "$BILLING_ACCOUNTS" | head -n 1)
    
    if [[ -z "$BILLING_ACCOUNT_ID" ]]; then
        error "Failed to get billing account ID"
        exit 1
    fi
    
    log "Using billing account: ${BILLING_ACCOUNT_ID}"
    echo "BILLING_ACCOUNT_ID=${BILLING_ACCOUNT_ID}" >> "${SCRIPT_DIR}/.deployment_config"
}

# Create and configure project
setup_project() {
    log "Creating and configuring Google Cloud project..."
    
    # Create project
    if ! gcloud projects create "${PROJECT_ID}" --name="Cost Optimization System" 2>/dev/null; then
        warn "Project ${PROJECT_ID} may already exist, continuing..."
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account
    gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"
    
    # Enable required APIs with progress indication
    log "Enabling required Google Cloud APIs..."
    local apis=(
        "cloudbilling.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "recommender.googleapis.com"
        "cloudscheduler.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "Project setup completed successfully"
}

# Create BigQuery dataset and tables
setup_bigquery() {
    log "Setting up BigQuery dataset and tables..."
    
    # Create dataset
    bq mk --dataset \
        --location="${REGION}" \
        --description="Cost optimization analytics dataset" \
        "${PROJECT_ID}:${DATASET_NAME}"
    
    # Create cost analysis table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.cost_analysis" \
        project_id:STRING,billing_account_id:STRING,service:STRING,cost:FLOAT,currency:STRING,usage_date:DATE,optimization_potential:FLOAT
    
    # Create recommendations table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.recommendations" \
        project_id:STRING,recommender_type:STRING,recommendation_id:STRING,description:STRING,potential_savings:FLOAT,priority:STRING,created_date:TIMESTAMP
    
    log "BigQuery setup completed successfully"
}

# Create Cloud Storage bucket
setup_storage() {
    log "Setting up Cloud Storage bucket..."
    
    # Create bucket with standard storage class
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"
    
    # Enable versioning for data protection
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Create folder structure
    gsutil -m cp /dev/null "gs://${BUCKET_NAME}/reports/.gitkeep"
    gsutil -m cp /dev/null "gs://${BUCKET_NAME}/recommendations/.gitkeep"
    gsutil -m cp /dev/null "gs://${BUCKET_NAME}/exports/.gitkeep"
    
    log "Cloud Storage setup completed successfully"
}

# Create Pub/Sub topics and subscriptions
setup_pubsub() {
    log "Setting up Pub/Sub topics and subscriptions..."
    
    # Create main topic
    gcloud pubsub topics create "${TOPIC_NAME}"
    
    # Create additional topics
    gcloud pubsub topics create cost-analysis-results
    gcloud pubsub topics create recommendations-generated
    gcloud pubsub topics create optimization-alerts
    
    # Create subscriptions
    gcloud pubsub subscriptions create cost-analysis-sub --topic="${TOPIC_NAME}"
    gcloud pubsub subscriptions create recommendations-sub --topic=recommendations-generated
    gcloud pubsub subscriptions create alerts-sub --topic=optimization-alerts
    
    log "Pub/Sub setup completed successfully"
}

# Deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    # Create temporary directories for each function
    local temp_dir=$(mktemp -d)
    
    # Deploy cost analysis function
    log "Deploying cost analysis function..."
    local cost_analysis_dir="${temp_dir}/cost-analysis"
    mkdir -p "${cost_analysis_dir}"
    
    # Copy function code
    cp "${FUNCTIONS_DIR}/cost_analysis.py" "${cost_analysis_dir}/main.py"
    cp "${FUNCTIONS_DIR}/requirements.txt" "${cost_analysis_dir}/"
    
    # Deploy function
    gcloud functions deploy analyze-costs \
        --runtime python39 \
        --trigger-topic "${TOPIC_NAME}" \
        --source "${cost_analysis_dir}" \
        --entry-point analyze_costs \
        --memory 256MB \
        --timeout 300s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME},PROJECT_ID=${PROJECT_ID}" \
        --quiet
    
    # Deploy recommendation engine function
    log "Deploying recommendation engine function..."
    local rec_engine_dir="${temp_dir}/recommendation-engine"
    mkdir -p "${rec_engine_dir}"
    
    cp "${FUNCTIONS_DIR}/recommendation_engine.py" "${rec_engine_dir}/main.py"
    cp "${FUNCTIONS_DIR}/requirements.txt" "${rec_engine_dir}/"
    
    gcloud functions deploy generate-recommendations \
        --runtime python39 \
        --trigger-topic recommendations-generated \
        --source "${rec_engine_dir}" \
        --entry-point generate_recommendations \
        --memory 512MB \
        --timeout 540s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME},PROJECT_ID=${PROJECT_ID},BUCKET_NAME=${BUCKET_NAME}" \
        --quiet
    
    # Deploy optimization automation function
    log "Deploying optimization automation function..."
    local opt_auto_dir="${temp_dir}/optimization-automation"
    mkdir -p "${opt_auto_dir}"
    
    cp "${FUNCTIONS_DIR}/optimization_automation.py" "${opt_auto_dir}/main.py"
    cp "${FUNCTIONS_DIR}/requirements.txt" "${opt_auto_dir}/"
    
    gcloud functions deploy optimize-resources \
        --runtime python39 \
        --trigger-topic recommendations-generated \
        --source "${opt_auto_dir}" \
        --entry-point optimize_resources \
        --memory 256MB \
        --timeout 300s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID}" \
        --quiet
    
    # Clean up temporary directories
    rm -rf "${temp_dir}"
    
    log "Cloud Functions deployment completed successfully"
}

# Create scheduled jobs
setup_scheduler() {
    log "Setting up Cloud Scheduler jobs..."
    
    # Create daily cost analysis job
    gcloud scheduler jobs create pubsub daily-cost-analysis \
        --schedule="0 9 * * *" \
        --time-zone="America/New_York" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"trigger":"scheduled_analysis","type":"daily"}' \
        --description="Daily cost analysis across all projects"
    
    # Create weekly comprehensive analysis
    gcloud scheduler jobs create pubsub weekly-cost-report \
        --schedule="0 8 * * 1" \
        --time-zone="America/New_York" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"trigger":"weekly_report","type":"comprehensive"}' \
        --description="Weekly comprehensive cost optimization report"
    
    # Create monthly optimization review
    gcloud scheduler jobs create pubsub monthly-optimization-review \
        --schedule="0 7 1 * *" \
        --time-zone="America/New_York" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"trigger":"monthly_review","type":"optimization"}' \
        --description="Monthly optimization opportunities review"
    
    log "Cloud Scheduler setup completed successfully"
}

# Set up monitoring and alerting
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create monitoring dashboard configuration
    local dashboard_config="${SCRIPT_DIR}/.dashboard_config.json"
    cat > "${dashboard_config}" << 'EOF'
{
  "displayName": "Cost Optimization Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Function Executions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Optimization Savings",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"global\"",
                "aggregation": {
                  "alignmentPeriod": "3600s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            }
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the dashboard
    gcloud monitoring dashboards create --config-from-file="${dashboard_config}"
    
    # Clean up temporary dashboard config
    rm -f "${dashboard_config}"
    
    log "Monitoring setup completed successfully"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test Pub/Sub message publishing
    log "Testing Pub/Sub message flow..."
    gcloud pubsub topics publish "${TOPIC_NAME}" --message='{"test": true, "trigger": "deployment_test"}'
    
    # Check BigQuery dataset
    log "Verifying BigQuery dataset..."
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "BigQuery dataset verification successful"
    else
        warn "BigQuery dataset verification failed"
    fi
    
    # Check Cloud Storage bucket
    log "Verifying Cloud Storage bucket..."
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Cloud Storage bucket verification successful"
    else
        warn "Cloud Storage bucket verification failed"
    fi
    
    # Check Cloud Functions
    log "Verifying Cloud Functions..."
    local functions_count=$(gcloud functions list --filter="name:analyze-costs OR name:generate-recommendations OR name:optimize-resources" --format="value(name)" | wc -l)
    if [[ $functions_count -eq 3 ]]; then
        log "Cloud Functions verification successful"
    else
        warn "Expected 3 Cloud Functions, found ${functions_count}"
    fi
    
    # Check scheduled jobs
    log "Verifying scheduled jobs..."
    local jobs_count=$(gcloud scheduler jobs list --filter="name:daily-cost-analysis OR name:weekly-cost-report OR name:monthly-optimization-review" --format="value(name)" | wc -l)
    if [[ $jobs_count -eq 3 ]]; then
        log "Scheduled jobs verification successful"
    else
        warn "Expected 3 scheduled jobs, found ${jobs_count}"
    fi
    
    log "Deployment testing completed"
}

# Display deployment summary
show_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   DEPLOYMENT COMPLETED SUCCESSFULLY   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Project Details:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Dataset: ${DATASET_NAME}"
    echo "  Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "Deployed Resources:"
    echo "  ✅ BigQuery dataset and tables"
    echo "  ✅ Cloud Storage bucket with versioning"
    echo "  ✅ Pub/Sub topics and subscriptions"
    echo "  ✅ 3 Cloud Functions for cost optimization"
    echo "  ✅ 3 Cloud Scheduler jobs for automation"
    echo "  ✅ Cloud Monitoring dashboard"
    echo ""
    echo "Next Steps:"
    echo "  1. Access the monitoring dashboard in Google Cloud Console"
    echo "  2. Review scheduled jobs in Cloud Scheduler"
    echo "  3. Check function logs in Cloud Logging"
    echo "  4. Monitor cost analysis results in BigQuery"
    echo ""
    echo "To clean up resources, run:"
    echo "  ./destroy.sh"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/.deployment_config"
    echo ""
}

# Main deployment flow
main() {
    log "Starting Multi-Cloud Cost Optimization deployment..."
    
    check_prerequisites
    confirm_deployment
    generate_identifiers
    get_billing_account
    setup_project
    setup_bigquery
    setup_storage
    setup_pubsub
    deploy_functions
    setup_scheduler
    setup_monitoring
    test_deployment
    show_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. You may need to clean up resources manually."; exit 1' INT TERM

# Run main function
main "$@"
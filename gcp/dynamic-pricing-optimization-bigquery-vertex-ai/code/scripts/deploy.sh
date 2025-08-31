#!/bin/bash

# Dynamic Pricing Optimization Deployment Script
# This script deploys the complete dynamic pricing optimization solution
# using BigQuery, Vertex AI, Cloud Functions, and Cloud Scheduler

set -euo pipefail

# Color codes for output
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
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: Full cleanup script should be run manually if needed
    exit 1
}

trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="pricing-opt"
REQUIRED_APIS=(
    "bigquery.googleapis.com"
    "aiplatform.googleapis.com"
    "cloudfunctions.googleapis.com"
    "cloudscheduler.googleapis.com"
    "storage.googleapis.com"
    "monitoring.googleapis.com"
    "artifactregistry.googleapis.com"
)

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY-RUN mode. No actual resources will be created."
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        log_info "[DRY-RUN] Purpose: $description"
    else
        log_info "Executing: $description"
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil not found. Please install Google Cloud SDK with gsutil."
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI not found. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if jq is available (for JSON processing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Some advanced features may not work properly."
        log_info "Install jq with: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not already set
    export PROJECT_ID="${PROJECT_ID:-${PROJECT_PREFIX}-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export DATASET_NAME="${DATASET_NAME:-pricing_optimization}"
    export MODEL_NAME="${MODEL_NAME:-pricing_model}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-pricing-data-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-pricing-optimizer-${RANDOM_SUFFIX}}"
    
    log_info "Environment variables configured:"
    log_info "  PROJECT_ID: $PROJECT_ID"
    log_info "  REGION: $REGION"
    log_info "  ZONE: $ZONE"
    log_info "  BUCKET_NAME: $BUCKET_NAME"
    log_info "  FUNCTION_NAME: $FUNCTION_NAME"
}

# Function to create and configure GCP project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Create project if it doesn't exist
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        execute_cmd "gcloud projects create ${PROJECT_ID} --name='Dynamic Pricing Optimization'" \
                   "Creating new GCP project"
    else
        log_info "Project $PROJECT_ID already exists"
    fi
    
    # Set current project
    execute_cmd "gcloud config set project ${PROJECT_ID}" \
               "Setting current project"
    execute_cmd "gcloud config set compute/region ${REGION}" \
               "Setting default region"
    execute_cmd "gcloud config set compute/zone ${ZONE}" \
               "Setting default zone"
    
    # Check if billing is enabled (cannot be set via CLI, so just check)
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! gcloud beta billing projects describe "$PROJECT_ID" &>/dev/null; then
            log_warning "Billing may not be enabled for project $PROJECT_ID"
            log_warning "Please enable billing in the Google Cloud Console before proceeding"
            read -p "Press Enter to continue or Ctrl+C to abort..."
        fi
    fi
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis_to_enable=()
    
    for api in "${REQUIRED_APIS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            apis_to_enable+=("$api")
        else
            if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
                apis_to_enable+=("$api")
            else
                log_info "API $api already enabled"
            fi
        fi
    done
    
    if [[ ${#apis_to_enable[@]} -gt 0 ]]; then
        local api_list=$(IFS=' '; echo "${apis_to_enable[*]}")
        execute_cmd "gcloud services enable $api_list" \
                   "Enabling APIs: $api_list"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log_info "Waiting for APIs to be fully enabled..."
            sleep 30
        fi
    fi
    
    log_success "API enablement completed"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Bucket gs://${BUCKET_NAME} already exists"
            return
        fi
    fi
    
    execute_cmd "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}" \
               "Creating Cloud Storage bucket"
    
    log_success "Cloud Storage bucket created: gs://${BUCKET_NAME}"
}

# Function to create BigQuery dataset and tables
setup_bigquery() {
    log_info "Setting up BigQuery dataset and tables..."
    
    # Create dataset
    execute_cmd "bq mk --dataset --description 'Dataset for dynamic pricing optimization' --location=${REGION} ${PROJECT_ID}:${DATASET_NAME}" \
               "Creating BigQuery dataset"
    
    # Create sales history table
    execute_cmd "bq mk --table ${PROJECT_ID}:${DATASET_NAME}.sales_history product_id:STRING,sale_date:DATE,price:FLOAT,quantity:INTEGER,revenue:FLOAT,competitor_price:FLOAT,inventory_level:INTEGER,season:STRING,promotion:BOOLEAN" \
               "Creating sales history table"
    
    # Create competitor pricing table
    execute_cmd "bq mk --table ${PROJECT_ID}:${DATASET_NAME}.competitor_pricing product_id:STRING,competitor:STRING,price:FLOAT,timestamp:TIMESTAMP,availability:BOOLEAN" \
               "Creating competitor pricing table"
    
    log_success "BigQuery setup completed"
}

# Function to load sample data
load_sample_data() {
    log_info "Loading sample training data..."
    
    # Create temporary data file
    local data_file="/tmp/sample_sales_data.csv"
    cat > "$data_file" << 'EOF'
product_id,sale_date,price,quantity,revenue,competitor_price,inventory_level,season,promotion
PROD001,2024-01-15,29.99,150,4498.50,31.99,1200,winter,false
PROD001,2024-02-15,27.99,180,5038.20,30.99,800,winter,true
PROD001,2024-03-15,32.99,120,3958.80,34.99,1500,spring,false
PROD002,2024-01-15,15.99,200,3198.00,16.99,500,winter,false
PROD002,2024-02-15,14.99,250,3747.50,15.99,300,winter,true
PROD002,2024-03-15,17.99,180,3238.20,18.99,600,spring,false
PROD003,2024-01-15,45.99,80,3679.20,47.99,200,winter,false
PROD003,2024-02-15,42.99,100,4299.00,45.99,150,winter,true
PROD003,2024-03-15,48.99,90,4409.10,49.99,250,spring,false
EOF
    
    execute_cmd "bq load --source_format=CSV --skip_leading_rows=1 --autodetect ${PROJECT_ID}:${DATASET_NAME}.sales_history $data_file" \
               "Loading sample data into BigQuery"
    
    # Clean up temp file
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f "$data_file"
    fi
    
    log_success "Sample data loaded"
}

# Function to create BigQuery ML model
create_bqml_model() {
    log_info "Creating BigQuery ML pricing model..."
    
    local model_query="CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_NAME}.pricing_prediction_model\`
OPTIONS(
  model_type='LINEAR_REG',
  input_label_cols=['revenue'],
  data_split_method='AUTO_SPLIT',
  data_split_eval_fraction=0.2
) AS
SELECT
  price,
  competitor_price,
  inventory_level,
  CASE 
    WHEN season = 'winter' THEN 1
    WHEN season = 'spring' THEN 2
    WHEN season = 'summer' THEN 3
    ELSE 4
  END as season_numeric,
  CASE WHEN promotion THEN 1 ELSE 0 END as promotion_flag,
  revenue
FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_history\`"
    
    execute_cmd "bq query --use_legacy_sql=false '$model_query'" \
               "Creating and training BigQuery ML model"
    
    log_success "BigQuery ML model created"
}

# Function to prepare Vertex AI training
setup_vertex_ai() {
    log_info "Setting up Vertex AI training job..."
    
    # Create training directory
    local training_dir="/tmp/vertex_ai_training"
    mkdir -p "$training_dir"
    
    # Create trainer script
    cat > "$training_dir/trainer.py" << 'EOF'
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, r2_score
import joblib
import argparse
from google.cloud import bigquery
import os

def train_pricing_model():
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Query training data
    query = f"""
    SELECT 
        price,
        competitor_price,
        inventory_level,
        CASE 
            WHEN season = 'winter' THEN 1
            WHEN season = 'spring' THEN 2
            WHEN season = 'summer' THEN 3
            ELSE 4
        END as season_numeric,
        CASE WHEN promotion THEN 1 ELSE 0 END as promotion_flag,
        revenue
    FROM `{os.environ.get('PROJECT_ID', 'default-project')}.pricing_optimization.sales_history`
    """
    
    df = client.query(query).to_dataframe()
    
    # Prepare features and target
    X = df[['price', 'competitor_price', 'inventory_level', 'season_numeric', 'promotion_flag']]
    y = df['revenue']
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Train Random Forest model
    model = RandomForestRegressor(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    
    # Evaluate model
    y_pred = model.predict(X_test)
    mse = mean_squared_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)
    
    print(f"Model Performance: MSE={mse:.2f}, R2={r2:.3f}")
    
    # Save model
    model_path = os.environ.get('AIP_MODEL_DIR', './model')
    os.makedirs(model_path, exist_ok=True)
    joblib.dump(model, f"{model_path}/pricing_model.joblib")
    
    print(f"Model saved to {model_path}")

if __name__ == "__main__":
    train_pricing_model()
EOF
    
    # Create requirements file
    cat > "$training_dir/requirements.txt" << 'EOF'
google-cloud-bigquery
pandas
scikit-learn
joblib
numpy
EOF
    
    # Upload training code to Cloud Storage
    execute_cmd "gsutil -m cp -r $training_dir gs://${BUCKET_NAME}/" \
               "Uploading Vertex AI training code"
    
    # Submit training job
    execute_cmd "gcloud ai custom-jobs create --region=${REGION} --display-name='pricing-optimization-training-$(date +%s)' --worker-pool-spec=machine-type=n1-standard-4,replica-count=1,executor-image-uri=us-docker.pkg.dev/vertex-ai/training/scikit-learn-cpu.1-0:latest,local-package-path=$training_dir,script=trainer.py --env-vars=PROJECT_ID=${PROJECT_ID}" \
               "Submitting Vertex AI training job"
    
    # Clean up temp directory
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$training_dir"
    fi
    
    log_success "Vertex AI training job submitted"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for pricing optimization..."
    
    # Create function directory
    local function_dir="/tmp/pricing_function"
    mkdir -p "$function_dir"
    
    # Create main.py
    cat > "$function_dir/main.py" << 'EOF'
import functions_framework
from google.cloud import bigquery
import json
import pandas as pd
import os

# Initialize clients
bq_client = bigquery.Client()

@functions_framework.http
def optimize_pricing(request):
    """HTTP Cloud Function for pricing optimization."""
    try:
        request_json = request.get_json()
        product_id = request_json.get('product_id')
        
        if not product_id:
            return {'error': 'product_id is required'}, 400
        
        project_id = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
        
        # Get current product data
        query = f"""
        SELECT 
            price,
            competitor_price,
            inventory_level,
            season,
            promotion
        FROM `{project_id}.pricing_optimization.sales_history`
        WHERE product_id = '{product_id}'
        ORDER BY sale_date DESC
        LIMIT 1
        """
        
        result = bq_client.query(query).to_dataframe()
        
        if result.empty:
            return {'error': 'Product not found'}, 404
        
        current_data = result.iloc[0]
        
        # Generate pricing recommendations using BigQuery ML
        ml_query = f"""
        SELECT 
            predicted_revenue
        FROM ML.PREDICT(MODEL `{project_id}.pricing_optimization.pricing_prediction_model`,
            (SELECT 
                {current_data['price']} as price,
                {current_data['competitor_price']} as competitor_price,
                {current_data['inventory_level']} as inventory_level,
                CASE 
                    WHEN '{current_data['season']}' = 'winter' THEN 1
                    WHEN '{current_data['season']}' = 'spring' THEN 2
                    WHEN '{current_data['season']}' = 'summer' THEN 3
                    ELSE 4
                END as season_numeric,
                CASE WHEN {current_data['promotion']} THEN 1 ELSE 0 END as promotion_flag
            )
        )
        """
        
        ml_result = bq_client.query(ml_query).to_dataframe()
        
        # Calculate optimal price range
        base_price = current_data['price']
        competitor_price = current_data['competitor_price']
        
        # Business rules for pricing constraints
        min_price = base_price * 0.8  # No more than 20% below current
        max_price = min(base_price * 1.3, competitor_price * 0.95)  # Max 30% increase or 5% below competitor
        
        # Simple optimization logic for demonstration
        if current_data['inventory_level'] > 1000:
            recommended_price = min(max_price, base_price * 1.05)  # Small increase if high inventory
        else:
            recommended_price = max(min_price, base_price * 0.95)  # Small decrease if low inventory
        
        response = {
            'product_id': product_id,
            'current_price': float(current_data['price']),
            'recommended_price': float(recommended_price),
            'competitor_price': float(current_data['competitor_price']),
            'predicted_revenue': float(ml_result.iloc[0]['predicted_revenue']),
            'price_change_percent': ((recommended_price - base_price) / base_price) * 100,
            'inventory_level': int(current_data['inventory_level']),
            'timestamp': pd.Timestamp.now().isoformat()
        }
        
        return response
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-bigquery
pandas
EOF
    
    # Deploy function
    execute_cmd "gcloud functions deploy ${FUNCTION_NAME} --runtime=python311 --region=${REGION} --source=$function_dir --entry-point=optimize_pricing --trigger=http --memory=512Mi --timeout=60s --allow-unauthenticated --set-env-vars=GCP_PROJECT=${PROJECT_ID}" \
               "Deploying Cloud Function"
    
    # Clean up temp directory
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$function_dir"
    fi
    
    log_success "Cloud Function deployed"
}

# Function to set up Cloud Scheduler
setup_scheduler() {
    log_info "Setting up Cloud Scheduler for automated pricing updates..."
    
    # Get Cloud Function URL
    if [[ "$DRY_RUN" != "true" ]]; then
        FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(httpsTrigger.url)")
    else
        FUNCTION_URL="https://example-function-url.cloudfunctions.net/pricing-optimizer"
    fi
    
    # Create scheduler jobs for different products
    local products=("PROD001" "PROD002" "PROD003")
    
    for product in "${products[@]}"; do
        local job_name="pricing-optimization-${product,,}"
        execute_cmd "gcloud scheduler jobs create http ${job_name} --location=${REGION} --schedule='0 */6 * * *' --uri=${FUNCTION_URL} --http-method=POST --message-body='{\"product_id\": \"${product}\"}' --headers='Content-Type=application/json'" \
                   "Creating scheduler job for product ${product}"
    done
    
    log_success "Cloud Scheduler jobs created"
}

# Function to configure monitoring
setup_monitoring() {
    log_info "Setting up monitoring dashboard..."
    
    # Create dashboard configuration
    local dashboard_config="/tmp/pricing_dashboard.json"
    cat > "$dashboard_config" << 'EOF'
{
  "displayName": "Dynamic Pricing Optimization Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Function Executions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "unitOverride": "1",
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
      }
    ]
  }
}
EOF
    
    execute_cmd "gcloud monitoring dashboards create --config-from-file=$dashboard_config" \
               "Creating monitoring dashboard"
    
    # Clean up temp file
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f "$dashboard_config"
    fi
    
    log_success "Monitoring dashboard configured"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping validation in dry-run mode"
        return
    fi
    
    # Check BigQuery dataset
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_success "BigQuery dataset validated"
    else
        log_error "BigQuery dataset not found"
        return 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_success "Cloud Function validated"
    else
        log_error "Cloud Function not found"
        return 1
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Cloud Storage bucket validated"
    else
        log_error "Cloud Storage bucket not found"
        return 1
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
show_deployment_summary() {
    log_info "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "BigQuery Dataset: ${PROJECT_ID}:${DATASET_NAME}"
    echo "Cloud Storage Bucket: gs://${BUCKET_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the Vertex AI training job completion"
    echo "2. Test the pricing optimization function"
    echo "3. Review the monitoring dashboard"
    echo "4. Customize business rules in the Cloud Function"
    echo ""
    echo "Estimated monthly cost: \$20-35 (depending on usage)"
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "Function URL:"
        gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(httpsTrigger.url)" 2>/dev/null || echo "Function URL not available yet"
    fi
}

# Main deployment function
main() {
    log_info "Starting Dynamic Pricing Optimization deployment..."
    log_info "=================================================="
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    setup_bigquery
    load_sample_data
    create_bqml_model
    setup_vertex_ai
    deploy_cloud_function
    setup_scheduler
    setup_monitoring
    validate_deployment
    
    log_success "Deployment completed successfully!"
    show_deployment_summary
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run          Run in dry-run mode (no resources created)"
            echo "  --project-id ID    Specify GCP project ID"
            echo "  --region REGION    Specify GCP region (default: us-central1)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
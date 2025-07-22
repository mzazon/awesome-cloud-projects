#!/bin/bash

# Intelligent Retail Inventory Optimization Deployment Script
# This script deploys the complete Google Cloud Platform infrastructure for
# intelligent retail inventory optimization using Fleet Engine and Cloud Optimization AI

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration values
DEFAULT_PROJECT_PREFIX="retail-inventory"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Trap for cleanup on script exit
trap cleanup EXIT

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed! Check ${LOG_FILE} for details."
        log_info "To cleanup partial deployment, run: ./destroy.sh"
    fi
    return $exit_code
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

log_step() {
    echo -e "\n${BLUE}=== $* ===${NC}" | tee -a "${LOG_FILE}"
}

# Save deployment state
save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "${STATE_FILE}"
}

# Load deployment state
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        source "${STATE_FILE}"
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating Prerequisites"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Check required APIs are available
    local required_apis=(
        "bigquery.googleapis.com"
        "aiplatform.googleapis.com"
        "optimization.googleapis.com"
        "fleetengine.googleapis.com"
        "run.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    log_info "Required APIs: ${required_apis[*]}"
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available"
        exit 1
    fi
    
    # Check minimum gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "0.0.0")
    log_info "Google Cloud SDK version: ${gcloud_version}"
    
    log_success "Prerequisites validation completed"
}

# Parse command line arguments
parse_arguments() {
    local project_prefix="${DEFAULT_PROJECT_PREFIX}"
    local region="${DEFAULT_REGION}"
    local zone="${DEFAULT_ZONE}"
    local dry_run=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-prefix)
                project_prefix="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --zone)
                zone="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Export configuration
    export PROJECT_PREFIX="${project_prefix}"
    export REGION="${region}"
    export ZONE="${zone}"
    export DRY_RUN="${dry_run}"
    export FORCE="${force}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy intelligent retail inventory optimization infrastructure on Google Cloud Platform.

Options:
    --project-prefix PREFIX    Project name prefix (default: ${DEFAULT_PROJECT_PREFIX})
    --region REGION           GCP region (default: ${DEFAULT_REGION})
    --zone ZONE              GCP zone (default: ${DEFAULT_ZONE})
    --dry-run                Show what would be deployed without making changes
    --force                  Force deployment even if resources exist
    --help, -h               Show this help message

Examples:
    $0                                          # Deploy with defaults
    $0 --project-prefix my-retail --region us-west1
    $0 --dry-run                               # Preview deployment
    $0 --force                                 # Force redeployment

Estimated cost: \$200-400 for complete setup and testing
EOF
}

# Set up environment variables
setup_environment() {
    log_step "Setting Up Environment Variables"
    
    # Generate unique suffix for resources
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3)
    
    # Core project configuration
    export PROJECT_ID="${PROJECT_PREFIX}-${timestamp}"
    export DATASET_NAME="retail_analytics_${random_suffix}"
    export BUCKET_NAME="retail-inventory-${PROJECT_ID}-${random_suffix}"
    export SERVICE_ACCOUNT="inventory-optimizer-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Service names
    export ANALYTICS_SERVICE_NAME="analytics-service"
    export OPTIMIZER_SERVICE_NAME="optimizer-service"
    
    # Save configuration to state file
    save_state "PROJECT_ID" "${PROJECT_ID}"
    save_state "REGION" "${REGION}"
    save_state "ZONE" "${ZONE}"
    save_state "DATASET_NAME" "${DATASET_NAME}"
    save_state "BUCKET_NAME" "${BUCKET_NAME}"
    save_state "SERVICE_ACCOUNT" "${SERVICE_ACCOUNT}"
    save_state "ANALYTICS_SERVICE_NAME" "${ANALYTICS_SERVICE_NAME}"
    save_state "OPTIMIZER_SERVICE_NAME" "${OPTIMIZER_SERVICE_NAME}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Dataset: ${DATASET_NAME}"
    log_info "Bucket: ${BUCKET_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    log_success "Environment variables configured"
}

# Create and configure GCP project
setup_project() {
    log_step "Setting Up Google Cloud Project"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create project: ${PROJECT_ID}"
        return 0
    fi
    
    # Create project
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Retail Inventory Optimization" \
            --labels="environment=demo,purpose=retail-optimization"
    else
        log_warning "Project ${PROJECT_ID} already exists"
        if [[ "${FORCE}" != "true" ]]; then
            log_error "Use --force to continue with existing project"
            exit 1
        fi
    fi
    
    # Set as default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account (if available)
    local billing_account
    billing_account=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1 2>/dev/null || echo "")
    
    if [[ -n "${billing_account}" ]]; then
        log_info "Linking billing account: ${billing_account}"
        gcloud billing projects link "${PROJECT_ID}" \
            --billing-account="${billing_account}" || log_warning "Failed to link billing account"
    else
        log_warning "No billing account found - you may need to link billing manually"
    fi
    
    log_success "Project setup completed"
}

# Enable required Google Cloud APIs
enable_apis() {
    log_step "Enabling Required APIs"
    
    local required_apis=(
        "bigquery.googleapis.com"
        "aiplatform.googleapis.com"
        "optimization.googleapis.com"
        "fleetengine.googleapis.com"
        "run.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would enable APIs: ${required_apis[*]}"
        return 0
    fi
    
    log_info "Enabling APIs (this may take a few minutes)..."
    
    # Enable APIs in parallel for faster deployment
    for api in "${required_apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" &
    done
    
    # Wait for all API enablement jobs to complete
    wait
    
    # Verify APIs are enabled
    log_info "Verifying API enablement..."
    local failed_apis=()
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
            failed_apis+=("${api}")
        fi
    done
    
    if [[ ${#failed_apis[@]} -gt 0 ]]; then
        log_error "Failed to enable APIs: ${failed_apis[*]}"
        exit 1
    fi
    
    log_success "All required APIs enabled"
}

# Create service account with proper permissions
setup_service_account() {
    log_step "Setting Up Service Account"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create service account: inventory-optimizer"
        return 0
    fi
    
    # Create service account
    if ! gcloud iam service-accounts describe "inventory-optimizer@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_info "Creating service account..."
        gcloud iam service-accounts create inventory-optimizer \
            --display-name="Inventory Optimization Service Account" \
            --description="Service account for retail inventory optimization system"
    else
        log_warning "Service account already exists"
    fi
    
    # Define required roles
    local required_roles=(
        "roles/bigquery.admin"
        "roles/aiplatform.user"
        "roles/optimization.admin"
        "roles/fleetengine.admin"
        "roles/storage.admin"
        "roles/run.admin"
        "roles/monitoring.editor"
        "roles/cloudbuild.builds.editor"
    )
    
    # Grant permissions
    log_info "Granting IAM permissions..."
    for role in "${required_roles[@]}"; do
        log_info "Granting ${role}..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT}" \
            --role="${role}" \
            --condition=None \
            --quiet || log_warning "Failed to grant ${role}"
    done
    
    log_success "Service account configured with permissions"
}

# Create BigQuery dataset and tables
setup_bigquery() {
    log_step "Setting Up BigQuery Dataset and Tables"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create BigQuery dataset: ${DATASET_NAME}"
        return 0
    fi
    
    # Create dataset
    if ! bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_info "Creating BigQuery dataset..."
        bq mk --dataset \
            --description="Retail inventory optimization analytics" \
            --location="${REGION}" \
            "${PROJECT_ID}:${DATASET_NAME}"
    else
        log_warning "BigQuery dataset already exists"
    fi
    
    # Create tables
    local tables=(
        "inventory_levels:store_id:STRING,product_id:STRING,current_stock:INTEGER,max_capacity:INTEGER,min_threshold:INTEGER,last_updated:TIMESTAMP"
        "sales_history:transaction_id:STRING,store_id:STRING,product_id:STRING,quantity:INTEGER,price:FLOAT,timestamp:TIMESTAMP,customer_demographics:STRING"
        "store_locations:store_id:STRING,store_name:STRING,latitude:FLOAT,longitude:FLOAT,region:STRING,store_type:STRING,capacity_tier:STRING"
    )
    
    for table_def in "${tables[@]}"; do
        local table_name="${table_def%%:*}"
        local schema="${table_def#*:}"
        
        if ! bq ls "${PROJECT_ID}:${DATASET_NAME}.${table_name}" &>/dev/null; then
            log_info "Creating table: ${table_name}"
            bq mk --table "${PROJECT_ID}:${DATASET_NAME}.${table_name}" "${schema}"
        else
            log_warning "Table ${table_name} already exists"
        fi
    done
    
    # Load sample training data
    log_info "Creating sample training data..."
    cat > /tmp/demand_training_data.csv << 'EOF'
store_id,product_id,date,sales_quantity,weather_condition,promotion_active,competitor_price,season
store_001,prod_123,2024-01-01,45,sunny,false,19.99,winter
store_001,prod_123,2024-01-02,52,cloudy,true,18.99,winter
store_002,prod_123,2024-01-01,38,rainy,false,20.50,winter
store_002,prod_123,2024-01-02,41,sunny,true,19.25,winter
store_003,prod_123,2024-01-03,47,sunny,false,20.00,winter
store_003,prod_123,2024-01-04,55,cloudy,true,19.50,winter
EOF
    
    # Load training data
    bq load --source_format=CSV \
        --skip_leading_rows=1 \
        --replace \
        "${DATASET_NAME}.demand_training_data" \
        /tmp/demand_training_data.csv \
        "store_id:STRING,product_id:STRING,date:DATE,sales_quantity:INTEGER,weather_condition:STRING,promotion_active:BOOLEAN,competitor_price:FLOAT,season:STRING"
    
    # Clean up temporary file
    rm -f /tmp/demand_training_data.csv
    
    log_success "BigQuery dataset and tables created"
}

# Create and configure Cloud Storage bucket
setup_storage() {
    log_step "Setting Up Cloud Storage"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create bucket
    if ! gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Creating Cloud Storage bucket..."
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Create directory structure
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw-data/.keep"
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/processed-data/.keep"
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/ml-models/.keep"
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/optimization-results/.keep"
        
        # Set up lifecycle management
        cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
        
        gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"
        rm -f /tmp/lifecycle.json
        
    else
        log_warning "Storage bucket already exists"
    fi
    
    log_success "Cloud Storage bucket configured"
}

# Create and train demand forecasting model
setup_ml_model() {
    log_step "Setting Up Machine Learning Model"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create ML model: demand_forecast_model"
        return 0
    fi
    
    # Create BigQuery ML forecasting model
    log_info "Creating demand forecasting model (this may take several minutes)..."
    
    bq query --use_legacy_sql=false --max_rows=0 << EOF
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_NAME}.demand_forecast_model\`
OPTIONS(
  model_type='ARIMA_PLUS',
  time_series_timestamp_col='date',
  time_series_data_col='sales_quantity',
  time_series_id_col=['store_id', 'product_id'],
  horizon=30,
  auto_arima=TRUE
) AS
SELECT
  store_id,
  product_id,
  date,
  sales_quantity
FROM \`${PROJECT_ID}.${DATASET_NAME}.demand_training_data\`
EOF
    
    log_success "Machine learning model created and training initiated"
}

# Build and deploy Cloud Run services
deploy_cloud_run_services() {
    log_step "Building and Deploying Cloud Run Services"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would deploy Cloud Run services: ${ANALYTICS_SERVICE_NAME}, ${OPTIMIZER_SERVICE_NAME}"
        return 0
    fi
    
    local temp_dir="/tmp/retail-inventory-services"
    mkdir -p "${temp_dir}"
    
    # Create analytics service
    create_analytics_service "${temp_dir}"
    
    # Create optimizer service  
    create_optimizer_service "${temp_dir}"
    
    # Build and deploy analytics service
    log_info "Building analytics service..."
    gcloud builds submit "${temp_dir}/analytics-service/" \
        --tag "gcr.io/${PROJECT_ID}/${ANALYTICS_SERVICE_NAME}:latest" \
        --timeout=600s
    
    log_info "Deploying analytics service..."
    gcloud run deploy "${ANALYTICS_SERVICE_NAME}" \
        --image "gcr.io/${PROJECT_ID}/${ANALYTICS_SERVICE_NAME}:latest" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},DATASET_NAME=${DATASET_NAME}" \
        --service-account "${SERVICE_ACCOUNT}" \
        --memory 1Gi \
        --cpu 1 \
        --timeout 300 \
        --max-instances 10
    
    # Get analytics service URL
    local analytics_url
    analytics_url=$(gcloud run services describe "${ANALYTICS_SERVICE_NAME}" \
        --region="${REGION}" \
        --format="value(status.url)")
    
    save_state "ANALYTICS_URL" "${analytics_url}"
    
    # Build and deploy optimizer service
    log_info "Building optimizer service..."
    gcloud builds submit "${temp_dir}/optimizer-service/" \
        --tag "gcr.io/${PROJECT_ID}/${OPTIMIZER_SERVICE_NAME}:latest" \
        --timeout=600s
    
    log_info "Deploying optimizer service..."
    gcloud run deploy "${OPTIMIZER_SERVICE_NAME}" \
        --image "gcr.io/${PROJECT_ID}/${OPTIMIZER_SERVICE_NAME}:latest" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},BUCKET_NAME=${BUCKET_NAME},ANALYTICS_URL=${analytics_url}" \
        --service-account "${SERVICE_ACCOUNT}" \
        --memory 2Gi \
        --cpu 2 \
        --timeout 900 \
        --max-instances 5
    
    # Get optimizer service URL
    local optimizer_url
    optimizer_url=$(gcloud run services describe "${OPTIMIZER_SERVICE_NAME}" \
        --region="${REGION}" \
        --format="value(status.url)")
    
    save_state "OPTIMIZER_URL" "${optimizer_url}"
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    log_success "Cloud Run services deployed successfully"
    log_info "Analytics Service URL: ${analytics_url}"
    log_info "Optimizer Service URL: ${optimizer_url}"
}

# Create analytics service source code
create_analytics_service() {
    local base_dir="$1"
    local service_dir="${base_dir}/analytics-service"
    mkdir -p "${service_dir}"
    
    # Create main.py
    cat > "${service_dir}/main.py" << 'EOF'
from flask import Flask, request, jsonify
from google.cloud import bigquery
from google.cloud import aiplatform
import os
import json
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize clients
bq_client = bigquery.Client()

PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_NAME = os.environ.get('DATASET_NAME')

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy", "service": "analytics"}), 200

@app.route('/demand-forecast', methods=['POST'])
def generate_demand_forecast():
    try:
        data = request.json
        store_ids = data.get('store_ids', [])
        product_ids = data.get('product_ids', [])
        
        # Generate demand forecast using BigQuery ML
        store_list = "', '".join(store_ids)
        product_list = "', '".join(product_ids)
        
        query = f"""
        SELECT
          store_id,
          product_id,
          forecast_timestamp,
          forecast_value,
          standard_error,
          confidence_level_80,
          confidence_level_95
        FROM
          ML.FORECAST(MODEL `{PROJECT_ID}.{DATASET_NAME}.demand_forecast_model`,
                     STRUCT(30 as horizon, 0.8 as confidence_level))
        WHERE store_id IN ('{store_list}')
        AND product_id IN ('{product_list}')
        ORDER BY forecast_timestamp
        LIMIT 100
        """
        
        query_job = bq_client.query(query)
        results = []
        for row in query_job:
            results.append({
                'store_id': row.store_id,
                'product_id': row.product_id,
                'forecast_timestamp': row.forecast_timestamp.isoformat(),
                'forecast_value': float(row.forecast_value),
                'confidence_80': float(row.confidence_level_80)
            })
        
        return jsonify({"forecasts": results}), 200
        
    except Exception as e:
        logging.error(f"Forecast error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/inventory-analysis', methods=['GET'])
def inventory_analysis():
    try:
        # Query current inventory levels and identify optimization opportunities
        query = f"""
        SELECT
          store_id,
          product_id,
          current_stock,
          max_capacity,
          min_threshold,
          CASE 
            WHEN current_stock < min_threshold THEN 'STOCKOUT_RISK'
            WHEN current_stock > max_capacity * 0.8 THEN 'OVERSTOCK'
            ELSE 'OPTIMAL'
          END as inventory_status
        FROM `{PROJECT_ID}.{DATASET_NAME}.inventory_levels`
        WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
        LIMIT 1000
        """
        
        query_job = bq_client.query(query)
        analysis = []
        for row in query_job:
            analysis.append({
                'store_id': row.store_id,
                'product_id': row.product_id,
                'current_stock': row.current_stock,
                'inventory_status': row.inventory_status
            })
        
        return jsonify({"analysis": analysis}), 200
        
    except Exception as e:
        logging.error(f"Analysis error: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements.txt
    cat > "${service_dir}/requirements.txt" << 'EOF'
Flask==3.0.0
google-cloud-bigquery==3.12.0
google-cloud-aiplatform==1.45.0
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > "${service_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF
}

# Create optimizer service source code
create_optimizer_service() {
    local base_dir="$1"
    local service_dir="${base_dir}/optimizer-service"
    mkdir -p "${service_dir}"
    
    # Create main.py
    cat > "${service_dir}/main.py" << 'EOF'
from flask import Flask, request, jsonify
from google.cloud import storage
import requests
import os
import json
import logging
from datetime import datetime, timedelta

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize clients
storage_client = storage.Client()

PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
ANALYTICS_URL = os.environ.get('ANALYTICS_URL')

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy", "service": "optimizer"}), 200

@app.route('/optimize-inventory', methods=['POST'])
def optimize_inventory():
    try:
        data = request.json
        optimization_params = data.get('parameters', {})
        
        # Step 1: Get demand forecasts from analytics service
        forecast_request = {
            'store_ids': optimization_params.get('store_ids', []),
            'product_ids': optimization_params.get('product_ids', [])
        }
        
        forecast_response = requests.post(
            f"{ANALYTICS_URL}/demand-forecast",
            json=forecast_request,
            timeout=30
        )
        
        if forecast_response.status_code != 200:
            raise Exception("Failed to get demand forecasts")
        
        forecasts = forecast_response.json()['forecasts']
        
        # Step 2: Create optimization model based on forecasts
        optimization_model = create_optimization_model(forecasts, optimization_params)
        
        # Step 3: Simulate optimization (placeholder for actual optimization)
        optimization_result = {
            "status": "optimized",
            "routes": create_sample_routes(forecasts),
            "total_cost": calculate_optimization_cost(forecasts),
            "solving_time": "5.2s",
            "forecasts_processed": len(forecasts)
        }
        
        # Step 4: Store optimization results
        store_optimization_results(optimization_result)
        
        return jsonify({
            "optimization_id": f"opt_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            "status": "completed",
            "summary": optimization_result
        }), 200
        
    except Exception as e:
        logging.error(f"Optimization error: {str(e)}")
        return jsonify({"error": str(e)}), 500

def create_optimization_model(forecasts, params):
    """Create optimization model from demand forecasts"""
    
    model = {
        "displayName": "Inventory Redistribution Optimization",
        "globalStartTime": (datetime.now() + timedelta(hours=1)).isoformat() + "Z",
        "globalEndTime": (datetime.now() + timedelta(hours=9)).isoformat() + "Z",
        "shipments": [],
        "vehicles": [
            {
                "startLocation": {"latitude": 40.7589, "longitude": -73.9851},
                "endLocation": {"latitude": 40.7589, "longitude": -73.9851},
                "capacities": [{"type": "weight", "value": "1000"}],
                "costPerKilometer": 0.5,
                "costPerHour": 20.0
            }
        ]
    }
    
    return model

def create_sample_routes(forecasts):
    """Create sample optimization routes"""
    routes = []
    for i, forecast in enumerate(forecasts[:5]):
        route = {
            "route_id": f"route_{i+1}",
            "vehicle_id": f"vehicle_{(i % 2) + 1}",
            "stops": [
                {
                    "store_id": forecast['store_id'],
                    "product_id": forecast['product_id'],
                    "delivery_quantity": int(forecast['forecast_value'] * 0.8),
                    "estimated_time": f"{8 + i}:00 AM"
                }
            ],
            "total_distance": round(10 + (i * 2.5), 1),
            "estimated_duration": f"{45 + (i * 15)} minutes"
        }
        routes.append(route)
    
    return routes

def calculate_optimization_cost(forecasts):
    """Calculate optimization cost estimate"""
    base_cost = 150.0
    forecast_cost = len(forecasts) * 2.5
    return round(base_cost + forecast_cost, 2)

def store_optimization_results(results):
    """Store optimization results in Cloud Storage"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        blob = bucket.blob(f"optimization-results/optimization_{timestamp}.json")
        blob.upload_from_string(json.dumps(results, indent=2))
    except Exception as e:
        logging.error(f"Failed to store results: {str(e)}")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements.txt
    cat > "${service_dir}/requirements.txt" << 'EOF'
Flask==3.0.0
google-cloud-storage==2.13.0
requests==2.31.0
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > "${service_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF
}

# Validate deployment
validate_deployment() {
    log_step "Validating Deployment"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Deployment validation skipped in dry-run mode"
        return 0
    fi
    
    # Load state
    load_state
    
    local validation_errors=0
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_success "BigQuery dataset validation passed"
    else
        log_error "BigQuery dataset validation failed"
        ((validation_errors++))
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Cloud Storage bucket validation passed"
    else
        log_error "Cloud Storage bucket validation failed"
        ((validation_errors++))
    fi
    
    # Check Cloud Run services
    if [[ -n "${ANALYTICS_URL:-}" ]]; then
        if curl -sf "${ANALYTICS_URL}/health" &>/dev/null; then
            log_success "Analytics service validation passed"
        else
            log_error "Analytics service validation failed"
            ((validation_errors++))
        fi
    fi
    
    if [[ -n "${OPTIMIZER_URL:-}" ]]; then
        if curl -sf "${OPTIMIZER_URL}/health" &>/dev/null; then
            log_success "Optimizer service validation passed"
        else
            log_error "Optimizer service validation failed"
            ((validation_errors++))
        fi
    fi
    
    # Check ML model
    if bq query --use_legacy_sql=false --max_rows=1 "SELECT * FROM ML.TRAINING_INFO(MODEL \`${PROJECT_ID}.${DATASET_NAME}.demand_forecast_model\`) LIMIT 1" &>/dev/null; then
        log_success "ML model validation passed"
    else
        log_warning "ML model may still be training"
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All validation checks passed"
    else
        log_error "${validation_errors} validation check(s) failed"
        return 1
    fi
}

# Display deployment summary
show_deployment_summary() {
    load_state
    
    log_step "Deployment Summary"
    
    cat << EOF

🎉 Intelligent Retail Inventory Optimization deployment completed successfully!

📋 Deployment Details:
   Project ID: ${PROJECT_ID}
   Region: ${REGION}
   Zone: ${ZONE}

🗄️  Data Infrastructure:
   BigQuery Dataset: ${DATASET_NAME}
   Storage Bucket: gs://${BUCKET_NAME}
   ML Model: demand_forecast_model

🚀 Services:
   Analytics Service: ${ANALYTICS_URL:-"Not deployed"}
   Optimizer Service: ${OPTIMIZER_URL:-"Not deployed"}

💡 Next Steps:
   1. Test the analytics API: curl ${ANALYTICS_URL:-"<analytics-url>"}/health
   2. Test inventory analysis: curl ${ANALYTICS_URL:-"<analytics-url>"}/inventory-analysis
   3. Run optimization: curl -X POST ${OPTIMIZER_URL:-"<optimizer-url>"}/optimize-inventory
   4. Monitor in Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}

⚠️  Important Notes:
   - Fleet Engine requires special access and manual setup
   - Estimated monthly cost: $200-400 (varies by usage)
   - Remember to run ./destroy.sh when done to avoid charges

📖 Documentation:
   - Deployment log: ${LOG_FILE}
   - State file: ${STATE_FILE}

EOF
}

# Main deployment function
main() {
    log_info "Starting intelligent retail inventory optimization deployment"
    log_info "Script version: 1.0"
    log_info "Timestamp: $(date)"
    
    # Initialize log file
    echo "=== Intelligent Retail Inventory Optimization Deployment Log ===" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute deployment steps
    validate_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_service_account
    setup_bigquery
    setup_storage
    setup_ml_model
    deploy_cloud_run_services
    validate_deployment
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
    
    # Mark completion in state
    save_state "DEPLOYMENT_STATUS" "COMPLETED"
    save_state "DEPLOYMENT_TIME" "$(date)"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
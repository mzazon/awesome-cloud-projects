#!/bin/bash

# High-Frequency Trading Risk Analytics Deployment Script
# This script deploys TPU Ironwood, Cloud Datastream, BigQuery, and Cloud Run infrastructure
# for real-time financial risk analytics at trading speeds

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/hft-risk-analytics-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
SKIP_CONFIRMATION=false
PROJECT_CREATED=false

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}" | tee -a "${LOG_FILE}"
    fi
}

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        error "Check log file: ${LOG_FILE}"
        if [[ "${PROJECT_CREATED}" == "true" ]]; then
            warn "Project was created during this deployment. Consider running destroy.sh to clean up."
        fi
    fi
    exit $exit_code
}

trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
High-Frequency Trading Risk Analytics Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Validate configuration without deploying resources
    -y, --yes               Skip confirmation prompts
    -p, --project PROJECT   Use existing GCP project ID
    -r, --region REGION     Specify GCP region (default: us-central1)
    -z, --zone ZONE         Specify GCP zone (default: us-central1-a)
    --debug                 Enable debug logging

EXAMPLES:
    $0                      Interactive deployment with prompts
    $0 -y -p my-project     Deploy to existing project without prompts
    $0 -d                   Dry run to validate configuration
    $0 --debug              Deploy with debug logging enabled

ESTIMATED COSTS:
    TPU Ironwood: \$2,000-\$4,000/day (v6e-256 cluster)
    Cloud Datastream: \$0.02/GB streamed + \$0.25/1M events
    BigQuery: \$5/TB queried + \$20/TB stored
    Cloud Run: \$0.48/vCPU-hour + \$0.05/GB-hour
    Total estimated: \$2,500-\$5,000/day (varies by usage)

WARNING: This deployment creates premium-tier infrastructure with substantial costs.
Monitor usage closely and implement proper resource quotas.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed"
        error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log "Google Cloud SDK version: ${gcloud_version}"
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with Google Cloud"
        error "Run: gcloud auth login"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log "Authenticated as: ${active_account}"
    
    # Check if bq CLI is available
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed"
        error "Install with: gcloud components install bq"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage CLI (gsutil) is not installed"
        error "Install with: gcloud components install gsutil"
        exit 1
    fi
    
    # Check internet connectivity
    if ! curl -s --max-time 5 https://cloud.google.com > /dev/null; then
        error "No internet connectivity to Google Cloud"
        exit 1
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Validate configuration
validate_config() {
    log "Validating configuration..."
    
    # Validate project ID format
    if [[ ! "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        error "Invalid project ID format: ${PROJECT_ID}"
        error "Project ID must be 6-30 characters, start with letter, contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
    
    # Validate region
    if ! gcloud compute regions describe "${REGION}" &> /dev/null; then
        error "Invalid region: ${REGION}"
        error "Use 'gcloud compute regions list' to see available regions"
        exit 1
    fi
    
    # Validate zone
    if ! gcloud compute zones describe "${ZONE}" &> /dev/null; then
        error "Invalid zone: ${ZONE}"
        error "Use 'gcloud compute zones list' to see available zones"
        exit 1
    fi
    
    # Check TPU availability in zone
    local tpu_available
    tpu_available=$(gcloud compute tpus accelerator-types list --zone="${ZONE}" --filter="name:v6e-256" --format="value(name)" | head -n1)
    if [[ -z "${tpu_available}" ]]; then
        warn "TPU v6e-256 may not be available in zone ${ZONE}"
        warn "Consider using us-central1-a, us-central1-b, or us-central1-c for TPU availability"
    fi
    
    log "✅ Configuration validation completed"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    PROJECT_ID="${PROJECT_ID:-hft-risk-analytics-$(date +%s)}"
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 4)
    
    # Export environment variables
    export PROJECT_ID
    export REGION
    export ZONE
    export DATASET_ID="trading_analytics"
    export DATASTREAM_NAME="trading-data-stream"
    export BUCKET_NAME="hft-risk-data-${RANDOM_SUFFIX}"
    export TPU_NAME="ironwood-risk-tpu-${RANDOM_SUFFIX}"
    export CLOUD_RUN_SERVICE="risk-analytics-api-${RANDOM_SUFFIX}"
    
    debug "PROJECT_ID: ${PROJECT_ID}"
    debug "REGION: ${REGION}"
    debug "ZONE: ${ZONE}"
    debug "RANDOM_SUFFIX: ${RANDOM_SUFFIX}"
    
    log "✅ Environment variables configured"
}

# Create or verify project
setup_project() {
    log "Setting up GCP project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log "Using existing project: ${PROJECT_ID}"
    else
        log "Creating new project: ${PROJECT_ID}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "[DRY RUN] Would create project: ${PROJECT_ID}"
            return 0
        fi
        
        # Create project
        gcloud projects create "${PROJECT_ID}" \
            --name="HFT Risk Analytics" \
            --labels="purpose=high-frequency-trading,component=risk-analytics,environment=production"
        
        PROJECT_CREATED=true
        
        # Link billing account (required for TPU and premium services)
        local billing_account
        billing_account=$(gcloud billing accounts list --filter="open:true" --format="value(name)" | head -n1)
        if [[ -n "${billing_account}" ]]; then
            gcloud billing projects link "${PROJECT_ID}" --billing-account="${billing_account}"
            log "Linked project to billing account: ${billing_account}"
        else
            error "No active billing account found. Please set up billing for the project."
            exit 1
        fi
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "✅ Project setup completed: ${PROJECT_ID}"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "tpu.googleapis.com"
        "datastream.googleapis.com"
        "bigquery.googleapis.com"
        "run.googleapis.com"
        "artifactregistry.googleapis.com"
        "aiplatform.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "compute.googleapis.com"
        "iam.googleapis.com"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "✅ All required APIs enabled"
}

# Create BigQuery dataset
setup_bigquery() {
    log "Setting up BigQuery infrastructure..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create BigQuery dataset: ${DATASET_ID}"
        return 0
    fi
    
    # Create dataset
    if ! bq ls "${PROJECT_ID}:${DATASET_ID}" &> /dev/null; then
        bq mk --dataset \
            --description="High-frequency trading risk analytics dataset" \
            --location="${REGION}" \
            --default_table_expiration=7776000 \
            --default_partition_expiration=2592000 \
            "${PROJECT_ID}:${DATASET_ID}"
        
        log "Created BigQuery dataset: ${DATASET_ID}"
    else
        log "BigQuery dataset already exists: ${DATASET_ID}"
    fi
    
    # Create trading positions table
    cat > /tmp/trading_positions_schema.sql << 'EOF'
CREATE TABLE IF NOT EXISTS `PROJECT_ID.DATASET_ID.trading_positions` (
  position_id STRING NOT NULL,
  symbol STRING NOT NULL,
  quantity NUMERIC NOT NULL,
  price NUMERIC NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  trader_id STRING NOT NULL,
  risk_score NUMERIC,
  var_1d NUMERIC,
  expected_shortfall NUMERIC,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(timestamp)
CLUSTER BY symbol, trader_id
EOF
    
    # Replace placeholders
    sed -i.bak "s/PROJECT_ID/${PROJECT_ID}/g; s/DATASET_ID/${DATASET_ID}/g" /tmp/trading_positions_schema.sql
    
    # Execute schema creation
    bq query --use_legacy_sql=false < /tmp/trading_positions_schema.sql
    
    # Create risk metrics table
    cat > /tmp/risk_metrics_schema.sql << 'EOF'
CREATE TABLE IF NOT EXISTS `PROJECT_ID.DATASET_ID.risk_metrics` (
  metric_id STRING NOT NULL,
  portfolio_id STRING NOT NULL,
  metric_type STRING NOT NULL,
  metric_value NUMERIC NOT NULL,
  calculation_timestamp TIMESTAMP NOT NULL,
  confidence_level NUMERIC,
  time_horizon_days INTEGER,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(calculation_timestamp)
CLUSTER BY portfolio_id, metric_type
EOF
    
    sed -i.bak "s/PROJECT_ID/${PROJECT_ID}/g; s/DATASET_ID/${DATASET_ID}/g" /tmp/risk_metrics_schema.sql
    bq query --use_legacy_sql=false < /tmp/risk_metrics_schema.sql
    
    # Create real-time analytics view
    cat > /tmp/real_time_view.sql << 'EOF'
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.real_time_risk_dashboard` AS
SELECT 
  'portfolio_001' as portfolio_id,
  symbol,
  SUM(quantity * price) as position_value,
  MAX(risk_score) as max_risk_score,
  AVG(var_1d) as avg_var_1d,
  COUNT(*) as position_count,
  MAX(timestamp) as last_update
FROM `PROJECT_ID.DATASET_ID.trading_positions`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY symbol
EOF
    
    sed -i.bak "s/PROJECT_ID/${PROJECT_ID}/g; s/DATASET_ID/${DATASET_ID}/g" /tmp/real_time_view.sql
    bq query --use_legacy_sql=false < /tmp/real_time_view.sql
    
    # Cleanup temp files
    rm -f /tmp/trading_positions_schema.sql /tmp/trading_positions_schema.sql.bak
    rm -f /tmp/risk_metrics_schema.sql /tmp/risk_metrics_schema.sql.bak
    rm -f /tmp/real_time_view.sql /tmp/real_time_view.sql.bak
    
    log "✅ BigQuery infrastructure created"
}

# Create Cloud Storage bucket
setup_storage() {
    log "Setting up Cloud Storage..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create storage bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create bucket
    if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            -b on \
            "gs://${BUCKET_NAME}"
        
        log "Created storage bucket: ${BUCKET_NAME}"
    else
        log "Storage bucket already exists: ${BUCKET_NAME}"
    fi
    
    # Set bucket policies for security
    gsutil iam ch "serviceAccount:service-${PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com:roles/storage.objectViewer" "gs://${BUCKET_NAME}"
    
    # Create directory structure
    echo "# TPU Models Directory" | gsutil cp - "gs://${BUCKET_NAME}/models/README.md"
    echo "# Streaming Data Directory" | gsutil cp - "gs://${BUCKET_NAME}/data/README.md"
    echo "# Logs Directory" | gsutil cp - "gs://${BUCKET_NAME}/logs/README.md"
    
    log "✅ Cloud Storage setup completed"
}

# Create TPU Ironwood cluster
setup_tpu() {
    log "Setting up TPU Ironwood cluster..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create TPU: ${TPU_NAME}"
        return 0
    fi
    
    # Check TPU quotas
    local quota_check
    quota_check=$(gcloud compute project-info describe --format="value(quotas[].limit)" --filter="quotas.metric:TPU_V6E_CORES AND quotas.region:${REGION}" 2>/dev/null || echo "0")
    
    if [[ "${quota_check}" == "0" ]]; then
        warn "TPU quota may not be available in ${REGION}"
        warn "Request TPU quota at: https://console.cloud.google.com/quotas"
    fi
    
    # Create TPU cluster
    log "Creating TPU Ironwood cluster (this may take 10-15 minutes)..."
    gcloud compute tpus tpu-vm create "${TPU_NAME}" \
        --zone="${ZONE}" \
        --accelerator-type=v6e-256 \
        --version=tpu-vm-v4-base \
        --network=default \
        --description="High-frequency trading risk analytics TPU cluster" \
        --labels="purpose=hft-risk-analytics,component=tpu-inference,environment=production" \
        --quiet
    
    # Wait for TPU to be ready
    log "Waiting for TPU to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local tpu_state
        tpu_state=$(gcloud compute tpus tpu-vm describe "${TPU_NAME}" --zone="${ZONE}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${tpu_state}" == "READY" ]]; then
            log "TPU cluster is ready"
            break
        elif [[ "${tpu_state}" == "FAILED" ]]; then
            error "TPU creation failed"
            exit 1
        fi
        
        debug "TPU state: ${tpu_state}, attempt ${attempt}/${max_attempts}"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "TPU did not become ready within expected time"
        exit 1
    fi
    
    # Configure TPU for financial workloads
    log "Configuring TPU for financial workloads..."
    gcloud compute tpus tpu-vm ssh "${TPU_NAME}" \
        --zone="${ZONE}" \
        --command="sudo apt-get update && sudo apt-get install -y python3-pip python3-venv && python3 -m pip install --upgrade pip"
    
    log "✅ TPU Ironwood cluster created and configured"
}

# Setup Cloud Datastream (placeholder - requires actual database connection)
setup_datastream() {
    log "Setting up Cloud Datastream configuration..."
    
    warn "Cloud Datastream setup requires a source database configuration"
    warn "This deployment creates the foundational infrastructure"
    warn "You will need to configure source database connections manually"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Datastream configuration"
        return 0
    fi
    
    # Create sample connection profile configurations
    mkdir -p /tmp/datastream-config
    
    cat > /tmp/datastream-config/mysql-source-config.json << EOF
{
  "includeObjects": {
    "mysqlDatabases": [
      {
        "database": "trading_db",
        "mysqlTables": [
          {
            "table": "positions"
          },
          {
            "table": "transactions"
          },
          {
            "table": "market_data"
          }
        ]
      }
    ]
  }
}
EOF
    
    cat > /tmp/datastream-config/bigquery-dest-config.json << EOF
{
  "datasetId": "${DATASET_ID}",
  "mergeMode": "MERGE",
  "appendOnly": false
}
EOF
    
    log "Datastream configuration files created in /tmp/datastream-config/"
    log "Configure your source database and run the following commands:"
    log ""
    log "# Create source connection profile"
    log "gcloud datastream connection-profiles create ${DATASTREAM_NAME}-source \\"
    log "    --location=${REGION} \\"
    log "    --type=mysql \\"
    log "    --mysql-hostname=YOUR_TRADING_DB_HOST \\"
    log "    --mysql-port=3306 \\"
    log "    --mysql-username=datastream_user \\"
    log "    --mysql-password=YOUR_SECURE_PASSWORD \\"
    log "    --display-name=\"Trading Database Source\""
    log ""
    log "# Create destination connection profile"
    log "gcloud datastream connection-profiles create ${DATASTREAM_NAME}-dest \\"
    log "    --location=${REGION} \\"
    log "    --type=bigquery \\"
    log "    --bigquery-dataset=${PROJECT_ID}.${DATASET_ID} \\"
    log "    --display-name=\"BigQuery Analytics Destination\""
    log ""
    log "# Create streaming pipeline"
    log "gcloud datastream streams create ${DATASTREAM_NAME} \\"
    log "    --location=${REGION} \\"
    log "    --source=${DATASTREAM_NAME}-source \\"
    log "    --destination=${DATASTREAM_NAME}-dest \\"
    log "    --mysql-source-config=/tmp/datastream-config/mysql-source-config.json \\"
    log "    --bigquery-destination-config=/tmp/datastream-config/bigquery-dest-config.json \\"
    log "    --display-name=\"Real-time Trading Data Stream\""
    
    log "✅ Datastream configuration prepared"
}

# Create Cloud Run service
setup_cloud_run() {
    log "Setting up Cloud Run API service..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Cloud Run service: ${CLOUD_RUN_SERVICE}"
        return 0
    fi
    
    # Create sample Cloud Run application
    local app_dir="/tmp/risk-api"
    mkdir -p "${app_dir}"
    
    # Create Dockerfile
    cat > "${app_dir}/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run application
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "--timeout", "30", "main:app"]
EOF
    
    # Create requirements.txt
    cat > "${app_dir}/requirements.txt" << 'EOF'
flask==2.3.3
google-cloud-aiplatform==1.34.0
google-cloud-bigquery==3.11.4
google-cloud-storage==2.10.0
numpy==1.24.3
pandas==2.0.3
gunicorn==21.2.0
requests==2.31.0
EOF
    
    # Create main application
    cat > "${app_dir}/main.py" << 'EOF'
import os
import json
import logging
import numpy as np
from flask import Flask, request, jsonify
from google.cloud import bigquery
from google.cloud import aiplatform
import traceback

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize Google Cloud clients
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_ID = os.environ.get('DATASET_ID', 'trading_analytics')

try:
    bigquery_client = bigquery.Client(project=PROJECT_ID)
    logger.info(f"Initialized BigQuery client for project: {PROJECT_ID}")
except Exception as e:
    logger.error(f"Failed to initialize BigQuery client: {e}")
    bigquery_client = None

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'risk-analytics-api',
        'project': PROJECT_ID
    })

@app.route('/calculate-risk', methods=['POST'])
def calculate_risk():
    """Calculate risk metrics for a portfolio or position"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        portfolio_id = data.get('portfolio_id', 'default')
        symbol = data.get('symbol', 'ALL')
        
        # Sample risk calculation (replace with actual TPU inference)
        risk_metrics = {
            'portfolio_id': portfolio_id,
            'symbol': symbol,
            'var_1d': np.random.uniform(0.01, 0.05),  # 1-day Value at Risk
            'expected_shortfall': np.random.uniform(0.02, 0.08),
            'risk_score': np.random.uniform(0.1, 0.9),
            'calculation_timestamp': 'CURRENT_TIMESTAMP()',
            'confidence_level': 0.95
        }
        
        # Store results in BigQuery
        if bigquery_client:
            try:
                table_id = f"{PROJECT_ID}.{DATASET_ID}.risk_metrics"
                rows_to_insert = [risk_metrics]
                
                table = bigquery_client.get_table(table_id)
                errors = bigquery_client.insert_rows_json(table, rows_to_insert)
                
                if errors:
                    logger.error(f"BigQuery insert errors: {errors}")
                else:
                    logger.info(f"Risk metrics stored for portfolio: {portfolio_id}")
            except Exception as e:
                logger.error(f"Failed to store risk metrics: {e}")
        
        return jsonify({
            'status': 'success',
            'risk_metrics': risk_metrics
        })
        
    except Exception as e:
        logger.error(f"Risk calculation error: {e}")
        logger.error(traceback.format_exc())
        return jsonify({
            'error': 'Risk calculation failed',
            'message': str(e)
        }), 500

@app.route('/portfolio-summary')
def portfolio_summary():
    """Get portfolio risk summary from BigQuery"""
    try:
        if not bigquery_client:
            return jsonify({'error': 'BigQuery client not available'}), 500
        
        query = f"""
        SELECT 
            portfolio_id,
            COUNT(*) as position_count,
            AVG(risk_score) as avg_risk_score,
            MAX(calculation_timestamp) as last_calculation
        FROM `{PROJECT_ID}.{DATASET_ID}.risk_metrics`
        WHERE calculation_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
        GROUP BY portfolio_id
        ORDER BY last_calculation DESC
        LIMIT 10
        """
        
        query_job = bigquery_client.query(query)
        results = query_job.result()
        
        portfolios = []
        for row in results:
            portfolios.append({
                'portfolio_id': row.portfolio_id,
                'position_count': row.position_count,
                'avg_risk_score': float(row.avg_risk_score) if row.avg_risk_score else 0,
                'last_calculation': row.last_calculation.isoformat() if row.last_calculation else None
            })
        
        return jsonify({
            'status': 'success',
            'portfolios': portfolios
        })
        
    except Exception as e:
        logger.error(f"Portfolio summary error: {e}")
        return jsonify({
            'error': 'Failed to fetch portfolio summary',
            'message': str(e)
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF
    
    # Build and deploy
    log "Building container image..."
    gcloud builds submit "${app_dir}" \
        --tag "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}:latest" \
        --quiet
    
    log "Deploying Cloud Run service..."
    gcloud run deploy "${CLOUD_RUN_SERVICE}" \
        --image "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}:latest" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --memory 2Gi \
        --cpu 2 \
        --concurrency 1000 \
        --timeout 30s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},DATASET_ID=${DATASET_ID}" \
        --labels="purpose=hft-risk-analytics,component=api-service,environment=production" \
        --quiet
    
    # Get service URL
    local service_url
    service_url=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" --format="value(status.url)")
    
    log "Cloud Run service deployed at: ${service_url}"
    
    # Cleanup temporary directory
    rm -rf "${app_dir}"
    
    log "✅ Cloud Run API service created"
}

# Setup monitoring and alerting
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create monitoring configuration"
        return 0
    fi
    
    # Create log-based metric for error tracking
    gcloud logging metrics create trading_error_rate \
        --description="Error rate in trading systems" \
        --log-filter='resource.type="cloud_run_revision" AND severity="ERROR"' \
        --quiet || true
    
    # Create custom metrics for TPU monitoring
    gcloud logging metrics create tpu_inference_latency \
        --description="TPU inference latency metrics" \
        --log-filter='resource.type="tpu_worker" AND jsonPayload.metric_type="inference_latency"' \
        --quiet || true
    
    log "Monitoring metrics created"
    log "Configure alerting policies in the Google Cloud Console:"
    log "https://console.cloud.google.com/monitoring/alerting?project=${PROJECT_ID}"
    
    log "✅ Monitoring setup completed"
}

# Display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
    log ""
    log "Created Resources:"
    log "  • TPU Ironwood Cluster: ${TPU_NAME}"
    log "  • BigQuery Dataset: ${DATASET_ID}"
    log "  • Cloud Storage Bucket: gs://${BUCKET_NAME}"
    log "  • Cloud Run Service: ${CLOUD_RUN_SERVICE}"
    log ""
    log "Next Steps:"
    log "1. Configure Cloud Datastream with your trading database"
    log "2. Deploy your risk calculation models to TPU cluster"
    log "3. Set up monitoring dashboards and alerts"
    log "4. Test the risk analytics API endpoints"
    log ""
    
    # Get service URL for API testing
    if ! [[ "${DRY_RUN}" == "true" ]]; then
        local service_url
        service_url=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" --format="value(status.url)" 2>/dev/null || echo "Not available")
        log "API Service URL: ${service_url}"
        log "Health Check: ${service_url}/health"
        log "Risk Calculation: ${service_url}/calculate-risk"
    fi
    
    log ""
    log "⚠️  IMPORTANT COST WARNING ⚠️"
    log "This deployment includes premium TPU Ironwood resources"
    log "Estimated daily cost: \$2,500-\$5,000"
    log "Monitor usage at: https://console.cloud.google.com/billing"
    log ""
    log "Deployment completed successfully!"
    log "Log file: ${LOG_FILE}"
}

# Confirmation prompt
confirm_deployment() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}⚠️  HIGH-COST INFRASTRUCTURE DEPLOYMENT ⚠️${NC}"
    echo ""
    echo "This will deploy premium-tier infrastructure including:"
    echo "  • TPU Ironwood v6e-256 cluster (~\$2,000-\$4,000/day)"
    echo "  • Cloud Datastream for real-time replication"
    echo "  • BigQuery for analytics processing"
    echo "  • Cloud Run for API services"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Estimated daily cost: \$2,500-\$5,000"
    echo ""
    read -p "Do you want to proceed with deployment? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    log "Starting High-Frequency Trading Risk Analytics deployment"
    log "Script: $0"
    log "Arguments: $*"
    log "Log file: ${LOG_FILE}"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment
    
    # Validate configuration
    validate_config
    
    # Get project number for IAM
    PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null || echo "")
    export PROJECT_NUMBER
    
    # Show confirmation prompt
    confirm_deployment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "=== DRY RUN MODE ==="
        log "This is a dry run. No resources will be created."
        log ""
    fi
    
    # Execute deployment steps
    setup_project
    enable_apis
    setup_bigquery
    setup_storage
    setup_tpu
    setup_datastream
    setup_cloud_run
    setup_monitoring
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
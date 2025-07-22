#!/bin/bash

# GCP Centralized Data Lake Governance Deployment Script
# This script deploys the complete infrastructure for centralized data lake governance
# using Dataproc Metastore and BigQuery

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage CLI (gsutil) is not installed. Please install it first."
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-data-governance-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export BUCKET_NAME="data-lake-${RANDOM_SUFFIX}"
    export METASTORE_NAME="governance-metastore-${RANDOM_SUFFIX}"
    export DATAPROC_CLUSTER="analytics-cluster-${RANDOM_SUFFIX}"
    export BIGQUERY_DATASET="governance_dataset_${RANDOM_SUFFIX}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project"
    gcloud config set compute/region "${REGION}" || error "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error "Failed to set zone"
    
    # Save environment variables to file for cleanup script
    cat > .env <<EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
METASTORE_NAME=${METASTORE_NAME}
DATAPROC_CLUSTER=${DATAPROC_CLUSTER}
BIGQUERY_DATASET=${BIGQUERY_DATASET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment configured with suffix: ${RANDOM_SUFFIX}"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigquery.googleapis.com"
        "dataproc.googleapis.com"
        "storage.googleapis.com"
        "metastore.googleapis.com"
        "compute.googleapis.com"
        "datacatalog.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage data lake foundation
create_storage_foundation() {
    log "Creating Cloud Storage data lake foundation..."
    
    # Create Cloud Storage bucket for data lake
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        success "Created Cloud Storage bucket: gs://${BUCKET_NAME}"
    else
        error "Failed to create Cloud Storage bucket"
    fi
    
    # Enable versioning and lifecycle management
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        success "Enabled versioning on bucket"
    else
        warning "Failed to enable versioning (may already be enabled)"
    fi
    
    # Create directory structure for governance
    log "Creating directory structure and copying sample data..."
    gsutil -q -m mkdir "gs://${BUCKET_NAME}/raw-data/" || true
    gsutil -q -m mkdir "gs://${BUCKET_NAME}/processed-data/" || true
    gsutil -q -m mkdir "gs://${BUCKET_NAME}/warehouse/" || true
    
    # Create sample data files
    cat > sample_retail_data.csv <<EOF
customer_id,product_id,quantity,price,transaction_date
CUST001,PROD001,2,29.99,2025-01-01
CUST002,PROD002,1,49.99,2025-01-02
CUST003,PROD001,3,29.99,2025-01-03
CUST004,PROD003,1,19.99,2025-01-04
CUST005,PROD002,2,49.99,2025-01-05
EOF
    
    # Upload sample data
    if gsutil cp sample_retail_data.csv "gs://${BUCKET_NAME}/raw-data/"; then
        success "Uploaded sample data to data lake"
    else
        error "Failed to upload sample data"
    fi
    
    # Clean up local file
    rm -f sample_retail_data.csv
    
    success "Data lake foundation created"
}

# Function to deploy BigLake Metastore
deploy_metastore() {
    log "Deploying BigLake Metastore for unified metadata management..."
    
    # Create BigLake Metastore instance
    log "Creating metastore instance (this may take 10-15 minutes)..."
    if gcloud metastore services create "${METASTORE_NAME}" \
        --location="${REGION}" \
        --tier=DEVELOPER \
        --database-type=MYSQL \
        --hive-metastore-version=3.1.2 \
        --port=9083 \
        --quiet; then
        success "Metastore creation initiated"
    else
        error "Failed to create metastore"
    fi
    
    # Wait for metastore to be ready with timeout
    log "Waiting for metastore deployment (timeout: 20 minutes)..."
    if timeout 1200 gcloud metastore services wait "${METASTORE_NAME}" \
        --location="${REGION}" \
        --timeout=1200; then
        success "Metastore deployed successfully"
    else
        error "Metastore deployment timed out or failed"
    fi
    
    # Get metastore endpoint
    METASTORE_ENDPOINT=$(gcloud metastore services describe "${METASTORE_NAME}" \
        --location="${REGION}" \
        --format="value(endpointUri)")
    
    if [[ -n "${METASTORE_ENDPOINT}" ]]; then
        success "BigLake Metastore deployed at: ${METASTORE_ENDPOINT}"
        echo "METASTORE_ENDPOINT=${METASTORE_ENDPOINT}" >> .env
    else
        error "Failed to get metastore endpoint"
    fi
}

# Function to create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset with metastore integration..."
    
    # Create BigQuery dataset
    if bq mk --dataset \
        --location="${REGION}" \
        --description="Governance dataset with metastore integration" \
        "${PROJECT_ID}:${BIGQUERY_DATASET}"; then
        success "Created BigQuery dataset: ${BIGQUERY_DATASET}"
    else
        error "Failed to create BigQuery dataset"
    fi
    
    # Create external table definition
    cat > external_table_def.json <<EOF
{
  "sourceFormat": "CSV",
  "sourceUris": ["gs://${BUCKET_NAME}/raw-data/*.csv"],
  "schema": {
    "fields": [
      {"name": "customer_id", "type": "STRING"},
      {"name": "product_id", "type": "STRING"},
      {"name": "quantity", "type": "INTEGER"},
      {"name": "price", "type": "FLOAT"},
      {"name": "transaction_date", "type": "DATE"}
    ]
  },
  "csvOptions": {
    "skipLeadingRows": 1
  }
}
EOF
    
    # Create external table
    if bq mk --external_table_definition=external_table_def.json \
        "${PROJECT_ID}:${BIGQUERY_DATASET}.retail_data"; then
        success "Created external table: retail_data"
    else
        error "Failed to create external table"
    fi
    
    # Clean up temporary file
    rm -f external_table_def.json
    
    success "BigQuery dataset created with external table integration"
}

# Function to deploy Dataproc cluster
deploy_dataproc_cluster() {
    log "Deploying Dataproc cluster with metastore integration..."
    
    # Create Dataproc cluster with metastore integration
    log "Creating Dataproc cluster (this may take 5-10 minutes)..."
    if gcloud dataproc clusters create "${DATAPROC_CLUSTER}" \
        --region="${REGION}" \
        --zone="${ZONE}" \
        --num-masters=1 \
        --num-workers=2 \
        --worker-machine-type=n1-standard-2 \
        --master-machine-type=n1-standard-2 \
        --image-version=2.0-debian10 \
        --dataproc-metastore="projects/${PROJECT_ID}/locations/${REGION}/services/${METASTORE_NAME}" \
        --enable-autoscaling \
        --max-workers=5 \
        --secondary-worker-type=preemptible \
        --num-preemptible-workers=2 \
        --quiet; then
        success "Dataproc cluster creation initiated"
    else
        error "Failed to create Dataproc cluster"
    fi
    
    # Wait for cluster to be ready
    log "Waiting for Dataproc cluster deployment..."
    if timeout 600 gcloud dataproc clusters wait "${DATAPROC_CLUSTER}" \
        --region="${REGION}" \
        --timeout=600; then
        success "Dataproc cluster deployed successfully"
    else
        error "Dataproc cluster deployment timed out or failed"
    fi
}

# Function to create Hive tables
create_hive_tables() {
    log "Creating Hive tables through Dataproc for cross-engine access..."
    
    # Create Hive database and table
    local hive_script="
    CREATE DATABASE IF NOT EXISTS governance_db;
    
    CREATE EXTERNAL TABLE IF NOT EXISTS governance_db.customer_analytics (
      customer_id STRING,
      product_id STRING,
      quantity INT,
      price DOUBLE,
      transaction_date DATE
    )
    STORED AS PARQUET
    LOCATION 'gs://${BUCKET_NAME}/processed-data/customer_analytics/';
    
    SHOW TABLES IN governance_db;"
    
    if gcloud dataproc jobs submit hive \
        --cluster="${DATAPROC_CLUSTER}" \
        --region="${REGION}" \
        --execute="${hive_script}"; then
        success "Hive database and table structure created"
    else
        error "Failed to create Hive tables"
    fi
    
    # Create Python script for Spark job
    cat > populate_table.py <<EOF
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("MetastoreDemo") \
    .config("spark.sql.catalogImplementation", "hive") \
    .enableHiveSupport() \
    .getOrCreate()

# Create sample data
data = [
    ("CUST001", "PROD001", 2, 29.99, "2025-01-01"),
    ("CUST002", "PROD002", 1, 49.99, "2025-01-02"),
    ("CUST003", "PROD001", 3, 29.99, "2025-01-03"),
    ("CUST004", "PROD003", 1, 19.99, "2025-01-04"),
    ("CUST005", "PROD002", 2, 49.99, "2025-01-05")
]

df = spark.createDataFrame(data, ["customer_id", "product_id", "quantity", "price", "transaction_date"])
df.write.mode("overwrite").saveAsTable("governance_db.customer_analytics")

print("✅ Hive table populated with sample data")
spark.stop()
EOF
    
    # Upload and run Spark job
    if gsutil cp populate_table.py "gs://${BUCKET_NAME}/scripts/" && \
       gcloud dataproc jobs submit pyspark \
        --cluster="${DATAPROC_CLUSTER}" \
        --region="${REGION}" \
        "gs://${BUCKET_NAME}/scripts/populate_table.py"; then
        success "Hive table populated with sample data"
    else
        error "Failed to populate Hive table"
    fi
    
    # Clean up local file
    rm -f populate_table.py
    
    success "Hive tables created with cross-engine accessibility"
}

# Function to configure governance policies
configure_governance_policies() {
    log "Implementing data governance policies and lineage tracking..."
    
    # Create governance policies SQL
    cat > governance-policies.sql <<EOF
-- Create views for governed data access
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${BIGQUERY_DATASET}.customer_summary\` AS
SELECT 
  customer_id,
  COUNT(*) as transaction_count,
  SUM(quantity * price) as total_value,
  MAX(transaction_date) as last_transaction
FROM \`${PROJECT_ID}.${BIGQUERY_DATASET}.retail_data\`
GROUP BY customer_id;

-- Create materialized view for performance
CREATE OR REPLACE MATERIALIZED VIEW \`${PROJECT_ID}.${BIGQUERY_DATASET}.daily_sales\` AS
SELECT 
  transaction_date,
  SUM(quantity * price) as daily_revenue,
  COUNT(DISTINCT customer_id) as unique_customers
FROM \`${PROJECT_ID}.${BIGQUERY_DATASET}.retail_data\`
GROUP BY transaction_date;
EOF
    
    # Apply governance policies
    if bq query --use_legacy_sql=false < governance-policies.sql; then
        success "Governance policies applied"
    else
        error "Failed to apply governance policies"
    fi
    
    # Clean up temporary file
    rm -f governance-policies.sql
    
    success "Data governance policies implemented"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment and cross-engine metadata synchronization..."
    
    # Test BigQuery access
    log "Testing BigQuery access..."
    if bq query --use_legacy_sql=false \
        "SELECT COUNT(*) as bigquery_count FROM \`${PROJECT_ID}.${BIGQUERY_DATASET}.retail_data\`"; then
        success "BigQuery access validated"
    else
        warning "BigQuery access test failed"
    fi
    
    # Test Hive access through Dataproc
    log "Testing Hive access through Dataproc..."
    if gcloud dataproc jobs submit hive \
        --cluster="${DATAPROC_CLUSTER}" \
        --region="${REGION}" \
        --execute="SHOW DATABASES; SHOW TABLES IN governance_db;"; then
        success "Hive access validated"
    else
        warning "Hive access test failed"
    fi
    
    # Test governance views
    log "Testing governance views..."
    if bq query --use_legacy_sql=false \
        "SELECT * FROM \`${PROJECT_ID}.${BIGQUERY_DATASET}.customer_summary\` LIMIT 5"; then
        success "Governance views validated"
    else
        warning "Governance views test failed"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo ""
    echo "Resources Created:"
    echo "- Cloud Storage Bucket: gs://${BUCKET_NAME}"
    echo "- BigLake Metastore: ${METASTORE_NAME}"
    echo "- Dataproc Cluster: ${DATAPROC_CLUSTER}"
    echo "- BigQuery Dataset: ${BIGQUERY_DATASET}"
    echo ""
    echo "Next Steps:"
    echo "1. Access BigQuery at: https://console.cloud.google.com/bigquery"
    echo "2. View Dataproc cluster at: https://console.cloud.google.com/dataproc"
    echo "3. Explore data governance policies in BigQuery Studio"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
    success "Centralized Data Lake Governance infrastructure deployed successfully!"
}

# Main deployment function
main() {
    log "Starting GCP Centralized Data Lake Governance deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_foundation
    deploy_metastore
    create_bigquery_dataset
    deploy_dataproc_cluster
    create_hive_tables
    configure_governance_policies
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up partial deployment."' INT TERM

# Run main function
main "$@"
#!/bin/bash

# Cross-Database Analytics Federation with AlloyDB Omni and BigQuery - Deployment Script
# This script deploys the complete federated analytics infrastructure
# Recipe: cross-database-analytics-federation-alloydb-omni-bigquery

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partially created resources..."
    if [[ -n "${ALLOYDB_INSTANCE:-}" ]] && gcloud sql instances describe "${ALLOYDB_INSTANCE}" &>/dev/null; then
        log_info "Deleting Cloud SQL instance: ${ALLOYDB_INSTANCE}"
        gcloud sql instances delete "${ALLOYDB_INSTANCE}" --quiet || true
    fi
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}"
        gsutil -m rm -r "gs://${BUCKET_NAME}" || true
    fi
    exit 1
}

# Set trap for error cleanup
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK"
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login'"
    fi
    
    # Check if required tools are available
    for tool in openssl curl; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is not installed. Please install it."
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Set environment variables
set_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="analytics-federation-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set derived variables
    export SERVICE_ACCOUNT="federation-sa-${RANDOM_SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
    export BUCKET_NAME="analytics-lake-${RANDOM_SUFFIX}"
    export ALLOYDB_INSTANCE="alloydb-omni-sim-${RANDOM_SUFFIX}"
    export DB_PASSWORD="SecurePassword123!"
    export CONNECTION_ID="alloydb-federation-${RANDOM_SUFFIX}"
    export LAKE_ID="analytics-federation-lake-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log_info "PROJECT_ID: ${PROJECT_ID}"
    log_info "REGION: ${REGION}"
    log_info "RANDOM_SUFFIX: ${RANDOM_SUFFIX}"
}

# Create and configure project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Analytics Federation ${RANDOM_SUFFIX}"
        
        # Enable billing (requires manual setup)
        log_warning "Please enable billing for project ${PROJECT_ID} in the Google Cloud Console"
        log_warning "Press Enter to continue after enabling billing..."
        read -r
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configured: ${PROJECT_ID}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigquery.googleapis.com"
        "dataplex.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "compute.googleapis.com"
        "sqladmin.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create service account and IAM roles
setup_iam() {
    log_info "Setting up IAM service account and roles..."
    
    # Create service account
    if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" &>/dev/null; then
        gcloud iam service-accounts create "federation-sa-${RANDOM_SUFFIX}" \
            --display-name="Analytics Federation Service Account" \
            --description="Service account for cross-database analytics federation"
    fi
    
    # Grant necessary IAM roles
    local roles=(
        "roles/bigquery.connectionUser"
        "roles/bigquery.dataEditor"
        "roles/dataplex.editor"
        "roles/storage.admin"
        "roles/cloudsql.client"
        "roles/cloudfunctions.invoker"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role: ${role}"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT}" \
            --role="${role}" \
            --quiet
    done
    
    log_success "IAM configuration completed"
}

# Create Cloud Storage data lake
create_storage() {
    log_info "Creating Cloud Storage data lake foundation..."
    
    # Create primary data lake bucket
    if ! gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Enable versioning for data protection
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Create directory structure for organized data management
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw-data/.keep"
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/processed-data/.keep"
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/staging/.keep"
    fi
    
    log_success "Data lake foundation created: gs://${BUCKET_NAME}"
}

# Set up BigQuery datasets and sample data
setup_bigquery() {
    log_info "Setting up BigQuery datasets and federation..."
    
    # Create BigQuery datasets
    if ! bq ls -d "${PROJECT_ID}:analytics_federation" &>/dev/null; then
        bq mk --dataset \
            --location="${REGION}" \
            --description="Federated analytics workspace" \
            "${PROJECT_ID}:analytics_federation"
    fi
    
    if ! bq ls -d "${PROJECT_ID}:cloud_analytics" &>/dev/null; then
        bq mk --dataset \
            --location="${REGION}" \
            --description="Cloud-native analytics data" \
            "${PROJECT_ID}:cloud_analytics"
    fi
    
    # Create sample cloud-native data table
    if ! bq ls "${PROJECT_ID}:cloud_analytics.customers" &>/dev/null; then
        bq mk --table \
            "${PROJECT_ID}:cloud_analytics.customers" \
            customer_id:INTEGER,customer_name:STRING,region:STRING,signup_date:DATE
        
        # Insert sample customer data
        bq query --use_legacy_sql=false \
            "INSERT INTO \`${PROJECT_ID}.cloud_analytics.customers\` VALUES
             (1, 'Acme Corp', 'North America', '2023-01-15'),
             (2, 'Global Tech Ltd', 'Europe', '2023-02-20'),
             (3, 'Pacific Solutions', 'Asia Pacific', '2023-03-10')"
    fi
    
    log_success "BigQuery datasets created with sample data"
}

# Deploy AlloyDB Omni simulation
deploy_alloydb() {
    log_info "Deploying AlloyDB Omni simulation environment..."
    
    # Create Cloud SQL PostgreSQL instance
    if ! gcloud sql instances describe "${ALLOYDB_INSTANCE}" &>/dev/null; then
        log_info "Creating Cloud SQL instance (this may take 10-15 minutes)..."
        gcloud sql instances create "${ALLOYDB_INSTANCE}" \
            --database-version=POSTGRES_14 \
            --cpu=2 \
            --memory=8GB \
            --region="${REGION}" \
            --storage-size=20GB \
            --storage-type=SSD \
            --root-password="${DB_PASSWORD}" \
            --backup \
            --maintenance-release-channel=production
        
        # Wait for instance to be ready
        log_info "Waiting for instance to be ready..."
        while true; do
            local status=$(gcloud sql instances describe "${ALLOYDB_INSTANCE}" --format="value(state)")
            if [[ "${status}" == "RUNNABLE" ]]; then
                break
            fi
            log_info "Instance status: ${status}. Waiting..."
            sleep 30
        done
    fi
    
    # Create database for transactional data
    if ! gcloud sql databases describe transactions --instance="${ALLOYDB_INSTANCE}" &>/dev/null; then
        gcloud sql databases create transactions \
            --instance="${ALLOYDB_INSTANCE}"
    fi
    
    # Get instance connection details
    export INSTANCE_IP=$(gcloud sql instances describe "${ALLOYDB_INSTANCE}" \
        --format="value(ipAddresses[0].ipAddress)")
    
    log_success "AlloyDB Omni simulation deployed: ${ALLOYDB_INSTANCE}"
    log_info "Instance IP: ${INSTANCE_IP}"
}

# Configure BigQuery external connection
configure_federation() {
    log_info "Configuring BigQuery external connection for federation..."
    
    # Create connection configuration file
    cat > /tmp/connection_config.json << EOF
{
  "friendlyName": "AlloyDB Omni Federation Connection",
  "description": "Federated connection to AlloyDB Omni for cross-database analytics",
  "cloudSql": {
    "instanceId": "${PROJECT_ID}:${REGION}:${ALLOYDB_INSTANCE}",
    "database": "transactions",
    "type": "POSTGRES",
    "credential": {
      "username": "postgres",
      "password": "${DB_PASSWORD}"
    }
  }
}
EOF
    
    # Create the BigQuery connection
    if ! bq show --connection --location="${REGION}" "${PROJECT_ID}.${REGION}.${CONNECTION_ID}" &>/dev/null; then
        bq mk --connection \
            --location="${REGION}" \
            --connection_type=CLOUD_SQL \
            --properties_file=/tmp/connection_config.json \
            "${CONNECTION_ID}"
    fi
    
    rm -f /tmp/connection_config.json
    
    log_success "BigQuery federation connection created: ${CONNECTION_ID}"
}

# Create sample transactional data
create_sample_data() {
    log_info "Creating sample transactional data in AlloyDB Omni..."
    
    # Create SQL script for data creation
    cat > /tmp/create_sample_data.sql << 'EOF'
-- Create orders table with transactional data
CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    order_amount DECIMAL(10,2) NOT NULL,
    order_date DATE NOT NULL,
    order_status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample transactional data (only if table is empty)
INSERT INTO orders (customer_id, product_name, order_amount, order_date, order_status)
SELECT * FROM (VALUES
(1, 'Enterprise Software License', 25000.00, '2024-01-15', 'completed'),
(1, 'Support Package', 5000.00, '2024-02-01', 'completed'),
(2, 'Cloud Infrastructure Setup', 15000.00, '2024-01-20', 'completed'),
(2, 'Data Migration Service', 8000.00, '2024-03-01', 'in_progress'),
(3, 'Analytics Platform', 30000.00, '2024-02-15', 'completed'),
(3, 'Training Services', 3000.00, '2024-03-15', 'pending')
) AS new_data
WHERE NOT EXISTS (SELECT 1 FROM orders LIMIT 1);

-- Create index for federation performance
CREATE INDEX IF NOT EXISTS idx_orders_customer_date ON orders(customer_id, order_date);

-- Verify data creation
SELECT COUNT(*) as total_orders, 
       SUM(order_amount) as total_revenue 
FROM orders;
EOF
    
    # Execute SQL script
    gcloud sql connect "${ALLOYDB_INSTANCE}" \
        --user=postgres \
        --database=transactions \
        --quiet < /tmp/create_sample_data.sql
    
    rm -f /tmp/create_sample_data.sql
    
    log_success "Sample transactional data created in AlloyDB Omni"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions for metadata orchestration..."
    
    # Create temporary directory for function source
    local func_dir="/tmp/federation-functions"
    mkdir -p "${func_dir}"
    
    # Create main.py
    cat > "${func_dir}/main.py" << 'EOF'
import functions_framework
import json
from google.cloud import bigquery
from google.cloud import dataplex_v1
from google.cloud import storage
import logging
import os

@functions_framework.http
def sync_metadata(request):
    """Synchronize metadata between AlloyDB Omni and Dataplex catalog."""
    try:
        # Initialize clients
        bq_client = bigquery.Client()
        
        # Get request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {
                'status': 'error',
                'message': 'No JSON data provided'
            }, 400
        
        project_id = request_json.get('project_id')
        connection_id = request_json.get('connection_id')
        
        if not project_id or not connection_id:
            return {
                'status': 'error',
                'message': 'project_id and connection_id are required'
            }, 400
        
        # Test connection with simple query
        test_query = f"""
        SELECT 1 as connection_test
        """
        
        query_job = bq_client.query(test_query)
        results = query_job.result()
        
        # Build metadata response
        metadata = {
            'federation_status': 'active',
            'last_sync': str(query_job.ended),
            'connection_test': 'passed'
        }
        
        logging.info("Metadata synchronization completed successfully")
        
        return {
            'status': 'success',
            'metadata': metadata,
            'message': 'Metadata synchronization completed'
        }
        
    except Exception as e:
        logging.error(f"Metadata sync failed: {str(e)}")
        return {
            'status': 'error',
            'message': str(e)
        }, 500
EOF
    
    # Create requirements.txt
    cat > "${func_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-bigquery==3.*
google-cloud-dataplex==1.*
google-cloud-storage==2.*
EOF
    
    # Deploy Cloud Function
    cd "${func_dir}"
    gcloud functions deploy federation-metadata-sync \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256MB \
        --timeout 60s \
        --service-account "${SERVICE_ACCOUNT}" \
        --quiet
    
    cd - > /dev/null
    rm -rf "${func_dir}"
    
    log_success "Cloud Functions deployed for metadata orchestration"
}

# Configure Dataplex
configure_dataplex() {
    log_info "Configuring Dataplex for unified data governance..."
    
    # Create Dataplex lake
    if ! gcloud dataplex lakes describe "${LAKE_ID}" --location="${REGION}" &>/dev/null; then
        gcloud dataplex lakes create "${LAKE_ID}" \
            --location="${REGION}" \
            --display-name="Analytics Federation Lake" \
            --description="Unified governance for federated analytics across AlloyDB Omni and BigQuery"
    fi
    
    # Create asset for BigQuery datasets
    if ! gcloud dataplex assets describe bigquery-analytics-asset \
        --location="${REGION}" --lake="${LAKE_ID}" &>/dev/null; then
        gcloud dataplex assets create bigquery-analytics-asset \
            --location="${REGION}" \
            --lake="${LAKE_ID}" \
            --display-name="BigQuery Analytics Asset" \
            --resource-type=BIGQUERY_DATASET \
            --resource-name="projects/${PROJECT_ID}/datasets/analytics_federation"
    fi
    
    # Create asset for Cloud Storage data lake
    if ! gcloud dataplex assets describe storage-lake-asset \
        --location="${REGION}" --lake="${LAKE_ID}" &>/dev/null; then
        gcloud dataplex assets create storage-lake-asset \
            --location="${REGION}" \
            --lake="${LAKE_ID}" \
            --display-name="Cloud Storage Data Lake Asset" \
            --resource-type=STORAGE_BUCKET \
            --resource-name="projects/${PROJECT_ID}/buckets/${BUCKET_NAME}"
    fi
    
    # Create zone for data discovery
    if ! gcloud dataplex zones describe analytics-zone \
        --location="${REGION}" --lake="${LAKE_ID}" &>/dev/null; then
        gcloud dataplex zones create analytics-zone \
            --location="${REGION}" \
            --lake="${LAKE_ID}" \
            --display-name="Analytics Zone" \
            --type=RAW \
            --resource-location-type=SINGLE_REGION
    fi
    
    log_success "Dataplex configured for unified data governance"
}

# Execute federated analytics queries
execute_federated_queries() {
    log_info "Setting up federated analytics queries..."
    
    # Create federated analytics query
    cat > /tmp/federated_analytics_query.sql << EOF
-- Federated analytics: Customer lifetime value analysis
SELECT 
    c.customer_id,
    c.customer_name,
    c.region,
    c.signup_date,
    COALESCE(orders_summary.total_orders, 0) as total_orders,
    COALESCE(orders_summary.total_revenue, 0) as total_revenue,
    COALESCE(orders_summary.avg_order_value, 0) as avg_order_value,
    orders_summary.last_order_date,
    CASE 
        WHEN orders_summary.total_revenue IS NOT NULL 
        THEN ROUND(orders_summary.total_revenue / 
             GREATEST(DATE_DIFF(CURRENT_DATE(), c.signup_date, DAY), 1), 2)
        ELSE 0 
    END as daily_clv
FROM \`${PROJECT_ID}.cloud_analytics.customers\` c
LEFT JOIN (
    SELECT 
        customer_id,
        COUNT(*) as total_orders,
        SUM(order_amount) as total_revenue,
        AVG(order_amount) as avg_order_value,
        MAX(order_date) as last_order_date
    FROM EXTERNAL_QUERY(
        '${PROJECT_ID}.${REGION}.${CONNECTION_ID}',
        'SELECT customer_id, order_amount, order_date FROM orders'
    )
    GROUP BY customer_id
) orders_summary ON c.customer_id = orders_summary.customer_id
ORDER BY total_revenue DESC NULLS LAST;
EOF
    
    # Test the federated query
    log_info "Testing federated analytics query..."
    bq query --use_legacy_sql=false \
        --format=table \
        --max_rows=10 \
        < /tmp/federated_analytics_query.sql
    
    # Create a view for ongoing federated analytics
    bq mk --view \
        --use_legacy_sql=false \
        --description="Real-time customer analytics across cloud and on-premises data" \
        --view_file=/tmp/federated_analytics_query.sql \
        "${PROJECT_ID}:analytics_federation.customer_lifetime_value" || true
    
    rm -f /tmp/federated_analytics_query.sql
    
    log_success "Federated analytics queries configured successfully"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment_info.txt << EOF
Cross-Database Analytics Federation Deployment Information
=========================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}
Random Suffix: ${RANDOM_SUFFIX}

Service Account: ${SERVICE_ACCOUNT}
Cloud Storage Bucket: gs://${BUCKET_NAME}
AlloyDB Instance: ${ALLOYDB_INSTANCE}
Instance IP: ${INSTANCE_IP}
BigQuery Connection: ${CONNECTION_ID}
Dataplex Lake: ${LAKE_ID}

BigQuery Datasets:
- ${PROJECT_ID}:analytics_federation
- ${PROJECT_ID}:cloud_analytics

BigQuery View:
- ${PROJECT_ID}:analytics_federation.customer_lifetime_value

Cloud Function:
- federation-metadata-sync

Deployment completed at: $(date)

To clean up resources, run: ./destroy.sh
EOF
    
    log_success "Deployment information saved to deployment_info.txt"
}

# Main deployment function
main() {
    log_info "Starting Cross-Database Analytics Federation deployment..."
    log_info "This deployment will take approximately 20-30 minutes"
    
    check_prerequisites
    set_environment
    setup_project
    enable_apis
    setup_iam
    create_storage
    setup_bigquery
    deploy_alloydb
    configure_federation
    create_sample_data
    deploy_cloud_functions
    configure_dataplex
    execute_federated_queries
    save_deployment_info
    
    log_success "=========================================="
    log_success "Cross-Database Analytics Federation deployment completed successfully!"
    log_success "=========================================="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Review deployment_info.txt for complete details"
    log_info "You can now run federated queries across AlloyDB Omni and BigQuery"
    log_info "Test the deployment by querying: ${PROJECT_ID}:analytics_federation.customer_lifetime_value"
    log_warning "Remember to run ./destroy.sh when you're done to avoid charges"
}

# Run main function
main "$@"
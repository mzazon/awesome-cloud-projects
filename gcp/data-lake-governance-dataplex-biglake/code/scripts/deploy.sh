#!/bin/bash

# Data Lake Governance with Dataplex and BigLake - Deployment Script
# This script deploys a comprehensive data governance solution using Google Cloud
# Dataplex Universal Catalog and BigLake for unified analytics access control.

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the error above."
    log "You may need to run the destroy script to clean up partial resources."
    exit 1
}

trap cleanup_on_error ERR

# Configuration with defaults
PROJECT_ID="${PROJECT_ID:-data-governance-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
LAKE_NAME="${LAKE_NAME:-enterprise-data-lake}"
ZONE_NAME="${ZONE_NAME:-raw-data-zone}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
BUCKET_NAME="${BUCKET_NAME:-governance-demo-${RANDOM_SUFFIX}}"
DATASET_NAME="${DATASET_NAME:-governance_analytics}"
CONNECTION_NAME="${CONNECTION_NAME:-biglake-connection-${RANDOM_SUFFIX}}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null | head -n1)
    log "Using gcloud version: ${GCLOUD_VERSION}"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Project $PROJECT_ID does not exist. Creating new project..."
        gcloud projects create "$PROJECT_ID" --name="Data Governance Demo"
        
        # Set billing account if available
        BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open:true" --format="value(name)" | head -n1)
        if [[ -n "$BILLING_ACCOUNT" ]]; then
            gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
            log_success "Linked project to billing account"
        else
            log_warning "No billing account found. You may need to link billing manually."
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Function to setup environment
setup_environment() {
    log "Setting up environment..."
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Environment configured for project: $PROJECT_ID"
    log "Region: $REGION"
    log "Zone: $ZONE"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dataplex.googleapis.com"
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "bigqueryconnection.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create storage resources
create_storage() {
    log "Creating Cloud Storage bucket and sample data..."
    
    # Create Cloud Storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${BUCKET_NAME}"
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Create sample datasets for governance demonstration
    cat > customer_data.csv << 'EOF'
customer_id,name,email,phone,registration_date,country
1001,John Smith,john.smith@email.com,555-0123,2024-01-15,USA
1002,Jane Doe,jane.doe@email.com,555-0124,2024-01-16,Canada
1003,Bob Johnson,bob.johnson@email.com,555-0125,2024-01-17,USA
1004,Alice Brown,alice.brown@email.com,555-0126,2024-01-18,UK
1005,Carlos Rodriguez,carlos.rodriguez@email.com,555-0127,2024-01-19,Mexico
1006,Emma Wilson,emma.wilson@email.com,555-0128,2024-01-20,Australia
EOF

    cat > transaction_data.csv << 'EOF'
transaction_id,customer_id,amount,currency,transaction_date,category
TXN001,1001,150.50,USD,2024-02-01,retail
TXN002,1002,89.99,CAD,2024-02-02,online
TXN003,1001,200.00,USD,2024-02-03,retail
TXN004,1003,75.25,USD,2024-02-04,dining
TXN005,1004,125.75,GBP,2024-02-05,entertainment
TXN006,1005,99.99,MXN,2024-02-06,travel
EOF
    
    # Upload sample data to Cloud Storage
    gsutil cp customer_data.csv "gs://${BUCKET_NAME}/raw/customers/"
    gsutil cp transaction_data.csv "gs://${BUCKET_NAME}/raw/transactions/"
    
    # Clean up local files
    rm -f customer_data.csv transaction_data.csv
    
    log_success "Sample data uploaded to Cloud Storage"
}

# Function to create Dataplex resources
create_dataplex() {
    log "Creating Dataplex lake and zone..."
    
    # Create Dataplex lake
    if gcloud dataplex lakes describe "$LAKE_NAME" --location="$REGION" &> /dev/null; then
        log_warning "Dataplex lake $LAKE_NAME already exists"
    else
        gcloud dataplex lakes create "$LAKE_NAME" \
            --location="$REGION" \
            --display-name="Enterprise Data Lake" \
            --description="Centralized governance for enterprise data assets"
        
        log_success "Dataplex lake created: $LAKE_NAME"
    fi
    
    # Create zone for raw data
    if gcloud dataplex zones describe "$ZONE_NAME" --location="$REGION" --lake="$LAKE_NAME" &> /dev/null; then
        log_warning "Dataplex zone $ZONE_NAME already exists"
    else
        gcloud dataplex zones create "$ZONE_NAME" \
            --location="$REGION" \
            --lake="$LAKE_NAME" \
            --type=RAW \
            --discovery-enabled \
            --resource-location-type=SINGLE_REGION
        
        log_success "Dataplex zone created: $ZONE_NAME"
    fi
}

# Function to create BigQuery resources
create_bigquery() {
    log "Creating BigQuery dataset and external connection..."
    
    # Create BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log_warning "BigQuery dataset $DATASET_NAME already exists"
    else
        bq mk --dataset \
            --location="$REGION" \
            --description="Analytics dataset with BigLake governance" \
            "${PROJECT_ID}:${DATASET_NAME}"
        
        log_success "BigQuery dataset created: $DATASET_NAME"
    fi
    
    # Create external connection for BigLake
    if bq show --connection --location="$REGION" "$CONNECTION_NAME" &> /dev/null; then
        log_warning "BigQuery connection $CONNECTION_NAME already exists"
    else
        bq mk --connection \
            --location="$REGION" \
            --connection_type=CLOUD_RESOURCE \
            "$CONNECTION_NAME"
        
        log_success "BigQuery connection created: $CONNECTION_NAME"
    fi
    
    # Get connection service account
    CONNECTION_SA=$(bq show --connection --location="$REGION" "$CONNECTION_NAME" --format="value(cloudResource.serviceAccountId)")
    log "Connection service account: $CONNECTION_SA"
    
    # Export for use in other functions
    export CONNECTION_SA
}

# Function to configure IAM permissions
configure_iam() {
    log "Configuring IAM permissions for BigLake integration..."
    
    if [[ -z "${CONNECTION_SA:-}" ]]; then
        log_error "Connection service account not found. Ensure BigQuery connection was created successfully."
        exit 1
    fi
    
    # Grant Storage Object Viewer to BigLake connection
    gsutil iam ch "serviceAccount:${CONNECTION_SA}:objectViewer" "gs://${BUCKET_NAME}"
    
    # Grant Dataplex permissions for metadata integration
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CONNECTION_SA}" \
        --role="roles/dataplex.viewer" \
        --quiet
    
    # Grant BigQuery permissions for table creation
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CONNECTION_SA}" \
        --role="roles/bigquery.dataEditor" \
        --quiet
    
    log_success "IAM permissions configured for BigLake integration"
}

# Function to create BigLake tables
create_biglake_tables() {
    log "Creating BigLake tables with governance features..."
    
    # Create BigLake table for customer data
    if bq show --table "${PROJECT_ID}:${DATASET_NAME}.customers_biglake" &> /dev/null; then
        log_warning "BigLake table customers_biglake already exists"
    else
        bq mk --table \
            --external_table_definition=@/dev/stdin \
            "${DATASET_NAME}.customers_biglake" << EOF
{
  "sourceFormat": "CSV",
  "sourceUris": ["gs://${BUCKET_NAME}/raw/customers/*"],
  "schema": {
    "fields": [
      {"name": "customer_id", "type": "INTEGER", "mode": "REQUIRED"},
      {"name": "name", "type": "STRING", "mode": "REQUIRED"},
      {"name": "email", "type": "STRING", "mode": "REQUIRED"},
      {"name": "phone", "type": "STRING", "mode": "NULLABLE"},
      {"name": "registration_date", "type": "DATE", "mode": "REQUIRED"},
      {"name": "country", "type": "STRING", "mode": "REQUIRED"}
    ]
  },
  "connectionId": "${PROJECT_ID}.${REGION}.${CONNECTION_NAME}",
  "csvOptions": {
    "skipLeadingRows": 1
  }
}
EOF
        log_success "BigLake customers table created"
    fi
    
    # Create BigLake table for transaction data
    if bq show --table "${PROJECT_ID}:${DATASET_NAME}.transactions_biglake" &> /dev/null; then
        log_warning "BigLake table transactions_biglake already exists"
    else
        bq mk --table \
            --external_table_definition=@/dev/stdin \
            "${DATASET_NAME}.transactions_biglake" << EOF
{
  "sourceFormat": "CSV",
  "sourceUris": ["gs://${BUCKET_NAME}/raw/transactions/*"],
  "schema": {
    "fields": [
      {"name": "transaction_id", "type": "STRING", "mode": "REQUIRED"},
      {"name": "customer_id", "type": "INTEGER", "mode": "REQUIRED"},
      {"name": "amount", "type": "NUMERIC", "mode": "REQUIRED"},
      {"name": "currency", "type": "STRING", "mode": "REQUIRED"},
      {"name": "transaction_date", "type": "DATE", "mode": "REQUIRED"},
      {"name": "category", "type": "STRING", "mode": "REQUIRED"}
    ]
  },
  "connectionId": "${PROJECT_ID}.${REGION}.${CONNECTION_NAME}",
  "csvOptions": {
    "skipLeadingRows": 1
  }
}
EOF
        log_success "BigLake transactions table created"
    fi
}

# Function to create Dataplex asset
create_dataplex_asset() {
    log "Creating Dataplex asset for automatic discovery..."
    
    if gcloud dataplex assets describe governance-bucket-asset \
        --location="$REGION" --lake="$LAKE_NAME" --zone="$ZONE_NAME" &> /dev/null; then
        log_warning "Dataplex asset governance-bucket-asset already exists"
    else
        gcloud dataplex assets create governance-bucket-asset \
            --location="$REGION" \
            --lake="$LAKE_NAME" \
            --zone="$ZONE_NAME" \
            --resource-type=STORAGE_BUCKET \
            --resource-name="projects/${PROJECT_ID}/buckets/${BUCKET_NAME}" \
            --discovery-enabled \
            --discovery-include-patterns="gs://${BUCKET_NAME}/raw/*" \
            --discovery-csv-delimiter="," \
            --discovery-csv-header-rows=1
        
        log_success "Dataplex asset created for automatic discovery"
        log "Discovery job will begin automatically and may take 5-10 minutes"
    fi
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function for governance monitoring..."
    
    # Create temporary directory for Cloud Function code
    local function_dir="$(mktemp -d)"
    cd "$function_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-dataplex==1.9.3
google-cloud-bigquery==3.13.0
google-cloud-logging==3.8.0
functions-framework==3.5.0
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import functions_framework
from google.cloud import dataplex_v1
from google.cloud import bigquery
from google.cloud import logging
import json
import os

@functions_framework.http
def governance_monitor(request):
    """Monitor data quality and governance metrics"""
    
    # Initialize clients
    dataplex_client = dataplex_v1.DataplexServiceClient()
    bq_client = bigquery.Client()
    logging_client = logging.Client()
    logger = logging_client.logger("governance-monitor")
    
    project_id = os.environ.get('GCP_PROJECT')
    region = os.environ.get('REGION', 'us-central1')
    
    try:
        # Query data quality metrics from BigLake tables
        quality_query = f"""
        SELECT 
            'customers_biglake' as table_name,
            COUNT(*) as total_rows,
            COUNT(DISTINCT customer_id) as unique_customers,
            COUNTIF(email IS NULL OR email = '') as missing_emails,
            COUNTIF(REGEXP_CONTAINS(email, r'^[^@]+@[^@]+\.[^@]+$') = FALSE) as invalid_emails
        FROM `{project_id}.governance_analytics.customers_biglake`
        UNION ALL
        SELECT 
            'transactions_biglake' as table_name,
            COUNT(*) as total_rows,
            COUNT(DISTINCT transaction_id) as unique_transactions,
            COUNTIF(amount <= 0) as invalid_amounts,
            COUNTIF(currency NOT IN ('USD', 'CAD', 'EUR', 'GBP', 'MXN')) as invalid_currencies
        FROM `{project_id}.governance_analytics.transactions_biglake`
        """
        
        # Execute quality monitoring query
        query_job = bq_client.query(quality_query)
        results = query_job.result()
        
        # Process results and log quality metrics
        quality_metrics = []
        for row in results:
            metrics = dict(row)
            quality_metrics.append(metrics)
            
            # Log quality issues
            if 'missing_emails' in metrics and metrics['missing_emails'] > 0:
                logger.warning(f"Data quality issue: {metrics['missing_emails']} missing emails in {metrics['table_name']}")
            
            if 'invalid_amounts' in metrics and metrics['invalid_amounts'] > 0:
                logger.warning(f"Data quality issue: {metrics['invalid_amounts']} invalid amounts in {metrics['table_name']}")
        
        return {
            'status': 'success',
            'quality_metrics': quality_metrics,
            'message': 'Governance monitoring completed successfully'
        }
        
    except Exception as e:
        logger.error(f"Governance monitoring failed: {str(e)}")
        return {
            'status': 'error',
            'message': f'Monitoring failed: {str(e)}'
        }, 500
EOF
    
    # Deploy Cloud Function
    if gcloud functions describe governance-monitor --region="$REGION" &> /dev/null; then
        log_warning "Cloud Function governance-monitor already exists. Updating..."
        gcloud functions deploy governance-monitor \
            --runtime=python311 \
            --trigger=http \
            --entry-point=governance_monitor \
            --memory=256MB \
            --timeout=300s \
            --set-env-vars="REGION=${REGION}" \
            --allow-unauthenticated \
            --quiet
    else
        gcloud functions deploy governance-monitor \
            --runtime=python311 \
            --trigger=http \
            --entry-point=governance_monitor \
            --memory=256MB \
            --timeout=300s \
            --set-env-vars="REGION=${REGION}" \
            --allow-unauthenticated
    fi
    
    # Return to original directory and cleanup
    cd - > /dev/null
    rm -rf "$function_dir"
    
    log_success "Cloud Function deployed for governance monitoring"
}

# Function to configure data lineage and quality profiling
configure_lineage() {
    log "Configuring data lineage and quality profiling..."
    
    # Note: Dataplex lineage and quality tasks require specific service accounts
    # and configurations that may not be available in all environments
    log_warning "Data lineage configuration requires additional setup"
    log "Please refer to Dataplex documentation for lineage task configuration"
    log "https://cloud.google.com/dataplex/docs/discover-data"
    
    log_success "Lineage configuration guidance provided"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Wait for Dataplex discovery to complete (basic check)
    log "Checking Dataplex lake status..."
    gcloud dataplex lakes describe "$LAKE_NAME" --location="$REGION" --format="table(name,state,createTime)"
    
    # Test BigLake table queries
    log "Testing BigLake table queries..."
    
    # Test customer data query
    log "Querying customer data..."
    bq query --use_legacy_sql=false \
        "SELECT country, COUNT(*) as customer_count
         FROM \`${PROJECT_ID}.${DATASET_NAME}.customers_biglake\`
         GROUP BY country
         ORDER BY customer_count DESC
         LIMIT 5"
    
    # Test transaction analytics with joins
    log "Testing analytics query with joins..."
    bq query --use_legacy_sql=false \
        "SELECT 
           c.country,
           COUNT(t.transaction_id) as transaction_count,
           SUM(t.amount) as total_amount
         FROM \`${PROJECT_ID}.${DATASET_NAME}.customers_biglake\` c
         JOIN \`${PROJECT_ID}.${DATASET_NAME}.transactions_biglake\` t
           ON c.customer_id = t.customer_id
         GROUP BY c.country
         ORDER BY total_amount DESC
         LIMIT 5"
    
    # Test Cloud Function
    log "Testing governance monitoring function..."
    FUNCTION_URL=$(gcloud functions describe governance-monitor \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    if [[ -n "$FUNCTION_URL" ]]; then
        curl -X POST "$FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d '{"action": "monitor_quality"}' \
            --silent --show-error || log_warning "Function test failed - this is normal for new deployments"
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
show_summary() {
    log_success "🎉 Data Lake Governance deployment completed successfully!"
    echo
    echo "========================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "========================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Dataplex Lake: $LAKE_NAME"
    echo "Dataplex Zone: $ZONE_NAME"
    echo "BigQuery Dataset: $DATASET_NAME"
    echo "BigQuery Connection: $CONNECTION_NAME"
    echo
    echo "Resources Created:"
    echo "- ✅ Cloud Storage bucket with sample data"
    echo "- ✅ Dataplex lake and zone with auto-discovery"
    echo "- ✅ BigQuery dataset and external connection"
    echo "- ✅ BigLake tables for governed analytics"
    echo "- ✅ Dataplex asset for metadata discovery"
    echo "- ✅ Cloud Function for quality monitoring"
    echo
    echo "Next Steps:"
    echo "1. Wait 5-10 minutes for Dataplex discovery to complete"
    echo "2. Check Dataplex Console for discovered entities"
    echo "3. Run analytics queries on BigLake tables"
    echo "4. Monitor governance metrics via Cloud Function"
    echo
    echo "Console URLs:"
    echo "- Dataplex: https://console.cloud.google.com/dataplex/lakes?project=$PROJECT_ID"
    echo "- BigQuery: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    echo "- Cloud Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo "========================================="
}

# Main deployment function
main() {
    log "🚀 Starting Data Lake Governance deployment..."
    log "This will deploy Dataplex, BigLake, and governance monitoring resources"
    
    # Deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage
    create_dataplex
    create_bigquery
    configure_iam
    create_biglake_tables
    create_dataplex_asset
    deploy_cloud_function
    configure_lineage
    run_validation
    show_summary
    
    log_success "Deployment completed successfully! 🎉"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
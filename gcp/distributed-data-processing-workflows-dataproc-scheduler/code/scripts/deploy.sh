#!/bin/bash

# Deploy script for Distributed Data Processing Workflows with Cloud Dataproc and Cloud Scheduler
# This script automates the deployment of a complete data processing pipeline

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    log_info "Run './destroy.sh' to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Configuration validation
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites validated successfully"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-dataproc-workflow-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-dataproc-data-${RANDOM_SUFFIX}}"
    export STAGING_BUCKET="${STAGING_BUCKET:-dataproc-staging-${RANDOM_SUFFIX}}"
    export DATASET_NAME="${DATASET_NAME:-analytics_results}"
    export WORKFLOW_NAME="${WORKFLOW_NAME:-sales-analytics-workflow}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-dataproc-scheduler}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-sales-analytics-daily}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Data Bucket: ${BUCKET_NAME}"
    log_info "Staging Bucket: ${STAGING_BUCKET}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment configured successfully"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dataproc.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
        "bigquery.googleapis.com"
        "compute.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    # Create main data bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" 2>/dev/null; then
        log_success "Created data bucket: gs://${BUCKET_NAME}"
    else
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_warning "Data bucket already exists: gs://${BUCKET_NAME}"
        else
            log_error "Failed to create data bucket: gs://${BUCKET_NAME}"
            exit 1
        fi
    fi
    
    # Create staging bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${STAGING_BUCKET}" 2>/dev/null; then
        log_success "Created staging bucket: gs://${STAGING_BUCKET}"
    else
        if gsutil ls "gs://${STAGING_BUCKET}" &>/dev/null; then
            log_warning "Staging bucket already exists: gs://${STAGING_BUCKET}"
        else
            log_error "Failed to create staging bucket: gs://${STAGING_BUCKET}"
            exit 1
        fi
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    gsutil versioning set on "gs://${STAGING_BUCKET}"
    
    log_success "Storage buckets created and configured"
}

# Create and upload sample data
create_sample_data() {
    log_info "Creating and uploading sample data..."
    
    # Create temporary directory for sample data
    local temp_dir=$(mktemp -d)
    local sales_file="${temp_dir}/sales_data.csv"
    
    cat > "${sales_file}" << 'EOF'
transaction_id,customer_id,product_id,product_name,category,quantity,unit_price,transaction_date,region
T001,C001,P001,Laptop Pro,Electronics,2,1299.99,2024-01-15,North
T002,C002,P002,Coffee Maker,Appliances,1,89.99,2024-01-15,South
T003,C003,P003,Running Shoes,Sports,1,129.99,2024-01-16,East
T004,C001,P004,Wireless Mouse,Electronics,3,29.99,2024-01-16,North
T005,C004,P005,Yoga Mat,Sports,2,49.99,2024-01-17,West
T006,C005,P001,Laptop Pro,Electronics,1,1299.99,2024-01-17,South
T007,C002,P006,Blender,Appliances,1,199.99,2024-01-18,South
T008,C006,P003,Running Shoes,Sports,2,129.99,2024-01-18,East
T009,C007,P007,Gaming Chair,Furniture,1,399.99,2024-01-19,North
T010,C003,P008,Desk Lamp,Furniture,1,79.99,2024-01-19,East
EOF
    
    # Upload sample data to Cloud Storage
    if gsutil cp "${sales_file}" "gs://${BUCKET_NAME}/input/"; then
        log_success "Sample data uploaded to gs://${BUCKET_NAME}/input/"
    else
        log_error "Failed to upload sample data"
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Cleanup temporary files
    rm -rf "${temp_dir}"
    
    log_success "Sample data created and uploaded"
}

# Create BigQuery dataset and table
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and table..."
    
    # Create BigQuery dataset
    if bq mk --location="${REGION}" --description="Sales analytics results from Dataproc processing" "${DATASET_NAME}" 2>/dev/null; then
        log_success "Created BigQuery dataset: ${DATASET_NAME}"
    else
        if bq ls -d "${DATASET_NAME}" &>/dev/null; then
            log_warning "BigQuery dataset already exists: ${DATASET_NAME}"
        else
            log_error "Failed to create BigQuery dataset: ${DATASET_NAME}"
            exit 1
        fi
    fi
    
    # Create table schema
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.sales_summary" \
        "region:STRING,category:STRING,total_sales:FLOAT,transaction_count:INTEGER,avg_order_value:FLOAT,processing_timestamp:TIMESTAMP" 2>/dev/null; then
        log_success "Created BigQuery table: sales_summary"
    else
        if bq ls "${DATASET_NAME}" | grep -q "sales_summary"; then
            log_warning "BigQuery table already exists: sales_summary"
        else
            log_error "Failed to create BigQuery table: sales_summary"
            exit 1
        fi
    fi
    
    log_success "BigQuery resources created successfully"
}

# Create and upload Spark script
create_spark_script() {
    log_info "Creating and uploading Spark processing script..."
    
    # Create temporary directory for script
    local temp_dir=$(mktemp -d)
    local spark_script="${temp_dir}/spark_sales_analysis.py"
    
    cat > "${spark_script}" << 'EOF'
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as spark_sum, count, avg, current_timestamp
import sys

def main():
    # Initialize Spark session with BigQuery connector
    spark = SparkSession.builder \
        .appName("SalesAnalyticsWorkflow") \
        .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.28.0") \
        .getOrCreate()
    
    try:
        # Read input data from Cloud Storage
        input_path = sys.argv[1] if len(sys.argv) > 1 else "gs://*/input/sales_data.csv"
        output_path = sys.argv[2] if len(sys.argv) > 2 else "gs://*/output/"
        project_id = sys.argv[3] if len(sys.argv) > 3 else "default-project"
        
        print(f"Processing data from: {input_path}")
        
        # Load sales data
        df = spark.read.option("header", "true").option("inferSchema", "true").csv(input_path)
        
        # Perform analytics aggregations
        sales_summary = df.groupBy("region", "category") \
            .agg(
                spark_sum(col("quantity") * col("unit_price")).alias("total_sales"),
                count("transaction_id").alias("transaction_count"),
                avg(col("quantity") * col("unit_price")).alias("avg_order_value")
            ) \
            .withColumn("processing_timestamp", current_timestamp())
        
        # Show sample results
        print("Sales Summary Results:")
        sales_summary.show()
        
        # Write results to Cloud Storage as Parquet
        sales_summary.write.mode("overwrite").parquet(f"{output_path}/sales_summary")
        
        # Write results to BigQuery
        sales_summary.write \
            .format("bigquery") \
            .option("table", f"{project_id}.analytics_results.sales_summary") \
            .option("writeMethod", "overwrite") \
            .save()
        
        print("✅ Processing completed successfully")
        
    except Exception as e:
        print(f"❌ Error during processing: {str(e)}")
        raise
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
EOF
    
    # Upload Spark script to Cloud Storage
    if gsutil cp "${spark_script}" "gs://${STAGING_BUCKET}/scripts/"; then
        log_success "Spark script uploaded to gs://${STAGING_BUCKET}/scripts/"
    else
        log_error "Failed to upload Spark script"
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Cleanup temporary files
    rm -rf "${temp_dir}"
    
    log_success "Spark processing script created and uploaded"
}

# Create Dataproc workflow template
create_workflow_template() {
    log_info "Creating Dataproc workflow template..."
    
    # Check if template already exists
    if gcloud dataproc workflow-templates describe "${WORKFLOW_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "Workflow template already exists. Deleting and recreating..."
        gcloud dataproc workflow-templates delete "${WORKFLOW_NAME}" --region="${REGION}" --quiet
    fi
    
    # Create the workflow template
    if gcloud dataproc workflow-templates create "${WORKFLOW_NAME}" --region="${REGION}"; then
        log_success "Created workflow template: ${WORKFLOW_NAME}"
    else
        log_error "Failed to create workflow template"
        exit 1
    fi
    
    # Configure managed ephemeral cluster
    if gcloud dataproc workflow-templates set-managed-cluster "${WORKFLOW_NAME}" \
        --region="${REGION}" \
        --cluster-name="sales-analytics-cluster" \
        --num-workers=2 \
        --worker-machine-type=e2-standard-4 \
        --worker-disk-size=50GB \
        --image-version=2.1-debian11 \
        --enable-autoscaling \
        --max-workers=4 \
        --enable-ip-alias \
        --metadata="enable-cloud-sql-hive-metastore=false"; then
        log_success "Configured managed cluster for workflow template"
    else
        log_error "Failed to configure managed cluster"
        exit 1
    fi
    
    # Add PySpark job to workflow template
    if gcloud dataproc workflow-templates add-job pyspark \
        "gs://${STAGING_BUCKET}/scripts/spark_sales_analysis.py" \
        --workflow-template="${WORKFLOW_NAME}" \
        --region="${REGION}" \
        --step-id=sales-analytics-job \
        --py-files="gs://${STAGING_BUCKET}/scripts/spark_sales_analysis.py" \
        -- "gs://${BUCKET_NAME}/input/sales_data.csv" \
           "gs://${BUCKET_NAME}/output/" \
           "${PROJECT_ID}"; then
        log_success "Added Spark job to workflow template"
    else
        log_error "Failed to add Spark job to workflow template"
        exit 1
    fi
    
    log_success "Workflow template created and configured successfully"
}

# Create service account
create_service_account() {
    log_info "Creating service account for Cloud Scheduler..."
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_warning "Service account already exists: ${sa_email}"
    else
        # Create service account
        if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --display-name="Dataproc Workflow Scheduler" \
            --description="Service account for scheduling Dataproc workflows"; then
            log_success "Created service account: ${sa_email}"
        else
            log_error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/dataproc.editor"
        "roles/storage.objectViewer"
        "roles/bigquery.dataEditor"
    )
    
    for role in "${roles[@]}"; do
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}" --quiet; then
            log_success "Granted ${role} to service account"
        else
            log_error "Failed to grant ${role} to service account"
            exit 1
        fi
    done
    
    log_success "Service account created with appropriate permissions"
}

# Create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job..."
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    local request_id=$(uuidgen 2>/dev/null || echo "req-$(date +%s)")
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
        log_warning "Scheduler job already exists. Deleting and recreating..."
        gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" --location="${REGION}" --quiet
    fi
    
    # Create Cloud Scheduler job
    if gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 2 * * *" \
        --time-zone="America/New_York" \
        --uri="https://dataproc.googleapis.com/v1/projects/${PROJECT_ID}/regions/${REGION}/workflowTemplates/${WORKFLOW_NAME}:instantiate" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --oauth-service-account-email="${sa_email}" \
        --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
        --message-body="{\"requestId\":\"${request_id}\"}" \
        --description="Daily sales analytics processing workflow"; then
        log_success "Created Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
    else
        log_error "Failed to create Cloud Scheduler job"
        exit 1
    fi
    
    log_success "Cloud Scheduler job created for daily execution at 2 AM EST"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test workflow template execution
    log_info "Executing workflow template for testing..."
    if gcloud dataproc workflow-templates instantiate "${WORKFLOW_NAME}" --region="${REGION}"; then
        log_success "Workflow template execution initiated"
        log_info "Monitor progress in Google Cloud Console: Dataproc > Workflows"
    else
        log_error "Failed to execute workflow template"
        exit 1
    fi
    
    # Wait for job completion (basic check)
    log_info "Waiting for initial job setup (60 seconds)..."
    sleep 60
    
    log_success "Deployment test completed. Check Cloud Console for detailed progress."
}

# Main deployment function
main() {
    log_info "Starting deployment of Distributed Data Processing Workflows..."
    log_info "================================================"
    
    validate_prerequisites
    setup_environment
    enable_apis
    create_storage_buckets
    create_sample_data
    create_bigquery_resources
    create_spark_script
    create_workflow_template
    create_service_account
    create_scheduler_job
    test_deployment
    
    log_success "================================================"
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "Resources created:"
    log_info "- Project ID: ${PROJECT_ID}"
    log_info "- Data Bucket: gs://${BUCKET_NAME}"
    log_info "- Staging Bucket: gs://${STAGING_BUCKET}"
    log_info "- BigQuery Dataset: ${DATASET_NAME}"
    log_info "- Workflow Template: ${WORKFLOW_NAME}"
    log_info "- Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    log_info "- Scheduler Job: ${SCHEDULER_JOB_NAME}"
    log_info ""
    log_info "Next steps:"
    log_info "1. Monitor the test workflow execution in Google Cloud Console"
    log_info "2. Check BigQuery for processed results"
    log_info "3. Verify Cloud Scheduler job is configured correctly"
    log_info "4. Run './destroy.sh' when ready to clean up resources"
}

# Run main function
main "$@"
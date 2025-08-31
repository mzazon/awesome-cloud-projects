#!/bin/bash

#############################################
# GCP BigQuery Serverless Spark Deployment Script
# 
# This script deploys a complete large-scale data processing 
# solution using BigQuery Serverless Spark, Cloud Storage,
# and data analytics components.
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID    Specify GCP project ID
#   --region REGION           Specify GCP region (default: us-central1)
#   --dry-run                 Show what would be deployed without executing
#   --verbose                 Enable verbose logging
#   --help                    Show this help message
#############################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/gcp-spark-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_NAME="$(basename "$0")"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false
VERBOSE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#############################################
# Logging Functions
#############################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

#############################################
# Utility Functions
#############################################

show_help() {
    cat << EOF
${SCRIPT_NAME} - Deploy GCP BigQuery Serverless Spark Data Processing Solution

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    --project-id PROJECT_ID    Specify GCP project ID (required)
    --region REGION           Specify GCP region (default: ${DEFAULT_REGION})
    --dry-run                 Show what would be deployed without executing
    --verbose                 Enable verbose logging
    --help                    Show this help message

EXAMPLES:
    ${SCRIPT_NAME} --project-id my-gcp-project
    ${SCRIPT_NAME} --project-id my-project --region us-west1 --verbose
    ${SCRIPT_NAME} --project-id my-project --dry-run

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and authenticated
    - BigQuery API enabled
    - Cloud Storage API enabled  
    - Dataproc API enabled
    - Appropriate IAM permissions (BigQuery Admin, Storage Admin, Dataproc Admin)

EOF
}

check_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "Required command '${cmd}' not found. Please install it first."
        exit 1
    fi
}

generate_random_suffix() {
    openssl rand -hex 3 2>/dev/null || echo "$(date +%s)"
}

check_gcp_authentication() {
    log_info "Checking GCP authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active GCP authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: ${active_account}"
}

check_gcp_project() {
    local project_id="$1"
    
    log_info "Validating GCP project: ${project_id}"
    
    if ! gcloud projects describe "${project_id}" &>/dev/null; then
        log_error "Project '${project_id}' not found or not accessible"
        exit 1
    fi
    
    log_success "Project validation successful: ${project_id}"
}

enable_apis() {
    local project_id="$1"
    
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigquery.googleapis.com"
        "storage.googleapis.com" 
        "dataproc.googleapis.com"
        "notebooks.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would enable API: ${api}"
        else
            log_info "Enabling API: ${api}"
            if gcloud services enable "${api}" --project="${project_id}"; then
                log_success "API enabled: ${api}"
            else
                log_error "Failed to enable API: ${api}"
                exit 1
            fi
        fi
    done
}

wait_for_operation() {
    local operation_name="$1"
    local max_wait="${2:-300}"  # Default 5 minutes
    local wait_interval="${3:-10}"  # Default 10 seconds
    
    log_info "Waiting for operation to complete: ${operation_name}"
    
    local elapsed=0
    while [[ ${elapsed} -lt ${max_wait} ]]; do
        if gcloud dataproc batches describe "${operation_name}" \
           --region="${REGION}" \
           --format="value(state)" 2>/dev/null | grep -E "(SUCCEEDED|FAILED|CANCELLED)" > /dev/null; then
            break
        fi
        
        log_info "Operation still running... (${elapsed}s elapsed)"
        sleep "${wait_interval}"
        elapsed=$((elapsed + wait_interval))
    done
    
    local final_state=$(gcloud dataproc batches describe "${operation_name}" \
                       --region="${REGION}" \
                       --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${final_state}" == "SUCCEEDED" ]]; then
        log_success "Operation completed successfully: ${operation_name}"
        return 0
    else
        log_error "Operation failed or timed out: ${operation_name} (State: ${final_state})"
        return 1
    fi
}

#############################################
# Deployment Functions
#############################################

create_storage_bucket() {
    local bucket_name="$1"
    local project_id="$2"
    local region="$3"
    
    log_info "Creating Cloud Storage bucket: gs://${bucket_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create bucket: gs://${bucket_name}"
        return 0
    fi
    
    # Check if bucket already exists
    if gsutil ls "gs://${bucket_name}" &>/dev/null; then
        log_warning "Bucket already exists: gs://${bucket_name}"
        return 0
    fi
    
    # Create bucket
    if gsutil mb -p "${project_id}" -c STANDARD -l "${region}" "gs://${bucket_name}"; then
        log_success "Created bucket: gs://${bucket_name}"
    else
        log_error "Failed to create bucket: gs://${bucket_name}"
        exit 1
    fi
    
    # Enable versioning
    log_info "Enabling versioning on bucket: gs://${bucket_name}"
    if gsutil versioning set on "gs://${bucket_name}"; then
        log_success "Versioning enabled on bucket"
    else
        log_warning "Failed to enable versioning (non-critical)"
    fi
    
    # Create folder structure
    log_info "Creating folder structure in bucket"
    local folders=("raw-data" "processed-data" "scripts")
    
    for folder in "${folders[@]}"; do
        if gsutil -m cp /dev/null "gs://${bucket_name}/${folder}/.gitkeep" 2>/dev/null; then
            log_info "Created folder: ${folder}/"
        else
            log_warning "Failed to create folder marker: ${folder}/"
        fi
    done
}

upload_sample_data() {
    local bucket_name="$1"
    local script_dir="$2"
    
    log_info "Uploading sample dataset to Cloud Storage"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would upload sample data to gs://${bucket_name}/raw-data/"
        return 0
    fi
    
    # Create sample transactions data
    local sample_file="${script_dir}/../sample_data/sample_transactions.csv"
    
    if [[ ! -f "${sample_file}" ]]; then
        log_info "Creating sample transactions data file"
        mkdir -p "$(dirname "${sample_file}")"
        
        cat > "${sample_file}" << 'EOF'
transaction_id,customer_id,product_id,product_category,quantity,unit_price,transaction_date,store_location
TXN001,CUST001,PROD001,Electronics,2,299.99,2024-01-15,New York
TXN002,CUST002,PROD002,Clothing,1,89.50,2024-01-15,Los Angeles
TXN003,CUST001,PROD003,Electronics,1,1299.99,2024-01-16,New York
TXN004,CUST003,PROD004,Home,3,45.00,2024-01-16,Chicago
TXN005,CUST002,PROD001,Electronics,1,299.99,2024-01-17,Los Angeles
TXN006,CUST004,PROD005,Clothing,2,125.00,2024-01-17,Miami
TXN007,CUST003,PROD002,Clothing,4,89.50,2024-01-18,Chicago
TXN008,CUST005,PROD006,Electronics,1,899.99,2024-01-18,Seattle
TXN009,CUST001,PROD007,Home,2,67.50,2024-01-19,New York
TXN010,CUST004,PROD003,Electronics,1,1299.99,2024-01-19,Miami
TXN011,CUST006,PROD008,Electronics,3,450.00,2024-01-20,Boston
TXN012,CUST007,PROD009,Clothing,1,75.99,2024-01-20,Denver
TXN013,CUST008,PROD010,Home,2,120.50,2024-01-21,Atlanta
TXN014,CUST002,PROD004,Home,1,45.00,2024-01-21,Los Angeles
TXN015,CUST009,PROD011,Electronics,1,2199.99,2024-01-22,San Francisco
EOF
    fi
    
    # Upload sample data
    if gsutil cp "${sample_file}" "gs://${bucket_name}/raw-data/"; then
        log_success "Sample data uploaded successfully"
    else
        log_error "Failed to upload sample data"
        exit 1
    fi
    
    # Verify upload
    log_info "Verifying data upload"
    if gsutil ls -la "gs://${bucket_name}/raw-data/sample_transactions.csv" &>/dev/null; then
        log_success "Data upload verification successful"
    else
        log_error "Data upload verification failed"
        exit 1
    fi
}

create_bigquery_dataset() {
    local dataset_name="$1"
    local project_id="$2"
    local region="$3"
    
    log_info "Creating BigQuery dataset: ${dataset_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create BigQuery dataset: ${dataset_name}"
        return 0
    fi
    
    # Check if dataset already exists
    if bq ls --project_id="${project_id}" | grep -q "${dataset_name}"; then
        log_warning "Dataset already exists: ${dataset_name}"
        return 0
    fi
    
    # Create dataset
    if bq mk --location="${region}" \
         --description="Analytics dataset for Serverless Spark processing" \
         "${project_id}:${dataset_name}"; then
        log_success "Created BigQuery dataset: ${dataset_name}"
    else
        log_error "Failed to create BigQuery dataset: ${dataset_name}"
        exit 1
    fi
}

upload_spark_script() {
    local bucket_name="$1"
    local script_dir="$2"
    local project_id="$3"
    local dataset_name="$4"
    
    log_info "Preparing and uploading PySpark processing script"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would upload Spark script to gs://${bucket_name}/scripts/"
        return 0
    fi
    
    local spark_script="${script_dir}/data_processing_spark.py"
    
    # Check if script exists, if not create it
    if [[ ! -f "${spark_script}" ]]; then
        log_info "Creating PySpark processing script"
        
        cat > "${spark_script}" << EOF
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import sys

def create_spark_session():
    """Create optimized Spark session for BigQuery integration"""
    return SparkSession.builder \\
        .appName("E-commerce Data Processing Pipeline") \\
        .config("spark.sql.adaptive.enabled", "true") \\
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \\
        .getOrCreate()

def process_transaction_data(spark, input_path, output_dataset):
    """Process e-commerce transaction data with advanced analytics"""
    
    # Read CSV data from Cloud Storage
    df = spark.read \\
        .option("header", "true") \\
        .option("inferSchema", "true") \\
        .csv(input_path)
    
    print(f"Loaded {df.count()} transactions for processing")
    
    # Data cleaning and transformation
    cleaned_df = df \\
        .withColumn("transaction_date", to_date(col("transaction_date"))) \\
        .withColumn("total_amount", col("quantity") * col("unit_price")) \\
        .withColumn("year_month", date_format(col("transaction_date"), "yyyy-MM")) \\
        .filter(col("quantity") > 0) \\
        .filter(col("unit_price") > 0)
    
    # Customer analytics aggregation
    customer_analytics = cleaned_df \\
        .groupBy("customer_id", "year_month") \\
        .agg(
            count("transaction_id").alias("transaction_count"),
            sum("total_amount").alias("total_spent"),
            avg("total_amount").alias("avg_transaction_value"),
            countDistinct("product_category").alias("unique_categories")
        ) \\
        .withColumn("customer_segment", 
            when(col("total_spent") > 1000, "Premium")
            .when(col("total_spent") > 500, "Standard")
            .otherwise("Basic"))
    
    # Product performance analytics
    product_analytics = cleaned_df \\
        .groupBy("product_category", "year_month") \\
        .agg(
            sum("quantity").alias("total_quantity_sold"),
            sum("total_amount").alias("category_revenue"),
            countDistinct("customer_id").alias("unique_customers"),
            avg("unit_price").alias("avg_unit_price")
        ) \\
        .withColumn("revenue_per_customer", 
            col("category_revenue") / col("unique_customers"))
    
    # Location-based analytics
    location_analytics = cleaned_df \\
        .groupBy("store_location", "product_category", "year_month") \\
        .agg(
            sum("total_amount").alias("location_category_revenue"),
            count("transaction_id").alias("transaction_volume")
        )
    
    # Write results to BigQuery
    customer_analytics.write \\
        .format("bigquery") \\
        .option("table", f"{output_dataset}.customer_analytics") \\
        .option("writeMethod", "direct") \\
        .mode("overwrite") \\
        .save()
    
    product_analytics.write \\
        .format("bigquery") \\
        .option("table", f"{output_dataset}.product_analytics") \\
        .option("writeMethod", "direct") \\
        .mode("overwrite") \\
        .save()
    
    location_analytics.write \\
        .format("bigquery") \\
        .option("table", f"{output_dataset}.location_analytics") \\
        .option("writeMethod", "direct") \\
        .mode("overwrite") \\
        .save()
    
    print("✅ All analytics tables successfully written to BigQuery")
    
    return customer_analytics, product_analytics, location_analytics

if __name__ == "__main__":
    # Configuration
    input_path = "gs://${bucket_name}/raw-data/sample_transactions.csv"
    output_dataset = "${project_id}.${dataset_name}"
    
    # Process data
    spark = create_spark_session()
    customer_df, product_df, location_df = process_transaction_data(
        spark, input_path, output_dataset)
    
    # Display sample results
    print("\\n=== Customer Analytics Sample ===")
    customer_df.show(10, truncate=False)
    
    print("\\n=== Product Analytics Sample ===")
    product_df.show(10, truncate=False)
    
    spark.stop()
EOF
    fi
    
    # Upload script to Cloud Storage
    if gsutil cp "${spark_script}" "gs://${bucket_name}/scripts/"; then
        log_success "PySpark script uploaded successfully"
    else
        log_error "Failed to upload PySpark script"
        exit 1
    fi
}

submit_spark_job() {
    local bucket_name="$1"
    local dataset_name="$2" 
    local project_id="$3"
    local region="$4"
    
    local job_name="${dataset_name}-processing-job"
    
    log_info "Submitting Serverless Spark batch job: ${job_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would submit Spark job: ${job_name}"
        return 0
    fi
    
    # Get service account for the job
    local service_account="${project_id}@appspot.gserviceaccount.com"
    
    # Submit the job
    if gcloud dataproc batches submit pyspark \
        "gs://${bucket_name}/scripts/data_processing_spark.py" \
        --batch="${job_name}" \
        --region="${region}" \
        --project="${project_id}" \
        --jars=gs://spark-lib/bigquery/spark-bigquery-latest.jar \
        --properties="spark.executor.instances=2,spark.executor.memory=4g,spark.executor.cores=2" \
        --ttl=30m \
        --service-account="${service_account}"; then
        
        log_success "Spark job submitted successfully: ${job_name}"
        
        # Wait for job completion
        if wait_for_operation "${job_name}" 600 15; then
            log_success "Spark job completed successfully"
        else
            log_error "Spark job failed or timed out"
            exit 1
        fi
    else
        log_error "Failed to submit Spark job"
        exit 1
    fi
}

validate_deployment() {
    local dataset_name="$1"
    local project_id="$2"
    
    log_info "Validating deployment and data processing results"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would validate deployment"
        return 0
    fi
    
    # Check BigQuery tables
    local tables=("customer_analytics" "product_analytics" "location_analytics")
    
    for table in "${tables[@]}"; do
        log_info "Validating table: ${table}"
        
        local row_count=$(bq query --use_legacy_sql=false --format=csv \
            "SELECT COUNT(*) FROM \`${project_id}.${dataset_name}.${table}\`" 2>/dev/null | tail -n +2)
        
        if [[ -n "${row_count}" && "${row_count}" -gt 0 ]]; then
            log_success "Table ${table} contains ${row_count} rows"
        else
            log_error "Table ${table} validation failed or empty"
            exit 1
        fi
    done
    
    # Run sample analytics query
    log_info "Running sample analytics query"
    local query_result=$(bq query --use_legacy_sql=false --format=csv \
        "SELECT customer_segment, COUNT(*) as customer_count 
         FROM \`${project_id}.${dataset_name}.customer_analytics\` 
         GROUP BY customer_segment 
         ORDER BY customer_count DESC" 2>/dev/null)
    
    if [[ -n "${query_result}" ]]; then
        log_success "Sample query executed successfully"
        echo "${query_result}"
    else
        log_warning "Sample query failed (non-critical)"
    fi
}

#############################################
# Main Deployment Logic
#############################################

main() {
    local project_id=""
    local region="${DEFAULT_REGION}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        show_help
        exit 1
    fi
    
    # Initialize deployment variables
    local random_suffix=$(generate_random_suffix)
    local bucket_name="data-lake-spark-${random_suffix}"
    local dataset_name="analytics_dataset_${random_suffix}"
    local zone="${region}-a"
    
    # Display deployment configuration
    cat << EOF

====================================================
GCP BigQuery Serverless Spark Deployment
====================================================
Project ID:     ${project_id}
Region:         ${region}
Zone:           ${zone}
Bucket Name:    ${bucket_name}
Dataset Name:   ${dataset_name}
Dry Run:        ${DRY_RUN}
Verbose:        ${VERBOSE}
Log File:       ${LOG_FILE}
====================================================

EOF
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        read -p "Proceed with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Prerequisites check
    log_info "Starting deployment prerequisites check..."
    
    check_command "gcloud"
    check_command "bq" 
    check_command "gsutil"
    check_command "openssl"
    
    check_gcp_authentication
    check_gcp_project "${project_id}"
    
    # Set gcloud configuration
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${project_id}"
        gcloud config set compute/region "${region}"
        gcloud config set compute/zone "${zone}"
        log_success "GCP configuration updated"
    fi
    
    # Enable APIs
    enable_apis "${project_id}"
    
    # Main deployment steps
    log_info "Starting infrastructure deployment..."
    
    create_storage_bucket "${bucket_name}" "${project_id}" "${region}"
    upload_sample_data "${bucket_name}" "${SCRIPT_DIR}"
    create_bigquery_dataset "${dataset_name}" "${project_id}" "${region}"
    upload_spark_script "${bucket_name}" "${SCRIPT_DIR}" "${project_id}" "${dataset_name}"
    submit_spark_job "${bucket_name}" "${dataset_name}" "${project_id}" "${region}"
    validate_deployment "${dataset_name}" "${project_id}"
    
    # Display success information
    cat << EOF

====================================================
✅ DEPLOYMENT COMPLETED SUCCESSFULLY
====================================================
Project ID:         ${project_id}
Storage Bucket:     gs://${bucket_name}
BigQuery Dataset:   ${project_id}.${dataset_name}
Region:             ${region}

Generated Resources:
- Cloud Storage bucket with sample data
- BigQuery dataset with analytics tables:
  - customer_analytics
  - product_analytics  
  - location_analytics
- Processed data from Serverless Spark job

Next Steps:
1. Explore data in BigQuery Console:
   https://console.cloud.google.com/bigquery?project=${project_id}

2. View job execution details:
   https://console.cloud.google.com/dataproc/batches?project=${project_id}

3. Monitor costs:
   https://console.cloud.google.com/billing?project=${project_id}

Cleanup:
Run ./destroy.sh --project-id ${project_id} when finished

Log File: ${LOG_FILE}
====================================================

EOF
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Execute main function
main "$@"
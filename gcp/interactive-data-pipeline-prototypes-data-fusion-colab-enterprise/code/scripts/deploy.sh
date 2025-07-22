#!/bin/bash

# Deploy Script for Interactive Data Pipeline Prototypes with Cloud Data Fusion and Colab Enterprise
# This script deploys the complete infrastructure for data pipeline prototyping using GCP services

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed. Please install $1 and try again."
    fi
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
    fi
}

# Function to validate project permissions
check_project_permissions() {
    local project_id="$1"
    log "Checking project permissions for ${project_id}..."
    
    # Check if user has required roles
    local required_roles=(
        "roles/datafusion.admin"
        "roles/notebooks.admin"
        "roles/bigquery.admin"
        "roles/storage.admin"
        "roles/compute.admin"
        "roles/iam.serviceAccountUser"
    )
    
    local user_email
    user_email=$(gcloud config get-value account)
    
    for role in "${required_roles[@]}"; do
        if ! gcloud projects get-iam-policy "${project_id}" \
            --flatten="bindings[].members" \
            --format="table(bindings.role)" \
            --filter="bindings.members:${user_email} AND bindings.role:${role}" | grep -q "${role}"; then
            warning "You may not have the required role: ${role}"
        fi
    done
}

# Function to enable required APIs
enable_apis() {
    local project_id="$1"
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "datafusion.googleapis.com"
        "notebooks.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "compute.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${project_id}"; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
        fi
    done
}

# Function to wait for API availability
wait_for_apis() {
    log "Waiting for APIs to become available..."
    sleep 30  # Give APIs time to propagate
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    local bucket_name="$1"
    local region="$2"
    local project_id="$3"
    
    log "Creating Cloud Storage buckets..."
    
    # Create primary data bucket
    if gsutil ls "gs://${bucket_name}" &>/dev/null; then
        warning "Bucket gs://${bucket_name} already exists"
    else
        if gsutil mb -p "${project_id}" -c STANDARD -l "${region}" "gs://${bucket_name}"; then
            success "Created primary data bucket: gs://${bucket_name}"
        else
            error "Failed to create primary data bucket"
        fi
    fi
    
    # Create staging bucket
    if gsutil ls "gs://${bucket_name}-staging" &>/dev/null; then
        warning "Bucket gs://${bucket_name}-staging already exists"
    else
        if gsutil mb -p "${project_id}" -c STANDARD -l "${region}" "gs://${bucket_name}-staging"; then
            success "Created staging bucket: gs://${bucket_name}-staging"
        else
            error "Failed to create staging bucket"
        fi
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${bucket_name}"
    gsutil versioning set on "gs://${bucket_name}-staging"
    success "Enabled versioning on storage buckets"
}

# Function to create BigQuery dataset
create_bigquery_dataset() {
    local dataset_name="$1"
    local region="$2"
    local project_id="$3"
    
    log "Creating BigQuery dataset..."
    
    if bq ls -d "${project_id}:${dataset_name}" &>/dev/null; then
        warning "BigQuery dataset ${dataset_name} already exists"
    else
        if bq mk --project_id="${project_id}" --location="${region}" --dataset "${dataset_name}"; then
            success "Created BigQuery dataset: ${dataset_name}"
        else
            error "Failed to create BigQuery dataset"
        fi
    fi
    
    # Set dataset description
    bq update --description "Analytics dataset for pipeline prototyping" "${project_id}:${dataset_name}"
    success "Updated BigQuery dataset description"
}

# Function to deploy Cloud Data Fusion instance
deploy_data_fusion() {
    local instance_name="$1"
    local region="$2"
    local project_id="$3"
    
    log "Deploying Cloud Data Fusion instance..."
    
    # Check if instance already exists
    if gcloud data-fusion instances describe "${instance_name}" --location="${region}" --project="${project_id}" &>/dev/null; then
        warning "Data Fusion instance ${instance_name} already exists"
        return 0
    fi
    
    # Create Data Fusion instance
    if gcloud data-fusion instances create "${instance_name}" \
        --location="${region}" \
        --edition=developer \
        --enable-stackdriver-logging \
        --enable-stackdriver-monitoring \
        --project="${project_id}"; then
        success "Created Data Fusion instance: ${instance_name}"
    else
        error "Failed to create Data Fusion instance"
    fi
    
    # Wait for instance to become ready
    log "Waiting for Data Fusion instance to become ready (this may take 15-20 minutes)..."
    if gcloud data-fusion instances wait "${instance_name}" \
        --location="${region}" \
        --condition=ready \
        --project="${project_id}" \
        --timeout=1800; then  # 30 minutes timeout
        success "Data Fusion instance is ready"
    else
        error "Data Fusion instance failed to become ready within timeout"
    fi
}

# Function to create sample data
create_sample_data() {
    local bucket_name="$1"
    
    log "Creating sample data files..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create customer data CSV
    cat > "${temp_dir}/customer_data.csv" << 'EOF'
customer_id,name,email,signup_date,region
1001,John Smith,john.smith@email.com,2023-01-15,US-East
1002,Jane Doe,jane.doe@email.com,2023-02-20,US-West
1003,Bob Johnson,bob.johnson@email.com,2023-03-10,EU-Central
1004,Alice Brown,alice.brown@email.com,2023-04-05,US-East
1005,Charlie Davis,charlie.davis@email.com,2023-05-12,APAC
EOF
    
    # Create transaction data JSON
    cat > "${temp_dir}/transaction_data.json" << 'EOF'
{"transaction_id": "tx001", "customer_id": 1001, "amount": 125.50, "timestamp": "2023-06-01T10:30:00Z", "product": "Widget A"}
{"transaction_id": "tx002", "customer_id": 1002, "amount": 75.25, "timestamp": "2023-06-01T11:15:00Z", "product": "Widget B"}
{"transaction_id": "tx003", "customer_id": 1003, "amount": 200.00, "timestamp": "2023-06-02T14:20:00Z", "product": "Widget C"}
{"transaction_id": "tx004", "customer_id": 1001, "amount": 89.99, "timestamp": "2023-06-02T09:45:00Z", "product": "Widget A"}
{"transaction_id": "tx005", "customer_id": 1004, "amount": 150.75, "timestamp": "2023-06-02T16:30:00Z", "product": "Widget B"}
EOF
    
    # Upload to Cloud Storage
    if gsutil cp "${temp_dir}/customer_data.csv" "gs://${bucket_name}/raw/customer_data.csv" && \
       gsutil cp "${temp_dir}/transaction_data.json" "gs://${bucket_name}/raw/transaction_data.json"; then
        success "Sample data uploaded to Cloud Storage"
    else
        error "Failed to upload sample data"
    fi
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
}

# Function to create notebook template
create_notebook_template() {
    local bucket_name="$1"
    local project_id="$2"
    local dataset_name="$3"
    
    log "Creating pipeline prototype notebook template..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create notebook template
    cat > "${temp_dir}/pipeline_prototype.ipynb" << EOF
{
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {},
      "source": [
        "# Pipeline Prototype: Customer Transaction Analysis\\n",
        "This notebook demonstrates interactive pipeline development for Cloud Data Fusion"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "import pandas as pd\\n",
        "import json\\n",
        "from google.cloud import bigquery, storage\\n",
        "from datetime import datetime\\n",
        "\\n",
        "# Initialize clients\\n",
        "bq_client = bigquery.Client()\\n",
        "storage_client = storage.Client()\\n",
        "\\n",
        "PROJECT_ID = '${project_id}'\\n",
        "BUCKET_NAME = '${bucket_name}'\\n",
        "DATASET_NAME = '${dataset_name}'"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "# Load customer data from Cloud Storage\\n",
        "customer_df = pd.read_csv(f'gs://{BUCKET_NAME}/raw/customer_data.csv')\\n",
        "print('Customer data shape:', customer_df.shape)\\n",
        "customer_df.head()"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "# Load transaction data from Cloud Storage\\n",
        "import pandas as pd\\n",
        "transaction_df = pd.read_json(f'gs://{BUCKET_NAME}/raw/transaction_data.json', lines=True)\\n",
        "print('Transaction data shape:', transaction_df.shape)\\n",
        "transaction_df.head()"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "# Prototype transformation: Join customer and transaction data\\n",
        "merged_df = customer_df.merge(transaction_df, on='customer_id', how='inner')\\n",
        "print('Merged data shape:', merged_df.shape)\\n",
        "merged_df.head()"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "# Data quality checks\\n",
        "print('Data quality summary:')\\n",
        "print(f'Total records: {len(merged_df)}')\\n",
        "print(f'Null values: {merged_df.isnull().sum().sum()}')\\n",
        "print(f'Duplicate records: {merged_df.duplicated().sum()}')\\n",
        "print(f'Unique customers: {merged_df.customer_id.nunique()}')\\n",
        "print(f'Unique products: {merged_df.product.nunique()}')"
      ]
    }
  ],
  "metadata": {
    "kernelspec": {
      "display_name": "Python 3",
      "language": "python",
      "name": "python3"
    }
  },
  "nbformat": 4,
  "nbformat_minor": 4
}
EOF
    
    # Upload notebook template
    if gsutil cp "${temp_dir}/pipeline_prototype.ipynb" "gs://${bucket_name}/notebooks/"; then
        success "Pipeline prototype notebook template uploaded"
    else
        error "Failed to upload notebook template"
    fi
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
}

# Function to create BigQuery table
create_bigquery_table() {
    local dataset_name="$1"
    local project_id="$2"
    
    log "Creating BigQuery table for pipeline output..."
    
    # Check if table already exists
    if bq ls -j "${project_id}:${dataset_name}.customer_transactions" &>/dev/null; then
        warning "BigQuery table customer_transactions already exists"
        return 0
    fi
    
    # Create table schema
    if bq mk \
        --project_id="${project_id}" \
        --table \
        "${dataset_name}.customer_transactions" \
        customer_id:INTEGER,name:STRING,email:STRING,signup_date:STRING,region:STRING,transaction_id:STRING,amount:FLOAT,timestamp:STRING,product:STRING; then
        success "Created BigQuery table: customer_transactions"
    else
        error "Failed to create BigQuery table"
    fi
}

# Function to get Data Fusion endpoint
get_data_fusion_endpoint() {
    local instance_name="$1"
    local region="$2"
    local project_id="$3"
    
    log "Retrieving Data Fusion endpoint..."
    
    local endpoint
    endpoint=$(gcloud data-fusion instances describe "${instance_name}" \
        --location="${region}" \
        --project="${project_id}" \
        --format="value(apiEndpoint)")
    
    if [[ -n "$endpoint" ]]; then
        success "Data Fusion endpoint: ${endpoint}"
        echo "${endpoint}"
    else
        error "Failed to retrieve Data Fusion endpoint"
    fi
}

# Function to display deployment summary
display_summary() {
    local project_id="$1"
    local instance_name="$2"
    local bucket_name="$3"
    local dataset_name="$4"
    local region="$5"
    local fusion_endpoint="$6"
    
    echo ""
    echo "========================================="
    echo "         DEPLOYMENT COMPLETED           "
    echo "========================================="
    echo ""
    echo "Project ID: ${project_id}"
    echo "Region: ${region}"
    echo ""
    echo "Resources Created:"
    echo "  - Data Fusion Instance: ${instance_name}"
    echo "  - Storage Buckets: ${bucket_name}, ${bucket_name}-staging"
    echo "  - BigQuery Dataset: ${dataset_name}"
    echo "  - Sample data files uploaded"
    echo "  - Notebook template created"
    echo ""
    echo "Access Information:"
    echo "  - Data Fusion UI: ${fusion_endpoint}"
    echo "  - Colab Enterprise: https://console.cloud.google.com/vertex-ai/colab"
    echo "  - BigQuery: https://console.cloud.google.com/bigquery"
    echo "  - Cloud Storage: https://console.cloud.google.com/storage"
    echo ""
    echo "Next Steps:"
    echo "  1. Open Colab Enterprise in the Google Cloud Console"
    echo "  2. Create a new runtime with the provided configuration"
    echo "  3. Import the notebook template from gs://${bucket_name}/notebooks/"
    echo "  4. Start prototyping your data pipeline transformations"
    echo "  5. Export pipeline configurations to Data Fusion when ready"
    echo ""
    echo "Cost Monitoring:"
    echo "  - Data Fusion Developer edition: ~\$0.20/hour when running"
    echo "  - Remember to stop or delete resources when not in use"
    echo ""
}

# Main deployment function
main() {
    log "Starting deployment of Interactive Data Pipeline Prototypes infrastructure..."
    
    # Check prerequisites
    log "Checking prerequisites..."
    check_command "gcloud"
    check_command "gsutil"
    check_command "bq"
    check_gcloud_auth
    
    # Set default values or get from environment
    export PROJECT_ID="${PROJECT_ID:-data-pipeline-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export INSTANCE_NAME="${INSTANCE_NAME:-data-fusion-${random_suffix}}"
    export BUCKET_NAME="${BUCKET_NAME:-pipeline-data-${random_suffix}}"
    export DATASET_NAME="${DATASET_NAME:-pipeline_analytics_${random_suffix//-/_}}"
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} does not exist or you don't have access to it"
    fi
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    success "Configured gcloud defaults"
    
    # Check permissions
    check_project_permissions "${PROJECT_ID}"
    
    # Enable APIs
    enable_apis "${PROJECT_ID}"
    wait_for_apis
    
    # Create resources
    create_storage_buckets "${BUCKET_NAME}" "${REGION}" "${PROJECT_ID}"
    create_bigquery_dataset "${DATASET_NAME}" "${REGION}" "${PROJECT_ID}"
    create_sample_data "${BUCKET_NAME}"
    create_notebook_template "${BUCKET_NAME}" "${PROJECT_ID}" "${DATASET_NAME}"
    create_bigquery_table "${DATASET_NAME}" "${PROJECT_ID}"
    
    # Deploy Data Fusion (this takes the longest)
    deploy_data_fusion "${INSTANCE_NAME}" "${REGION}" "${PROJECT_ID}"
    
    # Get Data Fusion endpoint
    local fusion_endpoint
    fusion_endpoint=$(get_data_fusion_endpoint "${INSTANCE_NAME}" "${REGION}" "${PROJECT_ID}")
    
    # Display summary
    display_summary "${PROJECT_ID}" "${INSTANCE_NAME}" "${BUCKET_NAME}" "${DATASET_NAME}" "${REGION}" "${fusion_endpoint}"
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"
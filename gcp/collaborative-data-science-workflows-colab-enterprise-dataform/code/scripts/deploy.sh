#!/bin/bash

# Collaborative Data Science Workflows with Colab Enterprise and Dataform - Deployment Script
# This script deploys the complete infrastructure for collaborative data science workflows
# using Colab Enterprise, Dataform, BigQuery, and Cloud Storage

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment due to error..."
    if [[ -f "${STATE_FILE}" ]]; then
        source "${STATE_FILE}"
        
        # Clean up BigQuery resources
        if [[ -n "${DATASET_NAME:-}" ]]; then
            log_info "Cleaning up BigQuery dataset: ${DATASET_NAME}"
            bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null || true
        fi
        
        # Clean up Cloud Storage bucket
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            log_info "Cleaning up Cloud Storage bucket: ${BUCKET_NAME}"
            gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
        fi
        
        # Clean up Dataform resources
        if [[ -n "${WORKSPACE_NAME:-}" && -n "${REPOSITORY_NAME:-}" ]]; then
            log_info "Cleaning up Dataform workspace: ${WORKSPACE_NAME}"
            gcloud dataform workspaces delete "${WORKSPACE_NAME}" \
                --repository="${REPOSITORY_NAME}" \
                --region="${REGION}" \
                --quiet 2>/dev/null || true
        fi
        
        if [[ -n "${REPOSITORY_NAME:-}" ]]; then
            log_info "Cleaning up Dataform repository: ${REPOSITORY_NAME}"
            gcloud dataform repositories delete "${REPOSITORY_NAME}" \
                --region="${REGION}" \
                --quiet 2>/dev/null || true
        fi
        
        rm -f "${STATE_FILE}"
    fi
}

# Set up error trap
trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not available. Please ensure Google Cloud SDK is properly installed"
    fi
    
    log_success "Prerequisites check completed"
}

# Project configuration
configure_project() {
    log_info "Configuring Google Cloud project..."
    
    # Set project ID (use existing or create new)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="ds-workflow-$(date +%s)"
        log_info "Using project ID: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Resource names
    export BUCKET_NAME="ds-workflow-${RANDOM_SUFFIX}"
    export DATASET_NAME="analytics_${RANDOM_SUFFIX}"
    export REPOSITORY_NAME="dataform-repo-${RANDOM_SUFFIX}"
    export WORKSPACE_NAME="dev-workspace-${RANDOM_SUFFIX}"
    export TEMPLATE_NAME="ds-runtime-template-${RANDOM_SUFFIX}"
    
    # Save state for cleanup
    cat > "${STATE_FILE}" << EOF
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
ZONE="${ZONE}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
BUCKET_NAME="${BUCKET_NAME}"
DATASET_NAME="${DATASET_NAME}"
REPOSITORY_NAME="${REPOSITORY_NAME}"
WORKSPACE_NAME="${WORKSPACE_NAME}"
TEMPLATE_NAME="${TEMPLATE_NAME}"
EOF
    
    # Configure gcloud defaults
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "storage.googleapis.com"
        "bigquery.googleapis.com"
        "dataform.googleapis.com"
        "aiplatform.googleapis.com"
        "notebooks.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}..."
    
    # Create bucket with appropriate configuration
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" || error_exit "Failed to create storage bucket"
    
    # Enable versioning for data protection
    gsutil versioning set on "gs://${BUCKET_NAME}" || error_exit "Failed to enable versioning"
    
    # Create folder structure
    local folders=("raw-data" "processed-data" "model-artifacts")
    for folder in "${folders[@]}"; do
        gsutil -m cp /dev/null "gs://${BUCKET_NAME}/${folder}/.keep" || error_exit "Failed to create folder structure"
    done
    
    log_success "Cloud Storage bucket created: gs://${BUCKET_NAME}"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log_info "Creating BigQuery dataset: ${DATASET_NAME}..."
    
    # Create dataset
    bq mk --location="${REGION}" \
        --description="Analytics dataset for collaborative data science" \
        "${PROJECT_ID}:${DATASET_NAME}" || error_exit "Failed to create BigQuery dataset"
    
    # Create sample tables
    log_info "Creating sample tables..."
    
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.customer_data" \
        customer_id:STRING,name:STRING,email:STRING,signup_date:DATE || error_exit "Failed to create customer_data table"
    
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.transaction_data" \
        transaction_id:STRING,customer_id:STRING,amount:FLOAT,transaction_date:TIMESTAMP || error_exit "Failed to create transaction_data table"
    
    log_success "BigQuery resources created"
}

# Create Dataform repository
create_dataform_repository() {
    log_info "Creating Dataform repository: ${REPOSITORY_NAME}..."
    
    gcloud dataform repositories create "${REPOSITORY_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" || error_exit "Failed to create Dataform repository"
    
    # Wait for repository creation
    sleep 10
    
    # Verify repository creation
    gcloud dataform repositories describe "${REPOSITORY_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" > /dev/null || error_exit "Failed to verify Dataform repository"
    
    log_success "Dataform repository created: ${REPOSITORY_NAME}"
}

# Create Dataform workspace
create_dataform_workspace() {
    log_info "Creating Dataform workspace: ${WORKSPACE_NAME}..."
    
    gcloud dataform workspaces create "${WORKSPACE_NAME}" \
        --repository="${REPOSITORY_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" || error_exit "Failed to create Dataform workspace"
    
    log_success "Dataform workspace created: ${WORKSPACE_NAME}"
}

# Create Colab Enterprise runtime template
create_runtime_template() {
    log_info "Creating Colab Enterprise runtime template: ${TEMPLATE_NAME}..."
    
    # Create temporary file for runtime template configuration
    local template_file="/tmp/runtime-template.json"
    
    cat > "${template_file}" << EOF
{
  "name": "projects/${PROJECT_ID}/locations/${REGION}/runtimeTemplates/${TEMPLATE_NAME}",
  "displayName": "Data Science Runtime Template",
  "description": "Optimized runtime for collaborative data science workflows",
  "machineSpec": {
    "machineType": "n1-standard-4"
  },
  "dataPersistentDiskSpec": {
    "diskType": "pd-standard",
    "diskSizeGb": "100"
  },
  "containerSpec": {
    "imageUri": "gcr.io/deeplearning-platform-release/base-cpu",
    "env": [
      {
        "name": "GOOGLE_CLOUD_PROJECT",
        "value": "${PROJECT_ID}"
      }
    ]
  },
  "networkSpec": {
    "enableIpForwarding": false
  }
}
EOF
    
    # Create runtime template using REST API
    curl -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @"${template_file}" \
        "https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/runtimeTemplates" \
        > /dev/null || error_exit "Failed to create runtime template"
    
    # Clean up temporary file
    rm -f "${template_file}"
    
    log_success "Runtime template created: ${TEMPLATE_NAME}"
}

# Load sample data
load_sample_data() {
    log_info "Loading sample data..."
    
    # Create temporary directory for sample data
    local temp_dir="/tmp/sample-data"
    mkdir -p "${temp_dir}"
    
    # Create sample customer data
    cat > "${temp_dir}/customer_data.csv" << 'EOF'
customer_id,name,email,signup_date
CUST001,Alice Johnson,alice@example.com,2023-01-15
CUST002,Bob Smith,bob@example.com,2023-02-20
CUST003,Carol Davis,carol@example.com,2023-03-10
CUST004,David Wilson,david@example.com,2023-04-05
CUST005,Eve Brown,eve@example.com,2023-05-12
EOF
    
    # Create sample transaction data
    cat > "${temp_dir}/transaction_data.csv" << 'EOF'
transaction_id,customer_id,amount,transaction_date
TXN001,CUST001,150.50,2023-06-01 10:30:00
TXN002,CUST002,89.99,2023-06-02 14:15:00
TXN003,CUST001,200.00,2023-06-03 09:45:00
TXN004,CUST003,75.25,2023-06-04 16:20:00
TXN005,CUST002,120.75,2023-06-05 11:10:00
TXN006,CUST004,95.50,2023-06-06 13:30:00
TXN007,CUST005,250.00,2023-06-07 08:45:00
TXN008,CUST003,180.25,2023-06-08 15:20:00
EOF
    
    # Upload data to Cloud Storage
    gsutil cp "${temp_dir}/customer_data.csv" "gs://${BUCKET_NAME}/raw-data/" || error_exit "Failed to upload customer data"
    gsutil cp "${temp_dir}/transaction_data.csv" "gs://${BUCKET_NAME}/raw-data/" || error_exit "Failed to upload transaction data"
    
    # Load data into BigQuery tables
    log_info "Loading data into BigQuery tables..."
    
    bq load --source_format=CSV --skip_leading_rows=1 \
        "${DATASET_NAME}.customer_data" \
        "gs://${BUCKET_NAME}/raw-data/customer_data.csv" \
        customer_id:STRING,name:STRING,email:STRING,signup_date:DATE || error_exit "Failed to load customer data"
    
    bq load --source_format=CSV --skip_leading_rows=1 \
        "${DATASET_NAME}.transaction_data" \
        "gs://${BUCKET_NAME}/raw-data/transaction_data.csv" \
        transaction_id:STRING,customer_id:STRING,amount:FLOAT,transaction_date:TIMESTAMP || error_exit "Failed to load transaction data"
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    log_success "Sample data loaded successfully"
}

# Configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions..."
    
    # Get current user email
    local user_email
    user_email=$(gcloud config get-value account) || error_exit "Failed to get user email"
    
    local roles=(
        "roles/notebooks.admin"
        "roles/aiplatform.user"
        "roles/bigquery.dataEditor"
        "roles/bigquery.jobUser"
        "roles/dataform.editor"
        "roles/storage.objectAdmin"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting ${role} to ${user_email}..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="user:${user_email}" \
            --role="${role}" > /dev/null || error_exit "Failed to grant ${role}"
    done
    
    log_success "IAM permissions configured"
}

# Validation functions
validate_deployment() {
    log_info "Validating deployment..."
    
    # Test BigQuery data access
    log_info "Testing BigQuery data access..."
    local customer_count
    customer_count=$(bq query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_NAME}.customer_data\`" | tail -n +2) || error_exit "Failed to query customer data"
    
    if [[ "${customer_count}" != "5" ]]; then
        error_exit "Expected 5 customers, found ${customer_count}"
    fi
    
    # Test Cloud Storage access
    log_info "Testing Cloud Storage access..."
    gsutil ls "gs://${BUCKET_NAME}/raw-data/" > /dev/null || error_exit "Failed to access Cloud Storage"
    
    # Test Dataform repository access
    log_info "Testing Dataform repository access..."
    gcloud dataform repositories describe "${REPOSITORY_NAME}" \
        --region="${REGION}" > /dev/null || error_exit "Failed to access Dataform repository"
    
    # Test Dataform workspace access
    log_info "Testing Dataform workspace access..."
    gcloud dataform workspaces describe "${WORKSPACE_NAME}" \
        --repository="${REPOSITORY_NAME}" \
        --region="${REGION}" > /dev/null || error_exit "Failed to access Dataform workspace"
    
    log_success "Deployment validation completed successfully"
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."
    
    cat << EOF

${GREEN}=================================================================${NC}
${GREEN}           DEPLOYMENT COMPLETED SUCCESSFULLY${NC}
${GREEN}=================================================================${NC}

${BLUE}Project Configuration:${NC}
  Project ID:      ${PROJECT_ID}
  Region:          ${REGION}
  Zone:            ${ZONE}

${BLUE}Cloud Storage:${NC}
  Bucket Name:     gs://${BUCKET_NAME}
  Data Folders:    raw-data/, processed-data/, model-artifacts/

${BLUE}BigQuery:${NC}
  Dataset:         ${DATASET_NAME}
  Tables:          customer_data, transaction_data
  Sample Records:  Customer data (5 records), Transaction data (8 records)

${BLUE}Dataform:${NC}
  Repository:      ${REPOSITORY_NAME}
  Workspace:       ${WORKSPACE_NAME}
  Region:          ${REGION}

${BLUE}Colab Enterprise:${NC}
  Runtime Template: ${TEMPLATE_NAME}
  Machine Type:     n1-standard-4
  Disk Size:        100 GB

${BLUE}Next Steps:${NC}
  1. Access Colab Enterprise: https://colab.research.google.com/
  2. Access Dataform: https://console.cloud.google.com/dataform
  3. Access BigQuery: https://console.cloud.google.com/bigquery
  4. Access Cloud Storage: https://console.cloud.google.com/storage

${BLUE}Estimated Monthly Cost:${NC}
  - BigQuery: \$10-30 (depending on usage)
  - Cloud Storage: \$5-15 (depending on data volume)
  - Colab Enterprise: \$20-50 (depending on runtime usage)
  - Dataform: Free tier available

${YELLOW}Important:${NC}
  - Remember to clean up resources when done to avoid charges
  - Use './destroy.sh' to remove all created resources
  - Monitor usage through Google Cloud Console

${GREEN}=================================================================${NC}

EOF
    
    # Save summary to file
    cat << EOF > "${SCRIPT_DIR}/deployment-summary.txt"
Collaborative Data Science Workflows Deployment Summary
Generated: $(date)

Project ID: ${PROJECT_ID}
Region: ${REGION}
Bucket: gs://${BUCKET_NAME}
BigQuery Dataset: ${DATASET_NAME}
Dataform Repository: ${REPOSITORY_NAME}
Dataform Workspace: ${WORKSPACE_NAME}
Runtime Template: ${TEMPLATE_NAME}

Access URLs:
- Colab Enterprise: https://colab.research.google.com/
- Dataform: https://console.cloud.google.com/dataform
- BigQuery: https://console.cloud.google.com/bigquery
- Cloud Storage: https://console.cloud.google.com/storage
EOF
    
    log_success "Deployment summary saved to deployment-summary.txt"
}

# Main deployment function
main() {
    log_info "Starting deployment of Collaborative Data Science Workflows..."
    log_info "Deployment started at: $(date)"
    
    # Initialize log file
    echo "Deployment Log - $(date)" > "${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    configure_project
    enable_apis
    create_storage_bucket
    create_bigquery_resources
    create_dataform_repository
    create_dataform_workspace
    create_runtime_template
    load_sample_data
    configure_iam_permissions
    validate_deployment
    generate_summary
    
    log_success "Deployment completed successfully at: $(date)"
    log_info "Total deployment time: $SECONDS seconds"
    
    # Clean up state file on successful completion
    rm -f "${STATE_FILE}"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
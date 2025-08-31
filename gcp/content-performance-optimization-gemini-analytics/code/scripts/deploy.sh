#!/bin/bash

# Content Performance Optimization with Gemini and Analytics - Deployment Script
# This script deploys the complete infrastructure for content performance optimization
# using Vertex AI Gemini, Cloud Functions, BigQuery, and Cloud Storage

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Attempt to clean up resources that might have been created
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${DATASET_NAME:-}" ]]; then
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
    
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if APIs are enabled
check_api_enabled() {
    local api_name="$1"
    if gcloud services list --enabled --filter="name:${api_name}" --format="value(name)" | grep -q "${api_name}"; then
        return 0
    else
        return 1
    fi
}

# Function to wait for API to be fully enabled
wait_for_api() {
    local api_name="$1"
    local max_wait=300
    local waited=0
    
    log_info "Waiting for ${api_name} to be fully enabled..."
    
    while ! check_api_enabled "${api_name}" && [ $waited -lt $max_wait ]; do
        sleep 10
        waited=$((waited + 10))
        echo -n "."
    done
    echo
    
    if [ $waited -ge $max_wait ]; then
        error_exit "Timeout waiting for ${api_name} to be enabled"
    fi
    
    log_success "${api_name} is enabled"
}

# Function to generate random suffix
generate_random_suffix() {
    if command_exists openssl; then
        openssl rand -hex 3
    elif command_exists python3; then
        python3 -c "import secrets; print(secrets.token_hex(3))"
    else
        # Fallback to date-based suffix
        date +%s | tail -c 7
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command_exists gcloud; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error_exit "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if bq is available
    if ! command_exists bq; then
        error_exit "BigQuery CLI (bq) is not available. Please install Google Cloud SDK"
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error_exit "Cloud Storage CLI (gsutil) is not available. Please install Google Cloud SDK"
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        error_exit "curl is required but not installed"
    fi
    
    log_success "All prerequisites met"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Project configuration
    export PROJECT_ID="${PROJECT_ID:-content-opt-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_random_suffix)
    export DATASET_NAME="content_analytics_${RANDOM_SUFFIX}"
    export FUNCTION_NAME="content-analyzer-${RANDOM_SUFFIX}"
    export BUCKET_NAME="content-optimization-${RANDOM_SUFFIX}"
    export TABLE_NAME="performance_data"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Dataset: ${DATASET_NAME}"
    log_info "Function: ${FUNCTION_NAME}"
    log_info "Bucket: ${BUCKET_NAME}"
}

# Function to configure project
configure_project() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if ! check_api_enabled "${api}"; then
            log_info "Enabling ${api}..."
            gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
            wait_for_api "${api}"
        else
            log_success "${api} is already enabled"
        fi
    done
    
    log_success "All required APIs are enabled"
}

# Function to create BigQuery dataset and table
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and table..."
    
    # Create BigQuery dataset
    if ! bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        bq mk --location="${REGION}" "${PROJECT_ID}:${DATASET_NAME}" || error_exit "Failed to create BigQuery dataset"
        log_success "BigQuery dataset created: ${DATASET_NAME}"
    else
        log_warning "BigQuery dataset already exists: ${DATASET_NAME}"
    fi
    
    # Create table schema
    cat > /tmp/schema.json << 'EOF'
[
  {"name": "content_id", "type": "STRING", "mode": "REQUIRED"},
  {"name": "title", "type": "STRING", "mode": "REQUIRED"},
  {"name": "content_type", "type": "STRING", "mode": "REQUIRED"},
  {"name": "publish_date", "type": "TIMESTAMP", "mode": "REQUIRED"},
  {"name": "page_views", "type": "INTEGER", "mode": "NULLABLE"},
  {"name": "engagement_rate", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "conversion_rate", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "time_on_page", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "social_shares", "type": "INTEGER", "mode": "NULLABLE"},
  {"name": "content_score", "type": "FLOAT", "mode": "NULLABLE"}
]
EOF
    
    # Create the performance data table
    if ! bq show "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" >/dev/null 2>&1; then
        bq mk --table "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" /tmp/schema.json || error_exit "Failed to create BigQuery table"
        log_success "BigQuery table created: ${TABLE_NAME}"
    else
        log_warning "BigQuery table already exists: ${TABLE_NAME}"
    fi
    
    # Clean up temporary file
    rm -f /tmp/schema.json
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Cloud Storage bucket already exists: ${BUCKET_NAME}"
    else
        # Create Cloud Storage bucket
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" || error_exit "Failed to create Cloud Storage bucket"
        log_success "Cloud Storage bucket created: ${BUCKET_NAME}"
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}" || error_exit "Failed to enable versioning"
    log_success "Versioning enabled for bucket"
    
    # Set appropriate IAM permissions for Cloud Functions
    gsutil iam ch "serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com:objectAdmin" "gs://${BUCKET_NAME}" || error_exit "Failed to set bucket permissions"
    log_success "Bucket permissions configured"
}

# Function to load sample data
load_sample_data() {
    log_info "Loading sample content performance data..."
    
    # Create sample data file
    cat > /tmp/sample_data.json << 'EOF'
{"content_id": "blog_001", "title": "10 Tips for Better SEO", "content_type": "blog", "publish_date": "2024-01-15 10:00:00", "page_views": 1250, "engagement_rate": 0.65, "conversion_rate": 0.08, "time_on_page": 180.5, "social_shares": 45, "content_score": 8.2}
{"content_id": "video_001", "title": "Product Demo Walkthrough", "content_type": "video", "publish_date": "2024-01-20 14:30:00", "page_views": 890, "engagement_rate": 0.78, "conversion_rate": 0.12, "time_on_page": 220.3, "social_shares": 67, "content_score": 9.1}
{"content_id": "infographic_001", "title": "Data Visualization Best Practices", "content_type": "infographic", "publish_date": "2024-01-25 09:15:00", "page_views": 2100, "engagement_rate": 0.72, "conversion_rate": 0.05, "time_on_page": 95.2, "social_shares": 89, "content_score": 7.8}
{"content_id": "blog_002", "title": "Advanced Analytics Techniques", "content_type": "blog", "publish_date": "2024-02-01 11:45:00", "page_views": 780, "engagement_rate": 0.58, "conversion_rate": 0.06, "time_on_page": 165.7, "social_shares": 23, "content_score": 6.9}
{"content_id": "case_study_001", "title": "Customer Success Story", "content_type": "case_study", "publish_date": "2024-02-05 16:20:00", "page_views": 1450, "engagement_rate": 0.82, "conversion_rate": 0.18, "time_on_page": 310.8, "social_shares": 78, "content_score": 9.5}
EOF
    
    # Load sample data into BigQuery
    bq load --source_format=NEWLINE_DELIMITED_JSON "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}" /tmp/sample_data.json || error_exit "Failed to load sample data"
    log_success "Sample data loaded into BigQuery"
    
    # Clean up temporary file
    rm -f /tmp/sample_data.json
}

# Function to create Cloud Function
create_cloud_function() {
    log_info "Creating Cloud Function for content analysis..."
    
    # Create temporary directory for Cloud Function source code
    local function_dir="/tmp/content-analyzer-${RANDOM_SUFFIX}"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.34.0
google-cloud-aiplatform==1.70.0
google-cloud-storage==2.19.0
pandas==2.3.0
functions-framework==3.8.0
EOF
    
    # Create main Cloud Function code
    cat > main.py << 'EOF'
import json
import pandas as pd
from google.cloud import bigquery
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
from datetime import datetime, timedelta
import os

# Initialize clients
bq_client = bigquery.Client()
storage_client = storage.Client()

@functions_framework.http
def analyze_content(request):
    """Analyze content performance and generate optimization recommendations."""
    
    project_id = os.environ.get('GCP_PROJECT')
    dataset_name = os.environ.get('DATASET_NAME')
    bucket_name = os.environ.get('BUCKET_NAME')
    
    try:
        # Query recent content performance data
        query = f"""
        SELECT 
            content_id,
            title,
            content_type,
            page_views,
            engagement_rate,
            conversion_rate,
            time_on_page,
            social_shares,
            content_score
        FROM `{project_id}.{dataset_name}.performance_data`
        WHERE publish_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        ORDER BY content_score DESC
        """
        
        query_job = bq_client.query(query)
        results = query_job.result()
        
        # Convert to DataFrame for analysis
        data = []
        for row in results:
            data.append({
                'content_id': row.content_id,
                'title': row.title,
                'content_type': row.content_type,
                'page_views': row.page_views,
                'engagement_rate': row.engagement_rate,
                'conversion_rate': row.conversion_rate,
                'time_on_page': row.time_on_page,
                'social_shares': row.social_shares,
                'content_score': row.content_score
            })
        
        df = pd.DataFrame(data)
        
        if df.empty:
            return {'status': 'no_data', 'message': 'No content data found'}
        
        # Prepare data for Gemini analysis
        content_summary = df.to_string(index=False)
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location='us-central1')
        
        # Create Gemini prompt for content analysis
        prompt = f"""
        Analyze the following content performance data and provide optimization recommendations:
        
        {content_summary}
        
        Please provide:
        1. Top 3 highest-performing content characteristics
        2. Content optimization recommendations for underperforming pieces
        3. Suggested content variations for the top-performing content
        4. Key performance indicators to monitor
        
        Format your response as a structured JSON with clear recommendations.
        """
        
        # Generate content with Gemini 2.5 Flash
        from vertexai.generative_models import GenerativeModel
        
        model = GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)
        
        # Store analysis results in Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        blob_name = f'analysis_results/content_analysis_{timestamp}.json'
        
        analysis_result = {
            'timestamp': timestamp,
            'data_analyzed': len(df),
            'gemini_analysis': response.text,
            'top_performers': df.nlargest(3, 'content_score').to_dict('records')
        }
        
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(analysis_result, indent=2))
        
        return {
            'status': 'success',
            'analysis_file': f'gs://{bucket_name}/{blob_name}',
            'content_analyzed': len(df),
            'recommendations_available': True
        }
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}
EOF
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point analyze_content \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},DATASET_NAME=${DATASET_NAME},BUCKET_NAME=${BUCKET_NAME}" || error_exit "Failed to deploy Cloud Function"
    
    # Get the function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" --gen2 --format="value(serviceConfig.uri)")
    export FUNCTION_URL
    
    log_success "Cloud Function deployed: ${FUNCTION_NAME}"
    log_info "Function URL: ${FUNCTION_URL}"
    
    # Clean up temporary directory
    cd /
    rm -rf "${function_dir}"
}

# Function to create BigQuery views
create_bigquery_views() {
    log_info "Creating BigQuery views for performance analytics..."
    
    # Create performance summary view
    bq mk --view \
        "SELECT 
            content_type,
            COUNT(*) as total_content,
            AVG(page_views) as avg_page_views,
            AVG(engagement_rate) as avg_engagement,
            AVG(conversion_rate) as avg_conversion,
            AVG(content_score) as avg_score,
            SUM(social_shares) as total_shares
         FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\`
         GROUP BY content_type
         ORDER BY avg_score DESC" \
        "${PROJECT_ID}:${DATASET_NAME}.content_performance_summary" || error_exit "Failed to create performance summary view"
    
    # Create content rankings view
    bq mk --view \
        "SELECT 
            content_id,
            title,
            content_type,
            content_score,
            CASE 
                WHEN content_score >= 9.0 THEN 'Excellent'
                WHEN content_score >= 7.5 THEN 'Good'
                WHEN content_score >= 6.0 THEN 'Average'
                ELSE 'Needs Improvement'
            END as performance_category
         FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_NAME}\`
         ORDER BY content_score DESC" \
        "${PROJECT_ID}:${DATASET_NAME}.content_rankings" || error_exit "Failed to create content rankings view"
    
    log_success "BigQuery views created successfully"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing content analysis system..."
    
    # Test Cloud Function
    log_info "Triggering content analysis..."
    response=$(curl -s -X POST "${FUNCTION_URL}" -H "Content-Type: application/json" -d '{"trigger": "manual_analysis"}') || error_exit "Failed to trigger Cloud Function"
    
    log_info "Function response: ${response}"
    
    # Wait for analysis to complete
    log_info "Waiting for analysis to complete..."
    sleep 30
    
    # Check for analysis results in Cloud Storage
    log_info "Checking analysis results..."
    if gsutil ls "gs://${BUCKET_NAME}/analysis_results/" >/dev/null 2>&1; then
        latest_file=$(gsutil ls "gs://${BUCKET_NAME}/analysis_results/" | tail -1)
        log_success "Analysis results available: ${latest_file}"
    else
        log_warning "No analysis results found yet"
    fi
    
    # Test BigQuery views
    log_info "Testing BigQuery views..."
    bq query --use_legacy_sql=false "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.content_performance_summary\`" || error_exit "Failed to query performance summary view"
    bq query --use_legacy_sql=false "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.content_rankings\` LIMIT 5" || error_exit "Failed to query content rankings view"
    
    log_success "Content analysis system tested successfully"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > /tmp/deployment_info.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "zone": "${ZONE}",
  "dataset_name": "${DATASET_NAME}",
  "function_name": "${FUNCTION_NAME}",
  "bucket_name": "${BUCKET_NAME}",
  "table_name": "${TABLE_NAME}",
  "function_url": "${FUNCTION_URL:-}",
  "resources": {
    "bigquery_dataset": "${PROJECT_ID}:${DATASET_NAME}",
    "bigquery_table": "${PROJECT_ID}:${DATASET_NAME}.${TABLE_NAME}",
    "bigquery_views": [
      "${PROJECT_ID}:${DATASET_NAME}.content_performance_summary",
      "${PROJECT_ID}:${DATASET_NAME}.content_rankings"
    ],
    "cloud_function": "${FUNCTION_NAME}",
    "storage_bucket": "gs://${BUCKET_NAME}"
  }
}
EOF
    
    # Store deployment info in Cloud Storage
    gsutil cp /tmp/deployment_info.json "gs://${BUCKET_NAME}/deployment_info.json" || log_warning "Failed to store deployment info"
    
    # Also save locally if possible
    if [[ -w "." ]]; then
        cp /tmp/deployment_info.json "./deployment_info.json"
        log_success "Deployment information saved to deployment_info.json"
    fi
    
    rm -f /tmp/deployment_info.json
}

# Main deployment function
main() {
    log_info "Starting Content Performance Optimization deployment..."
    log_info "This will deploy Vertex AI Gemini, Cloud Functions, BigQuery, and Cloud Storage resources"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_bigquery_resources
    create_storage_bucket
    load_sample_data
    create_cloud_function
    create_bigquery_views
    test_deployment
    save_deployment_info
    
    log_success "=== Deployment completed successfully! ==="
    log_info "Resources deployed:"
    log_info "  Project: ${PROJECT_ID}"
    log_info "  BigQuery Dataset: ${DATASET_NAME}"
    log_info "  Cloud Function: ${FUNCTION_NAME}"
    log_info "  Storage Bucket: ${BUCKET_NAME}"
    log_info "  Function URL: ${FUNCTION_URL:-}"
    log_info ""
    log_info "Next steps:"
    log_info "1. Access BigQuery views for content performance insights"
    log_info "2. Use the Cloud Function URL to trigger content analysis"
    log_info "3. Check Cloud Storage bucket for analysis results"
    log_info "4. Monitor costs in Google Cloud Console billing section"
    log_info ""
    log_warning "Remember to run destroy.sh when done to avoid ongoing charges!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
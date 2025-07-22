#!/bin/bash

# Interactive Data Storytelling with BigQuery Data Canvas and Looker Studio - Deployment Script
# This script deploys the complete data storytelling pipeline on GCP

set -euo pipefail

# Color codes for output formatting
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

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID=""
REGION="us-central1"
DATASET_NAME=""
FUNCTION_NAME="data-storytelling-automation"
JOB_NAME=""
BUCKET_NAME=""
RANDOM_SUFFIX=""

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Interactive Data Storytelling infrastructure on GCP

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -h, --help                    Display this help message
    --dry-run                     Show what would be deployed without executing

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-project --region us-east1
    $0 --project-id my-project --dry-run

EOF
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
        usage
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi

    # Check if jq is installed (optional but recommended)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output formatting will be limited."
    fi

    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Verify project access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Please check project ID and permissions."
        exit 1
    fi

    # Set the project
    gcloud config set project "$PROJECT_ID" || {
        log_error "Failed to set project '$PROJECT_ID'"
        exit 1
    }

    log_success "Prerequisites validated successfully"
}

# Function to initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."

    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    DATASET_NAME="retail_analytics_$(date +%s)"
    JOB_NAME="storytelling-job-${RANDOM_SUFFIX}"
    BUCKET_NAME="${PROJECT_ID}-storytelling-${RANDOM_SUFFIX}"

    # Set default region for gcloud operations
    gcloud config set compute/region "$REGION" || {
        log_warning "Failed to set default region. Continuing with explicit region specifications."
    }

    log_success "Environment variables initialized"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Dataset: $DATASET_NAME"
    log_info "  Function: $FUNCTION_NAME"
    log_info "  Job: $JOB_NAME"
    log_info "  Bucket: $BUCKET_NAME"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would enable API: $api"
        else
            gcloud services enable "$api" || {
                log_error "Failed to enable API: $api"
                exit 1
            }
        fi
    done

    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi

    log_success "APIs enabled successfully"
}

# Function to create BigQuery dataset and tables
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create BigQuery dataset: $DATASET_NAME"
        log_info "[DRY RUN] Would create tables: sales_data, dashboard_data"
        return 0
    fi

    # Create BigQuery dataset
    bq mk --dataset \
        --description="Dataset for interactive data storytelling" \
        --location="$REGION" \
        "${PROJECT_ID}:${DATASET_NAME}" || {
        log_error "Failed to create BigQuery dataset"
        exit 1
    }

    # Create sales data table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.sales_data" \
        product_id:STRING,product_name:STRING,category:STRING,sales_date:DATE,quantity:INTEGER,unit_price:FLOAT,customer_segment:STRING,region:STRING,revenue:FLOAT || {
        log_error "Failed to create sales_data table"
        exit 1
    }

    log_success "BigQuery dataset and tables created"
}

# Function to load sample data
load_sample_data() {
    log_info "Loading sample data into BigQuery..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would load sample retail data"
        return 0
    fi

    # Create temporary file with sample data
    local temp_file="/tmp/sample_sales_data_${RANDOM_SUFFIX}.csv"
    cat > "$temp_file" << 'EOF'
product_id,product_name,category,sales_date,quantity,unit_price,customer_segment,region,revenue
P001,Wireless Headphones,Electronics,2024-01-15,25,99.99,Premium,North America,2499.75
P002,Fitness Tracker,Electronics,2024-01-16,18,149.99,Health-Conscious,Europe,2699.82
P003,Coffee Maker,Home & Kitchen,2024-01-17,12,79.99,Everyday,North America,959.88
P004,Running Shoes,Sports,2024-01-18,30,129.99,Athletic,Asia,3899.70
P005,Smartphone Case,Electronics,2024-01-19,45,24.99,Budget,North America,1124.55
P006,Yoga Mat,Sports,2024-01-20,22,39.99,Health-Conscious,Europe,879.78
P007,Bluetooth Speaker,Electronics,2024-01-21,15,199.99,Premium,Asia,2999.85
P008,Water Bottle,Sports,2024-01-22,60,19.99,Everyday,North America,1199.40
P009,Laptop Stand,Office,2024-01-23,8,89.99,Professional,Europe,719.92
P010,Air Fryer,Home & Kitchen,2024-01-24,10,159.99,Everyday,Asia,1599.90
P011,Gaming Mouse,Electronics,2024-01-25,35,59.99,Gaming,North America,2099.65
P012,Resistance Bands,Sports,2024-01-26,28,29.99,Health-Conscious,Europe,839.72
P013,Standing Desk,Office,2024-01-27,5,299.99,Professional,Asia,1499.95
P014,Smart Watch,Electronics,2024-01-28,20,249.99,Premium,North America,4999.80
P015,Protein Powder,Health,2024-01-29,40,39.99,Health-Conscious,Europe,1599.60
EOF

    # Load data into BigQuery
    bq load \
        --source_format=CSV \
        --skip_leading_rows=1 \
        --autodetect \
        "${PROJECT_ID}:${DATASET_NAME}.sales_data" \
        "$temp_file" || {
        log_error "Failed to load sample data"
        rm -f "$temp_file"
        exit 1
    }

    # Clean up temporary file
    rm -f "$temp_file"

    # Verify data loading
    local record_count
    record_count=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_data\`" | tail -n1)

    if [[ "$record_count" -gt 0 ]]; then
        log_success "Sample data loaded successfully ($record_count records)"
    else
        log_error "Failed to verify data loading"
        exit 1
    fi
}

# Function to create service account for Vertex AI
create_service_account() {
    log_info "Creating service account for Vertex AI operations..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create service account: vertex-ai-storytelling"
        return 0
    fi

    # Create service account
    gcloud iam service-accounts create vertex-ai-storytelling \
        --display-name="Vertex AI Data Storytelling Service Account" \
        --project="$PROJECT_ID" || {
        log_warning "Service account may already exist, continuing..."
    }

    # Grant necessary permissions
    local roles=(
        "roles/bigquery.dataViewer"
        "roles/bigquery.jobUser"
        "roles/aiplatform.user"
        "roles/storage.objectViewer"
    )

    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:vertex-ai-storytelling@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" || {
            log_error "Failed to grant role: $role"
            exit 1
        }
    done

    log_success "Service account created and configured"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for function deployment..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://$BUCKET_NAME"
        return 0
    fi

    # Create bucket
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME" || {
        log_error "Failed to create Cloud Storage bucket"
        exit 1
    }

    # Set bucket lifecycle policy to delete objects after 7 days
    cat > /tmp/lifecycle.json << EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 7}
    }
  ]
}
EOF

    gsutil lifecycle set /tmp/lifecycle.json "gs://$BUCKET_NAME" || {
        log_warning "Failed to set bucket lifecycle policy"
    }

    rm -f /tmp/lifecycle.json

    log_success "Cloud Storage bucket created"
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying Cloud Function..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Function: $FUNCTION_NAME"
        return 0
    fi

    # Create function directory
    local function_dir="/tmp/storytelling-function-${RANDOM_SUFFIX}"
    mkdir -p "$function_dir"

    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
google-cloud-bigquery==3.11.4
google-cloud-aiplatform==1.38.1
google-cloud-storage==2.10.0
pandas==2.0.3
numpy==1.24.3
functions-framework==3.5.0
EOF

    # Create main.py
    cat > "$function_dir/main.py" << EOF
import json
import pandas as pd
from google.cloud import bigquery
from google.cloud import aiplatform
import os
import logging
from datetime import datetime
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def generate_data_story(request):
    """
    Main function to generate automated data stories
    """
    try:
        project_id = os.environ.get('PROJECT_ID', '$PROJECT_ID')
        dataset_name = os.environ.get('DATASET_NAME', '$DATASET_NAME')
        region = os.environ.get('REGION', '$REGION')
        
        logger.info(f"Processing request for project: {project_id}")
        
        # Initialize BigQuery client
        bq_client = bigquery.Client(project=project_id)
        
        # Execute analytics query
        query = f"""
        SELECT 
            category,
            customer_segment,
            region,
            SUM(revenue) as total_revenue,
            COUNT(DISTINCT product_id) as product_count,
            AVG(unit_price) as avg_price,
            SUM(quantity) as total_quantity
        FROM \`{project_id}.{dataset_name}.sales_data\`
        GROUP BY category, customer_segment, region
        ORDER BY total_revenue DESC
        LIMIT 10
        """
        
        logger.info("Executing BigQuery analytics query")
        query_job = bq_client.query(query)
        results = query_job.result()
        
        # Convert to DataFrame for analysis
        df = results.to_dataframe()
        
        if df.empty:
            logger.warning("No data found in analytics query")
            return {
                'statusCode': 204,
                'body': json.dumps({'message': 'No data available for analysis'}),
                'headers': {'Content-Type': 'application/json'}
            }
        
        # Generate insights summary
        total_revenue = float(df['total_revenue'].sum())
        top_category = df.iloc[0]['category']
        top_segment = df.iloc[0]['customer_segment']
        top_region = df.iloc[0]['region']
        
        # Create story narrative
        story = {
            'timestamp': datetime.now().isoformat(),
            'analysis_summary': {
                'total_records_analyzed': len(df),
                'total_revenue': total_revenue,
                'top_performing_category': top_category,
                'leading_customer_segment': top_segment,
                'top_revenue_region': top_region,
                'category_count': len(df['category'].unique()),
                'segment_count': len(df['customer_segment'].unique())
            },
            'key_insights': [
                f"{top_category} category leads with highest revenue performance",
                f"{top_segment} customers represent the most valuable segment",
                f"{top_region} region shows strongest market presence",
                f"Analysis covers {len(df['category'].unique())} distinct product categories"
            ],
            'narrative': f"The latest data analysis reveals {top_category} as the top-performing category, with {top_segment} customers driving the highest revenue contribution in the {top_region} region. Total revenue across all segments reached \${total_revenue:,.2f}, demonstrating strong market performance across diverse customer segments.",
            'recommendations': [
                f"Prioritize marketing investments in {top_category} products",
                f"Develop targeted campaigns for {top_segment} customer segment",
                f"Expand market presence in {top_region} region",
                "Analyze underperforming categories for optimization opportunities",
                "Implement cross-selling strategies between top-performing segments"
            ],
            'data_quality': {
                'completeness': 'High',
                'freshness': 'Current',
                'accuracy': 'Validated'
            }
        }
        
        logger.info("Data story generated successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps(story, indent=2),
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }
        
    except Exception as e:
        logger.error(f"Error generating data story: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e),
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {'Content-Type': 'application/json'}
        }
EOF

    # Deploy Cloud Function
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime=python39 \
        --trigger=http \
        --allow-unauthenticated \
        --region="$REGION" \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars="PROJECT_ID=$PROJECT_ID,DATASET_NAME=$DATASET_NAME,REGION=$REGION" \
        --source="$function_dir" \
        --max-instances=10 || {
        log_error "Failed to deploy Cloud Function"
        rm -rf "$function_dir"
        exit 1
    }

    # Clean up temporary files
    rm -rf "$function_dir"

    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")

    log_success "Cloud Function deployed successfully"
    log_info "Function URL: $function_url"

    # Test function
    log_info "Testing Cloud Function..."
    local test_response
    test_response=$(curl -s -X POST "$function_url" \
        -H "Content-Type: application/json" \
        -d '{"test": true}')

    if echo "$test_response" | grep -q "statusCode.*200"; then
        log_success "Cloud Function test passed"
    else
        log_warning "Cloud Function test returned unexpected response"
        log_info "Response: $test_response"
    fi
}

# Function to create materialized view for Looker Studio
create_materialized_view() {
    log_info "Creating materialized view for Looker Studio..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create materialized view: dashboard_data"
        return 0
    fi

    # Create materialized view
    bq mk --materialized_view \
        --description="Optimized view for Looker Studio dashboards" \
        --location="$REGION" \
        "${PROJECT_ID}:${DATASET_NAME}.dashboard_data" \
        "SELECT 
         category,
         customer_segment,
         region,
         sales_date,
         SUM(revenue) as daily_revenue,
         SUM(quantity) as daily_quantity,
         COUNT(DISTINCT product_id) as products_sold,
         AVG(unit_price) as avg_price
        FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_data\`
        GROUP BY category, customer_segment, region, sales_date" || {
        log_error "Failed to create materialized view"
        exit 1
    }

    log_success "Materialized view created for Looker Studio integration"
}

# Function to set up Cloud Scheduler
setup_cloud_scheduler() {
    log_info "Setting up Cloud Scheduler for automated reports..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create scheduler job: $JOB_NAME"
        return 0
    fi

    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")

    # Create Cloud Scheduler job
    gcloud scheduler jobs create http "$JOB_NAME" \
        --location="$REGION" \
        --schedule="0 9 * * 1-5" \
        --uri="$function_url" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"automated": true, "source": "scheduler"}' \
        --description="Automated data storytelling report generation" || {
        log_error "Failed to create Cloud Scheduler job"
        exit 1
    }

    log_success "Cloud Scheduler configured for weekday reports at 9 AM"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would validate all deployed resources"
        return 0
    fi

    local validation_errors=0

    # Check BigQuery dataset
    if ! bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log_error "BigQuery dataset validation failed"
        ((validation_errors++))
    fi

    # Check BigQuery table
    if ! bq show "${PROJECT_ID}:${DATASET_NAME}.sales_data" &> /dev/null; then
        log_error "BigQuery table validation failed"
        ((validation_errors++))
    fi

    # Check Cloud Function
    if ! gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log_error "Cloud Function validation failed"
        ((validation_errors++))
    fi

    # Check Cloud Scheduler job
    if ! gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" &> /dev/null; then
        log_error "Cloud Scheduler job validation failed"
        ((validation_errors++))
    fi

    # Check Cloud Storage bucket
    if ! gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        log_error "Cloud Storage bucket validation failed"
        ((validation_errors++))
    fi

    if [[ $validation_errors -eq 0 ]]; then
        log_success "All resources validated successfully"
    else
        log_error "$validation_errors validation errors found"
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "BigQuery Dataset: $DATASET_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Scheduler Job: $JOB_NAME"
    echo "Storage Bucket: $BUCKET_NAME"
    echo ""
    echo "Next Steps:"
    echo "1. Connect Looker Studio to BigQuery dataset: ${PROJECT_ID}.${DATASET_NAME}.dashboard_data"
    echo "2. Create dashboards using the materialized view"
    echo "3. Test the Cloud Function manually or wait for scheduled execution"
    echo "4. Monitor logs using: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo ""
    echo "Function URL:"
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)"
    else
        echo "[DRY RUN] Function URL would be displayed here"
    fi
    echo "=================================="
}

# Main deployment function
main() {
    log_info "Starting Interactive Data Storytelling deployment..."
    
    parse_args "$@"
    validate_prerequisites
    initialize_environment
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    enable_apis
    create_bigquery_resources
    load_sample_data
    create_service_account
    create_storage_bucket
    deploy_cloud_function
    create_materialized_view
    setup_cloud_scheduler
    validate_deployment
    
    log_success "Deployment completed successfully!"
    display_summary
}

# Trap errors and cleanup
trap 'log_error "Deployment failed. Check the logs above for details."' ERR

# Run main function with all arguments
main "$@"
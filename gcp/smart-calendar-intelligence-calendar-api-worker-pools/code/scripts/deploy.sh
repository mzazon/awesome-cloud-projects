#!/bin/bash

# Smart Calendar Intelligence with Cloud Calendar API and Cloud Run Worker Pools - Deployment Script
# This script deploys the complete calendar intelligence infrastructure on Google Cloud Platform
# 
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Required APIs enabled
# - Appropriate IAM permissions
# - Google Workspace account for Calendar API access

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="calendar-ai"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Smart Calendar Intelligence infrastructure on Google Cloud Platform.

OPTIONS:
    -p, --project-id PROJECT_ID    Specify GCP project ID (optional, will generate if not provided)
    -r, --region REGION           Specify GCP region (default: us-central1)
    -z, --zone ZONE              Specify GCP zone (default: us-central1-a)
    -d, --dry-run                Run in dry-run mode (show commands without executing)
    -h, --help                   Display this help message

EXAMPLES:
    $0                                           # Deploy with generated project ID
    $0 -p my-calendar-project                   # Deploy to specific project
    $0 -p my-project -r us-west1 -z us-west1-a # Deploy to specific region/zone
    $0 --dry-run                                # Show what would be deployed

EOF
}

# Parse command line arguments
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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -d|--dry-run)
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

# Set default values if not provided
PROJECT_ID=${PROJECT_ID:-"${PROJECT_PREFIX}-$(date +%s)"}
REGION=${REGION:-$DEFAULT_REGION}
ZONE=${ZONE:-$DEFAULT_ZONE}

# Function to execute commands (respects dry-run mode)
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        echo "  Command: $cmd"
    else
        log_info "$description"
        if eval "$cmd"; then
            log_success "Completed: $description"
        else
            log_error "Failed: $description"
            return 1
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        log_error "Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "bq (BigQuery CLI) is not available"
        log_error "Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Export environment variables for the deployment
    export PROJECT_ID
    export REGION
    export ZONE
    export WORKER_POOL_NAME="calendar-intelligence-${RANDOM_SUFFIX}"
    export TASK_QUEUE_NAME="calendar-tasks-${RANDOM_SUFFIX}"
    export DATASET_NAME="calendar_analytics_${RANDOM_SUFFIX}"
    export BUCKET_NAME="calendar-intelligence-${PROJECT_ID}"
    export SERVICE_ACCOUNT_NAME="calendar-intelligence-worker"
    export API_SERVICE_NAME="calendar-intelligence-api"
    export REPOSITORY_NAME="calendar-intelligence"
    
    log_success "Resource names generated with suffix: ${RANDOM_SUFFIX}"
}

# Function to create or configure GCP project
setup_project() {
    log_info "Setting up GCP project: ${PROJECT_ID}"
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_warning "Project ${PROJECT_ID} does not exist"
        if [[ "$DRY_RUN" == "false" ]]; then
            read -p "Create new project ${PROJECT_ID}? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                execute_command "gcloud projects create ${PROJECT_ID}" "Creating project ${PROJECT_ID}"
            else
                log_error "Project creation cancelled"
                exit 1
            fi
        fi
    fi
    
    # Set default project
    execute_command "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_command "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_command "gcloud config set compute/zone ${ZONE}" "Setting default zone"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "calendar-json.googleapis.com"
        "run.googleapis.com"
        "cloudtasks.googleapis.com"
        "aiplatform.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable ${api}" "Enabling ${api}"
    done
    
    log_success "All required APIs enabled"
}

# Function to create storage resources
create_storage_resources() {
    log_info "Creating storage and analytics resources..."
    
    # Create Cloud Storage bucket
    execute_command "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}" \
        "Creating Cloud Storage bucket"
    
    # Enable versioning for data protection
    execute_command "gsutil versioning set on gs://${BUCKET_NAME}" \
        "Enabling bucket versioning"
    
    # Create BigQuery dataset
    execute_command "bq mk --dataset --location=${REGION} --description='Calendar intelligence analytics dataset' ${PROJECT_ID}:${DATASET_NAME}" \
        "Creating BigQuery dataset"
    
    # Create BigQuery table for calendar insights
    local schema='[
        {"name": "calendar_id", "type": "STRING", "mode": "REQUIRED"},
        {"name": "analysis_timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
        {"name": "insights", "type": "STRING", "mode": "NULLABLE"},
        {"name": "processed_date", "type": "DATE", "mode": "REQUIRED"}
    ]'
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$schema" > /tmp/calendar_insights_schema.json
        execute_command "bq mk --table --schema=/tmp/calendar_insights_schema.json --description='Calendar intelligence insights storage' ${PROJECT_ID}:${DATASET_NAME}.calendar_insights" \
            "Creating BigQuery table for insights"
        rm -f /tmp/calendar_insights_schema.json
    else
        log_info "[DRY-RUN] Would create BigQuery table with schema: $schema"
    fi
    
    log_success "Storage and analytics resources created"
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    execute_command "gcloud artifacts repositories create ${REPOSITORY_NAME} --repository-format=docker --location=${REGION} --description='Calendar intelligence container repository'" \
        "Creating Artifact Registry repository"
    
    execute_command "gcloud auth configure-docker ${REGION}-docker.pkg.dev" \
        "Configuring Docker authentication"
    
    log_success "Artifact Registry repository created and configured"
}

# Function to create IAM service account
create_service_account() {
    log_info "Creating IAM service account and permissions..."
    
    # Create service account
    execute_command "gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} --description='Service account for calendar intelligence worker pool' --display-name='Calendar Intelligence Worker'" \
        "Creating service account"
    
    # Grant necessary permissions
    local roles=(
        "roles/aiplatform.user"
        "roles/bigquery.dataEditor"
        "roles/storage.objectAdmin"
        "roles/cloudtasks.enqueuer"
        "roles/run.invoker"
    )
    
    for role in "${roles[@]}"; do
        execute_command "gcloud projects add-iam-policy-binding ${PROJECT_ID} --member='serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com' --role='${role}'" \
            "Granting ${role} to service account"
    done
    
    log_success "Service account created with appropriate permissions"
}

# Function to create Cloud Tasks queue
create_task_queue() {
    log_info "Creating Cloud Tasks queue..."
    
    execute_command "gcloud tasks queues create ${TASK_QUEUE_NAME} --location=${REGION} --max-concurrent-dispatches=10 --max-dispatches-per-second=5 --max-retry-duration=3600s --max-attempts=3" \
        "Creating Cloud Tasks queue"
    
    log_success "Cloud Tasks queue created"
}

# Function to build and deploy worker application
deploy_worker_application() {
    log_info "Building and deploying worker application..."
    
    local worker_dir="${SCRIPT_DIR}/../worker"
    local image_url="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/worker:latest"
    
    if [[ ! -d "$worker_dir" ]]; then
        log_warning "Worker application directory not found at ${worker_dir}"
        log_info "Creating sample worker application structure..."
        
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$worker_dir/src"
            
            # Create sample worker application
            cat > "${worker_dir}/src/calendar_worker.py" << 'EOF'
#!/usr/bin/env python3
import os
import json
import logging
from datetime import datetime, timedelta
from google.cloud import tasks_v2
from google.cloud import aiplatform
from google.cloud import bigquery
import vertexai
from vertexai.generative_models import GenerativeModel

class CalendarIntelligenceWorker:
    def __init__(self):
        self.project_id = os.environ['GOOGLE_CLOUD_PROJECT']
        self.region = os.environ['GOOGLE_CLOUD_REGION']
        self.setup_clients()
    
    def setup_clients(self):
        """Initialize Google Cloud and Calendar API clients"""
        self.tasks_client = tasks_v2.CloudTasksClient()
        self.bq_client = bigquery.Client(project=self.project_id)
        
        # Initialize Vertex AI
        vertexai.init(project=self.project_id, location=self.region)
        self.ai_model = GenerativeModel("gemini-1.5-flash")
    
    def process_calendar_task(self, task_data):
        """Process calendar intelligence task"""
        calendar_id = task_data.get('calendar_id', 'primary')
        analysis_type = task_data.get('analysis_type', 'basic')
        
        logging.info(f"Processing calendar task for {calendar_id}")
        
        # Simulate calendar analysis
        insights = {
            'calendar_id': calendar_id,
            'analysis_type': analysis_type,
            'processed_at': datetime.utcnow().isoformat(),
            'insights': 'Sample calendar intelligence insights would be generated here'
        }
        
        # Store results in BigQuery
        self.store_analysis_results(calendar_id, insights)
        
        return insights
    
    def store_analysis_results(self, calendar_id, analysis):
        """Store analysis results in BigQuery"""
        dataset_name = os.environ.get('DATASET_NAME', 'calendar_analytics')
        table_id = f"{self.project_id}.{dataset_name}.calendar_insights"
        
        rows_to_insert = [{
            'calendar_id': calendar_id,
            'analysis_timestamp': datetime.utcnow().isoformat(),
            'insights': json.dumps(analysis),
            'processed_date': datetime.utcnow().date().isoformat()
        }]
        
        errors = self.bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            logging.error(f"BigQuery insert errors: {errors}")
        else:
            logging.info("Analysis results stored successfully")

def main():
    """Main worker function"""
    logging.basicConfig(level=logging.INFO)
    
    worker = CalendarIntelligenceWorker()
    
    # Simulate processing a calendar task
    sample_task = {
        'calendar_id': 'primary',
        'analysis_type': 'intelligence'
    }
    
    results = worker.process_calendar_task(sample_task)
    logging.info(f"Processing completed: {results}")

if __name__ == "__main__":
    main()
EOF
            
            # Create requirements file
            cat > "${worker_dir}/requirements.txt" << 'EOF'
google-cloud-tasks==2.16.4
google-cloud-aiplatform==1.38.1
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
EOF
            
            # Create Dockerfile
            cat > "${worker_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/

# Set environment variables
ENV PYTHONPATH=/app
ENV GOOGLE_CLOUD_REGION=us-central1

# Run the worker application
CMD ["python", "src/calendar_worker.py"]
EOF
        fi
    fi
    
    # Build and deploy worker
    if [[ -d "$worker_dir" ]]; then
        execute_command "cd ${worker_dir} && gcloud builds submit --tag ${image_url} ." \
            "Building worker container image"
        
        execute_command "gcloud beta run worker-pools deploy ${WORKER_POOL_NAME} --image=${image_url} --service-account=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --memory=2Gi --cpu=1 --min-instances=0 --max-instances=10 --region=${REGION} --set-env-vars='GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_REGION=${REGION},DATASET_NAME=${DATASET_NAME}'" \
            "Deploying worker pool"
    else
        log_warning "Skipping worker deployment - source code not found"
    fi
}

# Function to deploy API service
deploy_api_service() {
    log_info "Building and deploying API service..."
    
    local api_dir="${SCRIPT_DIR}/../api"
    local api_image_url="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/api:latest"
    
    if [[ ! -d "$api_dir" ]]; then
        log_warning "API service directory not found at ${api_dir}"
        log_info "Creating sample API service structure..."
        
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$api_dir"
            
            # Create sample API application
            cat > "${api_dir}/main.py" << 'EOF'
#!/usr/bin/env python3
import os
import json
from flask import Flask, request, jsonify
from google.cloud import tasks_v2

app = Flask(__name__)

class CalendarTaskCreator:
    def __init__(self):
        self.project_id = os.environ['GOOGLE_CLOUD_PROJECT']
        self.region = os.environ['GOOGLE_CLOUD_REGION']
        self.queue_name = os.environ['TASK_QUEUE_NAME']
        self.client = tasks_v2.CloudTasksClient()
        self.parent = self.client.queue_path(
            self.project_id, self.region, self.queue_name
        )
    
    def create_calendar_analysis_task(self, calendar_id, priority=0):
        """Create a calendar analysis task"""
        task = {
            'app_engine_http_request': {
                'http_method': tasks_v2.HttpMethod.POST,
                'relative_uri': '/process-calendar',
                'body': json.dumps({
                    'calendar_id': calendar_id,
                    'analysis_type': 'intelligence'
                }).encode()
            }
        }
        
        response = self.client.create_task(
            request={"parent": self.parent, "task": task}
        )
        return response.name

task_creator = CalendarTaskCreator()

@app.route('/trigger-analysis', methods=['POST'])
def trigger_calendar_analysis():
    """API endpoint to trigger calendar analysis"""
    data = request.get_json()
    calendar_ids = data.get('calendar_ids', ['primary'])
    
    created_tasks = []
    for calendar_id in calendar_ids:
        task_name = task_creator.create_calendar_analysis_task(calendar_id)
        created_tasks.append({
            'calendar_id': calendar_id,
            'task_name': task_name
        })
    
    return jsonify({
        'status': 'success',
        'created_tasks': created_tasks
    })

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
            
            # Create API requirements
            cat > "${api_dir}/requirements.txt" << 'EOF'
Flask==3.0.0
google-cloud-tasks==2.16.4
gunicorn==21.2.0
EOF
            
            # Create API Dockerfile
            cat > "${api_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

ENV PORT=8080
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF
        fi
    fi
    
    # Build and deploy API service
    if [[ -d "$api_dir" ]]; then
        execute_command "cd ${api_dir} && gcloud builds submit --tag ${api_image_url} ." \
            "Building API container image"
        
        execute_command "gcloud run deploy ${API_SERVICE_NAME} --image=${api_image_url} --platform=managed --region=${REGION} --allow-unauthenticated --memory=1Gi --cpu=1 --min-instances=0 --max-instances=5 --set-env-vars='GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_REGION=${REGION},TASK_QUEUE_NAME=${TASK_QUEUE_NAME}'" \
            "Deploying API service"
        
        # Get service URL
        if [[ "$DRY_RUN" == "false" ]]; then
            API_URL=$(gcloud run services describe ${API_SERVICE_NAME} --region=${REGION} --format="value(status.url)")
            export API_URL
            log_success "API service deployed at: ${API_URL}"
        fi
    else
        log_warning "Skipping API deployment - source code not found"
    fi
}

# Function to create scheduled jobs
create_scheduled_jobs() {
    log_info "Creating scheduled analysis jobs..."
    
    if [[ -n "${API_URL:-}" ]]; then
        execute_command "gcloud scheduler jobs create http calendar-daily-analysis --location=${REGION} --schedule='0 9 * * *' --uri='${API_URL}/trigger-analysis' --http-method=POST --headers='Content-Type=application/json' --message-body='{\"calendar_ids\": [\"primary\"]}'" \
            "Creating daily analysis scheduler job"
    else
        log_warning "Skipping scheduler creation - API URL not available"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    
    cat << EOF

================================================================================
                    SMART CALENDAR INTELLIGENCE DEPLOYMENT SUMMARY
================================================================================

Project Information:
  Project ID:           ${PROJECT_ID}
  Region:               ${REGION}
  Zone:                 ${ZONE}

Resources Created:
  ✅ Cloud Storage Bucket:     gs://${BUCKET_NAME}
  ✅ BigQuery Dataset:         ${DATASET_NAME}
  ✅ Artifact Registry:        ${REPOSITORY_NAME}
  ✅ Service Account:          ${SERVICE_ACCOUNT_NAME}
  ✅ Cloud Tasks Queue:        ${TASK_QUEUE_NAME}
  ✅ Worker Pool:              ${WORKER_POOL_NAME}
  ✅ API Service:              ${API_SERVICE_NAME}

Next Steps:
  1. Configure Google Calendar API credentials for your organization
  2. Test the API endpoint: ${API_URL:-"<API_URL_NOT_AVAILABLE>"}
  3. Monitor worker pool performance in Cloud Monitoring
  4. Review BigQuery analytics dashboard

Useful Commands:
  # Check worker pool status
  gcloud beta run worker-pools describe ${WORKER_POOL_NAME} --region=${REGION}
  
  # View Cloud Tasks queue
  gcloud tasks queues describe ${TASK_QUEUE_NAME} --location=${REGION}
  
  # Query analytics data
  bq query "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.calendar_insights\` LIMIT 10"

Cost Monitoring:
  Monitor your spending at: https://console.cloud.google.com/billing
  
For cleanup, run: ./destroy.sh

================================================================================
EOF
}

# Main deployment function
main() {
    log_info "Starting Smart Calendar Intelligence deployment..."
    log_info "Target project: ${PROJECT_ID}"
    log_info "Target region: ${REGION}"
    log_info "Dry run mode: ${DRY_RUN}"
    
    check_prerequisites
    generate_resource_names
    setup_project
    enable_apis
    create_storage_resources
    create_artifact_registry
    create_service_account
    create_task_queue
    deploy_worker_application
    deploy_api_service
    create_scheduled_jobs
    
    if [[ "$DRY_RUN" == "false" ]]; then
        display_summary
    else
        log_info "Dry run completed. No resources were created."
    fi
}

# Trap errors and cleanup
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"
#!/bin/bash

# GCP Task Queue System Deployment Script
# This script deploys a complete task queue system using Cloud Tasks and Cloud Functions
# Author: Generated from GCP Recipe
# Version: 1.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="/tmp/gcp-task-queue-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FUNCTION_DIR="${SCRIPT_DIR}/../function_code"

# Configuration variables
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
QUEUE_NAME="${QUEUE_NAME:-background-tasks}"
FUNCTION_NAME="${FUNCTION_NAME:-task-processor}"
BUCKET_NAME=""
FUNCTION_URL=""
DRY_RUN="${DRY_RUN:-false}"

# Function to log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
    esac
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy GCP Task Queue System with Cloud Tasks and Cloud Functions

OPTIONS:
    -p, --project-id       GCP Project ID (required)
    -r, --region          GCP Region (default: us-central1)
    -q, --queue-name      Cloud Tasks queue name (default: background-tasks)
    -f, --function-name   Cloud Function name (default: task-processor)
    -d, --dry-run         Show what would be deployed without executing
    -h, --help            Show this help message
    -v, --verbose         Enable verbose logging

ENVIRONMENT VARIABLES:
    PROJECT_ID            GCP Project ID
    REGION               GCP Region
    GOOGLE_CLOUD_PROJECT  Alternative project ID variable

EXAMPLES:
    $0 -p my-project-123
    $0 --project-id my-project-123 --region us-west1
    DRY_RUN=true $0 -p my-project-123

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
            -q|--queue-name)
                QUEUE_NAME="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Function to validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud >/dev/null 2>&1; then
        log "ERROR" "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log "ERROR" "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check for Python dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        log "ERROR" "Python 3 is required but not installed."
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        # Try to get from gcloud config or environment
        PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"
        if [[ -z "$PROJECT_ID" ]]; then
            log "ERROR" "Project ID is required. Use -p flag or set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log "ERROR" "Project '$PROJECT_ID' does not exist or is not accessible."
        exit 1
    fi
    
    # Check billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        log "WARN" "Billing may not be enabled for project '$PROJECT_ID'. Some services may not work."
    fi
    
    log "INFO" "Prerequisites validation completed successfully"
}

# Function to setup GCP project configuration
setup_project() {
    log "INFO" "Setting up GCP project configuration..."
    
    # Set the project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    # Generate unique bucket name
    BUCKET_NAME="${PROJECT_ID}-task-results-$(date +%s)"
    
    log "INFO" "Project configured: $PROJECT_ID"
    log "INFO" "Region set to: $REGION"
    log "INFO" "Bucket name: $BUCKET_NAME"
}

# Function to enable required APIs
enable_apis() {
    log "INFO" "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudtasks.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log "INFO" "Enabling API: $api"
        if ! gcloud services enable "$api" --quiet; then
            log "ERROR" "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "INFO" "Waiting for APIs to be fully activated..."
    sleep 30
    
    log "INFO" "All required APIs enabled successfully"
}

# Function to create Cloud Tasks queue
create_task_queue() {
    log "INFO" "Creating Cloud Tasks queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create queue '$QUEUE_NAME' in region '$REGION'"
        return 0
    fi
    
    # Check if queue already exists
    if gcloud tasks queues describe "$QUEUE_NAME" --location="$REGION" >/dev/null 2>&1; then
        log "WARN" "Queue '$QUEUE_NAME' already exists, skipping creation"
        return 0
    fi
    
    # Create the queue with retry configuration
    if gcloud tasks queues create "$QUEUE_NAME" \
        --location="$REGION" \
        --max-attempts=3 \
        --max-retry-duration=300s \
        --max-doublings=5; then
        log "INFO" "Cloud Tasks queue '$QUEUE_NAME' created successfully"
    else
        log "ERROR" "Failed to create Cloud Tasks queue"
        exit 1
    fi
}

# Function to create storage bucket
create_storage_bucket() {
    log "INFO" "Creating Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create bucket '$BUCKET_NAME'"
        return 0
    fi
    
    # Check if bucket already exists
    if gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log "WARN" "Bucket '$BUCKET_NAME' already exists, skipping creation"
        return 0
    fi
    
    # Create the bucket
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        log "INFO" "Storage bucket created: $BUCKET_NAME"
        
        # Set bucket permissions for Cloud Function
        local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
        if gsutil iam ch "serviceAccount:${service_account}:objectAdmin" "gs://$BUCKET_NAME"; then
            log "INFO" "Bucket permissions configured for Cloud Function"
        else
            log "WARN" "Failed to set bucket permissions, function may not work properly"
        fi
    else
        log "ERROR" "Failed to create storage bucket"
        exit 1
    fi
}

# Function to prepare function code
prepare_function_code() {
    log "INFO" "Preparing Cloud Function code..."
    
    # Create function directory if it doesn't exist
    if [[ ! -d "$FUNCTION_DIR" ]]; then
        mkdir -p "$FUNCTION_DIR"
    fi
    
    # Create requirements.txt
    cat > "$FUNCTION_DIR/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-logging==3.*
EOF
    
    # Create main.py with the function code
    cat > "$FUNCTION_DIR/main.py" << 'EOF'
import functions_framework
import json
import logging
from google.cloud import storage
from datetime import datetime
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def task_processor(request):
    """
    Process background tasks from Cloud Tasks queue
    """
    try:
        # Parse task payload
        task_data = request.get_json(silent=True)
        if not task_data:
            logger.error("No task data received")
            return {"status": "error", "message": "No task data"}, 400
        
        # Extract task details
        task_type = task_data.get('task_type', 'unknown')
        task_id = task_data.get('task_id', 'no-id')
        
        logger.info(f"Processing task {task_id} of type {task_type}")
        
        # Simulate task processing based on type
        if task_type == 'process_file':
            result = process_file_task(task_data)
        elif task_type == 'send_email':
            result = send_email_task(task_data)
        else:
            result = {
                "status": "success", 
                "message": f"Unknown task type: {task_type}"
            }
        
        logger.info(f"Task {task_id} completed successfully")
        return result, 200
        
    except Exception as e:
        logger.error(f"Task processing failed: {str(e)}", exc_info=True)
        return {"status": "error", "message": str(e)}, 500

def process_file_task(task_data):
    """Process file-related background task"""
    filename = task_data.get('filename', 'test-file.txt')
    content = task_data.get('content', 'Default task content')
    
    # Initialize Cloud Storage client
    client = storage.Client()
    bucket_name = os.environ.get('STORAGE_BUCKET', 'default-bucket')
    
    try:
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(f"processed/{filename}")
        
        # Create processed content with timestamp
        processed_content = f"""Task processed at: {datetime.now().isoformat()}
Original content: {content}
Processing status: Complete
"""
        
        blob.upload_from_string(processed_content)
        
        return {
            "status": "success",
            "message": f"File {filename} processed and saved",
            "processed_at": datetime.now().isoformat()
        }
    except Exception as e:
        raise Exception(f"File processing failed: {str(e)}")

def send_email_task(task_data):
    """Simulate email sending task"""
    recipient = task_data.get('recipient', 'user@example.com')
    subject = task_data.get('subject', 'Background Task Complete')
    
    # In production, integrate with SendGrid, Mailgun, or Gmail API
    logger.info(f"Simulating email to {recipient} with subject: {subject}")
    
    return {
        "status": "success",
        "message": f"Email sent to {recipient}",
        "sent_at": datetime.now().isoformat()
    }
EOF
    
    log "INFO" "Function code prepared successfully"
}

# Function to deploy Cloud Function
deploy_function() {
    log "INFO" "Deploying Cloud Function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would deploy function '$FUNCTION_NAME' from '$FUNCTION_DIR'"
        return 0
    fi
    
    # Deploy the function
    if gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime python311 \
        --source "$FUNCTION_DIR" \
        --entry-point task_processor \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "STORAGE_BUCKET=$BUCKET_NAME" \
        --region="$REGION" \
        --quiet; then
        
        # Get function URL
        FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --format="value(serviceConfig.uri)" 2>/dev/null || echo "")
        
        log "INFO" "Cloud Function deployed successfully"
        log "INFO" "Function URL: $FUNCTION_URL"
    else
        log "ERROR" "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Function to create task creation script
create_task_script() {
    log "INFO" "Creating task creation script..."
    
    local script_path="${SCRIPT_DIR}/create_task.py"
    
    cat > "$script_path" << 'EOF'
#!/usr/bin/env python3
import json
import sys
import os
from google.cloud import tasks_v2
from datetime import datetime, timedelta

def create_task(project_id, location, queue_name, function_url, task_data):
    """Create a task in Cloud Tasks queue"""
    
    try:
        # Initialize the Tasks client
        client = tasks_v2.CloudTasksClient()
        
        # Construct the fully qualified queue name
        parent = client.queue_path(project_id, location, queue_name)
        
        # Construct task payload
        task_payload = {
            'task_id': f"task-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
            'created_at': datetime.now().isoformat(),
            **task_data
        }
        
        # Create the task request
        task = {
            'http_request': {
                'http_method': tasks_v2.HttpMethod.POST,
                'url': function_url,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(task_payload).encode('utf-8')
            }
        }
        
        # Optionally schedule task for future execution
        if 'schedule_time' in task_data:
            schedule_time = datetime.now() + \
                timedelta(seconds=task_data['schedule_time'])
            task['schedule_time'] = {
                'seconds': int(schedule_time.timestamp())
            }
        
        # Submit the task
        response = client.create_task(request={'parent': parent, 'task': task})
        
        print(f"✅ Task created: {response.name}")
        print(f"Task ID: {task_payload['task_id']}")
        return response
        
    except Exception as e:
        print(f"❌ Error creating task: {str(e)}")
        return None

if __name__ == "__main__":
    project_id = os.environ.get('PROJECT_ID')
    location = os.environ.get('REGION', 'us-central1')
    queue_name = os.environ.get('QUEUE_NAME', 'background-tasks')
    function_url = os.environ.get('FUNCTION_URL')
    
    if not all([project_id, function_url]):
        print("❌ Missing required environment variables:")
        print("   PROJECT_ID, FUNCTION_URL")
        sys.exit(1)
    
    # Example file processing task
    file_task = {
        'task_type': 'process_file',
        'filename': 'sample-document.txt',
        'content': 'This is sample content for background processing'
    }
    
    # Example email task scheduled for 30 seconds from now
    email_task = {
        'task_type': 'send_email',
        'recipient': 'admin@example.com',
        'subject': 'Background Task Demo Complete',
        'schedule_time': 30
    }
    
    print("Creating background tasks...")
    create_task(project_id, location, queue_name, function_url, file_task)
    create_task(project_id, location, queue_name, function_url, email_task)
    
    print(f"\n✅ Tasks submitted to queue '{queue_name}'")
    print("Tasks will be processed automatically by Cloud Function")
EOF
    
    chmod +x "$script_path"
    log "INFO" "Task creation script created: $script_path"
}

# Function to test the deployment
test_deployment() {
    log "INFO" "Testing deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Wait for function to be fully deployed
    log "INFO" "Waiting for function to be fully deployed..."
    sleep 10
    
    # Test creating tasks if Python and dependencies are available
    if command -v pip3 >/dev/null 2>&1; then
        log "INFO" "Installing Python dependencies for testing..."
        pip3 install google-cloud-tasks >/dev/null 2>&1 || {
            log "WARN" "Could not install google-cloud-tasks. Manual testing required."
            return 0
        }
        
        # Set environment variables and run test
        export PROJECT_ID REGION QUEUE_NAME FUNCTION_URL
        
        if python3 "${SCRIPT_DIR}/create_task.py"; then
            log "INFO" "Test tasks created successfully"
        else
            log "WARN" "Test task creation failed. Check function logs for details."
        fi
    else
        log "WARN" "pip3 not available. Skipping automated testing."
    fi
}

# Function to display deployment summary
display_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "=================="
    log "INFO" "Project ID: $PROJECT_ID"
    log "INFO" "Region: $REGION"
    log "INFO" "Queue Name: $QUEUE_NAME"
    log "INFO" "Function Name: $FUNCTION_NAME"
    log "INFO" "Storage Bucket: $BUCKET_NAME"
    log "INFO" "Function URL: $FUNCTION_URL"
    log "INFO" "Log File: $LOG_FILE"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "1. Test the deployment by running:"
    log "INFO" "   export PROJECT_ID=$PROJECT_ID REGION=$REGION QUEUE_NAME=$QUEUE_NAME FUNCTION_URL='$FUNCTION_URL'"
    log "INFO" "   python3 ${SCRIPT_DIR}/create_task.py"
    log "INFO" ""
    log "INFO" "2. Monitor function logs:"
    log "INFO" "   gcloud functions logs read $FUNCTION_NAME --gen2 --region=$REGION --limit=10"
    log "INFO" ""
    log "INFO" "3. Check queue status:"
    log "INFO" "   gcloud tasks queues describe $QUEUE_NAME --location=$REGION"
    log "INFO" ""
    log "INFO" "4. View processed files:"
    log "INFO" "   gsutil ls gs://$BUCKET_NAME/processed/"
}

# Function to handle cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Deployment failed with exit code $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
        log "INFO" "To clean up partial deployment, run: ${SCRIPT_DIR}/destroy.sh -p $PROJECT_ID"
    fi
    exit $exit_code
}

# Main deployment function
main() {
    log "INFO" "Starting GCP Task Queue System deployment..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Set up signal handlers
    trap cleanup_on_exit EXIT
    trap 'log "ERROR" "Deployment interrupted by user"; exit 130' INT TERM
    
    # Parse command line arguments
    parse_args "$@"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup project configuration
    setup_project
    
    # Enable required APIs
    enable_apis
    
    # Create Cloud Tasks queue
    create_task_queue
    
    # Create storage bucket
    create_storage_bucket
    
    # Prepare and deploy function
    prepare_function_code
    deploy_function
    
    # Create task creation script
    create_task_script
    
    # Test the deployment
    test_deployment
    
    # Display summary
    display_summary
    
    log "INFO" "✅ GCP Task Queue System deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
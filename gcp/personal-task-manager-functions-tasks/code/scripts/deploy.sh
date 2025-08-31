#!/bin/bash

# Deploy script for Personal Task Manager with Cloud Functions and Google Tasks
# This script automates the deployment of the serverless task management solution

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
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

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly TEMP_DIR="${PROJECT_DIR}/temp"

# Default values (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-task-manager-$(date +%s)}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-task-manager}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found."
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python is available (required for Cloud Functions)
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. This is required for Cloud Functions."
        exit 1
    fi
    
    # Check if curl is available (for testing)
    if ! command -v curl &> /dev/null; then
        log_warning "curl is not installed. Testing functionality will be limited."
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Function to setup project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --name="Personal Task Manager"; then
            log_error "Failed to create project. You may need billing enabled or different project ID."
            exit 1
        fi
    fi
    
    # Set project as active
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Project setup completed: ${PROJECT_ID}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "tasks.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
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
    
    log_info "Waiting for API enablement to propagate (30 seconds)..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Function to create service account
create_service_account() {
    log_info "Creating service account for Cloud Function..."
    
    local sa_name="task-manager-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log_warning "Service account ${sa_email} already exists. Reusing existing account."
    else
        log_info "Creating service account: ${sa_name}"
        gcloud iam service-accounts create "${sa_name}" \
            --display-name="Task Manager Service Account" \
            --description="Service account for accessing Google Tasks API"
    fi
    
    # Create and download service account key
    local key_file="${TEMP_DIR}/credentials.json"
    mkdir -p "${TEMP_DIR}"
    
    if [[ -f "${key_file}" ]]; then
        log_warning "Service account key already exists. Reusing existing key."
    else
        log_info "Creating service account key..."
        gcloud iam service-accounts keys create "${key_file}" \
            --iam-account="${sa_email}"
    fi
    
    # Copy credentials to function directory
    cp "${key_file}" "${PROJECT_DIR}/function/credentials.json"
    
    log_success "Service account setup completed: ${sa_email}"
}

# Function to create function directory and files
setup_function_code() {
    log_info "Setting up Cloud Function code..."
    
    local function_dir="${PROJECT_DIR}/function"
    mkdir -p "${function_dir}"
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-api-python-client==2.150.0
google-auth==2.35.0
google-auth-httplib2==0.2.0
functions-framework==3.8.1
EOF
    
    # Create main.py with the function code
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
import functions_framework
from googleapiclient.discovery import build
from google.oauth2 import service_account
from flask import jsonify

# Initialize credentials and service
SCOPES = ['https://www.googleapis.com/auth/tasks']

def get_tasks_service():
    """Initialize Google Tasks API service with credentials."""
    credentials = service_account.Credentials.from_service_account_file(
        'credentials.json',
        scopes=SCOPES
    )
    return build('tasks', 'v1', credentials=credentials)

@functions_framework.http
def task_manager(request):
    """HTTP Cloud Function for managing Google Tasks."""
    
    # Enable CORS for web clients
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        service = get_tasks_service()
        
        if request.method == 'GET' and request.path == '/tasks':
            # List all tasks from default task list
            task_lists = service.tasklists().list().execute()
            if not task_lists.get('items'):
                return jsonify({'error': 'No task lists found'}), 404
            
            default_list = task_lists['items'][0]['id']
            tasks = service.tasks().list(tasklist=default_list).execute()
            return jsonify(tasks.get('items', [])), 200, headers
        
        elif request.method == 'POST' and request.path == '/tasks':
            # Create a new task
            request_json = request.get_json(silent=True)
            if not request_json or 'title' not in request_json:
                return jsonify({'error': 'Task title is required'}), 400
            
            task_lists = service.tasklists().list().execute()
            if not task_lists.get('items'):
                return jsonify({'error': 'No task lists found'}), 404
            
            default_list = task_lists['items'][0]['id']
            task = {
                'title': request_json['title'],
                'notes': request_json.get('notes', '')
            }
            
            result = service.tasks().insert(
                tasklist=default_list, 
                body=task
            ).execute()
            return jsonify(result), 201, headers
        
        elif request.method == 'DELETE' and '/tasks/' in request.path:
            # Delete a specific task
            task_id = request.path.split('/tasks/')[-1]
            if not task_id:
                return jsonify({'error': 'Task ID is required'}), 400
            
            task_lists = service.tasklists().list().execute()
            if not task_lists.get('items'):
                return jsonify({'error': 'No task lists found'}), 404
            
            default_list = task_lists['items'][0]['id']
            service.tasks().delete(
                tasklist=default_list, 
                task=task_id
            ).execute()
            return jsonify({'message': 'Task deleted successfully'}), 200, headers
        
        else:
            return jsonify({'error': 'Endpoint not found'}), 404, headers
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500, headers
EOF
    
    log_success "Function code setup completed"
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    
    local function_dir="${PROJECT_DIR}/function"
    
    # Change to function directory for deployment
    cd "${function_dir}"
    
    # Deploy the function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point task_manager \
        --source . \
        --memory 256MB \
        --timeout 60s \
        --region "${REGION}" \
        --quiet; then
        
        log_success "Cloud Function deployed successfully"
        
        # Get function URL
        local function_url
        function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(httpsTrigger.url)")
        
        log_success "Function URL: ${function_url}"
        
        # Save URL to file for easy access
        echo "${function_url}" > "${PROJECT_DIR}/function_url.txt"
        
        return 0
    else
        log_error "Failed to deploy Cloud Function"
        return 1
    fi
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    if [[ ! -f "${PROJECT_DIR}/function_url.txt" ]]; then
        log_error "Function URL not found. Deployment may have failed."
        return 1
    fi
    
    local function_url
    function_url=$(cat "${PROJECT_DIR}/function_url.txt")
    
    if ! command -v curl &> /dev/null; then
        log_warning "curl not available. Skipping automated tests."
        log_info "You can manually test at: ${function_url}"
        return 0
    fi
    
    log_info "Testing task creation..."
    local test_response
    test_response=$(curl -s -w "%{http_code}" -X POST "${function_url}/tasks" \
        -H "Content-Type: application/json" \
        -d '{
            "title": "Test deployment task",
            "notes": "Created by deployment script"
        }' || echo "000")
    
    local http_code="${test_response: -3}"
    
    if [[ "${http_code}" == "201" ]]; then
        log_success "Task creation test passed"
        
        log_info "Testing task listing..."
        local list_response
        list_response=$(curl -s -w "%{http_code}" -X GET "${function_url}/tasks" || echo "000")
        local list_http_code="${list_response: -3}"
        
        if [[ "${list_http_code}" == "200" ]]; then
            log_success "Task listing test passed"
            log_success "All tests passed successfully!"
        else
            log_warning "Task listing test failed (HTTP ${list_http_code})"
        fi
    else
        log_warning "Task creation test failed (HTTP ${http_code})"
        log_info "The function may still be initializing. Try testing manually in a few minutes."
    fi
    
    log_info "Manual testing URL: ${function_url}"
}

# Function to save deployment info
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${PROJECT_DIR}/deployment_info.json"
    
    cat > "${info_file}" << EOF
{
    "project_id": "${PROJECT_ID}",
    "region": "${REGION}",
    "function_name": "${FUNCTION_NAME}",
    "deployment_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "function_url": "$(cat "${PROJECT_DIR}/function_url.txt" 2>/dev/null || echo 'URL not available')",
    "service_account": "task-manager-sa@${PROJECT_ID}.iam.gserviceaccount.com"
}
EOF
    
    log_success "Deployment info saved to: ${info_file}"
}

# Function to display summary
display_summary() {
    log_success "=== DEPLOYMENT SUMMARY ==="
    echo
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    
    if [[ -f "${PROJECT_DIR}/function_url.txt" ]]; then
        local function_url
        function_url=$(cat "${PROJECT_DIR}/function_url.txt")
        log_info "Function URL: ${function_url}"
        echo
        log_info "Test commands:"
        echo "  # Create a task:"
        echo "  curl -X POST '${function_url}/tasks' \\"
        echo "    -H 'Content-Type: application/json' \\"
        echo "    -d '{\"title\":\"My task\",\"notes\":\"Task notes\"}'"
        echo
        echo "  # List tasks:"
        echo "  curl -X GET '${function_url}/tasks'"
    fi
    
    echo
    log_info "To clean up resources, run: ./destroy.sh"
    echo
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed with exit code ${exit_code}"
        log_info "Check the logs above for error details"
        log_info "You may need to clean up partial resources manually"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy Personal Task Manager with Cloud Functions and Google Tasks"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID     Google Cloud Project ID (default: task-manager-\$(date +%s))"
    echo "  REGION         Deployment region (default: us-central1)"
    echo "  FUNCTION_NAME  Cloud Function name (default: task-manager)"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Check prerequisites without deploying"
    echo
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  PROJECT_ID=my-project $0              # Deploy to specific project"
    echo "  REGION=us-east1 $0                    # Deploy to specific region"
    echo "  $0 --dry-run                          # Check prerequisites only"
}

# Main execution function
main() {
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up exit trap
    trap cleanup_on_exit EXIT
    
    log_info "Starting deployment of Personal Task Manager..."
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    echo
    
    # Run prerequisite checks
    check_prerequisites
    
    if [[ "${dry_run}" == "true" ]]; then
        log_success "Dry run completed successfully. Prerequisites are satisfied."
        exit 0
    fi
    
    # Execute deployment steps
    setup_project
    enable_apis
    create_service_account
    setup_function_code
    
    if deploy_function; then
        test_deployment
        save_deployment_info
        display_summary
        log_success "Deployment completed successfully!"
    else
        log_error "Deployment failed during function deployment"
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
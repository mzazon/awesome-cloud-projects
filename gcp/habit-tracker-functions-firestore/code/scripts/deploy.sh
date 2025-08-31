#!/bin/bash

# ============================================================================
# GCP Habit Tracker Deployment Script
# Simple Habit Tracker with Cloud Functions and Firestore
# ============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly FUNCTION_SOURCE_DIR="${SCRIPT_DIR}/../function-source"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handler
handle_error() {
    local line_number=$1
    error "Deployment failed at line $line_number"
    error "Check the log file: $LOG_FILE"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Clean up on exit
cleanup() {
    if [[ -d "$FUNCTION_SOURCE_DIR" ]]; then
        rm -rf "$FUNCTION_SOURCE_DIR"
        info "Cleaned up temporary function source directory"
    fi
}

trap cleanup EXIT

# Initialize log file
echo "# GCP Habit Tracker Deployment Log - $(date)" > "$LOG_FILE"

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3.9 or later"
        exit 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
    if [[ $(echo "$python_version < 3.9" | bc -l) -eq 1 ]]; then
        error "Python 3.9 or later is required. Current version: $python_version"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# ============================================================================
# Project Setup
# ============================================================================

setup_project() {
    info "Setting up GCP project..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="habit-tracker-$(date +%s)"
        info "Generated project ID: $PROJECT_ID"
    fi
    
    # Set default region and zone if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="${FUNCTION_NAME:-habit-tracker-${RANDOM_SUFFIX}}"
    
    info "Project configuration:"
    info "  Project ID: $PROJECT_ID"
    info "  Region: $REGION"
    info "  Zone: $ZONE"
    info "  Function Name: $FUNCTION_NAME"
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Habit Tracker" || {
            error "Failed to create project. You may need billing account setup."
            error "Please visit: https://console.cloud.google.com/billing"
            exit 1
        }
    else
        info "Using existing project: $PROJECT_ID"
    fi
    
    # Set current project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "Project setup completed"
}

# ============================================================================
# Enable APIs
# ============================================================================

enable_apis() {
    info "Enabling required APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling $api..."
        gcloud services enable "$api" || {
            error "Failed to enable $api"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "APIs enabled successfully"
}

# ============================================================================
# Create Firestore Database
# ============================================================================

create_firestore() {
    info "Creating Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases list --format="value(name)" | grep -q "projects/$PROJECT_ID/databases/(default)"; then
        info "Firestore database already exists"
        return 0
    fi
    
    # Create Firestore database in Native mode
    gcloud firestore databases create --region="$REGION" || {
        error "Failed to create Firestore database"
        exit 1
    }
    
    # Wait for database to be ready
    info "Waiting for Firestore database to be ready..."
    local max_attempts=12
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if gcloud firestore databases list --format="value(name)" | grep -q "projects/$PROJECT_ID/databases/(default)"; then
            success "Firestore database created successfully"
            return 0
        fi
        
        info "Waiting for database... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    error "Timeout waiting for Firestore database creation"
    exit 1
}

# ============================================================================
# Prepare Function Source Code
# ============================================================================

prepare_function_source() {
    info "Preparing Cloud Function source code..."
    
    # Create temporary directory for function source
    mkdir -p "$FUNCTION_SOURCE_DIR"
    
    # Create main.py with the habit tracker function
    cat > "$FUNCTION_SOURCE_DIR/main.py" << 'EOF'
import json
from datetime import datetime, timezone
from flask import Request
import functions_framework
from google.cloud import firestore

# Initialize Firestore client
db = firestore.Client()
COLLECTION_NAME = 'habits'

@functions_framework.http
def habit_tracker(request: Request):
    """HTTP Cloud Function for habit tracking CRUD operations."""
    
    # Set CORS headers for web client compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        if request.method == 'POST':
            return create_habit(request, headers)
        elif request.method == 'GET':
            return get_habits(request, headers)
        elif request.method == 'PUT':
            return update_habit(request, headers)
        elif request.method == 'DELETE':
            return delete_habit(request, headers)
        else:
            return (json.dumps({'error': 'Method not allowed'}), 405, headers)
    
    except Exception as e:
        return (json.dumps({'error': str(e)}), 500, headers)

def create_habit(request: Request, headers):
    """Create a new habit record."""
    data = request.get_json()
    
    if not data or 'name' not in data:
        return (json.dumps({'error': 'Habit name is required'}), 400, headers)
    
    habit_data = {
        'name': data['name'],
        'description': data.get('description', ''),
        'completed': data.get('completed', False),
        'created_at': datetime.now(timezone.utc),
        'updated_at': datetime.now(timezone.utc)
    }
    
    # Create new document with auto-generated ID
    doc_ref, doc_id = db.collection(COLLECTION_NAME).add(habit_data)
    
    habit_data['id'] = doc_id.id
    habit_data['created_at'] = habit_data['created_at'].isoformat()
    habit_data['updated_at'] = habit_data['updated_at'].isoformat()
    
    return (json.dumps(habit_data), 201, headers)

def get_habits(request: Request, headers):
    """Retrieve all habit records or a specific habit by ID."""
    habit_id = request.args.get('id')
    
    if habit_id:
        # Get specific habit
        doc_ref = db.collection(COLLECTION_NAME).document(habit_id)
        doc = doc_ref.get()
        
        if not doc.exists:
            return (json.dumps({'error': 'Habit not found'}), 404, headers)
        
        habit = doc.to_dict()
        habit['id'] = doc.id
        habit['created_at'] = habit['created_at'].isoformat()
        habit['updated_at'] = habit['updated_at'].isoformat()
        
        return (json.dumps(habit), 200, headers)
    else:
        # Get all habits
        habits = []
        docs = db.collection(COLLECTION_NAME).order_by('created_at').stream()
        
        for doc in docs:
            habit = doc.to_dict()
            habit['id'] = doc.id
            habit['created_at'] = habit['created_at'].isoformat()
            habit['updated_at'] = habit['updated_at'].isoformat()
            habits.append(habit)
        
        return (json.dumps(habits), 200, headers)

def update_habit(request: Request, headers):
    """Update an existing habit record."""
    habit_id = request.args.get('id')
    
    if not habit_id:
        return (json.dumps({'error': 'Habit ID is required'}), 400, headers)
    
    data = request.get_json()
    if not data:
        return (json.dumps({'error': 'Request body is required'}), 400, headers)
    
    doc_ref = db.collection(COLLECTION_NAME).document(habit_id)
    doc = doc_ref.get()
    
    if not doc.exists:
        return (json.dumps({'error': 'Habit not found'}), 404, headers)
    
    # Update allowed fields
    update_data = {}
    if 'name' in data:
        update_data['name'] = data['name']
    if 'description' in data:
        update_data['description'] = data['description']
    if 'completed' in data:
        update_data['completed'] = data['completed']
    
    update_data['updated_at'] = datetime.now(timezone.utc)
    
    # Update the document
    doc_ref.update(update_data)
    
    # Return updated document
    updated_doc = doc_ref.get()
    habit = updated_doc.to_dict()
    habit['id'] = updated_doc.id
    habit['created_at'] = habit['created_at'].isoformat()
    habit['updated_at'] = habit['updated_at'].isoformat()
    
    return (json.dumps(habit), 200, headers)

def delete_habit(request: Request, headers):
    """Delete a habit record."""
    habit_id = request.args.get('id')
    
    if not habit_id:
        return (json.dumps({'error': 'Habit ID is required'}), 400, headers)
    
    doc_ref = db.collection(COLLECTION_NAME).document(habit_id)
    doc = doc_ref.get()
    
    if not doc.exists:
        return (json.dumps({'error': 'Habit not found'}), 404, headers)
    
    # Delete the document
    doc_ref.delete()
    
    return (json.dumps({'message': 'Habit deleted successfully'}), 200, headers)
EOF
    
    # Create requirements.txt
    cat > "$FUNCTION_SOURCE_DIR/requirements.txt" << 'EOF'
google-cloud-firestore==2.21.0
functions-framework==3.8.3
EOF
    
    success "Function source code prepared"
}

# ============================================================================
# Deploy Cloud Function
# ============================================================================

deploy_function() {
    info "Deploying Cloud Function..."
    
    cd "$FUNCTION_SOURCE_DIR"
    
    # Deploy the function with proper configuration
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point habit_tracker \
        --memory 256MB \
        --timeout 60s \
        --region "$REGION" \
        --quiet || {
        error "Failed to deploy Cloud Function"
        exit 1
    }
    
    # Get function URL
    export FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    if [[ -z "$FUNCTION_URL" ]]; then
        error "Failed to retrieve function URL"
        exit 1
    fi
    
    success "Cloud Function deployed successfully"
    success "Function URL: $FUNCTION_URL"
    
    cd "$SCRIPT_DIR"
}

# ============================================================================
# Test Deployment
# ============================================================================

test_deployment() {
    info "Testing deployment..."
    
    if [[ -z "${FUNCTION_URL:-}" ]]; then
        error "Function URL not available for testing"
        exit 1
    fi
    
    # Test CREATE operation
    info "Testing CREATE operation..."
    local test_response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Test Habit",
            "description": "Test habit for deployment verification",
            "completed": false
        }' || echo "curl_failed")
    
    if [[ "$test_response" == "curl_failed" ]]; then
        error "Failed to test CREATE operation"
        exit 1
    fi
    
    # Extract habit ID from response for further testing
    local habit_id=$(echo "$test_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
    
    if [[ -z "$habit_id" ]]; then
        warn "Could not extract habit ID from response, skipping further tests"
        warn "Response: $test_response"
    else
        success "CREATE operation successful (ID: $habit_id)"
        
        # Test READ operation
        info "Testing READ operation..."
        local read_response=$(curl -s "$FUNCTION_URL" || echo "curl_failed")
        
        if [[ "$read_response" == "curl_failed" ]]; then
            warn "READ operation test failed"
        else
            success "READ operation successful"
        fi
        
        # Test DELETE operation (cleanup test data)
        info "Cleaning up test data..."
        curl -s -X DELETE "$FUNCTION_URL?id=$habit_id" &> /dev/null || warn "Failed to cleanup test data"
    fi
    
    success "Deployment testing completed"
}

# ============================================================================
# Save Deployment Info
# ============================================================================

save_deployment_info() {
    info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment-info.env"
    
    cat > "$info_file" << EOF
# Habit Tracker Deployment Information
# Generated: $(date)

PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_URL=$FUNCTION_URL

# Usage Examples:
# Create habit: curl -X POST $FUNCTION_URL -H "Content-Type: application/json" -d '{"name": "Daily Exercise", "description": "30 minutes workout", "completed": false}'
# Get all habits: curl $FUNCTION_URL
# Get specific habit: curl "$FUNCTION_URL?id=HABIT_ID"
# Update habit: curl -X PUT "$FUNCTION_URL?id=HABIT_ID" -H "Content-Type: application/json" -d '{"completed": true}'
# Delete habit: curl -X DELETE "$FUNCTION_URL?id=HABIT_ID"
EOF
    
    success "Deployment information saved to: $info_file"
}

# ============================================================================
# Main Deployment Flow
# ============================================================================

main() {
    info "Starting GCP Habit Tracker deployment..."
    info "Log file: $LOG_FILE"
    
    # Check for dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "DRY RUN MODE - No resources will be created"
        check_prerequisites
        info "Dry run completed successfully"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_firestore
    prepare_function_source
    deploy_function
    test_deployment
    save_deployment_info
    
    success "=========================================="
    success "Deployment completed successfully!"
    success "=========================================="
    success "Project ID: $PROJECT_ID"
    success "Function Name: $FUNCTION_NAME"
    success "Function URL: $FUNCTION_URL"
    success "Region: $REGION"
    success ""
    success "Next steps:"
    success "1. Test the API using the examples in deployment-info.env"
    success "2. Check the Cloud Console: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    success "3. Monitor logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    success ""
    success "To clean up resources, run: ./destroy.sh"
    success "=========================================="
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
GCP Habit Tracker Deployment Script

Usage: $0 [OPTIONS]

Options:
  --dry-run     Validate prerequisites without creating resources
  --help, -h    Show this help message

Environment Variables:
  PROJECT_ID    GCP project ID (auto-generated if not set)
  REGION        GCP region (default: us-central1)
  ZONE          GCP zone (default: us-central1-a)
  FUNCTION_NAME Function name (auto-generated if not set)

Examples:
  $0                    # Normal deployment
  $0 --dry-run         # Validate without deploying
  PROJECT_ID=my-project $0  # Use specific project ID

For more information, see the recipe documentation.
EOF
    exit 0
fi

# Run main function
main "$@"
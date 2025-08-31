#!/bin/bash

# Deploy script for Tip Calculator API with Cloud Functions
# This script deploys a serverless tip calculator API using Google Cloud Functions

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

# Exit on error with cleanup
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Clean up any partial resources if needed
    exit 1
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python is available (needed for local testing)
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_warning "Python is not available. Local testing will be skipped."
    fi
    
    # Check if curl is available (needed for testing)
    if ! command -v curl &> /dev/null; then
        log_warning "curl is not available. Function testing will be skipped."
    fi
    
    # Check if pip is available
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        log_warning "pip is not available. Local testing will be skipped."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-tip-calc-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-tip-calculator}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    
    # Check if project exists, create if it doesn't and user confirms
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} does not exist."
        read -p "Do you want to create a new project? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gcloud projects create "${PROJECT_ID}" --name="Tip Calculator API" || {
                log_error "Failed to create project. You may need billing enabled or different project ID."
                exit 1
            }
            log_success "Project ${PROJECT_ID} created"
        else
            log_error "Project ${PROJECT_ID} is required. Exiting."
            exit 1
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Environment setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudfunctions.googleapis.com"
        "run.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || {
            log_error "Failed to enable ${api}"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create function source code
create_function_code() {
    log_info "Creating function source code..."
    
    # Create project directory
    mkdir -p tip-calculator-function
    cd tip-calculator-function
    
    # Create the main function file
    cat > main.py << 'EOF'
import json
from flask import Request
import functions_framework

@functions_framework.http
def calculate_tip(request: Request):
    """
    Calculate tip amounts and split bills among multiple people.
    
    Request JSON format:
    {
        "bill_amount": 100.00,
        "tip_percentage": 18,
        "number_of_people": 4
    }
    """
    
    # Set CORS headers for web applications
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request data
        if request.method == 'GET':
            bill_amount = float(request.args.get('bill_amount', 0))
            tip_percentage = float(request.args.get('tip_percentage', 15))
            number_of_people = int(request.args.get('number_of_people', 1))
        else:  # POST request
            request_json = request.get_json(silent=True)
            if not request_json:
                return (json.dumps({'error': 'No JSON data provided'}), 400, headers)
            
            bill_amount = float(request_json.get('bill_amount', 0))
            tip_percentage = float(request_json.get('tip_percentage', 15))
            number_of_people = int(request_json.get('number_of_people', 1))
        
        # Validate input parameters
        if bill_amount <= 0:
            return (json.dumps({'error': 'Bill amount must be greater than 0'}), 400, headers)
        
        if tip_percentage < 0 or tip_percentage > 100:
            return (json.dumps({'error': 'Tip percentage must be between 0 and 100'}), 400, headers)
        
        if number_of_people <= 0:
            return (json.dumps({'error': 'Number of people must be greater than 0'}), 400, headers)
        
        # Calculate tip and totals
        tip_amount = bill_amount * (tip_percentage / 100)
        total_amount = bill_amount + tip_amount
        per_person_bill = bill_amount / number_of_people
        per_person_tip = tip_amount / number_of_people
        per_person_total = total_amount / number_of_people
        
        # Prepare response
        response_data = {
            'input': {
                'bill_amount': round(bill_amount, 2),
                'tip_percentage': tip_percentage,
                'number_of_people': number_of_people
            },
            'calculations': {
                'tip_amount': round(tip_amount, 2),
                'total_amount': round(total_amount, 2),
                'per_person': {
                    'bill_share': round(per_person_bill, 2),
                    'tip_share': round(per_person_tip, 2),
                    'total_share': round(per_person_total, 2)
                }
            },
            'formatted_summary': f"Bill: ${bill_amount:.2f} | Tip ({tip_percentage}%): ${tip_amount:.2f} | Total: ${total_amount:.2f} | Per person: ${per_person_total:.2f}"
        }
        
        return (json.dumps(response_data, indent=2), 200, headers)
        
    except ValueError as e:
        return (json.dumps({'error': f'Invalid input: {str(e)}'}), 400, headers)
    except Exception as e:
        return (json.dumps({'error': f'Internal error: {str(e)}'}), 500, headers)
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
functions-framework==3.*
flask>=2.0.0
EOF
    
    log_success "Function source code created"
}

# Function to test locally (optional)
test_locally() {
    if command -v python3 &> /dev/null && command -v pip3 &> /dev/null; then
        log_info "Testing function locally (optional)..."
        
        # Install dependencies locally for testing
        python3 -m pip install -r requirements.txt --user --quiet || {
            log_warning "Failed to install dependencies locally. Skipping local test."
            return
        }
        
        # Start local development server in background
        python3 -m functions_framework --target=calculate_tip --debug &
        LOCAL_PID=$!
        
        # Wait for server to start
        sleep 5
        
        # Test if server is responding
        if command -v curl &> /dev/null; then
            if curl -s http://localhost:8080 > /dev/null 2>&1; then
                log_success "Local function server started successfully"
            else
                log_warning "Local function server may not have started properly"
            fi
        fi
        
        # Stop local development server
        kill $LOCAL_PID 2>/dev/null || true
        sleep 2
        
        log_info "Local testing completed"
    else
        log_info "Skipping local testing (Python/pip not available)"
    fi
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    # Deploy function with HTTP trigger
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point calculate_tip \
        --region "${REGION}" \
        --memory 256MB \
        --timeout 60s \
        --max-instances 100 || {
        log_error "Failed to deploy Cloud Function"
        exit 1
    }
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region "${REGION}" \
        --format="value(httpsTrigger.url)") || {
        log_error "Failed to get function URL"
        exit 1
    }
    
    # Update function with metadata
    gcloud functions deploy "${FUNCTION_NAME}" \
        --update-labels environment=demo,type=calculator \
        --description "Serverless tip calculator API for restaurant bills" \
        --region "${REGION}" || {
        log_warning "Failed to update function metadata, but function is deployed"
    }
    
    log_success "Function deployed successfully"
    log_success "Function URL: ${FUNCTION_URL}"
    
    # Store function URL for testing
    export FUNCTION_URL
}

# Function to test deployed function
test_deployed_function() {
    if command -v curl &> /dev/null && [ -n "${FUNCTION_URL:-}" ]; then
        log_info "Testing deployed function..."
        
        # Test basic functionality
        log_info "Testing GET request..."
        RESPONSE=$(curl -s "${FUNCTION_URL}?bill_amount=100&tip_percentage=18&number_of_people=4" \
            -H "Content-Type: application/json" || true)
        
        if echo "$RESPONSE" | grep -q "total_amount"; then
            log_success "GET request test passed"
        else
            log_warning "GET request test may have failed. Response: $RESPONSE"
        fi
        
        # Test POST request
        log_info "Testing POST request..."
        cat > test_data.json << 'EOF'
{
  "bill_amount": 87.45,
  "tip_percentage": 20,
  "number_of_people": 3
}
EOF
        
        RESPONSE=$(curl -s -X POST "${FUNCTION_URL}" \
            -H "Content-Type: application/json" \
            -d @test_data.json || true)
        
        if echo "$RESPONSE" | grep -q "total_amount"; then
            log_success "POST request test passed"
        else
            log_warning "POST request test may have failed. Response: $RESPONSE"
        fi
        
        # Test error handling
        log_info "Testing error handling..."
        RESPONSE=$(curl -s "${FUNCTION_URL}?bill_amount=-50&tip_percentage=15" \
            -H "Content-Type: application/json" || true)
        
        if echo "$RESPONSE" | grep -q "error"; then
            log_success "Error handling test passed"
        else
            log_warning "Error handling test may have failed"
        fi
        
        # Clean up test file
        rm -f test_data.json
        
        log_success "Function testing completed"
    else
        log_info "Skipping function testing (curl not available or function URL missing)"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "=== Deployment Summary ==="
    echo -e "${GREEN}Project ID:${NC} ${PROJECT_ID}"
    echo -e "${GREEN}Region:${NC} ${REGION}"
    echo -e "${GREEN}Function Name:${NC} ${FUNCTION_NAME}"
    if [ -n "${FUNCTION_URL:-}" ]; then
        echo -e "${GREEN}Function URL:${NC} ${FUNCTION_URL}"
        echo
        echo -e "${BLUE}Test your function:${NC}"
        echo "curl \"${FUNCTION_URL}?bill_amount=100&tip_percentage=18&number_of_people=4\""
        echo
        echo -e "${BLUE}Or with POST:${NC}"
        echo "curl -X POST \"${FUNCTION_URL}\" -H \"Content-Type: application/json\" -d '{\"bill_amount\": 87.45, \"tip_percentage\": 20, \"number_of_people\": 3}'"
    fi
    echo
    echo -e "${YELLOW}To clean up resources, run:${NC} ./destroy.sh"
    echo -e "${YELLOW}Estimated monthly cost:${NC} $0.00 (within free tier for typical usage)"
}

# Main deployment function
main() {
    log_info "Starting deployment of Tip Calculator API..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_function_code
    test_locally
    deploy_function
    test_deployed_function
    
    # Go back to original directory
    cd ..
    
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
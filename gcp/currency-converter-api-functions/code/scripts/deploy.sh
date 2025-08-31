#!/bin/bash

# Currency Converter API with Cloud Functions - Deployment Script
# This script deploys a serverless currency converter API using Google Cloud Functions
# and Secret Manager for secure API key storage.

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

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to validate environment variables
validate_env() {
    local var_name=$1
    local var_value=${!var_name:-}
    
    if [[ -z "$var_value" ]]; then
        log_error "Environment variable $var_name is not set or empty."
        return 1
    fi
}

# Function to prompt for user confirmation
confirm_action() {
    local message=$1
    local response
    
    read -p "$message (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for operation completion
wait_for_operation() {
    local operation=$1
    local timeout=300  # 5 minutes timeout
    local elapsed=0
    
    log_info "Waiting for operation to complete: $operation"
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(gcloud operations describe "$operation" --format="value(status)" 2>/dev/null || echo "PENDING")
        
        if [[ "$status" == "DONE" ]]; then
            log_success "Operation completed successfully"
            return 0
        elif [[ "$status" == "ERROR" ]]; then
            log_error "Operation failed"
            return 1
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done
    
    log_error "Operation timed out after $timeout seconds"
    return 1
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local additional_flags=${3:-}
    
    gcloud "$resource_type" describe "$resource_name" $additional_flags &>/dev/null
}

# Main deployment function
deploy_currency_converter() {
    log_info "Starting Currency Converter API deployment..."
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command "gcloud"
    check_command "curl"
    check_command "openssl"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &>/dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Set default environment variables if not already set
    export PROJECT_ID=${PROJECT_ID:-"currency-converter-$(date +%s)"}
    export REGION=${REGION:-"us-central1"}
    export FUNCTION_NAME=${FUNCTION_NAME:-"currency-converter"}
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SECRET_NAME=${SECRET_NAME:-"exchange-api-key-${RANDOM_SUFFIX}"}
    
    log_info "Deployment configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Secret Name: $SECRET_NAME"
    
    # Confirm deployment
    if ! confirm_action "Do you want to proceed with the deployment?"; then
        log_info "Deployment cancelled by user."
        exit 0
    fi
    
    # Prompt for API key if not set
    if [[ -z "${EXCHANGE_API_KEY:-}" ]]; then
        log_warning "Exchange API key not found in environment variable EXCHANGE_API_KEY"
        log_info "You can get a free API key from https://fixer.io"
        read -s -p "Please enter your exchange API key: " EXCHANGE_API_KEY
        echo
        
        if [[ -z "$EXCHANGE_API_KEY" ]]; then
            log_error "API key is required for deployment."
            exit 1
        fi
        export EXCHANGE_API_KEY
    fi
    
    # Set gcloud project and region
    log_info "Configuring gcloud project and region..."
    gcloud config set project "$PROJECT_ID" || {
        log_error "Failed to set project. Make sure the project exists and you have access."
        exit 1
    }
    gcloud config set compute/region "$REGION"
    
    # Enable required APIs
    log_info "Enabling required Google Cloud APIs..."
    local apis=(
        "cloudfunctions.googleapis.com"
        "secretmanager.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "  Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "  $api enabled"
        else
            log_error "  Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully activated
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    # Create Secret Manager secret
    log_info "Creating Secret Manager secret for API key..."
    if resource_exists "secrets" "$SECRET_NAME"; then
        log_warning "Secret $SECRET_NAME already exists. Updating it..."
        echo -n "$EXCHANGE_API_KEY" | gcloud secrets versions add "$SECRET_NAME" --data-file=-
    else
        echo -n "$EXCHANGE_API_KEY" | gcloud secrets create "$SECRET_NAME" --data-file=-
    fi
    log_success "Secret created/updated: $SECRET_NAME"
    
    # Create function source code directory
    log_info "Creating function source code..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import requests
import json
from google.cloud import secretmanager

# Initialize Secret Manager client
secret_client = secretmanager.SecretManagerServiceClient()

def get_api_key():
    """Retrieve API key from Secret Manager"""
    import os
    project_id = os.environ.get('GCP_PROJECT')
    secret_name = os.environ.get('SECRET_NAME')
    
    name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = secret_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def currency_converter(request):
    """HTTP Cloud Function for currency conversion"""
    
    # Set CORS headers for web browsers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request parameters
        if request.method == 'GET':
            from_currency = request.args.get('from', 'USD')
            to_currency = request.args.get('to', 'EUR')
            amount = float(request.args.get('amount', '1'))
        else:
            request_json = request.get_json()
            from_currency = request_json.get('from', 'USD')
            to_currency = request_json.get('to', 'EUR')
            amount = float(request_json.get('amount', '1'))
        
        # Get API key from Secret Manager
        api_key = get_api_key()
        
        # Call exchange rate API (use HTTPS for security)
        url = f"https://data.fixer.io/api/convert"
        params = {
            'access_key': api_key,
            'from': from_currency,
            'to': to_currency,
            'amount': amount
        }
        
        response = requests.get(url, params=params)
        data = response.json()
        
        if data.get('success'):
            result = {
                'success': True,
                'from': from_currency,
                'to': to_currency,
                'amount': amount,
                'result': data['result'],
                'rate': data['info']['rate'],
                'timestamp': data['date']
            }
        else:
            result = {
                'success': False,
                'error': data.get('error', {}).get('info', 'Unknown error')
            }
        
        return (json.dumps(result), 200, headers)
        
    except Exception as e:
        error_result = {
            'success': False,
            'error': f'Internal error: {str(e)}'
        }
        return (json.dumps(error_result), 500, headers)
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework>=3.0.0,<4.0.0
google-cloud-secret-manager>=2.16.0,<3.0.0
requests>=2.31.0,<3.0.0
EOF
    
    log_success "Function source code created in temporary directory"
    
    # Deploy the Cloud Function
    log_info "Deploying Cloud Function..."
    if gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point currency_converter \
        --memory 256MB \
        --timeout 60s \
        --region="$REGION" \
        --set-env-vars "GCP_PROJECT=$PROJECT_ID,SECRET_NAME=$SECRET_NAME" \
        --quiet; then
        log_success "Function deployed successfully"
    else
        log_error "Failed to deploy function"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    # Grant function access to Secret Manager
    log_info "Configuring Secret Manager permissions..."
    
    # Get the function's service account
    FUNCTION_SA=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(serviceAccountEmail)")
    
    if [[ -z "$FUNCTION_SA" ]]; then
        log_error "Failed to get function service account"
        exit 1
    fi
    
    # Grant secret accessor role to function service account
    if gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
        --member="serviceAccount:$FUNCTION_SA" \
        --role="roles/secretmanager.secretAccessor" \
        --quiet; then
        log_success "Secret access permissions granted to: $FUNCTION_SA"
    else
        log_error "Failed to grant secret access permissions"
        exit 1
    fi
    
    # Get the function URL
    log_info "Retrieving function URL..."
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    if [[ -z "$FUNCTION_URL" ]]; then
        log_error "Failed to retrieve function URL"
        exit 1
    fi
    
    # Test the function
    log_info "Testing the deployed function..."
    if curl -s -f "$FUNCTION_URL?from=USD&to=EUR&amount=100" > /dev/null; then
        log_success "Function is responding correctly"
    else
        log_warning "Function may not be responding correctly. Please check the logs."
    fi
    
    # Display deployment summary
    echo
    log_success "=== DEPLOYMENT COMPLETE ==="
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Function URL: $FUNCTION_URL"
    log_info "Secret Name: $SECRET_NAME"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    echo
    log_info "Test your function with:"
    echo "  curl \"$FUNCTION_URL?from=USD&to=EUR&amount=100\""
    echo
    log_info "To clean up resources, run: ./destroy.sh"
    
    # Save deployment info for cleanup script
    cat > .deployment_info << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
FUNCTION_NAME=$FUNCTION_NAME
SECRET_NAME=$SECRET_NAME
FUNCTION_URL=$FUNCTION_URL
EOF
    
    log_success "Deployment information saved to .deployment_info"
}

# Trap to ensure cleanup on script exit
cleanup_on_exit() {
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup_on_exit EXIT

# Main execution
main() {
    log_info "Currency Converter API Deployment Script"
    log_info "========================================"
    
    deploy_currency_converter
    
    log_success "Deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
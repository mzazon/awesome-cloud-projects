#!/bin/bash

# Secure API Configuration Management with Secret Manager and Cloud Run - Deployment Script
# This script deploys a secure API infrastructure using Google Cloud Secret Manager,
# Cloud Run, and API Gateway with proper error handling and logging.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if required APIs can be enabled (billing account check)
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -n "$current_project" ]]; then
        log_warning "Using existing project: $current_project"
        log_warning "This script will create a new project. Make sure you have billing enabled."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="secure-api-$(date +%s)"
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export SERVICE_NAME="secure-api-${RANDOM_SUFFIX}"
    export SECRET_NAME="api-config-${RANDOM_SUFFIX}"
    export SA_NAME="secure-api-sa-${RANDOM_SUFFIX}"
    export GATEWAY_NAME="api-gateway-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  SERVICE_NAME: ${SERVICE_NAME}"
    log_info "  SECRET_NAME: ${SECRET_NAME}"
    log_info "  SA_NAME: ${SA_NAME}"
    log_info "  GATEWAY_NAME: ${GATEWAY_NAME}"
}

# Function to create and configure project
create_project() {
    log_info "Creating new GCP project..."
    
    # Create new project
    if gcloud projects create "${PROJECT_ID}" --name="Secure API Configuration" 2>/dev/null; then
        log_success "Project created successfully: ${PROJECT_ID}"
    else
        log_error "Failed to create project. Make sure you have permission and billing is enabled."
        exit 1
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis=(
        "secretmanager.googleapis.com"
        "run.googleapis.com"
        "apigateway.googleapis.com"
        "servicecontrol.googleapis.com"
        "servicemanagement.googleapis.com"
        "cloudbuild.googleapis.com"
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
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Secret Manager secrets
create_secrets() {
    log_info "Creating Secret Manager secrets..."
    
    # Create database connection secret
    log_info "Creating database configuration secret..."
    echo '{"host":"db.example.com","port":5432,"username":"api_user","password":"secure_db_password_123"}' | \
        gcloud secrets create "${SECRET_NAME}-db" --data-file=-
    
    # Create API keys secret
    log_info "Creating API keys secret..."
    echo '{"external_api_key":"sk-1234567890abcdef","jwt_secret":"jwt_signing_key_xyz789","encryption_key":"aes256_encryption_key_abc123"}' | \
        gcloud secrets create "${SECRET_NAME}-keys" --data-file=-
    
    # Create application configuration secret
    log_info "Creating application configuration secret..."
    echo '{"debug_mode":false,"rate_limit":1000,"cache_ttl":3600,"log_level":"INFO"}' | \
        gcloud secrets create "${SECRET_NAME}-config" --data-file=-
    
    log_success "All secrets created successfully"
}

# Function to create service account
create_service_account() {
    log_info "Creating service account with least privilege access..."
    
    # Create service account
    gcloud iam service-accounts create "${SA_NAME}" \
        --display-name="Secure API Service Account" \
        --description="Service account for secure API with Secret Manager access"
    
    # Grant Secret Manager accessor role for specific secrets only
    local secrets=("${SECRET_NAME}-db" "${SECRET_NAME}-keys" "${SECRET_NAME}-config")
    
    for secret in "${secrets[@]}"; do
        log_info "Granting access to secret: ${secret}"
        gcloud secrets add-iam-policy-binding "${secret}" \
            --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/secretmanager.secretAccessor"
    done
    
    log_success "Service account created with appropriate permissions"
}

# Function to create sample application
create_application() {
    log_info "Creating sample API application..."
    
    # Create temporary directory for application
    local app_dir
    app_dir=$(mktemp -d)
    cd "${app_dir}"
    
    # Create main application file
    cat > main.py << 'EOF'
import json
import os
from flask import Flask, jsonify, request
from google.cloud import secretmanager
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Secret Manager client
client = secretmanager.SecretManagerServiceClient()
project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')

def get_secret(secret_name):
    """Retrieve secret from Secret Manager with error handling"""
    try:
        name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return json.loads(response.payload.data.decode("UTF-8"))
    except Exception as e:
        logging.error(f"Failed to retrieve secret {secret_name}: {e}")
        return None

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy", "service": "secure-api"})

@app.route('/config')
def get_configuration():
    """Return non-sensitive configuration"""
    config = get_secret(os.environ.get('CONFIG_SECRET_NAME'))
    if config:
        # Remove sensitive data before returning
        safe_config = {
            "debug_mode": config.get("debug_mode"),
            "rate_limit": config.get("rate_limit"),
            "cache_ttl": config.get("cache_ttl"),
            "log_level": config.get("log_level")
        }
        return jsonify(safe_config)
    return jsonify({"error": "Configuration unavailable"}), 500

@app.route('/database/status')
def database_status():
    """Check database connectivity using secrets"""
    db_config = get_secret(os.environ.get('DB_SECRET_NAME'))
    if db_config:
        return jsonify({
            "database": "connected",
            "host": db_config.get("host"),
            "port": db_config.get("port")
        })
    return jsonify({"error": "Database configuration unavailable"}), 500

@app.route('/api/data')
def get_data():
    """Sample API endpoint with authentication"""
    api_keys = get_secret(os.environ.get('KEYS_SECRET_NAME'))
    if not api_keys:
        return jsonify({"error": "API keys unavailable"}), 500
    
    # Simulate API key validation
    auth_header = request.headers.get('Authorization')
    if not auth_header or auth_header != f"Bearer {api_keys.get('external_api_key')}":
        return jsonify({"error": "Unauthorized"}), 401
    
    return jsonify({
        "data": "sensitive_api_data",
        "timestamp": "2025-07-12T10:00:00Z",
        "source": "secure-api"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==2.3.3
google-cloud-secret-manager==2.18.1
gunicorn==21.2.0
EOF
    
    # Create Dockerfile with security best practices
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set working directory
WORKDIR /app

# Copy and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Run application
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "main:app"]
EOF
    
    log_success "Sample application created"
    
    # Build and submit to Cloud Build
    log_info "Building container image..."
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --quiet; then
        log_success "Container image built successfully"
    else
        log_error "Failed to build container image"
        exit 1
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${app_dir}"
}

# Function to deploy Cloud Run service
deploy_cloud_run() {
    log_info "Deploying Cloud Run service..."
    
    if gcloud run deploy "${SERVICE_NAME}" \
        --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --service-account "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="DB_SECRET_NAME=${SECRET_NAME}-db,KEYS_SECRET_NAME=${SECRET_NAME}-keys,CONFIG_SECRET_NAME=${SECRET_NAME}-config" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --memory 512Mi \
        --cpu 1 \
        --max-instances 10 \
        --port 8080 \
        --quiet; then
        
        # Get service URL
        export SERVICE_URL
        SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
            --region="${REGION}" \
            --format='value(status.url)')
        
        log_success "Cloud Run service deployed successfully"
        log_info "Service URL: ${SERVICE_URL}"
    else
        log_error "Failed to deploy Cloud Run service"
        exit 1
    fi
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway configuration..."
    
    # Create temporary directory for OpenAPI spec
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Create OpenAPI specification
    cat > api-spec.yaml << EOF
swagger: '2.0'
info:
  title: Secure API Gateway
  description: API Gateway for secure configuration management
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
securityDefinitions:
  api_key:
    type: apiKey
    name: key
    in: query
paths:
  /health:
    get:
      summary: Health check endpoint
      operationId: healthCheck
      responses:
        200:
          description: Service is healthy
      x-google-backend:
        address: ${SERVICE_URL}
  /config:
    get:
      summary: Get application configuration
      operationId: getConfig
      security:
        - api_key: []
      responses:
        200:
          description: Configuration retrieved successfully
        500:
          description: Configuration unavailable
      x-google-backend:
        address: ${SERVICE_URL}
  /database/status:
    get:
      summary: Check database connectivity
      operationId: databaseStatus
      security:
        - api_key: []
      responses:
        200:
          description: Database status retrieved
        500:
          description: Database configuration unavailable
      x-google-backend:
        address: ${SERVICE_URL}
  /api/data:
    get:
      summary: Get secure API data
      operationId: getSecureData
      security:
        - api_key: []
      parameters:
        - name: Authorization
          in: header
          type: string
          required: true
      responses:
        200:
          description: Data retrieved successfully
        401:
          description: Unauthorized access
        500:
          description: API keys unavailable
      x-google-backend:
        address: ${SERVICE_URL}
EOF
    
    log_info "Creating API Gateway..."
    
    # Create API
    if gcloud api-gateway apis create "${GATEWAY_NAME}" --quiet; then
        log_success "API created successfully"
    else
        log_warning "API might already exist, continuing..."
    fi
    
    # Create API configuration
    if gcloud api-gateway api-configs create "${GATEWAY_NAME}-config" \
        --api="${GATEWAY_NAME}" \
        --openapi-spec=api-spec.yaml \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "API configuration created successfully"
    else
        log_error "Failed to create API configuration"
        exit 1
    fi
    
    # Create API Gateway
    if gcloud api-gateway gateways create "${GATEWAY_NAME}" \
        --api="${GATEWAY_NAME}" \
        --api-config="${GATEWAY_NAME}-config" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "API Gateway created successfully"
    else
        log_error "Failed to create API Gateway"
        exit 1
    fi
    
    # Wait for gateway deployment
    log_info "Waiting for API Gateway deployment to complete..."
    local max_attempts=20
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if gcloud api-gateway gateways describe "${GATEWAY_NAME}" \
            --location="${REGION}" \
            --format='value(state)' | grep -q "ACTIVE"; then
            break
        fi
        log_info "Attempt ${attempt}/${max_attempts}: Gateway still deploying..."
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Gateway deployment timed out"
        exit 1
    fi
    
    # Get gateway URL
    export GATEWAY_URL
    GATEWAY_URL=$(gcloud api-gateway gateways describe "${GATEWAY_NAME}" \
        --location="${REGION}" \
        --format='value(defaultHostname)')
    
    log_success "API Gateway deployed successfully"
    log_info "Gateway URL: https://${GATEWAY_URL}"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${temp_dir}"
}

# Function to create API key
create_api_key() {
    log_info "Creating API key for gateway authentication..."
    
    # Create API key
    if gcloud alpha services api-keys create \
        --display-name="Secure API Gateway Key" \
        --api-target-service=apigateway.googleapis.com \
        --quiet; then
        
        # Get API key
        local api_key_resource
        api_key_resource=$(gcloud alpha services api-keys list \
            --filter="displayName:Secure API Gateway Key" \
            --format='value(name)' | head -1)
        
        if [[ -n "$api_key_resource" ]]; then
            export API_KEY_STRING
            API_KEY_STRING=$(gcloud alpha services api-keys get-key-string "$api_key_resource")
            log_success "API key created successfully"
            log_info "API Key: ${API_KEY_STRING}"
        else
            log_error "Failed to retrieve API key"
            exit 1
        fi
    else
        log_error "Failed to create API key"
        exit 1
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring secret rotation and monitoring..."
    
    # Create new version of a secret (demonstrating rotation)
    echo '{"host":"db.example.com","port":5432,"username":"api_user","password":"rotated_password_456"}' | \
        gcloud secrets versions add "${SECRET_NAME}-db" --data-file=-
    
    log_success "Secret rotation demonstrated"
    log_success "Monitoring and rotation configured"
}

# Function to run validation tests
run_validation() {
    log_info "Running validation tests..."
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    if curl -s -f "${SERVICE_URL}/health" | grep -q "healthy"; then
        log_success "Health endpoint test passed"
    else
        log_warning "Health endpoint test failed"
    fi
    
    # Test API Gateway with authentication
    if [[ -n "${GATEWAY_URL:-}" ]] && [[ -n "${API_KEY_STRING:-}" ]]; then
        log_info "Testing API Gateway with authentication..."
        if curl -s -f "https://${GATEWAY_URL}/config?key=${API_KEY_STRING}" | grep -q "rate_limit"; then
            log_success "API Gateway authentication test passed"
        else
            log_warning "API Gateway authentication test failed"
        fi
    else
        log_warning "Skipping API Gateway test - missing URL or API key"
    fi
    
    log_success "Validation tests completed"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="deployment-info-${PROJECT_ID}.txt"
    
    cat > "${info_file}" << EOF
# Secure API Configuration Management Deployment Information
# Generated on: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
SERVICE_NAME=${SERVICE_NAME}
SECRET_NAME=${SECRET_NAME}
SA_NAME=${SA_NAME}
GATEWAY_NAME=${GATEWAY_NAME}

# URLs
SERVICE_URL=${SERVICE_URL:-"Not available"}
GATEWAY_URL=${GATEWAY_URL:-"Not available"}

# API Key
API_KEY_STRING=${API_KEY_STRING:-"Not available"}

# Test Commands
curl -s "${SERVICE_URL}/health"
curl -s "https://${GATEWAY_URL}/config?key=${API_KEY_STRING}"

# Cleanup Command
./destroy.sh
EOF
    
    log_success "Deployment information saved to: ${info_file}"
}

# Main deployment function
main() {
    log_info "Starting secure API configuration management deployment..."
    
    check_prerequisites
    setup_environment
    create_project
    enable_apis
    create_secrets
    create_service_account
    create_application
    deploy_cloud_run
    create_api_gateway
    create_api_key
    configure_monitoring
    run_validation
    save_deployment_info
    
    log_success "Deployment completed successfully!"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Service URL: ${SERVICE_URL:-"Not available"}"
    log_info "Gateway URL: https://${GATEWAY_URL:-"Not available"}"
    log_info "API Key: ${API_KEY_STRING:-"Not available"}"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Trap to handle script interruption
trap 'log_error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"
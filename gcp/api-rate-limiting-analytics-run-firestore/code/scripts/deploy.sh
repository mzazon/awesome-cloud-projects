#!/bin/bash

# API Rate Limiting and Analytics with Cloud Run and Firestore - Deployment Script
# This script deploys the complete infrastructure for the API rate limiting solution

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DEPLOY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --project-id)
            PROJECT_ID_OVERRIDE="$2"
            shift 2
            ;;
        --region)
            REGION_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--project-id PROJECT_ID] [--region REGION]"
            echo "  --dry-run: Show what would be deployed without making changes"
            echo "  --force: Force deployment even if resources exist"
            echo "  --project-id: Override default project ID"
            echo "  --region: Override default region"
            exit 0
            ;;
        *)
            error "Unknown option $1"
            exit 1
            ;;
    esac
done

log "Starting API Rate Limiting and Analytics deployment..."

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed (for local building if needed)
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed. Cloud Build will be used for container building."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        error "curl is required for testing but not found."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some testing features may be limited."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    # Use override values if provided, otherwise generate defaults
    if [[ -n "${PROJECT_ID_OVERRIDE:-}" ]]; then
        export PROJECT_ID="${PROJECT_ID_OVERRIDE}"
    else
        export PROJECT_ID="api-gateway-$(date +%s)"
    fi
    
    if [[ -n "${REGION_OVERRIDE:-}" ]]; then
        export REGION="${REGION_OVERRIDE}"
    else
        export REGION="us-central1"
    fi
    
    export SERVICE_NAME="api-rate-limiter"
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Store environment in file for cleanup script
    cat > .env.deploy << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
SERVICE_NAME=${SERVICE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOY_TIMESTAMP=$(date +%s)
EOF
    
    log "Environment configured:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Service Name: ${SERVICE_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No actual resources will be created"
        return 0
    fi
}

# Create and configure GCP project
setup_project() {
    log "Setting up GCP project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would create project: ${PROJECT_ID}"
        log "Would enable required APIs"
        return 0
    fi
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            warn "Project ${PROJECT_ID} already exists, continuing with force flag"
        else
            error "Project ${PROJECT_ID} already exists. Use --force to continue or choose a different project ID."
            exit 1
        fi
    else
        # Create project
        log "Creating project ${PROJECT_ID}..."
        gcloud projects create "${PROJECT_ID}" \
            --name="API Rate Limiting Demo" || {
            error "Failed to create project ${PROJECT_ID}"
            exit 1
        }
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Enable required APIs
    log "Enabling required APIs..."
    local apis=(
        "run.googleapis.com"
        "firestore.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "containerregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" || {
            error "Failed to enable ${api}"
            exit 1
        }
    done
    
    success "Project setup completed"
}

# Create Firestore database
setup_firestore() {
    log "Setting up Firestore database..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would create Firestore database in region: ${REGION}"
        return 0
    fi
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --region="${REGION}" --format="value(name)" &>/dev/null; then
        warn "Firestore database already exists in region ${REGION}"
    else
        log "Creating Firestore database in native mode..."
        gcloud firestore databases create --region="${REGION}" || {
            error "Failed to create Firestore database"
            exit 1
        }
    fi
    
    success "Firestore database setup completed"
}

# Create application code structure
create_application_code() {
    log "Creating application code structure..."
    
    local app_dir="api-gateway"
    
    if [[ -d "${app_dir}" ]] && [[ "$FORCE_DEPLOY" != "true" ]]; then
        error "Application directory ${app_dir} already exists. Use --force to overwrite."
        exit 1
    fi
    
    # Create directory structure
    mkdir -p "${app_dir}"/{src,config}
    cd "${app_dir}"
    
    # Create main application file
    log "Creating main application code..."
    cat > src/main.py << 'EOF'
import os
import json
import time
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from google.cloud import firestore
import requests
import logging

# Configure logging for Cloud Run
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
db = firestore.Client()

# Rate limiting configuration
DEFAULT_RATE_LIMIT = 100  # requests per hour
RATE_WINDOW = 3600  # 1 hour in seconds

class RateLimiter:
    def __init__(self, firestore_client):
        self.db = firestore_client

    def is_allowed(self, api_key, endpoint):
        """Check if request is allowed based on rate limits"""
        try:
            # Get current time
            now = datetime.utcnow()
            window_start = now - timedelta(seconds=RATE_WINDOW)
            
            # Reference to rate limit document
            limit_ref = self.db.collection('rate_limits').document(f"{api_key}_{endpoint}")
            
            # Use Firestore transaction for consistency
            transaction = self.db.transaction()
            
            @firestore.transactional
            def update_rate_limit(transaction, limit_ref):
                limit_doc = limit_ref.get(transaction=transaction)
                
                if limit_doc.exists:
                    data = limit_doc.to_dict()
                    current_count = data.get('count', 0)
                    last_reset = data.get('last_reset')
                    
                    # Reset counter if window has passed
                    if last_reset and last_reset < window_start:
                        current_count = 0
                else:
                    current_count = 0
                
                # Check if under limit
                if current_count >= DEFAULT_RATE_LIMIT:
                    return False, current_count
                
                # Increment counter
                transaction.set(limit_ref, {
                    'count': current_count + 1,
                    'last_reset': now,
                    'api_key': api_key,
                    'endpoint': endpoint
                }, merge=True)
                
                return True, current_count + 1
            
            return update_rate_limit(transaction, limit_ref)
            
        except Exception as e:
            logger.error(f"Rate limiting error: {e}")
            return True, 0  # Allow on error to prevent service disruption

    def log_analytics(self, api_key, endpoint, status_code, response_time):
        """Log API usage analytics"""
        try:
            analytics_ref = self.db.collection('api_analytics').document()
            analytics_ref.set({
                'api_key': api_key,
                'endpoint': endpoint,
                'timestamp': datetime.utcnow(),
                'status_code': status_code,
                'response_time_ms': response_time,
                'date': datetime.utcnow().strftime('%Y-%m-%d'),
                'user_agent': request.headers.get('User-Agent', ''),
                'ip_address': request.headers.get('X-Forwarded-For', request.remote_addr)
            })
        except Exception as e:
            logger.error(f"Analytics logging error: {e}")

rate_limiter = RateLimiter(db)

@app.before_request
def before_request():
    """Middleware for rate limiting and authentication"""
    start_time = time.time()
    request.start_time = start_time
    
    # Skip rate limiting for health checks
    if request.path == '/health':
        return
    
    # Extract API key from headers
    api_key = request.headers.get('X-API-Key')
    if not api_key:
        return jsonify({
            'error': 'API key required',
            'message': 'Please provide X-API-Key header'
        }), 401
    
    # Check rate limits
    endpoint = request.path
    allowed, current_count = rate_limiter.is_allowed(api_key, endpoint)
    
    if not allowed:
        # Log rate limit exceeded
        response_time = (time.time() - start_time) * 1000
        rate_limiter.log_analytics(api_key, endpoint, 429, response_time)
        
        return jsonify({
            'error': 'Rate limit exceeded',
            'limit': DEFAULT_RATE_LIMIT,
            'window': RATE_WINDOW,
            'current_usage': current_count,
            'reset_time': int(time.time() + RATE_WINDOW)
        }), 429
    
    # Store current count for response headers
    request.rate_limit_count = current_count

@app.after_request
def after_request(response):
    """Log analytics after request processing"""
    if hasattr(request, 'start_time'):
        api_key = request.headers.get('X-API-Key')
        if api_key and request.path != '/health':
            response_time = (time.time() - request.start_time) * 1000
            rate_limiter.log_analytics(
                api_key, 
                request.path, 
                response.status_code, 
                response_time
            )
            
            # Add rate limit headers
            response.headers['X-RateLimit-Limit'] = str(DEFAULT_RATE_LIMIT)
            response.headers['X-RateLimit-Remaining'] = str(
                max(0, DEFAULT_RATE_LIMIT - getattr(request, 'rate_limit_count', 0))
            )
            response.headers['X-RateLimit-Reset'] = str(int(time.time() + RATE_WINDOW))
            response.headers['X-RateLimit-Window'] = str(RATE_WINDOW)
    
    return response

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy', 
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'api-rate-limiter'
    })

@app.route('/api/v1/data')
def get_data():
    """Sample API endpoint with rate limiting"""
    return jsonify({
        'data': 'This is protected data',
        'timestamp': datetime.utcnow().isoformat(),
        'message': 'Successfully accessed rate-limited endpoint',
        'api_version': 'v1'
    })

@app.route('/api/v1/analytics')
def get_analytics():
    """Get API usage analytics"""
    try:
        api_key = request.headers.get('X-API-Key')
        
        # Query analytics for the API key
        analytics_ref = db.collection('api_analytics')
        query = analytics_ref.where('api_key', '==', api_key) \
                             .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                             .limit(100)
        docs = query.stream()
        
        analytics_data = []
        for doc in docs:
            data = doc.to_dict()
            # Convert timestamp to string for JSON serialization
            if 'timestamp' in data:
                data['timestamp'] = data['timestamp'].isoformat()
            analytics_data.append(data)
        
        return jsonify({
            'analytics': analytics_data,
            'total_requests': len(analytics_data),
            'api_key': api_key[:8] + "***"  # Masked for security
        })
        
    except Exception as e:
        logger.error(f"Analytics retrieval error: {e}")
        return jsonify({'error': 'Failed to retrieve analytics'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

    # Create requirements.txt
    log "Creating requirements.txt..."
    cat > requirements.txt << 'EOF'
Flask==3.0.3
google-cloud-firestore==2.21.0
requests==2.32.3
gunicorn==23.0.0
EOF

    # Create Dockerfile
    log "Creating Dockerfile..."
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/

# Set environment variables
ENV PYTHONPATH=/app/src
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8080

# Run with gunicorn for production
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 \
    --timeout 0 --keep-alive 2 src.main:app
EOF

    cd ..
    success "Application code structure created"
}

# Build and deploy Cloud Run service
deploy_cloud_run() {
    log "Building and deploying Cloud Run service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would build container: gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
        log "Would deploy Cloud Run service: ${SERVICE_NAME}"
        return 0
    fi
    
    cd api-gateway
    
    # Build container using Cloud Build
    log "Building container with Cloud Build..."
    gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --timeout=600s || {
        error "Failed to build container"
        exit 1
    }
    
    # Deploy to Cloud Run
    log "Deploying to Cloud Run..."
    gcloud run deploy "${SERVICE_NAME}" \
        --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID}" \
        --memory 1Gi \
        --cpu 1 \
        --concurrency 100 \
        --timeout 300 \
        --max-instances 10 \
        --min-instances 0 || {
        error "Failed to deploy Cloud Run service"
        exit 1
    }
    
    # Get service URL
    export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    # Save service URL to environment file
    echo "SERVICE_URL=${SERVICE_URL}" >> ../.env.deploy
    
    cd ..
    success "Cloud Run service deployed successfully"
    log "Service URL: ${SERVICE_URL}"
}

# Configure Firestore security rules
configure_firestore_rules() {
    log "Configuring Firestore security rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would configure Firestore security rules"
        return 0
    fi
    
    # Create Firestore security rules
    cat > firestore.rules << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Rate limits collection - allow reads and writes for authenticated services
    match /rate_limits/{document} {
      allow read, write: if true; // Allow for Cloud Run service
    }
    
    // API analytics collection - allow writes and filtered reads
    match /api_analytics/{document} {
      allow write: if true; // Allow writes from Cloud Run service
      allow read: if true; // Allow reads for analytics endpoints
    }
  }
}
EOF
    
    # Deploy Firestore rules
    gcloud firestore rules update firestore.rules || {
        error "Failed to update Firestore rules"
        exit 1
    }
    
    success "Firestore security rules configured"
}

# Create monitoring configuration
setup_monitoring() {
    log "Setting up Cloud Monitoring configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would create monitoring dashboard and alerts"
        return 0
    fi
    
    # Create monitoring dashboard configuration
    cat > monitoring-dashboard.json << 'EOF'
{
  "displayName": "API Gateway Analytics Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "API Request Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"api-rate-limiter\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Response Status Codes",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["metric.labels.response_code"]
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

    warn "Monitoring dashboard configuration created as monitoring-dashboard.json"
    warn "Manual setup required in Cloud Console for dashboard and alerting policies"
    
    success "Monitoring configuration prepared"
}

# Generate test API keys and run basic tests
generate_test_keys() {
    log "Generating test API keys and running validation..."
    
    # Generate test API keys
    export TEST_API_KEY_1="test-key-$(openssl rand -hex 16)"
    export TEST_API_KEY_2="test-key-$(openssl rand -hex 16)"
    
    # Save test keys to environment file
    echo "TEST_API_KEY_1=${TEST_API_KEY_1}" >> .env.deploy
    echo "TEST_API_KEY_2=${TEST_API_KEY_2}" >> .env.deploy
    
    log "Generated test API keys:"
    log "  API Key 1: ${TEST_API_KEY_1}"
    log "  API Key 2: ${TEST_API_KEY_2}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would test health endpoint and API functionality"
        return 0
    fi
    
    # Wait for service to be ready
    log "Waiting for service to be ready..."
    sleep 30
    
    # Test health endpoint
    log "Testing health endpoint..."
    if curl -s -f "${SERVICE_URL}/health" > /dev/null; then
        success "Health check passed"
    else
        error "Health check failed"
        exit 1
    fi
    
    # Test authenticated endpoint
    log "Testing authenticated endpoint..."
    response=$(curl -s -H "X-API-Key: ${TEST_API_KEY_1}" \
                   "${SERVICE_URL}/api/v1/data")
    
    if echo "${response}" | grep -q "This is protected data"; then
        success "API authentication test passed"
    else
        error "API authentication test failed"
        log "Response: ${response}"
        exit 1
    fi
    
    success "Test API keys generated and basic validation completed"
}

# Main deployment function
main() {
    log "Starting deployment of API Rate Limiting and Analytics solution"
    
    check_prerequisites
    set_environment
    setup_project
    setup_firestore
    create_application_code
    deploy_cloud_run
    configure_firestore_rules
    setup_monitoring
    generate_test_keys
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN completed - no resources were actually created"
        log "To deploy for real, run: $0 without --dry-run flag"
    else
        success "🎉 Deployment completed successfully!"
        log ""
        log "=== Deployment Summary ==="
        log "Project ID: ${PROJECT_ID}"
        log "Region: ${REGION}"
        log "Service Name: ${SERVICE_NAME}"
        log "Service URL: ${SERVICE_URL}"
        log "Test API Key 1: ${TEST_API_KEY_1}"
        log "Test API Key 2: ${TEST_API_KEY_2}"
        log ""
        log "=== Next Steps ==="
        log "1. Test the API endpoints using the provided API keys"
        log "2. Monitor usage in Cloud Console"
        log "3. Configure monitoring dashboards manually if needed"
        log "4. Run './destroy.sh' when you're done testing"
        log ""
        log "Environment details saved to: .env.deploy"
    fi
}

# Run main function
main "$@"
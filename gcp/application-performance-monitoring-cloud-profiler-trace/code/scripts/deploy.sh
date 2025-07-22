#!/bin/bash

# Deploy script for Application Performance Monitoring with Cloud Profiler and Cloud Trace
# This script deploys a complete microservices architecture with performance monitoring
# on Google Cloud Platform

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check for gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check for python3
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    success "All prerequisites are installed"
}

# Initialize environment variables
init_environment() {
    log "Initializing environment variables..."
    
    # Set environment variables for consistent resource naming
    export PROJECT_ID="performance-demo-$(date +%s)"
    export REGION="us-central1"
    export SERVICE_ACCOUNT_NAME="profiler-trace-sa"
    
    # Generate unique suffix for resource names to avoid conflicts
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FRONTEND_SERVICE="frontend-${RANDOM_SUFFIX}"
    export API_SERVICE="api-gateway-${RANDOM_SUFFIX}"
    export AUTH_SERVICE="auth-service-${RANDOM_SUFFIX}"
    export DATA_SERVICE="data-service-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  SERVICE_ACCOUNT_NAME: ${SERVICE_ACCOUNT_NAME}"
    log "  RANDOM_SUFFIX: ${RANDOM_SUFFIX}"
}

# Create and configure GCP project
setup_project() {
    log "Creating and configuring GCP project..."
    
    # Create the project
    log "Creating project: ${PROJECT_ID}"
    gcloud projects create ${PROJECT_ID} --name="Performance Monitoring Demo" || {
        error "Failed to create project. Project ID might already exist."
        exit 1
    }
    
    # Set project configuration
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    
    # Enable billing (user must have billing account linked)
    warning "Please ensure billing is enabled for project ${PROJECT_ID}"
    warning "You can enable billing in the GCP Console: https://console.cloud.google.com/billing"
    
    success "Project created and configured"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "cloudprofiler.googleapis.com"
        "cloudtrace.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: ${api}"
        gcloud services enable ${api} || {
            error "Failed to enable API: ${api}"
            exit 1
        }
    done
    
    success "All required APIs enabled"
}

# Create service account with appropriate permissions
create_service_account() {
    log "Creating service account with appropriate permissions..."
    
    # Create service account
    gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} \
        --display-name="Cloud Profiler and Trace Service Account" || {
        error "Failed to create service account"
        exit 1
    }
    
    # Add profiler agent role
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudprofiler.agent" || {
        error "Failed to add profiler agent role"
        exit 1
    }
    
    # Add trace agent role  
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudtrace.agent" || {
        error "Failed to add trace agent role"
        exit 1
    }
    
    success "Service account created with appropriate permissions"
}

# Create application source code
create_application_code() {
    log "Creating application source code..."
    
    # Create project structure
    mkdir -p performance-demo/{frontend,api-gateway,auth-service,data-service}
    cd performance-demo
    
    # Create Frontend Service
    cat > frontend/main.py << 'EOF'
import os
import time
import random
import requests
from flask import Flask, request, jsonify
from google.cloud import profiler
from opencensus.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.ext.stackdriver import trace_exporter
from opencensus.trace.samplers import ProbabilitySampler

app = Flask(__name__)

# Initialize Cloud Profiler for continuous performance monitoring
try:
    profiler.start(
        service='frontend-service',
        service_version='1.0.0',
        verbose=3
    )
except Exception as e:
    print(f"Profiler initialization error: {e}")

# Initialize Cloud Trace for distributed request tracing
middleware = FlaskMiddleware(
    app,
    exporter=trace_exporter.StackdriverExporter(),
    sampler=ProbabilitySampler(rate=1.0)
)

@app.route('/')
def frontend_handler():
    # Simulate CPU-intensive operation for profiling demonstration
    start_time = time.time()
    result = 0
    for i in range(100000):
        result += i * random.random()
    
    # Call downstream API service
    api_url = os.getenv('API_SERVICE_URL', 'http://localhost:8081')
    try:
        response = requests.get(f"{api_url}/api/data", timeout=5)
        api_data = response.json()
    except Exception as e:
        api_data = {"error": str(e)}
    
    processing_time = time.time() - start_time
    
    return jsonify({
        "service": "frontend",
        "processing_time_ms": processing_time * 1000,
        "computation_result": result,
        "api_response": api_data
    })

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy", "service": "frontend"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
    
    # Create requirements file
    cat > frontend/requirements.txt << 'EOF'
Flask==2.3.3
google-cloud-profiler==4.1.0
opencensus-ext-flask==0.8.0
opencensus-ext-stackdriver==0.8.0
requests==2.31.0
EOF
    
    # Create API Gateway Service
    cat > api-gateway/main.py << 'EOF'
import os
import time
import json
import requests
from flask import Flask, request, jsonify
from google.cloud import profiler
from opencensus.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.ext.stackdriver import trace_exporter
from opencensus.trace.samplers import ProbabilitySampler
from opencensus.trace import tracer as tracer_module

app = Flask(__name__)

# Initialize profiling for API gateway performance analysis
try:
    profiler.start(
        service='api-gateway-service',
        service_version='1.0.0',
        verbose=3
    )
except Exception as e:
    print(f"Profiler initialization error: {e}")

# Configure distributed tracing with custom spans
tracer = tracer_module.Tracer(
    exporter=trace_exporter.StackdriverExporter(),
    sampler=ProbabilitySampler(rate=1.0)
)

middleware = FlaskMiddleware(app, exporter=trace_exporter.StackdriverExporter())

@app.route('/api/data')
def get_data():
    with tracer.span(name='api_gateway_processing') as span:
        # Add custom attributes for enhanced tracing
        span.add_attribute('endpoint', '/api/data')
        span.add_attribute('method', 'GET')
        
        # Simulate authentication call with tracing
        with tracer.span(name='authentication_check') as auth_span:
            auth_url = os.getenv('AUTH_SERVICE_URL', 'http://localhost:8082')
            auth_start = time.time()
            try:
                auth_response = requests.get(f"{auth_url}/auth/verify", timeout=3)
                auth_success = auth_response.status_code == 200
                auth_span.add_attribute('auth_result', 'success' if auth_success else 'failed')
            except Exception as e:
                auth_success = False
                auth_span.add_attribute('auth_error', str(e))
            
            auth_duration = time.time() - auth_start
            auth_span.add_attribute('auth_duration_ms', auth_duration * 1000)
        
        if not auth_success:
            span.add_attribute('error', 'authentication_failed')
            return jsonify({"error": "Authentication failed"}), 401
        
        # Call data service with performance tracking
        with tracer.span(name='data_service_call') as data_span:
            data_url = os.getenv('DATA_SERVICE_URL', 'http://localhost:8083')
            data_start = time.time()
            try:
                data_response = requests.get(f"{data_url}/data/fetch", timeout=5)
                data_result = data_response.json()
                data_span.add_attribute('data_size_bytes', len(json.dumps(data_result)))
            except Exception as e:
                data_result = {"error": str(e)}
                data_span.add_attribute('data_error', str(e))
            
            data_duration = time.time() - data_start
            data_span.add_attribute('data_duration_ms', data_duration * 1000)
        
        return jsonify({
            "service": "api-gateway",
            "data": data_result,
            "auth_duration_ms": auth_duration * 1000,
            "data_duration_ms": data_duration * 1000
        })

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy", "service": "api-gateway"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
EOF
    
    # Create Auth Service
    cat > auth-service/main.py << 'EOF'
import os
import time
import hashlib
import secrets
from flask import Flask, request, jsonify
from google.cloud import profiler
from opencensus.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.ext.stackdriver import trace_exporter
from opencensus.trace.samplers import ProbabilitySampler

app = Flask(__name__)

# Initialize profiler with focus on memory allocation patterns
try:
    profiler.start(
        service='auth-service',
        service_version='1.0.0',
        verbose=3
    )
except Exception as e:
    print(f"Profiler initialization error: {e}")

middleware = FlaskMiddleware(
    app,
    exporter=trace_exporter.StackdriverExporter(),
    sampler=ProbabilitySampler(rate=1.0)
)

# Simulate user session storage for memory profiling
user_sessions = {}

@app.route('/auth/verify')
def verify_auth():
    # Simulate memory-intensive authentication operations
    start_time = time.time()
    
    # Generate session data (memory allocation intensive)
    session_id = secrets.token_hex(32)
    user_data = {
        "session_id": session_id,
        "permissions": ["read", "write", "admin"] * 100,  # Large permission set
        "metadata": {f"key_{i}": f"value_{i}" * 50 for i in range(100)},  # Memory intensive
        "timestamps": [time.time() + i for i in range(1000)]
    }
    
    # Store session in memory (for profiling demonstration)
    user_sessions[session_id] = user_data
    
    # Simulate cryptographic operations (CPU intensive)
    for i in range(1000):
        hash_value = hashlib.sha256(f"auth_token_{i}_{session_id}".encode()).hexdigest()
    
    # Clean up old sessions periodically (memory management)
    if len(user_sessions) > 50:
        oldest_sessions = list(user_sessions.keys())[:25]
        for old_session in oldest_sessions:
            del user_sessions[old_session]
    
    processing_time = time.time() - start_time
    
    return jsonify({
        "service": "auth",
        "authenticated": True,
        "session_id": session_id,
        "processing_time_ms": processing_time * 1000,
        "active_sessions": len(user_sessions)
    })

@app.route('/health')
def health_check():
    return jsonify({
        "status": "healthy", 
        "service": "auth",
        "memory_usage_sessions": len(user_sessions)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8082)
EOF
    
    # Create Data Service
    cat > data-service/main.py << 'EOF'
import os
import time
import random
import sqlite3
from flask import Flask, request, jsonify
from google.cloud import profiler
from opencensus.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.ext.stackdriver import trace_exporter
from opencensus.trace.samplers import ProbabilitySampler
from opencensus.trace import tracer as tracer_module

app = Flask(__name__)

# Initialize profiler for data processing performance analysis
try:
    profiler.start(
        service='data-service',
        service_version='1.0.0',
        verbose=3
    )
except Exception as e:
    print(f"Profiler initialization error: {e}")

tracer = tracer_module.Tracer(
    exporter=trace_exporter.StackdriverExporter(),
    sampler=ProbabilitySampler(rate=1.0)
)

middleware = FlaskMiddleware(app, exporter=trace_exporter.StackdriverExporter())

# Initialize in-memory database for performance testing
def init_database():
    conn = sqlite3.connect(':memory:', check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE performance_data (
            id INTEGER PRIMARY KEY,
            name TEXT,
            value REAL,
            category TEXT,
            timestamp REAL
        )
    ''')
    
    # Insert sample data for querying
    sample_data = [
        (i, f"item_{i}", random.uniform(0, 1000), f"category_{i % 10}", time.time())
        for i in range(10000)
    ]
    cursor.executemany(
        'INSERT INTO performance_data (id, name, value, category, timestamp) VALUES (?, ?, ?, ?, ?)',
        sample_data
    )
    conn.commit()
    return conn

# Global database connection for demonstration
db_conn = init_database()

@app.route('/data/fetch')
def fetch_data():
    with tracer.span(name='data_fetch_operation') as span:
        start_time = time.time()
        
        # Simulate complex database query with tracing
        with tracer.span(name='database_query') as db_span:
            cursor = db_conn.cursor()
            query_start = time.time()
            
            # Complex query for performance analysis
            cursor.execute('''
                SELECT category, COUNT(*) as count, AVG(value) as avg_value, 
                       MAX(value) as max_value, MIN(value) as min_value
                FROM performance_data 
                WHERE value > ? 
                GROUP BY category 
                ORDER BY avg_value DESC
            ''', (random.uniform(100, 500),))
            
            results = cursor.fetchall()
            query_duration = time.time() - query_start
            
            db_span.add_attribute('query_duration_ms', query_duration * 1000)
            db_span.add_attribute('result_count', len(results))
            db_span.add_attribute('query_type', 'aggregate_analysis')
        
        # Simulate data processing (CPU intensive for profiling)
        with tracer.span(name='data_processing') as proc_span:
            processed_data = []
            for row in results:
                category, count, avg_val, max_val, min_val = row
                
                # Simulate complex calculations
                processed_item = {
                    "category": category,
                    "statistics": {
                        "count": count,
                        "average": round(avg_val, 2),
                        "maximum": max_val,
                        "minimum": min_val,
                        "variance": random.uniform(0, 100),
                        "processed_score": sum([avg_val * 0.4, max_val * 0.3, count * 0.3])
                    }
                }
                processed_data.append(processed_item)
                
                # Simulate additional CPU work for profiling
                for _ in range(100):
                    _ = sum([random.random() for _ in range(50)])
            
            proc_span.add_attribute('items_processed', len(processed_data))
        
        total_duration = time.time() - start_time
        span.add_attribute('total_duration_ms', total_duration * 1000)
        
        return jsonify({
            "service": "data",
            "total_items": len(processed_data),
            "processing_time_ms": total_duration * 1000,
            "query_time_ms": query_duration * 1000,
            "data": processed_data[:5]  # Return sample of results
        })

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy", "service": "data"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8083)
EOF
    
    # Copy requirements to all services
    for service in api-gateway auth-service data-service; do
        cp frontend/requirements.txt ${service}/requirements.txt
    done
    
    success "Application source code created"
}

# Create Dockerfiles for all services
create_dockerfiles() {
    log "Creating Dockerfiles for all services..."
    
    for service in frontend api-gateway auth-service data-service; do
        cat > ${service}/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8080

CMD ["python", "main.py"]
EOF
    done
    
    success "Dockerfiles created for all services"
}

# Build and deploy services to Cloud Run
deploy_services() {
    log "Building and deploying services to Cloud Run..."
    
    local services=("frontend" "api-gateway" "auth-service" "data-service")
    
    for service in "${services[@]}"; do
        log "Building and deploying ${service}..."
        
        # Build container image
        log "Building container image for ${service}..."
        gcloud builds submit ${service} \
            --tag gcr.io/${PROJECT_ID}/${service}:latest || {
            error "Failed to build ${service}"
            exit 1
        }
        
        # Deploy to Cloud Run
        log "Deploying ${service} to Cloud Run..."
        gcloud run deploy ${service} \
            --image gcr.io/${PROJECT_ID}/${service}:latest \
            --platform managed \
            --region ${REGION} \
            --allow-unauthenticated \
            --service-account ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
            --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
            --memory 1Gi \
            --cpu 1 \
            --max-instances 10 || {
            error "Failed to deploy ${service}"
            exit 1
        }
        
        success "${service} deployed successfully"
    done
}

# Configure cross-service communication
configure_services() {
    log "Configuring cross-service communication..."
    
    # Get service URLs
    FRONTEND_URL=$(gcloud run services describe frontend \
        --region=${REGION} --format="value(status.url)")
    API_URL=$(gcloud run services describe api-gateway \
        --region=${REGION} --format="value(status.url)")
    AUTH_URL=$(gcloud run services describe auth-service \
        --region=${REGION} --format="value(status.url)")
    DATA_URL=$(gcloud run services describe data-service \
        --region=${REGION} --format="value(status.url)")
    
    # Update services with cross-service URLs
    gcloud run services update frontend \
        --region=${REGION} \
        --set-env-vars "API_SERVICE_URL=${API_URL}" || {
        error "Failed to update frontend service"
        exit 1
    }
    
    gcloud run services update api-gateway \
        --region=${REGION} \
        --set-env-vars "AUTH_SERVICE_URL=${AUTH_URL},DATA_SERVICE_URL=${DATA_URL}" || {
        error "Failed to update api-gateway service"
        exit 1
    }
    
    success "Cross-service communication configured"
    
    # Store URLs for later use
    echo "FRONTEND_URL=${FRONTEND_URL}" > ../service_urls.env
    echo "API_URL=${API_URL}" >> ../service_urls.env
    echo "AUTH_URL=${AUTH_URL}" >> ../service_urls.env
    echo "DATA_URL=${DATA_URL}" >> ../service_urls.env
    
    log "Service URLs saved to service_urls.env"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    cat > ../dashboard_config.json << 'EOF'
{
  "displayName": "Application Performance Monitoring Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Run Request Latency",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.label.service_name"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Cloud Trace Request Count",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"cloudtrace.googleapis.com/trace_span/count\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                },
                "plotType": "STACKED_AREA"
              }
            ]
          }
        }
      },
      {
        "width": 12,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Service CPU Utilization by Cloud Profiler",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.label.service_name"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the monitoring dashboard
    gcloud monitoring dashboards create --config-from-file=../dashboard_config.json || {
        warning "Failed to create monitoring dashboard. You can create it manually in the console."
    }
    
    success "Monitoring dashboard created"
}

# Generate load for testing
generate_load() {
    log "Generating load for performance testing..."
    
    # Source the service URLs
    source ../service_urls.env
    
    # Create load generation script
    cat > ../load_generator.py << EOF
import requests
import time
import concurrent.futures
import random
import json

def make_request(frontend_url, request_id):
    try:
        start_time = time.time()
        response = requests.get(frontend_url, timeout=30)
        duration = time.time() - start_time
        
        print(f"Request {request_id}: Status {response.status_code}, Duration: {duration:.2f}s")
        return {
            "request_id": request_id,
            "status_code": response.status_code,
            "duration": duration,
            "success": response.status_code == 200
        }
    except Exception as e:
        print(f"Request {request_id} failed: {e}")
        return {"request_id": request_id, "error": str(e), "success": False}

def generate_load(frontend_url, num_requests=100, concurrent_requests=10):
    print(f"Generating load: {num_requests} requests with {concurrent_requests} concurrent workers")
    
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_requests) as executor:
        futures = []
        
        for i in range(num_requests):
            future = executor.submit(make_request, frontend_url, i)
            futures.append(future)
            
            # Add slight delay between request submissions
            time.sleep(random.uniform(0.1, 0.5))
        
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
    
    # Calculate statistics
    successful_requests = [r for r in results if r.get("success", False)]
    failed_requests = [r for r in results if not r.get("success", False)]
    
    if successful_requests:
        durations = [r["duration"] for r in successful_requests]
        avg_duration = sum(durations) / len(durations)
        max_duration = max(durations)
        min_duration = min(durations)
        
        print(f"\\nLoad Generation Complete:")
        print(f"  Successful requests: {len(successful_requests)}")
        print(f"  Failed requests: {len(failed_requests)}")
        print(f"  Average duration: {avg_duration:.2f}s")
        print(f"  Max duration: {max_duration:.2f}s")
        print(f"  Min duration: {min_duration:.2f}s")
    
    return results

if __name__ == "__main__":
    frontend_url = "${FRONTEND_URL}"
    generate_load(frontend_url, num_requests=50, concurrent_requests=5)
EOF
    
    # Execute load generation
    cd ..
    python3 load_generator.py || {
        warning "Load generation failed. You can run it manually later."
    }
    
    success "Load generation completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    log "=================="
    
    source service_urls.env
    
    echo ""
    echo "🚀 Application Performance Monitoring Demo Deployed Successfully!"
    echo ""
    echo "Service URLs:"
    echo "  Frontend:     ${FRONTEND_URL}"
    echo "  API Gateway:  ${API_URL}"
    echo "  Auth Service: ${AUTH_URL}"
    echo "  Data Service: ${DATA_URL}"
    echo ""
    echo "Google Cloud Console Links:"
    echo "  Project:      https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    echo "  Cloud Run:    https://console.cloud.google.com/run?project=${PROJECT_ID}"
    echo "  Cloud Trace:  https://console.cloud.google.com/traces?project=${PROJECT_ID}"
    echo "  Cloud Profiler: https://console.cloud.google.com/profiler?project=${PROJECT_ID}"
    echo "  Monitoring:   https://console.cloud.google.com/monitoring?project=${PROJECT_ID}"
    echo ""
    echo "To test the application:"
    echo "  curl ${FRONTEND_URL}"
    echo ""
    echo "To generate additional load:"
    echo "  python3 load_generator.py"
    echo ""
    echo "To clean up resources:"
    echo "  ./destroy.sh"
    echo ""
    
    success "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting Application Performance Monitoring deployment..."
    
    check_prerequisites
    init_environment
    setup_project
    enable_apis
    create_service_account
    create_application_code
    create_dockerfiles
    deploy_services
    configure_services
    create_monitoring_dashboard
    generate_load
    print_summary
    
    success "All deployment steps completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Please run destroy.sh to clean up any partially created resources."; exit 1' INT TERM

# Execute main function
main "$@"
#!/bin/bash

# Resource Allocation with Cloud Quotas API and Cloud Run GPU - Deployment Script
# This script deploys an intelligent resource allocation system for GPU workloads

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output formatting
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
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        log_error "openssl is required for generating random suffixes. Please install openssl."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Check if project is set
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No default project set. Please run 'gcloud config set project PROJECT_ID'."
        exit 1
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="quota-manager-${RANDOM_SUFFIX}"
    export SERVICE_NAME="ai-inference-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-quota-policies-${RANDOM_SUFFIX}"
    export JOB_NAME="quota-analysis-job-${RANDOM_SUFFIX}"
    export PEAK_JOB_NAME="peak-analysis-job-${RANDOM_SUFFIX}"
    
    # Set default configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}, Zone: ${ZONE}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudquotas.googleapis.com"
        "run.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "firestore.googleapis.com"
        "storage.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
        "containerregistry.googleapis.com"
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

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for quota policies..."
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Bucket gs://${BUCKET_NAME} created"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Versioning enabled on bucket"
    else
        log_warning "Failed to enable versioning, continuing..."
    fi
    
    # Create quota policy configuration
    log_info "Creating quota policy configuration..."
    cat > quota-policy.json << 'EOF'
{
  "allocation_thresholds": {
    "gpu_utilization_trigger": 0.8,
    "cpu_utilization_trigger": 0.75,
    "memory_utilization_trigger": 0.85
  },
  "gpu_families": {
    "nvidia-l4": {
      "max_quota": 10,
      "min_quota": 1,
      "increment_size": 2
    },
    "nvidia-t4": {
      "max_quota": 8,
      "min_quota": 1,
      "increment_size": 1
    }
  },
  "regions": ["us-central1", "us-west1", "us-east1"],
  "cost_optimization": {
    "enable_preemptible": true,
    "max_cost_per_hour": 50.0
  }
}
EOF
    
    # Upload policy to bucket
    if gsutil cp quota-policy.json "gs://${BUCKET_NAME}/"; then
        log_success "Quota policy uploaded to bucket"
        rm quota-policy.json
    else
        log_error "Failed to upload quota policy"
        exit 1
    fi
}

# Function to initialize Firestore
initialize_firestore() {
    log_info "Initializing Firestore database..."
    
    # Check if Firestore is already initialized
    if gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -q "${PROJECT_ID}"; then
        log_warning "Firestore database already exists, skipping initialization"
        return 0
    fi
    
    # Create Firestore database in Native mode
    if gcloud firestore databases create --region="${REGION}" --type=firestore-native --quiet; then
        log_success "Firestore database initialized"
    else
        log_error "Failed to initialize Firestore database"
        exit 1
    fi
    
    # Wait for database to be ready
    log_info "Waiting for Firestore to be ready..."
    sleep 10
    
    log_success "Firestore initialization completed"
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying Cloud Function for quota intelligence..."
    
    # Create directory for Cloud Function code
    local function_dir="quota-manager-function"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-monitoring==2.16.0
google-cloud-quotas==0.8.0
google-cloud-firestore==2.13.1
google-cloud-storage==2.10.0
google-cloud-run==0.10.3
functions-framework==3.5.0
numpy==1.24.3
scikit-learn==1.3.0
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any

from google.cloud import monitoring_v3
from google.cloud import quotas_v1
from google.cloud import firestore
from google.cloud import storage
from google.cloud import run_v2
import numpy as np
from sklearn.linear_model import LinearRegression

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def analyze_gpu_utilization(request):
    """Main Cloud Function entry point for quota analysis"""
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            request_json = {}
        
        project_id = request_json.get('project_id')
        region = request_json.get('region', 'us-central1')
        
        if not project_id:
            return {'status': 'error', 'message': 'project_id is required'}, 400
        
        # Initialize clients
        monitoring_client = monitoring_v3.MetricServiceClient()
        quotas_client = quotas_v1.CloudQuotasClient()
        firestore_client = firestore.Client()
        storage_client = storage.Client()
        
        # Analyze current utilization
        utilization_data = get_gpu_utilization_metrics(
            monitoring_client, project_id, region
        )
        
        # Load quota policies
        policies = load_quota_policies(storage_client, project_id)
        
        # Make intelligent quota decisions
        recommendations = generate_quota_recommendations(
            utilization_data, policies, firestore_client
        )
        
        # Execute approved recommendations (simulation mode)
        results = execute_quota_adjustments(
            quotas_client, recommendations, project_id
        )
        
        # Store results in Firestore
        store_allocation_history(firestore_client, results)
        
        return {
            'status': 'success',
            'recommendations': len(recommendations),
            'executed': len(results),
            'timestamp': datetime.utcnow().isoformat(),
            'project_id': project_id,
            'region': region
        }
        
    except Exception as e:
        logger.error(f"Quota analysis failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def get_gpu_utilization_metrics(client, project_id: str, region: str) -> Dict:
    """Retrieve GPU utilization metrics from Cloud Monitoring"""
    try:
        project_name = f"projects/{project_id}"
        interval = monitoring_v3.TimeInterval()
        now = datetime.utcnow()
        interval.end_time.seconds = int(now.timestamp())
        interval.start_time.seconds = int((now - timedelta(hours=1)).timestamp())
        
        # Query GPU utilization for Cloud Run services
        gpu_filter = (
            f'resource.type="cloud_run_revision" AND '
            f'resource.labels.location="{region}" AND '
            f'metric.type="run.googleapis.com/container/gpu/utilization"'
        )
        
        request = monitoring_v3.ListTimeSeriesRequest(
            name=project_name,
            filter=gpu_filter,
            interval=interval,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        )
        
        utilization_data = {
            'average_utilization': 0.0,
            'peak_utilization': 0.0,
            'service_count': 0,
            'total_gpus': 0
        }
        
        try:
            time_series = client.list_time_series(request=request)
            utilizations = []
            
            for series in time_series:
                for point in series.points:
                    utilizations.append(point.value.double_value)
                utilization_data['service_count'] += 1
            
            if utilizations:
                utilization_data['average_utilization'] = np.mean(utilizations)
                utilization_data['peak_utilization'] = np.max(utilizations)
            else:
                # Simulate some utilization data for demo purposes
                utilization_data['average_utilization'] = np.random.uniform(0.3, 0.9)
                utilization_data['peak_utilization'] = utilization_data['average_utilization'] + np.random.uniform(0.1, 0.2)
                utilization_data['service_count'] = 1
                
        except Exception as metric_error:
            logger.warning(f"Could not fetch real metrics, using simulated data: {str(metric_error)}")
            # Provide simulated data for demonstration
            utilization_data['average_utilization'] = np.random.uniform(0.3, 0.9)
            utilization_data['peak_utilization'] = utilization_data['average_utilization'] + np.random.uniform(0.1, 0.2)
            utilization_data['service_count'] = 1
        
        logger.info(f"GPU utilization analysis: {utilization_data}")
        return utilization_data
        
    except Exception as e:
        logger.error(f"Failed to get utilization metrics: {str(e)}")
        return {'error': str(e)}

def load_quota_policies(storage_client, project_id: str) -> Dict:
    """Load quota management policies from Cloud Storage"""
    try:
        # Find bucket with quota policies
        bucket_name = None
        for bucket in storage_client.list_buckets():
            if bucket.name.startswith(f"{project_id}-quota-policies"):
                bucket_name = bucket.name
                break
        
        if not bucket_name:
            logger.warning("Quota policies bucket not found, using default policies")
            return {
                "allocation_thresholds": {
                    "gpu_utilization_trigger": 0.8,
                    "cpu_utilization_trigger": 0.75,
                    "memory_utilization_trigger": 0.85
                },
                "gpu_families": {
                    "nvidia-l4": {"max_quota": 10, "min_quota": 1, "increment_size": 2},
                    "nvidia-t4": {"max_quota": 8, "min_quota": 1, "increment_size": 1}
                }
            }
        
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob('quota-policy.json')
        
        policy_content = blob.download_as_text()
        return json.loads(policy_content)
        
    except Exception as e:
        logger.error(f"Failed to load quota policies: {str(e)}")
        return {}

def generate_quota_recommendations(
    utilization_data: Dict, policies: Dict, firestore_client
) -> List[Dict]:
    """Generate intelligent quota adjustment recommendations"""
    recommendations = []
    
    if not utilization_data or 'average_utilization' not in utilization_data:
        return recommendations
    
    avg_util = utilization_data['average_utilization']
    peak_util = utilization_data['peak_utilization']
    
    # Check if utilization exceeds thresholds
    gpu_threshold = policies.get('allocation_thresholds', {}).get('gpu_utilization_trigger', 0.8)
    
    if peak_util > gpu_threshold:
        # Recommend quota increase
        for gpu_family, settings in policies.get('gpu_families', {}).items():
            current_quota = get_current_quota(gpu_family)
            new_quota = min(
                current_quota + settings.get('increment_size', 1),
                settings.get('max_quota', 10)
            )
            
            if new_quota > current_quota:
                recommendations.append({
                    'action': 'increase',
                    'gpu_family': gpu_family,
                    'current_quota': current_quota,
                    'recommended_quota': new_quota,
                    'reason': f'Peak utilization {peak_util:.2f} exceeds threshold {gpu_threshold}'
                })
    
    elif avg_util < gpu_threshold * 0.5:
        # Consider quota decrease for cost optimization
        for gpu_family, settings in policies.get('gpu_families', {}).items():
            current_quota = get_current_quota(gpu_family)
            new_quota = max(
                current_quota - 1,
                settings.get('min_quota', 1)
            )
            
            if new_quota < current_quota:
                recommendations.append({
                    'action': 'decrease',
                    'gpu_family': gpu_family,
                    'current_quota': current_quota,
                    'recommended_quota': new_quota,
                    'reason': f'Low utilization {avg_util:.2f} allows cost optimization'
                })
    
    return recommendations

def get_current_quota(gpu_family: str) -> int:
    """Get current GPU quota for specified family"""
    # Simplified implementation - would query Cloud Quotas API in production
    return np.random.randint(2, 6)  # Random quota between 2-5 for demo

def execute_quota_adjustments(
    quotas_client, recommendations: List[Dict], project_id: str
) -> List[Dict]:
    """Execute approved quota adjustments via Cloud Quotas API"""
    results = []
    
    for rec in recommendations:
        try:
            # Create quota preference request (simulation)
            quota_preference = {
                'service': 'run.googleapis.com',
                'quota_id': f'GPU-{rec["gpu_family"].upper()}-per-project-region',
                'quota_config': {
                    'preferred_value': rec['recommended_quota']
                },
                'dimensions': {
                    'region': 'us-central1',
                    'gpu_family': rec['gpu_family']
                },
                'justification': f'Automated allocation: {rec["reason"]}',
                'contact_email': 'admin@example.com'
            }
            
            logger.info(f"Simulating quota adjustment: {quota_preference}")
            
            # Store successful execution
            results.append({
                'recommendation': rec,
                'status': 'simulated',
                'timestamp': datetime.utcnow().isoformat(),
                'quota_preference': quota_preference
            })
            
        except Exception as e:
            logger.error(f"Failed to execute quota adjustment: {str(e)}")
            results.append({
                'recommendation': rec,
                'status': 'failed',
                'error': str(e)
            })
    
    return results

def store_allocation_history(firestore_client, results: List[Dict]):
    """Store allocation history in Firestore"""
    try:
        doc_ref = firestore_client.collection('quota_history').document('gpu_allocations')
        
        # Try to update existing document, create if doesn't exist
        try:
            doc_ref.update({
                'allocations': firestore.ArrayUnion([{
                    'timestamp': datetime.utcnow().isoformat(),
                    'results': results
                }])
            })
        except:
            # Document doesn't exist, create it
            doc_ref.set({
                'created_at': datetime.utcnow().isoformat(),
                'allocations': [{
                    'timestamp': datetime.utcnow().isoformat(),
                    'results': results
                }]
            })
        
        logger.info("Allocation history stored successfully")
        
    except Exception as e:
        logger.error(f"Failed to store allocation history: {str(e)}")
EOF
    
    # Deploy the Cloud Function
    log_info "Deploying Cloud Function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python311 \
        --trigger=http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=512MB \
        --timeout=540s \
        --entry-point=analyze_gpu_utilization \
        --quiet; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        cd ..
        exit 1
    fi
    
    cd ..
    log_success "Cloud Function deployment completed"
}

# Function to deploy Cloud Run GPU service
deploy_cloud_run_service() {
    log_info "Creating and deploying Cloud Run GPU service..."
    
    # Create directory for Cloud Run service
    local service_dir="ai-inference-service"
    mkdir -p "${service_dir}"
    cd "${service_dir}"
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Set environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Start the application
CMD ["python", "app.py"]
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
flask==2.3.3
google-cloud-monitoring==2.16.0
numpy==1.24.3
psutil==5.9.6
gunicorn==21.2.0
EOF
    
    # Create main application code
    cat > app.py << 'EOF'
import os
import time
import json
import psutil
import logging
from flask import Flask, request, jsonify
from google.cloud import monitoring_v3
from datetime import datetime
import numpy as np

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize monitoring client
project_id = os.environ.get('GOOGLE_CLOUD_PROJECT', 'default-project')

@app.route('/')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'ai-inference',
        'timestamp': datetime.utcnow().isoformat(),
        'project_id': project_id
    })

@app.route('/infer', methods=['POST'])
def process_inference():
    """AI inference endpoint that simulates GPU workload"""
    start_time = time.time()
    
    try:
        # Get request data
        data = request.get_json() or {}
        model_type = data.get('model', 'default')
        complexity = data.get('complexity', 'medium')
        
        # Simulate GPU-intensive processing
        processing_time = simulate_gpu_inference(complexity)
        
        # Record metrics
        record_inference_metrics(processing_time, model_type)
        
        # Generate response
        result = {
            'status': 'success',
            'model': model_type,
            'processing_time': processing_time,
            'complexity': complexity,
            'inference_id': f"inf_{int(time.time())}_{hash(str(data)) % 10000}",
            'timestamp': datetime.utcnow().isoformat(),
            'project_id': project_id
        }
        
        logger.info(f"Inference completed: {result['inference_id']} in {processing_time:.2f}s")
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Inference failed: {str(e)}")
        return jsonify({
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 500

def simulate_gpu_inference(complexity: str) -> float:
    """Simulate GPU inference processing with variable load"""
    complexity_multipliers = {
        'low': 0.5,
        'medium': 1.0,
        'high': 2.0,
        'extreme': 4.0
    }
    
    base_time = 0.1  # Base processing time
    multiplier = complexity_multipliers.get(complexity, 1.0)
    
    # Simulate variable processing load
    processing_time = base_time * multiplier * (1 + np.random.uniform(0, 0.5))
    
    # Simulate actual computation
    time.sleep(min(processing_time, 2.0))  # Cap at 2 seconds for demo
    
    return processing_time

def record_inference_metrics(processing_time: float, model_type: str):
    """Record custom metrics to Cloud Monitoring"""
    try:
        logger.info(f"Recording metric: latency={processing_time:.3f}s, model={model_type}")
        # In a real environment with proper monitoring setup, this would send metrics
        
    except Exception as e:
        logger.error(f"Failed to record metrics: {str(e)}")

@app.route('/metrics')
def get_metrics():
    """Endpoint to expose current resource utilization"""
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        
        metrics = {
            'cpu_utilization': cpu_percent,
            'memory_utilization': memory.percent,
            'memory_available_gb': memory.available / (1024**3),
            'timestamp': datetime.utcnow().isoformat(),
            'project_id': project_id
        }
        
        return jsonify(metrics)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
EOF
    
    # Build and deploy to Cloud Run
    log_info "Building container image..."
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --quiet; then
        log_success "Container image built successfully"
    else
        log_error "Failed to build container image"
        cd ..
        exit 1
    fi
    
    log_info "Deploying to Cloud Run with GPU..."
    if gcloud run deploy "${SERVICE_NAME}" \
        --image="gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --region="${REGION}" \
        --gpu=1 \
        --gpu-type=nvidia-l4 \
        --memory=4Gi \
        --cpu=2 \
        --min-instances=0 \
        --max-instances=10 \
        --allow-unauthenticated \
        --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_REGION=${REGION}" \
        --quiet; then
        log_success "Cloud Run service deployed successfully"
    else
        log_warning "Failed to deploy with GPU, trying without GPU for testing..."
        # Fallback deployment without GPU for testing
        if gcloud run deploy "${SERVICE_NAME}" \
            --image="gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
            --region="${REGION}" \
            --memory=2Gi \
            --cpu=1 \
            --min-instances=0 \
            --max-instances=5 \
            --allow-unauthenticated \
            --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_REGION=${REGION}" \
            --quiet; then
            log_warning "Cloud Run service deployed without GPU (fallback mode)"
        else
            log_error "Failed to deploy Cloud Run service"
            cd ..
            exit 1
        fi
    fi
    
    cd ..
    log_success "Cloud Run service deployment completed"
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    log_info "Creating Cloud Scheduler jobs for automated analysis..."
    
    # Get Cloud Function URL
    local function_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    
    # Create regular analysis job
    log_info "Creating regular quota analysis job..."
    if gcloud scheduler jobs create http "${JOB_NAME}" \
        --location="${REGION}" \
        --schedule="*/15 * * * *" \
        --uri="${function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body="{\"project_id\":\"${PROJECT_ID}\",\"region\":\"${REGION}\"}" \
        --description="Automated GPU quota analysis and adjustment" \
        --quiet; then
        log_success "Regular analysis job created"
    else
        log_error "Failed to create regular analysis job"
        exit 1
    fi
    
    # Create peak hour analysis job
    log_info "Creating peak hour analysis job..."
    if gcloud scheduler jobs create http "${PEAK_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 9-17 * * 1-5" \
        --uri="${function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body="{\"project_id\":\"${PROJECT_ID}\",\"region\":\"${REGION}\",\"analysis_type\":\"peak\"}" \
        --description="Peak hour intensive quota analysis" \
        --quiet; then
        log_success "Peak hour analysis job created"
    else
        log_error "Failed to create peak hour analysis job"
        exit 1
    fi
    
    log_success "Cloud Scheduler jobs created successfully"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check if Cloud Function is deployed
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(status)" 2>/dev/null | grep -q "ACTIVE"; then
        log_success "Cloud Function is active"
    else
        log_warning "Cloud Function may not be fully ready yet"
    fi
    
    # Check if Cloud Run service is deployed
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" --format="value(status.url)" >/dev/null 2>&1; then
        local service_url=$(gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" --format="value(status.url)")
        log_success "Cloud Run service is deployed at: ${service_url}"
        
        # Test the health check endpoint
        log_info "Testing Cloud Run service health check..."
        if curl -s "${service_url}/" | grep -q "healthy"; then
            log_success "Cloud Run service health check passed"
        else
            log_warning "Cloud Run service health check may have failed"
        fi
    else
        log_warning "Cloud Run service may not be fully ready yet"
    fi
    
    # Check if storage bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_success "Storage bucket is accessible"
    else
        log_warning "Storage bucket may not be accessible"
    fi
    
    # Check if scheduler jobs exist
    if gcloud scheduler jobs list --location="${REGION}" --filter="name:${JOB_NAME}" --format="value(name)" | grep -q "${JOB_NAME}"; then
        log_success "Scheduler jobs are created"
    else
        log_warning "Scheduler jobs may not be fully ready yet"
    fi
    
    log_success "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Random Suffix: ${RANDOM_SUFFIX}"
    echo ""
    echo "Deployed Resources:"
    echo "- Cloud Function: ${FUNCTION_NAME}"
    echo "- Cloud Run Service: ${SERVICE_NAME}"
    echo "- Storage Bucket: ${BUCKET_NAME}"
    echo "- Scheduler Jobs: ${JOB_NAME}, ${PEAK_JOB_NAME}"
    echo ""
    
    # Get service URL if available
    local service_url=$(gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" --format="value(status.url)" 2>/dev/null || echo "Not available")
    echo "Cloud Run Service URL: ${service_url}"
    
    echo ""
    echo "Next Steps:"
    echo "1. Test the AI inference service:"
    echo "   curl -X POST ${service_url}/infer -H 'Content-Type: application/json' -d '{\"model\": \"test\", \"complexity\": \"medium\"}'"
    echo ""
    echo "2. Monitor quota analysis in Cloud Function logs:"
    echo "   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo ""
    echo "3. View Firestore data in the Console:"
    echo "   https://console.cloud.google.com/firestore/data"
    echo ""
    echo "4. Check Cloud Scheduler jobs:"
    echo "   gcloud scheduler jobs list --location=${REGION}"
    echo ""
    log_success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log_info "Starting deployment of Resource Allocation with Cloud Quotas API and Cloud Run GPU"
    
    # Store deployment info for cleanup script
    cat > .deployment_info << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
FUNCTION_NAME=${FUNCTION_NAME}
SERVICE_NAME=${SERVICE_NAME}
BUCKET_NAME=${BUCKET_NAME}
JOB_NAME=${JOB_NAME}
PEAK_JOB_NAME=${PEAK_JOB_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    initialize_firestore
    deploy_cloud_function
    deploy_cloud_run_service
    create_scheduler_jobs
    verify_deployment
    display_summary
    
    log_success "All deployment steps completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. You may need to run the destroy script to clean up partial deployment."; exit 1' INT TERM

# Run main function
main "$@"
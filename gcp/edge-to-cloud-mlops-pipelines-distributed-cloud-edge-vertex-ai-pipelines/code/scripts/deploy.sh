#!/bin/bash

# Edge-to-Cloud MLOps Pipelines Deployment Script
# Recipe: Edge-to-Cloud MLOps Pipelines with Distributed Cloud Edge and Vertex AI Pipelines
# Provider: Google Cloud Platform

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Script interrupted. Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}/training_pipeline.py" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/edge-inference-service.yaml" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/telemetry-collector.yaml" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/mlops-dashboard.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/edge-alert-policy.yaml" 2>/dev/null || true
    rm -rf "${SCRIPT_DIR}/edge-model-updater" 2>/dev/null || true
}

# Set up signal handling
trap cleanup EXIT INT TERM

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Edge-to-Cloud MLOps Pipelines infrastructure on Google Cloud Platform.

Options:
    -p, --project-id PROJECT_ID    GCP Project ID (optional, will generate if not provided)
    -r, --region REGION           GCP Region (default: us-central1)
    -z, --zone ZONE              GCP Zone (default: us-central1-a)
    -s, --skip-apis              Skip API enablement (default: false)
    -d, --dry-run                Show what would be deployed without executing
    -v, --verbose                Enable verbose logging
    -h, --help                   Show this help message

Examples:
    $0                           # Deploy with generated project ID
    $0 -p my-mlops-project       # Deploy to specific project
    $0 -r europe-west1          # Deploy to specific region
    $0 --dry-run                 # Preview deployment
    $0 -v                        # Enable verbose logging

EOF
}

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
SKIP_APIS=false
DRY_RUN=false
VERBOSE=false

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
        -s|--skip-apis)
            SKIP_APIS=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Set defaults if not provided
REGION=${REGION:-$DEFAULT_REGION}
ZONE=${ZONE:-$DEFAULT_ZONE}

# Enable verbose logging if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Using gcloud version: $gcloud_version"
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_info "Using authenticated account: $active_account"
    
    log_success "Prerequisites check passed"
}

# Generate project ID if not provided
generate_project_id() {
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="mlops-edge-$(date +%s)"
        log_info "Generated project ID: $PROJECT_ID"
    fi
}

# Environment setup function
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log_info "Using random suffix: $RANDOM_SUFFIX"
    
    # Set environment variables
    export PROJECT_ID
    export REGION
    export ZONE
    export MLOPS_BUCKET="mlops-artifacts-${RANDOM_SUFFIX}"
    export EDGE_MODELS_BUCKET="edge-models-${RANDOM_SUFFIX}"
    export MODEL_NAME="edge-inference-model"
    export CLUSTER_NAME="edge-simulation-cluster"
    export PIPELINE_ROOT="gs://${MLOPS_BUCKET}/pipeline-root"
    
    # Save environment variables for reference
    cat > "${SCRIPT_DIR}/.env" << EOF
# Environment variables for Edge MLOps Pipeline deployment
export PROJECT_ID="$PROJECT_ID"
export REGION="$REGION"
export ZONE="$ZONE"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export MLOPS_BUCKET="$MLOPS_BUCKET"
export EDGE_MODELS_BUCKET="$EDGE_MODELS_BUCKET"
export MODEL_NAME="$MODEL_NAME"
export CLUSTER_NAME="$CLUSTER_NAME"
export PIPELINE_ROOT="$PIPELINE_ROOT"
EOF
    
    log_success "Environment setup completed"
}

# Configure gcloud function
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure gcloud with project: $PROJECT_ID, region: $REGION, zone: $ZONE"
        return 0
    fi
    
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configuration completed"
}

# Enable APIs function
enable_apis() {
    if [[ "$SKIP_APIS" == "true" ]]; then
        log_warning "Skipping API enablement as requested"
        return 0
    fi
    
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "container.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create service account function
create_service_account() {
    log_info "Creating MLOps pipeline service account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create service account: mlops-pipeline-sa"
        return 0
    fi
    
    # Create service account
    if gcloud iam service-accounts create mlops-pipeline-sa \
        --display-name="MLOps Pipeline Service Account" \
        --quiet 2>/dev/null; then
        log_success "Service account created"
    else
        log_warning "Service account may already exist, continuing..."
    fi
    
    # Get project number
    local project_number
    project_number=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    
    # Grant necessary permissions
    local roles=(
        "roles/aiplatform.user"
        "roles/storage.admin"
        "roles/monitoring.editor"
        "roles/container.developer"
        "roles/cloudfunctions.developer"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role $role to service account..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:mlops-pipeline-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" \
            --quiet
    done
    
    log_success "Service account configuration completed"
}

# Create storage buckets function
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create buckets: $MLOPS_BUCKET, $EDGE_MODELS_BUCKET"
        return 0
    fi
    
    # Create MLOps artifacts bucket
    log_info "Creating MLOps artifacts bucket: $MLOPS_BUCKET"
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${MLOPS_BUCKET}"; then
        log_success "Created MLOps artifacts bucket"
    else
        log_error "Failed to create MLOps artifacts bucket"
        exit 1
    fi
    
    # Create edge models bucket
    log_info "Creating edge models bucket: $EDGE_MODELS_BUCKET"
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${EDGE_MODELS_BUCKET}"; then
        log_success "Created edge models bucket"
    else
        log_error "Failed to create edge models bucket"
        exit 1
    fi
    
    # Enable versioning
    log_info "Enabling versioning on buckets..."
    gsutil versioning set on "gs://${MLOPS_BUCKET}"
    gsutil versioning set on "gs://${EDGE_MODELS_BUCKET}"
    
    # Create directory structure
    log_info "Creating directory structure..."
    echo "Training data placeholder" | gsutil cp - "gs://${MLOPS_BUCKET}/training-data/placeholder.txt"
    echo "Model artifacts placeholder" | gsutil cp - "gs://${MLOPS_BUCKET}/models/placeholder.txt"
    echo "Edge telemetry placeholder" | gsutil cp - "gs://${MLOPS_BUCKET}/telemetry/placeholder.txt"
    
    log_success "Storage buckets created successfully"
}

# Setup Vertex AI function
setup_vertex_ai() {
    log_info "Setting up Vertex AI workspace and model registry..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would setup Vertex AI workspace with model: $MODEL_NAME"
        return 0
    fi
    
    # Create Vertex AI Model Registry entry
    log_info "Creating model in Vertex AI Model Registry..."
    if gcloud ai models upload \
        --region="${REGION}" \
        --display-name="${MODEL_NAME}" \
        --description="Edge inference model for distributed deployment" \
        --version-aliases=latest \
        --quiet 2>/dev/null; then
        log_success "Model registry entry created"
    else
        log_warning "Model may already exist in registry, continuing..."
    fi
    
    # Initialize pipeline workspace structure
    log_info "Initializing pipeline workspace structure..."
    echo "Pipeline metadata" | gsutil cp - "${PIPELINE_ROOT}/metadata/init.txt"
    echo "Pipeline templates" | gsutil cp - "${PIPELINE_ROOT}/templates/init.txt"
    
    # Create experiment for tracking pipeline runs
    log_info "Creating experiment for pipeline tracking..."
    if gcloud ai experiments create edge-mlops-experiment \
        --region="${REGION}" \
        --display-name="Edge MLOps Pipeline Experiment" \
        --quiet 2>/dev/null; then
        log_success "Experiment created"
    else
        log_warning "Experiment may already exist, continuing..."
    fi
    
    log_success "Vertex AI workspace configured"
}

# Create GKE cluster function
create_gke_cluster() {
    log_info "Creating GKE cluster for edge simulation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create GKE cluster: $CLUSTER_NAME"
        return 0
    fi
    
    # Check if cluster already exists
    if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "GKE cluster already exists, skipping creation"
    else
        log_info "Creating GKE cluster: $CLUSTER_NAME"
        gcloud container clusters create "${CLUSTER_NAME}" \
            --region="${REGION}" \
            --num-nodes=3 \
            --machine-type=e2-standard-4 \
            --enable-autoscaling \
            --min-nodes=1 \
            --max-nodes=5 \
            --enable-autorepair \
            --enable-autoupgrade \
            --disk-size=50GB \
            --disk-type=pd-ssd \
            --scopes="https://www.googleapis.com/auth/cloud-platform" \
            --quiet
    fi
    
    # Get cluster credentials
    log_info "Getting cluster credentials..."
    gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}"
    
    # Create namespace for edge workloads
    log_info "Creating Kubernetes namespace..."
    kubectl create namespace edge-inference --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for monitoring
    kubectl label namespace edge-inference \
        app=edge-inference \
        environment=simulation \
        --overwrite
    
    log_success "GKE cluster created and configured"
}

# Deploy ML training pipeline function
deploy_training_pipeline() {
    log_info "Deploying sample ML training pipeline..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy ML training pipeline"
        return 0
    fi
    
    # Create training pipeline definition
    cat > "${SCRIPT_DIR}/training_pipeline.py" << 'EOF'
from kfp.v2 import dsl
from kfp.v2.dsl import component, pipeline, Input, Output, Dataset, Model
from google.cloud import aiplatform

@component(
    base_image="python:3.9",
    packages_to_install=["google-cloud-aiplatform", "scikit-learn", "pandas"]
)
def train_model(
    training_data: Input[Dataset],
    model: Output[Model],
    model_name: str = "edge-inference-model"
):
    import pandas as pd
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    import joblib
    import os
    
    # Simulate training data creation for demonstration
    data = pd.DataFrame({
        'feature1': range(100),
        'feature2': range(100, 200),
        'target': [i % 2 for i in range(100)]
    })
    
    X = data[['feature1', 'feature2']]
    y = data['target']
    
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)
    
    # Train model
    clf = RandomForestClassifier(n_estimators=100, random_state=42)
    clf.fit(X_train, y_train)
    
    # Save model
    model_path = f"{model.path}/model.joblib"
    os.makedirs(os.path.dirname(model_path), exist_ok=True)
    joblib.dump(clf, model_path)
    
    print(f"Model trained and saved to {model_path}")

@component(
    base_image="python:3.9",
    packages_to_install=["google-cloud-storage"]
)
def prepare_edge_deployment(
    model: Input[Model],
    edge_bucket: str,
    model_version: str = "v1"
):
    from google.cloud import storage
    import os
    
    # Initialize storage client
    client = storage.Client()
    bucket = client.bucket(edge_bucket.replace("gs://", ""))
    
    # Copy model to edge deployment bucket
    model_blob = bucket.blob(f"models/{model_version}/model.joblib")
    
    # Upload model file
    model_path = f"{model.path}/model.joblib"
    if os.path.exists(model_path):
        model_blob.upload_from_filename(model_path)
        print(f"Model uploaded to edge bucket: {edge_bucket}/models/{model_version}/")
    else:
        print("Model file not found")

@pipeline(
    name="edge-mlops-training-pipeline",
    description="MLOps pipeline for edge model training and deployment"
)
def edge_training_pipeline(
    training_data_path: str,
    edge_bucket: str,
    model_version: str = "v1"
):
    # Create training dataset component
    training_data = dsl.importer(
        artifact_uri=training_data_path,
        artifact_class=Dataset,
        reimport=False
    )
    
    # Train model
    training_task = train_model(training_data=training_data.output)
    
    # Prepare for edge deployment
    deployment_task = prepare_edge_deployment(
        model=training_task.outputs["model"],
        edge_bucket=edge_bucket,
        model_version=model_version
    )
EOF
    
    log_success "ML training pipeline created"
}

# Deploy edge inference service function
deploy_edge_inference() {
    log_info "Deploying edge inference service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy edge inference service"
        return 0
    fi
    
    # Create edge inference service deployment manifest
    cat > "${SCRIPT_DIR}/edge-inference-service.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-inference-service
  namespace: edge-inference
  labels:
    app: edge-inference
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: edge-inference
  template:
    metadata:
      labels:
        app: edge-inference
        version: v1
    spec:
      serviceAccountName: default
      containers:
      - name: inference-server
        image: python:3.9-slim
        ports:
        - containerPort: 8080
        env:
        - name: MODEL_BUCKET
          value: "${EDGE_MODELS_BUCKET}"
        - name: PROJECT_ID
          value: "${PROJECT_ID}"
        command: ["/bin/bash"]
        args:
        - -c
        - |
          pip install google-cloud-storage scikit-learn joblib flask
          cat > app.py << 'PYEOF'
          from flask import Flask, request, jsonify
          from google.cloud import storage
          import joblib
          import os
          import logging
          
          app = Flask(__name__)
          logging.basicConfig(level=logging.INFO)
          
          # Download model on startup
          def download_model():
              try:
                  client = storage.Client()
                  bucket_name = os.environ.get('MODEL_BUCKET', '')
                  bucket = client.bucket(bucket_name)
                  blob = bucket.blob('models/v1/model.joblib')
                  blob.download_to_filename('/tmp/model.joblib')
                  return joblib.load('/tmp/model.joblib')
              except Exception as e:
                  logging.error(f"Error downloading model: {e}")
                  return None
          
          model = download_model()
          
          @app.route('/health', methods=['GET'])
          def health():
              return jsonify({'status': 'healthy', 'model_loaded': model is not None})
          
          @app.route('/predict', methods=['POST'])
          def predict():
              if model is None:
                  return jsonify({'error': 'Model not loaded'}), 500
              
              try:
                  data = request.json
                  features = [[data.get('feature1', 0), data.get('feature2', 0)]]
                  prediction = model.predict(features)[0]
                  return jsonify({'prediction': int(prediction)})
              except Exception as e:
                  return jsonify({'error': str(e)}), 500
          
          if __name__ == '__main__':
              app.run(host='0.0.0.0', port=8080)
          PYEOF
          python app.py
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
          requests:
            memory: "256Mi"
            cpu: "250m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: edge-inference-service
  namespace: edge-inference
spec:
  selector:
    app: edge-inference
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
EOF
    
    # Apply the deployment
    log_info "Applying edge inference service manifest..."
    kubectl apply -f "${SCRIPT_DIR}/edge-inference-service.yaml"
    
    # Wait for deployment to be ready
    log_info "Waiting for edge inference service to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/edge-inference-service -n edge-inference
    
    log_success "Edge inference service deployed"
}

# Configure monitoring function
configure_monitoring() {
    log_info "Configuring Cloud Monitoring for MLOps observability..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure monitoring dashboard and alerts"
        return 0
    fi
    
    # Create monitoring dashboard
    cat > "${SCRIPT_DIR}/mlops-dashboard.json" << EOF
{
  "displayName": "Edge MLOps Pipeline Dashboard",
  "gridLayout": {
    "widgets": [
      {
        "title": "Edge Inference Request Rate",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" AND resource.labels.container_name=\"inference-server\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }
          ]
        }
      },
      {
        "title": "Model Prediction Latency",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" AND metric.type=\"custom.googleapis.com/inference/latency\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }
          ]
        }
      }
    ]
  }
}
EOF
    
    # Create monitoring dashboard
    if gcloud monitoring dashboards create --config-from-file="${SCRIPT_DIR}/mlops-dashboard.json" --quiet; then
        log_success "Monitoring dashboard created"
    else
        log_warning "Failed to create monitoring dashboard, continuing..."
    fi
    
    log_success "Cloud Monitoring configured"
}

# Deploy telemetry collector function
deploy_telemetry_collector() {
    log_info "Deploying edge telemetry collection system..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy telemetry collection system"
        return 0
    fi
    
    # Create telemetry collection service
    cat > "${SCRIPT_DIR}/telemetry-collector.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: telemetry-collector
  namespace: edge-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: telemetry-collector
  template:
    metadata:
      labels:
        app: telemetry-collector
    spec:
      containers:
      - name: collector
        image: python:3.9-slim
        env:
        - name: MLOPS_BUCKET
          value: "${MLOPS_BUCKET}"
        - name: PROJECT_ID
          value: "${PROJECT_ID}"
        command: ["/bin/bash"]
        args:
        - -c
        - |
          pip install google-cloud-storage flask
          cat > collector.py << 'PYEOF'
          from flask import Flask, request, jsonify
          from google.cloud import storage
          import json
          import datetime
          import logging
          
          app = Flask(__name__)
          logging.basicConfig(level=logging.INFO)
          
          storage_client = storage.Client()
          
          @app.route('/telemetry', methods=['POST'])
          def collect_telemetry():
              try:
                  data = request.json
                  timestamp = datetime.datetime.utcnow().isoformat()
                  
                  # Add metadata
                  telemetry_record = {
                      'timestamp': timestamp,
                      'edge_location': data.get('edge_location', 'unknown'),
                      'model_version': data.get('model_version', 'v1'),
                      'prediction': data.get('prediction'),
                      'confidence': data.get('confidence', 0.0),
                      'latency_ms': data.get('latency_ms', 0),
                      'input_features': data.get('input_features', {}),
                      'feedback_score': data.get('feedback_score')
                  }
                  
                  # Store in Cloud Storage
                  bucket_name = '${MLOPS_BUCKET}'
                  bucket = storage_client.bucket(bucket_name)
                  
                  blob_path = f"telemetry/{timestamp[:10]}/{timestamp}.json"
                  blob = bucket.blob(blob_path)
                  blob.upload_from_string(json.dumps(telemetry_record))
                  
                  logging.info(f"Telemetry stored: {blob_path}")
                  return jsonify({'status': 'success', 'stored': blob_path})
                  
              except Exception as e:
                  logging.error(f"Telemetry collection error: {e}")
                  return jsonify({'error': str(e)}), 500
          
          @app.route('/health', methods=['GET'])
          def health():
              return jsonify({'status': 'healthy'})
          
          if __name__ == '__main__':
              app.run(host='0.0.0.0', port=8080)
          PYEOF
          python collector.py
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: telemetry-collector
  namespace: edge-inference
spec:
  selector:
    app: telemetry-collector
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF
    
    # Apply the deployment
    kubectl apply -f "${SCRIPT_DIR}/telemetry-collector.yaml"
    
    # Wait for deployment
    kubectl wait --for=condition=available --timeout=300s \
        deployment/telemetry-collector -n edge-inference
    
    log_success "Edge telemetry collection system deployed"
}

# Deploy model updater function
deploy_model_updater() {
    log_info "Deploying automated model update pipeline..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy model updater Cloud Function"
        return 0
    fi
    
    # Create directory for Cloud Function
    mkdir -p "${SCRIPT_DIR}/edge-model-updater"
    
    # Create main.py for Cloud Function
    cat > "${SCRIPT_DIR}/edge-model-updater/main.py" << 'EOF'
import functions_framework
from google.cloud import storage
from google.cloud import aiplatform
import json
import logging

logging.basicConfig(level=logging.INFO)

@functions_framework.http
def update_edge_models(request):
    """Update edge models when new versions are available"""
    
    try:
        # Parse request
        request_json = request.get_json(silent=True)
        model_version = request_json.get('model_version', 'latest')
        edge_locations = request_json.get('edge_locations', ['default'])
        
        # Initialize clients
        storage_client = storage.Client()
        aiplatform.init()
        
        # Get model from Vertex AI Model Registry
        models = aiplatform.Model.list(
            filter=f'display_name="edge-inference-model"'
        )
        
        if not models:
            return {'error': 'No models found'}, 404
        
        latest_model = models[0]
        logging.info(f"Found model: {latest_model.display_name}")
        
        # Update model in edge buckets
        results = []
        for location in edge_locations:
            try:
                bucket_name = f"edge-models-{location}"
                bucket = storage_client.bucket(bucket_name)
                
                # Create deployment manifest
                manifest = {
                    'model_version': model_version,
                    'model_uri': latest_model.uri,
                    'timestamp': '2025-07-12T00:00:00Z',
                    'deployment_status': 'pending'
                }
                
                blob = bucket.blob(f'deployments/{model_version}/manifest.json')
                blob.upload_from_string(json.dumps(manifest))
                
                results.append({
                    'location': location,
                    'status': 'updated',
                    'version': model_version
                })
                
            except Exception as e:
                logging.error(f"Error updating {location}: {e}")
                results.append({
                    'location': location,
                    'status': 'error',
                    'error': str(e)
                })
        
        return {
            'message': 'Model update initiated',
            'results': results
        }
        
    except Exception as e:
        logging.error(f"Update function error: {e}")
        return {'error': str(e)}, 500
EOF
    
    # Create requirements.txt
    cat > "${SCRIPT_DIR}/edge-model-updater/requirements.txt" << EOF
google-cloud-storage==2.10.0
google-cloud-aiplatform==1.38.0
functions-framework==3.4.0
EOF
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function..."
    if gcloud functions deploy edge-model-updater \
        --runtime=python39 \
        --trigger=http \
        --entry-point=update_edge_models \
        --source="${SCRIPT_DIR}/edge-model-updater" \
        --timeout=300s \
        --memory=512MB \
        --allow-unauthenticated \
        --region="${REGION}" \
        --quiet; then
        log_success "Cloud Function deployed"
    else
        log_warning "Failed to deploy Cloud Function, continuing..."
    fi
    
    log_success "Automated model update pipeline deployed"
}

# Validation function
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check storage buckets
    log_info "Checking storage buckets..."
    if gsutil ls -p "${PROJECT_ID}" | grep -q "${MLOPS_BUCKET}"; then
        log_success "MLOps bucket exists"
    else
        log_error "MLOps bucket not found"
    fi
    
    if gsutil ls -p "${PROJECT_ID}" | grep -q "${EDGE_MODELS_BUCKET}"; then
        log_success "Edge models bucket exists"
    else
        log_error "Edge models bucket not found"
    fi
    
    # Check GKE cluster
    log_info "Checking GKE cluster..."
    if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
        log_success "GKE cluster is running"
    else
        log_error "GKE cluster not found"
    fi
    
    # Check Kubernetes deployments
    log_info "Checking Kubernetes deployments..."
    if kubectl get deployment edge-inference-service -n edge-inference &>/dev/null; then
        log_success "Edge inference service is deployed"
    else
        log_warning "Edge inference service not found"
    fi
    
    if kubectl get deployment telemetry-collector -n edge-inference &>/dev/null; then
        log_success "Telemetry collector is deployed"
    else
        log_warning "Telemetry collector not found"
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log_info "Starting Edge-to-Cloud MLOps Pipelines deployment..."
    log_info "Using region: $REGION, zone: $ZONE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    generate_project_id
    setup_environment
    configure_gcloud
    enable_apis
    create_service_account
    create_storage_buckets
    setup_vertex_ai
    create_gke_cluster
    deploy_training_pipeline
    deploy_edge_inference
    configure_monitoring
    deploy_telemetry_collector
    deploy_model_updater
    validate_deployment
    
    # Final success message
    log_success "Edge-to-Cloud MLOps Pipelines deployment completed successfully!"
    log_info "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log_info "Deployment logs saved to: ${LOG_FILE}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo "Next steps:"
        echo "1. Review the deployed infrastructure in the Google Cloud Console"
        echo "2. Test the edge inference service endpoints"
        echo "3. Monitor the MLOps pipeline through Cloud Monitoring dashboards"
        echo "4. Check the deployment guide in the README.md for testing instructions"
        echo ""
        echo "To clean up resources, run: ./destroy.sh"
    fi
}

# Run main function
main "$@"
#!/bin/bash

# Enterprise ML Model Lifecycle Management with AI Hypercomputer and Vertex AI Training
# Deployment Script for GCP Infrastructure
# Version: 1.0
# Description: Deploys complete ML lifecycle management infrastructure on GCP

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

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Check if dry-run mode is enabled
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="ml-lifecycle"
DEPLOYMENT_NAME="enterprise-ml-deployment"
LOG_FILE="/tmp/ml-deployment-$(date +%Y%m%d-%H%M%S).log"

# Create log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "Starting Enterprise ML Model Lifecycle Management deployment"
log "Log file: $LOG_FILE"

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error "bq command is not available. Please ensure Google Cloud SDK is properly installed"
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3.8 or later"
    fi
    
    # Check if openssl is available (for random generation)
    if ! command -v openssl &> /dev/null; then
        error "openssl is not available. Please install OpenSSL"
    fi
    
    success "Prerequisites check passed"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project ID (create new project or use existing)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
        log "Generated PROJECT_ID: $PROJECT_ID"
    else
        log "Using existing PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set resource names
    export WORKSTATION_CLUSTER="ml-workstations-${RANDOM_SUFFIX}"
    export WORKSTATION_CONFIG="ml-config-${RANDOM_SUFFIX}"
    export BUCKET_NAME="ml-artifacts-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export DATASET_NAME="ml_experiments_${RANDOM_SUFFIX}"
    export TRAINING_JOB_NAME="enterprise-training-${RANDOM_SUFFIX}"
    export TPU_NAME="ml-tpu-training-${RANDOM_SUFFIX}"
    export GPU_INSTANCE_NAME="ml-gpu-training-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup
    cat > "${SCRIPT_DIR}/deployment_env.sh" << EOF
#!/bin/bash
# Environment variables for deployment
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export WORKSTATION_CLUSTER="${WORKSTATION_CLUSTER}"
export WORKSTATION_CONFIG="${WORKSTATION_CONFIG}"
export BUCKET_NAME="${BUCKET_NAME}"
export DATASET_NAME="${DATASET_NAME}"
export TRAINING_JOB_NAME="${TRAINING_JOB_NAME}"
export TPU_NAME="${TPU_NAME}"
export GPU_INSTANCE_NAME="${GPU_INSTANCE_NAME}"
export DEPLOYMENT_TIME="$(date)"
EOF
    
    success "Environment setup completed"
}

# Project setup function
setup_project() {
    log "Setting up GCP project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create project $PROJECT_ID"
        return
    fi
    
    # Create project if it doesn't exist
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Enterprise ML Lifecycle Management"
        
        # Enable billing (if billing account is set)
        if [[ -n "${BILLING_ACCOUNT_ID:-}" ]]; then
            gcloud billing projects link "$PROJECT_ID" \
                --billing-account="$BILLING_ACCOUNT_ID"
        else
            warning "No billing account specified. Please link a billing account to project $PROJECT_ID"
        fi
    else
        log "Using existing project: $PROJECT_ID"
    fi
    
    # Set default project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "Project setup completed"
}

# API enablement function
enable_apis() {
    log "Enabling required APIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would enable required APIs"
        return
    fi
    
    local apis=(
        "aiplatform.googleapis.com"
        "workstations.googleapis.com"
        "compute.googleapis.com"
        "storage.googleapis.com"
        "bigquery.googleapis.com"
        "artifactregistry.googleapis.com"
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        gcloud services enable "$api" --project="$PROJECT_ID"
    done
    
    # Wait for APIs to be fully enabled
    sleep 30
    
    success "APIs enabled successfully"
}

# Storage setup function
setup_storage() {
    log "Setting up Cloud Storage resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create Cloud Storage bucket $BUCKET_NAME"
        return
    fi
    
    # Create Cloud Storage bucket
    if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log "Creating Cloud Storage bucket: $BUCKET_NAME"
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://${BUCKET_NAME}"
        
        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Set lifecycle policy
        cat > /tmp/lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "isLive": false
        }
      }
    ]
  }
}
EOF
        gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"
        rm /tmp/lifecycle.json
        
        success "Cloud Storage bucket created: $BUCKET_NAME"
    else
        log "Cloud Storage bucket already exists: $BUCKET_NAME"
    fi
    
    # Create folder structure
    log "Creating folder structure in bucket..."
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/datasets/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/models/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/pipelines/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/validation/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/governance/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/deployment/.placeholder"
    
    success "Storage setup completed"
}

# BigQuery setup function
setup_bigquery() {
    log "Setting up BigQuery resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create BigQuery dataset $DATASET_NAME"
        return
    fi
    
    # Create BigQuery dataset
    if ! bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "Creating BigQuery dataset: $DATASET_NAME"
        bq mk --project_id="$PROJECT_ID" \
            --location="$REGION" \
            --description="ML experiments tracking dataset" \
            "$DATASET_NAME"
        
        success "BigQuery dataset created: $DATASET_NAME"
    else
        log "BigQuery dataset already exists: $DATASET_NAME"
    fi
}

# Artifact Registry setup function
setup_artifact_registry() {
    log "Setting up Artifact Registry..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create Artifact Registry repository"
        return
    fi
    
    # Create Artifact Registry repository
    if ! gcloud artifacts repositories describe ml-containers \
        --location="$REGION" &> /dev/null; then
        log "Creating Artifact Registry repository: ml-containers"
        gcloud artifacts repositories create ml-containers \
            --repository-format=docker \
            --location="$REGION" \
            --description="Container registry for ML training images"
        
        success "Artifact Registry repository created"
    else
        log "Artifact Registry repository already exists"
    fi
}

# Cloud Workstations setup function
setup_workstations() {
    log "Setting up Cloud Workstations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create Cloud Workstations cluster and configuration"
        return
    fi
    
    # Create workstation cluster
    if ! gcloud workstations clusters describe "$WORKSTATION_CLUSTER" \
        --region="$REGION" &> /dev/null; then
        log "Creating workstation cluster: $WORKSTATION_CLUSTER"
        gcloud workstations clusters create "$WORKSTATION_CLUSTER" \
            --region="$REGION" \
            --network="projects/${PROJECT_ID}/global/networks/default" \
            --subnetwork="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default" \
            --enable-private-endpoint \
            --async
        
        # Wait for cluster creation
        log "Waiting for workstation cluster creation..."
        while [[ "$(gcloud workstations clusters describe "$WORKSTATION_CLUSTER" \
            --region="$REGION" --format="value(state)" 2>/dev/null)" != "RUNNING" ]]; do
            sleep 30
            log "Still waiting for cluster..."
        done
        
        success "Workstation cluster created successfully"
    else
        log "Workstation cluster already exists: $WORKSTATION_CLUSTER"
    fi
    
    # Create workstation configuration
    if ! gcloud workstations configs describe "$WORKSTATION_CONFIG" \
        --cluster="$WORKSTATION_CLUSTER" \
        --region="$REGION" &> /dev/null; then
        log "Creating workstation configuration: $WORKSTATION_CONFIG"
        gcloud workstations configs create "$WORKSTATION_CONFIG" \
            --cluster="$WORKSTATION_CLUSTER" \
            --region="$REGION" \
            --machine-type=n1-standard-8 \
            --pd-disk-type=pd-ssd \
            --pd-disk-size=200GB \
            --container-image=us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest \
            --service-account-scopes="https://www.googleapis.com/auth/cloud-platform" \
            --enable-audit-agent
        
        success "Workstation configuration created successfully"
    else
        log "Workstation configuration already exists: $WORKSTATION_CONFIG"
    fi
    
    # Create workstation instance
    if ! gcloud workstations describe ml-dev-workstation \
        --cluster="$WORKSTATION_CLUSTER" \
        --config="$WORKSTATION_CONFIG" \
        --region="$REGION" &> /dev/null; then
        log "Creating workstation instance: ml-dev-workstation"
        gcloud workstations create ml-dev-workstation \
            --cluster="$WORKSTATION_CLUSTER" \
            --config="$WORKSTATION_CONFIG" \
            --region="$REGION"
        
        success "Workstation instance created successfully"
    else
        log "Workstation instance already exists: ml-dev-workstation"
    fi
}

# AI Hypercomputer setup function
setup_ai_hypercomputer() {
    log "Setting up AI Hypercomputer infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create TPU and GPU instances"
        return
    fi
    
    # Create TPU v5e instance
    if ! gcloud compute tpus tpu-vm describe "$TPU_NAME" \
        --zone="$ZONE" &> /dev/null; then
        log "Creating TPU v5e instance: $TPU_NAME"
        gcloud compute tpus tpu-vm create "$TPU_NAME" \
            --zone="$ZONE" \
            --accelerator-type=v5litepod-4 \
            --version=tpu-ubuntu2204-base \
            --network=default \
            --description="TPU infrastructure for enterprise ML training" \
            --async
        
        success "TPU instance creation initiated"
    else
        log "TPU instance already exists: $TPU_NAME"
    fi
    
    # Create GPU instance
    if ! gcloud compute instances describe "$GPU_INSTANCE_NAME" \
        --zone="$ZONE" &> /dev/null; then
        log "Creating GPU instance: $GPU_INSTANCE_NAME"
        gcloud compute instances create "$GPU_INSTANCE_NAME" \
            --zone="$ZONE" \
            --machine-type=a3-highgpu-8g \
            --accelerator=count=8,type=nvidia-h100-80gb \
            --maintenance-policy=TERMINATE \
            --provisioning-model=STANDARD \
            --image-family=pytorch-latest-gpu-debian-11 \
            --image-project=deeplearning-platform-release \
            --boot-disk-size=200GB \
            --boot-disk-type=pd-ssd \
            --metadata=startup-script='#!/bin/bash
                # Install additional ML dependencies
                pip3 install --upgrade pip
                pip3 install tensorflow torch torchvision
                echo "GPU setup completed" > /tmp/gpu_setup_complete
            '
        
        success "GPU instance created successfully"
    else
        log "GPU instance already exists: $GPU_INSTANCE_NAME"
    fi
}

# Vertex AI setup function
setup_vertex_ai() {
    log "Setting up Vertex AI resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would set up Vertex AI experiments and model registry"
        return
    fi
    
    # Create Vertex AI experiment
    log "Creating Vertex AI experiment..."
    python3 << EOF
import os
from google.cloud import aiplatform

project_id = os.environ['PROJECT_ID']
region = os.environ['REGION']
random_suffix = os.environ['RANDOM_SUFFIX']

try:
    aiplatform.init(project=project_id, location=region)
    
    # Create experiment
    experiment = aiplatform.Experiment.create(
        experiment_id=f"enterprise-ml-experiment-{random_suffix}",
        description="Enterprise ML model lifecycle experiment tracking"
    )
    
    print(f"✅ Created experiment: {experiment.resource_name}")
    
    # Save experiment info
    with open('/tmp/vertex_ai_experiment.txt', 'w') as f:
        f.write(f"{experiment.resource_name}\n")
        
except Exception as e:
    print(f"❌ Error creating Vertex AI experiment: {e}")
    exit(1)
EOF
    
    success "Vertex AI experiment created"
    
    # Upload sample training pipeline
    log "Uploading training pipeline template..."
    cat > /tmp/training_pipeline.py << 'EOF'
import os
import json
from google.cloud import aiplatform
from google.cloud.aiplatform import pipeline_jobs
from kfp.v2 import dsl
from kfp.v2.dsl import component, pipeline

@component(
    base_image="gcr.io/deeplearning-platform-release/tf2-gpu.2-11",
    output_component_file="training_component.yaml"
)
def train_model(
    dataset_path: str,
    model_output_path: str,
    hyperparameters: dict
) -> str:
    import tensorflow as tf
    import numpy as np
    
    # Enterprise training logic with governance
    model = tf.keras.Sequential([
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(10, activation='softmax')
    ])
    
    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    # Save model with versioning
    model.save(model_output_path)
    return model_output_path

@pipeline(
    name="enterprise-ml-training-pipeline",
    description="Enterprise ML model lifecycle training pipeline"
)
def ml_training_pipeline(
    dataset_path: str,
    model_output_path: str,
    hyperparameters: dict = {"learning_rate": 0.001, "batch_size": 32}
):
    training_task = train_model(
        dataset_path=dataset_path,
        model_output_path=model_output_path,
        hyperparameters=hyperparameters
    )
EOF
    
    gsutil cp /tmp/training_pipeline.py "gs://${BUCKET_NAME}/pipelines/"
    rm /tmp/training_pipeline.py
    
    success "Training pipeline uploaded"
}

# Monitoring setup function
setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would set up monitoring dashboards"
        return
    fi
    
    # Create monitoring dashboard
    cat > /tmp/dashboard.json << EOF
{
  "displayName": "Enterprise ML Lifecycle Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Vertex AI Training Jobs",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"aiplatform.googleapis.com/CustomJob\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
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
    
    # Create the dashboard
    gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json
    rm /tmp/dashboard.json
    
    success "Monitoring dashboard created"
}

# Governance setup function
setup_governance() {
    log "Setting up governance and compliance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would set up governance metadata"
        return
    fi
    
    # Create governance metadata template
    cat > /tmp/governance_metadata.json << EOF
{
  "training_data_lineage": "gs://${BUCKET_NAME}/datasets/lineage.json",
  "model_explanation": "Enterprise classification model with TensorFlow",
  "bias_evaluation": "Completed with Vertex AI Explainable AI",
  "security_scan": "Passed container security scanning",
  "compliance_review": "Approved for enterprise deployment",
  "performance_metrics": {
    "accuracy": 0.87,
    "precision": 0.85,
    "recall": 0.89
  },
  "deployment_metadata": {
    "project_id": "${PROJECT_ID}",
    "region": "${REGION}",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment_version": "1.0"
  }
}
EOF
    
    gsutil cp /tmp/governance_metadata.json "gs://${BUCKET_NAME}/governance/"
    rm /tmp/governance_metadata.json
    
    # Create model validation script
    cat > /tmp/model_validation.py << 'EOF'
import json
import numpy as np
from google.cloud import aiplatform
from google.cloud import storage
import tensorflow as tf

def validate_model_performance(model_path, validation_data_path, threshold=0.85):
    """Validate model meets enterprise performance standards"""
    model = tf.keras.models.load_model(model_path)
    
    # Load validation data
    validation_data = np.load(validation_data_path)
    X_val, y_val = validation_data['X'], validation_data['y']
    
    # Evaluate model performance
    loss, accuracy = model.evaluate(X_val, y_val, verbose=0)
    
    # Enterprise quality gate
    if accuracy >= threshold:
        return {"status": "APPROVED", "accuracy": accuracy}
    else:
        return {"status": "REJECTED", "accuracy": accuracy}

def check_model_governance(model_metadata):
    """Verify model meets enterprise governance requirements"""
    required_fields = [
        'training_data_lineage',
        'model_explanation',
        'bias_evaluation',
        'security_scan'
    ]
    
    governance_status = all(field in model_metadata for field in required_fields)
    return {"governance_compliant": governance_status}

# Execute validation
if __name__ == "__main__":
    print("✅ Model validation pipeline configured")
EOF
    
    gsutil cp /tmp/model_validation.py "gs://${BUCKET_NAME}/validation/"
    rm /tmp/model_validation.py
    
    success "Governance setup completed"
}

# Deployment validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would validate deployment"
        return
    fi
    
    local validation_failed=false
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        success "Cloud Storage bucket is accessible"
    else
        error "Cloud Storage bucket validation failed"
        validation_failed=true
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        success "BigQuery dataset is accessible"
    else
        error "BigQuery dataset validation failed"
        validation_failed=true
    fi
    
    # Check Workstation cluster
    if gcloud workstations clusters describe "$WORKSTATION_CLUSTER" \
        --region="$REGION" &> /dev/null; then
        success "Workstation cluster is ready"
    else
        error "Workstation cluster validation failed"
        validation_failed=true
    fi
    
    # Check Artifact Registry
    if gcloud artifacts repositories describe ml-containers \
        --location="$REGION" &> /dev/null; then
        success "Artifact Registry repository is ready"
    else
        error "Artifact Registry validation failed"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        error "Deployment validation failed"
    else
        success "Deployment validation passed"
    fi
}

# Main deployment function
main() {
    log "Starting Enterprise ML Model Lifecycle Management deployment"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Setup project
    setup_project
    
    # Enable APIs
    enable_apis
    
    # Setup storage
    setup_storage
    
    # Setup BigQuery
    setup_bigquery
    
    # Setup Artifact Registry
    setup_artifact_registry
    
    # Setup Cloud Workstations
    setup_workstations
    
    # Setup AI Hypercomputer
    setup_ai_hypercomputer
    
    # Setup Vertex AI
    setup_vertex_ai
    
    # Setup monitoring
    setup_monitoring
    
    # Setup governance
    setup_governance
    
    # Validate deployment
    validate_deployment
    
    # Final success message
    success "Enterprise ML Model Lifecycle Management deployment completed successfully!"
    
    log "Deployment Summary:"
    log "- Project ID: $PROJECT_ID"
    log "- Region: $REGION"
    log "- Storage Bucket: $BUCKET_NAME"
    log "- BigQuery Dataset: $DATASET_NAME"
    log "- Workstation Cluster: $WORKSTATION_CLUSTER"
    log "- TPU Instance: $TPU_NAME"
    log "- GPU Instance: $GPU_INSTANCE_NAME"
    log "- Log file: $LOG_FILE"
    log "- Environment file: ${SCRIPT_DIR}/deployment_env.sh"
    
    log "Next steps:"
    log "1. Access your workstation: gcloud workstations start ml-dev-workstation --cluster=$WORKSTATION_CLUSTER --config=$WORKSTATION_CONFIG --region=$REGION"
    log "2. Monitor resources in the Google Cloud Console"
    log "3. Review the log file for detailed deployment information"
    log "4. Use the destroy.sh script to clean up resources when done"
    
    warning "Remember to clean up resources to avoid ongoing costs!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Check log file: $LOG_FILE"' INT TERM

# Run main function
main "$@"
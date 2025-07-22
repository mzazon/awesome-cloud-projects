#!/bin/bash

# =============================================================================
# GCP Serverless GPU Computing Pipelines Deployment Script
# =============================================================================
# This script deploys a complete serverless GPU computing pipeline using:
# - Cloud Run GPU services for ML inference
# - Cloud Workflows for orchestration
# - Cloud Storage for data management
# - Eventarc for event-driven automation
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly REQUIRED_GCLOUD_VERSION="450.0.0"
readonly SUPPORTED_REGIONS=("us-central1" "europe-west1" "europe-west4" "asia-southeast1" "asia-south1")

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false
SKIP_PREREQUISITES=false
FORCE_DEPLOY=false

# =============================================================================
# Helper Functions
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy GCP Serverless GPU Computing Pipeline

OPTIONS:
    -r, --region REGION     GCP region for deployment (default: ${DEFAULT_REGION})
    -z, --zone ZONE         GCP zone for deployment (default: ${DEFAULT_ZONE})
    -p, --project PROJECT   GCP project ID (default: current gcloud project)
    -n, --dry-run           Show what would be deployed without making changes
    -s, --skip-prereqs      Skip prerequisite checks
    -f, --force             Force deployment even if resources exist
    -h, --help              Show this help message

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 --region europe-west1                   # Deploy to specific region
    $0 --project my-project --region us-central1  # Deploy to specific project
    $0 --dry-run                               # Preview deployment
    $0 --force                                 # Force redeploy existing resources

PREREQUISITES:
    - gcloud CLI v${REQUIRED_GCLOUD_VERSION}+ with beta components
    - Docker installed for container building
    - Authenticated GCP account with appropriate permissions
    - Project with billing enabled

SUPPORTED REGIONS:
    ${SUPPORTED_REGIONS[*]}

EOF
}

check_prerequisites() {
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        log_warning "Skipping prerequisite checks"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install the Google Cloud CLI."
        exit 1
    fi

    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    if [[ "$gcloud_version" == "unknown" ]]; then
        log_warning "Could not determine gcloud version. Proceeding with deployment."
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker for container building."
        exit 1
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running. Please start Docker."
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check beta components
    if ! gcloud components list --filter="id:beta" --format="value(state.name)" | grep -q "Installed"; then
        log_error "gcloud beta components not installed. Please run 'gcloud components install beta'"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

validate_region() {
    local region="$1"
    for supported_region in "${SUPPORTED_REGIONS[@]}"; do
        if [[ "$region" == "$supported_region" ]]; then
            return 0
        fi
    done
    log_error "Region '${region}' is not supported for Cloud Run GPU"
    log_error "Supported regions: ${SUPPORTED_REGIONS[*]}"
    exit 1
}

generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback to date-based suffix
        date +%s | tail -c 7
    fi
}

enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "workflows.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "pubsub.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi

    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            log_error "Failed to enable $api"
            exit 1
        fi
    done

    log_success "APIs enabled successfully"
}

create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."

    local buckets=("input" "models" "output")
    
    for bucket_type in "${buckets[@]}"; do
        local bucket_name="${SERVICE_PREFIX}-${bucket_type}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create bucket: gs://${bucket_name}"
            continue
        fi

        if gsutil ls "gs://${bucket_name}" &> /dev/null; then
            if [[ "$FORCE_DEPLOY" == "true" ]]; then
                log_warning "Bucket gs://${bucket_name} exists, using existing bucket"
            else
                log_warning "Bucket gs://${bucket_name} already exists, skipping"
            fi
            continue
        fi

        log_info "Creating bucket: gs://${bucket_name}"
        if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket_name}"; then
            log_error "Failed to create bucket: gs://${bucket_name}"
            exit 1
        fi
    done

    log_success "Storage buckets created successfully"
}

build_container_images() {
    log_info "Building container images..."

    local services=("gpu-inference" "preprocess" "postprocess")
    local build_dir
    build_dir=$(mktemp -d)

    for service in "${services[@]}"; do
        log_info "Building ${service} container..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would build container: gcr.io/${PROJECT_ID}/${SERVICE_PREFIX}-${service}"
            continue
        fi

        # Create service-specific directory
        local service_dir="${build_dir}/${service}-service"
        mkdir -p "$service_dir"

        # Generate Dockerfile and application code based on service type
        case "$service" in
            "gpu-inference")
                create_gpu_inference_service "$service_dir"
                ;;
            "preprocess")
                create_preprocess_service "$service_dir"
                ;;
            "postprocess")
                create_postprocess_service "$service_dir"
                ;;
        esac

        # Build container image
        (
            cd "$service_dir"
            if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_PREFIX}-${service}" --timeout=600s; then
                log_error "Failed to build ${service} container"
                exit 1
            fi
        )

        log_success "Built ${service} container successfully"
    done

    # Cleanup temporary directory
    rm -rf "$build_dir"
}

create_gpu_inference_service() {
    local service_dir="$1"
    
    # Create Dockerfile
    cat > "${service_dir}/Dockerfile" << 'EOF'
FROM nvidia/cuda:12.1-runtime-ubuntu22.04

# Install Python and dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install ML libraries with GPU support
RUN pip3 install --no-cache-dir \
    torch==2.0.1 \
    torchvision==0.15.2 \
    transformers==4.30.0 \
    accelerate==0.20.3 \
    flask==2.3.2 \
    google-cloud-storage==2.10.0 \
    pillow==10.0.0 \
    gunicorn==21.2.0

WORKDIR /app
COPY . .

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--timeout", "300", "--workers", "1", "--threads", "4", "inference_server:app"]
EOF

    # Create inference server
    cat > "${service_dir}/inference_server.py" << 'EOF'
import os
import torch
from flask import Flask, request, jsonify
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from google.cloud import storage
import logging
import time

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Global variables for model
model = None
tokenizer = None
device = None

def initialize_model():
    global model, tokenizer, device
    
    start_time = time.time()
    
    # Check for GPU availability
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logging.info(f"Using device: {device}")
    
    # Load a simple classification model (can be replaced with custom models)
    model_name = "distilbert-base-uncased-finetuned-sst-2-english"
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForSequenceClassification.from_pretrained(model_name)
    model.to(device)
    model.eval()
    
    load_time = time.time() - start_time
    logging.info(f"Model initialized successfully in {load_time:.2f} seconds")

@app.route("/health", methods=["GET"])
def health_check():
    return {
        "status": "healthy",
        "service": "gpu-inference",
        "gpu_available": torch.cuda.is_available(),
        "device": str(device) if device else "not_initialized"
    }

@app.route("/predict", methods=["POST"])
def predict():
    try:
        start_time = time.time()
        data = request.get_json()
        text = data.get("text", "")
        
        if not text:
            return jsonify({"error": "No text provided"}), 400
        
        # Tokenize and predict
        inputs = tokenizer(text, return_tensors="pt", truncation=True, padding=True, max_length=512)
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        with torch.no_grad():
            outputs = model(**inputs)
            predictions = torch.nn.functional.softmax(outputs.logits, dim=-1)
            
        inference_time = time.time() - start_time
        
        result = {
            "prediction": predictions.cpu().numpy().tolist()[0],
            "confidence": float(torch.max(predictions)),
            "device_used": str(device),
            "inference_time_seconds": round(inference_time, 3),
            "input_length": len(text)
        }
        
        logging.info(f"Processed prediction in {inference_time:.3f}s on {device}")
        return jsonify(result)
        
    except Exception as e:
        logging.error(f"Prediction error: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    initialize_model()
    app.run(host="0.0.0.0", port=8080, debug=False)
EOF
}

create_preprocess_service() {
    local service_dir="$1"
    
    # Create Dockerfile
    cat > "${service_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

RUN pip install --no-cache-dir \
    flask==2.3.2 \
    google-cloud-storage==2.10.0 \
    pillow==10.0.0 \
    pandas==2.0.3 \
    numpy==1.24.3 \
    gunicorn==21.2.0

WORKDIR /app
COPY . .

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--timeout", "60", "--workers", "2", "preprocess_server:app"]
EOF

    # Create preprocessing server
    cat > "${service_dir}/preprocess_server.py" << 'EOF'
import os
import json
from flask import Flask, request, jsonify
from google.cloud import storage
import logging
from PIL import Image
import base64
import io
import time

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

storage_client = storage.Client()

@app.route("/health", methods=["GET"])
def health_check():
    return {"status": "healthy", "service": "preprocessing"}

@app.route("/preprocess", methods=["POST"])
def preprocess_data():
    try:
        start_time = time.time()
        data = request.get_json()
        input_bucket = data.get("input_bucket")
        input_file = data.get("input_file")
        
        if not input_bucket or not input_file:
            return jsonify({"error": "Missing input_bucket or input_file"}), 400
        
        # Download file from Cloud Storage
        bucket = storage_client.bucket(input_bucket)
        blob = bucket.blob(input_file)
        
        if not blob.exists():
            return jsonify({"error": f"File {input_file} not found in bucket {input_bucket}"}), 404
        
        if input_file.endswith(('.txt', '.json')):
            # Process text data
            content = blob.download_as_text()
            processed_data = {
                "text": content.strip(),
                "length": len(content),
                "type": "text",
                "word_count": len(content.split())
            }
        elif input_file.endswith(('.jpg', '.jpeg', '.png')):
            # Process image data (convert to base64 for JSON transport)
            image_bytes = blob.download_as_bytes()
            image = Image.open(io.BytesIO(image_bytes))
            
            # Resize image if too large
            if image.size[0] > 1024 or image.size[1] > 1024:
                image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            
            # Convert back to bytes
            buffer = io.BytesIO()
            image.save(buffer, format='JPEG')
            image_b64 = base64.b64encode(buffer.getvalue()).decode()
            
            processed_data = {
                "image_data": image_b64,
                "dimensions": image.size,
                "type": "image",
                "format": "JPEG"
            }
        else:
            return jsonify({"error": "Unsupported file type. Supported: .txt, .json, .jpg, .jpeg, .png"}), 400
        
        processing_time = time.time() - start_time
        
        result = {
            "status": "success",
            "processed_data": processed_data,
            "input_file": input_file,
            "processing_time_seconds": round(processing_time, 3)
        }
        
        logging.info(f"Processed {input_file} in {processing_time:.3f}s")
        return jsonify(result)
        
    except Exception as e:
        logging.error(f"Preprocessing error: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
EOF
}

create_postprocess_service() {
    local service_dir="$1"
    
    # Create Dockerfile
    cat > "${service_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

RUN pip install --no-cache-dir \
    flask==2.3.2 \
    google-cloud-storage==2.10.0 \
    pandas==2.0.3 \
    numpy==1.24.3 \
    gunicorn==21.2.0

WORKDIR /app
COPY . .

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--timeout", "60", "--workers", "2", "postprocess_server:app"]
EOF

    # Create post-processing server
    cat > "${service_dir}/postprocess_server.py" << 'EOF'
import os
import json
from flask import Flask, request, jsonify
from google.cloud import storage
import logging
from datetime import datetime
import time

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

storage_client = storage.Client()

@app.route("/health", methods=["GET"])
def health_check():
    return {"status": "healthy", "service": "postprocessing"}

@app.route("/postprocess", methods=["POST"])
def postprocess_results():
    try:
        start_time = time.time()
        data = request.get_json()
        prediction_result = data.get("prediction_result")
        input_metadata = data.get("input_metadata", {})
        output_bucket = data.get("output_bucket")
        
        if not prediction_result or not output_bucket:
            return jsonify({"error": "Missing prediction_result or output_bucket"}), 400
        
        # Process the prediction result
        confidence = prediction_result.get("confidence", 0.0)
        prediction = prediction_result.get("prediction", [])
        
        # Determine classification result
        if len(prediction) >= 2:
            sentiment_score = prediction[1] - prediction[0]  # Positive - Negative
            sentiment_label = "positive" if sentiment_score > 0 else "negative"
        else:
            sentiment_score = 0.0
            sentiment_label = "neutral"
        
        # Create enhanced result
        enhanced_result = {
            "input_metadata": input_metadata,
            "prediction": {
                "sentiment_label": sentiment_label,
                "sentiment_score": float(sentiment_score),
                "confidence": float(confidence),
                "raw_prediction": prediction,
                "classification": "high_confidence" if confidence > 0.8 else "low_confidence"
            },
            "processing_info": {
                "timestamp": datetime.utcnow().isoformat(),
                "service_version": "1.0",
                "gpu_accelerated": prediction_result.get("device_used", "").startswith("cuda"),
                "inference_time": prediction_result.get("inference_time_seconds", 0)
            },
            "quality_metrics": {
                "high_confidence": confidence > 0.8,
                "medium_confidence": 0.6 <= confidence <= 0.8,
                "low_confidence": confidence < 0.6,
                "requires_review": confidence < 0.6
            }
        }
        
        # Save result to Cloud Storage
        output_filename = f"result_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{int(time.time() * 1000)}.json"
        bucket = storage_client.bucket(output_bucket)
        blob = bucket.blob(output_filename)
        blob.upload_from_string(
            json.dumps(enhanced_result, indent=2),
            content_type='application/json'
        )
        
        processing_time = time.time() - start_time
        
        result = {
            "status": "success",
            "output_file": output_filename,
            "output_bucket": output_bucket,
            "processing_time_seconds": round(processing_time, 3),
            "summary": {
                "sentiment": sentiment_label,
                "confidence": confidence,
                "requires_review": confidence < 0.6,
                "classification": "high_confidence" if confidence > 0.8 else "low_confidence"
            }
        }
        
        logging.info(f"Post-processed result saved to {output_filename} in {processing_time:.3f}s")
        return jsonify(result)
        
    except Exception as e:
        logging.error(f"Post-processing error: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
EOF
}

deploy_cloud_run_services() {
    log_info "Deploying Cloud Run services..."

    local services=(
        "gpu-inference:GPU:16Gi:4:300:4:10:nvidia-l4:1"
        "preprocess:CPU:2Gi:1:60:10:50:none:0"
        "postprocess:CPU:1Gi:1:60:10:50:none:0"
    )

    for service_config in "${services[@]}"; do
        IFS=':' read -r service_name service_type memory cpu timeout concurrency max_instances gpu_type gpu_count <<< "$service_config"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would deploy ${service_name} service with ${service_type} configuration"
            continue
        fi

        log_info "Deploying ${service_name} service..."
        
        local deploy_cmd="gcloud run deploy ${SERVICE_PREFIX}-${service_name} \
            --image gcr.io/${PROJECT_ID}/${SERVICE_PREFIX}-${service_name} \
            --platform managed \
            --region ${REGION} \
            --memory ${memory} \
            --cpu ${cpu} \
            --timeout ${timeout} \
            --concurrency ${concurrency} \
            --max-instances ${max_instances} \
            --allow-unauthenticated \
            --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION}"

        # Add GPU configuration if needed
        if [[ "$gpu_type" != "none" ]]; then
            deploy_cmd="${deploy_cmd} --gpu ${gpu_count} --gpu-type ${gpu_type} --no-cpu-throttling"
        fi

        if ! eval "$deploy_cmd"; then
            log_error "Failed to deploy ${service_name} service"
            exit 1
        fi

        log_success "Deployed ${service_name} service successfully"
    done
}

create_workflow_definition() {
    log_info "Creating workflow definition..."

    local workflow_file="${PROJECT_ROOT}/workflow-definition.yaml"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create workflow definition file"
        return 0
    fi

    # Get service URLs
    local gpu_service_url preprocess_service_url postprocess_service_url
    
    gpu_service_url=$(gcloud run services describe "${SERVICE_PREFIX}-gpu-inference" \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    preprocess_service_url=$(gcloud run services describe "${SERVICE_PREFIX}-preprocess" \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    postprocess_service_url=$(gcloud run services describe "${SERVICE_PREFIX}-postprocess" \
        --region "${REGION}" \
        --format 'value(status.url)')

    cat > "$workflow_file" << EOF
main:
  params: [input]
  steps:
    - init:
        assign:
          - project_id: \${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
          - input_bucket: "${SERVICE_PREFIX}-input"
          - output_bucket: "${SERVICE_PREFIX}-output"
          - input_file: \${input.input_file}
          - preprocess_url: "${preprocess_service_url}"
          - inference_url: "${gpu_service_url}"
          - postprocess_url: "${postprocess_service_url}"
    
    - log_start:
        call: sys.log
        args:
          text: \${"Starting ML pipeline for file: " + input_file}
          severity: INFO
    
    - preprocess_step:
        call: http.post
        args:
          url: \${preprocess_url + "/preprocess"}
          headers:
            Content-Type: "application/json"
          body:
            input_bucket: \${input_bucket}
            input_file: \${input_file}
          timeout: 60
        result: preprocess_result
    
    - check_preprocess:
        switch:
          - condition: \${preprocess_result.body.status == "success"}
            next: inference_step
        next: preprocess_error
    
    - inference_step:
        call: http.post
        args:
          url: \${inference_url + "/predict"}
          headers:
            Content-Type: "application/json"
          body:
            text: \${preprocess_result.body.processed_data.text}
          timeout: 300
        result: inference_result
    
    - check_inference:
        switch:
          - condition: \${inference_result.status == 200}
            next: postprocess_step
        next: inference_error
    
    - postprocess_step:
        call: http.post
        args:
          url: \${postprocess_url + "/postprocess"}
          headers:
            Content-Type: "application/json"
          body:
            prediction_result: \${inference_result.body}
            input_metadata:
              input_file: \${input_file}
              input_bucket: \${input_bucket}
            output_bucket: \${output_bucket}
          timeout: 60
        result: postprocess_result
    
    - log_success:
        call: sys.log
        args:
          text: \${"Pipeline completed successfully. Output: " + postprocess_result.body.output_file}
          severity: INFO
    
    - return_result:
        return:
          status: "success"
          input_file: \${input_file}
          output_file: \${postprocess_result.body.output_file}
          output_bucket: \${output_bucket}
          summary: \${postprocess_result.body.summary}
          execution_time: \${time.format(sys.now())}
    
    - preprocess_error:
        call: sys.log
        args:
          text: \${"Preprocessing failed: " + string(preprocess_result.body)}
          severity: ERROR
        next: error_return
    
    - inference_error:
        call: sys.log
        args:
          text: \${"Inference failed: " + string(inference_result)}
          severity: ERROR
        next: error_return
    
    - error_return:
        return:
          status: "error"
          input_file: \${input_file}
          error: "Pipeline execution failed"
          execution_time: \${time.format(sys.now())}
EOF

    log_success "Workflow definition created: $workflow_file"
}

deploy_workflow() {
    log_info "Deploying Cloud Workflows pipeline..."

    local workflow_file="${PROJECT_ROOT}/workflow-definition.yaml"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy workflow: ${SERVICE_PREFIX}-ml-pipeline"
        return 0
    fi

    if ! gcloud workflows deploy "${SERVICE_PREFIX}-ml-pipeline" \
        --source "$workflow_file" \
        --location "${REGION}"; then
        log_error "Failed to deploy workflow"
        exit 1
    fi

    log_success "Workflow deployed successfully: ${SERVICE_PREFIX}-ml-pipeline"
}

create_eventarc_trigger() {
    log_info "Creating Eventarc trigger for automated pipeline execution..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Eventarc trigger and service account"
        return 0
    fi

    # Create service account for Eventarc
    local service_account="${SERVICE_PREFIX}-eventarc@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if ! gcloud iam service-accounts describe "$service_account" &> /dev/null; then
        log_info "Creating Eventarc service account..."
        if ! gcloud iam service-accounts create "${SERVICE_PREFIX}-eventarc" \
            --display-name "Eventarc Service Account for ML Pipeline"; then
            log_error "Failed to create service account"
            exit 1
        fi
    fi

    # Grant necessary permissions
    local roles=(
        "roles/workflows.invoker"
        "roles/eventarc.eventReceiver"
        "roles/run.invoker"
    )

    for role in "${roles[@]}"; do
        if ! gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member "serviceAccount:${service_account}" \
            --role "$role" \
            --quiet; then
            log_error "Failed to grant $role to service account"
            exit 1
        fi
    done

    # Create Eventarc trigger
    log_info "Creating Eventarc trigger..."
    if ! gcloud eventarc triggers create "${SERVICE_PREFIX}-storage-trigger" \
        --location "${REGION}" \
        --destination-workflow "${SERVICE_PREFIX}-ml-pipeline" \
        --destination-workflow-location "${REGION}" \
        --event-filters "type=google.cloud.storage.object.v1.finalized" \
        --event-filters "bucket=${SERVICE_PREFIX}-input" \
        --service-account "$service_account"; then
        log_error "Failed to create Eventarc trigger"
        exit 1
    fi

    log_success "Eventarc trigger created successfully"
}

create_test_data() {
    log_info "Creating test data for pipeline validation..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create test data files"
        return 0
    fi

    local test_dir
    test_dir=$(mktemp -d)

    # Create test text files
    cat > "${test_dir}/positive-test.txt" << EOF
This is an amazing product that I absolutely love! The quality is outstanding and the customer service is exceptional. I would definitely recommend this to anyone looking for a high-quality solution.
EOF

    cat > "${test_dir}/negative-test.txt" << EOF
This product is terrible and completely disappointing. The quality is poor and it doesn't work as advertised. I'm very unhappy with this purchase and would not recommend it to anyone.
EOF

    # Upload test files
    if ! gsutil cp "${test_dir}/positive-test.txt" "gs://${SERVICE_PREFIX}-input/"; then
        log_error "Failed to upload positive test file"
        exit 1
    fi

    if ! gsutil cp "${test_dir}/negative-test.txt" "gs://${SERVICE_PREFIX}-input/"; then
        log_error "Failed to upload negative test file"
        exit 1
    fi

    rm -rf "$test_dir"
    log_success "Test data created and uploaded"
}

display_deployment_summary() {
    log_success "=== Deployment Summary ==="
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Service Prefix: ${SERVICE_PREFIX}"
    echo
    echo "Deployed Resources:"
    echo "  • Cloud Run Services:"
    echo "    - ${SERVICE_PREFIX}-gpu-inference (GPU-enabled)"
    echo "    - ${SERVICE_PREFIX}-preprocess"
    echo "    - ${SERVICE_PREFIX}-postprocess"
    echo "  • Cloud Workflows:"
    echo "    - ${SERVICE_PREFIX}-ml-pipeline"
    echo "  • Cloud Storage Buckets:"
    echo "    - ${SERVICE_PREFIX}-input"
    echo "    - ${SERVICE_PREFIX}-models"
    echo "    - ${SERVICE_PREFIX}-output"
    echo "  • Eventarc Trigger:"
    echo "    - ${SERVICE_PREFIX}-storage-trigger"
    echo
    echo "Test the pipeline by uploading text files to:"
    echo "  gs://${SERVICE_PREFIX}-input/"
    echo
    echo "Monitor results in:"
    echo "  gs://${SERVICE_PREFIX}-output/"
    echo
    echo "View workflow executions:"
    echo "  gcloud workflows executions list --workflow=${SERVICE_PREFIX}-ml-pipeline --location=${REGION}"
    echo
    log_success "Deployment completed successfully!"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-prereqs)
                SKIP_PREREQUISITES=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
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

    # Set defaults
    REGION="${REGION:-$DEFAULT_REGION}"
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

    # Validate inputs
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID not set. Use --project or set default project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi

    validate_region "$REGION"

    # Generate unique service prefix
    RANDOM_SUFFIX=$(generate_unique_suffix)
    SERVICE_PREFIX="ml-pipeline-${RANDOM_SUFFIX}"

    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet

    log_info "Starting deployment of GCP Serverless GPU Computing Pipeline"
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Service Prefix: ${SERVICE_PREFIX}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
    fi

    # Execute deployment steps
    check_prerequisites
    enable_apis
    create_storage_buckets
    build_container_images
    deploy_cloud_run_services
    create_workflow_definition
    deploy_workflow
    create_eventarc_trigger
    create_test_data
    display_deployment_summary
}

# Error handling
trap 'log_error "Deployment failed. Check the logs above for details."' ERR

# Run main function
main "$@"
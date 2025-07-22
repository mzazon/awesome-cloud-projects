#!/bin/bash

# Multi-Agent AI Systems Deployment Script for GCP
# Deploys GPU-accelerated multi-agent AI systems using Cloud Run and Vertex AI Agent Engine
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID    Specify GCP project ID (optional)
#   --region REGION           Specify GCP region (optional)
#   --dry-run                 Show what would be deployed without executing
#   --skip-build             Skip container image builds
#   --help                   Show this help message

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/multi-agent-deploy-$(date +%Y%m%d-%H%M%S).log"

# Flags
DRY_RUN=false
SKIP_BUILD=false
PROJECT_ID=""
REGION=""

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check log file: $LOG_FILE"
    log_error "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Multi-Agent AI Systems Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    --project-id PROJECT_ID    Specify GCP project ID (optional)
    --region REGION           Specify GCP region (default: $DEFAULT_REGION)
    --dry-run                 Show what would be deployed without executing
    --skip-build             Skip container image builds
    --help                   Show this help message

EXAMPLES:
    ./deploy.sh
    ./deploy.sh --project-id my-project --region us-west1
    ./deploy.sh --dry-run
    ./deploy.sh --skip-build

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Docker installed (unless using --skip-build)
    - Billing enabled on GCP project
    - Required APIs enabled (script will enable them)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set defaults
if [[ -z "$REGION" ]]; then
    REGION="$DEFAULT_REGION"
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be created"
    echo() { printf "DRY RUN: %s\n" "$*"; }
    gcloud() { printf "DRY RUN: gcloud %s\n" "$*"; }
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it first."
        log_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if docker is installed (unless skipping build)
    if [[ "$SKIP_BUILD" == "false" ]] && ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it or use --skip-build flag."
        log_error "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "Not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Get or validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID specified and no default project set."
            log_error "Use: ./deploy.sh --project-id YOUR_PROJECT_ID"
            exit 1
        fi
        log "Using current project: $PROJECT_ID"
    else
        # Validate project exists
        if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
            log_error "Project $PROJECT_ID does not exist or you don't have access."
            exit 1
        fi
    fi
    
    # Check billing
    if ! gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        log_error "Billing is not enabled for project $PROJECT_ID"
        log_error "Enable billing at: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export PROJECT_ID="$PROJECT_ID"
    export REGION="$REGION"
    export ZONE="${REGION}-a"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    export CLUSTER_NAME="agent-cluster-${RANDOM_SUFFIX}"
    export MASTER_AGENT_NAME="master-agent-${RANDOM_SUFFIX}"
    export VISION_AGENT_NAME="vision-agent-${RANDOM_SUFFIX}"
    export LANGUAGE_AGENT_NAME="language-agent-${RANDOM_SUFFIX}"
    export REASONING_AGENT_NAME="reasoning-agent-${RANDOM_SUFFIX}"
    export TOOL_AGENT_NAME="tool-agent-${RANDOM_SUFFIX}"
    export REDIS_INSTANCE="agent-cache-${RANDOM_SUFFIX}"
    export TOPIC_NAME="agent-tasks-${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Environment configured for project: $PROJECT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "aiplatform.googleapis.com"
        "redis.googleapis.com"
        "monitoring.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        gcloud services enable "$api"
    done
    
    log_success "All required APIs enabled"
}

# Create Artifact Registry repository
create_artifact_registry() {
    log "Creating Artifact Registry repository..."
    
    if gcloud artifacts repositories describe agent-images --location="$REGION" &>/dev/null; then
        log_warning "Artifact Registry repository 'agent-images' already exists"
    else
        gcloud artifacts repositories create agent-images \
            --repository-format=docker \
            --location="$REGION" \
            --description="Multi-agent AI system container images"
        log_success "Artifact Registry repository created"
    fi
}

# Create Redis instance
create_redis_instance() {
    log "Creating Cloud Memorystore Redis instance..."
    
    if gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" &>/dev/null; then
        log_warning "Redis instance '$REDIS_INSTANCE' already exists"
    else
        gcloud redis instances create "$REDIS_INSTANCE" \
            --size=1 \
            --region="$REGION" \
            --redis-version=redis_7_0 \
            --tier=basic \
            --enable-auth
        
        log "Waiting for Redis instance to be ready..."
        local timeout=300  # 5 minutes
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            local state=$(gcloud redis instances describe "$REDIS_INSTANCE" \
                --region="$REGION" \
                --format="value(state)" 2>/dev/null || echo "")
            
            if [[ "$state" == "READY" ]]; then
                break
            fi
            
            log "Redis instance state: $state (waiting...)"
            sleep 10
            elapsed=$((elapsed + 10))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for Redis instance to be ready"
            exit 1
        fi
        
        log_success "Redis instance created and ready"
    fi
    
    # Get Redis connection details
    export REDIS_HOST=$(gcloud redis instances describe "$REDIS_INSTANCE" \
        --region="$REGION" \
        --format="value(host)")
    export REDIS_PORT=$(gcloud redis instances describe "$REDIS_INSTANCE" \
        --region="$REGION" \
        --format="value(port)")
    
    log "Redis connection: $REDIS_HOST:$REDIS_PORT"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topic and subscription..."
    
    # Create topic
    if gcloud pubsub topics describe "$TOPIC_NAME" &>/dev/null; then
        log_warning "Pub/Sub topic '$TOPIC_NAME' already exists"
    else
        gcloud pubsub topics create "$TOPIC_NAME"
        log_success "Pub/Sub topic created: $TOPIC_NAME"
    fi
    
    # Create subscription
    local subscription_name="${TOPIC_NAME}-subscription"
    if gcloud pubsub subscriptions describe "$subscription_name" &>/dev/null; then
        log_warning "Pub/Sub subscription '$subscription_name' already exists"
    else
        gcloud pubsub subscriptions create "$subscription_name" \
            --topic="$TOPIC_NAME" \
            --ack-deadline=600
        log_success "Pub/Sub subscription created: $subscription_name"
    fi
}

# Build and deploy agent containers
build_and_deploy_agents() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_warning "Skipping container builds as requested"
        return
    fi
    
    log "Building and deploying agent containers..."
    
    local temp_dir="/tmp/multi-agent-build-$$"
    mkdir -p "$temp_dir"
    
    # Build Vision Agent
    build_vision_agent "$temp_dir"
    
    # Build Language Agent
    build_language_agent "$temp_dir"
    
    # Build Reasoning Agent
    build_reasoning_agent "$temp_dir"
    
    # Build Tool Agent
    build_tool_agent "$temp_dir"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "All agents built and deployed"
}

# Build Vision Agent
build_vision_agent() {
    local build_dir="$1/vision-agent"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    log "Building Vision Agent with GPU support..."
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM nvidia/cuda:12.2-runtime-ubuntu22.04

# Install Python and dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8080

# Run the application
CMD ["python3", "main.py"]
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
torch==2.1.0
torchvision==0.16.0
transformers==4.36.0
Pillow==10.1.0
fastapi==0.104.1
uvicorn==0.24.0
redis==5.0.1
google-cloud-pubsub==2.18.4
google-cloud-monitoring==2.17.0
numpy==1.24.4
opencv-python==4.8.1.78
EOF

    # Create application
    cat > main.py << 'EOF'
import torch
import torchvision.transforms as transforms
from PIL import Image
import redis
import json
import os
from fastapi import FastAPI, UploadFile, File
import uvicorn
from google.cloud import pubsub_v1
from google.cloud import monitoring_v1
import time

app = FastAPI()
redis_client = redis.Redis(host=os.getenv('REDIS_HOST'), 
                          port=int(os.getenv('REDIS_PORT')), 
                          decode_responses=True)

@app.post("/analyze")
async def analyze_image(file: UploadFile = File(...)):
    start_time = time.time()
    
    # Process image with GPU acceleration
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    
    # Simulate vision processing (replace with actual model)
    result = {
        "objects_detected": ["person", "car", "building"],
        "confidence_scores": [0.95, 0.87, 0.92],
        "processing_time": time.time() - start_time,
        "gpu_used": torch.cuda.is_available()
    }
    
    # Store result in Redis for other agents
    redis_client.setex(f"vision_result_{file.filename}", 
                      3600, json.dumps(result))
    
    return result

@app.get("/health")
async def health_check():
    return {"status": "healthy", "gpu_available": torch.cuda.is_available()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    # Build and push image
    local image_tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-images/vision-agent:latest"
    gcloud builds submit --tag "$image_tag"
    
    # Deploy to Cloud Run with GPU
    gcloud run deploy "$VISION_AGENT_NAME" \
        --image="$image_tag" \
        --platform=managed \
        --region="$REGION" \
        --gpu=1 \
        --gpu-type=nvidia-l4 \
        --memory=16Gi \
        --cpu=4 \
        --min-instances=0 \
        --max-instances=10 \
        --set-env-vars="REDIS_HOST=${REDIS_HOST},REDIS_PORT=${REDIS_PORT}" \
        --allow-unauthenticated
    
    log_success "Vision Agent deployed"
}

# Build Language Agent
build_language_agent() {
    local build_dir="$1/language-agent"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    log "Building Language Agent with GPU support..."
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM nvidia/cuda:12.2-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip3 install -r requirements.txt

COPY . .
EXPOSE 8080

CMD ["python3", "main.py"]
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
torch==2.1.0
transformers==4.36.0
fastapi==0.104.1
uvicorn==0.24.0
redis==5.0.1
google-cloud-pubsub==2.18.4
google-cloud-aiplatform==1.38.0
numpy==1.24.4
sentencepiece==0.1.99
accelerate==0.24.1
EOF

    # Create application
    cat > main.py << 'EOF'
import torch
from transformers import pipeline
import redis
import json
import os
from fastapi import FastAPI, Request
import uvicorn
from google.cloud import pubsub_v1
import time

app = FastAPI()
redis_client = redis.Redis(host=os.getenv('REDIS_HOST'), 
                          port=int(os.getenv('REDIS_PORT')), 
                          decode_responses=True)

# Initialize language model pipeline
device = 0 if torch.cuda.is_available() else -1
nlp_pipeline = pipeline("text-generation", 
                       model="microsoft/DialoGPT-medium", 
                       device=device)

@app.post("/process")
async def process_text(request: Request):
    data = await request.json()
    text = data.get("text", "")
    start_time = time.time()
    
    # Process text with GPU acceleration
    result = nlp_pipeline(text, max_length=150, 
                         num_return_sequences=1)
    
    response = {
        "processed_text": result[0]["generated_text"],
        "original_text": text,
        "processing_time": time.time() - start_time,
        "gpu_used": torch.cuda.is_available()
    }
    
    # Store result in Redis
    task_id = f"lang_result_{int(time.time())}"
    redis_client.setex(task_id, 3600, json.dumps(response))
    
    return response

@app.get("/health")
async def health_check():
    return {"status": "healthy", "gpu_available": torch.cuda.is_available()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    # Build and deploy
    local image_tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-images/language-agent:latest"
    gcloud builds submit --tag "$image_tag"
    
    gcloud run deploy "$LANGUAGE_AGENT_NAME" \
        --image="$image_tag" \
        --platform=managed \
        --region="$REGION" \
        --gpu=1 \
        --gpu-type=nvidia-l4 \
        --memory=16Gi \
        --cpu=4 \
        --min-instances=0 \
        --max-instances=10 \
        --set-env-vars="REDIS_HOST=${REDIS_HOST},REDIS_PORT=${REDIS_PORT}" \
        --allow-unauthenticated
    
    log_success "Language Agent deployed"
}

# Build Reasoning Agent
build_reasoning_agent() {
    local build_dir="$1/reasoning-agent"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    log "Building Reasoning Agent with GPU support..."
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM nvidia/cuda:12.2-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip3 install -r requirements.txt

COPY . .
EXPOSE 8080

CMD ["python3", "main.py"]
EOF

    cat > requirements.txt << 'EOF'
torch==2.1.0
transformers==4.36.0
fastapi==0.104.1
uvicorn==0.24.0
redis==5.0.1
google-cloud-pubsub==2.18.4
numpy==1.24.4
scipy==1.11.4
networkx==3.2.1
pandas==2.1.4
EOF

    cat > main.py << 'EOF'
import torch
import numpy as np
import redis
import json
import os
from fastapi import FastAPI, Request
import uvicorn
import time
import networkx as nx

app = FastAPI()
redis_client = redis.Redis(host=os.getenv('REDIS_HOST'), 
                          port=int(os.getenv('REDIS_PORT')), 
                          decode_responses=True)

@app.post("/reason")
async def complex_reasoning(request: Request):
    data = await request.json()
    problem = data.get("problem", "")
    context = data.get("context", {})
    start_time = time.time()
    
    # GPU-accelerated reasoning simulation
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    
    # Simulate complex reasoning with tensor operations
    reasoning_tensor = torch.randn(1000, 1000, device=device)
    result_tensor = torch.matmul(reasoning_tensor, reasoning_tensor.T)
    confidence = torch.mean(result_tensor).item()
    
    # Create reasoning graph
    G = nx.Graph()
    G.add_edges_from([(1, 2), (2, 3), (3, 4), (4, 1)])
    
    reasoning_result = {
        "solution": f"Analyzed problem: {problem}",
        "confidence": abs(confidence) % 1.0,
        "reasoning_steps": ["Step 1: Problem analysis", 
                           "Step 2: Context evaluation", 
                           "Step 3: Solution synthesis"],
        "processing_time": time.time() - start_time,
        "gpu_used": torch.cuda.is_available(),
        "graph_complexity": len(G.edges())
    }
    
    # Store in Redis for other agents
    task_id = f"reasoning_result_{int(time.time())}"
    redis_client.setex(task_id, 3600, json.dumps(reasoning_result))
    
    return reasoning_result

@app.get("/health")
async def health_check():
    return {"status": "healthy", "gpu_available": torch.cuda.is_available()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    # Build and deploy
    local image_tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-images/reasoning-agent:latest"
    gcloud builds submit --tag "$image_tag"
    
    gcloud run deploy "$REASONING_AGENT_NAME" \
        --image="$image_tag" \
        --platform=managed \
        --region="$REGION" \
        --gpu=1 \
        --gpu-type=nvidia-l4 \
        --memory=16Gi \
        --cpu=4 \
        --min-instances=0 \
        --max-instances=10 \
        --set-env-vars="REDIS_HOST=${REDIS_HOST},REDIS_PORT=${REDIS_PORT}" \
        --allow-unauthenticated
    
    log_success "Reasoning Agent deployed"
}

# Build Tool Agent
build_tool_agent() {
    local build_dir="$1/tool-agent"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    log "Building Tool Agent..."
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
EXPOSE 8080

CMD ["python", "main.py"]
EOF

    cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
redis==5.0.1
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
requests==2.31.0
pandas==2.1.4
EOF

    cat > main.py << 'EOF'
import redis
import json
import os
from fastapi import FastAPI, Request
import uvicorn
import requests
import pandas as pd
from google.cloud import storage
import time

app = FastAPI()
redis_client = redis.Redis(host=os.getenv('REDIS_HOST'), 
                          port=int(os.getenv('REDIS_PORT')), 
                          decode_responses=True)

@app.post("/fetch_data")
async def fetch_external_data(request: Request):
    data = await request.json()
    source = data.get("source", "")
    parameters = data.get("parameters", {})
    start_time = time.time()
    
    # Simulate external data fetching
    result = {
        "source": source,
        "data_retrieved": True,
        "record_count": 1000,
        "parameters_used": parameters,
        "processing_time": time.time() - start_time
    }
    
    # Store result in Redis
    task_id = f"tool_result_{int(time.time())}"
    redis_client.setex(task_id, 3600, json.dumps(result))
    
    return result

@app.post("/process_files")
async def process_files(request: Request):
    data = await request.json()
    file_paths = data.get("files", [])
    
    # Process files without GPU requirements
    processed_files = []
    for file_path in file_paths:
        processed_files.append({
            "file": file_path,
            "status": "processed",
            "size": "1.2MB"
        })
    
    result = {
        "processed_files": processed_files,
        "total_files": len(file_paths),
        "processing_time": time.time()
    }
    
    return result

@app.get("/health")
async def health_check():
    return {"status": "healthy", "type": "tool_agent"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    # Build and deploy
    local image_tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-images/tool-agent:latest"
    gcloud builds submit --tag "$image_tag"
    
    gcloud run deploy "$TOOL_AGENT_NAME" \
        --image="$image_tag" \
        --platform=managed \
        --region="$REGION" \
        --memory=2Gi \
        --cpu=1 \
        --min-instances=0 \
        --max-instances=5 \
        --set-env-vars="REDIS_HOST=${REDIS_HOST},REDIS_PORT=${REDIS_PORT}" \
        --allow-unauthenticated
    
    log_success "Tool Agent deployed"
}

# Configure monitoring
configure_monitoring() {
    log "Configuring Cloud Monitoring and alerting..."
    
    # Create log-based metrics for agent performance
    if ! gcloud logging metrics describe agent_response_time &>/dev/null; then
        gcloud logging metrics create agent_response_time \
            --description="Track agent response times" \
            --log-filter='resource.type="cloud_run_revision" jsonPayload.processing_time>0'
        log_success "Created log-based metric: agent_response_time"
    else
        log_warning "Log-based metric 'agent_response_time' already exists"
    fi
    
    log_success "Monitoring configured"
}

# Print deployment summary
print_summary() {
    log_success "Multi-Agent AI System Deployment Completed!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Resource Suffix: ${RANDOM_SUFFIX}"
    echo
    echo "=== DEPLOYED RESOURCES ==="
    echo "Redis Instance: $REDIS_INSTANCE ($REDIS_HOST:$REDIS_PORT)"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "Cloud Run Services:"
    echo "  - Vision Agent: $VISION_AGENT_NAME"
    echo "  - Language Agent: $LANGUAGE_AGENT_NAME"
    echo "  - Reasoning Agent: $REASONING_AGENT_NAME"
    echo "  - Tool Agent: $TOOL_AGENT_NAME"
    echo
    echo "=== SERVICE URLS ==="
    gcloud run services list --platform=managed --region="$REGION" --format="table(METADATA.NAME,STATUS.URL)" --filter="metadata.name:agent"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Test individual agents using their health endpoints"
    echo "2. Configure Vertex AI Agent Engine for orchestration"
    echo "3. Monitor GPU utilization in Cloud Console"
    echo "4. Review costs in Cloud Billing"
    echo
    echo "=== CLEANUP ==="
    echo "To destroy all resources: ./destroy.sh"
    echo
    echo "Deployment log saved to: $LOG_FILE"
}

# Main deployment flow
main() {
    log "Starting Multi-Agent AI System deployment..."
    log "Log file: $LOG_FILE"
    
    check_prerequisites
    setup_environment
    enable_apis
    create_artifact_registry
    create_redis_instance
    create_pubsub_resources
    build_and_deploy_agents
    configure_monitoring
    print_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"
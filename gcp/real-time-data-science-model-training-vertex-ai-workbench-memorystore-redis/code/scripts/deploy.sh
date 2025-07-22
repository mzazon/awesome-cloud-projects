#!/bin/bash

# Real-Time Data Science Model Training with Vertex AI Workbench and Memorystore Redis
# Deployment Script for GCP
# This script deploys the complete ML training infrastructure with Redis caching

set -euo pipefail

# Color codes for output
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

# Configuration
PROJECT_ID="${PROJECT_ID:-ml-training-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Resource names
REDIS_INSTANCE_NAME="ml-feature-cache-${RANDOM_SUFFIX}"
WORKBENCH_NAME="ml-workbench-${RANDOM_SUFFIX}"
BUCKET_NAME="ml-training-bucket-${RANDOM_SUFFIX}"
JOB_NAME="ml-training-job-${RANDOM_SUFFIX}"

# Cleanup function for error handling
cleanup_on_error() {
    warning "Deployment failed. Cleaning up partially created resources..."
    
    # Delete batch job if it exists
    if gcloud batch jobs describe "${JOB_NAME}" --location="${REGION}" --quiet 2>/dev/null; then
        log "Deleting batch job: ${JOB_NAME}"
        gcloud batch jobs delete "${JOB_NAME}" --location="${REGION}" --quiet || true
    fi
    
    # Delete workbench instance if it exists
    if gcloud workbench instances describe "${WORKBENCH_NAME}" --location="${ZONE}" --quiet 2>/dev/null; then
        log "Deleting workbench instance: ${WORKBENCH_NAME}"
        gcloud workbench instances delete "${WORKBENCH_NAME}" --location="${ZONE}" --quiet || true
    fi
    
    # Delete Redis instance if it exists
    if gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
        log "Deleting Redis instance: ${REDIS_INSTANCE_NAME}"
        gcloud redis instances delete "${REDIS_INSTANCE_NAME}" --region="${REGION}" --quiet || true
    fi
    
    # Delete storage bucket if it exists
    if gsutil ls -b "gs://${BUCKET_NAME}" 2>/dev/null; then
        log "Deleting storage bucket: ${BUCKET_NAME}"
        gsutil -m rm -r "gs://${BUCKET_NAME}" || true
    fi
    
    # Delete firewall rule if it exists
    if gcloud compute firewall-rules describe allow-redis-access --quiet 2>/dev/null; then
        log "Deleting firewall rule: allow-redis-access"
        gcloud compute firewall-rules delete allow-redis-access --quiet || true
    fi
    
    error "Deployment failed and cleanup completed"
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo "============================================"
echo "Real-Time ML Training Infrastructure Deploy"
echo "============================================"
echo ""

# Prerequisites check
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install it first."
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    error "gsutil is not installed. Please install it first."
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
fi

# Check if openssl is available
if ! command -v openssl &> /dev/null; then
    error "openssl is not installed. Please install it first."
fi

success "Prerequisites check passed"

# Display configuration
log "Deployment Configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Random Suffix: ${RANDOM_SUFFIX}"
echo "  Redis Instance: ${REDIS_INSTANCE_NAME}"
echo "  Workbench Instance: ${WORKBENCH_NAME}"
echo "  Storage Bucket: ${BUCKET_NAME}"
echo ""

# Confirmation prompt
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Set default project and region
log "Configuring gcloud defaults..."
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"

# Enable required APIs
log "Enabling required Google Cloud APIs..."
gcloud services enable aiplatform.googleapis.com \
    redis.googleapis.com \
    batch.googleapis.com \
    monitoring.googleapis.com \
    storage.googleapis.com \
    compute.googleapis.com \
    workbench.googleapis.com \
    notebooks.googleapis.com

success "APIs enabled successfully"

# Create Cloud Storage bucket
log "Creating Cloud Storage bucket: ${BUCKET_NAME}"
gsutil mb -p "${PROJECT_ID}" \
    -c STANDARD \
    -l "${REGION}" \
    "gs://${BUCKET_NAME}"

# Enable versioning
gsutil versioning set on "gs://${BUCKET_NAME}"

success "Cloud Storage bucket created with versioning enabled"

# Create Memorystore Redis instance
log "Creating Memorystore Redis instance: ${REDIS_INSTANCE_NAME}"
gcloud redis instances create "${REDIS_INSTANCE_NAME}" \
    --size=5 \
    --region="${REGION}" \
    --redis-version=redis_7_0 \
    --tier=standard \
    --enable-auth \
    --display-name="ML Feature Cache" \
    --labels=environment=training,use-case=ml-caching

# Wait for Redis instance to be ready
log "Waiting for Redis instance to be ready..."
while [[ $(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --format="value(state)") != "READY" ]]; do
    log "Redis instance state: $(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --format="value(state)")"
    sleep 30
done

success "Redis instance created and ready"

# Get Redis connection details
REDIS_HOST=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
    --region="${REGION}" \
    --format="value(host)")
REDIS_PORT=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
    --region="${REGION}" \
    --format="value(port)")

log "Redis connection details: ${REDIS_HOST}:${REDIS_PORT}"

# Create firewall rule for Redis access
log "Creating firewall rule for Redis access..."
gcloud compute firewall-rules create allow-redis-access \
    --allow "tcp:${REDIS_PORT}" \
    --source-ranges=10.0.0.0/8 \
    --target-tags=redis-client \
    --description="Allow Redis access from Workbench instances"

success "Firewall rule created for Redis access"

# Create Vertex AI Workbench instance
log "Creating Vertex AI Workbench instance: ${WORKBENCH_NAME}"
gcloud workbench instances create "${WORKBENCH_NAME}" \
    --location="${ZONE}" \
    --machine-type=n1-standard-4 \
    --accelerator-type=NVIDIA_TESLA_T4 \
    --accelerator-core-count=1 \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-ssd \
    --data-disk-size=200GB \
    --data-disk-type=pd-ssd \
    --metadata="enable-oslogin=true" \
    --labels=environment=training,team=data-science \
    --tags=redis-client

# Wait for Workbench instance to be ready
log "Waiting for Workbench instance to be ready..."
sleep 120

# Check instance status
while [[ $(gcloud workbench instances describe "${WORKBENCH_NAME}" --location="${ZONE}" --format="value(state)") != "ACTIVE" ]]; do
    log "Workbench instance state: $(gcloud workbench instances describe "${WORKBENCH_NAME}" --location="${ZONE}" --format="value(state)")"
    sleep 30
done

success "Vertex AI Workbench instance created with GPU acceleration"

# Create sample training dataset
log "Creating sample training dataset..."
cat > generate_dataset.py << 'EOF'
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification
import os

# Generate synthetic dataset for demonstration
X, y = make_classification(
    n_samples=10000,
    n_features=20,
    n_informative=15,
    n_redundant=5,
    n_classes=2,
    random_state=42
)

# Create feature names
feature_names = [f'feature_{i}' for i in range(20)]

# Create DataFrame
df = pd.DataFrame(X, columns=feature_names)
df['target'] = y

# Save dataset
df.to_csv('training_dataset.csv', index=False)
print(f"Dataset created with {len(df)} samples and {len(feature_names)} features")
EOF

# Generate the dataset
python3 generate_dataset.py

# Upload dataset to Cloud Storage
gsutil cp training_dataset.csv "gs://${BUCKET_NAME}/datasets/"

success "Training dataset created and uploaded to Cloud Storage"

# Create training script
log "Creating training script..."
cat > training_script.py << 'EOF'
import os
import redis
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import pickle
import json
from google.cloud import storage
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def connect_to_redis():
    """Connect to Redis cache"""
    redis_host = os.environ.get('REDIS_HOST')
    redis_port = int(os.environ.get('REDIS_PORT', 6379))
    
    r = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    logger.info(f"Connected to Redis at {redis_host}:{redis_port}")
    return r

def cache_features(r, X_train, X_test, y_train, y_test):
    """Cache preprocessed features in Redis"""
    logger.info("Caching features in Redis...")
    
    # Cache training features
    r.set('X_train', pickle.dumps(X_train))
    r.set('y_train', pickle.dumps(y_train))
    r.set('X_test', pickle.dumps(X_test))
    r.set('y_test', pickle.dumps(y_test))
    
    # Set expiration (24 hours)
    r.expire('X_train', 86400)
    r.expire('y_train', 86400)
    r.expire('X_test', 86400)
    r.expire('y_test', 86400)
    
    logger.info("Features cached successfully")

def train_model():
    """Main training function"""
    logger.info("Starting model training...")
    
    # Connect to Redis
    r = connect_to_redis()
    
    # Download dataset from Cloud Storage
    bucket_name = os.environ.get('BUCKET_NAME')
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob('datasets/training_dataset.csv')
    blob.download_to_filename('training_dataset.csv')
    
    # Load and prepare data
    df = pd.read_csv('training_dataset.csv')
    X = df.drop('target', axis=1)
    y = df['target']
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Cache features in Redis
    cache_features(r, X_train, X_test, y_train, y_test)
    
    # Train model
    logger.info("Training Random Forest model...")
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    
    # Make predictions
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    logger.info(f"Model training completed. Accuracy: {accuracy:.4f}")
    
    # Save model
    with open('trained_model.pkl', 'wb') as f:
        pickle.dump(model, f)
    
    # Upload model to Cloud Storage
    blob = bucket.blob('models/trained_model.pkl')
    blob.upload_from_filename('trained_model.pkl')
    
    # Cache model metrics in Redis
    metrics = {
        'accuracy': accuracy,
        'model_path': f'gs://{bucket_name}/models/trained_model.pkl'
    }
    r.set('model_metrics', json.dumps(metrics))
    
    logger.info("Model saved and metrics cached")

if __name__ == "__main__":
    train_model()
EOF

# Upload training script to Cloud Storage
gsutil cp training_script.py "gs://${BUCKET_NAME}/scripts/"

success "Training script created and uploaded"

# Create Cloud Batch job configuration
log "Creating Cloud Batch job configuration..."
cat > batch_job.json << EOF
{
  "taskGroups": [{
    "taskSpec": {
      "runnables": [{
        "container": {
          "imageUri": "gcr.io/deeplearning-platform-release/tf2-cpu.2-11:latest",
          "commands": [
            "bash",
            "-c",
            "pip install redis google-cloud-storage scikit-learn pandas numpy && gsutil cp gs://${BUCKET_NAME}/scripts/training_script.py /tmp/ && python3 /tmp/training_script.py"
          ]
        }
      }],
      "computeResource": {
        "cpuMilli": 2000,
        "memoryMib": 4096
      },
      "environment": {
        "variables": {
          "REDIS_HOST": "${REDIS_HOST}",
          "REDIS_PORT": "${REDIS_PORT}",
          "BUCKET_NAME": "${BUCKET_NAME}"
        }
      }
    },
    "taskCount": 1
  }],
  "allocationPolicy": {
    "instances": [{
      "policy": {
        "machineType": "e2-standard-2"
      }
    }]
  }
}
EOF

success "Batch job configuration created"

# Create Jupyter notebook
log "Creating Jupyter notebook..."
cat > ml_training_notebook.ipynb << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Real-Time ML Training with Redis Caching\n",
    "\n",
    "This notebook demonstrates high-performance model training using Vertex AI Workbench with Redis caching for feature storage and retrieval."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Install required packages\n",
    "!pip install redis pandas scikit-learn google-cloud-storage google-cloud-monitoring"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import redis\nimport pandas as pd\nimport numpy as np\nfrom sklearn.ensemble import RandomForestClassifier\nfrom sklearn.model_selection import train_test_split\nfrom sklearn.metrics import accuracy_score\nimport pickle\nimport time\nfrom google.cloud import storage\nimport os\n\n# Configuration\nREDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')\nREDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))\nBUCKET_NAME = os.environ.get('BUCKET_NAME')\n\nprint(f'Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Connect to Redis cache\nr = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=False)\nprint('Redis connection status:', r.ping())\n\n# Check cache statistics\ninfo = r.info()\nprint(f'Redis memory usage: {info[\"used_memory_human\"]}')\nprint(f'Connected clients: {info[\"connected_clients\"]}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load data with caching optimization\ndef load_cached_features():\n    \"\"\"Load features from Redis cache or Cloud Storage\"\"\"\n    \n    # Try to load from cache first\n    cached_X = r.get('X_train')\n    cached_y = r.get('y_train')\n    \n    if cached_X and cached_y:\n        print('Loading features from Redis cache...')\n        X_train = pickle.loads(cached_X)\n        y_train = pickle.loads(cached_y)\n        return X_train, y_train\n    \n    # Load from Cloud Storage if not cached\n    print('Loading features from Cloud Storage and caching...')\n    client = storage.Client()\n    bucket = client.bucket(BUCKET_NAME)\n    blob = bucket.blob('datasets/training_dataset.csv')\n    blob.download_to_filename('/tmp/dataset.csv')\n    \n    df = pd.read_csv('/tmp/dataset.csv')\n    X = df.drop('target', axis=1)\n    y = df['target']\n    \n    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)\n    \n    # Cache for future use\n    r.setex('X_train', 3600, pickle.dumps(X_train))\n    r.setex('y_train', 3600, pickle.dumps(y_train))\n    r.setex('X_test', 3600, pickle.dumps(X_test))\n    r.setex('y_test', 3600, pickle.dumps(y_test))\n    \n    return X_train, y_train\n\n# Load features\nstart_time = time.time()\nX_train, y_train = load_cached_features()\nload_time = time.time() - start_time\nprint(f'Data loading completed in {load_time:.2f} seconds')\nprint(f'Training data shape: {X_train.shape}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Train model with performance monitoring\nprint('Starting model training...')\nstart_time = time.time()\n\nmodel = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)\nmodel.fit(X_train, y_train)\n\ntraining_time = time.time() - start_time\nprint(f'Model training completed in {training_time:.2f} seconds')\n\n# Cache trained model\nmodel_bytes = pickle.dumps(model)\nr.setex('trained_model', 3600, model_bytes)\nprint('Model cached in Redis for fast access')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Evaluate model performance\nX_test = pickle.loads(r.get('X_test'))\ny_test = pickle.loads(r.get('y_test'))\n\npredictions = model.predict(X_test)\naccuracy = accuracy_score(y_test, predictions)\n\nprint(f'Model Accuracy: {accuracy:.4f}')\n\n# Store metrics in Redis\nmetrics = {\n    'accuracy': accuracy,\n    'training_time': training_time,\n    'data_load_time': load_time,\n    'timestamp': time.time()\n}\nr.setex('model_metrics', 3600, pickle.dumps(metrics))\nprint('Metrics cached for dashboard access')"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

# Upload notebook to Cloud Storage
gsutil cp ml_training_notebook.ipynb "gs://${BUCKET_NAME}/notebooks/"

success "Jupyter notebook created and uploaded"

# Create monitoring dashboard
log "Creating monitoring dashboard..."
cat > monitoring_dashboard.json << EOF
{
  "displayName": "ML Training Pipeline Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Redis Cache Hit Ratio",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"redis_instance\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Workbench Instance CPU Usage",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"compute_instance\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      }
    ]
  }
}
EOF

# Create monitoring dashboard
gcloud monitoring dashboards create --config-from-file=monitoring_dashboard.json

success "Monitoring dashboard created"

# Submit batch job
log "Submitting Cloud Batch training job..."
gcloud batch jobs submit "${JOB_NAME}" \
    --location="${REGION}" \
    --config=batch_job.json

success "Batch job submitted successfully"

# Save configuration for cleanup
cat > deployment_config.env << EOF
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
ZONE="${ZONE}"
REDIS_INSTANCE_NAME="${REDIS_INSTANCE_NAME}"
WORKBENCH_NAME="${WORKBENCH_NAME}"
BUCKET_NAME="${BUCKET_NAME}"
JOB_NAME="${JOB_NAME}"
REDIS_HOST="${REDIS_HOST}"
REDIS_PORT="${REDIS_PORT}"
EOF

# Clean up temporary files
rm -f generate_dataset.py training_script.py batch_job.json
rm -f monitoring_dashboard.json ml_training_notebook.ipynb training_dataset.csv

success "Deployment configuration saved to deployment_config.env"

# Display deployment summary
echo ""
echo "============================================"
echo "Deployment Summary"
echo "============================================"
echo "✅ Project: ${PROJECT_ID}"
echo "✅ Region: ${REGION}"
echo "✅ Redis Instance: ${REDIS_INSTANCE_NAME}"
echo "✅ Redis Endpoint: ${REDIS_HOST}:${REDIS_PORT}"
echo "✅ Workbench Instance: ${WORKBENCH_NAME}"
echo "✅ Storage Bucket: gs://${BUCKET_NAME}"
echo "✅ Training Job: ${JOB_NAME}"
echo ""
echo "Next Steps:"
echo "1. Monitor the batch job: gcloud batch jobs describe ${JOB_NAME} --location=${REGION}"
echo "2. Access Workbench: gcloud workbench instances describe ${WORKBENCH_NAME} --location=${ZONE}"
echo "3. Check Redis status: gcloud redis instances describe ${REDIS_INSTANCE_NAME} --region=${REGION}"
echo "4. View monitoring dashboard in Cloud Console"
echo ""
echo "To clean up resources, run: ./destroy.sh"
echo "============================================"

success "Real-Time ML Training Infrastructure deployment completed successfully!"
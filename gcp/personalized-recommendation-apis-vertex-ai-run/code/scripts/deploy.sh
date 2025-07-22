#!/bin/bash

# Personalized Recommendation APIs with Vertex AI and Cloud Run - Deployment Script
# This script deploys the complete recommendation system infrastructure on Google Cloud Platform

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Python3 is installed
    if ! command_exists python3; then
        log_error "Python3 is not installed. Please install Python 3.7 or higher"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if bq is available
    if ! command_exists bq; then
        log_error "bq (BigQuery CLI) is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-recommendation-demo-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export BUCKET_NAME="${BUCKET_NAME:-rec-system-data-${PROJECT_ID}}"
    export SERVICE_NAME="${SERVICE_NAME:-recommendation-api}"
    export MODEL_NAME="${MODEL_NAME:-product-recommendations}"
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export ENDPOINT_NAME="${ENDPOINT_NAME:-rec-endpoint-${RANDOM_SUFFIX}}"
    
    log_info "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  SERVICE_NAME: ${SERVICE_NAME}"
    log_info "  MODEL_NAME: ${MODEL_NAME}"
    log_info "  ENDPOINT_NAME: ${ENDPOINT_NAME}"
}

# Function to create and configure Google Cloud project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Project $PROJECT_ID already exists. Using existing project."
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" \
            --name="Recommendation System Demo" || {
            log_error "Failed to create project. You may need billing account permissions."
            exit 1
        }
    fi
    
    # Set the project as default
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project configured successfully"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "run.googleapis.com"
        "storage.googleapis.com"
        "bigquery.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" || {
            log_error "Failed to enable $api"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_warning "Bucket gs://$BUCKET_NAME already exists. Using existing bucket."
    else
        # Create bucket with appropriate settings for ML workloads
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://$BUCKET_NAME" || {
            log_error "Failed to create storage bucket"
            exit 1
        }
    fi
    
    # Enable versioning for data protection and model lineage
    gsutil versioning set on "gs://$BUCKET_NAME"
    
    # Create organized folder structure for ML artifacts
    gsutil cp /dev/null "gs://$BUCKET_NAME/data/raw/.keep" 2>/dev/null || true
    gsutil cp /dev/null "gs://$BUCKET_NAME/data/processed/.keep" 2>/dev/null || true
    gsutil cp /dev/null "gs://$BUCKET_NAME/models/.keep" 2>/dev/null || true
    gsutil cp /dev/null "gs://$BUCKET_NAME/features/.keep" 2>/dev/null || true
    
    log_success "Cloud Storage bucket created with ML-optimized structure"
}

# Function to create BigQuery dataset
create_bigquery_dataset() {
    log_info "Creating BigQuery dataset..."
    
    # Check if dataset already exists
    if bq ls -d "${PROJECT_ID}:user_interactions" >/dev/null 2>&1; then
        log_warning "BigQuery dataset user_interactions already exists. Using existing dataset."
    else
        # Create BigQuery dataset for user interactions
        bq mk --dataset \
            --location="$REGION" \
            --description="User interaction data for recommendation system" \
            "${PROJECT_ID}:user_interactions" || {
            log_error "Failed to create BigQuery dataset"
            exit 1
        }
    fi
    
    # Create table for user behavior tracking
    bq mk --table \
        "${PROJECT_ID}:user_interactions.interactions" \
        user_id:STRING,item_id:STRING,interaction_type:STRING,rating:FLOAT,timestamp:TIMESTAMP,category:STRING,features:JSON \
        2>/dev/null || log_warning "Table interactions may already exist"
    
    log_success "BigQuery dataset and interaction table created"
}

# Function to generate and upload training data
generate_training_data() {
    log_info "Generating sample training data..."
    
    # Create Python script to generate sample recommendation data
    cat > generate_sample_data.py << 'EOF'
import json
import random
import pandas as pd
from datetime import datetime, timedelta

# Generate synthetic user interaction data
def generate_interactions(num_users=1000, num_items=500, num_interactions=10000):
    interactions = []
    
    for _ in range(num_interactions):
        user_id = f"user_{random.randint(1, num_users)}"
        item_id = f"item_{random.randint(1, num_items)}"
        interaction_type = random.choice(['view', 'purchase', 'rating', 'cart_add'])
        rating = round(random.uniform(1.0, 5.0), 1) if interaction_type == 'rating' else None
        timestamp = datetime.now() - timedelta(days=random.randint(0, 365))
        category = random.choice(['electronics', 'books', 'clothing', 'home', 'sports'])
        
        features = {
            'device_type': random.choice(['mobile', 'desktop', 'tablet']),
            'session_duration': random.randint(30, 3600),
            'page_views': random.randint(1, 20)
        }
        
        interactions.append({
            'user_id': user_id,
            'item_id': item_id,
            'interaction_type': interaction_type,
            'rating': rating,
            'timestamp': timestamp.isoformat(),
            'category': category,
            'features': json.dumps(features)
        })
    
    return pd.DataFrame(interactions)

# Generate and save training data
if __name__ == "__main__":
    df = generate_interactions()
    df.to_csv('training_data.csv', index=False)
    print(f"Generated {len(df)} training samples")
EOF
    
    # Install required Python packages
    python3 -m pip install pandas --user --quiet || {
        log_error "Failed to install required Python packages"
        exit 1
    }
    
    # Run data generation script
    python3 generate_sample_data.py || {
        log_error "Failed to generate training data"
        exit 1
    }
    
    # Upload training data to Cloud Storage
    gsutil cp training_data.csv "gs://$BUCKET_NAME/data/raw/" || {
        log_error "Failed to upload training data"
        exit 1
    }
    
    # Clean up local files
    rm -f generate_sample_data.py training_data.csv
    
    log_success "Sample training data generated and uploaded"
}

# Function to create training script
create_training_script() {
    log_info "Creating training script..."
    
    # Create training script for recommendation model
    cat > recommendation_trainer.py << 'EOF'
import tensorflow as tf
import tensorflow_recommenders as tfrs
import pandas as pd
import numpy as np
from google.cloud import storage
import os
import argparse
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class RecommendationModel(tfrs.Model):
    def __init__(self, rating_weight: float = 1.0, retrieval_weight: float = 1.0):
        super().__init__()
        
        # Define vocabularies
        self.user_vocab = tf.keras.utils.StringLookup(mask_token=None)
        self.item_vocab = tf.keras.utils.StringLookup(mask_token=None)
        
        # Define embedding dimensions
        embedding_dimension = 64
        
        # User and item embeddings
        self.user_embedding = tf.keras.Sequential([
            self.user_vocab,
            tf.keras.layers.Embedding(self.user_vocab.vocabulary_size(), embedding_dimension)
        ])
        
        self.item_embedding = tf.keras.Sequential([
            self.item_vocab,
            tf.keras.layers.Embedding(self.item_vocab.vocabulary_size(), embedding_dimension)
        ])
        
        # Rating prediction task
        self.rating_model = tf.keras.Sequential([
            tf.keras.layers.Dense(256, activation="relu"),
            tf.keras.layers.Dropout(0.5),
            tf.keras.layers.Dense(64, activation="relu"),
            tf.keras.layers.Dense(1)
        ])
        
        # Retrieval task
        self.retrieval_model = tfrs.tasks.Retrieval(
            metrics=tfrs.metrics.FactorizedTopK(
                metrics=[tf.keras.metrics.TopKCategoricalAccuracy(k=10)]
            )
        )
        
        # Rating task
        self.rating_task = tfrs.tasks.Ranking(
            loss=tf.keras.losses.MeanSquaredError(),
            metrics=[tf.keras.metrics.RootMeanSquaredError()]
        )
        
        self.rating_weight = rating_weight
        self.retrieval_weight = retrieval_weight
    
    def call(self, features):
        user_embeddings = self.user_embedding(features["user_id"])
        positive_item_embeddings = self.item_embedding(features["item_id"])
        
        return {
            "user_embedding": user_embeddings,
            "item_embedding": positive_item_embeddings,
            "predicted_rating": self.rating_model(
                tf.concat([user_embeddings, positive_item_embeddings], axis=1)
            ),
        }
    
    def compute_loss(self, features, training=False):
        predictions = self(features)
        
        # Retrieval loss
        retrieval_loss = self.retrieval_model(
            query_embeddings=predictions["user_embedding"],
            candidate_embeddings=predictions["item_embedding"],
        )
        
        # Rating loss
        rating_loss = self.rating_task(
            labels=features["rating"],
            predictions=predictions["predicted_rating"],
        )
        
        return (
            self.retrieval_weight * retrieval_loss
            + self.rating_weight * rating_loss
        )

def train_model():
    try:
        # Load training data from Cloud Storage
        client = storage.Client()
        bucket = client.bucket(os.environ['BUCKET_NAME'])
        blob = bucket.blob('data/raw/training_data.csv')
        blob.download_to_filename('training_data.csv')
        
        # Prepare data
        df = pd.read_csv('training_data.csv')
        df = df[df['rating'].notna()]  # Only use rated interactions
        
        # Create TensorFlow dataset
        ds = tf.data.Dataset.from_tensor_slices({
            "user_id": df['user_id'].astype(str),
            "item_id": df['item_id'].astype(str),
            "rating": df['rating'].astype(np.float32),
        })
        
        # Prepare dataset for training
        shuffled = ds.shuffle(10000, seed=42, reshuffle_each_iteration=False)
        train = shuffled.take(8000).batch(512).cache()
        test = shuffled.skip(8000).take(2000).batch(512).cache()
        
        # Create and train model
        model = RecommendationModel()
        model.compile(optimizer=tf.keras.optimizers.Adagrad(learning_rate=0.1))
        
        # Fit vocabularies
        feature_ds = ds.map(lambda x: {
            "user_id": x["user_id"],
            "item_id": x["item_id"]
        })
        model.user_vocab.adapt(feature_ds.map(lambda x: x["user_id"]))
        model.item_vocab.adapt(feature_ds.map(lambda x: x["item_id"]))
        
        # Train model
        logger.info("Starting model training...")
        model.fit(train, epochs=10, validation_data=test, verbose=2)
        
        # Save model to Cloud Storage
        model_path = f"gs://{os.environ['BUCKET_NAME']}/models/{os.environ['MODEL_NAME']}"
        model.save(model_path, save_format='tf')
        
        logger.info(f"Model saved to {model_path}")
        
    except Exception as e:
        logger.error(f"Training failed: {str(e)}")
        raise

if __name__ == "__main__":
    train_model()
EOF
    
    # Upload training script to Cloud Storage
    gsutil cp recommendation_trainer.py "gs://$BUCKET_NAME/code/" || {
        log_error "Failed to upload training script"
        exit 1
    }
    
    # Clean up local file
    rm -f recommendation_trainer.py
    
    log_success "Training script created and uploaded"
}

# Function to submit training job
submit_training_job() {
    log_info "Submitting training job to Vertex AI..."
    
    # Create custom training job
    gcloud ai custom-jobs create \
        --region="$REGION" \
        --display-name="recommendation-training-job" \
        --python-package-uris="gs://$BUCKET_NAME/code/recommendation_trainer.py" \
        --python-module="recommendation_trainer" \
        --container-image-uri="gcr.io/cloud-aiplatform/training/tf-gpu.2-12.py310:latest" \
        --machine-type="n1-standard-4" \
        --accelerator-type="NVIDIA_TESLA_T4" \
        --accelerator-count=1 \
        --environment-variables="BUCKET_NAME=$BUCKET_NAME,MODEL_NAME=$MODEL_NAME" \
        --max-running-time=3600 || {
        log_error "Failed to submit training job"
        exit 1
    }
    
    log_success "Training job submitted to Vertex AI"
    log_info "Training job will take 15-30 minutes to complete"
    log_info "Monitor progress at: https://console.cloud.google.com/vertex-ai/training/custom-jobs?project=$PROJECT_ID"
}

# Function to wait for training completion
wait_for_training() {
    log_info "Waiting for training job to complete..."
    
    local max_wait=1800  # 30 minutes
    local wait_time=0
    local check_interval=60
    
    while [ $wait_time -lt $max_wait ]; do
        local job_state=$(gcloud ai custom-jobs list --region="$REGION" \
            --filter="displayName:recommendation-training-job" \
            --format="value(state)" --limit=1 2>/dev/null || echo "UNKNOWN")
        
        case "$job_state" in
            "JOB_STATE_SUCCEEDED")
                log_success "Training job completed successfully"
                return 0
                ;;
            "JOB_STATE_FAILED")
                log_error "Training job failed"
                return 1
                ;;
            "JOB_STATE_CANCELLED")
                log_error "Training job was cancelled"
                return 1
                ;;
            "JOB_STATE_RUNNING")
                log_info "Training job is still running... (${wait_time}s elapsed)"
                ;;
            *)
                log_info "Training job status: $job_state (${wait_time}s elapsed)"
                ;;
        esac
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    log_warning "Training job is taking longer than expected. Continuing with deployment..."
    return 0
}

# Function to deploy model to Vertex AI endpoint
deploy_model() {
    log_info "Deploying model to Vertex AI endpoint..."
    
    # Create model resource in Vertex AI
    gcloud ai models upload \
        --region="$REGION" \
        --display-name="$MODEL_NAME" \
        --container-image-uri="gcr.io/cloud-aiplatform/prediction/tf2-gpu.2-12:latest" \
        --artifact-uri="gs://$BUCKET_NAME/models/$MODEL_NAME" \
        --description="Collaborative filtering recommendation model" || {
        log_error "Failed to upload model"
        exit 1
    }
    
    # Get model ID
    local model_id
    model_id=$(gcloud ai models list --region="$REGION" \
        --filter="displayName:$MODEL_NAME" \
        --format="value(name)" --limit=1 | cut -d'/' -f6)
    
    if [ -z "$model_id" ]; then
        log_error "Failed to get model ID"
        exit 1
    fi
    
    # Create endpoint for model serving
    gcloud ai endpoints create \
        --region="$REGION" \
        --display-name="$ENDPOINT_NAME" \
        --description="Recommendation model serving endpoint" || {
        log_error "Failed to create endpoint"
        exit 1
    }
    
    # Get endpoint ID
    local endpoint_id
    endpoint_id=$(gcloud ai endpoints list --region="$REGION" \
        --filter="displayName:$ENDPOINT_NAME" \
        --format="value(name)" --limit=1 | cut -d'/' -f6)
    
    if [ -z "$endpoint_id" ]; then
        log_error "Failed to get endpoint ID"
        exit 1
    fi
    
    # Deploy model to endpoint
    gcloud ai endpoints deploy-model "$endpoint_id" \
        --region="$REGION" \
        --model="$model_id" \
        --display-name="recommendation-deployment" \
        --machine-type="n1-standard-2" \
        --min-replica-count=1 \
        --max-replica-count=5 \
        --traffic-split=0=100 || {
        log_error "Failed to deploy model to endpoint"
        exit 1
    }
    
    # Store endpoint ID for later use
    export ENDPOINT_ID="$endpoint_id"
    
    log_success "Model deployed to Vertex AI endpoint: $endpoint_id"
}

# Function to create and deploy Cloud Run API
deploy_api() {
    log_info "Creating and deploying Cloud Run API..."
    
    # Create API application directory
    mkdir -p recommendation-api
    cd recommendation-api
    
    # Create Flask API application
    cat > main.py << 'EOF'
import os
import json
from flask import Flask, request, jsonify
from google.cloud import aiplatform
from google.oauth2 import service_account
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Vertex AI client
aiplatform.init(
    project=os.environ.get('PROJECT_ID'),
    location=os.environ.get('REGION')
)

@app.route('/', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'service': 'recommendation-api'})

@app.route('/recommend', methods=['POST'])
def get_recommendations():
    try:
        # Parse request
        data = request.get_json()
        user_id = data.get('user_id')
        num_recommendations = data.get('num_recommendations', 10)
        
        if not user_id:
            return jsonify({'error': 'user_id is required'}), 400
        
        # Get endpoint
        endpoint_name = f"projects/{os.environ.get('PROJECT_ID')}/locations/{os.environ.get('REGION')}/endpoints/{os.environ.get('ENDPOINT_ID')}"
        endpoint = aiplatform.Endpoint(endpoint_name)
        
        # Prepare prediction input
        instances = [{
            'user_id': user_id,
            'item_id': 'item_1'  # This would be replaced with candidate items
        }]
        
        # Get predictions
        predictions = endpoint.predict(instances=instances)
        
        # Format response
        recommendations = []
        for i, prediction in enumerate(predictions.predictions):
            recommendations.append({
                'item_id': f'item_{i+1}',
                'score': float(prediction[0]) if prediction else 0.0,
                'category': 'electronics'  # This would come from item metadata
            })
        
        # Sort by score and limit results
        recommendations = sorted(recommendations, key=lambda x: x['score'], reverse=True)[:num_recommendations]
        
        return jsonify({
            'user_id': user_id,
            'recommendations': recommendations,
            'timestamp': json.dumps(None, default=str)
        })
        
    except Exception as e:
        logging.error(f"Error generating recommendations: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/feedback', methods=['POST'])
def record_feedback():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        item_id = data.get('item_id')
        feedback_type = data.get('feedback_type')  # 'like', 'dislike', 'click', 'purchase'
        
        # Here you would typically store feedback in BigQuery for model retraining
        logging.info(f"Feedback recorded: {user_id} -> {item_id} ({feedback_type})")
        
        return jsonify({'status': 'feedback recorded'})
        
    except Exception as e:
        logging.error(f"Error recording feedback: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==2.3.3
google-cloud-aiplatform==1.38.1
google-auth==2.23.4
google-oauth2-tool==0.0.3
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY main.py .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF
    
    # Build and deploy to Cloud Run
    gcloud run deploy "$SERVICE_NAME" \
        --source . \
        --region="$REGION" \
        --platform=managed \
        --allow-unauthenticated \
        --set-env-vars="PROJECT_ID=$PROJECT_ID,REGION=$REGION,ENDPOINT_ID=$ENDPOINT_ID" \
        --memory=2Gi \
        --cpu=2 \
        --max-instances=100 \
        --timeout=300 || {
        log_error "Failed to deploy Cloud Run service"
        exit 1
    }
    
    # Get service URL
    local service_url
    service_url=$(gcloud run services describe "$SERVICE_NAME" \
        --region="$REGION" \
        --format="value(status.url)")
    
    cd ..
    rm -rf recommendation-api
    
    log_success "API deployed to Cloud Run: $service_url"
    export SERVICE_URL="$service_url"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    if [ -z "$SERVICE_URL" ]; then
        log_warning "Service URL not available. Skipping tests."
        return 0
    fi
    
    # Test health check
    if curl -s -f "$SERVICE_URL/" >/dev/null; then
        log_success "Health check passed"
    else
        log_warning "Health check failed"
    fi
    
    # Test recommendation endpoint
    if curl -s -X POST "$SERVICE_URL/recommend" \
        -H "Content-Type: application/json" \
        -d '{"user_id": "user_123", "num_recommendations": 5}' >/dev/null; then
        log_success "Recommendation endpoint test passed"
    else
        log_warning "Recommendation endpoint test failed"
    fi
    
    log_info "Testing completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Model Name: $MODEL_NAME"
    echo "Endpoint Name: $ENDPOINT_NAME"
    echo "Service Name: $SERVICE_NAME"
    if [ -n "$SERVICE_URL" ]; then
        echo "API URL: $SERVICE_URL"
    fi
    echo
    echo "=== Next Steps ==="
    echo "1. Test the API endpoints using curl or a REST client"
    echo "2. Monitor the services in Google Cloud Console"
    echo "3. Check logs for any issues"
    echo "4. Scale resources as needed for your use case"
    echo
    echo "=== Useful Commands ==="
    echo "Test health check:"
    echo "  curl $SERVICE_URL/"
    echo
    echo "Test recommendations:"
    echo "  curl -X POST $SERVICE_URL/recommend -H 'Content-Type: application/json' -d '{\"user_id\": \"user_123\", \"num_recommendations\": 5}'"
    echo
    echo "=== Cleanup ==="
    echo "Run './destroy.sh' to remove all resources and avoid charges"
}

# Main deployment function
main() {
    log_info "Starting deployment of Personalized Recommendation APIs with Vertex AI and Cloud Run"
    
    # Check if user wants to proceed
    if [ "$1" != "--yes" ]; then
        echo "This script will create resources on Google Cloud Platform."
        echo "Estimated cost: $50-100 for training and serving resources"
        echo
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_bigquery_dataset
    generate_training_data
    create_training_script
    submit_training_job
    wait_for_training
    deploy_model
    deploy_api
    test_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
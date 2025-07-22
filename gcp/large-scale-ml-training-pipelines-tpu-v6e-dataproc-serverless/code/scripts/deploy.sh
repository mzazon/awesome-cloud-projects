#!/bin/bash

# Large-Scale ML Training Pipeline Deployment Script
# Deploys Cloud TPU v6e and Dataproc Serverless infrastructure for ML training
# Recipe: large-scale-ml-training-pipelines-tpu-v6e-dataproc-serverless

set -euo pipefail

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        log_error "No default project set. Run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Check for required tools
    for tool in gsutil openssl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it before proceeding."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core project settings
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central2"
    export ZONE="us-central2-b"
    export BUCKET_NAME="ml-training-pipeline-$(date +%s)"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export TPU_NAME="training-tpu-${RANDOM_SUFFIX}"
    export DATAPROC_BATCH_ID="preprocessing-${RANDOM_SUFFIX}"
    
    # Configure gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "TPU Name: ${TPU_NAME}"
    log_info "Storage Bucket: ${BUCKET_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "tpu.googleapis.com"
        "dataproc.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for API enablement to propagate
    log_info "Waiting for API enablement to propagate..."
    sleep 30
    
    log_success "Required APIs enabled"
}

# Function to create storage infrastructure
create_storage() {
    log_info "Creating Cloud Storage infrastructure..."
    
    # Create the main storage bucket
    if ! gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Enable versioning for data protection
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        log_success "Storage bucket created: ${BUCKET_NAME}"
    else
        log_warning "Storage bucket already exists: ${BUCKET_NAME}"
    fi
    
    # Create directory structure
    log_info "Setting up pipeline directory structure..."
    gsutil -m mkdir "gs://${BUCKET_NAME}/raw-data/" || true
    gsutil -m mkdir "gs://${BUCKET_NAME}/processed-data/" || true
    gsutil -m mkdir "gs://${BUCKET_NAME}/models/" || true
    gsutil -m mkdir "gs://${BUCKET_NAME}/checkpoints/" || true
    gsutil -m mkdir "gs://${BUCKET_NAME}/logs/" || true
    gsutil -m mkdir "gs://${BUCKET_NAME}/scripts/" || true
    
    # Configure bucket for high-performance ML workloads
    cat > /tmp/cors.json << 'EOF'
[
  {
    "origin": ["*"],
    "method": ["GET", "POST", "PUT"],
    "responseHeader": ["Content-Type"],
    "maxAgeSeconds": 3600
  }
]
EOF
    
    gsutil cors set /tmp/cors.json "gs://${BUCKET_NAME}"
    rm /tmp/cors.json
    
    # Upload sample data if available
    log_info "Copying sample training data..."
    if gsutil ls "gs://cloud-ml-public-datasets/sample-text-data/" &> /dev/null; then
        gsutil -m cp -r "gs://cloud-ml-public-datasets/sample-text-data/" \
            "gs://${BUCKET_NAME}/raw-data/" || log_warning "Sample data copy failed, continuing..."
    else
        log_warning "Sample dataset not available, you'll need to upload your own training data"
    fi
    
    log_success "Storage infrastructure created successfully"
}

# Function to create preprocessing scripts
create_preprocessing_script() {
    log_info "Creating data preprocessing script..."
    
    cat > /tmp/preprocessing_job.py << 'EOF'
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
import sys
import logging

def preprocess_training_data(input_path, output_path):
    """
    Preprocess training data for TPU consumption
    Optimizes data format and partitioning for high-performance training
    """
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    logger.info(f"Starting preprocessing: {input_path} -> {output_path}")
    
    spark = SparkSession.builder \
        .appName("ML-Data-Preprocessing") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.sql.adaptive.skewJoin.enabled", "true") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .getOrCreate()
    
    try:
        # Read raw text data with error handling
        df = spark.read.option("multiline", "true").text(input_path)
        logger.info(f"Read {df.count()} records from input")
        
        # Data preprocessing for language model training
        processed_df = df.select(
            col("value").alias("text")
        ).filter(
            # Filter out empty or very short text
            (col("text").isNotNull()) & 
            (length(trim(col("text"))) > 10)
        ).withColumn(
            # Add text length for analysis
            "text_length", length(col("text"))
        ).repartition(100)  # Optimize for TPU consumption
        
        # Log processing statistics
        total_records = processed_df.count()
        logger.info(f"Processed {total_records} records")
        
        # Write preprocessed data in Parquet format for optimal TPU reading
        processed_df.write.mode("overwrite") \
            .option("compression", "snappy") \
            .parquet(output_path)
        
        logger.info("Preprocessing completed successfully")
        
    except Exception as e:
        logger.error(f"Preprocessing failed: {str(e)}")
        raise
    finally:
        spark.stop()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: preprocessing_job.py <input_path> <output_path>")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    preprocess_training_data(input_path, output_path)
EOF
    
    # Upload preprocessing script to Cloud Storage
    gsutil cp /tmp/preprocessing_job.py "gs://${BUCKET_NAME}/scripts/"
    rm /tmp/preprocessing_job.py
    
    log_success "Preprocessing script created and uploaded"
}

# Function to deploy Dataproc Serverless
deploy_dataproc() {
    log_info "Deploying Dataproc Serverless for data preprocessing..."
    
    # Check if batch already exists and is running
    if gcloud dataproc batches describe "${DATAPROC_BATCH_ID}" --region="${REGION}" &> /dev/null; then
        local batch_state=$(gcloud dataproc batches describe "${DATAPROC_BATCH_ID}" \
            --region="${REGION}" --format="value(state)")
        
        if [[ "${batch_state}" == "RUNNING" ]]; then
            log_warning "Dataproc batch ${DATAPROC_BATCH_ID} is already running"
            return 0
        fi
    fi
    
    # Submit Dataproc Serverless batch job
    log_info "Submitting preprocessing job..."
    gcloud dataproc batches submit pyspark \
        "gs://${BUCKET_NAME}/scripts/preprocessing_job.py" \
        --batch="${DATAPROC_BATCH_ID}" \
        --region="${REGION}" \
        --deps-bucket="${BUCKET_NAME}" \
        --subnet=default \
        --service-account="${PROJECT_ID}-compute@developer.gserviceaccount.com" \
        --properties="spark.executor.memory=4g,spark.driver.memory=2g,spark.executor.instances=4" \
        --labels="environment=ml-training,recipe=tpu-v6e-pipeline" \
        -- "gs://${BUCKET_NAME}/raw-data/" "gs://${BUCKET_NAME}/processed-data/" \
        --quiet
    
    log_success "Dataproc Serverless preprocessing job submitted: ${DATAPROC_BATCH_ID}"
}

# Function to create TPU training infrastructure
create_tpu_infrastructure() {
    log_info "Creating Cloud TPU v6e training infrastructure..."
    
    # Check TPU v6e availability
    log_info "Checking TPU v6e availability in ${REGION}..."
    local available_types=$(gcloud compute tpus locations describe "${REGION}" \
        --format="value(availableAcceleratorTypes[])" | grep -o "v6e" || true)
    
    if [[ -z "${available_types}" ]]; then
        log_warning "TPU v6e may not be available in ${REGION}. Check availability and adjust region if needed."
    fi
    
    # Check if TPU already exists
    if gcloud compute tpus tpu-vm describe "${TPU_NAME}" --zone="${ZONE}" &> /dev/null; then
        log_warning "TPU ${TPU_NAME} already exists"
        return 0
    fi
    
    log_info "Creating TPU v6e instance: ${TPU_NAME}"
    gcloud compute tpus tpu-vm create "${TPU_NAME}" \
        --zone="${ZONE}" \
        --accelerator-type=v6e-8 \
        --version=tpu-vm-v4-base \
        --network=default \
        --subnetwork=default \
        --service-account="${PROJECT_ID}-compute@developer.gserviceaccount.com" \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --tags=ml-training \
        --labels="environment=ml-training,recipe=tpu-v6e-pipeline" \
        --quiet
    
    # Wait for TPU to become ready
    log_info "Waiting for TPU to become ready..."
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local tpu_state=$(gcloud compute tpus tpu-vm describe "${TPU_NAME}" \
            --zone="${ZONE}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${tpu_state}" == "READY" ]]; then
            break
        fi
        
        log_info "TPU state: ${tpu_state}. Waiting... (${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        log_error "TPU failed to become ready within expected time"
        return 1
    fi
    
    # Get TPU IP for reference
    export TPU_IP=$(gcloud compute tpus tpu-vm describe "${TPU_NAME}" \
        --zone="${ZONE}" --format="value(networkEndpoints[0].ipAddress)")
    
    log_success "TPU v6e created successfully: ${TPU_NAME}"
    log_info "TPU IP Address: ${TPU_IP}"
}

# Function to create training scripts
create_training_scripts() {
    log_info "Creating TPU training scripts..."
    
    cat > /tmp/tpu_training_script.py << 'EOF'
import jax
import jax.numpy as jnp
from jax import random
import flax.linen as nn
import optax
import os
import logging
from typing import Any, Callable
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TransformerModel(nn.Module):
    """Simple transformer model optimized for TPU v6e training"""
    vocab_size: int
    hidden_dim: int = 512
    num_heads: int = 8
    num_layers: int = 6
    max_seq_length: int = 512
    
    @nn.compact
    def __call__(self, x, training=True):
        # Token and position embeddings
        x = nn.Embed(self.vocab_size, self.hidden_dim)(x)
        
        # Add positional encoding
        seq_length = x.shape[1]
        pos_encoding = self.param('pos_encoding',
                                nn.initializers.normal(stddev=0.02),
                                (self.max_seq_length, self.hidden_dim))
        x = x + pos_encoding[:seq_length]
        
        # Transformer layers
        for layer_idx in range(self.num_layers):
            # Multi-head attention with residual connection
            attn_out = nn.MultiHeadDotProductAttention(
                num_heads=self.num_heads,
                qkv_features=self.hidden_dim,
                dropout_rate=0.1 if training else 0.0
            )(x, x)
            x = nn.LayerNorm()(x + attn_out)
            
            # Feed-forward network with residual connection
            ff_out = nn.Dense(self.hidden_dim * 4)(x)
            ff_out = nn.gelu(ff_out)
            ff_out = nn.Dense(self.hidden_dim)(ff_out)
            if training:
                ff_out = nn.Dropout(rate=0.1)(ff_out, deterministic=False)
            x = nn.LayerNorm()(x + ff_out)
        
        # Output projection
        return nn.Dense(self.vocab_size)(x)

def create_train_step(model: nn.Module, optimizer: optax.GradientTransformation):
    """Create optimized training step for TPU v6e"""
    
    def train_step(params, opt_state, batch, dropout_key):
        def loss_fn(params):
            logits = model.apply(
                params, batch['input_ids'], 
                training=True, rngs={'dropout': dropout_key}
            )
            # Compute cross-entropy loss
            loss = optax.softmax_cross_entropy_with_integer_labels(
                logits, batch['labels']
            ).mean()
            return loss, logits
        
        # Compute gradients
        (loss, logits), grads = jax.value_and_grad(loss_fn, has_aux=True)(params)
        
        # Apply gradients
        updates, opt_state = optimizer.update(grads, opt_state, params)
        params = optax.apply_updates(params, updates)
        
        # Compute accuracy for monitoring
        predictions = jnp.argmax(logits, axis=-1)
        accuracy = jnp.mean(predictions == batch['labels'])
        
        return params, opt_state, loss, accuracy
    
    # Parallelize across TPU cores
    return jax.pmap(train_step, axis_name='devices')

def create_dummy_batch(batch_size: int, seq_length: int, vocab_size: int, key: Any):
    """Create dummy training batch for demonstration"""
    input_key, label_key = random.split(key)
    
    return {
        'input_ids': random.randint(input_key, (batch_size, seq_length), 0, vocab_size),
        'labels': random.randint(label_key, (batch_size, seq_length), 0, vocab_size)
    }

def main():
    """Main training function optimized for TPU v6e"""
    logger.info("Starting TPU v6e training...")
    
    # Training configuration
    config = {
        'vocab_size': 50000,
        'hidden_dim': 512,
        'num_heads': 8,
        'num_layers': 6,
        'batch_size': 32,
        'seq_length': 512,
        'learning_rate': 1e-4,
        'num_steps': 1000,
    }
    
    # Initialize model
    key = random.PRNGKey(42)
    model = TransformerModel(
        vocab_size=config['vocab_size'],
        hidden_dim=config['hidden_dim'],
        num_heads=config['num_heads'],
        num_layers=config['num_layers']
    )
    
    # Initialize parameters
    dummy_input = jnp.ones((1, config['seq_length']), dtype=jnp.int32)
    params = model.init(key, dummy_input, training=False)
    
    # Create optimizer optimized for TPU
    optimizer = optax.chain(
        optax.clip_by_global_norm(1.0),  # Gradient clipping
        optax.adamw(
            learning_rate=optax.cosine_decay_schedule(
                init_value=config['learning_rate'],
                decay_steps=config['num_steps']
            ),
            weight_decay=0.01
        )
    )
    opt_state = optimizer.init(params)
    
    # Replicate for multi-device training
    num_devices = jax.device_count()
    logger.info(f"Training on {num_devices} TPU cores")
    logger.info(f"TPU devices: {jax.devices()}")
    
    params = jax.tree_map(lambda x: jnp.array([x] * num_devices), params)
    opt_state = jax.tree_map(lambda x: jnp.array([x] * num_devices), opt_state)
    
    # Create training step function
    train_step = create_train_step(model, optimizer)
    
    # Training loop
    logger.info("Starting training loop...")
    batch_key = random.PRNGKey(1)
    
    for step in range(config['num_steps']):
        step_start_time = time.time()
        
        # Create training batch (replace with real data loading)
        batch_key, data_key, dropout_key = random.split(batch_key, 3)
        batch = create_dummy_batch(
            config['batch_size'] // num_devices,  # Per-device batch size
            config['seq_length'],
            config['vocab_size'],
            data_key
        )
        
        # Replicate batch across devices
        batch = jax.tree_map(lambda x: jnp.array([x] * num_devices), batch)
        dropout_keys = random.split(dropout_key, num_devices)
        
        # Training step
        params, opt_state, loss, accuracy = train_step(
            params, opt_state, batch, dropout_keys
        )
        
        # Log progress
        if step % 100 == 0:
            step_time = time.time() - step_start_time
            avg_loss = jnp.mean(loss)
            avg_accuracy = jnp.mean(accuracy)
            
            logger.info(f"Step {step}: loss={avg_loss:.4f}, "
                       f"accuracy={avg_accuracy:.4f}, "
                       f"time={step_time:.2f}s")
            
            # Log to Cloud Logging
            os.system(f'gcloud logging write tpu-training '
                     f'"Step {step}: loss={avg_loss:.4f}, accuracy={avg_accuracy:.4f}" '
                     f'--severity=INFO')
    
    logger.info("Training completed successfully!")
    return params

if __name__ == "__main__":
    main()
EOF
    
    # Upload training script to TPU
    gsutil cp /tmp/tpu_training_script.py "gs://${BUCKET_NAME}/scripts/"
    
    # Copy training script to TPU instance
    log_info "Uploading training script to TPU..."
    gcloud compute tpus tpu-vm scp /tmp/tpu_training_script.py \
        "${TPU_NAME}:/tmp/training_script.py" --zone="${ZONE}" --quiet
    
    rm /tmp/tpu_training_script.py
    
    log_success "Training scripts created and uploaded"
}

# Function to setup TPU environment
setup_tpu_environment() {
    log_info "Setting up TPU training environment..."
    
    # Install required packages on TPU
    log_info "Installing TPU training dependencies..."
    gcloud compute tpus tpu-vm ssh "${TPU_NAME}" \
        --zone="${ZONE}" \
        --command="pip install --upgrade pip && \
                   pip install jax[tpu] flax optax tensorflow google-cloud-storage google-cloud-logging && \
                   python -c 'import jax; print(f\"JAX devices: {jax.devices()}\")'" \
        --quiet
    
    log_success "TPU environment setup completed"
}

# Function to create monitoring dashboard
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create monitoring dashboard configuration
    cat > /tmp/monitoring_dashboard.json << 'EOF'
{
  "displayName": "TPU v6e Training Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "TPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"tpu_worker\"",
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
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Dataproc Batch Status",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"dataproc_batch\"",
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
      }
    ]
  }
}
EOF
    
    # Create monitoring dashboard
    if gcloud monitoring dashboards create --config-from-file=/tmp/monitoring_dashboard.json --quiet 2>/dev/null; then
        log_success "Monitoring dashboard created"
    else
        log_warning "Failed to create monitoring dashboard (may already exist)"
    fi
    
    rm /tmp/monitoring_dashboard.json
}

# Function to wait for preprocessing completion
wait_for_preprocessing() {
    log_info "Waiting for data preprocessing to complete..."
    
    local max_wait_time=3600  # 1 hour
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [[ ${elapsed_time} -gt ${max_wait_time} ]]; then
            log_error "Preprocessing timeout after ${max_wait_time} seconds"
            return 1
        fi
        
        local batch_state=$(gcloud dataproc batches describe "${DATAPROC_BATCH_ID}" \
            --region="${REGION}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        case "${batch_state}" in
            "SUCCEEDED")
                log_success "Data preprocessing completed successfully"
                return 0
                ;;
            "FAILED"|"CANCELLED")
                log_error "Data preprocessing failed with state: ${batch_state}"
                return 1
                ;;
            "RUNNING")
                log_info "Preprocessing still running... (${elapsed_time}s elapsed)"
                ;;
            *)
                log_info "Preprocessing state: ${batch_state}"
                ;;
        esac
        
        sleep 60
    done
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "TPU Name: ${TPU_NAME}"
    echo "Dataproc Batch ID: ${DATAPROC_BATCH_ID}"
    echo "=================================================="
    echo ""
    echo "Next Steps:"
    echo "1. Monitor preprocessing: gcloud dataproc batches describe ${DATAPROC_BATCH_ID} --region=${REGION}"
    echo "2. Check TPU status: gcloud compute tpus tpu-vm describe ${TPU_NAME} --zone=${ZONE}"
    echo "3. Start training: gcloud compute tpus tpu-vm ssh ${TPU_NAME} --zone=${ZONE} --command='cd /tmp && python training_script.py'"
    echo "4. Monitor logs: gcloud logging read \"resource.type=tpu_worker\" --limit=50"
    echo ""
    echo "Cleanup: Run ./destroy.sh when finished"
}

# Main deployment function
main() {
    echo "=============================================="
    echo "  ML Training Pipeline Deployment Script"
    echo "  Recipe: TPU v6e + Dataproc Serverless"
    echo "=============================================="
    echo ""
    
    check_prerequisites
    setup_environment
    enable_apis
    create_storage
    create_preprocessing_script
    deploy_dataproc
    create_tpu_infrastructure
    create_training_scripts
    setup_tpu_environment
    setup_monitoring
    
    log_success "Deployment completed successfully!"
    display_summary
    
    # Save environment variables for cleanup script
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
TPU_NAME=${TPU_NAME}
DATAPROC_BATCH_ID=${DATAPROC_BATCH_ID}
EOF
    
    log_info "Environment variables saved to .env file"
}

# Run main function
main "$@"
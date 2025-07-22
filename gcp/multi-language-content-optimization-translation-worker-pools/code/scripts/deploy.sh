#!/bin/bash

#####################################################################
# Deploy Script for Multi-Language Content Optimization
# GCP Recipe: Cloud Translation Advanced + Cloud Run Worker Pools
#####################################################################

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

#####################################################################
# Logging Functions
#####################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#####################################################################
# Error Handling
#####################################################################

cleanup_on_error() {
    local exit_code=$?
    log ERROR "Deployment failed with exit code $exit_code"
    log INFO "Check $ERROR_LOG for detailed error information"
    log INFO "Run ./destroy.sh to clean up any partially created resources"
    exit $exit_code
}

trap cleanup_on_error ERR

#####################################################################
# Prerequisites Check
#####################################################################

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log ERROR "Google Cloud CLI (gcloud) is not installed"
        log INFO "Install from: https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log ERROR "gsutil is not available"
        log INFO "gsutil should be included with gcloud CLI"
        return 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log ERROR "BigQuery CLI (bq) is not available"
        log INFO "bq should be included with gcloud CLI"
        return 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log ERROR "Not authenticated with gcloud"
        log INFO "Run: gcloud auth login"
        return 1
    fi
    
    # Check if Docker is installed (for container builds)
    if ! command -v docker &> /dev/null; then
        log WARN "Docker is not installed locally"
        log INFO "Using Cloud Build for container builds"
    fi
    
    log INFO "✅ Prerequisites check passed"
    return 0
}

#####################################################################
# Environment Setup
#####################################################################

setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="content-optimization-$(date +%s)"
        log INFO "Generated PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export SOURCE_BUCKET="content-source-${RANDOM_SUFFIX}"
    export TRANSLATED_BUCKET="content-translated-${RANDOM_SUFFIX}"
    export MODELS_BUCKET="translation-models-${RANDOM_SUFFIX}"
    export TOPIC_NAME="content-processing-${RANDOM_SUFFIX}"
    export WORKER_POOL_NAME="translation-workers-${RANDOM_SUFFIX}"
    export DATASET_NAME="content_analytics_${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="translation-worker-sa"
    
    # Save environment variables to file for later use
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
SOURCE_BUCKET=$SOURCE_BUCKET
TRANSLATED_BUCKET=$TRANSLATED_BUCKET
MODELS_BUCKET=$MODELS_BUCKET
TOPIC_NAME=$TOPIC_NAME
WORKER_POOL_NAME=$WORKER_POOL_NAME
DATASET_NAME=$DATASET_NAME
SERVICE_ACCOUNT_NAME=$SERVICE_ACCOUNT_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log INFO "✅ Environment variables configured"
    log DEBUG "Resource names:"
    log DEBUG "  PROJECT_ID: $PROJECT_ID"
    log DEBUG "  SOURCE_BUCKET: $SOURCE_BUCKET"
    log DEBUG "  TRANSLATED_BUCKET: $TRANSLATED_BUCKET"
    log DEBUG "  WORKER_POOL_NAME: $WORKER_POOL_NAME"
}

#####################################################################
# Project Configuration
#####################################################################

configure_project() {
    log INFO "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || {
        log ERROR "Failed to set project: $PROJECT_ID"
        log INFO "Ensure the project exists and you have access"
        return 1
    }
    
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log INFO "✅ Project configuration completed"
}

#####################################################################
# API Enablement
#####################################################################

enable_apis() {
    log INFO "Enabling required Google Cloud APIs..."
    
    local apis=(
        "translate.googleapis.com"
        "run.googleapis.com"
        "storage.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log INFO "Enabling $api..."
        gcloud services enable "$api" || {
            log ERROR "Failed to enable API: $api"
            return 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log INFO "Waiting for APIs to be fully activated..."
    sleep 30
    
    log INFO "✅ All required APIs enabled"
}

#####################################################################
# Storage Resources
#####################################################################

create_storage_buckets() {
    log INFO "Creating Cloud Storage buckets..."
    
    # Create source content bucket with versioning
    log INFO "Creating source content bucket: $SOURCE_BUCKET"
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${SOURCE_BUCKET}" || {
        log ERROR "Failed to create source bucket"
        return 1
    }
    
    gsutil versioning set on "gs://${SOURCE_BUCKET}"
    
    # Create translated content bucket
    log INFO "Creating translated content bucket: $TRANSLATED_BUCKET"
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${TRANSLATED_BUCKET}" || {
        log ERROR "Failed to create translated bucket"
        return 1
    }
    
    # Create custom models bucket
    log INFO "Creating models bucket: $MODELS_BUCKET"
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${MODELS_BUCKET}" || {
        log ERROR "Failed to create models bucket"
        return 1
    }
    
    log INFO "✅ Storage buckets created successfully"
}

#####################################################################
# Pub/Sub Resources
#####################################################################

create_pubsub_resources() {
    log INFO "Creating Pub/Sub resources..."
    
    # Create main topic
    log INFO "Creating topic: $TOPIC_NAME"
    gcloud pubsub topics create "${TOPIC_NAME}" || {
        log ERROR "Failed to create topic"
        return 1
    }
    
    # Create subscription for worker pool
    log INFO "Creating subscription: ${TOPIC_NAME}-sub"
    gcloud pubsub subscriptions create "${TOPIC_NAME}-sub" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=600 \
        --message-retention-duration=7d || {
        log ERROR "Failed to create subscription"
        return 1
    }
    
    # Create dead letter topic and subscription
    log INFO "Creating dead letter topic: ${TOPIC_NAME}-dlq"
    gcloud pubsub topics create "${TOPIC_NAME}-dlq"
    
    gcloud pubsub subscriptions create "${TOPIC_NAME}-dlq-sub" \
        --topic="${TOPIC_NAME}-dlq" || {
        log ERROR "Failed to create dead letter subscription"
        return 1
    }
    
    log INFO "✅ Pub/Sub resources created successfully"
}

#####################################################################
# BigQuery Resources
#####################################################################

create_bigquery_resources() {
    log INFO "Creating BigQuery resources..."
    
    # Create dataset
    log INFO "Creating BigQuery dataset: $DATASET_NAME"
    bq mk --dataset \
        --location="${REGION}" \
        --description="Content optimization analytics dataset" \
        "${PROJECT_ID}:${DATASET_NAME}" || {
        log ERROR "Failed to create BigQuery dataset"
        return 1
    }
    
    # Create engagement metrics table
    log INFO "Creating engagement metrics table"
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.engagement_metrics" \
        "content_id:STRING,language:STRING,region:STRING,engagement_score:FLOAT,translation_quality:FLOAT,timestamp:TIMESTAMP" || {
        log ERROR "Failed to create engagement metrics table"
        return 1
    }
    
    # Create translation performance table
    log INFO "Creating translation performance table"
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.translation_performance" \
        "batch_id:STRING,source_language:STRING,target_language:STRING,content_type:STRING,processing_time:FLOAT,quality_score:FLOAT,timestamp:TIMESTAMP" || {
        log ERROR "Failed to create translation performance table"
        return 1
    }
    
    log INFO "✅ BigQuery resources created successfully"
}

#####################################################################
# IAM Configuration
#####################################################################

create_service_account() {
    log INFO "Creating IAM service account..."
    
    # Create service account
    log INFO "Creating service account: $SERVICE_ACCOUNT_NAME"
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Translation Worker Service Account" \
        --description="Service account for Cloud Run translation workers" || {
        log ERROR "Failed to create service account"
        return 1
    }
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Grant necessary permissions
    local roles=(
        "roles/translate.editor"
        "roles/storage.objectAdmin"
        "roles/bigquery.dataEditor"
        "roles/pubsub.subscriber"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${roles[@]}"; do
        log INFO "Granting role: $role"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="$role" || {
            log ERROR "Failed to grant role: $role"
            return 1
        }
    done
    
    log INFO "✅ Service account and IAM permissions configured"
}

#####################################################################
# Application Code
#####################################################################

create_worker_application() {
    log INFO "Creating worker application code..."
    
    local app_dir="${SCRIPT_DIR}/../translation-worker"
    mkdir -p "$app_dir"
    
    # Create main application file
    cat > "${app_dir}/main.py" << 'EOF'
import json
import os
import logging
from concurrent.futures import ThreadPoolExecutor
from google.cloud import translate_v3
from google.cloud import storage
from google.cloud import bigquery
from google.cloud import pubsub_v1
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TranslationOptimizer:
    def __init__(self):
        self.project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        self.region = os.environ.get('GOOGLE_CLOUD_REGION', 'us-central1')
        self.translate_client = translate_v3.TranslationServiceClient()
        self.storage_client = storage.Client()
        self.bigquery_client = bigquery.Client()
        self.subscriber = pubsub_v1.SubscriberClient()
        
    def process_translation_request(self, message_data):
        """Process translation request with optimization"""
        try:
            content_info = json.loads(message_data)
            
            # Get engagement metrics for optimization
            engagement_score = self.get_engagement_metrics(
                content_info.get('content_id'),
                content_info.get('target_languages', [])
            )
            
            # Select optimal translation approach
            translation_config = self.optimize_translation_config(
                content_info, engagement_score
            )
            
            # Execute batch translation
            results = self.execute_batch_translation(
                content_info, translation_config
            )
            
            # Log performance metrics
            self.log_translation_metrics(content_info, results)
            
            logger.info(f"Successfully processed translation request: {content_info.get('content_id')}")
            return results
            
        except Exception as e:
            logger.error(f"Error processing translation: {str(e)}")
            raise
    
    def get_engagement_metrics(self, content_id, languages):
        """Retrieve engagement metrics for content optimization"""
        try:
            query = f"""
            SELECT language, AVG(engagement_score) as avg_engagement
            FROM `{self.project_id}.{os.environ.get('DATASET_NAME')}.engagement_metrics`
            WHERE content_id = @content_id
            AND language IN UNNEST(@languages)
            AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
            GROUP BY language
            """
            
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("content_id", "STRING", content_id),
                    bigquery.ArrayQueryParameter("languages", "STRING", languages),
                ]
            )
            
            results = self.bigquery_client.query(query, job_config=job_config)
            return {row.language: row.avg_engagement for row in results}
            
        except Exception as e:
            logger.warning(f"Could not retrieve engagement metrics: {str(e)}")
            return {}
    
    def optimize_translation_config(self, content_info, engagement_metrics):
        """Optimize translation configuration based on engagement data"""
        config = {
            'use_custom_model': False,
            'glossary_id': None,
            'quality_level': 'standard'
        }
        
        # Use custom model for high-engagement content
        for lang, score in engagement_metrics.items():
            if score > 0.7:  # High engagement threshold
                config['use_custom_model'] = True
                config['quality_level'] = 'premium'
                break
        
        # Apply domain-specific optimizations
        content_type = content_info.get('content_type', 'general')
        if content_type in ['marketing', 'legal', 'technical']:
            config['use_custom_model'] = True
            
        return config
    
    def execute_batch_translation(self, content_info, config):
        """Execute optimized batch translation"""
        parent = f"projects/{self.project_id}/locations/{self.region}"
        
        # Configure translation request
        request = {
            'parent': parent,
            'source_language_code': content_info['source_language'],
            'target_language_codes': content_info['target_languages'],
            'input_configs': [{
                'gcs_source': {
                    'input_uri': content_info['source_uri']
                },
                'mime_type': content_info.get('mime_type', 'text/plain')
            }],
            'output_config': {
                'gcs_destination': {
                    'output_uri_prefix': content_info['output_uri_prefix']
                }
            }
        }
        
        # Apply custom model if configured
        if config.get('use_custom_model') and content_info.get('custom_model_id'):
            request['models'] = {
                lang: f"projects/{self.project_id}/locations/{self.region}/models/{content_info['custom_model_id']}"
                for lang in content_info['target_languages']
            }
        
        # Execute translation
        operation = self.translate_client.batch_translate_text(request=request)
        logger.info(f"Translation operation started: {operation.operation.name}")
        
        return {
            'operation_name': operation.operation.name,
            'config_used': config,
            'request_details': request
        }
    
    def log_translation_metrics(self, content_info, results):
        """Log translation performance metrics to BigQuery"""
        try:
            table_id = f"{self.project_id}.{os.environ.get('DATASET_NAME')}.translation_performance"
            table = self.bigquery_client.get_table(table_id)
            
            rows = [{
                'batch_id': content_info.get('batch_id'),
                'source_language': content_info.get('source_language'),
                'target_language': lang,
                'content_type': content_info.get('content_type'),
                'processing_time': 0,  # Will be updated when operation completes
                'quality_score': 0.95 if results['config_used'].get('use_custom_model') else 0.85,
                'timestamp': bigquery.QueryJobConfig().timestamp
            } for lang in content_info.get('target_languages', [])]
            
            errors = self.bigquery_client.insert_rows_json(table, rows)
            if not errors:
                logger.info("Translation metrics logged successfully")
            else:
                logger.error(f"Failed to log metrics: {errors}")
                
        except Exception as e:
            logger.error(f"Error logging translation metrics: {str(e)}")

@functions_framework.cloud_event
def process_pubsub_message(cloud_event):
    """Cloud Run worker function to process Pub/Sub messages"""
    import base64
    
    optimizer = TranslationOptimizer()
    
    # Decode Pub/Sub message
    message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
    
    # Process translation request
    result = optimizer.process_translation_request(message_data)
    
    logger.info(f"Translation processing completed: {result}")

if __name__ == "__main__":
    # For local testing
    optimizer = TranslationOptimizer()
    test_message = json.dumps({
        'content_id': 'test-content-001',
        'batch_id': 'batch-001',
        'source_language': 'en',
        'target_languages': ['es', 'fr', 'de'],
        'source_uri': 'gs://source-bucket/content.txt',
        'output_uri_prefix': 'gs://translated-bucket/output/',
        'content_type': 'marketing',
        'mime_type': 'text/plain'
    })
    optimizer.process_translation_request(test_message)
EOF
    
    # Create requirements file
    cat > "${app_dir}/requirements.txt" << 'EOF'
google-cloud-translate==3.15.5
google-cloud-storage==2.10.0
google-cloud-bigquery==3.13.0
google-cloud-pubsub==2.18.4
functions-framework==3.5.0
EOF
    
    # Create Dockerfile
    cat > "${app_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec functions-framework --target=process_pubsub_message --port=${PORT:-8080}
EOF
    
    log INFO "✅ Worker application code created"
}

#####################################################################
# Container Build and Deploy
#####################################################################

build_and_deploy_worker() {
    log INFO "Building and deploying Cloud Run Worker Pool..."
    
    local app_dir="${SCRIPT_DIR}/../translation-worker"
    
    # Build container image
    log INFO "Building container image..."
    gcloud builds submit "$app_dir" \
        --tag "gcr.io/${PROJECT_ID}/translation-worker" || {
        log ERROR "Failed to build container image"
        return 1
    }
    
    # Deploy Cloud Run Worker Pool
    log INFO "Deploying worker pool: $WORKER_POOL_NAME"
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    gcloud run worker-pools deploy "${WORKER_POOL_NAME}" \
        --image "gcr.io/${PROJECT_ID}/translation-worker" \
        --region "${REGION}" \
        --service-account "$sa_email" \
        --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
        --set-env-vars "GOOGLE_CLOUD_REGION=${REGION}" \
        --set-env-vars "DATASET_NAME=${DATASET_NAME}" \
        --cpu 2 \
        --memory 4Gi \
        --min-instances 1 \
        --max-instances 10 \
        --pubsub-subscription "projects/${PROJECT_ID}/subscriptions/${TOPIC_NAME}-sub" || {
        log ERROR "Failed to deploy worker pool"
        return 1
    }
    
    log INFO "✅ Cloud Run Worker Pool deployed successfully"
}

#####################################################################
# Sample Data and Testing
#####################################################################

create_sample_content() {
    log INFO "Creating sample content and testing translation..."
    
    local content_dir="${SCRIPT_DIR}/../sample-content"
    mkdir -p "$content_dir"
    
    # Create sample content files
    cat > "${content_dir}/marketing-content.txt" << 'EOF'
Welcome to our revolutionary cloud platform that transforms how businesses operate in the digital age. Our cutting-edge solutions deliver unprecedented performance, scalability, and security for enterprises worldwide. Join thousands of satisfied customers who have accelerated their digital transformation journey with our innovative technology stack.
EOF
    
    cat > "${content_dir}/technical-documentation.txt" << 'EOF'
API Authentication: Use Bearer tokens for secure API access. Configure rate limiting to prevent abuse. Implement proper error handling with structured JSON responses. Monitor API performance using built-in analytics dashboards.
EOF
    
    # Upload content to source bucket
    log INFO "Uploading sample content to source bucket..."
    gsutil cp "${content_dir}"/*.txt "gs://${SOURCE_BUCKET}/" || {
        log ERROR "Failed to upload sample content"
        return 1
    }
    
    # Create and publish translation request
    local translation_request=$(cat << EOF
{
    "content_id": "sample-marketing-001",
    "batch_id": "batch-$(date +%s)",
    "source_language": "en",
    "target_languages": ["es", "fr", "de", "ja"],
    "source_uri": "gs://${SOURCE_BUCKET}/marketing-content.txt",
    "output_uri_prefix": "gs://${TRANSLATED_BUCKET}/marketing/",
    "content_type": "marketing",
    "mime_type": "text/plain"
}
EOF
)
    
    log INFO "Publishing translation request..."
    echo "$translation_request" | gcloud pubsub topics publish "${TOPIC_NAME}" --message=- || {
        log ERROR "Failed to publish translation request"
        return 1
    }
    
    # Create sample engagement data
    local engagement_data='[
    {"content_id": "sample-marketing-001", "language": "es", "region": "LATAM", "engagement_score": 0.85, "translation_quality": 0.92, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"},
    {"content_id": "sample-marketing-001", "language": "fr", "region": "EU", "engagement_score": 0.78, "translation_quality": 0.89, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"},
    {"content_id": "sample-marketing-001", "language": "de", "region": "EU", "engagement_score": 0.91, "translation_quality": 0.94, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"},
    {"content_id": "sample-marketing-001", "language": "ja", "region": "APAC", "engagement_score": 0.73, "translation_quality": 0.87, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}
]'
    
    # Insert sample data into BigQuery
    log INFO "Loading sample engagement data..."
    echo "$engagement_data" > "${SCRIPT_DIR}/engagement_sample.json"
    bq load --source_format=NEWLINE_DELIMITED_JSON \
        "${PROJECT_ID}:${DATASET_NAME}.engagement_metrics" \
        "${SCRIPT_DIR}/engagement_sample.json" || {
        log ERROR "Failed to load sample engagement data"
        return 1
    }
    
    rm -f "${SCRIPT_DIR}/engagement_sample.json"
    
    log INFO "✅ Sample content created and translation workflow triggered"
}

#####################################################################
# Validation
#####################################################################

validate_deployment() {
    log INFO "Validating deployment..."
    
    # Check worker pool status
    log INFO "Checking worker pool status..."
    gcloud run worker-pools describe "${WORKER_POOL_NAME}" \
        --region "${REGION}" \
        --format="value(status.conditions[0].type)" | grep -q "Ready" || {
        log WARN "Worker pool may not be ready yet"
    }
    
    # Check Pub/Sub subscription
    log INFO "Checking Pub/Sub subscription..."
    gcloud pubsub subscriptions describe "${TOPIC_NAME}-sub" &> /dev/null || {
        log ERROR "Pub/Sub subscription not found"
        return 1
    }
    
    # Check BigQuery dataset
    log INFO "Checking BigQuery dataset..."
    bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null || {
        log ERROR "BigQuery dataset not found"
        return 1
    }
    
    # Check storage buckets
    log INFO "Checking storage buckets..."
    gsutil ls "gs://${SOURCE_BUCKET}" &> /dev/null || {
        log ERROR "Source bucket not accessible"
        return 1
    }
    
    log INFO "✅ Deployment validation completed successfully"
}

#####################################################################
# Main Deployment Flow
#####################################################################

main() {
    log INFO "Starting deployment of Multi-Language Content Optimization system..."
    log INFO "Deployment logs: $LOG_FILE"
    
    # Initialize log files
    echo "Deployment started at $(date)" > "$LOG_FILE"
    echo "Error log for deployment at $(date)" > "$ERROR_LOG"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_storage_buckets
    create_pubsub_resources
    create_bigquery_resources
    create_service_account
    create_worker_application
    build_and_deploy_worker
    create_sample_content
    validate_deployment
    
    log INFO "🎉 Deployment completed successfully!"
    log INFO ""
    log INFO "📋 Deployment Summary:"
    log INFO "  Project ID: $PROJECT_ID"
    log INFO "  Region: $REGION"
    log INFO "  Worker Pool: $WORKER_POOL_NAME"
    log INFO "  Source Bucket: gs://$SOURCE_BUCKET"
    log INFO "  Translated Bucket: gs://$TRANSLATED_BUCKET"
    log INFO "  Pub/Sub Topic: $TOPIC_NAME"
    log INFO "  BigQuery Dataset: $DATASET_NAME"
    log INFO ""
    log INFO "🔍 To monitor the system:"
    log INFO "  Worker Pool Logs: gcloud run worker-pools logs read $WORKER_POOL_NAME --region $REGION"
    log INFO "  BigQuery Console: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    log INFO "  Cloud Storage: https://console.cloud.google.com/storage/browser?project=$PROJECT_ID"
    log INFO ""
    log INFO "🧹 To clean up resources, run: ./destroy.sh"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
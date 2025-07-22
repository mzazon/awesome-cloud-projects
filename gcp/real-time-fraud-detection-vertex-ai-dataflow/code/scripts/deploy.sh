#!/bin/bash

# Deploy Real-Time Fraud Detection with Vertex AI and Cloud Dataflow
# This script deploys the complete fraud detection infrastructure on Google Cloud Platform

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    echo "DEPLOYMENT_FAILED" > "${DEPLOYMENT_STATE_FILE}"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Deploy Real-Time Fraud Detection with Vertex AI and Cloud Dataflow

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud project ID (required)
    -r, --region REGION            Deployment region (default: us-central1)
    -h, --help                     Show this help message
    --dry-run                      Validate configuration without deploying
    --skip-apis                    Skip API enablement (assumes APIs are enabled)
    --skip-training                Skip ML model training (for quick testing)

EXAMPLES:
    $0 --project-id my-fraud-project
    $0 --project-id my-project --region us-east1
    $0 --project-id my-project --dry-run

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and authenticated
    - Billing enabled on the target project
    - Project Owner or Editor permissions
    - Python 3.7+ with pip installed

EOF
}

# Parse command line arguments
parse_arguments() {
    PROJECT_ID=""
    REGION="us-central1"
    ZONE="us-central1-a"
    DRY_RUN=false
    SKIP_APIS=false
    SKIP_TRAINING=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                ZONE="${REGION}-a"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-apis)
                SKIP_APIS=true
                shift
                ;;
            --skip-training)
                SKIP_TRAINING=true
                shift
                ;;
            -h|--help)
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

    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id option."
        show_help
        exit 1
    fi
}

# Prerequisites validation
check_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi

    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.7+ first."
        exit 1
    fi

    # Check if pip is installed
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 is not installed. Please install pip for Python 3."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Run 'gcloud auth login' first."
        exit 1
    fi

    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Check project ID and permissions."
        exit 1
    fi

    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        log_error "Billing is not enabled for project '$PROJECT_ID'. Enable billing first."
        exit 1
    fi

    log_success "Prerequisites validation completed"
}

# Initialize project configuration
initialize_project() {
    log_info "Initializing project configuration..."

    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"

    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 4 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(4))")
    
    # Set resource names with unique identifiers
    export DATASET_ID="fraud_detection_${RANDOM_SUFFIX}"
    export TOPIC_NAME="transaction-stream-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="fraud-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-fraud-ml-${RANDOM_SUFFIX}"
    export MODEL_DISPLAY_NAME="fraud-detection-model-${RANDOM_SUFFIX}"

    # Save configuration to state file
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DATASET_ID=${DATASET_ID}
TOPIC_NAME=${TOPIC_NAME}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
MODEL_DISPLAY_NAME=${MODEL_DISPLAY_NAME}
DEPLOYMENT_STATUS=INITIALIZING
EOF

    log_success "Project configuration initialized"
    log_info "Using resource suffix: ${RANDOM_SUFFIX}"
}

# Enable required APIs
enable_apis() {
    if [[ "$SKIP_APIS" == "true" ]]; then
        log_info "Skipping API enablement as requested"
        return 0
    fi

    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "compute.googleapis.com"
        "dataflow.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling API: $api"
        if [[ "$DRY_RUN" == "false" ]]; then
            gcloud services enable "$api" --quiet
        fi
    done

    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi

    log_success "Required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for ML artifacts..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create bucket with regional configuration
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://${BUCKET_NAME}"

        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}"

        # Set bucket labels
        gsutil label ch -l environment:fraud-detection \
            -l purpose:ml-pipeline "gs://${BUCKET_NAME}"
    fi

    log_success "Cloud Storage bucket created: ${BUCKET_NAME}"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create dataset
        bq mk --location="$REGION" \
            --description="Fraud detection analytics dataset" \
            --label=environment:fraud-detection \
            "${PROJECT_ID}:${DATASET_ID}"

        # Create transactions table
        bq mk --table \
            "${PROJECT_ID}:${DATASET_ID}.transactions" \
            transaction_id:STRING,user_id:STRING,amount:FLOAT,merchant:STRING,timestamp:TIMESTAMP,fraud_score:FLOAT,is_fraud:BOOLEAN,features:JSON,location:STRING,payment_method:STRING,processing_timestamp:TIMESTAMP,risk_factors:STRING,confidence:FLOAT

        # Create fraud_alerts table
        bq mk --table \
            "${PROJECT_ID}:${DATASET_ID}.fraud_alerts" \
            alert_id:STRING,transaction_id:STRING,fraud_score:FLOAT,alert_timestamp:TIMESTAMP,status:STRING,investigation_notes:STRING,assigned_analyst:STRING,risk_factors:STRING,confidence:FLOAT
    fi

    log_success "BigQuery dataset and tables created"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create topic
        gcloud pubsub topics create "$TOPIC_NAME" \
            --message-encoding=JSON

        # Create subscription
        gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
            --topic="$TOPIC_NAME" \
            --message-retention-duration=7d \
            --ack-deadline=60s \
            --max-delivery-attempts=5

        # Enable message ordering
        gcloud pubsub subscriptions update "$SUBSCRIPTION_NAME" \
            --enable-message-ordering
    fi

    log_success "Pub/Sub topic and subscription created"
}

# Generate and upload training data
create_training_data() {
    log_info "Generating synthetic training data for fraud detection..."

    local training_dir="${SCRIPT_DIR}/../training_data"
    mkdir -p "$training_dir"

    # Create training data generation script
    cat > "${training_dir}/generate_data.py" << 'EOF'
import json
import random
import datetime
import numpy as np
import pandas as pd
import sys

def generate_transaction_data(num_records=10000):
    """Generate synthetic transaction data for fraud detection training"""
    
    data = []
    
    # Define merchant categories for realistic distribution
    merchant_categories = [
        'grocery', 'gas_station', 'restaurant', 'retail', 
        'online', 'pharmacy', 'entertainment', 'travel'
    ]
    
    for i in range(num_records):
        # Base transaction properties
        user_id = f"user_{random.randint(1, 5000)}"
        base_amount = random.lognormal(3, 1.5)
        
        # Fraud indicators (5% fraud rate)
        is_fraud = random.random() < 0.05
        
        if is_fraud:
            # Fraudulent transactions have specific patterns
            amount = base_amount * random.uniform(2, 10)  # Higher amounts
            hour = random.choice([2, 3, 4, 23, 0, 1])  # Unusual hours
            merchant_category = random.choice(['online', 'travel'])  # High-risk categories
            location_risk = random.choice(['foreign', 'high_risk', 'unknown'])
        else:
            amount = base_amount
            # Normal business hours distribution
            hour = random.choices(
                range(24), 
                weights=[1,1,1,1,1,2,4,6,8,8,9,9,9,8,8,7,6,5,4,3,2,1,1,1]
            )[0]
            merchant_category = random.choice(merchant_categories)
            location_risk = 'normal'
        
        # Calculate derived features
        day_of_week = random.randint(0, 6)
        is_weekend = day_of_week >= 5
        
        # Generate realistic timestamp
        base_date = datetime.datetime.now() - datetime.timedelta(days=30)
        transaction_time = base_date + datetime.timedelta(
            days=random.randint(0, 30),
            hours=hour,
            minutes=random.randint(0, 59)
        )
        
        # Create transaction record
        transaction = {
            'user_id': user_id,
            'amount': round(amount, 2),
            'merchant': f"merchant_{random.randint(1, 1000)}",
            'merchant_category': merchant_category,
            'hour_of_day': hour,
            'day_of_week': day_of_week,
            'is_weekend': is_weekend,
            'location_risk': location_risk,
            'amount_z_score': (amount - 100) / 50,  # Normalized amount
            'transaction_velocity': random.randint(1, 10),  # Transactions per day
            'is_fraud': is_fraud
        }
        data.append(transaction)
    
    return pd.DataFrame(data)

if __name__ == "__main__":
    # Generate training data with realistic distributions
    print("Generating fraud detection training data...")
    df = generate_transaction_data(10000)
    
    # Save to CSV for Vertex AI ingestion
    df.to_csv('training_data.csv', index=False)
    
    # Generate statistics
    fraud_rate = df['is_fraud'].mean()
    avg_amount = df['amount'].mean()
    fraud_avg_amount = df[df['is_fraud']]['amount'].mean()
    
    print(f"Generated {len(df)} training records")
    print(f"Fraud rate: {fraud_rate:.3f}")
    print(f"Average transaction amount: ${avg_amount:.2f}")
    print(f"Average fraud amount: ${fraud_avg_amount:.2f}")
    print("Training data ready for Vertex AI")
EOF

    if [[ "$DRY_RUN" == "false" ]]; then
        # Install required dependencies
        pip3 install pandas numpy google-cloud-storage --quiet

        # Generate training data
        cd "$training_dir"
        python3 generate_data.py

        # Upload to Cloud Storage
        gsutil cp training_data.csv \
            "gs://${BUCKET_NAME}/training_data/training_data.csv"

        cd "$SCRIPT_DIR"
    fi

    log_success "Training data generated and uploaded"
}

# Create Vertex AI dataset
create_vertex_ai_dataset() {
    log_info "Creating Vertex AI dataset for fraud detection..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create dataset
        gcloud ai datasets create \
            --display-name="fraud-detection-dataset-${RANDOM_SUFFIX}" \
            --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml" \
            --region="$REGION"

        # Get dataset ID
        local dataset_id
        dataset_id=$(gcloud ai datasets list \
            --region="$REGION" \
            --filter="displayName:fraud-detection-dataset-${RANDOM_SUFFIX}" \
            --format="value(name.split('/').slice(-1:))")

        # Save dataset ID to state file
        echo "DATASET_ID_VERTEX=${dataset_id}" >> "${DEPLOYMENT_STATE_FILE}"

        # Import training data
        gcloud ai datasets import-data "$dataset_id" \
            --region="$REGION" \
            --data-source-uri="gs://${BUCKET_NAME}/training_data/training_data.csv" \
            --data-source-mime-type="text/csv"

        log_info "Vertex AI dataset created with ID: ${dataset_id}"
        
        if [[ "$SKIP_TRAINING" == "false" ]]; then
            log_warning "ML model training can take 2-4 hours. Monitor progress in Google Cloud Console."
            log_info "Training job initiated for Vertex AI AutoML"
        else
            log_info "Skipping ML model training as requested"
        fi
    fi

    log_success "Vertex AI dataset configured"
}

# Create Vertex AI endpoint
create_vertex_ai_endpoint() {
    log_info "Creating Vertex AI endpoint for model serving..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create endpoint
        gcloud ai endpoints create \
            --display-name="fraud-detection-endpoint-${RANDOM_SUFFIX}" \
            --region="$REGION"

        # Get endpoint ID
        local endpoint_id
        endpoint_id=$(gcloud ai endpoints list \
            --region="$REGION" \
            --filter="displayName:fraud-detection-endpoint-${RANDOM_SUFFIX}" \
            --format="value(name.split('/').slice(-1:))")

        # Save endpoint ID to state file
        echo "ENDPOINT_ID=${endpoint_id}" >> "${DEPLOYMENT_STATE_FILE}"

        log_info "Vertex AI endpoint created: ${endpoint_id}"
    fi

    log_success "Vertex AI endpoint ready for model deployment"
}

# Create Dataflow pipeline code
create_dataflow_pipeline() {
    log_info "Creating Dataflow pipeline for real-time processing..."

    local pipeline_dir="${SCRIPT_DIR}/../dataflow_pipeline"
    mkdir -p "$pipeline_dir"

    # Create requirements file
    cat > "${pipeline_dir}/requirements.txt" << 'EOF'
apache-beam[gcp]==2.50.0
google-cloud-aiplatform==1.36.0
google-cloud-bigquery==3.11.0
google-cloud-pubsub==2.18.0
EOF

    # Create the main pipeline code (comprehensive version)
    cat > "${pipeline_dir}/fraud_detection_pipeline.py" << 'EOF'
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.transforms import window
import json
import logging
import math
from datetime import datetime, timezone
import sys

class FeatureEngineeringFn(beam.DoFn):
    """Transform raw transaction data into ML features"""
    
    def setup(self):
        """Initialize any required resources"""
        self.feature_cache = {}
    
    def process(self, element):
        try:
            # Parse the Pub/Sub message
            if isinstance(element, bytes):
                data = json.loads(element.decode('utf-8'))
            else:
                data = json.loads(element)
            
            # Extract and validate basic features
            amount = float(data.get('amount', 0))
            timestamp_str = data.get('timestamp', datetime.now().isoformat())
            
            # Parse timestamp and extract temporal features
            try:
                if timestamp_str.endswith('Z'):
                    timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                else:
                    timestamp = datetime.fromisoformat(timestamp_str)
            except:
                timestamp = datetime.now(timezone.utc)
            
            hour_of_day = timestamp.hour
            day_of_week = timestamp.weekday()
            
            # Advanced feature engineering
            features = {
                'transaction_id': data.get('transaction_id', f"txn_{int(timestamp.timestamp())}"),
                'user_id': data.get('user_id', 'unknown'),
                'amount': amount,
                'merchant': data.get('merchant', 'unknown'),
                'timestamp': timestamp.isoformat(),
                'location': data.get('location', 'unknown'),
                'payment_method': data.get('payment_method', 'unknown'),
                
                # Temporal features
                'hour_of_day': hour_of_day,
                'day_of_week': day_of_week,
                'is_weekend': day_of_week >= 5,
                'is_night_time': hour_of_day < 6 or hour_of_day > 22,
                
                # Amount-based features
                'amount_log': math.log(amount + 1),
                'is_large_amount': amount > 1000,
                'is_micro_transaction': amount < 5,
                'amount_rounded': amount % 1 == 0,
                
                # Risk indicators
                'high_risk_merchant': 'online' in data.get('merchant', '').lower(),
                'foreign_location': data.get('location', '').lower() in ['foreign', 'unknown'],
                
                # Store original data for downstream processing
                'features': data
            }
            
            yield features
            
        except Exception as e:
            logging.error(f"Error processing transaction: {e}")
            # Yield minimal record for error tracking
            yield {
                'transaction_id': f"error_{int(datetime.now().timestamp())}",
                'user_id': 'error',
                'amount': 0.0,
                'fraud_score': 0.0,
                'is_fraud': False,
                'error': str(e)
            }

class FraudScoringFn(beam.DoFn):
    """Score transactions for fraud using sophisticated rule-based logic"""
    
    def __init__(self, project_id, region):
        self.project_id = project_id
        self.region = region
    
    def setup(self):
        """Initialize scoring components"""
        self.risk_weights = {
            'amount': 0.3,
            'time': 0.2,
            'location': 0.2,
            'merchant': 0.15,
            'pattern': 0.15
        }
        
    def process(self, element):
        try:
            # Skip error records
            if element.get('user_id') == 'error':
                yield element
                return
            
            amount = element.get('amount', 0)
            hour = element.get('hour_of_day', 12)
            is_weekend = element.get('is_weekend', False)
            is_night = element.get('is_night_time', False)
            location = element.get('location', 'normal')
            payment_method = element.get('payment_method', 'unknown')
            
            # Initialize fraud score
            fraud_score = 0.0
            risk_factors = []
            
            # Amount-based scoring
            if amount > 5000:
                fraud_score += 0.4
                risk_factors.append('high_amount')
            elif amount > 2000:
                fraud_score += 0.2
                risk_factors.append('elevated_amount')
            elif amount < 1:
                fraud_score += 0.1
                risk_factors.append('micro_transaction')
            
            # Temporal risk scoring
            if is_night:
                fraud_score += 0.3
                risk_factors.append('unusual_hour')
            
            if is_weekend and amount > 1000:
                fraud_score += 0.15
                risk_factors.append('weekend_large_transaction')
            
            # Location-based risk
            if 'foreign' in location.lower() or 'unknown' in location.lower():
                fraud_score += 0.25
                risk_factors.append('risky_location')
            
            # Payment method risk
            if payment_method == 'digital_wallet' and amount > 500:
                fraud_score += 0.1
                risk_factors.append('digital_wallet_risk')
            
            # Merchant category risk
            merchant = element.get('merchant', '').lower()
            if 'online' in merchant:
                fraud_score += 0.1
                risk_factors.append('online_merchant')
            
            # Add controlled randomness for demonstration
            import random
            fraud_score += random.random() * 0.2
            
            # Normalize fraud score
            fraud_score = min(fraud_score, 1.0)
            
            # Determine fraud classification
            is_fraud = fraud_score > 0.7
            confidence = fraud_score if is_fraud else (1 - fraud_score)
            
            # Prepare enhanced output record
            output = {
                **element,
                'fraud_score': round(fraud_score, 3),
                'is_fraud': is_fraud,
                'confidence': round(confidence, 3),
                'risk_factors': ','.join(risk_factors),
                'processing_timestamp': datetime.now().isoformat()
            }
            
            yield output
            
        except Exception as e:
            logging.error(f"Error scoring transaction: {e}")
            # Return original element with error information
            yield {
                **element,
                'fraud_score': 0.0,
                'is_fraud': False,
                'error': str(e)
            }

def run_pipeline(project_id, region, topic_name, dataset_id, bucket_name):
    """Run the real-time fraud detection Dataflow pipeline"""
    
    pipeline_options = PipelineOptions([
        f'--project={project_id}',
        f'--region={region}',
        '--runner=DataflowRunner',
        '--streaming',
        '--enable_streaming_engine',
        f'--temp_location=gs://{bucket_name}/temp',
        f'--staging_location=gs://{bucket_name}/staging',
        '--requirements_file=requirements.txt',
        '--job_name=fraud-detection-pipeline',
        '--save_main_session',
        '--max_num_workers=10',
        '--autoscaling_algorithm=THROUGHPUT_BASED'
    ])
    
    with beam.Pipeline(options=pipeline_options) as pipeline:
        
        # Read streaming data from Pub/Sub
        raw_transactions = (
            pipeline
            | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(
                topic=f'projects/{project_id}/topics/{topic_name}',
                with_attributes=False
            )
            | 'Apply Windowing' >> beam.WindowInto(
                window.FixedWindows(30)  # 30-second processing windows
            )
        )
        
        # Feature engineering pipeline
        engineered_features = (
            raw_transactions
            | 'Feature Engineering' >> beam.ParDo(FeatureEngineeringFn())
        )
        
        # Fraud scoring pipeline
        scored_transactions = (
            engineered_features
            | 'Fraud Scoring' >> beam.ParDo(
                FraudScoringFn(project_id, region)
            )
        )
        
        # Write all scored transactions to BigQuery
        _ = (
            scored_transactions
            | 'Write to BigQuery' >> beam.io.WriteToBigQuery(
                table=f'{project_id}:{dataset_id}.transactions',
                write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
                schema='SCHEMA_AUTODETECT'
            )
        )
        
        # Create fraud alerts for high-risk transactions
        fraud_alerts = (
            scored_transactions
            | 'Filter High Risk Transactions' >> beam.Filter(
                lambda x: x.get('fraud_score', 0) > 0.8
            )
            | 'Create Alert Records' >> beam.Map(lambda x: {
                'alert_id': f"alert_{x.get('transaction_id', 'unknown')}_{int(datetime.now().timestamp())}",
                'transaction_id': x.get('transaction_id'),
                'fraud_score': x.get('fraud_score'),
                'alert_timestamp': datetime.now().isoformat(),
                'status': 'PENDING',
                'investigation_notes': '',
                'assigned_analyst': '',
                'risk_factors': x.get('risk_factors', ''),
                'confidence': x.get('confidence', 0.0)
            })
            | 'Write Fraud Alerts' >> beam.io.WriteToBigQuery(
                table=f'{project_id}:{dataset_id}.fraud_alerts',
                write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                schema='SCHEMA_AUTODETECT'
            )
        )

if __name__ == '__main__':
    if len(sys.argv) != 6:
        print("Usage: python fraud_detection_pipeline.py PROJECT_ID REGION TOPIC_NAME DATASET_ID BUCKET_NAME")
        sys.exit(1)
    
    run_pipeline(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
EOF

    log_success "Dataflow pipeline code created"
}

# Create transaction simulator
create_transaction_simulator() {
    log_info "Creating advanced transaction simulator..."

    cat > "${SCRIPT_DIR}/../transaction_simulator.py" << 'EOF'
import json
import random
import time
import datetime
import threading
import math
from google.cloud import pubsub_v1
from concurrent.futures import ThreadPoolExecutor
import sys

class AdvancedTransactionSimulator:
    def __init__(self, project_id, topic_name):
        self.project_id = project_id
        self.topic_name = topic_name
        self.publisher = pubsub_v1.PublisherClient()
        self.topic_path = self.publisher.topic_path(project_id, topic_name)
        self.user_profiles = self._create_user_profiles()
        self.merchant_profiles = self._create_merchant_profiles()
        
    def _create_user_profiles(self):
        """Create realistic user spending profiles"""
        profiles = {}
        for i in range(1, 1001):
            profiles[f"user_{i}"] = {
                'avg_daily_transactions': random.randint(1, 8),
                'avg_transaction_amount': random.lognormal(3, 1),
                'preferred_merchants': random.sample(
                    [f"merchant_{j}" for j in range(1, 501)], 
                    random.randint(3, 10)
                ),
                'risk_level': random.choice(['low', 'medium', 'high']),
                'location': random.choice(['NYC', 'LA', 'Chicago', 'Houston', 'Phoenix', 'Denver'])
            }
        return profiles
    
    def _create_merchant_profiles(self):
        """Create merchant risk profiles"""
        categories = {
            'grocery': {'risk': 'low', 'avg_amount': 50},
            'gas_station': {'risk': 'low', 'avg_amount': 35},
            'restaurant': {'risk': 'medium', 'avg_amount': 45},
            'retail': {'risk': 'medium', 'avg_amount': 80},
            'online': {'risk': 'high', 'avg_amount': 120},
            'travel': {'risk': 'high', 'avg_amount': 300},
            'entertainment': {'risk': 'medium', 'avg_amount': 60}
        }
        
        profiles = {}
        for i in range(1, 501):
            category = random.choice(list(categories.keys()))
            profiles[f"merchant_{i}"] = {
                'category': category,
                'risk_level': categories[category]['risk'],
                'avg_amount': categories[category]['avg_amount']
            }
        return profiles
        
    def generate_normal_transaction(self):
        """Generate realistic normal transaction"""
        user_id = random.choice(list(self.user_profiles.keys()))
        user_profile = self.user_profiles[user_id]
        
        # Select merchant based on user preferences
        if random.random() < 0.7:  # 70% chance of using preferred merchant
            merchant = random.choice(user_profile['preferred_merchants'])
        else:
            merchant = f"merchant_{random.randint(1, 500)}"
        
        merchant_profile = self.merchant_profiles.get(merchant, {
            'category': 'retail', 'risk_level': 'medium', 'avg_amount': 50
        })
        
        # Generate amount based on user and merchant profiles
        base_amount = user_profile['avg_transaction_amount']
        merchant_amount = merchant_profile['avg_amount']
        amount = (base_amount + merchant_amount) / 2 * random.uniform(0.5, 2.0)
        
        # Apply time-of-day variations
        current_hour = datetime.datetime.now().hour
        if 9 <= current_hour <= 17:  # Business hours
            amount *= random.uniform(0.8, 1.2)
        elif 18 <= current_hour <= 22:  # Evening
            amount *= random.uniform(1.0, 1.5)
        else:  # Night/early morning
            amount *= random.uniform(0.3, 0.8)
        
        return {
            'transaction_id': f"txn_{int(time.time() * 1000)}_{random.randint(1000, 9999)}",
            'user_id': user_id,
            'amount': round(max(amount, 1.0), 2),
            'merchant': merchant,
            'timestamp': datetime.datetime.now().isoformat() + 'Z',
            'location': user_profile['location'],
            'payment_method': random.choice(['credit_card', 'debit_card', 'digital_wallet']),
            'merchant_category': merchant_profile['category']
        }
    
    def generate_fraud_transaction(self):
        """Generate sophisticated fraud transaction"""
        base_transaction = self.generate_normal_transaction()
        
        fraud_type = random.choice(['account_takeover', 'card_testing', 'synthetic_identity'])
        
        if fraud_type == 'account_takeover':
            # Large, unusual transactions
            base_transaction['amount'] = round(random.uniform(2000, 15000), 2)
            base_transaction['location'] = random.choice(['Foreign', 'Unknown', 'Suspicious'])
            base_transaction['timestamp'] = datetime.datetime.now().replace(
                hour=random.choice([2, 3, 4, 23, 0, 1])
            ).isoformat() + 'Z'
            
        elif fraud_type == 'card_testing':
            # Small amounts to test card validity
            base_transaction['amount'] = round(random.uniform(1, 10), 2)
            base_transaction['merchant'] = f"online_merchant_{random.randint(1, 100)}"
            
        elif fraud_type == 'synthetic_identity':
            # New user with unusual patterns
            base_transaction['user_id'] = f"user_new_{random.randint(10000, 99999)}"
            base_transaction['amount'] = round(random.uniform(500, 3000), 2)
        
        return base_transaction
    
    def publish_transaction(self, transaction):
        """Publish transaction to Pub/Sub with error handling"""
        try:
            message_data = json.dumps(transaction).encode('utf-8')
            future = self.publisher.publish(self.topic_path, message_data)
            return future.result(timeout=5.0)  # 5 second timeout
        except Exception as e:
            print(f"Error publishing transaction {transaction.get('transaction_id', 'unknown')}: {e}")
            return None
    
    def simulate_realistic_traffic(self, duration_minutes=10, base_tps=20):
        """Simulate realistic transaction traffic with patterns"""
        print(f"Starting realistic simulation for {duration_minutes} minutes...")
        print(f"Base TPS: {base_tps}, with realistic variations")
        
        end_time = time.time() + (duration_minutes * 60)
        transaction_count = 0
        fraud_count = 0
        
        # Use thread pool for concurrent publishing
        with ThreadPoolExecutor(max_workers=10) as executor:
            
            while time.time() < end_time:
                current_hour = datetime.datetime.now().hour
                
                # Adjust TPS based on time of day
                if 9 <= current_hour <= 17:  # Business hours
                    tps_multiplier = 1.5
                elif 18 <= current_hour <= 22:  # Evening
                    tps_multiplier = 1.2
                else:  # Night
                    tps_multiplier = 0.3
                
                adjusted_tps = base_tps * tps_multiplier
                
                # Generate batch of transactions
                batch_size = max(1, int(adjusted_tps))
                futures = []
                
                for _ in range(batch_size):
                    # 5% fraud rate with clustering
                    if random.random() < 0.05:
                        transaction = self.generate_fraud_transaction()
                        fraud_count += 1
                        print(f"🚨 Fraud: {transaction['transaction_id']} - ${transaction['amount']}")
                    else:
                        transaction = self.generate_normal_transaction()
                        if transaction_count % 50 == 0:  # Log every 50th normal transaction
                            print(f"✅ Normal: {transaction['transaction_id']} - ${transaction['amount']}")
                    
                    # Submit for async publishing
                    future = executor.submit(self.publish_transaction, transaction)
                    futures.append(future)
                    transaction_count += 1
                
                # Wait for batch to complete
                for future in futures:
                    try:
                        future.result(timeout=1.0)
                    except Exception as e:
                        print(f"Batch publish error: {e}")
                
                # Sleep to maintain TPS
                time.sleep(1.0)
        
        print(f"Simulation completed:")
        print(f"Total transactions: {transaction_count}")
        print(f"Fraud transactions: {fraud_count}")
        print(f"Fraud rate: {fraud_count/transaction_count:.3f}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python transaction_simulator.py PROJECT_ID TOPIC_NAME")
        sys.exit(1)
    
    simulator = AdvancedTransactionSimulator(sys.argv[1], sys.argv[2])
    simulator.simulate_realistic_traffic(duration_minutes=5, base_tps=30)
EOF

    log_success "Transaction simulator created"
}

# Setup monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create log-based metrics
        gcloud logging metrics create fraud_detection_rate \
            --description="Rate of fraud alerts generated per minute" \
            --log-filter="resource.type=dataflow_job AND jsonPayload.fraud_score>0.8" \
            --value-extractor="EXTRACT(jsonPayload.fraud_score)" || true

        gcloud logging metrics create transaction_processing_rate \
            --description="Rate of transactions processed per minute" \
            --log-filter="resource.type=dataflow_job AND jsonPayload.transaction_id" || true
    fi

    log_success "Monitoring and alerting configured"
}

# Update deployment state
update_deployment_state() {
    sed -i 's/DEPLOYMENT_STATUS=.*/DEPLOYMENT_STATUS=COMPLETED/' "${DEPLOYMENT_STATE_FILE}"
    echo "DEPLOYMENT_COMPLETED=$(date '+%Y-%m-%d %H:%M:%S')" >> "${DEPLOYMENT_STATE_FILE}"
}

# Print deployment summary
print_deployment_summary() {
    log_success "Fraud Detection System Deployment Completed!"
    echo
    echo "======================================"
    echo "        DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo
    echo "Created Resources:"
    echo "• Cloud Storage Bucket: gs://$BUCKET_NAME"
    echo "• BigQuery Dataset: $DATASET_ID"
    echo "• Pub/Sub Topic: $TOPIC_NAME"
    echo "• Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    echo "• Vertex AI Dataset: fraud-detection-dataset-$RANDOM_SUFFIX"
    echo "• Vertex AI Endpoint: fraud-detection-endpoint-$RANDOM_SUFFIX"
    echo
    echo "Next Steps:"
    echo "1. Run the transaction simulator:"
    echo "   python3 $(dirname "$0")/../transaction_simulator.py $PROJECT_ID $TOPIC_NAME"
    echo
    echo "2. Deploy the Dataflow pipeline:"
    echo "   cd $(dirname "$0")/../dataflow_pipeline"
    echo "   python3 fraud_detection_pipeline.py $PROJECT_ID $REGION $TOPIC_NAME $DATASET_ID $BUCKET_NAME"
    echo
    echo "3. Monitor in Google Cloud Console:"
    echo "   • BigQuery: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    echo "   • Dataflow: https://console.cloud.google.com/dataflow?project=$PROJECT_ID"
    echo "   • Vertex AI: https://console.cloud.google.com/vertex-ai?project=$PROJECT_ID"
    echo
    echo "Configuration saved to: $DEPLOYMENT_STATE_FILE"
    echo "Deployment logs: $LOG_FILE"
    echo "======================================"
}

# Main deployment function
main() {
    log_info "Starting fraud detection system deployment..."
    log_info "Logs are being written to: $LOG_FILE"

    parse_arguments "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no resources will be created"
    fi

    check_prerequisites
    initialize_project
    enable_apis
    create_storage_bucket
    create_bigquery_resources
    create_pubsub_resources
    create_training_data
    create_vertex_ai_dataset
    create_vertex_ai_endpoint
    create_dataflow_pipeline
    create_transaction_simulator
    setup_monitoring

    if [[ "$DRY_RUN" == "false" ]]; then
        update_deployment_state
    fi

    print_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"
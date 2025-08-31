#!/bin/bash

# Real-time Fraud Detection with Spanner and Vertex AI - Deployment Script
# This script deploys the complete fraud detection infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_warning "To clean up partially deployed resources, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Configuration validation
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Please authenticate with Google Cloud: gcloud auth login"
        exit 1
    fi
    
    # Check if curl and openssl are available
    for cmd in curl openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "Prerequisites validated successfully"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables with defaults or user input
    export PROJECT_ID="${PROJECT_ID:-fraud-detection-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export SPANNER_INSTANCE="${SPANNER_INSTANCE:-fraud-detection-instance}"
    export DATABASE_NAME="${DATABASE_NAME:-fraud-detection-db}"
    
    # Generate unique suffix for resource names to avoid conflicts
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="${FUNCTION_NAME:-fraud-detector-${RANDOM_SUFFIX}}"
    export TOPIC_NAME="${TOPIC_NAME:-transaction-events-${RANDOM_SUFFIX}}"
    export SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-fraud-processing-${RANDOM_SUFFIX}}"
    export MODEL_NAME="${MODEL_NAME:-fraud-model-${RANDOM_SUFFIX}}"
    
    # Save configuration for cleanup script
    cat > "${CONFIG_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
SPANNER_INSTANCE=${SPANNER_INSTANCE}
DATABASE_NAME=${DATABASE_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
TOPIC_NAME=${TOPIC_NAME}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME}
MODEL_NAME=${MODEL_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Topic Name: ${TOPIC_NAME}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment configured successfully"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "spanner.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "✅ ${api} enabled"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create Cloud Spanner resources
create_spanner_resources() {
    log_info "Creating Cloud Spanner instance and database..."
    
    # Create Spanner instance
    log_info "Creating Spanner instance: ${SPANNER_INSTANCE}"
    if gcloud spanner instances create "${SPANNER_INSTANCE}" \
        --config=nam3 \
        --description="Fraud detection database instance" \
        --processing-units=100 \
        --quiet; then
        log_success "✅ Spanner instance created successfully"
    else
        log_error "Failed to create Spanner instance"
        exit 1
    fi
    
    # Create database
    log_info "Creating database: ${DATABASE_NAME}"
    if gcloud spanner databases create "${DATABASE_NAME}" \
        --instance="${SPANNER_INSTANCE}" \
        --quiet; then
        log_success "✅ Database created successfully"
    else
        log_error "Failed to create database"
        exit 1
    fi
    
    log_success "Spanner resources created successfully"
}

# Create database schema
create_database_schema() {
    log_info "Creating database schema..."
    
    # Create SQL schema file
    cat > "${SCRIPT_DIR}/schema.sql" << 'EOF'
CREATE TABLE Users (
    user_id STRING(36) NOT NULL,
    email STRING(255),
    created_at TIMESTAMP,
    risk_score FLOAT64,
    country_code STRING(2),
) PRIMARY KEY (user_id);

CREATE TABLE Transactions (
    transaction_id STRING(36) NOT NULL,
    user_id STRING(36) NOT NULL,
    amount NUMERIC,
    currency STRING(3),
    merchant_id STRING(50),
    transaction_time TIMESTAMP,
    fraud_score FLOAT64,
    fraud_prediction STRING(20),
    ip_address STRING(45),
    device_fingerprint STRING(255),
    FOREIGN KEY (user_id) REFERENCES Users (user_id)
) PRIMARY KEY (transaction_id),
INTERLEAVE IN PARENT Users ON DELETE CASCADE;

CREATE INDEX UserTransactionsByTime
ON Transactions (user_id, transaction_time DESC);

CREATE INDEX FraudScoreIndex
ON Transactions (fraud_score DESC);
EOF
    
    # Execute schema creation
    if gcloud spanner databases ddl update "${DATABASE_NAME}" \
        --instance="${SPANNER_INSTANCE}" \
        --ddl-file="${SCRIPT_DIR}/schema.sql" \
        --quiet; then
        log_success "✅ Database schema created successfully"
    else
        log_error "Failed to create database schema"
        exit 1
    fi
    
    log_success "Database schema configured successfully"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create topic
    if gcloud pubsub topics create "${TOPIC_NAME}" --quiet; then
        log_success "✅ Pub/Sub topic created: ${TOPIC_NAME}"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=60 \
        --message-retention-duration=7d \
        --quiet; then
        log_success "✅ Pub/Sub subscription created: ${SUBSCRIPTION_NAME}"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    log_success "Pub/Sub resources created successfully"
}

# Create Cloud Storage resources for Vertex AI
create_storage_resources() {
    log_info "Creating Cloud Storage resources for ML data..."
    
    # Create bucket for training data
    local bucket_name="${PROJECT_ID}-fraud-detection-data"
    
    if gsutil mb "gs://${bucket_name}" 2>/dev/null || gsutil ls "gs://${bucket_name}" &>/dev/null; then
        log_success "✅ Storage bucket ready: gs://${bucket_name}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Create sample training data
    cat > "${SCRIPT_DIR}/training_data.csv" << 'EOF'
amount,merchant_category,hour_of_day,day_of_week,user_age,transaction_count_1h,fraud_label
25.50,grocery,14,2,32,1,0
1250.00,electronics,23,6,45,1,1
15.75,coffee,8,1,28,3,0
850.00,jewelry,2,0,52,1,1
45.20,gas,17,4,35,2,0
2500.00,travel,22,5,29,1,1
12.99,subscription,10,3,41,1,0
EOF
    
    # Upload training data
    if gsutil cp "${SCRIPT_DIR}/training_data.csv" "gs://${bucket_name}/"; then
        log_success "✅ Training data uploaded successfully"
    else
        log_error "Failed to upload training data"
        exit 1
    fi
    
    log_success "Storage resources created successfully"
}

# Create Vertex AI dataset
create_vertex_ai_dataset() {
    log_info "Creating Vertex AI dataset..."
    
    # Create dataset using REST API
    local access_token
    access_token=$(gcloud auth print-access-token)
    
    local dataset_response
    dataset_response=$(curl -s -X POST \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d '{
            "display_name": "fraud-detection-dataset",
            "metadata_schema_uri": "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
        }' \
        "https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/datasets")
    
    if echo "${dataset_response}" | grep -q "name"; then
        log_success "✅ Vertex AI dataset created successfully"
    else
        log_warning "Vertex AI dataset creation may have failed, but continuing deployment"
        log_info "Response: ${dataset_response}"
    fi
    
    log_success "Vertex AI resources configured"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for fraud detection..."
    
    # Create function source directory
    local function_dir="${SCRIPT_DIR}/fraud-detection-function"
    mkdir -p "${function_dir}"
    
    # Create main function code
    cat > "${function_dir}/main.py" << 'EOF'
import json
import logging
import base64
from google.cloud import spanner
from google.cloud import aiplatform
from google.cloud import pubsub_v1
import functions_framework
import os

# Initialize clients
spanner_client = spanner.Client()
instance_id = os.environ['SPANNER_INSTANCE']
database_id = os.environ['DATABASE_NAME']
instance = spanner_client.instance(instance_id)
database = instance.database(database_id)

@functions_framework.cloud_event
def process_transaction(cloud_event):
    """Process incoming transaction for fraud detection."""
    try:
        # Decode Pub/Sub message
        transaction_data = json.loads(
            base64.b64decode(cloud_event.data["message"]["data"]).decode()
        )
        
        # Extract transaction details
        user_id = transaction_data['user_id']
        amount = float(transaction_data['amount'])
        merchant_id = transaction_data['merchant_id']
        
        # Query user history from Spanner
        fraud_score = calculate_fraud_score(
            user_id, amount, merchant_id
        )
        
        # Store transaction with fraud score
        store_transaction(transaction_data, fraud_score)
        
        # Take action if high fraud risk
        if fraud_score > 0.8:
            block_transaction(transaction_data['transaction_id'])
        
        logging.info(f"Processed transaction {transaction_data['transaction_id']} with fraud score {fraud_score}")
        
    except Exception as e:
        logging.error(f"Error processing transaction: {str(e)}")
        raise

def calculate_fraud_score(user_id, amount, merchant_id):
    """Calculate fraud score using business rules and ML model."""
    # Simple rule-based scoring (in production, use Vertex AI)
    base_score = 0.1
    
    # Check for unusual amount
    if amount > 1000:
        base_score += 0.3
    
    # Check transaction velocity
    with database.snapshot() as snapshot:
        query = """
        SELECT COUNT(*) as transaction_count
        FROM Transactions
        WHERE user_id = @user_id
        AND transaction_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
        """
        
        results = snapshot.execute_sql(
            query, params={'user_id': user_id}
        )
        
        for row in results:
            if row[0] > 5:  # More than 5 transactions in 1 hour
                base_score += 0.4
    
    return min(base_score, 1.0)

def store_transaction(transaction_data, fraud_score):
    """Store transaction in Spanner with fraud score."""
    with database.batch() as batch:
        batch.insert(
            table='Transactions',
            columns=[
                'transaction_id', 'user_id', 'amount',
                'currency', 'merchant_id', 'transaction_time',
                'fraud_score', 'fraud_prediction'
            ],
            values=[
                [
                    transaction_data['transaction_id'],
                    transaction_data['user_id'],
                    float(transaction_data['amount']),
                    transaction_data['currency'],
                    transaction_data['merchant_id'],
                    spanner.COMMIT_TIMESTAMP,
                    fraud_score,
                    'HIGH_RISK' if fraud_score > 0.8 else 'LOW_RISK'
                ]
            ]
        )

def block_transaction(transaction_id):
    """Send alert for high-risk transactions."""
    logging.warning(f"FRAUD ALERT: Blocking transaction {transaction_id}")
    # In production, integrate with alert systems
EOF
    
    # Create requirements file
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-spanner==3.47.0
google-cloud-aiplatform==1.38.0
google-cloud-pubsub==2.18.4
functions-framework==3.5.0
EOF
    
    # Deploy Cloud Function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python312 \
        --trigger-topic "${TOPIC_NAME}" \
        --source "${function_dir}" \
        --entry-point process_transaction \
        --memory 512MB \
        --timeout 60s \
        --max-instances 10 \
        --set-env-vars "SPANNER_INSTANCE=${SPANNER_INSTANCE},DATABASE_NAME=${DATABASE_NAME}" \
        --region "${REGION}" \
        --quiet; then
        log_success "✅ Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    log_success "Cloud Function deployment completed"
}

# Create sample data
create_sample_data() {
    log_info "Creating sample users and test data..."
    
    # Create sample users SQL
    cat > "${SCRIPT_DIR}/insert_users.sql" << 'EOF'
INSERT INTO Users (user_id, email, created_at, risk_score, country_code) VALUES
('user-1', 'john.doe@example.com', CURRENT_TIMESTAMP(), 0.1, 'US'),
('user-2', 'jane.smith@example.com', CURRENT_TIMESTAMP(), 0.2, 'CA'),
('user-3', 'bob.johnson@example.com', CURRENT_TIMESTAMP(), 0.8, 'US');
EOF
    
    # Insert sample users
    if gcloud spanner databases execute-sql "${DATABASE_NAME}" \
        --instance="${SPANNER_INSTANCE}" \
        --sql="$(cat "${SCRIPT_DIR}/insert_users.sql")" \
        --quiet; then
        log_success "✅ Sample users created successfully"
    else
        log_error "Failed to create sample users"
        exit 1
    fi
    
    # Publish test transaction
    local transaction_data='{
        "transaction_id": "txn-123",
        "user_id": "user-1",
        "amount": "150.00",
        "currency": "USD",
        "merchant_id": "merchant-grocery-1"
    }'
    
    if echo "${transaction_data}" | gcloud pubsub topics publish "${TOPIC_NAME}" --message=-; then
        log_success "✅ Test transaction published successfully"
    else
        log_warning "Failed to publish test transaction, but deployment continues"
    fi
    
    log_success "Sample data created successfully"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check Spanner instance
    if gcloud spanner instances describe "${SPANNER_INSTANCE}" --quiet &>/dev/null; then
        log_success "✅ Spanner instance is operational"
    else
        log_error "Spanner instance verification failed"
        exit 1
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" --quiet &>/dev/null; then
        log_success "✅ Pub/Sub topic is operational"
    else
        log_error "Pub/Sub topic verification failed"
        exit 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet &>/dev/null; then
        log_success "✅ Cloud Function is deployed"
    else
        log_error "Cloud Function verification failed"
        exit 1
    fi
    
    log_success "Deployment verification completed successfully"
}

# Display deployment summary
display_summary() {
    log_success "🎉 Fraud Detection System Deployment Complete!"
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Spanner Instance: ${SPANNER_INSTANCE}"
    echo "Database: ${DATABASE_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Pub/Sub Topic: ${TOPIC_NAME}"
    echo "Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
    echo ""
    echo "Configuration saved to: ${CONFIG_FILE}"
    echo "Deployment log: ${LOG_FILE}"
    echo ""
    echo "To test the system:"
    echo "  1. Publish transactions to: ${TOPIC_NAME}"
    echo "  2. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --gen2 --region=${REGION}"
    echo "  3. Query results: gcloud spanner databases execute-sql ${DATABASE_NAME} --instance=${SPANNER_INSTANCE} --sql=\"SELECT * FROM Transactions\""
    echo ""
    echo "To clean up resources: ./destroy.sh"
    echo "=========================================="
}

# Main deployment function
main() {
    log_info "Starting fraud detection system deployment..."
    log_info "Deployment log: ${LOG_FILE}"
    
    validate_prerequisites
    setup_environment
    enable_apis
    create_spanner_resources
    create_database_schema
    create_pubsub_resources
    create_storage_resources
    create_vertex_ai_dataset
    deploy_cloud_function
    create_sample_data
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully in $(date)"
}

# Execute main function
main "$@"
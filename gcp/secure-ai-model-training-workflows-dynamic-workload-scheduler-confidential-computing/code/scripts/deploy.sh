#!/bin/bash

# Secure AI Model Training Workflows with Dynamic Workload Scheduler and Confidential Computing
# Deploy Script for GCP Infrastructure
# 
# This script deploys the complete infrastructure for secure AI model training
# using Dynamic Workload Scheduler and Confidential Computing on Google Cloud Platform.

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/secure-ai-training-deploy-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    echo -e "${RED}Deployment failed. Check log file: $LOG_FILE${NC}"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment due to error..."
    # This will be called if the script exits with an error
    # Add specific cleanup commands here if needed
    log_warning "Partial cleanup completed. Manual verification may be required."
}

trap cleanup_on_error ERR

# Display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy secure AI model training infrastructure on Google Cloud Platform.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -z, --zone ZONE              GCP zone (default: us-central1-a)
    -s, --skip-apis              Skip API enablement (default: false)
    -d, --dry-run                Show what would be deployed without executing
    -v, --verbose                Enable verbose logging
    -h, --help                   Show this help message

EXAMPLES:
    $SCRIPT_NAME --project-id my-secure-ai-project
    $SCRIPT_NAME -p my-project -r us-west1 -z us-west1-a
    $SCRIPT_NAME --project-id my-project --dry-run

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT         Alternative way to specify project ID
    GCP_REGION                   Alternative way to specify region
    GCP_ZONE                     Alternative way to specify zone

EOF
}

# Default values
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
SKIP_APIS=false
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
parse_args() {
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
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log "Google Cloud SDK version: $gcloud_version"
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project ID is provided
    if [[ -z "$PROJECT_ID" ]]; then
        if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
            PROJECT_ID="$GOOGLE_CLOUD_PROJECT"
            log "Using project ID from environment variable: $PROJECT_ID"
        else
            error_exit "Project ID is required. Use --project-id option or set GOOGLE_CLOUD_PROJECT environment variable."
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' does not exist or is not accessible."
    fi
    
    # Check billing account
    local billing_account
    billing_account=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        log_warning "No billing account associated with project $PROJECT_ID. This may prevent resource creation."
    fi
    
    # Validate region and zone
    if ! gcloud compute regions describe "$REGION" &> /dev/null; then
        error_exit "Region '$REGION' is not valid."
    fi
    
    if ! gcloud compute zones describe "$ZONE" &> /dev/null; then
        error_exit "Zone '$ZONE' is not valid."
    fi
    
    log_success "Prerequisites validation completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Export environment variables for use in subsequent commands
    export PROJECT_ID
    export REGION
    export ZONE
    export SERVICE_ACCOUNT_NAME="ai-training-sa"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="secure-training-data-${RANDOM_SUFFIX}"
    export KEYRING_NAME="ai-training-keyring-${RANDOM_SUFFIX}"
    export KEY_NAME="training-data-key"
    export VERTEX_JOB_NAME="secure-training-job-${RANDOM_SUFFIX}"
    
    # Set gcloud configuration
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log "Environment setup completed"
    if [[ "$VERBOSE" == true ]]; then
        log "PROJECT_ID: $PROJECT_ID"
        log "REGION: $REGION"
        log "ZONE: $ZONE"
        log "BUCKET_NAME: $BUCKET_NAME"
        log "KEYRING_NAME: $KEYRING_NAME"
        log "RANDOM_SUFFIX: $RANDOM_SUFFIX"
    fi
}

# Enable required Google Cloud APIs
enable_apis() {
    if [[ "$SKIP_APIS" == true ]]; then
        log "Skipping API enablement as requested"
        return 0
    fi
    
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "storage.googleapis.com"
        "cloudkms.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "confidentialcomputing.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            log "[DRY-RUN] Would enable API: $api"
        else
            log "Enabling API: $api"
            if gcloud services enable "$api" --quiet; then
                log "✅ Enabled API: $api"
            else
                error_exit "Failed to enable API: $api"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" == false ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
        log_success "All required APIs enabled"
    fi
}

# Create Cloud KMS encryption infrastructure
create_kms_infrastructure() {
    log "Creating Cloud KMS encryption infrastructure..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create KMS keyring: $KEYRING_NAME in region: $REGION"
        log "[DRY-RUN] Would create KMS key: $KEY_NAME with 30-day rotation"
        return 0
    fi
    
    # Create KMS keyring
    log "Creating KMS keyring: $KEYRING_NAME"
    if gcloud kms keyrings create "$KEYRING_NAME" --location="$REGION" --quiet; then
        log "✅ Created KMS keyring: $KEYRING_NAME"
    else
        # Check if keyring already exists
        if gcloud kms keyrings describe "$KEYRING_NAME" --location="$REGION" &> /dev/null; then
            log "KMS keyring already exists: $KEYRING_NAME"
        else
            error_exit "Failed to create KMS keyring: $KEYRING_NAME"
        fi
    fi
    
    # Create encryption key
    log "Creating KMS encryption key: $KEY_NAME"
    local next_rotation
    next_rotation=$(date -d "+30 days" --iso-8601)
    
    if gcloud kms keys create "$KEY_NAME" \
        --location="$REGION" \
        --keyring="$KEYRING_NAME" \
        --purpose=encryption \
        --rotation-period=30d \
        --next-rotation-time="$next_rotation" \
        --quiet; then
        log "✅ Created KMS encryption key: $KEY_NAME"
    else
        # Check if key already exists
        if gcloud kms keys describe "$KEY_NAME" --location="$REGION" --keyring="$KEYRING_NAME" &> /dev/null; then
            log "KMS encryption key already exists: $KEY_NAME"
        else
            error_exit "Failed to create KMS encryption key: $KEY_NAME"
        fi
    fi
    
    log_success "KMS encryption infrastructure created"
}

# Create service account with security permissions
create_service_account() {
    log "Creating confidential computing service account..."
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create service account: $SERVICE_ACCOUNT_NAME"
        log "[DRY-RUN] Would assign IAM roles for confidential computing"
        return 0
    fi
    
    # Create service account
    log "Creating service account: $SERVICE_ACCOUNT_NAME"
    if gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="AI Training Confidential Computing SA" \
        --description="Service account for secure AI training in TEE" \
        --quiet; then
        log "✅ Created service account: $SERVICE_ACCOUNT_NAME"
    else
        # Check if service account already exists
        if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
            log "Service account already exists: $SERVICE_ACCOUNT_NAME"
        else
            error_exit "Failed to create service account: $SERVICE_ACCOUNT_NAME"
        fi
    fi
    
    # Grant necessary IAM roles
    local roles=(
        "roles/aiplatform.user"
        "roles/storage.objectAdmin"
        "roles/cloudkms.cryptoKeyEncrypterDecrypter"
        "roles/confidentialcomputing.workloadUser"
        "roles/compute.instanceAdmin.v1"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role: $role to service account"
        if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$sa_email" \
            --role="$role" \
            --quiet; then
            log "✅ Granted role: $role"
        else
            log_warning "Failed to grant role: $role (may already exist)"
        fi
    done
    
    log_success "Service account created and configured"
}

# Create encrypted Cloud Storage bucket
create_encrypted_storage() {
    log "Creating encrypted Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create encrypted bucket: $BUCKET_NAME"
        log "[DRY-RUN] Would configure CMEK encryption with key: $KEY_NAME"
        return 0
    fi
    
    # Create storage bucket
    log "Creating storage bucket: $BUCKET_NAME"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        log "✅ Created storage bucket: $BUCKET_NAME"
    else
        # Check if bucket already exists
        if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
            log "Storage bucket already exists: $BUCKET_NAME"
        else
            error_exit "Failed to create storage bucket: $BUCKET_NAME"
        fi
    fi
    
    # Configure bucket with customer-managed encryption
    log "Configuring CMEK encryption for bucket"
    local kms_key="projects/$PROJECT_ID/locations/$REGION/keyRings/$KEYRING_NAME/cryptoKeys/$KEY_NAME"
    if gsutil kms encryption -k "$kms_key" "gs://$BUCKET_NAME"; then
        log "✅ Configured CMEK encryption"
    else
        error_exit "Failed to configure CMEK encryption"
    fi
    
    # Set bucket lifecycle policy
    log "Setting bucket lifecycle policy"
    local lifecycle_config
    lifecycle_config=$(cat << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
)
    
    if echo "$lifecycle_config" | gsutil lifecycle set /dev/stdin "gs://$BUCKET_NAME"; then
        log "✅ Set bucket lifecycle policy"
    else
        log_warning "Failed to set bucket lifecycle policy"
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://$BUCKET_NAME"; then
        log "✅ Enabled bucket versioning"
    else
        log_warning "Failed to enable bucket versioning"
    fi
    
    log_success "Encrypted storage bucket created and configured"
}

# Upload sample training data
upload_training_data() {
    log "Uploading sample training data..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create and upload sample training data"
        return 0
    fi
    
    # Create local training data directory
    local temp_dir
    temp_dir=$(mktemp -d)
    local training_dir="$temp_dir/training_data"
    mkdir -p "$training_dir"
    
    # Generate sample training dataset
    cat > "$training_dir/dataset.csv" << 'EOF'
feature1,feature2,feature3,label
0.1,0.2,0.3,1
0.4,0.5,0.6,0
0.7,0.8,0.9,1
0.2,0.3,0.4,0
0.5,0.6,0.7,1
0.8,0.9,0.1,0
0.3,0.4,0.5,1
0.6,0.7,0.8,0
0.9,0.1,0.2,1
0.1,0.5,0.9,0
EOF
    
    # Create sample training script
    cat > "$training_dir/secure_training.py" << 'EOF'
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import pickle
import os
import logging

# Configure logging for confidential environment
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def main():
    logger.info("Starting secure training in confidential computing environment")
    
    try:
        # Load encrypted data within TEE
        data_path = '/tmp/dataset.csv'
        if not os.path.exists(data_path):
            # Fallback to mounted storage path
            data_path = '/mnt/training_data/dataset.csv'
        
        logger.info(f"Loading data from: {data_path}")
        data = pd.read_csv(data_path)
        
        # Prepare features and labels
        X = data[['feature1', 'feature2', 'feature3']]
        y = data['label']
        
        logger.info(f"Dataset shape: {X.shape}, Labels: {y.value_counts().to_dict()}")
        
        # Split data for training and validation
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.3, random_state=42, stratify=y
        )
        
        # Train model within confidential environment
        logger.info("Training RandomForest model in TEE...")
        model = RandomForestClassifier(
            n_estimators=100, 
            random_state=42, 
            max_depth=5,
            min_samples_split=2,
            min_samples_leaf=1
        )
        model.fit(X_train, y_train)
        
        # Evaluate model
        y_pred = model.predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)
        
        logger.info(f"Model training completed - Accuracy: {accuracy:.4f}")
        logger.info("Classification Report:")
        logger.info(f"\n{classification_report(y_test, y_pred)}")
        
        # Save model securely within TEE
        model_path = '/tmp/secure_model.pkl'
        with open(model_path, 'wb') as f:
            pickle.dump(model, f)
        
        logger.info(f"Model saved securely at: {model_path}")
        
        # Feature importance analysis
        feature_importance = dict(zip(['feature1', 'feature2', 'feature3'], model.feature_importances_))
        logger.info(f"Feature importance: {feature_importance}")
        
        logger.info("Secure training completed successfully in confidential environment")
        return accuracy
        
    except Exception as e:
        logger.error(f"Training failed: {str(e)}")
        raise

if __name__ == "__main__":
    accuracy = main()
    print(f"TRAINING_RESULT: {accuracy:.4f}")
EOF
    
    # Upload training data to encrypted bucket
    log "Uploading training data to encrypted bucket"
    if gsutil -m cp -r "$training_dir"/* "gs://$BUCKET_NAME/training/"; then
        log "✅ Training data uploaded successfully"
    else
        error_exit "Failed to upload training data"
    fi
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    log_success "Sample training data uploaded"
}

# Configure Dynamic Workload Scheduler reservation
configure_workload_scheduler() {
    log "Configuring Dynamic Workload Scheduler reservation..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create compute reservation for GPU resources"
        log "[DRY-RUN] Would create confidential compute instance template"
        return 0
    fi
    
    # Check GPU quota availability
    log "Checking GPU quota availability..."
    local gpu_quota
    gpu_quota=$(gcloud compute project-info describe --format="value(quotas[].limit)" --filter="quotas.metric:NVIDIA_A100_GPUS" 2>/dev/null || echo "0")
    
    if [[ "$gpu_quota" -eq 0 ]]; then
        log_warning "No A100 GPU quota available. You may need to request quota increase."
        log_warning "Consider using alternative GPU types like nvidia-tesla-t4"
    fi
    
    # Create Dynamic Workload Scheduler reservation
    log "Creating compute reservation for secure AI training"
    if gcloud beta compute reservations create secure-ai-training-reservation \
        --zone="$ZONE" \
        --vm-count=1 \
        --machine-type=a2-highgpu-1g \
        --accelerator=type=nvidia-tesla-a100,count=1 \
        --require-specific-reservation \
        --reservation-affinity=specific \
        --quiet; then
        log "✅ Created compute reservation"
    else
        # Check if reservation already exists
        if gcloud compute reservations describe secure-ai-training-reservation --zone="$ZONE" &> /dev/null; then
            log "Compute reservation already exists"
        else
            log_warning "Failed to create compute reservation. Continuing without reservation."
        fi
    fi
    
    # Create compute instance template for confidential computing
    log "Creating confidential computing instance template"
    if gcloud compute instance-templates create confidential-training-template \
        --machine-type=a2-highgpu-1g \
        --accelerator=type=nvidia-tesla-a100,count=1 \
        --image-family=deep-learning-vm \
        --image-project=ml-images \
        --boot-disk-size=100GB \
        --boot-disk-type=pd-ssd \
        --confidential-compute \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --metadata=enable-oslogin=true \
        --tags=confidential-training \
        --quiet; then
        log "✅ Created confidential computing instance template"
    else
        # Check if template already exists
        if gcloud compute instance-templates describe confidential-training-template &> /dev/null; then
            log "Instance template already exists"
        else
            error_exit "Failed to create instance template"
        fi
    fi
    
    log_success "Dynamic Workload Scheduler configured"
}

# Deploy confidential computing training environment
deploy_confidential_environment() {
    log "Deploying confidential computing training environment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create confidential VM with GPU acceleration"
        return 0
    fi
    
    # Create confidential computing instance
    log "Creating confidential computing instance"
    if gcloud compute instances create confidential-training-vm \
        --source-instance-template=confidential-training-template \
        --zone="$ZONE" \
        --confidential-compute \
        --confidential-compute-type=SEV \
        --quiet; then
        log "✅ Created confidential computing VM"
    else
        # Check if instance already exists
        if gcloud compute instances describe confidential-training-vm --zone="$ZONE" &> /dev/null; then
            log "Confidential computing VM already exists"
        else
            error_exit "Failed to create confidential computing VM"
        fi
    fi
    
    # Wait for instance to be ready
    log "Waiting for confidential VM to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local status
        status=$(gcloud compute instances describe confidential-training-vm --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$status" == "RUNNING" ]]; then
            log "✅ Confidential VM is running"
            break
        fi
        
        ((attempt++))
        log "VM status: $status (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error_exit "Timeout waiting for confidential VM to be ready"
    fi
    
    # Additional wait for GPU initialization
    log "Waiting for GPU initialization..."
    sleep 60
    
    log_success "Confidential computing training environment deployed"
}

# Configure monitoring and attestation
configure_monitoring() {
    log "Configuring monitoring and attestation..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would configure Cloud Monitoring policies"
        log "[DRY-RUN] Would enable audit logging"
        return 0
    fi
    
    # Create monitoring policy for confidential computing
    local policy_file
    policy_file=$(mktemp)
    
    cat > "$policy_file" << EOF
displayName: "Confidential Training Security Policy"
conditions:
- displayName: "TEE Attestation Failure"
  conditionThreshold:
    filter: 'resource.type="gce_instance" AND metric.type="compute.googleapis.com/instance/confidential_compute/attestation_failure"'
    comparison: COMPARISON_GREATER_THAN
    thresholdValue: 0
notificationChannels: []
alertStrategy:
  autoClose: 86400s
documentation:
  content: "Alert triggered when confidential computing attestation fails"
EOF
    
    # Create monitoring policy
    log "Creating Cloud Monitoring policy"
    if gcloud alpha monitoring policies create --policy-from-file="$policy_file" --quiet; then
        log "✅ Created monitoring policy"
    else
        log_warning "Failed to create monitoring policy (may require alpha components)"
    fi
    
    rm -f "$policy_file"
    
    # Enable audit logging
    log "Configuring audit logging for confidential computing"
    if gcloud logging sinks create confidential-training-audit \
        cloud-logging-bucket \
        --log-filter='protoPayload.serviceName=("compute.googleapis.com" OR "confidentialcomputing.googleapis.com")' \
        --project="$PROJECT_ID" \
        --quiet; then
        log "✅ Configured audit logging"
    else
        log_warning "Failed to configure audit logging (may already exist)"
    fi
    
    log_success "Monitoring and attestation configured"
}

# Execute deployment
execute_deployment() {
    log "Starting secure AI model training infrastructure deployment..."
    
    # Deployment steps
    setup_environment
    enable_apis
    create_kms_infrastructure
    create_service_account
    create_encrypted_storage
    upload_training_data
    configure_workload_scheduler
    deploy_confidential_environment
    configure_monitoring
    
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry-run completed successfully. No resources were created."
        return 0
    fi
    
    # Display deployment summary
    echo ""
    echo "======================================"
    echo "DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "KMS Keyring: $KEYRING_NAME"
    echo "KMS Key: $KEY_NAME"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "Confidential VM: confidential-training-vm"
    echo "Log File: $LOG_FILE"
    echo ""
    echo "Next Steps:"
    echo "1. Verify confidential VM status:"
    echo "   gcloud compute instances describe confidential-training-vm --zone=$ZONE"
    echo ""
    echo "2. Submit a Vertex AI training job:"
    echo "   gcloud ai custom-jobs create --region=$REGION --config=training_job_config.yaml"
    echo ""
    echo "3. Monitor training progress in Cloud Console"
    echo "======================================"
    
    log_success "Secure AI model training infrastructure deployment completed successfully"
}

# Main execution
main() {
    echo -e "${BLUE}Secure AI Model Training Infrastructure Deployment${NC}"
    echo "Starting deployment on $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    
    parse_args "$@"
    validate_prerequisites
    execute_deployment
    
    echo ""
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    exit 0
}

# Execute main function with all arguments
main "$@"
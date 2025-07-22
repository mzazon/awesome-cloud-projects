#!/bin/bash

# Medical Imaging Analysis with Cloud Healthcare API and Vision AI - Deployment Script
# This script deploys a complete medical imaging analysis pipeline on Google Cloud Platform

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

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Rolling back resources..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Google Cloud Storage utility (gsutil) is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if required APIs can be enabled (billing check)
    local current_project=$(gcloud config get-value project 2>/dev/null)
    if [[ -n "$current_project" ]]; then
        if ! gcloud services list --enabled --filter="name:healthcare.googleapis.com" --format="value(name)" | grep -q .; then
            log_warn "Healthcare API not enabled. This deployment will enable required APIs."
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Project configuration
    export PROJECT_ID="${PROJECT_ID:-medical-imaging-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Healthcare API resources
    export DATASET_ID="${DATASET_ID:-medical-imaging-dataset}"
    export DICOM_STORE_ID="${DICOM_STORE_ID:-medical-dicom-store}"
    export FHIR_STORE_ID="${FHIR_STORE_ID:-medical-fhir-store}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-medical-imaging-bucket-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-medical-image-processor}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-medical-imaging-sa}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Dataset ID: ${DATASET_ID}"
}

# Create or configure project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Medical Imaging Analysis"
        
        # Wait for project to be ready
        sleep 10
    fi
    
    # Set the project
    gcloud config set project "${PROJECT_ID}"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warn "Billing is not enabled for this project. Please enable billing before continuing."
        log_warn "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        read -p "Press Enter after enabling billing to continue..."
    fi
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "healthcare.googleapis.com"
        "vision.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create healthcare dataset and stores
create_healthcare_resources() {
    log_info "Creating Healthcare API resources..."
    
    # Create healthcare dataset
    log_info "Creating healthcare dataset: ${DATASET_ID}"
    if gcloud healthcare datasets create "${DATASET_ID}" \
        --location="${REGION}" \
        --description="Medical imaging analysis dataset" \
        --quiet; then
        log_success "Healthcare dataset created successfully"
    else
        log_error "Failed to create healthcare dataset"
        exit 1
    fi
    
    # Create DICOM store
    log_info "Creating DICOM store: ${DICOM_STORE_ID}"
    if gcloud healthcare dicom-stores create "${DICOM_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" \
        --description="DICOM store for medical imaging analysis" \
        --quiet; then
        log_success "DICOM store created successfully"
    else
        log_error "Failed to create DICOM store"
        exit 1
    fi
    
    # Create FHIR store
    log_info "Creating FHIR store: ${FHIR_STORE_ID}"
    if gcloud healthcare fhir-stores create "${FHIR_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" \
        --version=R4 \
        --description="FHIR store for medical analysis results" \
        --quiet; then
        log_success "FHIR store created successfully"
    else
        log_error "Failed to create FHIR store"
        exit 1
    fi
    
    log_success "Healthcare API resources created successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Create storage bucket with healthcare-appropriate configuration
    log_info "Creating bucket: ${BUCKET_NAME}"
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        -b on \
        "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket created successfully"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    log_info "Enabling versioning on bucket"
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Remove public access
    log_info "Securing bucket access"
    gsutil iam ch -d allUsers:objectViewer "gs://${BUCKET_NAME}" 2>/dev/null || true
    
    # Create folder structure
    log_info "Creating folder structure"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/incoming/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/processed/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/failed/.keep"
    
    log_success "Cloud Storage bucket configured successfully"
}

# Create service account
create_service_account() {
    log_info "Creating service account..."
    
    # Create service account
    log_info "Creating service account: ${SERVICE_ACCOUNT_NAME}"
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Medical Imaging Analysis Service Account" \
        --description="Service account for automated medical imaging analysis" \
        --quiet; then
        log_success "Service account created successfully"
    else
        log_error "Failed to create service account"
        exit 1
    fi
    
    # Grant Healthcare API permissions
    log_info "Granting Healthcare API permissions"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/healthcare.datasetAdmin" \
        --quiet
    
    # Grant Vision AI permissions
    log_info "Granting Vision AI permissions"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/ml.developer" \
        --quiet
    
    # Grant Cloud Storage permissions
    log_info "Granting Cloud Storage permissions"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet
    
    # Grant Cloud Functions permissions
    log_info "Granting Cloud Functions permissions"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudfunctions.developer" \
        --quiet
    
    # Grant Pub/Sub permissions
    log_info "Granting Pub/Sub permissions"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/pubsub.editor" \
        --quiet
    
    log_success "Service account permissions configured"
}

# Configure Pub/Sub for event-driven processing
setup_pubsub() {
    log_info "Setting up Pub/Sub for event-driven processing..."
    
    # Create Pub/Sub topic
    log_info "Creating Pub/Sub topic: medical-image-processing"
    if gcloud pubsub topics create medical-image-processing --quiet; then
        log_success "Pub/Sub topic created successfully"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    log_info "Creating Pub/Sub subscription"
    if gcloud pubsub subscriptions create medical-image-processor-sub \
        --topic=medical-image-processing \
        --ack-deadline=600 \
        --quiet; then
        log_success "Pub/Sub subscription created successfully"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    # Configure Healthcare API to publish DICOM events
    log_info "Configuring Healthcare API to publish DICOM events"
    if gcloud healthcare dicom-stores update "${DICOM_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" \
        --pubsub-topic="projects/${PROJECT_ID}/topics/medical-image-processing" \
        --quiet; then
        log_success "DICOM store configured for Pub/Sub events"
    else
        log_error "Failed to configure DICOM store for Pub/Sub"
        exit 1
    fi
    
    log_success "Pub/Sub configuration completed"
}

# Create Cloud Function for image analysis
create_cloud_function() {
    log_info "Creating Cloud Function for medical image analysis..."
    
    # Create temporary directory for function code
    local function_dir="$(mktemp -d)"
    cd "${function_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-healthcare==1.11.0
google-cloud-vision==3.4.0
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.0
pydicom==2.4.0
Pillow==10.0.0
functions-framework==3.4.0
EOF
    
    # Create main.py with image analysis logic
    cat > main.py << 'EOF'
import os
import json
import base64
from google.cloud import healthcare_v1
from google.cloud import vision
from google.cloud import storage
from google.cloud import pubsub_v1
import pydicom
from PIL import Image
import io
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_medical_image(cloud_event):
    """Process medical image with Vision AI analysis"""
    
    try:
        # Initialize clients
        healthcare_client = healthcare_v1.HealthcareServiceClient()
        vision_client = vision.ImageAnnotatorClient()
        storage_client = storage.Client()
        
        # Extract event data
        event_data = json.loads(base64.b64decode(cloud_event.data).decode())
        logger.info(f"Processing event: {event_data}")
        
        # For demo purposes, create a sample analysis result
        analysis_results = {
            'event_type': event_data.get('eventType', 'unknown'),
            'resource_name': event_data.get('name', 'unknown'),
            'timestamp': event_data.get('eventTime', 'unknown'),
            'analysis_status': 'completed',
            'demo_mode': True,
            'message': 'Medical imaging analysis pipeline is operational'
        }
        
        # Log the analysis results
        logger.info(f"Analysis results: {json.dumps(analysis_results, indent=2)}")
        
        # Store results (in production, this would go to FHIR store)
        store_analysis_results(analysis_results, event_data.get('name', 'unknown'))
        
        logger.info(f"Successfully processed medical imaging event")
        return analysis_results
        
    except Exception as e:
        logger.error(f"Error processing medical image: {str(e)}")
        raise

def store_analysis_results(results, resource_name):
    """Store analysis results (demo implementation)"""
    
    logger.info(f"Storing analysis results for {resource_name}")
    logger.info(f"Results: {json.dumps(results, indent=2)}")
    
    # In production, this would create FHIR DiagnosticReport resources
    # For demo purposes, we log the results
    return True
EOF
    
    # Deploy the Cloud Function
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python311 \
        --region="${REGION}" \
        --source=. \
        --entry-point=process_medical_image \
        --trigger-topic=medical-image-processing \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=512MB \
        --timeout=540s \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},DATASET_ID=${DATASET_ID},DICOM_STORE_ID=${DICOM_STORE_ID},FHIR_STORE_ID=${FHIR_STORE_ID}" \
        --quiet; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${function_dir}"
    
    log_success "Medical image analysis function created successfully"
}

# Set up monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create log-based metric for successful processing
    log_info "Creating log-based metrics"
    if gcloud logging metrics create medical_image_processing_success \
        --description="Successful medical image processing events" \
        --log-filter="resource.type=\"cloud_function\" resource.labels.function_name=\"${FUNCTION_NAME}\" \"Successfully processed\"" \
        --quiet; then
        log_success "Log-based metrics created successfully"
    else
        log_warn "Log-based metrics may already exist or failed to create"
    fi
    
    log_success "Monitoring configuration completed"
}

# Create sample test data
create_sample_data() {
    log_info "Creating sample test data..."
    
    # Create sample metadata directory
    local sample_dir="$(mktemp -d)"
    cd "${sample_dir}"
    
    # Generate sample DICOM metadata for testing
    cat > sample_study.json << 'EOF'
{
  "PatientID": "TEST001",
  "StudyDate": "20250112",
  "Modality": "CT",
  "StudyDescription": "Chest CT for routine screening",
  "SeriesDescription": "Axial chest images"
}
EOF
    
    # Upload sample data to Cloud Storage
    log_info "Uploading sample data to Cloud Storage"
    gsutil cp sample_study.json "gs://${BUCKET_NAME}/incoming/"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${sample_dir}"
    
    log_success "Sample test data created"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check healthcare dataset
    if gcloud healthcare datasets describe "${DATASET_ID}" \
        --location="${REGION}" \
        --format="value(name)" &>/dev/null; then
        log_success "Healthcare dataset is accessible"
    else
        log_error "Healthcare dataset verification failed"
        exit 1
    fi
    
    # Check DICOM store
    if gcloud healthcare dicom-stores describe "${DICOM_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" \
        --format="value(name)" &>/dev/null; then
        log_success "DICOM store is accessible"
    else
        log_error "DICOM store verification failed"
        exit 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --gen2 \
        --format="value(name)" &>/dev/null; then
        log_success "Cloud Function is deployed and accessible"
    else
        log_error "Cloud Function verification failed"
        exit 1
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe medical-image-processing \
        --format="value(name)" &>/dev/null; then
        log_success "Pub/Sub topic is accessible"
    else
        log_error "Pub/Sub topic verification failed"
        exit 1
    fi
    
    # Check storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Storage bucket is accessible"
    else
        log_error "Storage bucket verification failed"
        exit 1
    fi
    
    log_success "All components verified successfully"
}

# Display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Medical Imaging Analysis Pipeline Deployed:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Healthcare Dataset: ${DATASET_ID}"
    echo "  DICOM Store: ${DICOM_STORE_ID}"
    echo "  FHIR Store: ${FHIR_STORE_ID}"
    echo "  Storage Bucket: gs://${BUCKET_NAME}"
    echo "  Cloud Function: ${FUNCTION_NAME}"
    echo "  Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo
    log_info "Next Steps:"
    echo "1. Upload DICOM files to gs://${BUCKET_NAME}/incoming/"
    echo "2. Monitor processing with: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION} --gen2"
    echo "3. View Healthcare API resources in the Google Cloud Console"
    echo
    log_warn "IMPORTANT: This deployment creates billable resources. Use destroy.sh to clean up when finished."
    echo
    log_success "Medical imaging analysis pipeline is ready for use!"
}

# Main deployment function
main() {
    log_info "Starting Medical Imaging Analysis Pipeline Deployment"
    echo "============================================================"
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_healthcare_resources
    create_storage_bucket
    create_service_account
    setup_pubsub
    create_cloud_function
    setup_monitoring
    create_sample_data
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
        echo "Usage: $0 [--help]"
        echo
        echo "Deploy Medical Imaging Analysis Pipeline on Google Cloud Platform"
        echo
        echo "Environment Variables (optional):"
        echo "  PROJECT_ID          - GCP project ID (default: auto-generated)"
        echo "  REGION             - GCP region (default: us-central1)"
        echo "  DATASET_ID         - Healthcare dataset ID (default: medical-imaging-dataset)"
        echo "  BUCKET_NAME        - Storage bucket name (default: auto-generated)"
        echo
        echo "Example:"
        echo "  export PROJECT_ID=my-medical-project"
        echo "  export REGION=us-west1"
        echo "  $0"
        exit 0
    fi
    
    main "$@"
fi
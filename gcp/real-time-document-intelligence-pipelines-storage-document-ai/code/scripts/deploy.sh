#!/bin/bash

# Real-Time Document Intelligence Pipelines Deployment Script
# This script deploys the complete infrastructure for a document processing pipeline
# using Google Cloud Storage, Document AI, Cloud Pub/Sub, and Cloud Functions

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Run 'gcloud auth login' to authenticate"
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        error "No default project set. Run 'gcloud config set project YOUR_PROJECT_ID'"
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Core environment variables
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export LOCATION="${LOCATION:-us}"
    export PROCESSOR_DISPLAY_NAME="${PROCESSOR_DISPLAY_NAME:-doc-intelligence-processor}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BUCKET_NAME="${BUCKET_NAME:-documents-${RANDOM_SUFFIX}}"
    export TOPIC_NAME="${TOPIC_NAME:-document-events-${RANDOM_SUFFIX}}"
    export RESULTS_TOPIC="${RESULTS_TOPIC:-document-results-${RANDOM_SUFFIX}}"
    export SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-process-docs-${RANDOM_SUFFIX}}"
    export RESULTS_SUBSCRIPTION="${RESULTS_SUBSCRIPTION:-consume-results-${RANDOM_SUFFIX}}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    info "Environment configured for project: ${PROJECT_ID}"
    info "Region: ${REGION}, Location: ${LOCATION}"
    info "Bucket: ${BUCKET_NAME}"
    info "Topics: ${TOPIC_NAME}, ${RESULTS_TOPIC}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "documentai.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "firestore.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
            info "API ${api} is already enabled"
        else
            info "Enabling API: ${api}"
            gcloud services enable "${api}" --quiet
        fi
    done
    
    log "All required APIs enabled ✅"
}

# Function to create Document AI processor
create_document_ai_processor() {
    log "Creating Document AI processor..."
    
    # Check if processor already exists
    local existing_processor
    existing_processor=$(gcloud documentai processors list \
        --location="${LOCATION}" \
        --filter="displayName:${PROCESSOR_DISPLAY_NAME}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${existing_processor}" ]]; then
        export PROCESSOR_ID=$(echo "${existing_processor}" | cut -d'/' -f6)
        info "Using existing Document AI processor: ${PROCESSOR_ID}"
    else
        info "Creating new Document AI processor..."
        gcloud documentai processors create \
            --location="${LOCATION}" \
            --display-name="${PROCESSOR_DISPLAY_NAME}" \
            --type=FORM_PARSER_PROCESSOR \
            --quiet
        
        # Get the processor ID
        export PROCESSOR_ID=$(gcloud documentai processors list \
            --location="${LOCATION}" \
            --filter="displayName:${PROCESSOR_DISPLAY_NAME}" \
            --format="value(name)" | cut -d'/' -f6)
    fi
    
    if [[ -z "${PROCESSOR_ID}" ]]; then
        error "Failed to create or retrieve Document AI processor"
    fi
    
    log "Document AI processor ready: ${PROCESSOR_ID} ✅"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        info "Bucket gs://${BUCKET_NAME} already exists"
    else
        info "Creating bucket: gs://${BUCKET_NAME}"
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Enable versioning for audit trails
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Set uniform bucket-level access
        gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"
    fi
    
    log "Cloud Storage bucket ready ✅"
}

# Function to create Pub/Sub topics and subscriptions
create_pubsub_resources() {
    log "Creating Pub/Sub topics and subscriptions..."
    
    # Create topics
    for topic in "${TOPIC_NAME}" "${RESULTS_TOPIC}"; do
        if gcloud pubsub topics describe "${topic}" &> /dev/null; then
            info "Topic ${topic} already exists"
        else
            info "Creating topic: ${topic}"
            gcloud pubsub topics create "${topic}" --quiet
        fi
    done
    
    # Create subscriptions
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" &> /dev/null; then
        info "Subscription ${SUBSCRIPTION_NAME} already exists"
    else
        info "Creating subscription: ${SUBSCRIPTION_NAME}"
        gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
            --topic="${TOPIC_NAME}" \
            --ack-deadline=600 \
            --quiet
    fi
    
    if gcloud pubsub subscriptions describe "${RESULTS_SUBSCRIPTION}" &> /dev/null; then
        info "Subscription ${RESULTS_SUBSCRIPTION} already exists"
    else
        info "Creating subscription: ${RESULTS_SUBSCRIPTION}"
        gcloud pubsub subscriptions create "${RESULTS_SUBSCRIPTION}" \
            --topic="${RESULTS_TOPIC}" \
            --ack-deadline=300 \
            --quiet
    fi
    
    log "Pub/Sub resources ready ✅"
}

# Function to configure Cloud Storage notifications
configure_bucket_notifications() {
    log "Configuring Cloud Storage notifications..."
    
    # Check if notification already exists
    local existing_notifications
    existing_notifications=$(gsutil notification list "gs://${BUCKET_NAME}" 2>/dev/null || echo "")
    
    if echo "${existing_notifications}" | grep -q "${TOPIC_NAME}"; then
        info "Bucket notifications already configured"
    else
        info "Creating bucket notification for topic: ${TOPIC_NAME}"
        gsutil notification create \
            -t "${TOPIC_NAME}" \
            -f json \
            -e OBJECT_FINALIZE \
            "gs://${BUCKET_NAME}"
    fi
    
    log "Bucket notifications configured ✅"
}

# Function to create Cloud Function for document processing
create_processing_function() {
    log "Creating document processing Cloud Function..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/doc-processor-$$"
    mkdir -p "${temp_dir}"
    
    # Create the main processing function
    cat > "${temp_dir}/main.py" << 'EOF'
import base64
import json
import os
from google.cloud import documentai
from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework

# Initialize clients
document_client = documentai.DocumentProcessorServiceClient()
publisher = pubsub_v1.PublisherClient()
storage_client = storage.Client()

@functions_framework.cloud_event
def process_document(cloud_event):
    """Process uploaded document with Document AI"""
    
    # Parse the Cloud Storage event
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]
    
    # Skip processing if not a document file
    if not file_name.lower().endswith(('.pdf', '.png', '.jpg', '.jpeg', '.tiff')):
        print(f"Skipping non-document file: {file_name}")
        return
    
    try:
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Configure Document AI request
        processor_name = f"projects/{os.environ['PROJECT_ID']}/locations/{os.environ['LOCATION']}/processors/{os.environ['PROCESSOR_ID']}"
        
        # Determine document MIME type
        mime_type = "application/pdf" if file_name.lower().endswith('.pdf') else "image/png"
        
        # Process document with Document AI
        document = documentai.Document(
            content=document_content,
            mime_type=mime_type
        )
        
        request = documentai.ProcessRequest(
            name=processor_name,
            document=document
        )
        
        result = document_client.process_document(request=request)
        
        # Extract text and form fields
        extracted_data = {
            "source_file": file_name,
            "bucket": bucket_name,
            "text": result.document.text,
            "pages": len(result.document.pages),
            "form_fields": [],
            "tables": []
        }
        
        # Extract form fields if available
        for page in result.document.pages:
            for form_field in page.form_fields:
                field_name = ""
                field_value = ""
                
                if form_field.field_name:
                    field_name = form_field.field_name.text_anchor.content
                if form_field.field_value:
                    field_value = form_field.field_value.text_anchor.content
                
                extracted_data["form_fields"].append({
                    "name": field_name.strip(),
                    "value": field_value.strip()
                })
        
        # Publish results to Pub/Sub
        results_topic = f"projects/{os.environ['PROJECT_ID']}/topics/{os.environ['RESULTS_TOPIC']}"
        message_data = json.dumps(extracted_data).encode('utf-8')
        
        publisher.publish(results_topic, message_data)
        
        print(f"Successfully processed {file_name} and published results")
        
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        raise
EOF
    
    # Create requirements file
    cat > "${temp_dir}/requirements.txt" << 'EOF'
google-cloud-documentai==2.25.0
google-cloud-pubsub==2.21.1
google-cloud-storage==2.14.0
functions-framework==3.5.0
EOF
    
    # Check if function already exists
    if gcloud functions describe process-document --region="${REGION}" &> /dev/null; then
        info "Cloud Function process-document already exists, updating..."
        local deploy_cmd="gcloud functions deploy process-document --gen2 --runtime=python311 --region=${REGION} --source=${temp_dir} --entry-point=process_document --trigger-topic=${TOPIC_NAME} --memory=512MB --timeout=540s --max-instances=10 --quiet --update-env-vars=PROJECT_ID=${PROJECT_ID},LOCATION=${LOCATION},PROCESSOR_ID=${PROCESSOR_ID},RESULTS_TOPIC=${RESULTS_TOPIC}"
    else
        info "Creating new Cloud Function: process-document"
        local deploy_cmd="gcloud functions deploy process-document --gen2 --runtime=python311 --region=${REGION} --source=${temp_dir} --entry-point=process_document --trigger-topic=${TOPIC_NAME} --memory=512MB --timeout=540s --max-instances=10 --quiet --set-env-vars=PROJECT_ID=${PROJECT_ID},LOCATION=${LOCATION},PROCESSOR_ID=${PROCESSOR_ID},RESULTS_TOPIC=${RESULTS_TOPIC}"
    fi
    
    # Deploy the function
    if eval "${deploy_cmd}"; then
        log "Document processing function deployed ✅"
    else
        error "Failed to deploy document processing function"
    fi
    
    # Cleanup temporary directory
    rm -rf "${temp_dir}"
}

# Function to create results consumer function
create_consumer_function() {
    log "Creating results consumer Cloud Function..."
    
    # Create temporary directory for consumer function code
    local temp_dir="/tmp/results-consumer-$$"
    mkdir -p "${temp_dir}"
    
    # Create results processing function
    cat > "${temp_dir}/main.py" << 'EOF'
import base64
import json
import functions_framework
from google.cloud import firestore

# Initialize clients
firestore_client = firestore.Client()

@functions_framework.cloud_event
def consume_results(cloud_event):
    """Consume and process Document AI results"""
    
    try:
        # Parse the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        document_data = json.loads(message_data)
        
        # Store results in Firestore for real-time access
        doc_ref = firestore_client.collection('processed_documents').document()
        doc_ref.set({
            'source_file': document_data['source_file'],
            'bucket': document_data['bucket'],
            'text_length': len(document_data['text']),
            'pages': document_data['pages'],
            'form_fields_count': len(document_data['form_fields']),
            'processed_at': firestore.SERVER_TIMESTAMP,
            'form_fields': document_data['form_fields']
        })
        
        # Log processing summary
        print(f"Processed document: {document_data['source_file']}")
        print(f"Pages: {document_data['pages']}")
        print(f"Form fields extracted: {len(document_data['form_fields'])}")
        print(f"Text length: {len(document_data['text'])} characters")
        
        # Example: Extract specific business data
        for field in document_data['form_fields']:
            if 'total' in field['name'].lower() or 'amount' in field['name'].lower():
                print(f"Found financial data - {field['name']}: {field['value']}")
        
        print("✅ Results processed and stored successfully")
        
    except Exception as e:
        print(f"Error consuming results: {str(e)}")
        raise
EOF
    
    # Create requirements for consumer function
    cat > "${temp_dir}/requirements.txt" << 'EOF'
google-cloud-firestore==2.14.0
functions-framework==3.5.0
EOF
    
    # Check if function already exists
    if gcloud functions describe consume-results --region="${REGION}" &> /dev/null; then
        info "Cloud Function consume-results already exists, updating..."
        local deploy_cmd="gcloud functions deploy consume-results --gen2 --runtime=python311 --region=${REGION} --source=${temp_dir} --entry-point=consume_results --trigger-topic=${RESULTS_TOPIC} --memory=256MB --timeout=300s --quiet"
    else
        info "Creating new Cloud Function: consume-results"
        local deploy_cmd="gcloud functions deploy consume-results --gen2 --runtime=python311 --region=${REGION} --source=${temp_dir} --entry-point=consume_results --trigger-topic=${RESULTS_TOPIC} --memory=256MB --timeout=300s --quiet"
    fi
    
    # Deploy the consumer function
    if eval "${deploy_cmd}"; then
        log "Results consumer function deployed ✅"
    else
        error "Failed to deploy results consumer function"
    fi
    
    # Cleanup temporary directory
    rm -rf "${temp_dir}"
}

# Function to test the deployment
test_deployment() {
    log "Testing the document processing pipeline..."
    
    # Create a test document
    local test_file="/tmp/test-invoice-$$.txt"
    cat > "${test_file}" << 'EOF'
Invoice Number: INV-12345
Date: 2025-07-12
Amount: $1,250.00
Customer: ABC Corporation

Description: Professional Services
Tax: $125.00
Total: $1,375.00
EOF
    
    # Upload test document to trigger processing
    info "Uploading test document to trigger processing..."
    if gsutil cp "${test_file}" "gs://${BUCKET_NAME}/test-invoices/"; then
        log "Test document uploaded successfully"
        info "Processing should begin automatically. Check function logs:"
        echo "  gcloud functions logs read process-document --region=${REGION} --limit=10"
        echo "  gcloud functions logs read consume-results --region=${REGION} --limit=10"
    else
        warn "Failed to upload test document"
    fi
    
    # Cleanup test file
    rm -f "${test_file}"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Location: ${LOCATION}"
    echo ""
    echo "Resources Created:"
    echo "- Document AI Processor: ${PROCESSOR_ID}"
    echo "- Storage Bucket: gs://${BUCKET_NAME}"
    echo "- Pub/Sub Topics: ${TOPIC_NAME}, ${RESULTS_TOPIC}"
    echo "- Pub/Sub Subscriptions: ${SUBSCRIPTION_NAME}, ${RESULTS_SUBSCRIPTION}"
    echo "- Cloud Functions: process-document, consume-results"
    echo ""
    echo "To test the pipeline:"
    echo "  gsutil cp your-document.pdf gs://${BUCKET_NAME}/"
    echo ""
    echo "To monitor processing:"
    echo "  gcloud functions logs read process-document --region=${REGION}"
    echo "  gcloud functions logs read consume-results --region=${REGION}"
    echo ""
    echo "To view processed documents in Firestore:"
    echo "  gcloud firestore databases list"
    echo ""
    warn "Remember to run ./destroy.sh when done to avoid ongoing charges!"
}

# Main deployment function
main() {
    log "Starting Real-Time Document Intelligence Pipeline Deployment"
    
    check_prerequisites
    setup_environment
    enable_apis
    create_document_ai_processor
    create_storage_bucket
    create_pubsub_resources
    configure_bucket_notifications
    create_processing_function
    create_consumer_function
    test_deployment
    display_summary
    
    log "🎉 Document Intelligence Pipeline deployed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted"' INT TERM

# Run main function
main "$@"
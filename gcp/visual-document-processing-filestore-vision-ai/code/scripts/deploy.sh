#!/bin/bash

# Deploy Visual Document Processing with Cloud Filestore and Vision AI
# This script deploys the complete infrastructure for automated document processing
# including Filestore, Pub/Sub, Cloud Functions, and supporting resources

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

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_warning "Some resources may have been created. Run destroy.sh to clean up."
    exit $exit_code
}

trap cleanup_on_error ERR

# Configuration and environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Check if project ID is provided as argument or environment variable
    if [[ $# -gt 0 ]]; then
        export PROJECT_ID="$1"
    elif [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="doc-processing-$(date +%s)"
        log_warning "No PROJECT_ID provided. Using generated ID: $PROJECT_ID"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FILESTORE_INSTANCE="docs-filestore-${RANDOM_SUFFIX}"
    export MONITOR_FUNCTION="file-monitor-${RANDOM_SUFFIX}"
    export PROCESSOR_FUNCTION="vision-processor-${RANDOM_SUFFIX}"
    export PUBSUB_TOPIC="document-processing-${RANDOM_SUFFIX}"
    export RESULTS_TOPIC="processing-results-${RANDOM_SUFFIX}"
    export STORAGE_BUCKET="${PROJECT_ID}-processed-docs-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    cat > .deployment_state << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
FILESTORE_INSTANCE=${FILESTORE_INSTANCE}
MONITOR_FUNCTION=${MONITOR_FUNCTION}
PROCESSOR_FUNCTION=${PROCESSOR_FUNCTION}
PUBSUB_TOPIC=${PUBSUB_TOPIC}
RESULTS_TOPIC=${RESULTS_TOPIC}
STORAGE_BUCKET=${STORAGE_BUCKET}
DEPLOYMENT_TIME=$(date -Iseconds)
EOF
    
    log_success "Environment configured for project: $PROJECT_ID"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Configure Google Cloud project
configure_project() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID} || {
        log_error "Failed to set project. Make sure project exists and you have access."
        exit 1
    }
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "file.googleapis.com"
        "vision.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable $api
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Filestore instance
create_filestore() {
    log_info "Creating Cloud Filestore instance..."
    
    # Check if instance already exists
    if gcloud filestore instances describe ${FILESTORE_INSTANCE} --zone=${ZONE} &>/dev/null; then
        log_warning "Filestore instance ${FILESTORE_INSTANCE} already exists"
        export FILESTORE_IP=$(gcloud filestore instances describe ${FILESTORE_INSTANCE} \
            --zone=${ZONE} \
            --format="value(networks.ipAddresses[0])")
        log_info "Using existing instance with IP: ${FILESTORE_IP}"
        return 0
    fi
    
    # Create Filestore instance
    gcloud filestore instances create ${FILESTORE_INSTANCE} \
        --zone=${ZONE} \
        --tier=STANDARD \
        --file-share=name="documents",capacity=1TB \
        --network=name="default"
    
    # Wait for instance to be ready
    log_info "Waiting for Filestore instance to be ready..."
    while [[ $(gcloud filestore instances describe ${FILESTORE_INSTANCE} \
        --zone=${ZONE} \
        --format="value(state)") != "READY" ]]; do
        sleep 30
        echo -n "."
    done
    echo
    
    # Get the Filestore IP address
    export FILESTORE_IP=$(gcloud filestore instances describe ${FILESTORE_INSTANCE} \
        --zone=${ZONE} \
        --format="value(networks.ipAddresses[0])")
    
    log_success "Filestore instance created with IP: ${FILESTORE_IP}"
    
    # Update deployment state
    echo "FILESTORE_IP=${FILESTORE_IP}" >> .deployment_state
}

# Create Pub/Sub topics and subscriptions
create_pubsub() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    # Create topics
    for topic in ${PUBSUB_TOPIC} ${RESULTS_TOPIC}; do
        if gcloud pubsub topics describe $topic &>/dev/null; then
            log_warning "Topic $topic already exists"
        else
            gcloud pubsub topics create $topic
            log_success "Created topic: $topic"
        fi
    done
    
    # Create subscriptions
    if gcloud pubsub subscriptions describe document-processing-sub &>/dev/null; then
        log_warning "Subscription document-processing-sub already exists"
    else
        gcloud pubsub subscriptions create document-processing-sub \
            --topic=${PUBSUB_TOPIC} \
            --ack-deadline=600
        log_success "Created subscription: document-processing-sub"
    fi
    
    if gcloud pubsub subscriptions describe results-sub &>/dev/null; then
        log_warning "Subscription results-sub already exists"
    else
        gcloud pubsub subscriptions create results-sub \
            --topic=${RESULTS_TOPIC} \
            --ack-deadline=300
        log_success "Created subscription: results-sub"
    fi
    
    log_success "Pub/Sub infrastructure created"
}

# Create Cloud Storage bucket
create_storage() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls gs://${STORAGE_BUCKET} &>/dev/null; then
        log_warning "Storage bucket ${STORAGE_BUCKET} already exists"
        return 0
    fi
    
    # Create storage bucket
    gsutil mb -p ${PROJECT_ID} \
        -c STANDARD \
        -l ${REGION} \
        gs://${STORAGE_BUCKET}
    
    # Enable versioning
    gsutil versioning set on gs://${STORAGE_BUCKET}
    
    # Set up lifecycle policy
    cat > /tmp/lifecycle.json << EOF
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
    
    gsutil lifecycle set /tmp/lifecycle.json gs://${STORAGE_BUCKET}
    rm /tmp/lifecycle.json
    
    log_success "Storage bucket created with lifecycle management"
}

# Deploy file monitoring Cloud Function
deploy_monitor_function() {
    log_info "Deploying file monitoring Cloud Function..."
    
    # Create temporary directory for function source
    local func_dir="/tmp/file-monitor-function-$$"
    mkdir -p "$func_dir"
    
    # Create the function source code
    cat > "$func_dir/main.py" << 'EOF'
import os
import json
import hashlib
from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework

# Initialize Pub/Sub client
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(os.environ['PROJECT_ID'], os.environ['PUBSUB_TOPIC'])

@functions_framework.cloud_event
def monitor_documents(cloud_event):
    """Monitor Filestore for new documents and publish to Pub/Sub"""
    
    # In production, this would monitor the actual Filestore mount
    # For this demo, we'll simulate document detection
    filestore_path = f"/mnt/filestore/{os.environ.get('FILESTORE_INSTANCE', 'documents')}"
    
    try:
        # Simulate finding new documents
        new_documents = [
            {"filename": "invoice_001.pdf", "path": f"{filestore_path}/invoices/invoice_001.pdf"},
            {"filename": "receipt_002.jpg", "path": f"{filestore_path}/receipts/receipt_002.jpg"},
            {"filename": "contract_003.png", "path": f"{filestore_path}/contracts/contract_003.png"}
        ]
        
        for doc in new_documents:
            # Create document processing message
            message_data = {
                "filename": doc["filename"],
                "filepath": doc["path"],
                "timestamp": cloud_event.get_time().isoformat(),
                "filestore_ip": os.environ.get('FILESTORE_IP', ''),
                "processing_id": hashlib.md5(doc["path"].encode()).hexdigest()
            }
            
            # Publish to Pub/Sub
            message_json = json.dumps(message_data).encode('utf-8')
            future = publisher.publish(topic_path, message_json)
            
            print(f"Published document for processing: {doc['filename']}")
            
    except Exception as e:
        print(f"Error monitoring documents: {str(e)}")
        raise

EOF
    
    # Create requirements file
    cat > "$func_dir/requirements.txt" << EOF
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
functions-framework==3.4.0
EOF
    
    # Deploy the function
    cd "$func_dir"
    
    # Check if function already exists
    if gcloud functions describe ${MONITOR_FUNCTION} --region=${REGION} &>/dev/null; then
        log_warning "Function ${MONITOR_FUNCTION} already exists, updating..."
        gcloud functions deploy ${MONITOR_FUNCTION} \
            --runtime=python311 \
            --trigger-topic=${PUBSUB_TOPIC} \
            --entry-point=monitor_documents \
            --memory=256MB \
            --timeout=60s \
            --region=${REGION} \
            --update-env-vars="PROJECT_ID=${PROJECT_ID},PUBSUB_TOPIC=${PUBSUB_TOPIC},FILESTORE_IP=${FILESTORE_IP},FILESTORE_INSTANCE=${FILESTORE_INSTANCE}"
    else
        gcloud functions deploy ${MONITOR_FUNCTION} \
            --runtime=python311 \
            --trigger-topic=${PUBSUB_TOPIC} \
            --entry-point=monitor_documents \
            --memory=256MB \
            --timeout=60s \
            --region=${REGION} \
            --set-env-vars="PROJECT_ID=${PROJECT_ID},PUBSUB_TOPIC=${PUBSUB_TOPIC},FILESTORE_IP=${FILESTORE_IP},FILESTORE_INSTANCE=${FILESTORE_INSTANCE}"
    fi
    
    cd - > /dev/null
    rm -rf "$func_dir"
    
    log_success "File monitor function deployed"
}

# Deploy Vision AI processing Cloud Function
deploy_processor_function() {
    log_info "Deploying Vision AI processing Cloud Function..."
    
    # Create temporary directory for function source
    local func_dir="/tmp/vision-processor-function-$$"
    mkdir -p "$func_dir"
    
    # Create the function source code
    cat > "$func_dir/main.py" << 'EOF'
import os
import json
import base64
from google.cloud import vision
from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework
from datetime import datetime

# Initialize clients
vision_client = vision.ImageAnnotatorClient()
publisher = pubsub_v1.PublisherClient()
storage_client = storage.Client()

@functions_framework.cloud_event
def process_document(cloud_event):
    """Process documents with Vision AI and publish results"""
    
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(cloud_event.data["message"]["data"])
        message_data = json.loads(pubsub_message.decode('utf-8'))
        
        filename = message_data.get('filename', '')
        filepath = message_data.get('filepath', '')
        processing_id = message_data.get('processing_id', '')
        
        print(f"Processing document: {filename}")
        
        # Simulate reading document from Filestore
        # In production, you would read from the actual mounted Filestore
        sample_image_content = create_sample_document()
        
        # Process with Vision AI
        image = vision.Image(content=sample_image_content)
        
        # Extract text using OCR
        text_response = vision_client.text_detection(image=image)
        extracted_text = text_response.text_annotations[0].description if text_response.text_annotations else ""
        
        # Detect document features
        features = [
            vision.Feature(type_=vision.Feature.Type.TEXT_DETECTION),
            vision.Feature(type_=vision.Feature.Type.DOCUMENT_TEXT_DETECTION),
            vision.Feature(type_=vision.Feature.Type.LABEL_DETECTION),
        ]
        
        response = vision_client.annotate_image({
            'image': image,
            'features': features
        })
        
        # Extract labels and document structure
        labels = [label.description for label in response.label_annotations]
        
        # Create processing results
        results = {
            "processing_id": processing_id,
            "filename": filename,
            "extracted_text": extracted_text[:1000],  # Truncate for demo
            "labels": labels[:10],  # Top 10 labels
            "confidence_scores": [label.score for label in response.label_annotations[:10]],
            "processing_timestamp": datetime.utcnow().isoformat(),
            "document_type": classify_document(labels, extracted_text),
            "word_count": len(extracted_text.split()) if extracted_text else 0,
            "status": "completed"
        }
        
        # Save results to Cloud Storage
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        blob = bucket.blob(f"processed/{processing_id}/{filename}.json")
        blob.upload_from_string(json.dumps(results, indent=2))
        
        # Publish results to Pub/Sub
        results_topic = publisher.topic_path(os.environ['PROJECT_ID'], os.environ['RESULTS_TOPIC'])
        result_message = json.dumps(results).encode('utf-8')
        publisher.publish(results_topic, result_message)
        
        print(f"Successfully processed: {filename}")
        
    except Exception as e:
        print(f"Error processing document: {str(e)}")
        # Publish error results
        error_results = {
            "processing_id": message_data.get('processing_id', 'unknown'),
            "filename": message_data.get('filename', 'unknown'),
            "error": str(e),
            "status": "failed",
            "processing_timestamp": datetime.utcnow().isoformat()
        }
        
        results_topic = publisher.topic_path(os.environ['PROJECT_ID'], os.environ['RESULTS_TOPIC'])
        error_message = json.dumps(error_results).encode('utf-8')
        publisher.publish(results_topic, error_message)

def create_sample_document():
    """Create a sample document image for demonstration"""
    # This would normally read from Filestore
    # For demo purposes, we'll create a simple text image
    import io
    from PIL import Image, ImageDraw, ImageFont
    
    # Create a simple document image
    img = Image.new('RGB', (800, 600), color='white')
    draw = ImageDraw.Draw(img)
    
    # Add sample text
    sample_text = [
        "INVOICE #12345",
        "Date: 2025-07-12",
        "Customer: Acme Corporation",
        "Amount: $1,234.56",
        "Description: Professional Services"
    ]
    
    y_position = 50
    for line in sample_text:
        draw.text((50, y_position), line, fill='black')
        y_position += 40
    
    # Convert to bytes
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format='PNG')
    return img_byte_arr.getvalue()

def classify_document(labels, text):
    """Simple document classification based on labels and text"""
    text_lower = text.lower() if text else ""
    
    if any(keyword in text_lower for keyword in ['invoice', 'bill', 'amount']):
        return "invoice"
    elif any(keyword in text_lower for keyword in ['receipt', 'purchase', 'store']):
        return "receipt"
    elif any(keyword in text_lower for keyword in ['contract', 'agreement', 'terms']):
        return "contract"
    else:
        return "document"

EOF
    
    # Create requirements file
    cat > "$func_dir/requirements.txt" << EOF
google-cloud-vision==3.4.5
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
functions-framework==3.4.0
Pillow==10.0.1
EOF
    
    # Deploy the function
    cd "$func_dir"
    
    # Check if function already exists
    if gcloud functions describe ${PROCESSOR_FUNCTION} --region=${REGION} &>/dev/null; then
        log_warning "Function ${PROCESSOR_FUNCTION} already exists, updating..."
        gcloud functions deploy ${PROCESSOR_FUNCTION} \
            --runtime=python311 \
            --trigger-topic=${PUBSUB_TOPIC} \
            --entry-point=process_document \
            --memory=512MB \
            --timeout=300s \
            --region=${REGION} \
            --update-env-vars="PROJECT_ID=${PROJECT_ID},RESULTS_TOPIC=${RESULTS_TOPIC},STORAGE_BUCKET=${STORAGE_BUCKET}"
    else
        gcloud functions deploy ${PROCESSOR_FUNCTION} \
            --runtime=python311 \
            --trigger-topic=${PUBSUB_TOPIC} \
            --entry-point=process_document \
            --memory=512MB \
            --timeout=300s \
            --region=${REGION} \
            --set-env-vars="PROJECT_ID=${PROJECT_ID},RESULTS_TOPIC=${RESULTS_TOPIC},STORAGE_BUCKET=${STORAGE_BUCKET}"
    fi
    
    cd - > /dev/null
    rm -rf "$func_dir"
    
    log_success "Vision AI processor function deployed"
}

# Create Compute Engine instance for Filestore access
create_filestore_client() {
    log_info "Creating Compute Engine instance for Filestore access..."
    
    # Check if instance already exists
    if gcloud compute instances describe filestore-client --zone=${ZONE} &>/dev/null; then
        log_warning "Instance filestore-client already exists"
        return 0
    fi
    
    # Create startup script
    local startup_script="#!/bin/bash
sudo apt-get update
sudo apt-get install -y nfs-common
sudo mkdir -p /mnt/filestore
echo \"${FILESTORE_IP}:/documents /mnt/filestore nfs defaults 0 0\" | sudo tee -a /etc/fstab
sudo mount -a
sudo mkdir -p /mnt/filestore/{invoices,receipts,contracts}
sudo chmod 777 /mnt/filestore /mnt/filestore/*
"
    
    # Create instance
    gcloud compute instances create filestore-client \
        --zone=${ZONE} \
        --machine-type=e2-medium \
        --boot-disk-size=20GB \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --scopes=cloud-platform \
        --metadata=startup-script="$startup_script"
    
    log_success "Filestore client instance created"
}

# Test the deployment
test_deployment() {
    log_info "Testing document processing pipeline..."
    
    # Wait for functions to be ready
    sleep 60
    
    # Trigger a test message
    gcloud pubsub topics publish ${PUBSUB_TOPIC} \
        --message='{"filename":"test_invoice.pdf","filepath":"/mnt/filestore/invoices/test_invoice.pdf","timestamp":"2025-07-12T10:00:00Z","processing_id":"test123"}'
    
    log_info "Test message published. Waiting for processing..."
    sleep 30
    
    # Check if processing completed
    if gsutil ls gs://${STORAGE_BUCKET}/processed/ &>/dev/null; then
        log_success "Document processing pipeline is working correctly"
    else
        log_warning "Processing may still be in progress. Check function logs for details."
    fi
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "Resources Created:"
    echo "- Filestore Instance: ${FILESTORE_INSTANCE} (IP: ${FILESTORE_IP})"
    echo "- Pub/Sub Topics: ${PUBSUB_TOPIC}, ${RESULTS_TOPIC}"
    echo "- Cloud Functions: ${MONITOR_FUNCTION}, ${PROCESSOR_FUNCTION}"
    echo "- Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "- Compute Instance: filestore-client"
    echo
    echo "Next Steps:"
    echo "1. Connect to the filestore-client instance to upload documents"
    echo "2. Monitor processing through Cloud Functions logs"
    echo "3. Check processed results in the storage bucket"
    echo
    echo "Useful Commands:"
    echo "- View function logs: gcloud functions logs read ${PROCESSOR_FUNCTION} --region=${REGION}"
    echo "- Check storage contents: gsutil ls -r gs://${STORAGE_BUCKET}/"
    echo "- Connect to client: gcloud compute ssh filestore-client --zone=${ZONE}"
    echo
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    echo "=== Visual Document Processing Deployment ==="
    echo "Starting deployment of Filestore and Vision AI infrastructure..."
    echo
    
    # Execute deployment steps
    setup_environment "$@"
    check_prerequisites
    configure_project
    enable_apis
    create_filestore
    create_pubsub
    create_storage
    deploy_monitor_function
    deploy_processor_function
    create_filestore_client
    test_deployment
    display_summary
    
    log_success "All deployment steps completed successfully!"
}

# Run main function with all arguments
main "$@"
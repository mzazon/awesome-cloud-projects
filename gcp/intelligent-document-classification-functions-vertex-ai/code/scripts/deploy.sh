#!/bin/bash

# deploy.sh - Deployment script for Intelligent Document Classification with Cloud Functions and Vertex AI
# This script deploys the complete infrastructure for automated document classification using GCP services

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
    fi
    
    success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="doc-classifier-$(date +%s)"
        warning "PROJECT_ID not set, using generated: ${PROJECT_ID}"
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
        warning "REGION not set, using default: ${REGION}"
    fi
    
    # Set default zone if not provided
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="us-central1-a"
        warning "ZONE not set, using default: ${ZONE}"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set bucket names with unique suffixes
    export INBOX_BUCKET="doc-inbox-${RANDOM_SUFFIX}"
    export CLASSIFIED_BUCKET="doc-classified-${RANDOM_SUFFIX}"
    
    # Store configuration in file for cleanup script
    cat > .deploy_config << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
INBOX_BUCKET=${INBOX_BUCKET}
CLASSIFIED_BUCKET=${CLASSIFIED_BUCKET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Inbox Bucket: ${INBOX_BUCKET}"
    log "Classified Bucket: ${CLASSIFIED_BUCKET}"
}

# Function to create or use existing project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log "Project ${PROJECT_ID} already exists, using existing project"
    else
        log "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" || error "Failed to create project"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project"
    gcloud config set compute/region "${REGION}" || error "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error "Failed to set zone"
    
    success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com" 
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" || error "Failed to enable ${api}"
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create inbox bucket for document uploads
    log "Creating inbox bucket: ${INBOX_BUCKET}"
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${INBOX_BUCKET}" || error "Failed to create inbox bucket"
    
    # Create classified bucket with folder structure
    log "Creating classified bucket: ${CLASSIFIED_BUCKET}"
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${CLASSIFIED_BUCKET}" || error "Failed to create classified bucket"
    
    # Create folder structure for classified documents
    log "Creating folder structure in classified bucket..."
    echo "" | gsutil cp - "gs://${CLASSIFIED_BUCKET}/contracts/.keep" || error "Failed to create contracts folder"
    echo "" | gsutil cp - "gs://${CLASSIFIED_BUCKET}/invoices/.keep" || error "Failed to create invoices folder"
    echo "" | gsutil cp - "gs://${CLASSIFIED_BUCKET}/reports/.keep" || error "Failed to create reports folder"
    echo "" | gsutil cp - "gs://${CLASSIFIED_BUCKET}/other/.keep" || error "Failed to create other folder"
    
    success "Storage buckets created with classification folders"
}

# Function to create service account
create_service_account() {
    log "Creating service account for Cloud Function..."
    
    local service_account_name="doc-classifier-sa"
    local service_account_email="${service_account_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        log "Service account ${service_account_email} already exists"
    else
        # Create service account
        gcloud iam service-accounts create "${service_account_name}" \
            --display-name "Document Classifier Service Account" \
            --description "Service account for document classification function" || error "Failed to create service account"
    fi
    
    # Grant necessary permissions
    log "Granting IAM permissions..."
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account_email}" \
        --role="roles/aiplatform.user" || error "Failed to grant aiplatform.user role"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account_email}" \
        --role="roles/storage.objectAdmin" || error "Failed to grant storage.objectAdmin role"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account_email}" \
        --role="roles/logging.logWriter" || error "Failed to grant logging.logWriter role"
    
    success "Service account created with required permissions"
}

# Function to create Cloud Function code
create_function_code() {
    log "Creating Cloud Function code..."
    
    # Create function directory
    local function_dir="doc-classifier-function"
    mkdir -p "${function_dir}"
    
    # Create main function file
    cat > "${function_dir}/main.py" << 'EOF'
import os
import json
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
from google.cloud import logging
import functions_framework

# Initialize clients
storage_client = storage.Client()
logging_client = logging.Client()
logger = logging_client.logger("document-classifier")

# Initialize Vertex AI
project_id = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
vertexai.init(project=project_id, location='us-central1')

@functions_framework.cloud_event
def classify_document(cloud_event):
    """Cloud Function triggered by Cloud Storage uploads."""
    
    try:
        # Extract file information from event
        bucket_name = cloud_event.data["bucket"]
        file_name = cloud_event.data["name"]
        
        logger.log_text(f"Processing document: {file_name}")
        
        # Skip if already processed or is a .keep file
        if file_name.endswith('.keep') or 'classified/' in file_name:
            return
        
        # Download and read document content
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Read text content (assuming text files for demo)
        try:
            document_content = blob.download_as_text()
        except Exception as e:
            logger.log_text(f"Error reading file {file_name}: {str(e)}")
            return
        
        # Classify document using Vertex AI Gemini
        classification = classify_with_gemini(document_content, file_name)
        
        # Move document to appropriate folder
        move_to_classified_folder(file_name, classification)
        
        logger.log_text(f"Successfully classified {file_name} as {classification}")
        
    except Exception as e:
        logger.log_text(f"Error processing document: {str(e)}")
        raise

def classify_with_gemini(content, filename):
    """Use Vertex AI Gemini to classify document content."""
    
    try:
        model = GenerativeModel("gemini-1.5-flash")
        
        prompt = f"""
        Analyze the following document content and classify it into one of these categories:
        - contracts: Legal agreements, terms of service, contracts
        - invoices: Bills, invoices, payment requests, receipts
        - reports: Business reports, analytics, summaries, presentations
        - other: Any other document type
        
        Document filename: {filename}
        Document content: {content[:2000]}
        
        Respond with only the category name (contracts, invoices, reports, or other).
        """
        
        response = model.generate_content(prompt)
        classification = response.text.strip().lower()
        
        # Validate classification
        valid_categories = ['contracts', 'invoices', 'reports', 'other']
        if classification not in valid_categories:
            classification = 'other'
            
        return classification
        
    except Exception as e:
        logger.log_text(f"Error with Gemini classification: {str(e)}")
        return 'other'

def move_to_classified_folder(filename, classification):
    """Move document to appropriate classified folder."""
    
    classified_bucket_name = os.environ.get('CLASSIFIED_BUCKET')
    inbox_bucket_name = os.environ.get('INBOX_BUCKET')
    
    # Source and destination
    source_bucket = storage_client.bucket(inbox_bucket_name)
    dest_bucket = storage_client.bucket(classified_bucket_name)
    
    source_blob = source_bucket.blob(filename)
    dest_blob_name = f"{classification}/{filename}"
    
    # Copy to classified bucket
    dest_bucket.copy_blob(source_blob, dest_bucket, dest_blob_name)
    
    # Delete from inbox
    source_blob.delete()
    
    logger.log_text(f"Moved {filename} to {classification} folder")
EOF
    
    # Create requirements file
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.17.0
google-cloud-aiplatform==1.60.0
google-cloud-logging==3.11.0
functions-framework==3.8.0
EOF
    
    success "Cloud Function code created in ${function_dir}/"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function with storage trigger..."
    
    local function_dir="doc-classifier-function"
    local service_account_email="doc-classifier-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    cd "${function_dir}"
    
    # Deploy Cloud Function with Cloud Storage trigger
    gcloud functions deploy classify-documents \
        --gen2 \
        --runtime python312 \
        --trigger-bucket "${INBOX_BUCKET}" \
        --source . \
        --entry-point classify_document \
        --memory 512MiB \
        --timeout 540s \
        --service-account "${service_account_email}" \
        --set-env-vars "CLASSIFIED_BUCKET=${CLASSIFIED_BUCKET},INBOX_BUCKET=${INBOX_BUCKET}" \
        --region "${REGION}" || error "Failed to deploy Cloud Function"
    
    cd ..
    
    success "Cloud Function deployed successfully"
}

# Function to create and upload sample documents
create_sample_documents() {
    log "Creating sample documents for testing..."
    
    # Create sample contract document
    cat > sample_contract.txt << 'EOF'
SERVICE AGREEMENT

This Service Agreement ("Agreement") is entered into on January 15, 2025, between TechCorp Inc. ("Provider") and BusinessCo LLC ("Client").

1. SCOPE OF SERVICES
Provider agrees to deliver software development services including application design, development, and maintenance as specified in Statement of Work documents.

2. TERM AND TERMINATION
This Agreement shall commence on February 1, 2025, and continue for a period of twelve (12) months unless terminated earlier in accordance with the terms herein.

3. COMPENSATION
Client agrees to pay Provider a monthly fee of $10,000 for services rendered under this Agreement.

4. CONFIDENTIALITY
Both parties acknowledge that they may have access to confidential information and agree to maintain strict confidentiality.

This Agreement constitutes the entire agreement between the parties.
EOF
    
    # Create sample invoice document
    cat > sample_invoice.txt << 'EOF'
INVOICE #INV-2025-0142

Date: January 12, 2025
Due Date: February 11, 2025

Bill To:
BusinessCo LLC
123 Main Street
Business City, BC 12345

From:
TechCorp Inc.
456 Tech Avenue
Tech City, TC 67890

Description of Services:
- Software Development Services (January 2025)
- Monthly Retainer Fee
- Additional Feature Development (15 hours @ $150/hour)

Subtotal: $10,000.00
Additional Development: $2,250.00
Tax (8.5%): $1,041.25
TOTAL AMOUNT DUE: $13,291.25

Payment Terms: Net 30 days
Please remit payment to: accounts@techcorp.com
EOF
    
    # Create sample report document
    cat > sample_report.txt << 'EOF'
QUARTERLY BUSINESS REPORT - Q4 2024

Executive Summary:
This report presents the business performance metrics and key achievements for Q4 2024. Overall performance exceeded expectations with significant growth in customer acquisition and revenue.

Key Metrics:
- Revenue: $2.5M (15% increase from Q3)
- New Customers: 1,250 (22% increase)
- Customer Satisfaction: 94% (up from 91%)
- Employee Retention: 96%

Notable Achievements:
1. Launched new product line generating $400K in first month
2. Expanded to three new geographic markets
3. Implemented AI-powered customer service reducing response time by 40%

Challenges and Mitigation:
- Supply chain delays addressed through diversified vendor strategy
- Increased competition managed through enhanced product differentiation

Outlook for Q1 2025:
Projected continued growth with focus on international expansion and product innovation.
EOF
    
    success "Sample documents created"
}

# Function to test the deployment
test_deployment() {
    log "Testing document classification system..."
    
    # Upload sample documents to trigger classification
    log "Uploading sample documents..."
    gsutil cp sample_contract.txt "gs://${INBOX_BUCKET}/" || error "Failed to upload contract sample"
    gsutil cp sample_invoice.txt "gs://${INBOX_BUCKET}/" || error "Failed to upload invoice sample"
    gsutil cp sample_report.txt "gs://${INBOX_BUCKET}/" || error "Failed to upload report sample"
    
    log "Documents uploaded. Waiting for classification processing..."
    sleep 60
    
    # Check if documents were classified and moved
    log "Checking classification results..."
    gsutil ls -r "gs://${CLASSIFIED_BUCKET}/"
    
    success "Test deployment completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo ""
    echo "🚀 Intelligent Document Classification System Deployed Successfully!"
    echo ""
    echo "📋 Resources Created:"
    echo "   • Project: ${PROJECT_ID}"
    echo "   • Inbox Bucket: gs://${INBOX_BUCKET}"
    echo "   • Classified Bucket: gs://${CLASSIFIED_BUCKET}"
    echo "   • Cloud Function: classify-documents"
    echo "   • Service Account: doc-classifier-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "📊 Usage:"
    echo "   • Upload documents to: gs://${INBOX_BUCKET}"
    echo "   • Find classified documents in: gs://${CLASSIFIED_BUCKET}"
    echo ""
    echo "🔍 Monitoring:"
    echo "   • Function Logs: gcloud functions logs read classify-documents --gen2 --region=${REGION}"
    echo "   • Storage Contents: gsutil ls -r gs://${CLASSIFIED_BUCKET}/"
    echo ""
    echo "🧹 Cleanup:"
    echo "   • Run: ./destroy.sh"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting deployment of Intelligent Document Classification system..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_buckets
    create_service_account
    create_function_code
    deploy_cloud_function
    create_sample_documents
    test_deployment
    display_summary
    
    log "Deployment process completed!"
}

# Handle script interruption
cleanup_on_exit() {
    warning "Script interrupted. Cleaning up temporary files..."
    rm -f sample_*.txt
    exit 1
}

trap cleanup_on_exit INT TERM

# Show usage if help requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Intelligent Document Classification with Cloud Functions and Vertex AI"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID    Google Cloud Project ID (default: auto-generated)"
    echo "  REGION        GCP Region (default: us-central1)"
    echo "  ZONE          GCP Zone (default: us-central1-a)"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh                              # Deploy with defaults"
    echo "  PROJECT_ID=my-project ./deploy.sh        # Deploy with custom project"
    echo "  REGION=us-west1 ./deploy.sh             # Deploy in different region"
    exit 0
fi

# Run main deployment
main
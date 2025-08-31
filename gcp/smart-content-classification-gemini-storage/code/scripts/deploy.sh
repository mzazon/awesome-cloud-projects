#!/bin/bash

#
# Smart Content Classification with Gemini and Cloud Storage - Deployment Script
# 
# This script deploys a complete content classification system using:
# - Cloud Storage buckets for staging and classification
# - Cloud Functions for AI-powered content processing
# - Vertex AI Gemini 2.5 Pro for intelligent classification
# - Service accounts with least-privilege access
#
# Prerequisites:
# - Google Cloud CLI (gcloud) installed and authenticated
# - Active Google Cloud project with billing enabled
# - Vertex AI API access
#

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
error_exit() {
    log_error "$1"
    exit 1
}

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FUNCTION_SOURCE_DIR="${SCRIPT_DIR}/../terraform/function_source"
readonly DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Deployment configuration
export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"

# Generate unique identifiers
readonly TIMESTAMP=$(date +%s)
readonly RANDOM_SUFFIX=$(openssl rand -hex 3)

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active Google Cloud authentication found. Please run 'gcloud auth login'."
    fi
    
    # Check if a project is set
    if ! gcloud config get-value project &> /dev/null; then
        error_exit "No Google Cloud project is set. Please run 'gcloud config set project PROJECT_ID'."
    fi
    
    # Check if billing is enabled
    readonly CURRENT_PROJECT=$(gcloud config get-value project)
    if ! gcloud beta billing projects describe "${CURRENT_PROJECT}" &> /dev/null; then
        log_warning "Unable to verify billing status. Please ensure billing is enabled for project: ${CURRENT_PROJECT}"
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Use current project or create new one
    if [[ "${USE_CURRENT_PROJECT:-false}" == "true" ]]; then
        export PROJECT_ID=$(gcloud config get-value project)
        log_info "Using current project: ${PROJECT_ID}"
    else
        export PROJECT_ID="${PROJECT_ID:-content-classifier-${TIMESTAMP}}"
        log_info "Project ID set to: ${PROJECT_ID}"
    fi
    
    # Resource names with unique suffixes
    export STAGING_BUCKET="staging-content-${RANDOM_SUFFIX}"
    export CONTRACTS_BUCKET="contracts-${RANDOM_SUFFIX}"
    export INVOICES_BUCKET="invoices-${RANDOM_SUFFIX}"
    export MARKETING_BUCKET="marketing-${RANDOM_SUFFIX}"
    export MISC_BUCKET="miscellaneous-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT="content-classifier-sa"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
STAGING_BUCKET=${STAGING_BUCKET}
CONTRACTS_BUCKET=${CONTRACTS_BUCKET}
INVOICES_BUCKET=${INVOICES_BUCKET}
MARKETING_BUCKET=${MARKETING_BUCKET}
MISC_BUCKET=${MISC_BUCKET}
SERVICE_ACCOUNT=${SERVICE_ACCOUNT}
DEPLOYMENT_TIMESTAMP=${TIMESTAMP}
EOF
    
    log_success "Environment variables configured and saved to .env file"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set project if creating new one
    if [[ "${USE_CURRENT_PROJECT:-false}" != "true" ]]; then
        # Note: In practice, you would need to create the project first
        # This is a placeholder for demonstration
        log_warning "Project creation not implemented in this script. Please create project '${PROJECT_ID}' manually if it doesn't exist."
    fi
    
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudfunctions.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            error_exit "Failed to enable ${api}"
        fi
    done
    
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    # Create staging bucket
    log_info "Creating staging bucket: gs://${STAGING_BUCKET}"
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${STAGING_BUCKET}"; then
        log_success "Created staging bucket: gs://${STAGING_BUCKET}"
    else
        error_exit "Failed to create staging bucket"
    fi
    
    # Create classification buckets
    local buckets=("${CONTRACTS_BUCKET}" "${INVOICES_BUCKET}" "${MARKETING_BUCKET}" "${MISC_BUCKET}")
    
    for bucket in "${buckets[@]}"; do
        log_info "Creating classification bucket: gs://${bucket}"
        if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket}"; then
            log_success "Created bucket: gs://${bucket}"
        else
            error_exit "Failed to create bucket: gs://${bucket}"
        fi
    done
    
    log_success "All storage buckets created successfully"
}

# Create service account
create_service_account() {
    log_info "Creating service account for Cloud Function..."
    
    # Create service account
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT}" \
        --display-name="Content Classifier Service Account" \
        --description="Service account for AI-powered content classification"; then
        log_success "Created service account: ${SERVICE_ACCOUNT}"
    else
        # Check if service account already exists
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
            log_warning "Service account already exists: ${SERVICE_ACCOUNT}"
        else
            error_exit "Failed to create service account"
        fi
    fi
    
    # Assign IAM roles
    local roles=(
        "roles/aiplatform.user"
        "roles/storage.admin"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log_info "Assigning role ${role} to service account..."
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" --quiet; then
            log_success "Assigned role: ${role}"
        else
            error_exit "Failed to assign role: ${role}"
        fi
    done
    
    log_success "Service account created and configured with appropriate permissions"
}

# Prepare Cloud Function source code
prepare_function_source() {
    log_info "Preparing Cloud Function source code..."
    
    # Create temporary directory for function source
    local temp_dir=$(mktemp -d)
    readonly FUNCTION_DEPLOY_DIR="${temp_dir}/cloud-function"
    mkdir -p "${FUNCTION_DEPLOY_DIR}"
    
    # Copy source files if they exist, otherwise create them
    if [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        log_info "Copying existing function source from ${FUNCTION_SOURCE_DIR}"
        cp -r "${FUNCTION_SOURCE_DIR}"/* "${FUNCTION_DEPLOY_DIR}/"
    else
        log_info "Creating function source code..."
        
        # Create requirements.txt
        cat > "${FUNCTION_DEPLOY_DIR}/requirements.txt" << 'EOF'
google-cloud-aiplatform==1.70.0
google-cloud-storage==2.18.0
google-cloud-logging==3.11.0
functions-framework==3.8.0
Pillow==10.4.0
EOF
        
        # Create main.py
        cat > "${FUNCTION_DEPLOY_DIR}/main.py" << 'EOF'
import json
import logging
import os
from google.cloud import aiplatform
from google.cloud import storage
from google.cloud import logging as cloud_logging
import vertexai
from vertexai.generative_models import GenerativeModel, Part
import mimetypes

# Initialize cloud logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = os.environ.get('FUNCTION_REGION', 'us-central1')
vertexai.init(project=PROJECT_ID, location=REGION)

# Initialize clients
storage_client = storage.Client()
model = GenerativeModel("gemini-2.5-pro")

# Classification bucket mapping
CLASSIFICATION_BUCKETS = {
    'contracts': os.environ.get('CONTRACTS_BUCKET'),
    'invoices': os.environ.get('INVOICES_BUCKET'),
    'marketing': os.environ.get('MARKETING_BUCKET'),
    'miscellaneous': os.environ.get('MISC_BUCKET')
}

def classify_content_with_gemini(file_content, file_name, mime_type):
    """Classify content using Gemini 2.5 multimodal capabilities."""
    
    classification_prompt = """
    Analyze the provided content and classify it into one of these categories:
    
    1. CONTRACTS: Legal agreements, terms of service, NDAs, employment contracts, vendor agreements
    2. INVOICES: Bills, receipts, purchase orders, financial statements, payment requests
    3. MARKETING: Promotional materials, advertisements, brochures, marketing campaigns, social media content
    4. MISCELLANEOUS: Any content that doesn't fit the above categories
    
    Consider:
    - Document structure and layout
    - Text content and terminology
    - Visual elements and design
    - Business context and purpose
    
    Respond with ONLY the category name (contracts, invoices, marketing, or miscellaneous).
    Provide your reasoning in a second line.
    """
    
    try:
        # Handle different content types
        if mime_type.startswith('image/'):
            # Image content
            image_part = Part.from_data(file_content, mime_type)
            response = model.generate_content([classification_prompt, image_part])
        elif mime_type.startswith('text/') or 'document' in mime_type:
            # Text content
            if isinstance(file_content, bytes):
                text_content = file_content.decode('utf-8', errors='ignore')
            else:
                text_content = str(file_content)
            
            combined_prompt = f"{classification_prompt}\n\nContent to classify:\n{text_content[:2000]}"
            response = model.generate_content(combined_prompt)
        else:
            # Default handling for other file types
            combined_prompt = f"{classification_prompt}\n\nFile: {file_name}\nMIME Type: {mime_type}"
            response = model.generate_content(combined_prompt)
        
        # Extract classification from response
        response_text = response.text.strip().lower()
        lines = response_text.split('\n')
        classification = lines[0].strip()
        reasoning = lines[1] if len(lines) > 1 else "No reasoning provided"
        
        # Validate classification
        if classification in CLASSIFICATION_BUCKETS:
            return classification, reasoning
        else:
            return 'miscellaneous', f"Unknown classification: {classification}"
            
    except Exception as e:
        logger.error(f"Error in Gemini classification: {e}")
        return 'miscellaneous', f"Classification error: {str(e)}"

def move_file_to_classified_bucket(source_bucket, source_blob_name, classification):
    """Move file to appropriate classification bucket."""
    
    try:
        target_bucket_name = CLASSIFICATION_BUCKETS[classification]
        if not target_bucket_name:
            logger.error(f"No bucket configured for classification: {classification}")
            return False
        
        # Get source blob
        source_bucket_obj = storage_client.bucket(source_bucket)
        source_blob = source_bucket_obj.blob(source_blob_name)
        
        # Get target bucket
        target_bucket_obj = storage_client.bucket(target_bucket_name)
        
        # Copy to target bucket
        target_blob = target_bucket_obj.blob(source_blob_name)
        target_blob.upload_from_string(
            source_blob.download_as_bytes(),
            content_type=source_blob.content_type
        )
        
        # Add metadata
        target_blob.metadata = {
            'classification': classification,
            'classified_by': 'gemini-2.5-pro',
            'original_bucket': source_bucket
        }
        target_blob.patch()
        
        # Delete from source
        source_blob.delete()
        
        logger.info(f"Moved {source_blob_name} to {target_bucket_name}")
        return True
        
    except Exception as e:
        logger.error(f"Error moving file: {e}")
        return False

def content_classifier(cloud_event):
    """Main Cloud Function entry point."""
    
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data['bucket']
        blob_name = data['name']
        
        logger.info(f"Processing file: {blob_name} from bucket: {bucket_name}")
        
        # Skip if already in a classification bucket
        if bucket_name in CLASSIFICATION_BUCKETS.values():
            logger.info(f"File already in classification bucket, skipping")
            return
        
        # Download file content
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        
        # Get file metadata
        blob.reload()
        mime_type = blob.content_type or mimetypes.guess_type(blob_name)[0] or 'application/octet-stream'
        
        # Download content (limit size for processing)
        if blob.size > 10 * 1024 * 1024:  # 10MB limit
            logger.warning(f"File too large for processing: {blob.size} bytes")
            classification = 'miscellaneous'
            reasoning = "File too large for content analysis"
        else:
            file_content = blob.download_as_bytes()
            classification, reasoning = classify_content_with_gemini(file_content, blob_name, mime_type)
        
        logger.info(f"Classification: {classification}, Reasoning: {reasoning}")
        
        # Move file to appropriate bucket
        success = move_file_to_classified_bucket(bucket_name, blob_name, classification)
        
        if success:
            logger.info(f"Successfully classified and moved {blob_name} to {classification}")
        else:
            logger.error(f"Failed to move {blob_name} to {classification}")
        
    except Exception as e:
        logger.error(f"Error in content classification: {e}")

if __name__ == "__main__":
    # For local testing
    print("Content Classifier Cloud Function")
EOF
    fi
    
    log_success "Cloud Function source code prepared in ${FUNCTION_DEPLOY_DIR}"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function with storage trigger..."
    
    # Change to function directory for deployment
    cd "${FUNCTION_DEPLOY_DIR}"
    
    # Deploy function with all required configuration
    if gcloud functions deploy content-classifier \
        --gen2 \
        --runtime python39 \
        --source . \
        --entry-point content_classifier \
        --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
        --trigger-event-filters="bucket=${STAGING_BUCKET}" \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory 1024MB \
        --timeout 540s \
        --max-instances 10 \
        --set-env-vars="CONTRACTS_BUCKET=${CONTRACTS_BUCKET},INVOICES_BUCKET=${INVOICES_BUCKET},MARKETING_BUCKET=${MARKETING_BUCKET},MISC_BUCKET=${MISC_BUCKET}" \
        --region "${REGION}" \
        --quiet; then
        
        log_success "Cloud Function deployed successfully"
    else
        error_exit "Failed to deploy Cloud Function"
    fi
    
    # Return to script directory
    cd "${SCRIPT_DIR}"
    
    log_info "Waiting for function deployment to complete..."
    sleep 30
    
    log_success "Function will automatically process files uploaded to gs://${STAGING_BUCKET}"
}

# Create sample test files
create_test_files() {
    log_info "Creating sample test files..."
    
    # Create sample contract document
    cat > "${SCRIPT_DIR}/sample_contract.txt" << 'EOF'
NON-DISCLOSURE AGREEMENT

This Non-Disclosure Agreement ("Agreement") is entered into on [Date] by and between:

Company ABC, a corporation organized under the laws of [State] ("Disclosing Party")
Company XYZ, a corporation organized under the laws of [State] ("Receiving Party")

WHEREAS, the parties wish to engage in discussions regarding potential business opportunities;
WHEREAS, such discussions may involve disclosure of confidential information;

NOW THEREFORE, the parties agree as follows:

1. CONFIDENTIAL INFORMATION: Any information disclosed by one party to the other, whether oral, written, or electronic, shall be considered confidential.

2. NON-DISCLOSURE: The Receiving Party agrees not to disclose any confidential information to third parties.

3. TERM: This Agreement shall remain in effect for a period of three (3) years from the date of execution.

IN WITNESS WHEREOF, the parties have executed this Agreement.
EOF
    
    # Create sample invoice document
    cat > "${SCRIPT_DIR}/sample_invoice.txt" << 'EOF'
INVOICE

Invoice Number: INV-2025-001
Date: January 15, 2025

Bill To:
ABC Corporation
123 Business Street
City, State 12345

From:
XYZ Services LLC
456 Service Avenue
City, State 67890

Description                    Quantity    Rate        Total
Professional Services         40 hours    $150/hour   $6,000.00
Project Management            1 month     $2,000      $2,000.00
                                                      ----------
                                          Subtotal:   $8,000.00
                                          Tax (8.5%): $680.00
                                          TOTAL:      $8,680.00

Payment Terms: Net 30 days
Due Date: February 14, 2025

Thank you for your business!
EOF
    
    # Create sample marketing content
    cat > "${SCRIPT_DIR}/sample_marketing.txt" << 'EOF'
EXCITING NEW PRODUCT LAUNCH!

🚀 Introducing CloudMax Pro - The Future of Cloud Computing

Are you ready to revolutionize your business operations?

CloudMax Pro delivers:
✅ 99.99% uptime guarantee
✅ Lightning-fast performance
✅ Enterprise-grade security
✅ 24/7 expert support

LIMITED TIME OFFER: 50% OFF your first year!

Join thousands of satisfied customers who have transformed their business with CloudMax Pro.

Don't miss out - this exclusive offer expires January 31st!

CLICK HERE TO GET STARTED TODAY!

Contact us: sales@cloudmax.com | 1-800-CLOUDMAX
Follow us on social media for more updates and special offers!

#CloudComputing #DigitalTransformation #TechInnovation
EOF
    
    log_success "Sample test files created for classification testing"
}

# Test the deployment (optional)
test_deployment() {
    if [[ "${SKIP_TESTING:-false}" == "true" ]]; then
        log_info "Skipping deployment testing as requested"
        return 0
    fi
    
    log_info "Testing the deployment with sample files..."
    
    # Upload sample files to trigger classification
    log_info "Uploading test files to staging bucket..."
    
    if gsutil cp "${SCRIPT_DIR}/sample_contract.txt" "gs://${STAGING_BUCKET}/"; then
        log_success "Uploaded sample_contract.txt"
    else
        log_warning "Failed to upload sample_contract.txt"
    fi
    
    if gsutil cp "${SCRIPT_DIR}/sample_invoice.txt" "gs://${STAGING_BUCKET}/"; then
        log_success "Uploaded sample_invoice.txt"
    else
        log_warning "Failed to upload sample_invoice.txt"
    fi
    
    if gsutil cp "${SCRIPT_DIR}/sample_marketing.txt" "gs://${STAGING_BUCKET}/"; then
        log_success "Uploaded sample_marketing.txt"
    else
        log_warning "Failed to upload sample_marketing.txt"
    fi
    
    log_info "Waiting for classification processing (60 seconds)..."
    sleep 60
    
    # Check function logs
    log_info "Checking Cloud Function logs..."
    gcloud functions logs read content-classifier \
        --region "${REGION}" \
        --limit 10 \
        --format "value(timestamp,message)" || log_warning "Could not retrieve function logs"
    
    # Check bucket contents
    log_info "Checking classification results..."
    
    echo "=== Contracts Bucket ==="
    gsutil ls -la "gs://${CONTRACTS_BUCKET}/" 2>/dev/null || echo "No files found"
    
    echo "=== Invoices Bucket ==="
    gsutil ls -la "gs://${INVOICES_BUCKET}/" 2>/dev/null || echo "No files found"
    
    echo "=== Marketing Bucket ==="
    gsutil ls -la "gs://${MARKETING_BUCKET}/" 2>/dev/null || echo "No files found"
    
    echo "=== Miscellaneous Bucket ==="
    gsutil ls -la "gs://${MISC_BUCKET}/" 2>/dev/null || echo "No files found"
    
    echo "=== Staging Bucket (should be empty after processing) ==="
    gsutil ls -la "gs://${STAGING_BUCKET}/" 2>/dev/null || echo "No files found"
    
    log_success "Deployment testing completed"
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment_summary.txt" << EOF
Smart Content Classification Deployment Summary
===============================================

Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}

Resources Created:
------------------
✅ Cloud Storage Buckets:
   - Staging: gs://${STAGING_BUCKET}
   - Contracts: gs://${CONTRACTS_BUCKET}
   - Invoices: gs://${INVOICES_BUCKET}
   - Marketing: gs://${MARKETING_BUCKET}
   - Miscellaneous: gs://${MISC_BUCKET}

✅ Service Account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com

✅ Cloud Function: content-classifier (Gen2, Python 3.9)
   - Memory: 1024MB
   - Timeout: 540s
   - Max Instances: 10
   - Trigger: Cloud Storage object creation on gs://${STAGING_BUCKET}

✅ APIs Enabled:
   - Artifact Registry API
   - Cloud Build API
   - Cloud Functions API
   - Eventarc API
   - Cloud Logging API
   - Cloud Storage API
   - Vertex AI API
   - Cloud Run API

How to Use:
-----------
1. Upload files to the staging bucket: gs://${STAGING_BUCKET}
2. Files will be automatically classified and moved to appropriate buckets
3. Monitor classification logs: gcloud functions logs read content-classifier --region ${REGION}

Sample Upload Command:
gsutil cp your-file.txt gs://${STAGING_BUCKET}/

Cleanup:
--------
To remove all resources, run: ./destroy.sh

Cost Estimation:
----------------
- Cloud Functions: Pay per invocation (~\$0.40 per 1M requests)
- Cloud Storage: ~\$0.020 per GB/month
- Vertex AI Gemini 2.5 Pro: ~\$0.00125 per 1K input tokens
- Estimated monthly cost for 1000 files: \$15-25

For support or issues, refer to the deployment log: ${DEPLOYMENT_LOG}
EOF
    
    log_success "Deployment summary saved to deployment_summary.txt"
}

# Main deployment function
main() {
    log_info "Starting Smart Content Classification deployment..."
    log_info "Deployment log: ${DEPLOYMENT_LOG}"
    
    # Redirect all output to log file while also displaying on console
    exec > >(tee -a "${DEPLOYMENT_LOG}") 2>&1
    
    echo "Deployment started at: $(date)"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_storage_buckets
    create_service_account
    prepare_function_source
    deploy_cloud_function
    create_test_files
    test_deployment
    generate_summary
    
    log_success "🎉 Smart Content Classification system deployed successfully!"
    log_info "📋 Check deployment_summary.txt for complete details"
    log_info "🧪 Test files have been created in the scripts directory"
    log_info "📝 Upload files to gs://${STAGING_BUCKET} to test classification"
    
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Upload test files: gsutil cp sample_*.txt gs://${STAGING_BUCKET}/"
    echo "2. Monitor logs: gcloud functions logs read content-classifier --region ${REGION}"
    echo "3. Check classified files in respective buckets"
    echo "4. When finished, run ./destroy.sh to clean up resources"
    echo ""
    
    log_success "Deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
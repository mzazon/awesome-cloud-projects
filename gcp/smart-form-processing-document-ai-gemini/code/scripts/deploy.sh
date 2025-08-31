#!/bin/bash

# Smart Form Processing with Document AI and Gemini - Deployment Script
# This script deploys the complete infrastructure for intelligent form processing
# using Google Cloud Document AI, Vertex AI Gemini, Cloud Functions, and Cloud Storage

set -euo pipefail

# Colors for output
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

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DEPLOYMENT_LOG="$PROJECT_ROOT/deployment.log"

# Initialize logging
exec 1> >(tee -a "$DEPLOYMENT_LOG")
exec 2>&1

log "Starting Smart Form Processing deployment..."

# Configuration variables
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
CLEANUP_ON_FAILURE=${CLEANUP_ON_FAILURE:-true}

# Default values (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-smart-forms-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
BUCKET_INPUT="${BUCKET_INPUT:-forms-input-${RANDOM_SUFFIX}}"
BUCKET_OUTPUT="${BUCKET_OUTPUT:-forms-output-${RANDOM_SUFFIX}}"

# Track deployed resources for cleanup
DEPLOYED_RESOURCES=()

# Cleanup function for failed deployments
cleanup_on_failure() {
    if [[ "$CLEANUP_ON_FAILURE" == "true" ]]; then
        warning "Deployment failed. Cleaning up resources..."
        "$SCRIPT_DIR/destroy.sh" --force
    else
        warning "Deployment failed. Use destroy.sh to clean up resources."
    fi
}

# Trap cleanup on failure
trap cleanup_on_failure ERR

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        error "openssl is not available. Please install openssl."
    fi
    
    # Check if jq is available (for JSON processing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. JSON output will not be formatted."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][-a-z0-9]{4,28}[a-z0-9]$ ]]; then
        error "Invalid PROJECT_ID format. Must be 6-30 characters, lowercase letters, digits, and hyphens."
    fi
    
    success "Prerequisites check completed"
}

# Project setup function
setup_project() {
    log "Setting up Google Cloud project: $PROJECT_ID"
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log "Using existing project: $PROJECT_ID"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create project: $PROJECT_ID"
            return
        fi
        
        log "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Smart Forms Processing"
        DEPLOYED_RESOURCES+=("project:$PROJECT_ID")
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "Project setup completed"
}

# Enable APIs function
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "documentai.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All APIs enabled successfully"
}

# Create storage buckets function
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create buckets: $BUCKET_INPUT, $BUCKET_OUTPUT"
        return
    fi
    
    # Create input bucket
    log "Creating input bucket: $BUCKET_INPUT"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_INPUT"; then
        success "Created input bucket: $BUCKET_INPUT"
        DEPLOYED_RESOURCES+=("bucket:$BUCKET_INPUT")
    else
        error "Failed to create input bucket: $BUCKET_INPUT"
    fi
    
    # Create output bucket
    log "Creating output bucket: $BUCKET_OUTPUT"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_OUTPUT"; then
        success "Created output bucket: $BUCKET_OUTPUT"
        DEPLOYED_RESOURCES+=("bucket:$BUCKET_OUTPUT")
    else
        error "Failed to create output bucket: $BUCKET_OUTPUT"
    fi
    
    # Set bucket lifecycle policies for cost optimization
    log "Setting up bucket lifecycle policies..."
    cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "NEARLINE"
        },
        "condition": {
          "age": 30
        }
      },
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "COLDLINE"
        },
        "condition": {
          "age": 90
        }
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set /tmp/lifecycle.json "gs://$BUCKET_INPUT"
    gsutil lifecycle set /tmp/lifecycle.json "gs://$BUCKET_OUTPUT"
    rm /tmp/lifecycle.json
    
    success "Storage buckets created and configured"
}

# Create Document AI processor function
create_documentai_processor() {
    log "Creating Document AI Form Parser processor..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Document AI processor in region: $REGION"
        export PROCESSOR_ID="dry-run-processor-id"
        return
    fi
    
    # Create processor
    log "Creating Form Parser processor..."
    if gcloud documentai processors create \
        --display-name="smart-form-processor-${RANDOM_SUFFIX}" \
        --type="FORM_PARSER_PROCESSOR" \
        --location="$REGION" \
        --quiet; then
        
        success "Document AI processor created"
        
        # Get processor ID
        export PROCESSOR_ID=$(gcloud documentai processors list \
            --location="$REGION" \
            --filter="displayName:smart-form-processor-${RANDOM_SUFFIX}" \
            --format="value(name.segment(-1))")
        
        if [[ -z "$PROCESSOR_ID" ]]; then
            error "Failed to retrieve processor ID"
        fi
        
        log "Processor ID: $PROCESSOR_ID"
        DEPLOYED_RESOURCES+=("processor:$PROCESSOR_ID")
        
        # Save processor ID for later use
        echo "PROCESSOR_ID=$PROCESSOR_ID" > "$PROJECT_ROOT/.env"
        
        success "Document AI processor configured: $PROCESSOR_ID"
    else
        error "Failed to create Document AI processor"
    fi
}

# Deploy Cloud Function function
deploy_cloud_function() {
    log "Deploying Cloud Function for form processing..."
    
    local function_dir="$PROJECT_ROOT/function-source"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy Cloud Function from: $function_dir"
        return
    fi
    
    # Create function directory if it doesn't exist
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create requirements.txt
    log "Creating function dependencies..."
    cat > requirements.txt << 'EOF'
google-cloud-documentai==2.30.0
google-cloud-aiplatform==1.71.0
google-cloud-storage==2.18.0
google-auth==2.34.0
functions-framework==3.8.1
vertexai==1.71.0
EOF
    
    # Create main.py with processing logic
    log "Creating function source code..."
    cat > main.py << 'EOF'
import json
import os
from google.cloud import documentai
from google.cloud import aiplatform
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework

# Initialize clients
storage_client = storage.Client()
docai_client = documentai.DocumentProcessorServiceClient()

def process_document_ai(file_content, processor_name):
    """Extract data using Document AI Form Parser"""
    # Create Document AI request
    raw_document = documentai.RawDocument(
        content=file_content,
        mime_type="application/pdf"
    )
    
    request = documentai.ProcessRequest(
        name=processor_name,
        raw_document=raw_document
    )
    
    # Process document
    result = docai_client.process_document(request=request)
    document = result.document
    
    # Extract form fields
    form_fields = {}
    for page in document.pages:
        for form_field in page.form_fields:
            field_name = form_field.field_name.text_anchor.content if form_field.field_name else "unknown"
            field_value = form_field.field_value.text_anchor.content if form_field.field_value else ""
            form_fields[field_name.strip()] = field_value.strip()
    
    # Calculate average confidence
    total_confidence = 0
    field_count = 0
    for page in document.pages:
        for form_field in page.form_fields:
            if form_field.field_value.confidence:
                total_confidence += form_field.field_value.confidence
                field_count += 1
    
    avg_confidence = total_confidence / field_count if field_count > 0 else 0.0
    
    return {
        "extracted_text": document.text,
        "form_fields": form_fields,
        "confidence": avg_confidence
    }

def validate_with_gemini(extracted_data):
    """Validate and enrich data using Gemini"""
    # Initialize Vertex AI
    vertexai.init(
        project=os.environ.get('GCP_PROJECT'), 
        location=os.environ.get('FUNCTION_REGION')
    )
    
    model = GenerativeModel("gemini-1.5-flash")
    
    prompt = f"""
    Analyze this extracted form data and provide validation and enrichment:
    
    Extracted Data: {json.dumps(extracted_data, indent=2)}
    
    Please provide:
    1. Data validation (check for completeness, format errors, inconsistencies)
    2. Data enrichment (suggest corrections, standardize formats)
    3. Confidence score (1-10) for overall data quality
    4. Specific issues found and recommendations
    
    Return response as JSON with keys: validation_results, enriched_data, confidence_score, recommendations
    """
    
    response = model.generate_content(prompt)
    
    try:
        # Parse Gemini response as JSON
        gemini_analysis = json.loads(response.text)
        return gemini_analysis
    except json.JSONDecodeError:
        # Fallback if response isn't valid JSON
        return {
            "validation_results": "Analysis completed",
            "enriched_data": extracted_data,
            "confidence_score": 7,
            "recommendations": response.text
        }

@functions_framework.cloud_event
def process_form(cloud_event):
    """Main Cloud Function triggered by Cloud Storage"""
    # Get file information from event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    if not file_name.endswith('.pdf'):
        print(f"Skipping non-PDF file: {file_name}")
        return
    
    try:
        # Download file from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        file_content = blob.download_as_bytes()
        
        # Process with Document AI
        processor_name = f"projects/{os.environ.get('GCP_PROJECT')}/locations/{os.environ.get('FUNCTION_REGION')}/processors/{os.environ.get('PROCESSOR_ID')}"
        docai_results = process_document_ai(file_content, processor_name)
        
        # Validate with Gemini
        gemini_analysis = validate_with_gemini(docai_results)
        
        # Combine results
        final_results = {
            "source_file": file_name,
            "timestamp": cloud_event.data.get('timeCreated'),
            "document_ai_extraction": docai_results,
            "gemini_analysis": gemini_analysis,
            "processing_complete": True
        }
        
        # Save results to output bucket
        output_bucket = storage_client.bucket(os.environ.get('OUTPUT_BUCKET'))
        output_file = f"processed/{file_name.replace('.pdf', '_results.json')}"
        output_blob = output_bucket.blob(output_file)
        output_blob.upload_from_string(
            json.dumps(final_results, indent=2),
            content_type='application/json'
        )
        
        print(f"Successfully processed {file_name} -> {output_file}")
        
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        raise
EOF
    
    # Deploy the function
    log "Deploying Cloud Function..."
    if gcloud functions deploy process-form \
        --gen2 \
        --runtime=python312 \
        --region="$REGION" \
        --source=. \
        --entry-point=process_form \
        --trigger-bucket="$BUCKET_INPUT" \
        --set-env-vars="GCP_PROJECT=$PROJECT_ID,FUNCTION_REGION=$REGION,PROCESSOR_ID=$PROCESSOR_ID,OUTPUT_BUCKET=$BUCKET_OUTPUT" \
        --memory=1024MB \
        --timeout=540s \
        --max-instances=10 \
        --quiet; then
        
        success "Cloud Function deployed successfully"
        DEPLOYED_RESOURCES+=("function:process-form")
    else
        error "Failed to deploy Cloud Function"
    fi
    
    cd "$SCRIPT_DIR"
}

# Create test form function
create_test_form() {
    log "Creating sample test form..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create test form and upload to: gs://$BUCKET_INPUT"
        return
    fi
    
    # Create sample form content
    cat > "$PROJECT_ROOT/sample_form.txt" << 'EOF'
EMPLOYEE INFORMATION FORM

Full Name: John Smith
Employee ID: EMP-12345
Department: Engineering
Start Date: 2024-01-15
Email: john.smith@company.com
Phone: (555) 123-4567

Agreements:
☑ I agree to company policies
☑ I have read the employee handbook

Signature: _John Smith_
Date: 2024-01-15
EOF
    
    # Upload test form
    log "Uploading test form to trigger processing..."
    if gsutil cp "$PROJECT_ROOT/sample_form.txt" "gs://$BUCKET_INPUT/sample_employee_form.pdf"; then
        success "Test form uploaded - processing should be initiated automatically"
    else
        warning "Failed to upload test form, but deployment is still successful"
    fi
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would validate deployment"
        return
    fi
    
    # Check if buckets exist
    if gsutil ls "gs://$BUCKET_INPUT" &>/dev/null && gsutil ls "gs://$BUCKET_OUTPUT" &>/dev/null; then
        success "Storage buckets are accessible"
    else
        warning "Storage buckets may not be properly configured"
    fi
    
    # Check if processor exists
    if gcloud documentai processors list --location="$REGION" --filter="name:*$PROCESSOR_ID" --format="value(name)" | grep -q "$PROCESSOR_ID"; then
        success "Document AI processor is active"
    else
        warning "Document AI processor may not be properly configured"
    fi
    
    # Check if function exists
    if gcloud functions describe process-form --region="$REGION" &>/dev/null; then
        success "Cloud Function is deployed"
    else
        warning "Cloud Function may not be properly deployed"
    fi
    
    # Wait and check for processed results (if test form was uploaded)
    if [[ -f "$PROJECT_ROOT/sample_form.txt" ]]; then
        log "Waiting 60 seconds for form processing to complete..."
        sleep 60
        
        if gsutil ls "gs://$BUCKET_OUTPUT/processed/" 2>/dev/null | grep -q "sample_employee_form_results.json"; then
            success "Test form processing completed successfully"
            log "Downloading test results..."
            gsutil cp "gs://$BUCKET_OUTPUT/processed/sample_employee_form_results.json" "$PROJECT_ROOT/"
            log "Test results saved to: $PROJECT_ROOT/sample_employee_form_results.json"
        else
            warning "Test form processing may still be in progress or failed"
        fi
    fi
}

# Save deployment info function
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > "$PROJECT_ROOT/deployment-info.json" << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "processor_id": "$PROCESSOR_ID",
  "input_bucket": "$BUCKET_INPUT",
  "output_bucket": "$BUCKET_OUTPUT",
  "function_name": "process-form",
  "deployed_resources": $(printf '%s\n' "${DEPLOYED_RESOURCES[@]}" | jq -R . | jq -s .),
  "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    success "Deployment information saved to: $PROJECT_ROOT/deployment-info.json"
}

# Main deployment function
main() {
    log "Smart Form Processing Deployment Started"
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Input Bucket: $BUCKET_INPUT"
    log "Output Bucket: $BUCKET_OUTPUT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No resources will be created"
    fi
    
    if [[ "$SKIP_CONFIRMATION" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        warning "This will create resources in Google Cloud that may incur charges."
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_storage_buckets
    create_documentai_processor
    deploy_cloud_function
    create_test_form
    validate_deployment
    save_deployment_info
    
    echo
    success "🎉 Smart Form Processing deployment completed successfully!"
    echo
    log "Deployment Summary:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Input Bucket: gs://$BUCKET_INPUT"
    log "  Output Bucket: gs://$BUCKET_OUTPUT"
    log "  Processor ID: $PROCESSOR_ID"
    log "  Function Name: process-form"
    echo
    log "Next Steps:"
    log "  1. Upload PDF forms to gs://$BUCKET_INPUT to trigger processing"
    log "  2. Check gs://$BUCKET_OUTPUT/processed/ for results"
    log "  3. Monitor function logs: gcloud functions logs read process-form --region=$REGION"
    log "  4. Use destroy.sh to clean up resources when done"
    echo
    log "Documentation: See README.md for usage instructions"
    
    # Disable trap
    trap - ERR
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --no-cleanup-on-failure)
            CLEANUP_ON_FAILURE=false
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --dry-run                    Show what would be deployed without creating resources"
            echo "  --skip-confirmation          Skip deployment confirmation prompt"
            echo "  --no-cleanup-on-failure      Don't clean up resources if deployment fails"
            echo "  --project-id PROJECT_ID      Override project ID"
            echo "  --region REGION              Override region (default: us-central1)"
            echo "  --help                       Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PROJECT_ID                   Google Cloud Project ID"
            echo "  REGION                       Deployment region"
            echo "  BUCKET_INPUT                 Input bucket name"
            echo "  BUCKET_OUTPUT                Output bucket name"
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Run main function
main
#!/bin/bash

# Content Accessibility Compliance Deployment Script
# Deploy Document AI and Gemini-based accessibility analysis system

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed or not in PATH"
        error "Please install Google Cloud SDK with gsutil"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed or not in PATH"
        error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "."; then
        error "No active gcloud authentication found"
        error "Please run: gcloud auth login"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to validate project access
validate_project_access() {
    log "Validating project access..."
    
    local project_id="$1"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$project_id" &> /dev/null; then
        error "Cannot access project: $project_id"
        error "Please verify the project ID and your permissions"
        exit 1
    fi
    
    # Check required permissions
    local required_roles=(
        "roles/storage.admin"
        "roles/cloudfunctions.admin"
        "roles/documentai.admin"
        "roles/aiplatform.user"
        "roles/serviceusage.serviceUsageAdmin"
    )
    
    for role in "${required_roles[@]}"; do
        if ! gcloud projects get-iam-policy "$project_id" --flatten="bindings[].members" --format="value(bindings.role)" | grep -q "$role"; then
            warning "Missing IAM role: $role"
            warning "You may need additional permissions for full deployment"
        fi
    done
    
    success "Project access validated"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "documentai.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    success "All APIs enabled successfully"
}

# Function to create storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    local bucket_name="$1"
    local region="$2"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
        warning "Bucket gs://${bucket_name} already exists"
        return 0
    fi
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${region}" "gs://${bucket_name}"; then
        success "Created bucket: gs://${bucket_name}"
    else
        error "Failed to create bucket: gs://${bucket_name}"
        exit 1
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${bucket_name}"; then
        success "Enabled versioning on bucket"
    else
        error "Failed to enable versioning"
        exit 1
    fi
    
    # Create folder structure
    local folders=("uploads" "reports" "processed")
    for folder in "${folders[@]}"; do
        echo "" | gsutil cp - "gs://${bucket_name}/${folder}/placeholder.txt"
        success "Created folder: ${folder}/"
    done
    
    success "Storage bucket setup completed"
}

# Function to create Document AI processor
create_document_ai_processor() {
    log "Creating Document AI processor..."
    
    local processor_name="$1"
    local region="$2"
    
    # Check if processor already exists
    if gcloud documentai processors list --location="${region}" --filter="displayName:${processor_name}" --format="value(name)" | grep -q "."; then
        warning "Document AI processor '${processor_name}' already exists"
        export PROCESSOR_ID=$(gcloud documentai processors list --location="${region}" --filter="displayName:${processor_name}" --format="value(name)" | cut -d'/' -f6)
        log "Using existing processor ID: ${PROCESSOR_ID}"
        return 0
    fi
    
    # Create processor
    if gcloud documentai processors create \
        --location="${region}" \
        --display-name="${processor_name}" \
        --type=OCR_PROCESSOR \
        --quiet; then
        success "Created Document AI processor"
    else
        error "Failed to create Document AI processor"
        exit 1
    fi
    
    # Get processor ID
    export PROCESSOR_ID=$(gcloud documentai processors list \
        --location="${region}" \
        --filter="displayName:${processor_name}" \
        --format="value(name)" | cut -d'/' -f6)
    
    if [[ -z "$PROCESSOR_ID" ]]; then
        error "Failed to retrieve processor ID"
        exit 1
    fi
    
    log "Processor ID: ${PROCESSOR_ID}"
    success "Document AI processor created successfully"
}

# Function to create Cloud Function
create_cloud_function() {
    log "Creating Cloud Function for accessibility analysis..."
    
    local function_name="$1"
    local region="$2"
    local bucket_name="$3"
    local processor_id="$4"
    local project_id="$5"
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-documentai==2.30.0
google-cloud-aiplatform==1.45.0
google-cloud-storage==2.12.0
functions-framework==3.6.0
Pillow==10.2.0
reportlab==4.1.0
EOF
    
    # Create main.py with accessibility analysis logic
    cat > main.py << 'EOF'
import json
import os
from google.cloud import documentai
from google.cloud import aiplatform
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
import tempfile

# Initialize clients
documentai_client = documentai.DocumentProcessorServiceClient()
storage_client = storage.Client()

def analyze_accessibility_with_gemini(document_content, layout_data):
    """Use Gemini to analyze document accessibility against WCAG 2.1 AA guidelines."""
    
    # Initialize Vertex AI
    vertexai.init(project=os.environ['PROJECT_ID'], location=os.environ['REGION'])
    model = GenerativeModel("gemini-1.5-pro")
    
    wcag_prompt = f"""
    You are an accessibility expert evaluating a document against WCAG 2.1 AA guidelines.
    
    Document Layout Analysis:
    {json.dumps(layout_data, indent=2)}
    
    Document Text Content:
    {document_content[:3000]}...
    
    Please evaluate this document against these WCAG 2.1 AA success criteria:
    
    1. Perceivable:
       - Images have appropriate alt text
       - Text has sufficient color contrast (4.5:1 ratio)
       - Content can be presented without loss of meaning
    
    2. Operable:
       - All functionality available via keyboard
       - No content causes seizures or physical reactions
       - Users have enough time to read content
    
    3. Understandable:
       - Text is readable and understandable
       - Content appears and operates predictably
       - Users are helped to avoid and correct mistakes
    
    4. Robust:
       - Content works with assistive technologies
       - Markup is valid and semantic
    
    Provide a detailed JSON response with:
    {{
        "overall_score": "Pass/Fail/Partial",
        "total_issues": number,
        "critical_issues": number,
        "issues": [
            {{
                "guideline": "WCAG guideline number",
                "level": "A/AA/AAA",
                "severity": "Critical/High/Medium/Low",
                "description": "Detailed issue description",
                "location": "Where in document",
                "recommendation": "Specific fix recommendation"
            }}
        ],
        "summary": "Overall accessibility assessment summary"
    }}
    """
    
    try:
        response = model.generate_content(wcag_prompt)
        # Parse JSON response from Gemini
        result = json.loads(response.text.strip().replace('```json', '').replace('```', ''))
        return result
    except Exception as e:
        print(f"Error in Gemini analysis: {e}")
        return {
            "overall_score": "Error",
            "total_issues": 0,
            "critical_issues": 0,
            "issues": [],
            "summary": f"Analysis error: {str(e)}"
        }

def process_document_with_docai(file_content, processor_path):
    """Process document with Document AI to extract structure and content."""
    
    # Create document for processing
    raw_document = documentai.RawDocument(
        content=file_content,
        mime_type="application/pdf"
    )
    
    # Configure processing request
    request = documentai.ProcessRequest(
        name=processor_path,
        raw_document=raw_document
    )
    
    # Process document
    result = documentai_client.process_document(request=request)
    document = result.document
    
    # Extract layout information
    layout_data = {
        "pages": len(document.pages),
        "paragraphs": [],
        "tables": [],
        "form_fields": [],
        "blocks": []
    }
    
    for page in document.pages:
        # Extract paragraphs
        for paragraph in page.paragraphs:
            layout_data["paragraphs"].append({
                "text": get_text(paragraph, document),
                "confidence": paragraph.layout.confidence
            })
        
        # Extract tables
        for table in page.tables:
            table_data = {
                "rows": len(table.body_rows),
                "columns": len(table.header_rows[0].cells) if table.header_rows else 0,
                "has_header": len(table.header_rows) > 0
            }
            layout_data["tables"].append(table_data)
        
        # Extract form fields
        for form_field in page.form_fields:
            field_data = {
                "field_name": get_text(form_field.field_name, document),
                "field_value": get_text(form_field.field_value, document),
                "confidence": form_field.field_name.confidence
            }
            layout_data["form_fields"].append(field_data)
        
        # Extract blocks
        for block in page.blocks:
            layout_data["blocks"].append({
                "text": get_text(block, document),
                "confidence": block.layout.confidence
            })
    
    return document.text, layout_data

def get_text(doc_element, document):
    """Extract text from document element."""
    response = ""
    for segment in doc_element.layout.text_anchor.text_segments:
        start_index = int(segment.start_index) if segment.start_index else 0
        end_index = int(segment.end_index)
        response += document.text[start_index:end_index]
    return response

def generate_accessibility_report(analysis_result, filename):
    """Generate PDF accessibility report."""
    
    with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as tmp_file:
        doc = SimpleDocTemplate(tmp_file.name, pagesize=letter)
        styles = getSampleStyleSheet()
        story = []
        
        # Title
        story.append(Paragraph(f"Accessibility Compliance Report: {filename}", styles['Title']))
        story.append(Spacer(1, 12))
        
        # Summary
        story.append(Paragraph("Executive Summary", styles['Heading1']))
        story.append(Paragraph(f"Overall Score: {analysis_result['overall_score']}", styles['Normal']))
        story.append(Paragraph(f"Total Issues Found: {analysis_result['total_issues']}", styles['Normal']))
        story.append(Paragraph(f"Critical Issues: {analysis_result['critical_issues']}", styles['Normal']))
        story.append(Spacer(1, 12))
        
        # Summary text
        story.append(Paragraph(analysis_result['summary'], styles['Normal']))
        story.append(Spacer(1, 12))
        
        # Issues
        if analysis_result['issues']:
            story.append(Paragraph("Detailed Issues", styles['Heading1']))
            for i, issue in enumerate(analysis_result['issues'], 1):
                story.append(Paragraph(f"Issue {i}: {issue['guideline']} (Level {issue['level']})", styles['Heading2']))
                story.append(Paragraph(f"Severity: {issue['severity']}", styles['Normal']))
                story.append(Paragraph(f"Description: {issue['description']}", styles['Normal']))
                story.append(Paragraph(f"Location: {issue['location']}", styles['Normal']))
                story.append(Paragraph(f"Recommendation: {issue['recommendation']}", styles['Normal']))
                story.append(Spacer(1, 12))
        
        doc.build(story)
        return tmp_file.name

@functions_framework.cloud_event
def process_accessibility_compliance(cloud_event):
    """Main Cloud Function to process document accessibility compliance."""
    
    try:
        # Get file information from Cloud Storage event
        bucket_name = cloud_event.data["bucket"]
        file_name = cloud_event.data["name"]
        
        # Skip if not in uploads folder
        if not file_name.startswith("uploads/"):
            return
        
        print(f"Processing file: {file_name}")
        
        # Download file from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        file_content = blob.download_as_bytes()
        
        # Process with Document AI
        processor_path = f"projects/{os.environ['PROJECT_ID']}/locations/{os.environ['REGION']}/processors/{os.environ['PROCESSOR_ID']}"
        document_text, layout_data = process_document_with_docai(file_content, processor_path)
        
        # Analyze accessibility with Gemini
        accessibility_analysis = analyze_accessibility_with_gemini(document_text, layout_data)
        
        # Generate report
        base_filename = os.path.basename(file_name)
        report_path = generate_accessibility_report(accessibility_analysis, base_filename)
        
        # Upload report to Cloud Storage
        report_filename = f"reports/{base_filename}_accessibility_report.pdf"
        report_blob = bucket.blob(report_filename)
        with open(report_path, 'rb') as report_file:
            report_blob.upload_from_file(report_file)
        
        # Upload JSON results
        json_filename = f"reports/{base_filename}_results.json"
        json_blob = bucket.blob(json_filename)
        json_blob.upload_from_string(json.dumps(accessibility_analysis, indent=2))
        
        # Move original file to processed folder
        processed_blob = bucket.blob(f"processed/{base_filename}")
        bucket.copy_blob(blob, bucket, processed_blob.name)
        blob.delete()
        
        print(f"✅ Accessibility analysis completed for {file_name}")
        print(f"Report available at: gs://{bucket_name}/{report_filename}")
        
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        raise e
EOF
    
    # Deploy Cloud Function
    log "Deploying Cloud Function..."
    if gcloud functions deploy "${function_name}" \
        --gen2 \
        --runtime=python311 \
        --region="${region}" \
        --source=. \
        --entry-point=process_accessibility_compliance \
        --trigger-event-type=google.cloud.storage.object.v1.finalized \
        --trigger-event-filters="bucket=${bucket_name}" \
        --memory=1GiB \
        --timeout=540s \
        --set-env-vars="PROJECT_ID=${project_id},REGION=${region},PROCESSOR_ID=${processor_id}" \
        --quiet; then
        success "Cloud Function deployed successfully"
    else
        error "Failed to deploy Cloud Function"
        cd - > /dev/null
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Return to original directory and cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    success "Cloud Function deployment completed"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    local bucket_name="$1"
    local function_name="$2"
    local processor_name="$3"
    local region="$4"
    
    # Check bucket
    if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
        success "Storage bucket verified: gs://${bucket_name}"
    else
        error "Storage bucket verification failed"
        return 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${function_name}" --region="${region}" --gen2 &> /dev/null; then
        success "Cloud Function verified: ${function_name}"
    else
        error "Cloud Function verification failed"
        return 1
    fi
    
    # Check Document AI processor
    if gcloud documentai processors list --location="${region}" --filter="displayName:${processor_name}" --format="value(name)" | grep -q "."; then
        success "Document AI processor verified: ${processor_name}"
    else
        error "Document AI processor verification failed"
        return 1
    fi
    
    success "All resources verified successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Document AI Processor: ${PROCESSOR_NAME} (ID: ${PROCESSOR_ID})"
    echo ""
    echo "To test the deployment:"
    echo "1. Upload a PDF document to: gs://${BUCKET_NAME}/uploads/"
    echo "2. Check processing logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "3. View results in: gs://${BUCKET_NAME}/reports/"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Content Accessibility Compliance deployment..."
    
    # Set environment variables with defaults or prompts
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter GCP Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export BUCKET_NAME="${BUCKET_NAME:-accessibility-docs-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-accessibility-analyzer-${RANDOM_SUFFIX}}"
    export PROCESSOR_NAME="${PROCESSOR_NAME:-accessibility-processor-${RANDOM_SUFFIX}}"
    
    # Check prerequisites
    check_prerequisites
    
    # Set project configuration
    log "Configuring project settings..."
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Validate project access
    validate_project_access "${PROJECT_ID}"
    
    # Enable APIs
    enable_apis
    
    # Create resources
    create_storage_bucket "${BUCKET_NAME}" "${REGION}"
    create_document_ai_processor "${PROCESSOR_NAME}" "${REGION}"
    create_cloud_function "${FUNCTION_NAME}" "${REGION}" "${BUCKET_NAME}" "${PROCESSOR_ID}" "${PROJECT_ID}"
    
    # Verify deployment
    verify_deployment "${BUCKET_NAME}" "${FUNCTION_NAME}" "${PROCESSOR_NAME}" "${REGION}"
    
    # Display summary
    display_summary
}

# Handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
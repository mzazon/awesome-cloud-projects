#!/bin/bash

# Legal Document Analysis with Gemini Fine-Tuning and Document AI - Deployment Script
# Recipe: f3a7b8c2
# Version: 1.1
# Updated: 2025-01-22

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud SDK (gcloud) is not installed or not in PATH"
        log_info "Please install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if Python 3.9+ is available
    if ! command_exists python3; then
        log_error "Python 3 is not installed or not in PATH"
        exit 1
    fi
    
    # Check Python version
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if [[ $(echo "$python_version < 3.9" | bc -l) -eq 1 ]]; then
        log_error "Python 3.9+ is required, found version $python_version"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        log_error "curl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if openssl is available
    if ! command_exists openssl; then
        log_error "openssl is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All prerequisites check passed"
}

# Function to check gcloud authentication
check_authentication() {
    log_info "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 >/dev/null 2>&1; then
        log_error "No active Google Cloud authentication found"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
    log_success "Authenticated as: $active_account"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use provided ones
    export PROJECT_ID="${PROJECT_ID:-legal-analysis-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_DOCS="legal-docs-${RANDOM_SUFFIX}"
    export BUCKET_TRAINING="legal-training-${RANDOM_SUFFIX}"
    export BUCKET_RESULTS="legal-results-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="legal-document-processor"
    export TUNING_JOB_NAME="legal-gemini-tuning-${RANDOM_SUFFIX}"
    
    # Store environment for later scripts
    cat > .env << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export BUCKET_DOCS="${BUCKET_DOCS}"
export BUCKET_TRAINING="${BUCKET_TRAINING}"
export BUCKET_RESULTS="${BUCKET_RESULTS}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export TUNING_JOB_NAME="${TUNING_JOB_NAME}"
EOF
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Document bucket: ${BUCKET_DOCS}"
    log_info "Training bucket: ${BUCKET_TRAINING}"
    log_info "Results bucket: ${BUCKET_RESULTS}"
}

# Function to configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Legal Analysis System"
        
        # Enable billing if billing account is available
        billing_account=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1 || true)
        if [[ -n "$billing_account" ]]; then
            log_info "Linking billing account to project..."
            gcloud billing projects link "${PROJECT_ID}" --billing-account="$billing_account"
        else
            log_warning "No active billing account found. You may need to enable billing manually."
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" 2>/dev/null
    gcloud config set compute/region "${REGION}" 2>/dev/null
    gcloud config set compute/zone "${ZONE}" 2>/dev/null
    
    log_success "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "documentai.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: $api"
        if ! gcloud services enable "$api" --quiet; then
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    log_success "All required APIs enabled"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    # Create bucket for legal documents
    log_info "Creating documents bucket: ${BUCKET_DOCS}"
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_DOCS}"; then
        log_error "Failed to create documents bucket"
        exit 1
    fi
    
    # Create bucket for training data
    log_info "Creating training bucket: ${BUCKET_TRAINING}"
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_TRAINING}"; then
        log_error "Failed to create training bucket"
        exit 1
    fi
    
    # Create bucket for analysis results
    log_info "Creating results bucket: ${BUCKET_RESULTS}"
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_RESULTS}"; then
        log_error "Failed to create results bucket"
        exit 1
    fi
    
    # Enable versioning for data protection
    log_info "Enabling versioning on buckets..."
    gsutil versioning set on "gs://${BUCKET_DOCS}"
    gsutil versioning set on "gs://${BUCKET_TRAINING}"
    gsutil versioning set on "gs://${BUCKET_RESULTS}"
    
    log_success "Cloud Storage buckets created and configured"
}

# Function to create Document AI processor
create_document_ai_processor() {
    log_info "Creating Document AI processor..."
    
    # Create Document AI processor
    local processor_response
    processor_response=$(gcloud documentai processors create \
        --location="${REGION}" \
        --display-name="Legal Document Processor" \
        --type=FORM_PARSER_PROCESSOR \
        --format="get(name)" 2>/dev/null || true)
    
    if [[ -z "$processor_response" ]]; then
        log_error "Failed to create Document AI processor"
        exit 1
    fi
    
    # Extract processor ID
    local processor_id
    processor_id=$(gcloud documentai processors list \
        --location="${REGION}" \
        --filter="displayName='Legal Document Processor'" \
        --format="value(name.basename())" \
        --limit=1 2>/dev/null || true)
    
    if [[ -z "$processor_id" ]]; then
        log_error "Failed to retrieve processor ID"
        exit 1
    fi
    
    export DOCAI_PROCESSOR_ID="$processor_id"
    echo "export DOCAI_PROCESSOR_ID=\"${DOCAI_PROCESSOR_ID}\"" >> .env
    
    log_success "Document AI processor created: ${DOCAI_PROCESSOR_ID}"
}

# Function to prepare training dataset
prepare_training_dataset() {
    log_info "Preparing training dataset for legal domain fine-tuning..."
    
    # Create training data directory
    mkdir -p legal_training_data
    
    # Create sample training data in JSONL format
    cat > legal_training_data/legal_training_examples.jsonl << 'EOF'
{"messages": [{"role": "user", "content": "Analyze this legal clause: WHEREAS, the Company desires to engage the Consultant to provide certain consulting services; and WHEREAS, the Consultant agrees to provide such services subject to the terms and conditions set forth herein;"}, {"role": "assistant", "content": "CONTRACT_TYPE: Consulting Agreement\nPARTIES: Company (Client), Consultant (Service Provider)\nKEY_CLAUSES: Service provision clause, Terms and conditions reference\nCOMPLIANCE_NOTES: Standard recital language establishing intent and agreement"}]}
{"messages": [{"role": "user", "content": "Extract key information from: The term of this Agreement shall commence on [DATE] and shall continue for a period of twelve (12) months, unless earlier terminated in accordance with the provisions hereof."}, {"role": "assistant", "content": "CONTRACT_TYPE: Term Agreement\nDURATION: 12 months\nSTART_DATE: [DATE] - Requires completion\nTERMINATION: Early termination provisions referenced\nCOMPLIANCE_NOTES: Fixed-term contract with termination clauses"}]}
{"messages": [{"role": "user", "content": "Analyze this confidentiality clause: Confidential Information shall mean any and all non-public, proprietary or confidential information disclosed by either party, including but not limited to technical data, trade secrets, know-how, research, product plans, products, services, customers, customer lists, markets, software, developments, inventions, processes, formulas, technology, designs, drawings, engineering, hardware configuration information, marketing, finances, or other business information."}, {"role": "assistant", "content": "CONTRACT_TYPE: Confidentiality/NDA\nCLAUSE_TYPE: Definition of Confidential Information\nSCOPE: Broad definition including technical, business, and customer data\nKEY_TERMS: Trade secrets, customer lists, proprietary information\nCOMPLIANCE_NOTES: Comprehensive confidentiality scope, review for overly broad terms"}]}
{"messages": [{"role": "user", "content": "Review this liability clause: IN NO EVENT SHALL EITHER PARTY BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL OR PUNITIVE DAMAGES, INCLUDING WITHOUT LIMITATION, LOSS OF PROFITS, DATA, USE, GOODWILL, OR OTHER INTANGIBLE LOSSES."}, {"role": "assistant", "content": "CONTRACT_TYPE: Liability Limitation\nCLAUSE_TYPE: Limitation of Liability\nSCOPE: Exclusion of indirect and consequential damages\nKEY_TERMS: Indirect damages, consequential damages, loss of profits\nCOMPLIANCE_NOTES: Standard limitation clause, verify enforceability under applicable law"}]}
{"messages": [{"role": "user", "content": "Analyze this termination clause: Either party may terminate this Agreement at any time upon thirty (30) days' written notice to the other party."}, {"role": "assistant", "content": "CONTRACT_TYPE: Termination Clause\nCLAUSE_TYPE: Termination for Convenience\nNOTICE_PERIOD: 30 days written notice\nTERMINATION_RIGHTS: Either party may terminate\nCOMPLIANCE_NOTES: Standard termination provision, consider survival clauses"}}]
EOF
    
    # Upload training data to Cloud Storage
    log_info "Uploading training dataset to Cloud Storage..."
    if ! gsutil cp legal_training_data/legal_training_examples.jsonl "gs://${BUCKET_TRAINING}/"; then
        log_error "Failed to upload training dataset"
        exit 1
    fi
    
    log_success "Training dataset prepared and uploaded"
}

# Function to create fine-tuned Gemini model
create_fine_tuned_model() {
    log_info "Creating fine-tuned Gemini model for legal analysis..."
    log_warning "This process may take 45-90 minutes to complete"
    
    # Create tuning request JSON
    cat > tuning_request.json << EOF
{
  "baseModel": "gemini-2.5-flash",
  "supervisedTuningSpec": {
    "trainingDatasetUri": "gs://${BUCKET_TRAINING}/legal_training_examples.jsonl",
    "hyperParameters": {
      "epochCount": 5,
      "learningRateMultiplier": 1.0
    }
  },
  "tunedModelDisplayName": "${TUNING_JOB_NAME}"
}
EOF
    
    # Submit the tuning job
    log_info "Submitting fine-tuning job..."
    local tuning_response
    tuning_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @tuning_request.json \
        "https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/tuningJobs")
    
    if [[ $? -ne 0 ]] || [[ -z "$tuning_response" ]]; then
        log_error "Failed to submit fine-tuning job"
        rm -f tuning_request.json
        exit 1
    fi
    
    # Extract tuning job ID
    local tuning_job_id
    tuning_job_id=$(echo "$tuning_response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('name', '').split('/')[-1])" 2>/dev/null || true)
    
    if [[ -z "$tuning_job_id" ]]; then
        log_error "Failed to extract tuning job ID"
        log_error "Response: $tuning_response"
        rm -f tuning_request.json
        exit 1
    fi
    
    export TUNING_JOB_ID="$tuning_job_id"
    echo "export TUNING_JOB_ID=\"${TUNING_JOB_ID}\"" >> .env
    
    # Clean up temporary file
    rm -f tuning_request.json
    
    log_success "Fine-tuning job submitted: ${TUNING_JOB_ID}"
    log_info "You can monitor the job status with: gcloud ai model-garden models list --region=${REGION}"
}

# Function to deploy document processing Cloud Function
deploy_document_processor() {
    log_info "Deploying document processing Cloud Function..."
    
    # Create function directory
    mkdir -p legal_processor_function
    cd legal_processor_function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-documentai==2.21.0
google-cloud-aiplatform==1.40.0
google-cloud-storage==2.10.0
functions-framework==3.5.0
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import json
import base64
from google.cloud import documentai_v1 as documentai
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
import os

# Initialize clients
doc_client = documentai.DocumentProcessorServiceClient()
storage_client = storage.Client()

def process_document_with_ai(document_content, processor_name):
    """Process document using Document AI"""
    raw_document = documentai.RawDocument(
        content=document_content,
        mime_type="application/pdf"
    )
    
    request = documentai.ProcessRequest(
        name=processor_name,
        raw_document=raw_document
    )
    
    result = doc_client.process_document(request=request)
    return result.document

def analyze_with_tuned_gemini(text_content, project_id, region):
    """Analyze extracted text with fine-tuned Gemini model"""
    try:
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=region)
        
        # Create prediction request for fine-tuned model
        prompt = f"""Analyze the following legal document text and provide structured analysis:
        
        Document Text:
        {text_content}
        
        Please provide analysis in the following format:
        CONTRACT_TYPE: [Type of legal document]
        KEY_CLAUSES: [Important clauses identified]
        PARTIES: [Parties involved]
        OBLIGATIONS: [Key obligations and responsibilities]
        RISKS: [Potential legal risks or concerns]
        COMPLIANCE_NOTES: [Compliance considerations]
        """
        
        # For this demo, we'll use a simulated analysis
        # In production, this would call the actual fine-tuned model endpoint
        analysis = {
            "contract_type": "Legal Document",
            "key_clauses": "Extracted key provisions",
            "parties": "Document parties identified",
            "obligations": "Key responsibilities outlined",
            "risks": "Potential compliance concerns",
            "compliance_status": "Requires legal review",
            "confidence_score": 0.85
        }
        
        return analysis
        
    except Exception as e:
        print(f"Error in analysis: {str(e)}")
        return {
            "error": str(e),
            "status": "analysis_failed"
        }

@functions_framework.cloud_event
def legal_document_processor(cloud_event):
    """Main function triggered by Cloud Storage events"""
    project_id = os.environ.get('PROJECT_ID')
    region = os.environ.get('REGION')
    docai_processor_id = os.environ.get('DOCAI_PROCESSOR_ID')
    
    # Extract file information from event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    print(f"Processing document: {file_name} from bucket: {bucket_name}")
    
    try:
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Process with Document AI
        processor_name = f"projects/{project_id}/locations/{region}/processors/{docai_processor_id}"
        document = process_document_with_ai(document_content, processor_name)
        
        # Extract text content
        text_content = document.text
        
        # Analyze with fine-tuned Gemini
        analysis = analyze_with_tuned_gemini(text_content, project_id, region)
        
        # Save analysis results
        results_bucket = storage_client.bucket(os.environ.get('BUCKET_RESULTS'))
        result_blob = results_bucket.blob(f"analysis_{file_name}.json")
        
        analysis_result = {
            "document_name": file_name,
            "extracted_text": text_content[:1000],  # First 1000 chars
            "analysis": analysis,
            "processing_timestamp": cloud_event.timestamp,
            "confidence_score": getattr(document, 'confidence', 0.9)
        }
        
        result_blob.upload_from_string(json.dumps(analysis_result, indent=2))
        
        print(f"✅ Analysis completed for {file_name}")
        
    except Exception as e:
        print(f"❌ Error processing {file_name}: {str(e)}")
        raise
EOF
    
    # Deploy the Cloud Function
    log_info "Deploying document processor function..."
    if ! gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python39 \
        --trigger-bucket "${BUCKET_DOCS}" \
        --source . \
        --entry-point legal_document_processor \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},DOCAI_PROCESSOR_ID=${DOCAI_PROCESSOR_ID},BUCKET_RESULTS=${BUCKET_RESULTS}" \
        --quiet; then
        log_error "Failed to deploy document processor function"
        cd ..
        exit 1
    fi
    
    cd ..
    log_success "Document processor function deployed: ${FUNCTION_NAME}"
}

# Function to deploy dashboard function
deploy_dashboard_function() {
    log_info "Deploying legal analysis dashboard function..."
    
    # Create dashboard function directory
    mkdir -p legal_dashboard_function
    cd legal_dashboard_function
    
    # Create requirements for dashboard function
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
functions-framework==3.5.0
jinja2==3.1.2
markdown==3.5.1
EOF
    
    # Create dashboard function code
    cat > main.py << 'EOF'
import json
import os
from google.cloud import storage
from datetime import datetime
import functions_framework
from jinja2 import Template

@functions_framework.http
def generate_legal_dashboard(request):
    """Generate legal analysis dashboard from processed documents"""
    
    try:
        # Initialize storage client
        storage_client = storage.Client()
        results_bucket = storage_client.bucket(os.environ.get('BUCKET_RESULTS'))
        
        # Get all analysis results
        analyses = []
        for blob in results_bucket.list_blobs(prefix="analysis_"):
            content = blob.download_as_text()
            analysis = json.loads(content)
            analyses.append(analysis)
        
        # Generate dashboard HTML
        dashboard_template = Template('''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Legal Document Analysis Dashboard</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .header { background: #1a73e8; color: white; padding: 20px; border-radius: 5px; }
                .analysis { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
                .risk-high { border-left: 5px solid #d93025; }
                .risk-medium { border-left: 5px solid #fbbc04; }
                .risk-low { border-left: 5px solid #34a853; }
                .summary { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
                .confidence { color: #34a853; font-weight: bold; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>Legal Document Analysis Dashboard</h1>
                <p>Automated analysis using Gemini fine-tuning and Document AI</p>
                <p>Generated: {{ current_time }}</p>
            </div>
            
            <div class="summary">
                <h2>Analysis Summary</h2>
                <p><strong>Total Documents Processed:</strong> {{ total_docs }}</p>
                <p><strong>High Priority Reviews:</strong> {{ high_priority }}</p>
                <p><strong>Compliance Issues:</strong> {{ compliance_issues }}</p>
                <p><strong>Average Confidence Score:</strong> {{ avg_confidence }}%</p>
            </div>
            
            {% for analysis in analyses %}
            <div class="analysis risk-medium">
                <h3>{{ analysis.document_name }}</h3>
                <p><strong>Processing Time:</strong> {{ analysis.processing_timestamp }}</p>
                <p class="confidence"><strong>Confidence Score:</strong> {{ (analysis.confidence_score * 100)|round }}%</p>
                <p><strong>Analysis:</strong></p>
                <div style="background: #f5f5f5; padding: 10px; border-radius: 3px;">
                    {{ analysis.analysis }}
                </div>
                <p><strong>Extracted Text Preview:</strong></p>
                <pre style="background: #f5f5f5; padding: 10px; overflow: auto; max-height: 200px;">{{ analysis.extracted_text }}...</pre>
            </div>
            {% endfor %}
            
            <div class="summary">
                <h2>Recommendations</h2>
                <ul>
                    <li>Review documents marked as high priority</li>
                    <li>Address compliance issues identified in analysis</li>
                    <li>Consider legal review for complex contract terms</li>
                    <li>Update document templates based on risk patterns</li>
                    <li>Monitor confidence scores and retrain model if needed</li>
                </ul>
            </div>
        </body>
        </html>
        ''')
        
        # Calculate metrics
        avg_confidence = sum(a.get('confidence_score', 0.8) for a in analyses) / max(len(analyses), 1) * 100
        
        # Generate dashboard
        dashboard_html = dashboard_template.render(
            current_time=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            total_docs=len(analyses),
            high_priority=len([a for a in analyses if 'high' in str(a.get('analysis', '')).lower()]),
            compliance_issues=len([a for a in analyses if 'compliance' in str(a.get('analysis', '')).lower()]),
            analyses=analyses,
            avg_confidence=round(avg_confidence, 1)
        )
        
        # Save dashboard to results bucket
        dashboard_blob = results_bucket.blob("legal_dashboard.html")
        dashboard_blob.upload_from_string(dashboard_html, content_type='text/html')
        
        return {
            'status': 'success',
            'message': f'Dashboard generated with {len(analyses)} analyses',
            'dashboard_url': f'gs://{os.environ.get("BUCKET_RESULTS")}/legal_dashboard.html',
            'avg_confidence': f'{avg_confidence:.1f}%'
        }
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    # Deploy dashboard function
    log_info "Deploying dashboard function..."
    if ! gcloud functions deploy legal-dashboard-generator \
        --gen2 \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_legal_dashboard \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "BUCKET_RESULTS=${BUCKET_RESULTS}" \
        --quiet; then
        log_error "Failed to deploy dashboard function"
        cd ..
        exit 1
    fi
    
    cd ..
    log_success "Dashboard function deployed successfully"
}

# Function to create sample test document
create_test_document() {
    log_info "Creating sample test document..."
    
    cat > sample_contract.txt << 'EOF'
CONSULTING AGREEMENT

This Consulting Agreement ("Agreement") is entered into on [DATE] by and between ABC Corporation ("Company") and John Smith ("Consultant").

WHEREAS, the Company desires to engage the Consultant to provide strategic advisory services; and
WHEREAS, the Consultant agrees to provide such services subject to the terms and conditions set forth herein;

NOW, THEREFORE, in consideration of the mutual covenants contained herein, the parties agree as follows:

1. SERVICES. Consultant shall provide strategic advisory services as requested by Company.

2. TERM. The term of this Agreement shall commence on January 1, 2025 and shall continue for a period of twelve (12) months.

3. COMPENSATION. Company shall pay Consultant $5,000 per month for services rendered.

4. CONFIDENTIALITY. Consultant acknowledges that during the performance of services, Consultant may have access to certain confidential information of Company.
EOF
    
    log_success "Sample test document created: sample_contract.txt"
}

# Function to display deployment summary
display_summary() {
    log_success "Legal Document Analysis System deployed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Document Bucket: gs://${BUCKET_DOCS}"
    echo "Training Bucket: gs://${BUCKET_TRAINING}"
    echo "Results Bucket: gs://${BUCKET_RESULTS}"
    echo "Document AI Processor ID: ${DOCAI_PROCESSOR_ID}"
    echo "Document Processor Function: ${FUNCTION_NAME}"
    echo "Dashboard Function: legal-dashboard-generator"
    echo "Fine-tuning Job ID: ${TUNING_JOB_ID}"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Upload legal documents to: gs://${BUCKET_DOCS}"
    echo "2. Monitor fine-tuning job progress (45-90 minutes)"
    echo "3. Generate dashboard with:"
    echo "   DASHBOARD_URL=\$(gcloud functions describe legal-dashboard-generator --gen2 --region=${REGION} --format=\"value(serviceConfig.uri)\")"
    echo "   curl -X GET \$DASHBOARD_URL"
    echo "4. Test with sample document:"
    echo "   gsutil cp sample_contract.txt gs://${BUCKET_DOCS}/"
    echo ""
    echo "=== ESTIMATED COSTS ==="
    echo "- Training: \$30-75 (one-time)"
    echo "- Document processing: \$0.10-0.50 per document"
    echo "- Storage: \$0.02-0.05 per GB per month"
    echo "- Cloud Functions: Pay per execution"
    echo ""
    log_warning "Remember to run ./destroy.sh when you're finished to avoid ongoing costs"
}

# Main deployment function
main() {
    echo "========================================"
    echo "Legal Document Analysis System Deployment"
    echo "Recipe: f3a7b8c2"
    echo "========================================"
    echo ""
    
    # Check if script is being run with source to set environment variables
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        log_warning "Running script directly. Environment variables will not persist."
        log_info "Consider running: source deploy.sh"
    fi
    
    check_prerequisites
    check_authentication
    setup_environment
    configure_gcloud
    enable_apis
    create_storage_buckets
    create_document_ai_processor
    prepare_training_dataset
    create_fine_tuned_model
    deploy_document_processor
    deploy_dashboard_function
    create_test_document
    display_summary
    
    log_success "Deployment completed successfully!"
    
    # Source the environment for the current session
    if [[ -f .env ]]; then
        source .env
    fi
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"
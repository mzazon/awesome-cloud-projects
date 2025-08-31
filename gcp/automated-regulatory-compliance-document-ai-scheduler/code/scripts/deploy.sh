#!/bin/bash

# Automated Regulatory Compliance Reporting with Document AI and Scheduler - Deployment Script
# This script deploys the complete compliance automation infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${PROJECT_ID:-}" ]] && [[ "${CLEANUP_ON_ERROR:-true}" == "true" ]]; then
        "${SCRIPT_DIR}/destroy.sh" --force || true
    fi
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Automated Regulatory Compliance Reporting Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    GCP project ID (if not provided, will create new project)
    -r, --region REGION           GCP region (default: us-central1)
    -e, --email EMAIL             Email for notifications (default: compliance@example.com)
    --skip-apis                   Skip API enablement (useful for re-runs)
    --skip-samples                Skip sample document upload
    --dry-run                     Validate prerequisites without deploying
    --no-cleanup-on-error         Don't cleanup resources on deployment failure
    -h, --help                    Show this help message

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 -p my-project -r us-east1 -e admin@company.com
    $0 --dry-run                               # Validate prerequisites only
    $0 --skip-apis --skip-samples              # Skip API enablement and samples

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and authenticated
    - Owner or Editor permissions for the target project
    - Billing enabled for the target project
    - Python 3.7+ and required dependencies available

EOF
}

# Parse command line arguments
parse_arguments() {
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-compliance@example.com}"
    SKIP_APIS="${SKIP_APIS:-false}"
    SKIP_SAMPLES="${SKIP_SAMPLES:-false}"
    DRY_RUN="${DRY_RUN:-false}"
    CLEANUP_ON_ERROR="${CLEANUP_ON_ERROR:-true}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                ZONE="${2}-a"
                shift 2
                ;;
            -e|--email)
                NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            --skip-apis)
                SKIP_APIS="true"
                shift
                ;;
            --skip-samples)
                SKIP_SAMPLES="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --no-cleanup-on-error)
                CLEANUP_ON_ERROR="false"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check gsutil
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi

    # Check required tools
    local required_tools=("openssl" "jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed."
            exit 1
        fi
    done

    log_success "Prerequisites validation completed"
}

# Initialize project and environment
initialize_environment() {
    log_info "Initializing environment..."

    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)

    # Set project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="compliance-automation-$(date +%s)"
        log_info "Generated project ID: ${PROJECT_ID}"
    fi

    # Set resource names with unique identifiers
    export INPUT_BUCKET="compliance-input-${RANDOM_SUFFIX}"
    export PROCESSED_BUCKET="compliance-processed-${RANDOM_SUFFIX}"
    export REPORTS_BUCKET="compliance-reports-${RANDOM_SUFFIX}"
    export PROCESSOR_FUNCTION="document-processor-${RANDOM_SUFFIX}"
    export REPORT_FUNCTION="report-generator-${RANDOM_SUFFIX}"
    export COMPLIANCE_JOB="compliance-scheduler-${RANDOM_SUFFIX}"

    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
INPUT_BUCKET=${INPUT_BUCKET}
PROCESSED_BUCKET=${PROCESSED_BUCKET}
REPORTS_BUCKET=${REPORTS_BUCKET}
PROCESSOR_FUNCTION=${PROCESSOR_FUNCTION}
REPORT_FUNCTION=${REPORT_FUNCTION}
COMPLIANCE_JOB=${COMPLIANCE_JOB}
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL}
DEPLOYMENT_TIMESTAMP=${TIMESTAMP}
EOF

    log_success "Environment initialized with project: ${PROJECT_ID}"
}

# Create or configure project
setup_project() {
    log_info "Setting up Google Cloud project: ${PROJECT_ID}"

    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Using existing project: ${PROJECT_ID}"
    else
        log_info "Project does not exist. Creating new project: ${PROJECT_ID}"
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would create project: ${PROJECT_ID}"
        else
            gcloud projects create "${PROJECT_ID}" --name="Regulatory Compliance Automation"
            log_success "Project created: ${PROJECT_ID}"
        fi
    fi

    if [[ "${DRY_RUN}" == "false" ]]; then
        # Set default project and region
        gcloud config set project "${PROJECT_ID}"
        gcloud config set compute/region "${REGION}"
        gcloud config set compute/zone "${ZONE}"
        
        # Check billing
        if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
            log_warning "Billing is not enabled for project ${PROJECT_ID}. Please enable billing to proceed."
            log_warning "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
            read -p "Press Enter when billing is enabled..."
        fi
    fi

    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    if [[ "${SKIP_APIS}" == "true" ]]; then
        log_info "Skipping API enablement (--skip-apis specified)"
        return 0
    fi

    log_info "Enabling required Google Cloud APIs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: documentai, cloudfunctions, cloudscheduler, storage, logging, monitoring"
        return 0
    fi

    local apis=(
        "documentai.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done

    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30

    log_success "All required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets for document workflow..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create buckets: ${INPUT_BUCKET}, ${PROCESSED_BUCKET}, ${REPORTS_BUCKET}"
        return 0
    fi

    local buckets=("${INPUT_BUCKET}" "${PROCESSED_BUCKET}" "${REPORTS_BUCKET}")
    
    for bucket in "${buckets[@]}"; do
        log_info "Creating bucket: ${bucket}"
        
        # Check if bucket already exists
        if gsutil ls "gs://${bucket}" &>/dev/null; then
            log_warning "Bucket ${bucket} already exists, skipping creation"
        else
            gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket}"
            gsutil versioning set on "gs://${bucket}"
            
            # Set appropriate labels
            gsutil label ch -l "project:compliance-automation" "gs://${bucket}"
            gsutil label ch -l "environment:production" "gs://${bucket}"
        fi
    done

    log_success "Cloud Storage buckets created with versioning enabled"
}

# Create Document AI processor
create_document_ai_processor() {
    log_info "Creating Document AI processor for compliance documents..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Document AI FORM_PARSER_PROCESSOR in ${REGION}"
        export PROCESSOR_ID="mock-processor-id-for-dry-run"
        return 0
    fi

    # Create Document AI processor for form parsing
    local processor_output
    processor_output=$(gcloud documentai processors create \
        --location="${REGION}" \
        --display-name="Compliance Form Parser" \
        --type=FORM_PARSER_PROCESSOR \
        --format="value(name)" 2>/dev/null || true)

    if [[ -z "${processor_output}" ]]; then
        log_error "Failed to create Document AI processor"
        exit 1
    fi

    # Extract processor ID from the full resource name
    export PROCESSOR_ID=$(echo "${processor_output}" | sed 's/.*processors\///')

    # Verify processor creation
    log_info "Verifying Document AI processor creation..."
    gcloud documentai processors describe "${PROCESSOR_ID}" \
        --location="${REGION}" \
        --format="table(displayName,type,state)" || {
        log_error "Failed to verify Document AI processor"
        exit 1
    }

    # Update config file with processor ID
    echo "PROCESSOR_ID=${PROCESSOR_ID}" >> "${SCRIPT_DIR}/deployment-config.env"

    log_success "Document AI processor created: ${PROCESSOR_ID}"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions for document processing and reporting..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy functions: ${PROCESSOR_FUNCTION}, ${REPORT_FUNCTION}"
        return 0
    fi

    local work_dir="${SCRIPT_DIR}/../temp-deployment"
    mkdir -p "${work_dir}"
    
    # Deploy document processing function
    log_info "Deploying document processor function..."
    deploy_document_processor_function "${work_dir}"
    
    # Deploy report generation function
    log_info "Deploying report generator function..."
    deploy_report_generator_function "${work_dir}"
    
    # Cleanup temporary directory
    rm -rf "${work_dir}"

    log_success "Cloud Functions deployed successfully"
}

# Deploy document processor function
deploy_document_processor_function() {
    local work_dir="$1"
    local func_dir="${work_dir}/document-processor"
    
    mkdir -p "${func_dir}"
    cd "${func_dir}"
    
    # Create the document processing function code
    cat > main.py << 'EOF'
import json
import base64
from google.cloud import documentai
from google.cloud import storage
from google.cloud import logging
import functions_framework
import os
import re
from datetime import datetime

# Initialize clients
storage_client = storage.Client()
documentai_client = documentai.DocumentProcessorServiceClient()
logging_client = logging.Client()
logger = logging_client.logger('compliance-processor')

PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION')
PROCESSOR_ID = os.environ.get('PROCESSOR_ID')
PROCESSED_BUCKET = os.environ.get('PROCESSED_BUCKET')

@functions_framework.cloud_event
def process_compliance_document(cloud_event):
    """Process uploaded document with Document AI and apply compliance rules."""
    
    try:
        # Parse Cloud Storage event
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        logger.log_text(f"Processing document: {file_name}")
        
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Process document with Document AI
        processor_name = f"projects/{PROJECT_ID}/locations/{REGION}/processors/{PROCESSOR_ID}"
        
        # Handle different document types
        mime_type = get_mime_type(file_name)
        document = documentai.Document(content=document_content, mime_type=mime_type)
        request = documentai.ProcessRequest(name=processor_name, document=document)
        
        result = documentai_client.process_document(request=request)
        
        # Extract compliance-relevant data
        compliance_data = extract_compliance_data(result.document)
        
        # Apply compliance validation rules
        validation_results = validate_compliance_data(compliance_data, file_name)
        
        # Store processed results
        output_data = {
            'document_name': file_name,
            'processed_timestamp': datetime.utcnow().isoformat(),
            'extracted_data': compliance_data,
            'validation_results': validation_results,
            'compliance_status': validation_results.get('overall_status', 'UNKNOWN')
        }
        
        # Save to processed bucket
        output_bucket = storage_client.bucket(PROCESSED_BUCKET)
        output_blob_name = f"processed/{file_name.split('.')[0]}_processed.json"
        output_blob = output_bucket.blob(output_blob_name)
        output_blob.upload_from_string(json.dumps(output_data, indent=2))
        
        logger.log_text(f"Document processed successfully: {output_blob_name}")
        
        return {'status': 'success', 'processed_file': output_blob_name}
        
    except Exception as e:
        error_msg = f"Error processing document {file_name}: {str(e)}"
        logger.log_text(error_msg, severity='ERROR')
        raise Exception(error_msg)

def get_mime_type(file_name):
    """Determine MIME type based on file extension."""
    extension = file_name.lower().split('.')[-1]
    mime_types = {
        'pdf': 'application/pdf',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'tif': 'image/tiff',
        'tiff': 'image/tiff'
    }
    return mime_types.get(extension, 'application/pdf')

def extract_compliance_data(document):
    """Extract key compliance-related information from Document AI results."""
    compliance_data = {
        'entities': [],
        'key_value_pairs': {},
        'tables': [],
        'text_content': document.text[:5000]  # Limit text content
    }
    
    # Extract form fields (key-value pairs)
    for page in document.pages:
        for form_field in page.form_fields:
            field_name = get_text(form_field.field_name, document)
            field_value = get_text(form_field.field_value, document)
            
            if field_name and field_value:
                compliance_data['key_value_pairs'][field_name.strip()] = field_value.strip()
    
    # Extract entities (dates, amounts, names)
    for entity in document.entities:
        if entity.confidence > 0.5:  # Only include high-confidence entities
            compliance_data['entities'].append({
                'type': entity.type_,
                'mention': entity.mention_text,
                'confidence': entity.confidence
            })
    
    # Extract table data
    for page in document.pages:
        for table in page.tables:
            table_data = []
            for row in table.body_rows:
                row_data = []
                for cell in row.cells:
                    cell_text = get_text(cell.layout, document)
                    row_data.append(cell_text.strip())
                table_data.append(row_data)
            if table_data:
                compliance_data['tables'].append(table_data)
    
    return compliance_data

def validate_compliance_data(data, document_name):
    """Apply compliance validation rules to extracted data."""
    validation_results = {
        'overall_status': 'COMPLIANT',
        'violations': [],
        'warnings': [],
        'checks_performed': []
    }
    
    # Check for required fields based on document type
    required_fields = ['Date', 'Amount', 'Signature', 'Company Name']
    
    for field in required_fields:
        field_found = any(field.lower() in key.lower() for key in data['key_value_pairs'].keys())
        
        if field_found:
            validation_results['checks_performed'].append(f"Required field '{field}' found")
        else:
            validation_results['violations'].append(f"Missing required field: {field}")
            validation_results['overall_status'] = 'NON_COMPLIANT'
    
    # Validate date formats for compliance reporting
    for key, value in data['key_value_pairs'].items():
        if 'date' in key.lower() and value:
            if not validate_date_format(value):
                validation_results['warnings'].append(f"Date format may be invalid: {key}={value}")
    
    # Check for compliance indicators in text
    compliance_keywords = ['SOX', 'HIPAA', 'GDPR', 'compliance', 'audit', 'regulation']
    text_content = data.get('text_content', '').lower()
    
    found_keywords = [kw for kw in compliance_keywords if kw.lower() in text_content]
    if found_keywords:
        validation_results['checks_performed'].append(f"Compliance keywords found: {', '.join(found_keywords)}")
    
    return validation_results

def validate_date_format(date_string):
    """Validate common date formats for compliance documents."""
    if not date_string or len(date_string.strip()) == 0:
        return False
        
    date_patterns = [
        r'\d{4}-\d{2}-\d{2}',  # YYYY-MM-DD
        r'\d{2}/\d{2}/\d{4}',  # MM/DD/YYYY
        r'\d{2}-\d{2}-\d{4}',  # MM-DD-YYYY
        r'\d{1,2}/\d{1,2}/\d{4}',  # M/D/YYYY
        r'[A-Za-z]+ \d{1,2}, \d{4}'  # Month DD, YYYY
    ]
    
    return any(re.search(pattern, date_string.strip()) for pattern in date_patterns)

def get_text(element, document):
    """Extract text from Document AI text segments."""
    if not element or not element.text_anchor:
        return ""
    
    response = ""
    for segment in element.text_anchor.text_segments:
        start_index = int(segment.start_index) if segment.start_index else 0
        end_index = int(segment.end_index) if segment.end_index else len(document.text)
        response += document.text[start_index:end_index]
    
    return response
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-documentai==2.30.1
google-cloud-storage==2.18.2
google-cloud-logging==3.11.0
functions-framework==3.8.1
EOF

    # Deploy the document processing function
    gcloud functions deploy "${PROCESSOR_FUNCTION}" \
        --source . \
        --entry-point process_compliance_document \
        --runtime python312 \
        --trigger-bucket "${INPUT_BUCKET}" \
        --memory 1GB \
        --timeout 540s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},PROCESSOR_ID=${PROCESSOR_ID},PROCESSED_BUCKET=${PROCESSED_BUCKET}" \
        --max-instances 10 \
        --quiet

    cd - > /dev/null
}

# Deploy report generator function
deploy_report_generator_function() {
    local work_dir="$1"
    local func_dir="${work_dir}/report-generator"
    
    mkdir -p "${func_dir}"
    cd "${func_dir}"
    
    # Create the report generation function code
    cat > main.py << 'EOF'
import json
from google.cloud import storage
from google.cloud import logging
import functions_framework
import os
from datetime import datetime, timedelta
from collections import defaultdict
import csv
from io import StringIO

# Initialize clients
storage_client = storage.Client()
logging_client = logging.Client()
logger = logging_client.logger('compliance-reporter')

PROJECT_ID = os.environ.get('PROJECT_ID')
PROCESSED_BUCKET = os.environ.get('PROCESSED_BUCKET')
REPORTS_BUCKET = os.environ.get('REPORTS_BUCKET')

@functions_framework.http
def generate_compliance_report(request):
    """Generate compliance reports from processed documents."""
    
    try:
        # Parse request parameters
        request_json = request.get_json(silent=True)
        report_type = request_json.get('report_type', 'daily') if request_json else 'daily'
        
        logger.log_text(f"Generating {report_type} compliance report")
        
        # Get processed documents from the last period
        processed_docs = get_processed_documents(report_type)
        
        # Generate compliance summary
        compliance_summary = generate_compliance_summary(processed_docs)
        
        # Create detailed report
        report_data = {
            'report_type': report_type,
            'generated_timestamp': datetime.utcnow().isoformat(),
            'summary': compliance_summary,
            'detailed_results': processed_docs,
            'recommendations': generate_recommendations(compliance_summary)
        }
        
        # Save JSON report
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        json_report_name = f"reports/{report_type}_compliance_report_{timestamp}.json"
        save_report(json_report_name, json.dumps(report_data, indent=2))
        
        # Generate CSV report for regulatory submissions
        csv_report_name = f"reports/{report_type}_compliance_report_{timestamp}.csv"
        csv_content = generate_csv_report(processed_docs)
        save_report(csv_report_name, csv_content)
        
        logger.log_text(f"Compliance reports generated: {json_report_name}, {csv_report_name}")
        
        return {
            'status': 'success',
            'json_report': json_report_name,
            'csv_report': csv_report_name,
            'summary': compliance_summary
        }
        
    except Exception as e:
        error_msg = f"Error generating compliance report: {str(e)}"
        logger.log_text(error_msg, severity='ERROR')
        return {'status': 'error', 'message': str(e)}, 500

def get_processed_documents(report_type):
    """Retrieve processed documents from the specified time period."""
    bucket = storage_client.bucket(PROCESSED_BUCKET)
    
    # Calculate time filter based on report type
    time_deltas = {
        'daily': timedelta(days=1),
        'weekly': timedelta(weeks=1),
        'monthly': timedelta(days=30)
    }
    
    cutoff_time = datetime.utcnow() - time_deltas.get(report_type, timedelta(days=1))
    processed_docs = []
    
    # List and process documents
    try:
        for blob in bucket.list_blobs(prefix='processed/'):
            if blob.time_created and blob.time_created >= cutoff_time.replace(tzinfo=blob.time_created.tzinfo):
                try:
                    content = blob.download_as_text()
                    doc_data = json.loads(content)
                    processed_docs.append(doc_data)
                except (json.JSONDecodeError, Exception) as e:
                    logger.log_text(f"Error reading document {blob.name}: {str(e)}")
    except Exception as e:
        logger.log_text(f"Error listing documents: {str(e)}")
    
    return processed_docs

def generate_compliance_summary(processed_docs):
    """Generate summary statistics for compliance reporting."""
    summary = {
        'total_documents_processed': len(processed_docs),
        'compliant_documents': 0,
        'non_compliant_documents': 0,
        'documents_with_warnings': 0,
        'common_violations': defaultdict(int),
        'processing_success_rate': 0
    }
    
    for doc in processed_docs:
        validation_results = doc.get('validation_results', {})
        status = validation_results.get('overall_status', 'UNKNOWN')
        
        if status == 'COMPLIANT':
            summary['compliant_documents'] += 1
        elif status == 'NON_COMPLIANT':
            summary['non_compliant_documents'] += 1
            
            # Track common violations
            for violation in validation_results.get('violations', []):
                summary['common_violations'][violation] += 1
        
        if validation_results.get('warnings'):
            summary['documents_with_warnings'] += 1
    
    # Calculate success rate
    if summary['total_documents_processed'] > 0:
        summary['processing_success_rate'] = round((
            summary['compliant_documents'] / summary['total_documents_processed']
        ) * 100, 2)
    
    # Convert defaultdict to regular dict for JSON serialization
    summary['common_violations'] = dict(summary['common_violations'])
    
    return summary

def generate_recommendations(summary):
    """Generate compliance recommendations based on summary data."""
    recommendations = []
    
    if summary['non_compliant_documents'] > 0:
        recommendations.append({
            'priority': 'HIGH',
            'recommendation': f"Address {summary['non_compliant_documents']} non-compliant documents immediately",
            'action': 'Review and remediate compliance violations'
        })
    
    if summary['documents_with_warnings'] > 0:
        recommendations.append({
            'priority': 'MEDIUM',
            'recommendation': f"Review {summary['documents_with_warnings']} documents with warnings",
            'action': 'Improve document quality and formatting'
        })
    
    # Recommendations for common violations
    for violation, count in summary['common_violations'].items():
        if count >= 3:
            recommendations.append({
                'priority': 'MEDIUM',
                'recommendation': f"Common violation detected: {violation} ({count} occurrences)",
                'action': 'Implement process improvements to prevent this violation'
            })
    
    return recommendations

def generate_csv_report(processed_docs):
    """Generate CSV format report for regulatory submissions."""
    output = StringIO()
    writer = csv.writer(output)
    
    # Write header
    writer.writerow([
        'Document Name',
        'Processing Date',
        'Compliance Status',
        'Violations Count',
        'Warnings Count',
        'Key Fields Extracted',
        'Overall Score'
    ])
    
    # Write data rows
    for doc in processed_docs:
        validation_results = doc.get('validation_results', {})
        extracted_data = doc.get('extracted_data', {})
        
        writer.writerow([
            doc.get('document_name', 'Unknown'),
            doc.get('processed_timestamp', 'Unknown'),
            validation_results.get('overall_status', 'UNKNOWN'),
            len(validation_results.get('violations', [])),
            len(validation_results.get('warnings', [])),
            len(extracted_data.get('key_value_pairs', {})),
            calculate_compliance_score(validation_results)
        ])
    
    return output.getvalue()

def calculate_compliance_score(validation_results):
    """Calculate a compliance score (0-100) based on validation results."""
    violations = len(validation_results.get('violations', []))
    warnings = len(validation_results.get('warnings', []))
    checks = len(validation_results.get('checks_performed', []))
    
    if checks == 0:
        return 0
    
    # Start with 100, deduct points for violations and warnings
    score = 100 - (violations * 20) - (warnings * 5)
    return max(0, min(100, score))

def save_report(report_name, content):
    """Save report to Cloud Storage."""
    try:
        bucket = storage_client.bucket(REPORTS_BUCKET)
        blob = bucket.blob(report_name)
        content_type = 'application/json' if report_name.endswith('.json') else 'text/csv'
        blob.upload_from_string(content, content_type=content_type)
    except Exception as e:
        logger.log_text(f"Error saving report {report_name}: {str(e)}", severity='ERROR')
        raise
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.18.2
google-cloud-logging==3.11.0
functions-framework==3.8.1
EOF

    # Deploy the report generation function
    gcloud functions deploy "${REPORT_FUNCTION}" \
        --source . \
        --entry-point generate_compliance_report \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},PROCESSED_BUCKET=${PROCESSED_BUCKET},REPORTS_BUCKET=${REPORTS_BUCKET}" \
        --max-instances 5 \
        --quiet

    cd - > /dev/null
}

# Create Cloud Scheduler jobs
create_scheduler_jobs() {
    log_info "Creating Cloud Scheduler jobs for automated compliance workflows..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create scheduler jobs: daily, weekly, monthly"
        return 0
    fi

    # Get the report function URL
    local function_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${REPORT_FUNCTION}"

    # Create daily compliance report generation job
    log_info "Creating daily compliance report job..."
    gcloud scheduler jobs create http "${COMPLIANCE_JOB}-daily" \
        --location="${REGION}" \
        --schedule="0 8 * * *" \
        --uri="${function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"report_type": "daily"}' \
        --description="Daily compliance report generation" \
        --quiet || log_warning "Daily scheduler job may already exist"

    # Create weekly compliance summary job
    log_info "Creating weekly compliance summary job..."
    gcloud scheduler jobs create http "${COMPLIANCE_JOB}-weekly" \
        --location="${REGION}" \
        --schedule="0 9 * * 1" \
        --uri="${function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"report_type": "weekly"}' \
        --description="Weekly compliance summary report" \
        --quiet || log_warning "Weekly scheduler job may already exist"

    # Create monthly compliance audit job
    log_info "Creating monthly compliance audit job..."
    gcloud scheduler jobs create http "${COMPLIANCE_JOB}-monthly" \
        --location="${REGION}" \
        --schedule="0 10 1 * *" \
        --uri="${function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"report_type": "monthly"}' \
        --description="Monthly compliance audit report" \
        --quiet || log_warning "Monthly scheduler job may already exist"

    log_success "Cloud Scheduler jobs created for automated compliance reporting"
}

# Configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions for service integration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure IAM permissions for Cloud Functions service account"
        return 0
    fi

    # Get the default Cloud Functions service account
    local project_number
    project_number=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    local function_sa="${PROJECT_ID}@appspot.gserviceaccount.com"

    # Grant required permissions
    local roles=(
        "roles/documentai.apiUser"
        "roles/storage.objectAdmin"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )

    for role in "${roles[@]}"; do
        log_info "Granting ${role} to ${function_sa}..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${function_sa}" \
            --role="${role}" \
            --quiet || log_warning "IAM binding may already exist for ${role}"
    done

    log_success "IAM permissions configured for secure service integration"
}

# Upload sample compliance documents
upload_sample_documents() {
    if [[ "${SKIP_SAMPLES}" == "true" ]]; then
        log_info "Skipping sample document upload (--skip-samples specified)"
        return 0
    fi

    log_info "Creating and uploading sample compliance documents for testing..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would upload sample documents to ${INPUT_BUCKET}"
        return 0
    fi

    local samples_dir="${SCRIPT_DIR}/../temp-samples"
    mkdir -p "${samples_dir}"

    # Create sample contract document
    cat > "${samples_dir}/sample_contract.txt" << 'EOF'
SERVICE AGREEMENT

Date: 2024-01-15
Company Name: Example Corp Ltd
Contract Number: CTR-2024-001
Amount: $50,000.00

TERMS AND CONDITIONS:
1. Service period: January 1, 2024 to December 31, 2024
2. Payment terms: Net 30 days
3. Compliance: This agreement complies with SOX requirements

Signatures:
Client: [Signed] John Smith, CEO
Date: 2024-01-15

Vendor: [Signed] Jane Doe, Director
Date: 2024-01-15

Audit Trail: Document reviewed and approved by legal department
Compliance Officer: Sarah Johnson
Review Date: 2024-01-10
EOF

    # Create sample financial disclosure document
    cat > "${samples_dir}/sample_disclosure.txt" << 'EOF'
QUARTERLY FINANCIAL DISCLOSURE

Report Period: Q4 2023
Company: Example Corp Ltd
Date: 2024-01-31
Amount: $2,500,000.00

FINANCIAL SUMMARY:
Revenue: $2,500,000
Expenses: $2,100,000
Net Income: $400,000

COMPLIANCE CERTIFICATIONS:
SOX Compliance: Yes
Audit Firm: ABC Auditors LLP
Date: 2024-01-25

CEO Signature: [Signed] John Smith
CFO Signature: [Signed] Michael Brown
Date: 2024-01-31

Board Approval: Approved by Board of Directors
Meeting Date: 2024-01-28
EOF

    # Create sample GDPR compliance document
    cat > "${samples_dir}/sample_gdpr_report.txt" << 'EOF'
GDPR COMPLIANCE REPORT

Report Date: 2024-02-15
Company Name: Example Corp Ltd
Data Protection Officer: Maria Garcia

DATA PROCESSING ACTIVITIES:
- Customer data collection and storage
- Marketing communications
- Analytics and reporting

COMPLIANCE STATUS:
GDPR Article 6 Basis: Legitimate Interest
Data Retention Period: 24 months
Right to Erasure: Implemented
Data Breach Notifications: 0 incidents

Signature: [Signed] Maria Garcia, DPO
Date: 2024-02-15
EOF

    # Upload sample documents to input bucket
    log_info "Uploading sample documents..."
    gsutil cp "${samples_dir}/sample_contract.txt" "gs://${INPUT_BUCKET}/sample_contract.pdf"
    gsutil cp "${samples_dir}/sample_disclosure.txt" "gs://${INPUT_BUCKET}/sample_disclosure.pdf"
    gsutil cp "${samples_dir}/sample_gdpr_report.txt" "gs://${INPUT_BUCKET}/sample_gdpr_report.pdf"

    # Cleanup temporary directory
    rm -rf "${samples_dir}"

    log_success "Sample compliance documents uploaded for testing"
}

# Set up monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting for compliance workflows..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set up logging metrics and alerting policies"
        return 0
    fi

    # Create log-based metrics
    log_info "Creating log-based metrics..."
    
    # Compliance violations metric
    gcloud logging metrics create compliance_violations \
        --description="Count of compliance violations detected" \
        --log-filter='resource.type="cloud_function" AND textPayload:"NON_COMPLIANT"' \
        --quiet || log_warning "Compliance violations metric may already exist"

    # Processing errors metric
    gcloud logging metrics create processing_errors \
        --description="Count of document processing errors" \
        --log-filter='resource.type="cloud_function" AND severity="ERROR"' \
        --quiet || log_warning "Processing errors metric may already exist"

    # Successful processing metric
    gcloud logging metrics create successful_processing \
        --description="Count of successful document processing" \
        --log-filter='resource.type="cloud_function" AND textPayload:"Document processed successfully"' \
        --quiet || log_warning "Successful processing metric may already exist"

    # Create notification channel
    log_info "Creating notification channel..."
    local notification_channel
    notification_channel=$(gcloud alpha monitoring channels create \
        --display-name="Compliance Alerts" \
        --type=email \
        --channel-labels="email_address=${NOTIFICATION_EMAIL}" \
        --format="value(name)" 2>/dev/null || echo "")

    if [[ -n "${notification_channel}" ]]; then
        # Save notification channel for cleanup
        echo "NOTIFICATION_CHANNEL=${notification_channel}" >> "${SCRIPT_DIR}/deployment-config.env"

        # Create alerting policies
        log_info "Creating alerting policies..."
        create_alerting_policies "${notification_channel}"
    else
        log_warning "Failed to create notification channel, skipping alerting policies"
    fi

    log_success "Monitoring and alerting configured for compliance workflows"
}

# Create alerting policies
create_alerting_policies() {
    local notification_channel="$1"
    local temp_dir="${SCRIPT_DIR}/../temp-policies"
    mkdir -p "${temp_dir}"

    # Create compliance violations alert policy
    cat > "${temp_dir}/compliance_alert_policy.yaml" << EOF
displayName: "Compliance Violations Alert"
conditions:
  - displayName: "High Compliance Violations"
    conditionThreshold:
      filter: 'metric.type="logging.googleapis.com/user/compliance_violations"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 5
      duration: 300s
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_RATE
notificationChannels:
  - ${notification_channel}
alertStrategy:
  autoClose: 604800s
enabled: true
EOF

    # Create processing errors alert policy
    cat > "${temp_dir}/processing_errors_policy.yaml" << EOF
displayName: "Processing Errors Alert"
conditions:
  - displayName: "High Processing Error Rate"
    conditionThreshold:
      filter: 'metric.type="logging.googleapis.com/user/processing_errors"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 10
      duration: 600s
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_RATE
notificationChannels:
  - ${notification_channel}
alertStrategy:
  autoClose: 604800s
enabled: true
EOF

    # Apply alerting policies
    gcloud alpha monitoring policies create \
        --policy-from-file="${temp_dir}/compliance_alert_policy.yaml" \
        --quiet || log_warning "Compliance alert policy may already exist"

    gcloud alpha monitoring policies create \
        --policy-from-file="${temp_dir}/processing_errors_policy.yaml" \
        --quiet || log_warning "Processing errors alert policy may already exist"

    # Cleanup temporary directory
    rm -rf "${temp_dir}"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================================================================="
    echo "✅ Regulatory Compliance Automation System Deployed Successfully"
    echo "=================================================================="
    echo ""
    echo "📊 Project Information:"
    echo "   Project ID: ${PROJECT_ID}"
    echo "   Region: ${REGION}"
    echo "   Deployment Time: ${TIMESTAMP}"
    echo ""
    echo "🗄️ Storage Resources:"
    echo "   Input Bucket: gs://${INPUT_BUCKET}"
    echo "   Processed Bucket: gs://${PROCESSED_BUCKET}"
    echo "   Reports Bucket: gs://${REPORTS_BUCKET}"
    echo ""
    echo "⚡ Cloud Functions:"
    echo "   Document Processor: ${PROCESSOR_FUNCTION}"
    echo "   Report Generator: ${REPORT_FUNCTION}"
    echo ""
    echo "🤖 Document AI:"
    echo "   Processor ID: ${PROCESSOR_ID:-N/A}"
    echo "   Type: FORM_PARSER_PROCESSOR"
    echo ""
    echo "⏰ Scheduler Jobs:"
    echo "   Daily Reports: ${COMPLIANCE_JOB}-daily (8:00 AM daily)"
    echo "   Weekly Reports: ${COMPLIANCE_JOB}-weekly (9:00 AM Mondays)"
    echo "   Monthly Reports: ${COMPLIANCE_JOB}-monthly (10:00 AM 1st of month)"
    echo ""
    echo "📧 Notifications:"
    echo "   Email: ${NOTIFICATION_EMAIL}"
    echo ""
    echo "🔗 Useful Commands:"
    echo "   List resources: gcloud projects describe ${PROJECT_ID}"
    echo "   View logs: gcloud logging read 'resource.type=\"cloud_function\"'"
    echo "   Monitor jobs: gcloud scheduler jobs list --location=${REGION}"
    echo ""
    echo "🔄 Next Steps:"
    echo "   1. Upload compliance documents to gs://${INPUT_BUCKET}"
    echo "   2. Monitor processing in Cloud Console"
    echo "   3. Check reports in gs://${REPORTS_BUCKET}/reports/"
    echo "   4. Customize compliance rules in Cloud Functions"
    echo ""
    echo "🧹 Cleanup:"
    echo "   Run: ${SCRIPT_DIR}/destroy.sh --project-id ${PROJECT_ID}"
    echo ""
    echo "📝 Configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
    echo "=================================================================="
}

# Main deployment function
main() {
    log_info "Starting Automated Regulatory Compliance Reporting deployment..."
    log_info "Deployment started at: $(date)"
    log_info "Log file: ${LOG_FILE}"

    # Parse command line arguments
    parse_arguments "$@"

    # Validate prerequisites
    validate_prerequisites

    # Initialize environment
    initialize_environment

    # Setup project
    setup_project

    # Enable APIs
    enable_apis

    # Create storage buckets
    create_storage_buckets

    # Create Document AI processor
    create_document_ai_processor

    # Deploy Cloud Functions
    deploy_cloud_functions

    # Create scheduler jobs
    create_scheduler_jobs

    # Configure IAM permissions
    configure_iam_permissions

    # Upload sample documents
    upload_sample_documents

    # Setup monitoring
    setup_monitoring

    # Display summary
    if [[ "${DRY_RUN}" == "false" ]]; then
        display_summary
    else
        log_info "[DRY RUN] Deployment validation completed successfully"
        log_info "Run without --dry-run to perform actual deployment"
    fi

    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"
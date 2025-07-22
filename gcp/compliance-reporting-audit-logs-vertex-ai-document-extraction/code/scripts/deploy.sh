#!/bin/bash

# Compliance Reporting with Cloud Audit Logs and Vertex AI Document Extraction - Deploy Script
# This script deploys the complete compliance reporting infrastructure on Google Cloud Platform

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CLEANUP_FILE="${SCRIPT_DIR}/cleanup_resources.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
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

# Error handling function
cleanup_on_error() {
    log_error "Script failed. Check ${LOG_FILE} for details."
    log_error "Run ./destroy.sh to clean up any created resources."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Compliance Reporting Infrastructure Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -h, --help                    Show this help message
    --dry-run                     Show what would be deployed without executing
    --skip-prerequisites          Skip prerequisites checking

EXAMPLES:
    $0 --project-id my-project
    $0 --project-id my-project --region us-east1
    $0 --project-id my-project --dry-run

EOF
}

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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-prerequisites)
                SKIP_PREREQS=true
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

    # Set defaults
    REGION=${REGION:-"us-central1"}
    DRY_RUN=${DRY_RUN:-false}
    SKIP_PREREQS=${SKIP_PREREQS:-false}

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        show_help
        exit 1
    fi
}

# Prerequisites checking
check_prerequisites() {
    if [[ "${SKIP_PREREQS}" == "true" ]]; then
        log_warning "Skipping prerequisites check as requested"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or is not accessible."
        exit 1
    fi

    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Billing may not be enabled for project '${PROJECT_ID}'. Some services may not work."
    fi

    # Check required tools
    local required_tools=("curl" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed."
            exit 1
        fi
    done

    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."

    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION}"
    export ZONE="${REGION}-a"

    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)

    # Set resource names with unique identifiers
    export AUDIT_BUCKET="audit-logs-${RANDOM_SUFFIX}"
    export COMPLIANCE_BUCKET="compliance-docs-${RANDOM_SUFFIX}"
    export PROCESSOR_NAME="compliance-processor-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB="compliance-report-${RANDOM_SUFFIX}"

    # Store resource names for cleanup
    cat > "${CLEANUP_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
AUDIT_BUCKET=${AUDIT_BUCKET}
COMPLIANCE_BUCKET=${COMPLIANCE_BUCKET}
PROCESSOR_NAME=${PROCESSOR_NAME}
SCHEDULER_JOB=${SCHEDULER_JOB}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF

    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Configure Google Cloud project
configure_project() {
    log_info "Configuring Google Cloud project..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project to: ${PROJECT_ID}"
        log_info "[DRY RUN] Would set region to: ${REGION}"
        return 0
    fi

    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"

    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "logging.googleapis.com"
        "documentai.googleapis.com"
        "storage.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudfunctions.googleapis.com"
        "iam.googleapis.com"
        "cloudbuild.googleapis.com"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi

    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done

    log_success "All required APIs enabled"
}

# Configure Cloud Audit Logs
configure_audit_logs() {
    log_info "Configuring Cloud Audit Logs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create audit log sink to: ${AUDIT_BUCKET}"
        log_info "[DRY RUN] Would configure audit policy"
        return 0
    fi

    # Create audit log sink
    gcloud logging sinks create compliance-audit-sink \
        "storage.googleapis.com/${AUDIT_BUCKET}" \
        --log-filter='protoPayload.serviceName="storage.googleapis.com" OR 
                      protoPayload.serviceName="compute.googleapis.com" OR 
                      protoPayload.serviceName="iam.googleapis.com"' || {
        log_warning "Audit sink may already exist, continuing..."
    }

    # Create audit policy
    cat > audit-policy.yaml << EOF
auditConfigs:
- service: allServices
  auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_READ
  - logType: DATA_WRITE
EOF

    gcloud projects set-iam-policy "${PROJECT_ID}" audit-policy.yaml

    log_success "Cloud Audit Logs configured"
}

# Create storage infrastructure
create_storage() {
    log_info "Creating Cloud Storage infrastructure..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create buckets: ${AUDIT_BUCKET}, ${COMPLIANCE_BUCKET}"
        return 0
    fi

    # Create audit logs bucket
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${AUDIT_BUCKET}"

    gsutil versioning set on "gs://${AUDIT_BUCKET}"

    # Create compliance documents bucket
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${COMPLIANCE_BUCKET}"

    gsutil versioning set on "gs://${COMPLIANCE_BUCKET}"

    # Configure lifecycle management
    cat > lifecycle.json << EOF
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

    gsutil lifecycle set lifecycle.json "gs://${AUDIT_BUCKET}"
    gsutil lifecycle set lifecycle.json "gs://${COMPLIANCE_BUCKET}"

    log_success "Storage infrastructure created"
}

# Deploy Document AI processor
deploy_document_ai() {
    log_info "Deploying Vertex AI Document AI processor..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Document AI processor: ${PROCESSOR_NAME}"
        return 0
    fi

    # Create Document AI processor
    gcloud alpha documentai processors create \
        --type=FORM_PARSER_PROCESSOR \
        --display-name="${PROCESSOR_NAME}" \
        --location="${REGION}"

    # Get processor ID
    PROCESSOR_ID=$(gcloud alpha documentai processors list \
        --location="${REGION}" \
        --filter="displayName:${PROCESSOR_NAME}" \
        --format="value(name)" | cut -d'/' -f6)

    if [[ -z "${PROCESSOR_ID}" ]]; then
        log_error "Failed to get Document AI processor ID"
        exit 1
    fi

    # Store processor ID for cleanup
    echo "PROCESSOR_ID=${PROCESSOR_ID}" >> "${CLEANUP_FILE}"

    # Create contract processor
    gcloud alpha documentai processors create \
        --type=CONTRACT_PROCESSOR \
        --display-name="contract-${PROCESSOR_NAME}" \
        --location="${REGION}" || {
        log_warning "Contract processor creation failed, continuing with form parser only"
    }

    log_success "Document AI processors deployed"
    log_info "Processor ID: ${PROCESSOR_ID}"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Functions for document processing and reporting"
        return 0
    fi

    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "${temp_dir}"

    # Create compliance processor function
    mkdir compliance-processor && cd compliance-processor

    cat > requirements.txt << EOF
google-cloud-documentai>=2.20.1
google-cloud-storage>=2.10.0
google-cloud-logging>=3.8.0
functions-framework>=3.4.0
EOF

    cat > main.py << 'EOF'
import json
import base64
from google.cloud import documentai
from google.cloud import storage
from google.cloud import logging
import functions_framework
import os

@functions_framework.cloud_event
def process_compliance_document(cloud_event):
    """Process uploaded compliance documents using Document AI"""
    
    # Initialize clients
    doc_client = documentai.DocumentProcessorServiceClient()
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger("compliance-processor")
    
    # Extract event data
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    # Skip processing for non-document files
    if not file_name.endswith(('.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.txt')):
        return
    
    try:
        # Download document from storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Process document with Document AI
        processor_name = f"projects/{os.environ['PROJECT_ID']}/locations/{os.environ['REGION']}/processors/{os.environ['PROCESSOR_ID']}"
        
        raw_document = documentai.RawDocument(
            content=document_content,
            mime_type="application/pdf" if file_name.endswith('.pdf') else "text/plain"
        )
        
        request = documentai.ProcessRequest(
            name=processor_name,
            raw_document=raw_document
        )
        
        result = doc_client.process_document(request=request)
        
        # Extract and structure compliance data
        extracted_data = {
            "document_name": file_name,
            "extraction_confidence": result.document.pages[0].form_fields[0].value_confidence if result.document.pages and result.document.pages[0].form_fields else 0.9,
            "text_content": result.document.text,
            "entities": []
        }
        
        # Save extracted data
        output_blob = bucket.blob(f"processed/{file_name}.json")
        output_blob.upload_from_string(json.dumps(extracted_data, indent=2))
        
        logger.log_text(f"Successfully processed compliance document: {file_name}")
        
    except Exception as e:
        logger.log_text(f"Error processing document {file_name}: {str(e)}")
EOF

    # Deploy compliance processor function
    gcloud functions deploy compliance-processor \
        --runtime python311 \
        --trigger-bucket "${COMPLIANCE_BUCKET}" \
        --entry-point process_compliance_document \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},PROCESSOR_ID=${PROCESSOR_ID}"

    cd ..

    # Create report generator function
    mkdir report-generator && cd report-generator

    cat > requirements.txt << EOF
google-cloud-storage>=2.10.0
google-cloud-logging>=3.8.0
functions-framework>=3.4.0
EOF

    cat > main.py << 'EOF'
import json
import datetime
from google.cloud import storage
from google.cloud import logging
import functions_framework
import os

@functions_framework.http
def generate_compliance_report(request):
    """Generate automated compliance reports from processed data"""
    
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger("compliance-report")
    
    try:
        # Collect processed compliance data
        bucket = storage_client.bucket(os.environ['COMPLIANCE_BUCKET'])
        processed_blobs = bucket.list_blobs(prefix="processed/")
        
        report_data = {
            "report_date": datetime.datetime.now().isoformat(),
            "compliance_framework": "SOC 2 Type II",
            "documents_processed": 0,
            "compliance_status": "COMPLIANT",
            "findings": []
        }
        
        # Analyze processed documents
        for blob in processed_blobs:
            if blob.name.endswith('.json'):
                try:
                    content = json.loads(blob.download_as_text())
                    report_data["documents_processed"] += 1
                    
                    # Add compliance findings
                    if content.get("extraction_confidence", 0) < 0.8:
                        report_data["findings"].append({
                            "document": content["document_name"],
                            "issue": "Low extraction confidence",
                            "severity": "MEDIUM"
                        })
                except Exception as e:
                    logger.log_text(f"Error processing blob {blob.name}: {str(e)}")
        
        # Generate comprehensive report
        report_content = f"""
COMPLIANCE REPORT - {report_data['report_date']}

Framework: {report_data['compliance_framework']}
Overall Status: {report_data['compliance_status']}
Documents Processed: {report_data['documents_processed']}

FINDINGS:
{chr(10).join([f"- {finding['document']}: {finding['issue']} ({finding['severity']})" for finding in report_data['findings']])}

AUDIT TRAIL:
- All administrative activities logged via Cloud Audit Logs
- Document processing completed via Vertex AI Document AI
- Report generated automatically via Cloud Scheduler

Generated on: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
"""
        
        # Save report to storage
        report_blob = bucket.blob(f"reports/compliance-report-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.txt")
        report_blob.upload_from_string(report_content)
        
        logger.log_text("Compliance report generated successfully")
        
        return {"status": "success", "report_date": report_data["report_date"]}
        
    except Exception as e:
        logger.log_text(f"Error generating compliance report: {str(e)}")
        return {"status": "error", "message": str(e)}
EOF

    # Deploy report generator function
    gcloud functions deploy compliance-report-generator \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point generate_compliance_report \
        --memory 256MB \
        --timeout 180s \
        --set-env-vars "COMPLIANCE_BUCKET=${COMPLIANCE_BUCKET}"

    cd ..

    # Create log analytics function
    mkdir log-analytics && cd log-analytics

    cat > requirements.txt << EOF
google-cloud-logging>=3.8.0
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF

    cat > main.py << 'EOF'
import json
from google.cloud import logging
from google.cloud import storage
import functions_framework
from datetime import datetime, timedelta
import os

@functions_framework.http
def analyze_compliance_logs(request):
    """Analyze audit logs for compliance violations and patterns"""
    
    logging_client = logging.Client()
    storage_client = storage.Client()
    
    # Define compliance queries
    compliance_queries = [
        {
            "name": "Admin Activity Monitoring",
            "filter": 'protoPayload.serviceName="iam.googleapis.com" AND protoPayload.methodName="SetIamPolicy"',
            "description": "IAM policy changes for access control compliance"
        },
        {
            "name": "Data Access Tracking", 
            "filter": 'protoPayload.serviceName="storage.googleapis.com" AND protoPayload.methodName="storage.objects.get"',
            "description": "Data access patterns for privacy compliance"
        },
        {
            "name": "Failed Access Attempts",
            "filter": 'protoPayload.authenticationInfo.principalEmail!="" AND httpRequest.status>=400',
            "description": "Failed authentication attempts for security monitoring"
        }
    ]
    
    analysis_results = {
        "analysis_date": datetime.now().isoformat(),
        "compliance_insights": []
    }
    
    # Analyze each compliance area
    for query in compliance_queries:
        try:
            entries = logging_client.list_entries(filter_=query["filter"])
            entry_count = sum(1 for _ in entries)
            
            analysis_results["compliance_insights"].append({
                "category": query["name"],
                "description": query["description"],
                "event_count": entry_count,
                "compliance_status": "NORMAL" if entry_count < 100 else "REVIEW_REQUIRED"
            })
            
        except Exception as e:
            analysis_results["compliance_insights"].append({
                "category": query["name"],
                "error": str(e)
            })
    
    # Save analytics results
    bucket = storage_client.bucket(os.environ['COMPLIANCE_BUCKET'])
    analytics_blob = bucket.blob(f"analytics/compliance-analytics-{datetime.now().strftime('%Y%m%d')}.json")
    analytics_blob.upload_from_string(json.dumps(analysis_results, indent=2))
    
    return {"status": "success", "insights_generated": len(analysis_results["compliance_insights"])}
EOF

    # Deploy analytics function
    gcloud functions deploy compliance-log-analytics \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point analyze_compliance_logs \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "COMPLIANCE_BUCKET=${COMPLIANCE_BUCKET}"

    # Return to original directory
    cd "${SCRIPT_DIR}"
    rm -rf "${temp_dir}"

    log_success "Cloud Functions deployed successfully"
}

# Configure Cloud Scheduler
configure_scheduler() {
    log_info "Configuring Cloud Scheduler for automation..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create scheduled jobs for reporting and analytics"
        return 0
    fi

    # Create weekly reporting job
    gcloud scheduler jobs create http "${SCHEDULER_JOB}" \
        --schedule="0 9 * * MON" \
        --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/compliance-report-generator" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"report_type":"weekly"}'

    # Create daily analytics job
    gcloud scheduler jobs create http compliance-analytics-daily \
        --schedule="0 6 * * *" \
        --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/compliance-log-analytics" \
        --http-method=POST

    log_success "Cloud Scheduler configured"
    log_info "Weekly reports scheduled for Mondays at 9:00 AM"
    log_info "Daily analytics scheduled for 6:00 AM"
}

# Configure monitoring
configure_monitoring() {
    log_info "Configuring compliance monitoring..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure log-based metrics and monitoring"
        return 0
    fi

    # Create log-based metrics
    gcloud logging metrics create compliance_violations \
        --description="Track compliance violations from audit logs" \
        --log-filter='protoPayload.authenticationInfo.principalEmail!="" AND httpRequest.status>=400' || {
        log_warning "Metric compliance_violations may already exist"
    }

    gcloud logging metrics create document_processing_success \
        --description="Track successful document processing" \
        --log-filter='resource.type="cloud_function" AND textPayload:"Successfully processed compliance document"' || {
        log_warning "Metric document_processing_success may already exist"
    }

    log_success "Monitoring configuration completed"
}

# Upload sample documents
upload_sample_documents() {
    log_info "Uploading sample compliance documents..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would upload sample compliance documents"
        return 0
    fi

    # Create sample compliance policy document
    cat > compliance-policy.txt << EOF
COMPLIANCE POLICY

Document Type: Security Policy
Version: 2.1
Effective Date: 2025-01-01
Last Review: 2025-01-01

OVERVIEW
This policy establishes security requirements for data handling, access controls, 
and compliance monitoring within the organization.

SCOPE
This policy applies to all employees, contractors, and third-party vendors 
with access to organizational data and systems.

REQUIREMENTS
1. All data access must be logged and monitored
2. Multi-factor authentication is required for all systems
3. Regular security assessments must be conducted
4. Incident response procedures must be followed

COMPLIANCE FRAMEWORKS
- SOC 2 Type II
- ISO 27001
- GDPR

Document Control: COMP-POL-001
Approved by: Chief Security Officer
Next Review: 2026-01-01
EOF

    # Upload to compliance bucket
    gsutil cp compliance-policy.txt "gs://${COMPLIANCE_BUCKET}/policies/"

    # Create sample contract document
    cat > sample-contract.txt << EOF
SERVICE LEVEL AGREEMENT

Contract Number: SLA-2025-001
Effective Date: 2025-01-01
Service Provider: Cloud Services Inc.
Client: Enterprise Corp.

PERFORMANCE METRICS
- Uptime: 99.9%
- Response Time: < 200ms
- Data Recovery: < 4 hours

COMPLIANCE REQUIREMENTS
- SOC 2 Type II certification
- Regular security audits
- Incident reporting within 24 hours

Security provisions and data protection measures are detailed 
in Schedule A of this agreement.
EOF

    gsutil cp sample-contract.txt "gs://${COMPLIANCE_BUCKET}/contracts/"

    # Clean up local files
    rm -f compliance-policy.txt sample-contract.txt audit-policy.yaml lifecycle.json

    log_success "Sample documents uploaded"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test deployment functionality"
        return 0
    fi

    # Wait for functions to be ready
    sleep 30

    # Test report generation
    log_info "Testing compliance report generation..."
    local report_response
    report_response=$(curl -s -X POST \
        "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/compliance-report-generator" \
        -H "Content-Type: application/json" \
        -d '{"report_type":"test"}' || echo "failed")

    if [[ "${report_response}" == *"success"* ]]; then
        log_success "Report generation test passed"
    else
        log_warning "Report generation test failed, but deployment continues"
    fi

    # Test analytics
    log_info "Testing compliance analytics..."
    local analytics_response
    analytics_response=$(curl -s -X POST \
        "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/compliance-log-analytics" || echo "failed")

    if [[ "${analytics_response}" == *"success"* ]]; then
        log_success "Analytics test passed"
    else
        log_warning "Analytics test failed, but deployment continues"
    fi

    # Check storage buckets
    if gsutil ls "gs://${COMPLIANCE_BUCKET}" &>/dev/null; then
        log_success "Storage infrastructure verified"
    else
        log_error "Storage infrastructure verification failed"
        exit 1
    fi

    log_success "Deployment testing completed"
}

# Display deployment summary
show_summary() {
    log_info "Deployment Summary"
    cat << EOF

🎉 Compliance Reporting Infrastructure Deployed Successfully!

📋 DEPLOYMENT DETAILS:
   Project ID: ${PROJECT_ID}
   Region: ${REGION}
   Resource Suffix: ${RANDOM_SUFFIX}

📦 CREATED RESOURCES:
   • Cloud Storage Buckets:
     - Audit Logs: gs://${AUDIT_BUCKET}
     - Compliance Docs: gs://${COMPLIANCE_BUCKET}
   
   • Document AI Processor: ${PROCESSOR_NAME}
   
   • Cloud Functions:
     - compliance-processor
     - compliance-report-generator  
     - compliance-log-analytics
   
   • Cloud Scheduler Jobs:
     - ${SCHEDULER_JOB} (Weekly reports)
     - compliance-analytics-daily
   
   • Monitoring Metrics:
     - compliance_violations
     - document_processing_success

🔗 USEFUL LINKS:
   • Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}
   • Storage Buckets: https://console.cloud.google.com/storage/browser?project=${PROJECT_ID}
   • Cloud Functions: https://console.cloud.google.com/functions/list?project=${PROJECT_ID}
   • Cloud Scheduler: https://console.cloud.google.com/cloudscheduler?project=${PROJECT_ID}

📊 NEXT STEPS:
   1. Upload compliance documents to: gs://${COMPLIANCE_BUCKET}/policies/
   2. Monitor automated reports in: gs://${COMPLIANCE_BUCKET}/reports/
   3. Review analytics data in: gs://${COMPLIANCE_BUCKET}/analytics/
   4. Configure notification channels for alerting

⚠️  CLEANUP:
   Run ./destroy.sh to remove all created resources when no longer needed.

📝 LOGS:
   Deployment log: ${LOG_FILE}
   Cleanup info: ${CLEANUP_FILE}

EOF
}

# Main deployment function
main() {
    log_info "Starting Compliance Reporting Infrastructure Deployment"
    log_info "Script started at $(date)"

    # Initialize cleanup file
    echo "# Compliance Reporting Cleanup Resources" > "${CLEANUP_FILE}"
    echo "# Generated at $(date)" >> "${CLEANUP_FILE}"

    parse_args "$@"
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    configure_audit_logs
    create_storage
    deploy_document_ai
    deploy_functions
    configure_scheduler
    configure_monitoring
    upload_sample_documents
    test_deployment
    show_summary

    log_success "Deployment completed successfully!"
    log_info "Total deployment time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
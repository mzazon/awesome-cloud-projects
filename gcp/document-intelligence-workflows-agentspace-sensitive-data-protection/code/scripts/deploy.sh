#!/bin/bash

# Deploy script for Document Intelligence Workflows with Agentspace and Sensitive Data Protection
# This script deploys the complete infrastructure for intelligent document processing

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    if [[ -n "${INPUT_BUCKET:-}" ]]; then
        gsutil -m rm -rf "gs://${INPUT_BUCKET}" 2>/dev/null || true
    fi
    if [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        gsutil -m rm -rf "gs://${OUTPUT_BUCKET}" 2>/dev/null || true
    fi
    if [[ -n "${AUDIT_BUCKET:-}" ]]; then
        gsutil -m rm -rf "gs://${AUDIT_BUCKET}" 2>/dev/null || true
    fi
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI is not installed. Please install Google Cloud SDK first."
        exit 1
    fi
    
    # Check if openssl is available for generating random values
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl for random value generation."
        exit 1
    fi
    
    # Check if base64 is available
    if ! command -v base64 &> /dev/null; then
        log_error "base64 is not installed. Please install base64 for document encoding."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No default project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Verify billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Unable to verify billing status. Please ensure billing is enabled for project $PROJECT_ID"
    fi
    
    log_success "All prerequisites check passed"
}

# Function to validate environment variables
validate_environment() {
    log "Validating environment configuration..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set and no default project configured"
        exit 1
    fi
    
    log "Using Project ID: $PROJECT_ID"
    log "Using Region: $REGION"
    log "Using Zone: $ZONE"
    
    log_success "Environment validation completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "documentai.googleapis.com"
        "dlp.googleapis.com"
        "workflows.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for GCP resources
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Set bucket names
    export INPUT_BUCKET="doc-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="doc-output-${RANDOM_SUFFIX}"
    export AUDIT_BUCKET="doc-audit-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets for document processing pipeline..."
    
    # Create input bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${INPUT_BUCKET}"; then
        log_success "Created input bucket: gs://${INPUT_BUCKET}"
    else
        log_error "Failed to create input bucket"
        exit 1
    fi
    
    # Create output bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${OUTPUT_BUCKET}"; then
        log_success "Created output bucket: gs://${OUTPUT_BUCKET}"
    else
        log_error "Failed to create output bucket"
        exit 1
    fi
    
    # Create audit bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${AUDIT_BUCKET}"; then
        log_success "Created audit bucket: gs://${AUDIT_BUCKET}"
    else
        log_error "Failed to create audit bucket"
        exit 1
    fi
    
    # Enable versioning for compliance
    log "Enabling versioning for data protection and audit compliance..."
    gsutil versioning set on "gs://${INPUT_BUCKET}"
    gsutil versioning set on "gs://${OUTPUT_BUCKET}"
    gsutil versioning set on "gs://${AUDIT_BUCKET}"
    
    log_success "Storage buckets created and configured with versioning"
}

# Function to create Document AI processor
create_document_ai_processor() {
    log "Creating Document AI processor for intelligent document analysis..."
    
    # Create Document AI processor
    if PROCESSOR_OUTPUT=$(gcloud documentai processors create \
        --location="${REGION}" \
        --processor-type=FORM_PARSER_PROCESSOR \
        --display-name="enterprise-doc-processor-${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null); then
        
        export PROCESSOR_ID=$(echo "$PROCESSOR_OUTPUT" | cut -d'/' -f6)
        export PROCESSOR_NAME="projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}"
        
        log_success "Document AI processor created: ${PROCESSOR_NAME}"
        
        # Save processor details to file
        echo "PROCESSOR_ID=${PROCESSOR_ID}" >> .env
        echo "PROCESSOR_NAME=${PROCESSOR_NAME}" >> .env
    else
        log_error "Failed to create Document AI processor"
        exit 1
    fi
}

# Function to configure DLP templates
configure_dlp_templates() {
    log "Configuring Sensitive Data Protection templates for compliance..."
    
    # Create DLP inspection template configuration
    cat > dlp-template.json << 'EOF'
{
  "displayName": "Enterprise Document PII Scanner",
  "description": "Comprehensive PII detection for enterprise documents",
  "inspectConfig": {
    "infoTypes": [
      {"name": "EMAIL_ADDRESS"},
      {"name": "PERSON_NAME"},
      {"name": "PHONE_NUMBER"},
      {"name": "CREDIT_CARD_NUMBER"},
      {"name": "US_SOCIAL_SECURITY_NUMBER"},
      {"name": "IBAN_CODE"},
      {"name": "DATE_OF_BIRTH"},
      {"name": "PASSPORT"},
      {"name": "MEDICAL_RECORD_NUMBER"},
      {"name": "US_BANK_ROUTING_MICR"}
    ],
    "minLikelihood": "POSSIBLE",
    "includeQuote": true,
    "limits": {
      "maxFindingsPerRequest": 1000
    }
  }
}
EOF
    
    # Create DLP inspection template
    if DLP_TEMPLATE_OUTPUT=$(gcloud dlp inspect-templates create \
        --source=dlp-template.json \
        --format="value(name)" 2>/dev/null); then
        
        export DLP_TEMPLATE_ID=$(echo "$DLP_TEMPLATE_OUTPUT" | cut -d'/' -f4)
        log_success "DLP inspection template created: ${DLP_TEMPLATE_ID}"
        
        # Save to environment file
        echo "DLP_TEMPLATE_ID=${DLP_TEMPLATE_ID}" >> .env
    else
        log_error "Failed to create DLP inspection template"
        exit 1
    fi
    
    # Create DLP de-identification template configuration
    cat > dlp-deidentify-template.json << 'EOF'
{
  "displayName": "Enterprise Document Redaction",
  "description": "Automated redaction for sensitive data in documents",
  "deidentifyConfig": {
    "infoTypeTransformations": {
      "transformations": [
        {
          "infoTypes": [
            {"name": "EMAIL_ADDRESS"},
            {"name": "PERSON_NAME"},
            {"name": "PHONE_NUMBER"}
          ],
          "primitiveTransformation": {
            "replaceConfig": {
              "newValue": {
                "stringValue": "[REDACTED]"
              }
            }
          }
        },
        {
          "infoTypes": [
            {"name": "CREDIT_CARD_NUMBER"},
            {"name": "US_SOCIAL_SECURITY_NUMBER"}
          ],
          "primitiveTransformation": {
            "cryptoHashConfig": {
              "cryptoKey": {
                "unwrapped": {
                  "key": "YWJjZGVmZ2hpamtsbW5vcA=="
                }
              }
            }
          }
        }
      ]
    }
  }
}
EOF
    
    # Create DLP de-identification template
    if DEIDENTIFY_TEMPLATE_OUTPUT=$(gcloud dlp deidentify-templates create \
        --source=dlp-deidentify-template.json \
        --format="value(name)" 2>/dev/null); then
        
        export DEIDENTIFY_TEMPLATE_ID=$(echo "$DEIDENTIFY_TEMPLATE_OUTPUT" | cut -d'/' -f4)
        log_success "DLP de-identification template created: ${DEIDENTIFY_TEMPLATE_ID}"
        
        # Save to environment file
        echo "DEIDENTIFY_TEMPLATE_ID=${DEIDENTIFY_TEMPLATE_ID}" >> .env
    else
        log_error "Failed to create DLP de-identification template"
        exit 1
    fi
    
    # Clean up temporary files
    rm -f dlp-template.json dlp-deidentify-template.json
    
    log_success "DLP templates configured for comprehensive data protection"
}

# Function to deploy Cloud Workflows
deploy_cloud_workflows() {
    log "Deploying Cloud Workflows for document processing orchestration..."
    
    # Create comprehensive document processing workflow
    cat > document-processing-workflow.yaml << EOF
main:
  params: [input]
  steps:
    - init:
        assign:
          - project_id: ${PROJECT_ID}
          - location: ${REGION}
          - processor_name: "${PROCESSOR_NAME}"
          - input_bucket: ${INPUT_BUCKET}
          - output_bucket: ${OUTPUT_BUCKET}
          - audit_bucket: ${AUDIT_BUCKET}
          - dlp_template: ${DLP_TEMPLATE_ID}
          - deidentify_template: ${DEIDENTIFY_TEMPLATE_ID}
          - document_path: \${input.document_path}
          - processing_start_time: \${sys.now()}
    
    - log_processing_start:
        call: sys.log
        args:
          text: \${"Starting document processing for: " + document_path}
          severity: "INFO"
    
    - process_document_ai:
        call: http.post
        args:
          url: \${"https://documentai.googleapis.com/v1/" + processor_name + ":process"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            rawDocument:
              content: \${input.document_content}
              mimeType: "application/pdf"
        result: docai_response
    
    - extract_document_text:
        assign:
          - extracted_text: \${docai_response.body.document.text}
          - entities: \${docai_response.body.document.entities}
    
    - scan_for_sensitive_data:
        call: http.post
        args:
          url: "https://dlp.googleapis.com/v2/projects/\${project_id}/content:inspect"
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            parent: \${"projects/" + project_id}
            inspectTemplate: \${"projects/" + project_id + "/inspectTemplates/" + dlp_template}
            item:
              value: \${extracted_text}
        result: dlp_scan_response
    
    - evaluate_sensitivity:
        switch:
          - condition: \${len(dlp_scan_response.body.result.findings) > 0}
            next: redact_sensitive_data
          - condition: true
            next: store_clean_document
    
    - redact_sensitive_data:
        call: http.post
        args:
          url: "https://dlp.googleapis.com/v2/projects/\${project_id}/content:deidentify"
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            parent: \${"projects/" + project_id}
            deidentifyTemplate: \${"projects/" + project_id + "/deidentifyTemplates/" + deidentify_template}
            item:
              value: \${extracted_text}
        result: redaction_response
        next: store_redacted_document
    
    - store_redacted_document:
        assign:
          - redacted_content: \${redaction_response.body.item.value}
          - output_path: \${"gs://" + output_bucket + "/redacted/" + document_path}
        next: log_completion
    
    - store_clean_document:
        assign:
          - clean_content: \${extracted_text}
          - output_path: \${"gs://" + output_bucket + "/clean/" + document_path}
        next: log_completion
    
    - log_completion:
        call: sys.log
        args:
          text: \${"Document processing completed for: " + document_path + " stored at: " + output_path}
          severity: "INFO"
        next: return_result
    
    - return_result:
        return:
          status: "completed"
          input_document: \${document_path}
          output_location: \${output_path}
          sensitive_data_found: \${len(dlp_scan_response.body.result.findings)}
          processing_time: \${sys.now() - processing_start_time}
          entities_extracted: \${len(entities)}
EOF
    
    # Deploy the document processing workflow
    export WORKFLOW_NAME="doc-intelligence-workflow-${RANDOM_SUFFIX}"
    if gcloud workflows deploy "${WORKFLOW_NAME}" \
        --source=document-processing-workflow.yaml \
        --location="${REGION}"; then
        
        log_success "Cloud Workflows deployed: ${WORKFLOW_NAME}"
        
        # Save to environment file
        echo "WORKFLOW_NAME=${WORKFLOW_NAME}" >> .env
    else
        log_error "Failed to deploy Cloud Workflows"
        exit 1
    fi
    
    # Clean up temporary workflow file
    rm -f document-processing-workflow.yaml
}

# Function to configure Agentspace integration
configure_agentspace_integration() {
    log "Configuring Agentspace Enterprise for intelligent document workflow management..."
    
    # Create Agentspace configuration
    cat > agentspace-config.json << EOF
{
  "agent_name": "DocumentIntelligenceAgent",
  "description": "Enterprise AI agent for intelligent document processing and workflow orchestration",
  "capabilities": [
    "document_classification",
    "content_extraction",
    "workflow_orchestration",
    "compliance_monitoring",
    "intelligent_routing"
  ],
  "data_sources": [
    {
      "type": "cloud_storage",
      "bucket": "${INPUT_BUCKET}",
      "access_pattern": "read_only"
    },
    {
      "type": "cloud_storage", 
      "bucket": "${OUTPUT_BUCKET}",
      "access_pattern": "read_write"
    }
  ],
  "workflow_integration": {
    "primary_workflow": "${WORKFLOW_NAME}",
    "trigger_conditions": [
      "new_document_upload",
      "processing_request",
      "compliance_review"
    ]
  },
  "security_controls": {
    "data_classification": "sensitive",
    "access_logging": true,
    "encryption_required": true
  }
}
EOF
    
    # Store Agentspace configuration in Cloud Storage
    if gsutil cp agentspace-config.json "gs://${AUDIT_BUCKET}/agentspace-config.json"; then
        log_success "Agentspace configuration stored"
    else
        log_error "Failed to store Agentspace configuration"
        exit 1
    fi
    
    # Create IAM service account for Agentspace integration
    if gcloud iam service-accounts create agentspace-doc-processor \
        --display-name="Agentspace Document Processor" \
        --description="Service account for Agentspace document processing integration"; then
        
        log_success "Created Agentspace service account"
    else
        log_warning "Service account may already exist, continuing..."
    fi
    
    # Grant necessary permissions
    local service_account="agentspace-doc-processor@${PROJECT_ID}.iam.gserviceaccount.com"
    local roles=(
        "roles/documentai.apiUser"
        "roles/dlp.user"
        "roles/workflows.invoker"
        "roles/storage.objectAdmin"
        "roles/bigquery.dataEditor"
    )
    
    for role in "${roles[@]}"; do
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="${role}"; then
            log_success "Granted role ${role} to Agentspace service account"
        else
            log_error "Failed to grant role ${role}"
            exit 1
        fi
    done
    
    # Clean up temporary files
    rm -f agentspace-config.json
    
    log_success "Agentspace integration configured"
}

# Function to setup BigQuery analytics
setup_bigquery_analytics() {
    log "Setting up BigQuery analytics for document intelligence..."
    
    # Create BigQuery dataset
    if bq mk --dataset \
        --description="Document intelligence processing analytics" \
        "${PROJECT_ID}:document_intelligence"; then
        
        log_success "Created BigQuery dataset: document_intelligence"
    else
        log_warning "BigQuery dataset may already exist, continuing..."
    fi
    
    # Create table for processed document metadata
    if bq mk --table \
        "${PROJECT_ID}:document_intelligence.processed_documents" \
        document_id:STRING,processing_timestamp:TIMESTAMP,document_type:STRING,sensitive_data_found:BOOLEAN,compliance_level:STRING,processing_status:STRING,file_path:STRING,entities_extracted:INTEGER,redaction_applied:BOOLEAN; then
        
        log_success "Created processed_documents table"
    else
        log_warning "Table may already exist, continuing..."
    fi
    
    # Create compliance summary view
    if bq query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`${PROJECT_ID}.document_intelligence.compliance_summary\` AS
    SELECT 
      DATE(processing_timestamp) as processing_date,
      document_type,
      compliance_level,
      COUNT(*) as document_count,
      SUM(CASE WHEN sensitive_data_found THEN 1 ELSE 0 END) as sensitive_documents,
      SUM(CASE WHEN redaction_applied THEN 1 ELSE 0 END) as redacted_documents
    FROM \`${PROJECT_ID}.document_intelligence.processed_documents\`
    GROUP BY processing_date, document_type, compliance_level
    ORDER BY processing_date DESC"; then
        
        log_success "Created compliance_summary view"
    else
        log_error "Failed to create compliance summary view"
        exit 1
    fi
}

# Function to configure monitoring and alerting
configure_monitoring() {
    log "Configuring monitoring and audit capabilities..."
    
    # Create audit log sink
    if gcloud logging sinks create doc-intelligence-audit-sink \
        "gs://${AUDIT_BUCKET}/audit-logs" \
        --log-filter='protoPayload.serviceName="documentai.googleapis.com" OR 
                     protoPayload.serviceName="dlp.googleapis.com" OR
                     protoPayload.serviceName="workflows.googleapis.com"'; then
        
        log_success "Created audit log sink"
    else
        log_warning "Audit log sink may already exist, continuing..."
    fi
    
    # Create custom metrics
    if gcloud logging metrics create document_processing_volume \
        --description="Volume of documents processed by the intelligence pipeline" \
        --log-filter='resource.type="cloud_workflow" AND jsonPayload.message:"Document processing completed"'; then
        
        log_success "Created document processing volume metric"
    else
        log_warning "Metric may already exist, continuing..."
    fi
    
    if gcloud logging metrics create sensitive_data_detections \
        --description="Count of sensitive data detections in processed documents" \
        --log-filter='resource.type="dlp_job" AND jsonPayload.findings:*'; then
        
        log_success "Created sensitive data detections metric"
    else
        log_warning "Metric may already exist, continuing..."
    fi
    
    log_success "Monitoring and audit capabilities configured"
}

# Function to create sample test document
create_test_document() {
    log "Creating sample test document for validation..."
    
    cat > sample-document.txt << 'EOF'
CONFIDENTIAL EMPLOYEE RECORD

Employee Information:
Name: John Smith
Email: john.smith@company.com
Phone: (555) 123-4567
SSN: 123-45-6789
Credit Card: 4532-1234-5678-9012

Performance Review:
This employee has demonstrated excellent performance in the finance department.
Salary: $85,000 annually
Start Date: January 15, 2020

Medical Information:
Health Insurance: Policy #HI-789654123
Emergency Contact: Jane Smith (555) 987-6543

This document contains sensitive personal information and should be handled
according to company data protection policies and applicable regulations.
EOF
    
    # Upload sample document to input bucket
    if gsutil cp sample-document.txt "gs://${INPUT_BUCKET}/sample-document.txt"; then
        log_success "Sample test document uploaded to input bucket"
    else
        log_error "Failed to upload sample document"
        exit 1
    fi
    
    # Clean up local file
    rm -f sample-document.txt
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment summary
    cat > deployment-summary.txt << EOF
Document Intelligence Workflows Deployment Summary
================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Deployment Time: $(date)

Resources Created:
- Storage Buckets:
  * Input: gs://${INPUT_BUCKET}
  * Output: gs://${OUTPUT_BUCKET}
  * Audit: gs://${AUDIT_BUCKET}

- Document AI Processor: ${PROCESSOR_NAME}
- DLP Templates:
  * Inspection: ${DLP_TEMPLATE_ID}
  * De-identification: ${DEIDENTIFY_TEMPLATE_ID}

- Cloud Workflow: ${WORKFLOW_NAME}
- BigQuery Dataset: ${PROJECT_ID}:document_intelligence

- Service Account: agentspace-doc-processor@${PROJECT_ID}.iam.gserviceaccount.com

Next Steps:
1. Test the workflow with sample documents
2. Configure Agentspace Enterprise integration
3. Set up monitoring dashboards
4. Review compliance and audit logs

Cost Estimate: $150-300 for 2 hours of testing
EOF
    
    # Save deployment summary to audit bucket
    gsutil cp deployment-summary.txt "gs://${AUDIT_BUCKET}/deployment-summary.txt"
    
    # Display summary
    cat deployment-summary.txt
    
    # Clean up local file
    rm -f deployment-summary.txt
    
    log_success "Deployment information saved to audit bucket"
}

# Main deployment function
main() {
    log "Starting Document Intelligence Workflows deployment..."
    log "This deployment will create a complete intelligent document processing system"
    log "with Agentspace integration and comprehensive data protection capabilities."
    
    # Check if user wants to proceed
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    validate_environment
    enable_apis
    setup_environment
    create_storage_buckets
    create_document_ai_processor
    configure_dlp_templates
    deploy_cloud_workflows
    configure_agentspace_integration
    setup_bigquery_analytics
    configure_monitoring
    create_test_document
    save_deployment_info
    
    log_success "Document Intelligence Workflows deployment completed successfully!"
    log_success "Review the deployment summary for next steps and testing instructions."
    log_warning "Remember to run the destroy script when finished testing to avoid ongoing charges."
}

# Run main function
main "$@"
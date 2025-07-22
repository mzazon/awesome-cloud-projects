#!/bin/bash
set -euo pipefail

# Document Validation Workflows with Document AI and Cloud Workflows - Deployment Script
# This script deploys the complete document validation pipeline infrastructure

# Colors for output
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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to validate environment variables
validate_env() {
    local required_vars=("PROJECT_ID" "REGION")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Environment variable $var is not set"
            exit 1
        fi
    done
}

# Function to check if user is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
}

# Function to check project existence and permissions
check_project() {
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error "Project ${PROJECT_ID} does not exist or you don't have access to it"
        exit 1
    fi
    
    info "Using project: ${PROJECT_ID}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "documentai.googleapis.com"
        "workflows.googleapis.com"
        "storage.googleapis.com"
        "eventarc.googleapis.com"
        "cloudbuild.googleapis.com"
        "bigquery.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${PROJECT_ID}" --quiet; then
            log "✅ ${api} enabled successfully"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create storage buckets
create_buckets() {
    log "Creating storage buckets for document processing pipeline..."
    
    # Generate unique suffix for bucket names
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100-999 -n 1)")
    
    export INPUT_BUCKET="doc-input-${timestamp}-${random_suffix}"
    export VALID_BUCKET="doc-valid-${timestamp}-${random_suffix}"
    export INVALID_BUCKET="doc-invalid-${timestamp}-${random_suffix}"
    export REVIEW_BUCKET="doc-review-${timestamp}-${random_suffix}"
    
    local buckets=("$INPUT_BUCKET" "$VALID_BUCKET" "$INVALID_BUCKET" "$REVIEW_BUCKET")
    
    for bucket in "${buckets[@]}"; do
        info "Creating bucket: gs://${bucket}"
        if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket}" &> /dev/null; then
            log "✅ Bucket gs://${bucket} created successfully"
        else
            error "Failed to create bucket gs://${bucket}"
            exit 1
        fi
    done
    
    # Store bucket names in environment file for cleanup
    cat > bucket_names.env << EOF
INPUT_BUCKET=${INPUT_BUCKET}
VALID_BUCKET=${VALID_BUCKET}
INVALID_BUCKET=${INVALID_BUCKET}
REVIEW_BUCKET=${REVIEW_BUCKET}
EOF
}

# Function to create Document AI processors
create_processors() {
    log "Creating Document AI processors..."
    
    # Create Form Parser processor
    info "Creating Form Parser processor..."
    local form_processor_output
    form_processor_output=$(gcloud documentai processors create \
        --location="${REGION}" \
        --display-name="form-processor-$(date +%s)" \
        --type=FORM_PARSER_PROCESSOR \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$form_processor_output" ]]; then
        export FORM_PROCESSOR_ID=$(echo "$form_processor_output" | sed 's/.*processors\///')
        log "✅ Form Processor created: ${FORM_PROCESSOR_ID}"
    else
        error "Failed to create Form Parser processor"
        exit 1
    fi
    
    # Create Invoice Parser processor
    info "Creating Invoice Parser processor..."
    local invoice_processor_output
    invoice_processor_output=$(gcloud documentai processors create \
        --location="${REGION}" \
        --display-name="invoice-processor-$(date +%s)" \
        --type=INVOICE_PROCESSOR \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$invoice_processor_output" ]]; then
        export INVOICE_PROCESSOR_ID=$(echo "$invoice_processor_output" | sed 's/.*processors\///')
        log "✅ Invoice Processor created: ${INVOICE_PROCESSOR_ID}"
    else
        error "Failed to create Invoice Parser processor"
        exit 1
    fi
    
    # Store processor IDs in environment file
    cat >> processor_ids.env << EOF
FORM_PROCESSOR_ID=${FORM_PROCESSOR_ID}
INVOICE_PROCESSOR_ID=${INVOICE_PROCESSOR_ID}
EOF
}

# Function to create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset for document analytics..."
    
    local timestamp=$(date +%s)
    export DATASET_NAME="document_analytics_${timestamp}"
    
    # Create dataset
    info "Creating BigQuery dataset: ${DATASET_NAME}"
    if bq mk --dataset \
        --location="${REGION}" \
        --description="Document processing analytics and validation metrics" \
        "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "✅ BigQuery dataset created: ${DATASET_NAME}"
    else
        error "Failed to create BigQuery dataset"
        exit 1
    fi
    
    # Create table for processing results
    info "Creating processing results table..."
    local schema="document_id:STRING,processor_type:STRING,processing_time:TIMESTAMP,validation_status:STRING,confidence_score:FLOAT,extracted_fields:JSON,validation_errors:JSON"
    
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.processing_results" \
        "$schema" &> /dev/null; then
        log "✅ Processing results table created"
    else
        error "Failed to create processing results table"
        exit 1
    fi
    
    # Store dataset name in environment file
    echo "DATASET_NAME=${DATASET_NAME}" > dataset_name.env
}

# Function to create workflow definition
create_workflow_definition() {
    log "Creating Cloud Workflows definition..."
    
    # Create workflow YAML file
    cat > document-validation-workflow.yaml << 'EOF'
main:
  params: [event]
  steps:
    - init:
        assign:
          - bucket: ${event.data.bucket}
          - name: ${event.data.name}
          - project_id: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
          - region: "us-central1"
          - form_processor: ${sys.get_env("FORM_PROCESSOR_ID")}
          - invoice_processor: ${sys.get_env("INVOICE_PROCESSOR_ID")}
    
    - log_start:
        call: sys.log
        args:
          text: ${"Starting document processing for: " + name}
          severity: INFO
    
    - determine_document_type:
        switch:
          - condition: ${text.match_regex(name, ".*invoice.*|.*bill.*|.*receipt.*")}
            assign:
              - processor_id: ${invoice_processor}
              - document_type: "invoice"
            next: process_document
          - condition: ${text.match_regex(name, ".*form.*|.*application.*")}
            assign:
              - processor_id: ${form_processor}
              - document_type: "form"
            next: process_document
        next: default_processing
    
    - default_processing:
        assign:
          - processor_id: ${form_processor}
          - document_type: "general"
    
    - process_document:
        try:
          call: googleapis.documentai.v1.projects.locations.processors.process
          args:
            name: ${"projects/" + project_id + "/locations/" + region + "/processors/" + processor_id}
            body:
              rawDocument:
                content: ${base64.encode(http.get("gs://" + bucket + "/" + name).body)}
                mimeType: "application/pdf"
          result: processing_result
        except:
          as: e
          steps:
            - log_error:
                call: sys.log
                args:
                  text: ${"Document processing failed: " + string(e)}
                  severity: ERROR
            - move_to_invalid:
                call: googleapis.storage.v1.objects.copy
                args:
                  sourceBucket: ${bucket}
                  sourceObject: ${name}
                  destinationBucket: ${sys.get_env("INVALID_BUCKET")}
                  destinationObject: ${name}
            - return_error:
                return: {"status": "error", "message": "Processing failed"}
    
    - validate_extraction:
        assign:
          - confidence_threshold: 0.8
          - validation_errors: []
          - extracted_data: ${processing_result.document.entities}
    
    - check_confidence:
        for:
          value: entity
          in: ${extracted_data}
          steps:
            - evaluate_confidence:
                switch:
                  - condition: ${entity.confidence < confidence_threshold}
                    steps:
                      - add_error:
                          assign:
                            - validation_errors: ${list.concat(validation_errors, [{"field": entity.type, "confidence": entity.confidence, "reason": "Low confidence"}])}
    
    - determine_routing:
        switch:
          - condition: ${len(validation_errors) == 0}
            assign:
              - destination_bucket: ${sys.get_env("VALID_BUCKET")}
              - validation_status: "valid"
            next: route_document
          - condition: ${len(validation_errors) > 0 and len(validation_errors) <= 2}
            assign:
              - destination_bucket: ${sys.get_env("REVIEW_BUCKET")}
              - validation_status: "needs_review"
            next: route_document
          - condition: ${len(validation_errors) > 2}
            assign:
              - destination_bucket: ${sys.get_env("INVALID_BUCKET")}
              - validation_status: "invalid"
            next: route_document
    
    - route_document:
        call: googleapis.storage.v1.objects.copy
        args:
          sourceBucket: ${bucket}
          sourceObject: ${name}
          destinationBucket: ${destination_bucket}
          destinationObject: ${name}
    
    - store_analytics:
        call: googleapis.bigquery.v2.tabledata.insertAll
        args:
          projectId: ${project_id}
          datasetId: ${sys.get_env("DATASET_NAME")}
          tableId: "processing_results"
          body:
            rows:
              - json:
                  document_id: ${name}
                  processor_type: ${document_type}
                  processing_time: ${time.now()}
                  validation_status: ${validation_status}
                  confidence_score: ${if(len(extracted_data) > 0, extracted_data[0].confidence, 0.0)}
                  extracted_fields: ${extracted_data}
                  validation_errors: ${validation_errors}
    
    - cleanup_source:
        call: googleapis.storage.v1.objects.delete
        args:
          bucket: ${bucket}
          object: ${name}
    
    - log_completion:
        call: sys.log
        args:
          text: ${"Document processing completed: " + name + " -> " + validation_status}
          severity: INFO
    
    - return_result:
        return:
          status: "success"
          document: ${name}
          validation_status: ${validation_status}
          processor_used: ${document_type}
          validation_errors: ${validation_errors}
EOF
    
    log "✅ Workflow definition created"
}

# Function to deploy Cloud Workflows
deploy_workflow() {
    log "Deploying Cloud Workflows..."
    
    # Load environment variables
    source bucket_names.env
    source processor_ids.env
    source dataset_name.env
    
    export WORKFLOW_NAME="document-validation-workflow"
    
    # Deploy workflow with environment variables
    info "Deploying workflow: ${WORKFLOW_NAME}"
    if gcloud workflows deploy "${WORKFLOW_NAME}" \
        --source=document-validation-workflow.yaml \
        --location="${REGION}" \
        --env-vars="FORM_PROCESSOR_ID=${FORM_PROCESSOR_ID},INVOICE_PROCESSOR_ID=${INVOICE_PROCESSOR_ID},VALID_BUCKET=${VALID_BUCKET},INVALID_BUCKET=${INVALID_BUCKET},REVIEW_BUCKET=${REVIEW_BUCKET},DATASET_NAME=${DATASET_NAME}" \
        --quiet &> /dev/null; then
        log "✅ Cloud Workflows deployed successfully"
    else
        error "Failed to deploy Cloud Workflows"
        exit 1
    fi
    
    # Store workflow name in environment file
    echo "WORKFLOW_NAME=${WORKFLOW_NAME}" > workflow_name.env
}

# Function to create service account and configure IAM
setup_iam() {
    log "Setting up IAM permissions..."
    
    # Create service account for Eventarc
    local sa_name="eventarc-workflows-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    info "Creating service account: ${sa_name}"
    if gcloud iam service-accounts create "${sa_name}" \
        --display-name="Eventarc Workflows Service Account" \
        --project="${PROJECT_ID}" \
        --quiet &> /dev/null; then
        log "✅ Service account created: ${sa_email}"
    else
        warn "Service account may already exist, continuing..."
    fi
    
    # Grant necessary permissions to service account
    local roles=(
        "roles/workflows.invoker"
        "roles/eventarc.eventReceiver"
    )
    
    for role in "${roles[@]}"; do
        info "Granting ${role} to service account..."
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}" \
            --quiet &> /dev/null; then
            log "✅ Role ${role} granted successfully"
        else
            error "Failed to grant role ${role}"
            exit 1
        fi
    done
    
    # Configure permissions for Compute Engine default service account
    local compute_sa="${PROJECT_ID}-compute@developer.gserviceaccount.com"
    
    info "Configuring permissions for Compute Engine service account..."
    local compute_roles=(
        "roles/documentai.apiUser"
        "roles/storage.objectAdmin"
        "roles/bigquery.dataEditor"
        "roles/bigquery.jobUser"
    )
    
    for role in "${compute_roles[@]}"; do
        info "Granting ${role} to Compute Engine service account..."
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${compute_sa}" \
            --role="${role}" \
            --quiet &> /dev/null; then
            log "✅ Role ${role} granted successfully"
        else
            error "Failed to grant role ${role}"
            exit 1
        fi
    done
    
    # Store service account info
    echo "EVENTARC_SA_EMAIL=${sa_email}" > service_account.env
}

# Function to create Eventarc trigger
create_eventarc_trigger() {
    log "Creating Eventarc trigger..."
    
    # Load environment variables
    source bucket_names.env
    source workflow_name.env
    source service_account.env
    
    local trigger_name="document-upload-trigger"
    
    info "Creating Eventarc trigger: ${trigger_name}"
    if gcloud eventarc triggers create "${trigger_name}" \
        --location="${REGION}" \
        --destination-workflow="${WORKFLOW_NAME}" \
        --destination-workflow-location="${REGION}" \
        --event-filters="type=google.cloud.storage.object.v1.finalized" \
        --event-filters="bucket=${INPUT_BUCKET}" \
        --service-account="${EVENTARC_SA_EMAIL}" \
        --quiet &> /dev/null; then
        log "✅ Eventarc trigger created successfully"
    else
        error "Failed to create Eventarc trigger"
        exit 1
    fi
    
    # Store trigger name
    echo "TRIGGER_NAME=${trigger_name}" > trigger_name.env
}

# Function to create sample documents
create_sample_documents() {
    log "Creating sample documents for testing..."
    
    # Load bucket names
    source bucket_names.env
    
    # Create sample invoice document
    cat > sample_invoice.txt << 'EOF'
INVOICE

Date: 2025-01-15
Invoice Number: INV-2025-001
Due Date: 2025-02-15

Bill To:
ABC Corporation
123 Business Street
City, State 12345

Description: Consulting Services
Amount: $2,500.00
Tax: $250.00
Total: $2,750.00

Payment Terms: Net 30 days
EOF
    
    # Create sample form document
    cat > sample_form.txt << 'EOF'
APPLICATION FORM

Name: John Doe
Email: john.doe@example.com
Phone: (555) 123-4567
Address: 456 Main Street, Anytown, ST 67890

Application Type: Business License
Date Submitted: 2025-01-15
Signature: [Digital Signature]
EOF
    
    # Upload sample documents
    info "Uploading sample documents to trigger processing..."
    if gsutil cp sample_invoice.txt "gs://${INPUT_BUCKET}/" &> /dev/null &&
       gsutil cp sample_form.txt "gs://${INPUT_BUCKET}/" &> /dev/null; then
        log "✅ Sample documents uploaded successfully"
    else
        error "Failed to upload sample documents"
        exit 1
    fi
    
    # Clean up local files
    rm -f sample_invoice.txt sample_form.txt
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Load environment variables
    source bucket_names.env
    source processor_ids.env
    source dataset_name.env
    source workflow_name.env
    source trigger_name.env
    
    # Check processors
    info "Checking Document AI processors..."
    if gcloud documentai processors list \
        --location="${REGION}" \
        --format="value(name)" | grep -q "${FORM_PROCESSOR_ID}"; then
        log "✅ Form processor is active"
    else
        error "Form processor not found"
        exit 1
    fi
    
    # Check workflow
    info "Checking Cloud Workflows..."
    if gcloud workflows describe "${WORKFLOW_NAME}" \
        --location="${REGION}" &> /dev/null; then
        log "✅ Workflow is deployed"
    else
        error "Workflow not found"
        exit 1
    fi
    
    # Check BigQuery dataset
    info "Checking BigQuery dataset..."
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "✅ BigQuery dataset is ready"
    else
        error "BigQuery dataset not found"
        exit 1
    fi
    
    # Check buckets
    info "Checking storage buckets..."
    for bucket in "${INPUT_BUCKET}" "${VALID_BUCKET}" "${INVALID_BUCKET}" "${REVIEW_BUCKET}"; do
        if gsutil ls "gs://${bucket}" &> /dev/null; then
            log "✅ Bucket gs://${bucket} is accessible"
        else
            error "Bucket gs://${bucket} not accessible"
            exit 1
        fi
    done
    
    # Check Eventarc trigger
    info "Checking Eventarc trigger..."
    if gcloud eventarc triggers describe "${TRIGGER_NAME}" \
        --location="${REGION}" &> /dev/null; then
        log "✅ Eventarc trigger is active"
    else
        error "Eventarc trigger not found"
        exit 1
    fi
    
    log "✅ All components validated successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================================="
    
    # Load all environment variables
    source bucket_names.env
    source processor_ids.env
    source dataset_name.env
    source workflow_name.env
    source trigger_name.env
    source service_account.env
    
    echo "📊 Resource Summary:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • Region: ${REGION}"
    echo "  • Input Bucket: gs://${INPUT_BUCKET}"
    echo "  • Valid Bucket: gs://${VALID_BUCKET}"
    echo "  • Invalid Bucket: gs://${INVALID_BUCKET}"
    echo "  • Review Bucket: gs://${REVIEW_BUCKET}"
    echo "  • Form Processor: ${FORM_PROCESSOR_ID}"
    echo "  • Invoice Processor: ${INVOICE_PROCESSOR_ID}"
    echo "  • BigQuery Dataset: ${DATASET_NAME}"
    echo "  • Workflow: ${WORKFLOW_NAME}"
    echo "  • Eventarc Trigger: ${TRIGGER_NAME}"
    echo ""
    echo "🔧 Next Steps:"
    echo "  • Upload documents to gs://${INPUT_BUCKET}/ to trigger processing"
    echo "  • Monitor workflow executions in the Google Cloud Console"
    echo "  • Check processing results in BigQuery dataset: ${DATASET_NAME}"
    echo "  • View validated documents in the respective output buckets"
    echo ""
    echo "💰 Cost Monitoring:"
    echo "  • Document AI charges per page processed"
    echo "  • Cloud Storage charges for bucket usage"
    echo "  • Workflow executions have minimal cost"
    echo "  • BigQuery charges for data storage and queries"
    echo ""
    echo "🧹 Cleanup:"
    echo "  • Run the destroy.sh script to remove all resources"
    echo "  • This will prevent ongoing charges"
}

# Main deployment function
main() {
    log "Starting Document Validation Workflows deployment..."
    
    # Check prerequisites
    info "Checking prerequisites..."
    check_command "gcloud"
    check_command "gsutil"
    check_command "bq"
    check_command "openssl"
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
    export REGION="${REGION:-us-central1}"
    
    # Validate environment
    validate_env
    check_auth
    check_project
    
    # Configure gcloud
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Deploy components
    enable_apis
    create_buckets
    create_processors
    create_bigquery_dataset
    create_workflow_definition
    deploy_workflow
    setup_iam
    create_eventarc_trigger
    create_sample_documents
    
    # Wait for everything to propagate
    info "Waiting for resources to propagate..."
    sleep 30
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    log "🎉 Document Validation Workflows deployment completed successfully!"
    log "🔄 Document processing pipeline is now active and ready to use."
}

# Run main function
main "$@"
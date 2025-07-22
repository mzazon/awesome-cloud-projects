#!/bin/bash

# Destroy script for Document Intelligence Workflows with Agentspace and Sensitive Data Protection
# This script safely removes all infrastructure created by the deployment script

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI is not installed. Cannot proceed with cleanup."
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
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables from .env file
load_environment() {
    log "Loading environment variables..."
    
    # Set default values
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    
    # Try to load from .env file if it exists
    if [[ -f ".env" ]]; then
        log "Loading configuration from .env file..."
        source .env
        log_success "Configuration loaded from .env file"
    else
        log_warning "No .env file found. Will attempt to discover resources automatically."
    fi
    
    log "Using Project ID: $PROJECT_ID"
    log "Using Region: $REGION"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This script will permanently delete ALL resources created by the Document Intelligence Workflows deployment."
    log_warning "This includes:"
    echo "  - Cloud Storage buckets and all their contents"
    echo "  - Document AI processors"
    echo "  - DLP templates"
    echo "  - Cloud Workflows"
    echo "  - BigQuery datasets and tables"
    echo "  - IAM service accounts and bindings"
    echo "  - Monitoring resources and log sinks"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup in 5 seconds..."
    sleep 5
}

# Function to discover resources if not found in environment
discover_resources() {
    log "Discovering Document Intelligence Workflows resources..."
    
    # Discover Cloud Storage buckets if not set
    if [[ -z "${INPUT_BUCKET:-}" ]] || [[ -z "${OUTPUT_BUCKET:-}" ]] || [[ -z "${AUDIT_BUCKET:-}" ]]; then
        log "Discovering Cloud Storage buckets..."
        
        # Find buckets with our naming pattern
        local buckets=$(gsutil ls -p "$PROJECT_ID" | grep -E "(doc-input-|doc-output-|doc-audit-)" | sed 's/gs:\/\///' | sed 's/\///' || true)
        
        for bucket in $buckets; do
            if [[ "$bucket" =~ doc-input- ]]; then
                export INPUT_BUCKET="$bucket"
                log "Found input bucket: gs://$bucket"
            elif [[ "$bucket" =~ doc-output- ]]; then
                export OUTPUT_BUCKET="$bucket"
                log "Found output bucket: gs://$bucket"
            elif [[ "$bucket" =~ doc-audit- ]]; then
                export AUDIT_BUCKET="$bucket"
                log "Found audit bucket: gs://$bucket"
            fi
        done
    fi
    
    # Discover Document AI processors if not set
    if [[ -z "${PROCESSOR_ID:-}" ]]; then
        log "Discovering Document AI processors..."
        
        local processors=$(gcloud documentai processors list \
            --location="$REGION" \
            --filter="displayName~enterprise-doc-processor-" \
            --format="value(name)" 2>/dev/null || true)
        
        for processor in $processors; do
            export PROCESSOR_ID=$(echo "$processor" | cut -d'/' -f6)
            export PROCESSOR_NAME="$processor"
            log "Found Document AI processor: $processor"
            break # Take the first one found
        done
    fi
    
    # Discover DLP templates if not set
    if [[ -z "${DLP_TEMPLATE_ID:-}" ]]; then
        log "Discovering DLP inspection templates..."
        
        local templates=$(gcloud dlp inspect-templates list \
            --filter="displayName~Enterprise Document PII Scanner" \
            --format="value(name)" 2>/dev/null || true)
        
        for template in $templates; do
            export DLP_TEMPLATE_ID=$(echo "$template" | cut -d'/' -f4)
            log "Found DLP inspection template: $template"
            break
        done
    fi
    
    if [[ -z "${DEIDENTIFY_TEMPLATE_ID:-}" ]]; then
        log "Discovering DLP de-identification templates..."
        
        local templates=$(gcloud dlp deidentify-templates list \
            --filter="displayName~Enterprise Document Redaction" \
            --format="value(name)" 2>/dev/null || true)
        
        for template in $templates; do
            export DEIDENTIFY_TEMPLATE_ID=$(echo "$template" | cut -d'/' -f4)
            log "Found DLP de-identification template: $template"
            break
        done
    fi
    
    # Discover Cloud Workflows if not set
    if [[ -z "${WORKFLOW_NAME:-}" ]]; then
        log "Discovering Cloud Workflows..."
        
        local workflows=$(gcloud workflows list \
            --location="$REGION" \
            --filter="name~doc-intelligence-workflow-" \
            --format="value(name)" 2>/dev/null || true)
        
        for workflow in $workflows; do
            export WORKFLOW_NAME=$(basename "$workflow")
            log "Found Cloud Workflow: $workflow"
            break
        done
    fi
    
    log_success "Resource discovery completed"
}

# Function to remove Cloud Workflows
remove_workflows() {
    log "Removing Cloud Workflows..."
    
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        # List and cancel any running executions first
        log "Checking for running workflow executions..."
        local executions=$(gcloud workflows executions list \
            --workflow="$WORKFLOW_NAME" \
            --location="$REGION" \
            --filter="state=ACTIVE" \
            --format="value(name)" 2>/dev/null || true)
        
        for execution in $executions; do
            log "Cancelling execution: $execution"
            gcloud workflows executions cancel "$execution" \
                --workflow="$WORKFLOW_NAME" \
                --location="$REGION" --quiet || true
        done
        
        # Wait a moment for executions to cancel
        if [[ -n "$executions" ]]; then
            log "Waiting for executions to cancel..."
            sleep 10
        fi
        
        # Delete the workflow
        if gcloud workflows delete "$WORKFLOW_NAME" \
            --location="$REGION" \
            --quiet; then
            log_success "Deleted Cloud Workflow: $WORKFLOW_NAME"
        else
            log_warning "Failed to delete Cloud Workflow or it may not exist"
        fi
    else
        log_warning "No Cloud Workflow found to delete"
    fi
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    log "Removing BigQuery datasets and tables..."
    
    # Check if dataset exists
    if bq ls -d "$PROJECT_ID:document_intelligence" >/dev/null 2>&1; then
        log "Deleting BigQuery dataset: document_intelligence"
        
        # Delete the entire dataset (including all tables and views)
        if bq rm -r -f "$PROJECT_ID:document_intelligence"; then
            log_success "Deleted BigQuery dataset: document_intelligence"
        else
            log_error "Failed to delete BigQuery dataset"
        fi
    else
        log_warning "BigQuery dataset 'document_intelligence' not found"
    fi
}

# Function to remove DLP templates
remove_dlp_templates() {
    log "Removing DLP templates..."
    
    # Remove DLP inspection template
    if [[ -n "${DLP_TEMPLATE_ID:-}" ]]; then
        if gcloud dlp inspect-templates delete "$DLP_TEMPLATE_ID" --quiet; then
            log_success "Deleted DLP inspection template: $DLP_TEMPLATE_ID"
        else
            log_warning "Failed to delete DLP inspection template or it may not exist"
        fi
    else
        log_warning "No DLP inspection template ID found"
    fi
    
    # Remove DLP de-identification template
    if [[ -n "${DEIDENTIFY_TEMPLATE_ID:-}" ]]; then
        if gcloud dlp deidentify-templates delete "$DEIDENTIFY_TEMPLATE_ID" --quiet; then
            log_success "Deleted DLP de-identification template: $DEIDENTIFY_TEMPLATE_ID"
        else
            log_warning "Failed to delete DLP de-identification template or it may not exist"
        fi
    else
        log_warning "No DLP de-identification template ID found"
    fi
}

# Function to remove Document AI processor
remove_document_ai_processor() {
    log "Removing Document AI processor..."
    
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        if gcloud documentai processors delete "$PROCESSOR_ID" \
            --location="$REGION" \
            --quiet; then
            log_success "Deleted Document AI processor: $PROCESSOR_ID"
        else
            log_warning "Failed to delete Document AI processor or it may not exist"
        fi
    else
        log_warning "No Document AI processor ID found"
    fi
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log "Removing monitoring and logging resources..."
    
    # Remove log sink
    if gcloud logging sinks describe doc-intelligence-audit-sink >/dev/null 2>&1; then
        if gcloud logging sinks delete doc-intelligence-audit-sink --quiet; then
            log_success "Deleted audit log sink"
        else
            log_warning "Failed to delete audit log sink"
        fi
    else
        log_warning "Audit log sink not found"
    fi
    
    # Remove custom metrics
    local metrics=("document_processing_volume" "sensitive_data_detections")
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "$metric" >/dev/null 2>&1; then
            if gcloud logging metrics delete "$metric" --quiet; then
                log_success "Deleted custom metric: $metric"
            else
                log_warning "Failed to delete custom metric: $metric"
            fi
        else
            log_warning "Custom metric '$metric' not found"
        fi
    done
    
    # Remove alerting policies (if any exist)
    local policies=$(gcloud alpha monitoring policies list \
        --filter="displayName~'High-Risk Document Processing Alert'" \
        --format="value(name)" 2>/dev/null || true)
    
    for policy in $policies; do
        if gcloud alpha monitoring policies delete "$policy" --quiet; then
            log_success "Deleted alerting policy: $policy"
        else
            log_warning "Failed to delete alerting policy: $policy"
        fi
    done
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM service accounts and bindings..."
    
    local service_account="agentspace-doc-processor@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$service_account" >/dev/null 2>&1; then
        log "Removing IAM policy bindings for service account..."
        
        # Remove project-level IAM bindings
        local roles=(
            "roles/documentai.apiUser"
            "roles/dlp.user"
            "roles/workflows.invoker"
            "roles/storage.objectAdmin"
            "roles/bigquery.dataEditor"
        )
        
        for role in "${roles[@]}"; do
            if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$service_account" \
                --role="$role" --quiet 2>/dev/null; then
                log_success "Removed IAM binding: $role"
            else
                log_warning "Failed to remove IAM binding: $role (may not exist)"
            fi
        done
        
        # Delete the service account
        if gcloud iam service-accounts delete "$service_account" --quiet; then
            log_success "Deleted service account: $service_account"
        else
            log_warning "Failed to delete service account"
        fi
    else
        log_warning "Service account not found: $service_account"
    fi
}

# Function to remove Cloud Storage buckets
remove_storage_buckets() {
    log "Removing Cloud Storage buckets and all contents..."
    
    local buckets=("${INPUT_BUCKET:-}" "${OUTPUT_BUCKET:-}" "${AUDIT_BUCKET:-}")
    
    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            log "Checking bucket: gs://$bucket"
            
            # Check if bucket exists
            if gsutil ls "gs://$bucket" >/dev/null 2>&1; then
                log "Removing all objects from bucket: gs://$bucket"
                
                # Remove all objects including versions
                if gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || true; then
                    log "Removed all objects from bucket"
                fi
                
                # Remove the bucket itself
                if gsutil rb "gs://$bucket"; then
                    log_success "Deleted bucket: gs://$bucket"
                else
                    log_error "Failed to delete bucket: gs://$bucket"
                fi
            else
                log_warning "Bucket not found: gs://$bucket"
            fi
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files=(".env" "deployment-summary.txt" "sample-document.txt" 
                "agentspace-config.json" "dlp-template.json" "dlp-deidentify-template.json"
                "document-processing-workflow.yaml" "agentspace-integration.yaml"
                "monitoring-config.yaml" "alerting-policy.json")
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed local file: $file"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check for remaining buckets
    local remaining_buckets=$(gsutil ls -p "$PROJECT_ID" | grep -E "(doc-input-|doc-output-|doc-audit-)" | wc -l || echo "0")
    if [[ "$remaining_buckets" -gt 0 ]]; then
        log_warning "$remaining_buckets document processing buckets still exist"
        cleanup_complete=false
    fi
    
    # Check for remaining Document AI processors
    local remaining_processors=$(gcloud documentai processors list \
        --location="$REGION" \
        --filter="displayName~enterprise-doc-processor-" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_processors" -gt 0 ]]; then
        log_warning "$remaining_processors Document AI processors still exist"
        cleanup_complete=false
    fi
    
    # Check for remaining workflows
    local remaining_workflows=$(gcloud workflows list \
        --location="$REGION" \
        --filter="name~doc-intelligence-workflow-" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_workflows" -gt 0 ]]; then
        log_warning "$remaining_workflows Cloud Workflows still exist"
        cleanup_complete=false
    fi
    
    # Check BigQuery dataset
    if bq ls -d "$PROJECT_ID:document_intelligence" >/dev/null 2>&1; then
        log_warning "BigQuery dataset 'document_intelligence' still exists"
        cleanup_complete=false
    fi
    
    if [[ "$cleanup_complete" == true ]]; then
        log_success "Cleanup verification completed successfully"
        log_success "All Document Intelligence Workflows resources have been removed"
    else
        log_warning "Some resources may still exist. Please review the warnings above."
        log_warning "You may need to manually remove remaining resources."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Cleanup Time: $(date)"
    echo ""
    echo "Resources Removed:"
    echo "- Cloud Storage buckets (input, output, audit)"
    echo "- Document AI processors"
    echo "- DLP templates (inspection and de-identification)"
    echo "- Cloud Workflows"
    echo "- BigQuery datasets and tables"
    echo "- IAM service accounts and policy bindings"
    echo "- Monitoring resources and log sinks"
    echo "- Local configuration files"
    echo ""
    log_success "Document Intelligence Workflows cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Document Intelligence Workflows cleanup..."
    log "This will remove ALL resources created by the deployment script."
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    discover_resources
    
    log "Beginning resource cleanup..."
    
    # Remove resources in reverse order of creation
    remove_workflows
    remove_bigquery_resources
    remove_dlp_templates
    remove_document_ai_processor
    remove_monitoring_resources
    remove_iam_resources
    remove_storage_buckets
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    display_cleanup_summary
}

# Run main function
main "$@"
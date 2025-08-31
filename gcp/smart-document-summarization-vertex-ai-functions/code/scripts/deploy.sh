#!/bin/bash
# =============================================================================
# Smart Document Summarization with Vertex AI and Cloud Functions - Deploy Script
# =============================================================================
# This script deploys the complete document summarization infrastructure on GCP
# including Cloud Storage, Cloud Functions, Vertex AI integration, and IAM setup.
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID    Use specific project ID (optional)
#   --region REGION           Use specific region (default: us-central1)
#   --function-name NAME      Use specific function name (default: summarize-document)
#   --dry-run                 Show what would be deployed without executing
#   --help                    Show this help message
#
# Prerequisites:
# - gcloud CLI installed and configured
# - Billing enabled on GCP project
# - Sufficient quotas for Vertex AI and Cloud Functions
# =============================================================================

set -euo pipefail

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_FUNCTION_NAME="summarize-document"
readonly REQUIRED_APIS=(
    "cloudfunctions.googleapis.com"
    "storage.googleapis.com"
    "aiplatform.googleapis.com"
    "cloudbuild.googleapis.com"
    "eventarc.googleapis.com"
)

# Global variables
PROJECT_ID=""
REGION="$DEFAULT_REGION"
FUNCTION_NAME="$DEFAULT_FUNCTION_NAME"
BUCKET_NAME=""
DRY_RUN=false
CLEANUP_ON_ERROR=true

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" >&2
}

# Error handling
cleanup_on_error() {
    if [[ "$CLEANUP_ON_ERROR" == "true" && -n "$BUCKET_NAME" ]]; then
        log_warn "Deployment failed. Cleaning up partial resources..."
        
        # Remove bucket if it was created
        if gsutil ls -b gs://"$BUCKET_NAME" &>/dev/null; then
            log_info "Removing bucket: gs://$BUCKET_NAME"
            gsutil -m rm -r gs://"$BUCKET_NAME" 2>/dev/null || true
        fi
        
        # Remove function if it was created
        if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 &>/dev/null; then
            log_info "Removing function: $FUNCTION_NAME"
            gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --gen2 --quiet || true
        fi
    fi
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Smart Document Summarization Deployment Script

This script deploys a complete document summarization solution using:
- Cloud Storage for document ingestion
- Cloud Functions for serverless processing
- Vertex AI Gemini for intelligent summarization
- Proper IAM configuration for secure operations

Usage: $0 [OPTIONS]

Options:
  --project-id PROJECT_ID    Use specific project ID (required)
  --region REGION           Use specific region (default: $DEFAULT_REGION)
  --function-name NAME      Use specific function name (default: $DEFAULT_FUNCTION_NAME)
  --dry-run                 Show what would be deployed without executing
  --help                    Show this help message

Examples:
  $0 --project-id my-gcp-project
  $0 --project-id my-project --region us-west1
  $0 --project-id my-project --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
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

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id option."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible."
        exit 1
    fi
    
    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        log_error "Billing is not enabled for project '$PROJECT_ID'. Please enable billing first."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Set project configuration
configure_project() {
    log_info "Configuring gcloud project settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set project: $PROJECT_ID"
        log_info "[DRY-RUN] Would set region: $REGION"
        return
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return
    fi
    
    local apis_to_enable=()
    
    # Check which APIs need to be enabled
    for api in "${REQUIRED_APIS[@]}"; do
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            apis_to_enable+=("$api")
        fi
    done
    
    if [[ ${#apis_to_enable[@]} -gt 0 ]]; then
        log_info "Enabling APIs: ${apis_to_enable[*]}"
        gcloud services enable "${apis_to_enable[@]}"
        
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    else
        log_info "All required APIs are already enabled"
    fi
    
    log_success "API enablement completed"
}

# Generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    BUCKET_NAME="doc-summarizer-${random_suffix}"
    
    log_info "Generated bucket name: $BUCKET_NAME"
    log_info "Function name: $FUNCTION_NAME"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create bucket: gs://$BUCKET_NAME"
        log_info "[DRY-RUN] Would enable versioning and create test file"
        return
    fi
    
    # Create bucket with appropriate settings
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        gs://"$BUCKET_NAME"
    
    # Enable versioning for document protection
    gsutil versioning set on gs://"$BUCKET_NAME"
    
    # Create initial test file
    echo "Processing pipeline ready - $(date)" | \
        gsutil cp - gs://"$BUCKET_NAME"/ready.txt
    
    log_success "Cloud Storage bucket created: gs://$BUCKET_NAME"
}

# Prepare Cloud Function source code
prepare_function_code() {
    log_info "Preparing Cloud Function source code..."
    
    local function_dir="$PROJECT_DIR/function-source"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would prepare function code in: $function_dir"
        return
    fi
    
    # Create function directory if it doesn't exist
    mkdir -p "$function_dir"
    
    # Copy function source files from terraform directory
    local terraform_function_dir="$PROJECT_DIR/terraform/function-source"
    if [[ -d "$terraform_function_dir" ]]; then
        cp "$terraform_function_dir"/* "$function_dir"/
        log_info "Copied function source files from terraform directory"
    else
        log_error "Function source files not found at: $terraform_function_dir"
        exit 1
    fi
    
    log_success "Function source code prepared"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function..."
    
    local function_dir="$PROJECT_DIR/function-source"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy function: $FUNCTION_NAME"
        log_info "[DRY-RUN] Would use bucket trigger: $BUCKET_NAME"
        return
    fi
    
    # Change to function directory
    pushd "$function_dir" > /dev/null
    
    # Deploy function with Cloud Storage trigger
    gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime python311 \
        --source . \
        --entry-point summarize_document \
        --trigger-bucket "$BUCKET_NAME" \
        --memory 1Gi \
        --timeout 540s \
        --max-instances 10 \
        --set-env-vars "GCP_PROJECT=$PROJECT_ID"
    
    popd > /dev/null
    
    log_success "Cloud Function deployed: $FUNCTION_NAME"
    log_info "Function will process files uploaded to: gs://$BUCKET_NAME"
}

# Configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions for Vertex AI access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure IAM permissions for function service account"
        return
    fi
    
    # Get the Cloud Function service account
    local function_sa
    function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --format="value(serviceConfig.serviceAccountEmail)")
    
    if [[ -z "$function_sa" ]]; then
        log_error "Failed to retrieve function service account"
        exit 1
    fi
    
    log_info "Function service account: $function_sa"
    
    # Grant Vertex AI User role for model access
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$function_sa" \
        --role="roles/aiplatform.user"
    
    # Grant additional storage permissions
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$function_sa" \
        --role="roles/storage.objectAdmin"
    
    log_success "IAM permissions configured"
    log_info "Service account: $function_sa"
}

# Create sample documents for testing
create_sample_documents() {
    log_info "Creating sample documents for testing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create sample documents and upload to bucket"
        return
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create sample business report
    cat > "$temp_dir/sample_report.txt" << 'EOF'
QUARTERLY BUSINESS REPORT - Q4 2024

Executive Summary:
This report presents the financial and operational performance for Q4 2024. 
Revenue increased by 15% compared to Q3, reaching $2.4 million. Key achievements 
include successful product launch, expansion into new markets, and improved 
customer satisfaction scores.

Financial Highlights:
- Total Revenue: $2,400,000 (15% increase)
- Net Profit: $360,000 (18% increase) 
- Operating Expenses: $1,890,000
- Customer Acquisition Cost: $120 (down from $145)

Strategic Initiatives:
1. Launched AI-powered customer service platform
2. Expanded operations to European markets
3. Implemented new data analytics infrastructure
4. Achieved ISO 27001 security certification

Market Analysis:
The competitive landscape shows continued growth opportunities in emerging 
markets. Customer feedback indicates strong satisfaction with new product 
features, particularly the mobile application updates released in November.

Recommendations:
- Increase marketing spend in European markets by 25%
- Hire additional technical support staff
- Invest in advanced analytics capabilities
- Continue focus on customer experience improvements
EOF
    
    # Create sample API documentation
    cat > "$temp_dir/api_documentation.txt" << 'EOF'
API INTEGRATION GUIDE - Version 2.1

Overview:
This document provides comprehensive guidance for integrating with our REST API.
The API supports authentication via OAuth 2.0 and returns data in JSON format.
Rate limiting is set to 1000 requests per hour for standard accounts.

Authentication:
All API requests require a valid access token obtained through OAuth 2.0 flow.
Token expiration is set to 24 hours. Refresh tokens are valid for 30 days.

Endpoints:
- GET /api/v2/users - Retrieve user information
- POST /api/v2/documents - Upload new documents
- GET /api/v2/documents/{id} - Retrieve specific document
- PUT /api/v2/documents/{id} - Update document metadata
- DELETE /api/v2/documents/{id} - Remove document

Error Handling:
The API returns standard HTTP status codes. Error responses include detailed 
error messages and suggested remediation steps. Common errors include 401 
(unauthorized), 403 (forbidden), 404 (not found), and 429 (rate limited).

Best Practices:
- Implement exponential backoff for retry logic
- Cache authentication tokens appropriately
- Use pagination for large result sets
- Monitor API usage to stay within rate limits
EOF
    
    # Upload sample documents to trigger processing
    gsutil cp "$temp_dir/sample_report.txt" gs://"$BUCKET_NAME"/
    gsutil cp "$temp_dir/api_documentation.txt" gs://"$BUCKET_NAME"/
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log_success "Sample documents created and uploaded"
    log_info "Documents uploaded to: gs://$BUCKET_NAME"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would verify bucket, function, and permissions"
        return
    fi
    
    # Check bucket exists
    if ! gsutil ls -b gs://"$BUCKET_NAME" &>/dev/null; then
        log_error "Bucket verification failed: gs://$BUCKET_NAME"
        exit 1
    fi
    
    # Check function exists and is active
    local function_state
    function_state=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --format="value(state)" 2>/dev/null || echo "")
    
    if [[ "$function_state" != "ACTIVE" ]]; then
        log_error "Function verification failed. State: $function_state"
        exit 1
    fi
    
    # Wait for processing to complete and check for summaries
    log_info "Waiting for document processing to complete (60 seconds)..."
    sleep 60
    
    # Check if summaries were generated
    local summary_count
    summary_count=$(gsutil ls gs://"$BUCKET_NAME"/*_summary.txt 2>/dev/null | wc -l || echo "0")
    
    if [[ "$summary_count" -gt 0 ]]; then
        log_success "Document summarization is working! Found $summary_count summaries"
        
        # Show summary files
        log_info "Generated summaries:"
        gsutil ls gs://"$BUCKET_NAME"/*_summary.txt
    else
        log_warn "No summaries found yet. Check function logs:"
        gcloud functions logs read "$FUNCTION_NAME" \
            --region="$REGION" \
            --gen2 \
            --limit=10
    fi
    
    log_success "Deployment verification completed"
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo ""
    echo "Next Steps:"
    echo "1. Upload documents to: gs://$BUCKET_NAME"
    echo "2. View summaries with: gsutil ls gs://$BUCKET_NAME/*_summary.txt"
    echo "3. Monitor function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION --gen2"
    echo "4. Clean up resources: ./destroy.sh --project-id $PROJECT_ID --bucket-name $BUCKET_NAME"
    echo ""
    echo "Estimated monthly cost: \$5-15 (varies by usage)"
}

# Main execution function
main() {
    log_info "Starting Smart Document Summarization deployment"
    
    parse_args "$@"
    validate_prerequisites
    configure_project
    enable_apis
    generate_resource_names
    create_storage_bucket
    prepare_function_code
    deploy_cloud_function
    configure_iam_permissions
    create_sample_documents
    verify_deployment
    
    # Disable cleanup on error since deployment succeeded
    CLEANUP_ON_ERROR=false
    
    log_success "Deployment completed successfully!"
    show_deployment_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
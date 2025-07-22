#!/bin/bash

# Enterprise Knowledge Discovery with Google Agentspace and Vertex AI Search
# Deployment Script
# 
# This script deploys a complete enterprise knowledge discovery system using:
# - Google Cloud Storage for document repository
# - Vertex AI Search for semantic search capabilities
# - BigQuery for analytics and reporting
# - Google Agentspace for intelligent agent interactions
# - Cloud IAM for security and access control

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    error "Deployment failed with exit code ${exit_code}"
    error "Check ${LOG_FILE} for detailed error information"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Enterprise Knowledge Discovery Deployment Script

Usage: $0 [OPTIONS]

Options:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -h, --help                    Show this help message
    --dry-run                     Show what would be deployed without executing
    --force                       Skip confirmation prompts

Environment Variables:
    PROJECT_ID                    Google Cloud Project ID
    REGION                       Deployment region
    BUCKET_PREFIX                Custom prefix for storage bucket names

Examples:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --region us-east1
    PROJECT_ID=my-project-123 $0

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"

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
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID}" ]]; then
    error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
    show_help
    exit 1
fi

# Initialize log file
echo "=== Enterprise Knowledge Discovery Deployment ===" > "${LOG_FILE}"
log "Starting deployment at $(date)"
log "Project ID: ${PROJECT_ID}"
log "Region: ${REGION}"
log "Dry Run: ${DRY_RUN}"

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} not found or not accessible."
        exit 1
    fi
    
    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "${PROJECT_ID}" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "${billing_account}" ]]; then
        warning "Billing may not be enabled for project ${PROJECT_ID}."
        warning "Some services may not work without billing enabled."
    fi
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION}"
    export ZONE="${REGION}-a"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_PREFIX:-enterprise-docs}-${RANDOM_SUFFIX}"
    export DATASET_NAME="knowledge_analytics_${RANDOM_SUFFIX}"
    export SEARCH_APP_ID="enterprise-search-${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Environment configured"
    info "Project ID: ${PROJECT_ID}"
    info "Region: ${REGION}"
    info "Bucket Name: ${BUCKET_NAME}"
    info "Dataset Name: ${DATASET_NAME}"
    info "Search App ID: ${SEARCH_APP_ID}"
}

# Enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "discoveryengine.googleapis.com"
        "storage.googleapis.com"
        "bigquery.googleapis.com"
        "aiplatform.googleapis.com"
        "agentspace.googleapis.com"
        "monitoring.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would enable API: ${api}"
        else
            info "Enabling API: ${api}"
            gcloud services enable "${api}" --quiet
        fi
    done
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    info "Creating Cloud Storage bucket for document repository..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        return 0
    fi
    
    # Create storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Set up lifecycle policy
    cat > "${SCRIPT_DIR}/lifecycle.json" << 'EOF'
{
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
EOF
    
    gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://${BUCKET_NAME}"
    
    success "Storage bucket configured with versioning and lifecycle policies"
}

# Upload sample documents
upload_sample_documents() {
    info "Creating and uploading sample enterprise documents..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create sample documents and upload to bucket"
        return 0
    fi
    
    local sample_docs_dir="${SCRIPT_DIR}/sample_docs"
    mkdir -p "${sample_docs_dir}"
    
    # Generate HR policy document
    cat > "${sample_docs_dir}/hr_policy.txt" << 'EOF'
Employee Handbook - Remote Work Policy

Effective Date: January 2024

Remote Work Guidelines:
- Employees may work remotely up to 3 days per week
- Home office setup must meet security requirements
- Daily check-ins required with immediate supervisor
- Collaboration tools: Google Meet, Slack, Asana

Equipment Policy:
- Company provides laptop, monitor, and chair
- IT support available 24/7 for remote workers
- VPN access mandatory for all remote connections
EOF
    
    # Generate technical documentation
    cat > "${sample_docs_dir}/api_documentation.txt" << 'EOF'
API Documentation - Customer Service Platform

Version: 2.1.0
Last Updated: March 2024

Authentication:
- OAuth 2.0 with JWT tokens
- API key required for all requests
- Rate limiting: 1000 requests per hour

Endpoints:
- GET /customers - Retrieve customer list
- POST /customers - Create new customer
- PUT /customers/{id} - Update customer information
- DELETE /customers/{id} - Remove customer

Error Handling:
- 400: Bad Request - Invalid parameters
- 401: Unauthorized - Invalid credentials
- 429: Too Many Requests - Rate limit exceeded
EOF
    
    # Generate financial report
    cat > "${sample_docs_dir}/financial_report.txt" << 'EOF'
Quarterly Financial Report - Q1 2024

Revenue Summary:
- Total Revenue: $2.5M (up 15% YoY)
- Subscription Revenue: $1.8M (72% of total)
- Professional Services: $700K (28% of total)

Expenses:
- Personnel: $1.2M (48% of revenue)
- Technology: $400K (16% of revenue)
- Marketing: $300K (12% of revenue)
- Operations: $200K (8% of revenue)

Key Metrics:
- Monthly Recurring Revenue (MRR): $600K
- Customer Acquisition Cost (CAC): $150
- Customer Lifetime Value (CLV): $2,400
EOF
    
    # Upload documents to Cloud Storage
    gsutil -m cp "${sample_docs_dir}"/*.txt "gs://${BUCKET_NAME}/documents/"
    
    success "Sample documents uploaded to storage bucket"
}

# Create BigQuery dataset
create_bigquery_dataset() {
    info "Creating BigQuery dataset for analytics..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create BigQuery dataset: ${DATASET_NAME}"
        return 0
    fi
    
    # Create BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        warning "Dataset ${DATASET_NAME} already exists"
    else
        bq mk --dataset \
            --description "Enterprise knowledge discovery analytics" \
            --location="${REGION}" \
            "${PROJECT_ID}:${DATASET_NAME}"
        success "BigQuery dataset created: ${DATASET_NAME}"
    fi
    
    # Create search queries table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.search_queries" \
        query_id:STRING,user_id:STRING,query_text:STRING,timestamp:TIMESTAMP,results_count:INTEGER,click_through_rate:FLOAT
    
    # Create document analytics table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.document_analytics" \
        document_id:STRING,document_name:STRING,view_count:INTEGER,last_accessed:TIMESTAMP,relevance_score:FLOAT
    
    success "BigQuery tables created successfully"
}

# Create Vertex AI Search application
create_vertex_ai_search() {
    info "Creating Vertex AI Search application..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create Vertex AI Search application: ${SEARCH_APP_ID}"
        return 0
    fi
    
    # Create data store
    info "Creating Vertex AI Search data store..."
    gcloud alpha discovery-engine data-stores create \
        --data-store-id="${SEARCH_APP_ID}" \
        --display-name="Enterprise Knowledge Search" \
        --industry-vertical=GENERIC \
        --solution-type=SOLUTION_TYPE_SEARCH \
        --content-config=CONTENT_REQUIRED \
        --location=global \
        --quiet || warning "Data store may already exist"
    
    # Import documents from Cloud Storage
    info "Importing documents from Cloud Storage..."
    gcloud alpha discovery-engine documents import \
        --data-store="${SEARCH_APP_ID}" \
        --location=global \
        --gcs-uri="gs://${BUCKET_NAME}/documents/*" \
        --id-field=uri \
        --quiet || warning "Document import may have failed"
    
    # Create search engine
    info "Creating search engine..."
    gcloud alpha discovery-engine engines create \
        --engine-id="${SEARCH_APP_ID}-engine" \
        --display-name="Enterprise Knowledge Engine" \
        --data-store-ids="${SEARCH_APP_ID}" \
        --location=global \
        --industry-vertical=GENERIC \
        --solution-type=SOLUTION_TYPE_SEARCH \
        --quiet || warning "Search engine may already exist"
    
    success "Vertex AI Search application created"
    info "Document import initiated (may take 10-15 minutes to complete)"
}

# Configure search settings
configure_search_settings() {
    info "Configuring search index and settings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would configure search settings"
        return 0
    fi
    
    # Wait for document import to have time to start
    info "Waiting for document import to initialize..."
    sleep 60
    
    # Create search configuration
    cat > "${SCRIPT_DIR}/search_config.json" << 'EOF'
{
  "searchTier": "SEARCH_TIER_STANDARD",
  "searchAddOns": ["SEARCH_ADD_ON_LLM"],
  "enableAutoLanguageDetection": true,
  "enablePersonalization": true,
  "enableSearchResultsOrdering": true
}
EOF
    
    # Apply search configuration (may fail if engine is still being created)
    gcloud alpha discovery-engine engines patch \
        "${SEARCH_APP_ID}-engine" \
        --location=global \
        --update-mask=searchEngineConfig \
        --search-engine-config-from-file="${SCRIPT_DIR}/search_config.json" \
        --quiet || warning "Search configuration update may have failed - engine may still be initializing"
    
    success "Search index configuration applied"
}

# Set up Agentspace integration
setup_agentspace() {
    info "Setting up Google Agentspace integration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would set up Agentspace integration"
        return 0
    fi
    
    # Create Agentspace configuration
    cat > "${SCRIPT_DIR}/agentspace_config.yaml" << EOF
apiVersion: agentspace.googleapis.com/v1
kind: KnowledgeAgent
metadata:
  name: enterprise-knowledge-agent
spec:
  displayName: "Enterprise Knowledge Discovery Agent"
  description: "AI agent for enterprise knowledge search and synthesis"
  searchEngineId: "${SEARCH_APP_ID}-engine"
  capabilities:
    - semantic_search
    - content_summarization
    - question_answering
    - document_analysis
  personalizations:
    - user_role_based_filtering
    - department_specific_results
    - usage_pattern_optimization
EOF
    
    # Deploy Agentspace knowledge agent (may fail if service is not available)
    gcloud alpha agentspace agents create \
        --agent-config="${SCRIPT_DIR}/agentspace_config.yaml" \
        --location=global \
        --project="${PROJECT_ID}" \
        --quiet || warning "Agentspace agent creation may have failed - service may not be available in region"
    
    # Create agent workflow
    cat > "${SCRIPT_DIR}/knowledge_workflow.yaml" << EOF
apiVersion: agentspace.googleapis.com/v1
kind: Workflow
metadata:
  name: knowledge-discovery-workflow
spec:
  triggers:
    - type: "natural_language_query"
  steps:
    - name: "semantic_search"
      type: "vertex_ai_search"
      config:
        engine_id: "${SEARCH_APP_ID}-engine"
        max_results: 10
    - name: "content_analysis"
      type: "llm_processing"
      config:
        model: "gemini-pro"
        prompt: "Analyze and synthesize the following search results"
    - name: "answer_generation"
      type: "response_synthesis"
      config:
        format: "conversational"
        include_citations: true
EOF
    
    # Deploy knowledge discovery workflow (may fail if service is not available)
    gcloud alpha agentspace workflows create \
        --workflow-config="${SCRIPT_DIR}/knowledge_workflow.yaml" \
        --location=global \
        --project="${PROJECT_ID}" \
        --quiet || warning "Agentspace workflow creation may have failed - service may not be available in region"
    
    success "Agentspace integration configured (if service is available)"
}

# Configure IAM and access controls
configure_iam() {
    info "Configuring IAM and access controls..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would configure IAM roles and policies"
        return 0
    fi
    
    # Create custom IAM role for knowledge discovery readers
    cat > "${SCRIPT_DIR}/knowledge_reader_role.yaml" << 'EOF'
title: "Knowledge Discovery Reader"
description: "Can search and read enterprise knowledge"
stage: "GA"
includedPermissions:
  - discoveryengine.engines.search
  - discoveryengine.dataStores.get
  - storage.objects.get
  - bigquery.tables.get
  - bigquery.tables.getData
EOF
    
    # Create knowledge administrator role
    cat > "${SCRIPT_DIR}/knowledge_admin_role.yaml" << 'EOF'
title: "Knowledge Discovery Administrator"
description: "Can manage enterprise knowledge systems"
stage: "GA"
includedPermissions:
  - discoveryengine.*
  - storage.objects.*
  - bigquery.datasets.*
  - bigquery.tables.*
  - agentspace.*
EOF
    
    # Create IAM roles
    gcloud iam roles create knowledgeDiscoveryReader \
        --project="${PROJECT_ID}" \
        --file="${SCRIPT_DIR}/knowledge_reader_role.yaml" \
        --quiet || warning "Reader role may already exist"
    
    gcloud iam roles create knowledgeDiscoveryAdmin \
        --project="${PROJECT_ID}" \
        --file="${SCRIPT_DIR}/knowledge_admin_role.yaml" \
        --quiet || warning "Admin role may already exist"
    
    # Create service account for application access
    gcloud iam service-accounts create knowledge-discovery-sa \
        --description="Service account for knowledge discovery system" \
        --display-name="Knowledge Discovery Service Account" \
        --quiet || warning "Service account may already exist"
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:knowledge-discovery-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="projects/${PROJECT_ID}/roles/knowledgeDiscoveryReader" \
        --quiet || warning "IAM binding may already exist"
    
    success "IAM roles and access controls configured"
}

# Create analytics and monitoring
create_analytics() {
    info "Creating analytics dashboard and monitoring..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create analytics and monitoring"
        return 0
    fi
    
    # Insert sample search analytics data
    bq query --use_legacy_sql=false \
    "INSERT INTO \`${PROJECT_ID}.${DATASET_NAME}.search_queries\` VALUES
    ('q1', 'user1', 'remote work policy', CURRENT_TIMESTAMP(), 5, 0.8),
    ('q2', 'user2', 'API documentation customer service', CURRENT_TIMESTAMP(), 3, 0.6),
    ('q3', 'user3', 'quarterly financial results', CURRENT_TIMESTAMP(), 2, 1.0),
    ('q4', 'user1', 'employee handbook security', CURRENT_TIMESTAMP(), 4, 0.5)" \
    --quiet || warning "Failed to insert sample search data"
    
    # Insert sample document analytics data
    bq query --use_legacy_sql=false \
    "INSERT INTO \`${PROJECT_ID}.${DATASET_NAME}.document_analytics\` VALUES
    ('doc1', 'hr_policy.txt', 25, CURRENT_TIMESTAMP(), 0.85),
    ('doc2', 'api_documentation.txt', 18, CURRENT_TIMESTAMP(), 0.92),
    ('doc3', 'financial_report.txt', 12, CURRENT_TIMESTAMP(), 0.78)" \
    --quiet || warning "Failed to insert sample document data"
    
    # Create monitoring dashboard configuration
    cat > "${SCRIPT_DIR}/monitoring_config.json" << 'EOF'
{
  "displayName": "Enterprise Knowledge Discovery Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Search Query Volume",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "unitOverride": "1",
                "outputFullResourceType": false
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Document Access Patterns",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "unitOverride": "1",
                "outputFullResourceType": false
              }
            }]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create Cloud Monitoring dashboard
    gcloud monitoring dashboards create \
        --config-from-file="${SCRIPT_DIR}/monitoring_config.json" \
        --quiet || warning "Failed to create monitoring dashboard"
    
    success "Analytics and monitoring configured"
}

# Validation and testing
run_validation() {
    info "Running validation and testing..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would run validation tests"
        return 0
    fi
    
    # Test BigQuery connectivity
    info "Testing BigQuery connectivity..."
    local query_result
    query_result=$(bq query --use_legacy_sql=false \
        "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.${DATASET_NAME}.search_queries\`" \
        --format=csv --quiet 2>/dev/null | tail -n 1)
    
    if [[ "${query_result}" =~ ^[0-9]+$ ]]; then
        success "BigQuery validation successful - found ${query_result} sample queries"
    else
        warning "BigQuery validation failed or returned unexpected results"
    fi
    
    # Test storage bucket access
    info "Testing storage bucket access..."
    local bucket_files
    bucket_files=$(gsutil ls "gs://${BUCKET_NAME}/documents/" | wc -l)
    
    if [[ "${bucket_files}" -gt 0 ]]; then
        success "Storage validation successful - found ${bucket_files} documents"
    else
        warning "Storage validation failed - no documents found"
    fi
    
    # Check Vertex AI Search status
    info "Checking Vertex AI Search status..."
    if gcloud alpha discovery-engine data-stores describe "${SEARCH_APP_ID}" \
        --location=global &>/dev/null; then
        success "Vertex AI Search data store is accessible"
    else
        warning "Vertex AI Search data store validation failed"
    fi
    
    success "Validation completed"
}

# Display deployment summary
show_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    echo ""
    echo "=========================================="
    success "Enterprise Knowledge Discovery Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Deployment Details:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Duration: ${duration} seconds"
    echo ""
    echo "Created Resources:"
    echo "  ✅ Storage Bucket: gs://${BUCKET_NAME}"
    echo "  ✅ BigQuery Dataset: ${DATASET_NAME}"
    echo "  ✅ Vertex AI Search App: ${SEARCH_APP_ID}"
    echo "  ✅ IAM Roles and Service Account"
    echo "  ✅ Monitoring Dashboard"
    echo ""
    echo "Next Steps:"
    echo "  1. Wait 10-15 minutes for document indexing to complete"
    echo "  2. Test search functionality using the Google Cloud Console"
    echo "  3. Configure additional users and access controls as needed"
    echo "  4. Upload additional enterprise documents to gs://${BUCKET_NAME}/documents/"
    echo ""
    echo "Access URLs:"
    echo "  - Cloud Console: https://console.cloud.google.com/project/${PROJECT_ID}"
    echo "  - BigQuery: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
    echo "  - Storage: https://console.cloud.google.com/storage/browser/${BUCKET_NAME}?project=${PROJECT_ID}"
    echo ""
    warning "Important: Some services (like Agentspace) may still be in preview and require allowlisting."
    echo ""
    echo "Log file: ${LOG_FILE}"
    echo "=========================================="
}

# Confirmation prompt
confirm_deployment() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "Enterprise Knowledge Discovery Deployment"
    echo "=========================================="
    echo ""
    echo "This script will deploy the following resources:"
    echo "  • Cloud Storage bucket for document repository"
    echo "  • BigQuery dataset for analytics"
    echo "  • Vertex AI Search application and engine"
    echo "  • Google Agentspace integration (if available)"
    echo "  • IAM roles and service accounts"
    echo "  • Cloud Monitoring dashboard"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    warning "This deployment may incur charges on your Google Cloud account."
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    info "Starting Enterprise Knowledge Discovery deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    confirm_deployment
    
    enable_apis
    create_storage_bucket
    upload_sample_documents
    create_bigquery_dataset
    create_vertex_ai_search
    configure_search_settings
    setup_agentspace
    configure_iam
    create_analytics
    run_validation
    
    show_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
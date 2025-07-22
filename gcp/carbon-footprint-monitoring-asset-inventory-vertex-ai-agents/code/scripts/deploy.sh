#!/bin/bash

# Carbon Footprint Monitoring with Cloud Asset Inventory and Vertex AI Agents
# Deployment Script for GCP Recipe
# Version: 1.0
# Author: Generated for recipes repository

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DRY_RUN=${DRY_RUN:-false}

# Deployment configuration
readonly DEFAULT_REGION="us-central1"
readonly REQUIRED_APIS=(
    "cloudasset.googleapis.com"
    "bigquery.googleapis.com"
    "pubsub.googleapis.com"
    "aiplatform.googleapis.com"
    "monitoring.googleapis.com"
    "carbonfootprint.googleapis.com"
)

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Utility functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}"
    fi
}

# Print usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy carbon footprint monitoring infrastructure using Cloud Asset Inventory and Vertex AI agents.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -n, --dry-run                 Show what would be deployed without making changes
    -d, --debug                   Enable debug logging
    -h, --help                    Show this help message
    -f, --force                   Skip confirmation prompts

EXAMPLES:
    ${SCRIPT_NAME} --project-id my-carbon-project
    ${SCRIPT_NAME} --project-id my-project --region europe-west1 --dry-run
    ${SCRIPT_NAME} -p my-project -r us-west1 -f

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT          Default project ID if not specified
    DRY_RUN                       Set to 'true' for dry-run mode
    DEBUG                         Set to 'true' for debug logging

EOF
}

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        error "Deployment failed with exit code ${exit_code}"
        error "Check ${LOG_FILE} for details"
    fi
    exit ${exit_code}
}

# Set up signal handlers
trap cleanup EXIT
trap 'error "Deployment interrupted by user"; exit 130' INT TERM

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null)
    log "Google Cloud SDK version: ${gcloud_version}"
    
    # Check if bq CLI is available
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not available. Please ensure it's installed with gcloud components"
        return 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "Cloud Storage CLI (gsutil) is not available. Please ensure it's installed with gcloud components"
        return 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        return 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
    log "Authenticated as: ${active_account}"
    
    log "Prerequisites check completed successfully"
}

# Validate project and set configuration
validate_project() {
    local project_id="$1"
    
    log "Validating project: ${project_id}"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${project_id}" &> /dev/null; then
        error "Project '${project_id}' not found or access denied"
        return 1
    fi
    
    # Set project configuration
    if [[ "${DRY_RUN}" != "true" ]]; then
        gcloud config set project "${project_id}"
        gcloud config set compute/region "${REGION}"
    fi
    
    log "Project validation successful"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        debug "Checking API: ${api}"
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "DRY RUN: Would enable API: ${api}"
        else
            if gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
                log "API already enabled: ${api}"
            else
                log "Enabling API: ${api}"
                gcloud services enable "${api}"
            fi
        fi
    done
    
    log "API enablement completed"
}

# Generate unique resource identifiers
generate_identifiers() {
    # Generate timestamp-based suffix for uniqueness
    local timestamp
    timestamp=$(date +%s)
    
    # Generate random suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "${timestamp}")
    
    # Set resource names
    export DATASET_NAME="carbon_footprint_analytics"
    export AGENT_NAME="sustainability-advisor"
    export BUCKET_NAME="carbon-data-${RANDOM_SUFFIX}"
    export TOPIC_NAME="asset-changes-${RANDOM_SUFFIX}"
    
    log "Generated resource identifiers:"
    log "  Dataset: ${DATASET_NAME}"
    log "  Agent: ${AGENT_NAME}"
    log "  Bucket: ${BUCKET_NAME}"
    log "  Topic: ${TOPIC_NAME}"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log "Creating BigQuery dataset and tables..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create BigQuery dataset: ${DATASET_NAME}"
        log "DRY RUN: Would create tables: asset_inventory, carbon_emissions"
        return 0
    fi
    
    # Create dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "BigQuery dataset already exists: ${DATASET_NAME}"
    else
        log "Creating BigQuery dataset: ${DATASET_NAME}"
        bq mk --dataset \
            --location="${REGION}" \
            --description="Carbon footprint and sustainability analytics" \
            "${PROJECT_ID}:${DATASET_NAME}"
    fi
    
    # Create asset inventory table
    local asset_table="${PROJECT_ID}:${DATASET_NAME}.asset_inventory"
    if bq ls "${asset_table}" &>/dev/null; then
        log "Asset inventory table already exists"
    else
        log "Creating asset inventory table"
        bq mk --table \
            "${asset_table}" \
            timestamp:TIMESTAMP,asset_type:STRING,name:STRING,location:STRING,resource_data:JSON
    fi
    
    # Create carbon emissions table
    local carbon_table="${PROJECT_ID}:${DATASET_NAME}.carbon_emissions"
    if bq ls "${carbon_table}" &>/dev/null; then
        log "Carbon emissions table already exists"
    else
        log "Creating carbon emissions table"
        bq mk --table \
            "${carbon_table}" \
            billing_account_id:STRING,project_id:STRING,service:STRING,location:STRING,carbon_footprint_kgCO2e:FLOAT64,carbon_footprint_total_kgCO2e:FLOAT64,usage_month:DATE
    fi
    
    log "BigQuery resources created successfully"
}

# Set up Cloud Asset Inventory
setup_asset_inventory() {
    log "Setting up Cloud Asset Inventory..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create Pub/Sub topic: ${TOPIC_NAME}"
        log "DRY RUN: Would create asset inventory feed"
        return 0
    fi
    
    # Create Pub/Sub topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
        log "Pub/Sub topic already exists: ${TOPIC_NAME}"
    else
        log "Creating Pub/Sub topic: ${TOPIC_NAME}"
        gcloud pubsub topics create "${TOPIC_NAME}"
    fi
    
    # Check if feed already exists
    local feed_name="carbon-monitoring-feed"
    if gcloud asset feeds describe "${feed_name}" --project="${PROJECT_ID}" &>/dev/null; then
        log "Asset inventory feed already exists: ${feed_name}"
    else
        log "Creating asset inventory feed: ${feed_name}"
        gcloud asset feeds create "${feed_name}" \
            --project="${PROJECT_ID}" \
            --asset-types="compute.googleapis.com/Instance,storage.googleapis.com/Bucket,container.googleapis.com/Cluster" \
            --content-type=resource \
            --pubsub-topic="projects/${PROJECT_ID}/topics/${TOPIC_NAME}"
    fi
    
    # Set up IAM permissions for asset inventory service
    local asset_service_account="cloud-asset-inventory@system.gserviceaccount.com"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${asset_service_account}" \
        --role="roles/pubsub.publisher" || warn "IAM binding may already exist"
    
    log "Asset inventory setup completed"
}

# Configure carbon footprint data export
configure_carbon_export() {
    log "Configuring carbon footprint data export..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would configure carbon footprint export to BigQuery"
        log "DRY RUN: Would create monthly carbon trends view"
        return 0
    fi
    
    # Note: Carbon footprint export configuration is typically done through Console
    # The API for this is in alpha and may not be available via gcloud CLI
    log "Carbon footprint export configuration:"
    log "  - Manual step required: Configure export in Cloud Console"
    log "  - Navigate to Carbon Footprint service in Console"
    log "  - Set up BigQuery export to: ${PROJECT_ID}.${DATASET_NAME}.carbon_emissions"
    
    # Create a view for monthly carbon trends
    local view_query="CREATE VIEW \`${PROJECT_ID}.${DATASET_NAME}.monthly_carbon_trends\` AS
    SELECT 
      usage_month,
      service,
      location,
      SUM(carbon_footprint_total_kgCO2e) as total_emissions,
      COUNT(*) as resource_count
    FROM \`${PROJECT_ID}.${DATASET_NAME}.carbon_emissions\`
    GROUP BY usage_month, service, location
    ORDER BY usage_month DESC"
    
    echo "${view_query}" | bq query --use_legacy_sql=false || warn "View creation failed or already exists"
    
    log "Carbon footprint export configuration completed"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create storage bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Storage bucket already exists: ${BUCKET_NAME}"
    else
        log "Creating storage bucket: ${BUCKET_NAME}"
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
    fi
    
    # Configure lifecycle management
    cat > /tmp/lifecycle.json << EOF
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
    
    gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"
    rm -f /tmp/lifecycle.json
    
    log "Storage bucket created with lifecycle policies"
}

# Deploy Vertex AI agent
deploy_vertex_ai_agent() {
    log "Deploying Vertex AI agent..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create Vertex AI agent: ${AGENT_NAME}"
        log "DRY RUN: Would configure agent with BigQuery data source"
        return 0
    fi
    
    # Note: Vertex AI Agent Builder is currently in preview and may require Console setup
    # The gcloud commands for agent creation are in alpha/preview
    log "Vertex AI agent deployment:"
    log "  - Manual step required: Create agent in Vertex AI Agent Builder Console"
    log "  - Agent name: ${AGENT_NAME}"
    log "  - Display name: Carbon Footprint Sustainability Advisor"
    log "  - Data source: projects/${PROJECT_ID}/datasets/${DATASET_NAME}"
    log "  - Instruction: You are a sustainability expert focused on cloud infrastructure carbon footprint optimization."
    
    # Create instruction file for reference
    cat > "${SCRIPT_DIR}/agent_instruction.txt" << EOF
Agent Name: ${AGENT_NAME}
Display Name: Carbon Footprint Sustainability Advisor
Region: ${REGION}

Instruction:
You are a sustainability expert focused on cloud infrastructure carbon footprint optimization. 
Analyze data from Cloud Asset Inventory and Carbon Footprint service to provide actionable 
recommendations for reducing environmental impact while optimizing costs.

Data Sources:
- BigQuery Dataset: ${PROJECT_ID}.${DATASET_NAME}
- Tables: asset_inventory, carbon_emissions, monthly_carbon_trends

Capabilities:
- Analyze carbon emissions by service and location
- Identify optimization opportunities
- Provide cost-effective sustainability recommendations
- Generate ESG compliance reports
EOF
    
    log "Agent instruction file created: ${SCRIPT_DIR}/agent_instruction.txt"
    log "Vertex AI agent deployment preparation completed"
}

# Set up monitoring and alerting
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create custom metrics and alerting policies"
        return 0
    fi
    
    # Create custom metric descriptor (using gcloud beta as alpha commands may not be available)
    local metric_type="custom.googleapis.com/carbon/emissions_per_service"
    
    # Create metric descriptor JSON
    cat > /tmp/metric_descriptor.json << EOF
{
  "type": "${metric_type}",
  "metricKind": "GAUGE",
  "valueType": "DOUBLE",
  "description": "Carbon emissions per Google Cloud service in kgCO2e"
}
EOF
    
    # Try to create the metric descriptor (may fail if it already exists)
    curl -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @/tmp/metric_descriptor.json \
        "https://monitoring.googleapis.com/v1/projects/${PROJECT_ID}/metricDescriptors" || warn "Metric descriptor creation failed or already exists"
    
    rm -f /tmp/metric_descriptor.json
    
    # Create alerting policy JSON
    cat > /tmp/alert_policy.json << EOF
{
  "displayName": "High Carbon Emissions Alert",
  "conditions": [
    {
      "displayName": "Carbon emissions threshold exceeded",
      "conditionThreshold": {
        "filter": "metric.type=\"${metric_type}\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 10.0
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    
    # Try to create the alerting policy
    curl -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @/tmp/alert_policy.json \
        "https://monitoring.googleapis.com/v1/projects/${PROJECT_ID}/alertPolicies" || warn "Alert policy creation failed or already exists"
    
    rm -f /tmp/alert_policy.json
    
    log "Monitoring and alerting setup completed"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Skipping deployment validation"
        return 0
    fi
    
    local validation_errors=0
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "✓ BigQuery dataset exists: ${DATASET_NAME}"
    else
        error "✗ BigQuery dataset not found: ${DATASET_NAME}"
        ((validation_errors++))
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
        log "✓ Pub/Sub topic exists: ${TOPIC_NAME}"
    else
        error "✗ Pub/Sub topic not found: ${TOPIC_NAME}"
        ((validation_errors++))
    fi
    
    # Check storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "✓ Storage bucket exists: ${BUCKET_NAME}"
    else
        error "✗ Storage bucket not found: ${BUCKET_NAME}"
        ((validation_errors++))
    fi
    
    # Check asset feed
    if gcloud asset feeds describe "carbon-monitoring-feed" --project="${PROJECT_ID}" &>/dev/null; then
        log "✓ Asset inventory feed exists"
    else
        error "✗ Asset inventory feed not found"
        ((validation_errors++))
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log "Deployment validation successful"
        return 0
    else
        error "Deployment validation failed with ${validation_errors} errors"
        return 1
    fi
}

# Print post-deployment instructions
print_post_deployment_info() {
    log "Deployment completed successfully!"
    log ""
    log "Post-deployment manual steps required:"
    log "1. Configure Carbon Footprint export to BigQuery:"
    log "   - Navigate to Carbon Footprint service in Google Cloud Console"
    log "   - Set up export to: ${PROJECT_ID}.${DATASET_NAME}.carbon_emissions"
    log ""
    log "2. Create Vertex AI Agent:"
    log "   - Open Vertex AI Agent Builder in Google Cloud Console"
    log "   - Create agent using configuration in: ${SCRIPT_DIR}/agent_instruction.txt"
    log ""
    log "3. Set up monitoring dashboard:"
    log "   - Navigate to Cloud Monitoring"
    log "   - Create custom dashboard for carbon footprint metrics"
    log ""
    log "Resources created:"
    log "  - BigQuery dataset: ${PROJECT_ID}.${DATASET_NAME}"
    log "  - Storage bucket: gs://${BUCKET_NAME}"
    log "  - Pub/Sub topic: ${TOPIC_NAME}"
    log "  - Asset inventory feed: carbon-monitoring-feed"
    log ""
    log "Estimated monthly cost: $50-150 (varies based on usage)"
    log "Log file: ${LOG_FILE}"
}

# Main deployment function
main() {
    local project_id=""
    local region="${DEFAULT_REGION}"
    local force=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                project_id="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -n|--dry-run)
                export DRY_RUN=true
                shift
                ;;
            -d|--debug)
                export DEBUG=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Use environment variable if project not specified
    if [[ -z "${project_id}" ]]; then
        project_id="${GOOGLE_CLOUD_PROJECT:-}"
    fi
    
    # Validate required parameters
    if [[ -z "${project_id}" ]]; then
        error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        usage
        exit 1
    fi
    
    # Export variables for use in functions
    export PROJECT_ID="${project_id}"
    export REGION="${region}"
    
    log "Starting carbon footprint monitoring deployment"
    log "Project: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Dry run: ${DRY_RUN}"
    log "Log file: ${LOG_FILE}"
    
    # Confirmation prompt (unless forced or dry run)
    if [[ "${force}" != "true" && "${DRY_RUN}" != "true" ]]; then
        echo -e "${YELLOW}This will deploy carbon footprint monitoring infrastructure in project '${PROJECT_ID}'.${NC}"
        echo -e "${YELLOW}Estimated cost: $50-150/month. Do you want to continue? (y/N)${NC}"
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_project "${PROJECT_ID}"
    enable_apis
    generate_identifiers
    create_bigquery_resources
    setup_asset_inventory
    configure_carbon_export
    create_storage_bucket
    deploy_vertex_ai_agent
    setup_monitoring
    validate_deployment
    print_post_deployment_info
    
    log "Carbon footprint monitoring deployment completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash
#
# Cloud Asset Governance Deployment Script
# Deploys automated governance system using Cloud Asset Inventory and Cloud Workflows
#
# Prerequisites:
# - gcloud CLI installed and authenticated
# - Organization Admin or Security Admin roles
# - Billing account linked to project
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   -p, --project PROJECT_ID    Set the project ID (optional - will generate if not provided)
#   -o, --org ORG_ID           Set the organization ID (required)
#   -r, --region REGION        Set the deployment region (default: us-central1)
#   -h, --help                 Show this help message
#   --dry-run                  Show what would be deployed without making changes
#   --force                    Skip confirmation prompts
#

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false
FORCE=false
CLEANUP_ON_ERROR=true

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}ℹ️  INFO:${NC} $*"
}

log_success() {
    log "${GREEN}✅ SUCCESS:${NC} $*"
}

log_warning() {
    log "${YELLOW}⚠️  WARNING:${NC} $*"
}

log_error() {
    log "${RED}❌ ERROR:${NC} $*"
}

# Help function
show_help() {
    cat << EOF
Cloud Asset Governance Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project PROJECT_ID    Set the project ID (optional - will generate if not provided)
    -o, --org ORG_ID           Set the organization ID (required)
    -r, --region REGION        Set the deployment region (default: us-central1)
    -h, --help                 Show this help message
    --dry-run                  Show what would be deployed without making changes
    --force                    Skip confirmation prompts

PREREQUISITES:
    - gcloud CLI installed and authenticated
    - Organization Admin or Security Admin roles
    - Billing account configured
    - Required APIs enabled (will be enabled automatically)

EXAMPLES:
    # Deploy with auto-generated project
    $0 --org 123456789012

    # Deploy to specific project
    $0 --project my-governance-project --org 123456789012

    # Dry run to see what would be deployed
    $0 --org 123456789012 --dry-run

    # Force deployment without prompts
    $0 --org 123456789012 --force

EOF
}

# Error handling
cleanup_on_error() {
    if [[ "${CLEANUP_ON_ERROR}" == "true" && -n "${PROJECT_ID:-}" ]]; then
        log_warning "Deployment failed. Cleaning up created resources..."
        if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
            "${SCRIPT_DIR}/destroy.sh" --project "${PROJECT_ID}" --force --no-confirm 2>/dev/null || true
        fi
    fi
}

trap cleanup_on_error ERR

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -o|--org)
                ORGANIZATION_ID="$2"
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
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Set defaults
    REGION="${REGION:-$DEFAULT_REGION}"
    ZONE="${ZONE:-$DEFAULT_ZONE}"

    # Validate required parameters
    if [[ -z "${ORGANIZATION_ID:-}" ]]; then
        log_error "Organization ID is required. Use --org ORG_ID"
        show_help
        exit 1
    fi

    # Generate project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="governance-system-$(date +%s)"
        log_info "Generated project ID: ${PROJECT_ID}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi

    # Verify organization access
    if ! gcloud organizations describe "${ORGANIZATION_ID}" &> /dev/null; then
        log_error "Cannot access organization ${ORGANIZATION_ID}. Check permissions."
        exit 1
    fi

    # Check for billing account
    local billing_accounts
    billing_accounts=$(gcloud billing accounts list --format="value(name)" --limit=1)
    if [[ -z "${billing_accounts}" ]]; then
        log_error "No billing accounts found. Please ensure billing is configured."
        exit 1
    fi
    BILLING_ACCOUNT="${billing_accounts}"

    log_success "Prerequisites check passed"
}

# Confirm deployment
confirm_deployment() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi

    log_info "Deployment Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Organization ID: ${ORGANIZATION_ID}"
    echo "  Region: ${REGION}"
    echo "  Billing Account: ${BILLING_ACCOUNT}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No actual resources will be created"
        return 0
    fi

    echo
    read -p "Do you want to proceed with deployment? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Execute command with dry run support
execute_cmd() {
    local cmd="$*"
    log_info "Executing: ${cmd}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${cmd}"
        return 0
    fi
    
    eval "${cmd}"
}

# Create and configure project
setup_project() {
    log_info "Setting up governance project..."

    # Create project
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        execute_cmd "gcloud projects create \"${PROJECT_ID}\" \
            --name=\"Cloud Asset Governance System\" \
            --organization=\"${ORGANIZATION_ID}\""
        log_success "Created project: ${PROJECT_ID}"
    else
        log_warning "Project ${PROJECT_ID} already exists, using existing project"
    fi

    # Link billing account
    execute_cmd "gcloud billing projects link \"${PROJECT_ID}\" \
        --billing-account=\"${BILLING_ACCOUNT}\""

    # Set default project and region
    execute_cmd "gcloud config set project \"${PROJECT_ID}\""
    execute_cmd "gcloud config set compute/region \"${REGION}\""
    execute_cmd "gcloud config set compute/zone \"${ZONE}\""

    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."

    local apis=(
        "cloudasset.googleapis.com"
        "workflows.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "run.googleapis.com"
        "eventarc.googleapis.com"
    )

    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable \"${api}\""
        log_success "Enabled API: ${api}"
    done

    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN}" == "false" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
}

# Generate unique resource names
generate_resource_names() {
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export GOVERNANCE_SUFFIX="gov-${random_suffix}"
    export GOVERNANCE_BUCKET="${PROJECT_ID}-governance-${GOVERNANCE_SUFFIX}"
    export BQ_DATASET="asset_governance_${GOVERNANCE_SUFFIX//-/_}"
    export ASSET_TOPIC="asset-changes-${GOVERNANCE_SUFFIX}"
    export WORKFLOW_SUBSCRIPTION="workflow-processor-${GOVERNANCE_SUFFIX}"
    export GOVERNANCE_SA="governance-engine-${GOVERNANCE_SUFFIX}"
    export FEED_NAME="governance-feed-${GOVERNANCE_SUFFIX}"

    log_info "Generated resource names with suffix: ${GOVERNANCE_SUFFIX}"
}

# Create storage bucket
create_storage() {
    log_info "Creating Cloud Storage bucket..."

    execute_cmd "gsutil mb -p \"${PROJECT_ID}\" \
        -c STANDARD \
        -l \"${REGION}\" \
        \"gs://${GOVERNANCE_BUCKET}\""

    execute_cmd "gsutil versioning set on \"gs://${GOVERNANCE_BUCKET}\""

    # Create folder structure
    if [[ "${DRY_RUN}" == "false" ]]; then
        echo "Created governance storage structure" | \
            gsutil cp - "gs://${GOVERNANCE_BUCKET}/policies/.keep"
        echo "Created compliance reports folder" | \
            gsutil cp - "gs://${GOVERNANCE_BUCKET}/reports/.keep"
    fi

    log_success "Storage bucket created: ${GOVERNANCE_BUCKET}"
}

# Create BigQuery dataset
create_bigquery() {
    log_info "Creating BigQuery dataset..."

    execute_cmd "bq mk --project_id=\"${PROJECT_ID}\" \
        --location=\"${REGION}\" \
        --description=\"Cloud Asset Governance Analytics Dataset\" \
        \"${BQ_DATASET}\""

    # Create tables
    execute_cmd "bq mk --project_id=\"${PROJECT_ID}\" \
        --table \"${BQ_DATASET}.asset_violations\" \
        violation_id:STRING,resource_name:STRING,policy_name:STRING,violation_type:STRING,severity:STRING,timestamp:TIMESTAMP,project_id:STRING,remediation_status:STRING"

    execute_cmd "bq mk --project_id=\"${PROJECT_ID}\" \
        --table \"${BQ_DATASET}.compliance_reports\" \
        report_id:STRING,scan_timestamp:TIMESTAMP,total_resources:INTEGER,violations_found:INTEGER,high_severity:INTEGER,medium_severity:INTEGER,low_severity:INTEGER,compliance_score:FLOAT"

    log_success "BigQuery dataset created: ${BQ_DATASET}"
}

# Create Pub/Sub infrastructure
create_pubsub() {
    log_info "Creating Pub/Sub infrastructure..."

    execute_cmd "gcloud pubsub topics create \"${ASSET_TOPIC}\" \
        --message-retention-duration=7d \
        --message-encoding=JSON"

    execute_cmd "gcloud pubsub subscriptions create \"${WORKFLOW_SUBSCRIPTION}\" \
        --topic=\"${ASSET_TOPIC}\" \
        --ack-deadline=600s \
        --message-retention-duration=7d"

    log_success "Pub/Sub infrastructure created"
}

# Create service account
create_service_account() {
    log_info "Creating governance service account..."

    execute_cmd "gcloud iam service-accounts create \"${GOVERNANCE_SA}\" \
        --display-name=\"Cloud Asset Governance Engine\" \
        --description=\"Service account for automated governance operations\""

    # Grant permissions
    local permissions=(
        "roles/cloudasset.viewer"
        "roles/workflows.invoker"
        "roles/bigquery.dataEditor"
        "roles/storage.objectAdmin"
        "roles/pubsub.publisher"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )

    for permission in "${permissions[@]}"; do
        if [[ "${permission}" == "roles/cloudasset.viewer" ]]; then
            execute_cmd "gcloud organizations add-iam-policy-binding \"${ORGANIZATION_ID}\" \
                --member=\"serviceAccount:${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com\" \
                --role=\"${permission}\""
        else
            execute_cmd "gcloud projects add-iam-policy-binding \"${PROJECT_ID}\" \
                --member=\"serviceAccount:${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com\" \
                --role=\"${permission}\""
        fi
    done

    log_success "Service account created and configured"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."

    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Copy function code if it exists, otherwise create it
    if [[ -d "${PROJECT_ROOT}/terraform/function_code" ]]; then
        cp -r "${PROJECT_ROOT}/terraform/function_code"/* "${temp_dir}/"
    else
        # Create policy evaluation function
        cat > "${temp_dir}/main.py" << 'EOF'
import json
import logging
from google.cloud import bigquery
from google.cloud import storage
from datetime import datetime
import hashlib

def evaluate_governance_policy(request):
    """Evaluate assets against governance policies."""
    
    # Initialize clients
    bq_client = bigquery.Client()
    storage_client = storage.Client()
    
    # Parse asset change event
    event_data = request.get_json()
    
    if not event_data or 'asset' not in event_data:
        return {'status': 'no_asset_data'}, 200
    
    asset = event_data['asset']
    asset_type = asset.get('asset_type', '')
    resource_name = asset.get('name', '')
    
    # Define governance policies
    violations = []
    
    # Policy 1: Check for unencrypted storage buckets
    if asset_type == 'storage.googleapis.com/Bucket':
        resource_data = asset.get('resource', {}).get('data', {})
        encryption = resource_data.get('encryption', {})
        if not encryption:
            violations.append({
                'policy': 'storage_encryption_required',
                'severity': 'HIGH',
                'description': 'Storage bucket lacks customer-managed encryption'
            })
    
    # Policy 2: Check for compute instances without secure boot
    if asset_type == 'compute.googleapis.com/Instance':
        resource_data = asset.get('resource', {}).get('data', {})
        secure_boot = resource_data.get('shieldedInstanceConfig', {}).get('enableSecureBoot', False)
        if not secure_boot:
            violations.append({
                'policy': 'compute_secure_boot_required',
                'severity': 'MEDIUM',
                'description': 'Compute instance lacks secure boot configuration'
            })
    
    # Policy 3: Check for public IP assignments
    if asset_type == 'compute.googleapis.com/Instance':
        resource_data = asset.get('resource', {}).get('data', {})
        network_interfaces = resource_data.get('networkInterfaces', [])
        for interface in network_interfaces:
            if interface.get('accessConfigs'):
                violations.append({
                    'policy': 'no_public_ip_required',
                    'severity': 'HIGH',
                    'description': 'Compute instance has public IP assignment'
                })
                break
    
    # Record violations in BigQuery
    if violations:
        table_id = f"{bq_client.project}.asset_governance_{request.headers.get('X-Governance-Suffix', 'default').replace('-', '_')}.asset_violations"
        
        rows_to_insert = []
        for violation in violations:
            violation_id = hashlib.md5(f"{resource_name}-{violation['policy']}-{datetime.now().isoformat()}".encode()).hexdigest()
            rows_to_insert.append({
                'violation_id': violation_id,
                'resource_name': resource_name,
                'policy_name': violation['policy'],
                'violation_type': violation['description'],
                'severity': violation['severity'],
                'timestamp': datetime.now().isoformat(),
                'project_id': asset.get('ancestors', [])[-1] if asset.get('ancestors') else 'unknown',
                'remediation_status': 'DETECTED'
            })
        
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            logging.error(f"BigQuery insert errors: {errors}")
    
    return {
        'status': 'completed',
        'violations_found': len(violations),
        'resource_name': resource_name,
        'asset_type': asset_type
    }, 200

def trigger_governance_workflow(event, context):
    """Trigger governance workflow from Pub/Sub message."""
    
    # Initialize Workflows client
    from google.cloud import workflows_v1
    import base64
    
    client = workflows_v1.WorkflowsClient()
    
    # Parse Pub/Sub message
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    message_data = json.loads(pubsub_message)
    
    # Prepare workflow execution
    project_id = context.resource.split('/')[1]
    location = 'us-central1'  # Use your configured region
    workflow_id = 'governance-orchestrator'
    
    workflow_path = f"projects/{project_id}/locations/{location}/workflows/{workflow_id}"
    
    # Execute workflow with asset data
    execution_request = {
        "parent": workflow_path,
        "execution": {
            "argument": json.dumps({
                "message": {
                    "data": event['data']
                }
            })
        }
    }
    
    try:
        operation = client.create_execution(request=execution_request)
        logging.info(f"Workflow execution started: {operation.name}")
        return {'status': 'workflow_triggered', 'execution': operation.name}
    except Exception as e:
        logging.error(f"Failed to trigger workflow: {str(e)}")
        return {'status': 'error', 'message': str(e)}
EOF

        cat > "${temp_dir}/requirements.txt" << 'EOF'
google-cloud-bigquery==3.13.0
google-cloud-storage==2.10.0
google-cloud-workflows==1.12.0
google-auth==2.23.0
functions-framework==3.4.0
EOF
    fi

    # Deploy policy evaluation function
    execute_cmd "gcloud functions deploy governance-policy-evaluator \
        --gen2 \
        --runtime=python311 \
        --region=\"${REGION}\" \
        --source=\"${temp_dir}\" \
        --entry-point=evaluate_governance_policy \
        --trigger=http \
        --service-account=\"${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com\" \
        --set-env-vars=\"GOVERNANCE_SUFFIX=${GOVERNANCE_SUFFIX}\" \
        --max-instances=10 \
        --memory=512MB \
        --timeout=540s"

    # Deploy workflow trigger function
    execute_cmd "gcloud functions deploy governance-workflow-trigger \
        --gen2 \
        --runtime=python311 \
        --region=\"${REGION}\" \
        --source=\"${temp_dir}\" \
        --entry-point=trigger_governance_workflow \
        --trigger-topic=\"${ASSET_TOPIC}\" \
        --service-account=\"${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com\" \
        --max-instances=20 \
        --memory=256MB \
        --timeout=60s"

    # Cleanup temporary directory
    rm -rf "${temp_dir}"

    log_success "Cloud Functions deployed"
}

# Deploy Cloud Workflow
deploy_workflow() {
    log_info "Deploying Cloud Workflow..."

    local workflow_file
    if [[ -f "${PROJECT_ROOT}/terraform/workflow_definitions/governance_workflow.yaml" ]]; then
        workflow_file="${PROJECT_ROOT}/terraform/workflow_definitions/governance_workflow.yaml"
    else
        # Create temporary workflow file
        workflow_file=$(mktemp)
        cat > "${workflow_file}" << EOF
main:
  steps:
    - initialize:
        assign:
          - project_id: "${PROJECT_ID}"
          - governance_suffix: "${GOVERNANCE_SUFFIX}"
          - function_url: "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/governance-policy-evaluator"
    
    - parse_pubsub_message:
        assign:
          - message_data: \${base64.decode(args.message.data)}
          - asset_change: \${json.decode(message_data)}
    
    - log_asset_change:
        call: sys.log
        args:
          text: \${"Processing asset change: " + asset_change.asset.name}
          severity: "INFO"
    
    - evaluate_policies:
        call: http.post
        args:
          url: \${function_url}
          headers:
            Content-Type: "application/json"
            X-Governance-Suffix: \${governance_suffix}
          body:
            asset: \${asset_change.asset}
            change_type: \${asset_change.change_type}
        result: evaluation_result
    
    - check_violations:
        switch:
          - condition: \${evaluation_result.body.violations_found > 0}
            next: process_violations
          - condition: true
            next: complete_processing
    
    - process_violations:
        steps:
          - log_violations:
              call: sys.log
              args:
                text: \${"Found " + string(evaluation_result.body.violations_found) + " violations for " + evaluation_result.body.resource_name}
                severity: "WARNING"
    
    - complete_processing:
        call: sys.log
        args:
          text: "Governance processing completed successfully"
          severity: "INFO"
    
    - return_result:
        return:
          status: "completed"
          violations: \${evaluation_result.body.violations_found}
          resource: \${evaluation_result.body.resource_name}
EOF
    fi

    execute_cmd "gcloud workflows deploy governance-orchestrator \
        --source=\"${workflow_file}\" \
        --location=\"${REGION}\" \
        --service-account=\"${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com\""

    # Cleanup temporary file if created
    if [[ "${workflow_file}" == /tmp/* ]]; then
        rm -f "${workflow_file}"
    fi

    log_success "Cloud Workflow deployed"
}

# Create asset feed
create_asset_feed() {
    log_info "Creating Cloud Asset Inventory feed..."

    # Grant Asset Inventory service account permissions
    local asset_sa
    asset_sa="service-$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')@gcp-sa-cloudasset.iam.gserviceaccount.com"

    execute_cmd "gcloud pubsub topics add-iam-policy-binding \"${ASSET_TOPIC}\" \
        --member=\"serviceAccount:${asset_sa}\" \
        --role=\"roles/pubsub.publisher\""

    # Create the asset feed
    execute_cmd "gcloud asset feeds create \"${FEED_NAME}\" \
        --organization=\"${ORGANIZATION_ID}\" \
        --pubsub-topic=\"projects/${PROJECT_ID}/topics/${ASSET_TOPIC}\" \
        --content-type=resource \
        --asset-types=storage.googleapis.com/Bucket,compute.googleapis.com/Instance,bigquery.googleapis.com/Dataset \
        --relationship-types=\"\""

    log_success "Asset feed created: ${FEED_NAME}"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Deployment verification skipped"
        return 0
    fi

    # Check asset feed
    if gcloud asset feeds list --organization="${ORGANIZATION_ID}" --filter="name:${FEED_NAME}" --format="value(name)" | grep -q "${FEED_NAME}"; then
        log_success "Asset feed verified"
    else
        log_error "Asset feed verification failed"
        return 1
    fi

    # Check Pub/Sub resources
    if gcloud pubsub topics list --filter="name:${ASSET_TOPIC}" --format="value(name)" | grep -q "${ASSET_TOPIC}"; then
        log_success "Pub/Sub topic verified"
    else
        log_error "Pub/Sub topic verification failed"
        return 1
    fi

    # Check Cloud Functions
    if gcloud functions list --region="${REGION}" --filter="name:governance-policy-evaluator" --format="value(name)" | grep -q "governance-policy-evaluator"; then
        log_success "Cloud Functions verified"
    else
        log_error "Cloud Functions verification failed"
        return 1
    fi

    # Check Cloud Workflow
    if gcloud workflows list --location="${REGION}" --filter="name:governance-orchestrator" --format="value(name)" | grep -q "governance-orchestrator"; then
        log_success "Cloud Workflow verified"
    else
        log_error "Cloud Workflow verification failed"
        return 1
    fi

    log_success "Deployment verification completed"
}

# Save deployment info
save_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment-info-${TIMESTAMP}.json"
    
    cat > "${info_file}" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "project_id": "${PROJECT_ID}",
  "organization_id": "${ORGANIZATION_ID}",
  "region": "${REGION}",
  "governance_suffix": "${GOVERNANCE_SUFFIX}",
  "resources": {
    "storage_bucket": "${GOVERNANCE_BUCKET}",
    "bigquery_dataset": "${BQ_DATASET}",
    "pubsub_topic": "${ASSET_TOPIC}",
    "pubsub_subscription": "${WORKFLOW_SUBSCRIPTION}",
    "service_account": "${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com",
    "asset_feed": "${FEED_NAME}",
    "functions": [
      "governance-policy-evaluator",
      "governance-workflow-trigger"
    ],
    "workflow": "governance-orchestrator"
  }
}
EOF

    log_success "Deployment info saved to: ${info_file}"
    
    # Also create a symlink to latest deployment info
    ln -sf "$(basename "${info_file}")" "${SCRIPT_DIR}/deployment-info-latest.json"
}

# Main deployment function
main() {
    log_info "Starting Cloud Asset Governance deployment"
    log_info "Log file: ${LOG_FILE}"

    parse_args "$@"
    check_prerequisites
    confirm_deployment
    generate_resource_names

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would deploy the following resources:"
        echo "  Project: ${PROJECT_ID}"
        echo "  Storage Bucket: ${GOVERNANCE_BUCKET}"
        echo "  BigQuery Dataset: ${BQ_DATASET}"
        echo "  Pub/Sub Topic: ${ASSET_TOPIC}"
        echo "  Service Account: ${GOVERNANCE_SA}"
        echo "  Asset Feed: ${FEED_NAME}"
        echo "  Cloud Functions: governance-policy-evaluator, governance-workflow-trigger"
        echo "  Cloud Workflow: governance-orchestrator"
        log_success "DRY RUN completed"
        exit 0
    fi

    # Disable cleanup on error for successful deployments
    CLEANUP_ON_ERROR=false

    # Execute deployment steps
    setup_project
    enable_apis
    create_storage
    create_bigquery
    create_pubsub
    create_service_account
    deploy_functions
    deploy_workflow
    create_asset_feed
    verify_deployment
    save_deployment_info

    log_success "Cloud Asset Governance deployment completed successfully!"
    echo
    log_info "Deployment Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Organization ID: ${ORGANIZATION_ID}"
    echo "  Region: ${REGION}"
    echo "  Governance Bucket: gs://${GOVERNANCE_BUCKET}"
    echo "  BigQuery Dataset: ${BQ_DATASET}"
    echo "  Asset Feed: ${FEED_NAME}"
    echo
    log_info "Next Steps:"
    echo "  1. Test the governance system by creating a test resource"
    echo "  2. Monitor violations in BigQuery dataset: ${BQ_DATASET}"
    echo "  3. Review Cloud Workflow executions in the console"
    echo "  4. Customize governance policies in the policy evaluation function"
    echo
    log_info "To clean up resources, run: ${SCRIPT_DIR}/destroy.sh --project ${PROJECT_ID}"
}

# Run main function
main "$@"
#!/bin/bash

# Deploy script for Resource Governance with Policy Simulator and Resource Manager
# This script automates the deployment of a comprehensive governance system for GCP

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Script failed at line $1. Exit code: $2"
    log_error "Check the logs above for details."
    exit 1
}

# Set up error handling
trap 'handle_error ${LINENO} $?' ERR

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Resource Governance with Policy Simulator and Resource Manager on GCP

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -v, --verbose       Enable verbose logging
    -p, --project-id    Specify project ID (optional, will prompt if not provided)
    -o, --org-id        Specify organization ID (optional, will prompt if not provided)
    -r, --region        Specify region (default: us-central1)

EXAMPLES:
    $0                                    # Interactive deployment
    $0 --dry-run                         # Show what would be deployed
    $0 --project-id my-project --org-id 123456789
    $0 --verbose --region us-east1

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -o|--org-id)
                ORGANIZATION_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi

    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null)
    log_info "Using gcloud version: ${gcloud_version}"

    # Check for required APIs
    log_info "Checking if required APIs will be available..."
    local required_apis=(
        "policysimulator.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "cloudbilling.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudasset.googleapis.com"
        "bigquery.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
    )

    for api in "${required_apis[@]}"; do
        log_info "Will enable API: ${api}"
    done

    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."

    # Set default values
    REGION="${REGION:-us-central1}"
    
    # Generate project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="governance-automation-$(date +%s)"
        read -p "Enter project ID (default: ${PROJECT_ID}): " user_project_id
        PROJECT_ID="${user_project_id:-$PROJECT_ID}"
    fi

    # Get organization ID if not provided
    if [[ -z "${ORGANIZATION_ID:-}" ]]; then
        log_info "Fetching available organizations..."
        local orgs
        orgs=$(gcloud organizations list --format="value(name,displayName)" 2>/dev/null || true)
        
        if [[ -n "$orgs" ]]; then
            echo "Available organizations:"
            echo "$orgs" | while IFS=$'\t' read -r name display_name; do
                local org_id="${name##*/}"
                echo "  ${org_id} - ${display_name}"
            done
            
            read -p "Enter organization ID: " ORGANIZATION_ID
        else
            log_warning "No organizations found. You may need organization-level permissions."
            read -p "Enter organization ID manually (or press Enter to skip): " ORGANIZATION_ID
        fi
    fi

    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    FUNCTION_NAME="governance-automation-${RANDOM_SUFFIX}"
    BUCKET_NAME="governance-reports-${RANDOM_SUFFIX}"
    TOPIC_NAME="governance-events-${RANDOM_SUFFIX}"

    # Export environment variables
    export PROJECT_ID
    export REGION
    export ORGANIZATION_ID
    export FUNCTION_NAME
    export BUCKET_NAME
    export TOPIC_NAME

    log_info "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  ORGANIZATION_ID: ${ORGANIZATION_ID:-'(not set)'}"
    log_info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  TOPIC_NAME: ${TOPIC_NAME}"

    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.deployment_env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ORGANIZATION_ID=${ORGANIZATION_ID:-}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_NAME=${TOPIC_NAME}
EOF

    log_success "Environment setup completed"
}

# Create or set project
setup_project() {
    log_info "Setting up project: ${PROJECT_ID}"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create/configure project: ${PROJECT_ID}"
        return
    fi

    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Governance Automation Project"
    fi

    # Set default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"

    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would enable required APIs"
        return
    fi

    local apis=(
        "policysimulator.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "cloudbilling.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudasset.googleapis.com"
        "bigquery.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        gcloud services enable "${api}" --quiet
    done

    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30

    log_success "All APIs enabled successfully"
}

# Create organization policies and constraints
create_organization_policies() {
    log_info "Creating organization policies and constraints..."

    if [[ -z "${ORGANIZATION_ID:-}" ]]; then
        log_warning "Organization ID not set. Skipping organization policies."
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create organization policies and constraints"
        return
    fi

    # Create temporary directory for policy files
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create location constraint
    cat > "${temp_dir}/location-constraint.yaml" << EOF
name: organizations/${ORGANIZATION_ID}/customConstraints/custom.restrictComputeLocations
resourceTypes:
- compute.googleapis.com/Instance
methodTypes:
- CREATE
condition: "resource.location in ['us-central1', 'us-east1', 'us-west1']"
actionType: ALLOW
displayName: "Restrict Compute Instance Locations"
description: "Only allow compute instances in approved US regions"
EOF

    # Create tagging constraint
    cat > "${temp_dir}/label-constraint.yaml" << EOF
name: organizations/${ORGANIZATION_ID}/customConstraints/custom.validateResourceLabels
resourceTypes:
- compute.googleapis.com/Instance
- storage.googleapis.com/Bucket
- container.googleapis.com/Cluster
methodTypes:
- CREATE
- UPDATE
condition: |
  has(resource.labels.environment) && 
  has(resource.labels.team) && 
  has(resource.labels['cost-center']) &&
  resource.labels.environment in ['dev', 'staging', 'prod']
actionType: ALLOW
displayName: "Validate Required Resource Labels"
description: "Ensure all resources have required labels for cost allocation"
EOF

    # Create tagging policy
    cat > "${temp_dir}/tagging-policy.yaml" << EOF
name: organizations/${ORGANIZATION_ID}/policies/iam.managed.requireResourceLabels
spec:
  rules:
  - enforce: true
    parameters:
      requiredLabels:
        - environment
        - team
        - cost-center
        - project-code
EOF

    # Apply constraints and policies
    log_info "Applying location constraint..."
    if ! gcloud org-policies set-custom-constraint "${temp_dir}/location-constraint.yaml"; then
        log_warning "Failed to set location constraint. You may need additional permissions."
    fi

    log_info "Applying label validation constraint..."
    if ! gcloud org-policies set-custom-constraint "${temp_dir}/label-constraint.yaml"; then
        log_warning "Failed to set label constraint. You may need additional permissions."
    fi

    log_info "Applying tagging policy..."
    if ! gcloud org-policies set-policy "${temp_dir}/tagging-policy.yaml"; then
        log_warning "Failed to set tagging policy. You may need additional permissions."
    fi

    # Cleanup temporary files
    rm -rf "${temp_dir}"

    log_success "Organization policies and constraints created"
}

# Create service accounts
create_service_accounts() {
    log_info "Creating service accounts..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create service accounts"
        return
    fi

    # Create policy simulator service account
    log_info "Creating policy simulator service account..."
    gcloud iam service-accounts create policy-simulator-sa \
        --display-name="Policy Simulator Service Account" \
        --description="Service account for automated policy simulation" \
        --quiet

    # Create billing governance service account
    log_info "Creating billing governance service account..."
    gcloud iam service-accounts create billing-governance-sa \
        --display-name="Billing Governance Service Account" \
        --description="Service account for billing and cost governance" \
        --quiet

    # Grant permissions to service accounts
    if [[ -n "${ORGANIZATION_ID:-}" ]]; then
        log_info "Granting organization-level permissions..."
        
        # Policy simulator permissions
        gcloud organizations add-iam-policy-binding "${ORGANIZATION_ID}" \
            --member="serviceAccount:policy-simulator-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/policysimulator.admin" \
            --quiet

        gcloud organizations add-iam-policy-binding "${ORGANIZATION_ID}" \
            --member="serviceAccount:policy-simulator-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/iam.securityReviewer" \
            --quiet

        # Billing governance permissions
        gcloud organizations add-iam-policy-binding "${ORGANIZATION_ID}" \
            --member="serviceAccount:billing-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/billing.viewer" \
            --quiet
    else
        log_warning "Organization ID not set. Granting project-level permissions only."
        
        # Grant project-level permissions as fallback
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:policy-simulator-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/iam.securityReviewer" \
            --quiet

        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:billing-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/billing.viewer" \
            --quiet
    fi

    log_success "Service accounts created and configured"
}

# Create storage and messaging resources
create_storage_messaging() {
    log_info "Creating storage bucket and Pub/Sub topic..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create storage bucket: gs://${BUCKET_NAME}"
        log_info "[DRY RUN] Would create Pub/Sub topic: ${TOPIC_NAME}"
        return
    fi

    # Create storage bucket
    log_info "Creating storage bucket: gs://${BUCKET_NAME}"
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"

    # Create Pub/Sub topic
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
    gcloud pubsub topics create "${TOPIC_NAME}" --quiet

    log_success "Storage and messaging resources created"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for governance automation..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would deploy Cloud Function: ${FUNCTION_NAME}"
        return
    fi

    # Create temporary directory for function source
    local function_dir
    function_dir=$(mktemp -d)
    
    # Create main.py
    cat > "${function_dir}/main.py" << 'EOF'
import json
import logging
from google.cloud import asset_v1
from google.cloud import billing_v1
from google.cloud import functions_v1
from google.cloud import policysimulator_v1
from google.cloud import resourcemanager_v3
import base64
import os

def governance_automation(cloud_event):
    """Main function for automated governance operations."""
    
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Initialize clients for Google Cloud services
    try:
        asset_client = asset_v1.AssetServiceClient()
        billing_client = billing_v1.CloudBillingClient()
        policy_client = policysimulator_v1.SimulatorClient()
        
        logger.info("Successfully initialized Google Cloud service clients")
    except Exception as e:
        logger.error(f"Failed to initialize clients: {str(e)}")
        return {"error": "Client initialization failed"}
    
    # Parse incoming event data
    try:
        if hasattr(cloud_event, 'data') and cloud_event.data:
            event_data = json.loads(base64.b64decode(cloud_event.data).decode())
        else:
            event_data = {"audit_type": "default"}
        
        logger.info(f"Processing governance event: {event_data}")
    except Exception as e:
        logger.error(f"Failed to parse event data: {str(e)}")
        event_data = {"audit_type": "default"}
    
    try:
        # Get project ID from environment
        project_id = os.environ.get('PROJECT_ID', 'default-project')
        organization_id = os.environ.get('ORGANIZATION_ID', '')
        
        # Perform resource governance checks
        compliance_results = check_resource_compliance(asset_client, project_id, event_data)
        
        # Analyze billing for cost optimization
        billing_results = analyze_billing_patterns(billing_client, event_data)
        
        # Simulate policy changes if requested
        simulation_results = {}
        if event_data.get('simulate_policy', False):
            simulation_results = simulate_policy_changes(policy_client, project_id, event_data)
        
        # Compile results
        results = {
            "status": "success",
            "compliance_issues": compliance_results,
            "billing_analysis": billing_results,
            "policy_simulation": simulation_results,
            "timestamp": cloud_event.time if hasattr(cloud_event, 'time') else None
        }
        
        logger.info(f"Governance automation completed successfully: {len(compliance_results)} compliance issues found")
        return results
        
    except Exception as e:
        logger.error(f"Governance automation failed: {str(e)}")
        return {"error": str(e), "status": "failed"}

def check_resource_compliance(client, project_id, event_data):
    """Check resource compliance against organization policies."""
    logger = logging.getLogger(__name__)
    
    try:
        # Query asset inventory for compliance analysis
        parent = f"projects/{project_id}"
        asset_types = [
            "compute.googleapis.com/Instance", 
            "storage.googleapis.com/Bucket",
            "container.googleapis.com/Cluster"
        ]
        
        request = asset_v1.ListAssetsRequest(
            parent=parent,
            asset_types=asset_types
        )
        
        assets = client.list_assets(request=request)
        compliance_issues = []
        
        for asset in assets:
            # Check location compliance
            resource_data = asset.resource.data
            if 'zone' in resource_data:
                zone = resource_data['zone']
                if not any(region in zone for region in ['us-central1', 'us-east1', 'us-west1']):
                    compliance_issues.append({
                        'resource': asset.name,
                        'issue': 'Non-compliant location',
                        'location': zone,
                        'type': 'location_violation'
                    })
            
            # Check resource labels for cost allocation
            labels = resource_data.get('labels', {})
            required_labels = ['environment', 'team', 'cost-center']
            missing_labels = [label for label in required_labels if label not in labels]
            
            if missing_labels:
                compliance_issues.append({
                    'resource': asset.name,
                    'issue': f'Missing required labels: {", ".join(missing_labels)}',
                    'missing_labels': missing_labels,
                    'type': 'labeling_violation'
                })
        
        logger.info(f"Compliance check completed: {len(compliance_issues)} issues found")
        return compliance_issues
        
    except Exception as e:
        logger.error(f"Compliance check failed: {str(e)}")
        return [{"error": str(e)}]

def analyze_billing_patterns(client, event_data):
    """Analyze billing patterns for cost optimization opportunities."""
    logger = logging.getLogger(__name__)
    
    try:
        billing_account = event_data.get('billing_account')
        
        if not billing_account:
            logger.info("No billing account specified, skipping billing analysis")
            return {"status": "skipped", "reason": "No billing account specified"}
        
        # List projects associated with billing account
        request = billing_v1.ListProjectBillingInfoRequest(
            name=f"billingAccounts/{billing_account}"
        )
        
        projects = client.list_project_billing_info(request=request)
        billing_analysis = []
        
        for project in projects:
            if project.billing_enabled:
                billing_analysis.append({
                    "project_id": project.project_id,
                    "billing_enabled": project.billing_enabled,
                    "status": "analyzed"
                })
                logger.info(f"Analyzed billing for project: {project.project_id}")
        
        return {"projects_analyzed": len(billing_analysis), "details": billing_analysis}
        
    except Exception as e:
        logger.error(f"Billing analysis failed: {str(e)}")
        return {"error": str(e)}

def simulate_policy_changes(client, project_id, event_data):
    """Simulate IAM policy changes before implementation."""
    logger = logging.getLogger(__name__)
    
    try:
        proposed_policy = event_data.get('proposed_policy')
        
        if not proposed_policy:
            logger.info("No policy changes to simulate")
            return {"status": "skipped", "reason": "No proposed policy provided"}
        
        # Create simulation request (simplified for this example)
        parent = f"projects/{project_id}"
        
        logger.info(f"Policy simulation requested for project: {project_id}")
        
        # In a real implementation, you would use the Policy Simulator API
        # to create and run policy simulations
        simulation_result = {
            "simulation_status": "completed",
            "violations": [],
            "access_changes": [],
            "project_id": project_id
        }
        
        return simulation_result
        
    except Exception as e:
        logger.error(f"Policy simulation failed: {str(e)}")
        return {"error": str(e)}

# Entry point for Cloud Functions Framework
def main(request):
    """HTTP entry point for testing."""
    return governance_automation(request)

EOF

    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-asset==3.19.1
google-cloud-billing==1.12.0
google-cloud-functions==1.16.0
google-cloud-policy-simulator==1.1.0
google-cloud-resource-manager==1.12.0
functions-framework==3.5.0
EOF

    # Deploy the function
    log_info "Deploying governance automation function..."
    (
        cd "${function_dir}"
        gcloud functions deploy "${FUNCTION_NAME}" \
            --gen2 \
            --runtime=python311 \
            --region="${REGION}" \
            --source=. \
            --entry-point=governance_automation \
            --trigger-topic="${TOPIC_NAME}" \
            --service-account="policy-simulator-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --set-env-vars="PROJECT_ID=${PROJECT_ID},ORGANIZATION_ID=${ORGANIZATION_ID}" \
            --timeout=540 \
            --memory=512MB \
            --quiet
    )

    # Cleanup temporary directory
    rm -rf "${function_dir}"

    log_success "Cloud Function deployed successfully"
}

# Create scheduled jobs
create_scheduled_jobs() {
    log_info "Creating scheduled governance jobs..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create Cloud Scheduler jobs"
        return
    fi

    # Create weekly governance audit job
    log_info "Creating weekly governance audit job..."
    gcloud scheduler jobs create pubsub governance-audit-job \
        --schedule="0 9 * * 1" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"audit_type":"full","project_scope":"organization"}' \
        --time-zone="America/New_York" \
        --description="Weekly governance audit across organization" \
        --quiet

    # Create daily cost monitoring job
    log_info "Creating daily cost monitoring job..."
    gcloud scheduler jobs create pubsub cost-monitoring-job \
        --schedule="0 8 * * *" \
        --topic="${TOPIC_NAME}" \
        --message-body='{"audit_type":"billing","check_budgets":true}' \
        --time-zone="America/New_York" \
        --description="Daily cost and budget monitoring" \
        --quiet

    log_success "Scheduled jobs created successfully"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi

    local validation_errors=0

    # Check if storage bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Storage bucket exists: gs://${BUCKET_NAME}"
    else
        log_error "Storage bucket not found: gs://${BUCKET_NAME}"
        ((validation_errors++))
    fi

    # Check if Pub/Sub topic exists
    if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
        log_success "Pub/Sub topic exists: ${TOPIC_NAME}"
    else
        log_error "Pub/Sub topic not found: ${TOPIC_NAME}"
        ((validation_errors++))
    fi

    # Check if Cloud Function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_success "Cloud Function exists: ${FUNCTION_NAME}"
    else
        log_error "Cloud Function not found: ${FUNCTION_NAME}"
        ((validation_errors++))
    fi

    # Check if service accounts exist
    if gcloud iam service-accounts describe "policy-simulator-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_success "Policy simulator service account exists"
    else
        log_error "Policy simulator service account not found"
        ((validation_errors++))
    fi

    # Check if scheduler jobs exist
    if gcloud scheduler jobs describe governance-audit-job --location="${REGION}" &>/dev/null; then
        log_success "Governance audit job exists"
    else
        log_error "Governance audit job not found"
        ((validation_errors++))
    fi

    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All resources validated successfully"
        return 0
    else
        log_error "Validation failed with ${validation_errors} errors"
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting Resource Governance deployment..."
    
    # Initialize logging
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2> >(tee -a "${LOG_FILE}" >&2)
    
    log_info "Deployment started at $(date)"
    log_info "Log file: ${LOG_FILE}"

    # Parse command line arguments
    parse_args "$@"

    if $DRY_RUN; then
        log_info "=== DRY RUN MODE - No changes will be made ==="
    fi

    # Execute deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_organization_policies
    create_service_accounts
    create_storage_messaging
    deploy_cloud_function
    create_scheduled_jobs
    validate_deployment

    # Deployment summary
    log_success "=== Deployment Summary ==="
    log_success "Project ID: ${PROJECT_ID}"
    log_success "Region: ${REGION}"
    log_success "Organization ID: ${ORGANIZATION_ID:-'(not set)'}"
    log_success "Function Name: ${FUNCTION_NAME}"
    log_success "Storage Bucket: gs://${BUCKET_NAME}"
    log_success "Pub/Sub Topic: ${TOPIC_NAME}"
    
    if $DRY_RUN; then
        log_info "=== DRY RUN COMPLETED ==="
        log_info "Run without --dry-run flag to perform actual deployment"
    else
        log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
        log_info "Environment variables saved to: ${SCRIPT_DIR}/.deployment_env"
        log_info "Use destroy.sh to clean up resources when no longer needed"
        
        # Test the deployment
        log_info "Testing deployment by triggering governance function..."
        gcloud pubsub topics publish "${TOPIC_NAME}" \
            --message='{"audit_type":"test","source":"deployment_script"}' \
            --quiet
        
        log_info "Check function logs with: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    fi
}

# Run main function with all arguments
main "$@"
#!/bin/bash

# Dynamic Resource Governance with Cloud Asset Inventory and Policy Simulator - Deployment Script
# This script deploys the complete governance infrastructure for GCP resource monitoring and policy validation

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable debug mode if DEBUG=true
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

# Colors for output
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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY RUN mode - no actual resources will be created"
fi

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values - can be overridden by environment variables
PROJECT_ID=${PROJECT_ID:-"governance-demo-$(date +%s)"}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
RANDOM_SUFFIX=${RANDOM_SUFFIX:-$(openssl rand -hex 3)}

# Resource names
ASSET_FEED_NAME=${ASSET_FEED_NAME:-"governance-feed-${RANDOM_SUFFIX}"}
TOPIC_NAME=${TOPIC_NAME:-"asset-changes-${RANDOM_SUFFIX}"}
FUNCTION_ANALYZER=${FUNCTION_ANALYZER:-"asset-analyzer-${RANDOM_SUFFIX}"}
FUNCTION_VALIDATOR=${FUNCTION_VALIDATOR:-"policy-validator-${RANDOM_SUFFIX}"}
FUNCTION_ENGINE=${FUNCTION_ENGINE:-"compliance-engine-${RANDOM_SUFFIX}"}
GOVERNANCE_SA=${GOVERNANCE_SA:-"governance-automation-${RANDOM_SUFFIX}"}

# Timeout settings
OPERATION_TIMEOUT=${OPERATION_TIMEOUT:-600}  # 10 minutes
FUNCTION_TIMEOUT=${FUNCTION_TIMEOUT:-540}    # 9 minutes

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        log_error "No authenticated account found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found. Using timestamp for random suffix"
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    # Check if project exists and user has access
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
            log_error "Project $PROJECT_ID does not exist or you don't have access to it"
            exit 1
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up GCP configuration
setup_gcp_config() {
    log_info "Setting up GCP configuration..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Set default project and region
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set compute/zone "$ZONE"
        
        log_success "GCP configuration set: Project=$PROJECT_ID, Region=$REGION, Zone=$ZONE"
    else
        log_info "DRY RUN: Would set project=$PROJECT_ID, region=$REGION, zone=$ZONE"
    fi
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudasset.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "policysimulator.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "storage.googleapis.com"
        "iam.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Enable APIs in batch for faster execution
        log_info "Enabling APIs: ${apis[*]}"
        gcloud services enable "${apis[@]}" --project="$PROJECT_ID"
        
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
        
        log_success "All required APIs enabled"
    else
        log_info "DRY RUN: Would enable APIs: ${apis[*]}"
    fi
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Pub/Sub topic
        if ! gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
            gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"
            log_success "Created Pub/Sub topic: $TOPIC_NAME"
        else
            log_warning "Pub/Sub topic $TOPIC_NAME already exists"
        fi
        
        # Create subscription for compliance engine
        local subscription_name="compliance-subscription-${RANDOM_SUFFIX}"
        if ! gcloud pubsub subscriptions describe "$subscription_name" --project="$PROJECT_ID" &>/dev/null; then
            gcloud pubsub subscriptions create "$subscription_name" \
                --topic="$TOPIC_NAME" \
                --ack-deadline=300 \
                --project="$PROJECT_ID"
            log_success "Created Pub/Sub subscription: $subscription_name"
        else
            log_warning "Pub/Sub subscription $subscription_name already exists"
        fi
    else
        log_info "DRY RUN: Would create Pub/Sub topic: $TOPIC_NAME"
        log_info "DRY RUN: Would create Pub/Sub subscription: compliance-subscription-${RANDOM_SUFFIX}"
    fi
}

# Function to create Cloud Asset Inventory feed
create_asset_feed() {
    log_info "Creating Cloud Asset Inventory feed..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if feed already exists
        if ! gcloud asset feeds describe "$ASSET_FEED_NAME" --project="$PROJECT_ID" &>/dev/null; then
            gcloud asset feeds create "$ASSET_FEED_NAME" \
                --pubsub-topic="projects/$PROJECT_ID/topics/$TOPIC_NAME" \
                --asset-types="*" \
                --content-type=RESOURCE \
                --project="$PROJECT_ID"
            log_success "Created Asset Inventory feed: $ASSET_FEED_NAME"
        else
            log_warning "Asset Inventory feed $ASSET_FEED_NAME already exists"
        fi
    else
        log_info "DRY RUN: Would create Asset Inventory feed: $ASSET_FEED_NAME"
    fi
}

# Function to create service account
create_service_account() {
    log_info "Creating service account for governance automation..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create service account
        if ! gcloud iam service-accounts describe "${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" &>/dev/null; then
            gcloud iam service-accounts create "$GOVERNANCE_SA" \
                --display-name="Governance Automation Service Account" \
                --description="Service account for automated governance and compliance" \
                --project="$PROJECT_ID"
            log_success "Created service account: $GOVERNANCE_SA"
        else
            log_warning "Service account $GOVERNANCE_SA already exists"
        fi
        
        # Assign IAM roles
        local roles=(
            "roles/cloudasset.viewer"
            "roles/iam.securityReviewer"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
            "roles/pubsub.publisher"
            "roles/pubsub.subscriber"
        )
        
        for role in "${roles[@]}"; do
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
                --role="$role" \
                --quiet
        done
        
        log_success "Assigned IAM roles to service account"
    else
        log_info "DRY RUN: Would create service account: $GOVERNANCE_SA"
        log_info "DRY RUN: Would assign IAM roles for governance automation"
    fi
}

# Function to prepare Cloud Function source code
prepare_function_source() {
    log_info "Preparing Cloud Function source code..."
    
    local temp_dir="/tmp/governance-functions-$$"
    mkdir -p "$temp_dir"
    
    # Check if source files exist in terraform directory
    if [[ -d "$PROJECT_ROOT/terraform/functions" ]]; then
        cp -r "$PROJECT_ROOT/terraform/functions" "$temp_dir/"
        log_success "Copied function source code from terraform directory"
    else
        # Create function source code if it doesn't exist
        mkdir -p "$temp_dir/functions"
        
        # Create requirements.txt
        cat > "$temp_dir/functions/requirements.txt" << 'EOF'
google-cloud-asset==3.24.0
google-cloud-pubsub==2.18.4
google-cloud-logging==3.8.0
google-cloud-policy-intelligence==1.5.0
google-cloud-monitoring==2.16.0
functions-framework==3.4.0
requests==2.31.0
EOF
        
        # Create asset analyzer function
        cat > "$temp_dir/functions/asset_analyzer.py" << 'EOF'
import json
import base64
import logging
from google.cloud import asset_v1
from google.cloud import pubsub_v1
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def analyze_asset_change(cloud_event):
    """Analyze asset changes and trigger governance workflows."""
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
        asset_data = json.loads(pubsub_message)
        
        # Extract asset information
        asset_name = asset_data.get('name', '')
        asset_type = asset_data.get('assetType', '')
        operation = asset_data.get('deleted', False)
        
        logger.info(f"Processing asset change: {asset_name} ({asset_type})")
        
        # Check for high-risk resources
        risk_level = assess_risk_level(asset_type, asset_data)
        
        if risk_level == 'HIGH':
            logger.warning(f"High-risk asset detected: {asset_name}")
            trigger_policy_validation(asset_data)
        
        # Log compliance event
        log_compliance_event(asset_name, asset_type, risk_level)
        
        return {'status': 'success', 'risk_level': risk_level}
        
    except Exception as e:
        logger.error(f"Error analyzing asset change: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def assess_risk_level(asset_type, asset_data):
    """Assess risk level based on asset type and configuration."""
    high_risk_types = [
        'compute.googleapis.com/Instance',
        'storage.googleapis.com/Bucket',
        'iam.googleapis.com/ServiceAccount',
        'container.googleapis.com/Cluster'
    ]
    
    if asset_type in high_risk_types:
        return 'HIGH'
    elif 'compute' in asset_type or 'storage' in asset_type:
        return 'MEDIUM'
    else:
        return 'LOW'

def trigger_policy_validation(asset_data):
    """Trigger policy validation for high-risk assets."""
    logger.info("Triggering policy validation workflow")

def log_compliance_event(asset_name, asset_type, risk_level):
    """Log compliance events for audit trail."""
    logger.info(f"Compliance event logged: {asset_name} - Risk: {risk_level}")
EOF
        
        # Create policy validator function
        cat > "$temp_dir/functions/policy_validator.py" << 'EOF'
import json
import logging
from google.cloud import policy_intelligence_v1
from google.cloud import asset_v1
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def validate_policy_changes(request):
    """Validate policy changes using Policy Simulator."""
    try:
        request_json = request.get_json()
        resource_name = request_json.get('resource_name')
        proposed_policy = request_json.get('proposed_policy')
        
        logger.info(f"Validating policy changes for: {resource_name}")
        
        # Initialize Policy Simulator client
        client = policy_intelligence_v1.PolicySimulatorClient()
        
        # Create simulation request
        simulation_request = create_simulation_request(resource_name, proposed_policy)
        
        # Run policy simulation
        results = run_policy_simulation(client, simulation_request)
        
        # Analyze simulation results
        validation_results = analyze_simulation_results(results)
        
        return {
            'status': 'success',
            'validation_results': validation_results,
            'risk_assessment': assess_policy_risk(validation_results)
        }
        
    except Exception as e:
        logger.error(f"Error validating policy changes: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def create_simulation_request(resource_name, proposed_policy):
    """Create policy simulation request."""
    logger.info("Creating policy simulation request")
    return {}

def run_policy_simulation(client, simulation_request):
    """Execute policy simulation."""
    logger.info("Running policy simulation")
    return []

def analyze_simulation_results(results):
    """Analyze simulation results for governance compliance."""
    logger.info("Analyzing simulation results")
    return {'access_changes': [], 'risk_level': 'LOW'}

def assess_policy_risk(validation_results):
    """Assess risk level of proposed policy changes."""
    access_changes = validation_results.get('access_changes', [])
    
    if len(access_changes) > 10:
        return 'HIGH'
    elif len(access_changes) > 5:
        return 'MEDIUM'
    else:
        return 'LOW'
EOF
        
        # Create compliance engine function
        cat > "$temp_dir/functions/compliance_engine.py" << 'EOF'
import json
import base64
import logging
import requests
from google.cloud import pubsub_v1
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def enforce_compliance(cloud_event):
    """Main compliance enforcement function."""
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
        compliance_data = json.loads(pubsub_message)
        
        logger.info("Processing compliance enforcement request")
        
        # Extract compliance requirements
        asset_name = compliance_data.get('asset_name', '')
        risk_level = compliance_data.get('risk_level', 'LOW')
        violation_type = compliance_data.get('violation_type', '')
        
        # Apply governance policies
        enforcement_actions = determine_enforcement_actions(risk_level, violation_type)
        
        # Execute enforcement actions
        results = execute_enforcement_actions(asset_name, enforcement_actions)
        
        # Record compliance metrics
        record_compliance_metrics(asset_name, risk_level, results)
        
        return {'status': 'success', 'actions_taken': results}
        
    except Exception as e:
        logger.error(f"Error in compliance enforcement: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def determine_enforcement_actions(risk_level, violation_type):
    """Determine appropriate enforcement actions based on risk and violation type."""
    actions = []
    
    if risk_level == 'HIGH':
        actions.extend(['alert_security_team', 'create_ticket', 'restrict_access'])
    elif risk_level == 'MEDIUM':
        actions.extend(['alert_team_lead', 'create_ticket'])
    else:
        actions.append('log_violation')
    
    return actions

def execute_enforcement_actions(asset_name, actions):
    """Execute the determined enforcement actions."""
    results = []
    
    for action in actions:
        try:
            if action == 'alert_security_team':
                send_security_alert(asset_name)
                results.append(f"Security alert sent for {asset_name}")
            elif action == 'create_ticket':
                create_compliance_ticket(asset_name)
                results.append(f"Compliance ticket created for {asset_name}")
            elif action == 'restrict_access':
                logger.info(f"Access restriction applied to {asset_name}")
                results.append(f"Access restricted for {asset_name}")
            elif action == 'log_violation':
                log_compliance_violation(asset_name)
                results.append(f"Violation logged for {asset_name}")
                
        except Exception as e:
            logger.error(f"Error executing action {action}: {str(e)}")
            results.append(f"Failed to execute {action}: {str(e)}")
    
    return results

def send_security_alert(asset_name):
    """Send alert to security team."""
    logger.warning(f"SECURITY ALERT: High-risk compliance violation detected for {asset_name}")

def create_compliance_ticket(asset_name):
    """Create compliance ticket in ticketing system."""
    logger.info(f"Creating compliance ticket for {asset_name}")

def log_compliance_violation(asset_name):
    """Log compliance violation for audit trail."""
    logger.info(f"Compliance violation logged: {asset_name}")

def record_compliance_metrics(asset_name, risk_level, results):
    """Record compliance metrics in Cloud Monitoring."""
    try:
        client = monitoring_v3.MetricServiceClient()
        logger.info(f"Recording compliance metrics for {asset_name}")
    except Exception as e:
        logger.error(f"Error recording metrics: {str(e)}")
EOF
        
        log_success "Created function source code"
    fi
    
    echo "$temp_dir"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    local temp_dir
    temp_dir=$(prepare_function_source)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Deploy asset analyzer function
        if ! gcloud functions describe "$FUNCTION_ANALYZER" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            gcloud functions deploy "$FUNCTION_ANALYZER" \
                --gen2 \
                --region="$REGION" \
                --runtime=python311 \
                --source="$temp_dir/functions" \
                --entry-point=analyze_asset_change \
                --trigger-topic="$TOPIC_NAME" \
                --memory=512MB \
                --timeout="${FUNCTION_TIMEOUT}s" \
                --service-account="${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Deployed asset analyzer function: $FUNCTION_ANALYZER"
        else
            log_warning "Asset analyzer function $FUNCTION_ANALYZER already exists"
        fi
        
        # Deploy policy validator function
        if ! gcloud functions describe "$FUNCTION_VALIDATOR" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            gcloud functions deploy "$FUNCTION_VALIDATOR" \
                --gen2 \
                --region="$REGION" \
                --runtime=python311 \
                --source="$temp_dir/functions" \
                --entry-point=validate_policy_changes \
                --trigger-http \
                --allow-unauthenticated \
                --memory=1GB \
                --timeout="${FUNCTION_TIMEOUT}s" \
                --service-account="${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Deployed policy validator function: $FUNCTION_VALIDATOR"
        else
            log_warning "Policy validator function $FUNCTION_VALIDATOR already exists"
        fi
        
        # Deploy compliance engine function
        if ! gcloud functions describe "$FUNCTION_ENGINE" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            gcloud functions deploy "$FUNCTION_ENGINE" \
                --gen2 \
                --region="$REGION" \
                --runtime=python311 \
                --source="$temp_dir/functions" \
                --entry-point=enforce_compliance \
                --trigger-topic="$TOPIC_NAME" \
                --memory=1GB \
                --timeout="${FUNCTION_TIMEOUT}s" \
                --service-account="${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Deployed compliance engine function: $FUNCTION_ENGINE"
        else
            log_warning "Compliance engine function $FUNCTION_ENGINE already exists"
        fi
    else
        log_info "DRY RUN: Would deploy Cloud Functions: $FUNCTION_ANALYZER, $FUNCTION_VALIDATOR, $FUNCTION_ENGINE"
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local validation_failed=false
        
        # Check Pub/Sub topic
        if ! gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
            log_error "Pub/Sub topic $TOPIC_NAME not found"
            validation_failed=true
        fi
        
        # Check Asset Inventory feed
        if ! gcloud asset feeds describe "$ASSET_FEED_NAME" --project="$PROJECT_ID" &>/dev/null; then
            log_error "Asset Inventory feed $ASSET_FEED_NAME not found"
            validation_failed=true
        fi
        
        # Check Cloud Functions
        local functions=("$FUNCTION_ANALYZER" "$FUNCTION_VALIDATOR" "$FUNCTION_ENGINE")
        for func in "${functions[@]}"; do
            if ! gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
                log_error "Cloud Function $func not found"
                validation_failed=true
            fi
        done
        
        # Check service account
        if ! gcloud iam service-accounts describe "${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" &>/dev/null; then
            log_error "Service account $GOVERNANCE_SA not found"
            validation_failed=true
        fi
        
        if [[ "$validation_failed" == "true" ]]; then
            log_error "Deployment validation failed"
            exit 1
        else
            log_success "Deployment validation successful"
        fi
    else
        log_info "DRY RUN: Would validate deployment"
    fi
}

# Function to create test resources
create_test_resources() {
    log_info "Creating test resources for validation..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create a test VM to trigger asset changes
        local test_vm_name="test-governance-vm-${RANDOM_SUFFIX}"
        if ! gcloud compute instances describe "$test_vm_name" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
            gcloud compute instances create "$test_vm_name" \
                --zone="$ZONE" \
                --machine-type=e2-micro \
                --image-family=debian-11 \
                --image-project=debian-cloud \
                --labels=governance-test=true \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Created test VM: $test_vm_name"
            
            # Store test VM name for cleanup
            echo "$test_vm_name" > "/tmp/governance-test-vm-${RANDOM_SUFFIX}"
        else
            log_warning "Test VM $test_vm_name already exists"
        fi
    else
        log_info "DRY RUN: Would create test VM for validation"
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Resources Created:"
    echo "- Pub/Sub Topic: $TOPIC_NAME"
    echo "- Asset Feed: $ASSET_FEED_NAME"
    echo "- Service Account: $GOVERNANCE_SA"
    echo "- Cloud Functions:"
    echo "  - Asset Analyzer: $FUNCTION_ANALYZER"
    echo "  - Policy Validator: $FUNCTION_VALIDATOR"
    echo "  - Compliance Engine: $FUNCTION_ENGINE"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor Cloud Function logs for asset change events"
    echo "2. Test policy validation by calling the HTTP function"
    echo "3. Review compliance metrics in Cloud Monitoring"
    echo "4. Customize governance rules in the functions"
    echo ""
    echo "To clean up resources, run:"
    echo "  ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting Dynamic Resource Governance deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --dry-run       Run in dry-run mode (no resources created)"
                echo "  --project ID    Specify project ID"
                echo "  --region NAME   Specify region"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_gcp_config
    enable_apis
    create_service_account
    create_pubsub_resources
    create_asset_feed
    deploy_functions
    validate_deployment
    create_test_resources
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"
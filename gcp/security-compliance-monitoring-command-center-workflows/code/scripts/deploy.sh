#!/bin/bash

# Deploy script for GCP Security Compliance Monitoring with Security Command Center and Cloud Workflows
# This script implements the infrastructure from the recipe:
# "Implementing Automated Security Compliance Monitoring with Security Command Center and Cloud Workflows"

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_info "Please check the error messages above for troubleshooting"
    log_info "You may need to run the destroy script to clean up partially created resources"
    exit $exit_code
}

trap cleanup_on_error ERR

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_PREFIX="security-compliance"
readonly REGION="${REGION:-us-central1}"
readonly ZONE="${ZONE:-us-central1-a}"

# Check if running in dry-run mode
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Google Cloud CLI is not authenticated"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if required tools are available
    local required_tools=("openssl" "date")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique project ID
    export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
    export REGION
    export ZONE
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export TOPIC_NAME="security-findings-${random_suffix}"
    export WORKFLOW_NAME="security-compliance-workflow-${random_suffix}"
    export FUNCTION_NAME="security-processor-${random_suffix}"
    
    # Get organization ID if available
    export ORGANIZATION_ID
    ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
    
    if [[ -z "$ORGANIZATION_ID" ]]; then
        log_warning "No organization found. Some Security Command Center features may not be available."
    fi
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "Topic Name: $TOPIC_NAME"
    log_info "Function Name: $FUNCTION_NAME"
    
    log_success "Environment variables set"
}

# Function to create and configure project
create_project() {
    log_info "Creating Google Cloud project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create project: $PROJECT_ID"
        return 0
    fi
    
    # Create project
    if ! gcloud projects create "$PROJECT_ID" --name="Security Compliance Monitoring"; then
        log_error "Failed to create project: $PROJECT_ID"
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Link billing account if available
    local billing_account
    billing_account=$(gcloud billing accounts list --format="value(name)" --filter="open:true" --limit=1 2>/dev/null || echo "")
    
    if [[ -n "$billing_account" ]]; then
        log_info "Linking billing account: $billing_account"
        gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account"
    else
        log_warning "No billing account found. You may need to link one manually."
        log_info "Visit: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
    fi
    
    log_success "Project created and configured: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local required_apis=(
        "securitycenter.googleapis.com"
        "pubsub.googleapis.com"
        "workflows.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${required_apis[*]}"
        return 0
    fi
    
    for api in "${required_apis[@]}"; do
        log_info "Enabling API: $api"
        if ! gcloud services enable "$api" --project="$PROJECT_ID"; then
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Pub/Sub topic: $TOPIC_NAME"
        return 0
    fi
    
    # Create Pub/Sub topic
    if ! gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"; then
        log_error "Failed to create Pub/Sub topic: $TOPIC_NAME"
        exit 1
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions create "${TOPIC_NAME}-sub" \
        --topic="$TOPIC_NAME" \
        --project="$PROJECT_ID"; then
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    # Verify topic creation
    gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" > /dev/null
    
    log_success "Pub/Sub resources created successfully"
}

# Function to configure Security Command Center notification
configure_scc_notification() {
    log_info "Configuring Security Command Center notification..."
    
    if [[ -z "$ORGANIZATION_ID" ]]; then
        log_warning "Skipping Security Command Center configuration - no organization found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure SCC notification for organization: $ORGANIZATION_ID"
        return 0
    fi
    
    # Get project number for service account
    local project_number
    project_number=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
    
    # Create notification configuration
    if ! gcloud scc notifications create "${TOPIC_NAME}-notification" \
        --organization="$ORGANIZATION_ID" \
        --pubsub-topic="projects/$PROJECT_ID/topics/$TOPIC_NAME" \
        --description="Automated security findings notification" \
        --filter='state="ACTIVE"'; then
        log_warning "Failed to create SCC notification. This may require Security Command Center Premium."
    fi
    
    # Grant Security Command Center permission to publish to topic
    if ! gcloud pubsub topics add-iam-policy-binding "$TOPIC_NAME" \
        --member="serviceAccount:service-${project_number}@gcp-sa-securitycenter.iam.gserviceaccount.com" \
        --role="roles/pubsub.publisher" \
        --project="$PROJECT_ID"; then
        log_warning "Failed to grant SCC permissions. Manual configuration may be required."
    fi
    
    log_success "Security Command Center notification configured"
}

# Function to create Cloud Function
create_cloud_function() {
    log_info "Creating Cloud Function for security finding processing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud Function: $FUNCTION_NAME"
        return 0
    fi
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Cleanup function for temp directory
    cleanup_temp_dir() {
        rm -rf "$temp_dir"
    }
    trap cleanup_temp_dir EXIT
    
    # Create function requirements
    cat > "$temp_dir/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-workflows==1.14.0
google-cloud-logging==3.8.0
google-cloud-pubsub==2.18.4
EOF
    
    # Create function code
    cat > "$temp_dir/main.py" << 'EOF'
import functions_framework
import json
import base64
import logging
import os
from google.cloud import workflows_v1
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def process_security_finding(cloud_event):
    """Process security findings and trigger workflows."""
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        finding = json.loads(message_data.decode('utf-8'))
        
        # Extract finding details
        finding_id = finding.get('name', 'unknown')
        severity = finding.get('severity', 'LOW')
        category = finding.get('category', 'unknown')
        
        logger.info(f"Processing finding: {finding_id} with severity: {severity}")
        
        # Determine workflow based on severity
        workflow_name = determine_workflow(severity, category)
        
        if workflow_name:
            # Trigger appropriate workflow
            trigger_workflow(workflow_name, finding)
            
        return 'OK'
        
    except Exception as e:
        logger.error(f"Error processing security finding: {str(e)}")
        raise

def determine_workflow(severity, category):
    """Determine which workflow to trigger based on finding."""
    if severity in ['HIGH', 'CRITICAL']:
        return 'high-severity-workflow'
    elif severity == 'MEDIUM':
        return 'medium-severity-workflow'
    else:
        return 'low-severity-workflow'

def trigger_workflow(workflow_name, finding):
    """Trigger Cloud Workflow with finding data."""
    try:
        client = workflows_v1.WorkflowsClient()
        
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION', 'us-central1')
        
        # Prepare workflow input
        workflow_input = {
            'finding': finding,
            'timestamp': finding.get('eventTime', ''),
            'severity': finding.get('severity', 'LOW')
        }
        
        # Execute workflow
        parent = f"projects/{project_id}/locations/{region}/workflows/{workflow_name}"
        execution = workflows_v1.Execution(argument=json.dumps(workflow_input))
        
        operation = client.create_execution(
            parent=parent,
            execution=execution
        )
        
        logger.info(f"Triggered workflow: {workflow_name}")
    except Exception as e:
        logger.warning(f"Failed to trigger workflow {workflow_name}: {str(e)}")
EOF
    
    # Deploy the function
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=python311 \
        --source="$temp_dir" \
        --entry-point=process_security_finding \
        --trigger-topic="$TOPIC_NAME" \
        --region="$REGION" \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars="PROJECT_ID=$PROJECT_ID,REGION=$REGION" \
        --project="$PROJECT_ID"; then
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    log_success "Cloud Function deployed successfully"
}

# Function to create workflows
create_workflows() {
    log_info "Creating Cloud Workflows for security remediation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create workflows for security remediation"
        return 0
    fi
    
    # Create high-severity workflow
    create_high_severity_workflow
    
    # Create medium-severity workflow
    create_medium_severity_workflow
    
    # Create low-severity workflow
    create_low_severity_workflow
    
    log_success "All workflows created successfully"
}

# Function to create high-severity workflow
create_high_severity_workflow() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "$temp_dir/high-severity-workflow.yaml" << 'EOF'
main:
  params: [input]
  steps:
    - init:
        assign:
          - finding: ${input.finding}
          - severity: ${input.severity}
          - project_id: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
    
    - log_incident:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + project_id + "/logs/security-compliance"}
                severity: CRITICAL
                jsonPayload:
                  finding_id: ${finding.name}
                  severity: ${severity}
                  action: "high_severity_workflow_triggered"
    
    - assess_threat:
        assign:
          - requires_immediate_action: ${severity == "CRITICAL"}
          - requires_escalation: true
    
    - immediate_remediation:
        switch:
          - condition: ${requires_immediate_action}
            steps:
              - disable_compromised_resource:
                  call: execute_remediation
                  args:
                    action: "disable_resource"
                    resource: ${finding.resourceName}
    
    - notify_security_team:
        call: send_notification
        args:
          severity: ${severity}
          finding: ${finding}
          action_taken: "immediate_remediation"
    
    - escalate_to_incident_response:
        switch:
          - condition: ${requires_escalation}
            steps:
              - create_incident:
                  call: create_security_incident
                  args:
                    finding: ${finding}
                    severity: ${severity}

execute_remediation:
  params: [action, resource]
  steps:
    - log_action:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-actions"}
                severity: INFO
                jsonPayload:
                  action: ${action}
                  resource: ${resource}
                  timestamp: ${time.now()}

send_notification:
  params: [severity, finding, action_taken]
  steps:
    - send_alert:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-notifications"}
                severity: WARNING
                jsonPayload:
                  alert_type: "security_finding"
                  severity: ${severity}
                  finding_id: ${finding.name}
                  action_taken: ${action_taken}

create_security_incident:
  params: [finding, severity]
  steps:
    - log_incident:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-incidents"}
                severity: ERROR
                jsonPayload:
                  incident_type: "security_finding"
                  severity: ${severity}
                  finding_id: ${finding.name}
                  status: "created"
EOF
    
    gcloud workflows deploy high-severity-workflow \
        --source="$temp_dir/high-severity-workflow.yaml" \
        --location="$REGION" \
        --project="$PROJECT_ID"
    
    rm -rf "$temp_dir"
}

# Function to create medium-severity workflow
create_medium_severity_workflow() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "$temp_dir/medium-severity-workflow.yaml" << 'EOF'
main:
  params: [input]
  steps:
    - init:
        assign:
          - finding: ${input.finding}
          - severity: ${input.severity}
          - project_id: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
    
    - log_finding:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + project_id + "/logs/security-compliance"}
                severity: WARNING
                jsonPayload:
                  finding_id: ${finding.name}
                  severity: ${severity}
                  action: "medium_severity_workflow_triggered"
    
    - assess_risk:
        assign:
          - requires_notification: true
          - requires_tracking: true
    
    - create_remediation_ticket:
        call: create_tracking_entry
        args:
          finding: ${finding}
          priority: "medium"
    
    - notify_security_team:
        call: send_notification
        args:
          severity: ${severity}
          finding: ${finding}
          action_taken: "ticket_created"
    
    - schedule_follow_up:
        call: create_follow_up_task
        args:
          finding: ${finding}
          follow_up_hours: 24

create_tracking_entry:
  params: [finding, priority]
  steps:
    - log_tracking:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-tracking"}
                severity: INFO
                jsonPayload:
                  tracking_type: "remediation_ticket"
                  finding_id: ${finding.name}
                  priority: ${priority}
                  status: "created"

send_notification:
  params: [severity, finding, action_taken]
  steps:
    - send_alert:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-notifications"}
                severity: INFO
                jsonPayload:
                  alert_type: "security_finding"
                  severity: ${severity}
                  finding_id: ${finding.name}
                  action_taken: ${action_taken}

create_follow_up_task:
  params: [finding, follow_up_hours]
  steps:
    - schedule_task:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-tasks"}
                severity: INFO
                jsonPayload:
                  task_type: "follow_up"
                  finding_id: ${finding.name}
                  scheduled_hours: ${follow_up_hours}
                  status: "scheduled"
EOF
    
    gcloud workflows deploy medium-severity-workflow \
        --source="$temp_dir/medium-severity-workflow.yaml" \
        --location="$REGION" \
        --project="$PROJECT_ID"
    
    rm -rf "$temp_dir"
}

# Function to create low-severity workflow
create_low_severity_workflow() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "$temp_dir/low-severity-workflow.yaml" << 'EOF'
main:
  params: [input]
  steps:
    - init:
        assign:
          - finding: ${input.finding}
          - severity: ${input.severity}
          - project_id: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
    
    - log_finding:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + project_id + "/logs/security-compliance"}
                severity: INFO
                jsonPayload:
                  finding_id: ${finding.name}
                  severity: ${severity}
                  action: "low_severity_workflow_triggered"
    
    - assess_finding:
        assign:
          - requires_aggregation: true
          - requires_periodic_review: true
    
    - aggregate_for_reporting:
        call: aggregate_finding
        args:
          finding: ${finding}
          category: "low_severity_findings"
    
    - check_threshold:
        call: check_aggregation_threshold
        args:
          category: "low_severity_findings"
          threshold: 100
    
    - conditional_notification:
        switch:
          - condition: ${threshold_exceeded}
            steps:
              - notify_trend:
                  call: send_trend_notification
                  args:
                    category: "low_severity_findings"
                    count: ${finding_count}

aggregate_finding:
  params: [finding, category]
  steps:
    - log_aggregation:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-aggregation"}
                severity: INFO
                jsonPayload:
                  aggregation_type: ${category}
                  finding_id: ${finding.name}
                  timestamp: ${time.now()}

check_aggregation_threshold:
  params: [category, threshold]
  steps:
    - check_count:
        assign:
          - threshold_exceeded: false
          - finding_count: 0

send_trend_notification:
  params: [category, count]
  steps:
    - send_alert:
        call: http.post
        args:
          url: https://logging.googleapis.com/v2/entries:write
          auth:
            type: OAuth2
          body:
            entries:
              - logName: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/logs/security-trends"}
                severity: WARNING
                jsonPayload:
                  alert_type: "trend_notification"
                  category: ${category}
                  count: ${count}
                  message: "Low severity findings threshold exceeded"
EOF
    
    gcloud workflows deploy low-severity-workflow \
        --source="$temp_dir/low-severity-workflow.yaml" \
        --location="$REGION" \
        --project="$PROJECT_ID"
    
    rm -rf "$temp_dir"
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure monitoring and alerting"
        return 0
    fi
    
    # Create log-based metrics
    gcloud logging metrics create security_findings_processed \
        --description="Count of security findings processed" \
        --log-filter='resource.type="cloud_function" AND textPayload:"Processing finding"' \
        --project="$PROJECT_ID" || log_warning "Failed to create security_findings_processed metric"
    
    gcloud logging metrics create workflow_executions \
        --description="Count of workflow executions" \
        --log-filter='resource.type="workflows.googleapis.com/Workflow"' \
        --project="$PROJECT_ID" || log_warning "Failed to create workflow_executions metric"
    
    log_success "Monitoring configuration completed"
}

# Function to create compliance dashboard
create_compliance_dashboard() {
    log_info "Creating compliance dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create compliance dashboard"
        return 0
    fi
    
    # Create dashboard configuration
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "$temp_dir/compliance-dashboard.json" << EOF
{
  "displayName": "Security Compliance Dashboard - $PROJECT_ID",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Security Findings by Severity",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"cloud_function\"",
                "aggregation": {
                  "alignmentPeriod": "3600s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Workflow Execution Success Rate",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"workflows.googleapis.com/Workflow\"",
                "aggregation": {
                  "alignmentPeriod": "3600s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            }
          }
        }
      }
    ]
  }
}
EOF
    
    gcloud monitoring dashboards create \
        --config-from-file="$temp_dir/compliance-dashboard.json" \
        --project="$PROJECT_ID" || log_warning "Failed to create dashboard"
    
    rm -rf "$temp_dir"
    log_success "Compliance dashboard created"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run validation tests"
        return 0
    fi
    
    # Test Pub/Sub topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" > /dev/null 2>&1; then
        log_success "Pub/Sub topic validation passed"
    else
        log_error "Pub/Sub topic validation failed"
        return 1
    fi
    
    # Test Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" --project="$PROJECT_ID" > /dev/null 2>&1; then
        log_success "Cloud Function validation passed"
    else
        log_error "Cloud Function validation failed"
        return 1
    fi
    
    # Test workflows
    local workflows=("high-severity-workflow" "medium-severity-workflow" "low-severity-workflow")
    for workflow in "${workflows[@]}"; do
        if gcloud workflows describe "$workflow" --location="$REGION" --project="$PROJECT_ID" > /dev/null 2>&1; then
            log_success "Workflow $workflow validation passed"
        else
            log_error "Workflow $workflow validation failed"
            return 1
        fi
    done
    
    log_success "All validation tests passed"
}

# Function to display deployment summary
display_deployment_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Workflows: high-severity-workflow, medium-severity-workflow, low-severity-workflow"
    echo "=================================="
    echo ""
    log_info "Next Steps:"
    echo "1. Configure Security Command Center Premium (if available)"
    echo "2. Set up notification channels for alerting"
    echo "3. Test the system with sample security findings"
    echo "4. Review and customize workflow logic as needed"
    echo ""
    log_info "Access your resources:"
    echo "- Console: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    echo "- Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    echo "- Workflows: https://console.cloud.google.com/workflows/list?project=$PROJECT_ID"
    echo "- Monitoring: https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
    echo ""
    log_success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log_info "Starting GCP Security Compliance Monitoring deployment"
    log_info "Script version: 1.0"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    set_environment_variables
    create_project
    enable_apis
    create_pubsub_resources
    configure_scc_notification
    create_cloud_function
    create_workflows
    configure_monitoring
    create_compliance_dashboard
    run_validation_tests
    display_deployment_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
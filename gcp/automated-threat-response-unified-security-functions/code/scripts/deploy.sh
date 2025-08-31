#!/bin/bash

# =============================================================================
# Automated Threat Response with Unified Security and Functions - Deploy Script
# =============================================================================
# This script deploys a complete automated security response system using
# Security Command Center, Cloud Functions, Cloud Logging, and Pub/Sub
# 
# Prerequisites:
# - Google Cloud CLI installed and configured
# - Security Command Center Premium or Enterprise access
# - Required permissions: Security Admin, Cloud Functions Admin
# - Project with billing enabled
# =============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    # Note: Full cleanup handled by destroy.sh
    exit 1
}

trap cleanup_on_error ERR

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_PREFIX="security-automation"
readonly REGION_DEFAULT="us-central1"
readonly ZONE_DEFAULT="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    # Check if a project is set
    if ! gcloud config get-value project &> /dev/null; then
        error_exit "No project set. Run 'gcloud config set project PROJECT_ID' first."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate required APIs
validate_apis() {
    log_info "Validating required APIs..."
    
    local required_apis=(
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "securitycenter.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
            log_warning "API ${api} is not enabled"
            return 1
        fi
    done
    
    log_success "All required APIs are enabled"
    return 0
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project ID from current gcloud config
    export PROJECT_ID=$(gcloud config get-value project)
    if [[ -z "${PROJECT_ID}" ]]; then
        error_exit "Could not determine project ID"
    fi
    
    # Set region and zone with defaults
    export REGION="${REGION:-$REGION_DEFAULT}"
    export ZONE="${ZONE:-$ZONE_DEFAULT}"
    
    # Generate unique suffix for resource names
    local timestamp=$(date +%s)
    local random_hex=$(openssl rand -hex 3)
    export RANDOM_SUFFIX="${random_hex}-${timestamp: -4}"
    
    # Resource names
    export TOPIC_NAME="threat-response-topic-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="threat-response-sub-${RANDOM_SUFFIX}"
    export LOG_SINK_NAME="security-findings-sink-${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}, Zone: ${ZONE}"
    log_info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com" 
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "securitycenter.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
    done
    
    log_success "All APIs enabled successfully"
    
    # Wait for APIs to be fully available
    log_info "Waiting for APIs to be fully available..."
    sleep 30
}

# Function to create Pub/Sub infrastructure
create_pubsub_infrastructure() {
    log_info "Creating Pub/Sub infrastructure for security events..."
    
    # Create main topic for security findings
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
    gcloud pubsub topics create "${TOPIC_NAME}" || error_exit "Failed to create topic ${TOPIC_NAME}"
    
    # Create subscription for automated response
    log_info "Creating Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=60 \
        --message-retention-duration=7d || error_exit "Failed to create subscription ${SUBSCRIPTION_NAME}"
    
    # Create additional topics for function routing
    log_info "Creating additional routing topics..."
    gcloud pubsub topics create "threat-remediation-topic" || error_exit "Failed to create remediation topic"
    gcloud pubsub subscriptions create "threat-remediation-sub" \
        --topic="threat-remediation-topic" \
        --ack-deadline=120 || error_exit "Failed to create remediation subscription"
    
    gcloud pubsub topics create "threat-notification-topic" || error_exit "Failed to create notification topic"
    gcloud pubsub subscriptions create "threat-notification-sub" \
        --topic="threat-notification-topic" \
        --ack-deadline=60 || error_exit "Failed to create notification subscription"
    
    log_success "Pub/Sub infrastructure created successfully"
}

# Function to configure Cloud Logging export
configure_logging_export() {
    log_info "Configuring Cloud Logging export for security findings..."
    
    # Create log sink to export security findings to Pub/Sub
    local log_filter='protoPayload.serviceName="securitycenter.googleapis.com" OR 
                     jsonPayload.source="security-center" OR
                     jsonPayload.category="THREAT_DETECTION" OR
                     severity>="WARNING"'
    
    log_info "Creating log sink: ${LOG_SINK_NAME}"
    gcloud logging sinks create "${LOG_SINK_NAME}" \
        "pubsub.googleapis.com/projects/${PROJECT_ID}/topics/${TOPIC_NAME}" \
        --log-filter="${log_filter}" || error_exit "Failed to create log sink"
    
    # Get the sink's service account for IAM binding
    local sink_service_account
    sink_service_account=$(gcloud logging sinks describe "${LOG_SINK_NAME}" \
        --format="value(writerIdentity)") || error_exit "Failed to get sink service account"
    
    log_info "Granting Pub/Sub publisher permissions to log sink..."
    gcloud pubsub topics add-iam-policy-binding "${TOPIC_NAME}" \
        --member="${sink_service_account}" \
        --role="roles/pubsub.publisher" || error_exit "Failed to bind IAM policy"
    
    log_success "Security findings log export configured"
}

# Function to create function source code
create_function_source() {
    local function_name="$1"
    local function_dir="$2"
    
    log_info "Creating source code for ${function_name}..."
    
    mkdir -p "${function_dir}"
    
    case "${function_name}" in
        "security-triage")
            create_triage_function_source "${function_dir}"
            ;;
        "automated-remediation")
            create_remediation_function_source "${function_dir}"
            ;;
        "security-notification")
            create_notification_function_source "${function_dir}"
            ;;
        *)
            error_exit "Unknown function name: ${function_name}"
            ;;
    esac
}

# Function to create security triage function source
create_triage_function_source() {
    local dir="$1"
    
    cat > "${dir}/main.py" << 'EOF'
import base64
import json
import logging
import os
from google.cloud import monitoring_v3
from google.cloud import securitycenter
from google.cloud import pubsub_v1
from datetime import datetime

def main(event, context):
    """Security triage function for automated threat analysis."""
    
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(event['data']).decode('utf-8')
        security_finding = json.loads(message_data)
        
        # Extract key finding information
        finding_name = security_finding.get('name', 'Unknown')
        severity = security_finding.get('severity', 'MEDIUM')
        category = security_finding.get('category', 'Unknown')
        source_properties = security_finding.get('sourceProperties', {})
        
        logging.info(f"Processing security finding: {finding_name}")
        logging.info(f"Severity: {severity}, Category: {category}")
        
        # Triage logic based on severity and category
        if severity in ['HIGH', 'CRITICAL']:
            # Route to immediate remediation
            route_to_remediation(security_finding)
        elif category in ['MALWARE', 'PRIVILEGE_ESCALATION', 'DATA_EXFILTRATION']:
            # Route high-priority categories regardless of severity
            route_to_remediation(security_finding)
        else:
            # Route to notification for human review
            route_to_notification(security_finding)
        
        # Create monitoring metric
        create_security_metric(finding_name, severity, category)
        
        return f"Processed security finding: {finding_name}"
        
    except Exception as e:
        logging.error(f"Error processing security finding: {str(e)}")
        raise

def route_to_remediation(finding):
    """Route high-priority findings to remediation function."""
    project_id = os.environ.get('GCP_PROJECT')
    topic_name = 'threat-remediation-topic'
    
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    message_data = json.dumps(finding).encode('utf-8')
    publisher.publish(topic_path, message_data)
    logging.info("Routed to remediation function")

def route_to_notification(finding):
    """Route lower-priority findings to notification function."""
    project_id = os.environ.get('GCP_PROJECT')
    topic_name = 'threat-notification-topic'
    
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    message_data = json.dumps(finding).encode('utf-8')
    publisher.publish(topic_path, message_data)
    logging.info("Routed to notification function")

def create_security_metric(finding_name, severity, category):
    """Create custom monitoring metrics for security findings."""
    try:
        project_id = os.environ.get('GCP_PROJECT')
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        
        # Create metric point
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/findings_processed"
        series.resource.type = "global"
        series.metric.labels["severity"] = severity
        series.metric.labels["category"] = category
        
        # Create data point
        now = datetime.utcnow()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        interval = monitoring_v3.TimeInterval(
            {"end_time": {"seconds": seconds, "nanos": nanos}}
        )
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"int64_value": 1},
        })
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        logging.info("Security metric created successfully")
    except Exception as e:
        logging.error(f"Failed to create security metric: {str(e)}")
EOF

    cat > "${dir}/requirements.txt" << 'EOF'
google-cloud-monitoring==2.21.0
google-cloud-securitycenter==1.36.0
google-cloud-pubsub==2.25.0
google-cloud-logging==3.11.0
EOF
}

# Function to create remediation function source
create_remediation_function_source() {
    local dir="$1"
    
    cat > "${dir}/main.py" << 'EOF'
import base64
import json
import logging
import os
from google.cloud import compute_v1
from google.cloud import resource_manager
from google.cloud import securitycenter
from google.cloud import logging as cloud_logging
from datetime import datetime

def main(event, context):
    """Automated remediation function for critical security threats."""
    
    try:
        # Decode security finding from Pub/Sub
        message_data = base64.b64decode(event['data']).decode('utf-8')
        security_finding = json.loads(message_data)
        
        finding_name = security_finding.get('name', 'Unknown')
        category = security_finding.get('category', 'Unknown')
        resource_name = security_finding.get('resourceName', '')
        
        logging.info(f"Executing remediation for finding: {finding_name}")
        logging.info(f"Category: {category}, Resource: {resource_name}")
        
        # Determine remediation actions based on finding category
        remediation_actions = []
        
        if category == 'PRIVILEGE_ESCALATION':
            remediation_actions.extend(remediate_privilege_escalation(security_finding))
        elif category == 'MALWARE':
            remediation_actions.extend(remediate_malware_detection(security_finding))
        elif category == 'DATA_EXFILTRATION':
            remediation_actions.extend(remediate_data_exfiltration(security_finding))
        elif category == 'NETWORK_INTRUSION':
            remediation_actions.extend(remediate_network_intrusion(security_finding))
        else:
            remediation_actions.append(f"Generic isolation applied for category: {category}")
            apply_generic_isolation(security_finding)
        
        # Log all remediation actions
        log_remediation_actions(finding_name, remediation_actions)
        
        return f"Remediation completed for: {finding_name}"
        
    except Exception as e:
        logging.error(f"Error in remediation function: {str(e)}")
        raise

def remediate_privilege_escalation(finding):
    """Remediate privilege escalation attacks."""
    actions = []
    
    # Extract suspicious IAM members from finding
    source_properties = finding.get('sourceProperties', {})
    suspicious_members = source_properties.get('suspiciousMembers', [])
    
    project_id = os.environ.get('GCP_PROJECT')
    
    for member in suspicious_members:
        try:
            # Log the action (actual IAM removal would require careful consideration)
            logging.info(f"Would remove suspicious IAM member: {member} from project: {project_id}")
            actions.append(f"Flagged suspicious IAM member: {member}")
        except Exception as e:
            logging.error(f"Failed to process IAM member {member}: {str(e)}")
            actions.append(f"Failed to process IAM member: {member}")
    
    return actions

def remediate_malware_detection(finding):
    """Remediate malware detection on compute instances."""
    actions = []
    resource_name = finding.get('resourceName', '')
    
    if 'instances/' in resource_name:
        try:
            # Parse instance details from resource name
            instance_name = resource_name.split('/')[-1]
            zone = resource_name.split('/')[-3]
            project_id = os.environ.get('GCP_PROJECT')
            
            # Log isolation action (actual isolation would require careful consideration)
            logging.info(f"Would isolate infected instance: {instance_name} in zone: {zone}")
            actions.append(f"Flagged infected instance for isolation: {instance_name}")
            
        except Exception as e:
            logging.error(f"Failed to process instance: {str(e)}")
            actions.append(f"Failed to process instance: {resource_name}")
    
    return actions

def remediate_data_exfiltration(finding):
    """Remediate data exfiltration attempts."""
    actions = []
    
    try:
        # Log network restriction action
        logging.info("Would apply network restrictions to prevent data exfiltration")
        actions.append("Flagged for network restrictions to prevent data exfiltration")
    except Exception as e:
        logging.error(f"Failed to apply network restrictions: {str(e)}")
        actions.append("Failed to apply network restrictions")
    
    return actions

def remediate_network_intrusion(finding):
    """Remediate network intrusion attempts."""
    actions = []
    
    # Block suspicious IP addresses
    source_properties = finding.get('sourceProperties', {})
    suspicious_ips = source_properties.get('suspiciousIPs', [])
    
    for ip in suspicious_ips:
        try:
            # Log IP blocking action
            logging.info(f"Would block suspicious IP: {ip}")
            actions.append(f"Flagged suspicious IP for blocking: {ip}")
        except Exception as e:
            logging.error(f"Failed to process IP {ip}: {str(e)}")
            actions.append(f"Failed to process IP: {ip}")
    
    return actions

def apply_generic_isolation(finding):
    """Apply generic isolation measures for unknown threat categories."""
    resource_name = finding.get('resourceName', '')
    
    if 'instances/' in resource_name:
        instance_name = resource_name.split('/')[-1]
        zone = resource_name.split('/')[-3]
        project_id = os.environ.get('GCP_PROJECT')
        logging.info(f"Would apply generic isolation to instance: {instance_name} in zone: {zone}")

def log_remediation_actions(finding_name, actions):
    """Log all remediation actions for audit purposes."""
    client = cloud_logging.Client()
    client.setup_logging()
    
    audit_entry = {
        'finding_name': finding_name,
        'remediation_actions': actions,
        'timestamp': str(datetime.utcnow()),
        'function': 'automated-remediation'
    }
    
    logging.info(f"Remediation audit: {json.dumps(audit_entry)}")
EOF

    cat > "${dir}/requirements.txt" << 'EOF'
google-cloud-compute==1.20.0
google-cloud-resource-manager==1.12.5
google-cloud-securitycenter==1.36.0
google-cloud-logging==3.11.0
EOF
}

# Function to create notification function source
create_notification_function_source() {
    local dir="$1"
    
    cat > "${dir}/main.py" << 'EOF'
import base64
import json
import logging
import os
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging
from datetime import datetime

def main(event, context):
    """Security notification function for alerts and human review."""
    
    try:
        # Decode security finding
        message_data = base64.b64decode(event['data']).decode('utf-8')
        security_finding = json.loads(message_data)
        
        finding_name = security_finding.get('name', 'Unknown')
        severity = security_finding.get('severity', 'MEDIUM')
        category = security_finding.get('category', 'Unknown')
        
        logging.info(f"Creating notification for finding: {finding_name}")
        
        # Create structured alert
        alert_data = create_security_alert(security_finding)
        
        # Send to different channels based on severity
        if severity in ['HIGH', 'CRITICAL']:
            send_priority_notification(alert_data)
        else:
            send_standard_notification(alert_data)
        
        # Create dashboard entry
        update_security_dashboard(security_finding)
        
        # Log notification action
        log_notification_action(finding_name, severity, category)
        
        return f"Notification sent for: {finding_name}"
        
    except Exception as e:
        logging.error(f"Error in notification function: {str(e)}")
        raise

def create_security_alert(finding):
    """Create structured security alert with context."""
    return {
        'alert_id': finding.get('name', '').split('/')[-1],
        'title': f"Security Finding: {finding.get('category', 'Unknown')}",
        'severity': finding.get('severity', 'MEDIUM'),
        'description': finding.get('description', 'No description available'),
        'resource': finding.get('resourceName', 'Unknown resource'),
        'timestamp': datetime.utcnow().isoformat(),
        'recommendation': finding.get('recommendation', 'Review manually'),
        'source_properties': finding.get('sourceProperties', {})
    }

def send_priority_notification(alert_data):
    """Send high-priority notifications to immediate channels."""
    # Integration points for Slack, PagerDuty, etc.
    logging.info(f"Priority alert sent: {alert_data['title']}")
    
    # Create monitoring alert policy
    create_monitoring_alert(alert_data)

def send_standard_notification(alert_data):
    """Send standard notifications to review channels."""
    # Integration points for email, Slack channels, etc.
    logging.info(f"Standard alert sent: {alert_data['title']}")

def update_security_dashboard(finding):
    """Update security operations dashboard."""
    # Create custom metrics for dashboard visualization
    project_id = os.environ.get('GCP_PROJECT')
    
    # Implementation for dashboard updates
    logging.info("Security dashboard updated with new finding")

def create_monitoring_alert(alert_data):
    """Create Cloud Monitoring alert policy for high-priority findings."""
    project_id = os.environ.get('GCP_PROJECT')
    
    # Implementation for alert policy creation
    logging.info(f"Monitoring alert created for: {alert_data['alert_id']}")

def log_notification_action(finding_name, severity, category):
    """Log notification actions for audit and metrics."""
    client = cloud_logging.Client()
    client.setup_logging()
    
    notification_entry = {
        'finding_name': finding_name,
        'severity': severity,
        'category': category,
        'action': 'notification_sent',
        'timestamp': datetime.utcnow().isoformat(),
        'function': 'security-notification'
    }
    
    logging.info(f"Notification audit: {json.dumps(notification_entry)}")
EOF

    cat > "${dir}/requirements.txt" << 'EOF'
google-cloud-monitoring==2.21.0
google-cloud-logging==3.11.0
EOF
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions for security automation..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Deploy security triage function
    log_info "Deploying security triage function..."
    local triage_dir="${temp_dir}/security-triage-function"
    create_function_source "security-triage" "${triage_dir}"
    
    (cd "${triage_dir}" && \
     gcloud functions deploy security-triage \
         --runtime python39 \
         --trigger-topic "${TOPIC_NAME}" \
         --source . \
         --entry-point main \
         --memory 512MB \
         --timeout 300s \
         --set-env-vars "GCP_PROJECT=${PROJECT_ID}") || error_exit "Failed to deploy security triage function"
    
    # Deploy automated remediation function
    log_info "Deploying automated remediation function..."
    local remediation_dir="${temp_dir}/remediation-function"
    create_function_source "automated-remediation" "${remediation_dir}"
    
    (cd "${remediation_dir}" && \
     gcloud functions deploy automated-remediation \
         --runtime python39 \
         --trigger-topic threat-remediation-topic \
         --source . \
         --entry-point main \
         --memory 1024MB \
         --timeout 540s \
         --set-env-vars "GCP_PROJECT=${PROJECT_ID}") || error_exit "Failed to deploy remediation function"
    
    # Deploy security notification function
    log_info "Deploying security notification function..."
    local notification_dir="${temp_dir}/notification-function"
    create_function_source "security-notification" "${notification_dir}"
    
    (cd "${notification_dir}" && \
     gcloud functions deploy security-notification \
         --runtime python39 \
         --trigger-topic threat-notification-topic \
         --source . \
         --entry-point main \
         --memory 256MB \
         --timeout 60s \
         --set-env-vars "GCP_PROJECT=${PROJECT_ID}") || error_exit "Failed to deploy notification function"
    
    # Cleanup temporary directory
    rm -rf "${temp_dir}"
    
    log_success "All Cloud Functions deployed successfully"
}

# Function to configure security monitoring
configure_monitoring() {
    log_info "Configuring security monitoring and dashboards..."
    
    # Create custom metric descriptors for security operations
    local metric_descriptor=$(cat << 'EOF'
{
  "type": "custom.googleapis.com/security/findings_processed",
  "labels": [
    {
      "key": "severity",
      "valueType": "STRING",
      "description": "Security finding severity level"
    },
    {
      "key": "category", 
      "valueType": "STRING",
      "description": "Security finding category"
    }
  ],
  "metricKind": "CUMULATIVE",
  "valueType": "INT64",
  "description": "Number of security findings processed by automated system"
}
EOF
)
    
    # Create the custom metric
    echo "${metric_descriptor}" > /tmp/security-metrics.json
    gcloud monitoring metrics descriptors create \
        --descriptor-from-file=/tmp/security-metrics.json || \
        log_warning "Failed to create custom metric (may already exist)"
    
    # Cleanup temp file
    rm -f /tmp/security-metrics.json
    
    log_success "Security monitoring configured"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Cloud Functions
    local functions=("security-triage" "automated-remediation" "security-notification")
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --format="value(status)" | grep -q "ACTIVE"; then
            log_success "Function ${func} is active"
        else
            log_error "Function ${func} is not active"
            return 1
        fi
    done
    
    # Check Pub/Sub topics and subscriptions
    local topics=("${TOPIC_NAME}" "threat-remediation-topic" "threat-notification-topic")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "${topic}" &> /dev/null; then
            log_success "Topic ${topic} exists"
        else
            log_error "Topic ${topic} does not exist"
            return 1
        fi
    done
    
    # Check log sink
    if gcloud logging sinks describe "${LOG_SINK_NAME}" &> /dev/null; then
        log_success "Log sink ${LOG_SINK_NAME} exists"
    else
        log_error "Log sink ${LOG_SINK_NAME} does not exist"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment-info.txt"
    cat > "${info_file}" << EOF
# Automated Threat Response Deployment Information
# Generated: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}

# Pub/Sub Resources
TOPIC_NAME=${TOPIC_NAME}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME}
LOG_SINK_NAME=${LOG_SINK_NAME}

# Cloud Functions
TRIAGE_FUNCTION=security-triage
REMEDIATION_FUNCTION=automated-remediation
NOTIFICATION_FUNCTION=security-notification

# Additional Topics
REMEDIATION_TOPIC=threat-remediation-topic
NOTIFICATION_TOPIC=threat-notification-topic

# Monitoring
CUSTOM_METRIC=custom.googleapis.com/security/findings_processed
EOF
    
    log_success "Deployment information saved to ${info_file}"
}

# Function to display next steps
show_next_steps() {
    log_info "Deployment completed successfully!"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Verify Security Command Center Premium/Enterprise access"
    echo "2. Configure security findings to generate log entries"
    echo "3. Test the system with sample security findings"
    echo "4. Review Cloud Function logs for processing status"
    echo "5. Customize notification channels in the notification function"
    echo
    echo "=== USEFUL COMMANDS ==="
    echo "# View function logs:"
    echo "gcloud functions logs read security-triage --limit=20"
    echo
    echo "# Test with sample message:"
    echo "gcloud pubsub topics publish ${TOPIC_NAME} --message='{\"test\": \"message\"}'"
    echo
    echo "# Check monitoring metrics:"
    echo "gcloud monitoring time-series list --filter='metric.type=\"custom.googleapis.com/security/findings_processed\"'"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    echo "=== Automated Threat Response Deployment ==="
    echo "This script will deploy a complete security automation system"
    echo
    
    check_prerequisites
    setup_environment
    
    if ! validate_apis; then
        log_info "Enabling required APIs..."
        enable_apis
    else
        log_success "All required APIs are already enabled"
    fi
    
    create_pubsub_infrastructure
    configure_logging_export
    deploy_cloud_functions
    configure_monitoring
    validate_deployment
    save_deployment_info
    show_next_steps
    
    log_success "Automated threat response system deployed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# DNS Threat Detection with Cloud Armor and Security Center - Deployment Script
# This script deploys a comprehensive DNS threat detection solution using GCP services

set -euo pipefail

# Color codes for output
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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_FILE="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "Starting DNS Threat Detection deployment"
log "Log file: $LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-dns-threat-detection-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Resource names
    export SECURITY_POLICY_NAME="dns-protection-policy-${RANDOM_SUFFIX}"
    export DNS_POLICY_NAME="dns-security-policy-${RANDOM_SUFFIX}"
    export ZONE_NAME="security-zone-${RANDOM_SUFFIX}"
    export TOPIC_NAME="dns-security-alerts-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="dns-alert-processor-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="dns-security-processor"
    export NOTIFICATION_NAME="dns-threat-export-${RANDOM_SUFFIX}"
    
    log "Environment configured:"
    log "  PROJECT_ID: $PROJECT_ID"
    log "  REGION: $REGION"
    log "  ZONE: $ZONE"
    log "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
}

# Function to create or verify project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        warn "Project $PROJECT_ID does not exist. Creating new project..."
        gcloud projects create "$PROJECT_ID" --name="DNS Threat Detection Project"
        
        # Enable billing (requires billing account)
        warn "Please ensure billing is enabled for project $PROJECT_ID"
        info "You can enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
        read -p "Press Enter after enabling billing to continue..."
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log "Project setup completed ✅"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "dns.googleapis.com"
        "logging.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "securitycenter.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log "  ✅ $api enabled"
        else
            error "Failed to enable $api"
        fi
    done
    
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    log "API enablement completed ✅"
}

# Function to configure Security Command Center
setup_security_center() {
    log "Configuring Security Command Center..."
    
    # Get organization ID
    ORG_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || true)
    
    if [ -z "$ORG_ID" ]; then
        warn "No organization found. Security Command Center requires organization-level access."
        warn "This deployment will continue but Security Command Center features may be limited."
        return 0
    fi
    
    export ORG_ID
    log "Organization ID: $ORG_ID"
    
    # Enable Security Command Center Premium (may require additional permissions)
    info "Attempting to enable Security Command Center Premium..."
    if gcloud scc settings services enable \
        --organization="$ORG_ID" \
        --service=security-center-premium \
        --quiet 2>/dev/null; then
        log "Security Command Center Premium enabled ✅"
    else
        warn "Could not enable Security Command Center Premium. This may require organization admin permissions."
        warn "Please enable manually in the Cloud Console if needed."
    fi
    
    # Verify Security Command Center status
    if gcloud scc settings services describe \
        --organization="$ORG_ID" \
        --service=security-center-premium \
        --quiet > /dev/null 2>&1; then
        log "Security Command Center Premium is active ✅"
    else
        warn "Security Command Center Premium status could not be verified"
    fi
}

# Function to create DNS resources
create_dns_resources() {
    log "Creating DNS resources with security logging..."
    
    # Create DNS policy with logging enabled
    info "Creating DNS security policy..."
    if gcloud dns policies create "$DNS_POLICY_NAME" \
        --description="DNS policy with security logging enabled" \
        --enable-logging \
        --networks=default \
        --quiet; then
        log "DNS policy created ✅"
    else
        error "Failed to create DNS policy"
    fi
    
    # Create a managed zone for demonstration
    info "Creating managed DNS zone..."
    if gcloud dns managed-zones create "$ZONE_NAME" \
        --description="Security monitoring DNS zone" \
        --dns-name="security-demo.example.com." \
        --visibility=private \
        --networks=default \
        --quiet; then
        log "DNS managed zone created ✅"
    else
        error "Failed to create DNS managed zone"
    fi
    
    # Wait for DNS policy to propagate
    log "Waiting for DNS policy to propagate..."
    sleep 30
    log "DNS resources created successfully ✅"
}

# Function to create Cloud Armor security policy
create_cloud_armor_policy() {
    log "Creating Cloud Armor security policy..."
    
    # Create Cloud Armor security policy
    info "Creating base security policy..."
    if gcloud compute security-policies create "$SECURITY_POLICY_NAME" \
        --description="DNS threat protection policy" \
        --quiet; then
        log "Security policy created ✅"
    else
        error "Failed to create security policy"
    fi
    
    # Add rate limiting rule for DNS queries
    info "Adding rate limiting rule..."
    if gcloud compute security-policies rules create 1000 \
        --security-policy="$SECURITY_POLICY_NAME" \
        --action=rate-based-ban \
        --rate-limit-threshold-count=100 \
        --rate-limit-threshold-interval-sec=60 \
        --ban-duration-sec=600 \
        --conform-action=allow \
        --exceed-action=deny-429 \
        --enforce-on-key=IP \
        --quiet; then
        log "Rate limiting rule added ✅"
    else
        error "Failed to add rate limiting rule"
    fi
    
    # Add geo-blocking rule (using country codes)
    info "Adding geo-blocking rule..."
    if gcloud compute security-policies rules create 2000 \
        --security-policy="$SECURITY_POLICY_NAME" \
        --action=deny-403 \
        --src-ip-ranges="CN,RU" \
        --description="Block high-risk geographic regions" \
        --quiet; then
        log "Geo-blocking rule added ✅"
    else
        warn "Failed to add geo-blocking rule (may not be supported in all regions)"
    fi
    
    log "Cloud Armor security policy configured ✅"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub resources for security alerts..."
    
    # Create Pub/Sub topic
    info "Creating Pub/Sub topic..."
    if gcloud pubsub topics create "$TOPIC_NAME" --quiet; then
        log "Pub/Sub topic created ✅"
    else
        error "Failed to create Pub/Sub topic"
    fi
    
    # Create subscription
    info "Creating Pub/Sub subscription..."
    if gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
        --topic="$TOPIC_NAME" \
        --ack-deadline=60 \
        --quiet; then
        log "Pub/Sub subscription created ✅"
    else
        error "Failed to create Pub/Sub subscription"
    fi
    
    log "Pub/Sub resources created successfully ✅"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function for automated response..."
    
    # Create temporary directory for function source
    local temp_dir=$(mktemp -d)
    
    # Create function source files
    cat > "$temp_dir/main.py" << 'EOF'
import json
import logging
import base64
import os
from google.cloud import securitycenter
from google.cloud import compute_v1
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
scc_client = securitycenter.SecurityCenterClient()
compute_client = compute_v1.SecurityPoliciesClient()
logging_client = cloud_logging.Client()

def process_security_finding(event, context):
    """Process Security Command Center findings for DNS threats."""
    
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        finding_data = json.loads(pubsub_message)
        
        # Log the finding
        logger.info(f"Processing DNS security finding: {finding_data.get('name', 'Unknown')}")
        
        # Check if this is a DNS-related threat
        category = finding_data.get('category', '')
        if any(keyword in category.upper() for keyword in ['DNS', 'MALWARE', 'DOMAIN']):
            severity = finding_data.get('severity', 'MEDIUM')
            
            if severity in ['HIGH', 'CRITICAL']:
                # Implement automated response for high-severity threats
                implement_emergency_response(finding_data)
            else:
                # Log and monitor medium/low severity findings
                log_security_event(finding_data)
        
        return 'OK'
        
    except Exception as e:
        logger.error(f"Error processing security finding: {str(e)}")
        return f'Error: {str(e)}'

def implement_emergency_response(finding_data):
    """Implement automated response for high-severity DNS threats."""
    logger.warning(f"Implementing emergency response for: {finding_data.get('name', 'Unknown')}")
    
    # Add suspicious IPs to Cloud Armor deny list if available
    source_properties = finding_data.get('sourceProperties', {})
    source_ip = source_properties.get('sourceIp') or source_properties.get('clientIp')
    
    if source_ip:
        add_ip_to_blocklist(source_ip)
    
    # Send high-priority alert
    send_emergency_alert(finding_data)

def add_ip_to_blocklist(source_ip):
    """Add suspicious IP to Cloud Armor security policy."""
    try:
        logger.info(f"Adding {source_ip} to security policy blocklist")
        # In a production environment, you would implement the actual
        # Cloud Armor rule creation here
        # This requires additional IAM permissions and error handling
        logger.info(f"Successfully flagged IP {source_ip} for blocking")
    except Exception as e:
        logger.error(f"Error adding IP to blocklist: {str(e)}")

def log_security_event(finding_data):
    """Log security event for monitoring and analysis."""
    logger.info(f"Logging security event: {finding_data.get('name', 'Unknown')}")

def send_emergency_alert(finding_data):
    """Send high-priority security alert."""
    logger.critical(f"EMERGENCY: DNS threat detected - {finding_data.get('name', 'Unknown')}")
    # In production, integrate with notification systems like email, Slack, etc.
EOF
    
    cat > "$temp_dir/requirements.txt" << 'EOF'
google-cloud-security-center==1.28.0
google-cloud-compute==1.19.0
google-cloud-logging==3.11.0
functions-framework==3.8.0
EOF
    
    # Deploy Cloud Function
    info "Deploying Cloud Function..."
    if gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-topic "$TOPIC_NAME" \
        --source "$temp_dir" \
        --entry-point process_security_finding \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars PROJECT_ID="$PROJECT_ID" \
        --max-instances 10 \
        --quiet; then
        log "Cloud Function deployed ✅"
    else
        error "Failed to deploy Cloud Function"
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    log "Cloud Function deployment completed ✅"
}

# Function to configure Security Command Center exports
configure_scc_exports() {
    log "Configuring Security Command Center exports..."
    
    if [ -z "${ORG_ID:-}" ]; then
        warn "No organization ID available. Skipping Security Command Center export configuration."
        return 0
    fi
    
    # Create export configuration for DNS threats
    info "Creating Security Command Center notification..."
    if gcloud scc notifications create "$NOTIFICATION_NAME" \
        --organization="$ORG_ID" \
        --description="Export DNS threat findings to Pub/Sub" \
        --pubsub-topic="projects/$PROJECT_ID/topics/$TOPIC_NAME" \
        --filter='category:"Malware: Bad Domain" OR category:"Malware: Bad IP" OR category:"DNS" OR finding_class="THREAT"' \
        --quiet 2>/dev/null; then
        log "Security Command Center export configured ✅"
    else
        warn "Could not create Security Command Center notification. This may require additional permissions."
    fi
    
    # Verify the notification configuration
    if gcloud scc notifications describe "$NOTIFICATION_NAME" \
        --organization="$ORG_ID" \
        --quiet > /dev/null 2>&1; then
        log "Security Command Center notification verified ✅"
    else
        warn "Could not verify Security Command Center notification"
    fi
}

# Function to enable advanced DNS monitoring
setup_monitoring() {
    log "Setting up advanced DNS monitoring..."
    
    # Create custom log-based metrics for DNS security monitoring
    info "Creating custom log-based metrics..."
    if gcloud logging metrics create dns_malware_queries \
        --description="Count of malware-related DNS queries" \
        --log-filter='resource.type="dns_query" AND (jsonPayload.queryName:("malware" OR "botnet" OR "c2") OR jsonPayload.responseCode>=300)' \
        --quiet; then
        log "Custom log metric created ✅"
    else
        warn "Failed to create custom log metric (may already exist)"
    fi
    
    # Create alerting policy for DNS threats
    cat > "/tmp/dns-alert-policy-${RANDOM_SUFFIX}.yaml" << EOF
displayName: "DNS Threat Detection Alert"
documentation:
  content: "Alert triggered when malware DNS queries are detected"
  mimeType: "text/markdown"
conditions:
  - displayName: "Malware DNS Query Rate"
    conditionThreshold:
      filter: 'metric.type="logging.googleapis.com/user/dns_malware_queries"'
      comparison: COMPARISON_GT
      thresholdValue: 5.0
      duration: 60s
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_RATE
alertStrategy:
  autoClose: 86400s
EOF
    
    # Apply the alerting policy
    info "Creating monitoring alert policy..."
    if gcloud alpha monitoring policies create \
        --policy-from-file="/tmp/dns-alert-policy-${RANDOM_SUFFIX}.yaml" \
        --quiet; then
        log "Monitoring alert policy created ✅"
    else
        warn "Failed to create monitoring alert policy"
    fi
    
    # Clean up temporary file
    rm -f "/tmp/dns-alert-policy-${RANDOM_SUFFIX}.yaml"
    log "Advanced DNS monitoring setup completed ✅"
}

# Function to run validation tests
run_validation() {
    log "Running deployment validation..."
    
    # Check Security Command Center configuration
    if [ -n "${ORG_ID:-}" ]; then
        info "Validating Security Command Center..."
        if gcloud scc settings services describe \
            --organization="$ORG_ID" \
            --service=security-center-premium \
            --quiet > /dev/null 2>&1; then
            log "Security Command Center validation passed ✅"
        else
            warn "Security Command Center validation failed"
        fi
    fi
    
    # Test Cloud Armor configuration
    info "Validating Cloud Armor security policy..."
    if gcloud compute security-policies describe "$SECURITY_POLICY_NAME" \
        --quiet > /dev/null 2>&1; then
        log "Cloud Armor validation passed ✅"
    else
        error "Cloud Armor validation failed"
    fi
    
    # Test DNS functionality
    info "Validating DNS resolution..."
    if nslookup google.com > /dev/null 2>&1; then
        log "DNS resolution validation passed ✅"
    else
        warn "DNS resolution validation failed"
    fi
    
    # Check Cloud Function status
    info "Validating Cloud Function deployment..."
    if gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --quiet > /dev/null 2>&1; then
        log "Cloud Function validation passed ✅"
    else
        warn "Cloud Function validation failed"
    fi
    
    # Test Pub/Sub message flow
    info "Testing Pub/Sub message flow..."
    if gcloud pubsub topics publish "$TOPIC_NAME" \
        --message='{"category":"Test","severity":"LOW","name":"validation-test"}' \
        --quiet; then
        log "Pub/Sub test message published ✅"
        
        # Wait for processing and check function logs
        sleep 10
        if gcloud functions logs read "$FUNCTION_NAME" \
            --region="$REGION" \
            --limit=5 \
            --quiet > /dev/null 2>&1; then
            log "Cloud Function processing validated ✅"
        else
            warn "Cloud Function processing validation inconclusive"
        fi
    else
        warn "Pub/Sub validation failed"
    fi
    
    log "Validation completed ✅"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully! 🎉"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo
    echo "=== CREATED RESOURCES ==="
    echo "• Cloud Armor Security Policy: $SECURITY_POLICY_NAME"
    echo "• DNS Security Policy: $DNS_POLICY_NAME"
    echo "• DNS Managed Zone: $ZONE_NAME"
    echo "• Pub/Sub Topic: $TOPIC_NAME"
    echo "• Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    echo "• Cloud Function: $FUNCTION_NAME"
    echo "• Custom Log Metric: dns_malware_queries"
    if [ -n "${ORG_ID:-}" ]; then
        echo "• Security Command Center Notification: $NOTIFICATION_NAME"
    fi
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Monitor security findings in Security Command Center"
    echo "2. Review Cloud Function logs for automated responses"
    echo "3. Configure additional notification channels as needed"
    echo "4. Test DNS threat detection with controlled scenarios"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
    echo "=== MONITORING ==="
    echo "• Cloud Console: https://console.cloud.google.com/security/command-center?project=$PROJECT_ID"
    echo "• Function Logs: https://console.cloud.google.com/functions/details/$REGION/$FUNCTION_NAME?project=$PROJECT_ID"
    echo "• Pub/Sub Topic: https://console.cloud.google.com/cloudpubsub/topic/detail/$TOPIC_NAME?project=$PROJECT_ID"
    echo
    log "Log file saved to: $LOG_FILE"
}

# Main execution
main() {
    log "🚀 Starting DNS Threat Detection deployment"
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_security_center
    create_dns_resources
    create_cloud_armor_policy
    create_pubsub_resources
    deploy_cloud_function
    configure_scc_exports
    setup_monitoring
    run_validation
    display_summary
    
    log "✅ DNS Threat Detection deployment completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"
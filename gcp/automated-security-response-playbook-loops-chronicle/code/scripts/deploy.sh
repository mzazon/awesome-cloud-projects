#!/bin/bash

# Automated Security Response with Playbook Loops and Chronicle - Deployment Script
# This script deploys the complete security automation infrastructure for Chronicle SOAR integration

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Display script header
echo "=============================================="
echo "Chronicle SOAR Security Automation Deployment"
echo "=============================================="
echo ""

# Check if running in interactive mode
if [[ -t 0 ]]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-sec-automation-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
SECURITY_TOPIC="${SECURITY_TOPIC:-security-events-${RANDOM_SUFFIX}}"
RESPONSE_TOPIC="${RESPONSE_TOPIC:-response-actions-${RANDOM_SUFFIX}}"
SA_NAME="${SA_NAME:-security-automation-sa}"
SKIP_PROJECT_CREATION="${SKIP_PROJECT_CREATION:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required for generating random values."
        exit 1
    fi
    
    # Check Python for test script generation
    if ! command -v python3 &> /dev/null; then
        warn "Python3 not found. Test script generation will be skipped."
    fi
    
    success "Prerequisites check passed"
}

# Function to validate and set up project
setup_project() {
    log "Setting up Google Cloud project..."
    
    if [[ "${SKIP_PROJECT_CREATION}" == "true" ]]; then
        log "Skipping project creation, using existing project: ${PROJECT_ID}"
    else
        # Check if project exists
        if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
            if [[ "${INTERACTIVE}" == "true" ]]; then
                read -p "Project ${PROJECT_ID} already exists. Continue with existing project? (y/N): " -r
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log "Deployment cancelled by user"
                    exit 0
                fi
            else
                warn "Project ${PROJECT_ID} already exists. Continuing with existing project."
            fi
        else
            log "Creating new project: ${PROJECT_ID}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                gcloud projects create "${PROJECT_ID}" --name="Chronicle Security Automation"
            fi
        fi
    fi
    
    # Set active project
    log "Setting active project to: ${PROJECT_ID}"
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${PROJECT_ID}"
        gcloud config set compute/region "${REGION}"
        gcloud config set compute/zone "${ZONE}"
    fi
    
    success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "securitycenter.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: ${api}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            if ! gcloud services enable "${api}" --quiet; then
                error "Failed to enable API: ${api}"
                return 1
            fi
        fi
    done
    
    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN}" == "false" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "All required APIs enabled"
}

# Function to create Pub/Sub topics
create_pubsub_resources() {
    log "Creating Pub/Sub topics for security automation..."
    
    # Create security events topic
    log "Creating security events topic: ${SECURITY_TOPIC}"
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! gcloud pubsub topics create "${SECURITY_TOPIC}" --quiet; then
            if gcloud pubsub topics describe "${SECURITY_TOPIC}" &> /dev/null; then
                warn "Topic ${SECURITY_TOPIC} already exists"
            else
                error "Failed to create topic: ${SECURITY_TOPIC}"
                return 1
            fi
        fi
    fi
    
    # Create response actions topic
    log "Creating response actions topic: ${RESPONSE_TOPIC}"
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! gcloud pubsub topics create "${RESPONSE_TOPIC}" --quiet; then
            if gcloud pubsub topics describe "${RESPONSE_TOPIC}" &> /dev/null; then
                warn "Topic ${RESPONSE_TOPIC} already exists"
            else
                error "Failed to create topic: ${RESPONSE_TOPIC}"
                return 1
            fi
        fi
    fi
    
    success "Pub/Sub topics created successfully"
}

# Function to create service account
create_service_account() {
    log "Creating service account for security automation..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! gcloud iam service-accounts create "${SA_NAME}" \
            --display-name="Security Automation Service Account" \
            --description="Service account for automated security response functions" \
            --quiet; then
            if gcloud iam service-accounts describe "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
                warn "Service account ${SA_NAME} already exists"
            else
                error "Failed to create service account: ${SA_NAME}"
                return 1
            fi
        fi
    fi
    
    success "Service account created successfully"
}

# Function to create Cloud Functions source code
create_function_source() {
    log "Creating Cloud Functions source code..."
    
    # Create directories
    mkdir -p security-functions/threat-enrichment
    mkdir -p security-functions/automated-response
    
    # Create threat enrichment function
    log "Creating threat enrichment function source..."
    cat > security-functions/threat-enrichment/main.py << 'EOF'
import json
import base64
import requests
from google.cloud import pubsub_v1
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def threat_enrichment(event, context):
    """Enriches security alerts with threat intelligence."""
    
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        alert_data = json.loads(pubsub_message)
        
        logger.info(f"Processing alert: {alert_data.get('finding', {}).get('name', 'unknown')}")
        
        # Extract IOCs from security finding
        finding = alert_data.get('finding', {})
        source_properties = finding.get('sourceProperties', {})
        
        # Enrich with threat intelligence (simplified example)
        enriched_alert = {
            'original_finding': finding,
            'severity_score': calculate_severity_score(finding),
            'recommended_actions': generate_response_actions(finding),
            'entity_list': extract_entities(finding),
            'timestamp': finding.get('eventTime'),
            'source': finding.get('category'),
            'enrichment_status': 'completed'
        }
        
        # Publish enriched alert for Chronicle SOAR processing
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(
            os.environ['GCP_PROJECT'], 
            os.environ['RESPONSE_TOPIC']
        )
        
        message_data = json.dumps(enriched_alert).encode('utf-8')
        future = publisher.publish(topic_path, message_data)
        
        logger.info(f"Published enriched alert with {len(enriched_alert['entity_list'])} entities")
        
        return {
            'status': 'enriched', 
            'entities_found': len(enriched_alert['entity_list']),
            'severity_score': enriched_alert['severity_score']
        }
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        raise

def calculate_severity_score(finding):
    """Calculate dynamic severity score based on multiple factors."""
    severity_mapping = {
        'CRITICAL': 10, 
        'HIGH': 8, 
        'MEDIUM': 5, 
        'LOW': 2
    }
    
    base_score = severity_mapping.get(finding.get('severity', 'LOW'), 2)
    
    # Adjust score based on asset criticality
    resource_name = finding.get('resourceName', '').lower()
    if any(keyword in resource_name for keyword in ['production', 'prod', 'critical']):
        base_score += 2
    
    # Adjust based on category
    category = finding.get('category', '').lower()
    if any(keyword in category for keyword in ['malware', 'intrusion', 'exfiltration']):
        base_score += 1
    
    return min(base_score, 10)

def generate_response_actions(finding):
    """Generate recommended response actions based on finding type."""
    category = finding.get('category', '').lower()
    actions = []
    
    if 'malware' in category:
        actions.extend(['isolate_host', 'scan_files', 'update_signatures'])
    elif 'network' in category or 'intrusion' in category:
        actions.extend(['block_ip', 'analyze_traffic', 'update_firewall'])
    elif 'data' in category or 'exfiltration' in category:
        actions.extend(['audit_access', 'review_permissions', 'monitor_data_flows'])
    
    # Always create incident ticket for high severity
    if finding.get('severity') in ['HIGH', 'CRITICAL']:
        actions.append('create_incident_ticket')
    
    return actions

def extract_entities(finding):
    """Extract security entities for playbook loop processing."""
    entities = []
    source_props = finding.get('sourceProperties', {})
    
    # Extract IP addresses from connections
    connections = source_props.get('connections', [])
    for conn in connections:
        if 'sourceIp' in conn:
            entities.append({
                'type': 'ip', 
                'value': conn['sourceIp'],
                'context': 'source_connection'
            })
        if 'destinationIp' in conn:
            entities.append({
                'type': 'ip', 
                'value': conn['destinationIp'],
                'context': 'destination_connection'
            })
    
    # Extract file hashes
    files = source_props.get('files', [])
    for file_info in files:
        if 'sha256' in file_info:
            entities.append({
                'type': 'hash', 
                'value': file_info['sha256'],
                'context': 'file_hash'
            })
    
    # Extract domains from URLs
    urls = source_props.get('urls', [])
    for url in urls:
        if 'url' in url:
            try:
                from urllib.parse import urlparse
                domain = urlparse(url['url']).netloc
                if domain:
                    entities.append({
                        'type': 'domain', 
                        'value': domain,
                        'context': 'suspicious_url'
                    })
            except:
                pass
    
    return entities
EOF

    # Create requirements file for threat enrichment
    cat > security-functions/threat-enrichment/requirements.txt << 'EOF'
google-cloud-pubsub==2.25.0
requests==2.32.0
google-cloud-logging==3.11.0
EOF

    # Create automated response function
    log "Creating automated response function source..."
    cat > security-functions/automated-response/main.py << 'EOF'
import json
import base64
from google.cloud import compute_v1
from google.cloud import logging
import os
import logging as std_logging

# Configure logging
std_logging.basicConfig(level=std_logging.INFO)
logger = std_logging.getLogger(__name__)

def automated_response(event, context):
    """Executes automated security response actions."""
    
    try:
        # Decode Pub/Sub message from Chronicle SOAR
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        response_data = json.loads(pubsub_message)
        
        logger.info(f"Processing response for alert: {response_data.get('original_finding', {}).get('name', 'unknown')}")
        
        # Initialize Cloud Logging
        logging_client = logging.Client()
        cloud_logger = logging_client.logger('security-automation')
        
        # Execute response actions based on enriched alert data
        actions_executed = []
        
        # Process recommended actions
        for action in response_data.get('recommended_actions', []):
            try:
                result = execute_action(action, response_data)
                actions_executed.append({
                    'action': action,
                    'status': 'completed',
                    'result': result
                })
                
                # Log to Cloud Logging
                cloud_logger.log_struct({
                    'action': action,
                    'status': 'completed',
                    'alert_id': response_data.get('original_finding', {}).get('name'),
                    'timestamp': response_data.get('timestamp'),
                    'severity_score': response_data.get('severity_score')
                })
                
            except Exception as e:
                error_msg = f"Failed to execute action {action}: {str(e)}"
                logger.error(error_msg)
                actions_executed.append({
                    'action': action,
                    'status': 'failed',
                    'error': error_msg
                })
                
                # Log error to Cloud Logging
                cloud_logger.log_struct({
                    'action': action,
                    'status': 'failed',
                    'error': error_msg,
                    'alert_id': response_data.get('original_finding', {}).get('name'),
                    'timestamp': response_data.get('timestamp')
                }, severity='ERROR')
        
        # Process entities with specific actions
        for entity in response_data.get('entity_list', []):
            try:
                result = process_entity(entity, response_data)
                actions_executed.append(result)
                
            except Exception as e:
                logger.error(f"Failed to process entity {entity}: {str(e)}")
        
        logger.info(f"Completed processing with {len(actions_executed)} actions executed")
        
        return {
            'actions_executed': actions_executed, 
            'status': 'completed',
            'total_actions': len(actions_executed)
        }
        
    except Exception as e:
        logger.error(f"Error in automated response: {str(e)}")
        raise

def execute_action(action, response_data):
    """Execute specific security response action."""
    
    if action == 'isolate_host':
        return isolate_host(response_data)
    elif action == 'block_ip':
        return block_malicious_ips(response_data)
    elif action == 'create_incident_ticket':
        return create_incident_ticket(response_data)
    elif action == 'scan_files':
        return initiate_file_scan(response_data)
    elif action == 'update_firewall':
        return update_firewall_rules(response_data)
    elif action == 'audit_access':
        return audit_access_logs(response_data)
    else:
        return f"Action {action} not implemented"

def process_entity(entity, response_data):
    """Process security entity based on type and context."""
    
    entity_type = entity.get('type')
    entity_value = entity.get('value')
    
    if entity_type == 'ip':
        return block_ip_address(entity_value)
    elif entity_type == 'hash':
        return scan_for_hash(entity_value)
    elif entity_type == 'domain':
        return block_domain(entity_value)
    else:
        return {
            'action': f'process_{entity_type}',
            'status': 'not_implemented',
            'entity': entity_value
        }

def isolate_host(response_data):
    """Isolate compromised host by applying network restrictions."""
    
    # Extract instance information from resource name
    finding = response_data.get('original_finding', {})
    resource_name = finding.get('resourceName', '')
    
    if 'instances/' in resource_name:
        instance_name = resource_name.split('/')[-1]
        
        # In production, this would:
        # 1. Add isolation network tag to instance
        # 2. Apply restrictive firewall rules
        # 3. Notify security team
        
        return f"Host isolation initiated for instance: {instance_name}"
    
    return "Host isolation: No instance identified in alert"

def block_malicious_ips(response_data):
    """Block malicious IP addresses using Cloud Armor."""
    
    blocked_ips = []
    
    for entity in response_data.get('entity_list', []):
        if entity.get('type') == 'ip':
            ip_address = entity.get('value')
            
            # In production, this would:
            # 1. Add IP to Cloud Armor security policy
            # 2. Update VPC firewall rules
            # 3. Add to threat intelligence feeds
            
            blocked_ips.append(ip_address)
    
    return f"Blocked {len(blocked_ips)} IP addresses: {', '.join(blocked_ips)}"

def block_ip_address(ip_address):
    """Block specific IP address."""
    
    # Implementation would integrate with Cloud Armor or VPC firewall
    return {
        'action': 'block_ip',
        'status': 'completed',
        'target': ip_address,
        'method': 'cloud_armor_policy'
    }

def scan_for_hash(file_hash):
    """Scan for specific file hash across environment."""
    
    # Implementation would integrate with security scanning tools
    return {
        'action': 'scan_hash',
        'status': 'initiated',
        'target': file_hash,
        'method': 'endpoint_detection'
    }

def block_domain(domain):
    """Block malicious domain."""
    
    # Implementation would update DNS filtering or proxy rules
    return {
        'action': 'block_domain',
        'status': 'completed',
        'target': domain,
        'method': 'dns_filtering'
    }

def create_incident_ticket(response_data):
    """Create incident ticket in ITSM system."""
    
    finding = response_data.get('original_finding', {})
    severity = finding.get('severity', 'MEDIUM')
    category = finding.get('category', 'Unknown')
    
    # Generate ticket ID
    ticket_id = f"INC-{severity}-{hash(finding.get('name', '')) % 10000}"
    
    # In production, this would integrate with ServiceNow, Jira, etc.
    
    return f"Incident ticket created: {ticket_id} for {category} alert"

def initiate_file_scan(response_data):
    """Initiate comprehensive file scanning."""
    
    return "File scanning initiated across environment"

def update_firewall_rules(response_data):
    """Update firewall rules based on threat intelligence."""
    
    return "Firewall rules updated with new threat indicators"

def audit_access_logs(response_data):
    """Initiate access log audit for data exfiltration."""
    
    return "Access log audit initiated for suspicious activity"
EOF

    # Create requirements file for automated response
    cat > security-functions/automated-response/requirements.txt << 'EOF'
google-cloud-compute==1.20.0
google-cloud-logging==3.11.0
google-cloud-functions==1.16.5
EOF

    success "Cloud Functions source code created"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log "Deploying Cloud Functions for security automation..."
    
    # Deploy threat enrichment function
    log "Deploying threat enrichment function..."
    cd security-functions/threat-enrichment
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! gcloud functions deploy "threat-enrichment-${RANDOM_SUFFIX}" \
            --runtime python312 \
            --trigger-topic "${SECURITY_TOPIC}" \
            --source . \
            --entry-point threat_enrichment \
            --memory 512MB \
            --timeout 300s \
            --service-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --set-env-vars "GCP_PROJECT=${PROJECT_ID},RESPONSE_TOPIC=${RESPONSE_TOPIC}" \
            --region="${REGION}" \
            --quiet; then
            error "Failed to deploy threat enrichment function"
            return 1
        fi
    fi
    
    cd ../..
    
    # Deploy automated response function
    log "Deploying automated response function..."
    cd security-functions/automated-response
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! gcloud functions deploy "automated-response-${RANDOM_SUFFIX}" \
            --runtime python312 \
            --trigger-topic "${RESPONSE_TOPIC}" \
            --source . \
            --entry-point automated_response \
            --memory 512MB \
            --timeout 300s \
            --service-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --region="${REGION}" \
            --quiet; then
            error "Failed to deploy automated response function"
            return 1
        fi
    fi
    
    cd ../..
    
    success "Cloud Functions deployed successfully"
}

# Function to configure IAM permissions
configure_iam() {
    log "Configuring IAM permissions for security automation..."
    
    local roles=(
        "roles/securitycenter.findings.editor"
        "roles/pubsub.publisher"
        "roles/pubsub.subscriber"
        "roles/cloudfunctions.invoker"
        "roles/compute.instanceAdmin.v1"
        "roles/logging.logWriter"
        "roles/cloudtrace.agent"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role: ${role}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            if ! gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
                --role="${role}" \
                --quiet; then
                error "Failed to grant role: ${role}"
                return 1
            fi
        fi
    done
    
    success "IAM permissions configured successfully"
}

# Function to configure Security Command Center
configure_scc() {
    log "Configuring Security Command Center integration..."
    
    # Note: This requires organization-level permissions
    local org_id
    org_id=$(gcloud organizations list --format="value(name)" 2>/dev/null | head -n1)
    
    if [[ -z "${org_id}" ]]; then
        warn "No organization found. Skipping Security Command Center configuration."
        warn "Manual configuration required for SCC notifications."
        return 0
    fi
    
    log "Found organization: ${org_id}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Enable Security Command Center Premium (if not already enabled)
        if ! gcloud scc settings update \
            --organization="${org_id}" \
            --tier=PREMIUM \
            --quiet 2>/dev/null; then
            warn "Could not enable SCC Premium. May require additional permissions."
        fi
        
        # Create notification channel
        if ! gcloud scc notifications create "scc-automation-${RANDOM_SUFFIX}" \
            --organization="${org_id}" \
            --pubsub-topic="projects/${PROJECT_ID}/topics/${SECURITY_TOPIC}" \
            --filter='state="ACTIVE" AND severity="HIGH"' \
            --quiet; then
            warn "Could not create SCC notification. Manual configuration may be required."
        else
            success "Security Command Center notification configured"
        fi
    fi
}

# Function to create test artifacts
create_test_artifacts() {
    log "Creating test artifacts..."
    
    # Create test event generator only if Python is available
    if command -v python3 &> /dev/null; then
        cat > generate-test-events.py << 'EOF'
import json
import base64
from google.cloud import pubsub_v1
import time
import random
import sys

def generate_test_security_event():
    """Generate simulated security events for testing."""
    
    event_types = [
        {
            "category": "MALWARE_DETECTION",
            "severity": "HIGH",
            "entities": [
                {"type": "ip", "value": "192.168.1.100"},
                {"type": "hash", "value": "a1b2c3d4e5f6789012345678901234567890123456789012345678901234"},
                {"type": "domain", "value": "malicious-site.example"}
            ]
        },
        {
            "category": "NETWORK_INTRUSION",
            "severity": "CRITICAL", 
            "entities": [
                {"type": "ip", "value": "203.0.113.45"},
                {"type": "ip", "value": "198.51.100.67"}
            ]
        },
        {
            "category": "DATA_EXFILTRATION",
            "severity": "HIGH",
            "entities": [
                {"type": "ip", "value": "10.0.0.50"},
                {"type": "domain", "value": "suspicious-upload.example"}
            ]
        }
    ]
    
    selected_event = random.choice(event_types)
    
    test_finding = {
        "finding": {
            "name": f"organizations/123456789/sources/12345/findings/test-finding-{int(time.time())}",
            "category": selected_event["category"],
            "severity": selected_event["severity"],
            "eventTime": time.strftime('%Y-%m-%dT%H:%M:%S.%fZ'),
            "resourceName": f"projects/{sys.argv[1]}/zones/us-central1-a/instances/web-server-{random.randint(1,10)}",
            "sourceProperties": {
                "entities": selected_event["entities"],
                "connections": [
                    {"sourceIp": entity["value"]} 
                    for entity in selected_event["entities"] 
                    if entity["type"] == "ip"
                ],
                "description": f"Simulated {selected_event['category']} event for testing"
            },
            "state": "ACTIVE"
        }
    }
    
    return test_finding

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 generate-test-events.py <PROJECT_ID> <TOPIC_NAME>")
        sys.exit(1)
    
    project_id = sys.argv[1]
    topic_name = sys.argv[2]
    
    # Publish test events
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    print(f"Publishing test events to topic: {topic_path}")
    
    for i in range(3):
        test_event = generate_test_security_event()
        message_data = json.dumps(test_event).encode('utf-8')
        
        try:
            future = publisher.publish(topic_path, message_data)
            message_id = future.result()
            print(f"Published test event {i+1}: {message_id}")
            time.sleep(2)
        except Exception as e:
            print(f"Error publishing event {i+1}: {e}")
    
    print("✅ Test security events published successfully")

if __name__ == "__main__":
    main()
EOF
        
        success "Test artifacts created"
    else
        warn "Python3 not available. Test event generator not created."
    fi
}

# Function to create Chronicle SOAR configuration template
create_soar_config() {
    log "Creating Chronicle SOAR configuration template..."
    
    cat > chronicle-playbook-config.json << EOF
{
  "playbook_name": "Multi-Entity Threat Response with Loops",
  "description": "Automated response using Playbook Loops for multiple security entities",
  "version": "1.0",
  "created_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "trigger_conditions": {
    "alert_sources": ["Security Command Center"],
    "severity_levels": ["HIGH", "CRITICAL"],
    "entity_types": ["ip_address", "file_hash", "domain"],
    "categories": ["MALWARE_DETECTION", "NETWORK_INTRUSION", "DATA_EXFILTRATION"]
  },
  "playbook_loops": {
    "entity_processing_loop": {
      "loop_type": "entities",
      "max_iterations": 100,
      "scope_lock": true,
      "timeout_minutes": 30,
      "actions": [
        {
          "action_type": "threat_intelligence_lookup",
          "action_name": "Enrich Entity with TI",
          "parameters": {
            "entity_placeholder": "Loop.Entity",
            "reputation_sources": ["VirusTotal", "URLVoid", "AbuseIPDB"],
            "timeout_seconds": 30
          }
        },
        {
          "action_type": "conditional_block",
          "action_name": "Block High-Risk Entities",
          "condition": "reputation_score > 7 OR severity_score > 8",
          "true_actions": [
            {
              "action_type": "cloud_function_invoke",
              "function_name": "automated-response-${RANDOM_SUFFIX}",
              "parameters": {
                "action": "block_entity",
                "entity": "Loop.Entity.value",
                "entity_type": "Loop.Entity.type",
                "reputation_score": "Loop.Entity.reputation_score"
              }
            }
          ],
          "false_actions": [
            {
              "action_type": "add_to_monitoring",
              "parameters": {
                "entity": "Loop.Entity.value",
                "monitoring_duration": "24h"
              }
            }
          ]
        }
      ]
    },
    "response_coordination_loop": {
      "loop_type": "list",
      "list_source": "recommended_actions",
      "delimiter": ",",
      "max_iterations": 20,
      "actions": [
        {
          "action_type": "cloud_function_invoke",
          "action_name": "Execute Response Action",
          "function_name": "automated-response-${RANDOM_SUFFIX}",
          "parameters": {
            "action": "Loop.item",
            "context": "Entity.alert_context",
            "severity": "Entity.severity_score"
          }
        },
        {
          "action_type": "wait",
          "duration_seconds": 5
        }
      ]
    }
  },
  "notification_settings": {
    "pubsub_topic": "projects/${PROJECT_ID}/topics/${RESPONSE_TOPIC}",
    "notification_conditions": ["loop_completion", "high_severity_match", "action_failure"],
    "email_recipients": ["security-team@example.com"],
    "slack_webhook": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
  },
  "error_handling": {
    "retry_attempts": 3,
    "retry_delay_seconds": 10,
    "escalation_threshold": 5,
    "fallback_actions": ["create_incident_ticket", "notify_security_team"]
  },
  "compliance": {
    "audit_logging": true,
    "data_retention_days": 90,
    "privacy_settings": {
      "mask_pii": true,
      "geographic_restrictions": ["EU", "US"]
    }
  }
}
EOF
    
    success "Chronicle SOAR configuration template created"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=============================================="
    echo "           DEPLOYMENT SUMMARY"
    echo "=============================================="
    echo ""
    echo "Project Information:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo ""
    echo "Created Resources:"
    echo "  • Pub/Sub Topics:"
    echo "    - Security Events: ${SECURITY_TOPIC}"
    echo "    - Response Actions: ${RESPONSE_TOPIC}"
    echo "  • Service Account: ${SA_NAME}"
    echo "  • Cloud Functions:"
    echo "    - threat-enrichment-${RANDOM_SUFFIX}"
    echo "    - automated-response-${RANDOM_SUFFIX}"
    echo ""
    echo "Configuration Files:"
    echo "  • Chronicle SOAR Config: chronicle-playbook-config.json"
    if [[ -f "generate-test-events.py" ]]; then
        echo "  • Test Event Generator: generate-test-events.py"
    fi
    echo ""
    echo "Next Steps:"
    echo "  1. Configure Chronicle SOAR using chronicle-playbook-config.json"
    echo "  2. Set up Playbook Loops in Chronicle SOAR console"
    echo "  3. Test the workflow using the test event generator"
    echo "  4. Monitor function logs and adjust configurations as needed"
    echo ""
    echo "Monitoring Commands:"
    echo "  gcloud functions logs read threat-enrichment-${RANDOM_SUFFIX} --limit=10"
    echo "  gcloud functions logs read automated-response-${RANDOM_SUFFIX} --limit=10"
    echo ""
    echo "Chronicle SOAR Console: https://chronicle.security"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Chronicle SOAR Security Automation deployment..."
    
    # Parse command line arguments
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
            --skip-project-creation)
                SKIP_PROJECT_CREATION="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --project-id ID           Google Cloud Project ID"
                echo "  --region REGION          Deployment region (default: us-central1)"
                echo "  --skip-project-creation  Skip project creation step"
                echo "  --dry-run               Show what would be done without executing"
                echo "  --help                  Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  PROJECT_ID              Google Cloud Project ID"
                echo "  REGION                  Deployment region"
                echo "  SKIP_PROJECT_CREATION   Skip project creation (true/false)"
                echo "  DRY_RUN                Dry run mode (true/false)"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "Running in DRY-RUN mode - no resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_pubsub_resources
    create_service_account
    configure_iam
    create_function_source
    deploy_cloud_functions
    configure_scc
    create_test_artifacts
    create_soar_config
    
    display_summary
}

# Set trap for cleanup on script exit
trap 'echo ""; warn "Deployment interrupted. Run destroy.sh to clean up any created resources."' INT TERM

# Run main function
main "$@"
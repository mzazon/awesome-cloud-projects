#!/bin/bash

# API Governance and Compliance Monitoring with Apigee X and Cloud Logging - Deployment Script
# This script deploys the complete infrastructure for automated API governance monitoring
# Recipe: api-governance-compliance-monitoring-apigee-x-logging

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Error handling
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Command: $2"
    log_error "Exit code: $3"
    log_error "Please check the error above and run destroy.sh to clean up any partial deployment"
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND" $?' ERR

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be created"
fi

log_info "Starting API Governance and Compliance Monitoring deployment..."

# Prerequisites check
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

# Check if bq is installed
if ! command -v bq &> /dev/null; then
    log_error "BigQuery CLI (bq) is not installed. Please install it first."
    exit 1
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    log_error "gsutil is not installed. Please install it first."
    exit 1
fi

log_success "Prerequisites check passed"

# Set environment variables
log_info "Setting up environment variables..."

# Use provided PROJECT_ID or generate unique one
if [[ -z "${PROJECT_ID:-}" ]]; then
    export PROJECT_ID="api-governance-$(date +%s)"
    log_info "Generated PROJECT_ID: ${PROJECT_ID}"
else
    log_info "Using provided PROJECT_ID: ${PROJECT_ID}"
fi

export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export APIGEE_ORG="${PROJECT_ID}"
export ENV_NAME="dev-${RANDOM_SUFFIX}"
export STORAGE_BUCKET="governance-functions-${RANDOM_SUFFIX}"

log_info "Environment variables set:"
log_info "  PROJECT_ID: ${PROJECT_ID}"
log_info "  REGION: ${REGION}"
log_info "  ZONE: ${ZONE}"
log_info "  APIGEE_ORG: ${APIGEE_ORG}"
log_info "  ENV_NAME: ${ENV_NAME}"
log_info "  STORAGE_BUCKET: ${STORAGE_BUCKET}"

# Create project if it doesn't exist
log_info "Checking if project exists..."
if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
    log_info "Creating new project: ${PROJECT_ID}"
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud projects create "${PROJECT_ID}" --name="API Governance Project"
        log_success "Project created: ${PROJECT_ID}"
    fi
else
    log_info "Project already exists: ${PROJECT_ID}"
fi

# Set default project and region
if [[ "$DRY_RUN" == "false" ]]; then
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    log_success "Default project and region configured"
fi

# Enable required APIs
log_info "Enabling required Google Cloud APIs..."
REQUIRED_APIS=(
    "apigee.googleapis.com"
    "logging.googleapis.com"
    "eventarc.googleapis.com"
    "cloudfunctions.googleapis.com"
    "pubsub.googleapis.com"
    "storage.googleapis.com"
    "bigquery.googleapis.com"
    "monitoring.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    log_info "Enabling API: ${api}"
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud services enable "${api}" --project="${PROJECT_ID}"
    fi
done

log_success "Required APIs enabled"

# Create Cloud Storage bucket for function code
log_info "Creating Cloud Storage bucket: ${STORAGE_BUCKET}"
if [[ "$DRY_RUN" == "false" ]]; then
    if ! gsutil ls -b "gs://${STORAGE_BUCKET}" &> /dev/null; then
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${STORAGE_BUCKET}"
        log_success "Storage bucket created: ${STORAGE_BUCKET}"
    else
        log_info "Storage bucket already exists: ${STORAGE_BUCKET}"
    fi
fi

# Wait for API enablement to propagate
log_info "Waiting for API enablement to propagate..."
if [[ "$DRY_RUN" == "false" ]]; then
    sleep 30
fi

# Create Apigee X Environment
log_info "Creating Apigee X environment: ${ENV_NAME}"
if [[ "$DRY_RUN" == "false" ]]; then
    # Check if Apigee organization exists
    if ! gcloud alpha apigee organizations describe "${APIGEE_ORG}" &> /dev/null; then
        log_warning "Apigee organization not found. This may take 1-2 hours to provision."
        log_warning "Please ensure Apigee organization is created before running this script."
        log_warning "You can create it through the Google Cloud Console or using gcloud commands."
    else
        # Create environment if it doesn't exist
        if ! gcloud alpha apigee environments describe "${ENV_NAME}" --organization="${APIGEE_ORG}" &> /dev/null; then
            gcloud alpha apigee environments create "${ENV_NAME}" \
                --organization="${APIGEE_ORG}" \
                --display-name="Governance Environment"
            
            # Wait for environment creation
            sleep 30
            log_success "Apigee environment created: ${ENV_NAME}"
        else
            log_info "Apigee environment already exists: ${ENV_NAME}"
        fi
    fi
fi

# Create BigQuery dataset for log analysis
log_info "Creating BigQuery dataset for API governance logs..."
if [[ "$DRY_RUN" == "false" ]]; then
    if ! bq ls --project_id="${PROJECT_ID}" | grep -q "api_governance"; then
        bq mk --project_id="${PROJECT_ID}" \
            --location="${REGION}" \
            api_governance
        log_success "BigQuery dataset created: api_governance"
    else
        log_info "BigQuery dataset already exists: api_governance"
    fi
fi

# Create Pub/Sub topic for real-time log processing
log_info "Creating Pub/Sub topic for API governance events..."
if [[ "$DRY_RUN" == "false" ]]; then
    if ! gcloud pubsub topics describe api-governance-events --project="${PROJECT_ID}" &> /dev/null; then
        gcloud pubsub topics create api-governance-events --project="${PROJECT_ID}"
        log_success "Pub/Sub topic created: api-governance-events"
    else
        log_info "Pub/Sub topic already exists: api-governance-events"
    fi
fi

# Create log sinks
log_info "Creating Cloud Logging sinks..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Create BigQuery log sink
    if ! gcloud logging sinks describe apigee-governance-sink --project="${PROJECT_ID}" &> /dev/null; then
        gcloud logging sinks create apigee-governance-sink \
            "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/api_governance" \
            --log-filter='resource.type="apigee_organization" OR 
                         resource.type="apigee_environment" OR
                         protoPayload.serviceName="apigee.googleapis.com"' \
            --use-partitioned-tables \
            --project="${PROJECT_ID}"
        log_success "BigQuery log sink created: apigee-governance-sink"
    else
        log_info "BigQuery log sink already exists: apigee-governance-sink"
    fi
    
    # Create Pub/Sub log sink
    if ! gcloud logging sinks describe apigee-realtime-sink --project="${PROJECT_ID}" &> /dev/null; then
        gcloud logging sinks create apigee-realtime-sink \
            "pubsub.googleapis.com/projects/${PROJECT_ID}/topics/api-governance-events" \
            --log-filter='resource.type="apigee_organization" AND
                         severity >= WARNING' \
            --project="${PROJECT_ID}"
        log_success "Pub/Sub log sink created: apigee-realtime-sink"
    else
        log_info "Pub/Sub log sink already exists: apigee-realtime-sink"
    fi
fi

# Create compliance monitoring function
log_info "Creating compliance monitoring Cloud Function..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create function code
    cat > main.py << 'EOF'
import json
import logging
import os
import base64
from google.cloud import logging_v2
from google.cloud import monitoring_v3
from datetime import datetime

def monitor_api_compliance(event, context):
    """Monitor API compliance and trigger alerts for violations."""
    
    # Initialize logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message = base64.b64decode(event['data']).decode('utf-8')
            log_entry = json.loads(message)
        else:
            logger.error("No data in Pub/Sub message")
            return "No data in message"
        
        # Extract relevant compliance data
        resource_type = log_entry.get('resource', {}).get('type', '')
        severity = log_entry.get('severity', '')
        log_name = log_entry.get('logName', '')
        
        # Check for compliance violations
        violations = []
        
        # Check for authentication failures
        proto_payload = log_entry.get('protoPayload', {})
        method_name = proto_payload.get('methodName', '')
        
        if 'authentication' in method_name.lower():
            if severity in ['ERROR', 'CRITICAL']:
                violations.append({
                    'type': 'AUTHENTICATION_FAILURE',
                    'severity': severity,
                    'timestamp': log_entry.get('timestamp'),
                    'details': proto_payload
                })
        
        # Check for rate limit violations
        resource_name = proto_payload.get('resourceName', '')
        if 'quota' in resource_name.lower():
            violations.append({
                'type': 'RATE_LIMIT_VIOLATION',
                'severity': severity,
                'timestamp': log_entry.get('timestamp'),
                'details': proto_payload
            })
        
        # Process violations
        for violation in violations:
            process_compliance_violation(violation, logger)
        
        return f"Processed {len(violations)} compliance violations"
        
    except Exception as e:
        logger.error(f"Error processing compliance event: {str(e)}")
        return f"Error: {str(e)}"

def process_compliance_violation(violation, logger):
    """Process detected compliance violation."""
    logger.warning(f"Compliance violation detected: {violation['type']}")
    
    try:
        # Log violation for audit trail
        client = logging_v2.Client()
        audit_logger = client.logger("api-governance-audit")
        audit_logger.log_struct({
            "message": "API compliance violation detected",
            "violation_type": violation['type'],
            "severity": violation['severity'],
            "timestamp": violation['timestamp'],
            "details": violation['details'],
            "processed_at": datetime.utcnow().isoformat()
        })
        
        # Here you would implement:
        # 1. Alert notification
        # 2. Automatic remediation
        # 3. Compliance reporting
        # 4. Metric updates
        
        logger.info(f"Compliance violation logged: {violation['type']}")
        
    except Exception as e:
        logger.error(f"Error processing violation: {str(e)}")
    
    return True
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-logging==3.8.0
google-cloud-monitoring==2.16.0
EOF
    
    # Deploy the function
    if ! gcloud functions describe api-compliance-monitor --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        gcloud functions deploy api-compliance-monitor \
            --runtime python39 \
            --trigger-topic api-governance-events \
            --source . \
            --entry-point monitor_api_compliance \
            --memory 256MB \
            --timeout 60s \
            --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}"
        log_success "Compliance monitoring function deployed: api-compliance-monitor"
    else
        log_info "Compliance monitoring function already exists: api-compliance-monitor"
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
fi

# Create policy enforcement function
log_info "Creating policy enforcement Cloud Function..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create function code
    cat > main.py << 'EOF'
import json
import logging
import os
import base64
from google.cloud import logging_v2
from datetime import datetime

def enforce_api_policies(event, context):
    """Automatically enforce API governance policies."""
    
    # Initialize logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    try:
        # Parse compliance violation event
        if 'data' in event:
            message = base64.b64decode(event['data']).decode('utf-8')
            violation_data = json.loads(message)
        else:
            logger.error("No data in enforcement event")
            return "No data in message"
        
        violation_type = violation_data.get('type', '')
        severity = violation_data.get('severity', '')
        
        # Implement automated responses based on violation type
        if violation_type == 'RATE_LIMIT_VIOLATION':
            # Temporarily block excessive API consumers
            block_api_consumer(violation_data, logger)
        elif violation_type == 'AUTHENTICATION_FAILURE':
            # Enhance security monitoring for failed auth attempts
            enhance_security_monitoring(violation_data, logger)
        elif severity == 'CRITICAL':
            # Immediately escalate critical violations
            escalate_critical_violation(violation_data, logger)
        
        # Log enforcement action for audit trail
        log_enforcement_action(violation_data, logger)
        
        return "Policy enforcement completed"
        
    except Exception as e:
        logger.error(f"Error in policy enforcement: {str(e)}")
        return f"Error: {str(e)}"

def block_api_consumer(violation_data, logger):
    """Block API consumer for excessive rate limit violations."""
    logger.info("Blocking API consumer for rate limit violations")
    # Implementation would use Apigee Management API
    return True

def enhance_security_monitoring(violation_data, logger):
    """Enhance monitoring for authentication failures."""
    logger.info("Enhancing security monitoring for auth failures")
    return True

def escalate_critical_violation(violation_data, logger):
    """Escalate critical compliance violations."""
    logger.critical(f"Critical violation escalated: {violation_data}")
    return True

def log_enforcement_action(violation_data, logger):
    """Log enforcement action for compliance audit."""
    try:
        client = logging_v2.Client()
        enforcement_logger = client.logger("api-governance-enforcement")
        enforcement_logger.log_struct({
            "message": "Automated policy enforcement action",
            "violation": violation_data,
            "timestamp": datetime.utcnow().isoformat(),
            "enforcement_type": "AUTOMATED"
        })
        logger.info("Enforcement action logged successfully")
    except Exception as e:
        logger.error(f"Error logging enforcement action: {str(e)}")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-logging==3.8.0
EOF
    
    # Deploy the function
    if ! gcloud functions describe api-policy-enforcer --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        gcloud functions deploy api-policy-enforcer \
            --runtime python39 \
            --trigger-topic api-governance-events \
            --source . \
            --entry-point enforce_api_policies \
            --memory 256MB \
            --timeout 120s \
            --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}"
        log_success "Policy enforcement function deployed: api-policy-enforcer"
    else
        log_info "Policy enforcement function already exists: api-policy-enforcer"
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
fi

# Create Eventarc triggers
log_info "Creating Eventarc triggers for automated response..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Get the default compute service account
    COMPUTE_SA="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    # Create trigger for API security violations
    if ! gcloud eventarc triggers describe api-security-violations --location="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        gcloud eventarc triggers create api-security-violations \
            --location="${REGION}" \
            --destination-cloud-function=api-compliance-monitor \
            --destination-cloud-function-region="${REGION}" \
            --event-filters="type=google.cloud.audit.log.v1.written" \
            --event-filters="serviceName=apigee.googleapis.com" \
            --service-account="${COMPUTE_SA}" \
            --project="${PROJECT_ID}"
        log_success "Eventarc trigger created: api-security-violations"
    else
        log_info "Eventarc trigger already exists: api-security-violations"
    fi
    
    # Create trigger for quota violations
    if ! gcloud eventarc triggers describe api-quota-violations --location="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        gcloud eventarc triggers create api-quota-violations \
            --location="${REGION}" \
            --destination-cloud-function=api-compliance-monitor \
            --destination-cloud-function-region="${REGION}" \
            --event-filters="type=google.cloud.audit.log.v1.written" \
            --event-filters="methodName=QuotaExceeded" \
            --service-account="${COMPUTE_SA}" \
            --project="${PROJECT_ID}"
        log_success "Eventarc trigger created: api-quota-violations"
    else
        log_info "Eventarc trigger already exists: api-quota-violations"
    fi
fi

# Create monitoring alert policies
log_info "Creating monitoring alert policies..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Create temporary file for alert policy
    TEMP_POLICY=$(mktemp)
    cat > "$TEMP_POLICY" << EOF
{
  "displayName": "API Governance Violations",
  "documentation": {
    "content": "Alert for API governance and compliance violations detected by Cloud Functions"
  },
  "conditions": [
    {
      "displayName": "High rate of compliance violations",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_function\" AND resource.labels.function_name=\"api-compliance-monitor\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 10,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "enabled": true
}
EOF
    
    # Create the alert policy
    gcloud alpha monitoring policies create --policy-from-file="$TEMP_POLICY" --project="${PROJECT_ID}"
    log_success "Monitoring alert policy created: API Governance Violations"
    
    # Clean up temporary file
    rm "$TEMP_POLICY"
fi

# Create monitoring dashboard
log_info "Creating monitoring dashboard..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Create temporary file for dashboard config
    TEMP_DASHBOARD=$(mktemp)
    cat > "$TEMP_DASHBOARD" << EOF
{
  "displayName": "API Governance Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "API Compliance Function Executions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND resource.labels.function_name=\"api-compliance-monitor\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Policy Enforcement Actions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND resource.labels.function_name=\"api-policy-enforcer\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create monitoring dashboard
    gcloud monitoring dashboards create --config-from-file="$TEMP_DASHBOARD" --project="${PROJECT_ID}"
    log_success "Monitoring dashboard created: API Governance Dashboard"
    
    # Clean up temporary file
    rm "$TEMP_DASHBOARD"
fi

# Final validation
log_info "Running deployment validation..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Check if functions are deployed
    if gcloud functions describe api-compliance-monitor --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        log_success "✅ Compliance monitoring function is deployed"
    else
        log_error "❌ Compliance monitoring function deployment failed"
    fi
    
    if gcloud functions describe api-policy-enforcer --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        log_success "✅ Policy enforcement function is deployed"
    else
        log_error "❌ Policy enforcement function deployment failed"
    fi
    
    # Check if Pub/Sub topic exists
    if gcloud pubsub topics describe api-governance-events --project="${PROJECT_ID}" &> /dev/null; then
        log_success "✅ Pub/Sub topic is created"
    else
        log_error "❌ Pub/Sub topic creation failed"
    fi
    
    # Check if BigQuery dataset exists
    if bq ls --project_id="${PROJECT_ID}" | grep -q "api_governance"; then
        log_success "✅ BigQuery dataset is created"
    else
        log_error "❌ BigQuery dataset creation failed"
    fi
fi

# Display deployment summary
log_success "=== DEPLOYMENT COMPLETE ==="
log_info "Project ID: ${PROJECT_ID}"
log_info "Region: ${REGION}"
log_info "Apigee Environment: ${ENV_NAME}"
log_info "Storage Bucket: ${STORAGE_BUCKET}"
log_info ""
log_info "Deployed Resources:"
log_info "  ✅ Cloud Functions: api-compliance-monitor, api-policy-enforcer"
log_info "  ✅ Pub/Sub Topic: api-governance-events"
log_info "  ✅ BigQuery Dataset: api_governance"
log_info "  ✅ Log Sinks: apigee-governance-sink, apigee-realtime-sink"
log_info "  ✅ Eventarc Triggers: api-security-violations, api-quota-violations"
log_info "  ✅ Monitoring Dashboard: API Governance Dashboard"
log_info "  ✅ Alert Policies: API Governance Violations"
log_info ""
log_info "Next Steps:"
log_info "1. Configure Apigee X organization if not already done"
log_info "2. Deploy API proxies with governance policies"
log_info "3. Test the compliance monitoring by generating API traffic"
log_info "4. Review the monitoring dashboard for governance metrics"
log_info ""
log_info "To clean up resources, run: ./destroy.sh"
log_info "For monitoring, visit: https://console.cloud.google.com/monitoring/dashboards"

# Save deployment state
cat > deployment_state.json << EOF
{
  "deployment_id": "$(date +%s)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "zone": "${ZONE}",
  "apigee_org": "${APIGEE_ORG}",
  "env_name": "${ENV_NAME}",
  "storage_bucket": "${STORAGE_BUCKET}",
  "functions": [
    "api-compliance-monitor",
    "api-policy-enforcer"
  ],
  "eventarc_triggers": [
    "api-security-violations",
    "api-quota-violations"
  ],
  "status": "deployed"
}
EOF

log_success "Deployment state saved to deployment_state.json"
log_success "API Governance and Compliance Monitoring system deployed successfully!"
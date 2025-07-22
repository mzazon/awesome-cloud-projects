#!/bin/bash

# Compliance Violation Detection with Cloud Audit Logs and Eventarc - Deployment Script
# This script deploys the complete infrastructure for automated compliance monitoring

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
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if API is enabled
check_api_enabled() {
    local api=$1
    if gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
        return 0
    else
        return 1
    fi
}

# Function to wait for operation to complete
wait_for_operation() {
    local operation_name=$1
    local operation_type=${2:-"global"}
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for operation ${operation_name} to complete..."
    
    while [ $attempt -le $max_attempts ]; do
        local status
        if [ "$operation_type" = "regional" ]; then
            status=$(gcloud compute operations describe "$operation_name" --region="$REGION" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
        else
            status=$(gcloud functions operations describe "$operation_name" --format="value(done)" 2>/dev/null || echo "false")
        fi
        
        if [ "$status" = "DONE" ] || [ "$status" = "true" ]; then
            log_success "Operation completed successfully"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts: Operation status: $status"
        sleep 10
        ((attempt++))
    done
    
    log_error "Operation timed out after $((max_attempts * 10)) seconds"
    return 1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("gcloud" "bq" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' is not installed or not in PATH"
        fi
    done
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
        error_exit "No project set in gcloud config. Please run 'gcloud config set project PROJECT_ID'"
    fi
    
    # Check billing account
    if ! gcloud billing projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Billing may not be enabled for project $PROJECT_ID"
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        export RANDOM_SUFFIX
    fi
    
    export FUNCTION_NAME="compliance-detector-${RANDOM_SUFFIX}"
    export TRIGGER_NAME="audit-log-trigger-${RANDOM_SUFFIX}"
    export TOPIC_NAME="compliance-alerts-${RANDOM_SUFFIX}"
    export DATASET_NAME="compliance_logs_${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set functions/region "${REGION}" || error_exit "Failed to set functions region"
    
    log_success "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log_info "  TRIGGER_NAME: ${TRIGGER_NAME}"
    log_info "  TOPIC_NAME: ${TOPIC_NAME}"
    log_info "  DATASET_NAME: ${DATASET_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
    )
    
    local apis_to_enable=()
    for api in "${apis[@]}"; do
        if ! check_api_enabled "$api"; then
            apis_to_enable+=("$api")
        else
            log_info "API $api is already enabled"
        fi
    done
    
    if [ ${#apis_to_enable[@]} -gt 0 ]; then
        log_info "Enabling APIs: ${apis_to_enable[*]}"
        gcloud services enable "${apis_to_enable[@]}" || error_exit "Failed to enable APIs"
        
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "All required APIs are enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub resources..."
    
    # Create topic
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_info "Topic $TOPIC_NAME already exists"
    else
        gcloud pubsub topics create "$TOPIC_NAME" || error_exit "Failed to create Pub/Sub topic"
        log_success "Created Pub/Sub topic: $TOPIC_NAME"
    fi
    
    # Create subscription
    local subscription_name="${TOPIC_NAME}-subscription"
    if gcloud pubsub subscriptions describe "$subscription_name" >/dev/null 2>&1; then
        log_info "Subscription $subscription_name already exists"
    else
        gcloud pubsub subscriptions create "$subscription_name" \
            --topic="$TOPIC_NAME" || error_exit "Failed to create Pub/Sub subscription"
        log_success "Created Pub/Sub subscription: $subscription_name"
    fi
}

# Function to create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery resources..."
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_info "BigQuery dataset $DATASET_NAME already exists"
    else
        bq mk --location="$REGION" \
            --description="Compliance violation logs and analysis" \
            "$DATASET_NAME" || error_exit "Failed to create BigQuery dataset"
        log_success "Created BigQuery dataset: $DATASET_NAME"
    fi
    
    # Create violations table
    local table_name="${PROJECT_ID}:${DATASET_NAME}.violations"
    if bq ls -t "$table_name" >/dev/null 2>&1; then
        log_info "BigQuery table violations already exists"
    else
        bq mk --table \
            "$table_name" \
            timestamp:TIMESTAMP,violation_type:STRING,severity:STRING,resource:STRING,principal:STRING,details:STRING,remediation_status:STRING \
            || error_exit "Failed to create BigQuery table"
        log_success "Created BigQuery table: violations"
    fi
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Preparing Cloud Function deployment..."
    
    # Create temporary directory for function source
    local temp_dir="/tmp/compliance-function-$$"
    mkdir -p "$temp_dir" || error_exit "Failed to create temporary directory"
    
    # Ensure cleanup of temp directory
    trap "rm -rf $temp_dir" EXIT
    
    cd "$temp_dir"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "compliance-detector",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/pubsub": "^4.0.0",
    "@google-cloud/bigquery": "^7.0.0",
    "@google-cloud/monitoring": "^4.0.0"
  }
}
EOF
    
    # Create the compliance detection function
    cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const { PubSub } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');
const { MetricServiceClient } = require('@google-cloud/monitoring');

const pubsub = new PubSub();
const bigquery = new BigQuery();
const monitoring = new MetricServiceClient();

// Compliance rules configuration
const COMPLIANCE_RULES = {
  IAM_POLICY_CHANGES: {
    severity: 'HIGH',
    methods: ['SetIamPolicy', 'setIamPolicy'],
    services: ['iam.googleapis.com', 'cloudresourcemanager.googleapis.com']
  },
  ADMIN_ACTIONS: {
    severity: 'MEDIUM',
    methods: ['Delete', 'Create', 'Update'],
    services: ['compute.googleapis.com', 'storage.googleapis.com']
  },
  DATA_ACCESS: {
    severity: 'LOW',
    logType: 'DATA_READ',
    services: ['storage.googleapis.com', 'bigquery.googleapis.com']
  }
};

functions.cloudEvent('analyzeAuditLog', async (cloudEvent) => {
  try {
    const auditLog = cloudEvent.data;
    const logEntry = auditLog.protoPayload || auditLog.jsonPayload;
    
    if (!logEntry) {
      console.log('No audit log payload found');
      return;
    }
    
    console.log('Processing audit log:', JSON.stringify(logEntry, null, 2));
    
    // Analyze for compliance violations
    const violations = await analyzeCompliance(logEntry, auditLog);
    
    if (violations.length > 0) {
      await Promise.all(violations.map(violation => processViolation(violation, auditLog)));
      console.log(`Processed ${violations.length} compliance violations`);
    }
    
  } catch (error) {
    console.error('Error processing audit log:', error);
    throw error;
  }
});

async function analyzeCompliance(logEntry, auditLog) {
  const violations = [];
  const timestamp = auditLog.timestamp;
  const resource = auditLog.resource?.labels?.resource_name || 'unknown';
  const principal = logEntry.authenticationInfo?.principalEmail || 'unknown';
  
  // Check IAM policy changes
  if (COMPLIANCE_RULES.IAM_POLICY_CHANGES.methods.includes(logEntry.methodName) &&
      COMPLIANCE_RULES.IAM_POLICY_CHANGES.services.includes(logEntry.serviceName)) {
    violations.push({
      type: 'IAM_POLICY_CHANGE',
      severity: 'HIGH',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `IAM policy modified: ${logEntry.methodName} on ${logEntry.serviceName}`,
      logEntry: logEntry
    });
  }
  
  // Check suspicious admin actions
  if (COMPLIANCE_RULES.ADMIN_ACTIONS.services.includes(logEntry.serviceName) &&
      COMPLIANCE_RULES.ADMIN_ACTIONS.methods.some(method => logEntry.methodName?.includes(method))) {
    violations.push({
      type: 'ADMIN_ACTION',
      severity: 'MEDIUM',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Administrative action: ${logEntry.methodName} on ${logEntry.serviceName}`,
      logEntry: logEntry
    });
  }
  
  // Check data access patterns
  if (auditLog.severity === 'INFO' && 
      logEntry.authenticationInfo && 
      COMPLIANCE_RULES.DATA_ACCESS.services.includes(logEntry.serviceName)) {
    violations.push({
      type: 'DATA_ACCESS',
      severity: 'LOW',
      timestamp: timestamp,
      resource: resource,
      principal: principal,
      details: `Data access: ${logEntry.methodName} on ${logEntry.serviceName}`,
      logEntry: logEntry
    });
  }
  
  return violations;
}

async function processViolation(violation, auditLog) {
  try {
    // Store in BigQuery for analysis
    await storeViolationInBigQuery(violation);
    
    // Send alert via Pub/Sub
    await sendAlert(violation);
    
    // Create custom metric for monitoring
    await createCustomMetric(violation);
    
    console.log(`Processed ${violation.type} violation for ${violation.principal}`);
    
  } catch (error) {
    console.error('Error processing violation:', error);
    throw error;
  }
}

async function storeViolationInBigQuery(violation) {
  const dataset = bigquery.dataset(process.env.DATASET_NAME);
  const table = dataset.table('violations');
  
  const row = {
    timestamp: violation.timestamp,
    violation_type: violation.type,
    severity: violation.severity,
    resource: violation.resource,
    principal: violation.principal,
    details: violation.details,
    remediation_status: 'PENDING'
  };
  
  await table.insert([row]);
}

async function sendAlert(violation) {
  const topic = pubsub.topic(process.env.TOPIC_NAME);
  
  const alertMessage = {
    violation_type: violation.type,
    severity: violation.severity,
    timestamp: violation.timestamp,
    resource: violation.resource,
    principal: violation.principal,
    details: violation.details,
    project_id: process.env.GOOGLE_CLOUD_PROJECT
  };
  
  await topic.publishMessage({
    data: Buffer.from(JSON.stringify(alertMessage))
  });
}

async function createCustomMetric(violation) {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT;
  const request = {
    name: `projects/${projectId}`,
    timeSeries: [{
      metric: {
        type: 'custom.googleapis.com/compliance/violations',
        labels: {
          violation_type: violation.type,
          severity: violation.severity
        }
      },
      resource: {
        type: 'global',
        labels: {
          project_id: projectId
        }
      },
      points: [{
        interval: {
          endTime: {
            seconds: Math.floor(Date.now() / 1000)
          }
        },
        value: {
          int64Value: 1
        }
      }]
    }]
  };
  
  try {
    await monitoring.createTimeSeries(request);
  } catch (error) {
    console.error('Error creating custom metric:', error);
  }
}
EOF
    
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    # Deploy the function
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime=nodejs20 \
        --trigger-event-filters="type=google.cloud.audit.log.v1.written" \
        --trigger-location="$REGION" \
        --entry-point=analyzeAuditLog \
        --set-env-vars="TOPIC_NAME=${TOPIC_NAME},DATASET_NAME=${DATASET_NAME}" \
        --timeout=540s \
        --memory=512MB \
        --max-instances=100 \
        --region="$REGION" \
        || error_exit "Failed to deploy Cloud Function"
    
    log_success "Cloud Function deployed successfully: $FUNCTION_NAME"
}

# Function to create Eventarc trigger
create_eventarc_trigger() {
    log_info "Creating Eventarc trigger..."
    
    # Check if trigger already exists
    if gcloud eventarc triggers describe "$TRIGGER_NAME" --location="$REGION" >/dev/null 2>&1; then
        log_info "Eventarc trigger $TRIGGER_NAME already exists"
        return 0
    fi
    
    # Get the service account for the function
    local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    # Create Eventarc trigger
    gcloud eventarc triggers create "$TRIGGER_NAME" \
        --location="$REGION" \
        --destination-run-service="$FUNCTION_NAME" \
        --event-filters="type=google.cloud.audit.log.v1.written" \
        --service-account="$service_account" \
        || error_exit "Failed to create Eventarc trigger"
    
    log_success "Eventarc trigger created: $TRIGGER_NAME"
}

# Function to configure audit logging
configure_audit_logging() {
    log_info "Configuring audit logging..."
    
    # Create audit policy file
    cat > /tmp/audit-policy.yaml << 'EOF'
auditConfigs:
- service: storage.googleapis.com
  auditLogConfigs:
  - logType: DATA_READ
  - logType: DATA_WRITE
- service: bigquery.googleapis.com
  auditLogConfigs:
  - logType: DATA_READ
  - logType: DATA_WRITE
- service: compute.googleapis.com
  auditLogConfigs:
  - logType: ADMIN_READ
EOF
    
    # Create logging sink if it doesn't exist
    local sink_name="compliance-audit-sink"
    if gcloud logging sinks describe "$sink_name" >/dev/null 2>&1; then
        log_info "Logging sink $sink_name already exists"
    else
        gcloud logging sinks create "$sink_name" \
            "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET_NAME}" \
            --log-filter='protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog"' \
            || error_exit "Failed to create logging sink"
        log_success "Created logging sink: $sink_name"
    fi
    
    # Create log-based metric
    local metric_name="compliance_violations"
    if gcloud logging metrics describe "$metric_name" >/dev/null 2>&1; then
        log_info "Log-based metric $metric_name already exists"
    else
        gcloud logging metrics create "$metric_name" \
            --description="Count of compliance violations detected" \
            --log-filter='resource.type="cloud_function" AND textPayload:"violation"' \
            || error_exit "Failed to create log-based metric"
        log_success "Created log-based metric: $metric_name"
    fi
    
    rm -f /tmp/audit-policy.yaml
}

# Function to create monitoring resources
create_monitoring_resources() {
    log_info "Creating monitoring resources..."
    
    # Create alert policy
    cat > /tmp/alert-policy.json << EOF
{
  "displayName": "High Severity Compliance Violations",
  "conditions": [
    {
      "displayName": "High severity violations detected",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/compliance/violations\" AND metric.labels.severity=\"HIGH\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0,
        "duration": "60s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true,
  "notificationChannels": []
}
EOF
    
    # Create alert policy
    if ! gcloud alpha monitoring policies create --policy-from-file=/tmp/alert-policy.json >/dev/null 2>&1; then
        log_warning "Failed to create alert policy - this may be due to existing policy or API limitations"
    else
        log_success "Created monitoring alert policy"
    fi
    
    # Create dashboard
    cat > /tmp/dashboard.json << EOF
{
  "displayName": "Compliance Monitoring Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Compliance Violations by Type",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/compliance/violations\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["metric.labels.violation_type"]
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
    
    # Create dashboard
    if ! gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json >/dev/null 2>&1; then
        log_warning "Failed to create dashboard - this may be due to existing dashboard or API limitations"
    else
        log_success "Created monitoring dashboard"
    fi
    
    rm -f /tmp/alert-policy.json /tmp/dashboard.json
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        local function_status
        function_status=$(gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --format="value(status)")
        if [ "$function_status" = "ACTIVE" ]; then
            log_success "Cloud Function is active: $FUNCTION_NAME"
        else
            log_warning "Cloud Function status: $function_status"
        fi
    else
        log_error "Cloud Function not found: $FUNCTION_NAME"
    fi
    
    # Check Eventarc trigger
    if gcloud eventarc triggers describe "$TRIGGER_NAME" --location="$REGION" >/dev/null 2>&1; then
        log_success "Eventarc trigger exists: $TRIGGER_NAME"
    else
        log_error "Eventarc trigger not found: $TRIGGER_NAME"
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_success "Pub/Sub topic exists: $TOPIC_NAME"
    else
        log_error "Pub/Sub topic not found: $TOPIC_NAME"
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_success "BigQuery dataset exists: $DATASET_NAME"
    else
        log_error "BigQuery dataset not found: $DATASET_NAME"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Compliance Violation Detection System deployed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Eventarc Trigger: $TRIGGER_NAME"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "BigQuery Dataset: $DATASET_NAME"
    echo
    echo "=== Next Steps ==="
    echo "1. Test the system by making some administrative changes in your GCP project"
    echo "2. Check the Cloud Function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "3. Query BigQuery for violations: bq query \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_NAME.violations\\\` ORDER BY timestamp DESC LIMIT 10\""
    echo "4. Monitor Pub/Sub messages: gcloud pubsub subscriptions pull ${TOPIC_NAME}-subscription --auto-ack"
    echo "5. View the monitoring dashboard in the Google Cloud Console"
    echo
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    echo "=== Compliance Violation Detection Deployment ==="
    echo "Starting deployment of automated compliance monitoring system..."
    echo
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup environment
    setup_environment
    
    # Enable APIs
    enable_apis
    
    # Create resources
    create_pubsub_resources
    create_bigquery_resources
    deploy_cloud_function
    create_eventarc_trigger
    configure_audit_logging
    create_monitoring_resources
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully! 🚀"
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may have been created. Check your GCP console."; exit 1' INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
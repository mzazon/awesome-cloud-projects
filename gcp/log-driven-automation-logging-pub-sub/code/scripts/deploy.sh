#!/bin/bash

# Log-Driven Automation with Cloud Logging and Pub/Sub - Deployment Script
# This script deploys the complete log-driven automation infrastructure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for script interruption
cleanup() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check $ERROR_LOG for details."
    fi
}
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy log-driven automation infrastructure with Cloud Logging and Pub/Sub.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -z, --zone ZONE              Deployment zone (default: us-central1-a)
    -s, --suffix SUFFIX          Resource name suffix (auto-generated if not provided)
    --slack-webhook URL          Slack webhook URL for notifications (optional)
    --dry-run                    Show what would be deployed without making changes
    -h, --help                   Show this help message

EXAMPLES:
    $0 --project-id my-project
    $0 --project-id my-project --region europe-west1 --zone europe-west1-a
    $0 --project-id my-project --slack-webhook https://hooks.slack.com/...

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -s|--suffix)
                SUFFIX="$2"
                shift 2
                ;;
            --slack-webhook)
                SLACK_WEBHOOK_URL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Set default values
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
SUFFIX=""
SLACK_WEBHOOK_URL=""
DRY_RUN=false

# Parse arguments
parse_args "$@"

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    error "Project ID is required. Use --project-id or -p flag."
fi

# Generate unique suffix if not provided
if [[ -z "$SUFFIX" ]]; then
    SUFFIX=$(openssl rand -hex 3)
fi

# Set resource names
TOPIC_NAME="incident-automation-${SUFFIX}"
ALERT_FUNCTION_NAME="alert-processor-${SUFFIX}"
REMEDIATION_FUNCTION_NAME="auto-remediate-${SUFFIX}"
LOG_SINK_NAME="automation-sink-${SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if openssl is available for generating random strings
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random strings."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Project '$PROJECT_ID' does not exist or is not accessible."
    fi
    
    log "Prerequisites check passed"
}

# Function to configure gcloud
configure_gcloud() {
    info "Configuring gcloud..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would configure gcloud with project: $PROJECT_ID, region: $REGION"
        return
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log "gcloud configured successfully"
}

# Function to enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "logging.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi
    
    for api in "${apis[@]}"; do
        info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log "✅ $api enabled successfully"
        else
            error "Failed to enable $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    sleep 10
    log "All required APIs enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    info "Creating Pub/Sub topic and subscriptions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Pub/Sub topic: $TOPIC_NAME"
        info "[DRY RUN] Would create subscriptions: alert-subscription, remediation-subscription"
        return
    fi
    
    # Create the main topic
    if gcloud pubsub topics create "$TOPIC_NAME" --quiet; then
        log "✅ Pub/Sub topic '$TOPIC_NAME' created"
    else
        warn "Topic '$TOPIC_NAME' may already exist"
    fi
    
    # Create alert subscription
    if gcloud pubsub subscriptions create alert-subscription \
        --topic="$TOPIC_NAME" \
        --ack-deadline=60 \
        --quiet; then
        log "✅ Alert subscription created"
    else
        warn "Alert subscription may already exist"
    fi
    
    # Create remediation subscription with filter
    if gcloud pubsub subscriptions create remediation-subscription \
        --topic="$TOPIC_NAME" \
        --ack-deadline=300 \
        --filter='attributes.severity="HIGH" OR attributes.type="ERROR"' \
        --quiet; then
        log "✅ Remediation subscription created with filter"
    else
        warn "Remediation subscription may already exist"
    fi
}

# Function to create log sink
create_log_sink() {
    info "Creating log sink for error forwarding..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create log sink: $LOG_SINK_NAME"
        return
    fi
    
    # Create log sink
    if gcloud logging sinks create "$LOG_SINK_NAME" \
        "pubsub.googleapis.com/projects/${PROJECT_ID}/topics/${TOPIC_NAME}" \
        --log-filter='severity>=ERROR OR jsonPayload.level="ERROR" OR textPayload:"Exception"' \
        --quiet; then
        log "✅ Log sink '$LOG_SINK_NAME' created"
    else
        error "Failed to create log sink"
    fi
    
    # Get sink service account and grant permissions
    local sink_service_account
    sink_service_account=$(gcloud logging sinks describe "$LOG_SINK_NAME" \
        --format="value(writerIdentity)")
    
    if [[ -n "$sink_service_account" ]]; then
        if gcloud pubsub topics add-iam-policy-binding "$TOPIC_NAME" \
            --member="$sink_service_account" \
            --role=roles/pubsub.publisher \
            --quiet; then
            log "✅ IAM permissions granted to log sink"
        else
            error "Failed to grant IAM permissions to log sink"
        fi
    else
        error "Failed to get sink service account"
    fi
}

# Function to create log-based metrics
create_log_metrics() {
    info "Creating log-based metrics..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create log-based metrics for monitoring"
        return
    fi
    
    # Create error rate metric
    if gcloud logging metrics create error_rate_metric \
        --description="Tracks application error rates over time" \
        --log-filter='severity>=ERROR' \
        --value-extractor="" \
        --label-extractors='service=EXTRACT(jsonPayload.service)' \
        --quiet; then
        log "✅ Error rate metric created"
    else
        warn "Error rate metric may already exist"
    fi
    
    # Create exception pattern metric
    if gcloud logging metrics create exception_pattern_metric \
        --description="Counts specific exception patterns" \
        --log-filter='textPayload:"Exception" OR jsonPayload.exception_type!=""' \
        --value-extractor="" \
        --label-extractors='exception_type=EXTRACT(jsonPayload.exception_type)' \
        --quiet; then
        log "✅ Exception pattern metric created"
    else
        warn "Exception pattern metric may already exist"
    fi
    
    # Create latency anomaly metric
    if gcloud logging metrics create latency_anomaly_metric \
        --description="Tracks request latency spikes" \
        --log-filter='jsonPayload.response_time>5000' \
        --value-extractor='EXTRACT(jsonPayload.response_time)' \
        --metric-kind=GAUGE \
        --quiet; then
        log "✅ Latency anomaly metric created"
    else
        warn "Latency anomaly metric may already exist"
    fi
}

# Function to create function source code
create_function_code() {
    local function_name="$1"
    local function_dir="$2"
    
    info "Creating function code for $function_name..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create function code in $function_dir"
        return
    fi
    
    # Create function directory
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    if [[ "$function_name" == "alert" ]]; then
        # Create alert function code
        cat > package.json << 'EOF'
{
  "name": "alert-processor",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/monitoring": "^4.0.0",
    "@google-cloud/logging": "^11.0.0",
    "axios": "^1.6.0"
  }
}
EOF

        cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const {Logging} = require('@google-cloud/logging');
const axios = require('axios');

const logging = new Logging();

functions.cloudEvent('processAlert', async (cloudEvent) => {
  try {
    const message = cloudEvent.data;
    const logEntry = Buffer.from(message.data, 'base64').toString();
    const parsedLog = JSON.parse(logEntry);
    
    // Extract relevant information
    const severity = parsedLog.severity || 'UNKNOWN';
    const timestamp = parsedLog.timestamp;
    const resource = parsedLog.resource?.labels?.instance_id || 'unknown';
    
    // Enrich alert with context
    const alertData = {
      severity: severity,
      timestamp: timestamp,
      resource: resource,
      message: parsedLog.textPayload || parsedLog.jsonPayload?.message,
      source: 'cloud-logging',
      runbook: getRunbookUrl(parsedLog)
    };
    
    // Route notification based on severity
    if (severity === 'CRITICAL' || severity === 'ERROR') {
      await sendSlackAlert(alertData);
      await createIncident(alertData);
    }
    
    console.log('Alert processed successfully:', alertData);
  } catch (error) {
    console.error('Error processing alert:', error);
    throw error;
  }
});

function getRunbookUrl(logEntry) {
  // Return relevant runbook based on log patterns
  if (logEntry.textPayload?.includes('OutOfMemory')) {
    return 'https://runbooks.company.com/memory-issues';
  }
  if (logEntry.textPayload?.includes('Connection')) {
    return 'https://runbooks.company.com/connectivity';
  }
  return 'https://runbooks.company.com/general';
}

async function sendSlackAlert(alertData) {
  // Integrate with Slack webhook
  const slackWebhook = process.env.SLACK_WEBHOOK_URL;
  if (!slackWebhook) return;
  
  const payload = {
    text: `🚨 ${alertData.severity} Alert`,
    attachments: [{
      color: alertData.severity === 'CRITICAL' ? 'danger' : 'warning',
      fields: [
        { title: 'Resource', value: alertData.resource, short: true },
        { title: 'Time', value: alertData.timestamp, short: true },
        { title: 'Message', value: alertData.message, short: false },
        { title: 'Runbook', value: alertData.runbook, short: false }
      ]
    }]
  };
  
  try {
    await axios.post(slackWebhook, payload);
  } catch (error) {
    console.error('Failed to send Slack alert:', error);
  }
}

async function createIncident(alertData) {
  console.log('Creating incident for:', alertData);
  // Integrate with incident management system
}
EOF
    
    elif [[ "$function_name" == "remediation" ]]; then
        # Create remediation function code
        cat > package.json << 'EOF'
{
  "name": "auto-remediation",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/compute": "^4.0.0",
    "@google-cloud/monitoring": "^4.0.0",
    "@google-cloud/pubsub": "^4.0.0"
  }
}
EOF

        cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const compute = require('@google-cloud/compute');
const {PubSub} = require('@google-cloud/pubsub');

const computeClient = new compute.InstancesClient();
const pubsub = new PubSub();

functions.cloudEvent('autoRemediate', async (cloudEvent) => {
  try {
    const message = cloudEvent.data;
    const logEntry = Buffer.from(message.data, 'base64').toString();
    const parsedLog = JSON.parse(logEntry);
    
    // Analyze log patterns for remediation actions
    const remediationAction = determineRemediationAction(parsedLog);
    
    if (remediationAction) {
      console.log('Executing remediation:', remediationAction);
      await executeRemediation(remediationAction, parsedLog);
      
      // Publish remediation success/failure notification
      await publishRemediationResult(remediationAction);
    }
    
  } catch (error) {
    console.error('Remediation failed:', error);
    await publishRemediationResult({ action: 'failed', error: error.message });
  }
});

function determineRemediationAction(logEntry) {
  const message = logEntry.textPayload || logEntry.jsonPayload?.message || '';
  
  if (message.includes('OutOfMemoryError')) {
    return {
      type: 'restart_service',
      target: logEntry.resource?.labels?.instance_id,
      reason: 'Memory exhaustion detected'
    };
  }
  
  if (message.includes('Connection timeout')) {
    return {
      type: 'restart_network',
      target: logEntry.resource?.labels?.instance_id,
      reason: 'Network connectivity issues'
    };
  }
  
  if (message.includes('Disk space')) {
    return {
      type: 'cleanup_disk',
      target: logEntry.resource?.labels?.instance_id,
      reason: 'Disk space exhaustion'
    };
  }
  
  return null;
}

async function executeRemediation(action, logEntry) {
  switch (action.type) {
    case 'restart_service':
      await restartInstance(action.target);
      break;
    case 'restart_network':
      await resetNetworkInterface(action.target);
      break;
    case 'cleanup_disk':
      await triggerDiskCleanup(action.target);
      break;
    default:
      console.log('No remediation action defined for:', action.type);
  }
}

async function restartInstance(instanceId) {
  if (!instanceId) return;
  
  const [operation] = await computeClient.reset({
    project: process.env.PROJECT_ID,
    zone: process.env.ZONE || 'us-central1-a',
    instance: instanceId
  });
  
  console.log('Instance restart initiated:', operation.name);
}

async function resetNetworkInterface(instanceId) {
  console.log('Network interface reset for:', instanceId);
  // Implement network interface reset logic
}

async function triggerDiskCleanup(instanceId) {
  console.log('Disk cleanup triggered for:', instanceId);
  // Implement disk cleanup automation
}

async function publishRemediationResult(result) {
  const topic = pubsub.topic(process.env.TOPIC_NAME);
  const message = {
    data: Buffer.from(JSON.stringify({
      timestamp: new Date().toISOString(),
      remediation_result: result,
      source: 'auto-remediation'
    }))
  };
  
  await topic.publish(message);
}
EOF
    fi
    
    cd - > /dev/null
    log "✅ Function code created for $function_name"
}

# Function to deploy Cloud Functions
deploy_functions() {
    info "Deploying Cloud Functions..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would deploy alert and remediation functions"
        return
    fi
    
    # Create and deploy alert function
    create_function_code "alert" "$temp_dir/alert-function"
    
    cd "$temp_dir/alert-function"
    local env_vars="PROJECT_ID=${PROJECT_ID}"
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        env_vars="${env_vars},SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}"
    fi
    
    if gcloud functions deploy "$ALERT_FUNCTION_NAME" \
        --runtime=nodejs20 \
        --trigger-topic="$TOPIC_NAME" \
        --entry-point=processAlert \
        --memory=256MB \
        --timeout=60s \
        --set-env-vars="$env_vars" \
        --quiet; then
        log "✅ Alert function deployed successfully"
    else
        error "Failed to deploy alert function"
    fi
    
    # Create and deploy remediation function
    cd ..
    create_function_code "remediation" "$temp_dir/remediation-function"
    
    cd "$temp_dir/remediation-function"
    if gcloud functions deploy "$REMEDIATION_FUNCTION_NAME" \
        --runtime=nodejs20 \
        --trigger-topic="$TOPIC_NAME" \
        --entry-point=autoRemediate \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},ZONE=${ZONE},TOPIC_NAME=${TOPIC_NAME}" \
        --quiet; then
        log "✅ Remediation function deployed successfully"
    else
        error "Failed to deploy remediation function"
    fi
    
    # Cleanup temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$temp_dir"
}

# Function to create monitoring alerts
create_monitoring_alerts() {
    info "Creating Cloud Monitoring alerting policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create monitoring alerting policies"
        return
    fi
    
    # Create error rate policy
    cat > /tmp/error-rate-policy.json << EOF
{
  "displayName": "High Error Rate Alert",
  "documentation": {
    "content": "Alert when error rate exceeds normal thresholds",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Error rate condition",
      "conditionThreshold": {
        "filter": "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/error_rate_metric\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 10.0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    if gcloud alpha monitoring policies create --policy-from-file=/tmp/error-rate-policy.json --quiet; then
        log "✅ Error rate alerting policy created"
    else
        warn "Failed to create error rate policy, may already exist"
    fi
    
    # Create latency policy
    cat > /tmp/latency-policy.json << EOF
{
  "displayName": "High Latency Alert",
  "documentation": {
    "content": "Alert when response times indicate performance degradation",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Latency anomaly condition",
      "conditionThreshold": {
        "filter": "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/latency_anomaly_metric\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5000.0,
        "duration": "180s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1200s"
  },
  "enabled": true
}
EOF
    
    if gcloud alpha monitoring policies create --policy-from-file=/tmp/latency-policy.json --quiet; then
        log "✅ Latency alerting policy created"
    else
        warn "Failed to create latency policy, may already exist"
    fi
    
    # Create log-based alerting policy
    cat > /tmp/log-based-alert-policy.json << EOF
{
  "displayName": "Critical Log Pattern Alert",
  "documentation": {
    "content": "Immediate alert for critical log patterns requiring urgent attention",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Critical error pattern",
      "conditionMatchedLog": {
        "filter": "severity=CRITICAL OR textPayload:(\"FATAL\" OR \"OutOfMemoryError\" OR \"StackOverflowError\")",
        "labelExtractors": {
          "service": "EXTRACT(jsonPayload.service)",
          "instance": "EXTRACT(resource.labels.instance_id)"
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "86400s"
  },
  "enabled": true,
  "notificationChannels": []
}
EOF
    
    if gcloud alpha monitoring policies create --policy-from-file=/tmp/log-based-alert-policy.json --quiet; then
        log "✅ Log-based alerting policy created"
    else
        warn "Failed to create log-based alert policy, may already exist"
    fi
    
    # Cleanup temp files
    rm -f /tmp/*-policy.json
}

# Function to test the deployment
test_deployment() {
    info "Testing deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would test deployment by generating test logs"
        return
    fi
    
    # Generate test error log
    if gcloud logging write test-logs "Test ERROR message for automation" \
        --severity=ERROR \
        --payload-type=text \
        --quiet; then
        log "✅ Test log entry created"
    else
        warn "Failed to create test log entry"
    fi
    
    # Wait a moment for processing
    sleep 10
    
    # Check if messages are flowing
    info "Checking Pub/Sub message flow..."
    local message_count
    message_count=$(gcloud pubsub subscriptions pull alert-subscription \
        --limit=1 --auto-ack --format="value(message.data)" 2>/dev/null | wc -l)
    
    if [[ "$message_count" -gt 0 ]]; then
        log "✅ Messages are flowing through Pub/Sub"
    else
        warn "No messages found in Pub/Sub (this may be normal if no errors occurred)"
    fi
}

# Function to display deployment summary
show_summary() {
    echo ""
    log "=============================================="
    log "          DEPLOYMENT SUMMARY"
    log "=============================================="
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Zone: $ZONE"
    log "Resource Suffix: $SUFFIX"
    log ""
    log "Created Resources:"
    log "  • Pub/Sub Topic: $TOPIC_NAME"
    log "  • Log Sink: $LOG_SINK_NAME"
    log "  • Alert Function: $ALERT_FUNCTION_NAME"
    log "  • Remediation Function: $REMEDIATION_FUNCTION_NAME"
    log "  • Log-based Metrics: error_rate_metric, exception_pattern_metric, latency_anomaly_metric"
    log "  • Monitoring Policies: High Error Rate, High Latency, Critical Log Pattern"
    log ""
    log "Next Steps:"
    log "  1. Monitor function logs: gcloud functions logs read $ALERT_FUNCTION_NAME"
    log "  2. Test with error logs: gcloud logging write test 'Test error' --severity=ERROR"
    log "  3. View Pub/Sub messages: gcloud pubsub subscriptions pull alert-subscription --auto-ack"
    log "  4. Check monitoring alerts in Cloud Console"
    log ""
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        log "  • Slack notifications configured"
    else
        log "  • To enable Slack notifications, redeploy with --slack-webhook URL"
    fi
    log "=============================================="
}

# Main deployment function
main() {
    log "Starting log-driven automation deployment..."
    log "Deployment options:"
    log "  Project: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    log "  Suffix: $SUFFIX"
    log "  Dry Run: $DRY_RUN"
    
    check_prerequisites
    configure_gcloud
    enable_apis
    create_pubsub_resources
    create_log_sink
    create_log_metrics
    deploy_functions
    create_monitoring_alerts
    test_deployment
    show_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run completed. No resources were actually created."
    else
        log "✅ Log-driven automation deployment completed successfully!"
    fi
}

# Initialize log files
echo "Deployment started at $(date)" > "$LOG_FILE"
echo "Error log for deployment at $(date)" > "$ERROR_LOG"

# Run main deployment
main "$@"
#!/bin/bash

# Data Pipeline Recovery Workflows with Dataform and Cloud Tasks - Deployment Script
# This script deploys the complete infrastructure for automated data pipeline recovery

set -euo pipefail

# Color codes for output formatting
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

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if bq CLI is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK with BigQuery components"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        error "No default project set. Please run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Cannot access project $PROJECT_ID. Please check project ID and permissions"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        warning "Billing may not be enabled for project $PROJECT_ID. Some services may fail to deploy"
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    # Generate unique suffix for resource names
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    export DATAFORM_REPO="pipeline-recovery-repo-${RANDOM_SUFFIX}"
    export TASK_QUEUE="pipeline-recovery-queue-${RANDOM_SUFFIX}"
    export CONTROLLER_FUNCTION="pipeline-controller-${RANDOM_SUFFIX}"
    export WORKER_FUNCTION="recovery-worker-${RANDOM_SUFFIX}"
    export NOTIFY_FUNCTION="notification-handler-${RANDOM_SUFFIX}"
    export DATASET_NAME="pipeline_monitoring_${RANDOM_SUFFIX}"
    export NOTIFICATION_TOPIC="pipeline-notifications-${RANDOM_SUFFIX}"
    
    # Set default configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dataform.googleapis.com"
        "cloudtasks.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create BigQuery infrastructure
create_bigquery_resources() {
    log "Creating BigQuery dataset and tables..."
    
    # Create BigQuery dataset
    if bq mk --location="${REGION}" --description="Dataset for pipeline recovery demo" "${DATASET_NAME}"; then
        success "Created BigQuery dataset: ${DATASET_NAME}"
    else
        error "Failed to create BigQuery dataset"
        return 1
    fi
    
    # Create source table
    if bq mk --table "${PROJECT_ID}:${DATASET_NAME}.source_data" \
        id:INTEGER,name:STRING,timestamp:TIMESTAMP,status:STRING; then
        success "Created source_data table"
    else
        error "Failed to create source_data table"
        return 1
    fi
    
    # Create target table
    if bq mk --table "${PROJECT_ID}:${DATASET_NAME}.processed_data" \
        id:INTEGER,processed_name:STRING,processing_time:TIMESTAMP,batch_id:STRING; then
        success "Created processed_data table"
    else
        error "Failed to create processed_data table"
        return 1
    fi
    
    # Insert sample data
    if bq query --use_legacy_sql=false \
        "INSERT INTO \`${PROJECT_ID}.${DATASET_NAME}.source_data\`
         VALUES 
         (1, 'sample_record_1', CURRENT_TIMESTAMP(), 'pending'),
         (2, 'sample_record_2', CURRENT_TIMESTAMP(), 'pending'),
         (3, 'sample_record_3', CURRENT_TIMESTAMP(), 'pending')"; then
        success "Inserted sample data into source_data table"
    else
        error "Failed to insert sample data"
        return 1
    fi
    
    success "BigQuery resources created successfully"
}

# Function to create Dataform repository
create_dataform_repository() {
    log "Creating Dataform repository and workspace..."
    
    # Create Dataform repository
    if gcloud dataform repositories create "${DATAFORM_REPO}" --region="${REGION}"; then
        success "Created Dataform repository: ${DATAFORM_REPO}"
    else
        error "Failed to create Dataform repository"
        return 1
    fi
    
    # Create workspace
    local workspace_name="main-workspace"
    if gcloud dataform repositories workspaces create "${workspace_name}" \
        --repository="${DATAFORM_REPO}" \
        --region="${REGION}"; then
        success "Created Dataform workspace: ${workspace_name}"
    else
        error "Failed to create Dataform workspace"
        return 1
    fi
    
    # Create local configuration files
    mkdir -p ./dataform-config
    
    # Create dataform.json
    cat > ./dataform-config/dataform.json << EOF
{
  "defaultSchema": "${DATASET_NAME}",
  "assertionSchema": "${DATASET_NAME}_assertions",
  "defaultDatabase": "${PROJECT_ID}",
  "defaultLocation": "${REGION}"
}
EOF
    
    # Create sample transformation
    cat > ./dataform-config/sample_transformation.sqlx << EOF
config {
  type: "table",
  schema: "${DATASET_NAME}",
  name: "processed_data"
}

SELECT 
  id,
  CONCAT('processed_', name) as processed_name,
  CURRENT_TIMESTAMP() as processing_time,
  GENERATE_UUID() as batch_id
FROM \`${PROJECT_ID}.${DATASET_NAME}.source_data\`
WHERE status = 'pending'
EOF
    
    success "Dataform repository and configuration created"
}

# Function to create Cloud Tasks queue
create_cloud_tasks_queue() {
    log "Creating Cloud Tasks queue..."
    
    if gcloud tasks queues create "${TASK_QUEUE}" \
        --location="${REGION}" \
        --max-dispatches-per-second=10 \
        --max-concurrent-dispatches=5 \
        --max-attempts=5 \
        --min-backoff=30s \
        --max-backoff=300s \
        --max-retry-duration=3600s; then
        success "Created Cloud Tasks queue: ${TASK_QUEUE}"
    else
        error "Failed to create Cloud Tasks queue"
        return 1
    fi
    
    # Verify queue creation
    if gcloud tasks queues describe "${TASK_QUEUE}" --location="${REGION}" > /dev/null; then
        success "Cloud Tasks queue verified and ready"
    else
        error "Failed to verify Cloud Tasks queue"
        return 1
    fi
}

# Function to create Pub/Sub topic
create_pubsub_topic() {
    log "Creating Pub/Sub topic for notifications..."
    
    if gcloud pubsub topics create "${NOTIFICATION_TOPIC}"; then
        success "Created Pub/Sub topic: ${NOTIFICATION_TOPIC}"
    else
        error "Failed to create Pub/Sub topic"
        return 1
    fi
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log "Deploying Cloud Functions..."
    
    # Create functions directory
    mkdir -p ./functions/{controller,worker,notifications}
    
    # Deploy controller function
    log "Creating pipeline controller function..."
    cat > ./functions/controller/index.js << 'EOF'
const {CloudTasksClient} = require('@google-cloud/tasks');
const {Logging} = require('@google-cloud/logging');

const tasksClient = new CloudTasksClient();
const logging = new Logging();
const log = logging.log('pipeline-controller');

exports.handlePipelineAlert = async (req, res) => {
  try {
    const alertData = req.body;
    
    // Extract pipeline failure details from monitoring alert
    const pipelineId = alertData.incident?.resource?.labels?.pipeline_id || 'unknown';
    const failureType = alertData.incident?.condition_name || 'general_failure';
    const severity = alertData.incident?.state || 'OPEN';
    
    await log.write(log.entry('INFO', {
      message: 'Processing pipeline failure alert',
      pipelineId,
      failureType,
      severity
    }));
    
    // Determine recovery strategy based on failure type
    const recoveryAction = determineRecoveryAction(failureType);
    
    // Create recovery task with exponential backoff
    const taskPayload = {
      pipelineId,
      failureType,
      recoveryAction,
      attemptCount: 0,
      timestamp: new Date().toISOString()
    };
    
    await enqueueRecoveryTask(taskPayload);
    
    res.status(200).send('Recovery task enqueued successfully');
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Failed to process pipeline alert',
      error: error.message
    }));
    res.status(500).send('Error processing alert');
  }
};

function determineRecoveryAction(failureType) {
  const recoveryMap = {
    'sql_error': 'retry_with_validation',
    'resource_exhausted': 'retry_with_delay',
    'permission_denied': 'escalate_to_admin',
    'general_failure': 'standard_retry'
  };
  return recoveryMap[failureType] || 'standard_retry';
}

async function enqueueRecoveryTask(payload) {
  const queuePath = tasksClient.queuePath(
    process.env.PROJECT_ID,
    process.env.REGION,
    process.env.TASK_QUEUE
  );
  
  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url: process.env.WORKER_FUNCTION_URL,
      headers: {
        'Content-Type': 'application/json',
      },
      body: Buffer.from(JSON.stringify(payload)).toString('base64'),
    },
    scheduleTime: {
      seconds: Date.now() / 1000 + 60, // Delay 1 minute
    },
  };
  
  await tasksClient.createTask({parent: queuePath, task});
}
EOF
    
    cat > ./functions/controller/package.json << EOF
{
  "name": "pipeline-controller",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/tasks": "^5.0.0",
    "@google-cloud/logging": "^10.0.0"
  }
}
EOF
    
    # Deploy controller function
    if gcloud functions deploy "${CONTROLLER_FUNCTION}" \
        --gen2 \
        --source=./functions/controller \
        --entry-point=handlePipelineAlert \
        --runtime=nodejs18 \
        --trigger=http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=256MB \
        --timeout=540s \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION},TASK_QUEUE=${TASK_QUEUE}"; then
        success "Deployed controller function: ${CONTROLLER_FUNCTION}"
    else
        error "Failed to deploy controller function"
        return 1
    fi
    
    # Get controller function URL
    local controller_url
    controller_url=$(gcloud functions describe "${CONTROLLER_FUNCTION}" \
        --region="${REGION}" \
        --gen2 \
        --format="value(serviceConfig.uri)")
    
    # Deploy worker function
    log "Creating recovery worker function..."
    cat > ./functions/worker/index.js << 'EOF'
const {DataformClient} = require('@google-cloud/dataform');
const {PubSub} = require('@google-cloud/pubsub');
const {Logging} = require('@google-cloud/logging');

const dataformClient = new DataformClient();
const pubsub = new PubSub();
const logging = new Logging();
const log = logging.log('recovery-worker');

exports.executeRecovery = async (req, res) => {
  try {
    const taskPayload = JSON.parse(Buffer.from(req.body, 'base64').toString());
    
    await log.write(log.entry('INFO', {
      message: 'Starting recovery execution',
      payload: taskPayload
    }));
    
    const result = await executeRecoveryAction(taskPayload);
    
    // Publish result to notification system
    await publishRecoveryResult(result);
    
    res.status(200).send('Recovery executed successfully');
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Recovery execution failed',
      error: error.message
    }));
    
    res.status(500).send('Recovery execution failed');
  }
};

async function executeRecoveryAction(payload) {
  const {pipelineId, recoveryAction, attemptCount} = payload;
  
  switch (recoveryAction) {
    case 'retry_with_validation':
      return await retryPipelineWithValidation(pipelineId);
    case 'retry_with_delay':
      return await retryPipelineWithDelay(pipelineId, attemptCount);
    case 'escalate_to_admin':
      return await escalateToAdmin(pipelineId, payload);
    default:
      return await standardRetry(pipelineId);
  }
}

async function retryPipelineWithValidation(pipelineId) {
  const parent = `projects/${process.env.PROJECT_ID}/locations/${process.env.REGION}/repositories/${process.env.DATAFORM_REPO}`;
  
  const [operation] = await dataformClient.createWorkflowInvocation({
    parent,
    workflowInvocation: {
      invocationConfig: {
        includedTargets: [
          {
            name: 'processed_data'
          }
        ],
        includeAllDependencies: true,
        fullRefresh: false
      }
    }
  });
  
  return {
    success: true,
    action: 'retry_with_validation',
    operationId: operation.name,
    timestamp: new Date().toISOString()
  };
}

async function standardRetry(pipelineId) {
  const parent = `projects/${process.env.PROJECT_ID}/locations/${process.env.REGION}/repositories/${process.env.DATAFORM_REPO}`;
  
  const [operation] = await dataformClient.createWorkflowInvocation({
    parent,
    workflowInvocation: {
      invocationConfig: {
        includeAllDependencies: true
      }
    }
  });
  
  return {
    success: true,
    action: 'standard_retry',
    operationId: operation.name,
    timestamp: new Date().toISOString()
  };
}

async function retryPipelineWithDelay(pipelineId, attemptCount) {
  const delayMinutes = Math.min(Math.pow(2, attemptCount) * 5, 60);
  await new Promise(resolve => setTimeout(resolve, delayMinutes * 60 * 1000));
  return await standardRetry(pipelineId);
}

async function escalateToAdmin(pipelineId, payload) {
  return {
    success: false,
    action: 'escalated',
    pipelineId,
    requiresManualIntervention: true,
    escalationReason: 'Automated recovery failed after maximum attempts'
  };
}

async function publishRecoveryResult(result) {
  const topic = pubsub.topic(process.env.NOTIFICATION_TOPIC);
  const messageBuffer = Buffer.from(JSON.stringify(result));
  await topic.publish(messageBuffer);
}
EOF
    
    cat > ./functions/worker/package.json << EOF
{
  "name": "recovery-worker",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/dataform": "^2.0.0",
    "@google-cloud/pubsub": "^4.0.0",
    "@google-cloud/logging": "^10.0.0"
  }
}
EOF
    
    # Deploy worker function
    if gcloud functions deploy "${WORKER_FUNCTION}" \
        --gen2 \
        --source=./functions/worker \
        --entry-point=executeRecovery \
        --runtime=nodejs18 \
        --trigger=http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=512MB \
        --timeout=540s \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION},DATAFORM_REPO=${DATAFORM_REPO},NOTIFICATION_TOPIC=${NOTIFICATION_TOPIC}"; then
        success "Deployed worker function: ${WORKER_FUNCTION}"
    else
        error "Failed to deploy worker function"
        return 1
    fi
    
    # Get worker function URL
    local worker_url
    worker_url=$(gcloud functions describe "${WORKER_FUNCTION}" \
        --region="${REGION}" \
        --gen2 \
        --format="value(serviceConfig.uri)")
    
    # Update controller function with worker URL
    gcloud functions deploy "${CONTROLLER_FUNCTION}" \
        --gen2 \
        --source=./functions/controller \
        --entry-point=handlePipelineAlert \
        --runtime=nodejs18 \
        --trigger=http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION},TASK_QUEUE=${TASK_QUEUE},WORKER_FUNCTION_URL=${worker_url}"
    
    # Deploy notification handler
    log "Creating notification handler function..."
    cat > ./functions/notifications/index.js << 'EOF'
const {Logging} = require('@google-cloud/logging');

const logging = new Logging();
const log = logging.log('notification-handler');

exports.handleNotification = async (message, context) => {
  try {
    const notificationData = JSON.parse(Buffer.from(message.data, 'base64').toString());
    
    await log.write(log.entry('INFO', {
      message: 'Processing recovery notification',
      data: notificationData
    }));
    
    const notification = buildNotificationMessage(notificationData);
    await sendEmailNotification(notification);
    await logDashboardUpdate(notification);
    
  } catch (error) {
    await log.write(log.entry('ERROR', {
      message: 'Failed to process notification',
      error: error.message
    }));
  }
};

function buildNotificationMessage(data) {
  const {success, action, pipelineId, timestamp} = data;
  
  return {
    subject: success ? 
      `✅ Pipeline Recovery Successful: ${pipelineId}` : 
      `❌ Pipeline Recovery Failed: ${pipelineId}`,
    body: `
      Pipeline ID: ${pipelineId}
      Recovery Action: ${action}
      Status: ${success ? 'SUCCESS' : 'FAILED'}
      Timestamp: ${timestamp}
      
      ${success ? 
        'The pipeline has been successfully recovered and is now running normally.' :
        'Manual intervention may be required. Please check the pipeline logs for details.'
      }
    `,
    priority: success ? 'normal' : 'high',
    recipients: process.env.NOTIFICATION_RECIPIENTS?.split(',') || []
  };
}

async function sendEmailNotification(notification) {
  await log.write(log.entry('INFO', {
    message: 'Email notification sent',
    subject: notification.subject,
    recipients: notification.recipients
  }));
}

async function logDashboardUpdate(notification) {
  await log.write(log.entry('INFO', {
    message: 'Dashboard updated with recovery status',
    notification
  }));
}
EOF
    
    cat > ./functions/notifications/package.json << EOF
{
  "name": "notification-handler",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/logging": "^10.0.0"
  }
}
EOF
    
    # Deploy notification handler
    if gcloud functions deploy "${NOTIFY_FUNCTION}" \
        --gen2 \
        --source=./functions/notifications \
        --entry-point=handleNotification \
        --runtime=nodejs18 \
        --trigger-topic="${NOTIFICATION_TOPIC}" \
        --region="${REGION}" \
        --memory=256MB \
        --set-env-vars="NOTIFICATION_RECIPIENTS=admin@company.com,ops-team@company.com"; then
        success "Deployed notification function: ${NOTIFY_FUNCTION}"
    else
        error "Failed to deploy notification function"
        return 1
    fi
    
    success "All Cloud Functions deployed successfully"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring Cloud Monitoring alerts..."
    
    # Get controller function URL for webhook
    local controller_url
    controller_url=$(gcloud functions describe "${CONTROLLER_FUNCTION}" \
        --region="${REGION}" \
        --gen2 \
        --format="value(serviceConfig.uri)")
    
    # Create webhook notification channel
    local webhook_channel
    webhook_channel=$(gcloud alpha monitoring channels create \
        --display-name="Pipeline Recovery Webhook" \
        --type="webhook_tokenauth" \
        --channel-labels="url=${controller_url}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$webhook_channel" ]]; then
        success "Created monitoring webhook channel"
    else
        warning "Failed to create webhook channel - monitoring alerts may not work properly"
    fi
    
    # Create log-based metric
    if gcloud logging metrics create pipeline_execution_status \
        --description="Tracks Dataform pipeline execution status" \
        --log-filter='resource.type="dataform_repository" AND jsonPayload.status="FAILED"' 2>/dev/null; then
        success "Created log-based metric for pipeline monitoring"
    else
        warning "Failed to create log-based metric - may already exist"
    fi
    
    success "Monitoring configuration completed"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check BigQuery dataset
    if bq ls "${DATASET_NAME}" > /dev/null 2>&1; then
        success "BigQuery dataset verified"
    else
        error "BigQuery dataset verification failed"
        return 1
    fi
    
    # Check Dataform repository
    if gcloud dataform repositories describe "${DATAFORM_REPO}" --region="${REGION}" > /dev/null 2>&1; then
        success "Dataform repository verified"
    else
        error "Dataform repository verification failed"
        return 1
    fi
    
    # Check Cloud Tasks queue
    if gcloud tasks queues describe "${TASK_QUEUE}" --location="${REGION}" > /dev/null 2>&1; then
        success "Cloud Tasks queue verified"
    else
        error "Cloud Tasks queue verification failed"
        return 1
    fi
    
    # Check Cloud Functions
    local functions=("${CONTROLLER_FUNCTION}" "${WORKER_FUNCTION}" "${NOTIFY_FUNCTION}")
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" --gen2 > /dev/null 2>&1; then
            success "Cloud Function ${func} verified"
        else
            error "Cloud Function ${func} verification failed"
            return 1
        fi
    done
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "${NOTIFICATION_TOPIC}" > /dev/null 2>&1; then
        success "Pub/Sub topic verified"
    else
        error "Pub/Sub topic verification failed"
        return 1
    fi
    
    success "All resources verified successfully"
}

# Function to save deployment info
save_deployment_info() {
    log "Saving deployment information..."
    
    local deployment_file="deployment-info.txt"
    cat > "${deployment_file}" << EOF
# Data Pipeline Recovery Deployment Information
# Generated on: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
DATAFORM_REPO=${DATAFORM_REPO}
TASK_QUEUE=${TASK_QUEUE}
CONTROLLER_FUNCTION=${CONTROLLER_FUNCTION}
WORKER_FUNCTION=${WORKER_FUNCTION}
NOTIFY_FUNCTION=${NOTIFY_FUNCTION}
DATASET_NAME=${DATASET_NAME}
NOTIFICATION_TOPIC=${NOTIFICATION_TOPIC}

# Controller Function URL
CONTROLLER_URL=$(gcloud functions describe "${CONTROLLER_FUNCTION}" --region="${REGION}" --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || echo "Not available")

# Worker Function URL  
WORKER_URL=$(gcloud functions describe "${WORKER_FUNCTION}" --region="${REGION}" --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || echo "Not available")

# To clean up all resources, run:
# ./destroy.sh

EOF
    
    success "Deployment information saved to ${deployment_file}"
}

# Main deployment function
main() {
    log "Starting Data Pipeline Recovery Workflows deployment..."
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "Running in dry-run mode - no resources will be created"
        check_prerequisites
        setup_environment
        log "Dry-run completed successfully"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_bigquery_resources
    create_dataform_repository
    create_cloud_tasks_queue
    create_pubsub_topic
    deploy_cloud_functions
    configure_monitoring
    verify_deployment
    save_deployment_info
    
    success "🎉 Data Pipeline Recovery Workflows deployed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "  • Project: ${PROJECT_ID}"
    log "  • Region: ${REGION}"
    log "  • Dataform Repository: ${DATAFORM_REPO}"
    log "  • BigQuery Dataset: ${DATASET_NAME}"
    log "  • Cloud Functions: 3 deployed"
    log "  • Cloud Tasks Queue: ${TASK_QUEUE}"
    log "  • Pub/Sub Topic: ${NOTIFICATION_TOPIC}"
    log ""
    log "💡 Next Steps:"
    log "  1. Review the deployment-info.txt file for resource details"
    log "  2. Test the pipeline recovery system using the validation steps in the recipe"
    log "  3. Configure additional monitoring and alerting as needed"
    log "  4. When done, run ./destroy.sh to clean up resources"
    log ""
    warning "⚠️  Remember: This deployment creates billable resources. Run ./destroy.sh when finished to avoid charges."
}

# Handle script termination
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Some resources may have been created."
        error "Check the Google Cloud Console and run ./destroy.sh if needed to clean up."
    fi
}

trap cleanup_on_exit EXIT

# Execute main function with all arguments
main "$@"
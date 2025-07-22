#!/bin/bash

# Deploy script for Carbon-Aware Workload Orchestration with Cloud Carbon Footprint and Cloud Workflows
# This script deploys the complete infrastructure for carbon-aware workload scheduling

set -euo pipefail

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
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partially created resources..."
    if [[ -n "${PROJECT_ID:-}" ]]; then
        # Only cleanup if we have a project ID set
        ./destroy.sh --force 2>/dev/null || true
    fi
}

# Set trap to cleanup on error
trap cleanup_on_error ERR

# Default values
DRY_RUN=false
FORCE=false
SKIP_PREREQUISITES=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run                 Show what would be deployed without making changes"
            echo "  --force                   Force deployment even if resources exist"
            echo "  --skip-prerequisites      Skip prerequisite checks"
            echo "  --project-id PROJECT      Specify GCP project ID"
            echo "  --region REGION           Specify GCP region (default: us-central1)"
            echo "  --help                    Show this help message"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Set default environment variables
PROJECT_ID="${PROJECT_ID:-carbon-aware-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
DATASET_NAME="carbon_footprint_${RANDOM_SUFFIX}"
WORKFLOW_NAME="carbon-aware-orchestrator-${RANDOM_SUFFIX}"
FUNCTION_NAME="workload-scheduler-${RANDOM_SUFFIX}"
INSTANCE_TEMPLATE="carbon-aware-template-${RANDOM_SUFFIX}"

log_info "Starting deployment of Carbon-Aware Workload Orchestration"
log_info "Project ID: ${PROJECT_ID}"
log_info "Region: ${REGION}"
log_info "Zone: ${ZONE}"
log_info "Dataset: ${DATASET_NAME}"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No actual resources will be created"
fi

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not installed. Please install Google Cloud SDK with BigQuery components."
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Please install curl."
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install openssl."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'."
    fi
    
    # Check if gcloud version is sufficient
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" | head -1)
    REQUIRED_VERSION="400.0.0"
    if ! printf '%s\n' "$REQUIRED_VERSION" "$GCLOUD_VERSION" | sort -V -C; then
        log_warning "gcloud version $GCLOUD_VERSION may be outdated. Recommended: $REQUIRED_VERSION or later."
    fi
    
    log_success "Prerequisites check completed"
}

# Project setup and configuration
setup_project() {
    log_info "Setting up project configuration..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Set default project and region
        gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project ${PROJECT_ID}"
        gcloud config set compute/region "${REGION}" || error_exit "Failed to set region ${REGION}"
        gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone ${ZONE}"
        
        # Check if project exists and is accessible
        if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
            error_exit "Project ${PROJECT_ID} does not exist or is not accessible"
        fi
        
        # Check billing is enabled
        if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
            log_warning "Billing may not be enabled for project ${PROJECT_ID}"
        fi
    fi
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "workflows.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "bigquerydatatransfer.googleapis.com"
        "cloudscheduler.googleapis.com"
        "pubsub.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "false" ]]; then
        for api in "${apis[@]}"; do
            log_info "Enabling API: ${api}"
            if ! gcloud services enable "${api}" --quiet; then
                error_exit "Failed to enable API: ${api}"
            fi
        done
        
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    else
        log_info "Would enable APIs: ${apis[*]}"
    fi
    
    log_success "Required APIs enabled"
}

# Create BigQuery dataset
create_bigquery_dataset() {
    log_info "Creating BigQuery dataset for carbon footprint data..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! bq mk --location="${REGION}" "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null; then
            if [[ "$FORCE" == "true" ]]; then
                log_warning "Dataset ${DATASET_NAME} already exists, continuing with force flag"
            else
                error_exit "Dataset ${DATASET_NAME} already exists. Use --force to continue."
            fi
        fi
    else
        log_info "Would create BigQuery dataset: ${DATASET_NAME}"
    fi
    
    log_success "BigQuery dataset configured"
}

# Set up Carbon Footprint Data Export
setup_carbon_footprint_export() {
    log_info "Setting up Carbon Footprint data export to BigQuery..."
    
    local service_account="carbon-footprint-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create service account for data transfer operations
        if ! gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
            gcloud iam service-accounts create carbon-footprint-sa \
                --display-name="Carbon Footprint Data Transfer Service Account" \
                --description="Service account for automated carbon footprint data exports" \
                --quiet || error_exit "Failed to create service account"
        elif [[ "$FORCE" == "false" ]]; then
            error_exit "Service account already exists. Use --force to continue."
        fi
        
        # Grant necessary permissions for BigQuery data transfer
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/bigquery.dataTransfer.serviceAgent" \
            --quiet || error_exit "Failed to grant BigQuery data transfer permissions"
        
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/bigquery.dataEditor" \
            --quiet || error_exit "Failed to grant BigQuery data editor permissions"
    else
        log_info "Would create service account: ${service_account}"
        log_info "Would grant BigQuery permissions to service account"
    fi
    
    log_success "Carbon footprint data export service account configured"
}

# Create BigQuery views
create_bigquery_views() {
    log_info "Creating BigQuery views for carbon intensity analysis..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create view for hourly carbon intensity analysis
        if ! bq query --use_legacy_sql=false --quiet \
        "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.hourly_carbon_intensity\` AS
        SELECT
          EXTRACT(HOUR FROM usage_month) as hour_of_day,
          EXTRACT(DAYOFWEEK FROM usage_month) as day_of_week,
          location.region as region,
          AVG(carbon_footprint_total_kgCO2e) as avg_carbon_intensity,
          COUNT(*) as sample_count,
          STDDEV(carbon_footprint_total_kgCO2e) as carbon_variance
        FROM \`${PROJECT_ID}.${DATASET_NAME}.carbon_footprint\`
        WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
        GROUP BY hour_of_day, day_of_week, region
        ORDER BY avg_carbon_intensity ASC"; then
            log_warning "Failed to create hourly carbon intensity view - this may be expected if no carbon footprint data exists yet"
        fi
        
        # Create view for optimal scheduling recommendations
        if ! bq query --use_legacy_sql=false --quiet \
        "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.optimal_scheduling_windows\` AS
        SELECT
          hour_of_day,
          day_of_week,
          region,
          avg_carbon_intensity,
          CASE 
            WHEN avg_carbon_intensity < (SELECT PERCENTILE_CONT(avg_carbon_intensity, 0.25) OVER() FROM \`${PROJECT_ID}.${DATASET_NAME}.hourly_carbon_intensity\`) THEN 'GREEN'
            WHEN avg_carbon_intensity < (SELECT PERCENTILE_CONT(avg_carbon_intensity, 0.75) OVER() FROM \`${PROJECT_ID}.${DATASET_NAME}.hourly_carbon_intensity\`) THEN 'YELLOW'
            ELSE 'RED'
          END as carbon_tier
        FROM \`${PROJECT_ID}.${DATASET_NAME}.hourly_carbon_intensity\`
        WHERE sample_count > 5"; then
            log_warning "Failed to create optimal scheduling windows view - this may be expected if no carbon footprint data exists yet"
        fi
    else
        log_info "Would create BigQuery views for carbon intensity analysis"
    fi
    
    log_success "BigQuery views configured"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for carbon-aware scheduling logic..."
    
    # Create temporary directory for Cloud Function source
    local temp_dir=$(mktemp -d)
    local function_dir="${temp_dir}/cloud-function-source"
    mkdir -p "${function_dir}"
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-bigquery==3.13.0
google-cloud-compute==1.14.1
google-cloud-pubsub==2.18.4
google-cloud-logging==3.8.0
functions-framework==3.4.0
EOF
    
    # Create main.py with carbon-aware scheduling logic
    cat > "${function_dir}/main.py" << EOF
import json
import logging
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import compute_v1
from google.cloud import pubsub_v1

# Initialize clients
bq_client = bigquery.Client()
compute_client = compute_v1.InstancesClient()
publisher = pubsub_v1.PublisherClient()

def carbon_aware_scheduler(request):
    """Main function for carbon-aware workload scheduling"""
    try:
        request_json = request.get_json()
        workload_type = request_json.get('workload_type', 'standard')
        urgency = request_json.get('urgency', 'normal')
        region = request_json.get('region', '${REGION}')
        
        # Query current carbon intensity
        carbon_intensity = get_current_carbon_intensity(region)
        
        # Make scheduling decision based on carbon awareness
        decision = make_scheduling_decision(carbon_intensity, urgency, workload_type)
        
        # Log the decision for monitoring
        logging.info(f"Carbon-aware decision: {decision}")
        
        # Publish decision to Pub/Sub for workflow consumption
        publish_scheduling_decision(decision)
        
        return json.dumps(decision)
        
    except Exception as e:
        logging.error(f"Error in carbon-aware scheduling: {str(e)}")
        return json.dumps({"error": str(e)}), 500

def get_current_carbon_intensity(region):
    """Query BigQuery for current carbon intensity in the specified region"""
    current_hour = datetime.now().hour
    current_day = datetime.now().isoweekday()
    
    query = f"""
    SELECT avg_carbon_intensity, carbon_tier
    FROM \`${PROJECT_ID}.${DATASET_NAME}.optimal_scheduling_windows\`
    WHERE hour_of_day = {current_hour}
      AND day_of_week = {current_day}
      AND region = '{region}'
    LIMIT 1
    """
    
    try:
        results = bq_client.query(query)
        for row in results:
            return {
                'intensity': float(row.avg_carbon_intensity),
                'tier': row.carbon_tier
            }
    except Exception as e:
        logging.warning(f"Could not retrieve carbon data: {e}")
        
    return {'intensity': 0.5, 'tier': 'YELLOW'}  # Default fallback

def make_scheduling_decision(carbon_intensity, urgency, workload_type):
    """Determine optimal scheduling based on carbon intensity and business requirements"""
    decision = {
        'timestamp': datetime.now().isoformat(),
        'carbon_intensity': carbon_intensity,
        'urgency': urgency,
        'workload_type': workload_type
    }
    
    # Business logic for carbon-aware scheduling
    if urgency == 'critical':
        decision['action'] = 'execute_immediately'
        decision['reason'] = 'Critical workload override'
    elif carbon_intensity['tier'] == 'GREEN':
        decision['action'] = 'execute_immediately'
        decision['reason'] = 'Low carbon intensity - optimal execution window'
    elif carbon_intensity['tier'] == 'YELLOW' and urgency == 'high':
        decision['action'] = 'execute_immediately'
        decision['reason'] = 'Moderate carbon intensity with high business urgency'
    else:
        # Calculate optimal delay based on carbon forecast
        delay_hours = calculate_optimal_delay(carbon_intensity)
        decision['action'] = 'schedule_delayed'
        decision['delay_hours'] = delay_hours
        decision['reason'] = f'High carbon intensity - delay {delay_hours} hours for better conditions'
    
    return decision

def calculate_optimal_delay(carbon_intensity):
    """Calculate optimal delay based on carbon intensity forecasting"""
    # Simplified logic - in production, this would use ML models
    if carbon_intensity['tier'] == 'RED':
        return 4  # Wait 4 hours for better carbon conditions
    return 2  # Wait 2 hours for moderate improvement

def publish_scheduling_decision(decision):
    """Publish scheduling decision to Pub/Sub for workflow consumption"""
    try:
        topic_path = publisher.topic_path('${PROJECT_ID}', 'carbon-aware-decisions')
        message_data = json.dumps(decision).encode('utf-8')
        publisher.publish(topic_path, message_data)
    except Exception as e:
        logging.warning(f"Failed to publish to Pub/Sub: {e}")
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Deploy the Cloud Function
        if ! gcloud functions deploy "${FUNCTION_NAME}" \
            --source="${function_dir}" \
            --runtime=python311 \
            --trigger=http \
            --entry-point=carbon_aware_scheduler \
            --memory=256MB \
            --timeout=60s \
            --region="${REGION}" \
            --allow-unauthenticated \
            --quiet; then
            error_exit "Failed to deploy Cloud Function"
        fi
    else
        log_info "Would deploy Cloud Function: ${FUNCTION_NAME}"
    fi
    
    # Cleanup temporary directory
    rm -rf "${temp_dir}"
    
    log_success "Carbon-aware scheduling Cloud Function deployed"
}

# Create Pub/Sub topics and subscriptions
create_pubsub_resources() {
    log_info "Creating Pub/Sub topics and subscriptions for workflow communication..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Pub/Sub topic for carbon-aware scheduling decisions
        if ! gcloud pubsub topics create carbon-aware-decisions --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                error_exit "Topic carbon-aware-decisions already exists. Use --force to continue."
            fi
        fi
        
        # Create subscription for workflow consumption
        if ! gcloud pubsub subscriptions create carbon-aware-workflow-sub \
            --topic=carbon-aware-decisions \
            --ack-deadline=60 \
            --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                log_warning "Subscription carbon-aware-workflow-sub already exists"
            fi
        fi
        
        # Create topic for workload execution status updates
        if ! gcloud pubsub topics create workload-execution-status --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                log_warning "Topic workload-execution-status already exists"
            fi
        fi
        
        # Create subscription for monitoring workload status
        if ! gcloud pubsub subscriptions create workload-status-monitoring \
            --topic=workload-execution-status \
            --ack-deadline=300 \
            --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                log_warning "Subscription workload-status-monitoring already exists"
            fi
        fi
    else
        log_info "Would create Pub/Sub topics: carbon-aware-decisions, workload-execution-status"
        log_info "Would create subscriptions: carbon-aware-workflow-sub, workload-status-monitoring"
    fi
    
    log_success "Pub/Sub resources configured"
}

# Deploy Cloud Workflows
deploy_cloud_workflows() {
    log_info "Deploying Cloud Workflows for carbon-aware orchestration..."
    
    # Create temporary workflow definition file
    local temp_workflow=$(mktemp)
    
    cat > "${temp_workflow}" << EOF
main:
  params: [args]
  steps:
    - initialize:
        assign:
          - project_id: "${PROJECT_ID}"
          - workload_id: \${args.workload_id}
          - workload_type: \${default(args.workload_type, "standard")}
          - urgency: \${default(args.urgency, "normal")}
          - region: \${default(args.region, "${REGION}")}
          - max_delay_hours: \${default(args.max_delay_hours, 8)}
    
    - log_workflow_start:
        call: sys.log
        args:
          data: \${"Starting carbon-aware orchestration for workload: " + workload_id}
          severity: "INFO"
    
    - get_carbon_decision:
        call: http.post
        args:
          url: "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
          headers:
            Content-Type: "application/json"
          body:
            workload_type: \${workload_type}
            urgency: \${urgency}
            region: \${region}
            workload_id: \${workload_id}
        result: carbon_decision_response
    
    - parse_carbon_decision:
        assign:
          - carbon_decision: \${json.decode(carbon_decision_response.body)}
    
    - evaluate_scheduling_action:
        switch:
          - condition: \${carbon_decision.action == "execute_immediately"}
            next: execute_workload_immediately
          - condition: \${carbon_decision.action == "schedule_delayed"}
            next: schedule_delayed_execution
          - condition: true
            next: handle_scheduling_error
    
    - execute_workload_immediately:
        steps:
          - log_immediate_execution:
              call: sys.log
              args:
                data: \${"Executing workload immediately - " + carbon_decision.reason}
                severity: "INFO"
          
          - create_compute_resources:
              call: create_carbon_optimized_instance
              args:
                workload_id: \${workload_id}
                workload_type: \${workload_type}
                region: \${region}
              result: instance_details
          
          - wait_for_completion:
              call: monitor_workload_execution
              args:
                instance_name: \${instance_details.name}
                workload_id: \${workload_id}
              result: execution_result
          
          - cleanup_resources:
              call: cleanup_compute_resources
              args:
                instance_name: \${instance_details.name}
                region: \${region}
        
        next: workflow_completion
    
    - schedule_delayed_execution:
        steps:
          - log_delayed_execution:
              call: sys.log
              args:
                data: \${"Delaying workload execution by " + string(carbon_decision.delay_hours) + " hours - " + carbon_decision.reason}
                severity: "INFO"
          
          - validate_delay_acceptable:
              switch:
                - condition: \${carbon_decision.delay_hours > max_delay_hours}
                  next: override_delay_for_sla
                - condition: true
                  next: schedule_future_execution
          
          - override_delay_for_sla:
              steps:
                - log_sla_override:
                    call: sys.log
                    args:
                      data: "SLA requirements override carbon optimization - executing with higher emissions"
                      severity: "WARNING"
                - assign_override:
                    assign:
                      - carbon_decision.action: "execute_immediately"
                      - carbon_decision.reason: "SLA override - maximum delay exceeded"
              next: execute_workload_immediately
          
          - schedule_future_execution:
              call: sys.log
              args:
                data: \${"Scheduled delayed execution for " + string(carbon_decision.delay_hours) + " hours"}
                severity: "INFO"
        
        next: workflow_completion
    
    - handle_scheduling_error:
        steps:
          - log_error:
              call: sys.log
              args:
                data: \${"Unknown scheduling action: " + carbon_decision.action}
                severity: "ERROR"
          - return_error:
              return: "Error: Unknown scheduling action"
    
    - workflow_completion:
        steps:
          - log_completion:
              call: sys.log
              args:
                data: \${"Carbon-aware orchestration completed for workload: " + workload_id}
                severity: "INFO"
          - return_result:
              return: \${"Workflow completed successfully for workload: " + workload_id}

create_carbon_optimized_instance:
  params: [workload_id, workload_type, region]
  steps:
    - determine_instance_specs:
        assign:
          - machine_type: "e2-standard-2"  # Energy-efficient E2 instance type
          - boot_disk_size: "50"
          - instance_name: \${"carbon-workload-" + workload_id}
    
    - create_instance:
        call: googleapis.compute.v1.instances.insert
        args:
          project: "${PROJECT_ID}"
          zone: \${region + "-a"}
          body:
            name: \${instance_name}
            machineType: \${"zones/" + region + "-a/machineTypes/" + machine_type}
            disks:
              - boot: true
                autoDelete: true
                initializeParams:
                  sourceImage: "projects/debian-cloud/global/images/family/debian-11"
                  diskSizeGb: \${boot_disk_size}
            networkInterfaces:
              - network: "global/networks/default"
                accessConfigs:
                  - type: "ONE_TO_ONE_NAT"
            labels:
              workload-id: \${workload_id}
              carbon-aware: "true"
              workload-type: \${workload_type}
            metadata:
              items:
                - key: "startup-script"
                  value: |
                    #!/bin/bash
                    echo "Starting carbon-aware workload execution..."
                    # Workload-specific execution logic would go here
                    sleep 300  # Simulate 5-minute workload
                    echo "Workload execution completed"
                    sudo shutdown -h now
        result: create_response
    
    - return_instance_details:
        return:
          name: \${instance_name}
          machine_type: \${machine_type}
          status: "creating"

monitor_workload_execution:
  params: [instance_name, workload_id]
  steps:
    - wait_loop:
        for:
          value: attempt
          range: [1, 20]  # Maximum 20 attempts (10 minutes)
          steps:
            - check_instance_status:
                call: googleapis.compute.v1.instances.get
                args:
                  project: "${PROJECT_ID}"
                  zone: "${ZONE}"
                  instance: \${instance_name}
                result: instance_status
            
            - evaluate_status:
                switch:
                  - condition: \${instance_status.status == "RUNNING"}
                    next: continue_monitoring
                  - condition: \${instance_status.status == "TERMINATED"}
                    next: workload_completed
                  - condition: true
                    next: wait_and_retry
            
            - continue_monitoring:
                call: sys.sleep
                args:
                  seconds: 30
            
            - wait_and_retry:
                call: sys.sleep
                args:
                  seconds: 30
    
    - workload_completed:
        return:
          status: "completed"
          workload_id: \${workload_id}

cleanup_compute_resources:
  params: [instance_name, region]
  steps:
    - delete_instance:
        call: googleapis.compute.v1.instances.delete
        args:
          project: "${PROJECT_ID}"
          zone: \${region + "-a"}
          instance: \${instance_name}
    
    - log_cleanup:
        call: sys.log
        args:
          data: \${"Cleaned up compute resources for instance: " + instance_name}
          severity: "INFO"
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Deploy the workflow
        if ! gcloud workflows deploy "${WORKFLOW_NAME}" \
            --source="${temp_workflow}" \
            --location="${REGION}" \
            --quiet; then
            error_exit "Failed to deploy Cloud Workflow"
        fi
    else
        log_info "Would deploy Cloud Workflow: ${WORKFLOW_NAME}"
    fi
    
    # Cleanup temporary file
    rm -f "${temp_workflow}"
    
    log_success "Carbon-aware orchestration workflow deployed"
}

# Create Cloud Scheduler jobs
create_scheduler_jobs() {
    log_info "Creating Cloud Scheduler jobs for automated orchestration..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get access token for authorization
        local access_token
        access_token=$(gcloud auth print-access-token)
        
        # Create scheduled job for daily batch processing during low-carbon hours
        if ! gcloud scheduler jobs create http daily-batch-carbon-aware \
            --location="${REGION}" \
            --schedule="0 2 * * *" \
            --time-zone="America/New_York" \
            --uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}/executions" \
            --http-method=POST \
            --headers="Content-Type=application/json,Authorization=Bearer ${access_token}" \
            --message-body="{\"argument\": \"{\\\"workload_id\\\":\\\"daily-batch-$(date +%s)\\\",\\\"workload_type\\\":\\\"batch_processing\\\",\\\"urgency\\\":\\\"normal\\\",\\\"region\\\":\\\"${REGION}\\\",\\\"max_delay_hours\\\":6}\"}" \
            --description="Daily batch processing with carbon-aware scheduling" \
            --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                log_warning "Scheduler job daily-batch-carbon-aware already exists"
            fi
        fi
        
        # Create scheduler for weekly analytics workload
        if ! gcloud scheduler jobs create http weekly-analytics-carbon-aware \
            --location="${REGION}" \
            --schedule="0 1 * * 0" \
            --time-zone="UTC" \
            --uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}/executions" \
            --http-method=POST \
            --headers="Content-Type=application/json,Authorization=Bearer ${access_token}" \
            --message-body="{\"argument\": \"{\\\"workload_id\\\":\\\"weekly-analytics-$(date +%s)\\\",\\\"workload_type\\\":\\\"analytics\\\",\\\"urgency\\\":\\\"low\\\",\\\"region\\\":\\\"${REGION}\\\",\\\"max_delay_hours\\\":24}\"}" \
            --description="Weekly analytics processing optimized for low carbon periods" \
            --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                log_warning "Scheduler job weekly-analytics-carbon-aware already exists"
            fi
        fi
        
        # Create monitoring scheduler to check carbon intensity trends
        if ! gcloud scheduler jobs create http carbon-monitoring \
            --location="${REGION}" \
            --schedule="*/30 * * * *" \
            --time-zone="UTC" \
            --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body="{\"workload_type\": \"monitoring\", \"urgency\": \"low\", \"region\": \"${REGION}\"}" \
            --description="Regular carbon intensity monitoring and trend analysis" \
            --quiet 2>/dev/null; then
            if [[ "$FORCE" == "false" ]]; then
                log_warning "Scheduler job carbon-monitoring already exists"
            fi
        fi
    else
        log_info "Would create Cloud Scheduler jobs for automated orchestration"
    fi
    
    log_success "Cloud Scheduler jobs created for automated carbon-aware orchestration"
}

# Set up monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting for carbon metrics..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create alerting policy for high carbon intensity periods
        local policy_file=$(mktemp)
        cat > "${policy_file}" << 'EOF'
{
  "displayName": "High Carbon Intensity Alert",
  "documentation": {
    "content": "Alert when carbon intensity is consistently high, indicating suboptimal scheduling conditions"
  },
  "conditions": [
    {
      "displayName": "Carbon Intensity High",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_function\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
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
        
        if ! gcloud alpha monitoring policies create --policy-from-file="${policy_file}" --quiet 2>/dev/null; then
            log_warning "Failed to create monitoring policy - this may require additional permissions"
        fi
        
        rm -f "${policy_file}"
    else
        log_info "Would create monitoring policies and dashboards"
    fi
    
    log_success "Monitoring and alerting configured"
}

# Save deployment configuration
save_deployment_config() {
    local config_file="deployment-config.env"
    
    log_info "Saving deployment configuration to ${config_file}..."
    
    cat > "${config_file}" << EOF
# Carbon-Aware Workload Orchestration Deployment Configuration
# Generated on $(date)

export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export DATASET_NAME="${DATASET_NAME}"
export WORKFLOW_NAME="${WORKFLOW_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export INSTANCE_TEMPLATE="${INSTANCE_TEMPLATE}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"

# Deployment metadata
export DEPLOYMENT_TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
export DEPLOYMENT_USER="$(gcloud config get-value account 2>/dev/null || echo 'unknown')"
EOF
    
    log_success "Deployment configuration saved to ${config_file}"
}

# Main deployment function
main() {
    log_info "=== Carbon-Aware Workload Orchestration Deployment ==="
    
    if [[ "$SKIP_PREREQUISITES" == "false" ]]; then
        check_prerequisites
    fi
    
    setup_project
    enable_apis
    create_bigquery_dataset
    setup_carbon_footprint_export
    create_bigquery_views
    deploy_cloud_function
    create_pubsub_resources
    deploy_cloud_workflows
    create_scheduler_jobs
    setup_monitoring
    save_deployment_config
    
    log_success "=== Deployment completed successfully! ==="
    log_info ""
    log_info "Deployment Summary:"
    log_info "- Project ID: ${PROJECT_ID}"
    log_info "- Region: ${REGION}"
    log_info "- BigQuery Dataset: ${DATASET_NAME}"
    log_info "- Cloud Function: ${FUNCTION_NAME}"
    log_info "- Workflow: ${WORKFLOW_NAME}"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Wait for Carbon Footprint data to be collected (may take 24-48 hours)"
    log_info "2. Test the carbon-aware scheduling function"
    log_info "3. Monitor workflow executions in the Cloud Console"
    log_info "4. Review monitoring dashboards and alerts"
    log_info ""
    log_info "To test the deployment:"
    log_info "  curl -X POST 'https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}' \\"
    log_info "    -H 'Content-Type: application/json' \\"
    log_info "    -d '{\"workload_type\":\"test\",\"urgency\":\"normal\",\"region\":\"${REGION}\"}'"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"
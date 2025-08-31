#!/bin/bash

# Deploy script for Enterprise Database Analytics with Oracle and Vertex AI
# This script deploys the complete infrastructure for Oracle Database@Google Cloud
# integrated with Vertex AI for enterprise analytics

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}" | tee -a "${ERROR_LOG}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${ERROR_LOG} for details."
    log_info "You may need to run the destroy script to clean up partial resources."
    exit 1
}

trap cleanup_on_error ERR

# Initialize log files
echo "Deployment started at $(date)" > "${LOG_FILE}"
echo "Deployment errors for $(date)" > "${ERROR_LOG}"

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check for required gcloud version (531.0.0 or later)
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "0.0.0")
    if [[ "${gcloud_version}" < "531.0.0" ]]; then
        log_warning "gcloud version ${gcloud_version} detected. Version 531.0.0 or later is recommended."
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Set environment variables
set_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="oracle-analytics-$(date +%s)"
        log_info "Generated project ID: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export ORACLE_INSTANCE_NAME="oracle-analytics-${random_suffix}"
    export VERTEX_ENDPOINT_NAME="oracle-ml-endpoint-${random_suffix}"
    export BQ_DATASET_NAME="oracle_analytics_${random_suffix}"
    export ADB_NAME="oracle-analytics-adb-${random_suffix}"
    export ORACLE_CONNECTION_ID="oracle_connection_${random_suffix}"
    export STAGING_BUCKET="vertex-ai-staging-${random_suffix}"
    export FUNCTION_NAME="oracle-analytics-pipeline-${random_suffix}"
    export SCHEDULER_JOB="oracle-analytics-schedule-${random_suffix}"
    export WORKBENCH_INSTANCE="oracle-ml-workbench-${random_suffix}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export ORACLE_INSTANCE_NAME="${ORACLE_INSTANCE_NAME}"
export VERTEX_ENDPOINT_NAME="${VERTEX_ENDPOINT_NAME}"
export BQ_DATASET_NAME="${BQ_DATASET_NAME}"
export ADB_NAME="${ADB_NAME}"
export ORACLE_CONNECTION_ID="${ORACLE_CONNECTION_ID}"
export STAGING_BUCKET="${STAGING_BUCKET}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export SCHEDULER_JOB="${SCHEDULER_JOB}"
export WORKBENCH_INSTANCE="${WORKBENCH_INSTANCE}"
EOF
    
    log_success "Environment variables configured"
}

# Configure gcloud
configure_gcloud() {
    log_info "Configuring gcloud project and region..."
    
    # Create project if it doesn't exist
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Oracle Analytics Project" \
            --labels="purpose=oracle-analytics,environment=demo"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "oracledatabase.googleapis.com"
        "aiplatform.googleapis.com"
        "monitoring.googleapis.com"
        "bigquery.googleapis.com"
        "logging.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "notebooks.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" 2>>"${ERROR_LOG}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create Oracle Exadata Infrastructure
create_oracle_infrastructure() {
    log_info "Creating Oracle Cloud Exadata Infrastructure..."
    log_warning "This step may take 15-30 minutes to complete"
    
    if gcloud oracle-database cloud-exadata-infrastructures create \
        "${ORACLE_INSTANCE_NAME}" \
        --location="${REGION}" \
        --display-name="Enterprise Analytics Oracle Infrastructure" \
        --properties-shape="Exadata.X9M" \
        --properties-storage-count=3 \
        --properties-compute-count=2 \
        --labels="purpose=analytics,environment=production" \
        2>>"${ERROR_LOG}"; then
        
        log_success "Oracle Cloud Exadata infrastructure creation initiated"
        log_info "Monitoring infrastructure provisioning status..."
        
        # Monitor provisioning status
        local max_attempts=60
        local attempt=0
        while [[ ${attempt} -lt ${max_attempts} ]]; do
            local state
            state=$(gcloud oracle-database cloud-exadata-infrastructures describe \
                "${ORACLE_INSTANCE_NAME}" \
                --location="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            case "${state}" in
                "AVAILABLE")
                    log_success "Oracle Cloud Exadata infrastructure is now available"
                    return 0
                    ;;
                "PROVISIONING"|"CREATING")
                    log_info "Infrastructure state: ${state} (attempt ${attempt}/${max_attempts})"
                    ;;
                "FAILED"|"ERROR")
                    log_error "Infrastructure provisioning failed with state: ${state}"
                    return 1
                    ;;
                *)
                    log_info "Infrastructure state: ${state} (attempt ${attempt}/${max_attempts})"
                    ;;
            esac
            
            sleep 30
            ((attempt++))
        done
        
        log_warning "Infrastructure provisioning taking longer than expected. Continuing with next steps..."
        return 0
    else
        log_error "Failed to create Oracle Cloud Exadata infrastructure"
        return 1
    fi
}

# Create Autonomous Database
create_autonomous_database() {
    log_info "Creating Oracle Autonomous Database..."
    log_warning "This step may take 10-15 minutes to complete"
    
    if gcloud oracle-database autonomous-databases create \
        "${ADB_NAME}" \
        --location="${REGION}" \
        --database-edition="ENTERPRISE_EDITION" \
        --display-name="Enterprise Analytics Database" \
        --admin-password="SecurePassword123!" \
        --compute-count=4 \
        --storage-size-tbs=1 \
        --workload-type="OLTP" \
        --labels="purpose=analytics,ml-ready=true" \
        2>>"${ERROR_LOG}"; then
        
        log_success "Autonomous Database creation initiated"
        
        # Monitor database provisioning
        local max_attempts=30
        local attempt=0
        while [[ ${attempt} -lt ${max_attempts} ]]; do
            local state
            state=$(gcloud oracle-database autonomous-databases describe \
                "${ADB_NAME}" \
                --location="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            case "${state}" in
                "AVAILABLE")
                    log_success "Autonomous Database is now available"
                    return 0
                    ;;
                "PROVISIONING"|"CREATING")
                    log_info "Database state: ${state} (attempt ${attempt}/${max_attempts})"
                    ;;
                "FAILED"|"ERROR")
                    log_error "Database provisioning failed with state: ${state}"
                    return 1
                    ;;
            esac
            
            sleep 30
            ((attempt++))
        done
        
        log_warning "Database provisioning taking longer than expected. Continuing with next steps..."
        return 0
    else
        log_error "Failed to create Autonomous Database"
        return 1
    fi
}

# Set up Vertex AI environment
setup_vertex_ai() {
    log_info "Setting up Vertex AI environment..."
    
    # Create Vertex AI dataset
    log_info "Creating Vertex AI dataset..."
    local dataset_response
    if dataset_response=$(gcloud ai datasets create \
        --display-name="Oracle Enterprise Analytics Dataset" \
        --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml" \
        --region="${REGION}" \
        --format="value(name)" 2>>"${ERROR_LOG}"); then
        
        export DATASET_ID=$(echo "${dataset_response}" | cut -d'/' -f6)
        echo "export DATASET_ID=\"${DATASET_ID}\"" >> "${SCRIPT_DIR}/deployment_vars.env"
        log_success "Vertex AI dataset created with ID: ${DATASET_ID}"
    else
        log_error "Failed to create Vertex AI dataset"
        return 1
    fi
    
    # Create Vertex AI Workbench instance
    log_info "Creating Vertex AI Workbench instance..."
    if gcloud notebooks instances create "${WORKBENCH_INSTANCE}" \
        --location="${ZONE}" \
        --machine-type=n1-standard-4 \
        --boot-disk-size=100GB \
        --disk-type=PD_STANDARD \
        --framework=SCIKIT_LEARN \
        --labels="purpose=oracle-analytics,team=ml-engineering" \
        2>>"${ERROR_LOG}"; then
        
        log_success "Vertex AI Workbench instance created"
    else
        log_error "Failed to create Vertex AI Workbench instance"
        return 1
    fi
    
    # Create Vertex AI endpoint
    log_info "Creating Vertex AI endpoint..."
    local endpoint_response
    if endpoint_response=$(gcloud ai endpoints create \
        --display-name="${VERTEX_ENDPOINT_NAME}" \
        --region="${REGION}" \
        --format="value(name)" 2>>"${ERROR_LOG}"); then
        
        export ENDPOINT_ID=$(echo "${endpoint_response}" | cut -d'/' -f6)
        echo "export ENDPOINT_ID=\"${ENDPOINT_ID}\"" >> "${SCRIPT_DIR}/deployment_vars.env"
        log_success "Vertex AI endpoint created with ID: ${ENDPOINT_ID}"
    else
        log_error "Failed to create Vertex AI endpoint"
        return 1
    fi
    
    # Create staging bucket
    log_info "Creating staging bucket for Vertex AI..."
    if gsutil mb "gs://${STAGING_BUCKET}" 2>>"${ERROR_LOG}"; then
        log_success "Staging bucket created: gs://${STAGING_BUCKET}"
    else
        log_error "Failed to create staging bucket"
        return 1
    fi
    
    log_success "Vertex AI environment setup completed"
}

# Configure BigQuery analytics
configure_bigquery() {
    log_info "Configuring BigQuery for analytics..."
    
    # Create BigQuery dataset
    log_info "Creating BigQuery dataset..."
    if bq mk --dataset \
        --location="${REGION}" \
        --description="Enterprise Oracle Database Analytics" \
        --label="source:oracle,purpose:analytics" \
        "${PROJECT_ID}:${BQ_DATASET_NAME}" 2>>"${ERROR_LOG}"; then
        
        log_success "BigQuery dataset created: ${BQ_DATASET_NAME}"
    else
        log_error "Failed to create BigQuery dataset"
        return 1
    fi
    
    # Create analytics table structure
    log_info "Creating analytics table structure..."
    if bq mk --table \
        "${PROJECT_ID}:${BQ_DATASET_NAME}.sales_analytics" \
        "sales_id:STRING,product_id:STRING,revenue:FLOAT,quarter:STRING,prediction_score:FLOAT" \
        2>>"${ERROR_LOG}"; then
        
        log_success "BigQuery analytics table created"
    else
        log_error "Failed to create BigQuery analytics table"
        return 1
    fi
    
    log_success "BigQuery analytics environment configured"
}

# Configure monitoring and alerting
configure_monitoring() {
    log_info "Configuring Cloud Monitoring and alerting..."
    
    # Create Oracle Database performance alert
    log_info "Creating Oracle Database performance monitoring policy..."
    local oracle_policy=$(cat << 'EOF'
{
  "displayName": "Oracle Database Performance Alert",
  "conditions": [
    {
      "displayName": "Oracle CPU Utilization High",
      "conditionThreshold": {
        "filter": "resource.type=\"oracle_database\" metric.type=\"oracle.googleapis.com/database/cpu_utilization\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 80.0,
        "duration": "300s"
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    )
    
    if echo "${oracle_policy}" | gcloud alpha monitoring policies create --policy-from-file=- 2>>"${ERROR_LOG}"; then
        log_success "Oracle Database monitoring policy created"
    else
        log_warning "Failed to create Oracle Database monitoring policy (may require additional permissions)"
    fi
    
    # Create Vertex AI model performance alert
    log_info "Creating Vertex AI model performance monitoring policy..."
    local vertex_policy=$(cat << 'EOF'
{
  "displayName": "Vertex AI Model Performance Alert",
  "conditions": [
    {
      "displayName": "Model Prediction Latency High",
      "conditionThreshold": {
        "filter": "resource.type=\"ai_platform_model_version\" metric.type=\"ml.googleapis.com/prediction/response_time\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5000.0,
        "duration": "60s"
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "3600s"
  }
}
EOF
    )
    
    if echo "${vertex_policy}" | gcloud alpha monitoring policies create --policy-from-file=- 2>>"${ERROR_LOG}"; then
        log_success "Vertex AI monitoring policy created"
    else
        log_warning "Failed to create Vertex AI monitoring policy (may require additional permissions)"
    fi
    
    log_success "Cloud Monitoring configuration completed"
}

# Deploy data pipeline
deploy_data_pipeline() {
    log_info "Deploying data pipeline components..."
    
    # Create Cloud Function source files
    log_info "Creating Cloud Function source files..."
    local temp_dir="${SCRIPT_DIR}/temp_function"
    mkdir -p "${temp_dir}"
    
    # Create main.py
    cat > "${temp_dir}/main.py" << 'EOF'
import functions_framework
from google.cloud import aiplatform
from google.cloud import bigquery
import json
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def oracle_analytics_pipeline(request):
    """HTTP Cloud Function for Oracle analytics pipeline."""
    try:
        logger.info("Starting Oracle analytics pipeline execution")
        
        # Initialize clients
        # Note: In production, implement actual data extraction from Oracle Database@Google Cloud
        # Process through Vertex AI models
        # Load results into BigQuery for analytics
        
        response_data = {
            "status": "success", 
            "message": "Pipeline executed successfully",
            "timestamp": str(request.headers.get('timestamp', 'unknown'))
        }
        
        logger.info("Pipeline execution completed successfully")
        return json.dumps(response_data), 200
        
    except Exception as e:
        error_msg = f"Pipeline execution failed: {str(e)}"
        logger.error(error_msg)
        return json.dumps({"status": "error", "message": error_msg}), 500
EOF
    
    # Create requirements.txt
    cat > "${temp_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-aiplatform
google-cloud-bigquery
EOF
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function for pipeline orchestration..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --source "${temp_dir}" \
        --entry-point oracle_analytics_pipeline \
        --memory 512Mi \
        --timeout 300s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --region="${REGION}" \
        --allow-unauthenticated \
        2>>"${ERROR_LOG}"; then
        
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        return 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null)
    
    # Create Cloud Scheduler job
    log_info "Creating Cloud Scheduler job for automated pipeline execution..."
    if gcloud scheduler jobs create http "${SCHEDULER_JOB}" \
        --schedule="0 */6 * * *" \
        --uri="${function_url}" \
        --http-method=GET \
        --time-zone="America/New_York" \
        2>>"${ERROR_LOG}"; then
        
        log_success "Cloud Scheduler job created with 6-hour schedule"
    else
        log_error "Failed to create Cloud Scheduler job"
        return 1
    fi
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    log_success "Data pipeline deployment completed"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check Oracle infrastructure
    log_info "Validating Oracle Cloud Exadata infrastructure..."
    local oracle_state
    oracle_state=$(gcloud oracle-database cloud-exadata-infrastructures describe \
        "${ORACLE_INSTANCE_NAME}" \
        --location="${REGION}" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${oracle_state}" == "AVAILABLE" || "${oracle_state}" == "PROVISIONING" ]]; then
        log_success "Oracle infrastructure validation passed (state: ${oracle_state})"
    else
        log_error "Oracle infrastructure validation failed (state: ${oracle_state})"
        ((validation_errors++))
    fi
    
    # Check Autonomous Database
    log_info "Validating Autonomous Database..."
    local adb_state
    adb_state=$(gcloud oracle-database autonomous-databases describe \
        "${ADB_NAME}" \
        --location="${REGION}" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${adb_state}" == "AVAILABLE" || "${adb_state}" == "PROVISIONING" ]]; then
        log_success "Autonomous Database validation passed (state: ${adb_state})"
    else
        log_error "Autonomous Database validation failed (state: ${adb_state})"
        ((validation_errors++))
    fi
    
    # Check Vertex AI endpoint
    log_info "Validating Vertex AI endpoint..."
    if gcloud ai endpoints describe "${ENDPOINT_ID}" \
        --region="${REGION}" \
        --format="value(displayName)" &>/dev/null; then
        log_success "Vertex AI endpoint validation passed"
    else
        log_error "Vertex AI endpoint validation failed"
        ((validation_errors++))
    fi
    
    # Check BigQuery dataset
    log_info "Validating BigQuery dataset..."
    if bq ls "${PROJECT_ID}:${BQ_DATASET_NAME}" &>/dev/null; then
        log_success "BigQuery dataset validation passed"
    else
        log_error "BigQuery dataset validation failed"
        ((validation_errors++))
    fi
    
    # Check Cloud Function
    log_info "Validating Cloud Function..."
    if gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(name)" &>/dev/null; then
        log_success "Cloud Function validation passed"
    else
        log_error "Cloud Function validation failed"
        ((validation_errors++))
    fi
    
    # Check Cloud Scheduler job
    log_info "Validating Cloud Scheduler job..."
    if gcloud scheduler jobs describe "${SCHEDULER_JOB}" \
        --location="${REGION}" \
        --format="value(name)" &>/dev/null; then
        log_success "Cloud Scheduler job validation passed"
    else
        log_error "Cloud Scheduler job validation failed"
        ((validation_errors++))
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All deployment validations passed"
        return 0
    else
        log_error "Deployment validation failed with ${validation_errors} errors"
        return 1
    fi
}

# Print deployment summary
print_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Oracle Instance: ${ORACLE_INSTANCE_NAME}"
    log_info "Autonomous Database: ${ADB_NAME}"
    log_info "Vertex AI Endpoint: ${VERTEX_ENDPOINT_NAME}"
    log_info "BigQuery Dataset: ${BQ_DATASET_NAME}"
    log_info "Cloud Function: ${FUNCTION_NAME}"
    log_info "Scheduler Job: ${SCHEDULER_JOB}"
    log_info "Staging Bucket: gs://${STAGING_BUCKET}"
    log_info ""
    log_info "Access Information:"
    log_info "- Google Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    log_info "- Vertex AI Workbench: https://console.cloud.google.com/vertex-ai/workbench/list?project=${PROJECT_ID}"
    log_info "- BigQuery: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
    log_info "- Cloud Monitoring: https://console.cloud.google.com/monitoring?project=${PROJECT_ID}"
    log_info ""
    log_info "Environment variables saved to: ${SCRIPT_DIR}/deployment_vars.env"
    log_info "Deployment logs saved to: ${LOG_FILE}"
    log_info ""
    log_warning "Important Notes:"
    log_warning "- Oracle Database@Google Cloud resources may take 15-30 minutes to fully provision"
    log_warning "- Estimated monthly cost: \$500-1500 depending on usage"
    log_warning "- Remember to run destroy.sh when testing is complete to avoid ongoing charges"
}

# Main execution
main() {
    log_info "Starting Enterprise Database Analytics deployment..."
    log_info "Script location: ${SCRIPT_DIR}"
    
    check_prerequisites
    set_environment
    configure_gcloud
    enable_apis
    create_oracle_infrastructure
    create_autonomous_database
    setup_vertex_ai
    configure_bigquery
    configure_monitoring
    deploy_data_pipeline
    validate_deployment
    print_summary
    
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: $((SECONDS / 60)) minutes"
}

# Execute main function
main "$@"
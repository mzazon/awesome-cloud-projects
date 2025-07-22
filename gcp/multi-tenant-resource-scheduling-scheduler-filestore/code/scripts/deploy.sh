#!/bin/bash

# Multi-Tenant Resource Scheduling Deployment Script
# This script deploys Cloud Scheduler, Cloud Filestore, Cloud Functions, and Cloud Monitoring
# for a complete multi-tenant resource scheduling solution

set -euo pipefail

# Color codes for output
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
    log_warning "Deployment failed. Starting cleanup of partially created resources..."
    
    # Only cleanup resources that might have been created
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${FILESTORE_NAME:-}" ]]; then
        gcloud filestore instances delete "${FILESTORE_NAME}" --zone="${ZONE}" --quiet 2>/dev/null || true
    fi
    
    # Clean up scheduler jobs
    for job in "${SCHEDULER_JOBS[@]:-}"; do
        gcloud scheduler jobs delete "${job}" --quiet 2>/dev/null || true
    done
    
    log_error "Cleanup completed. Please review any remaining resources manually."
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it first."
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install it first."
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "gcloud is not authenticated. Please run 'gcloud auth login' first."
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        error_exit "No GCP project is set. Please run 'gcloud config set project PROJECT_ID' first."
    fi
    
    # Check billing account
    if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Billing may not be enabled for project ${PROJECT_ID}. This deployment may fail if billing is required."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RESOURCE_SUFFIX="mt-${RANDOM_SUFFIX}"
    
    # Resource names
    export FILESTORE_NAME="tenant-data-${RESOURCE_SUFFIX}"
    export FUNCTION_NAME="resource-scheduler-${RESOURCE_SUFFIX}"
    
    # Scheduler job names
    export CLEANUP_JOB="tenant-cleanup-${RESOURCE_SUFFIX}"
    export QUOTA_JOB="quota-monitor-${RESOURCE_SUFFIX}"
    export TENANT_A_JOB="tenant-a-processing-${RESOURCE_SUFFIX}"
    
    SCHEDULER_JOBS=("${CLEANUP_JOB}" "${QUOTA_JOB}" "${TENANT_A_JOB}")
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Resource suffix: ${RESOURCE_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "file.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            error_exit "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to set default region and zone
set_defaults() {
    log_info "Setting default region and zone..."
    
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Default region and zone configured"
}

# Function to create Cloud Filestore instance
create_filestore() {
    log_info "Creating Cloud Filestore instance: ${FILESTORE_NAME}..."
    
    # Check if Filestore instance already exists
    if gcloud filestore instances describe "${FILESTORE_NAME}" --zone="${ZONE}" &>/dev/null; then
        log_warning "Filestore instance ${FILESTORE_NAME} already exists"
        export FILESTORE_IP=$(gcloud filestore instances describe "${FILESTORE_NAME}" \
            --zone="${ZONE}" \
            --format="value(networks[0].ipAddresses[0])")
        return 0
    fi
    
    if gcloud filestore instances create "${FILESTORE_NAME}" \
        --zone="${ZONE}" \
        --tier=BASIC_HDD \
        --file-share=name="tenant_storage",capacity=1TB \
        --network=name="default" \
        --quiet; then
        
        log_success "Filestore instance created successfully"
        
        # Get Filestore IP address
        log_info "Retrieving Filestore IP address..."
        export FILESTORE_IP=$(gcloud filestore instances describe "${FILESTORE_NAME}" \
            --zone="${ZONE}" \
            --format="value(networks[0].ipAddresses[0])")
        
        log_success "Filestore IP: ${FILESTORE_IP}"
    else
        error_exit "Failed to create Filestore instance"
    fi
}

# Function to create Cloud Function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    local source_dir="cloud-function-source"
    mkdir -p "${source_dir}"
    
    # Create main.py
    cat > "${source_dir}/main.py" << 'EOF'
import json
import logging
import os
from datetime import datetime, timedelta
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging
import subprocess
import tempfile

def schedule_tenant_resources(request):
    """
    Main function to handle tenant resource scheduling requests
    """
    # Set up logging
    client = cloud_logging.Client()
    client.setup_logging()
    
    try:
        # Parse request data
        request_json = request.get_json()
        tenant_id = request_json.get('tenant_id')
        resource_type = request_json.get('resource_type', 'compute')
        requested_capacity = int(request_json.get('capacity', 1))
        duration_hours = int(request_json.get('duration', 2))
        
        logging.info(f"Processing request for tenant {tenant_id}")
        
        # Get tenant quota and current usage
        tenant_quota = get_tenant_quota(tenant_id)
        current_usage = get_current_usage(tenant_id)
        
        # Check if request can be fulfilled
        if current_usage + requested_capacity > tenant_quota:
            return {
                'status': 'denied',
                'reason': 'Quota exceeded',
                'current_usage': current_usage,
                'quota': tenant_quota
            }, 403
        
        # Schedule resource allocation
        allocation_result = allocate_resources(
            tenant_id, resource_type, requested_capacity, duration_hours
        )
        
        # Update tenant storage with allocation info
        update_tenant_storage(tenant_id, allocation_result)
        
        # Send metrics to Cloud Monitoring
        send_allocation_metrics(tenant_id, requested_capacity, 'success')
        
        return {
            'status': 'scheduled',
            'tenant_id': tenant_id,
            'allocation_id': allocation_result['allocation_id'],
            'scheduled_time': allocation_result['start_time'],
            'duration_hours': duration_hours,
            'capacity': requested_capacity
        }
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        send_allocation_metrics(tenant_id if 'tenant_id' in locals() else 'unknown', 
                              requested_capacity if 'requested_capacity' in locals() else 0, 
                              'error')
        return {'status': 'error', 'message': str(e)}, 500

def get_tenant_quota(tenant_id):
    """Get tenant resource quota from configuration"""
    # In production, this would read from Firestore or Cloud SQL
    tenant_quotas = {
        'tenant_a': 10,
        'tenant_b': 15,
        'tenant_c': 8,
        'default': 5
    }
    return tenant_quotas.get(tenant_id, tenant_quotas['default'])

def get_current_usage(tenant_id):
    """Get current resource usage for tenant"""
    # In production, this would query actual resource usage
    # For demo, return simulated usage
    import random
    return random.randint(0, 3)

def allocate_resources(tenant_id, resource_type, capacity, duration):
    """Simulate resource allocation logic"""
    from uuid import uuid4
    
    allocation_id = str(uuid4())[:8]
    start_time = datetime.now().isoformat()
    
    # Create tenant directory structure in Filestore
    filestore_ip = os.environ.get('FILESTORE_IP', '10.0.0.2')
    mount_point = f"/mnt/tenant_storage"
    tenant_dir = f"{mount_point}/tenants/{tenant_id}/allocations/{allocation_id}"
    
    # In production, this would mount Filestore and create directories
    # For demo, we simulate the allocation
    
    return {
        'allocation_id': allocation_id,
        'start_time': start_time,
        'tenant_id': tenant_id,
        'resource_type': resource_type,
        'capacity': capacity,
        'duration_hours': duration,
        'storage_path': tenant_dir
    }

def update_tenant_storage(tenant_id, allocation_info):
    """Update tenant storage with allocation information"""
    # In production, this would write to mounted Filestore
    logging.info(f"Updated storage for tenant {tenant_id}: {allocation_info}")
    
def send_allocation_metrics(tenant_id, capacity, status):
    """Send metrics to Cloud Monitoring"""
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{os.environ.get('GCP_PROJECT')}"
        
        # Create a time series for the allocation metric
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/tenant/resource_allocations"
        series.metric.labels["tenant_id"] = tenant_id
        series.metric.labels["status"] = status
        
        series.resource.type = "global"
        series.resource.labels["project_id"] = os.environ.get('GCP_PROJECT')
        
        now = datetime.now()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": seconds, "nanos": nanos}
        })
        
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"double_value": capacity}
        })
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        logging.info(f"Sent metrics for tenant {tenant_id}")
        
    except Exception as e:
        logging.error(f"Failed to send metrics: {str(e)}")
EOF
    
    # Create requirements.txt
    cat > "${source_dir}/requirements.txt" << 'EOF'
google-cloud-monitoring==2.16.0
google-cloud-logging==3.8.0
functions-framework==3.4.0
EOF
    
    log_success "Cloud Function source code created"
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}..."
    
    # Check if function already exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "Function ${FUNCTION_NAME} already exists, updating..."
    fi
    
    cd cloud-function-source
    
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python311 \
        --trigger=http \
        --entry-point=schedule_tenant_resources \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars="FILESTORE_IP=${FILESTORE_IP},GCP_PROJECT=${PROJECT_ID}" \
        --allow-unauthenticated \
        --region="${REGION}" \
        --quiet; then
        
        log_success "Cloud Function deployed successfully"
        
        # Get function URL
        export FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(httpsTrigger.url)")
        
        log_info "Function URL: ${FUNCTION_URL}"
    else
        cd ..
        error_exit "Failed to deploy Cloud Function"
    fi
    
    cd ..
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    log_info "Creating Cloud Scheduler jobs..."
    
    # Create scheduler job for tenant resource cleanup
    log_info "Creating cleanup job: ${CLEANUP_JOB}..."
    if gcloud scheduler jobs create http "${CLEANUP_JOB}" \
        --schedule="0 2 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"action":"cleanup","tenant_id":"all"}' \
        --time-zone="America/New_York" \
        --description="Daily cleanup of expired tenant resources" \
        --quiet; then
        log_success "Created cleanup job"
    else
        error_exit "Failed to create cleanup job"
    fi
    
    # Create scheduler job for quota monitoring
    log_info "Creating quota monitoring job: ${QUOTA_JOB}..."
    if gcloud scheduler jobs create http "${QUOTA_JOB}" \
        --schedule="0 */6 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"action":"monitor_quotas","tenant_id":"all"}' \
        --time-zone="America/New_York" \
        --description="Monitor tenant quota usage every 6 hours" \
        --quiet; then
        log_success "Created quota monitoring job"
    else
        error_exit "Failed to create quota monitoring job"
    fi
    
    # Create scheduler job for tenant A specific tasks
    log_info "Creating tenant A processing job: ${TENANT_A_JOB}..."
    if gcloud scheduler jobs create http "${TENANT_A_JOB}" \
        --schedule="0 9 * * 1-5" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"tenant_id":"tenant_a","resource_type":"compute","capacity":5,"duration":8}' \
        --time-zone="America/New_York" \
        --description="Weekday resource allocation for Tenant A" \
        --quiet; then
        log_success "Created tenant A processing job"
    else
        error_exit "Failed to create tenant A processing job"
    fi
    
    log_success "All Cloud Scheduler jobs created successfully"
}

# Function to configure Cloud Monitoring
configure_monitoring() {
    log_info "Configuring Cloud Monitoring..."
    
    # Create alert policy for tenant quota violations
    cat > quota-alert-policy.yaml << 'EOF'
displayName: "Tenant Quota Violation Alert"
documentation:
  content: "Alert when tenant exceeds 80% of allocated quota"
conditions:
  - displayName: "Quota usage high"
    conditionThreshold:
      filter: 'metric.type="custom.googleapis.com/tenant/resource_allocations"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 8
      duration: "300s"
      aggregations:
        - alignmentPeriod: "300s"
          perSeriesAligner: ALIGN_MEAN
          crossSeriesReducer: REDUCE_SUM
          groupByFields:
            - "metric.label.tenant_id"
alertStrategy:
  autoClose: "1800s"
enabled: true
EOF
    
    if gcloud alpha monitoring policies create --policy-from-file=quota-alert-policy.yaml --quiet; then
        log_success "Created quota violation alert policy"
    else
        log_warning "Failed to create alert policy (may already exist)"
    fi
    
    # Create custom dashboard for tenant monitoring
    cat > tenant-dashboard.json << 'EOF'
{
  "displayName": "Multi-Tenant Resource Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Tenant Resource Allocations",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/tenant/resource_allocations\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["metric.label.tenant_id"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Resource Units",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    if gcloud monitoring dashboards create --config-from-file=tenant-dashboard.json --quiet; then
        log_success "Created multi-tenant resource dashboard"
    else
        log_warning "Failed to create dashboard (may already exist)"
    fi
    
    log_success "Cloud Monitoring configured successfully"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the multi-tenant scheduling system..."
    
    # Test tenant A resource request
    log_info "Testing tenant A resource request..."
    local response=$(curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{
            "tenant_id": "tenant_a",
            "resource_type": "compute",
            "capacity": 3,
            "duration": 4
        }')
    
    local status=$(echo "${response}" | jq -r '.status' 2>/dev/null || echo "error")
    if [[ "${status}" == "scheduled" ]]; then
        log_success "Tenant A request test passed"
    else
        log_warning "Tenant A request test failed: ${response}"
    fi
    
    # Test quota violation scenario
    log_info "Testing quota violation scenario..."
    local quota_response=$(curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{
            "tenant_id": "tenant_c",
            "resource_type": "compute",
            "capacity": 15,
            "duration": 1
        }')
    
    local quota_status=$(echo "${quota_response}" | jq -r '.status' 2>/dev/null || echo "error")
    if [[ "${quota_status}" == "denied" ]]; then
        log_success "Quota violation test passed"
    else
        log_warning "Quota violation test failed: ${quota_response}"
    fi
    
    log_success "Deployment testing completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "Resource Suffix: ${RESOURCE_SUFFIX}"
    echo
    echo "=== CREATED RESOURCES ==="
    echo "Filestore Instance: ${FILESTORE_NAME}"
    echo "Filestore IP: ${FILESTORE_IP}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Function URL: ${FUNCTION_URL}"
    echo "Scheduler Jobs:"
    echo "  - ${CLEANUP_JOB}"
    echo "  - ${QUOTA_JOB}"
    echo "  - ${TENANT_A_JOB}"
    echo
    echo "=== MONITORING ==="
    echo "- Quota violation alert policy created"
    echo "- Multi-tenant resource dashboard created"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. View the Cloud Functions console: https://console.cloud.google.com/functions"
    echo "2. View Cloud Scheduler: https://console.cloud.google.com/cloudscheduler"
    echo "3. View Cloud Monitoring: https://console.cloud.google.com/monitoring"
    echo "4. Test the API using the Function URL above"
    echo
    echo "To clean up resources, run: ./destroy.sh"
}

# Function to save deployment info
save_deployment_info() {
    local info_file="deployment-info.json"
    
    cat > "${info_file}" << EOF
{
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "zone": "${ZONE}",
  "resource_suffix": "${RESOURCE_SUFFIX}",
  "filestore_name": "${FILESTORE_NAME}",
  "filestore_ip": "${FILESTORE_IP}",
  "function_name": "${FUNCTION_NAME}",
  "function_url": "${FUNCTION_URL}",
  "scheduler_jobs": [
    "${CLEANUP_JOB}",
    "${QUOTA_JOB}",
    "${TENANT_A_JOB}"
  ],
  "deployment_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    log_success "Deployment info saved to ${info_file}"
}

# Main deployment function
main() {
    log_info "Starting Multi-Tenant Resource Scheduling deployment..."
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    enable_apis
    set_defaults
    create_filestore
    create_function_source
    deploy_function
    create_scheduler_jobs
    configure_monitoring
    test_deployment
    save_deployment_info
    display_summary
    
    log_success "All deployment steps completed successfully!"
}

# Run main function
main "$@"
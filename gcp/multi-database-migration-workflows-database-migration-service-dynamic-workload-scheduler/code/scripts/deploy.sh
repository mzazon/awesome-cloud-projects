#!/bin/bash

# Multi-Database Migration Workflows Deployment Script
# This script deploys a comprehensive database migration platform using
# Database Migration Service and Dynamic Workload Scheduler

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running in Google Cloud Shell or with gcloud authenticated
check_authentication() {
    log_info "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    log_success "Google Cloud authentication verified"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Using gcloud version: $GCLOUD_VERSION"
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available. Please ensure it's installed with gcloud."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not available. Please install it for random string generation."
    fi
    
    log_success "All prerequisites are satisfied"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Project setup
    export PROJECT_ID="${PROJECT_ID:-migration-workshop-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export NETWORK_NAME="${NETWORK_NAME:-migration-network}"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export INSTANCE_TEMPLATE="migration-template-${RANDOM_SUFFIX}"
    export CLOUD_SQL_INSTANCE="mysql-target-${RANDOM_SUFFIX}"
    export ALLOYDB_CLUSTER="postgres-cluster-${RANDOM_SUFFIX}"
    
    # Source database configuration (placeholder IPs - replace with actual values)
    export SOURCE_MYSQL_HOST="${SOURCE_MYSQL_HOST:-203.0.113.1}"
    export SOURCE_POSTGRES_HOST="${SOURCE_POSTGRES_HOST:-203.0.113.2}"
    export SOURCE_DB_USERNAME="${SOURCE_DB_USERNAME:-migration_user}"
    export SOURCE_DB_PASSWORD="${SOURCE_DB_PASSWORD:-SecureSourcePass123!}"
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "Network: $NETWORK_NAME"
    log_info "Instance Template: $INSTANCE_TEMPLATE"
    log_info "Cloud SQL Instance: $CLOUD_SQL_INSTANCE"
    log_info "AlloyDB Cluster: $ALLOYDB_CLUSTER"
    
    log_success "Environment variables configured"
}

# Configure gcloud defaults
configure_gcloud() {
    log_info "Configuring gcloud defaults..."
    
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "gcloud defaults configured"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "sqladmin.googleapis.com"
        "alloydb.googleapis.com"
        "datamigration.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" || error_exit "Failed to enable $api"
    done
    
    log_success "All required APIs enabled"
}

# Create VPC network
create_network() {
    log_info "Creating VPC network and subnet..."
    
    # Create VPC network
    if ! gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
        gcloud compute networks create "${NETWORK_NAME}" \
            --subnet-mode regional \
            --bgp-routing-mode regional || error_exit "Failed to create VPC network"
        log_success "VPC network created: ${NETWORK_NAME}"
    else
        log_warning "VPC network ${NETWORK_NAME} already exists"
    fi
    
    # Create subnet
    if ! gcloud compute networks subnets describe "${NETWORK_NAME}-subnet" --region="${REGION}" &>/dev/null; then
        gcloud compute networks subnets create "${NETWORK_NAME}-subnet" \
            --network "${NETWORK_NAME}" \
            --range 10.0.0.0/24 \
            --region "${REGION}" || error_exit "Failed to create subnet"
        log_success "Subnet created: ${NETWORK_NAME}-subnet"
    else
        log_warning "Subnet ${NETWORK_NAME}-subnet already exists"
    fi
}

# Create instance template for migration workers
create_instance_template() {
    log_info "Creating instance template for migration workers..."
    
    if ! gcloud compute instance-templates describe "${INSTANCE_TEMPLATE}" &>/dev/null; then
        gcloud compute instance-templates create "${INSTANCE_TEMPLATE}" \
            --machine-type e2-standard-4 \
            --network-interface network="${NETWORK_NAME}",subnet="${NETWORK_NAME}-subnet" \
            --boot-disk-size 100GB \
            --boot-disk-type pd-ssd \
            --image-family debian-12 \
            --image-project debian-cloud \
            --scopes cloud-platform \
            --tags migration-worker \
            --metadata startup-script='#!/bin/bash
apt-get update
apt-get install -y mysql-client postgresql-client python3-pip
pip3 install google-cloud-monitoring google-cloud-logging' || error_exit "Failed to create instance template"
        
        log_success "Instance template created: ${INSTANCE_TEMPLATE}"
    else
        log_warning "Instance template ${INSTANCE_TEMPLATE} already exists"
    fi
}

# Create managed instance group
create_instance_group() {
    log_info "Creating managed instance group for migration workers..."
    
    if ! gcloud compute instance-groups managed describe migration-workers --region="${REGION}" &>/dev/null; then
        gcloud compute instance-groups managed create migration-workers \
            --template "${INSTANCE_TEMPLATE}" \
            --size 0 \
            --region "${REGION}" || error_exit "Failed to create managed instance group"
        
        log_success "Managed instance group created: migration-workers"
    else
        log_warning "Managed instance group migration-workers already exists"
    fi
    
    # Configure autoscaling
    log_info "Configuring autoscaling for migration workers..."
    gcloud compute instance-groups managed set-autoscaling migration-workers \
        --region "${REGION}" \
        --max-num-replicas 8 \
        --min-num-replicas 0 \
        --target-cpu-utilization 0.7 \
        --cool-down-period 300 || error_exit "Failed to configure autoscaling"
    
    log_success "Autoscaling configured for migration workers"
}

# Create Cloud SQL instance
create_cloud_sql() {
    log_info "Creating Cloud SQL MySQL instance..."
    
    if ! gcloud sql instances describe "${CLOUD_SQL_INSTANCE}" &>/dev/null; then
        gcloud sql instances create "${CLOUD_SQL_INSTANCE}" \
            --database-version MYSQL_8_0 \
            --tier db-n1-standard-4 \
            --region "${REGION}" \
            --network "${NETWORK_NAME}" \
            --no-assign-ip \
            --storage-type SSD \
            --storage-size 100GB \
            --storage-auto-increase \
            --backup-start-time 03:00 \
            --enable-bin-log \
            --maintenance-window-day SUN \
            --maintenance-window-hour 04 \
            --deletion-protection || error_exit "Failed to create Cloud SQL instance"
        
        log_success "Cloud SQL instance created: ${CLOUD_SQL_INSTANCE}"
        
        # Wait for instance to be ready
        log_info "Waiting for Cloud SQL instance to be ready..."
        while [[ $(gcloud sql instances describe "${CLOUD_SQL_INSTANCE}" --format="value(state)") != "RUNNABLE" ]]; do
            echo "Cloud SQL instance still initializing..."
            sleep 30
        done
        
        # Create database user
        log_info "Creating migration user..."
        gcloud sql users create migration-user \
            --instance "${CLOUD_SQL_INSTANCE}" \
            --password "SecureMigration123!" || error_exit "Failed to create database user"
        
        # Create target database
        log_info "Creating target database..."
        gcloud sql databases create sample_db \
            --instance "${CLOUD_SQL_INSTANCE}" || error_exit "Failed to create target database"
        
        log_success "Cloud SQL configuration completed"
    else
        log_warning "Cloud SQL instance ${CLOUD_SQL_INSTANCE} already exists"
    fi
}

# Create AlloyDB cluster
create_alloydb() {
    log_info "Creating AlloyDB cluster for PostgreSQL workloads..."
    
    if ! gcloud alloydb clusters describe "${ALLOYDB_CLUSTER}" --region="${REGION}" &>/dev/null; then
        gcloud alloydb clusters create "${ALLOYDB_CLUSTER}" \
            --region "${REGION}" \
            --network "${NETWORK_NAME}" \
            --database-version POSTGRES_15 || error_exit "Failed to create AlloyDB cluster"
        
        log_success "AlloyDB cluster created: ${ALLOYDB_CLUSTER}"
        
        # Create primary instance
        log_info "Creating AlloyDB primary instance..."
        gcloud alloydb instances create "${ALLOYDB_CLUSTER}-primary" \
            --cluster "${ALLOYDB_CLUSTER}" \
            --region "${REGION}" \
            --instance-type PRIMARY \
            --cpu-count 4 \
            --memory-size 16GB || error_exit "Failed to create AlloyDB primary instance"
        
        # Wait for cluster to be ready
        log_info "Waiting for AlloyDB cluster to become ready..."
        while [[ $(gcloud alloydb clusters describe "${ALLOYDB_CLUSTER}" --region="${REGION}" --format="value(state)") != "READY" ]]; do
            echo "AlloyDB cluster still initializing..."
            sleep 30
        done
        
        log_success "AlloyDB cluster ready: ${ALLOYDB_CLUSTER}"
    else
        log_warning "AlloyDB cluster ${ALLOYDB_CLUSTER} already exists"
    fi
}

# Create Database Migration Service connection profiles
create_connection_profiles() {
    log_info "Creating Database Migration Service connection profiles..."
    
    # Create source MySQL connection profile
    if ! gcloud database-migration connection-profiles describe source-mysql --region="${REGION}" &>/dev/null; then
        gcloud database-migration connection-profiles create mysql source-mysql \
            --region="${REGION}" \
            --host "${SOURCE_MYSQL_HOST}" \
            --port 3306 \
            --username "${SOURCE_DB_USERNAME}" \
            --password "${SOURCE_DB_PASSWORD}" || error_exit "Failed to create MySQL source connection profile"
        
        log_success "MySQL source connection profile created"
    else
        log_warning "MySQL source connection profile already exists"
    fi
    
    # Create destination Cloud SQL connection profile
    if ! gcloud database-migration connection-profiles describe dest-cloudsql --region="${REGION}" &>/dev/null; then
        gcloud database-migration connection-profiles create cloudsql dest-cloudsql \
            --region="${REGION}" \
            --cloudsql-instance "projects/${PROJECT_ID}/instances/${CLOUD_SQL_INSTANCE}" || error_exit "Failed to create Cloud SQL destination connection profile"
        
        log_success "Cloud SQL destination connection profile created"
    else
        log_warning "Cloud SQL destination connection profile already exists"
    fi
    
    # Create source PostgreSQL connection profile
    if ! gcloud database-migration connection-profiles describe source-postgres --region="${REGION}" &>/dev/null; then
        gcloud database-migration connection-profiles create postgresql source-postgres \
            --region="${REGION}" \
            --host "${SOURCE_POSTGRES_HOST}" \
            --port 5432 \
            --username "${SOURCE_DB_USERNAME}" \
            --password "${SOURCE_DB_PASSWORD}" || error_exit "Failed to create PostgreSQL source connection profile"
        
        log_success "PostgreSQL source connection profile created"
    else
        log_warning "PostgreSQL source connection profile already exists"
    fi
    
    # Create destination AlloyDB connection profile
    if ! gcloud database-migration connection-profiles describe dest-alloydb --region="${REGION}" &>/dev/null; then
        gcloud database-migration connection-profiles create alloydb dest-alloydb \
            --region="${REGION}" \
            --alloydb-cluster "projects/${PROJECT_ID}/locations/${REGION}/clusters/${ALLOYDB_CLUSTER}" || error_exit "Failed to create AlloyDB destination connection profile"
        
        log_success "AlloyDB destination connection profile created"
    else
        log_warning "AlloyDB destination connection profile already exists"
    fi
}

# Create Dynamic Workload Scheduler configuration
create_dynamic_workload_scheduler() {
    log_info "Creating Dynamic Workload Scheduler flex-start capacity..."
    
    if ! gcloud compute future-reservations describe migration-flex-capacity --zone="${ZONE}" &>/dev/null; then
        gcloud compute future-reservations create migration-flex-capacity \
            --source-instance-template "${INSTANCE_TEMPLATE}" \
            --total-count 4 \
            --planning-status PLANNING_STATUS_PLANNED \
            --zone "${ZONE}" || error_exit "Failed to create flex-start capacity reservation"
        
        log_success "Flex-start capacity reservation created"
    else
        log_warning "Flex-start capacity reservation already exists"
    fi
}

# Create Cloud Storage bucket for migration artifacts
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for migration artifacts..."
    
    local bucket_name="${PROJECT_ID}-migration-bucket"
    
    if ! gsutil ls -b "gs://${bucket_name}" &>/dev/null; then
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket_name}" || error_exit "Failed to create Cloud Storage bucket"
        log_success "Cloud Storage bucket created: gs://${bucket_name}"
    else
        log_warning "Cloud Storage bucket already exists: gs://${bucket_name}"
    fi
}

# Deploy migration orchestration function
deploy_orchestration_function() {
    log_info "Deploying Cloud Function for migration orchestration..."
    
    # Create temporary directory for function source
    local temp_dir=$(mktemp -d)
    
    # Create the orchestration function
    cat > "${temp_dir}/main.py" << 'EOF'
import os
import json
from google.cloud import compute_v1
from google.cloud import monitoring_v3
import functions_framework

@functions_framework.http
def orchestrate_migration(request):
    """Orchestrate database migration workflows with Dynamic Workload Scheduler"""
    
    try:
        # Parse migration request
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Invalid JSON request'}, 400
            
        migration_priority = request_json.get('priority', 'low')
        database_size = request_json.get('size_gb', 100)
        
        # Calculate optimal worker count based on database size
        worker_count = min(max(database_size // 50, 1), 8)
        
        # Scale migration workers based on workload
        compute_client = compute_v1.InstanceGroupManagersClient()
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION')
        
        if not project_id or not region:
            return {'error': 'Missing environment variables'}, 500
        
        try:
            operation = compute_client.resize(
                project=project_id,
                region=region,
                instance_group_manager='migration-workers',
                size=worker_count
            )
            
            return {
                'status': 'success',
                'worker_count': worker_count,
                'migration_mode': 'flex-start' if migration_priority == 'low' else 'calendar',
                'operation_id': operation.name
            }
        except Exception as e:
            return {'error': f'Failed to scale workers: {str(e)}'}, 500
            
    except Exception as e:
        return {'error': f'Internal error: {str(e)}'}, 500
EOF
    
    # Create requirements.txt
    cat > "${temp_dir}/requirements.txt" << 'EOF'
google-cloud-compute>=1.19.0
google-cloud-monitoring>=2.21.0
functions-framework>=3.8.0
EOF
    
    # Deploy the function
    cd "${temp_dir}"
    gcloud functions deploy migration-orchestrator \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point orchestrate_migration \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --timeout 540s \
        --memory 256MB || error_exit "Failed to deploy orchestration function"
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    log_success "Migration orchestration function deployed"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating monitoring dashboard for migration workflows..."
    
    # Create temporary file for dashboard configuration
    local temp_file=$(mktemp)
    
    cat > "${temp_file}" << 'EOF'
{
  "displayName": "Database Migration Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Migration Worker CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND resource.label.instance_name=~\"migration-workers-.*\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN"
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
        "yPos": 0,
        "xPos": 6,
        "widget": {
          "title": "Active Migration Workers",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance_group\" AND resource.label.instance_group_name=\"migration-workers\" AND metric.type=\"compute.googleapis.com/instance_group/size\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
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
    
    # Create the dashboard
    gcloud monitoring dashboards create --config-from-file="${temp_file}" || log_warning "Failed to create monitoring dashboard (may already exist)"
    
    # Clean up
    rm "${temp_file}"
    
    log_success "Monitoring dashboard configuration completed"
}

# Create alerting policy
create_alerting_policy() {
    log_info "Creating alerting policy for migration failures..."
    
    # Create temporary file for alerting policy
    local temp_file=$(mktemp)
    
    cat > "${temp_file}" << 'EOF'
displayName: "Migration Worker Failure Alert"
conditions:
  - displayName: "High error rate"
    conditionThreshold:
      filter: 'resource.type="gce_instance" AND resource.label.instance_name=~"migration-workers-.*"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 0.1
      duration: 300s
enabled: true
combiner: OR
EOF
    
    # Create the alerting policy
    gcloud alpha monitoring policies create --policy-from-file="${temp_file}" || log_warning "Failed to create alerting policy (may already exist)"
    
    # Clean up
    rm "${temp_file}"
    
    log_success "Alerting policy configuration completed"
}

# Display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Migration Platform Resources:"
    echo "  • Project ID: ${PROJECT_ID}"
    echo "  • Region: ${REGION}"
    echo "  • VPC Network: ${NETWORK_NAME}"
    echo "  • Cloud SQL Instance: ${CLOUD_SQL_INSTANCE}"
    echo "  • AlloyDB Cluster: ${ALLOYDB_CLUSTER}"
    echo "  • Instance Template: ${INSTANCE_TEMPLATE}"
    echo "  • Storage Bucket: gs://${PROJECT_ID}-migration-bucket"
    echo
    log_info "Next Steps:"
    echo "  1. Update source database connection details in connection profiles"
    echo "  2. Create and start migration jobs using the Database Migration Service"
    echo "  3. Monitor migration progress through the Cloud Console"
    echo "  4. Use the orchestration function to optimize resource allocation"
    echo
    log_warning "Important: Remember to clean up resources when testing is complete to avoid ongoing charges"
    echo
    log_info "To start a migration, use the following commands:"
    echo "  gcloud database-migration migration-jobs create mysql-migration-job --region=${REGION} --source=source-mysql --destination=dest-cloudsql --type=CONTINUOUS"
    echo "  gcloud database-migration migration-jobs start mysql-migration-job --region=${REGION}"
}

# Main execution flow
main() {
    log_info "Starting Multi-Database Migration Workflows deployment..."
    echo
    
    check_authentication
    check_prerequisites
    setup_environment
    configure_gcloud
    
    enable_apis
    create_network
    create_instance_template
    create_instance_group
    create_cloud_sql
    create_alloydb
    create_connection_profiles
    create_dynamic_workload_scheduler
    create_storage_bucket
    deploy_orchestration_function
    create_monitoring_dashboard
    create_alerting_policy
    
    display_summary
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Execute main function
main "$@"
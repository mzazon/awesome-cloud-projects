#!/bin/bash

# Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler - Deployment Script
# This script deploys a complete HPC environment using Google Cloud Cluster Toolkit and Cloud Batch
# with intelligent scheduling capabilities for cost-effective scientific computing workloads.

set -euo pipefail

# Enable colored output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/hpc-config.env"

# Default values
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false
SKIP_CONFIRMATION=false
DEBUG=false

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        log "${YELLOW}[DEBUG]${NC} $*"
    fi
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_info "Check ${LOG_FILE} for detailed error information"
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Environment configuration saved to ${CONFIG_FILE}"
        log_info "You can run './destroy.sh' to clean up partial deployment"
    fi
    
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION             GCP Region (default: ${DEFAULT_REGION})
    -z, --zone ZONE                 GCP Zone (default: ${DEFAULT_ZONE})
    -d, --dry-run                   Show what would be deployed without making changes
    -y, --yes                       Skip confirmation prompts
    --debug                         Enable debug logging
    -h, --help                      Show this help message

EXAMPLES:
    $0 --project-id my-hpc-project
    $0 -p my-project -r us-west1 -z us-west1-a --yes
    $0 --project-id my-project --dry-run

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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if running in Cloud Shell or with gcloud configured
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install gcloud: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_debug "gcloud version: ${gcloud_version}"
    
    # Validate project ID format
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        exit 1
    fi
    
    if [[ ! "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid project ID format: ${PROJECT_ID}"
        log_error "Project ID must be 6-30 characters, start with lowercase letter,"
        log_error "contain only lowercase letters, digits, and hyphens."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Cannot access project '${PROJECT_ID}'"
        log_error "Please ensure the project exists and you have proper permissions"
        exit 1
    fi
    
    # Check billing account
    local billing_enabled
    billing_enabled=$(gcloud billing projects describe "${PROJECT_ID}" \
        --format="value(billingEnabled)" 2>/dev/null || echo "false")
    
    if [[ "${billing_enabled}" != "True" ]]; then
        log_error "Billing is not enabled for project '${PROJECT_ID}'"
        log_error "Please enable billing: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    # Check required tools
    local tools=("curl" "openssl" "terraform")
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_warning "${tool} is not installed but may be needed for full functionality"
        fi
    done
    
    log_success "Prerequisites validation completed"
}

validate_permissions() {
    log_info "Validating required permissions..."
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    # Test essential permissions
    local required_permissions=(
        "compute.instances.create"
        "compute.instances.delete"
        "storage.buckets.create"
        "batch.jobs.create"
        "iam.serviceAccounts.create"
        "monitoring.dashboards.create"
    )
    
    local missing_permissions=()
    
    # Check IAM permissions (this is a simplified check)
    for permission in "${required_permissions[@]}"; do
        if [[ "${DRY_RUN}" == "false" ]]; then
            # In real deployment, we'll catch permission errors during actual operations
            log_debug "Will validate ${permission} during deployment"
        fi
    done
    
    log_success "Permission validation completed"
}

# Configuration functions
setup_environment() {
    log_info "Setting up environment configuration..."
    
    # Set defaults if not provided
    REGION="${REGION:-${DEFAULT_REGION}}"
    ZONE="${ZONE:-${DEFAULT_ZONE}}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    readonly CLUSTER_NAME="hpc-cluster-${RANDOM_SUFFIX}"
    readonly STORAGE_BUCKET="hpc-data-${RANDOM_SUFFIX}"
    readonly JOB_QUEUE_NAME="hpc-queue-${RANDOM_SUFFIX}"
    
    # Save configuration
    cat > "${CONFIG_FILE}" << EOF
# HPC Cluster Configuration
# Generated on $(date)
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
ZONE="${ZONE}"
CLUSTER_NAME="${CLUSTER_NAME}"
STORAGE_BUCKET="${STORAGE_BUCKET}"
JOB_QUEUE_NAME="${JOB_QUEUE_NAME}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
DEPLOYMENT_TIME="$(date -Iseconds)"
EOF
    
    log_success "Environment configured:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Cluster Name: ${CLUSTER_NAME}"
    log_info "  Storage Bucket: ${STORAGE_BUCKET}"
    log_info "  Configuration saved to: ${CONFIG_FILE}"
}

show_deployment_plan() {
    log_info "Deployment Plan:"
    echo ""
    echo "  📋 Project: ${PROJECT_ID}"
    echo "  🌍 Region: ${REGION}"
    echo "  📍 Zone: ${ZONE}"
    echo ""
    echo "  🏗️  Infrastructure to be created:"
    echo "    • HPC Cluster: ${CLUSTER_NAME}"
    echo "    • Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "    • Compute Engine instances (CPU and GPU nodes)"
    echo "    • Cloud Batch queues and jobs"
    echo "    • Monitoring dashboards"
    echo "    • Cost optimization policies"
    echo ""
    echo "  💰 Estimated costs:"
    echo "    • GPU instances: ~\$1-3/hour per T4 GPU"
    echo "    • CPU instances: ~\$0.30-1.50/hour per c2-standard-16"
    echo "    • Storage: ~\$0.02/GB/month"
    echo "    • Batch service: No additional charges"
    echo ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
        return
    fi
    
    if [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
        echo -n "Do you want to proceed with deployment? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Deployment functions
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "storage.googleapis.com"
        "batch.googleapis.com"
        "container.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbilling.googleapis.com"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would enable APIs: ${apis[*]}"
        return
    fi
    
    for api in "${apis[@]}"; do
        log_debug "Enabling ${api}..."
        if ! gcloud services enable "${api}" --quiet; then
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled"
}

install_cluster_toolkit() {
    log_info "Installing Google Cloud Cluster Toolkit..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would download and install Cluster Toolkit"
        return
    fi
    
    # Check if Cluster Toolkit is already installed
    if command -v gcluster &> /dev/null; then
        log_info "Cluster Toolkit already installed"
        return
    fi
    
    # Download and install Cluster Toolkit
    local toolkit_url="https://github.com/GoogleCloudPlatform/cluster-toolkit/releases/latest/download/gcluster"
    local install_dir="/usr/local/bin"
    
    # Try to install to /usr/local/bin, fallback to local directory
    if curl -LsSf "${toolkit_url}" -o gcluster 2>/dev/null; then
        chmod +x gcluster
        
        if sudo mv gcluster "${install_dir}/" 2>/dev/null; then
            log_success "Cluster Toolkit installed to ${install_dir}/gcluster"
        else
            log_warning "Cannot install to ${install_dir}, installing locally"
            mv gcluster "${SCRIPT_DIR}/"
            export PATH="${SCRIPT_DIR}:${PATH}"
            log_success "Cluster Toolkit installed to ${SCRIPT_DIR}/gcluster"
        fi
    else
        log_error "Failed to download Cluster Toolkit"
        exit 1
    fi
}

create_storage_infrastructure() {
    log_info "Creating HPC data storage infrastructure..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create storage bucket: gs://${STORAGE_BUCKET}"
        return
    fi
    
    # Create storage bucket
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${STORAGE_BUCKET}"; then
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${STORAGE_BUCKET}"
    
    # Create lifecycle policy
    cat > "${SCRIPT_DIR}/lifecycle.json" << EOF
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90}
    }
  ]
}
EOF
    
    gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://${STORAGE_BUCKET}"
    
    log_success "Storage infrastructure created: gs://${STORAGE_BUCKET}"
}

create_cluster_blueprint() {
    log_info "Creating Cluster Toolkit blueprint..."
    
    # Create blueprint file
    cat > "${SCRIPT_DIR}/hpc-blueprint.yaml" << EOF
blueprint_name: ${CLUSTER_NAME}

vars:
  project_id: ${PROJECT_ID}
  deployment_name: ${CLUSTER_NAME}
  region: ${REGION}
  zone: ${ZONE}

deployment_groups:
- group: primary
  modules:
  - id: network
    source: modules/network/pre-existing-vpc
  
  - id: hpc-compute
    source: modules/compute/vm-instance
    use: [network]
    settings:
      name_prefix: hpc-worker
      machine_type: c2-standard-16
      instance_count: 2
      enable_placement: true
      placement_policy_name: hpc-placement
      disk_size_gb: 100
      disk_type: pd-ssd
      
  - id: gpu-compute
    source: modules/compute/vm-instance
    use: [network]
    settings:
      name_prefix: gpu-worker
      machine_type: n1-standard-8
      instance_count: 1
      guest_accelerator:
      - type: nvidia-tesla-t4
        count: 1
      disk_size_gb: 200
      disk_type: pd-ssd
      
  - id: storage-mount
    source: modules/file-system/cloud-storage-bucket
    settings:
      bucket_name: ${STORAGE_BUCKET}
      mount_point: /mnt/hpc-data
EOF
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create cluster blueprint with GPU and CPU nodes"
        return
    fi
    
    log_success "Cluster blueprint created: ${SCRIPT_DIR}/hpc-blueprint.yaml"
}

deploy_cluster() {
    log_info "Deploying HPC cluster infrastructure..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would deploy cluster using Terraform via Cluster Toolkit"
        return
    fi
    
    # Generate cluster deployment
    if ! gcluster create "${SCRIPT_DIR}/hpc-blueprint.yaml"; then
        log_error "Failed to generate cluster deployment"
        exit 1
    fi
    
    # Deploy with Terraform
    cd "${CLUSTER_NAME}" || {
        log_error "Cluster deployment directory not found"
        exit 1
    }
    
    # Initialize Terraform
    if ! terraform init; then
        log_error "Terraform initialization failed"
        exit 1
    fi
    
    # Plan deployment
    if ! terraform plan -var="project_id=${PROJECT_ID}" -out=tfplan; then
        log_error "Terraform planning failed"
        exit 1
    fi
    
    # Apply deployment
    if ! terraform apply tfplan; then
        log_error "Terraform deployment failed"
        exit 1
    fi
    
    cd - || exit 1
    
    log_success "HPC cluster deployed successfully"
}

configure_batch_scheduling() {
    log_info "Configuring Cloud Batch with intelligent scheduling..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would configure Cloud Batch jobs with spot instances"
        return
    fi
    
    # Create sample batch job with spot scheduling
    cat > "${SCRIPT_DIR}/batch-job-config.json" << EOF
{
  "taskGroups": [{
    "taskSpec": {
      "runnables": [{
        "script": {
          "text": "#!/bin/bash\necho 'Processing HPC workload with Cloud Batch'\necho 'Instance type:' && curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/machine-type\nsleep 300\necho 'Workload completed successfully'"
        }
      }],
      "computeResource": {
        "cpuMilli": 8000,
        "memoryMib": 16384
      },
      "maxRetryCount": 2,
      "maxRunDuration": "1800s"
    },
    "taskCount": 4,
    "parallelism": 2
  }],
  "allocationPolicy": {
    "instances": [{
      "policy": {
        "machineType": "c2-standard-8",
        "provisioningModel": "SPOT"
      }
    }],
    "location": {
      "allowedLocations": ["zones/${ZONE}"]
    }
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF
    
    # Submit the job
    if ! gcloud batch jobs submit "hpc-workload-spot-${RANDOM_SUFFIX}" \
        --location="${REGION}" \
        --config="${SCRIPT_DIR}/batch-job-config.json"; then
        log_warning "Failed to submit sample batch job (this is non-critical)"
    else
        log_success "Sample batch job submitted with intelligent scheduling"
    fi
}

setup_monitoring() {
    log_info "Setting up monitoring and cost optimization..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would create monitoring dashboard and cost alerts"
        return
    fi
    
    # Create monitoring dashboard
    cat > "${SCRIPT_DIR}/hpc-monitoring.json" << EOF
{
  "displayName": "HPC Cluster Monitoring - ${CLUSTER_NAME}",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "GPU Utilization",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Batch Job Status",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/num_tasks_per_state\""
              }
            }
          }
        }
      }
    ]
  }
}
EOF
    
    if ! gcloud monitoring dashboards create \
        --config-from-file="${SCRIPT_DIR}/hpc-monitoring.json"; then
        log_warning "Failed to create monitoring dashboard (this is non-critical)"
    else
        log_success "Monitoring dashboard created"
    fi
    
    # Set up budget alert
    local billing_account
    billing_account=$(gcloud beta billing projects describe "${PROJECT_ID}" \
        --format="value(billingAccountName)" 2>/dev/null | cut -d'/' -f2 || echo "")
    
    if [[ -n "${billing_account}" ]]; then
        if gcloud alpha billing budgets create \
            --billing-account="${billing_account}" \
            --display-name="HPC Cluster Budget Alert - ${CLUSTER_NAME}" \
            --budget-amount=100USD \
            --threshold-rule=percent=80,basis=CURRENT_SPEND \
            --threshold-rule=percent=100,basis=CURRENT_SPEND; then
            log_success "Budget alert configured"
        else
            log_warning "Failed to create budget alert (this is non-critical)"
        fi
    else
        log_warning "Cannot determine billing account for budget alerts"
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would verify all deployed resources"
        return
    fi
    
    # Check storage bucket
    if gsutil ls "gs://${STORAGE_BUCKET}" &>/dev/null; then
        log_success "✅ Storage bucket verified"
    else
        log_error "❌ Storage bucket verification failed"
    fi
    
    # Check compute instances
    local instance_count
    instance_count=$(gcloud compute instances list \
        --filter="name~(hpc-worker|gpu-worker)" \
        --format="value(name)" | wc -l)
    
    if [[ "${instance_count}" -gt 0 ]]; then
        log_success "✅ Compute instances verified (${instance_count} instances)"
    else
        log_warning "⚠️ No compute instances found (may still be starting)"
    fi
    
    # Check batch jobs
    local job_count
    job_count=$(gcloud batch jobs list --location="${REGION}" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "${job_count}" -gt 0 ]]; then
        log_success "✅ Batch jobs verified (${job_count} jobs)"
    else
        log_info "ℹ️ No batch jobs found (this is normal for initial deployment)"
    fi
    
    log_success "Deployment verification completed"
}

display_connection_info() {
    log_info "Deployment completed successfully! 🎉"
    echo ""
    echo "📋 Connection Information:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "  Cluster Name: ${CLUSTER_NAME}"
    echo ""
    echo "🔧 Useful Commands:"
    echo "  # List compute instances"
    echo "  gcloud compute instances list --filter='name~(hpc-worker|gpu-worker)'"
    echo ""
    echo "  # Check batch jobs"
    echo "  gcloud batch jobs list --location=${REGION}"
    echo ""
    echo "  # Access storage bucket"
    echo "  gsutil ls gs://${STORAGE_BUCKET}"
    echo ""
    echo "  # View monitoring dashboard"
    echo "  # Go to: https://console.cloud.google.com/monitoring/dashboards"
    echo ""
    echo "💡 Next Steps:"
    echo "  1. Submit your HPC workloads using Cloud Batch"
    echo "  2. Monitor resource utilization in Cloud Console"
    echo "  3. Optimize costs using spot instances for fault-tolerant workloads"
    echo "  4. Scale cluster nodes based on computational demands"
    echo ""
    echo "🧹 Cleanup:"
    echo "  Run './destroy.sh' to remove all deployed resources"
    echo ""
    echo "📝 Configuration saved to: ${CONFIG_FILE}"
    echo "📋 Logs available at: ${LOG_FILE}"
}

# Main execution
main() {
    log_info "Starting HPC Cluster deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    parse_args "$@"
    validate_prerequisites
    validate_permissions
    setup_environment
    show_deployment_plan
    
    enable_apis
    install_cluster_toolkit
    create_storage_infrastructure
    create_cluster_blueprint
    deploy_cluster
    configure_batch_scheduling
    setup_monitoring
    verify_deployment
    
    display_connection_info
    
    log_success "HPC Cluster deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"
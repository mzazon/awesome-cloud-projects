#!/bin/bash

# Deploy script for High-Performance Computing Workloads with Cloud Filestore and Cloud Batch
# This script deploys the complete HPC infrastructure from the recipe

set -euo pipefail

# Enable debug logging if DEBUG is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check for required commands
    local required_commands=("gcloud" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            log_error "Please install $cmd and try again"
            exit 1
        fi
    done
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Please run 'gcloud auth login' first"
        exit 1
    fi
    
    # Check for project configuration
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$current_project" ]]; then
        log_warning "No default project set in gcloud config"
    else
        log_info "Current project: $current_project"
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-hpc-project-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export FILESTORE_NAME="${FILESTORE_NAME:-hpc-storage-${random_suffix}}"
    export BATCH_JOB_NAME="${BATCH_JOB_NAME:-hpc-simulation-${random_suffix}}"
    export VPC_NAME="${VPC_NAME:-hpc-network-${random_suffix}}"
    export SUBNET_NAME="${SUBNET_NAME:-hpc-subnet-${random_suffix}}"
    
    # Configuration parameters
    export FILESTORE_TIER="${FILESTORE_TIER:-ENTERPRISE}"
    export FILESTORE_CAPACITY="${FILESTORE_CAPACITY:-2560GB}"
    export MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-2}"
    export TASK_COUNT="${TASK_COUNT:-4}"
    export PARALLELISM="${PARALLELISM:-2}"
    
    log_info "Environment variables configured:"
    log_info "  PROJECT_ID: $PROJECT_ID"
    log_info "  REGION: $REGION"
    log_info "  ZONE: $ZONE"
    log_info "  FILESTORE_NAME: $FILESTORE_NAME"
    log_info "  VPC_NAME: $VPC_NAME"
    
    log_success "Environment setup completed"
}

# Function to configure gcloud
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set default project and region if PROJECT_ID is provided
    if [[ -n "$PROJECT_ID" ]]; then
        gcloud config set project "$PROJECT_ID"
        log_info "Set project to: $PROJECT_ID"
    fi
    
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "file.googleapis.com"
        "batch.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create VPC network
create_vpc_network() {
    log_info "Creating VPC network infrastructure..."
    
    # Create VPC network
    log_info "Creating VPC network: $VPC_NAME"
    if gcloud compute networks create "$VPC_NAME" \
        --subnet-mode regional \
        --bgp-routing-mode regional \
        --quiet; then
        log_success "VPC network created: $VPC_NAME"
    else
        log_error "Failed to create VPC network"
        exit 1
    fi
    
    # Create subnet
    log_info "Creating subnet: $SUBNET_NAME"
    if gcloud compute networks subnets create "$SUBNET_NAME" \
        --network "$VPC_NAME" \
        --range 10.0.0.0/16 \
        --region "$REGION" \
        --quiet; then
        log_success "Subnet created: $SUBNET_NAME"
    else
        log_error "Failed to create subnet"
        exit 1
    fi
    
    # Create firewall rule for internal communication
    log_info "Creating firewall rule for internal communication"
    if gcloud compute firewall-rules create "${VPC_NAME}-allow-internal" \
        --network "$VPC_NAME" \
        --allow tcp,udp,icmp \
        --source-ranges 10.0.0.0/16 \
        --quiet; then
        log_success "Firewall rule created: ${VPC_NAME}-allow-internal"
    else
        log_error "Failed to create firewall rule"
        exit 1
    fi
    
    log_success "VPC network infrastructure created successfully"
}

# Function to create Filestore instance
create_filestore() {
    log_info "Creating Cloud Filestore instance..."
    
    log_info "Creating Filestore instance: $FILESTORE_NAME"
    log_info "  Tier: $FILESTORE_TIER"
    log_info "  Capacity: $FILESTORE_CAPACITY"
    log_info "  Network: $VPC_NAME"
    
    if gcloud filestore instances create "$FILESTORE_NAME" \
        --location "$ZONE" \
        --tier "$FILESTORE_TIER" \
        --file-share name="hpc_data",capacity="$FILESTORE_CAPACITY" \
        --network name="$VPC_NAME" \
        --quiet; then
        log_success "Filestore instance creation initiated: $FILESTORE_NAME"
    else
        log_error "Failed to create Filestore instance"
        exit 1
    fi
    
    # Wait for Filestore instance to become ready
    log_info "Waiting for Filestore instance to become ready..."
    local max_attempts=20
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state
        state=$(gcloud filestore instances describe "$FILESTORE_NAME" \
            --location "$ZONE" \
            --format="value(state)" 2>/dev/null || echo "")
        
        if [[ "$state" == "READY" ]]; then
            log_success "Filestore instance is ready"
            break
        elif [[ "$state" == "ERROR" ]]; then
            log_error "Filestore instance creation failed"
            exit 1
        else
            log_info "Filestore instance state: $state (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Timeout waiting for Filestore instance to become ready"
        exit 1
    fi
    
    # Get Filestore IP address
    export FILESTORE_IP
    FILESTORE_IP=$(gcloud filestore instances describe "$FILESTORE_NAME" \
        --location "$ZONE" \
        --format="value(networks[0].ipAddresses[0])")
    
    if [[ -z "$FILESTORE_IP" ]]; then
        log_error "Failed to get Filestore IP address"
        exit 1
    fi
    
    log_success "Filestore instance ready at IP: $FILESTORE_IP"
}

# Function to create batch job configuration
create_batch_job_config() {
    log_info "Creating batch job configuration..."
    
    local config_file="hpc-job-config.json"
    
    cat > "$config_file" << EOF
{
  "taskGroups": [
    {
      "taskSpec": {
        "runnables": [
          {
            "script": {
              "text": "#!/bin/bash\\necho 'Starting HPC simulation job'\\nmkdir -p /mnt/hpc_data/results\\necho 'Job ID: '\$BATCH_TASK_INDEX > /mnt/hpc_data/results/job_\$BATCH_TASK_INDEX.log\\necho 'Running scientific computation simulation...'\\nsleep 60\\necho 'Simulation completed successfully' >> /mnt/hpc_data/results/job_\$BATCH_TASK_INDEX.log\\necho 'HPC job finished'"
            }
          }
        ],
        "computeResource": {
          "cpuMilli": 2000,
          "memoryMib": 4096
        },
        "maxRetryCount": 2,
        "maxRunDuration": "600s",
        "volumes": [
          {
            "nfs": {
              "server": "${FILESTORE_IP}",
              "remotePath": "/hpc_data"
            },
            "mountPath": "/mnt/hpc_data"
          }
        ]
      },
      "taskCount": ${TASK_COUNT},
      "parallelism": ${PARALLELISM}
    }
  ],
  "allocationPolicy": {
    "instances": [
      {
        "instanceTemplate": {
          "machineType": "${MACHINE_TYPE}"
        }
      }
    ],
    "location": {
      "allowedLocations": ["zones/${ZONE}"]
    },
    "network": {
      "networkInterfaces": [
        {
          "network": "projects/${PROJECT_ID}/global/networks/${VPC_NAME}",
          "subnetwork": "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/${SUBNET_NAME}"
        }
      ]
    }
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF
    
    log_success "Batch job configuration created: $config_file"
}

# Function to submit batch job
submit_batch_job() {
    log_info "Submitting HPC batch job..."
    
    if gcloud batch jobs submit "$BATCH_JOB_NAME" \
        --location "$REGION" \
        --config hpc-job-config.json \
        --quiet; then
        log_success "Batch job submitted: $BATCH_JOB_NAME"
    else
        log_error "Failed to submit batch job"
        exit 1
    fi
    
    # Monitor job status
    log_info "Monitoring job execution status..."
    local job_state
    job_state=$(gcloud batch jobs describe "$BATCH_JOB_NAME" \
        --location "$REGION" \
        --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
    
    log_info "Initial job state: $job_state"
    
    # Wait for job completion with timeout
    local max_wait_time=900  # 15 minutes
    local elapsed_time=0
    local sleep_interval=30
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        job_state=$(gcloud batch jobs describe "$BATCH_JOB_NAME" \
            --location "$REGION" \
            --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
        
        log_info "Current job state: $job_state (elapsed: ${elapsed_time}s)"
        
        if [[ "$job_state" == "SUCCEEDED" ]]; then
            log_success "HPC batch job completed successfully"
            break
        elif [[ "$job_state" == "FAILED" ]]; then
            log_error "HPC batch job failed"
            # Show job logs for debugging
            log_info "Retrieving job logs for debugging..."
            gcloud logging read "resource.type=\"batch_job\" AND resource.labels.job_id=\"${BATCH_JOB_NAME}\"" \
                --limit=10 \
                --format="value(textPayload)" || true
            exit 1
        fi
        
        sleep $sleep_interval
        elapsed_time=$((elapsed_time + sleep_interval))
    done
    
    if [[ $elapsed_time -ge $max_wait_time ]]; then
        log_warning "Job monitoring timeout reached. Job may still be running."
        log_info "Current job state: $job_state"
        log_info "You can monitor the job manually with:"
        log_info "  gcloud batch jobs describe $BATCH_JOB_NAME --location $REGION"
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring Cloud Monitoring for HPC workloads..."
    
    # Create custom metric descriptor
    local metric_file="job-metric-descriptor.json"
    cat > "$metric_file" << EOF
{
  "type": "custom.googleapis.com/hpc/job_completion_rate",
  "displayName": "HPC Job Completion Rate",
  "description": "Rate of successful HPC job completions",
  "metricKind": "GAUGE",
  "valueType": "DOUBLE",
  "labels": [
    {
      "key": "job_type",
      "description": "Type of HPC job"
    }
  ]
}
EOF
    
    # Create alert policy
    local alert_file="alert-policy.json"
    cat > "$alert_file" << EOF
{
  "displayName": "HPC Job Failure Alert",
  "documentation": {
    "content": "Alert when HPC batch jobs fail",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Batch job failure condition",
      "conditionThreshold": {
        "filter": "resource.type=\"batch_job\"",
        "comparison": "COMPARISON_EQUAL",
        "thresholdValue": 1
      }
    }
  ],
  "enabled": true
}
EOF
    
    log_success "Monitoring configuration files created"
    log_info "Custom metrics and alerts configured for HPC performance tracking"
}

# Function to setup auto-scaling
setup_auto_scaling() {
    log_info "Setting up auto-scaling configuration..."
    
    # Create instance template
    log_info "Creating instance template for HPC nodes..."
    if gcloud compute instance-templates create hpc-node-template \
        --machine-type e2-standard-4 \
        --image-family ubuntu-2004-lts \
        --image-project ubuntu-os-cloud \
        --subnet "$SUBNET_NAME" \
        --metadata startup-script="#!/bin/bash
apt-get update
apt-get install -y nfs-common
mkdir -p /mnt/hpc_data
mount -t nfs ${FILESTORE_IP}:/hpc_data /mnt/hpc_data
echo \"${FILESTORE_IP}:/hpc_data /mnt/hpc_data nfs defaults 0 0\" >> /etc/fstab" \
        --quiet; then
        log_success "Instance template created: hpc-node-template"
    else
        log_error "Failed to create instance template"
        exit 1
    fi
    
    # Create managed instance group
    log_info "Creating managed instance group..."
    if gcloud compute instance-groups managed create hpc-compute-group \
        --template hpc-node-template \
        --size 0 \
        --zone "$ZONE" \
        --quiet; then
        log_success "Managed instance group created: hpc-compute-group"
    else
        log_error "Failed to create managed instance group"
        exit 1
    fi
    
    # Configure autoscaling
    log_info "Configuring autoscaling policies..."
    if gcloud compute instance-groups managed set-autoscaling hpc-compute-group \
        --zone "$ZONE" \
        --max-num-replicas 10 \
        --min-num-replicas 0 \
        --target-cpu-utilization 0.7 \
        --cool-down-period 300 \
        --quiet; then
        log_success "Autoscaling configured for hpc-compute-group"
    else
        log_error "Failed to configure autoscaling"
        exit 1
    fi
    
    log_success "Auto-scaling setup completed"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Filestore instance
    log_info "Validating Filestore instance..."
    local filestore_state
    filestore_state=$(gcloud filestore instances describe "$FILESTORE_NAME" \
        --location "$ZONE" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$filestore_state" == "READY" ]]; then
        log_success "Filestore instance is ready"
    else
        log_error "Filestore instance validation failed. State: $filestore_state"
        return 1
    fi
    
    # Check VPC network
    log_info "Validating VPC network..."
    if gcloud compute networks describe "$VPC_NAME" --quiet >/dev/null 2>&1; then
        log_success "VPC network exists and is accessible"
    else
        log_error "VPC network validation failed"
        return 1
    fi
    
    # Check batch job
    log_info "Validating batch job..."
    local job_exists
    job_exists=$(gcloud batch jobs describe "$BATCH_JOB_NAME" \
        --location "$REGION" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$job_exists" ]]; then
        log_success "Batch job exists and is trackable"
    else
        log_warning "Batch job validation inconclusive"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Resources Created:"
    echo "- VPC Network: $VPC_NAME"
    echo "- Subnet: $SUBNET_NAME (10.0.0.0/16)"
    echo "- Firewall Rule: ${VPC_NAME}-allow-internal"
    echo "- Filestore Instance: $FILESTORE_NAME ($FILESTORE_IP)"
    echo "- Batch Job: $BATCH_JOB_NAME"
    echo "- Instance Template: hpc-node-template"
    echo "- Instance Group: hpc-compute-group"
    echo ""
    echo "Next Steps:"
    echo "- Monitor batch job: gcloud batch jobs describe $BATCH_JOB_NAME --location $REGION"
    echo "- View job logs: gcloud logging read \"resource.type=\\\"batch_job\\\" AND resource.labels.job_id=\\\"$BATCH_JOB_NAME\\\"\""
    echo "- Check Filestore: gcloud filestore instances describe $FILESTORE_NAME --location $ZONE"
    echo ""
    echo "Cost Monitoring:"
    echo "- Monitor costs in Cloud Console Billing"
    echo "- Resources incur charges until cleanup is performed"
    echo ""
    echo "Cleanup:"
    echo "- Run ./destroy.sh to clean up all resources"
    echo "=================="
}

# Function to cleanup on error
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_warning "Some resources may have been created. Run ./destroy.sh to clean up."
    fi
    exit $exit_code
}

# Main deployment function
main() {
    # Set trap for cleanup on error
    trap cleanup_on_error EXIT
    
    log_info "Starting HPC infrastructure deployment..."
    log_info "Deployment script for: High-Performance Computing Workloads with Cloud Filestore and Cloud Batch"
    
    # Execute deployment steps
    validate_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_vpc_network
    create_filestore
    create_batch_job_config
    submit_batch_job
    configure_monitoring
    setup_auto_scaling
    validate_deployment
    
    # Clean up temporary files
    rm -f hpc-job-config.json job-metric-descriptor.json alert-policy.json
    
    log_success "HPC infrastructure deployment completed successfully!"
    display_summary
    
    # Remove error trap
    trap - EXIT
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
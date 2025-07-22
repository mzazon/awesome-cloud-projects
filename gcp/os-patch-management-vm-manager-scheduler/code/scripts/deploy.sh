#!/bin/bash

#########################################################################
# GCP OS Patch Management with VM Manager and Cloud Scheduler
# Deployment Script
#
# This script automates the deployment of a comprehensive OS patch 
# management system using Google Cloud's VM Manager, Cloud Scheduler,
# and Cloud Monitoring.
#
# Author: Generated from Recipe b7e4f8c2
# Version: 1.0
#########################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Exit on error with cleanup
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    # Add any specific cleanup logic here if needed
    exit 1
}

trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.deploy_config"

# Default values
DEFAULT_PROJECT_ID="patch-mgmt-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_VM_COUNT=3

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    log "Loading configuration from $CONFIG_FILE"
else
    log "No configuration file found, using defaults"
fi

# Set environment variables with defaults
export PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
export REGION="${REGION:-$DEFAULT_REGION}"
export ZONE="${ZONE:-$DEFAULT_ZONE}"
export VM_COUNT="${VM_COUNT:-$DEFAULT_VM_COUNT}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export INSTANCE_GROUP_NAME="patch-test-group-${RANDOM_SUFFIX}"
export SCHEDULER_JOB_NAME="patch-deployment-${RANDOM_SUFFIX}"
export FUNCTION_NAME="patch-trigger-${RANDOM_SUFFIX}"
export BUCKET_NAME="patch-scripts-${PROJECT_ID}"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists (create if it doesn't)
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        warning "Project $PROJECT_ID does not exist. Creating it..."
        gcloud projects create "$PROJECT_ID" --name="OS Patch Management"
    fi
    
    success "Prerequisites check completed"
}

# Display deployment summary
show_deployment_summary() {
    log "Deployment Configuration Summary:"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "VM Count: $VM_COUNT"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Function Name: $FUNCTION_NAME"
    echo "Scheduler Job: $SCHEDULER_JOB_NAME"
    echo "=================================="
    echo ""
    
    read -p "Do you want to continue with this deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user."
        exit 0
    fi
}

# Save configuration
save_config() {
    log "Saving configuration to $CONFIG_FILE"
    cat > "$CONFIG_FILE" << EOF
# GCP OS Patch Management Deployment Configuration
# Generated: $(date)
PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
VM_COUNT="$VM_COUNT"
INSTANCE_GROUP_NAME="$INSTANCE_GROUP_NAME"
SCHEDULER_JOB_NAME="$SCHEDULER_JOB_NAME"
FUNCTION_NAME="$FUNCTION_NAME"
BUCKET_NAME="$BUCKET_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    success "Configuration saved"
}

# Configure GCP project and enable APIs
configure_gcp_project() {
    log "Configuring GCP project and enabling APIs..."
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Enable required APIs
    local apis=(
        "compute.googleapis.com"
        "osconfig.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        gcloud services enable "$api"
    done
    
    success "GCP project configured and APIs enabled"
}

# Create VM instances with VM Manager enabled
create_vm_instances() {
    log "Creating VM instances with VM Manager enabled..."
    
    for ((i=1; i<=VM_COUNT; i++)); do
        local vm_name="patch-test-vm-${i}"
        log "Creating VM instance: $vm_name"
        
        gcloud compute instances create "$vm_name" \
            --zone="$ZONE" \
            --machine-type=e2-medium \
            --image-family=ubuntu-2004-lts \
            --image-project=ubuntu-os-cloud \
            --boot-disk-size=20GB \
            --boot-disk-type=pd-standard \
            --metadata=enable-osconfig=TRUE \
            --tags=patch-management \
            --scopes=https://www.googleapis.com/auth/cloud-platform \
            --quiet
    done
    
    success "Created $VM_COUNT VM instances with VM Manager enabled"
}

# Wait for and verify VM Manager setup
verify_vm_manager_setup() {
    log "Waiting for VM Manager to collect OS inventory..."
    sleep 60
    
    local vm_name="patch-test-vm-1"
    log "Checking OS inventory for $vm_name"
    
    if gcloud compute os-config inventories describe \
        --instance="$vm_name" \
        --instance-zone="$ZONE" \
        --format="table(updateTime,osInfo.shortName,osInfo.version)" \
        --quiet > /dev/null 2>&1; then
        success "VM Manager OS inventory collection verified"
    else
        warning "VM Manager inventory not yet available (this is normal for new instances)"
    fi
}

# Create Cloud Storage bucket and upload patch scripts
create_storage_bucket() {
    log "Creating Cloud Storage bucket for patch scripts..."
    
    # Create bucket
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME"
    
    # Create pre-patch backup script
    cat > "${SCRIPT_DIR}/pre-patch-backup.sh" << 'EOF'
#!/bin/bash
echo "Starting pre-patch backup at $(date)"

# Create system backup
sudo tar -czf /tmp/system-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
    /etc /var/log /home --exclude=/home/*/.cache 2>/dev/null || true

echo "Pre-patch backup completed successfully"
EOF
    
    # Create post-patch validation script
    cat > "${SCRIPT_DIR}/post-patch-validation.sh" << 'EOF'
#!/bin/bash
echo "Starting post-patch validation at $(date)"

# Check system services
systemctl status ssh || true
systemctl status networking || true

# Verify disk space
df -h

# Check for any failed services
systemctl --failed || true

echo "Post-patch validation completed at $(date)"
EOF
    
    # Upload scripts to Cloud Storage
    gsutil cp "${SCRIPT_DIR}/pre-patch-backup.sh" "gs://$BUCKET_NAME/"
    gsutil cp "${SCRIPT_DIR}/post-patch-validation.sh" "gs://$BUCKET_NAME/"
    
    success "Cloud Storage bucket created and patch scripts uploaded"
}

# Deploy Cloud Function for patch orchestration
deploy_cloud_function() {
    log "Deploying Cloud Function for patch orchestration..."
    
    # Create function directory
    local func_dir="${SCRIPT_DIR}/../patch-function"
    mkdir -p "$func_dir"
    
    # Create Cloud Function source code
    cat > "$func_dir/main.py" << 'EOF'
import json
import os
from google.cloud import compute_v1
from google.cloud import osconfig_v1
from flask import Request

def trigger_patch_deployment(request: Request):
    """Cloud Function to trigger VM patch deployment"""
    
    project_id = os.environ.get('GCP_PROJECT')
    zone = os.environ.get('ZONE', 'us-central1-a')
    
    try:
        # Initialize OS Config client
        client = osconfig_v1.OsConfigServiceClient()
        
        # Create patch job request
        patch_job = {
            "description": "Automated patch deployment via Cloud Scheduler",
            "instance_filter": {
                "instance_name_prefixes": ["patch-test-vm-"]
            },
            "patch_config": {
                "reboot_config": osconfig_v1.PatchConfig.RebootConfig.REBOOT_IF_REQUIRED,
                "apt": {
                    "type": osconfig_v1.AptSettings.Type.UPGRADE,
                    "excludes": ["test-package"]
                }
            },
            "duration": {"seconds": 7200},
            "dry_run": False
        }
        
        # Execute patch job
        parent = f"projects/{project_id}"
        response = client.execute_patch_job(
            request={"parent": parent, "patch_job": patch_job}
        )
        
        return {
            "status": "success",
            "patch_job_name": response.name,
            "message": f"Patch job {response.name} started successfully"
        }
        
    except Exception as e:
        return {
            "status": "error",
            "message": f"Failed to start patch job: {str(e)}"
        }
EOF
    
    cat > "$func_dir/requirements.txt" << 'EOF'
google-cloud-compute==1.14.1
google-cloud-os-config==1.17.1
flask==2.3.3
EOF
    
    # Deploy Cloud Function
    cd "$func_dir"
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python39 \
        --trigger-http \
        --entry-point trigger_patch_deployment \
        --memory 256MB \
        --timeout 300s \
        --set-env-vars ZONE="$ZONE" \
        --allow-unauthenticated \
        --quiet
    
    cd "$SCRIPT_DIR"
    
    success "Cloud Function deployed for patch orchestration"
}

# Create Cloud Scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job for automated patch deployment..."
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    # Create Cloud Scheduler job
    gcloud scheduler jobs create http "$SCHEDULER_JOB_NAME" \
        --schedule="0 2 * * SUN" \
        --time-zone="America/New_York" \
        --uri="$function_url" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"scheduled-patch-deployment"}' \
        --description="Weekly automated patch deployment for VM fleet" \
        --quiet
    
    success "Cloud Scheduler job created for weekly patch deployment"
}

# Configure Cloud Monitoring dashboard
configure_monitoring() {
    log "Configuring Cloud Monitoring dashboard..."
    
    # Create monitoring dashboard configuration
    cat > "${SCRIPT_DIR}/dashboard-config.json" << EOF
{
  "displayName": "VM Patch Management Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "VM Instance Status",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/up\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
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
    gcloud monitoring dashboards create \
        --config-from-file="${SCRIPT_DIR}/dashboard-config.json" \
        --quiet
    
    success "Cloud Monitoring dashboard created"
}

# Set up alert policies
setup_alert_policies() {
    log "Setting up alert policies for patch management..."
    
    # Create alert policy configuration
    cat > "${SCRIPT_DIR}/alert-policy.yaml" << EOF
displayName: "Patch Deployment Failure Alert"
documentation:
  content: "Alert triggered when patch deployment fails on VM instances"
conditions:
  - displayName: "VM Instance Down"
    conditionThreshold:
      filter: 'resource.type="gce_instance" AND metric.type="compute.googleapis.com/instance/up"'
      comparison: COMPARISON_LESS_THAN
      thresholdValue: 1
      duration: 300s
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_MEAN
notificationChannels: []
alertStrategy:
  autoClose: 86400s
EOF
    
    # Create alert policy
    gcloud alpha monitoring policies create \
        --policy-from-file="${SCRIPT_DIR}/alert-policy.yaml" \
        --quiet
    
    success "Alert policy created for patch deployment monitoring"
}

# Main deployment function
main() {
    log "Starting GCP OS Patch Management deployment..."
    
    # Run deployment steps
    check_prerequisites
    show_deployment_summary
    save_config
    configure_gcp_project
    create_vm_instances
    verify_vm_manager_setup
    create_storage_bucket
    deploy_cloud_function
    create_scheduler_job
    configure_monitoring
    setup_alert_policies
    
    # Display completion summary
    echo ""
    success "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "VM Instances: $VM_COUNT (patch-test-vm-1 to patch-test-vm-$VM_COUNT)"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Scheduler Job: $SCHEDULER_JOB_NAME"
    echo "Storage Bucket: $BUCKET_NAME"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Check VM Manager inventory collection in the Cloud Console"
    echo "2. Monitor patch deployment jobs in OS Config"
    echo "3. Review Cloud Monitoring dashboard for system health"
    echo "4. Test manual patch deployment if needed"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    
    success "All resources deployed successfully!"
}

# Run main function
main "$@"
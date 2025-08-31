#!/bin/bash

# AI Training Optimization with Dynamic Workload Scheduler and Batch - Deployment Script
# This script deploys the complete AI training optimization infrastructure on Google Cloud Platform

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Script metadata
SCRIPT_VERSION="1.0"
RECIPE_NAME="AI Training Optimization with Dynamic Workload Scheduler and Batch"

log "Starting deployment of $RECIPE_NAME"
log "Script version: $SCRIPT_VERSION"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Required for generating random suffixes."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'."
    fi
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Check if PROJECT_ID is already set, otherwise prompt
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            error "Project ID cannot be empty"
        fi
    fi
    
    export PROJECT_ID="$PROJECT_ID"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Zone: $ZONE"
    log "Random suffix: $RANDOM_SUFFIX"
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Project '$PROJECT_ID' not found or not accessible"
    fi
    
    success "Environment variables configured"
}

# Configure gcloud settings
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    gcloud config set project "$PROJECT_ID" || error "Failed to set project"
    gcloud config set compute/region "$REGION" || error "Failed to set region"
    gcloud config set compute/zone "$ZONE" || error "Failed to set zone"
    
    success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "batch.googleapis.com"
        "monitoring.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "$api enabled"
        else
            error "Failed to enable $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully activated..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create service account
create_service_account() {
    log "Creating service account for batch jobs..."
    
    export SERVICE_ACCOUNT_NAME="batch-training-sa-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account
    if gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Batch Training Service Account" \
        --description="Service account for AI training batch jobs" \
        --quiet; then
        success "Service account created: $SERVICE_ACCOUNT"
    else
        error "Failed to create service account"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/storage.objectViewer"
        "roles/monitoring.metricWriter"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log "Granting $role to service account..."
        if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT" \
            --role="$role" \
            --quiet; then
            success "Role $role granted"
        else
            warning "Failed to grant role $role (may already exist)"
        fi
    done
    
    success "Service account configuration completed"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for training data..."
    
    export BUCKET_NAME="ai-training-data-${RANDOM_SUFFIX}"
    
    # Create bucket
    if gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME"; then
        success "Storage bucket created: gs://$BUCKET_NAME"
    else
        error "Failed to create storage bucket"
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://$BUCKET_NAME"; then
        success "Versioning enabled on bucket"
    else
        warning "Failed to enable versioning"
    fi
    
    # Create training script
    log "Creating and uploading training script..."
    
    cat > /tmp/training_script.py << 'EOF'
#!/usr/bin/env python3
import time
import os
import logging
from google.cloud import monitoring_v3
from google.cloud import storage

def setup_logging():
    logging.basicConfig(level=logging.INFO)
    return logging.getLogger(__name__)

def simulate_training(duration_minutes=15):
    logger = setup_logging()
    logger.info("Starting AI model training simulation...")
    
    # Simulate training epochs
    epochs = 10
    for epoch in range(epochs):
        logger.info(f"Training epoch {epoch + 1}/{epochs}")
        
        # Simulate training computation
        time.sleep(duration_minutes * 60 / epochs)
        
        # Log training metrics
        accuracy = 0.7 + (epoch * 0.03)
        loss = 2.5 - (epoch * 0.2)
        logger.info(f"Epoch {epoch + 1} - Accuracy: {accuracy:.3f}, Loss: {loss:.3f}")
    
    logger.info("Training completed successfully!")
    return True

if __name__ == "__main__":
    success = simulate_training()
    exit(0 if success else 1)
EOF
    
    # Upload training script
    if gsutil cp /tmp/training_script.py "gs://$BUCKET_NAME/scripts/"; then
        success "Training script uploaded"
        rm -f /tmp/training_script.py
    else
        error "Failed to upload training script"
    fi
    
    success "Storage bucket setup completed"
}

# Create instance template
create_instance_template() {
    log "Creating instance template for GPU training..."
    
    export TEMPLATE_NAME="ai-training-template-${RANDOM_SUFFIX}"
    
    # Create instance template with GPU configuration
    if gcloud compute instance-templates create "$TEMPLATE_NAME" \
        --machine-type=g2-standard-4 \
        --accelerator=count=1,type=nvidia-l4 \
        --image-family=pytorch-latest-gpu \
        --image-project=deeplearning-platform-release \
        --boot-disk-size=50GB \
        --boot-disk-type=pd-standard \
        --service-account="$SERVICE_ACCOUNT" \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --metadata=install-nvidia-driver=True \
        --tags=ai-training,batch-job \
        --quiet; then
        success "Instance template created: $TEMPLATE_NAME"
    else
        error "Failed to create instance template"
    fi
    
    success "Instance template configuration completed"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating Cloud Monitoring dashboard..."
    
    cat > /tmp/dashboard-config.json << EOF
{
  "displayName": "AI Training Optimization Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "GPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"compute_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\"",
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
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Batch Job Status",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/task/count\"",
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
    
    # Create dashboard
    if gcloud monitoring dashboards create \
        --config-from-file=/tmp/dashboard-config.json \
        --quiet; then
        success "Monitoring dashboard created"
        rm -f /tmp/dashboard-config.json
    else
        warning "Failed to create monitoring dashboard (dashboard may already exist)"
        rm -f /tmp/dashboard-config.json
    fi
    
    success "Monitoring dashboard setup completed"
}

# Create batch job configuration
create_batch_job_config() {
    log "Creating Cloud Batch job configuration..."
    
    cat > /tmp/batch-job.json << EOF
{
  "taskGroups": [
    {
      "name": "training-task-group",
      "taskSpec": {
        "runnables": [
          {
            "container": {
              "imageUri": "gcr.io/deeplearning-platform-release/pytorch-gpu.1-13:latest",
              "commands": [
                "/bin/bash",
                "-c",
                "gsutil cp gs://${BUCKET_NAME}/scripts/training_script.py . && python training_script.py"
              ]
            }
          }
        ],
        "computeResource": {
          "cpuMilli": 4000,
          "memoryMib": 16384
        },
        "maxRetryCount": 2,
        "maxRunDuration": "3600s"
      },
      "taskCount": 1,
      "parallelism": 1
    }
  ],
  "allocationPolicy": {
    "instances": [
      {
        "instanceTemplate": "projects/${PROJECT_ID}/global/instanceTemplates/${TEMPLATE_NAME}",
        "policy": {
          "machineType": "g2-standard-4",
          "accelerators": [
            {
              "type": "nvidia-l4",
              "count": 1
            }
          ],
          "provisioningModel": "STANDARD"
        }
      }
    ]
  },
  "labels": {
    "workload-type": "ai-training",
    "scheduler": "dynamic-workload-scheduler",
    "cost-center": "ml-research"
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF
    
    success "Batch job configuration created"
}

# Submit training job
submit_training_job() {
    log "Submitting training job to Dynamic Workload Scheduler..."
    
    export JOB_NAME="ai-training-job-${RANDOM_SUFFIX}"
    
    # Submit batch job
    if gcloud batch jobs submit "$JOB_NAME" \
        --location="$REGION" \
        --config=/tmp/batch-job.json \
        --quiet; then
        success "Training job submitted: $JOB_NAME"
    else
        error "Failed to submit training job"
    fi
    
    # Clean up temporary file
    rm -f /tmp/batch-job.json
    
    # Check initial job status
    local job_status
    job_status=$(gcloud batch jobs describe "$JOB_NAME" \
        --location="$REGION" \
        --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    log "Initial job status: $job_status"
    
    success "Training job submission completed"
}

# Configure monitoring alerts
configure_monitoring_alerts() {
    log "Configuring monitoring alerts..."
    
    cat > /tmp/alert-policy.json << EOF
{
  "displayName": "AI Training GPU Underutilization Alert",
  "conditions": [
    {
      "displayName": "GPU Utilization Below 70%",
      "conditionThreshold": {
        "filter": "resource.type=\"compute_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\"",
        "comparison": "COMPARISON_LESS_THAN",
        "thresholdValue": 0.7,
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
    
    # Create alert policy
    if gcloud alpha monitoring policies create \
        --policy-from-file=/tmp/alert-policy.json \
        --quiet; then
        success "Monitoring alert policy created"
        rm -f /tmp/alert-policy.json
    else
        warning "Failed to create alert policy (may already exist)"
        rm -f /tmp/alert-policy.json
    fi
    
    success "Monitoring alerts configuration completed"
}

# Save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    local config_file="./deployment-config-${RANDOM_SUFFIX}.env"
    
    cat > "$config_file" << EOF
# AI Training Optimization Deployment Configuration
# Generated on $(date)

PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
SERVICE_ACCOUNT="$SERVICE_ACCOUNT"
BUCKET_NAME="$BUCKET_NAME"
TEMPLATE_NAME="$TEMPLATE_NAME"
JOB_NAME="$JOB_NAME"
EOF
    
    success "Deployment configuration saved to: $config_file"
    log "Use this file with the destroy script: ./destroy.sh --config $config_file"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "======================================================"
    echo "Recipe: $RECIPE_NAME"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "======================================================"
    echo "Resources Created:"
    echo "  • Service Account: $SERVICE_ACCOUNT"
    echo "  • Storage Bucket: gs://$BUCKET_NAME"
    echo "  • Instance Template: $TEMPLATE_NAME"
    echo "  • Batch Job: $JOB_NAME"
    echo "  • Monitoring Dashboard: AI Training Optimization Dashboard"
    echo "  • Alert Policy: AI Training GPU Underutilization Alert"
    echo "======================================================"
    echo "Next Steps:"
    echo "  1. Monitor job progress: gcloud batch jobs describe $JOB_NAME --location=$REGION"
    echo "  2. View logs: gcloud logging read 'resource.type=\"batch_job\" AND resource.labels.job_id=\"$JOB_NAME\"'"
    echo "  3. Access monitoring dashboard in Google Cloud Console"
    echo "  4. Run cleanup: ./destroy.sh --config deployment-config-${RANDOM_SUFFIX}.env"
    echo "======================================================"
}

# Main deployment function
main() {
    log "Starting AI Training Optimization deployment..."
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_service_account
    create_storage_bucket
    create_instance_template
    create_monitoring_dashboard
    create_batch_job_config
    submit_training_job
    configure_monitoring_alerts
    save_deployment_config
    display_summary
    
    success "Deployment completed successfully!"
    log "Total deployment time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        log "Check the logs above for error details"
        log "You may need to run the destroy script to clean up partial deployments"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID    Google Cloud Project ID"
            echo "  --region REGION            Deployment region (default: us-central1)"
            echo "  --zone ZONE                Deployment zone (default: us-central1-a)"
            echo "  --help, -h                 Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Execute main function
main "$@"
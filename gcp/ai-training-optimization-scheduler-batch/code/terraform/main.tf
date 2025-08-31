# Main Terraform configuration for AI Training Optimization with Dynamic Workload Scheduler and Batch
# This configuration creates a complete infrastructure for optimized GPU-based AI training workloads

# Generate random suffix for unique resource naming
resource "random_id" "resource_suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with optional custom suffix or generated random suffix
  suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.resource_suffix.hex
  
  # Common labels applied to all resources for organization and cost tracking
  common_labels = merge({
    terraform     = "true"
    environment   = var.environment
    workload-type = "ai-training"
    scheduler     = "dynamic-workload-scheduler"
    cost-center   = var.cost_center
    team          = var.team
    recipe        = "ai-training-optimization-scheduler-batch"
  }, var.additional_labels)

  # Service account email for batch job execution
  service_account_email = google_service_account.batch_training_sa.email
  
  # Storage bucket name with suffix for uniqueness
  bucket_name = "${var.storage_bucket_name}-${local.suffix}"
  
  # Instance template name with suffix
  instance_template_name = "ai-training-template-${local.suffix}"
}

# Enable required Google Cloud APIs for the training infrastructure
resource "google_project_service" "required_apis" {
  for_each = var.enable_required_apis ? toset(var.required_apis) : toset([])
  
  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for training data, scripts, and model artifacts
resource "google_storage_bucket" "training_data" {
  name     = local.bucket_name
  location = var.storage_location
  project  = var.project_id

  # Enable uniform bucket-level access for simplified IAM management
  uniform_bucket_level_access = true
  
  # Storage class optimized for frequent access during training
  storage_class = "STANDARD"

  # Versioning configuration for model checkpoint protection
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Lifecycle management to optimize storage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Apply common labels for cost tracking and organization
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload sample training script to Cloud Storage
resource "google_storage_bucket_object" "training_script" {
  name   = var.training_script_path
  bucket = google_storage_bucket.training_data.name
  
  # Inline training script content optimized for AI training workflows
  content = <<-EOF
#!/usr/bin/env python3
"""
AI Training Simulation Script for Dynamic Workload Scheduler and Cloud Batch
This script simulates machine learning model training with comprehensive logging and monitoring.
"""

import time
import os
import logging
import json
from datetime import datetime
from google.cloud import monitoring_v3
from google.cloud import storage

def setup_logging():
    """Configure logging for training job visibility."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    return logging.getLogger(__name__)

def log_system_info(logger):
    """Log system information for debugging and optimization."""
    logger.info("=== System Information ===")
    logger.info(f"GPU Device: {os.environ.get('CUDA_VISIBLE_DEVICES', 'None')}")
    logger.info(f"Batch Job ID: {os.environ.get('BATCH_JOB_ID', 'Unknown')}")
    logger.info(f"Task Index: {os.environ.get('BATCH_TASK_INDEX', 'Unknown')}")
    logger.info(f"Instance Zone: {os.environ.get('ZONE', 'Unknown')}")
    logger.info("========================")

def simulate_data_loading(logger, duration_seconds=60):
    """Simulate data loading phase with progress tracking."""
    logger.info("Starting data loading phase...")
    
    # Simulate loading large datasets
    for i in range(10):
        time.sleep(duration_seconds / 10)
        progress = (i + 1) * 10
        logger.info(f"Data loading progress: {progress}% complete")
    
    logger.info("Data loading completed successfully")

def simulate_training_epochs(logger, epochs=10, epoch_duration=120):
    """Simulate training epochs with realistic progress and metrics."""
    logger.info(f"Starting training with {epochs} epochs...")
    
    best_accuracy = 0.0
    
    for epoch in range(epochs):
        logger.info(f"Starting epoch {epoch + 1}/{epochs}")
        
        # Simulate training computation with variable duration
        time.sleep(epoch_duration)
        
        # Generate realistic training metrics
        accuracy = 0.65 + (epoch * 0.025) + (random.uniform(-0.01, 0.01))
        loss = 2.8 - (epoch * 0.15) + (random.uniform(-0.05, 0.05))
        learning_rate = 0.001 * (0.95 ** epoch)
        
        # Track best accuracy for model checkpointing
        if accuracy > best_accuracy:
            best_accuracy = accuracy
            logger.info(f"New best accuracy achieved: {accuracy:.4f}")
        
        # Log comprehensive training metrics
        metrics = {
            "epoch": epoch + 1,
            "accuracy": round(accuracy, 4),
            "loss": round(loss, 4),
            "learning_rate": round(learning_rate, 6),
            "best_accuracy": round(best_accuracy, 4),
            "timestamp": datetime.now().isoformat()
        }
        
        logger.info(f"Epoch {epoch + 1} metrics: {json.dumps(metrics, indent=2)}")
        
        # Simulate checkpoint saving for larger models
        if (epoch + 1) % 3 == 0:
            logger.info(f"Saving checkpoint at epoch {epoch + 1}")
    
    return best_accuracy

def simulate_model_evaluation(logger, duration_seconds=180):
    """Simulate model evaluation and validation."""
    logger.info("Starting model evaluation phase...")
    
    # Simulate evaluation on validation dataset
    time.sleep(duration_seconds)
    
    # Generate evaluation metrics
    val_accuracy = 0.82 + random.uniform(-0.02, 0.02)
    val_loss = 0.45 + random.uniform(-0.05, 0.05)
    f1_score = 0.79 + random.uniform(-0.02, 0.02)
    
    evaluation_results = {
        "validation_accuracy": round(val_accuracy, 4),
        "validation_loss": round(val_loss, 4),
        "f1_score": round(f1_score, 4),
        "evaluation_timestamp": datetime.now().isoformat()
    }
    
    logger.info(f"Evaluation results: {json.dumps(evaluation_results, indent=2)}")
    logger.info("Model evaluation completed successfully")
    
    return evaluation_results

def main():
    """Main training function orchestrating the complete workflow."""
    logger = setup_logging()
    
    try:
        # Log job start and system information
        logger.info("AI Training Job Started")
        log_system_info(logger)
        
        # Simulate complete training pipeline
        start_time = time.time()
        
        # Phase 1: Data loading
        simulate_data_loading(logger, duration_seconds=60)
        
        # Phase 2: Model training
        best_accuracy = simulate_training_epochs(logger, epochs=8, epoch_duration=120)
        
        # Phase 3: Model evaluation
        evaluation_results = simulate_model_evaluation(logger, duration_seconds=180)
        
        # Calculate total training time
        total_time = time.time() - start_time
        
        # Log final results
        final_results = {
            "training_completed": True,
            "total_training_time_seconds": round(total_time, 2),
            "best_training_accuracy": best_accuracy,
            "final_validation_accuracy": evaluation_results["validation_accuracy"],
            "job_completion_timestamp": datetime.now().isoformat()
        }
        
        logger.info("=== Training Job Summary ===")
        logger.info(json.dumps(final_results, indent=2))
        logger.info("===========================")
        logger.info("AI Training Job Completed Successfully!")
        
        return True
        
    except Exception as e:
        logger.error(f"Training job failed with error: {str(e)}")
        return False

if __name__ == "__main__":
    import random
    success = main()
    exit(0 if success else 1)
EOF

  # Apply common labels for organization
  metadata = local.common_labels
}

# Create service account for batch training jobs with minimal required permissions
resource "google_service_account" "batch_training_sa" {
  account_id   = "${var.service_account_name}-${local.suffix}"
  display_name = var.service_account_display_name
  description  = "Service account for AI training batch jobs with Dynamic Workload Scheduler"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant storage object viewer permissions for accessing training data
resource "google_project_iam_member" "batch_sa_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.batch_training_sa.email}"
}

# Grant monitoring metric writer permissions for custom metrics
resource "google_project_iam_member" "batch_sa_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.batch_training_sa.email}"
}

# Grant logging write permissions for job logs
resource "google_project_iam_member" "batch_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.batch_training_sa.email}"
}

# Create compute instance template optimized for GPU-based AI training
resource "google_compute_instance_template" "ai_training_template" {
  name         = local.instance_template_name
  description  = "Instance template for AI training with GPU acceleration and Dynamic Workload Scheduler integration"
  project      = var.project_id
  region       = var.region

  # Machine configuration optimized for GPU workloads
  machine_type = var.machine_type

  # GPU accelerator configuration for AI training
  guest_accelerator {
    type  = var.accelerator_type
    count = var.accelerator_count
  }

  # Boot disk configuration with optimized image for deep learning
  disk {
    source_image = "projects/deeplearning-platform-release/global/images/family/pytorch-latest-gpu"
    boot         = true
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = var.boot_disk_type
    auto_delete  = true
  }

  # Network configuration
  network_interface {
    network    = var.network_name != "" ? var.network_name : "default"
    subnetwork = var.subnet_name != "" ? var.subnet_name : null
    
    # Assign external IP for internet access (required for package downloads)
    access_config {}
  }

  # Service account configuration for secure access to cloud resources
  service_account {
    email  = google_service_account.batch_training_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Metadata for GPU driver installation and job configuration
  metadata = {
    install-nvidia-driver = "True"
    enable-oslogin       = "TRUE"
    startup-script       = "#!/bin/bash\necho 'Instance ready for AI training workloads'"
  }

  # Security configuration following Google Cloud best practices
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = var.enable_vtpm
    enable_integrity_monitoring = var.enable_integrity_monitoring
  }

  # Scheduling configuration for GPU availability optimization
  scheduling {
    # Allow preemption for cost optimization (DWS will handle rescheduling)
    preemptible         = false
    automatic_restart   = true
    on_host_maintenance = "TERMINATE"  # Required for GPU instances
  }

  # Network tags for firewall rules and organization
  tags = ["ai-training", "batch-job", "gpu-workload"]

  # Apply common labels for cost tracking
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
  
  # Ensure template recreation when major configuration changes
  lifecycle {
    create_before_destroy = true
  }
}

# Create Cloud Monitoring dashboard for training job visibility and optimization
resource "google_monitoring_dashboard" "ai_training_dashboard" {
  count = var.enable_monitoring_dashboard ? 1 : 0
  
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "AI Training Optimization Dashboard - ${local.suffix}"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "GPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"compute_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields = ["resource.label.instance_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "GPU Utilization (%)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Batch Job Task Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/task/count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields = ["metric.label.state"]
                      }
                    }
                  }
                  plotType = "STACKED_AREA"
                }
              ]
              yAxis = {
                label = "Task Count"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Instance CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"compute_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields = ["resource.label.instance_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "CPU Utilization (%)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"compute_instance\" AND metric.type=\"compute.googleapis.com/instance/memory/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields = ["resource.label.instance_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Memory Utilization (%)"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
    
    labels = local.common_labels
  })

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for GPU utilization monitoring and optimization
resource "google_monitoring_alert_policy" "gpu_underutilization_alert" {
  count = var.enable_monitoring_dashboard ? 1 : 0
  
  project      = var.project_id
  display_name = "AI Training GPU Underutilization Alert - ${local.suffix}"
  
  documentation {
    content = "Alert triggered when GPU utilization falls below ${var.gpu_utilization_threshold * 100}% for training instances, indicating potential optimization opportunities."
  }

  conditions {
    display_name = "GPU Utilization Below ${var.gpu_utilization_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"compute_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\" AND resource.label.instance_name=~\".*ai-training.*\""
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = var.gpu_utilization_threshold
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Notification channels for alert delivery
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      channel = notification_channels.value
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true

  depends_on = [google_project_service.required_apis]
}

# Create sample batch job configuration for AI training with DWS integration
resource "local_file" "batch_job_config" {
  filename = "${path.module}/batch-job-config.json"
  
  content = jsonencode({
    taskGroups = [
      {
        name = "training-task-group"
        taskSpec = {
          runnables = [
            {
              container = {
                imageUri = var.container_image
                commands = [
                  "/bin/bash",
                  "-c",
                  "gsutil cp gs://${google_storage_bucket.training_data.name}/${var.training_script_path} . && python ${basename(var.training_script_path)}"
                ]
              }
            }
          ]
          computeResource = {
            cpuMilli  = var.cpu_milli
            memoryMib = var.memory_mib
          }
          maxRetryCount   = var.max_retry_count
          maxRunDuration  = "${var.max_training_duration}s"
        }
        taskCount   = var.task_count
        parallelism = var.parallelism
      }
    ]
    
    allocationPolicy = {
      instances = [
        {
          instanceTemplate = google_compute_instance_template.ai_training_template.self_link
          policy = {
            machineType = var.machine_type
            accelerators = [
              {
                type  = var.accelerator_type
                count = var.accelerator_count
              }
            ]
            # Use STANDARD provisioning model with DWS for intelligent scheduling
            provisioningModel = "STANDARD"
          }
        }
      ]
    }
    
    # Labels for cost tracking and resource organization
    labels = merge(local.common_labels, {
      scheduler = "dynamic-workload-scheduler"
      job-type  = "ai-training"
    })
    
    # Logging configuration for comprehensive job monitoring
    logsPolicy = {
      destination = "CLOUD_LOGGING"
    }
  })
}

# Create deployment script for easy batch job submission
resource "local_file" "deploy_script" {
  filename = "${path.module}/deploy-training-job.sh"
  
  content = <<-EOF
#!/bin/bash
# Deployment script for AI Training Job with Dynamic Workload Scheduler

set -e

# Configuration variables
PROJECT_ID="${var.project_id}"
REGION="${var.region}"
BUCKET_NAME="${google_storage_bucket.training_data.name}"
JOB_NAME_PREFIX="ai-training-job"

# Generate unique job name with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JOB_NAME="$${JOB_NAME_PREFIX}-$${TIMESTAMP}"

echo "🚀 Starting AI Training Job Deployment"
echo "Project: $${PROJECT_ID}"
echo "Region: $${REGION}"
echo "Job Name: $${JOB_NAME}"
echo "Storage Bucket: $${BUCKET_NAME}"

# Verify prerequisites
echo "📋 Verifying prerequisites..."
gcloud auth list --filter="status:ACTIVE" --format="value(account)" > /dev/null || {
    echo "❌ Error: No active gcloud authentication found"
    echo "Please run: gcloud auth login"
    exit 1
}

gcloud config get-value project > /dev/null || {
    echo "❌ Error: No default project configured"
    echo "Please run: gcloud config set project $${PROJECT_ID}"
    exit 1
}

# Submit batch job with Dynamic Workload Scheduler
echo "📤 Submitting batch job to Dynamic Workload Scheduler..."
gcloud batch jobs submit "$${JOB_NAME}" \
    --location="$${REGION}" \
    --config=batch-job-config.json

# Monitor job status
echo "📊 Job submitted successfully! Monitoring status..."
echo "Job Name: $${JOB_NAME}"
echo "Region: $${REGION}"

# Provide monitoring commands
echo ""
echo "📈 Use these commands to monitor your training job:"
echo "gcloud batch jobs describe $${JOB_NAME} --location=$${REGION}"
echo "gcloud logging read \"resource.type=batch_job AND resource.labels.job_id=$${JOB_NAME}\" --limit=20"
echo ""
echo "🎯 View training progress in Cloud Console:"
echo "https://console.cloud.google.com/batch/jobs/$${JOB_NAME}?project=$${PROJECT_ID}"
echo ""
echo "✅ AI Training Job deployment completed!"
EOF

  file_permission = "0755"
}

# Create cleanup script for resource management
resource "local_file" "cleanup_script" {
  filename = "${path.module}/cleanup-resources.sh"
  
  content = <<-EOF
#!/bin/bash
# Cleanup script for AI Training resources

set -e

PROJECT_ID="${var.project_id}"
REGION="${var.region}"
BUCKET_NAME="${google_storage_bucket.training_data.name}"

echo "🧹 Starting resource cleanup for AI Training infrastructure"

# List and optionally delete batch jobs
echo "📋 Checking for active batch jobs..."
ACTIVE_JOBS=$(gcloud batch jobs list --location="$${REGION}" --filter="labels.recipe=ai-training-optimization-scheduler-batch" --format="value(name)" 2>/dev/null || echo "")

if [ ! -z "$${ACTIVE_JOBS}" ]; then
    echo "Found active batch jobs:"
    echo "$${ACTIVE_JOBS}"
    read -p "Do you want to delete these batch jobs? (y/N): " -n 1 -r
    echo
    if [[ $$REPLY =~ ^[Yy]$$ ]]; then
        echo "$${ACTIVE_JOBS}" | while read job; do
            if [ ! -z "$$job" ]; then
                echo "Deleting batch job: $$job"
                gcloud batch jobs delete "$$job" --location="$${REGION}" --quiet
            fi
        done
    fi
fi

# Storage cleanup
echo "💾 Storage bucket cleanup..."
read -p "Do you want to delete the training data bucket ($${BUCKET_NAME})? This will remove all training data and scripts. (y/N): " -n 1 -r
echo
if [[ $$REPLY =~ ^[Yy]$$ ]]; then
    echo "Deleting storage bucket: $${BUCKET_NAME}"
    gsutil -m rm -r gs://$${BUCKET_NAME} 2>/dev/null || echo "Bucket already deleted or empty"
fi

# Clean up local files
echo "🗂️ Cleaning up local configuration files..."
rm -f batch-job-config.json
rm -f training-logs.txt

echo "✅ Resource cleanup completed!"
echo "Note: Terraform-managed resources (instance templates, service accounts, monitoring) remain active."
echo "Run 'terraform destroy' to remove all infrastructure resources."
EOF

  file_permission = "0755"
}
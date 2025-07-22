# Batch Processing with Cloud Run Jobs and Cloud Scheduler
# This Terraform configuration creates a complete serverless batch processing system
# using Google Cloud Run Jobs, Cloud Scheduler, and supporting services.

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "resource_suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Resource naming with suffix
  resource_suffix = random_id.resource_suffix.hex
  
  # Service account configuration
  service_account_id = "${var.service_account_id}-${local.resource_suffix}"
  
  # Artifact Registry repository name
  registry_name = "${var.registry_repository_id}-${local.resource_suffix}"
  
  # Storage bucket name
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_id}-batch-data-${local.resource_suffix}"
  
  # Cloud Run job name
  job_name = "${var.job_name}-${local.resource_suffix}"
  
  # Cloud Scheduler job name
  scheduler_name = "${var.scheduler_job_name}-${local.resource_suffix}"
  
  # Container image URL
  container_image_url = var.container_image != "" ? var.container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/batch-processor:latest"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment    = var.environment
    resource-type  = "batch-processing"
    created-by     = "terraform"
    suffix         = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "batch_processing_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Wait for APIs to be fully enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.batch_processing_apis]
  
  create_duration = "60s"
}

# Create IAM Service Account for batch processing
resource "google_service_account" "batch_processor" {
  depends_on = [time_sleep.wait_for_apis]
  
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = var.service_account_description
  project      = var.project_id
}

# IAM Role Bindings for Service Account
# Storage Object Admin for read/write access to Cloud Storage
resource "google_project_iam_member" "storage_object_admin" {
  depends_on = [google_service_account.batch_processor]
  
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.batch_processor.email}"
}

# Cloud Logging Writer for log output
resource "google_project_iam_member" "logging_log_writer" {
  depends_on = [google_service_account.batch_processor]
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.batch_processor.email}"
}

# Cloud Monitoring Metric Writer for custom metrics
resource "google_project_iam_member" "monitoring_metric_writer" {
  depends_on = [google_service_account.batch_processor]
  
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.batch_processor.email}"
}

# Cloud Run Invoker for job execution
resource "google_project_iam_member" "run_invoker" {
  depends_on = [google_service_account.batch_processor]
  
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.batch_processor.email}"
}

# Create Artifact Registry Repository for container images
resource "google_artifact_registry_repository" "batch_registry" {
  depends_on = [time_sleep.wait_for_apis]
  
  location      = var.region
  repository_id = local.registry_name
  description   = "Container registry for batch processing applications"
  format        = var.registry_format
  project       = var.project_id
  
  labels = local.common_labels
  
  # Enable vulnerability scanning
  docker_config {
    immutable_tags = false
  }
}

# Grant service account access to pull images from Artifact Registry
resource "google_artifact_registry_repository_iam_member" "batch_registry_reader" {
  depends_on = [google_artifact_registry_repository.batch_registry]
  
  project    = var.project_id
  location   = google_artifact_registry_repository.batch_registry.location
  repository = google_artifact_registry_repository.batch_registry.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.batch_processor.email}"
}

# Create Cloud Storage Bucket for batch processing data
resource "google_storage_bucket" "batch_data" {
  depends_on = [time_sleep.wait_for_apis]
  
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
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
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Enable logging for audit purposes
  logging {
    log_bucket = google_storage_bucket.batch_data.name
  }
  
  labels = local.common_labels
}

# Create input and output directories in the bucket
resource "google_storage_bucket_object" "input_directory" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "input/"
  source = "/dev/null"
}

resource "google_storage_bucket_object" "output_directory" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "output/"
  source = "/dev/null"
}

# Create Cloud Run Job for batch processing
resource "google_cloud_run_v2_job" "batch_processor" {
  depends_on = [
    time_sleep.wait_for_apis,
    google_service_account.batch_processor,
    google_artifact_registry_repository.batch_registry,
    google_storage_bucket.batch_data
  ]
  
  name     = local.job_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  template {
    # Job execution configuration
    task_count  = var.job_task_count
    parallelism = var.job_parallelism
    
    # Task timeout and retry configuration
    task_timeout = "${var.job_task_timeout}s"
    
    template {
      # Service account for job execution
      service_account = google_service_account.batch_processor.email
      
      # Retry policy
      max_retries = var.job_max_retries
      
      # Container configuration
      containers {
        image = local.container_image_url
        
        # Resource allocation
        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }
        
        # Environment variables
        dynamic "env" {
          for_each = merge(
            var.batch_environment_variables,
            {
              BUCKET_NAME = google_storage_bucket.batch_data.name
              PROJECT_ID  = var.project_id
              REGION      = var.region
            }
          )
          
          content {
            name  = env.key
            value = env.value
          }
        }
      }
      
      # Network configuration (uses default VPC)
      vpc_access {
        network_interfaces {
          network = var.network_name
          subnetwork = var.subnet_name
        }
      }
    }
  }
  
  # Prevent deletion during development
  lifecycle {
    prevent_destroy = false
  }
}

# Create Cloud Scheduler Job for automated execution
resource "google_cloud_scheduler_job" "batch_schedule" {
  depends_on = [
    time_sleep.wait_for_apis,
    google_cloud_run_v2_job.batch_processor
  ]
  
  name        = local.scheduler_name
  description = var.scheduler_description
  schedule    = var.scheduler_cron_schedule
  time_zone   = var.scheduler_timezone
  region      = var.region
  project     = var.project_id
  
  # Retry configuration
  retry_config {
    retry_count = 3
    max_retry_duration = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "300s"
    max_doublings = 5
  }
  
  # HTTP target configuration for Cloud Run Job
  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.batch_processor.name}:run"
    
    # OAuth authentication
    oauth_token {
      service_account_email = google_service_account.batch_processor.email
    }
    
    # Request headers
    headers = {
      "Content-Type" = "application/json"
    }
    
    # Request body (empty for job execution)
    body = base64encode("{}")
  }
}

# Create log-based metric for monitoring job executions
resource "google_logging_metric" "batch_job_executions" {
  count = var.enable_monitoring ? 1 : 0
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_cloud_run_v2_job.batch_processor
  ]
  
  name    = "batch_job_executions_${local.resource_suffix}"
  project = var.project_id
  
  filter = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.batch_processor.name}\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    unit        = "1"
    display_name = "Batch Job Executions"
    description = "Count of batch job executions"
  }
  
  label_extractors = {
    "job_name" = "EXTRACT(resource.labels.job_name)"
    "severity" = "EXTRACT(severity)"
  }
}

# Create alerting policy for failed job executions
resource "google_monitoring_alert_policy" "batch_job_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_cloud_run_v2_job.batch_processor
  ]
  
  display_name = "Batch Job Failure Alert - ${local.resource_suffix}"
  project      = var.project_id
  
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud Run Job Failed"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.batch_processor.name}\" AND severity=\"ERROR\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  # Alert strategy
  alert_strategy {
    auto_close = "1800s"
    
    notification_rate_limit {
      period = "300s"
    }
  }
  
  # Documentation for the alert
  documentation {
    content = "Batch processing job has failed. Check the Cloud Run job logs for detailed error information."
    mime_type = "text/markdown"
  }
}

# Create log sink for long-term storage (optional)
resource "google_logging_project_sink" "batch_job_logs" {
  count = var.enable_monitoring ? 1 : 0
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_storage_bucket.batch_data
  ]
  
  name        = "batch-job-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.batch_data.name}/logs"
  project     = var.project_id
  
  filter = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.batch_processor.name}\""
  
  # Use unique writer identity
  unique_writer_identity = true
}

# Grant log sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  depends_on = [google_logging_project_sink.batch_job_logs]
  
  bucket = google_storage_bucket.batch_data.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.batch_job_logs[0].writer_identity
}

# Create a Cloud Build trigger for automated container builds (optional)
resource "google_cloudbuild_trigger" "batch_processor_build" {
  count = var.container_image == "" ? 1 : 0
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_artifact_registry_repository.batch_registry
  ]
  
  name        = "batch-processor-build-${local.resource_suffix}"
  description = "Build trigger for batch processing container"
  project     = var.project_id
  
  # Manual trigger (can be connected to source repository)
  source_to_build {
    uri       = "https://github.com/example/batch-processor"
    ref       = "refs/heads/main"
    repo_type = "GITHUB"
  }
  
  # Build configuration
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/batch-processor:$SHORT_SHA",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/batch-processor:latest",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/batch-processor:$SHORT_SHA"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/batch-processor:latest"
      ]
    }
    
    options {
      machine_type = var.build_machine_type
    }
    
    timeout = "${var.build_timeout}s"
  }
  
  # Substitutions for build variables
  substitutions = {
    _REGION       = var.region
    _REGISTRY_NAME = local.registry_name
  }
}

# Create a sample batch processing application files (for reference)
resource "google_storage_bucket_object" "sample_batch_app" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "application/batch_processor.py"
  
  content = <<-EOF
import os
import sys
import json
import time
from google.cloud import storage
from google.cloud import logging
from datetime import datetime

def setup_logging():
    """Configure Cloud Logging for batch job monitoring"""
    client = logging.Client()
    client.setup_logging()
    return client

def process_data_files(bucket_name, input_prefix="input/", output_prefix="output/"):
    """Process data files from Cloud Storage"""
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    processed_files = []
    
    # List and process input files
    blobs = bucket.list_blobs(prefix=input_prefix)
    
    for blob in blobs:
        if blob.name.endswith('.txt') or blob.name.endswith('.csv'):
            print(f"Processing file: {blob.name}")
            
            # Download file content
            content = blob.download_as_text()
            
            # Simulate data processing (add timestamp)
            processed_content = f"Processed at {datetime.now()}\n{content}"
            
            # Upload processed file to output prefix
            output_name = blob.name.replace(input_prefix, output_prefix)
            output_blob = bucket.blob(output_name)
            output_blob.upload_from_string(processed_content)
            
            processed_files.append(output_name)
            print(f"✅ Processed and saved: {output_name}")
    
    return processed_files

def main():
    """Main batch processing function"""
    print("Starting batch processing job...")
    
    # Setup logging
    setup_logging()
    
    # Get configuration from environment variables
    bucket_name = os.environ.get('BUCKET_NAME')
    batch_size = int(os.environ.get('BATCH_SIZE', '10'))
    
    if not bucket_name:
        print("ERROR: BUCKET_NAME environment variable not set")
        sys.exit(1)
    
    try:
        # Process data files
        processed_files = process_data_files(bucket_name)
        
        # Create processing summary
        summary = {
            'timestamp': datetime.now().isoformat(),
            'processed_files_count': len(processed_files),
            'processed_files': processed_files,
            'status': 'success'
        }
        
        print(f"Batch processing completed successfully: {json.dumps(summary, indent=2)}")
        
    except Exception as e:
        print(f"ERROR in batch processing: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
}

# Create sample Dockerfile for reference
resource "google_storage_bucket_object" "sample_dockerfile" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "application/Dockerfile"
  
  content = <<-EOF
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY src/ ./src/

# Set environment variables
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Run the batch processing application
CMD ["python", "src/batch_processor.py"]
EOF
}

# Create sample requirements.txt for reference
resource "google_storage_bucket_object" "sample_requirements" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "application/requirements.txt"
  
  content = <<-EOF
google-cloud-storage==2.18.0
google-cloud-logging==3.11.0
google-cloud-core==2.4.1
EOF
}

# Create sample Cloud Build configuration for reference
resource "google_storage_bucket_object" "sample_cloudbuild" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "application/cloudbuild.yaml"
  
  content = <<-EOF
steps:
  # Build the container image
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'build',
      '-t', '$${_REGION}-docker.pkg.dev/$${PROJECT_ID}/$${_REGISTRY_NAME}/batch-processor:$${SHORT_SHA}',
      '-t', '$${_REGION}-docker.pkg.dev/$${PROJECT_ID}/$${_REGISTRY_NAME}/batch-processor:latest',
      '.'
    ]
  
  # Push the container image to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'push',
      '$${_REGION}-docker.pkg.dev/$${PROJECT_ID}/$${_REGISTRY_NAME}/batch-processor:$${SHORT_SHA}'
    ]
  
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'push',
      '$${_REGION}-docker.pkg.dev/$${PROJECT_ID}/$${_REGISTRY_NAME}/batch-processor:latest'
    ]

# Specify build timeout and machine type for complex builds
timeout: '600s'
options:
  machineType: 'E2_STANDARD_2'

substitutions:
  _REGION: ${var.region}
  _REGISTRY_NAME: ${local.registry_name}
EOF
}

# Create sample input data files for testing
resource "google_storage_bucket_object" "sample_input_data1" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "input/sample1.txt"
  
  content = <<-EOF
Sample data for batch processing - File 1
Transaction,Amount,Date
TXN001,150.00,2025-01-01
TXN002,75.50,2025-01-02
EOF
}

resource "google_storage_bucket_object" "sample_input_data2" {
  depends_on = [google_storage_bucket.batch_data]
  
  bucket = google_storage_bucket.batch_data.name
  name   = "input/sample2.csv"
  
  content = <<-EOF
Sample data for batch processing - File 2
Customer,Revenue,Quarter
CUST001,25000,Q1
CUST002,18500,Q1
EOF
}
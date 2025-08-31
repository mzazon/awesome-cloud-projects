# Main Terraform configuration for Oracle Database@Google Cloud Enterprise Analytics with Vertex AI
# This file creates the complete infrastructure for enterprise database analytics solution

# ==============================================================================
# LOCAL VALUES AND RANDOM RESOURCES
# ==============================================================================

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  oracle_instance_name = "${var.resource_prefix}-${local.resource_suffix}"
  autonomous_db_name = "${var.resource_prefix}-adb-${local.resource_suffix}"
  vertex_endpoint_name = "${var.resource_prefix}-ml-endpoint-${local.resource_suffix}"
  bigquery_dataset_name = "${var.bigquery_dataset_id}_${local.resource_suffix}"
  cloud_function_name = "${var.resource_prefix}-pipeline-${local.resource_suffix}"
  workbench_instance_name = "${var.resource_prefix}-workbench-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.additional_labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
    created-by  = "terraform"
    solution    = "oracle-vertex-ai-analytics"
  })
  
  # API services required for the solution
  required_apis = [
    "oracledatabase.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "notebooks.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com"
  ]
}

# ==============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ==============================================================================

# Enable all required Google Cloud APIs for the solution
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Disable dependent services when this resource is destroyed
  disable_dependent_services = false
  # Don't disable the service when this resource is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled before creating dependent resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

# ==============================================================================
# STORAGE RESOURCES
# ==============================================================================

# Cloud Storage bucket for Vertex AI artifacts and staging
resource "google_storage_bucket" "vertex_ai_staging" {
  name     = "vertex-ai-staging-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  # Prevent accidental deletion
  force_destroy = false
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Versioning configuration
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for multipart uploads cleanup
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "cloud_functions_source" {
  name     = "cloud-functions-source-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  force_destroy = true  # Allow destruction for source code bucket
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# ==============================================================================
# ORACLE DATABASE@GOOGLE CLOUD INFRASTRUCTURE
# ==============================================================================

# Oracle Cloud Exadata Infrastructure - the foundation for Oracle Database@Google Cloud
resource "google_oracle_database_cloud_exadata_infrastructure" "main" {
  provider = google-beta
  
  cloud_exadata_infrastructure_id = local.oracle_instance_name
  location = var.region
  project  = var.project_id
  
  display_name = "Enterprise Analytics Oracle Infrastructure"
  
  properties {
    shape                = var.oracle_exadata_shape
    storage_count        = var.oracle_storage_count
    compute_count        = var.oracle_compute_count
    customer_contacts {
      email = "admin@${var.project_id}.iam.gserviceaccount.com"
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "oracle-infrastructure"
    type    = "exadata"
  })
  
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Oracle Autonomous Database instance for analytics workloads
resource "google_oracle_database_autonomous_database" "analytics_db" {
  provider = google-beta
  
  autonomous_database_id = local.autonomous_db_name
  location = var.region
  project  = var.project_id
  
  database_edition = var.autonomous_database_edition
  display_name     = "Enterprise Analytics Database"
  
  properties {
    admin_password = var.autonomous_database_admin_password
    compute_count  = var.autonomous_database_compute_count
    storage_size_tbs = var.autonomous_database_storage_size_tbs
    workload_type  = var.autonomous_database_workload_type
    
    # Enable features for analytics and ML integration
    is_auto_scaling_enabled = var.enable_auto_scaling
    is_mtls_connection_required = true
    
    # Configure database options for analytics workloads
    license_model = "LICENSE_INCLUDED"
    
    # Backup configuration
    backup_retention_period_in_days = var.backup_retention_days
  }
  
  labels = merge(local.common_labels, {
    purpose = "analytics-database"
    type    = "autonomous-database"
    ml-ready = "true"
  })
  
  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
  
  depends_on = [
    google_oracle_database_cloud_exadata_infrastructure.main,
    time_sleep.wait_for_apis
  ]
}

# ==============================================================================
# VERTEX AI RESOURCES
# ==============================================================================

# Vertex AI dataset for Oracle analytics
resource "google_vertex_ai_dataset" "oracle_analytics_dataset" {
  display_name = "Oracle Enterprise Analytics Dataset"
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region = var.vertex_ai_region
  project = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "vertex-ai-dataset"
    data-source = "oracle"
  })
  
  depends_on = [time_sleep.wait_for_apis]
}

# Vertex AI Workbench instance for ML development
resource "google_notebooks_instance" "oracle_ml_workbench" {
  name     = local.workbench_instance_name
  location = var.zone
  project  = var.project_id
  
  machine_type = var.vertex_notebook_machine_type
  
  # Boot disk configuration
  boot_disk_type = var.vertex_notebook_disk_type
  boot_disk_size_gb = var.vertex_notebook_boot_disk_size_gb
  
  # Instance configuration for ML workloads
  no_public_ip = false  # Set to true for production environments with Private Google Access
  no_proxy_access = false
  
  # Service account for Vertex AI access
  service_account = google_service_account.vertex_ai_service_account.email
  
  # Install ML frameworks
  install_gpu_driver = false  # Set to true if using GPU instances
  
  # Instance metadata for ML environment setup
  metadata = {
    framework = "TensorFlow/PyTorch"
    proxy-mode = "service_account"
    enable-oslogin = "true"
  }
  
  labels = merge(local.common_labels, {
    purpose = "ml-development"
    type    = "workbench"
  })
  
  depends_on = [
    google_service_account.vertex_ai_service_account,
    time_sleep.wait_for_apis
  ]
}

# Vertex AI model endpoint for serving ML models
resource "google_vertex_ai_endpoint" "oracle_ml_endpoint" {
  name     = var.vertex_model_display_name
  display_name = var.vertex_model_display_name
  location = var.vertex_ai_region
  project  = var.project_id
  
  description = "Endpoint for Oracle database analytics ML models"
  
  labels = merge(local.common_labels, {
    purpose = "model-serving"
    type    = "endpoint"
  })
  
  depends_on = [time_sleep.wait_for_apis]
}

# ==============================================================================
# BIGQUERY RESOURCES
# ==============================================================================

# BigQuery dataset for Oracle analytics
resource "google_bigquery_dataset" "oracle_analytics" {
  dataset_id = local.bigquery_dataset_name
  location   = var.bigquery_location
  project    = var.project_id
  
  friendly_name = "Oracle Enterprise Analytics"
  description   = var.bigquery_dataset_description
  
  # Access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.analytics_service_account.email
  }
  
  access {
    role          = "READER"
    user_by_email = google_service_account.vertex_ai_service_account.email
  }
  
  # Default table expiration (optional cost optimization)
  default_table_expiration_ms = var.enable_cost_optimization ? 2592000000 : null # 30 days
  
  # Delete protection
  delete_contents_on_destroy = !var.bigquery_table_deletion_protection
  
  labels = merge(local.common_labels, {
    purpose = "analytics-data-warehouse"
    type    = "bigquery-dataset"
  })
  
  depends_on = [
    google_service_account.analytics_service_account,
    google_service_account.vertex_ai_service_account,
    time_sleep.wait_for_apis
  ]
}

# BigQuery table for sales analytics
resource "google_bigquery_table" "sales_analytics" {
  dataset_id = google_bigquery_dataset.oracle_analytics.dataset_id
  table_id   = "sales_analytics"
  project    = var.project_id
  
  description = "Sales analytics data from Oracle database with ML predictions"
  
  # Table schema
  schema = jsonencode([
    {
      name = "sales_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for sales record"
    },
    {
      name = "product_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Product identifier"
    },
    {
      name = "revenue"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Revenue amount"
    },
    {
      name = "quarter"
      type = "STRING"
      mode = "REQUIRED"
      description = "Sales quarter"
    },
    {
      name = "prediction_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "ML model prediction score"
    },
    {
      name = "created_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Record creation timestamp"
    }
  ])
  
  # Time partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "created_timestamp"
  }
  
  # Clustering for query optimization
  clustering = ["quarter", "product_id"]
  
  labels = merge(local.common_labels, {
    purpose = "sales-analytics"
    type    = "bigquery-table"
  })
  
  deletion_protection = var.bigquery_table_deletion_protection
}

# BigQuery external connection to Oracle Database@Google Cloud
resource "google_bigquery_connection" "oracle_connection" {
  connection_id = "oracle-connection-${local.resource_suffix}"
  location      = var.bigquery_location
  project       = var.project_id
  
  friendly_name = "Oracle Database@Google Cloud Connection"
  description   = "Connection to Oracle Autonomous Database for analytics"
  
  # Note: Oracle connection configuration would need to be completed
  # after the Oracle database is provisioned with actual connection details
  cloud_sql {
    instance_id = "${var.project_id}:${var.region}:placeholder" # Placeholder for Oracle connection
    database    = "analytics"
    type        = "MYSQL" # Placeholder - Oracle type not yet supported
  }
  
  depends_on = [
    google_oracle_database_autonomous_database.analytics_db,
    google_bigquery_dataset.oracle_analytics
  ]
}

# ==============================================================================
# SERVICE ACCOUNTS AND IAM
# ==============================================================================

# Service account for Vertex AI operations
resource "google_service_account" "vertex_ai_service_account" {
  account_id   = "vertex-ai-sa-${local.resource_suffix}"
  display_name = "Vertex AI Service Account"
  description  = "Service account for Vertex AI operations in Oracle analytics pipeline"
  project      = var.project_id
}

# Service account for analytics operations
resource "google_service_account" "analytics_service_account" {
  account_id   = "analytics-sa-${local.resource_suffix}"
  display_name = "Analytics Service Account"
  description  = "Service account for Oracle analytics operations"
  project      = var.project_id
}

# Service account for Cloud Functions
resource "google_service_account" "cloud_function_service_account" {
  account_id   = "cf-pipeline-sa-${local.resource_suffix}"
  display_name = "Cloud Function Pipeline Service Account"
  description  = "Service account for Cloud Function data pipeline operations"
  project      = var.project_id
}

# IAM roles for Vertex AI service account
resource "google_project_iam_member" "vertex_ai_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/storage.objectAdmin",
    "roles/bigquery.dataEditor",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account.email}"
}

# IAM roles for analytics service account
resource "google_project_iam_member" "analytics_roles" {
  for_each = toset([
    "roles/bigquery.admin",
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.analytics_service_account.email}"
}

# IAM roles for Cloud Function service account
resource "google_project_iam_member" "cloud_function_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/bigquery.dataEditor",
    "roles/cloudsql.client",
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_function_service_account.email}"
}

# ==============================================================================
# CLOUD FUNCTIONS FOR DATA PIPELINE
# ==============================================================================

# Create source code archive for Cloud Function
data "archive_file" "cloud_function_source" {
  type        = "zip"
  output_path = "/tmp/oracle-analytics-pipeline.zip"
  
  source {
    content = <<-EOF
import functions_framework
from google.cloud import aiplatform
from google.cloud import bigquery
import json
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def oracle_analytics_pipeline(request):
    """HTTP Cloud Function for Oracle analytics pipeline."""
    try:
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION')
        
        logger.info(f"Starting Oracle analytics pipeline for project: {project_id}")
        
        # Initialize clients
        aiplatform.init(project=project_id, location=region)
        bq_client = bigquery.Client(project=project_id)
        
        # TODO: Implement Oracle data extraction
        # TODO: Process through Vertex AI models
        # TODO: Load results into BigQuery
        
        # Placeholder implementation
        result = {
            "status": "success",
            "message": "Oracle analytics pipeline executed successfully",
            "project_id": project_id,
            "region": region,
            "timestamp": bq_client.query("SELECT CURRENT_TIMESTAMP()").to_dataframe().iloc[0, 0].isoformat()
        }
        
        logger.info("Pipeline execution completed successfully")
        return json.dumps(result), 200
        
    except Exception as e:
        logger.error(f"Pipeline execution failed: {str(e)}")
        error_result = {
            "status": "error",
            "message": str(e),
            "error_type": type(e).__name__
        }
        return json.dumps(error_result), 500
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
functions-framework==3.*
google-cloud-aiplatform>=1.36.0
google-cloud-bigquery>=3.11.0
pandas>=1.5.0
numpy>=1.21.0
EOF
    filename = "requirements.txt"
  }
}

# Upload Cloud Function source code to Storage
resource "google_storage_bucket_object" "cloud_function_source" {
  name   = "oracle-analytics-pipeline-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.cloud_functions_source.name
  source = data.archive_file.cloud_function_source.output_path
  
  depends_on = [data.archive_file.cloud_function_source]
}

# Cloud Function for data pipeline orchestration
resource "google_cloudfunctions2_function" "oracle_analytics_pipeline" {
  name     = local.cloud_function_name
  location = var.region
  project  = var.project_id
  
  description = "Oracle analytics data pipeline orchestration function"
  
  build_config {
    runtime     = "python311"
    entry_point = "oracle_analytics_pipeline"
    
    source {
      storage_source {
        bucket = google_storage_bucket.cloud_functions_source.name
        object = google_storage_bucket_object.cloud_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.cloud_function_memory_mb}Mi"
    timeout_seconds    = var.cloud_function_timeout_seconds
    
    service_account_email = google_service_account.cloud_function_service_account.email
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      VERTEX_AI_REGION = var.vertex_ai_region
      BIGQUERY_DATASET = google_bigquery_dataset.oracle_analytics.dataset_id
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "data-pipeline"
    type    = "cloud-function"
  })
  
  depends_on = [
    google_storage_bucket_object.cloud_function_source,
    google_service_account.cloud_function_service_account,
    google_project_iam_member.cloud_function_roles
  ]
}

# Cloud Function IAM for public access (adjust for production security requirements)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.oracle_analytics_pipeline.location
  cloud_function = google_cloudfunctions2_function.oracle_analytics_pipeline.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.cloud_function_service_account.email}"
}

# ==============================================================================
# CLOUD SCHEDULER FOR AUTOMATED PIPELINE EXECUTION
# ==============================================================================

# Cloud Scheduler job for automated pipeline execution
resource "google_cloud_scheduler_job" "oracle_analytics_schedule" {
  name     = "oracle-analytics-schedule-${local.resource_suffix}"
  region   = var.region
  project  = var.project_id
  
  description  = "Scheduled execution of Oracle analytics pipeline"
  schedule     = var.cloud_scheduler_schedule
  time_zone    = var.cloud_scheduler_timezone
  
  attempt_deadline = "600s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.oracle_analytics_pipeline.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.cloud_function_service_account.email
    }
  }
  
  depends_on = [
    google_cloudfunctions2_function.oracle_analytics_pipeline,
    google_cloudfunctions2_function_iam_member.invoker
  ]
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

# Monitoring alert policy for Oracle database CPU utilization
resource "google_monitoring_alert_policy" "oracle_cpu_alert" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Oracle Database Performance Alert"
  project      = var.project_id
  
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Oracle CPU Utilization High"
    
    condition_threshold {
      filter          = "resource.type=\"oracle_database\" AND metric.type=\"oracle.googleapis.com/database/cpu_utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.oracle_cpu_alert_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.monitoring_notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "Oracle database CPU utilization has exceeded ${var.oracle_cpu_alert_threshold}% threshold"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Monitoring alert policy for Vertex AI model performance
resource "google_monitoring_alert_policy" "vertex_ai_latency_alert" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Vertex AI Model Performance Alert"
  project      = var.project_id
  
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Model Prediction Latency High"
    
    condition_threshold {
      filter          = "resource.type=\"ai_platform_model_version\" AND metric.type=\"ml.googleapis.com/prediction/response_time\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.vertex_ai_latency_alert_threshold_ms
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.monitoring_notification_channels
  
  alert_strategy {
    auto_close = "3600s"
  }
  
  documentation {
    content = "Vertex AI model response time has exceeded ${var.vertex_ai_latency_alert_threshold_ms}ms threshold"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}
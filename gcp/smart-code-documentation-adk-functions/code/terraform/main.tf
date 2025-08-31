# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  
  # Bucket names with project and suffix
  input_bucket_name  = "${var.project_id}-code-input-${local.resource_suffix}"
  output_bucket_name = "${var.project_id}-docs-output-${local.resource_suffix}"
  temp_bucket_name   = "${var.project_id}-processing-${local.resource_suffix}"
  
  # Function source bucket for deployment artifacts
  function_bucket_name = "${var.project_id}-function-source-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
    created-by  = "terraform"
  })
  
  # Service account email for Cloud Function
  function_service_account_email = google_service_account.function_sa.email
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",     # Vertex AI for Gemini models
    "cloudfunctions.googleapis.com", # Cloud Functions for serverless execution
    "storage.googleapis.com",        # Cloud Storage for data persistence
    "cloudbuild.googleapis.com",     # Cloud Build for function deployment
    "logging.googleapis.com",        # Cloud Logging for monitoring
    "monitoring.googleapis.com",     # Cloud Monitoring for observability
    "eventarc.googleapis.com",       # Eventarc for event-driven triggers
    "run.googleapis.com",            # Cloud Run (required for 2nd gen functions)
    "artifactregistry.googleapis.com" # Artifact Registry for container images
  ])
  
  service                    = each.value
  project                    = var.project_id
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Cloud Storage bucket for code input (triggers documentation generation)
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.storage_location
  storage_class = var.storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access for improved security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for documentation output
resource "google_storage_bucket" "output_bucket" {
  name          = local.output_bucket_name
  location      = var.storage_location
  storage_class = var.storage_class
  project       = var.project_id
  
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  versioning {
    enabled = var.enable_versioning
  }
  
  # CORS configuration for web access to documentation
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for temporary processing files
resource "google_storage_bucket" "temp_bucket" {
  name          = local.temp_bucket_name
  location      = var.storage_location
  storage_class = "STANDARD"  # Use standard for processing performance
  project       = var.project_id
  
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Aggressive lifecycle management for temporary files
  lifecycle_rule {
    condition {
      age = 7  # Delete temporary files after 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  # Auto-delete incomplete multipart uploads
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 1
    }
    action {
      type = "Delete"
    }
  }
  
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source_bucket" {
  name          = local.function_bucket_name
  location      = var.region
  storage_class = "STANDARD"
  project       = var.project_id
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Function with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = "${var.project_name}-function-sa"
  display_name = "ADK Code Documentation Function Service Account"
  description  = "Service account for ADK-powered code documentation Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for Cloud Function service account - Storage permissions
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  condition {
    title       = "Storage access for documentation buckets"
    description = "Allow access only to documentation-related storage buckets"
    expression = <<-EOT
      resource.name.startsWith("projects/_/buckets/${local.input_bucket_name}") ||
      resource.name.startsWith("projects/_/buckets/${local.output_bucket_name}") ||
      resource.name.startsWith("projects/_/buckets/${local.temp_bucket_name}")
    EOT
  }
}

# IAM binding for Vertex AI access (required for Gemini models)
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Logging
resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Monitoring
resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create source code archive for Cloud Function deployment
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/adk-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id     = var.project_id
      output_bucket  = local.output_bucket_name
      temp_bucket    = local.temp_bucket_name
      gemini_model   = var.gemini_model
      vertex_location = var.vertex_ai_location
      log_level      = var.log_level
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_source/code_analysis_agent.py", {
      project_id      = var.project_id
      vertex_location = var.vertex_ai_location
      gemini_model    = var.gemini_model
    })
    filename = "code_analysis_agent.py"
  }
  
  source {
    content = templatefile("${path.module}/function_source/documentation_agent.py", {
      project_id      = var.project_id
      vertex_location = var.vertex_ai_location
      gemini_model    = var.gemini_model
    })
    filename = "documentation_agent.py"
  }
  
  source {
    content = templatefile("${path.module}/function_source/review_agent.py", {
      project_id      = var.project_id
      vertex_location = var.vertex_ai_location
      gemini_model    = var.gemini_model
    })
    filename = "review_agent.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Trigger redeployment when source changes
  content_md5 = data.archive_file.function_source.output_md5
}

# Cloud Function (2nd generation) for ADK-powered code documentation
resource "google_cloudfunctions2_function" "adk_documentation_function" {
  name        = var.function_name
  location    = var.region
  description = "ADK-powered multi-agent system for intelligent code documentation generation"
  project     = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "process_code_repository"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      GOOGLE_BUILDABLE = "function_source"
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = 0
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    
    # Environment variables for runtime
    environment_variables = {
      GCP_PROJECT      = var.project_id
      OUTPUT_BUCKET    = local.output_bucket_name
      TEMP_BUCKET      = local.temp_bucket_name
      VERTEX_LOCATION  = var.vertex_ai_location
      GEMINI_MODEL     = var.gemini_model
      LOG_LEVEL        = var.log_level
      DEBUG_MODE       = var.enable_debug_mode ? "true" : "false"
    }
    
    # Use custom service account with minimal permissions
    service_account_email = google_service_account.function_sa.email
    
    # Security settings
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  # Event trigger for Cloud Storage bucket events
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.input_bucket.name
    }
    
    # Only trigger on .zip files
    event_filters {
      attribute = "eventType"
      value     = "google.cloud.storage.object.v1.finalized"
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_vertex_ai_user,
    google_project_iam_member.function_logging_writer,
    google_project_iam_member.function_monitoring_writer
  ]
}

# Create sample repository for testing (optional)
resource "google_storage_bucket_object" "sample_repository" {
  count = var.create_sample_repository ? 1 : 0
  
  name   = "sample_project.zip"
  bucket = google_storage_bucket.input_bucket.name
  
  # Sample Python project structure
  source = data.archive_file.sample_project[0].output_path
}

# Sample project archive for testing
data "archive_file" "sample_project" {
  count = var.create_sample_repository ? 1 : 0
  
  type        = "zip"
  output_path = "/tmp/sample_project.zip"
  
  source {
    content = <<-EOT
"""
Main application module demonstrating ADK documentation capabilities.
This module orchestrates various services and handles user interactions.
"""

from typing import Dict, List, Optional
import asyncio
from utils.data_processor import DataProcessor
from utils.config_manager import ConfigManager

class ApplicationService:
    """
    Core application service that manages business logic and coordinates
    between different system components for optimal performance.
    """
    
    def __init__(self, config_path: str):
        self.config = ConfigManager(config_path)
        self.processor = DataProcessor(self.config.get_db_settings())
        self.is_running = False
    
    async def start_service(self) -> bool:
        """
        Initialize and start the application service with proper error handling
        and resource management.
        """
        try:
            await self.processor.initialize_connections()
            self.is_running = True
            return True
        except Exception as e:
            print(f"Failed to start service: {e}")
            return False
    
    def process_user_data(self, user_id: str, data: Dict) -> Optional[Dict]:
        """Process user data through the configured data pipeline."""
        if not self.is_running:
            raise RuntimeError("Service not started")
        
        return self.processor.transform_data(user_id, data)
EOT
    filename = "src/main.py"
  }
  
  source {
    content = <<-EOT
"""
Data processing utilities for handling various data transformation tasks
with support for multiple data formats and validation rules.
"""

from typing import Dict, Any, List
import json
import asyncio

class DataProcessor:
    """Handles data transformation and validation for the application."""
    
    def __init__(self, db_config: Dict[str, Any]):
        self.db_config = db_config
        self.connection_pool = None
    
    async def initialize_connections(self):
        """Set up database connections and connection pooling."""
        await asyncio.sleep(0.1)  # Simulate async database setup
        self.connection_pool = {"status": "connected", "pool_size": 10}
    
    def transform_data(self, user_id: str, raw_data: Dict) -> Dict:
        """
        Transform raw user data according to business rules and validation schema.
        
        Args:
            user_id: Unique identifier for the user
            raw_data: Raw data dictionary to be processed
            
        Returns:
            Transformed and validated data dictionary
        """
        transformed = {
            "user_id": user_id,
            "processed_at": "2025-07-12T00:00:00Z",
            "data": self._validate_and_clean(raw_data),
            "status": "processed"
        }
        return transformed
    
    def _validate_and_clean(self, data: Dict) -> Dict:
        """Internal method for data validation and cleaning."""
        # Remove None values and empty strings
        cleaned = {k: v for k, v in data.items() if v is not None and v != ""}
        return cleaned
EOT
    filename = "src/utils/data_processor.py"
  }
  
  source {
    content = <<-EOT
"""Configuration management utilities for application settings."""

import json
from typing import Dict, Any

class ConfigManager:
    """Manages application configuration with support for multiple environments."""
    
    def __init__(self, config_path: str):
        self.config_path = config_path
        self.config_data = self._load_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from file or return defaults."""
        try:
            with open(self.config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """Return default configuration settings."""
        return {
            "database": {
                "host": "localhost",
                "port": 5432,
                "name": "app_db"
            },
            "api": {
                "timeout": 30,
                "retry_attempts": 3
            }
        }
    
    def get_db_settings(self) -> Dict[str, Any]:
        """Get database configuration settings."""
        return self.config_data.get("database", {})
EOT
    filename = "src/utils/config_manager.py"
  }
  
  source {
    content = "# Smart Code Documentation Sample Project\n\nThis is a sample Python project to demonstrate ADK-powered documentation generation.\n"
    filename = "README.md"
  }
}

# Cloud Monitoring alert for function errors (optional but recommended)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_function_logging ? 1 : 0
  
  display_name = "ADK Documentation Function Error Rate"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Function Error Rate > 5%"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = ["resource.labels.function_name"]
      }
    }
  }
  
  notification_channels = []  # Add notification channels as needed
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Logging sink for function logs (for advanced monitoring)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_function_logging ? 1 : 0
  
  name        = "adk-function-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.temp_bucket.name}"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${var.function_name}"
    severity>=WARNING
  EOT
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant the logging sink service account storage access
resource "google_storage_bucket_iam_member" "logging_sink_writer" {
  count = var.enable_function_logging ? 1 : 0
  
  bucket = google_storage_bucket.temp_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}
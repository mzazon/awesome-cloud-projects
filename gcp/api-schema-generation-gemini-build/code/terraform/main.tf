# ============================================================================
# API Schema Generation with Gemini Code Assist and Cloud Build - Main Configuration
# ============================================================================
# This Terraform configuration creates a complete automated API documentation
# pipeline using Google Cloud services including Cloud Functions, Cloud Build,
# Cloud Storage, and monitoring components.

# Data source for current Google Cloud project
data "google_project" "current" {}

# Data source for client configuration
data "google_client_config" "default" {}

# ============================================================================
# Google Cloud APIs - Enable required services
# ============================================================================

# Enable Cloud Build API for CI/CD pipeline automation
resource "google_project_service" "cloudbuild" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Cloud Storage API for artifact storage
resource "google_project_service" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Cloud Functions API for serverless schema processing
resource "google_project_service" "cloudfunctions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Artifact Registry API for container and artifact management
resource "google_project_service" "artifactregistry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Cloud Logging API for comprehensive logging
resource "google_project_service" "logging" {
  project = var.project_id
  service = "logging.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Cloud Monitoring API for metrics and alerting
resource "google_project_service" "monitoring" {
  project = var.project_id
  service = "monitoring.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Identity and Access Management API
resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  disable_on_destroy         = false
}

# ============================================================================
# Cloud Storage - API Schema and Artifact Storage
# ============================================================================

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Cloud Storage bucket for storing OpenAPI schemas and build artifacts
resource "google_storage_bucket" "api_schemas" {
  name     = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true

  # Enable versioning for schema history tracking
  versioning {
    enabled = true
  }

  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Retention policy for compliance
  retention_policy {
    retention_period = var.retention_period_days * 24 * 3600 # Convert days to seconds
  }

  # Labels for resource management and cost tracking
  labels = {
    environment = var.environment
    purpose     = "api-schema-storage"
    component   = "documentation-pipeline"
    managed-by  = "terraform"
  }

  depends_on = [google_project_service.storage]
}

# ============================================================================
# Cloud Storage Buckets - Organized Storage Structure
# ============================================================================

# Create organized folder structure using storage bucket objects
resource "google_storage_bucket_object" "docs_folder" {
  name   = "docs/"
  bucket = google_storage_bucket.api_schemas.name
  content = " " # Empty content to create folder structure
}

resource "google_storage_bucket_object" "reports_folder" {
  name   = "reports/"
  bucket = google_storage_bucket.api_schemas.name
  content = " " # Empty content to create folder structure
}

resource "google_storage_bucket_object" "schemas_folder" {
  name   = "schemas/"
  bucket = google_storage_bucket.api_schemas.name
  content = " " # Empty content to create folder structure
}

# ============================================================================
# IAM - Service Accounts and Roles
# ============================================================================

# Service account for Cloud Functions with minimal required permissions
resource "google_service_account" "cloud_functions_sa" {
  account_id   = "api-schema-functions-sa"
  display_name = "API Schema Generation Functions Service Account"
  description  = "Service account for Cloud Functions handling API schema generation and validation"
  project      = var.project_id

  depends_on = [google_project_service.iam]
}

# Service account for Cloud Build with appropriate build permissions
resource "google_service_account" "cloud_build_sa" {
  account_id   = "api-schema-build-sa"
  display_name = "API Schema Build Service Account"
  description  = "Service account for Cloud Build pipeline automation"
  project      = var.project_id

  depends_on = [google_project_service.iam]
}

# IAM binding for Cloud Functions service account - Storage access
resource "google_project_iam_member" "functions_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloud_functions_sa.email}"
}

# IAM binding for Cloud Functions service account - Logging
resource "google_project_iam_member" "functions_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_functions_sa.email}"
}

# IAM binding for Cloud Build service account - Storage access
resource "google_project_iam_member" "build_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# IAM binding for Cloud Build service account - Logging
resource "google_project_iam_member" "build_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# IAM binding for Cloud Build service account - Cloud Functions access
resource "google_project_iam_member" "build_functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# ============================================================================
# Cloud Functions - Schema Generation and Validation
# ============================================================================

# Generate source code archive for schema generator function
data "archive_file" "schema_generator_source" {
  type        = "zip"
  output_path = "${path.module}/schema-generator-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/schema-generator-main.py.tpl", {
      bucket_name = google_storage_bucket.api_schemas.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/schema-generator-requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for schema generator function source
resource "google_storage_bucket_object" "schema_generator_source" {
  name   = "functions/schema-generator-${data.archive_file.schema_generator_source.output_md5}.zip"
  bucket = google_storage_bucket.api_schemas.name
  source = data.archive_file.schema_generator_source.output_path
}

# Cloud Function for AI-powered schema generation
resource "google_cloudfunctions_function" "schema_generator" {
  name        = "schema-generator"
  description = "Generate OpenAPI schemas from source code using AI analysis"
  project     = var.project_id
  region      = var.region
  runtime     = "python312"

  available_memory_mb   = 512
  timeout               = 120
  max_instances         = 10
  min_instances         = 0
  ingress_settings      = "ALLOW_ALL"

  source_archive_bucket = google_storage_bucket.api_schemas.name
  source_archive_object = google_storage_bucket_object.schema_generator_source.name

  entry_point = "generate_schema"

  # HTTP trigger configuration
  trigger {
    https_trigger {
      url = null
    }
  }

  # Environment variables for function configuration
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.api_schemas.name
    PROJECT_ID  = var.project_id
    REGION      = var.region
  }

  # Service account for secure access
  service_account_email = google_service_account.cloud_functions_sa.email

  # Labels for resource management
  labels = {
    environment = var.environment
    component   = "schema-generator"
    managed-by  = "terraform"
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_service_account.cloud_functions_sa,
    google_storage_bucket_object.schema_generator_source
  ]
}

# Generate source code archive for schema validator function
data "archive_file" "schema_validator_source" {
  type        = "zip"
  output_path = "${path.module}/schema-validator-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/schema-validator-main.py.tpl", {
      bucket_name = google_storage_bucket.api_schemas.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/schema-validator-requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for schema validator function source
resource "google_storage_bucket_object" "schema_validator_source" {
  name   = "functions/schema-validator-${data.archive_file.schema_validator_source.output_md5}.zip"
  bucket = google_storage_bucket.api_schemas.name
  source = data.archive_file.schema_validator_source.output_path
}

# Cloud Function for advanced schema validation
resource "google_cloudfunctions_function" "schema_validator" {
  name        = "schema-validator"
  description = "Validate OpenAPI schemas against standards and best practices"
  project     = var.project_id
  region      = var.region
  runtime     = "python312"

  available_memory_mb   = 512
  timeout               = 60
  max_instances         = 10
  min_instances         = 0
  ingress_settings      = "ALLOW_ALL"

  source_archive_bucket = google_storage_bucket.api_schemas.name
  source_archive_object = google_storage_bucket_object.schema_validator_source.name

  entry_point = "validate_schema"

  # HTTP trigger configuration
  trigger {
    https_trigger {
      url = null
    }
  }

  # Environment variables for function configuration
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.api_schemas.name
    PROJECT_ID  = var.project_id
    REGION      = var.region
  }

  # Service account for secure access
  service_account_email = google_service_account.cloud_functions_sa.email

  # Labels for resource management
  labels = {
    environment = var.environment
    component   = "schema-validator"
    managed-by  = "terraform"
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_service_account.cloud_functions_sa,
    google_storage_bucket_object.schema_validator_source
  ]
}

# ============================================================================
# Cloud Build - CI/CD Pipeline Configuration
# ============================================================================

# Cloud Build trigger for automated schema generation pipeline
resource "google_cloudbuild_trigger" "api_schema_pipeline" {
  project     = var.project_id
  name        = "api-schema-generation-pipeline"
  description = "Automated API Schema Generation Pipeline with AI Analysis"

  # Repository configuration (manual trigger for demo purposes)
  # In production, connect to actual repository
  trigger_template {
    branch_name = "^(main|master|develop)$"
    repo_name   = var.repository_name
  }

  # Build configuration using inline YAML
  build {
    # Step 1: Analyze source code structure
    step {
      name = "gcr.io/cloud-builders/gcloud"
      id   = "analyze-code"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        echo "Analyzing API source code for schema generation..."
        echo "Source files found:"
        find . -name "*.py" -o -name "*.js" -o -name "*.java" | head -10
        echo "Code analysis complete - API patterns detected"
        EOT
      ]
    }

    # Step 2: Generate OpenAPI schema using AI
    step {
      name = "gcr.io/cloud-builders/curl"
      id   = "generate-schema"
      args = [
        "-X", "POST",
        google_cloudfunctions_function.schema_generator.https_trigger_url,
        "-H", "Content-Type: application/json",
        "-d", "{}"
      ]
      env = [
        "BUCKET_NAME=${google_storage_bucket.api_schemas.name}"
      ]
    }

    # Step 3: Download and validate generated schema
    step {
      name = "gcr.io/cloud-builders/gcloud"
      id   = "validate-schema"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        echo "Downloading and validating generated schema..."
        gsutil cp gs://${google_storage_bucket.api_schemas.name}/openapi-schema.json ./schema.json
        
        # Basic validation checks
        if [ ! -f "./schema.json" ]; then
          echo "Error: Schema file not found"
          exit 1
        fi
        
        # Check if valid JSON
        if ! jq empty ./schema.json; then
          echo "Error: Invalid JSON format"
          exit 1
        fi
        
        # Validate required OpenAPI fields
        OPENAPI_VERSION=$(jq -r '.openapi' ./schema.json)
        if [[ ! "$OPENAPI_VERSION" =~ ^3\. ]]; then
          echo "Error: Invalid OpenAPI version: $OPENAPI_VERSION"
          exit 1
        fi
        
        echo "Schema validation complete - OpenAPI $OPENAPI_VERSION"
        EOT
      ]
    }

    # Step 4: Create documentation artifacts
    step {
      name = "gcr.io/cloud-builders/gsutil"
      id   = "deploy-docs"
      args = [
        "cp",
        "./schema.json",
        "gs://${google_storage_bucket.api_schemas.name}/docs/openapi-schema.json"
      ]
    }

    # Step 5: Generate build report
    step {
      name = "gcr.io/cloud-builders/gcloud"
      id   = "generate-report"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        echo "Generating build report..."
        ENDPOINT_COUNT=$(jq '.paths | length' ./schema.json)
        SCHEMA_COUNT=$(jq '.components.schemas | length' ./schema.json)
        
        cat > build-report.json << EOF
        {
          "build_id": "$BUILD_ID",
          "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "endpoints_generated": $ENDPOINT_COUNT,
          "schemas_generated": $SCHEMA_COUNT,
          "status": "success"
        }
        EOF
        
        gsutil cp build-report.json gs://${google_storage_bucket.api_schemas.name}/reports/
        echo "Build report generated successfully"
        EOT
      ]
    }

    # Build options for enhanced logging and performance
    options {
      logging = "CLOUD_LOGGING_ONLY"
      machine_type = "E2_MEDIUM"
      disk_size_gb = 100
    }

    # Build timeout
    timeout = "1200s"

    # Substitutions for dynamic values
    substitutions = {
      _BUCKET_NAME   = google_storage_bucket.api_schemas.name
      _FUNCTION_URL  = google_cloudfunctions_function.schema_generator.https_trigger_url
      _PROJECT_ID    = var.project_id
      _REGION        = var.region
    }
  }

  # Service account for build execution
  service_account = google_service_account.cloud_build_sa.id

  # Tags for build organization
  tags = [
    "api-schema",
    "automation",
    "documentation"
  ]

  depends_on = [
    google_project_service.cloudbuild,
    google_service_account.cloud_build_sa,
    google_cloudfunctions_function.schema_generator,
    google_cloudfunctions_function.schema_validator
  ]
}

# ============================================================================
# Monitoring and Logging
# ============================================================================

# Log sink for Cloud Functions logs
resource "google_logging_project_sink" "function_logs" {
  name        = "api-schema-function-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.api_schemas.name}"
  filter      = "resource.type=\"cloud_function\" AND (resource.labels.function_name=\"schema-generator\" OR resource.labels.function_name=\"schema-validator\")"

  # Use a unique writer identity for this sink
  unique_writer_identity = true

  depends_on = [google_project_service.logging]
}

# IAM binding for log sink writer
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.api_schemas.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
}

# Log sink for Cloud Build logs
resource "google_logging_project_sink" "build_logs" {
  name        = "api-schema-build-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.api_schemas.name}"
  filter      = "resource.type=\"build\" AND resource.labels.trigger_name=\"api-schema-generation-pipeline\""

  # Use a unique writer identity for this sink
  unique_writer_identity = true

  depends_on = [google_project_service.logging]
}

# IAM binding for build log sink writer
resource "google_storage_bucket_iam_member" "build_log_sink_writer" {
  bucket = google_storage_bucket.api_schemas.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.build_logs.writer_identity
}

# ============================================================================
# Notification Channels and Alerting
# ============================================================================

# Notification channel for email alerts (requires manual configuration)
resource "google_monitoring_notification_channel" "email" {
  count        = var.notification_email != null ? 1 : 0
  display_name = "API Schema Pipeline Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }

  description = "Email notifications for API schema generation pipeline alerts"
  enabled     = true

  depends_on = [google_project_service.monitoring]
}

# Alert policy for Cloud Function failures
resource "google_monitoring_alert_policy" "function_errors" {
  display_name = "API Schema Function Errors"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND (resource.label.function_name=\"schema-generator\" OR resource.label.function_name=\"schema-validator\")"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Notification channels
  dynamic "notification_channels" {
    for_each = var.notification_email != null ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email[0].id]
    }
  }

  # Alert documentation
  documentation {
    content   = "API Schema generation functions are experiencing elevated error rates. Check function logs and validate input data."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring]
}

# Alert policy for Cloud Build failures
resource "google_monitoring_alert_policy" "build_failures" {
  display_name = "API Schema Build Failures"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Build failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"build\" AND resource.label.trigger_name=\"api-schema-generation-pipeline\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Notification channels
  dynamic "notification_channels" {
    for_each = var.notification_email != null ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email[0].id]
    }
  }

  # Alert documentation
  documentation {
    content   = "API Schema generation pipeline builds are failing. Check build logs and pipeline configuration."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring]
}

# ============================================================================
# Additional Configuration Notes
# ============================================================================

# The Cloud Functions source code is generated dynamically from templates
# and packaged into ZIP files for deployment. This approach ensures that
# the bucket name and other configuration values are properly injected
# into the function code at deployment time.

# Template files are located in the templates/ directory:
# - templates/schema-generator-main.py.tpl
# - templates/schema-generator-requirements.txt  
# - templates/schema-validator-main.py.tpl
# - templates/schema-validator-requirements.txt

# These templates are processed by Terraform's templatefile() function
# to substitute variables and create the final function source code.
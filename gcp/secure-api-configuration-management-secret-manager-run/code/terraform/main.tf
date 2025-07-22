# Main Terraform configuration for Secure API Configuration Management
# This configuration deploys a secure API using Cloud Run, Secret Manager, and API Gateway
# with comprehensive security controls and monitoring

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention with random suffix
  resource_suffix = random_id.suffix.hex
  service_name    = "${var.service_name}-${local.resource_suffix}"
  gateway_name    = "${var.api_gateway_name}-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
  
  # Secret configurations with structured data
  secret_configs = {
    database = {
      name = "${local.service_name}-db-config"
      data = jsonencode({
        host     = "db.example.com"
        port     = 5432
        username = "api_user"
        password = "secure_db_password_123"
        database = "api_db"
        ssl_mode = "require"
      })
    }
    api_keys = {
      name = "${local.service_name}-api-keys"
      data = jsonencode({
        external_api_key = "sk-1234567890abcdef"
        jwt_secret       = "jwt_signing_key_xyz789"
        encryption_key   = "aes256_encryption_key_abc123"
        webhook_secret   = "webhook_secret_456"
      })
    }
    application = {
      name = "${local.service_name}-app-config"
      data = jsonencode({
        debug_mode      = false
        rate_limit      = 1000
        cache_ttl       = 3600
        log_level       = "INFO"
        cors_origins    = ["https://example.com"]
        session_timeout = 1800
      })
    }
  }
}

# Data source for current project information
data "google_project" "current" {}

# Data source for Cloud Run service account
data "google_compute_default_service_account" "default" {}

# Enable required APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset([
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "apigateway.googleapis.com",
    "servicecontrol.googleapis.com",
    "servicemanagement.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "5m"
    update = "5m"
  }
}

# Create dedicated service account for Cloud Run with least privilege access
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${local.service_name}-sa"
  display_name = "Cloud Run Service Account for ${local.service_name}"
  description  = "Service account for secure API with minimal required permissions"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Secret Manager secrets for secure configuration storage
resource "google_secret_manager_secret" "api_secrets" {
  for_each = local.secret_configs
  
  project   = var.project_id
  secret_id = each.value.name
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  # Enable rotation if configured
  dynamic "rotation" {
    for_each = var.enable_secret_rotation ? [1] : []
    content {
      next_rotation_time = timeadd(timestamp(), var.secret_rotation_period)
      rotation_period    = var.secret_rotation_period
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Secret versions with actual secret data
resource "google_secret_manager_secret_version" "api_secret_versions" {
  for_each = local.secret_configs
  
  secret      = google_secret_manager_secret.api_secrets[each.key].id
  secret_data = each.value.data
  
  lifecycle {
    ignore_changes = [secret_data]
  }
}

# IAM binding for service account to access specific secrets
resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  for_each = local.secret_configs
  
  project   = var.project_id
  secret_id = google_secret_manager_secret.api_secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
  
  depends_on = [google_secret_manager_secret_version.api_secret_versions]
}

# Additional IAM roles for Cloud Run service account
resource "google_project_iam_member" "cloud_run_permissions" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create application source archive for Cloud Build
data "archive_file" "api_source" {
  type        = "zip"
  output_path = "${path.module}/secure-api-source.zip"
  
  source {
    content = templatefile("${path.module}/api_application.py", {
      project_id = var.project_id
      secrets = {
        database    = google_secret_manager_secret.api_secrets["database"].secret_id
        api_keys    = google_secret_manager_secret.api_secrets["api_keys"].secret_id
        application = google_secret_manager_secret.api_secrets["application"].secret_id
      }
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
  
  source {
    content  = file("${path.module}/Dockerfile")
    filename = "Dockerfile"
  }
}

# Cloud Storage bucket for storing application source
resource "google_storage_bucket" "source_bucket" {
  name     = "${local.service_name}-source-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Upload source code to Cloud Storage
resource "google_storage_bucket_object" "source_archive" {
  name   = "secure-api-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.api_source.output_path
  
  lifecycle {
    replace_triggered_by = [data.archive_file.api_source]
  }
}

# Cloud Run v2 service with comprehensive security configuration
resource "google_cloud_run_v2_service" "secure_api" {
  name     = local.service_name
  location = var.region
  project  = var.project_id
  
  deletion_protection = var.deletion_protection
  ingress             = var.ingress_traffic
  
  labels = local.common_labels
  
  template {
    # Use dedicated service account
    service_account = google_service_account.cloud_run_sa.email
    
    # Configure scaling
    scaling {
      min_instance_count = var.scaling_config.min_instances
      max_instance_count = var.scaling_config.max_instances
    }
    
    # Set execution environment and timeout
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    timeout               = "300s"
    
    # Configure container with security best practices
    containers {
      image = var.container_image
      
      # Resource limits for security and cost control
      resources {
        limits = var.container_resources
        startup_cpu_boost = true
      }
      
      # Environment variables for secret references (not secret values)
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      env {
        name  = "DB_SECRET_NAME"
        value = google_secret_manager_secret.api_secrets["database"].secret_id
      }
      
      env {
        name  = "KEYS_SECRET_NAME"
        value = google_secret_manager_secret.api_secrets["api_keys"].secret_id
      }
      
      env {
        name  = "CONFIG_SECRET_NAME"
        value = google_secret_manager_secret.api_secrets["application"].secret_id
      }
      
      # Health probes for reliability
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 3
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 3
        period_seconds        = 30
        failure_threshold     = 3
      }
      
      # Configure container port
      ports {
        container_port = 8080
        name          = "http1"
      }
    }
    
    # VPC access configuration (optional)
    dynamic "vpc_access" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        connector = var.vpc_connector_name
        egress    = "PRIVATE_RANGES_ONLY"
      }
    }
  }
  
  # Traffic allocation
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_secret_manager_secret_iam_member.secret_accessor,
    google_project_iam_member.cloud_run_permissions,
    google_project_service.required_apis
  ]
}

# API Gateway configuration for managed API access
resource "google_api_gateway_api" "secure_api_gateway" {
  provider = google-beta
  
  project  = var.project_id
  api_id   = local.gateway_name
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# OpenAPI specification for API Gateway
resource "local_file" "openapi_spec" {
  filename = "${path.module}/openapi-spec.yaml"
  content = templatefile("${path.module}/openapi-spec.yaml.tpl", {
    service_url = google_cloud_run_v2_service.secure_api.uri
    service_name = local.service_name
  })
}

# API Gateway configuration
resource "google_api_gateway_api_config" "secure_api_config" {
  provider = google-beta
  
  project       = var.project_id
  api           = google_api_gateway_api.secure_api_gateway.api_id
  api_config_id = "${local.gateway_name}-config"
  
  openapi_documents {
    document {
      path     = "openapi-spec.yaml"
      contents = base64encode(local_file.openapi_spec.content)
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_cloud_run_v2_service.secure_api]
}

# Deploy API Gateway
resource "google_api_gateway_gateway" "secure_api_gateway" {
  provider = google-beta
  
  project    = var.project_id
  region     = var.region
  gateway_id = local.gateway_name
  
  api_config = google_api_gateway_api_config.secure_api_config.id
  
  labels = local.common_labels
  
  depends_on = [google_api_gateway_api_config.secure_api_config]
}

# Monitoring alert policy for secret access anomalies (if monitoring enabled)
resource "google_monitoring_alert_policy" "secret_access_anomaly" {
  count = var.enable_monitoring ? 1 : 0
  
  project      = var.project_id
  display_name = "Secret Manager High Access Rate - ${local.service_name}"
  
  documentation {
    content = "Alert triggered when secret access rate exceeds normal thresholds"
  }
  
  conditions {
    display_name = "Secret Manager access rate"
    
    condition_threshold {
      filter          = "resource.type=\"secret_manager_secret\" AND resource.labels.secret_id=~\"${local.service_name}.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 100
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log-based metric for monitoring secret access patterns
resource "google_logging_metric" "secret_access_metric" {
  count = var.enable_monitoring ? 1 : 0
  
  project = var.project_id
  name    = "${local.service_name}-secret-access"
  
  filter = <<-EOT
    protoPayload.serviceName="secretmanager.googleapis.com"
    AND protoPayload.resourceName=~"projects/${var.project_id}/secrets/${local.service_name}.*"
    AND protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"
  EOT
  
  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Secret Manager Access Count"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Audit log configuration for Secret Manager (if audit logs enabled)
resource "google_logging_project_sink" "secret_audit_sink" {
  count = var.enable_audit_logs ? 1 : 0
  
  project     = var.project_id
  name        = "${local.service_name}-secret-audit"
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs[0].name}"
  
  filter = <<-EOT
    protoPayload.serviceName="secretmanager.googleapis.com"
    AND (
      protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"
      OR protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.CreateSecret"
      OR protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.UpdateSecret"
      OR protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.DeleteSecret"
    )
    AND protoPayload.resourceName=~"projects/${var.project_id}/secrets/${local.service_name}.*"
  EOT
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Audit logs storage bucket (if audit logs enabled)
resource "google_storage_bucket" "audit_logs" {
  count = var.enable_audit_logs ? 1 : 0
  
  name     = "${local.service_name}-audit-logs-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 365 # Keep audit logs for 1 year
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for audit log sink to write to storage bucket
resource "google_storage_bucket_iam_member" "audit_sink_writer" {
  count = var.enable_audit_logs ? 1 : 0
  
  bucket = google_storage_bucket.audit_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.secret_audit_sink[0].writer_identity
}
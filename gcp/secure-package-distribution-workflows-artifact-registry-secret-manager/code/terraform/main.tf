# Secure Package Distribution Workflows with Artifact Registry and Secret Manager
# This infrastructure creates a comprehensive secure package distribution system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and tagging
  name_prefix = "secure-packages-${random_id.suffix.hex}"
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    component   = "package-distribution"
  })
  
  # Service account email for package distribution
  service_account_email = google_service_account.package_distributor.email
  
  # Secret names for different environments
  environments = ["dev", "staging", "prod"]
  
  # Cloud Function source code
  function_source_dir = "${path.module}/function_source"
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudtasks.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudkms.googleapis.com"
  ])
  
  service = each.value
  project = var.project_id
  
  disable_on_destroy = false
}

# Create KMS key ring for encryption
resource "google_kms_key_ring" "package_distribution" {
  name     = "${local.name_prefix}-keyring"
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create KMS crypto key for Artifact Registry encryption
resource "google_kms_crypto_key" "artifact_registry" {
  name     = "artifact-registry-key"
  key_ring = google_kms_key_ring.package_distribution.id
  
  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = "${var.kms_key_rotation_period}s"
  
  labels = local.common_labels
}

# Create KMS crypto key for Secret Manager encryption
resource "google_kms_crypto_key" "secret_manager" {
  name     = "secret-manager-key"
  key_ring = google_kms_key_ring.package_distribution.id
  
  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = "${var.kms_key_rotation_period}s"
  
  labels = local.common_labels
}

# Create Artifact Registry repositories using the official Google Cloud Platform module
module "artifact_registry_repositories" {
  source = "GoogleCloudPlatform/artifact-registry/google"
  version = "~> 0.3.0"
  
  for_each = toset(var.repository_formats)
  
  project_id    = var.project_id
  location      = var.region
  repository_id = "${local.name_prefix}-${each.value}"
  format        = upper(each.value)
  description   = "Secure ${each.value} package repository for distribution workflows"
  
  labels = local.common_labels
  
  # Enable KMS encryption
  kms_key_name = google_kms_crypto_key.artifact_registry.id
  
  # Configure cleanup policies
  cleanup_policies = var.cleanup_policy_enabled ? {
    "keep-recent-versions" = {
      action = "DELETE"
      condition = {
        older_than = var.cleanup_policy_older_than
      }
      most_recent_versions = {
        keep_count = var.cleanup_policy_keep_count
      }
    }
  } : {}
  
  # Configure Docker-specific settings
  docker_config = each.value == "docker" ? {
    immutable_tags = true
  } : null
  
  # Configure Maven-specific settings
  maven_config = each.value == "maven" ? {
    allow_snapshot_overwrites = false
    version_policy           = "VERSION_POLICY_UNSPECIFIED"
  } : null
  
  # Configure IAM members for repository access
  members = {
    readers = [
      "serviceAccount:${local.service_account_email}",
      "group:package-readers@${var.project_id}.iam.gserviceaccount.com"
    ]
    writers = [
      "serviceAccount:${local.service_account_email}",
      "group:package-writers@${var.project_id}.iam.gserviceaccount.com"
    ]
  }
  
  depends_on = [
    google_project_service.apis,
    google_service_account.package_distributor
  ]
}

# Create service account for package distribution
resource "google_service_account" "package_distributor" {
  account_id   = "${local.name_prefix}-sa"
  display_name = "Package Distribution Service Account"
  description  = "Service account for automated package distribution workflows"
  project      = var.project_id
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "package_distributor_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/artifactregistry.writer",
    "roles/secretmanager.secretAccessor",
    "roles/cloudfunctions.invoker",
    "roles/cloudtasks.enqueuer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.package_distributor.email}"
}

# Grant KMS encrypt/decrypt permissions
resource "google_kms_crypto_key_iam_member" "artifact_registry_key_user" {
  crypto_key_id = google_kms_crypto_key.artifact_registry.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.package_distributor.email}"
}

resource "google_kms_crypto_key_iam_member" "secret_manager_key_user" {
  crypto_key_id = google_kms_crypto_key.secret_manager.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.package_distributor.email}"
}

# Create Secret Manager secrets for different environments
resource "google_secret_manager_secret" "registry_credentials" {
  for_each = toset(local.environments)
  
  secret_id = "${local.name_prefix}-registry-credentials-${each.value}"
  project   = var.project_id
  
  labels = merge(local.common_labels, {
    environment = each.value
    purpose     = "registry-auth"
  })
  
  replication {
    dynamic "user_managed" {
      for_each = var.secret_replication_policy == "user-managed" ? [1] : []
      content {
        replicas {
          location = var.region
          customer_managed_encryption {
            kms_key_name = google_kms_crypto_key.secret_manager.id
          }
        }
      }
    }
    
    dynamic "automatic" {
      for_each = var.secret_replication_policy == "automatic" ? [1] : []
      content {
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secret_manager.id
        }
      }
    }
  }
  
  # Enable rotation
  rotation {
    rotation_period = "${var.secret_rotation_period}s"
  }
  
  depends_on = [google_project_service.apis]
}

# Create initial secret versions with placeholder values
resource "google_secret_manager_secret_version" "registry_credentials_initial" {
  for_each = toset(local.environments)
  
  secret      = google_secret_manager_secret.registry_credentials[each.value].id
  secret_data = "${each.value}-registry-token-placeholder"
  
  # This is a placeholder - in production, you would use actual tokens
  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Create distribution configuration secret
resource "google_secret_manager_secret" "distribution_config" {
  secret_id = "${local.name_prefix}-distribution-config"
  project   = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "distribution-config"
  })
  
  replication {
    dynamic "user_managed" {
      for_each = var.secret_replication_policy == "user-managed" ? [1] : []
      content {
        replicas {
          location = var.region
          customer_managed_encryption {
            kms_key_name = google_kms_crypto_key.secret_manager.id
          }
        }
      }
    }
    
    dynamic "automatic" {
      for_each = var.secret_replication_policy == "automatic" ? [1] : []
      content {
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secret_manager.id
        }
      }
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Create distribution configuration secret version
resource "google_secret_manager_secret_version" "distribution_config" {
  secret = google_secret_manager_secret.distribution_config.id
  secret_data = jsonencode({
    environments = {
      dev = {
        endpoint = "dev.example.com"
        timeout  = 30
      }
      staging = {
        endpoint = "staging.example.com"
        timeout  = 60
      }
      prod = {
        endpoint = "prod.example.com"
        timeout  = 120
      }
    }
  })
}

# Create Cloud Tasks queues for workflow orchestration
resource "google_cloud_tasks_queue" "package_distribution" {
  name     = "${local.name_prefix}-distribution-queue"
  location = var.region
  project  = var.project_id
  
  rate_limits {
    max_dispatches_per_second = var.task_queue_max_dispatches_per_second
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
  }
  
  retry_config {
    max_attempts       = 3
    max_retry_duration = "${var.task_queue_max_retry_duration}s"
    min_backoff        = "1s"
    max_backoff        = "300s"
    max_doublings      = 5
  }
  
  depends_on = [google_project_service.apis]
}

# Create high-priority production queue
resource "google_cloud_tasks_queue" "prod_distribution" {
  name     = "${local.name_prefix}-prod-distribution-queue"
  location = var.region
  project  = var.project_id
  
  rate_limits {
    max_dispatches_per_second = 5
    max_concurrent_dispatches = 2
  }
  
  retry_config {
    max_attempts       = 5
    max_retry_duration = "7200s"
    min_backoff        = "5s"
    max_backoff        = "600s"
    max_doublings      = 3
  }
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source"
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
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Create Cloud Function for package distribution
resource "google_cloudfunctions_function" "package_distributor" {
  name                  = "${local.name_prefix}-distributor"
  location              = var.region
  project               = var.project_id
  description           = "Serverless function for secure package distribution workflows"
  runtime               = var.function_runtime
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point           = "distribute_package"
  service_account_email = google_service_account.package_distributor.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  trigger {
    http_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    GCP_PROJECT    = var.project_id
    RANDOM_SUFFIX  = random_id.suffix.hex
    REGION         = var.region
    ENVIRONMENT    = var.environment
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.function_source
  ]
}

# Create Cloud Scheduler jobs for automated distribution
resource "google_cloud_scheduler_job" "nightly_distribution" {
  name             = "${local.name_prefix}-nightly"
  description      = "Nightly package distribution to development environment"
  schedule         = var.scheduler_nightly_schedule
  time_zone        = var.scheduler_timezone
  region           = var.region
  project          = var.project_id
  attempt_deadline = "300s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.package_distributor.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      package_name    = "webapp"
      package_version = "latest"
      environment     = "dev"
    }))
    
    oidc_token {
      service_account_email = google_service_account.package_distributor.email
    }
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions_function.package_distributor
  ]
}

# Create weekly staging deployment job
resource "google_cloud_scheduler_job" "weekly_staging" {
  name             = "${local.name_prefix}-weekly-staging"
  description      = "Weekly package distribution to staging environment"
  schedule         = var.scheduler_weekly_schedule
  time_zone        = var.scheduler_timezone
  region           = var.region
  project          = var.project_id
  attempt_deadline = "300s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.package_distributor.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      package_name    = "webapp"
      package_version = "stable"
      environment     = "staging"
    }))
    
    oidc_token {
      service_account_email = google_service_account.package_distributor.email
    }
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions_function.package_distributor
  ]
}

# Create production deployment job (manual trigger recommended)
resource "google_cloud_scheduler_job" "prod_manual" {
  name             = "${local.name_prefix}-prod-manual"
  description      = "Production package distribution (manual trigger recommended)"
  schedule         = "0 0 1 1 *"  # Very rare schedule, meant to be triggered manually
  time_zone        = var.scheduler_timezone
  region           = var.region
  project          = var.project_id
  attempt_deadline = "300s"
  
  retry_config {
    retry_count = 5
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.package_distributor.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      package_name    = "webapp"
      package_version = "release"
      environment     = "prod"
    }))
    
    oidc_token {
      service_account_email = google_service_account.package_distributor.email
    }
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions_function.package_distributor
  ]
}

# Create log-based metrics for monitoring
resource "google_logging_metric" "distribution_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "${local.name_prefix}-distribution-failures"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions_function.package_distributor.name}"
    severity="ERROR"
  EOT
  
  label_extractors = {
    "error_type" = "EXTRACT(jsonPayload.error)"
  }
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Package Distribution Failures"
    description  = "Count of package distribution failures"
    labels {
      key         = "error_type"
      value_type  = "STRING"
      description = "Type of error that occurred"
    }
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions_function.package_distributor
  ]
}

resource "google_logging_metric" "distribution_success" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "${local.name_prefix}-distribution-success"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions_function.package_distributor.name}"
    jsonPayload.status="success"
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Package Distribution Success"
    description  = "Count of successful package distributions"
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions_function.package_distributor
  ]
}

# Create monitoring notification channel (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Package Distribution Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.apis]
}

# Create alerting policy for distribution failures
resource "google_monitoring_alert_policy" "distribution_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Package Distribution Failures"
  project      = var.project_id
  
  documentation {
    content = "Alert when package distribution failures exceed threshold"
  }
  
  conditions {
    display_name = "Distribution failure rate"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.distribution_failures[0].name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 2
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  enabled = true
  
  depends_on = [
    google_project_service.apis,
    google_logging_metric.distribution_failures
  ]
}

# Create audit log sink for compliance
resource "google_logging_project_sink" "audit_log_sink" {
  count = var.enable_audit_logging ? 1 : 0
  
  name        = "${local.name_prefix}-audit-sink"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs[0].name}"
  
  filter = <<-EOT
    protoPayload.serviceName="artifactregistry.googleapis.com"
    OR protoPayload.serviceName="secretmanager.googleapis.com"
    OR protoPayload.serviceName="cloudfunctions.googleapis.com"
    OR protoPayload.serviceName="cloudscheduler.googleapis.com"
    OR protoPayload.serviceName="cloudtasks.googleapis.com"
  EOT
  
  unique_writer_identity = true
}

# Create Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  count = var.enable_audit_logging ? 1 : 0
  
  name     = "${local.name_prefix}-audit-logs"
  location = var.region
  project  = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "audit-logs"
  })
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Grant storage admin role to audit log sink
resource "google_storage_bucket_iam_member" "audit_log_sink_writer" {
  count = var.enable_audit_logging ? 1 : 0
  
  bucket = google_storage_bucket.audit_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_log_sink[0].writer_identity
}
# Main Terraform configuration for GCP data pipeline automation
# with BigQuery Continuous Queries and Cloud KMS

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  name_suffix = random_id.suffix.hex
  common_labels = {
    environment = var.environment
    project     = "data-pipeline-automation"
    managed-by  = "terraform"
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "bigquery.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudscheduler.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com"
  ]) : []

  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

#------------------------------------------------------------------------------
# Cloud KMS Infrastructure for Data Encryption
#------------------------------------------------------------------------------

# Create KMS key ring for centralized key management
resource "google_kms_key_ring" "pipeline_keyring" {
  name     = "${var.keyring_name}-${local.name_suffix}"
  location = var.region
  
  depends_on = [time_sleep.wait_for_apis]
  
  labels = local.common_labels
}

# Create primary encryption key with automatic rotation
resource "google_kms_crypto_key" "data_encryption_key" {
  name     = var.key_name
  key_ring = google_kms_key_ring.pipeline_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  # Configure automatic key rotation
  rotation_period = var.key_rotation_period
  
  # Configure key version template
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE" # Use "HSM" for hardware security modules in production
  }
  
  labels = local.common_labels
  
  lifecycle {
    prevent_destroy = true
  }
}

# Create column-level encryption key
resource "google_kms_crypto_key" "column_encryption_key" {
  name     = "${var.key_name}-column"
  key_ring = google_kms_key_ring.pipeline_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
  
  labels = local.common_labels
  
  lifecycle {
    prevent_destroy = true
  }
}

#------------------------------------------------------------------------------
# BigQuery Infrastructure with Customer-Managed Encryption
#------------------------------------------------------------------------------

# Create BigQuery dataset with CMEK encryption
resource "google_bigquery_dataset" "streaming_analytics" {
  dataset_id                  = var.dataset_id
  friendly_name              = "Streaming Analytics Dataset"
  description                = "Dataset for real-time streaming analytics with CMEK encryption"
  location                   = var.region
  delete_contents_on_destroy = !var.deletion_protection
  
  # Configure customer-managed encryption
  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.data_encryption_key.id
  }
  
  # Configure access controls
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }
  
  access {
    role   = "READER"
    domain = "google.com"
  }
  
  labels = local.common_labels
  
  depends_on = [google_kms_crypto_key.data_encryption_key]
}

# Create source table for streaming data
resource "google_bigquery_table" "raw_events" {
  dataset_id          = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id           = "raw_events"
  deletion_protection = var.deletion_protection
  
  description = "Raw events table for streaming data ingestion"
  
  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the event"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Event timestamp"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "User identifier"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of event"
    },
    {
      name = "metadata"
      type = "JSON"
      mode = "NULLABLE"
      description = "Event metadata in JSON format"
    }
  ])
  
  # Configure time partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Configure clustering for query optimization
  clustering = ["event_type", "user_id"]
  
  labels = local.common_labels
}

# Create processed events table
resource "google_bigquery_table" "processed_events" {
  dataset_id          = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id           = "processed_events"
  deletion_protection = var.deletion_protection
  
  description = "Processed events with enrichment and risk scoring"
  
  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Original event identifier"
    },
    {
      name = "processed_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Processing timestamp"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "User identifier"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of event"
    },
    {
      name = "enriched_data"
      type = "JSON"
      mode = "NULLABLE"
      description = "Enriched event data"
    },
    {
      name = "risk_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Calculated risk score"
    }
  ])
  
  time_partitioning {
    type  = "DAY"
    field = "processed_timestamp"
  }
  
  clustering = ["event_type", "risk_score"]
  
  labels = local.common_labels
}

# Create encrypted user data table with column-level encryption
resource "google_bigquery_table" "encrypted_user_data" {
  dataset_id          = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id           = "encrypted_user_data"
  deletion_protection = var.deletion_protection
  
  description = "User data table with column-level encryption for sensitive fields"
  
  schema = jsonencode([
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "User identifier"
    },
    {
      name = "email_encrypted"
      type = "BYTES"
      mode = "NULLABLE"
      description = "Encrypted email address"
    },
    {
      name = "phone_encrypted"
      type = "BYTES"
      mode = "NULLABLE"
      description = "Encrypted phone number"
    },
    {
      name = "created_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Record creation timestamp"
      defaultValueExpression = "CURRENT_TIMESTAMP()"
    },
    {
      name = "last_updated"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Last update timestamp"
      defaultValueExpression = "CURRENT_TIMESTAMP()"
    }
  ])
  
  labels = local.common_labels
}

#------------------------------------------------------------------------------
# Cloud Pub/Sub Infrastructure with Encryption
#------------------------------------------------------------------------------

# Create Pub/Sub topic with CMEK encryption
resource "google_pubsub_topic" "streaming_events" {
  name = "streaming-events-${local.name_suffix}"
  
  # Configure customer-managed encryption
  kms_key_name = google_kms_crypto_key.data_encryption_key.id
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_kms_crypto_key.data_encryption_key]
}

# Create subscription for BigQuery streaming
resource "google_pubsub_subscription" "bq_streaming_sub" {
  name  = "${google_pubsub_topic.streaming_events.name}-bq-sub"
  topic = google_pubsub_topic.streaming_events.name
  
  # Configure acknowledgment deadline
  ack_deadline_seconds = 600
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.streaming_events_dlq.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "streaming_events_dlq" {
  name = "${google_pubsub_topic.streaming_events.name}-dlq"
  
  kms_key_name = google_kms_crypto_key.data_encryption_key.id
  
  labels = local.common_labels
}

#------------------------------------------------------------------------------
# Cloud Storage Infrastructure with Encryption
#------------------------------------------------------------------------------

# Create Cloud Storage bucket with CMEK encryption
resource "google_storage_bucket" "pipeline_data" {
  name          = "pipeline-data-${local.name_suffix}"
  location      = var.region
  storage_class = var.storage_class
  
  # Configure customer-managed encryption
  encryption {
    default_kms_key_name = google_kms_crypto_key.data_encryption_key.id
  }
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Configure uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_kms_crypto_key.data_encryption_key]
}

# Create directory structure for organized data storage
resource "google_storage_bucket_object" "schemas_directory" {
  name    = "schemas/"
  content = " " # Placeholder content for directory
  bucket  = google_storage_bucket.pipeline_data.name
}

resource "google_storage_bucket_object" "exports_directory" {
  name    = "exports/"
  content = " " # Placeholder content for directory
  bucket  = google_storage_bucket.pipeline_data.name
}

resource "google_storage_bucket_object" "audit_logs_directory" {
  name    = "audit-logs/"
  content = " " # Placeholder content for directory
  bucket  = google_storage_bucket.pipeline_data.name
}

# Create event schema file
resource "google_storage_bucket_object" "event_schema" {
  name    = "schemas/event_schema.csv"
  content = "timestamp,event_data"
  bucket  = google_storage_bucket.pipeline_data.name
}

#------------------------------------------------------------------------------
# Cloud Functions for Security and Encryption Operations
#------------------------------------------------------------------------------

# Create Cloud Function source code for security audit
resource "google_storage_bucket_object" "security_audit_source" {
  name   = "functions/security-audit.zip"
  bucket = google_storage_bucket.pipeline_data.name
  source = "${path.module}/functions/security-audit.zip"
  
  # This is a placeholder - in a real deployment, you would upload actual function code
  content_type = "application/zip"
}

# Security audit Cloud Function
resource "google_cloudfunctions_function" "security_audit" {
  name        = "security-audit-${local.name_suffix}"
  description = "Automated security audit function for KMS and data pipeline"
  runtime     = "python311"
  
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.pipeline_data.name
  source_archive_object = google_storage_bucket_object.security_audit_source.name
  
  timeout = 60
  entry_point = "security_audit"
  
  trigger {
    https_trigger {
      url = "https://${var.region}-${var.project_id}.cloudfunctions.net/security-audit-${local.name_suffix}"
    }
  }
  
  environment_variables = {
    PROJECT_ID   = var.project_id
    LOCATION     = var.region
    KEYRING_NAME = google_kms_key_ring.pipeline_keyring.name
  }
  
  labels = local.common_labels
  
  depends_on = [google_storage_bucket_object.security_audit_source]
}

# Create Cloud Function for data encryption/decryption
resource "google_storage_bucket_object" "encryption_function_source" {
  name   = "functions/encrypt-sensitive-data.zip"
  bucket = google_storage_bucket.pipeline_data.name
  source = "${path.module}/functions/encrypt-sensitive-data.zip"
  
  content_type = "application/zip"
}

# Data encryption Cloud Function
resource "google_cloudfunctions_function" "encrypt_sensitive_data" {
  name        = "encrypt-sensitive-data-${local.name_suffix}"
  description = "Function for encrypting sensitive data using Cloud KMS"
  runtime     = "python311"
  
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.pipeline_data.name
  source_archive_object = google_storage_bucket_object.encryption_function_source.name
  
  timeout = 60
  entry_point = "encrypt_sensitive_data"
  
  trigger {
    https_trigger {
      url = "https://${var.region}-${var.project_id}.cloudfunctions.net/encrypt-sensitive-data-${local.name_suffix}"
    }
  }
  
  environment_variables = {
    PROJECT_ID         = var.project_id
    LOCATION           = var.region
    COLUMN_KEY_NAME    = google_kms_crypto_key.column_encryption_key.id
  }
  
  labels = local.common_labels
  
  depends_on = [google_storage_bucket_object.encryption_function_source]
}

#------------------------------------------------------------------------------
# Cloud Scheduler for Automated Security Operations
#------------------------------------------------------------------------------

# Create Cloud Scheduler job for daily security audits
resource "google_cloud_scheduler_job" "security_audit_daily" {
  count = var.monitoring_enabled ? 1 : 0
  
  name             = "security-audit-daily-${local.name_suffix}"
  description      = "Daily automated security audit job"
  schedule         = var.security_audit_schedule
  time_zone        = "UTC"
  attempt_deadline = "60s"
  
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    max_backoff_duration = "60s"
    min_backoff_duration = "10s"
    max_doublings        = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.security_audit.trigger[0].https_trigger[0].url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      project_id   = var.project_id
      location     = var.region
      keyring_name = google_kms_key_ring.pipeline_keyring.name
      timestamp    = "scheduled"
    }))
  }
  
  depends_on = [google_cloudfunctions_function.security_audit]
}

#------------------------------------------------------------------------------
# Monitoring and Logging Infrastructure
#------------------------------------------------------------------------------

# Create log-based metric for KMS key usage
resource "google_logging_metric" "kms_key_usage" {
  count = var.monitoring_enabled ? 1 : 0
  
  name   = "kms_key_usage_${local.name_suffix}"
  filter = <<EOF
resource.type="cloudkms_cryptokey"
AND (protoPayload.methodName="Encrypt" OR protoPayload.methodName="Decrypt")
EOF
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "KMS Key Usage Count"
  }
  
  label_extractors = {
    "key_name" = "EXTRACT(protoPayload.resourceName)"
    "method"   = "EXTRACT(protoPayload.methodName)"
  }
}

# Create log-based metric for continuous query performance
resource "google_logging_metric" "continuous_query_performance" {
  count = var.monitoring_enabled ? 1 : 0
  
  name   = "continuous_query_performance_${local.name_suffix}"
  filter = <<EOF
resource.type="bigquery_resource"
AND protoPayload.methodName="jobservice.jobcompleted"
AND protoPayload.serviceData.jobCompletedEvent.job.jobConfiguration.query.continuous=true
EOF
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Continuous Query Performance"
  }
  
  label_extractors = {
    "job_id" = "EXTRACT(protoPayload.serviceData.jobCompletedEvent.job.jobName.jobId)"
  }
}

# Create log sink for security audit trail
resource "google_logging_project_sink" "security_audit_sink" {
  count = var.monitoring_enabled ? 1 : 0
  
  name        = "security-audit-sink-${local.name_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.pipeline_data.name}/audit-logs"
  
  filter = <<EOF
protoPayload.authenticationInfo.principalEmail!=""
AND (resource.type="cloudkms_cryptokey"
OR resource.type="bigquery_resource"
OR resource.type="pubsub_topic")
EOF
  
  unique_writer_identity = true
}

# Grant storage object creator role to the log sink service account
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.monitoring_enabled ? 1 : 0
  
  bucket = google_storage_bucket.pipeline_data.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.security_audit_sink[0].writer_identity
}

#------------------------------------------------------------------------------
# IAM and Security Configuration
#------------------------------------------------------------------------------

# Get current user information
data "google_client_openid_userinfo" "me" {}

# Grant BigQuery data editor role to the current user
resource "google_bigquery_dataset_iam_member" "dataset_admin" {
  dataset_id = google_bigquery_dataset.streaming_analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "user:${data.google_client_openid_userinfo.me.email}"
}

# Grant KMS encrypt/decrypt permissions to BigQuery service account
data "google_project" "current" {}

resource "google_kms_crypto_key_iam_member" "bigquery_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.data_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:bq-${data.google_project.current.number}@bigquery-encryption.iam.gserviceaccount.com"
}

# Grant KMS permissions to Pub/Sub service account
resource "google_kms_crypto_key_iam_member" "pubsub_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.data_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Grant KMS permissions to Cloud Storage service account
resource "google_kms_crypto_key_iam_member" "storage_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.data_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}
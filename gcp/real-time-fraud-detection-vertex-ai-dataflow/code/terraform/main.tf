# ============================================================================
# Real-Time Fraud Detection Infrastructure with Vertex AI and Cloud Dataflow
# ============================================================================

# Generate unique suffix for resource names to avoid conflicts
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming conventions
  name_prefix = "${var.fraud_detection_system_name}-${var.environment}"
  resource_suffix = random_id.suffix.hex
  
  # Computed resource names
  bucket_name = "${var.project_id}-${var.storage_bucket_name}-${local.resource_suffix}"
  dataset_id = "${var.bigquery_dataset_id}_${local.resource_suffix}"
  topic_name = "${var.pubsub_topic_name}-${local.resource_suffix}"
  subscription_name = "${var.pubsub_subscription_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    project     = var.project_id
  })
}

# ============================================================================
# API Services Configuration
# ============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.required_apis)
  
  project = var.project_id
  service = each.key
  
  disable_dependent_services = var.disable_dependent_services
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be ready before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# ============================================================================
# IAM Service Accounts Configuration
# ============================================================================

# Service account for Dataflow pipeline execution
resource "google_service_account" "dataflow_service_account" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${local.name_prefix}-dataflow-sa"
  display_name = "Fraud Detection Dataflow Service Account"
  description  = "Service account for running Dataflow fraud detection pipeline"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Service account for Vertex AI operations
resource "google_service_account" "vertex_ai_service_account" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${local.name_prefix}-vertex-ai-sa"
  display_name = "Fraud Detection Vertex AI Service Account"
  description  = "Service account for Vertex AI fraud detection model operations"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Service account for BigQuery operations
resource "google_service_account" "bigquery_service_account" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${local.name_prefix}-bigquery-sa"
  display_name = "Fraud Detection BigQuery Service Account"
  description  = "Service account for BigQuery fraud detection operations"
  
  depends_on = [time_sleep.wait_for_apis]
}

# ============================================================================
# IAM Role Bindings for Service Accounts
# ============================================================================

# Dataflow service account IAM bindings
resource "google_project_iam_member" "dataflow_worker" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_service_account[0].email}"
}

resource "google_project_iam_member" "dataflow_compute_instanceAdmin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.dataflow_service_account[0].email}"
}

resource "google_project_iam_member" "dataflow_storage_objectAdmin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dataflow_service_account[0].email}"
}

resource "google_project_iam_member" "dataflow_bigquery_dataEditor" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataflow_service_account[0].email}"
}

resource "google_project_iam_member" "dataflow_pubsub_subscriber" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.dataflow_service_account[0].email}"
}

resource "google_project_iam_member" "dataflow_aiplatform_user" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.dataflow_service_account[0].email}"
}

# Vertex AI service account IAM bindings
resource "google_project_iam_member" "vertex_ai_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account[0].email}"
}

resource "google_project_iam_member" "vertex_ai_storage_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account[0].email}"
}

resource "google_project_iam_member" "vertex_ai_bigquery_user" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account[0].email}"
}

# BigQuery service account IAM bindings
resource "google_project_iam_member" "bigquery_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.bigquery_service_account[0].email}"
}

# ============================================================================
# Cloud Storage Configuration
# ============================================================================

# Primary storage bucket for ML artifacts and pipeline data
resource "google_storage_bucket" "fraud_detection_bucket" {
  name                        = local.bucket_name
  location                    = var.storage_bucket_location
  force_destroy               = true
  uniform_bucket_level_access = true
  storage_class               = var.storage_bucket_storage_class
  
  labels = local.common_labels
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle configuration for cost optimization
  lifecycle_rule {
    condition {
      age = var.auto_delete_resources_after_days > 0 ? var.auto_delete_resources_after_days : 365
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for transitioning to cheaper storage classes
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
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create directory structure in the bucket using objects
resource "google_storage_bucket_object" "training_data_folder" {
  name    = "training_data/"
  content = " "
  bucket  = google_storage_bucket.fraud_detection_bucket.name
}

resource "google_storage_bucket_object" "temp_folder" {
  name    = "temp/"
  content = " "
  bucket  = google_storage_bucket.fraud_detection_bucket.name
}

resource "google_storage_bucket_object" "staging_folder" {
  name    = "staging/"
  content = " "
  bucket  = google_storage_bucket.fraud_detection_bucket.name
}

resource "google_storage_bucket_object" "models_folder" {
  name    = "models/"
  content = " "
  bucket  = google_storage_bucket.fraud_detection_bucket.name
}

resource "google_storage_bucket_object" "validation_folder" {
  name    = "validation/"
  content = " "
  bucket  = google_storage_bucket.fraud_detection_bucket.name
}

# ============================================================================
# BigQuery Configuration
# ============================================================================

# BigQuery dataset for fraud detection analytics
resource "google_bigquery_dataset" "fraud_detection_dataset" {
  dataset_id    = local.dataset_id
  friendly_name = "Fraud Detection Analytics"
  description   = var.bigquery_dataset_description
  location      = var.region
  
  labels = local.common_labels
  
  # Dataset access configuration
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.access_token != "" ? data.google_service_account.compute_default.email : null
  }
  
  dynamic "access" {
    for_each = var.create_service_accounts ? [1] : []
    content {
      role          = "WRITER"
      user_by_email = google_service_account.dataflow_service_account[0].email
    }
  }
  
  dynamic "access" {
    for_each = var.create_service_accounts ? [1] : []
    content {
      role          = "READER"
      user_by_email = google_service_account.vertex_ai_service_account[0].email
    }
  }
  
  # Default table expiration
  default_table_expiration_ms = var.bigquery_table_expiration_ms
  
  depends_on = [time_sleep.wait_for_apis]
}

# Transactions table for storing processed transaction data
resource "google_bigquery_table" "transactions_table" {
  dataset_id          = google_bigquery_dataset.fraud_detection_dataset.dataset_id
  table_id           = "transactions"
  friendly_name      = "Transaction Records"
  description        = "Table storing all processed transactions with fraud scores"
  deletion_protection = false
  
  labels = local.common_labels
  
  # Define table schema optimized for fraud detection
  schema = jsonencode([
    {
      name = "transaction_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique transaction identifier"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "User account identifier"
    },
    {
      name = "amount"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Transaction amount in base currency"
    },
    {
      name = "merchant"
      type = "STRING"
      mode = "NULLABLE"
      description = "Merchant identifier or name"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Transaction timestamp"
    },
    {
      name = "fraud_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "ML model fraud score (0.0 to 1.0)"
    },
    {
      name = "is_fraud"
      type = "BOOLEAN"
      mode = "NULLABLE"
      description = "Binary fraud classification"
    },
    {
      name = "features"
      type = "JSON"
      mode = "NULLABLE"
      description = "Engineered features used for prediction"
    },
    {
      name = "location"
      type = "STRING"
      mode = "NULLABLE"
      description = "Transaction location or region"
    },
    {
      name = "payment_method"
      type = "STRING"
      mode = "NULLABLE"
      description = "Payment method used for transaction"
    },
    {
      name = "risk_factors"
      type = "STRING"
      mode = "NULLABLE"
      description = "Comma-separated list of identified risk factors"
    },
    {
      name = "confidence"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Model confidence score"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "When the transaction was processed by the pipeline"
    }
  ])
  
  # Partitioning by transaction timestamp for performance
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
    require_partition_filter = false
  }
  
  # Clustering for improved query performance
  clustering = ["user_id", "is_fraud", "fraud_score"]
}

# Fraud alerts table for investigation workflow
resource "google_bigquery_table" "fraud_alerts_table" {
  dataset_id          = google_bigquery_dataset.fraud_detection_dataset.dataset_id
  table_id           = "fraud_alerts"
  friendly_name      = "Fraud Alert Records"
  description        = "Table storing high-risk fraud alerts for investigation"
  deletion_protection = false
  
  labels = local.common_labels
  
  # Define schema for fraud alert management
  schema = jsonencode([
    {
      name = "alert_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique alert identifier"
    },
    {
      name = "transaction_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Associated transaction identifier"
    },
    {
      name = "fraud_score"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Fraud score that triggered the alert"
    },
    {
      name = "alert_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the alert was generated"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Alert status (PENDING, INVESTIGATING, RESOLVED, FALSE_POSITIVE)"
    },
    {
      name = "investigation_notes"
      type = "STRING"
      mode = "NULLABLE"
      description = "Notes from fraud investigation"
    },
    {
      name = "assigned_analyst"
      type = "STRING"
      mode = "NULLABLE"
      description = "Analyst assigned to investigate the alert"
    },
    {
      name = "risk_factors"
      type = "STRING"
      mode = "NULLABLE"
      description = "Risk factors that contributed to the alert"
    },
    {
      name = "confidence"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Model confidence for the fraud prediction"
    },
    {
      name = "resolution_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "When the alert was resolved"
    }
  ])
  
  # Partitioning by alert timestamp
  time_partitioning {
    type  = "DAY"
    field = "alert_timestamp"
    require_partition_filter = false
  }
  
  # Clustering for investigation workflow
  clustering = ["status", "assigned_analyst", "fraud_score"]
}

# ============================================================================
# Pub/Sub Configuration
# ============================================================================

# Pub/Sub topic for transaction streaming
resource "google_pubsub_topic" "transaction_stream" {
  name = local.topic_name
  
  labels = local.common_labels
  
  # Message retention configuration
  message_retention_duration = "604800s" # 7 days
  
  # Schema validation for transaction messages
  schema_settings {
    schema   = google_pubsub_schema.transaction_schema.id
    encoding = "JSON"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Schema definition for transaction messages
resource "google_pubsub_schema" "transaction_schema" {
  name = "${local.name_prefix}-transaction-schema"
  type = "AVRO"
  
  definition = jsonencode({
    type = "record"
    name = "Transaction"
    fields = [
      {
        name = "transaction_id"
        type = "string"
      },
      {
        name = "user_id"
        type = "string"
      },
      {
        name = "amount"
        type = "double"
      },
      {
        name = "merchant"
        type = ["null", "string"]
        default = null
      },
      {
        name = "timestamp"
        type = "string"
      },
      {
        name = "location"
        type = ["null", "string"]
        default = null
      },
      {
        name = "payment_method"
        type = ["null", "string"]
        default = null
      },
      {
        name = "merchant_category"
        type = ["null", "string"]
        default = null
      }
    ]
  })
}

# Pub/Sub subscription for Dataflow processing
resource "google_pubsub_subscription" "fraud_processor" {
  name  = local.subscription_name
  topic = google_pubsub_topic.transaction_stream.name
  
  labels = local.common_labels
  
  # Subscription configuration optimized for stream processing
  message_retention_duration = var.pubsub_message_retention_duration
  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  
  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter queue configuration
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = var.pubsub_max_delivery_attempts
  }
  
  # Enable ordering for consistent processing
  enable_message_ordering = true
  
  # Flow control settings for high-throughput processing
  flow_control_settings {
    max_outstanding_messages = 1000
    max_outstanding_bytes    = 10485760 # 10MB
  }
  
  depends_on = [google_pubsub_topic.transaction_stream]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter_topic" {
  name = "${local.topic_name}-dlq"
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
  
  message_retention_duration = "2592000s" # 30 days
}

# ============================================================================
# Vertex AI Configuration
# ============================================================================

# Vertex AI dataset for fraud detection training
resource "google_vertex_ai_dataset" "fraud_detection_dataset" {
  display_name   = "${var.vertex_ai_dataset_display_name} ${title(var.environment)}"
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region         = var.vertex_ai_region
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Vertex AI endpoint for model serving
resource "google_vertex_ai_endpoint" "fraud_detection_endpoint" {
  name         = "${local.name_prefix}-endpoint"
  display_name = "${var.vertex_ai_endpoint_display_name} ${title(var.environment)}"
  description  = "Endpoint for serving fraud detection model predictions"
  location     = var.vertex_ai_region
  region       = var.vertex_ai_region
  
  labels = local.common_labels
  
  # Encryption configuration
  encryption_spec {
    kms_key_name = var.enable_cost_optimization ? null : google_kms_crypto_key.vertex_ai_key[0].id
  }
  
  depends_on = [google_vertex_ai_dataset.fraud_detection_dataset]
}

# ============================================================================
# Cloud KMS Configuration (Optional for Production)
# ============================================================================

# KMS keyring for encryption (only if cost optimization is disabled)
resource "google_kms_key_ring" "fraud_detection_keyring" {
  count = var.enable_cost_optimization ? 0 : 1
  
  name     = "${local.name_prefix}-keyring"
  location = var.region
  
  depends_on = [time_sleep.wait_for_apis]
}

# KMS key for Vertex AI encryption
resource "google_kms_crypto_key" "vertex_ai_key" {
  count = var.enable_cost_optimization ? 0 : 1
  
  name     = "${local.name_prefix}-vertex-ai-key"
  key_ring = google_kms_key_ring.fraud_detection_keyring[0].id
  
  purpose = "ENCRYPT_DECRYPT"
  
  lifecycle {
    prevent_destroy = false
  }
}

# ============================================================================
# Cloud Monitoring Configuration
# ============================================================================

# Log-based metric for fraud detection rate
resource "google_logging_metric" "fraud_detection_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${local.name_prefix}-fraud-detection-rate"
  filter = "resource.type=dataflow_job AND jsonPayload.fraud_score>0.8"
  
  label_extractors = {
    "fraud_score" = "EXTRACT(jsonPayload.fraud_score)"
  }
  
  value_extractor = "EXTRACT(jsonPayload.fraud_score)"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Fraud Detection Rate"
    description  = "Rate of fraud alerts generated per minute"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Log-based metric for transaction processing rate
resource "google_logging_metric" "transaction_processing_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${local.name_prefix}-transaction-processing-rate"
  filter = "resource.type=dataflow_job AND jsonPayload.transaction_id"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Transaction Processing Rate"
    description  = "Rate of transactions processed per minute"
  }
}

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Fraud Detection Alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Alert policy for high fraud rate
resource "google_monitoring_alert_policy" "high_fraud_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Fraud Rate Detected"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High fraud rate condition"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fraud_detection_rate[0].name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 15
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content   = "High fraud rate detected in the fraud detection system. Investigate immediately."
    mime_type = "text/markdown"
  }
}

# Alert policy for processing lag
resource "google_monitoring_alert_policy" "processing_lag" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Transaction Processing Lag"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Processing lag condition"
    
    condition_threshold {
      filter          = "resource.type=\"dataflow_job\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  documentation {
    content   = "Transaction processing is experiencing significant lag. Check Dataflow pipeline health."
    mime_type = "text/markdown"
  }
}

# ============================================================================
# Data Sources for Configuration
# ============================================================================

# Get current Google Cloud configuration
data "google_client_config" "current" {}

# Get default compute service account
data "google_service_account" "compute_default" {
  account_id = "${data.google_client_config.current.project}-compute@developer.gserviceaccount.com"
}
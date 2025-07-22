# High-Frequency Trading Risk Analytics Infrastructure with TPU Ironwood and Cloud Datastream
# This Terraform configuration deploys a complete real-time risk analytics platform
# for high-frequency trading operations using Google Cloud's latest AI and streaming technologies

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming conventions for consistency
  name_prefix = "hft-risk-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment    = var.environment
    project       = "hft-risk-analytics"
    managed-by    = "terraform"
    created-date  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Service account email for Datastream
  datastream_service_account = "service-${data.google_project.current.number}@gcp-sa-datastream.iam.gserviceaccount.com"
}

# Get current project information
data "google_project" "current" {}

# Get available TPU runtime versions for validation
data "google_tpu_v2_runtime_versions" "available" {
  provider = google-beta
  zone     = var.zone
}

# Enable required APIs for the trading analytics platform
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",           # Compute Engine for networking
    "tpu.googleapis.com",              # TPU for AI inference
    "datastream.googleapis.com",       # Datastream for real-time replication
    "bigquery.googleapis.com",         # BigQuery for analytics
    "run.googleapis.com",              # Cloud Run for API services
    "artifactregistry.googleapis.com", # Artifact Registry for containers
    "aiplatform.googleapis.com",       # Vertex AI for ML platform
    "monitoring.googleapis.com",       # Cloud Monitoring
    "logging.googleapis.com",          # Cloud Logging
    "storage.googleapis.com",          # Cloud Storage
    "cloudbuild.googleapis.com",       # Cloud Build for CI/CD
    "secretmanager.googleapis.com",    # Secret Manager for credentials
    "cloudkms.googleapis.com"          # Cloud KMS for encryption
  ])
  
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be enabled
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.required_apis]
  create_duration = "60s"
}

# =============================================================================
# NETWORKING INFRASTRUCTURE
# =============================================================================

# VPC network for the trading analytics infrastructure
resource "google_compute_network" "hft_network" {
  name                    = "${local.name_prefix}-network-${local.name_suffix}"
  auto_create_subnetworks = false
  mtu                     = 1460
  description             = "VPC network for high-frequency trading risk analytics infrastructure"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Subnet for the trading analytics infrastructure
resource "google_compute_subnetwork" "hft_subnet" {
  name          = "${local.name_prefix}-subnet-${local.name_suffix}"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.hft_network.id
  description   = "Subnet for high-frequency trading analytics infrastructure"
  
  # Enable private Google access for accessing Google APIs
  private_ip_google_access = true
  
  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rules for secure access
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal-${local.name_suffix}"
  network = google_compute_network.hft_network.name
  
  description = "Allow internal communication within the VPC"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "8080", "8443"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.subnet_cidr]
  target_tags   = ["hft-internal"]
}

# Firewall rule for TPU communication
resource "google_compute_firewall" "allow_tpu" {
  name    = "${local.name_prefix}-allow-tpu-${local.name_suffix}"
  network = google_compute_network.hft_network.name
  
  description = "Allow TPU communication for machine learning workloads"
  
  allow {
    protocol = "tcp"
    ports    = ["8470-8479"]
  }
  
  source_ranges = [var.tpu_cidr_block]
  target_tags   = ["tpu-worker"]
}

# =============================================================================
# CLOUD STORAGE FOR MODEL ARTIFACTS AND DATA
# =============================================================================

# Cloud Storage bucket for model artifacts and streaming data
resource "google_storage_bucket" "hft_data_bucket" {
  name          = "${local.name_prefix}-data-${local.name_suffix}"
  location      = var.region
  force_destroy = !var.deletion_protection
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM binding for Datastream service account to access the bucket
resource "google_storage_bucket_iam_member" "datastream_bucket_access" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/storage.objectCreator",
    "roles/storage.legacyBucketReader"
  ])
  
  bucket = google_storage_bucket.hft_data_bucket.name
  role   = each.value
  member = "serviceAccount:${local.datastream_service_account}"
}

# =============================================================================
# BIGQUERY ANALYTICS DATA WAREHOUSE
# =============================================================================

# BigQuery dataset for trading analytics
resource "google_bigquery_dataset" "trading_dataset" {
  dataset_id                 = var.trading_dataset_id
  friendly_name              = "High-Frequency Trading Analytics Dataset"
  description                = "Dataset for real-time trading data, risk metrics, and compliance reporting"
  location                   = var.region
  delete_contents_on_destroy = !var.deletion_protection
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Trading positions table schema
resource "google_bigquery_table" "trading_positions" {
  dataset_id          = google_bigquery_dataset.trading_dataset.dataset_id
  table_id            = "trading_positions"
  deletion_protection = var.deletion_protection
  
  description = "Real-time trading positions with risk metrics"
  
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  clustering = ["symbol", "trader_id"]
  
  schema = jsonencode([
    {
      name        = "position_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the trading position"
    },
    {
      name        = "symbol"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Trading symbol or instrument identifier"
    },
    {
      name        = "quantity"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Position quantity (positive for long, negative for short)"
    },
    {
      name        = "price"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Current market price of the position"
    },
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the position was recorded"
    },
    {
      name        = "trader_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Identifier of the trader who holds the position"
    },
    {
      name        = "risk_score"
      type        = "NUMERIC"
      mode        = "NULLABLE"
      description = "Calculated risk score for the position"
    },
    {
      name        = "var_1d"
      type        = "NUMERIC"
      mode        = "NULLABLE"
      description = "1-day Value at Risk calculation"
    },
    {
      name        = "expected_shortfall"
      type        = "NUMERIC"
      mode        = "NULLABLE"
      description = "Expected shortfall (conditional VaR) calculation"
    },
    {
      name        = "created_at"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "Record creation timestamp"
    }
  ])
  
  labels = local.common_labels
}

# Risk metrics table schema
resource "google_bigquery_table" "risk_metrics" {
  dataset_id          = google_bigquery_dataset.trading_dataset.dataset_id
  table_id            = "risk_metrics"
  deletion_protection = var.deletion_protection
  
  description = "Comprehensive risk metrics and calculations"
  
  time_partitioning {
    type  = "DAY"
    field = "calculation_timestamp"
  }
  
  clustering = ["portfolio_id", "metric_type"]
  
  schema = jsonencode([
    {
      name        = "metric_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the risk metric"
    },
    {
      name        = "portfolio_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Portfolio identifier"
    },
    {
      name        = "metric_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of risk metric (VaR, Expected Shortfall, etc.)"
    },
    {
      name        = "metric_value"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Calculated value of the risk metric"
    },
    {
      name        = "calculation_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "When the metric was calculated"
    },
    {
      name        = "confidence_level"
      type        = "NUMERIC"
      mode        = "NULLABLE"
      description = "Confidence level for the metric (e.g., 0.95 for 95%)"
    },
    {
      name        = "time_horizon_days"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Time horizon for the risk calculation in days"
    },
    {
      name        = "created_at"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "Record creation timestamp"
    }
  ])
  
  labels = local.common_labels
}

# Real-time risk dashboard view
resource "google_bigquery_table" "real_time_risk_view" {
  dataset_id = google_bigquery_dataset.trading_dataset.dataset_id
  table_id   = "real_time_risk_dashboard"
  
  description = "Real-time view for risk monitoring dashboard"
  
  view {
    query = <<-EOT
      SELECT 
        trader_id as portfolio_id,
        symbol,
        SUM(quantity * price) as position_value,
        MAX(risk_score) as max_risk_score,
        AVG(var_1d) as avg_var_1d,
        COUNT(*) as position_count,
        MAX(timestamp) as last_update
      FROM `${var.project_id}.${var.trading_dataset_id}.trading_positions`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      GROUP BY trader_id, symbol
    EOT
    
    use_legacy_sql = false
  }
  
  labels = local.common_labels
}

# =============================================================================
# TPU IRONWOOD CLUSTER FOR AI INFERENCE
# =============================================================================

# Service account for TPU operations
resource "google_service_account" "tpu_service_account" {
  account_id   = "${local.name_prefix}-tpu-sa-${local.name_suffix}"
  display_name = "TPU Service Account for HFT Risk Analytics"
  description  = "Service account for TPU Ironwood cluster operations"
}

# IAM roles for TPU service account
resource "google_project_iam_member" "tpu_sa_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.tpu_service_account.email}"
}

# Wait for service account creation to avoid eventual consistency issues
resource "time_sleep" "wait_for_tpu_sa" {
  depends_on      = [google_service_account.tpu_service_account]
  create_duration = "30s"
}

# TPU Ironwood cluster for ultra-low latency AI inference
resource "google_tpu_v2_vm" "ironwood_cluster" {
  provider = google-beta
  
  name        = "${local.name_prefix}-tpu-${local.name_suffix}"
  zone        = var.zone
  description = "TPU Ironwood cluster for high-frequency trading risk analytics"
  
  runtime_version = var.tpu_runtime_version
  
  # TPU Ironwood v6e configuration for optimal inference performance
  accelerator_config {
    type     = "V6E"
    topology = replace(var.tpu_accelerator_type, "v6e-", "")
  }
  
  # Network configuration for optimal performance
  cidr_block = var.tpu_cidr_block
  
  network_config {
    network         = google_compute_network.hft_network.id
    subnetwork      = google_compute_subnetwork.hft_subnet.id
    can_ip_forward  = true
    enable_external_ips = false  # Use private IPs for security
    queue_count     = 32         # Optimize for high-throughput networking
  }
  
  # Service account configuration
  service_account {
    email = google_service_account.tpu_service_account.email
    scope = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  
  # Enable secure boot for enhanced security
  shielded_instance_config {
    enable_secure_boot = true
  }
  
  # Use spot instances for cost optimization in non-production environments
  dynamic "scheduling_config" {
    for_each = var.environment != "prod" ? [1] : []
    content {
      preemptible = true
      spot       = true
    }
  }
  
  labels = local.common_labels
  tags   = ["tpu-worker", "hft-internal"]
  
  depends_on = [
    time_sleep.wait_for_tpu_sa,
    google_compute_subnetwork.hft_subnet,
    google_compute_firewall.allow_tpu
  ]
}

# =============================================================================
# CLOUD DATASTREAM FOR REAL-TIME DATABASE REPLICATION
# =============================================================================

# Datastream connection profile for source database (conditional)
resource "google_datastream_connection_profile" "source_connection_profile" {
  count = var.enable_datastream && var.source_database_host != "" ? 1 : 0
  
  display_name          = "Trading Database Source"
  location              = var.region
  connection_profile_id = "${local.name_prefix}-source-${local.name_suffix}"
  
  # Dynamic source configuration based on database type
  dynamic "mysql_profile" {
    for_each = var.source_database_type == "mysql" ? [1] : []
    content {
      hostname = var.source_database_host
      port     = var.source_database_port
      username = var.source_database_username
      password = var.source_database_password
    }
  }
  
  dynamic "postgresql_profile" {
    for_each = var.source_database_type == "postgresql" ? [1] : []
    content {
      hostname = var.source_database_host
      port     = var.source_database_port
      username = var.source_database_username
      password = var.source_database_password
      database = "postgres"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Datastream connection profile for BigQuery destination
resource "google_datastream_connection_profile" "destination_connection_profile" {
  count = var.enable_datastream ? 1 : 0
  
  display_name          = "BigQuery Analytics Destination"
  location              = var.region
  connection_profile_id = "${local.name_prefix}-dest-${local.name_suffix}"
  
  bigquery_profile {}
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Real-time data stream from trading database to BigQuery
resource "google_datastream_stream" "trading_data_stream" {
  count = var.enable_datastream && var.source_database_host != "" ? 1 : 0
  
  stream_id    = "${local.name_prefix}-stream-${local.name_suffix}"
  location     = var.region
  display_name = "Real-time Trading Data Stream"
  
  # Start the stream in NOT_STARTED state for manual activation
  desired_state = "NOT_STARTED"
  
  source_config {
    source_connection_profile = google_datastream_connection_profile.source_connection_profile[0].id
    
    # Configure source based on database type
    dynamic "mysql_source_config" {
      for_each = var.source_database_type == "mysql" ? [1] : []
      content {
        max_concurrent_cdc_tasks      = 8
        max_concurrent_backfill_tasks = 12
        
        # Include all objects by default (can be customized)
        include_objects {
          mysql_databases {
            database = "trading"
            mysql_tables {
              table = "positions"
            }
            mysql_tables {
              table = "transactions"
            }
            mysql_tables {
              table = "market_data"
            }
          }
        }
      }
    }
    
    dynamic "postgresql_source_config" {
      for_each = var.source_database_type == "postgresql" ? [1] : []
      content {
        max_concurrent_backfill_tasks = 12
        publication                   = "trading_publication"
        replication_slot             = "trading_slot"
        
        include_objects {
          postgresql_schemas {
            schema = "trading"
            postgresql_tables {
              table = "positions"
            }
            postgresql_tables {
              table = "transactions"
            }
            postgresql_tables {
              table = "market_data"
            }
          }
        }
      }
    }
  }
  
  destination_config {
    destination_connection_profile = google_datastream_connection_profile.destination_connection_profile[0].id
    
    bigquery_destination_config {
      data_freshness = var.bigquery_data_freshness
      
      source_hierarchy_datasets {
        dataset_template {
          location = var.region
          
          # Use dataset prefix for organization
          dataset_id_prefix = "hft"
        }
      }
    }
  }
  
  # Configure backfill strategy
  backfill_all {}
  
  labels = local.common_labels
  
  depends_on = [
    google_datastream_connection_profile.source_connection_profile,
    google_datastream_connection_profile.destination_connection_profile,
    google_bigquery_dataset.trading_dataset
  ]
}

# =============================================================================
# CLOUD RUN API SERVICES
# =============================================================================

# Service account for Cloud Run services
resource "google_service_account" "cloud_run_service_account" {
  account_id   = "${local.name_prefix}-run-sa-${local.name_suffix}"
  display_name = "Cloud Run Service Account for Risk Analytics API"
  description  = "Service account for Cloud Run risk analytics API services"
}

# IAM roles for Cloud Run service account
resource "google_project_iam_member" "cloud_run_sa_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
}

# Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_registry" {
  repository_id = "${local.name_prefix}-containers-${local.name_suffix}"
  location      = var.region
  format        = "DOCKER"
  description   = "Container registry for high-frequency trading risk analytics services"
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Run service for risk analytics API
resource "google_cloud_run_v2_service" "risk_analytics_api" {
  name     = "${local.name_prefix}-api-${local.name_suffix}"
  location = var.region
  
  description = "High-frequency trading risk analytics API service"
  
  template {
    service_account = google_service_account.cloud_run_service_account.email
    
    # Configure container specifications for high-performance API
    containers {
      # Placeholder image - will be updated during deployment
      image = "gcr.io/cloudrun/hello"
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      
      # Environment variables for application configuration
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "DATASET_ID"
        value = var.trading_dataset_id
      }
      
      env {
        name  = "TPU_NAME"
        value = google_tpu_v2_vm.ironwood_cluster.name
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      # Health check configuration
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
    
    # Scaling configuration for high-frequency trading loads
    scaling {
      min_instance_count = var.environment == "prod" ? 2 : 0
      max_instance_count = var.environment == "prod" ? 100 : 10
    }
    
    # Network configuration
    vpc_access {
      network_interfaces {
        network    = google_compute_network.hft_network.id
        subnetwork = google_compute_subnetwork.hft_subnet.id
        tags       = ["hft-internal"]
      }
      egress = "PRIVATE_RANGES_ONLY"
    }
    
    # Performance optimization
    max_instance_request_concurrency = var.cloud_run_concurrency
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Timeout configuration for financial calculations
    timeout = "300s"
  }
  
  # Traffic configuration
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_service_account.cloud_run_service_account,
    google_project_iam_member.cloud_run_sa_roles,
    google_tpu_v2_vm.ironwood_cluster
  ]
}

# IAM policy for Cloud Run service access
resource "google_cloud_run_v2_service_iam_binding" "public_access" {
  location = google_cloud_run_v2_service.risk_analytics_api.location
  name     = google_cloud_run_v2_service.risk_analytics_api.name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Monitoring notification channel for alerts
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "HFT Risk Analytics Email Alerts"
  type         = "email"
  
  labels = {
    email_address = "alerts@${var.project_id}.example.com"
  }
  
  description = "Email notifications for high-frequency trading system alerts"
}

# Alert policy for TPU inference latency
resource "google_monitoring_alert_policy" "tpu_latency_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "TPU Inference Latency Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "TPU inference latency exceeds threshold"
    
    condition_threshold {
      filter          = "resource.type=\"tpu_worker\" AND resource.labels.project_id=\"${var.project_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 1.0  # 1 millisecond threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.enable_monitoring ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }
  
  depends_on = [google_tpu_v2_vm.ironwood_cluster]
}

# Alert policy for Cloud Run API response time
resource "google_monitoring_alert_policy" "api_response_time_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "API Response Time Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "API response time exceeds threshold"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.risk_analytics_api.name}\""
      duration        = "120s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 500  # 500ms threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.enable_monitoring ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_cloud_run_v2_service.risk_analytics_api]
}

# Log-based metric for tracking trading errors
resource "google_logging_metric" "trading_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${local.name_prefix}-trading-error-rate-${local.name_suffix}"
  filter = "resource.type=\"cloud_run_revision\" AND severity=\"ERROR\" AND jsonPayload.component=\"trading-system\""
  
  description = "Rate of errors in the trading system"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "1"
    
    labels {
      key         = "error_type"
      value_type  = "STRING"
      description = "Type of trading error"
    }
  }
  
  label_extractors = {
    error_type = "EXTRACT(jsonPayload.error_type)"
  }
}

# =============================================================================
# SECURITY AND ENCRYPTION
# =============================================================================

# KMS keyring for customer-managed encryption
resource "google_kms_key_ring" "hft_keyring" {
  count = var.enable_encryption ? 1 : 0
  
  name     = "${local.name_prefix}-keyring-${local.name_suffix}"
  location = var.region
  
  depends_on = [time_sleep.wait_for_apis]
}

# KMS key for encrypting sensitive trading data
resource "google_kms_crypto_key" "hft_encryption_key" {
  count = var.enable_encryption ? 1 : 0
  
  name     = "${local.name_prefix}-encryption-key-${local.name_suffix}"
  key_ring = google_kms_key_ring.hft_keyring[0].id
  purpose  = "ENCRYPT_DECRYPT"
  
  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
  
  labels = local.common_labels
}

# IAM binding for Datastream service account to use KMS key
resource "google_kms_crypto_key_iam_member" "datastream_key_user" {
  count = var.enable_encryption && var.enable_datastream ? 1 : 0
  
  crypto_key_id = google_kms_crypto_key.hft_encryption_key[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.datastream_service_account}"
}

# IAM binding for BigQuery service account to use KMS key
data "google_bigquery_default_service_account" "bq_sa" {
  count = var.enable_encryption ? 1 : 0
}

resource "google_kms_crypto_key_iam_member" "bigquery_key_user" {
  count = var.enable_encryption ? 1 : 0
  
  crypto_key_id = google_kms_crypto_key.hft_encryption_key[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_bigquery_default_service_account.bq_sa[0].email}"
}
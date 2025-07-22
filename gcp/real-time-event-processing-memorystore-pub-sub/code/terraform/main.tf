# ==============================================================================
# Real-Time Event Processing with Cloud Memorystore and Pub/Sub
# ==============================================================================
# This Terraform configuration deploys a complete real-time event processing
# solution using Cloud Memorystore for Redis, Pub/Sub for messaging, Cloud 
# Functions for serverless processing, and BigQuery for analytics.
# ==============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "redis.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "networkconnectivity.googleapis.com",
    "vpcaccess.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service            = each.value
  disable_on_destroy = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# ==============================================================================
# Networking Infrastructure
# ==============================================================================

# VPC Network for secure communication between services
resource "google_compute_network" "event_processing_vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
  description            = "VPC network for event processing infrastructure"

  depends_on = [google_project_service.required_apis]
}

# Primary subnet for application resources
resource "google_compute_subnetwork" "main_subnet" {
  name          = "${var.prefix}-main-subnet"
  ip_cidr_range = var.main_subnet_cidr
  region        = var.region
  network       = google_compute_network.event_processing_vpc.id
  description   = "Main subnet for event processing resources"
  
  # Enable private Google access for serverless resources
  private_ip_google_access = true
  
  # Log subnet flow for security monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Dedicated subnet for VPC Access Connector (required for Cloud Functions)
resource "google_compute_subnetwork" "connector_subnet" {
  name          = "${var.prefix}-connector-subnet"
  ip_cidr_range = var.connector_subnet_cidr
  region        = var.region
  network       = google_compute_network.event_processing_vpc.id
  description   = "Subnet for VPC Access Connector"
  
  private_ip_google_access = true
}

# ==============================================================================
# Cloud Memorystore for Redis - In-Memory Cache
# ==============================================================================

# Service Connection Policy required for new Memorystore instances
resource "google_network_connectivity_service_connection_policy" "memorystore_policy" {
  name          = "${var.prefix}-memorystore-policy"
  location      = var.region
  service_class = "gcp-memorystore"
  description   = "Service connection policy for Cloud Memorystore access"
  network       = google_compute_network.event_processing_vpc.id
  
  psc_config {
    subnetworks = [google_compute_subnetwork.main_subnet.id]
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Memorystore Redis instance for sub-millisecond data access
resource "google_memorystore_instance" "redis_cache" {
  instance_id = "${var.prefix}-redis-cache"
  shard_count = var.redis_shard_count
  location    = var.region

  # Network configuration for secure private access
  desired_auto_created_endpoints {
    network    = google_compute_network.event_processing_vpc.id
    project_id = var.project_id
  }

  # Performance and scaling configuration
  replica_count = var.redis_replica_count
  node_type     = var.redis_node_type
  
  # Security settings - configure based on requirements
  authorization_mode      = var.redis_auth_enabled ? "IAM_AUTH" : "AUTH_DISABLED"
  transit_encryption_mode = var.redis_encryption_enabled ? "SERVER_AUTHENTICATION" : "TRANSIT_ENCRYPTION_DISABLED"
  
  # Engine configuration for optimal caching performance
  engine_version = "VALKEY_7_2"
  engine_configs = {
    maxmemory-policy = "allkeys-lru"  # LRU eviction for cache workloads
  }

  # Zone distribution for high availability
  zone_distribution_config {
    mode = var.redis_multi_zone ? "MULTI_ZONE" : "SINGLE_ZONE"
    zone = var.redis_multi_zone ? null : "${var.region}-a"
  }

  # Maintenance window configuration
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  # Persistence configuration for data durability
  dynamic "persistence_config" {
    for_each = var.redis_persistence_enabled ? [1] : []
    content {
      mode = "RDB"
      rdb_config {
        rdb_snapshot_period     = "SIX_HOURS"
        rdb_snapshot_start_time = formatdate("RFC3339", timestamp())
      }
    }
  }

  deletion_protection_enabled = var.deletion_protection

  # Resource dependencies
  depends_on = [
    google_network_connectivity_service_connection_policy.memorystore_policy
  ]

  labels = merge(var.labels, {
    component = "cache"
    service   = "memorystore"
  })
}

# ==============================================================================
# Pub/Sub - Event Messaging System
# ==============================================================================

# Main topic for event ingestion
resource "google_pubsub_topic" "events_topic" {
  name = "${var.prefix}-events-topic"

  # Message retention for reliability
  message_retention_duration = var.pubsub_message_retention

  # Geographic restrictions for data residency
  message_storage_policy {
    allowed_persistence_regions = [var.region]
    enforce_in_transit          = true
  }

  labels = merge(var.labels, {
    component = "messaging"
    service   = "pubsub"
  })

  depends_on = [google_project_service.required_apis]
}

# Subscription for Cloud Functions trigger
resource "google_pubsub_subscription" "events_subscription" {
  name  = "${var.prefix}-events-subscription"
  topic = google_pubsub_topic.events_topic.id

  # Message acknowledgment settings
  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  message_retention_duration = var.pubsub_subscription_retention
  retain_acked_messages      = false

  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = var.pubsub_max_delivery_attempts
  }

  # Enable exactly-once delivery for data consistency
  enable_exactly_once_delivery = true

  labels = merge(var.labels, {
    component = "messaging"
    service   = "pubsub"
  })
}

# Dead letter topic for failed message handling
resource "google_pubsub_topic" "dead_letter_topic" {
  name = "${var.prefix}-dead-letter-topic"

  message_retention_duration = "604800s" # 7 days

  labels = merge(var.labels, {
    component = "messaging"
    service   = "pubsub"
    purpose   = "dead-letter"
  })
}

# ==============================================================================
# BigQuery - Analytics Data Warehouse
# ==============================================================================

# Dataset for storing processed events
resource "google_bigquery_dataset" "event_analytics" {
  dataset_id    = "${replace(var.prefix, "-", "_")}_event_analytics"
  friendly_name = "Event Analytics Dataset"
  description   = "Dataset for storing and analyzing processed events"
  location      = var.bigquery_location

  # Data lifecycle management
  default_table_expiration_ms = var.bigquery_table_expiration_ms

  # Access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.function_sa.email
  }

  access {
    role   = "READER"
    domain = var.organization_domain
  }

  labels = merge(var.labels, {
    component = "analytics"
    service   = "bigquery"
  })

  depends_on = [google_project_service.required_apis]
}

# Table for processed events with optimized schema
resource "google_bigquery_table" "processed_events" {
  dataset_id = google_bigquery_dataset.event_analytics.dataset_id
  table_id   = "processed_events"

  # Schema definition for event data
  schema = jsonencode([
    {
      name        = "event_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique event identifier"
    },
    {
      name        = "user_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "User identifier"
    },
    {
      name        = "event_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of event (login, purchase, etc.)"
    },
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Event timestamp in UTC"
    },
    {
      name        = "source"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Event source (web, mobile, api)"
    },
    {
      name        = "metadata"
      type        = "JSON"
      mode        = "NULLABLE"
      description = "Additional event metadata"
    },
    {
      name        = "processing_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "When the event was processed"
    }
  ])

  # Time partitioning for query performance and cost optimization
  time_partitioning {
    type          = "DAY"
    field         = "timestamp"
    expiration_ms = var.bigquery_partition_expiration_ms
  }

  # Clustering for better query performance
  clustering = ["event_type", "user_id"]

  deletion_protection = var.deletion_protection

  labels = merge(var.labels, {
    component = "analytics"
    service   = "bigquery"
    table     = "events"
  })
}

# ==============================================================================
# Cloud Storage - Function Source Code
# ==============================================================================

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-${var.prefix}-function-source"
  location = var.region

  # Security configuration
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Versioning for source code management
  versioning {
    enabled = true
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(var.labels, {
    component = "storage"
    service   = "gcs"
    purpose   = "function-source"
  })

  depends_on = [google_project_service.required_apis]
}

# Placeholder source code archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${formatdate("YYYY-MM-DD-hhmm", timestamp())}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  # Content hash for change detection
  content_type = "application/zip"
}

# ==============================================================================
# VPC Access Connector - Cloud Functions Networking
# ==============================================================================

# VPC Access Connector for Cloud Functions to access Redis privately
resource "google_vpc_access_connector" "function_connector" {
  name = "${var.prefix}-function-connector"
  
  # Use dedicated subnet for better control
  subnet {
    name       = google_compute_subnetwork.connector_subnet.name
    project_id = var.project_id
  }

  # Instance configuration for connector
  machine_type  = var.vpc_connector_machine_type
  min_instances = var.vpc_connector_min_instances
  max_instances = var.vpc_connector_max_instances

  region = var.region

  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# Service Accounts & IAM - Security Configuration
# ==============================================================================

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${var.prefix}-function-sa"
  display_name = "Event Processing Function Service Account"
  description  = "Service account for event processing Cloud Functions"
}

# IAM binding for BigQuery data editor
resource "google_bigquery_dataset_iam_member" "function_bigquery_editor" {
  dataset_id = google_bigquery_dataset.event_analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Pub/Sub subscriber
resource "google_pubsub_subscription_iam_member" "function_pubsub_subscriber" {
  subscription = google_pubsub_subscription.events_subscription.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Functions invoker
resource "google_project_iam_member" "function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for monitoring metric writer
resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# ==============================================================================
# Cloud Functions - Serverless Event Processing
# ==============================================================================

# Cloud Function for processing events
resource "google_cloudfunctions2_function" "event_processor" {
  name        = "${var.prefix}-event-processor"
  location    = var.region
  description = "Processes events from Pub/Sub and caches in Redis"

  # Build configuration
  build_config {
    runtime     = "python312"
    entry_point = "process_event"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  # Service configuration
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = var.function_min_instances
    available_memory                = var.function_memory
    timeout_seconds                 = var.function_timeout_seconds
    max_instance_request_concurrency = var.function_concurrency
    available_cpu                   = var.function_cpu

    # VPC access for Redis connectivity
    vpc_connector                 = google_vpc_access_connector.function_connector.id
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
    
    # Security settings
    ingress_settings          = "ALLOW_INTERNAL_ONLY"
    service_account_email     = google_service_account.function_sa.email
    all_traffic_on_latest_revision = true

    # Environment variables
    environment_variables = {
      PROJECT_ID        = var.project_id
      REDIS_HOST        = google_memorystore_instance.redis_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address
      REDIS_PORT        = "6379"
      BIGQUERY_DATASET  = google_bigquery_dataset.event_analytics.dataset_id
      BIGQUERY_TABLE    = google_bigquery_table.processed_events.table_id
      CACHE_TTL_SECONDS = tostring(var.redis_cache_ttl_seconds)
    }
  }

  # Event trigger configuration
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic         = google_pubsub_topic.events_topic.id
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email
  }

  labels = merge(var.labels, {
    component = "processing"
    service   = "cloud-functions"
  })

  depends_on = [
    google_project_service.required_apis,
    google_bigquery_dataset_iam_member.function_bigquery_editor,
    google_pubsub_subscription_iam_member.function_pubsub_subscriber
  ]
}

# ==============================================================================
# Cloud Monitoring - Observability & Alerting
# ==============================================================================

# Log-based metric for monitoring event processing rate
resource "google_logging_metric" "event_processing_rate" {
  name   = "${var.prefix}-event-processing-rate"
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.event_processor.name}\" AND textPayload:\"Event processed successfully\""

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Event Processing Rate"
  }

  label_extractors = {
    user_id    = "EXTRACT(textPayload)"
    event_type = "EXTRACT(textPayload)"
  }
}

# Alerting policy for high error rate
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "${var.prefix} High Error Rate Alert"
  combiner     = "OR"
  enabled      = var.monitoring_enabled

  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.event_processor.name}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.error_rate_threshold
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "Alert triggered when Cloud Function error rate exceeds ${var.error_rate_threshold}%"
  }

  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# Firewall Rules - Network Security
# ==============================================================================

# Allow internal communication within VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.prefix}-allow-internal"
  network = google_compute_network.event_processing_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "6379"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.main_subnet_cidr, var.connector_subnet_cidr]
  target_tags   = ["event-processing"]

  description = "Allow internal communication for event processing"
}

# Allow egress to Google APIs
resource "google_compute_firewall" "allow_google_apis" {
  name      = "${var.prefix}-allow-google-apis"
  network   = google_compute_network.event_processing_vpc.name
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = ["199.36.153.8/30"]
  target_tags        = ["event-processing"]

  description = "Allow egress to Google APIs"
}
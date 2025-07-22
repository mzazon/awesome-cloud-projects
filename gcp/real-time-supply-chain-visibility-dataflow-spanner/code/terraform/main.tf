# ============================================================================
# Real-Time Supply Chain Visibility Infrastructure
# ============================================================================
# This Terraform configuration creates a complete supply chain visibility platform
# using Cloud Dataflow, Cloud Spanner, Pub/Sub, and BigQuery for real-time
# event processing and analytics.

# ============================================================================
# Random Resources for Unique Naming
# ============================================================================

resource "random_id" "resource_suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and tagging
  resource_suffix = random_id.resource_suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
  
  # Derived resource names
  spanner_instance_name  = "${var.environment}-supply-chain-instance-${local.resource_suffix}"
  storage_bucket_name    = "${var.project_id}-${var.storage_bucket_name}-${local.resource_suffix}"
  service_account_id     = "${var.environment}-supply-chain-sa-${local.resource_suffix}"
  dataflow_job_name      = "${var.dataflow_job_name}-${local.resource_suffix}"
}

# ============================================================================
# Google Cloud APIs
# ============================================================================

resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "compute.googleapis.com",
    "dataflow.googleapis.com",
    "spanner.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
  ]) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ============================================================================
# Service Account for Dataflow and Application Services
# ============================================================================

resource "google_service_account" "supply_chain_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = "Service account for supply chain visibility platform"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "supply_chain_sa_roles" {
  for_each = var.create_service_accounts ? toset([
    "roles/dataflow.worker",
    "roles/dataflow.admin",
    "roles/spanner.databaseUser",
    "roles/spanner.databaseReader",
    "roles/spanner.databaseAdmin",
    "roles/pubsub.subscriber",
    "roles/pubsub.publisher",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.supply_chain_sa[0].email}"
  
  depends_on = [google_service_account.supply_chain_sa]
}

# ============================================================================
# Cloud Storage Bucket for Dataflow Staging and Temporary Files
# ============================================================================

resource "google_storage_bucket" "dataflow_staging" {
  name          = local.storage_bucket_name
  location      = var.storage_bucket_location
  storage_class = var.storage_bucket_storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Prevent accidental deletion
  force_destroy = var.auto_delete_buckets
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 7 # Delete objects older than 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for important staging files
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# Cloud Spanner Instance and Database
# ============================================================================

resource "google_spanner_instance" "supply_chain_instance" {
  name             = local.spanner_instance_name
  config           = var.spanner_instance_config
  display_name     = "Supply Chain Visibility Database Instance"
  project          = var.project_id
  edition          = var.spanner_edition
  force_destroy    = !var.enable_spanner_deletion_protection
  
  # Use either node count or processing units, but not both
  num_nodes        = var.spanner_processing_units == null ? var.spanner_node_count : null
  processing_units = var.spanner_processing_units
  
  # Enable automatic backups for production workloads
  default_backup_schedule_type = var.environment == "prod" ? "AUTOMATIC" : "NONE"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

resource "google_spanner_database" "supply_chain_database" {
  instance = google_spanner_instance.supply_chain_instance.name
  name     = var.spanner_database_name
  project  = var.project_id
  
  # Database schema for supply chain data
  ddl = [
    # Shipments table for tracking shipment information
    <<-EOT
    CREATE TABLE Shipments (
      ShipmentId STRING(50) NOT NULL,
      OrderId STRING(50) NOT NULL,
      CarrierId STRING(50),
      TrackingNumber STRING(100),
      Status STRING(20) NOT NULL,
      OriginLocation STRING(100),
      DestinationLocation STRING(100),
      EstimatedDelivery TIMESTAMP,
      ActualDelivery TIMESTAMP,
      LastUpdated TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
      CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
    ) PRIMARY KEY (ShipmentId)
    EOT
    ,
    # Inventory table for tracking inventory levels
    <<-EOT
    CREATE TABLE Inventory (
      ItemId STRING(50) NOT NULL,
      LocationId STRING(50) NOT NULL,
      Quantity INT64 NOT NULL,
      AvailableQuantity INT64 NOT NULL,
      ReservedQuantity INT64 NOT NULL,
      LastUpdated TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
    ) PRIMARY KEY (ItemId, LocationId)
    EOT
    ,
    # Events table for logging all supply chain events
    <<-EOT
    CREATE TABLE Events (
      EventId STRING(50) NOT NULL,
      ShipmentId STRING(50),
      EventType STRING(50) NOT NULL,
      EventData JSON,
      Location STRING(100),
      Timestamp TIMESTAMP NOT NULL,
      ProcessedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
    ) PRIMARY KEY (EventId)
    EOT
    ,
    # Secondary index for efficient event queries by shipment
    <<-EOT
    CREATE INDEX EventsByShipment ON Events(ShipmentId, Timestamp)
    EOT
    ,
    # Secondary index for efficient event queries by type
    <<-EOT
    CREATE INDEX EventsByType ON Events(EventType, Timestamp)
    EOT
  ]
  
  # Enable database deletion protection in production
  deletion_protection = var.enable_spanner_deletion_protection
  
  depends_on = [google_spanner_instance.supply_chain_instance]
}

# ============================================================================
# Cloud Pub/Sub Topic and Subscription
# ============================================================================

resource "google_pubsub_topic" "logistics_events" {
  name    = var.pubsub_topic_name
  project = var.project_id
  
  # Message retention for event replay capability
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "logistics_events_subscription" {
  name    = var.pubsub_subscription_name
  topic   = google_pubsub_topic.logistics_events.name
  project = var.project_id
  
  # Acknowledgment deadline for message processing
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Message retention for unprocessed messages
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter topic for failed messages (optional)
  # dead_letter_policy {
  #   dead_letter_topic = google_pubsub_topic.logistics_events_dead_letter.id
  #   max_delivery_attempts = 5
  # }
  
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.logistics_events]
}

# ============================================================================
# BigQuery Dataset and Tables for Analytics
# ============================================================================

resource "google_bigquery_dataset" "supply_chain_analytics" {
  dataset_id  = var.bigquery_dataset_name
  location    = var.bigquery_dataset_location
  project     = var.project_id
  description = "Supply chain analytics dataset for real-time insights"
  
  # Table expiration settings
  default_table_expiration_ms = var.bigquery_table_expiration_days > 0 ? var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000 : null
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Shipment analytics table
resource "google_bigquery_table" "shipment_analytics" {
  dataset_id  = google_bigquery_dataset.supply_chain_analytics.dataset_id
  table_id    = "shipment_analytics"
  project     = var.project_id
  description = "Shipment analytics table for supply chain insights"
  
  # Table schema for shipment analytics
  schema = jsonencode([
    {
      name = "shipment_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the shipment"
    },
    {
      name = "order_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Order identifier associated with the shipment"
    },
    {
      name = "carrier_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Carrier handling the shipment"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Current status of the shipment"
    },
    {
      name = "origin"
      type = "STRING"
      mode = "NULLABLE"
      description = "Origin location of the shipment"
    },
    {
      name = "destination"
      type = "STRING"
      mode = "NULLABLE"
      description = "Destination location of the shipment"
    },
    {
      name = "estimated_delivery"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Estimated delivery timestamp"
    },
    {
      name = "actual_delivery"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Actual delivery timestamp"
    },
    {
      name = "transit_time_hours"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Transit time in hours"
    },
    {
      name = "created_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date the shipment was created"
    }
  ])
  
  # Partition by created date for efficient querying
  time_partitioning {
    type  = "DAY"
    field = "created_date"
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.supply_chain_analytics]
}

# Event analytics table with partitioning
resource "google_bigquery_table" "event_analytics" {
  dataset_id  = google_bigquery_dataset.supply_chain_analytics.dataset_id
  table_id    = "event_analytics"
  project     = var.project_id
  description = "Event analytics table for supply chain event processing"
  
  # Table schema for event analytics
  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the event"
    },
    {
      name = "shipment_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Shipment identifier associated with the event"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of supply chain event"
    },
    {
      name = "location"
      type = "STRING"
      mode = "NULLABLE"
      description = "Location where the event occurred"
    },
    {
      name = "event_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the event occurred"
    },
    {
      name = "processing_delay_seconds"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Delay between event occurrence and processing"
    }
  ])
  
  # Partition by event timestamp for efficient querying
  time_partitioning {
    type  = "DAY"
    field = "event_timestamp"
  }
  
  # Clustering for better query performance
  clustering = ["event_type", "shipment_id"]
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.supply_chain_analytics]
}

# ============================================================================
# Cloud Dataflow Flex Template Job
# ============================================================================

# Note: This resource creates a Dataflow job from a Flex Template
# In practice, you would need to build and deploy the Dataflow pipeline
# as a Flex Template first, then reference it here.

# For this example, we'll create a placeholder that demonstrates the configuration
# The actual Dataflow job would be deployed using the gcloud command or
# through a CI/CD pipeline after the Flex Template is built.

resource "google_dataflow_flex_template_job" "supply_chain_streaming" {
  # Only create the job if explicitly enabled (set to false by default)
  count = 0 # Set to 1 to enable Dataflow job creation
  
  name     = local.dataflow_job_name
  project  = var.project_id
  region   = var.region
  
  container_spec_gcs_path = "gs://${google_storage_bucket.dataflow_staging.name}/templates/supply-chain-streaming-template.json"
  
  parameters = {
    inputSubscription = google_pubsub_subscription.logistics_events_subscription.id
    spannerInstanceId = google_spanner_instance.supply_chain_instance.name
    spannerDatabaseId = google_spanner_database.supply_chain_database.name
    bigQueryDataset   = google_bigquery_dataset.supply_chain_analytics.dataset_id
    bigQueryTable     = google_bigquery_table.event_analytics.table_id
    tempLocation      = "gs://${google_storage_bucket.dataflow_staging.name}/temp"
    stagingLocation   = "gs://${google_storage_bucket.dataflow_staging.name}/staging"
  }
  
  # Dataflow job configuration
  labels                  = local.common_labels
  network                 = var.dataflow_network
  subnetwork              = var.dataflow_subnetwork
  service_account_email   = var.dataflow_service_account_email != null ? var.dataflow_service_account_email : google_service_account.supply_chain_sa[0].email
  machine_type            = var.dataflow_machine_type
  max_workers             = var.dataflow_max_workers
  num_workers             = var.dataflow_num_workers
  disk_size_gb            = var.dataflow_disk_size_gb
  enable_streaming_engine = true
  
  # Use preemptible instances for cost optimization if enabled
  additional_experiments = var.preemptible_dataflow_workers ? ["use_runner_v2", "enable_streaming_engine"] : ["use_runner_v2"]
  
  depends_on = [
    google_storage_bucket.dataflow_staging,
    google_spanner_database.supply_chain_database,
    google_pubsub_subscription.logistics_events_subscription,
    google_bigquery_table.event_analytics,
    google_service_account.supply_chain_sa
  ]
}

# ============================================================================
# Cloud Monitoring Alerts and Dashboards
# ============================================================================

# Monitoring alert for Dataflow job failures
resource "google_monitoring_alert_policy" "dataflow_job_failed" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Dataflow Job Failed - Supply Chain"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Dataflow job failed"
    
    condition_threshold {
      filter          = "resource.type=\"dataflow_job\" AND resource.labels.job_name=\"${local.dataflow_job_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Notification channels would be configured here
  # notification_channels = [var.notification_channel_id]
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring alert for Spanner high CPU usage
resource "google_monitoring_alert_policy" "spanner_high_cpu" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Spanner High CPU Usage"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Spanner CPU usage above 80%"
    
    condition_threshold {
      filter          = "resource.type=\"spanner_instance\" AND resource.labels.instance_id=\"${google_spanner_instance.supply_chain_instance.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  depends_on = [google_spanner_instance.supply_chain_instance]
}

# ============================================================================
# Cloud Logging Configuration
# ============================================================================

# Log sink for Dataflow job logs
resource "google_logging_project_sink" "dataflow_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "dataflow-supply-chain-logs"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.supply_chain_analytics.dataset_id}"
  
  filter = <<-EOT
    resource.type="dataflow_job"
    resource.labels.job_name="${local.dataflow_job_name}"
  EOT
  
  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_bigquery_dataset.supply_chain_analytics]
}

# Grant BigQuery Data Editor role to log sink writer
resource "google_bigquery_dataset_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  dataset_id = google_bigquery_dataset.supply_chain_analytics.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.dataflow_logs[0].writer_identity
  
  depends_on = [google_logging_project_sink.dataflow_logs]
}
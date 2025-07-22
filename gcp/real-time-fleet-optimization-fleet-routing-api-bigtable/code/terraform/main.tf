# ============================================================================
# Real-Time Fleet Optimization with Cloud Fleet Routing API and Cloud Bigtable
# ============================================================================
# This Terraform configuration deploys a complete real-time fleet optimization 
# system using Google Cloud services including Cloud Bigtable for historical 
# traffic data, Pub/Sub for real-time event processing, Cloud Functions for 
# data processing and route optimization, and integrates with Google's Fleet 
# Routing API for advanced route optimization algorithms.

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# ============================================================================
# API Enablement
# ============================================================================
# Enable required Google Cloud APIs for the fleet optimization platform

resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigtable.googleapis.com",           # Cloud Bigtable for traffic data storage
    "pubsub.googleapis.com",             # Pub/Sub for real-time messaging
    "cloudfunctions.googleapis.com",     # Cloud Functions for processing
    "cloudbuild.googleapis.com",         # Cloud Build for function deployment
    "eventarc.googleapis.com",           # Eventarc for event-driven architecture
    "run.googleapis.com",                # Cloud Run (required for Cloud Functions 2nd gen)
    "apikeys.googleapis.com",            # API Keys for Maps Platform integration
    "secretmanager.googleapis.com",      # Secret Manager for secure API key storage
    "optimization.googleapis.com",       # Optimization AI (Fleet Routing API)
    "routes.googleapis.com",             # Routes API for routing calculations
    "cloudkms.googleapis.com",           # Cloud KMS for encryption
    "monitoring.googleapis.com",         # Cloud Monitoring for observability
    "logging.googleapis.com"             # Cloud Logging for audit trails
  ])

  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ============================================================================
# KMS Configuration for Encryption
# ============================================================================
# Create KMS keyring and keys for encrypting sensitive data

resource "google_kms_key_ring" "fleet_optimization" {
  name     = "fleet-optimization-${random_id.suffix.hex}"
  location = var.region

  depends_on = [google_project_service.required_apis]
}

resource "google_kms_crypto_key" "bigtable_key" {
  name     = "bigtable-encryption-key"
  key_ring = google_kms_key_ring.fleet_optimization.id
  purpose  = "ENCRYPT_DECRYPT"

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# Cloud Storage for Function Source Code
# ============================================================================
# Create storage bucket for Cloud Functions source code deployment

resource "google_storage_bucket" "function_source" {
  name                        = "fleet-optimization-functions-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy              = true

  # Enable versioning for source code history
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

  labels = {
    environment = var.environment
    application = "fleet-optimization"
    component   = "function-source"
  }

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# Cloud Bigtable Configuration
# ============================================================================
# Deploy Cloud Bigtable instance with autoscaling for storing historical 
# traffic patterns and real-time vehicle location data

resource "google_bigtable_instance" "fleet_data" {
  name         = "fleet-data-${random_id.suffix.hex}"
  display_name = "Fleet Optimization Data Store"

  # Enable deletion protection for production workloads
  deletion_protection = var.environment == "production" ? true : false

  # Primary cluster with autoscaling for high-performance traffic data queries
  cluster {
    cluster_id   = "main-cluster"
    zone         = var.zone
    storage_type = "SSD"

    # Autoscaling configuration optimized for real-time queries
    autoscaling_config {
      min_nodes      = var.bigtable_min_nodes
      max_nodes      = var.bigtable_max_nodes
      cpu_target     = 70
      storage_target = 4000  # 4TB storage target for SSD
    }

    # Encrypt data at rest using customer-managed encryption keys
    kms_key_name = google_kms_crypto_key.bigtable_key.id
  }

  # Optional replica cluster for high availability and disaster recovery
  dynamic "cluster" {
    for_each = var.enable_bigtable_replication ? [1] : []
    content {
      cluster_id   = "replica-cluster"
      zone         = var.replica_zone
      storage_type = "SSD"

      autoscaling_config {
        min_nodes      = 1
        max_nodes      = 5
        cpu_target     = 70
        storage_target = 2000
      }

      kms_key_name = google_kms_crypto_key.bigtable_key.id
    }
  }

  labels = {
    environment = var.environment
    application = "fleet-optimization"
    component   = "data-storage"
    cost-center = "logistics"
  }

  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key.bigtable_key
  ]
}

# Create Bigtable table for storing historical traffic patterns
resource "google_bigtable_table" "traffic_patterns" {
  name          = "traffic_patterns"
  instance_name = google_bigtable_instance.fleet_data.name

  # Column families optimized for time-series traffic data
  column_family {
    family = "traffic_speed"
  }

  column_family {
    family = "traffic_volume"
  }

  column_family {
    family = "road_conditions"
  }

  # Garbage collection policy to manage data lifecycle (30 days retention)
  column_family {
    family = "metadata"
  }
}

# Create table for real-time vehicle location tracking
resource "google_bigtable_table" "vehicle_locations" {
  name          = "vehicle_locations"
  instance_name = google_bigtable_instance.fleet_data.name

  # Column families for location and status data
  column_family {
    family = "location"
  }

  column_family {
    family = "status"
  }

  column_family {
    family = "route_info"
  }
}

# Create table for optimized route storage and historical analysis
resource "google_bigtable_table" "route_history" {
  name          = "route_history"
  instance_name = google_bigtable_instance.fleet_data.name

  column_family {
    family = "route_data"
  }

  column_family {
    family = "performance_metrics"
  }

  column_family {
    family = "optimization_params"
  }
}

# ============================================================================
# Pub/Sub Configuration for Real-Time Event Processing
# ============================================================================
# Create Pub/Sub topics and subscriptions for real-time fleet event processing

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name = "fleet-dead-letter-${random_id.suffix.hex}"

  message_retention_duration = "604800s" # 7 days

  labels = {
    component = "error-handling"
  }

  depends_on = [google_project_service.required_apis]
}

# Schema for vehicle location updates
resource "google_pubsub_schema" "vehicle_location_schema" {
  name = "vehicle-location-schema-${random_id.suffix.hex}"
  type = "AVRO"

  definition = jsonencode({
    type = "record"
    name = "VehicleLocation"
    fields = [
      {
        name = "vehicle_id"
        type = "string"
      },
      {
        name = "latitude"
        type = "double"
      },
      {
        name = "longitude"
        type = "double"
      },
      {
        name = "timestamp"
        type = "long"
      },
      {
        name = "speed"
        type = ["null", "double"]
        default = null
      },
      {
        name = "heading"
        type = ["null", "double"]
        default = null
      },
      {
        name = "road_segment"
        type = ["null", "string"]
        default = null
      }
    ]
  })

  depends_on = [google_project_service.required_apis]
}

# Topic for fleet events (vehicle locations, traffic updates)
resource "google_pubsub_topic" "fleet_events" {
  name = "fleet-events-${random_id.suffix.hex}"

  # Retention for event replay capability
  message_retention_duration = "604800s" # 7 days

  # Geographic message storage policy for compliance
  message_storage_policy {
    allowed_persistence_regions = [
      var.region,
      var.backup_region
    ]
    enforce_in_transit = true
  }

  # Schema validation for data quality
  schema_settings {
    schema   = google_pubsub_schema.vehicle_location_schema.id
    encoding = "JSON"
  }

  labels = {
    component = "fleet-tracking"
    data-type = "location"
  }

  depends_on = [google_project_service.required_apis]
}

# Topic for route optimization requests
resource "google_pubsub_topic" "route_optimization_requests" {
  name = "route-optimization-requests-${random_id.suffix.hex}"

  message_retention_duration = "86400s" # 24 hours

  labels = {
    component = "route-optimization"
    data-type = "requests"
  }

  depends_on = [google_project_service.required_apis]
}

# Topic for optimized route results
resource "google_pubsub_topic" "optimized_routes" {
  name = "optimized-routes-${random_id.suffix.hex}"

  message_retention_duration = "259200s" # 3 days

  labels = {
    component = "route-optimization"
    data-type = "results"
  }

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# Service Accounts and IAM Configuration
# ============================================================================
# Create service accounts with least privilege access for each component

# Service account for location processing function
resource "google_service_account" "location_processor" {
  account_id   = "location-processor-${random_id.suffix.hex}"
  display_name = "Fleet Location Processor Service Account"
  description  = "Service account for processing vehicle location updates"
}

# Service account for route optimization function
resource "google_service_account" "route_optimizer" {
  account_id   = "route-optimizer-${random_id.suffix.hex}"
  display_name = "Fleet Route Optimizer Service Account"
  description  = "Service account for route optimization using Fleet Routing API"
}

# Service account for function builds
resource "google_service_account" "function_builder" {
  account_id   = "function-builder-${random_id.suffix.hex}"
  display_name = "Function Builder Service Account"
  description  = "Service account for building Cloud Functions"
}

# Service account for dashboard function
resource "google_service_account" "dashboard" {
  account_id   = "fleet-dashboard-${random_id.suffix.hex}"
  display_name = "Fleet Dashboard Service Account"
  description  = "Service account for fleet management dashboard"
}

# Service account for Pub/Sub to invoke functions
resource "google_service_account" "pubsub_invoker" {
  account_id   = "pubsub-invoker-${random_id.suffix.hex}"
  display_name = "Pub/Sub Function Invoker"
  description  = "Service account for Pub/Sub to invoke Cloud Functions"
}

# ============================================================================
# IAM Role Bindings for Location Processor
# ============================================================================

# Bigtable access for location processor
resource "google_bigtable_instance_iam_member" "location_processor_bigtable" {
  instance = google_bigtable_instance.fleet_data.name
  role     = "roles/bigtable.user"
  member   = "serviceAccount:${google_service_account.location_processor.email}"
}

# Pub/Sub subscription access for location processor
resource "google_pubsub_subscription_iam_member" "location_processor_subscriber" {
  subscription = google_pubsub_subscription.location_processor.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.location_processor.email}"
}

# ============================================================================
# IAM Role Bindings for Route Optimizer
# ============================================================================

# Bigtable access for route optimizer
resource "google_bigtable_instance_iam_member" "route_optimizer_bigtable" {
  instance = google_bigtable_instance.fleet_data.name
  role     = "roles/bigtable.user"
  member   = "serviceAccount:${google_service_account.route_optimizer.email}"
}

# Pub/Sub publisher role for route optimizer
resource "google_pubsub_topic_iam_member" "route_optimizer_publisher" {
  topic  = google_pubsub_topic.optimized_routes.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.route_optimizer.email}"
}

# Maps Platform API access for route optimizer
resource "google_project_iam_member" "route_optimizer_maps" {
  role   = "roles/serviceusage.serviceUsageConsumer"
  member = "serviceAccount:${google_service_account.route_optimizer.email}"
}

# ============================================================================
# Secret Manager Configuration
# ============================================================================
# Store API keys securely using Secret Manager

resource "google_secret_manager_secret" "maps_api_key" {
  secret_id = "maps-api-key-${random_id.suffix.hex}"

  replication {
    auto {}
  }

  labels = {
    component = "api-keys"
    service   = "maps-platform"
  }

  depends_on = [google_project_service.required_apis]
}

# IAM for secret access by route optimizer
resource "google_secret_manager_secret_iam_member" "route_optimizer_secret" {
  secret_id = google_secret_manager_secret.maps_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.route_optimizer.email}"
}

# ============================================================================
# Pub/Sub Subscriptions with Error Handling
# ============================================================================

# Subscription for location processing with dead letter queue
resource "google_pubsub_subscription" "location_processor" {
  name  = "location-processor-sub-${random_id.suffix.hex}"
  topic = google_pubsub_topic.fleet_events.name

  # Optimized for real-time processing
  ack_deadline_seconds = 20

  # Dead letter policy for error handling
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  # Exponential backoff retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Message ordering for vehicle location updates
  enable_message_ordering = true

  labels = {
    component = "location-processing"
  }

  depends_on = [google_project_service.required_apis]
}

# Subscription for route optimization requests
resource "google_pubsub_subscription" "route_optimizer" {
  name  = "route-optimizer-sub-${random_id.suffix.hex}"
  topic = google_pubsub_topic.route_optimization_requests.name

  ack_deadline_seconds = 60 # Longer timeout for optimization calculations

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 3
  }

  retry_policy {
    minimum_backoff = "15s"
    maximum_backoff = "900s"
  }

  labels = {
    component = "route-optimization"
  }

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# Cloud Functions for Data Processing and Route Optimization
# ============================================================================

# Create placeholder source code archives for Cloud Functions
data "archive_file" "location_processor_source" {
  type        = "zip"
  output_path = "/tmp/location-processor-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/location_processor.py", {
      project_id       = var.project_id
      bigtable_instance = google_bigtable_instance.fleet_data.name
      traffic_table    = google_bigtable_table.traffic_patterns.name
      location_table   = google_bigtable_table.vehicle_locations.name
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "route_optimizer_source" {
  type        = "zip"
  output_path = "/tmp/route-optimizer-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/route_optimizer.py", {
      project_id        = var.project_id
      bigtable_instance = google_bigtable_instance.fleet_data.name
      traffic_table     = google_bigtable_table.traffic_patterns.name
      route_table       = google_bigtable_table.route_history.name
      maps_secret       = google_secret_manager_secret.maps_api_key.secret_id
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "location_processor_source" {
  name   = "location-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.location_processor_source.output_path

  lifecycle {
    replace_triggered_by = [
      data.archive_file.location_processor_source
    ]
  }
}

resource "google_storage_bucket_object" "route_optimizer_source" {
  name   = "route-optimizer-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.route_optimizer_source.output_path

  lifecycle {
    replace_triggered_by = [
      data.archive_file.route_optimizer_source
    ]
  }
}

# Cloud Function for processing vehicle location updates
resource "google_cloudfunctions2_function" "location_processor" {
  name        = "location-processor-${random_id.suffix.hex}"
  location    = var.region
  description = "Process vehicle location updates and store in Bigtable"

  build_config {
    runtime     = "python312"
    entry_point = "process_location"

    environment_variables = {
      GOOGLE_CLOUD_PROJECT = var.project_id
    }

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.location_processor_source.name
      }
    }

    service_account = google_service_account.function_builder.id
  }

  service_config {
    # Resource allocation optimized for data processing
    available_memory                 = "1Gi"
    available_cpu                    = "1"
    timeout_seconds                  = 60
    max_instance_count              = var.max_function_instances
    min_instance_count              = 2
    max_instance_request_concurrency = 10

    # Environment variables for Bigtable integration
    environment_variables = {
      BIGTABLE_INSTANCE_ID = google_bigtable_instance.fleet_data.name
      TRAFFIC_TABLE        = google_bigtable_table.traffic_patterns.name
      LOCATION_TABLE       = google_bigtable_table.vehicle_locations.name
      PROJECT_ID           = var.project_id
    }

    service_account_email = google_service_account.location_processor.email
    ingress_settings      = "ALLOW_INTERNAL_ONLY"

    # Use latest revision for automatic updates
    all_traffic_on_latest_revision = true
  }

  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic         = google_pubsub_topic.fleet_events.id
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.pubsub_invoker.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.location_processor_source
  ]
}

# Cloud Function for route optimization using Fleet Routing API
resource "google_cloudfunctions2_function" "route_optimizer" {
  name        = "route-optimizer-${random_id.suffix.hex}"
  location    = var.region
  description = "Optimize fleet routes using Google Cloud Fleet Routing API"

  build_config {
    runtime     = "python312"
    entry_point = "optimize_routes"

    environment_variables = {
      GOOGLE_CLOUD_PROJECT = var.project_id
    }

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.route_optimizer_source.name
      }
    }

    service_account = google_service_account.function_builder.id
  }

  service_config {
    # Higher resource allocation for CPU-intensive route optimization
    available_memory                 = "4Gi"
    available_cpu                    = "2"
    timeout_seconds                  = 540
    max_instance_count              = var.max_function_instances
    min_instance_count              = 1
    max_instance_request_concurrency = 5

    environment_variables = {
      BIGTABLE_INSTANCE_ID = google_bigtable_instance.fleet_data.name
      TRAFFIC_TABLE        = google_bigtable_table.traffic_patterns.name
      ROUTE_TABLE          = google_bigtable_table.route_history.name
      PROJECT_ID           = var.project_id
      OPTIMIZATION_ENDPOINT = "https://routeoptimization.googleapis.com/v1"
    }

    # Secret environment variable for Maps API key
    secret_environment_variables {
      key        = "MAPS_API_KEY"
      project_id = var.project_id
      secret     = google_secret_manager_secret.maps_api_key.secret_id
      version    = "latest"
    }

    service_account_email = google_service_account.route_optimizer.email
    ingress_settings      = "ALLOW_INTERNAL_ONLY"

    all_traffic_on_latest_revision = true
  }

  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic         = google_pubsub_topic.route_optimization_requests.id
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.pubsub_invoker.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.route_optimizer_source
  ]
}

# ============================================================================
# Fleet Management Dashboard Function
# ============================================================================

# Create dashboard function source code
data "archive_file" "dashboard_source" {
  type        = "zip"
  output_path = "/tmp/dashboard-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/dashboard.py", {
      project_id        = var.project_id
      bigtable_instance = google_bigtable_instance.fleet_data.name
      traffic_table     = google_bigtable_table.traffic_patterns.name
      location_table    = google_bigtable_table.vehicle_locations.name
      route_table       = google_bigtable_table.route_history.name
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/function_templates/dashboard_requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "dashboard_source" {
  name   = "dashboard-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.dashboard_source.output_path

  lifecycle {
    replace_triggered_by = [
      data.archive_file.dashboard_source
    ]
  }
}

# Fleet management dashboard HTTP function
resource "google_cloudfunctions2_function" "dashboard" {
  name        = "fleet-dashboard-${random_id.suffix.hex}"
  location    = var.region
  description = "Fleet management dashboard for real-time monitoring"

  build_config {
    runtime     = "python312"
    entry_point = "fleet_dashboard"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.dashboard_source.name
      }
    }

    service_account = google_service_account.function_builder.id
  }

  service_config {
    available_memory               = "1Gi"
    available_cpu                  = "1"
    timeout_seconds                = 60
    max_instance_count            = 10
    min_instance_count            = 1
    max_instance_request_concurrency = 20

    environment_variables = {
      BIGTABLE_INSTANCE_ID = google_bigtable_instance.fleet_data.name
      TRAFFIC_TABLE        = google_bigtable_table.traffic_patterns.name
      LOCATION_TABLE       = google_bigtable_table.vehicle_locations.name
      ROUTE_TABLE          = google_bigtable_table.route_history.name
      PROJECT_ID           = var.project_id
    }

    service_account_email = google_service_account.dashboard.email
    
    # Allow external access for dashboard
    ingress_settings = var.dashboard_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"

    all_traffic_on_latest_revision = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.dashboard_source
  ]
}

# IAM binding for dashboard Bigtable access
resource "google_bigtable_instance_iam_member" "dashboard_bigtable" {
  instance = google_bigtable_instance.fleet_data.name
  role     = "roles/bigtable.reader"
  member   = "serviceAccount:${google_service_account.dashboard.email}"
}

# IAM binding to allow unauthenticated access to dashboard (if enabled)
resource "google_cloudfunctions2_function_iam_member" "dashboard_public_access" {
  count = var.dashboard_public_access ? 1 : 0

  location       = google_cloudfunctions2_function.dashboard.location
  cloud_function = google_cloudfunctions2_function.dashboard.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ============================================================================
# Monitoring and Alerting Configuration
# ============================================================================

# Log-based metric for monitoring function errors
resource "google_logging_metric" "function_errors" {
  name   = "fleet_optimization_function_errors"
  filter = <<-EOF
    resource.type="cloud_function"
    resource.labels.function_name=~"location-processor-.*|route-optimizer-.*|fleet-dashboard-.*"
    severity>=ERROR
  EOF

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Fleet Optimization Function Errors"
  }

  label_extractors = {
    "function_name" = "EXTRACT(resource.labels.function_name)"
  }
}

# Alerting policy for function errors
resource "google_monitoring_alert_policy" "function_error_alert" {
  display_name = "Fleet Optimization Function Errors"
  combiner     = "OR"

  conditions {
    display_name = "Function error rate too high"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/fleet_optimization_function_errors\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s" # 24 hours
  }

  enabled = var.enable_monitoring_alerts
}

# ============================================================================
# Data Lifecycle Management
# ============================================================================

# Scheduler job for data cleanup and optimization
resource "google_cloud_scheduler_job" "data_cleanup" {
  count = var.enable_data_cleanup ? 1 : 0

  name             = "fleet-data-cleanup-${random_id.suffix.hex}"
  description      = "Clean up old traffic data and optimize Bigtable performance"
  schedule         = "0 2 * * *" # Daily at 2 AM
  time_zone        = "UTC"
  attempt_deadline = "320s"

  pubsub_target {
    topic_name = google_pubsub_topic.route_optimization_requests.id
    data = base64encode(jsonencode({
      action = "cleanup"
      retention_days = var.data_retention_days
    }))
  }

  depends_on = [google_project_service.required_apis]
}
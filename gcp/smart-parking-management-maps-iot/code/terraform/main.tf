# Smart Parking Management - Main Terraform Configuration
# Deploys a complete IoT parking management system on Google Cloud Platform
# including Pub/Sub, Cloud Functions, Firestore, and Maps Platform integration

# ================================================================================
# RANDOM RESOURCE GENERATION
# ================================================================================

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
  prefix      = "${var.project_name}-${var.environment}-"
}

# Generate random password for potential database encryption
resource "random_password" "encryption_key" {
  length  = 32
  special = true
}

# ================================================================================
# GOOGLE CLOUD APIs ENABLEMENT
# ================================================================================

# Enable required Google Cloud APIs for the smart parking system
resource "google_project_service" "required_apis" {
  for_each = toset([
    "pubsub.googleapis.com",           # Pub/Sub for message queuing
    "cloudfunctions.googleapis.com",   # Cloud Functions for serverless processing
    "firestore.googleapis.com",        # Firestore for NoSQL database
    "maps-backend.googleapis.com",     # Maps Platform for location services
    "cloudbuild.googleapis.com",       # Cloud Build for function deployment
    "logging.googleapis.com",          # Cloud Logging for centralized logs
    "monitoring.googleapis.com",       # Cloud Monitoring for metrics
    "secretmanager.googleapis.com",    # Secret Manager for secure storage
    "cloudresourcemanager.googleapis.com" # Resource Manager for project management
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental disabling of APIs
  disable_dependent_services = false
  disable_on_destroy         = false

  depends_on = []
}

# ================================================================================
# IAM SERVICE ACCOUNTS
# ================================================================================

# Service account for MQTT broker to publish messages to Pub/Sub
resource "google_service_account" "mqtt_publisher" {
  account_id   = "${var.mqtt_service_account_name}-${random_id.suffix.hex}"
  display_name = var.mqtt_service_account_display_name
  description  = "Service account for MQTT broker to publish parking sensor data to Pub/Sub"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Functions with minimal required permissions
resource "google_service_account" "cloud_functions" {
  account_id   = "parking-functions-${random_id.suffix.hex}"
  display_name = "Smart Parking Cloud Functions"
  description  = "Service account for parking management Cloud Functions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# ================================================================================
# IAM ROLE BINDINGS
# ================================================================================

# Grant Pub/Sub publisher role to MQTT service account
resource "google_project_iam_member" "mqtt_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.mqtt_publisher.email}"

  depends_on = [google_service_account.mqtt_publisher]
}

# Grant Firestore user role to Cloud Functions service account
resource "google_project_iam_member" "functions_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_functions.email}"

  depends_on = [google_service_account.cloud_functions]
}

# Grant Cloud Functions invoker role for API function
resource "google_project_iam_member" "functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.cloud_functions.email}"

  depends_on = [google_service_account.cloud_functions]
}

# Grant logging writer role to service accounts
resource "google_project_iam_member" "mqtt_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mqtt_publisher.email}"

  depends_on = [google_service_account.mqtt_publisher]
}

resource "google_project_iam_member" "functions_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_functions.email}"

  depends_on = [google_service_account.cloud_functions]
}

# ================================================================================
# SERVICE ACCOUNT KEY GENERATION
# ================================================================================

# Create service account key for MQTT broker authentication (if enabled)
resource "google_service_account_key" "mqtt_key" {
  count              = var.create_service_account_key ? 1 : 0
  service_account_id = google_service_account.mqtt_publisher.name
  public_key_type    = "TYPE_X509_PEM_FILE"

  depends_on = [google_service_account.mqtt_publisher]
}

# Store service account key in Secret Manager for secure access
resource "google_secret_manager_secret" "mqtt_key" {
  count     = var.create_service_account_key ? 1 : 0
  project   = var.project_id
  secret_id = "mqtt-service-account-key-${random_id.suffix.hex}"

  labels = merge(var.labels, {
    component = "mqtt-authentication"
    purpose   = "service-account-key"
  })

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Store the actual key value in Secret Manager
resource "google_secret_manager_secret_version" "mqtt_key" {
  count       = var.create_service_account_key ? 1 : 0
  secret      = google_secret_manager_secret.mqtt_key[0].id
  secret_data = base64decode(google_service_account_key.mqtt_key[0].private_key)

  depends_on = [google_secret_manager_secret.mqtt_key]
}

# ================================================================================
# PUB/SUB INFRASTRUCTURE
# ================================================================================

# Pub/Sub topic for receiving parking sensor data from MQTT brokers
resource "google_pubsub_topic" "parking_events" {
  name    = "${var.pubsub_topic_name}-${random_id.suffix.hex}"
  project = var.project_id

  labels = merge(var.labels, {
    component = "messaging"
    purpose   = "sensor-data-ingestion"
  })

  # Configure message storage policy for compliance and data residency
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  # Enable message ordering for sequential sensor updates if needed
  enable_message_ordering = false

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for Cloud Function processing
resource "google_pubsub_subscription" "parking_processing" {
  name    = "${var.pubsub_subscription_name}-${random_id.suffix.hex}"
  topic   = google_pubsub_topic.parking_events.name
  project = var.project_id

  labels = merge(var.labels, {
    component = "messaging"
    purpose   = "function-trigger"
  })

  # Configure acknowledgment deadline for message processing
  ack_deadline_seconds = var.pubsub_ack_deadline

  # Configure message retention for unprocessed messages
  message_retention_duration = var.pubsub_message_retention_duration

  # Configure retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  # Configure dead letter policy for permanently failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.parking_events_dlq.id
    max_delivery_attempts = 5
  }

  # Enable exactly-once delivery for critical parking updates
  enable_exactly_once_delivery = true

  depends_on = [google_pubsub_topic.parking_events]
}

# Dead letter queue for failed message processing
resource "google_pubsub_topic" "parking_events_dlq" {
  name    = "${var.pubsub_topic_name}-dlq-${random_id.suffix.hex}"
  project = var.project_id

  labels = merge(var.labels, {
    component = "messaging"
    purpose   = "dead-letter-queue"
  })

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  depends_on = [google_project_service.required_apis]
}

# ================================================================================
# FIRESTORE DATABASE
# ================================================================================

# Firestore database for storing parking space data and zone statistics
resource "google_firestore_database" "parking_data" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location_id
  type        = var.firestore_database_type

  # Configure point-in-time recovery for data protection
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"

  # Configure deletion protection for production environments
  deletion_policy = var.environment == "prod" ? "DELETE_PROTECTION_ENABLED" : "ABANDON"

  depends_on = [google_project_service.required_apis]
}

# ================================================================================
# CLOUD STORAGE FOR FUNCTION SOURCE CODE
# ================================================================================

# Storage bucket for Cloud Function deployment packages
resource "google_storage_bucket" "function_source" {
  name     = "parking-functions-source-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  labels = merge(var.labels, {
    component = "storage"
    purpose   = "function-deployment"
  })

  # Configure versioning for function deployment history
  versioning {
    enabled = true
  }

  # Configure lifecycle management to reduce storage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Configure uniform bucket-level access for security
  uniform_bucket_level_access = true

  # Prevent accidental deletion
  force_destroy = var.environment != "prod"

  depends_on = [google_project_service.required_apis]
}

# ================================================================================
# CLOUD FUNCTION SOURCE CODE PREPARATION
# ================================================================================

# Create parking data processor function source code
data "template_file" "parking_processor_source" {
  template = file("${path.module}/functions/parking-processor/index.js")
  vars = {
    parking_spaces_collection = var.parking_spaces_collection
    parking_zones_collection  = var.parking_zones_collection
    project_id               = var.project_id
  }
}

# Create parking data processor package.json
data "template_file" "parking_processor_package" {
  template = file("${path.module}/functions/parking-processor/package.json")
  vars = {
    function_name = var.parking_processor_function_name
  }
}

# Create parking API function source code
data "template_file" "parking_api_source" {
  template = file("${path.module}/functions/parking-api/index.js")
  vars = {
    parking_spaces_collection = var.parking_spaces_collection
    parking_zones_collection  = var.parking_zones_collection
    project_id               = var.project_id
  }
}

# Create parking API package.json
data "template_file" "parking_api_package" {
  template = file("${path.module}/functions/parking-api/package.json")
  vars = {
    function_name = var.parking_api_function_name
  }
}

# Archive parking data processor function
data "archive_file" "parking_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/parking-processor-${random_id.suffix.hex}.zip"
  
  source {
    content  = data.template_file.parking_processor_source.rendered
    filename = "index.js"
  }
  
  source {
    content  = data.template_file.parking_processor_package.rendered
    filename = "package.json"
  }
}

# Archive parking API function
data "archive_file" "parking_api_zip" {
  type        = "zip"
  output_path = "${path.module}/parking-api-${random_id.suffix.hex}.zip"
  
  source {
    content  = data.template_file.parking_api_source.rendered
    filename = "index.js"
  }
  
  source {
    content  = data.template_file.parking_api_package.rendered
    filename = "package.json"
  }
}

# Upload parking processor function source to Cloud Storage
resource "google_storage_bucket_object" "parking_processor_source" {
  name   = "parking-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.parking_processor_zip.output_path

  depends_on = [google_storage_bucket.function_source]
}

# Upload parking API function source to Cloud Storage
resource "google_storage_bucket_object" "parking_api_source" {
  name   = "parking-api-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.parking_api_zip.output_path

  depends_on = [google_storage_bucket.function_source]
}

# ================================================================================
# CLOUD FUNCTIONS DEPLOYMENT
# ================================================================================

# Cloud Function for processing parking sensor data from Pub/Sub
resource "google_cloudfunctions2_function" "parking_processor" {
  name     = "${var.parking_processor_function_name}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  description = "Processes parking sensor data from Pub/Sub and updates Firestore"

  labels = merge(var.labels, {
    component = "processing"
    purpose   = "sensor-data-processing"
  })

  build_config {
    runtime     = var.function_runtime
    entry_point = "processParkingData"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.parking_processor_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.cloud_functions.email

    environment_variables = {
      PROJECT_ID                = var.project_id
      PARKING_SPACES_COLLECTION = var.parking_spaces_collection
      PARKING_ZONES_COLLECTION  = var.parking_zones_collection
      ENVIRONMENT              = var.environment
    }

    # Configure VPC access if private networking is required
    dynamic "vpc_connector" {
      for_each = var.enable_private_google_access ? [1] : []
      content {
        name = google_vpc_access_connector.functions_connector[0].id
      }
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.parking_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_storage_bucket_object.parking_processor_source,
    google_service_account.cloud_functions,
    google_project_iam_member.functions_firestore_user
  ]
}

# Cloud Function for parking management REST API
resource "google_cloudfunctions2_function" "parking_api" {
  name     = "${var.parking_api_function_name}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  description = "REST API for parking space search and zone statistics"

  labels = merge(var.labels, {
    component = "api"
    purpose   = "parking-management-api"
  })

  build_config {
    runtime     = var.function_runtime
    entry_point = "parkingApi"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.parking_api_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.cloud_functions.email

    environment_variables = {
      PROJECT_ID                = var.project_id
      PARKING_SPACES_COLLECTION = var.parking_spaces_collection
      PARKING_ZONES_COLLECTION  = var.parking_zones_collection
      ENVIRONMENT              = var.environment
    }

    # Configure ingress settings for API access
    ingress_settings = var.enable_api_authentication ? "ALLOW_INTERNAL_ONLY" : "ALLOW_ALL"

    # Configure VPC access if private networking is required
    dynamic "vpc_connector" {
      for_each = var.enable_private_google_access ? [1] : []
      content {
        name = google_vpc_access_connector.functions_connector[0].id
      }
    }
  }

  depends_on = [
    google_storage_bucket_object.parking_api_source,
    google_service_account.cloud_functions,
    google_project_iam_member.functions_firestore_user
  ]
}

# IAM binding to allow public access to parking API function (if authentication is disabled)
resource "google_cloudfunctions2_function_iam_member" "parking_api_invoker" {
  count          = var.enable_api_authentication ? 0 : 1
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.parking_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.parking_api]
}

# ================================================================================
# GOOGLE MAPS PLATFORM API KEY
# ================================================================================

# API key for Google Maps Platform services
resource "google_apikeys_key" "maps_api" {
  name         = "${lower(replace(var.maps_api_key_name, " ", "-"))}-${random_id.suffix.hex}"
  display_name = "${var.maps_api_key_name} (${title(var.environment)})"
  project      = var.project_id

  # Configure API restrictions for security
  restrictions {
    api_targets {
      service = "maps-backend.googleapis.com"
      methods = [
        "GET /maps/api/geocode/*",
        "GET /maps/api/place/*",
        "GET /maps/api/distancematrix/*",
        "GET /maps/api/directions/*"
      ]
    }

    dynamic "browser_key_restrictions" {
      for_each = var.enable_maps_api_restrictions ? [1] : []
      content {
        allowed_referrers = var.maps_allowed_referrers
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# ================================================================================
# VPC NETWORKING (OPTIONAL)
# ================================================================================

# VPC network for private communication (if enabled)
resource "google_compute_network" "parking_vpc" {
  count                   = var.enable_private_google_access ? 1 : 0
  name                    = "parking-vpc-${random_id.suffix.hex}"
  project                 = var.project_id
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Subnet for Cloud Functions VPC connector
resource "google_compute_subnetwork" "functions_subnet" {
  count         = var.enable_private_google_access ? 1 : 0
  name          = "functions-subnet-${random_id.suffix.hex}"
  project       = var.project_id
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.parking_vpc[0].id

  # Enable Private Google Access for API connectivity
  private_ip_google_access = true

  # Enable flow logs if configured
  dynamic "log_config" {
    for_each = var.enable_vpc_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }

  depends_on = [google_compute_network.parking_vpc]
}

# VPC connector for Cloud Functions to access VPC resources
resource "google_vpc_access_connector" "functions_connector" {
  count         = var.enable_private_google_access ? 1 : 0
  name          = "functions-connector-${random_id.suffix.hex}"
  project       = var.project_id
  region        = var.region
  ip_cidr_range = "10.1.0.0/28"
  network       = google_compute_network.parking_vpc[0].name

  # Configure connector scaling
  min_throughput = 200
  max_throughput = 300

  depends_on = [
    google_compute_network.parking_vpc,
    google_project_service.required_apis
  ]
}

# ================================================================================
# CLOUD MONITORING AND ALERTING
# ================================================================================

# Notification channel for alerts (email-based)
resource "google_monitoring_notification_channel" "email_alerts" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Smart Parking Email Alerts"
  project      = var.project_id
  type         = "email"

  labels = {
    email_address = "admin@example.com" # Replace with actual email
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for high Pub/Sub message backlog
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Parking Pub/Sub Message Backlog Alert"
  project      = var.project_id

  conditions {
    display_name = "Pub/Sub subscription has high message backlog"
    
    condition_threshold {
      filter         = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.parking_processing.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 1000

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_alerts[0].id]

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_subscription.parking_processing
  ]
}

# Alert policy for Cloud Function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Parking Cloud Function Error Rate Alert"
  project      = var.project_id

  conditions {
    display_name = "Cloud Function error rate is high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.parking_processor_function_name}.*|${var.parking_api_function_name}.*\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.labels.function_name"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_alerts[0].id]

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.parking_processor,
    google_cloudfunctions2_function.parking_api
  ]
}
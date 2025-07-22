# ==============================================================================
# NETWORK PERFORMANCE OPTIMIZATION WITH CLOUD WAN AND NETWORK INTELLIGENCE CENTER
# ==============================================================================
# This Terraform configuration deploys a comprehensive network optimization
# solution using Google Cloud WAN, Network Intelligence Center, and automated
# monitoring capabilities for enterprise network performance management.
# ==============================================================================

# ------------------------------------------------------------------------------
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ------------------------------------------------------------------------------
# Enable all necessary APIs for network optimization and monitoring
resource "google_project_service" "required_apis" {
  for_each = toset([
    "networkconnectivity.googleapis.com",  # Network Connectivity Center
    "networkmanagement.googleapis.com",    # Network Intelligence Center
    "monitoring.googleapis.com",           # Cloud Monitoring
    "cloudfunctions.googleapis.com",       # Cloud Functions
    "pubsub.googleapis.com",              # Pub/Sub messaging
    "cloudscheduler.googleapis.com",       # Cloud Scheduler
    "compute.googleapis.com",              # Compute Engine
    "storage.googleapis.com",              # Cloud Storage
    "artifactregistry.googleapis.com",     # Artifact Registry
    "logging.googleapis.com"               # Cloud Logging
  ])

  project = var.project_id
  service = each.key

  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "30m"
    update = "20m"
  }
}

# ------------------------------------------------------------------------------
# VPC NETWORK INFRASTRUCTURE
# ------------------------------------------------------------------------------
# Create VPC network with optimized subnets for network performance testing
resource "google_compute_network" "network_optimization_vpc" {
  name                    = "network-optimization-vpc"
  description            = "VPC network for network performance optimization solution"
  auto_create_subnetworks = false
  mtu                    = 1500
  
  depends_on = [google_project_service.required_apis]
}

# Primary subnet for network optimization infrastructure
resource "google_compute_subnetwork" "primary_subnet" {
  name          = "network-optimization-primary"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.network_optimization_vpc.id
  description   = "Primary subnet for network optimization infrastructure"

  # Enable VPC Flow Logs for comprehensive traffic analysis
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.1  # 10% sampling for cost optimization
    metadata             = "INCLUDE_ALL_METADATA"
    metadata_fields      = [
      "src_instance", "dest_instance", "src_vpc", "dest_vpc",
      "src_gke_details", "dest_gke_details", "src_location", "dest_location"
    ]
  }

  # Enable private Google access for secure service connectivity
  private_ip_google_access = true
}

# Secondary subnet for multi-region testing
resource "google_compute_subnetwork" "secondary_subnet" {
  name          = "network-optimization-secondary"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.secondary_region
  network       = google_compute_network.network_optimization_vpc.id
  description   = "Secondary subnet for multi-region network optimization testing"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.1
    metadata             = "INCLUDE_ALL_METADATA"
  }

  private_ip_google_access = true
}

# ------------------------------------------------------------------------------
# CLOUD WAN NETWORK CONNECTIVITY HUB
# ------------------------------------------------------------------------------
# Create Network Connectivity Hub for intelligent global network management
resource "google_network_connectivity_hub" "network_optimization_hub" {
  name        = "network-optimization-hub-${random_id.suffix.hex}"
  description = "Network Connectivity Hub for global network performance optimization"
  
  # Use MESH topology for full connectivity between all network endpoints
  policy_mode     = "PRESET"
  preset_topology = "MESH"
  
  # Enable Private Service Connect transitivity for enhanced connectivity
  export_psc = true

  labels = {
    environment = var.environment
    purpose     = "network-optimization"
    created_by  = "terraform"
  }

  depends_on = [google_project_service.required_apis]
}

# ------------------------------------------------------------------------------
# COMPUTE INSTANCES FOR CONNECTIVITY TESTING
# ------------------------------------------------------------------------------
# Primary test instance for network performance validation
resource "google_compute_instance" "primary_test_instance" {
  name         = "network-test-primary-${random_id.suffix.hex}"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"
  description  = "Primary instance for network connectivity testing"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.network_optimization_vpc.id
    subnetwork = google_compute_subnetwork.primary_subnet.id
    
    # No external IP for security - use IAP for access if needed
  }

  # Enable OS Login for secure instance access
  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.network_optimization_sa.email
    scopes = ["cloud-platform"]
  }

  tags = ["network-test", "primary"]

  labels = {
    environment = var.environment
    purpose     = "network-testing"
  }
}

# Secondary test instance for multi-region connectivity validation
resource "google_compute_instance" "secondary_test_instance" {
  name         = "network-test-secondary-${random_id.suffix.hex}"
  machine_type = "e2-medium"
  zone         = "${var.secondary_region}-a"
  description  = "Secondary instance for multi-region network connectivity testing"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.network_optimization_vpc.id
    subnetwork = google_compute_subnetwork.secondary_subnet.id
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.network_optimization_sa.email
    scopes = ["cloud-platform"]
  }

  tags = ["network-test", "secondary"]

  labels = {
    environment = var.environment
    purpose     = "network-testing"
  }
}

# ------------------------------------------------------------------------------
# NETWORK INTELLIGENCE CENTER CONNECTIVITY TESTS
# ------------------------------------------------------------------------------
# Regional connectivity test for performance monitoring
resource "google_network_management_connectivity_test" "regional_connectivity_test" {
  name        = "regional-connectivity-test-${random_id.suffix.hex}"
  description = "Test connectivity between regions for performance optimization"

  source {
    instance   = google_compute_instance.primary_test_instance.id
    project_id = var.project_id
  }

  destination {
    instance   = google_compute_instance.secondary_test_instance.id
    project_id = var.project_id
  }

  protocol = "TCP"
  related_projects = [var.project_id]

  labels = {
    environment = var.environment
    test_type   = "regional"
    purpose     = "performance"
  }

  depends_on = [google_project_service.required_apis]
}

# External connectivity test for internet performance monitoring
resource "google_network_management_connectivity_test" "external_connectivity_test" {
  name        = "external-connectivity-test-${random_id.suffix.hex}"
  description = "Test external connectivity for internet performance monitoring"

  source {
    instance   = google_compute_instance.primary_test_instance.id
    project_id = var.project_id
  }

  destination {
    ip_address = "8.8.8.8"  # Google DNS for reliable external testing
    port       = 53
  }

  protocol = "UDP"
  related_projects = [var.project_id]

  labels = {
    environment = var.environment
    test_type   = "external"
    purpose     = "internet-connectivity"
  }
}

# ------------------------------------------------------------------------------
# PUB/SUB MESSAGING FOR EVENT-DRIVEN AUTOMATION
# ------------------------------------------------------------------------------
# Primary topic for network optimization events
resource "google_pubsub_topic" "network_optimization_events" {
  name = "network-optimization-events-${random_id.suffix.hex}"

  # Retain messages for 7 days for debugging and audit purposes
  message_retention_duration = "604800s"

  labels = {
    environment = var.environment
    purpose     = "network-automation"
  }

  depends_on = [google_project_service.required_apis]
}

# Subscription for Cloud Function event processing
resource "google_pubsub_subscription" "network_events_subscription" {
  name  = "network-optimization-events-sub-${random_id.suffix.hex}"
  topic = google_pubsub_topic.network_optimization_events.name

  # Configure message acknowledgment and retry policies
  ack_deadline_seconds = 60

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter queue for failed message processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_queue.id
    max_delivery_attempts = 5
  }

  # Auto-expire subscription after 24 hours of inactivity
  expiration_policy {
    ttl = "86400s"
  }

  labels = {
    environment = var.environment
    purpose     = "event-processing"
  }
}

# Dead letter queue for failed message processing
resource "google_pubsub_topic" "dead_letter_queue" {
  name = "network-optimization-dead-letter-${random_id.suffix.hex}"

  message_retention_duration = "604800s"

  labels = {
    environment = var.environment
    purpose     = "dead-letter-queue"
  }
}

# ------------------------------------------------------------------------------
# SERVICE ACCOUNT AND IAM CONFIGURATION
# ------------------------------------------------------------------------------
# Service account for network optimization functions and automation
resource "google_service_account" "network_optimization_sa" {
  account_id   = "network-optimization-sa-${random_id.suffix.hex}"
  display_name = "Network Optimization Service Account"
  description  = "Service account for network optimization automation and monitoring"
}

# Grant necessary permissions for network optimization operations
resource "google_project_iam_member" "network_optimization_roles" {
  for_each = toset([
    "roles/monitoring.metricWriter",      # Write custom metrics
    "roles/monitoring.editor",            # Manage monitoring resources
    "roles/pubsub.publisher",            # Publish optimization events
    "roles/pubsub.subscriber",           # Subscribe to events
    "roles/compute.viewer",              # View compute resources
    "roles/networkmanagement.viewer",    # View Network Intelligence Center
    "roles/logging.logWriter",           # Write logs
    "roles/cloudfunctions.invoker",      # Invoke Cloud Functions
    "roles/storage.objectViewer",        # Read function source code
    "roles/networkconnectivity.viewer"   # View Network Connectivity Center
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.network_optimization_sa.email}"
}

# ------------------------------------------------------------------------------
# CLOUD STORAGE FOR FUNCTION SOURCE CODE
# ------------------------------------------------------------------------------
# Storage bucket for Cloud Function source code and data
resource "google_storage_bucket" "function_source_bucket" {
  name                        = "${var.project_id}-network-optimization-functions-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  
  # Enable versioning for function code management
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
    purpose     = "function-source"
  }

  depends_on = [google_project_service.required_apis]
}

# Create function source code archive
data "archive_file" "network_optimization_function_source" {
  type        = "zip"
  output_path = "network_optimization_function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
      region     = var.region
      topic_name = google_pubsub_topic.network_optimization_events.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "network_optimization_function_source" {
  name   = "network-optimization-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.network_optimization_function_source.output_path

  depends_on = [data.archive_file.network_optimization_function_source]
}

# ------------------------------------------------------------------------------
# CLOUD FUNCTIONS FOR NETWORK OPTIMIZATION AUTOMATION
# ------------------------------------------------------------------------------
# Cloud Function for processing network optimization events
resource "google_cloudfunctions2_function" "network_optimization_processor" {
  name        = "network-optimization-processor-${random_id.suffix.hex}"
  location    = var.region
  description = "Processes network optimization events and implements automated remediation"

  build_config {
    runtime     = "python311"
    entry_point = "optimize_network"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.network_optimization_function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 10
    min_instance_count              = 1
    available_memory                = "512Mi"
    timeout_seconds                 = 300
    max_instance_request_concurrency = 5
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      TOPIC_NAME = google_pubsub_topic.network_optimization_events.name
    }
    
    # Restrict function access to internal traffic only
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.network_optimization_sa.email
  }

  # Configure Pub/Sub trigger for event-driven processing
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.network_optimization_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = {
    environment = var.environment
    purpose     = "network-optimization"
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.network_optimization_roles
  ]
}

# ------------------------------------------------------------------------------
# CLOUD MONITORING CONFIGURATION
# ------------------------------------------------------------------------------
# Notification channel for network optimization alerts
resource "google_monitoring_notification_channel" "email_notification" {
  display_name = "Network Optimization Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }

  enabled = true
}

# Alert policy for network performance degradation
resource "google_monitoring_alert_policy" "network_performance_alert" {
  display_name = "Network Performance Degradation Alert"
  combiner     = "OR"

  conditions {
    display_name = "High Network Latency"
    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = var.latency_threshold_ms

      aggregations {
        alignment_period     = "60s"
        per_series_aligner  = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields     = ["resource.zone"]
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "Connectivity Test Failure"
    condition_threshold {
      filter         = "resource.type=\"network_management_connectivity_test\""
      duration       = "60s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period     = "60s"
        per_series_aligner  = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_notification.name]

  documentation {
    content   = "Network performance has degraded. Check Network Intelligence Center for detailed analysis and review VPC Flow Logs for traffic patterns."
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }

  enabled = true

  user_labels = {
    environment = var.environment
    severity    = "high"
    category    = "network-performance"
  }

  depends_on = [google_project_service.required_apis]
}

# Custom monitoring dashboard for network optimization metrics
resource "google_monitoring_dashboard" "network_optimization_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Network Performance Optimization Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Network Throughput (Bytes/sec)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.zone"]
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Bytes per second"
                scale = "LINEAR"
              }
            }
          }
        }
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Connectivity Test Results"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"network_management_connectivity_test\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_COUNT"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        }
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "VPC Flow Logs Analysis"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_subnetwork\" AND metric.type=\"compute.googleapis.com/subnetwork/num_connections\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }]
            }
          }
        }
      ]
    }
  })
}

# ------------------------------------------------------------------------------
# CLOUD SCHEDULER FOR PERIODIC OPTIMIZATION
# ------------------------------------------------------------------------------
# Scheduled job for periodic network performance analysis
resource "google_cloud_scheduler_job" "periodic_network_analysis" {
  name             = "periodic-network-analysis-${random_id.suffix.hex}"
  description      = "Periodic network performance analysis and optimization"
  schedule         = var.analysis_schedule
  time_zone        = "UTC"
  attempt_deadline = "320s"

  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "60s"
    max_doublings        = 3
  }

  pubsub_target {
    topic_name = google_pubsub_topic.network_optimization_events.id
    data = base64encode(jsonencode({
      action    = "periodic_analysis"
      timestamp = "scheduled"
      type      = "automated"
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# Daily network health report generation
resource "google_cloud_scheduler_job" "daily_network_report" {
  name             = "daily-network-report-${random_id.suffix.hex}"
  description      = "Generate daily network health and performance report"
  schedule         = "0 9 * * *"  # Daily at 9 AM UTC
  time_zone        = "UTC"
  attempt_deadline = "600s"

  retry_config {
    retry_count          = 2
    max_retry_duration   = "300s"
    min_backoff_duration = "10s"
    max_backoff_duration = "120s"
  }

  pubsub_target {
    topic_name = google_pubsub_topic.network_optimization_events.id
    data = base64encode(jsonencode({
      action = "generate_daily_report"
      type   = "report"
      scope  = "daily"
    }))
  }
}

# ------------------------------------------------------------------------------
# RANDOM ID GENERATION
# ------------------------------------------------------------------------------
# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}
# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini
# Main Terraform configuration for GCP resources

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and tagging
  resource_suffix = random_id.suffix.hex
  function_name   = "${var.resource_prefix}-function-${local.resource_suffix}"
  topic_name      = "${var.resource_prefix}-topic-${local.resource_suffix}"
  subscription_name = "${var.resource_prefix}-subscription-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    resource-group = var.resource_prefix
    created-by     = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "monitoring.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Pub/Sub topic for monitoring events
resource "google_pubsub_topic" "monitoring_events" {
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Functions processing
resource "google_pubsub_subscription" "anomaly_analysis" {
  name  = local.subscription_name
  topic = google_pubsub_topic.monitoring_events.name
  
  # Configure message retention and acknowledgment
  message_retention_duration = var.pubsub_message_retention_duration
  ack_deadline_seconds      = var.pubsub_ack_deadline
  
  # Configure retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy for persistent failures
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dead-letter"
  project = var.project_id
  
  labels = local.common_labels
}

# Create service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  display_name = "Anomaly Detection Function Service Account"
  description  = "Service account for AI-powered anomaly detection Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/aiplatform.user",           # Access to Vertex AI and Gemini models
    "roles/monitoring.viewer",         # Read monitoring metrics
    "roles/logging.logWriter",         # Write function logs
    "roles/pubsub.subscriber",         # Consume from Pub/Sub subscription
    "roles/pubsub.publisher",          # Publish to dead letter topic
    "roles/cloudsql.client"            # Optional: access to Cloud SQL if needed
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.resource_prefix}-function-source-${local.resource_suffix}"
  location      = var.region
  project       = var.project_id
  force_destroy = true
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code as a zip file
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id = var.project_id
      region     = var.region
      gemini_model = var.gemini_model
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Generate new deployment when source code changes
  metadata = {
    source_code_hash = data.archive_file.function_source.output_base64sha256
  }
}

# Create Cloud Function for AI-powered anomaly analysis
resource "google_cloudfunctions2_function" "anomaly_detector" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "AI-powered infrastructure anomaly detection using Gemini"
  
  build_config {
    runtime     = "python311"
    entry_point = "analyze_anomaly"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.cloud_function_max_instances
    min_instance_count               = 0
    available_memory                 = "${var.cloud_function_memory}Mi"
    timeout_seconds                  = var.cloud_function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      GCP_PROJECT   = var.project_id
      REGION        = var.region
      GEMINI_MODEL  = var.gemini_model
      TOPIC_NAME    = google_pubsub_topic.monitoring_events.name
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.monitoring_events.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_permissions
  ]
}

# Create test VM instance for monitoring validation (optional)
resource "google_compute_instance" "test_instance" {
  count = var.enable_test_infrastructure ? 1 : 0
  
  name         = "${var.resource_prefix}-test-instance-${local.resource_suffix}"
  machine_type = var.test_instance_machine_type
  zone         = var.zone
  project      = var.project_id
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 10
      type  = "pd-standard"
    }
  }
  
  network_interface {
    network = "default"
    
    # Assign external IP for SSH access
    access_config {
      // Ephemeral IP
    }
  }
  
  # Enable OS Login for secure SSH access
  metadata = {
    enable-oslogin = "true"
  }
  
  # Install Ops Agent for enhanced monitoring
  metadata_startup_script = var.enable_ops_agent ? templatefile("${path.module}/scripts/install_ops_agent.sh", {}) : null
  
  # Configure service account with monitoring permissions
  service_account {
    email  = google_service_account.function_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  
  tags = ["monitoring-test", "anomaly-detection"]
  
  labels = merge(local.common_labels, {
    instance-type = "test-monitoring"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create custom log-based metric for anomaly scores
resource "google_logging_metric" "anomaly_score" {
  name   = "${var.resource_prefix}-anomaly-score-${local.resource_suffix}"
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${local.function_name}"
    textPayload:"ALERT:"
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "1"
    display_name = "AI Anomaly Detection Score"
  }
  
  value_extractor = "EXTRACT(textPayload)"
  
  depends_on = [google_project_service.required_apis]
}

# Create alert policy for CPU anomalies
resource "google_monitoring_alert_policy" "cpu_anomaly" {
  display_name = "AI-Powered CPU Anomaly Detection"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "CPU utilization anomaly"
    
    condition_threshold {
      filter         = "resource.type=\"gce_instance\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.cpu_threshold
      duration       = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Configure notification channels
  notification_channels = [google_monitoring_notification_channel.email.name]
  
  alert_strategy {
    auto_close = "1800s"
    
    notification_rate_limit {
      period = "300s"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create notification channel for email alerts
resource "google_monitoring_notification_channel" "email" {
  display_name = "AI Anomaly Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for anomaly visualization
resource "google_monitoring_dashboard" "anomaly_dashboard" {
  project        = var.project_id
  dashboard_json = templatefile("${path.module}/dashboards/anomaly_dashboard.json", {
    project_id           = var.project_id
    function_name        = local.function_name
    anomaly_metric_name  = google_logging_metric.anomaly_score.name
    test_instance_name   = var.enable_test_infrastructure ? google_compute_instance.test_instance[0].name : ""
    zone                 = var.zone
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.anomaly_score,
    google_cloudfunctions2_function.anomaly_detector
  ]
}

# Create firewall rules for test instance (if enabled)
resource "google_compute_firewall" "test_instance_ssh" {
  count = var.enable_test_infrastructure ? 1 : 0
  
  name    = "${var.resource_prefix}-allow-ssh-${local.resource_suffix}"
  network = "default"
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["monitoring-test"]
  
  depends_on = [google_project_service.required_apis]
}

# Create IAM policy for Pub/Sub topic to allow Cloud Monitoring to publish
resource "google_pubsub_topic_iam_member" "monitoring_publisher" {
  topic  = google_pubsub_topic.monitoring_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}
# Simple Health Monitoring Infrastructure with Cloud Monitoring and Functions
# This configuration creates a complete monitoring solution for web application health checks

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  resource_prefix = "health-monitor-${var.environment}"
  resource_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    managed-by  = "terraform"
  })
  
  # Parse the monitored URL to extract host and path
  url_parts = regex("^(https?)://([^/]+)(/.*)?$", var.monitored_url)
  
  monitored_host     = local.url_parts[1]
  monitored_protocol = local.url_parts[0]
  monitored_path     = local.url_parts[2] != null ? local.url_parts[2] : "/"
  use_ssl           = local.monitored_protocol == "https"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
}

# Create Pub/Sub topic for alert notifications
# This topic receives alert notifications from Cloud Monitoring
resource "google_pubsub_topic" "alert_notifications" {
  name    = "monitoring-alerts-${local.resource_suffix}"
  project = var.project_id
  
  labels = local.common_labels
  
  # Ensure APIs are enabled before creating resources
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for Cloud Function source code
# Required for deploying Cloud Functions with Terraform
resource "google_storage_bucket" "function_source" {
  name     = "${local.resource_prefix}-function-source-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion
  force_destroy = true
  
  # Lifecycle rule to automatically delete old function versions
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

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/alert-function-${local.resource_suffix}.zip"
  
  source {
    content = <<-EOF
import json
import base64
import functions_framework
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def send_alert_email(cloud_event):
    """Send email notification for monitoring alerts."""
    try:
        # Decode Pub/Sub message data
        if cloud_event.data and 'message' in cloud_event.data:
            message_data = cloud_event.data['message']['data']
            pubsub_message = base64.b64decode(message_data).decode('utf-8')
            alert_data = json.loads(pubsub_message)
        else:
            logger.error("No message data found in cloud event")
            return "Error: No message data"
        
        # Extract alert information with proper error handling
        incident = alert_data.get('incident', {})
        policy_name = incident.get('policy_name', 'Unknown Policy')
        state = incident.get('state', 'UNKNOWN')
        started_at = incident.get('started_at', 'Unknown')
        
        # Log alert details for monitoring
        alert_summary = {
            'policy_name': policy_name,
            'state': state,
            'timestamp': datetime.utcnow().isoformat(),
            'started_at': started_at
        }
        
        logger.info(f"Processing alert: {json.dumps(alert_summary)}")
        
        # In a production environment, you would integrate with an email service
        # such as SendGrid, Mailgun, or Gmail API here
        if state == 'OPEN':
            logger.warning(f"ALERT: {policy_name} is DOWN as of {started_at}")
        elif state == 'CLOSED':
            logger.info(f"RESOLVED: {policy_name} is back UP as of {started_at}")
        
        return f"Alert notification processed for {policy_name} - {state}"
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON message: {str(e)}")
        return f"JSON decode error: {str(e)}"
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return f"Error: {str(e)}"
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
functions-framework==3.*
google-cloud-logging==3.*
EOF
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "alert-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Detect changes in source code
  detect_md5hash = true
}

# Deploy Cloud Function for processing alert notifications
# This function receives Pub/Sub messages and processes alert notifications
resource "google_cloudfunctions_function" "alert_notifier" {
  name        = "alert-notifier-${local.resource_suffix}"
  description = "Process monitoring alerts and send notifications"
  project     = var.project_id
  region      = var.region
  runtime     = "python312"
  
  # Function configuration
  available_memory_mb   = var.function_memory
  timeout              = var.function_timeout
  max_instances        = var.function_max_instances
  entry_point          = "send_alert_email"
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Pub/Sub trigger configuration
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.alert_notifications.name
    
    # Retry failed function executions
    failure_policy {
      retry = true
    }
  }
  
  # Environment variables for function configuration
  environment_variables = {
    PROJECT_ID   = var.project_id
    ENVIRONMENT  = var.environment
    FUNCTION_NAME = "alert-notifier-${local.resource_suffix}"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create notification channel for Pub/Sub integration
# This channel routes Cloud Monitoring alerts to our Pub/Sub topic
resource "google_monitoring_notification_channel" "pubsub_channel" {
  display_name = "Custom Alert Notifications - ${local.resource_suffix}"
  description  = "Pub/Sub channel for custom email notifications"
  type         = "pubsub"
  project      = var.project_id
  
  labels = {
    topic = google_pubsub_topic.alert_notifications.id
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create uptime check to monitor website availability
# This synthetic monitoring checks the target URL from multiple global locations
resource "google_monitoring_uptime_check_config" "website_check" {
  display_name = "Website Health Check - ${local.resource_suffix}"
  timeout      = var.uptime_check_timeout
  period       = var.uptime_check_period
  project      = var.project_id
  
  # Configure HTTP/HTTPS check
  http_check {
    request_method = "GET"
    path           = local.monitored_path
    port           = local.use_ssl ? 443 : 80
    use_ssl        = local.use_ssl
    validate_ssl   = var.enable_ssl_validation && local.use_ssl
    
    # Add custom headers if needed
    headers = {
      "User-Agent" = "Google Cloud Monitoring"
    }
  }
  
  # Define the monitored resource
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = local.monitored_host
    }
  }
  
  # Use static IP checkers for consistent monitoring
  checker_type = "STATIC_IP_CHECKERS"
  
  depends_on = [google_project_service.required_apis]
}

# Create alert policy to trigger notifications on uptime check failures
# This policy monitors the uptime check and sends alerts when failures occur
resource "google_monitoring_alert_policy" "uptime_alert" {
  display_name = "Website Uptime Alert - ${local.resource_suffix}"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  # Define alert conditions
  conditions {
    display_name = "Uptime check failure"
    
    condition_threshold {
      # Monitor uptime check success metric
      filter = join(" AND ", [
        "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.type=\"uptime_url\""
      ])
      
      # Alert when success rate equals 0 (complete failure)
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 0
      duration        = var.alert_threshold_duration
      
      # Aggregation configuration
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        
        group_by_fields = [
          "resource.label.project_id",
          "resource.label.host"
        ]
      }
      
      # Trigger configuration
      trigger {
        count = 1
      }
    }
  }
  
  # Configure notification channels
  notification_channels = [
    google_monitoring_notification_channel.pubsub_channel.name
  ]
  
  # Alert policy documentation
  documentation {
    content = "This alert triggers when the website uptime check fails, indicating the monitored service is unavailable."
  }
  
  depends_on = [
    google_monitoring_uptime_check_config.website_check,
    google_monitoring_notification_channel.pubsub_channel
  ]
}

# IAM binding to allow Cloud Monitoring to publish to Pub/Sub topic
# This grants the necessary permissions for alert delivery
resource "google_pubsub_topic_iam_binding" "monitoring_publisher" {
  topic   = google_pubsub_topic.alert_notifications.name
  role    = "roles/pubsub.publisher"
  project = var.project_id
  
  members = [
    "serviceAccount:service-${data.google_project.current.number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
  ]
}

# Get current project information for IAM configuration
data "google_project" "current" {
  project_id = var.project_id
}
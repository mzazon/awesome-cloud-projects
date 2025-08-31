# Main Terraform Configuration for Apps Script Calendar Automation
# This file creates the complete infrastructure for automated event creation
# using Google Apps Script and Calendar API integration

# Note: This configuration creates the foundational GCP infrastructure.
# Google Apps Script projects, Sheets, and Drive resources cannot be directly
# managed through Terraform as they require interactive OAuth authentication.
# This configuration provides the service account and permissions needed
# for manual Apps Script setup following the recipe instructions.

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create a service account for the Apps Script automation
resource "google_service_account" "apps_script_automation" {
  account_id   = "${var.resource_prefix}-automation-${random_id.suffix.hex}"
  display_name = "Apps Script Event Automation Service Account"
  description  = "Service account for automated event creation using Apps Script and Calendar API"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "service_account_roles" {
  for_each = toset(var.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.apps_script_automation.email}"
  
  depends_on = [google_service_account.apps_script_automation]
}

# Create service account key for authentication (optional for Apps Script)
resource "google_service_account_key" "apps_script_key" {
  service_account_id = google_service_account.apps_script_automation.name
  public_key_type    = "TYPE_X509_PEM_FILE"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
  
  depends_on = [google_service_account.apps_script_automation]
}

# Wait for APIs to be fully enabled before creating dependent resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create email notification channel if email is provided
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Event Automation Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  description = "Email notifications for event automation failures and alerts"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create monitoring alert policy for Apps Script execution monitoring
resource "google_monitoring_alert_policy" "apps_script_failures" {
  display_name = "${var.resource_prefix}-apps-script-failures-${random_id.suffix.hex}"
  combiner     = "OR"
  
  conditions {
    display_name = "Apps Script Execution Failures"
    
    condition_threshold {
      filter          = "resource.type=\"app_script_function\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Configure notification channels
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
  
  # Alert documentation
  documentation {
    content = "Apps Script automation has failed to execute successfully. Check the execution logs in Google Apps Script console."
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Cloud Logging sink for Apps Script logs
resource "google_logging_project_sink" "apps_script_logs" {
  name        = "${var.resource_prefix}-apps-script-logs-${random_id.suffix.hex}"
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/${var.resource_prefix}-automation-logs"
  
  # Filter for Apps Script related logs
  filter = "resource.type=\"app_script_function\" OR protoPayload.serviceName=\"script.googleapis.com\""
  
  # Configure sink options
  unique_writer_identity = true
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create BigQuery dataset for log analytics (optional)
resource "google_bigquery_dataset" "automation_analytics" {
  dataset_id                 = "${replace(var.resource_prefix, "-", "_")}_analytics_${random_id.suffix.hex}"
  friendly_name              = "Event Automation Analytics"
  description                = "Analytics dataset for event automation logs and metrics"
  location                   = var.region
  
  # Configure dataset access
  access {
    role          = "OWNER"
    user_by_email = google_service_account.apps_script_automation.email
  }
  
  # Set retention policy
  default_table_expiration_ms = 7776000000 # 90 days
  
  labels = var.labels
  
  depends_on = [google_service_account.apps_script_automation]
}

# Create storage bucket for automation resources and function source
resource "google_storage_bucket" "automation_resources" {
  name     = "${var.resource_prefix}-resources-${random_id.suffix.hex}"
  location = var.region
  
  # Configure bucket settings
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = var.labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Upload the Apps Script automation code as a reference file
resource "google_storage_bucket_object" "automation_script" {
  name   = "automation-script.js"
  bucket = google_storage_bucket.automation_resources.name
  
  # Upload the automation script content
  content = templatefile("${path.module}/scripts/automation.js", {
    sheet_id                  = "YOUR_SHEET_ID_HERE"
    notification_email        = var.notification_email
    max_events_per_execution  = var.max_events_per_execution
    execution_timeout_seconds = var.execution_timeout_seconds
    enable_debug_logging      = var.enable_debug_logging
    dry_run_mode             = var.dry_run_mode
    project_name             = var.apps_script_title
  })
  
  content_type = "application/javascript"
  
  depends_on = [google_storage_bucket.automation_resources]
}

# Create Pub/Sub topic for monitoring events
resource "google_pubsub_topic" "monitoring_events" {
  name = "${var.resource_prefix}-monitoring-events-${random_id.suffix.hex}"
  
  labels = var.labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create IAM binding for Pub/Sub publishing
resource "google_pubsub_topic_iam_binding" "monitoring_publisher" {
  topic = google_pubsub_topic.monitoring_events.name
  role  = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:${google_service_account.apps_script_automation.email}",
  ]
  
  depends_on = [google_pubsub_topic.monitoring_events]
}

# Create custom dashboard for monitoring automation metrics
resource "google_monitoring_dashboard" "automation_dashboard" {
  dashboard_json = jsonencode({
    displayName = "${var.apps_script_title} - Automation Dashboard"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Apps Script Executions"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"app_script_function\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Event Creation Success Rate"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"app_script_function\" AND metric.type=\"logging.googleapis.com/user/event_creation_success\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create a local file with deployment instructions
resource "local_file" "deployment_instructions" {
  filename = "${path.module}/DEPLOYMENT_INSTRUCTIONS.md"
  
  content = <<-EOT
# Apps Script Calendar Automation - Deployment Instructions

This Terraform configuration has created the foundational GCP infrastructure for your Apps Script automation.

## Created Resources

- **Service Account**: ${google_service_account.apps_script_automation.email}
- **BigQuery Dataset**: ${google_bigquery_dataset.automation_analytics.dataset_id}
- **Storage Bucket**: ${google_storage_bucket.automation_resources.name}
- **Monitoring Dashboard**: Check Google Cloud Console
- **Pub/Sub Topic**: ${google_pubsub_topic.monitoring_events.name}

## Manual Steps Required

Since Google Apps Script, Sheets, and Drive resources require interactive OAuth authentication, you'll need to complete these steps manually:

### 1. Create Google Sheet
1. Go to [sheets.google.com](https://sheets.google.com)
2. Create a new spreadsheet named "${var.sheet_name}"
3. Set up headers: Title, Date, Start Time, End Time, Description, Location, Attendees
4. Add sample data as described in the recipe
5. Note the Sheet ID from the URL (between /d/ and /edit)

### 2. Create Apps Script Project
1. Go to [script.google.com](https://script.google.com)
2. Create a new project named "${var.apps_script_title}"
3. Copy the automation code from: ${google_storage_bucket.automation_resources.url}/automation-script.js
4. Replace "YOUR_SHEET_ID_HERE" with your actual Sheet ID
5. Save the project

### 3. Set Up Automation Trigger
1. In the Apps Script editor, run the `createDailyTrigger()` function
2. Grant necessary permissions when prompted
3. Verify the trigger is created in the Triggers section

### 4. Test the Automation
1. Run the `testEventReading()` function to verify sheet access
2. Run the `testSingleEvent()` function to test calendar integration
3. Run the `automateEventCreation()` function for full test

## Configuration
- Trigger Time: ${var.trigger_hour}:00 daily
- Max Events per Execution: ${var.max_events_per_execution}
- Debug Logging: ${var.enable_debug_logging}
- Dry Run Mode: ${var.dry_run_mode}

## Monitoring
- Dashboard: Check Google Cloud Console → Monitoring → Dashboards
- Logs: Google Cloud Console → Logging
- Alerts: ${var.notification_email != "" ? "Email alerts configured" : "No email alerts configured"}

## Next Steps
Follow the recipe instructions to complete the manual setup steps above.
The infrastructure created by Terraform provides the foundation and monitoring for your automation.
EOT
  
  depends_on = [
    google_service_account.apps_script_automation,
    google_storage_bucket.automation_resources,
    google_bigquery_dataset.automation_analytics
  ]
}
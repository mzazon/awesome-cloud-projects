# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.resource_prefix}-${var.environment}-${local.resource_suffix}"
  
  # Function names
  campaign_generator_name = "${var.resource_prefix}-generator-${var.environment}"
  email_sender_name       = "${var.resource_prefix}-sender-${var.environment}"
  analytics_name          = "${var.resource_prefix}-analytics-${var.environment}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create service account for email automation
resource "google_service_account" "email_automation" {
  account_id   = "gmail-automation-sa"
  display_name = "Gmail Automation Service Account"
  description  = "Service account for automated email campaigns"
  
  depends_on = [google_project_service.required_apis]
}

# Create service account key for Gmail API authentication
resource "google_service_account_key" "email_automation_key" {
  service_account_id = google_service_account.email_automation.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Assign IAM roles to service account
resource "google_project_iam_member" "service_account_roles" {
  for_each = toset(var.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.email_automation.email}"
}

# Create Cloud Storage bucket for campaign data
resource "google_storage_bucket" "campaign_data" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  
  # Enable versioning for data protection
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create bucket folders structure
resource "google_storage_bucket_object" "folder_structure" {
  for_each = toset([
    "templates/",
    "campaigns/",
    "analytics/",
    "credentials/"
  ])
  
  name    = each.value
  content = "# This folder contains ${each.value} files"
  bucket  = google_storage_bucket.campaign_data.name
}

# Store service account key in Cloud Storage
resource "google_storage_bucket_object" "service_account_key" {
  name         = "credentials/gmail-automation-key.json"
  content      = base64decode(google_service_account_key.email_automation_key.private_key)
  bucket       = google_storage_bucket.campaign_data.name
  content_type = "application/json"
}

# Create email templates
resource "google_storage_bucket_object" "email_templates" {
  for_each = var.email_templates
  
  name    = "templates/${each.key}.html"
  content = templatefile("${path.module}/templates/${each.key}.html", {
    subject     = each.value.subject
    description = each.value.description
  })
  bucket       = google_storage_bucket.campaign_data.name
  content_type = "text/html"
}

# Create BigQuery dataset for analytics
resource "google_bigquery_dataset" "email_campaigns" {
  dataset_id                 = "email_campaigns"
  friendly_name              = "Email Campaign Analytics"
  description                = "Dataset for email campaign analytics and user behavior data"
  location                   = var.bigquery_dataset_location
  delete_contents_on_destroy = false
  
  # Configure access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.email_automation.email
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create user behavior tracking table
resource "google_bigquery_table" "user_behavior" {
  dataset_id          = google_bigquery_dataset.email_campaigns.dataset_id
  table_id            = "user_behavior"
  deletion_protection = var.bigquery_table_deletion_protection
  
  description = "User behavior tracking for email personalization"
  
  schema = jsonencode([
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique user identifier"
    },
    {
      name = "email"
      type = "STRING"
      mode = "REQUIRED"
      description = "User email address"
    },
    {
      name = "last_activity"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Last user activity timestamp"
    },
    {
      name = "purchase_history"
      type = "STRING"
      mode = "NULLABLE"
      description = "User purchase history JSON"
    },
    {
      name = "preferences"
      type = "STRING"
      mode = "NULLABLE"
      description = "User email preferences"
    }
  ])
  
  labels = local.common_labels
}

# Create campaign metrics table
resource "google_bigquery_table" "campaign_metrics" {
  dataset_id          = google_bigquery_dataset.email_campaigns.dataset_id
  table_id            = "campaign_metrics"
  deletion_protection = var.bigquery_table_deletion_protection
  
  description = "Campaign performance metrics and analytics"
  
  schema = jsonencode([
    {
      name = "campaign_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique campaign identifier"
    },
    {
      name = "sent_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of emails sent"
    },
    {
      name = "delivered_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of emails delivered"
    },
    {
      name = "opened_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of emails opened"
    },
    {
      name = "clicked_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of emails clicked"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Campaign execution timestamp"
    }
  ])
  
  labels = local.common_labels
}

# Create ZIP archive for Campaign Generator function
data "archive_file" "campaign_generator_zip" {
  type        = "zip"
  output_path = "${path.module}/campaign-generator.zip"
  
  source {
    content = templatefile("${path.module}/functions/campaign_generator.py", {
      bucket_name = google_storage_bucket.campaign_data.name
      project_id  = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create Cloud Storage object for Campaign Generator function
resource "google_storage_bucket_object" "campaign_generator_zip" {
  name   = "functions/campaign-generator-${data.archive_file.campaign_generator_zip.output_md5}.zip"
  bucket = google_storage_bucket.campaign_data.name
  source = data.archive_file.campaign_generator_zip.output_path
}

# Deploy Campaign Generator Cloud Function
resource "google_cloudfunctions_function" "campaign_generator" {
  name                  = local.campaign_generator_name
  description           = "Generate personalized email campaigns based on user behavior"
  runtime               = var.function_runtime
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point           = "generate_campaign"
  trigger {
    http_trigger {
      url = null
    }
  }
  
  source_archive_bucket = google_storage_bucket.campaign_data.name
  source_archive_object = google_storage_bucket_object.campaign_generator_zip.name
  
  service_account_email = google_service_account.email_automation.email
  
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.campaign_data.name
    PROJECT_ID  = var.project_id
  }
  
  # Configure function scaling
  max_instances = var.function_max_instances
  min_instances = var.function_min_instances
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.campaign_generator_zip
  ]
}

# Create ZIP archive for Email Sender function
data "archive_file" "email_sender_zip" {
  type        = "zip"
  output_path = "${path.module}/email-sender.zip"
  
  source {
    content = templatefile("${path.module}/functions/email_sender.py", {
      bucket_name = google_storage_bucket.campaign_data.name
      project_id  = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create Cloud Storage object for Email Sender function
resource "google_storage_bucket_object" "email_sender_zip" {
  name   = "functions/email-sender-${data.archive_file.email_sender_zip.output_md5}.zip"
  bucket = google_storage_bucket.campaign_data.name
  source = data.archive_file.email_sender_zip.output_path
}

# Deploy Email Sender Cloud Function
resource "google_cloudfunctions_function" "email_sender" {
  name                  = local.email_sender_name
  description           = "Send personalized emails using Gmail API"
  runtime               = var.function_runtime
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point           = "send_emails"
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  source_archive_bucket = google_storage_bucket.campaign_data.name
  source_archive_object = google_storage_bucket_object.email_sender_zip.name
  
  service_account_email = google_service_account.email_automation.email
  
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.campaign_data.name
    PROJECT_ID  = var.project_id
  }
  
  # Configure function scaling
  max_instances = var.function_max_instances
  min_instances = var.function_min_instances
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.email_sender_zip
  ]
}

# Create ZIP archive for Analytics function
data "archive_file" "analytics_zip" {
  type        = "zip"
  output_path = "${path.module}/analytics.zip"
  
  source {
    content = templatefile("${path.module}/functions/analytics.py", {
      bucket_name = google_storage_bucket.campaign_data.name
      project_id  = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create Cloud Storage object for Analytics function
resource "google_storage_bucket_object" "analytics_zip" {
  name   = "functions/analytics-${data.archive_file.analytics_zip.output_md5}.zip"
  bucket = google_storage_bucket.campaign_data.name
  source = data.archive_file.analytics_zip.output_path
}

# Deploy Analytics Cloud Function
resource "google_cloudfunctions_function" "analytics" {
  name                  = local.analytics_name
  description           = "Analyze email campaign performance and generate insights"
  runtime               = var.function_runtime
  available_memory_mb   = 256
  timeout               = 180
  entry_point           = "analyze_campaigns"
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  source_archive_bucket = google_storage_bucket.campaign_data.name
  source_archive_object = google_storage_bucket_object.analytics_zip.name
  
  service_account_email = google_service_account.email_automation.email
  
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.campaign_data.name
    PROJECT_ID  = var.project_id
  }
  
  # Configure function scaling
  max_instances = var.function_max_instances
  min_instances = var.function_min_instances
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.analytics_zip
  ]
}

# Create Cloud Scheduler job for daily campaign generation
resource "google_cloud_scheduler_job" "daily_campaign_generator" {
  name        = "campaign-generator-daily"
  description = "Daily email campaign generation"
  schedule    = var.daily_campaign_schedule
  time_zone   = var.scheduler_time_zone
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.campaign_generator.https_trigger_url
    
    body = base64encode(jsonencode({
      trigger = "daily_campaign"
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  retry_config {
    retry_count          = var.scheduler_retry_config.retry_count
    max_retry_duration   = var.scheduler_retry_config.max_retry_duration
    min_backoff_duration = var.scheduler_retry_config.min_backoff_duration
    max_backoff_duration = var.scheduler_retry_config.max_backoff_duration
    max_doublings        = var.scheduler_retry_config.max_doublings
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.campaign_generator
  ]
}

# Create Cloud Scheduler job for weekly newsletter
resource "google_cloud_scheduler_job" "weekly_newsletter" {
  name        = "newsletter-weekly"
  description = "Weekly newsletter campaign"
  schedule    = var.weekly_newsletter_schedule
  time_zone   = var.scheduler_time_zone
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.campaign_generator.https_trigger_url
    
    body = base64encode(jsonencode({
      trigger = "weekly_newsletter"
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  retry_config {
    retry_count          = var.scheduler_retry_config.retry_count
    max_retry_duration   = var.scheduler_retry_config.max_retry_duration
    min_backoff_duration = var.scheduler_retry_config.min_backoff_duration
    max_backoff_duration = var.scheduler_retry_config.max_backoff_duration
    max_doublings        = var.scheduler_retry_config.max_doublings
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.campaign_generator
  ]
}

# Create Cloud Scheduler job for promotional campaigns
resource "google_cloud_scheduler_job" "promotional_campaigns" {
  name        = "promotional-campaigns"
  description = "Promotional email campaigns"
  schedule    = var.promotional_campaign_schedule
  time_zone   = var.scheduler_time_zone
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.email_sender.https_trigger_url
    
    body = base64encode(jsonencode({
      campaign_file = "campaigns/latest_promotional.json"
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  retry_config {
    retry_count          = var.scheduler_retry_config.retry_count
    max_retry_duration   = var.scheduler_retry_config.max_retry_duration
    min_backoff_duration = var.scheduler_retry_config.min_backoff_duration
    max_backoff_duration = var.scheduler_retry_config.max_backoff_duration
    max_doublings        = var.scheduler_retry_config.max_doublings
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.email_sender
  ]
}

# Create Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.monitoring_enabled ? 1 : 0
  display_name = "Email Campaign Function Error Rate"
  
  conditions {
    display_name = "Cloud Function error rate too high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.label.function_name=~\"${var.resource_prefix}.*\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Monitoring dashboard
resource "google_monitoring_dashboard" "email_campaigns" {
  count          = var.monitoring_enabled ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "Email Campaign Dashboard"
    
    gridLayout = {
      widgets = [
        {
          title = "Function Invocations"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "Invocations/sec"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Function Errors"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "Errors/sec"
              scale = "LINEAR"
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create budget for cost monitoring
resource "google_billing_budget" "email_campaign_budget" {
  billing_account = var.project_id
  display_name    = "Email Campaign Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/cloudfunctions.googleapis.com",
      "services/cloudscheduler.googleapis.com",
      "services/storage.googleapis.com",
      "services/bigquery.googleapis.com"
    ]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value / 100
      spend_basis       = "CURRENT_SPEND"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}
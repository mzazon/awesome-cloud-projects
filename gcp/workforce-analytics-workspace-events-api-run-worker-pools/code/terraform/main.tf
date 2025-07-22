# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with suffix
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
  
  # Resource names
  dataset_name        = "workforce_analytics_${local.resource_suffix}"
  worker_pool_name    = "analytics-processor-${local.resource_suffix}"
  topic_name          = "workspace-events-${local.resource_suffix}"
  subscription_name   = "events-processor-${local.resource_suffix}"
  bucket_name         = "workforce-data-${var.project_id}-${local.resource_suffix}"
  service_account_id  = "workforce-analytics-sa-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_dependent_services = false
  disable_on_destroy         = false
}

#------------------------------------------------------------------------------
# BigQuery Resources
#------------------------------------------------------------------------------

# BigQuery dataset for workforce analytics data warehouse
resource "google_bigquery_dataset" "workforce_analytics" {
  dataset_id    = local.dataset_name
  friendly_name = "Workforce Analytics Dataset"
  description   = var.dataset_description
  location      = var.dataset_location
  
  # Set default table expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.bigquery_table_expiration_days > 0 ? [1] : []
    content {
      default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for meeting events
resource "google_bigquery_table" "meeting_events" {
  dataset_id = google_bigquery_dataset.workforce_analytics.dataset_id
  table_id   = "meeting_events"
  
  description = "Table storing Google Calendar and Meet event data for workforce analytics"
  
  labels = local.common_labels
  
  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the workspace event"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of workspace event (e.g., calendar.event.created)"
    },
    {
      name = "meeting_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Unique identifier for the meeting"
    },
    {
      name = "organizer_email"
      type = "STRING"
      mode = "NULLABLE"
      description = "Email address of the meeting organizer"
    },
    {
      name = "participant_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of participants in the meeting"
    },
    {
      name = "start_time"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Meeting start time"
    },
    {
      name = "end_time"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Meeting end time"
    },
    {
      name = "duration_minutes"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Duration of the meeting in minutes"
    },
    {
      name = "meeting_title"
      type = "STRING"
      mode = "NULLABLE"
      description = "Title of the meeting"
    },
    {
      name = "calendar_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Calendar ID where the meeting is scheduled"
    },
    {
      name = "created_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the record was created in BigQuery"
    }
  ])
}

# BigQuery table for file collaboration events
resource "google_bigquery_table" "file_events" {
  dataset_id = google_bigquery_dataset.workforce_analytics.dataset_id
  table_id   = "file_events"
  
  description = "Table storing Google Drive and Docs collaboration event data"
  
  labels = local.common_labels
  
  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the workspace event"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of workspace event (e.g., drive.file.created)"
    },
    {
      name = "file_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Unique identifier for the file"
    },
    {
      name = "user_email"
      type = "STRING"
      mode = "NULLABLE"
      description = "Email address of the user performing the action"
    },
    {
      name = "file_name"
      type = "STRING"
      mode = "NULLABLE"
      description = "Name of the file"
    },
    {
      name = "file_type"
      type = "STRING"
      mode = "NULLABLE"
      description = "Type/extension of the file"
    },
    {
      name = "action"
      type = "STRING"
      mode = "NULLABLE"
      description = "Action performed on the file (created, updated, shared)"
    },
    {
      name = "shared_with_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of users the file is shared with"
    },
    {
      name = "folder_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "ID of the folder containing the file"
    },
    {
      name = "drive_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "ID of the shared drive (if applicable)"
    },
    {
      name = "created_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the record was created in BigQuery"
    }
  ])
}

# BigQuery view for meeting analytics
resource "google_bigquery_table" "meeting_analytics_view" {
  dataset_id = google_bigquery_dataset.workforce_analytics.dataset_id
  table_id   = "meeting_analytics"
  
  description = "View providing meeting analytics and productivity insights"
  
  view {
    query = <<-EOF
      SELECT 
        DATE(start_time) as meeting_date,
        organizer_email,
        COUNT(*) as total_meetings,
        AVG(duration_minutes) as avg_duration,
        AVG(participant_count) as avg_participants,
        SUM(duration_minutes * participant_count) as total_person_minutes
      FROM `${var.project_id}.${local.dataset_name}.meeting_events`
      WHERE start_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 30 DAY)
      GROUP BY meeting_date, organizer_email
      ORDER BY meeting_date DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.meeting_events]
}

# BigQuery view for collaboration analytics
resource "google_bigquery_table" "collaboration_analytics_view" {
  dataset_id = google_bigquery_dataset.workforce_analytics.dataset_id
  table_id   = "collaboration_analytics"
  
  description = "View providing file collaboration analytics and sharing patterns"
  
  view {
    query = <<-EOF
      SELECT 
        DATE(created_time) as activity_date,
        user_email,
        file_type,
        action,
        COUNT(*) as action_count,
        COUNT(DISTINCT file_id) as unique_files,
        AVG(shared_with_count) as avg_sharing
      FROM `${var.project_id}.${local.dataset_name}.file_events`
      WHERE created_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 30 DAY)
      GROUP BY activity_date, user_email, file_type, action
      ORDER BY activity_date DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.file_events]
}

# BigQuery view for productivity insights
resource "google_bigquery_table" "productivity_insights_view" {
  dataset_id = google_bigquery_dataset.workforce_analytics.dataset_id
  table_id   = "productivity_insights"
  
  description = "View providing comprehensive productivity insights combining meeting and collaboration data"
  
  view {
    query = <<-EOF
      WITH meeting_stats AS (
        SELECT 
          organizer_email as email,
          COUNT(*) as meetings_organized,
          SUM(duration_minutes) as total_meeting_time
        FROM `${var.project_id}.${local.dataset_name}.meeting_events`
        WHERE start_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 7 DAY)
        GROUP BY organizer_email
      ),
      collaboration_stats AS (
        SELECT 
          user_email as email,
          COUNT(*) as file_actions,
          COUNT(DISTINCT file_id) as files_touched
        FROM `${var.project_id}.${local.dataset_name}.file_events`
        WHERE created_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 7 DAY)
        GROUP BY user_email
      )
      SELECT 
        COALESCE(m.email, c.email) as user_email,
        COALESCE(meetings_organized, 0) as meetings_organized,
        COALESCE(total_meeting_time, 0) as total_meeting_time,
        COALESCE(file_actions, 0) as file_actions,
        COALESCE(files_touched, 0) as files_touched,
        ROUND((COALESCE(file_actions, 0) + COALESCE(meetings_organized, 0) * 2) / 7, 2) as activity_score
      FROM meeting_stats m
      FULL OUTER JOIN collaboration_stats c ON m.email = c.email
      ORDER BY activity_score DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_bigquery_table.meeting_events,
    google_bigquery_table.file_events
  ]
}

#------------------------------------------------------------------------------
# Cloud Pub/Sub Resources
#------------------------------------------------------------------------------

# Pub/Sub topic for workspace events
resource "google_pubsub_topic" "workspace_events" {
  name = local.topic_name
  
  labels = local.common_labels
  
  # Message retention for 7 days
  message_retention_duration = var.message_retention_duration
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for worker pool processing
resource "google_pubsub_subscription" "events_processor" {
  name  = local.subscription_name
  topic = google_pubsub_topic.workspace_events.name
  
  labels = local.common_labels
  
  # Acknowledgment deadline (10 minutes)
  ack_deadline_seconds = var.ack_deadline_seconds
  
  # Message retention for 7 days
  message_retention_duration = var.message_retention_duration
  
  # Enable message ordering for consistent processing
  enable_message_ordering = var.enable_message_ordering
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_pubsub_topic.workspace_events]
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "${local.topic_name}-deadletter"
  
  labels = merge(local.common_labels, {
    component = "dead-letter"
  })
  
  depends_on = [google_project_service.required_apis]
}

#------------------------------------------------------------------------------
# Cloud Storage Resources
#------------------------------------------------------------------------------

# Cloud Storage bucket for application code and temporary data
resource "google_storage_bucket" "workforce_data" {
  name     = local.bucket_name
  location = var.region
  
  labels = local.common_labels
  
  # Storage class configuration
  storage_class = var.storage_class
  
  # Enable versioning for code deployment tracking
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  depends_on = [google_project_service.required_apis]
}

# Create organized directory structure in bucket
resource "google_storage_bucket_object" "code_directory" {
  name   = "code/"
  bucket = google_storage_bucket.workforce_data.name
  content = "Directory for application code"
  
  depends_on = [google_storage_bucket.workforce_data]
}

resource "google_storage_bucket_object" "temp_directory" {
  name   = "temp/"
  bucket = google_storage_bucket.workforce_data.name
  content = "Directory for temporary processing files"
  
  depends_on = [google_storage_bucket.workforce_data]
}

resource "google_storage_bucket_object" "archive_directory" {
  name   = "archive/"
  bucket = google_storage_bucket.workforce_data.name
  content = "Directory for archived analytics data"
  
  depends_on = [google_storage_bucket.workforce_data]
}

#------------------------------------------------------------------------------
# IAM and Service Account Resources
#------------------------------------------------------------------------------

# Custom service account for worker pool (if enabled)
resource "google_service_account" "worker_pool_sa" {
  count = var.create_custom_service_account ? 1 : 0
  
  account_id   = local.service_account_id
  display_name = "Workforce Analytics Worker Pool Service Account"
  description  = "Service account for Cloud Run Worker Pool processing workspace events"
  
  depends_on = [google_project_service.required_apis]
}

# IAM role bindings for service account
resource "google_project_iam_member" "worker_pool_roles" {
  for_each = var.create_custom_service_account ? toset(var.service_account_roles) : []
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.worker_pool_sa[0].email}"
  
  depends_on = [google_service_account.worker_pool_sa]
}

# Additional IAM binding for Cloud Storage access
resource "google_storage_bucket_iam_member" "worker_pool_storage" {
  count = var.create_custom_service_account ? 1 : 0
  
  bucket = google_storage_bucket.workforce_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.worker_pool_sa[0].email}"
  
  depends_on = [
    google_service_account.worker_pool_sa,
    google_storage_bucket.workforce_data
  ]
}

#------------------------------------------------------------------------------
# Cloud Run Worker Pool Resources
#------------------------------------------------------------------------------

# Note: Cloud Run Worker Pools are in preview/beta
# Using google-beta provider for worker pool resources
resource "google_cloud_run_v2_job" "workspace_event_processor" {
  provider = google-beta
  
  name     = local.worker_pool_name
  location = var.region
  
  labels = local.common_labels
  
  template {
    template {
      # Use custom service account if created, otherwise use default
      service_account = var.create_custom_service_account ? google_service_account.worker_pool_sa[0].email : null
      
      # Container configuration
      containers {
        # Use provided image or default to gcr.io placeholder
        image = var.container_image != "" ? var.container_image : "gcr.io/${var.project_id}/workspace-analytics:latest"
        
        # Resource allocation
        resources {
          limits = {
            cpu    = var.worker_pool_cpu
            memory = var.worker_pool_memory
          }
        }
        
        # Environment variables for application
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "SUBSCRIPTION_NAME"
          value = google_pubsub_subscription.events_processor.name
        }
        
        env {
          name  = "DATASET_NAME"
          value = google_bigquery_dataset.workforce_analytics.dataset_id
        }
        
        env {
          name  = "REGION"
          value = var.region
        }
        
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
      }
    }
    
    # Parallelism and task configuration for worker pool behavior
    parallelism = var.worker_pool_max_instances
    task_count  = 1  # Continuous running job
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_subscription.events_processor,
    google_bigquery_dataset.workforce_analytics
  ]
}

#------------------------------------------------------------------------------
# Cloud Monitoring Resources
#------------------------------------------------------------------------------

# Monitoring dashboard for workforce analytics
resource "google_monitoring_dashboard" "workforce_analytics" {
  count = var.create_monitoring_dashboard ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Workforce Analytics Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Event Processing Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_job\" AND metric.type=\"run.googleapis.com/job/completed_execution_count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Pub/Sub Message Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_topic\" AND metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "BigQuery Insert Operations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_dataset\" AND metric.type=\"bigquery.googleapis.com/job/query/count\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Alerting policy for high processing latency
resource "google_monitoring_alert_policy" "high_processing_latency" {
  count = var.create_alerting_policies ? 1 : 0
  
  display_name = "High Event Processing Latency"
  combiner     = "OR"
  
  conditions {
    display_name = "Processing latency too high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_job\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5000  # 5 seconds
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Notification channels (if provided)
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alerting policy for failed Pub/Sub deliveries
resource "google_monitoring_alert_policy" "pubsub_delivery_failures" {
  count = var.create_alerting_policies ? 1 : 0
  
  display_name = "Pub/Sub Message Delivery Failures"
  combiner     = "OR"
  
  conditions {
    display_name = "High rate of delivery failures"
    
    condition_threshold {
      filter         = "resource.type=\"pubsub_subscription\" AND metric.type=\"pubsub.googleapis.com/subscription/dead_letter_message_count\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_subscription.events_processor
  ]
}
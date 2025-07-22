# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  suffix                    = random_id.suffix.hex
  pubsub_topic_raw         = "raw-events-${local.suffix}"
  pubsub_topic_insights    = "insights-${local.suffix}"
  workflow_name            = "analytics-automation-${local.suffix}"
  continuous_query_job_id  = "continuous-analytics-${local.suffix}"
  service_account_id       = "agentspace-analytics-${local.suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    suffix = local.suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "workflows.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ============================================================================
# PUB/SUB INFRASTRUCTURE
# ============================================================================

# Pub/Sub topic for raw streaming events
resource "google_pubsub_topic" "raw_events" {
  name    = local.pubsub_topic_raw
  project = var.project_id

  labels = local.common_labels

  message_retention_duration = var.pubsub_message_retention_duration

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for processed insights
resource "google_pubsub_topic" "insights" {
  name    = local.pubsub_topic_insights
  project = var.project_id

  labels = local.common_labels

  message_retention_duration = var.pubsub_message_retention_duration

  depends_on = [google_project_service.required_apis]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "dead-letter-${local.suffix}"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Subscription for BigQuery continuous query consumption
resource "google_pubsub_subscription" "raw_events_bq" {
  name    = "${local.pubsub_topic_raw}-bq-sub"
  project = var.project_id
  topic   = google_pubsub_topic.raw_events.name

  labels = local.common_labels

  # Message retention for 7 days
  message_retention_duration = "604800s"

  # Acknowledge deadline of 60 seconds
  ack_deadline_seconds = 60

  # Retry policy with exponential backoff
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.pubsub_dead_letter_max_delivery_attempts
  }

  # Enable exactly once delivery
  enable_exactly_once_delivery = true
}

# Subscription for insights consumption by workflows
resource "google_pubsub_subscription" "insights_workflow" {
  name    = "${local.pubsub_topic_insights}-workflow-sub"
  project = var.project_id
  topic   = google_pubsub_topic.insights.name

  labels = local.common_labels

  # Push configuration to trigger Cloud Workflows
  push_config {
    push_endpoint = "https://workflows.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${local.workflow_name}/executions"
    
    attributes = {
      "x-goog-version" = "v1"
    }

    oidc_token {
      service_account_email = var.create_service_account ? google_service_account.agentspace_analytics[0].email : ""
    }
  }

  # Acknowledge deadline of 60 seconds
  ack_deadline_seconds = 60

  depends_on = [google_workflows_workflow.analytics_automation]
}

# ============================================================================
# BIGQUERY INFRASTRUCTURE
# ============================================================================

# BigQuery dataset for real-time analytics
resource "google_bigquery_dataset" "analytics" {
  dataset_id  = var.dataset_name
  project     = var.project_id
  location    = var.bigquery_location
  description = "Real-time analytics dataset for streaming data processing"

  labels = local.common_labels

  # Delete contents when dataset is deleted
  delete_contents_on_destroy = true

  # Access control
  access {
    role          = "OWNER"
    user_by_email = "user@example.com" # This should be replaced with actual user email
  }

  depends_on = [google_project_service.required_apis]
}

# BigQuery table for processed events with optimized schema
resource "google_bigquery_table" "processed_events" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = var.table_name
  project             = var.project_id
  deletion_protection = var.table_deletion_protection

  labels = local.common_labels

  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the event"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Event timestamp in UTC"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "User identifier"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of event (purchase, view, click, etc.)"
    },
    {
      name = "value"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Numeric value associated with the event"
    },
    {
      name = "metadata"
      type = "JSON"
      mode = "NULLABLE"
      description = "Additional event metadata in JSON format"
    }
  ])

  # Partition by timestamp for query optimization
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  # Cluster by user_id and event_type for performance
  clustering = ["user_id", "event_type"]
}

# BigQuery table for real-time insights
resource "google_bigquery_table" "insights" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = var.insights_table_name
  project             = var.project_id
  deletion_protection = var.table_deletion_protection

  labels = local.common_labels

  schema = jsonencode([
    {
      name = "insight_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the insight"
    },
    {
      name = "generated_at"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when insight was generated"
    },
    {
      name = "insight_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of insight (anomaly_detection, prediction, etc.)"
    },
    {
      name = "confidence"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Confidence score for the insight (0.0 to 1.0)"
    },
    {
      name = "recommendation"
      type = "STRING"
      mode = "NULLABLE"
      description = "Human-readable recommendation based on the insight"
    },
    {
      name = "data_points"
      type = "JSON"
      mode = "NULLABLE"
      description = "Supporting data points for the insight"
    }
  ])

  # Partition by generation timestamp
  time_partitioning {
    type  = "DAY"
    field = "generated_at"
  }

  # Cluster by insight type and confidence for analysis
  clustering = ["insight_type", "confidence"]
}

# ============================================================================
# SERVICE ACCOUNT AND IAM
# ============================================================================

# Service account for Agentspace integration
resource "google_service_account" "agentspace_analytics" {
  count = var.create_service_account ? 1 : 0

  account_id   = local.service_account_id
  project      = var.project_id
  display_name = "Agentspace Analytics Service Account"
  description  = "Service account for Agentspace AI agent integration with real-time analytics"
}

# IAM binding for Pub/Sub subscriber role
resource "google_project_iam_member" "agentspace_pubsub_subscriber" {
  count = var.create_service_account ? 1 : 0

  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.agentspace_analytics[0].email}"
}

# IAM binding for BigQuery data viewer role
resource "google_project_iam_member" "agentspace_bigquery_viewer" {
  count = var.create_service_account ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.agentspace_analytics[0].email}"
}

# IAM binding for Workflows invoker role
resource "google_project_iam_member" "agentspace_workflows_invoker" {
  count = var.create_service_account ? 1 : 0

  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.agentspace_analytics[0].email}"
}

# IAM binding for AI Platform user role
resource "google_project_iam_member" "agentspace_aiplatform_user" {
  count = var.create_service_account ? 1 : 0

  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.agentspace_analytics[0].email}"
}

# ============================================================================
# CLOUD WORKFLOWS
# ============================================================================

# Cloud Workflows for business process automation
resource "google_workflows_workflow" "analytics_automation" {
  name            = local.workflow_name
  project         = var.project_id
  region          = var.region
  description     = var.workflow_description
  service_account = var.create_service_account ? google_service_account.agentspace_analytics[0].id : null

  labels = local.common_labels

  source_contents = templatefile("${path.module}/templates/workflow.yaml", {
    project_id = var.project_id
    region     = var.region
  })

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CONTINUOUS QUERY CONFIGURATION
# ============================================================================

# Note: BigQuery Continuous Queries are currently managed through the BigQuery API
# and don't have direct Terraform support. This data source can be used to reference
# the continuous query job after it's created manually or via gcloud CLI.

# Local file for continuous query SQL
resource "local_file" "continuous_query_sql" {
  count = var.enable_continuous_query ? 1 : 0

  filename = "${path.module}/continuous_query.sql"
  content = templatefile("${path.module}/templates/continuous_query.sql", {
    project_id            = var.project_id
    dataset_name          = var.dataset_name
    table_name            = var.table_name
    insights_topic        = google_pubsub_topic.insights.name
    insights_table        = var.insights_table_name
  })

  file_permission = "0644"
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

# Monitoring notification channel (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0

  project      = var.project_id
  display_name = "Real-time Analytics Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for BigQuery job failures
resource "google_monitoring_alert_policy" "bigquery_job_failure" {
  count = var.enable_monitoring ? 1 : 0

  project      = var.project_id
  display_name = "BigQuery Continuous Query Failure"
  combiner     = "OR"

  conditions {
    display_name = "BigQuery job failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"bigquery_project\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for Pub/Sub message backlog
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  count = var.enable_monitoring ? 1 : 0

  project      = var.project_id
  display_name = "Pub/Sub Message Backlog"
  combiner     = "OR"

  conditions {
    display_name = "High message backlog"
    
    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 1000
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# TEMPLATE FILES CREATION
# ============================================================================

# Create workflow template file
resource "local_file" "workflow_template" {
  filename = "${path.module}/templates/workflow.yaml"
  content = <<-EOT
main:
  params: [input]
  steps:
    - extract_insight:
        assign:
          - insight_data: $${input.insight}
          - confidence: $${insight_data.confidence}
          - insight_type: $${insight_data.insight_type}
    
    - evaluate_confidence:
        switch:
          - condition: $${confidence > 0.9}
            next: high_priority_action
          - condition: $${confidence > 0.7}
            next: medium_priority_action
          - condition: true
            next: low_priority_action
    
    - high_priority_action:
        call: execute_immediate_response
        args:
          action_type: "immediate"
          insight: $${insight_data}
        next: log_action
    
    - medium_priority_action:
        call: execute_scheduled_response
        args:
          action_type: "scheduled"
          insight: $${insight_data}
        next: log_action
    
    - low_priority_action:
        call: execute_monitoring_response
        args:
          action_type: "monitoring"
          insight: $${insight_data}
        next: log_action
    
    - log_action:
        call: http.post
        args:
          url: "https://logging.googleapis.com/v2/entries:write"
          headers:
            Authorization: $${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
          body:
            entries:
              - logName: $${"projects/${project_id}/logs/analytics-automation"}
                resource:
                  type: "workflow"
                jsonPayload:
                  insight_id: $${insight_data.insight_id}
                  action_taken: "processed"
                  confidence: $${confidence}
        result: log_result

execute_immediate_response:
  params: [action_type, insight]
  steps:
    - send_alert:
        call: http.post
        args:
          url: "https://pubsub.googleapis.com/v1/projects/${project_id}/topics/alerts:publish"
          headers:
            Authorization: $${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
          body:
            messages:
              - data: $${base64.encode(json.encode(insight))}
                attributes:
                  priority: "high"
                  action_type: $${action_type}

execute_scheduled_response:
  params: [action_type, insight]
  steps:
    - schedule_review:
        call: sys.log
        args:
          data: $${"Scheduled review for insight: " + insight.insight_id}

execute_monitoring_response:
  params: [action_type, insight]
  steps:
    - add_to_monitoring:
        call: sys.log
        args:
          data: $${"Added to monitoring: " + insight.insight_id}
EOT

  depends_on = [google_workflows_workflow.analytics_automation]
}

# Create continuous query SQL template
resource "local_file" "continuous_query_template" {
  filename = "${path.module}/templates/continuous_query.sql"
  content = <<-EOT
EXPORT DATA
OPTIONS (
  uri = 'projects/${project_id}/topics/${insights_topic}',
  format = 'JSON',
  overwrite = false
) AS
WITH real_time_aggregates AS (
  SELECT
    GENERATE_UUID() as insight_id,
    CURRENT_TIMESTAMP() as generated_at,
    'anomaly_detection' as insight_type,
    user_id,
    event_type,
    AVG(value) OVER (
      PARTITION BY user_id, event_type 
      ORDER BY timestamp 
      ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) as moving_avg,
    value,
    CASE 
      WHEN ABS(value - AVG(value) OVER (
        PARTITION BY user_id, event_type 
        ORDER BY timestamp 
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
      )) > 2 * STDDEV(value) OVER (
        PARTITION BY user_id, event_type 
        ORDER BY timestamp 
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
      ) THEN 0.95
      ELSE 0.1
    END as confidence,
    metadata
  FROM `${project_id}.${dataset_name}.${table_name}`
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
)
SELECT
  insight_id,
  generated_at,
  insight_type,
  confidence,
  CONCAT('Potential anomaly detected for user ', user_id, 
         ' with event type ', event_type,
         '. Value: ', CAST(value AS STRING),
         ', Expected: ', CAST(moving_avg AS STRING)) as recommendation,
  TO_JSON(STRUCT(
    user_id,
    event_type,
    value,
    moving_avg,
    metadata
  )) as data_points
FROM real_time_aggregates
WHERE confidence > 0.8;
EOT
}
# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  random_suffix = random_id.suffix.hex
  bucket_name   = "${var.resource_prefix}-data-${local.random_suffix}"
  topic_name    = "${var.resource_prefix}-asset-changes-${local.random_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    deployment_id = local.random_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudasset.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "carbonfootprint.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent disabling these APIs when destroying the Terraform configuration
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create BigQuery dataset for carbon footprint analytics
resource "google_bigquery_dataset" "carbon_analytics" {
  dataset_id    = var.dataset_name
  location      = var.region
  description   = var.dataset_description
  
  # Configure dataset expiration if specified
  default_table_expiration_ms = var.table_expiration_days > 0 ? var.table_expiration_days * 24 * 60 * 60 * 1000 : null
  
  labels = local.common_labels

  # Ensure BigQuery API is enabled before creating dataset
  depends_on = [google_project_service.required_apis]
}

# Create table for asset inventory tracking
resource "google_bigquery_table" "asset_inventory" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "asset_inventory"
  
  description = "Table for tracking cloud asset inventory changes and configurations"
  
  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the asset change was recorded"
    },
    {
      name = "asset_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of the Google Cloud asset (e.g., compute.googleapis.com/Instance)"
    },
    {
      name = "name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Full resource name of the asset"
    },
    {
      name = "location"
      type = "STRING"
      mode = "NULLABLE"
      description = "Geographic location of the asset"
    },
    {
      name = "resource_data"
      type = "JSON"
      mode = "NULLABLE"
      description = "Complete resource configuration and metadata"
    },
    {
      name = "labels"
      type = "JSON"
      mode = "NULLABLE"
      description = "Resource labels and tags"
    }
  ])

  labels = local.common_labels
}

# Create table for carbon emissions data
resource "google_bigquery_table" "carbon_emissions" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "carbon_emissions"
  
  description = "Table for storing Google Cloud Carbon Footprint service data"
  
  schema = jsonencode([
    {
      name = "billing_account_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Billing account associated with the emissions"
    },
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud project ID"
    },
    {
      name = "service"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud service name"
    },
    {
      name = "location"
      type = "STRING"
      mode = "REQUIRED"
      description = "Geographic location of the service usage"
    },
    {
      name = "carbon_footprint_kgCO2e"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Carbon footprint in kilograms of CO2 equivalent"
    },
    {
      name = "carbon_footprint_total_kgCO2e"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Total carbon footprint including all scopes in kgCO2e"
    },
    {
      name = "usage_month"
      type = "DATE"
      mode = "REQUIRED"
      description = "Month of the usage data"
    }
  ])

  labels = local.common_labels
}

# Create BigQuery view for monthly carbon trends analysis
resource "google_bigquery_table" "monthly_carbon_trends" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "monthly_carbon_trends"
  
  description = "View showing carbon emission trends aggregated by month, service, and location"
  
  view {
    query = <<-EOT
      SELECT 
        usage_month,
        service,
        location,
        SUM(carbon_footprint_total_kgCO2e) as total_emissions,
        COUNT(*) as resource_count,
        AVG(carbon_footprint_total_kgCO2e) as avg_emissions_per_resource
      FROM `${var.project_id}.${var.dataset_name}.carbon_emissions`
      GROUP BY usage_month, service, location
      ORDER BY usage_month DESC, total_emissions DESC
    EOT
    
    use_legacy_sql = false
  }

  labels = local.common_labels
  
  depends_on = [google_bigquery_table.carbon_emissions]
}

# Create Pub/Sub topic for real-time asset change notifications
resource "google_pubsub_topic" "asset_changes" {
  name = local.topic_name
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for processing asset changes
resource "google_pubsub_subscription" "asset_changes_subscription" {
  name  = "${local.topic_name}-subscription"
  topic = google_pubsub_topic.asset_changes.name
  
  # Configure message delivery settings
  ack_deadline_seconds       = 20
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages      = false
  
  # Configure dead letter policy for failed message processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.asset_changes_dead_letter.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Create dead letter topic for failed asset change messages
resource "google_pubsub_topic" "asset_changes_dead_letter" {
  name = "${local.topic_name}-dead-letter"
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Asset Inventory
resource "google_service_account" "asset_inventory_sa" {
  account_id   = "${var.resource_prefix}-asset-inventory"
  display_name = "Cloud Asset Inventory Service Account"
  description  = "Service account for Cloud Asset Inventory operations and BigQuery integration"
}

# Grant necessary permissions to asset inventory service account
resource "google_project_iam_member" "asset_inventory_permissions" {
  for_each = toset([
    "roles/pubsub.publisher",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.asset_inventory_sa.email}"
}

# Create Cloud Storage bucket for AI agent data and reports
resource "google_storage_bucket" "carbon_data_bucket" {
  name     = local.bucket_name
  location = var.region
  
  # Configure storage class
  storage_class = var.bucket_storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_nearline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_coldline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Configure versioning for data protection
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Vertex AI operations
resource "google_service_account" "vertex_ai_sa" {
  account_id   = "${var.resource_prefix}-vertex-ai"
  display_name = "Vertex AI Agent Service Account"
  description  = "Service account for Vertex AI agent operations and data access"
}

# Grant necessary permissions to Vertex AI service account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/storage.objectViewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_sa.email}"
}

# Create custom metric descriptor for carbon emissions monitoring
resource "google_monitoring_metric_descriptor" "carbon_emissions_metric" {
  description  = "Carbon emissions per Google Cloud service in kgCO2e"
  display_name = "Carbon Emissions per Service"
  type         = "custom.googleapis.com/carbon/emissions_per_service"
  
  metric_kind = "GAUGE"
  value_type  = "DOUBLE"
  
  labels {
    key         = "service"
    value_type  = "STRING"
    description = "Google Cloud service name"
  }
  
  labels {
    key         = "location"
    value_type  = "STRING"
    description = "Geographic location of the service"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create notification channel for carbon emissions alerts (if email provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Carbon Footprint Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  description = "Email notification channel for carbon footprint monitoring alerts"
}

# Create alerting policy for carbon emission spikes
resource "google_monitoring_alert_policy" "high_carbon_emissions" {
  display_name = "High Carbon Emissions Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Carbon emissions threshold exceeded"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/carbon/emissions_per_service\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_threshold_carbon_emissions
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Add email notification if provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email_notification[0].name]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "Carbon emissions have exceeded the configured threshold of ${var.alert_threshold_carbon_emissions} kgCO2e. Review resource usage and consider optimization opportunities."
    mime_type = "text/markdown"
  }
  
  depends_on = [
    google_monitoring_metric_descriptor.carbon_emissions_metric,
    google_project_service.required_apis
  ]
}

# Create Cloud Function for processing asset inventory changes (placeholder)
# Note: This would typically require deploying function code, which is beyond Terraform scope
resource "google_storage_bucket_object" "function_source_placeholder" {
  name   = "functions/asset-processor.zip"
  bucket = google_storage_bucket.carbon_data_bucket.name
  source = "/dev/null"  # Placeholder - actual function code would be deployed separately
  
  # This is a placeholder for the actual function deployment
  # In a real implementation, you would:
  # 1. Build the function code
  # 2. Create a ZIP archive
  # 3. Upload it to Cloud Storage
  # 4. Deploy the Cloud Function
}

# Create IAM bindings for Carbon Footprint service integration
resource "google_project_iam_member" "carbon_footprint_bigquery_access" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:carbon-footprint@google-cloud-carbon-footprint.iam.gserviceaccount.com"
}

# Output key information for validation and integration
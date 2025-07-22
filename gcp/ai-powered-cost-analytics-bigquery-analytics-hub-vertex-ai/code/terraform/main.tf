# Main Terraform configuration for AI-Powered Cost Analytics solution
# This configuration deploys BigQuery Analytics Hub, Vertex AI, and Cloud Monitoring
# for intelligent cost analytics and predictive modeling

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed resource names and configurations
locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  model_display_name = "${var.model_name}-${random_id.suffix.hex}"
  endpoint_display_name = "${var.endpoint_name}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    deployment-id = random_id.suffix.hex
    created-by    = "terraform"
    solution      = "cost-analytics"
  })
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com", 
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbilling.googleapis.com",
    "datacatalog.googleapis.com",
    "analyticshub.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  service = each.key
  project = var.project_id
  
  # Prevent disabling APIs when destroying to avoid issues
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for model artifacts and data
resource "google_storage_bucket" "model_artifacts" {
  name          = local.bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable versioning for model artifact management
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Force destroy for development environments
  force_destroy = var.force_destroy
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery dataset for cost analytics
resource "google_bigquery_dataset" "cost_analytics" {
  dataset_id  = var.dataset_id
  project     = var.project_id
  location    = var.bigquery_location
  description = "Cost analytics dataset with ML models and shared data"
  
  # Enable deletion of non-empty dataset for development
  delete_contents_on_destroy = var.force_destroy
  
  # Default table expiration (90 days) for cost management
  default_table_expiration_ms = 7776000000
  
  # Access controls and permissions
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.project
  }
  
  access {
    role   = "READER"
    domain = "google.com"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for billing data with partitioning
resource "google_bigquery_table" "billing_data" {
  dataset_id  = google_bigquery_dataset.cost_analytics.dataset_id
  table_id    = "billing_data"
  project     = var.project_id
  description = "Daily cost and usage data with time partitioning"
  
  # Time partitioning for query performance and cost optimization
  time_partitioning {
    type          = "DAY"
    field         = "usage_start_time"
    expiration_ms = 7776000000 # 90 days
  }
  
  # Clustering for query optimization
  clustering = ["service_description", "project_id"]
  
  schema = jsonencode([
    {
      name        = "usage_start_time"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Start time of resource usage"
    },
    {
      name        = "service_description"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Google Cloud service name"
    },
    {
      name        = "sku_description"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Specific SKU or resource type"
    },
    {
      name        = "project_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Google Cloud project identifier"
    },
    {
      name        = "cost"
      type        = "FLOAT64"
      mode        = "REQUIRED"
      description = "Cost amount in specified currency"
    },
    {
      name        = "currency"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Currency code (USD, EUR, etc.)"
    },
    {
      name        = "usage_amount"
      type        = "FLOAT64"
      mode        = "NULLABLE"
      description = "Amount of resource usage"
    },
    {
      name        = "usage_unit"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Unit of measurement for usage"
    },
    {
      name        = "location"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Geographic location of resource"
    },
    {
      name        = "labels"
      type        = "JSON"
      mode        = "NULLABLE"
      description = "Resource labels and metadata"
    }
  ])
  
  labels = local.common_labels
}

# Analytics Hub data exchange for cost data sharing
resource "google_bigquery_analytics_hub_data_exchange" "cost_exchange" {
  provider     = google-beta
  location     = var.bigquery_location
  data_exchange_id = var.exchange_id
  display_name = "Cost Analytics Exchange"
  description  = "Shared cost data and optimization insights across teams"
  
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Analytics Hub listing for billing dataset
resource "google_bigquery_analytics_hub_listing" "billing_feed" {
  provider         = google-beta
  location         = var.bigquery_location
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.cost_exchange.data_exchange_id
  listing_id       = "billing_feed"
  display_name     = "Billing Data Feed"
  description      = "Real-time billing and usage data for cost analytics"
  
  bigquery_dataset {
    dataset = google_bigquery_dataset.cost_analytics.id
  }
  
  project = var.project_id
}

# BigQuery view for daily cost summaries
resource "google_bigquery_table" "daily_cost_summary" {
  dataset_id  = google_bigquery_dataset.cost_analytics.dataset_id
  table_id    = "daily_cost_summary"
  project     = var.project_id
  description = "Daily cost aggregations by service and project"
  
  view {
    query = <<-EOF
      SELECT
        DATE(usage_start_time) as usage_date,
        service_description,
        project_id,
        location,
        SUM(cost) as total_cost,
        SUM(usage_amount) as total_usage,
        COUNT(*) as transaction_count,
        AVG(cost) as avg_cost_per_transaction
      FROM `${var.project_id}.${var.dataset_id}.billing_data`
      GROUP BY usage_date, service_description, project_id, location
      ORDER BY usage_date DESC, total_cost DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.billing_data]
}

# BigQuery view for cost trend analysis
resource "google_bigquery_table" "cost_trends" {
  dataset_id  = google_bigquery_dataset.cost_analytics.dataset_id
  table_id    = "cost_trends"
  project     = var.project_id
  description = "7-day rolling cost trends with growth rates"
  
  view {
    query = <<-EOF
      WITH daily_costs AS (
        SELECT
          DATE(usage_start_time) as usage_date,
          service_description,
          SUM(cost) as daily_cost
        FROM `${var.project_id}.${var.dataset_id}.billing_data`
        GROUP BY usage_date, service_description
      )
      SELECT
        usage_date,
        service_description,
        daily_cost,
        AVG(daily_cost) OVER (
          PARTITION BY service_description 
          ORDER BY usage_date 
          ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) as seven_day_avg,
        LAG(daily_cost, 7) OVER (
          PARTITION BY service_description 
          ORDER BY usage_date
        ) as cost_7_days_ago,
        SAFE_DIVIDE(
          daily_cost - LAG(daily_cost, 7) OVER (
            PARTITION BY service_description 
            ORDER BY usage_date
          ),
          LAG(daily_cost, 7) OVER (
            PARTITION BY service_description 
            ORDER BY usage_date
          )
        ) * 100 as growth_rate_pct
      FROM daily_costs
      ORDER BY usage_date DESC, daily_cost DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.billing_data]
}

# BigQuery view for cost anomaly detection results
resource "google_bigquery_table" "cost_anomalies" {
  dataset_id  = google_bigquery_dataset.cost_analytics.dataset_id
  table_id    = "cost_anomalies"
  project     = var.project_id
  description = "Cost anomalies with severity scores"
  
  view {
    query = <<-EOF
      WITH anomaly_scores AS (
        SELECT
          usage_date,
          service_description,
          daily_cost,
          seven_day_avg,
          growth_rate_pct,
          -- Simplified anomaly score based on growth rate and deviation from average
          ABS(growth_rate_pct) + 
          ABS(SAFE_DIVIDE(daily_cost - seven_day_avg, seven_day_avg) * 100) as anomaly_score
        FROM `${var.project_id}.${var.dataset_id}.cost_trends`
        WHERE growth_rate_pct IS NOT NULL
      )
      SELECT
        *,
        CASE
          WHEN anomaly_score > ${var.anomaly_threshold * 100} THEN 'HIGH'
          WHEN anomaly_score > ${var.anomaly_threshold * 50} THEN 'MEDIUM'
          ELSE 'LOW'
        END as severity
      FROM anomaly_scores
      WHERE anomaly_score > ${var.anomaly_threshold * 25}
      ORDER BY anomaly_score DESC, usage_date DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.cost_trends]
}

# Monitoring metrics view for Cloud Monitoring integration
resource "google_bigquery_table" "monitoring_metrics" {
  dataset_id  = google_bigquery_dataset.cost_analytics.dataset_id
  table_id    = "monitoring_metrics"
  project     = var.project_id
  description = "Metrics for Cloud Monitoring integration"
  
  view {
    query = <<-EOF
      SELECT
        CURRENT_TIMESTAMP() as timestamp,
        service_description,
        daily_cost,
        growth_rate_pct,
        CASE
          WHEN growth_rate_pct > 50 THEN 1
          ELSE 0
        END as high_growth_alert
      FROM `${var.project_id}.${var.dataset_id}.cost_trends`
      WHERE usage_date = CURRENT_DATE() - 1
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.cost_trends]
}

# Populate sample billing data using null_resource and local-exec
resource "null_resource" "populate_sample_data" {
  provisioner "local-exec" {
    command = <<-EOF
      bq query --use_legacy_sql=false --project_id=${var.project_id} "
      INSERT INTO \`${var.project_id}.${var.dataset_id}.billing_data\`
      (usage_start_time, service_description, sku_description, project_id, cost, currency, usage_amount, usage_unit, location, labels)
      WITH sample_data AS (
        SELECT
          TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL MOD(seq, 365) DAY) as usage_start_time,
          CASE MOD(seq, 5)
            WHEN 0 THEN 'Compute Engine'
            WHEN 1 THEN 'BigQuery'
            WHEN 2 THEN 'Cloud Storage'
            WHEN 3 THEN 'Cloud Functions'
            ELSE 'Vertex AI'
          END as service_description,
          CASE MOD(seq, 5)
            WHEN 0 THEN 'N1 Standard Instance Core'
            WHEN 1 THEN 'Analysis'
            WHEN 2 THEN 'Standard Storage'
            WHEN 3 THEN 'Invocations'
            ELSE 'Training'
          END as sku_description,
          CONCAT('project-', MOD(seq, 10)) as project_id,
          ROUND(RAND() * 1000 + 50, 2) as cost,
          'USD' as currency,
          ROUND(RAND() * 100, 2) as usage_amount,
          CASE MOD(seq, 5)
            WHEN 0 THEN 'hour'
            WHEN 1 THEN 'byte'
            WHEN 2 THEN 'byte-second'
            WHEN 3 THEN 'request'
            ELSE 'training-hour'
          END as usage_unit,
          '${var.region}' as location,
          JSON '{\"team\": \"engineering\", \"environment\": \"production\"}' as labels
        FROM UNNEST(GENERATE_ARRAY(1, ${var.sample_data_rows})) as seq
      )
      SELECT * FROM sample_data"
    EOF
  }
  
  depends_on = [
    google_bigquery_table.billing_data,
    google_project_service.required_apis
  ]
}

# Cloud Monitoring notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Cost Anomaly Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for high cost anomalies
resource "google_monitoring_alert_policy" "cost_anomaly_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Cost Anomaly Alert"
  project      = var.project_id
  
  documentation {
    content   = "Alert triggered when cost anomalies exceed configured threshold"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High Anomaly Score Condition"
    
    condition_threshold {
      filter          = "resource.type=\"global\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.anomaly_threshold
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  # Add notification channels if email is provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Data source for current Google Cloud configuration
data "google_client_config" "current" {}

# Service account for Vertex AI operations
resource "google_service_account" "vertex_ai_service_account" {
  account_id   = "vertex-ai-cost-analytics"
  display_name = "Vertex AI Cost Analytics Service Account"
  description  = "Service account for Vertex AI model training and serving"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for Vertex AI service account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account.email}"
}

# Note: Vertex AI model creation and endpoint deployment are complex operations
# that typically require custom training code or pre-trained models.
# In a production environment, you would:
# 1. Upload a trained model to the storage bucket
# 2. Create a Vertex AI model resource
# 3. Deploy the model to an endpoint
#
# For this example, we provide the infrastructure foundation.
# The actual model training and deployment would typically be done
# through a separate pipeline or manually after infrastructure creation.

# Output important resource information for reference
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for model artifacts"
  value       = google_storage_bucket.model_artifacts.name
}

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for cost analytics"
  value       = google_bigquery_dataset.cost_analytics.dataset_id
}

output "analytics_hub_exchange_id" {
  description = "ID of the Analytics Hub data exchange"
  value       = google_bigquery_analytics_hub_data_exchange.cost_exchange.data_exchange_id
}

output "service_account_email" {
  description = "Email of the Vertex AI service account"
  value       = google_service_account.vertex_ai_service_account.email
}
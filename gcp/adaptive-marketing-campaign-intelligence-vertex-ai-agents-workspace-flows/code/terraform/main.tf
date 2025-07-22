# =====================================
# Adaptive Marketing Campaign Intelligence
# with Vertex AI Agents and Google Workspace Flows
# =====================================

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming
  resource_suffix = random_id.suffix.hex
  project_id      = var.project_id
  region          = var.region
  
  # BigQuery dataset and table names
  dataset_name                     = "${var.dataset_name}_${local.resource_suffix}"
  campaign_performance_table       = "campaign_performance"
  customer_interactions_table      = "customer_interactions"
  ai_insights_table               = "ai_insights"
  campaign_dashboard_view         = "campaign_dashboard"
  
  # Storage bucket name
  bucket_name = "${var.project_id}-marketing-intelligence-${local.resource_suffix}"
  
  # Service account names
  vertex_ai_sa_name     = "vertex-ai-marketing-${local.resource_suffix}"
  workspace_flows_sa_name = "workspace-flows-${local.resource_suffix}"
  
  # Required APIs for the solution
  required_apis = [
    "aiplatform.googleapis.com",        # Vertex AI platform
    "bigquery.googleapis.com",          # BigQuery data warehouse
    "storage.googleapis.com",           # Cloud Storage
    "gmail.googleapis.com",             # Gmail API for automated emails
    "sheets.googleapis.com",            # Google Sheets API
    "docs.googleapis.com",              # Google Docs API
    "calendar.googleapis.com",          # Google Calendar API
    "admin.googleapis.com",             # Google Workspace Admin SDK
    "cloudbuild.googleapis.com",        # Cloud Build for automation
    "cloudresourcemanager.googleapis.com", # Resource management
    "serviceusage.googleapis.com",      # Service usage for API management
  ]
  
  # Labels for resource organization and billing
  common_labels = {
    environment     = var.environment
    project         = "marketing-intelligence"
    solution        = "adaptive-campaign-ai"
    cost-center     = var.cost_center
    managed-by      = "terraform"
    recipe-version  = "1.0"
  }
}

# =====================================
# API Enablement
# =====================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = local.project_id
  service = each.value
  
  # Prevent accidental disabling of APIs during destroy
  disable_on_destroy = false
  
  # Add a small delay to prevent API quota issues
  provisioner "local-exec" {
    command = "sleep 10"
  }
}

# =====================================
# Service Accounts and IAM
# =====================================

# Service account for Vertex AI operations
resource "google_service_account" "vertex_ai_service_account" {
  account_id   = local.vertex_ai_sa_name
  display_name = "Vertex AI Marketing Intelligence Service Account"
  description  = "Service account for Vertex AI agents and ML operations in marketing intelligence system"
  
  depends_on = [google_project_service.required_apis]
}

# Service account for Google Workspace Flows integration
resource "google_service_account" "workspace_flows_service_account" {
  account_id   = local.workspace_flows_sa_name
  display_name = "Workspace Flows Marketing Automation Service Account"
  description  = "Service account for Google Workspace Flows automation and API integration"
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for Vertex AI service account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = toset([
    "roles/aiplatform.admin",           # Full Vertex AI access
    "roles/bigquery.dataOwner",         # BigQuery data management
    "roles/bigquery.user",              # BigQuery query execution
    "roles/storage.objectAdmin",        # Cloud Storage object management
    "roles/ml.admin",                   # ML Engine access for legacy compatibility
    "roles/notebooks.admin",            # Workbench instance management
  ])
  
  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account.email}"
  
  depends_on = [google_service_account.vertex_ai_service_account]
}

# IAM roles for Workspace Flows service account
resource "google_project_iam_member" "workspace_flows_permissions" {
  for_each = toset([
    "roles/bigquery.dataViewer",        # Read access to BigQuery data
    "roles/storage.objectViewer",       # Read access to Cloud Storage
    "roles/sheets.editor",              # Google Sheets API access
    "roles/docs.editor",                # Google Docs API access
    "roles/calendar.events.admin",      # Google Calendar API access
  ])
  
  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workspace_flows_service_account.email}"
  
  depends_on = [google_service_account.workspace_flows_service_account]
}

# Custom IAM role for marketing automation workflow
resource "google_project_iam_custom_role" "marketing_automation_role" {
  role_id     = "marketingAutomationRunner${title(local.resource_suffix)}"
  title       = "Marketing Automation Runner"
  description = "Custom role for marketing automation workflows with AI insights"
  
  permissions = [
    # Vertex AI permissions
    "aiplatform.customJobs.create",
    "aiplatform.customJobs.get",
    "aiplatform.endpoints.predict",
    "aiplatform.models.get",
    
    # BigQuery permissions
    "bigquery.datasets.get",
    "bigquery.tables.get",
    "bigquery.tables.getData",
    "bigquery.jobs.create",
    
    # Storage permissions
    "storage.objects.get",
    "storage.objects.create",
    "storage.objects.list",
    
    # Workspace API permissions
    "gmail.messages.send",
    "gmail.drafts.create",
    "sheets.spreadsheets.update",
    "docs.documents.create",
    "calendar.events.create",
  ]
  
  depends_on = [google_project_service.required_apis]
}

# Assign custom role to both service accounts
resource "google_project_iam_member" "vertex_ai_custom_role" {
  project = local.project_id
  role    = google_project_iam_custom_role.marketing_automation_role.name
  member  = "serviceAccount:${google_service_account.vertex_ai_service_account.email}"
}

resource "google_project_iam_member" "workspace_flows_custom_role" {
  project = local.project_id
  role    = google_project_iam_custom_role.marketing_automation_role.name
  member  = "serviceAccount:${google_service_account.workspace_flows_service_account.email}"
}

# =====================================
# Cloud Storage for Data Processing
# =====================================

# Cloud Storage bucket for marketing intelligence data and processing
resource "google_storage_bucket" "marketing_intelligence_bucket" {
  name     = local.bucket_name
  location = var.storage_location
  
  # Security and access configuration
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90  # Archive data after 90 days
    }
    action {
      type = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365  # Delete data after 1 year
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Encryption configuration
  encryption {
    default_kms_key_name = var.kms_key_name
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for storage bucket access
resource "google_storage_bucket_iam_member" "vertex_ai_bucket_access" {
  bucket = google_storage_bucket.marketing_intelligence_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vertex_ai_service_account.email}"
}

resource "google_storage_bucket_iam_member" "workspace_flows_bucket_access" {
  bucket = google_storage_bucket.marketing_intelligence_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.workspace_flows_service_account.email}"
}

# =====================================
# BigQuery Data Warehouse
# =====================================

# BigQuery dataset for marketing intelligence data
resource "google_bigquery_dataset" "marketing_data" {
  dataset_id  = local.dataset_name
  location    = var.bigquery_location
  description = "Marketing campaign intelligence dataset for AI-powered analytics and automation"
  
  # Data retention and lifecycle settings
  default_table_expiration_ms = var.table_expiration_days * 24 * 60 * 60 * 1000  # Convert days to milliseconds
  default_partition_expiration_ms = 30 * 24 * 60 * 60 * 1000  # 30 days for partitions
  
  # Access controls
  access {
    role          = "OWNER"
    user_by_email = google_service_account.vertex_ai_service_account.email
  }
  
  access {
    role          = "READER"
    user_by_email = google_service_account.workspace_flows_service_account.email
  }
  
  # Additional access for data analysts group if specified
  dynamic "access" {
    for_each = var.data_analysts_group != "" ? [1] : []
    content {
      role           = "READER"
      group_by_email = var.data_analysts_group
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Campaign performance data table
resource "google_bigquery_table" "campaign_performance" {
  dataset_id = google_bigquery_dataset.marketing_data.dataset_id
  table_id   = local.campaign_performance_table
  
  description = "Campaign performance metrics and analytics data"
  
  # Define table schema for campaign performance tracking
  schema = jsonencode([
    {
      name = "campaign_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for marketing campaign"
    },
    {
      name = "campaign_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Human-readable campaign name"
    },
    {
      name = "channel"
      type = "STRING"
      mode = "REQUIRED"
      description = "Marketing channel (email, social, paid, organic, etc.)"
    },
    {
      name = "start_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Campaign start date"
    },
    {
      name = "end_date"
      type = "DATE"
      mode = "NULLABLE"
      description = "Campaign end date"
    },
    {
      name = "impressions"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total number of impressions"
    },
    {
      name = "clicks"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total number of clicks"
    },
    {
      name = "conversions"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total number of conversions"
    },
    {
      name = "spend"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total campaign spend in USD"
    },
    {
      name = "revenue"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total revenue generated in USD"
    },
    {
      name = "ctr"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Click-through rate percentage"
    },
    {
      name = "conversion_rate"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Conversion rate percentage"
    },
    {
      name = "roas"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Return on ad spend ratio"
    },
    {
      name = "audience_segment"
      type = "STRING"
      mode = "NULLABLE"
      description = "Target audience segment"
    },
    {
      name = "geo_location"
      type = "STRING"
      mode = "NULLABLE"
      description = "Geographic targeting location"
    },
    {
      name = "device_type"
      type = "STRING"
      mode = "NULLABLE"
      description = "Device type (desktop, mobile, tablet)"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Record creation timestamp"
    }
  ])
  
  # Time partitioning for performance optimization
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for query optimization
  clustering = ["channel", "audience_segment", "campaign_id"]
  
  labels = local.common_labels
}

# Customer interactions table
resource "google_bigquery_table" "customer_interactions" {
  dataset_id = google_bigquery_dataset.marketing_data.dataset_id
  table_id   = local.customer_interactions_table
  
  description = "Customer interaction events and engagement tracking"
  
  schema = jsonencode([
    {
      name = "customer_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique customer identifier"
    },
    {
      name = "interaction_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of interaction (email_open, click, purchase, etc.)"
    },
    {
      name = "interaction_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the interaction occurred"
    },
    {
      name = "campaign_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Associated campaign identifier"
    },
    {
      name = "channel"
      type = "STRING"
      mode = "NULLABLE"
      description = "Interaction channel"
    },
    {
      name = "engagement_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Calculated engagement score (0-10)"
    },
    {
      name = "sentiment_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Sentiment analysis score (-1 to 1)"
    },
    {
      name = "conversion_value"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Value of conversion in USD"
    },
    {
      name = "customer_lifetime_value"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Predicted customer lifetime value"
    },
    {
      name = "demographic_segment"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer demographic segment"
    },
    {
      name = "behavioral_tags"
      type = "STRING"
      mode = "REPEATED"
      description = "Behavioral classification tags"
    }
  ])
  
  time_partitioning {
    type  = "DAY"
    field = "interaction_timestamp"
  }
  
  clustering = ["customer_id", "interaction_type", "campaign_id"]
  
  labels = local.common_labels
}

# AI insights and recommendations table
resource "google_bigquery_table" "ai_insights" {
  dataset_id = google_bigquery_dataset.marketing_data.dataset_id
  table_id   = local.ai_insights_table
  
  description = "AI-generated insights, recommendations, and automated actions"
  
  schema = jsonencode([
    {
      name = "insight_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique insight identifier"
    },
    {
      name = "generated_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the insight was generated"
    },
    {
      name = "insight_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of insight (performance_anomaly, optimization_opportunity, etc.)"
    },
    {
      name = "campaign_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Associated campaign identifier"
    },
    {
      name = "recommendation"
      type = "STRING"
      mode = "REQUIRED"
      description = "AI-generated recommendation text"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Confidence score for the recommendation (0-1)"
    },
    {
      name = "predicted_impact"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Predicted impact score"
    },
    {
      name = "action_required"
      type = "BOOLEAN"
      mode = "REQUIRED"
      description = "Whether automated action is required"
    },
    {
      name = "priority_level"
      type = "STRING"
      mode = "REQUIRED"
      description = "Priority level (low, medium, high, critical)"
    },
    {
      name = "execution_status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Status of recommendation execution (pending, in_progress, completed, failed)"
    }
  ])
  
  time_partitioning {
    type  = "DAY"
    field = "generated_timestamp"
  }
  
  clustering = ["insight_type", "priority_level", "campaign_id"]
  
  labels = local.common_labels
}

# Campaign dashboard view for real-time analytics
resource "google_bigquery_table" "campaign_dashboard_view" {
  dataset_id = google_bigquery_dataset.marketing_data.dataset_id
  table_id   = local.campaign_dashboard_view
  
  description = "Real-time campaign dashboard view with aggregated metrics and AI insights"
  
  view {
    query = templatefile("${path.module}/sql/campaign_dashboard_view.sql", {
      project_id = local.project_id
      dataset_id = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_bigquery_table.campaign_performance,
    google_bigquery_table.customer_interactions,
    google_bigquery_table.ai_insights
  ]
}

# =====================================
# BigQuery ML Model for Customer LTV Prediction
# =====================================

# Customer lifetime value prediction model
resource "google_bigquery_table" "customer_ltv_model" {
  dataset_id = google_bigquery_dataset.marketing_data.dataset_id
  table_id   = "customer_ltv_model"
  
  description = "ML model for predicting customer lifetime value based on engagement patterns"
  
  view {
    query = templatefile("${path.module}/sql/customer_ltv_model.sql", {
      project_id = local.project_id
      dataset_id = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.customer_interactions]
}

# =====================================
# Vertex AI Workbench for Development
# =====================================

# Vertex AI Workbench instance for data science and model development
resource "google_workbench_instance" "marketing_ai_workbench" {
  name     = "marketing-ai-workbench-${local.resource_suffix}"
  location = var.region
  
  gce_setup {
    machine_type = var.workbench_machine_type
    
    # Configure VM with appropriate resources for ML workloads
    vm_image {
      project      = "deeplearning-platform-release"
      family       = "tf-ent-2-11-cu113-notebooks"
    }
    
    # Attach additional disk for data storage
    data_disks {
      disk_size_gb = var.workbench_disk_size_gb
      disk_type    = "PD_SSD"
    }
    
    # Network configuration
    enable_ip_forwarding = false
    
    # Service account for workbench
    service_account = google_service_account.vertex_ai_service_account.email
    
    # Security and access configuration
    disable_public_ip = var.disable_workbench_public_ip
    
    # Boot disk configuration
    boot_disk {
      disk_size_gb = 100
      disk_type    = "PD_STANDARD"
    }
    
    # Enable necessary scopes
    service_account_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email"
    ]
  }
  
  # Instance-level configuration
  instance_owners = var.workbench_owners
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.vertex_ai_service_account
  ]
}

# =====================================
# Sample Data Upload
# =====================================

# Sample marketing data for initial testing and validation
resource "google_storage_bucket_object" "sample_campaign_data" {
  name   = "sample-data/campaign_performance_sample.csv"
  bucket = google_storage_bucket.marketing_intelligence_bucket.name
  content = templatefile("${path.module}/sample-data/campaign_performance_sample.csv", {
    timestamp = formatdate("YYYY-MM-DD hh:mm:ss", timestamp())
  })
  
  depends_on = [google_storage_bucket.marketing_intelligence_bucket]
}

resource "google_storage_bucket_object" "sample_customer_data" {
  name   = "sample-data/customer_interactions_sample.csv"
  bucket = google_storage_bucket.marketing_intelligence_bucket.name
  content = templatefile("${path.module}/sample-data/customer_interactions_sample.csv", {
    timestamp = formatdate("YYYY-MM-DD hh:mm:ss", timestamp())
  })
  
  depends_on = [google_storage_bucket.marketing_intelligence_bucket]
}

# =====================================
# Monitoring and Alerting
# =====================================

# Notification channel for alerting (email-based)
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.alert_email != "" ? 1 : 0
  
  display_name = "Marketing Intelligence Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.alert_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for BigQuery job failures
resource "google_monitoring_alert_policy" "bigquery_job_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "BigQuery Job Failures - Marketing Intelligence"
  combiner     = "OR"
  
  conditions {
    display_name = "BigQuery job failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"bigquery_job\" AND metric.type=\"bigquery.googleapis.com/job/num_failed_jobs\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.alert_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for storage bucket access anomalies
resource "google_monitoring_alert_policy" "storage_access_anomalies" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Storage Access Anomalies - Marketing Intelligence"
  combiner     = "OR"
  
  conditions {
    display_name = "Unusual storage access patterns"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"${google_storage_bucket.marketing_intelligence_bucket.name}\""
      duration        = "600s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 1000  # Alert if more than 1000 requests in 10 minutes
      
      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.alert_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  depends_on = [google_project_service.required_apis]
}
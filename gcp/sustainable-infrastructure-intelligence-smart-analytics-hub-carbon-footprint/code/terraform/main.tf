# ==============================================================================
# RANDOM SUFFIX FOR GLOBALLY UNIQUE RESOURCE NAMES
# ==============================================================================

resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# GOOGLE CLOUD APIS ENABLEMENT
# ==============================================================================

# Enable required Google Cloud APIs for the sustainability intelligence solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "analyticshub.googleapis.com",
    "cloudbuild.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# ==============================================================================
# BIGQUERY DATASET FOR CARBON INTELLIGENCE
# ==============================================================================

# Primary dataset for carbon footprint analytics and intelligence
resource "google_bigquery_dataset" "carbon_intelligence" {
  dataset_id    = var.dataset_name
  friendly_name = "Carbon Intelligence Dataset"
  description   = var.dataset_description
  location      = var.dataset_location

  # Default table expiration for data governance
  default_table_expiration_ms = var.data_retention_days * 24 * 60 * 60 * 1000

  # Labels for resource organization and cost tracking
  labels = merge(var.labels, {
    component = "bigquery"
    purpose   = "carbon-analytics"
  })

  # Access control configuration
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }

  access {
    role           = "READER"
    special_group  = "projectReaders"
  }

  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }

  # Deletion protection for production data
  deletion_protection = var.environment == "prod" ? true : false

  depends_on = [
    google_project_service.required_apis
  ]
}

# ==============================================================================
# BIGQUERY ANALYTICS HUB (SMART ANALYTICS HUB)
# ==============================================================================

# Data exchange for sharing sustainability analytics across the organization
resource "google_bigquery_analytics_hub_data_exchange" "sustainability_exchange" {
  count = var.enable_data_sharing ? 1 : 0

  location         = var.region
  data_exchange_id = var.data_exchange_name
  display_name     = var.data_exchange_display_name
  description      = "Shared carbon footprint and sustainability metrics for organizational collaboration"

  primary_contact = data.google_client_openid_userinfo.me.email
  documentation   = "This data exchange provides access to carbon footprint analytics and sustainability insights to enable data-driven environmental decision making across the organization."

  depends_on = [
    google_project_service.required_apis,
    google_bigquery_dataset.carbon_intelligence
  ]
}

# Data listing for monthly emissions trend sharing
resource "google_bigquery_analytics_hub_listing" "monthly_emissions_listing" {
  count = var.enable_data_sharing ? 1 : 0

  location         = var.region
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.sustainability_exchange[0].data_exchange_id
  listing_id       = "monthly-emissions-trends"
  display_name     = "Monthly Carbon Emissions Trends"
  description      = "Monthly aggregated carbon emissions across projects and services with trend analysis"

  primary_contact = data.google_client_openid_userinfo.me.email
  documentation   = "Access monthly carbon emissions data aggregated across all projects and services. Includes trend analysis and comparative metrics for sustainability reporting."

  # BigQuery dataset source configuration
  bigquery_dataset {
    dataset = google_bigquery_dataset.carbon_intelligence.id
  }

  # Data provider information
  data_provider {
    name                 = "Sustainability Intelligence Team"
    primary_contact      = data.google_client_openid_userinfo.me.email
  }

  depends_on = [
    google_bigquery_analytics_hub_data_exchange.sustainability_exchange
  ]
}

# ==============================================================================
# CLOUD STORAGE FOR SUSTAINABILITY REPORTS
# ==============================================================================

# Storage bucket for generated sustainability reports and recommendations
resource "google_storage_bucket" "reports_bucket" {
  name          = "${var.reports_bucket_name}-${random_id.suffix.hex}"
  location      = var.region
  storage_class = var.reports_bucket_storage_class
  
  # Enable versioning for report history and audit trails
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 1095  # 3 years
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  
  public_access_prevention = var.enable_public_access_prevention ? "enforced" : "unspecified"

  # Labels for resource organization
  labels = merge(var.labels, {
    component = "storage"
    purpose   = "sustainability-reports"
  })

  depends_on = [
    google_project_service.required_apis
  ]
}

# ==============================================================================
# PUB/SUB TOPIC AND SUBSCRIPTION FOR ALERTS
# ==============================================================================

# Pub/Sub topic for carbon emission alerts and notifications
resource "google_pubsub_topic" "carbon_alerts" {
  name = var.alerts_topic_name

  # Message retention for reliable delivery
  message_retention_duration = var.message_retention_duration

  # Labels for resource organization
  labels = merge(var.labels, {
    component = "pubsub"
    purpose   = "carbon-alerts"
  })

  depends_on = [
    google_project_service.required_apis
  ]
}

# Subscription for processing carbon emission alerts
resource "google_pubsub_subscription" "carbon_alerts_subscription" {
  name  = "${var.alerts_topic_name}-subscription"
  topic = google_pubsub_topic.carbon_alerts.name

  # Acknowledgment deadline for message processing
  ack_deadline_seconds = 60

  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter policy for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.carbon_alerts_dead_letter.id
    max_delivery_attempts = 5
  }

  # Labels for resource organization
  labels = merge(var.labels, {
    component = "pubsub"
    purpose   = "carbon-alerts-processing"
  })

  depends_on = [
    google_pubsub_topic.carbon_alerts
  ]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "carbon_alerts_dead_letter" {
  name = "${var.alerts_topic_name}-dead-letter"

  # Extended retention for failed messages analysis
  message_retention_duration = "2419200s"  # 28 days

  labels = merge(var.labels, {
    component = "pubsub"
    purpose   = "dead-letter-queue"
  })

  depends_on = [
    google_project_service.required_apis
  ]
}

# ==============================================================================
# SERVICE ACCOUNTS FOR CLOUD FUNCTIONS
# ==============================================================================

# Service account for data processing Cloud Function
resource "google_service_account" "data_processor_sa" {
  count = var.create_service_accounts ? 1 : 0

  account_id   = "${var.data_processor_function_name}-sa"
  display_name = "Carbon Data Processor Service Account"
  description  = "Service account for carbon footprint data processing Cloud Function"
}

# Service account for recommendations engine Cloud Function
resource "google_service_account" "recommendations_sa" {
  count = var.create_service_accounts ? 1 : 0

  account_id   = "${var.recommendations_function_name}-sa"
  display_name = "Recommendations Engine Service Account"
  description  = "Service account for sustainability recommendations Cloud Function"
}

# Service account for Looker Studio BigQuery access
resource "google_service_account" "looker_studio_sa" {
  account_id   = "looker-studio-sa"
  display_name = "Looker Studio Service Account"
  description  = "Service account for Looker Studio dashboard access to BigQuery"
}

# ==============================================================================
# IAM PERMISSIONS FOR SERVICE ACCOUNTS
# ==============================================================================

# Data processor function IAM permissions
resource "google_project_iam_member" "data_processor_bigquery_editor" {
  count = var.create_service_accounts ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.data_processor_sa[0].email}"
}

resource "google_project_iam_member" "data_processor_bigquery_job_user" {
  count = var.create_service_accounts ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.data_processor_sa[0].email}"
}

resource "google_project_iam_member" "data_processor_pubsub_publisher" {
  count = var.create_service_accounts ? 1 : 0

  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.data_processor_sa[0].email}"
}

# Recommendations engine IAM permissions
resource "google_project_iam_member" "recommendations_bigquery_viewer" {
  count = var.create_service_accounts ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.recommendations_sa[0].email}"
}

resource "google_project_iam_member" "recommendations_bigquery_job_user" {
  count = var.create_service_accounts ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.recommendations_sa[0].email}"
}

resource "google_project_iam_member" "recommendations_storage_admin" {
  count = var.create_service_accounts ? 1 : 0

  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.recommendations_sa[0].email}"
}

# Looker Studio service account permissions
resource "google_project_iam_member" "looker_studio_bigquery_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.looker_studio_sa.email}"
}

resource "google_project_iam_member" "looker_studio_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.looker_studio_sa.email}"
}

# ==============================================================================
# CLOUD FUNCTION SOURCE CODE ARCHIVES
# ==============================================================================

# Create source code for data processing function
resource "local_file" "data_processor_main" {
  filename = "${path.module}/function_source/data_processor/main.py"
  content = templatefile("${path.module}/function_templates/data_processor_main.py.tpl", {
    project_id           = var.project_id
    dataset_name         = var.dataset_name
    topic_name           = var.alerts_topic_name
    increase_threshold   = var.carbon_increase_threshold
    monitoring_months    = var.monitoring_window_months
  })

  depends_on = [
    google_bigquery_dataset.carbon_intelligence,
    google_pubsub_topic.carbon_alerts
  ]
}

resource "local_file" "data_processor_requirements" {
  filename = "${path.module}/function_source/data_processor/requirements.txt"
  content  = file("${path.module}/function_templates/data_processor_requirements.txt")
}

# Create source code for recommendations engine function
resource "local_file" "recommendations_main" {
  filename = "${path.module}/function_source/recommendations_engine/main.py"
  content = templatefile("${path.module}/function_templates/recommendations_main.py.tpl", {
    project_id           = var.project_id
    dataset_name         = var.dataset_name
    bucket_name          = google_storage_bucket.reports_bucket.name
    monitoring_months    = var.monitoring_window_months
  })

  depends_on = [
    google_bigquery_dataset.carbon_intelligence,
    google_storage_bucket.reports_bucket
  ]
}

resource "local_file" "recommendations_requirements" {
  filename = "${path.module}/function_source/recommendations_engine/requirements.txt"
  content  = file("${path.module}/function_templates/recommendations_requirements.txt")
}

# Archive data processing function source code
data "archive_file" "data_processor_source" {
  type        = "zip"
  output_path = "${path.module}/function_source/data_processor.zip"
  source_dir  = "${path.module}/function_source/data_processor"

  depends_on = [
    local_file.data_processor_main,
    local_file.data_processor_requirements
  ]
}

# Archive recommendations engine function source code
data "archive_file" "recommendations_source" {
  type        = "zip"
  output_path = "${path.module}/function_source/recommendations_engine.zip"
  source_dir  = "${path.module}/function_source/recommendations_engine"

  depends_on = [
    local_file.recommendations_main,
    local_file.recommendations_requirements
  ]
}

# ==============================================================================
# CLOUD STORAGE FOR FUNCTION SOURCE CODE
# ==============================================================================

# Upload data processor function source to Cloud Storage
resource "google_storage_bucket_object" "data_processor_source" {
  name   = "functions/data-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.reports_bucket.name
  source = data.archive_file.data_processor_source.output_path

  depends_on = [
    data.archive_file.data_processor_source
  ]
}

# Upload recommendations engine function source to Cloud Storage
resource "google_storage_bucket_object" "recommendations_source" {
  name   = "functions/recommendations-engine-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.reports_bucket.name
  source = data.archive_file.recommendations_source.output_path

  depends_on = [
    data.archive_file.recommendations_source
  ]
}

# ==============================================================================
# CLOUD FUNCTIONS (GENERATION 2)
# ==============================================================================

# Data processing Cloud Function for carbon footprint analysis
resource "google_cloudfunctions2_function" "data_processor" {
  name        = var.data_processor_function_name
  location    = var.region
  description = "Processes carbon footprint data and generates analytical insights"

  build_config {
    runtime     = var.function_runtime
    entry_point = "process_carbon_data"
    
    source {
      storage_source {
        bucket = google_storage_bucket.reports_bucket.name
        object = google_storage_bucket_object.data_processor_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    
    # Environment variables for function configuration
    environment_variables = {
      GCP_PROJECT           = var.project_id
      DATASET_NAME          = var.dataset_name
      TOPIC_NAME           = var.alerts_topic_name
      INCREASE_THRESHOLD   = var.carbon_increase_threshold
      MONITORING_MONTHS    = var.monitoring_window_months
      ENVIRONMENT          = var.environment
    }

    # Service account for secure access
    service_account_email = var.create_service_accounts ? google_service_account.data_processor_sa[0].email : null

    # VPC access configuration for enhanced security
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
  }

  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.carbon_alerts.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }

  # Labels for resource organization
  labels = merge(var.labels, {
    component = "cloud-function"
    purpose   = "data-processing"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.data_processor_source
  ]
}

# Recommendations engine Cloud Function for sustainability insights
resource "google_cloudfunctions2_function" "recommendations_engine" {
  name        = var.recommendations_function_name
  location    = var.region
  description = "Generates sustainability recommendations based on carbon footprint analysis"

  build_config {
    runtime     = var.function_runtime
    entry_point = "generate_recommendations"
    
    source {
      storage_source {
        bucket = google_storage_bucket.reports_bucket.name
        object = google_storage_bucket_object.recommendations_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = 120  # Longer timeout for analysis processing
    
    # Environment variables for function configuration
    environment_variables = {
      GCP_PROJECT      = var.project_id
      DATASET_NAME     = var.dataset_name
      BUCKET_NAME      = google_storage_bucket.reports_bucket.name
      MONITORING_MONTHS = var.monitoring_window_months
      ENVIRONMENT      = var.environment
    }

    # Service account for secure access
    service_account_email = var.create_service_accounts ? google_service_account.recommendations_sa[0].email : null

    # VPC access configuration for enhanced security
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
  }

  # Labels for resource organization
  labels = merge(var.labels, {
    component = "cloud-function"
    purpose   = "recommendations-engine"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.recommendations_source
  ]
}

# ==============================================================================
# CLOUD SCHEDULER JOBS FOR AUTOMATION
# ==============================================================================

# Weekly recommendations generation job
resource "google_cloud_scheduler_job" "recommendations_weekly" {
  name             = "recommendations-weekly"
  region           = var.region
  description      = "Weekly generation of sustainability recommendations"
  schedule         = var.recommendations_schedule
  time_zone        = var.scheduler_timezone
  attempt_deadline = "320s"

  retry_config {
    retry_count          = 3
    max_retry_duration   = "60s"
    max_backoff_duration = "30s"
    max_doublings        = 3
  }

  http_target {
    uri         = google_cloudfunctions2_function.recommendations_engine.service_config[0].uri
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      trigger = "scheduled_weekly"
      source  = "cloud_scheduler"
    }))

    # Authentication configuration
    oidc_token {
      service_account_email = var.create_service_accounts ? google_service_account.recommendations_sa[0].email : null
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.recommendations_engine
  ]
}

# Monthly data processing job
resource "google_cloud_scheduler_job" "data_processing_monthly" {
  name             = "data-processing-monthly"
  region           = var.region
  description      = "Monthly processing of carbon footprint data"
  schedule         = var.data_processing_schedule
  time_zone        = var.scheduler_timezone
  attempt_deadline = "320s"

  retry_config {
    retry_count          = 3
    max_retry_duration   = "60s"
    max_backoff_duration = "30s"
    max_doublings        = 3
  }

  pubsub_target {
    topic_name = google_pubsub_topic.carbon_alerts.id
    data       = base64encode(jsonencode({
      trigger = "monthly_processing"
      source  = "cloud_scheduler"
    }))
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.carbon_alerts
  ]
}

# ==============================================================================
# DATA SOURCES FOR CURRENT USER AND BILLING INFORMATION
# ==============================================================================

# Get current user information for IAM and ownership
data "google_client_openid_userinfo" "me" {}

# Get billing account information for carbon footprint data transfer
data "google_billing_account" "account" {
  count           = var.billing_account_id != "" ? 1 : 0
  billing_account = var.billing_account_id
}

# ==============================================================================
# BIGQUERY DATA TRANSFER FOR CARBON FOOTPRINT
# ==============================================================================

# Automated transfer of carbon footprint data to BigQuery
# Note: This resource requires the Carbon Footprint API to be enabled
# and may need manual configuration for billing account access
resource "google_bigquery_data_transfer_config" "carbon_footprint_transfer" {
  count = var.billing_account_id != "" ? 1 : 0

  display_name           = "Carbon Footprint Export"
  location               = var.region
  data_source_id         = "61cede5a-0000-2440-ad42-883d24f8f7b8"  # Carbon Footprint data source ID
  destination_dataset_id = google_bigquery_dataset.carbon_intelligence.dataset_id
  
  # Transfer configuration parameters
  params = {
    billing_accounts = var.billing_account_id
  }

  # Schedule for data transfer (daily processing of monthly data)
  schedule = "every day 06:00"

  # Notification settings
  notification_pubsub_topic = google_pubsub_topic.carbon_alerts.id

  depends_on = [
    google_project_service.required_apis,
    google_bigquery_dataset.carbon_intelligence
  ]
}
# Terraform configuration for GCP Content Performance Optimization using Gemini and Analytics
# This configuration deploys BigQuery, Cloud Storage, Cloud Functions, and Vertex AI integration

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix    = random_id.suffix.hex
  dataset_name      = "${var.dataset_name}_${local.resource_suffix}"
  bucket_name       = "${var.bucket_name}-${local.resource_suffix}"
  function_name     = "${var.function_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
    recipe-id     = "a3f7b9c2"
  })
  
  # Required Google Cloud APIs for the solution
  required_apis = [
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com", 
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  service = each.value
  project = var.project_id
  
  # Prevent APIs from being disabled when Terraform is destroyed
  disable_on_destroy         = false
  disable_dependent_services = false
}

# BigQuery dataset for content analytics
resource "google_bigquery_dataset" "content_analytics" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.region
  
  friendly_name   = "Content Analytics Dataset"
  description     = "Dataset for storing content performance metrics and analytics data"
  
  # Data retention and access configuration
  default_table_expiration_ms = 0  # No automatic expiration
  delete_contents_on_destroy  = !var.deletion_protection
  
  # Security and access configuration
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.current.email
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for content performance data
resource "google_bigquery_table" "performance_data" {
  dataset_id = google_bigquery_dataset.content_analytics.dataset_id
  table_id   = var.table_name
  project    = var.project_id
  
  friendly_name = "Content Performance Data"
  description   = "Table storing content performance metrics including views, engagement, and conversion rates"
  
  # Table schema for content performance data
  schema = jsonencode([
    {
      name = "content_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for content piece"
    },
    {
      name = "title"
      type = "STRING"
      mode = "REQUIRED"
      description = "Content title or headline"
    },
    {
      name = "content_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of content (blog, video, infographic, etc.)"
    },
    {
      name = "publish_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Content publication timestamp"
    },
    {
      name = "page_views"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total page views for the content"
    },
    {
      name = "engagement_rate"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Engagement rate as a decimal (0.0 to 1.0)"
    },
    {
      name = "conversion_rate"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Conversion rate as a decimal (0.0 to 1.0)"
    },
    {
      name = "time_on_page"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average time spent on page in seconds"
    },
    {
      name = "social_shares"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total social media shares"
    },
    {
      name = "content_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Overall content performance score (0.0 to 10.0)"
    }
  ])
  
  labels = local.common_labels
  
  deletion_protection = var.deletion_protection
}

# BigQuery view for performance summary analytics
resource "google_bigquery_table" "performance_summary_view" {
  dataset_id = google_bigquery_dataset.content_analytics.dataset_id
  table_id   = "content_performance_summary"
  project    = var.project_id
  
  friendly_name = "Content Performance Summary"
  description   = "Aggregated view of content performance metrics by content type"
  
  view {
    query = templatefile("${path.module}/sql/performance_summary.sql", {
      project_id   = var.project_id
      dataset_name = google_bigquery_dataset.content_analytics.dataset_id
      table_name   = google_bigquery_table.performance_data.table_id
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.performance_data]
}

# BigQuery view for content rankings
resource "google_bigquery_table" "content_rankings_view" {
  dataset_id = google_bigquery_dataset.content_analytics.dataset_id
  table_id   = "content_rankings"
  project    = var.project_id
  
  friendly_name = "Content Rankings"
  description   = "View showing content ranked by performance with categorization"
  
  view {
    query = templatefile("${path.module}/sql/content_rankings.sql", {
      project_id   = var.project_id
      dataset_name = google_bigquery_dataset.content_analytics.dataset_id
      table_name   = google_bigquery_table.performance_data.table_id
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.performance_data]
}

# Cloud Storage bucket for content assets and analysis results
resource "google_storage_bucket" "content_optimization" {
  name     = local.bucket_name
  project  = var.project_id
  location = var.region
  
  # Prevent accidental deletion
  force_destroy = !var.deletion_protection
  
  # Bucket configuration
  storage_class = "STANDARD"
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Function
resource "google_service_account" "content_analyzer" {
  account_id   = "content-analyzer-${local.resource_suffix}"
  display_name = "Content Analyzer Function Service Account"
  description  = "Service account for Cloud Function content analysis operations"
  project      = var.project_id
}

# IAM bindings for service account - BigQuery permissions
resource "google_project_iam_member" "content_analyzer_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.content_analyzer.email}"
}

resource "google_bigquery_dataset_iam_member" "content_analyzer_dataset_editor" {
  dataset_id = google_bigquery_dataset.content_analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.content_analyzer.email}"
  project    = var.project_id
}

# IAM bindings for service account - Cloud Storage permissions
resource "google_storage_bucket_iam_member" "content_analyzer_storage_admin" {
  bucket = google_storage_bucket.content_optimization.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.content_analyzer.email}"
}

# IAM bindings for service account - Vertex AI permissions
resource "google_project_iam_member" "content_analyzer_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.content_analyzer.email}"
}

# Create ZIP archive of Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function/main.py", {
      gemini_model = var.gemini_model
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for function source code
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.content_optimization.name
  source = data.archive_file.function_source.output_path
  
  # Ensure the function is redeployed when source changes
  content_md5 = data.archive_file.function_source.output_md5
}

# Cloud Function (2nd generation) for content analysis
resource "google_cloudfunctions2_function" "content_analyzer" {
  name     = local.function_name
  location = var.region
  project  = var.project_id
  
  description = "Serverless function for analyzing content performance using Gemini AI"
  
  build_config {
    runtime     = "python312"
    entry_point = "analyze_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.content_optimization.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.content_analyzer.email
    
    # Environment variables for function configuration
    environment_variables = {
      GCP_PROJECT   = var.project_id
      DATASET_NAME  = google_bigquery_dataset.content_analytics.dataset_id
      BUCKET_NAME   = google_storage_bucket.content_optimization.name
      TABLE_NAME    = google_bigquery_table.performance_data.table_id
      GEMINI_MODEL  = var.gemini_model
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# HTTP trigger for Cloud Function
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.content_analyzer.location
  cloud_function = google_cloudfunctions2_function.content_analyzer.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Load sample data into BigQuery table (optional)
resource "google_bigquery_job" "load_sample_data" {
  count   = var.enable_sample_data ? 1 : 0
  job_id  = "load-sample-data-${local.resource_suffix}"
  project = var.project_id
  
  load {
    source_uris = [
      "gs://${google_storage_bucket.content_optimization.name}/sample-data.json"
    ]
    
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.content_analytics.dataset_id
      table_id   = google_bigquery_table.performance_data.table_id
    }
    
    source_format      = "NEWLINE_DELIMITED_JSON"
    write_disposition  = "WRITE_APPEND"
    
    schema_update_options = ["ALLOW_FIELD_ADDITION"]
  }
  
  depends_on = [
    google_storage_bucket_object.sample_data,
    google_bigquery_table.performance_data
  ]
}

# Upload sample data to Cloud Storage
resource "google_storage_bucket_object" "sample_data" {
  count   = var.enable_sample_data ? 1 : 0
  name    = "sample-data.json"
  bucket  = google_storage_bucket.content_optimization.name
  content = file("${path.module}/data/sample_data.json")
}

# Get current user information for dataset access
data "google_client_openid_userinfo" "current" {}

# Create necessary directories in Cloud Storage bucket
resource "google_storage_bucket_object" "analysis_results_folder" {
  name    = "analysis_results/.gitkeep"
  bucket  = google_storage_bucket.content_optimization.name
  content = "# This folder stores content analysis results from Gemini AI"
}

resource "google_storage_bucket_object" "content_assets_folder" {
  name    = "content_assets/.gitkeep"
  bucket  = google_storage_bucket.content_optimization.name
  content = "# This folder stores content assets and variations"
}
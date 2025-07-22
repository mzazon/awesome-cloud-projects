# Main Terraform configuration for collaborative data science workflows
# This creates a complete data science environment with Colab Enterprise, Dataform, BigQuery, and Cloud Storage

# Local values for resource naming and labeling
locals {
  # Generate unique suffix for resource names to avoid conflicts
  random_suffix = random_id.suffix.hex
  
  # Base name for resources
  base_name = "${var.team_name}-${var.environment}"
  
  # Common labels applied to all resources for governance and cost tracking
  common_labels = merge({
    environment    = var.environment
    team          = var.team_name
    project       = var.project_id
    managed_by    = "terraform"
    use_case      = "collaborative-data-science"
    recipe_id     = "f7a9e2b3"
  }, var.labels)
  
  # Storage bucket name (must be globally unique)
  bucket_name = "${local.base_name}-data-lake-${local.random_suffix}"
  
  # BigQuery dataset name
  dataset_name = "${replace(local.base_name, "-", "_")}_analytics_${local.random_suffix}"
  
  # Dataform repository name
  dataform_repo_name = "${local.base_name}-dataform-repo-${local.random_suffix}"
  
  # Required Google Cloud APIs for the data science workflow
  required_apis = var.enable_apis ? [
    "compute.googleapis.com",
    "storage.googleapis.com", 
    "bigquery.googleapis.com",
    "dataform.googleapis.com",
    "aiplatform.googleapis.com",
    "notebooks.googleapis.com",
    "secretmanager.googleapis.com"
  ] : []
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs for the data science workflow
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying to avoid dependency issues
  disable_on_destroy = false
}

# ============================================================================
# CLOUD STORAGE - Data Lake Infrastructure
# ============================================================================

# Cloud Storage bucket for data lake with versioning and lifecycle management
resource "google_storage_bucket" "data_lake" {
  name     = local.bucket_name
  location = var.bucket_location
  
  # Enhanced security configuration
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Enable versioning for data protection and rollback capabilities
  versioning {
    enabled = true
  }
  
  # Soft delete policy for additional data protection
  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_days * 24 * 60 * 60
  }
  
  # Lifecycle management to control storage costs
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule to move old versions to cheaper storage classes
  lifecycle_rule {
    condition {
      age                = 30
      with_state         = "ARCHIVED"
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create organized folder structure in the data lake
resource "google_storage_bucket_object" "folder_structure" {
  for_each = toset([
    "raw-data/",
    "processed-data/", 
    "model-artifacts/",
    "notebooks/",
    "scripts/"
  ])
  
  name         = each.value
  content      = " "  # Empty content to create folder structure
  content_type = "application/x-directory"
  bucket       = google_storage_bucket.data_lake.name
}

# ============================================================================
# BIGQUERY - Data Warehouse and Analytics
# ============================================================================

# BigQuery dataset for analytics with proper governance and access controls
resource "google_bigquery_dataset" "analytics" {
  dataset_id    = local.dataset_name
  friendly_name = "Analytics Dataset for ${title(var.team_name)}"
  description   = "Centralized analytics dataset for collaborative data science workflows"
  location      = var.dataset_location
  
  # Configure time travel for data recovery
  max_time_travel_hours = var.bigquery_time_travel_hours
  
  # Default encryption configuration (uses Google-managed keys by default)
  default_encryption_configuration {
    kms_key_name = null  # Use Google-managed encryption
  }
  
  # Labels for governance and cost allocation
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Sample customer data table for demonstration
resource "google_bigquery_table" "customer_data" {
  count = var.enable_sample_data ? 1 : 0
  
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "customer_data"
  
  description = "Customer master data for analytics and machine learning"
  
  # Define table schema with appropriate data types
  schema = jsonencode([
    {
      name        = "customer_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique customer identifier"
    },
    {
      name        = "name"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Customer full name"
    },
    {
      name        = "email"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Customer email address"
    },
    {
      name        = "signup_date"
      type        = "DATE"
      mode        = "REQUIRED"
      description = "Date customer signed up"
    },
    {
      name        = "last_updated"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "Timestamp of last record update"
    }
  ])
  
  labels = local.common_labels
}

# Sample transaction data table with partitioning for performance
resource "google_bigquery_table" "transaction_data" {
  count = var.enable_sample_data ? 1 : 0
  
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "transaction_data"
  
  description = "Transaction data for customer analytics and ML model training"
  
  # Time partitioning for better query performance and cost optimization
  time_partitioning {
    type  = "DAY"
    field = "transaction_date"
  }
  
  # Clustering for improved query performance
  clustering = ["customer_id", "transaction_type"]
  
  # Define table schema with proper data types
  schema = jsonencode([
    {
      name        = "transaction_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique transaction identifier"
    },
    {
      name        = "customer_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Reference to customer who made the transaction"
    },
    {
      name        = "amount"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Transaction amount in dollars"
      precision   = 10
      scale       = 2
    },
    {
      name        = "transaction_date"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when transaction occurred"
    },
    {
      name        = "transaction_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of transaction (purchase, refund, etc.)"
    },
    {
      name        = "created_at"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "Timestamp when record was created"
    }
  ])
  
  labels = local.common_labels
}

# ============================================================================
# DATAFORM - Data Transformation and Version Control
# ============================================================================

# Dataform repository for version-controlled data transformations
resource "google_dataform_repository" "analytics_repo" {
  provider = google-beta
  
  name         = local.dataform_repo_name
  display_name = "Analytics Dataform Repository"
  region       = var.region
  
  # Git integration configuration (optional)
  dynamic "git_remote_settings" {
    for_each = var.dataform_git_url != "" ? [1] : []
    content {
      url                                = var.dataform_git_url
      default_branch                     = var.dataform_default_branch
      authentication_token_secret_version = null  # Configure manually or use Secret Manager
    }
  }
  
  # Workspace compilation overrides for environment-specific settings
  workspace_compilation_overrides {
    default_database = var.project_id
    schema_suffix    = "_${var.environment}"
    table_prefix     = "${var.environment}_"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Development workspace for collaborative development
resource "google_dataform_repository_workspace" "dev_workspace" {
  count = var.enable_dataform_workspace ? 1 : 0
  
  provider = google-beta
  
  repository   = google_dataform_repository.analytics_repo.name
  name         = "dev-workspace-${local.random_suffix}"
  region       = var.region
}

# ============================================================================
# VERTEX AI / COLAB ENTERPRISE - Notebook Infrastructure
# ============================================================================

# Service account for Colab Enterprise notebooks with appropriate permissions
resource "google_service_account" "notebook_sa" {
  account_id   = "${local.base_name}-notebook-sa-${local.random_suffix}"
  display_name = "Service Account for Colab Enterprise Notebooks"
  description  = "Service account used by data science notebooks for accessing GCP resources"
}

# Grant necessary permissions to the notebook service account
resource "google_project_iam_member" "notebook_sa_permissions" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser", 
    "roles/storage.objectAdmin",
    "roles/aiplatform.user",
    "roles/notebooks.runner"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.notebook_sa.email}"
}

# Colab Enterprise runtime template for standardized environments
resource "google_notebooks_runtime_template" "data_science_template" {
  name         = "${local.base_name}-runtime-template-${local.random_suffix}"
  display_name = "Data Science Runtime Template"
  description  = "Standardized runtime template for collaborative data science workflows"
  location     = var.region
  
  # Machine configuration for data science workloads
  machine_spec {
    machine_type = var.notebook_machine_type
  }
  
  # Persistent disk for notebook storage
  data_persistent_disk_spec {
    disk_type    = "pd-standard"
    disk_size_gb = 100
  }
  
  # Container specification with data science tools
  container_spec {
    image_uri = "gcr.io/deeplearning-platform-release/base-cpu"
    
    # Environment variables for GCP integration
    env {
      name  = "GOOGLE_CLOUD_PROJECT"
      value = var.project_id
    }
    
    env {
      name  = "GOOGLE_CLOUD_REGION"
      value = var.region
    }
  }
  
  # Network configuration
  network_spec {
    enable_ip_forwarding = false
    machine_type        = var.notebook_machine_type
  }
  
  # Service account configuration
  service_account_spec {
    service_account = google_service_account.notebook_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.notebook_sa_permissions
  ]
}

# ============================================================================
# IAM - Collaborative Access Control
# ============================================================================

# IAM binding for data scientists - full access to development resources
resource "google_project_iam_member" "data_scientists" {
  for_each = toset(var.data_scientists)
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "user:${each.value}"
}

resource "google_project_iam_member" "data_scientists_notebooks" {
  for_each = toset(var.data_scientists)
  
  project = var.project_id
  role    = "roles/notebooks.admin"
  member  = "user:${each.value}"
}

resource "google_project_iam_member" "data_scientists_ai_platform" {
  for_each = toset(var.data_scientists)
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "user:${each.value}"
}

# IAM binding for data engineers - full access to data pipeline resources
resource "google_project_iam_member" "data_engineers" {
  for_each = toset(var.data_engineers)
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "user:${each.value}"
}

resource "google_project_iam_member" "data_engineers_dataform" {
  for_each = toset(var.data_engineers)
  
  project = var.project_id
  role    = "roles/dataform.editor"
  member  = "user:${each.value}"
}

resource "google_project_iam_member" "data_engineers_storage" {
  for_each = toset(var.data_engineers)
  
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "user:${each.value}"
}

# IAM binding for analysts - read-only access to data and dashboards
resource "google_project_iam_member" "analysts" {
  for_each = toset(var.analysts)
  
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "user:${each.value}"
}

resource "google_project_iam_member" "analysts_storage_read" {
  for_each = toset(var.analysts)
  
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "user:${each.value}"
}

# Resource-specific IAM for fine-grained access control
resource "google_storage_bucket_iam_member" "data_team_storage" {
  for_each = toset(concat(var.data_scientists, var.data_engineers))
  
  bucket = google_storage_bucket.data_lake.name
  role   = "roles/storage.objectAdmin"
  member = "user:${each.value}"
}

resource "google_bigquery_dataset_iam_member" "data_team_bigquery" {
  for_each = toset(concat(var.data_scientists, var.data_engineers))
  
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "user:${each.value}"
}

resource "google_bigquery_dataset_iam_member" "analysts_bigquery_read" {
  for_each = toset(var.analysts)
  
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "user:${each.value}"
}

# ============================================================================
# MONITORING AND LOGGING (Optional Enhancement)
# ============================================================================

# Log sink for BigQuery audit logs to track data access patterns
resource "google_logging_project_sink" "bigquery_audit_sink" {
  name        = "${local.base_name}-bigquery-audit-sink"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.analytics.dataset_id}"
  
  # Filter for BigQuery data access and admin activity
  filter = <<-EOT
    protoPayload.serviceName="bigquery.googleapis.com"
    AND (
      protoPayload.methodName="jobservice.insert"
      OR protoPayload.methodName="tableservice.insert"
      OR protoPayload.methodName="datasetservice.insert"
    )
  EOT
  
  # Create dataset if it doesn't exist
  unique_writer_identity = true
  
  depends_on = [google_bigquery_dataset.analytics]
}
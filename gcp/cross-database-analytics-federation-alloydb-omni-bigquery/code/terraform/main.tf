# Cross-Database Analytics Federation with AlloyDB Omni and BigQuery
# This Terraform configuration deploys a federated analytics platform that combines
# AlloyDB Omni (simulated with Cloud SQL PostgreSQL) with BigQuery for real-time
# cross-database analytics without data movement.

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels for resource organization
  common_labels = {
    project     = "analytics-federation"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  # Resource naming with random suffix
  resource_suffix    = random_id.suffix.hex
  bucket_name       = "analytics-lake-${local.resource_suffix}"
  service_account   = "federation-sa-${local.resource_suffix}"
  alloydb_instance  = "alloydb-omni-sim-${local.resource_suffix}"
  connection_id     = "alloydb-federation-${local.resource_suffix}"
  lake_id          = "analytics-federation-lake-${local.resource_suffix}"
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "dataplex.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service account for cross-service authentication
resource "google_service_account" "federation_sa" {
  account_id   = local.service_account
  display_name = "Analytics Federation Service Account"
  description  = "Service account for federated analytics across AlloyDB Omni and BigQuery"
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "bigquery_connection_user" {
  project = var.project_id
  role    = "roles/bigquery.connectionUser"
  member  = "serviceAccount:${google_service_account.federation_sa.email}"
}

resource "google_project_iam_member" "bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.federation_sa.email}"
}

resource "google_project_iam_member" "dataplex_editor" {
  project = var.project_id
  role    = "roles/dataplex.editor"
  member  = "serviceAccount:${google_service_account.federation_sa.email}"
}

resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.federation_sa.email}"
}

# Cloud Storage bucket for data lake foundation
resource "google_storage_bucket" "analytics_lake" {
  name     = local.bucket_name
  location = var.region
  
  # Storage configuration
  storage_class = "STANDARD"
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management
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
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create directory structure in bucket
resource "google_storage_bucket_object" "data_directories" {
  for_each = toset([
    "raw-data/.keep",
    "processed-data/.keep",
    "staging/.keep"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.analytics_lake.name
  source = "/dev/null"
}

# BigQuery datasets for federated analytics
resource "google_bigquery_dataset" "analytics_federation" {
  dataset_id                  = "analytics_federation"
  friendly_name              = "Federated Analytics Workspace"
  description                = "Main dataset for federated analytics across AlloyDB Omni and BigQuery"
  location                   = var.region
  default_table_expiration_ms = null
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

resource "google_bigquery_dataset" "cloud_analytics" {
  dataset_id                  = "cloud_analytics"
  friendly_name              = "Cloud Analytics Data"
  description                = "Cloud-native analytics data for federation with on-premises sources"
  location                   = var.region
  default_table_expiration_ms = null
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Sample customer table in BigQuery
resource "google_bigquery_table" "customers" {
  dataset_id = google_bigquery_dataset.cloud_analytics.dataset_id
  table_id   = "customers"
  
  schema = jsonencode([
    {
      name = "customer_id"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "customer_name"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "region"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "signup_date"
      type = "DATE"
      mode = "REQUIRED"
    }
  ])
  
  labels = local.common_labels
}

# Cloud SQL instance (AlloyDB Omni simulation)
resource "google_sql_database_instance" "alloydb_omni_sim" {
  name             = local.alloydb_instance
  database_version = "POSTGRES_14"
  region           = var.region
  
  settings {
    tier      = "db-custom-2-8192"  # 2 CPU, 8GB RAM
    disk_size = 20
    disk_type = "PD_SSD"
    
    # High availability for production-like environment
    availability_type = "REGIONAL"
    
    # Backup configuration
    backup_configuration {
      enabled    = true
      start_time = "03:00"
      
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration
    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "all-networks"
        value = "0.0.0.0/0"  # In production, restrict this to specific networks
      }
    }
    
    # Database flags for optimal performance
    database_flags {
      name  = "max_connections"
      value = "200"
    }
    
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    
    user_labels = local.common_labels
  }
  
  # Root password for initial setup
  root_password = var.db_password
  
  deletion_protection = false
  
  depends_on = [google_project_service.required_apis]
}

# Database for transactional data
resource "google_sql_database" "transactions" {
  name     = "transactions"
  instance = google_sql_database_instance.alloydb_omni_sim.name
}

# BigQuery connection for federation
resource "google_bigquery_connection" "alloydb_federation" {
  connection_id = local.connection_id
  location      = var.region
  
  friendly_name = "AlloyDB Omni Federation Connection"
  description   = "Federated connection to AlloyDB Omni for cross-database analytics"
  
  cloud_sql {
    instance_id = google_sql_database_instance.alloydb_omni_sim.connection_name
    database    = google_sql_database.transactions.name
    type        = "POSTGRES"
    
    credential {
      username = "postgres"
      password = var.db_password
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.alloydb_omni_sim
  ]
}

# Dataplex lake for unified data governance
resource "google_dataplex_lake" "analytics_federation_lake" {
  location = var.region
  name     = local.lake_id
  
  display_name = "Analytics Federation Lake"
  description  = "Unified governance for federated analytics across AlloyDB Omni and BigQuery"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Dataplex zone for analytics
resource "google_dataplex_zone" "analytics_zone" {
  location = var.region
  name     = "analytics-zone"
  lake     = google_dataplex_lake.analytics_federation_lake.name
  
  display_name = "Analytics Zone"
  description  = "Zone for raw and processed analytics data"
  
  type                   = "RAW"
  resource_location_type = "SINGLE_REGION"
  
  labels = local.common_labels
}

# Dataplex asset for BigQuery datasets
resource "google_dataplex_asset" "bigquery_analytics_asset" {
  location = var.region
  name     = "bigquery-analytics-asset"
  lake     = google_dataplex_lake.analytics_federation_lake.name
  zone     = google_dataplex_zone.analytics_zone.name
  
  display_name = "BigQuery Analytics Asset"
  description  = "BigQuery datasets for federated analytics"
  
  resource_spec {
    name = "projects/${var.project_id}/datasets/${google_bigquery_dataset.analytics_federation.dataset_id}"
    type = "BIGQUERY_DATASET"
  }
  
  labels = local.common_labels
}

# Dataplex asset for Cloud Storage data lake
resource "google_dataplex_asset" "storage_lake_asset" {
  location = var.region
  name     = "storage-lake-asset"
  lake     = google_dataplex_lake.analytics_federation_lake.name
  zone     = google_dataplex_zone.analytics_zone.name
  
  display_name = "Cloud Storage Data Lake Asset"
  description  = "Cloud Storage bucket for data lake foundation"
  
  resource_spec {
    name = "projects/${var.project_id}/buckets/${google_storage_bucket.analytics_lake.name}"
    type = "STORAGE_BUCKET"
  }
  
  labels = local.common_labels
}

# Cloud Function source code bucket
resource "google_storage_bucket" "function_source" {
  name     = "function-source-${local.resource_suffix}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py.tpl", {
      project_id    = var.project_id
      region        = var.region
      connection_id = local.connection_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for metadata orchestration
resource "google_cloudfunctions_function" "federation_metadata_sync" {
  name        = "federation-metadata-sync-${local.resource_suffix}"
  description = "Metadata synchronization for federated analytics"
  region      = var.region
  
  runtime             = "python39"
  available_memory_mb = 256
  timeout             = 60
  entry_point         = "sync_metadata"
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  service_account_email = google_service_account.federation_sa.email
  
  environment_variables = {
    PROJECT_ID    = var.project_id
    REGION        = var.region
    CONNECTION_ID = local.connection_id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_bigquery_connection.alloydb_federation
  ]
}

# IAM for Cloud Function invocation
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.federation_metadata_sync.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"  # In production, restrict this appropriately
}

# Cloud Scheduler job for automated metadata sync
resource "google_cloud_scheduler_job" "metadata_sync_schedule" {
  name        = "metadata-sync-${local.resource_suffix}"
  description = "Scheduled metadata synchronization for federated analytics"
  schedule    = "0 */6 * * *"  # Every 6 hours
  time_zone   = "UTC"
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.federation_metadata_sync.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      project_id    = var.project_id
      connection_id = local.connection_id
    }))
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.federation_metadata_sync
  ]
}

# BigQuery view for federated customer lifetime value analysis
resource "google_bigquery_table" "customer_lifetime_value_view" {
  dataset_id = google_bigquery_dataset.analytics_federation.dataset_id
  table_id   = "customer_lifetime_value"
  
  view {
    query = templatefile("${path.module}/sql/customer_lifetime_value.sql.tpl", {
      project_id    = var.project_id
      region        = var.region
      connection_id = local.connection_id
    })
    use_legacy_sql = false
  }
  
  description = "Real-time customer analytics across cloud and on-premises data"
  
  labels = local.common_labels
  
  depends_on = [
    google_bigquery_connection.alloydb_federation,
    google_bigquery_table.customers
  ]
}
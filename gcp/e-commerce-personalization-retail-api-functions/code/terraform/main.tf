# Main Terraform Configuration for E-commerce Personalization with Retail API and Cloud Functions
# This file creates the complete infrastructure for the e-commerce personalization solution

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
    recipe-id     = "f8e2d1c3"
  })
  
  # Required Google Cloud APIs
  required_apis = [
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "firestore.googleapis.com",
    "retail.googleapis.com",
    "discoveryengine.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
  
  # Function source code ZIP files
  function_sources = {
    catalog_sync      = "catalog-sync-function.zip"
    user_events       = "user-events-function.zip"
    recommendations   = "recommendations-function.zip"
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  timeouts {
    create = "30m"
    update = "40m"
  }
  
  disable_on_destroy = false
}

# Create service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "retail-functions-sa-${local.resource_suffix}"
  display_name = "Retail Functions Service Account"
  description  = "Service account for retail personalization Cloud Functions"
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the function service account
resource "google_project_iam_member" "function_roles" {
  for_each = toset([
    "roles/retail.admin",
    "roles/discoveryengine.admin",
    "roles/storage.objectAdmin",
    "roles/firestore.user",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudsql.client"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Cloud Storage bucket for product catalog data
resource "google_storage_bucket" "product_catalog_bucket" {
  name          = "${var.project_id}-product-catalog-${local.resource_suffix}"
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_management ? [1] : []
    content {
      condition {
        age = var.nearline_transition_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_management ? [1] : []
    content {
      condition {
        age = var.coldline_transition_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_management ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${var.project_id}-function-source-${local.resource_suffix}"
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Firestore database for user profiles and metadata
resource "google_firestore_database" "user_profiles_db" {
  name        = "user-profiles-${local.resource_suffix}"
  location_id = var.firestore_location
  type        = var.firestore_database_type
  
  # Security and compliance configurations
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = var.enable_point_in_time_recovery ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  delete_protection_state           = var.enable_delete_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = "ABANDON"
  
  depends_on = [google_project_service.required_apis]
}

# Create placeholder source code archives for Cloud Functions
data "archive_file" "catalog_sync_source" {
  type        = "zip"
  output_path = "${path.module}/catalog-sync-function.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/catalog-sync.js.tpl", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "catalog-sync-function"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/retail" = "^3.0.0"
        "@google-cloud/storage" = "^7.0.0"
        "@google-cloud/functions-framework" = "^3.0.0"
      }
    })
    filename = "package.json"
  }
}

data "archive_file" "user_events_source" {
  type        = "zip"
  output_path = "${path.module}/user-events-function.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/user-events.js.tpl", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "user-events-function"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/retail" = "^3.0.0"
        "@google-cloud/firestore" = "^7.0.0"
        "@google-cloud/functions-framework" = "^3.0.0"
      }
    })
    filename = "package.json"
  }
}

data "archive_file" "recommendations_source" {
  type        = "zip"
  output_path = "${path.module}/recommendations-function.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/recommendations.js.tpl", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "recommendations-function"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/retail" = "^3.0.0"
        "@google-cloud/firestore" = "^7.0.0"
        "@google-cloud/functions-framework" = "^3.0.0"
      }
    })
    filename = "package.json"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "catalog_sync_source" {
  name   = "catalog-sync-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.catalog_sync_source.output_path
}

resource "google_storage_bucket_object" "user_events_source" {
  name   = "user-events-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.user_events_source.output_path
}

resource "google_storage_bucket_object" "recommendations_source" {
  name   = "recommendations-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.recommendations_source.output_path
}

# Cloud Function for catalog synchronization
resource "google_cloudfunctions2_function" "catalog_sync_function" {
  name        = "catalog-sync-${local.resource_suffix}"
  location    = var.region
  description = "Synchronizes product catalog data with Retail API"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "syncCatalog"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.catalog_sync_source.name
      }
    }
    
    environment_variables = {
      BUILD_ENV = var.environment
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = var.function_concurrency
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID         = var.project_id
      CATALOG_NAME       = var.retail_catalog_name
      BRANCH_NAME        = var.retail_branch_name
      FIRESTORE_DATABASE = google_firestore_database.user_profiles_db.name
    }
    
    ingress_settings               = var.function_ingress_settings
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.catalog_sync_source
  ]
}

# Cloud Function for user event tracking
resource "google_cloudfunctions2_function" "user_events_function" {
  name        = "track-user-events-${local.resource_suffix}"
  location    = var.region
  description = "Tracks user events for personalization and sends to Retail API"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "trackEvent"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.user_events_source.name
      }
    }
    
    environment_variables = {
      BUILD_ENV = var.environment
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = var.function_concurrency
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID         = var.project_id
      CATALOG_NAME       = var.retail_catalog_name
      BRANCH_NAME        = var.retail_branch_name
      FIRESTORE_DATABASE = google_firestore_database.user_profiles_db.name
    }
    
    ingress_settings               = var.function_ingress_settings
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.user_events_source
  ]
}

# Cloud Function for serving recommendations
resource "google_cloudfunctions2_function" "recommendations_function" {
  name        = "get-recommendations-${local.resource_suffix}"
  location    = var.region
  description = "Generates and serves personalized product recommendations"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "getRecommendations"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.recommendations_source.name
      }
    }
    
    environment_variables = {
      BUILD_ENV = var.environment
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = var.function_concurrency
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID         = var.project_id
      CATALOG_NAME       = var.retail_catalog_name
      BRANCH_NAME        = var.retail_branch_name
      FIRESTORE_DATABASE = google_firestore_database.user_profiles_db.name
    }
    
    ingress_settings               = var.function_ingress_settings
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.recommendations_source
  ]
}

# Cloud Function IAM bindings to allow HTTP invocation
resource "google_cloudfunctions2_function_iam_binding" "catalog_sync_invoker" {
  count = var.function_ingress_settings == "ALLOW_ALL" ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.catalog_sync_function.name
  role           = "roles/cloudfunctions.invoker"
  members        = ["allUsers"]
}

resource "google_cloudfunctions2_function_iam_binding" "user_events_invoker" {
  count = var.function_ingress_settings == "ALLOW_ALL" ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.user_events_function.name
  role           = "roles/cloudfunctions.invoker"
  members        = ["allUsers"]
}

resource "google_cloudfunctions2_function_iam_binding" "recommendations_invoker" {
  count = var.function_ingress_settings == "ALLOW_ALL" ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.recommendations_function.name
  role           = "roles/cloudfunctions.invoker"
  members        = ["allUsers"]
}

# Firestore collection for user profiles (placeholder - collections are created by application)
resource "google_firestore_document" "user_profiles_collection_placeholder" {
  project     = var.project_id
  database    = google_firestore_database.user_profiles_db.name
  collection  = "user_profiles"
  document_id = "_placeholder"
  
  fields = jsonencode({
    created = {
      timestampValue = timestamp()
    }
    description = {
      stringValue = "Placeholder document for user profiles collection"
    }
    delete_me = {
      booleanValue = true
    }
  })
  
  depends_on = [google_firestore_database.user_profiles_db]
}

# Create sample product data in Cloud Storage for testing
resource "google_storage_bucket_object" "sample_products" {
  name   = "sample-products.json"
  bucket = google_storage_bucket.product_catalog_bucket.name
  
  content = jsonencode({
    products = [
      {
        id                = "product_001"
        title             = "Wireless Bluetooth Headphones"
        categories        = ["Electronics", "Audio", "Headphones"]
        price             = 99.99
        originalPrice     = 129.99
        currencyCode      = "USD"
        availability      = "IN_STOCK"
        attributes = {
          brand     = "TechAudio"
          color     = "Black"
          wireless  = "true"
        }
      },
      {
        id           = "product_002"
        title        = "Smart Fitness Watch"
        categories   = ["Electronics", "Wearables", "Fitness"]
        price        = 199.99
        currencyCode = "USD"
        availability = "IN_STOCK"
        attributes = {
          brand        = "FitTech"
          waterproof   = "true"
          battery_life = "7 days"
        }
      },
      {
        id           = "product_003"
        title        = "Organic Cotton T-Shirt"
        categories   = ["Clothing", "Men", "T-Shirts"]
        price        = 29.99
        currencyCode = "USD"
        availability = "IN_STOCK"
        attributes = {
          material = "Organic Cotton"
          size     = "Medium"
          color    = "Navy Blue"
        }
      }
    ]
  })
  
  content_type = "application/json"
}

# Log sink for function logs (optional)
resource "google_logging_project_sink" "function_logs_sink" {
  count = var.enable_logging ? 1 : 0
  
  name        = "retail-function-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.product_catalog_bucket.name}/logs"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name:\"catalog-sync-${local.resource_suffix}\" OR resource.labels.function_name:\"track-user-events-${local.resource_suffix}\" OR resource.labels.function_name:\"get-recommendations-${local.resource_suffix}\""
  
  unique_writer_identity = true
}

# Grant the log sink writer access to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.product_catalog_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs_sink[0].writer_identity
}
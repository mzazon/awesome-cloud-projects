# MongoDB to Firestore Migration Infrastructure
# This Terraform configuration deploys a complete migration solution including:
# - Firestore database in Native mode
# - Cloud Functions for migration and API compatibility
# - Secret Manager for secure credential storage
# - Cloud Build pipeline for automated migration
# - IAM roles and permissions

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention with random suffix
  name_prefix = "${var.environment}-mongo-migration"
  name_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.resource_labels, {
    environment = var.environment
    component   = "mongodb-firestore-migration"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "firestore.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  # Don't disable services when destroying the infrastructure
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Firestore database in Native mode
resource "google_firestore_database" "migration_database" {
  provider = google-beta
  
  project                     = var.project_id
  name                       = "(default)"
  location_id                = var.firestore_location
  type                       = "FIRESTORE_NATIVE"
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"

  depends_on = [google_project_service.required_apis]
}

# Store MongoDB connection string in Secret Manager
resource "google_secret_manager_secret" "mongodb_connection" {
  secret_id = "${local.name_prefix}-mongodb-connection-${local.name_suffix}"
  
  labels = local.common_labels
  
  replication {
    auto {
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Store the actual connection string value
resource "google_secret_manager_secret_version" "mongodb_connection_value" {
  secret      = google_secret_manager_secret.mongodb_connection.id
  secret_data = var.mongodb_connection_string
}

# Create service account for Cloud Functions
resource "google_service_account" "functions_sa" {
  account_id   = "${local.name_prefix}-functions-${local.name_suffix}"
  display_name = "Service Account for MongoDB Migration Functions"
  description  = "Service account used by Cloud Functions for MongoDB to Firestore migration"
}

# IAM binding for functions service account to access secrets
resource "google_secret_manager_secret_iam_binding" "functions_secret_access" {
  secret_id = google_secret_manager_secret.mongodb_connection.secret_id
  role      = "roles/secretmanager.secretAccessor"
  
  members = [
    "serviceAccount:${google_service_account.functions_sa.email}",
    "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
  ]
}

# IAM binding for functions service account to access Firestore
resource "google_project_iam_binding" "functions_firestore_access" {
  project = var.project_id
  role    = "roles/datastore.user"
  
  members = [
    "serviceAccount:${google_service_account.functions_sa.email}"
  ]
}

# IAM binding for Cloud Build service account
resource "google_project_iam_binding" "cloudbuild_additional_roles" {
  for_each = toset(var.cloud_build_service_account_roles)
  
  project = var.project_id
  role    = each.value
  
  members = [
    "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  ]
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-functions-${local.name_suffix}"
  location = var.region
  
  labels = local.common_labels
  
  # Lifecycle rule to clean up old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for function deployments
  versioning {
    enabled = true
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
}

# Create ZIP archive for migration function source code
data "archive_file" "migration_function_source" {
  type        = "zip"
  output_path = "${path.module}/migration-function.zip"
  
  source {
    content = file("${path.module}/functions/migration/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/migration/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload migration function source to Cloud Storage
resource "google_storage_bucket_object" "migration_function_source" {
  name   = "migration-function-${data.archive_file.migration_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.migration_function_source.output_path
}

# Create ZIP archive for API compatibility function source code
data "archive_file" "api_function_source" {
  type        = "zip"
  output_path = "${path.module}/api-function.zip"
  
  source {
    content = file("${path.module}/functions/api/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/api/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload API compatibility function source to Cloud Storage
resource "google_storage_bucket_object" "api_function_source" {
  name   = "api-function-${data.archive_file.api_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.api_function_source.output_path
}

# Deploy migration Cloud Function
resource "google_cloudfunctions2_function" "migration_function" {
  name     = "${local.name_prefix}-migration-${local.name_suffix}"
  location = var.region
  
  description = "Function to migrate MongoDB collections to Firestore"
  
  build_config {
    runtime     = "python312"
    entry_point = "migrate_collection"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.migration_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.migration_function_memory}Mi"
    timeout_seconds    = var.migration_function_timeout
    
    environment_variables = {
      GCP_PROJECT = var.project_id
    }
    
    service_account_email = google_service_account.functions_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_binding.functions_firestore_access,
    google_secret_manager_secret_iam_binding.functions_secret_access
  ]
}

# Create IAM policy for migration function to allow unauthenticated access
resource "google_cloudfunctions2_function_iam_binding" "migration_function_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.migration_function.name
  role           = "roles/cloudfunctions.invoker"
  
  members = [
    "allUsers"
  ]
}

# Deploy API compatibility Cloud Function
resource "google_cloudfunctions2_function" "api_function" {
  name     = "${local.name_prefix}-api-${local.name_suffix}"
  location = var.region
  
  description = "MongoDB-compatible API layer for Firestore"
  
  build_config {
    runtime     = "python312"
    entry_point = "mongo_api_compatibility"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.api_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 100
    min_instance_count = 0
    available_memory   = "${var.api_function_memory}Mi"
    timeout_seconds    = var.api_function_timeout
    
    ingress = "INGRESS_SETTINGS_ALLOW_ALL"
    
    service_account_email = google_service_account.functions_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_binding.functions_firestore_access
  ]
}

# Create IAM policy for API function to allow unauthenticated access
resource "google_cloudfunctions2_function_iam_binding" "api_function_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.api_function.name
  role           = "roles/cloudfunctions.invoker"
  
  members = [
    "allUsers"
  ]
}

# Create Cloud Build trigger for migration pipeline
resource "google_cloudbuild_trigger" "migration_pipeline" {
  name        = "${local.name_prefix}-pipeline-${local.name_suffix}"
  description = "Automated migration pipeline for MongoDB to Firestore"
  
  # Manual trigger - can be modified to use GitHub/Cloud Source Repositories
  manual_trigger {}
  
  build {
    step {
      name = "python:3.12"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        pip install pymongo google-cloud-secret-manager
        python -c "
        from google.cloud import secretmanager
        import pymongo
        import os
        
        client = secretmanager.SecretManagerServiceClient()
        name = f'projects/$PROJECT_ID/secrets/$_SECRET_NAME/versions/latest'
        response = client.access_secret_version(request={'name': name})
        connection_string = response.payload.data.decode('UTF-8')
        
        mongo_client = pymongo.MongoClient(connection_string)
        databases = mongo_client.list_database_names()
        print(f'✅ MongoDB connection validated. Databases found: {databases}')
        "
        EOT
      ]
    }
    
    step {
      name = "gcr.io/google.com/cloudsdktool/cloud-sdk:latest"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        # Get migration function URL
        MIGRATION_URL=$(gcloud functions describe ${google_cloudfunctions2_function.migration_function.name} \
            --region=${var.region} \
            --format="value(serviceConfig.uri)")
        
        # Migrate common collections (customize based on your schema)
        for collection in users products orders; do
          echo "Migrating collection: $collection"
          curl -X POST "$MIGRATION_URL" \
            -H "Content-Type: application/json" \
            -d "{\"collection\": \"$collection\", \"batch_size\": 100}" \
            --fail --silent --show-error
          echo "✅ Collection $collection migration completed"
        done
        EOT
      ]
    }
    
    step {
      name = "python:3.12"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        pip install google-cloud-firestore
        python -c "
        from google.cloud import firestore
        
        db = firestore.Client()
        collections = ['users', 'products', 'orders']
        
        for collection_name in collections:
            try:
                docs = list(db.collection(collection_name).limit(5).stream())
                count = len(docs)
                print(f'✅ Validation: {collection_name} has {count} documents in Firestore')
            except Exception as e:
                print(f'❌ Collection {collection_name}: Error - {e}')
        "
        EOT
      ]
    }
    
    substitutions = {
      _REGION      = var.region
      _SECRET_NAME = google_secret_manager_secret.mongodb_connection.secret_id
    }
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
      machine_type = "E2_HIGHCPU_8"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}
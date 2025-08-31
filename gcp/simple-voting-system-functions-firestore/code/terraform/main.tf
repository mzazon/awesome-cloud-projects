# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and labeling
locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = "voting-system"
    managed-by  = "terraform"
  })
  
  # Function names with suffix for uniqueness
  submit_function_name  = "${var.resource_prefix}-submit-${local.resource_suffix}"
  results_function_name = "${var.resource_prefix}-results-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "cloud_functions" {
  service = "cloudfunctions.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "cloud_build" {
  service = "cloudbuild.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "firestore" {
  service = "firestore.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "cloud_resource_manager" {
  service = "cloudresourcemanager.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

# Create Firestore database
resource "google_firestore_database" "voting_database" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location
  type        = var.firestore_database_type
  
  # Prevent accidental deletion
  deletion_policy = "DELETE"
  
  depends_on = [google_project_service.firestore]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-${var.resource_prefix}-functions-${local.resource_suffix}"
  location = var.region
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Configure object lifecycle for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.cloud_functions]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/voting-functions-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_source/index.js", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = templatefile("${path.module}/function_source/package.json", {
      function_name = "voting-system-functions"
    })
    filename = "package.json"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "voting-functions-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Ensure function redeployment when source changes
  detect_md5hash = data.archive_file.function_source.output_md5
}

# IAM service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "${var.resource_prefix}-functions-sa-${local.resource_suffix}"
  display_name = "Voting System Functions Service Account"
  description  = "Service account for voting system Cloud Functions"
}

# Grant Firestore access to the service account
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Grant Cloud Functions Invoker role for public access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "submit_function_invoker" {
  count = var.allow_unauthenticated_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.submit_vote.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "results_function_invoker" {
  count = var.allow_unauthenticated_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.get_results.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Function for vote submission
resource "google_cloudfunctions2_function" "submit_vote" {
  name     = local.submit_function_name
  location = var.region
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "submitVote"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.functions_max_instances
    min_instance_count    = 0
    available_memory      = "${var.functions_memory}Mi"
    timeout_seconds       = var.functions_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = var.project_id
      FIRESTORE_DATABASE   = google_firestore_database.voting_database.name
    }
    
    # Enable HTTP/2 for better performance
    ingress_settings = "ALLOW_ALL"
    
    # Security settings
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.cloud_functions,
    google_project_service.cloud_build,
    google_firestore_database.voting_database
  ]
}

# Cloud Function for retrieving results
resource "google_cloudfunctions2_function" "get_results" {
  name     = local.results_function_name
  location = var.region
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "getResults"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.functions_max_instances
    min_instance_count    = 0
    available_memory      = "${var.functions_memory}Mi"
    timeout_seconds       = var.functions_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = var.project_id
      FIRESTORE_DATABASE   = google_firestore_database.voting_database.name
    }
    
    # Enable HTTP/2 for better performance
    ingress_settings = "ALLOW_ALL"
    
    # Security settings
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.cloud_functions,
    google_project_service.cloud_build,
    google_firestore_database.voting_database
  ]
}

# Optional: Create Firestore indexes for better query performance
resource "google_firestore_index" "vote_topic_index" {
  project    = var.project_id
  database   = google_firestore_database.voting_database.name
  collection = "votes"
  
  fields {
    field_path = "topicId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.voting_database]
}

resource "google_firestore_index" "vote_count_index" {
  project    = var.project_id
  database   = google_firestore_database.voting_database.name
  collection = "voteCounts"
  
  fields {
    field_path = "topicId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "lastUpdated"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.voting_database]
}
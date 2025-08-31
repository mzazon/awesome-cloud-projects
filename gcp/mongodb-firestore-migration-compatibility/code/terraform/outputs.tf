# Outputs for MongoDB to Firestore migration infrastructure

output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "firestore_database_name" {
  description = "The name of the Firestore database"
  value       = google_firestore_database.migration_database.name
}

output "firestore_database_location" {
  description = "The location of the Firestore database"
  value       = google_firestore_database.migration_database.location_id
}

output "firestore_database_type" {
  description = "The type of the Firestore database (FIRESTORE_NATIVE)"
  value       = google_firestore_database.migration_database.type
}

output "mongodb_secret_name" {
  description = "The name of the Secret Manager secret containing MongoDB connection string"
  value       = google_secret_manager_secret.mongodb_connection.secret_id
}

output "mongodb_secret_id" {
  description = "The full resource ID of the MongoDB connection secret"
  value       = google_secret_manager_secret.mongodb_connection.id
}

output "functions_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.functions_sa.email
}

output "functions_service_account_id" {
  description = "The ID of the service account used by Cloud Functions"
  value       = google_service_account.functions_sa.account_id
}

output "migration_function_name" {
  description = "The name of the migration Cloud Function"
  value       = google_cloudfunctions2_function.migration_function.name
}

output "migration_function_url" {
  description = "The HTTP trigger URL for the migration Cloud Function"
  value       = google_cloudfunctions2_function.migration_function.service_config[0].uri
}

output "api_function_name" {
  description = "The name of the API compatibility Cloud Function"
  value       = google_cloudfunctions2_function.api_function.name
}

output "api_function_url" {
  description = "The HTTP trigger URL for the API compatibility Cloud Function"
  value       = google_cloudfunctions2_function.api_function.service_config[0].uri
  sensitive   = false
}

output "function_source_bucket" {
  description = "The name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "The URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

output "cloud_build_trigger_name" {
  description = "The name of the Cloud Build trigger for migration pipeline"
  value       = google_cloudbuild_trigger.migration_pipeline.name
}

output "cloud_build_trigger_id" {
  description = "The ID of the Cloud Build trigger for migration pipeline"
  value       = google_cloudbuild_trigger.migration_pipeline.trigger_id
}

# Sensitive outputs for application configuration
output "migration_endpoint" {
  description = "Complete endpoint configuration for migration function"
  value = {
    url        = google_cloudfunctions2_function.migration_function.service_config[0].uri
    name       = google_cloudfunctions2_function.migration_function.name
    region     = var.region
    project_id = var.project_id
  }
  sensitive = false
}

output "api_endpoint" {
  description = "Complete endpoint configuration for API compatibility function"
  value = {
    url        = google_cloudfunctions2_function.api_function.service_config[0].uri
    name       = google_cloudfunctions2_function.api_function.name
    region     = var.region
    project_id = var.project_id
  }
  sensitive = false
}

# Resource summary for documentation
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    firestore_database     = google_firestore_database.migration_database.name
    migration_function     = google_cloudfunctions2_function.migration_function.name
    api_function          = google_cloudfunctions2_function.api_function.name
    secret_manager_secret = google_secret_manager_secret.mongodb_connection.secret_id
    service_account       = google_service_account.functions_sa.email
    storage_bucket        = google_storage_bucket.function_source.name
    build_trigger         = google_cloudbuild_trigger.migration_pipeline.name
    environment           = var.environment
  }
}

# URLs for quick testing and integration
output "quick_test_commands" {
  description = "Commands for quick testing of the deployed infrastructure"
  value = {
    test_migration_function = "curl -X POST '${google_cloudfunctions2_function.migration_function.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"collection\": \"test\", \"batch_size\": 10}'"
    test_api_function      = "curl -X GET '${google_cloudfunctions2_function.api_function.service_config[0].uri}?collection=test&limit=5'"
    trigger_build_pipeline = "gcloud builds triggers run ${google_cloudbuild_trigger.migration_pipeline.name} --region=${var.region}"
    check_firestore_status = "gcloud firestore databases describe --database=${google_firestore_database.migration_database.name}"
  }
}
# Output Values for E-commerce Personalization Infrastructure
# These outputs provide important information about the deployed resources

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = local.resource_suffix
}

# Cloud Storage Outputs
output "product_catalog_bucket_name" {
  description = "Name of the Cloud Storage bucket for product catalog data"
  value       = google_storage_bucket.product_catalog_bucket.name
}

output "product_catalog_bucket_url" {
  description = "URL of the Cloud Storage bucket for product catalog data"
  value       = google_storage_bucket.product_catalog_bucket.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

output "sample_products_url" {
  description = "URL of the sample products JSON file"
  value       = "gs://${google_storage_bucket.product_catalog_bucket.name}/${google_storage_bucket_object.sample_products.name}"
}

# Firestore Database Outputs
output "firestore_database_name" {
  description = "Name of the Firestore database for user profiles"
  value       = google_firestore_database.user_profiles_db.name
}

output "firestore_database_id" {
  description = "Full resource ID of the Firestore database"
  value       = google_firestore_database.user_profiles_db.id
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.user_profiles_db.location_id
}

# Service Account Outputs
output "function_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_unique_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.unique_id
}

# Cloud Functions Outputs
output "catalog_sync_function_name" {
  description = "Name of the catalog synchronization Cloud Function"
  value       = google_cloudfunctions2_function.catalog_sync_function.name
}

output "catalog_sync_function_url" {
  description = "HTTP trigger URL for the catalog synchronization function"
  value       = google_cloudfunctions2_function.catalog_sync_function.service_config[0].uri
}

output "user_events_function_name" {
  description = "Name of the user events tracking Cloud Function"
  value       = google_cloudfunctions2_function.user_events_function.name
}

output "user_events_function_url" {
  description = "HTTP trigger URL for the user events tracking function"
  value       = google_cloudfunctions2_function.user_events_function.service_config[0].uri
}

output "recommendations_function_name" {
  description = "Name of the recommendations serving Cloud Function"
  value       = google_cloudfunctions2_function.recommendations_function.name
}

output "recommendations_function_url" {
  description = "HTTP trigger URL for the recommendations serving function"
  value       = google_cloudfunctions2_function.recommendations_function.service_config[0].uri
}

# Retail API Configuration Outputs
output "retail_catalog_name" {
  description = "Name of the Retail API catalog"
  value       = var.retail_catalog_name
}

output "retail_branch_name" {
  description = "Name of the Retail API branch"
  value       = var.retail_branch_name
}

output "retail_catalog_full_name" {
  description = "Full resource name of the Retail API catalog"
  value       = "projects/${var.project_id}/locations/global/catalogs/${var.retail_catalog_name}"
}

output "retail_branch_full_name" {
  description = "Full resource name of the Retail API branch"
  value       = "projects/${var.project_id}/locations/global/catalogs/${var.retail_catalog_name}/branches/${var.retail_branch_name}"
}

# API Endpoints for Testing
output "test_catalog_sync_curl" {
  description = "cURL command to test catalog synchronization"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.catalog_sync_function.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d @sample_products.json
  EOT
}

output "test_user_events_curl" {
  description = "cURL command to test user event tracking"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.user_events_function.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d '{
        "userId": "user_123",
        "eventType": "detail-page-view",
        "productId": "product_001",
        "pageInfo": {
          "pageCategory": "product_detail"
        }
      }'
  EOT
}

output "test_recommendations_curl" {
  description = "cURL command to test recommendations generation"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.recommendations_function.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d '{
        "userId": "user_123",
        "pageType": "home-page",
        "filter": "availability: \"IN_STOCK\""
      }'
  EOT
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Security and Configuration
output "function_ingress_settings" {
  description = "Ingress settings for Cloud Functions"
  value       = var.function_ingress_settings
}

output "firestore_point_in_time_recovery" {
  description = "Point-in-time recovery status for Firestore database"
  value       = google_firestore_database.user_profiles_db.point_in_time_recovery_enablement
}

output "bucket_uniform_access" {
  description = "Uniform bucket-level access status for product catalog bucket"
  value       = google_storage_bucket.product_catalog_bucket.uniform_bucket_level_access
}

output "bucket_public_access_prevention" {
  description = "Public access prevention status for product catalog bucket"
  value       = google_storage_bucket.product_catalog_bucket.public_access_prevention
}

# Cost Monitoring
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    cloud_functions = "~$10-50 (depends on invocations)"
    cloud_storage   = "~$5-20 (depends on storage and operations)"
    firestore       = "~$5-25 (depends on reads/writes)"
    retail_api      = "~$0-100 (depends on API calls)"
    total_estimate  = "~$20-195 per month"
  }
}

# Monitoring and Logging
output "logging_enabled" {
  description = "Whether logging is enabled for the deployment"
  value       = var.enable_logging
}

output "log_retention_days" {
  description = "Number of days logs will be retained"
  value       = var.log_retention_days
}

# Environment Information
output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "terraform_version" {
  description = "Terraform version used for this deployment"
  value       = "~> 1.8.0"
}

output "google_provider_version" {
  description = "Google Cloud provider version used"
  value       = "~> 6.44.0"
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    1. Download the sample products file: gsutil cp ${google_storage_bucket_object.sample_products.name} ./sample_products.json
    2. Test catalog sync: ${google_cloudfunctions2_function.catalog_sync_function.service_config[0].uri}
    3. Test user events: ${google_cloudfunctions2_function.user_events_function.service_config[0].uri}
    4. Test recommendations: ${google_cloudfunctions2_function.recommendations_function.service_config[0].uri}
    5. Monitor functions: gcloud functions logs read --region=${var.region}
    6. Check Firestore data: gcloud firestore export gs://${google_storage_bucket.product_catalog_bucket.name}/firestore-export
  EOT
}
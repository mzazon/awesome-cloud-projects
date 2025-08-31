# Outputs for AI-Powered App Development with Firebase Studio and Gemini
# These outputs provide important information for accessing and configuring the deployed resources

# Project and basic configuration outputs
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "app_name" {
  description = "The application name prefix used for resource naming"
  value       = var.app_name
}

output "resource_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Firebase project and web app outputs
output "firebase_project_id" {
  description = "The Firebase project ID (same as Google Cloud project ID)"
  value       = google_firebase_project.default.project
}

output "firebase_web_app_id" {
  description = "The Firebase web app ID for Studio integration"
  value       = google_firebase_web_app.studio_app.app_id
}

output "firebase_studio_url" {
  description = "URL to access Firebase Studio development environment"
  value       = "https://studio.firebase.google.com"
}

output "firebase_console_url" {
  description = "URL to access Firebase Console for project management"
  value       = "https://console.firebase.google.com/project/${var.project_id}"
}

# Firestore database outputs
output "firestore_database_name" {
  description = "The name of the Firestore database"
  value       = var.enable_firestore ? google_firestore_database.database[0].name : null
}

output "firestore_location" {
  description = "The location of the Firestore database"
  value       = var.enable_firestore ? google_firestore_database.database[0].location_id : null
}

output "firestore_database_id" {
  description = "The full resource ID of the Firestore database"
  value       = var.enable_firestore ? google_firestore_database.database[0].id : null
}

# Cloud Run API service outputs
output "api_service_name" {
  description = "The name of the Cloud Run API service"
  value       = google_cloud_run_v2_service.api_service.name
}

output "api_service_url" {
  description = "The URL of the deployed Cloud Run API service"
  value       = google_cloud_run_v2_service.api_service.uri
}

output "api_service_location" {
  description = "The location of the Cloud Run API service"
  value       = google_cloud_run_v2_service.api_service.location
}

# Storage and registry outputs
output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket for Firebase Storage"
  value       = google_storage_bucket.firebase_storage.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.firebase_storage.url
}

output "artifact_registry_repository" {
  description = "The name of the Artifact Registry repository for containers"
  value       = var.enable_app_hosting ? google_artifact_registry_repository.container_registry[0].name : null
}

output "artifact_registry_url" {
  description = "The URL of the Artifact Registry repository"
  value       = var.enable_app_hosting ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry[0].repository_id}" : null
}

# Secret Manager outputs
output "gemini_api_key_secret_name" {
  description = "The name of the Secret Manager secret for Gemini API key"
  value       = var.enable_secret_manager ? google_secret_manager_secret.gemini_api_key[0].secret_id : null
}

output "gemini_api_key_secret_id" {
  description = "The full resource ID of the Gemini API key secret"
  value       = var.enable_secret_manager ? google_secret_manager_secret.gemini_api_key[0].id : null
}

# Authentication configuration outputs
output "firebase_auth_domain" {
  description = "The Firebase Authentication domain for the project"
  value       = "${var.project_id}.firebaseapp.com"
}

output "identity_platform_config" {
  description = "Information about the Identity Platform configuration"
  value = {
    project                   = google_identity_platform_config.auth_config.project
    autodelete_anonymous_users = google_identity_platform_config.auth_config.autodelete_anonymous_users
  }
  sensitive = false
}

# Service account outputs
output "cloud_build_service_account_email" {
  description = "The email of the Cloud Build service account"
  value       = var.enable_cloud_build ? google_service_account.cloud_build_sa[0].email : null
}

output "cloud_build_service_account_name" {
  description = "The name of the Cloud Build service account"
  value       = var.enable_cloud_build ? google_service_account.cloud_build_sa[0].name : null
}

# Monitoring and alerting outputs
output "notification_channels" {
  description = "The monitoring notification channels for alerts"
  value = var.enable_monitoring && length(var.notification_emails) > 0 ? [
    for channel in google_monitoring_notification_channel.email_alerts : {
      name  = channel.name
      email = channel.labels.email_address
    }
  ] : []
}

output "uptime_check_name" {
  description = "The name of the API uptime check"
  value       = var.enable_monitoring ? google_monitoring_uptime_check_config.api_uptime_check[0].name : null
}

output "budget_name" {
  description = "The name of the billing budget"
  value       = var.enable_monitoring && var.budget_amount > 0 ? google_billing_budget.project_budget[0].name : null
}

# Development and deployment information
output "development_urls" {
  description = "Important URLs for development and management"
  value = {
    firebase_studio   = "https://studio.firebase.google.com"
    firebase_console  = "https://console.firebase.google.com/project/${var.project_id}"
    cloud_console     = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    firestore_console = "https://console.firebase.google.com/project/${var.project_id}/firestore"
    cloud_run_console = "https://console.cloud.google.com/run?project=${var.project_id}"
    cloud_build_console = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
  }
}

# Firebase configuration for client SDKs
output "firebase_config" {
  description = "Firebase configuration object for client-side SDKs"
  value = {
    apiKey            = "AIza..." # This should be retrieved from Firebase Console
    authDomain        = "${var.project_id}.firebaseapp.com"
    projectId         = var.project_id
    storageBucket     = google_storage_bucket.firebase_storage.name
    messagingSenderId = "123456789"  # This should be retrieved from Firebase Console
    appId             = google_firebase_web_app.studio_app.app_id
  }
  sensitive = false
}

# Instructions for next steps
output "next_steps" {
  description = "Instructions for completing the setup"
  value = {
    step_1 = "Visit Firebase Studio at https://studio.firebase.google.com and select your project"
    step_2 = "Configure OAuth providers in Firebase Console Authentication section"
    step_3 = "Update API service with your application code using Cloud Build or manual deployment"
    step_4 = "Configure GitHub repository for App Hosting continuous deployment"
    step_5 = "Test the application and monitor using Cloud Console dashboards"
  }
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    firebase_project_created      = true
    firestore_database_enabled    = var.enable_firestore
    cloud_run_api_deployed       = true
    storage_bucket_created        = true
    secret_manager_configured     = var.enable_secret_manager
    artifact_registry_configured = var.enable_app_hosting
    monitoring_enabled           = var.enable_monitoring
    budget_configured            = var.enable_monitoring && var.budget_amount > 0
    total_apis_enabled           = length(local.required_apis)
  }
}

# Cost estimation information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (in USD)"
  value = {
    firestore_reads_writes = "Free tier: 50K reads, 20K writes per day"
    cloud_run_requests     = "Free tier: 2M requests per month"
    cloud_storage          = "Free tier: 5GB per month"
    secret_manager         = "$0.06 per 10K operations"
    artifact_registry      = "$0.10 per GB per month"
    cloud_build            = "Free tier: 120 build-minutes per day"
    estimated_total        = "$5-20 per month (depending on usage)"
    budget_alert_threshold = "${var.budget_amount} USD"
  }
}
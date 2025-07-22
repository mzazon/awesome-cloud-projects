# Output Values for Firebase Studio and Gemini Code Assist Development Environment
# This file defines all the outputs that will be displayed after deployment

# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "project_number" {
  description = "The Google Cloud project number"
  value       = data.google_project.current.number
}

output "region" {
  description = "The deployment region"
  value       = var.region
}

output "zone" {
  description = "The deployment zone"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.suffix.hex
}

# Network Configuration
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.firebase_studio_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.firebase_studio_vpc.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.firebase_studio_subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = google_compute_subnetwork.firebase_studio_subnet.ip_cidr_range
}

# Source Repository Information
output "source_repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.ai_app_repo.name
}

output "source_repository_url" {
  description = "Clone URL for the Cloud Source Repository"
  value       = google_sourcerepo_repository.ai_app_repo.url
}

output "source_repository_clone_command" {
  description = "Git clone command for the repository"
  value       = "git clone ${google_sourcerepo_repository.ai_app_repo.url}"
}

# Artifact Registry Information
output "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.ai_app_registry.repository_id
}

output "artifact_registry_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_registry.repository_id}"
}

output "docker_configure_command" {
  description = "Command to configure Docker for Artifact Registry"
  value       = "gcloud auth configure-docker ${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev"
}

# Cloud Build Information
output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.ai_app_build_trigger.name
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.ai_app_build_trigger.trigger_id
}

output "cloud_build_service_account" {
  description = "Email of the Cloud Build service account"
  value       = google_service_account.cloud_build.email
}

# Cloud Run Information
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_service.ai_app.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_service.ai_app.status[0].url
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_service.ai_app.location
}

# Firebase Configuration
output "firebase_project_id" {
  description = "Firebase project ID"
  value       = google_firebase_project.firebase_project.project
}

output "firebase_location" {
  description = "Firebase project location"
  value       = google_firebase_project_location.firebase_location.location_id
}

output "firebase_web_app_id" {
  description = "Firebase web app ID"
  value       = google_firebase_web_app.firebase_web_app.app_id
}

output "firebase_web_app_config" {
  description = "Firebase web app configuration"
  value = {
    apiKey            = google_firebase_web_app.firebase_web_app.api_key
    authDomain        = "${var.project_id}.firebaseapp.com"
    projectId         = var.project_id
    storageBucket     = "${var.project_id}.appspot.com"
    messagingSenderId = data.google_project.current.number
    appId             = google_firebase_web_app.firebase_web_app.app_id
  }
  sensitive = true
}

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.firestore_db.name
}

# Service Account Information
output "gemini_service_account_email" {
  description = "Email of the Gemini Code Assist service account"
  value       = google_service_account.gemini_code_assist.email
}

output "gemini_service_account_id" {
  description = "ID of the Gemini Code Assist service account"
  value       = google_service_account.gemini_code_assist.account_id
}

# Secret Manager Information
output "firebase_config_secret_id" {
  description = "Secret Manager secret ID for Firebase configuration"
  value       = google_secret_manager_secret.firebase_config.secret_id
}

output "firebase_config_secret_name" {
  description = "Full name of the Firebase configuration secret"
  value       = google_secret_manager_secret.firebase_config.name
}

# Binary Authorization Information (conditional)
output "binary_authorization_attestor_name" {
  description = "Name of the Binary Authorization attestor"
  value       = var.enable_binary_authorization ? google_binary_authorization_attestor.attestor[0].name : null
}

output "container_analysis_note_name" {
  description = "Name of the Container Analysis note"
  value       = var.enable_binary_authorization ? google_container_analysis_note.attestor_note[0].name : null
}

# Monitoring Information (conditional)
output "monitoring_notification_channel" {
  description = "Email notification channel for monitoring alerts"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email_notification[0].name : null
}

output "log_bucket_name" {
  description = "Name of the Cloud Storage bucket for logs"
  value       = var.enable_monitoring ? google_storage_bucket.log_bucket[0].name : null
}

output "log_sink_name" {
  description = "Name of the logging sink"
  value       = var.enable_monitoring ? google_logging_project_sink.ai_app_logs[0].name : null
}

# Cost Management Information (conditional)
output "billing_budget_name" {
  description = "Name of the billing budget"
  value       = var.enable_cost_alerts ? google_billing_budget.development_budget[0].display_name : null
}

# Quick Start Commands
output "firebase_studio_url" {
  description = "URL to access Firebase Studio"
  value       = "https://studio.firebase.google.com"
}

output "google_cloud_console_url" {
  description = "URL to access Google Cloud Console for this project"
  value       = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
}

output "firebase_console_url" {
  description = "URL to access Firebase Console for this project"
  value       = "https://console.firebase.google.com/project/${var.project_id}"
}

# Development Environment Setup Commands
output "development_setup_commands" {
  description = "Commands to set up the development environment"
  value = [
    "# Set up environment variables",
    "export PROJECT_ID=${var.project_id}",
    "export REGION=${var.region}",
    "export REPO_URL=${google_sourcerepo_repository.ai_app_repo.url}",
    "export REGISTRY_URL=${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_registry.repository_id}",
    "",
    "# Configure Git credentials",
    "git config --global credential.helper gcloud.sh",
    "",
    "# Configure Docker for Artifact Registry",
    "gcloud auth configure-docker ${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev",
    "",
    "# Clone the repository",
    "git clone ${google_sourcerepo_repository.ai_app_repo.url}",
    "",
    "# Access Firebase Studio",
    "echo 'Navigate to: https://studio.firebase.google.com'",
    "echo 'Select project: ${var.project_id}'"
  ]
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = [
    "# Verify enabled APIs",
    "gcloud services list --enabled --project=${var.project_id}",
    "",
    "# Check Cloud Run service status",
    "gcloud run services describe ${google_cloud_run_service.ai_app.name} --region=${var.region} --project=${var.project_id}",
    "",
    "# Test Cloud Run service",
    "curl -H 'Authorization: Bearer $(gcloud auth print-access-token)' ${google_cloud_run_service.ai_app.status[0].url}",
    "",
    "# Check Cloud Build triggers",
    "gcloud builds triggers list --project=${var.project_id}",
    "",
    "# Verify Artifact Registry",
    "gcloud artifacts repositories describe ${google_artifact_registry_repository.ai_app_registry.repository_id} --location=${var.region} --project=${var.project_id}",
    "",
    "# Check Firebase project",
    "firebase projects:list | grep ${var.project_id}"
  ]
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    project_id           = var.project_id
    region              = var.region
    vpc_network         = google_compute_network.firebase_studio_vpc.name
    source_repository   = google_sourcerepo_repository.ai_app_repo.name
    artifact_registry   = google_artifact_registry_repository.ai_app_registry.repository_id
    cloud_run_service   = google_cloud_run_service.ai_app.name
    firebase_project    = google_firebase_project.firebase_project.project
    gemini_service_account = google_service_account.gemini_code_assist.email
    resource_suffix     = random_id.suffix.hex
  }
}
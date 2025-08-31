# Outputs for automated code refactoring infrastructure
# These outputs provide essential information for using and managing the deployed resources

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "repository_name" {
  description = "Name of the created Source Repository"
  value       = google_sourcerepo_repository.refactoring_repo.name
}

output "repository_url" {
  description = "HTTPS clone URL for the Source Repository"
  value       = google_sourcerepo_repository.refactoring_repo.url
  sensitive   = false
}

output "repository_clone_command" {
  description = "Command to clone the repository locally"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.refactoring_repo.name} --project=${var.project_id}"
}

output "service_account_email" {
  description = "Email of the service account used for Cloud Build operations"
  value       = google_service_account.refactor_service_account.email
}

output "service_account_id" {
  description = "Full ID of the service account"
  value       = google_service_account.refactor_service_account.id
}

output "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.refactoring_trigger.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.refactoring_trigger.trigger_id
}

output "build_trigger_url" {
  description = "Console URL for managing the Cloud Build trigger"
  value       = "https://console.cloud.google.com/cloud-build/triggers/edit/${google_cloudbuild_trigger.refactoring_trigger.trigger_id}?project=${var.project_id}"
}

output "source_repo_console_url" {
  description = "Console URL for managing the Source Repository"
  value       = "https://source.cloud.google.com/repo/${google_sourcerepo_repository.refactoring_repo.name}?project=${var.project_id}"
}

output "cloud_build_console_url" {
  description = "Console URL for monitoring Cloud Build history"
  value       = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
}

output "build_logs_bucket" {
  description = "Cloud Storage bucket for build logs (if created)"
  value       = var.log_bucket != "" ? google_storage_bucket.build_logs[0].name : null
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this solution"
  value       = var.enable_apis ? local.required_apis : []
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "service_account_roles" {
  description = "IAM roles assigned to the service account"
  value       = local.service_account_roles
}

output "build_machine_type" {
  description = "Machine type configured for Cloud Build workers"
  value       = var.build_machine_type
}

output "build_timeout" {
  description = "Build timeout configuration in seconds"
  value       = var.build_timeout
}

output "worker_pool_name" {
  description = "Name of the Cloud Build worker pool (if created)"
  value       = var.build_machine_type == "E2_HIGHCPU_32" ? google_cloudbuild_worker_pool.refactoring_pool[0].name : null
}

output "repository_labels" {
  description = "Labels applied to the Source Repository"
  value       = var.labels
}

output "quick_start_commands" {
  description = "Commands to get started with the automated refactoring system"
  value = {
    clone_repo = "gcloud source repos clone ${google_sourcerepo_repository.refactoring_repo.name} --project=${var.project_id}"
    check_trigger = "gcloud builds triggers list --filter='name:${google_cloudbuild_trigger.refactoring_trigger.name}' --project=${var.project_id}"
    view_builds = "gcloud builds list --limit=5 --project=${var.project_id}"
    manual_trigger = "gcloud builds submit --config=cloudbuild.yaml --project=${var.project_id}"
  }
}

output "gemini_integration_status" {
  description = "Status of Gemini Code Assist integration"
  value = {
    api_enabled = contains(local.required_apis, "cloudaicompanion.googleapis.com")
    service_account_permission = "roles/cloudaicompanion.user"
    integration_note = "For full Gemini integration, configure IDE plugins or Cloud Shell Editor"
  }
}

output "cost_optimization_notes" {
  description = "Cost optimization recommendations for this infrastructure"
  value = {
    build_frequency = "Monitor build trigger frequency to optimize costs"
    machine_type = "Consider smaller machine types for simple refactoring tasks"
    log_retention = "Build logs are retained for 30 days by default"
    worker_pool = var.build_machine_type == "E2_HIGHCPU_32" ? "Dedicated worker pool created for high-performance builds" : "Using shared Cloud Build infrastructure"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Clone the repository using: gcloud source repos clone ${google_sourcerepo_repository.refactoring_repo.name} --project=${var.project_id}",
    "Add sample code and cloudbuild.yaml configuration file",
    "Push code to main branch to trigger automated refactoring",
    "Monitor builds at: https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}",
    "Configure Gemini Code Assist in your IDE for enhanced AI assistance"
  ]
}
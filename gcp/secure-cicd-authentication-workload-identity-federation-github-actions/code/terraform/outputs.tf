# Output values for Workload Identity Federation with GitHub Actions
# These outputs provide essential information for configuring GitHub Actions workflows

# Project Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

# Workload Identity Federation Configuration
output "workload_identity_pool_name" {
  description = "The full resource name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_pool.name
  sensitive   = false
}

output "workload_identity_pool_id" {
  description = "The ID of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
}

output "workload_identity_provider_name" {
  description = "The full resource name of the GitHub OIDC provider (use this in GitHub Actions)"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
  sensitive   = false
}

output "workload_identity_provider_id" {
  description = "The ID of the GitHub OIDC provider"
  value       = google_iam_workload_identity_pool_provider.github_provider.workload_identity_pool_provider_id
}

# Service Account Information
output "service_account_email" {
  description = "The email address of the GitHub Actions service account (use this in GitHub Actions)"
  value       = google_service_account.github_actions.email
  sensitive   = false
}

output "service_account_id" {
  description = "The ID of the GitHub Actions service account"
  value       = google_service_account.github_actions.account_id
}

output "service_account_unique_id" {
  description = "The unique ID of the GitHub Actions service account"
  value       = google_service_account.github_actions.unique_id
}

# Artifact Registry Information
output "artifact_registry_repository_name" {
  description = "The name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.repository_id
}

output "artifact_registry_repository_url" {
  description = "The full URL of the Artifact Registry repository for docker commands"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}"
}

output "artifact_registry_location" {
  description = "The location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.location
}

# Cloud Run Information
output "cloud_run_service_name" {
  description = "The name of the Cloud Run service"
  value       = google_cloud_run_v2_service.demo_app.name
}

output "cloud_run_service_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.demo_app.uri
  sensitive   = false
}

output "cloud_run_service_location" {
  description = "The location of the Cloud Run service"
  value       = google_cloud_run_v2_service.demo_app.location
}

# GitHub Actions Configuration Values
output "github_actions_workflow_config" {
  description = "Configuration values for GitHub Actions workflow"
  value = {
    workload_identity_provider = google_iam_workload_identity_pool_provider.github_provider.name
    service_account           = google_service_account.github_actions.email
    project_id               = var.project_id
    region                   = var.region
    artifact_repository      = google_artifact_registry_repository.container_repo.repository_id
    cloud_run_service        = google_cloud_run_v2_service.demo_app.name
    docker_registry_url      = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}"
  }
  sensitive = false
}

# GitHub Repository Configuration
output "github_repository_full" {
  description = "The full GitHub repository name (owner/repo) configured for access"
  value       = "${var.github_repo_owner}/${var.github_repo_name}"
}

output "additional_github_repositories" {
  description = "Additional GitHub repositories configured for access"
  value       = var.additional_github_repos
}

# Security Information
output "iam_roles_assigned" {
  description = "List of IAM roles assigned to the GitHub Actions service account"
  value       = local.all_iam_roles
}

output "attribute_conditions" {
  description = "Attribute conditions applied to the OIDC provider for security"
  value       = google_iam_workload_identity_pool_provider.github_provider.attribute_condition
}

# Resource Naming
output "resource_prefix" {
  description = "The prefix used for naming resources"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "The random suffix applied to resource names"
  value       = random_id.suffix.hex
}

# Instructions for GitHub Actions Setup
output "github_actions_setup_instructions" {
  description = "Instructions for setting up GitHub Actions with Workload Identity Federation"
  value = <<-EOT
    To configure GitHub Actions with Workload Identity Federation:
    
    1. Add the following to your GitHub Actions workflow:
    
    ```yaml
    permissions:
      contents: read
      id-token: write
    
    steps:
    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: '${google_iam_workload_identity_pool_provider.github_provider.name}'
        service_account: '${google_service_account.github_actions.email}'
    
    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2
    ```
    
    2. Use these environment variables in your workflow:
       PROJECT_ID: ${var.project_id}
       REGION: ${var.region}
       ARTIFACT_REPO: ${google_artifact_registry_repository.container_repo.repository_id}
       SERVICE_NAME: ${google_cloud_run_v2_service.demo_app.name}
    
    3. Docker registry URL for image pushes:
       ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}
    
    4. Cloud Run service URL (after deployment):
       ${google_cloud_run_v2_service.demo_app.uri}
  EOT
  sensitive = false
}

# API Status
output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled"
  value       = var.enable_apis ? local.required_apis : []
}

# Tags Applied
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = local.resource_tags
}
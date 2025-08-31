# Output values for GitOps Development Workflow Infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Project and region information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming to ensure uniqueness"
  value       = random_id.suffix.hex
}

# Network information
output "network_name" {
  description = "Name of the VPC network used by the infrastructure"
  value       = local.network_name
}

output "subnet_name" {
  description = "Name of the subnet used by the infrastructure"
  value       = local.subnet_name
}

output "network_self_link" {
  description = "Self-link of the VPC network used by the infrastructure"
  value       = local.network_self_link
}

# GKE cluster information
output "gke_staging_cluster_name" {
  description = "Name of the GKE staging cluster"
  value       = google_container_cluster.staging.name
}

output "gke_staging_cluster_endpoint" {
  description = "Endpoint for the GKE staging cluster"
  value       = google_container_cluster.staging.endpoint
  sensitive   = true
}

output "gke_staging_cluster_location" {
  description = "Location of the GKE staging cluster"
  value       = google_container_cluster.staging.location
}

output "gke_production_cluster_name" {
  description = "Name of the GKE production cluster"
  value       = google_container_cluster.production.name
}

output "gke_production_cluster_endpoint" {
  description = "Endpoint for the GKE production cluster"
  value       = google_container_cluster.production.endpoint
  sensitive   = true
}

output "gke_production_cluster_location" {
  description = "Location of the GKE production cluster"
  value       = google_container_cluster.production.location
}

# Commands to get cluster credentials
output "gke_staging_get_credentials_command" {
  description = "Command to get credentials for the staging GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.staging.name} --region=${google_container_cluster.staging.location} --project=${var.project_id}"
}

output "gke_production_get_credentials_command" {
  description = "Command to get credentials for the production GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.production.name} --region=${google_container_cluster.production.location} --project=${var.project_id}"
}

# Cloud Workstations information
output "workstation_cluster_name" {
  description = "Name of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
}

output "workstation_config_name" {
  description = "Name of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.dev_config.workstation_config_id
}

output "workstation_instance_name" {
  description = "Name of the Cloud Workstation instance"
  value       = google_workstations_workstation.dev_workstation.workstation_id
}

output "workstation_access_command" {
  description = "Command to start and access the Cloud Workstation"
  value       = "gcloud workstations start ${google_workstations_workstation.dev_workstation.workstation_id} --config=${google_workstations_workstation_config.dev_config.workstation_config_id} --cluster=${google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id} --cluster-region=${var.region} --region=${var.region}"
}

# Source repositories information
output "app_repository_name" {
  description = "Name of the application source repository"
  value       = google_sourcerepo_repository.app_repo.name
}

output "app_repository_url" {
  description = "URL of the application source repository"
  value       = google_sourcerepo_repository.app_repo.url
}

output "env_repository_name" {
  description = "Name of the environment configuration repository"
  value       = google_sourcerepo_repository.env_repo.name
}

output "env_repository_url" {
  description = "URL of the environment configuration repository"
  value       = google_sourcerepo_repository.env_repo.url
}

# Clone commands for repositories
output "app_repository_clone_command" {
  description = "Command to clone the application repository"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.app_repo.name} --project=${var.project_id}"
}

output "env_repository_clone_command" {
  description = "Command to clone the environment repository"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.env_repo.name} --project=${var.project_id}"
}

# Artifact Registry information
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.repository_id
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.location
}

output "artifact_registry_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${google_artifact_registry_repository.container_repo.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}"
}

output "docker_configure_command" {
  description = "Command to configure Docker authentication for Artifact Registry"
  value       = "gcloud auth configure-docker ${google_artifact_registry_repository.container_repo.location}-docker.pkg.dev"
}

# Cloud Build information
output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger for the application repository"
  value       = google_cloudbuild_trigger.app_trigger.name
}

output "cloud_build_service_account" {
  description = "Email of the Cloud Build service account"
  value       = google_service_account.cloudbuild.email
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.app_trigger.trigger_id
}

# Cloud Deploy information
output "cloud_deploy_pipeline_name" {
  description = "Name of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.gitops_pipeline.name
}

output "cloud_deploy_staging_target" {
  description = "Name of the Cloud Deploy staging target"
  value       = google_clouddeploy_target.staging.name
}

output "cloud_deploy_production_target" {
  description = "Name of the Cloud Deploy production target"
  value       = google_clouddeploy_target.production.name
}

# Monitoring and management commands
output "list_builds_command" {
  description = "Command to list recent Cloud Build executions"
  value       = "gcloud builds list --limit=10 --project=${var.project_id}"
}

output "list_releases_command" {
  description = "Command to list Cloud Deploy releases"
  value       = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.gitops_pipeline.name} --region=${var.region} --project=${var.project_id}"
}

output "check_workstation_status_command" {
  description = "Command to check Cloud Workstation status"
  value       = "gcloud workstations list --config=${google_workstations_workstation_config.dev_config.workstation_config_id} --cluster=${google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id} --cluster-region=${var.region} --region=${var.region} --project=${var.project_id}"
}

# Container image examples
output "sample_image_name" {
  description = "Example container image name for the hello-app"
  value       = "${google_artifact_registry_repository.container_repo.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/hello-app:latest"
}

# Kubernetes deployment commands
output "kubectl_staging_context" {
  description = "kubectl context for the staging cluster"
  value       = "gke_${var.project_id}_${google_container_cluster.staging.location}_${google_container_cluster.staging.name}"
}

output "kubectl_production_context" {
  description = "kubectl context for the production cluster"
  value       = "gke_${var.project_id}_${google_container_cluster.production.location}_${google_container_cluster.production.name}"
}

# Validation commands
output "validation_commands" {
  description = "Commands to validate the GitOps infrastructure deployment"
  value = {
    check_clusters = "gcloud container clusters list --filter='name~${var.cluster_name_prefix}' --project=${var.project_id}"
    check_repos    = "gcloud source repos list --project=${var.project_id}"
    check_registry = "gcloud artifacts repositories list --location=${var.region} --project=${var.project_id}"
    check_pipeline = "gcloud deploy delivery-pipelines list --region=${var.region} --project=${var.project_id}"
    check_workstations = "gcloud workstations list --config=${google_workstations_workstation_config.dev_config.workstation_config_id} --cluster=${google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id} --cluster-region=${var.region} --region=${var.region} --project=${var.project_id}"
  }
}

# URLs and access information
output "console_urls" {
  description = "Google Cloud Console URLs for accessing deployed resources"
  value = {
    project_dashboard = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    gke_clusters     = "https://console.cloud.google.com/kubernetes/list?project=${var.project_id}"
    workstations     = "https://console.cloud.google.com/workstations?project=${var.project_id}"
    source_repos     = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    artifact_registry = "https://console.cloud.google.com/artifacts?project=${var.project_id}"
    cloud_build      = "https://console.cloud.google.com/cloud-build?project=${var.project_id}"
    cloud_deploy     = "https://console.cloud.google.com/deploy?project=${var.project_id}"
  }
}

# Resource summary
output "resource_summary" {
  description = "Summary of all deployed resources"
  value = {
    gke_clusters = {
      staging    = google_container_cluster.staging.name
      production = google_container_cluster.production.name
    }
    workstations = {
      cluster_name    = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
      config_name     = google_workstations_workstation_config.dev_config.workstation_config_id
      instance_name   = google_workstations_workstation.dev_workstation.workstation_id
    }
    repositories = {
      app_repo = google_sourcerepo_repository.app_repo.name
      env_repo = google_sourcerepo_repository.env_repo.name
    }
    artifact_registry = {
      repository_name = google_artifact_registry_repository.container_repo.repository_id
      location        = google_artifact_registry_repository.container_repo.location
    }
    ci_cd = {
      build_trigger   = google_cloudbuild_trigger.app_trigger.name
      deploy_pipeline = google_clouddeploy_delivery_pipeline.gitops_pipeline.name
      staging_target  = google_clouddeploy_target.staging.name
      production_target = google_clouddeploy_target.production.name
    }
  }
}
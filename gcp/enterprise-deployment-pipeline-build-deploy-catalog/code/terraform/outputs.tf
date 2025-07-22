# Outputs for GCP Enterprise Deployment Pipeline Infrastructure

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

# GKE Cluster Information
output "gke_cluster_names" {
  description = "Names of the created GKE clusters by environment"
  value       = local.cluster_names
}

output "gke_cluster_endpoints" {
  description = "Endpoints of the created GKE clusters by environment"
  value = var.gke_autopilot_enabled ? {
    for env, cluster_name in local.cluster_names :
    env => google_container_cluster.gke_clusters[env].endpoint
  } : {
    for env, cluster_name in local.cluster_names :
    env => google_container_cluster.gke_standard_clusters[env].endpoint
  }
  sensitive = true
}

output "gke_cluster_ca_certificates" {
  description = "Base64-encoded public certificates for GKE clusters"
  value = var.gke_autopilot_enabled ? {
    for env, cluster_name in local.cluster_names :
    env => google_container_cluster.gke_clusters[env].master_auth[0].cluster_ca_certificate
  } : {
    for env, cluster_name in local.cluster_names :
    env => google_container_cluster.gke_standard_clusters[env].master_auth[0].cluster_ca_certificate
  }
  sensitive = true
}

output "gke_cluster_locations" {
  description = "Locations of the created GKE clusters"
  value = var.gke_autopilot_enabled ? {
    for env, cluster_name in local.cluster_names :
    env => google_container_cluster.gke_clusters[env].location
  } : {
    for env, cluster_name in local.cluster_names :
    env => google_container_cluster.gke_standard_clusters[env].location
  }
}

# Artifact Registry Information
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repository.name
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repository.repository_id}"
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repository.location
}

# Cloud Source Repositories Information
output "source_repository_names" {
  description = "Names of the created Cloud Source Repositories"
  value = {
    for repo_name in var.source_repo_names :
    repo_name => google_sourcerepo_repository.source_repositories[repo_name].name
  }
}

output "source_repository_urls" {
  description = "Clone URLs for the Cloud Source Repositories"
  value = {
    for repo_name in var.source_repo_names :
    repo_name => google_sourcerepo_repository.source_repositories[repo_name].url
  }
}

# Cloud Deploy Pipeline Information
output "clouddeploy_pipeline_name" {
  description = "Name of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.enterprise_pipeline.name
}

output "clouddeploy_pipeline_uid" {
  description = "Unique identifier of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.enterprise_pipeline.uid
}

output "clouddeploy_target_names" {
  description = "Names of the Cloud Deploy targets by environment"
  value = {
    for env in var.environments :
    env => google_clouddeploy_target.deployment_targets[env].name
  }
}

output "clouddeploy_target_uids" {
  description = "Unique identifiers of the Cloud Deploy targets"
  value = {
    for env in var.environments :
    env => google_clouddeploy_target.deployment_targets[env].uid
  }
}

# Cloud Build Information
output "cloudbuild_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.deployment_trigger.name
}

output "cloudbuild_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.deployment_trigger.trigger_id
}

output "cloudbuild_service_account_email" {
  description = "Email of the Cloud Build service account"
  value       = google_service_account.cloudbuild_service_account.email
}

# Service Account Information
output "gke_service_account_email" {
  description = "Email of the GKE node service account (for standard clusters)"
  value       = var.gke_autopilot_enabled ? null : google_service_account.gke_service_account.email
}

# Console URLs for easy access
output "console_urls" {
  description = "Google Cloud Console URLs for key resources"
  value = {
    cloudbuild_triggers = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
    clouddeploy_pipelines = "https://console.cloud.google.com/deploy/delivery-pipelines?project=${var.project_id}"
    gke_clusters = "https://console.cloud.google.com/kubernetes/list/overview?project=${var.project_id}"
    artifact_registry = "https://console.cloud.google.com/artifacts?project=${var.project_id}"
    source_repositories = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Useful commands for deployment and management"
  value = {
    # Commands to get GKE cluster credentials
    gke_credentials = {
      for env, cluster_name in local.cluster_names :
      env => "gcloud container clusters get-credentials ${cluster_name} --location=${var.gke_autopilot_enabled ? var.region : var.zone} --project=${var.project_id}"
    }
    
    # Command to clone source repositories
    clone_repositories = {
      for repo_name in var.source_repo_names :
      repo_name => "gcloud source repos clone ${google_sourcerepo_repository.source_repositories[repo_name].name} --project=${var.project_id}"
    }
    
    # Command to create a Cloud Deploy release
    create_release = "gcloud deploy releases create release-$(date +%s) --delivery-pipeline=${google_clouddeploy_delivery_pipeline.enterprise_pipeline.name} --region=${var.region} --source=."
    
    # Command to list Cloud Deploy releases
    list_releases = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.enterprise_pipeline.name} --region=${var.region}"
    
    # Command to configure Docker authentication for Artifact Registry
    configure_docker = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
  }
}

# Resource Names with Suffix
output "resource_names" {
  description = "Generated resource names with random suffix"
  value = {
    name_suffix = local.name_suffix
    repository_name = local.repository_name
    pipeline_name = local.pipeline_name
    cluster_names = local.cluster_names
  }
}

# Environment Configuration
output "environment_config" {
  description = "Environment-specific configuration"
  value = {
    environments = var.environments
    autopilot_enabled = var.gke_autopilot_enabled
    network_policy_enabled = var.enable_network_policy
    shielded_nodes_enabled = var.enable_shielded_nodes
  }
}
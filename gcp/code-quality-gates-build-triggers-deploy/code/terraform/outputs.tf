# Outputs for the code quality gates pipeline infrastructure

output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone used for resources"
  value       = var.zone
}

# Source Repository Outputs
output "repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.name
}

output "repository_url" {
  description = "URL for the Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.url
}

output "repository_clone_url" {
  description = "HTTPS clone URL for the Cloud Source Repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.app_repo.name}"
}

# Artifact Registry Outputs
output "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.app_registry.repository_id
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.app_registry.location
}

output "container_image_base_url" {
  description = "Base URL for container images in Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_registry.repository_id}"
}

# GKE Cluster Outputs
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.quality_gates_cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint for the GKE cluster"
  value       = google_container_cluster.quality_gates_cluster.endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.quality_gates_cluster.location
}

output "cluster_master_version" {
  description = "Version of the GKE cluster master"
  value       = google_container_cluster.quality_gates_cluster.master_version
}

output "cluster_node_pool_name" {
  description = "Name of the GKE cluster node pool"
  value       = google_container_node_pool.primary_nodes.name
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA certificate for the GKE cluster"
  value       = google_container_cluster.quality_gates_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

# Kubernetes Namespace Outputs
output "kubernetes_namespaces" {
  description = "List of created Kubernetes namespaces"
  value       = kubernetes_namespace.environments[*].metadata[0].name
}

# Cloud Build Outputs
output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_trigger.name
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_trigger.trigger_id
}

output "cloud_build_service_account" {
  description = "Email of the Cloud Build service account"
  value       = local.cloudbuild_sa_email
}

# Cloud Deploy Outputs
output "delivery_pipeline_name" {
  description = "Name of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.quality_pipeline.name
}

output "delivery_pipeline_location" {
  description = "Location of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.quality_pipeline.location
}

output "deploy_targets" {
  description = "Map of Cloud Deploy target information"
  value = {
    development = {
      name        = google_clouddeploy_target.development.name
      description = google_clouddeploy_target.development.description
      location    = google_clouddeploy_target.development.location
    }
    staging = {
      name        = google_clouddeploy_target.staging.name
      description = google_clouddeploy_target.staging.description
      location    = google_clouddeploy_target.staging.location
    }
    production = {
      name        = google_clouddeploy_target.production.name
      description = google_clouddeploy_target.production.description
      location    = google_clouddeploy_target.production.location
    }
  }
}

# Binary Authorization Outputs
output "binary_authorization_enabled" {
  description = "Whether Binary Authorization is enabled"
  value       = var.enable_binary_authorization
}

output "binary_authorization_policy_name" {
  description = "Name of the Binary Authorization policy (if enabled)"
  value       = var.enable_binary_authorization ? google_binary_authorization_policy.policy[0].name : null
}

# Security and Feature Outputs
output "security_features_enabled" {
  description = "Map of enabled security features"
  value = {
    network_policy        = var.enable_network_policy
    workload_identity     = var.enable_workload_identity
    shielded_nodes        = var.enable_shielded_nodes
    binary_authorization  = var.enable_binary_authorization
    vulnerability_scanning = var.enable_vulnerability_scanning
  }
}

# Console URLs for easy access
output "console_urls" {
  description = "URLs for accessing resources in Google Cloud Console"
  value = {
    cloud_build_history   = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    cloud_deploy_pipeline = "https://console.cloud.google.com/deploy/delivery-pipelines/${var.region}/${google_clouddeploy_delivery_pipeline.quality_pipeline.name}?project=${var.project_id}"
    gke_cluster          = "https://console.cloud.google.com/kubernetes/clusters/details/${var.zone}/${google_container_cluster.quality_gates_cluster.name}?project=${var.project_id}"
    source_repository    = "https://source.cloud.google.com/${var.project_id}/${google_sourcerepo_repository.app_repo.name}"
    artifact_registry    = "https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/${google_artifact_registry_repository.app_registry.repository_id}?project=${var.project_id}"
  }
}

# Getting Started Commands
output "getting_started_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    configure_kubectl = "gcloud container clusters get-credentials ${google_container_cluster.quality_gates_cluster.name} --zone=${var.zone} --project=${var.project_id}"
    clone_repository  = "gcloud source repos clone ${google_sourcerepo_repository.app_repo.name} --project=${var.project_id}"
    view_builds       = "gcloud builds list --project=${var.project_id} --limit=10"
    view_releases     = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.quality_pipeline.name} --region=${var.region} --project=${var.project_id}"
    view_pods         = "kubectl get pods --all-namespaces"
  }
}

# Resource Identifiers for programmatic access
output "resource_ids" {
  description = "Resource identifiers for programmatic access"
  value = {
    project_number        = data.google_project.current.number
    cluster_id           = google_container_cluster.quality_gates_cluster.id
    repository_id        = google_sourcerepo_repository.app_repo.id
    registry_id          = google_artifact_registry_repository.app_registry.id
    pipeline_id          = google_clouddeploy_delivery_pipeline.quality_pipeline.id
    trigger_id           = google_cloudbuild_trigger.main_trigger.trigger_id
    random_suffix        = local.suffix
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Information for estimating costs of deployed resources"
  value = {
    gke_nodes_count      = var.gke_node_count
    gke_machine_type     = var.gke_machine_type
    gke_disk_size_gb     = var.gke_disk_size_gb
    region               = var.region
    estimated_monthly_cost = "Estimated $50-150/month depending on usage (GKE cluster, Cloud Build minutes, storage)"
  }
}

# Monitoring and Logging Information
output "monitoring_info" {
  description = "Information about monitoring and logging configuration"
  value = {
    gke_logging_enabled     = "SYSTEM_COMPONENTS, WORKLOADS"
    gke_monitoring_enabled  = "SYSTEM_COMPONENTS"
    cloud_build_logs        = "Available in Cloud Logging"
    cluster_operations_logs = "Available in Cloud Logging"
  }
}
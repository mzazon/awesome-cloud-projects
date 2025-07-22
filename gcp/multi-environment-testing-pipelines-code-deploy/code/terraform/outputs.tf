# Project and Resource Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone used for zonal resources"
  value       = var.zone
}

output "resource_prefix" {
  description = "The prefix used for all resource names"
  value       = local.name_prefix
}

# Artifact Registry Information
output "artifact_registry_repository" {
  description = "The name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.name
}

output "artifact_registry_repository_url" {
  description = "The URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.name}"
}

# GKE Cluster Information
output "dev_cluster_name" {
  description = "The name of the development GKE cluster"
  value       = google_container_cluster.dev.name
}

output "dev_cluster_endpoint" {
  description = "The endpoint of the development GKE cluster"
  value       = google_container_cluster.dev.endpoint
  sensitive   = true
}

output "dev_cluster_location" {
  description = "The location of the development GKE cluster"
  value       = google_container_cluster.dev.location
}

output "staging_cluster_name" {
  description = "The name of the staging GKE cluster"
  value       = google_container_cluster.staging.name
}

output "staging_cluster_endpoint" {
  description = "The endpoint of the staging GKE cluster"
  value       = google_container_cluster.staging.endpoint
  sensitive   = true
}

output "staging_cluster_location" {
  description = "The location of the staging GKE cluster"
  value       = google_container_cluster.staging.location
}

output "prod_cluster_name" {
  description = "The name of the production GKE cluster"
  value       = google_container_cluster.prod.name
}

output "prod_cluster_endpoint" {
  description = "The endpoint of the production GKE cluster"
  value       = google_container_cluster.prod.endpoint
  sensitive   = true
}

output "prod_cluster_location" {
  description = "The location of the production GKE cluster"
  value       = google_container_cluster.prod.location
}

# Cloud Deploy Information
output "delivery_pipeline_name" {
  description = "The name of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.pipeline.name
}

output "delivery_pipeline_uid" {
  description = "The unique identifier of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.pipeline.uid
}

output "cloud_deploy_targets" {
  description = "Information about Cloud Deploy targets"
  value = {
    dev = {
      name        = google_clouddeploy_target.dev.name
      target_id   = google_clouddeploy_target.dev.target_id
      description = google_clouddeploy_target.dev.description
    }
    staging = {
      name        = google_clouddeploy_target.staging.name
      target_id   = google_clouddeploy_target.staging.target_id
      description = google_clouddeploy_target.staging.description
    }
    prod = {
      name        = google_clouddeploy_target.prod.name
      target_id   = google_clouddeploy_target.prod.target_id
      description = google_clouddeploy_target.prod.description
    }
  }
}

# Service Account Information
output "cloud_build_service_account" {
  description = "The email of the Cloud Build service account"
  value       = google_service_account.cloud_build.email
}

output "cloud_deploy_service_account" {
  description = "The email of the Cloud Deploy service account"
  value       = google_service_account.cloud_deploy.email
}

output "gke_nodes_service_account" {
  description = "The email of the GKE nodes service account"
  value       = google_service_account.gke_nodes.email
}

# Storage Information
output "deploy_artifacts_bucket" {
  description = "The name of the Cloud Storage bucket for deployment artifacts"
  value       = google_storage_bucket.deploy_artifacts.name
}

output "deploy_artifacts_bucket_url" {
  description = "The URL of the Cloud Storage bucket for deployment artifacts"
  value       = google_storage_bucket.deploy_artifacts.url
}

# Cloud Build Information
output "cloud_build_trigger_name" {
  description = "The name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_trigger.name
}

output "cloud_build_trigger_id" {
  description = "The ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_trigger.trigger_id
}

# Monitoring Information
output "monitoring_dashboard_id" {
  description = "The ID of the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.pipeline_dashboard[0].id : null
}

output "alert_policy_id" {
  description = "The ID of the Cloud Monitoring alert policy for failed deployments"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.failed_deployments[0].name : null
}

# Connection Commands
output "connect_to_dev_cluster" {
  description = "Command to connect to the development cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.dev.name} --zone=${google_container_cluster.dev.location} --project=${var.project_id}"
}

output "connect_to_staging_cluster" {
  description = "Command to connect to the staging cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.staging.name} --zone=${google_container_cluster.staging.location} --project=${var.project_id}"
}

output "connect_to_prod_cluster" {
  description = "Command to connect to the production cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.prod.name} --zone=${google_container_cluster.prod.location} --project=${var.project_id}"
}

# Docker Authentication Commands
output "configure_docker_auth" {
  description = "Command to configure Docker authentication for Artifact Registry"
  value       = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
}

# Sample Application Build Command
output "sample_build_command" {
  description = "Sample command to build and push an image to Artifact Registry"
  value       = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.name}/${var.app_name}:latest . && docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.name}/${var.app_name}:latest"
}

# Cloud Deploy Release Command
output "sample_release_command" {
  description = "Sample command to create a Cloud Deploy release"
  value       = "gcloud deploy releases create release-$(date +%Y%m%d-%H%M%S) --delivery-pipeline=${google_clouddeploy_delivery_pipeline.pipeline.name} --region=${var.region} --images=${var.app_name}=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.name}/${var.app_name}:latest"
}

# URLs and Links
output "console_urls" {
  description = "Useful Google Cloud Console URLs"
  value = {
    cloud_deploy_pipelines = "https://console.cloud.google.com/deploy/delivery-pipelines?project=${var.project_id}"
    artifact_registry      = "https://console.cloud.google.com/artifacts?project=${var.project_id}"
    gke_clusters           = "https://console.cloud.google.com/kubernetes/list/overview?project=${var.project_id}"
    cloud_build_history    = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    monitoring_dashboards  = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
  }
}

# Environment Configuration Summary
output "environment_summary" {
  description = "Summary of the multi-environment pipeline configuration"
  value = {
    pipeline_name = google_clouddeploy_delivery_pipeline.pipeline.name
    environments = {
      development = {
        cluster_name = google_container_cluster.dev.name
        node_count   = var.dev_cluster_config.node_count
        machine_type = var.dev_cluster_config.machine_type
      }
      staging = {
        cluster_name = google_container_cluster.staging.name
        node_count   = var.staging_cluster_config.node_count
        machine_type = var.staging_cluster_config.machine_type
      }
      production = {
        cluster_name = google_container_cluster.prod.name
        node_count   = var.prod_cluster_config.node_count
        machine_type = var.prod_cluster_config.machine_type
      }
    }
    features = {
      verification_enabled     = var.enable_verification
      production_approval      = var.require_approval_prod
      monitoring_enabled       = var.enable_monitoring
      network_policy_enabled   = var.enable_network_policy
      workload_identity_enabled = var.enable_workload_identity
    }
  }
}
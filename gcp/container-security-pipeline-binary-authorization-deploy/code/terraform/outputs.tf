# Outputs for Container Security Pipeline with Binary Authorization and Cloud Deploy
# This file defines all output values that will be displayed after deployment

# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone"
  value       = var.zone
}

# Artifact Registry Outputs
output "artifact_registry_repository_url" {
  description = "The URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_apps_repo.repository_id}"
}

output "artifact_registry_repository_id" {
  description = "The ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_apps_repo.repository_id
}

output "artifact_registry_location" {
  description = "The location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_apps_repo.location
}

# GKE Cluster Outputs
output "staging_cluster_name" {
  description = "The name of the staging GKE cluster"
  value       = google_container_cluster.staging_cluster.name
}

output "staging_cluster_location" {
  description = "The location of the staging GKE cluster"
  value       = google_container_cluster.staging_cluster.location
}

output "staging_cluster_endpoint" {
  description = "The endpoint of the staging GKE cluster"
  value       = google_container_cluster.staging_cluster.endpoint
  sensitive   = true
}

output "production_cluster_name" {
  description = "The name of the production GKE cluster"
  value       = google_container_cluster.production_cluster.name
}

output "production_cluster_location" {
  description = "The location of the production GKE cluster"
  value       = google_container_cluster.production_cluster.location
}

output "production_cluster_endpoint" {
  description = "The endpoint of the production GKE cluster"
  value       = google_container_cluster.production_cluster.endpoint
  sensitive   = true
}

output "staging_cluster_ca_certificate" {
  description = "The CA certificate of the staging GKE cluster"
  value       = google_container_cluster.staging_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "production_cluster_ca_certificate" {
  description = "The CA certificate of the production GKE cluster"
  value       = google_container_cluster.production_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

# Binary Authorization Outputs
output "binary_authorization_attestor_name" {
  description = "The name of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.build_attestor.name
}

output "binary_authorization_attestor_id" {
  description = "The full resource ID of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.build_attestor.id
}

output "container_analysis_note_name" {
  description = "The name of the Container Analysis note"
  value       = google_container_analysis_note.attestor_note.name
}

output "container_analysis_note_id" {
  description = "The full resource ID of the Container Analysis note"
  value       = google_container_analysis_note.attestor_note.id
}

# Cloud Deploy Outputs
output "cloud_deploy_pipeline_name" {
  description = "The name of the Cloud Deploy pipeline"
  value       = google_clouddeploy_delivery_pipeline.secure_app_pipeline.name
}

output "cloud_deploy_pipeline_id" {
  description = "The full resource ID of the Cloud Deploy pipeline"
  value       = google_clouddeploy_delivery_pipeline.secure_app_pipeline.id
}

output "cloud_deploy_staging_target_name" {
  description = "The name of the staging Cloud Deploy target"
  value       = google_clouddeploy_target.staging_target.name
}

output "cloud_deploy_production_target_name" {
  description = "The name of the production Cloud Deploy target"
  value       = google_clouddeploy_target.production_target.name
}

# Service Account Outputs
output "cloud_build_service_account_email" {
  description = "The email address of the Cloud Build service account"
  value       = google_service_account.cloud_build_sa.email
}

output "cloud_deploy_service_account_email" {
  description = "The email address of the Cloud Deploy service account"
  value       = google_service_account.cloud_deploy_sa.email
}

output "gke_workload_service_account_email" {
  description = "The email address of the GKE workload service account"
  value       = google_service_account.gke_workload_sa.email
}

# Network Outputs
output "vpc_network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.container_security_network.name
}

output "vpc_network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.container_security_network.id
}

output "subnet_name" {
  description = "The name of the subnet"
  value       = google_compute_subnetwork.container_security_subnet.name
}

output "subnet_id" {
  description = "The ID of the subnet"
  value       = google_compute_subnetwork.container_security_subnet.id
}

output "subnet_cidr" {
  description = "The CIDR range of the subnet"
  value       = google_compute_subnetwork.container_security_subnet.ip_cidr_range
}

# Security and Compliance Outputs
output "binary_authorization_policy_status" {
  description = "The status of the Binary Authorization policy"
  value = {
    global_policy_evaluation_mode = google_binary_authorization_policy.container_security_policy.global_policy_evaluation_mode
    default_enforcement_mode      = google_binary_authorization_policy.container_security_policy.default_admission_rule[0].enforcement_mode
  }
}

output "vulnerability_scanning_enabled" {
  description = "Whether vulnerability scanning is enabled"
  value       = var.enable_vulnerability_scanning
}

output "workload_identity_enabled" {
  description = "Whether Workload Identity is enabled"
  value       = var.security_config.enable_workload_identity
}

# Kubectl Connection Commands
output "kubectl_connection_commands" {
  description = "Commands to connect to the GKE clusters using kubectl"
  value = {
    staging_cluster = "gcloud container clusters get-credentials ${google_container_cluster.staging_cluster.name} --zone ${google_container_cluster.staging_cluster.location} --project ${var.project_id}"
    production_cluster = "gcloud container clusters get-credentials ${google_container_cluster.production_cluster.name} --zone ${google_container_cluster.production_cluster.location} --project ${var.project_id}"
  }
}

# Docker Configuration Commands
output "docker_config_commands" {
  description = "Commands to configure Docker for Artifact Registry authentication"
  value = {
    configure_docker = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    example_push = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_apps_repo.repository_id}/app:latest"
  }
}

# Cloud Deploy Commands
output "cloud_deploy_commands" {
  description = "Common Cloud Deploy commands for pipeline management"
  value = {
    create_release = "gcloud deploy releases create release-$(date +%Y%m%d-%H%M%S) --delivery-pipeline=${google_clouddeploy_delivery_pipeline.secure_app_pipeline.name} --region=${var.region} --source=."
    list_releases = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.secure_app_pipeline.name} --region=${var.region}"
    promote_release = "gcloud deploy rollouts promote --release=RELEASE_NAME --delivery-pipeline=${google_clouddeploy_delivery_pipeline.secure_app_pipeline.name} --region=${var.region}"
  }
}

# Monitoring and Logging URLs
output "monitoring_dashboard_urls" {
  description = "URLs for monitoring and logging dashboards"
  value = {
    cloud_console = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    gke_clusters = "https://console.cloud.google.com/kubernetes/list/overview?project=${var.project_id}"
    cloud_deploy = "https://console.cloud.google.com/deploy/delivery-pipelines?project=${var.project_id}"
    artifact_registry = "https://console.cloud.google.com/artifacts?project=${var.project_id}"
    binary_authorization = "https://console.cloud.google.com/security/binary-authorization?project=${var.project_id}"
    cloud_build = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    security_command_center = "https://console.cloud.google.com/security/command-center?project=${var.project_id}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    artifact_registry_repositories = 1
    gke_clusters = 2
    service_accounts = 3
    binary_authorization_attestors = 1
    cloud_deploy_pipelines = 1
    cloud_deploy_targets = 2
    vpc_networks = 1
    subnets = 1
    firewall_rules = 1
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation"
  value = {
    gke_node_count_total = var.gke_cluster_config.node_count * 2
    gke_machine_type = var.gke_cluster_config.machine_type
    gke_disk_size_gb = var.gke_cluster_config.disk_size_gb
    estimated_monthly_cost_usd = "Estimated $200-400 USD/month for GKE clusters (excluding image registry and other services)"
  }
}
# Output values for the secure remote development environment

# Project and region information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for resource naming"
  value       = local.resource_suffix
}

# Networking outputs
output "vpc_network_name" {
  description = "Name of the VPC network for the development environment"
  value       = google_compute_network.dev_vpc.name
}

output "vpc_network_id" {
  description = "Full resource ID of the VPC network"
  value       = google_compute_network.dev_vpc.id
}

output "subnet_name" {
  description = "Name of the subnet hosting workstations and build pools"
  value       = google_compute_subnetwork.dev_subnet.name
}

output "subnet_cidr_range" {
  description = "CIDR range of the development subnet"
  value       = google_compute_subnetwork.dev_subnet.ip_cidr_range
}

# Cloud Workstations outputs
output "workstation_cluster_name" {
  description = "Name of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
}

output "workstation_cluster_id" {
  description = "Full resource ID of the workstation cluster"
  value       = google_workstations_workstation_cluster.dev_cluster.id
}

output "workstation_config_name" {
  description = "Name of the workstation configuration template"
  value       = google_workstations_workstation_config.secure_config.workstation_config_id
}

output "workstation_config_id" {
  description = "Full resource ID of the workstation configuration"
  value       = google_workstations_workstation_config.secure_config.id
}

output "workstation_instance_name" {
  description = "Name of the created workstation instance"
  value       = google_workstations_workstation.dev_workstation.workstation_id
}

output "workstation_instance_id" {
  description = "Full resource ID of the workstation instance"
  value       = google_workstations_workstation.dev_workstation.id
}

output "workstation_host" {
  description = "Host address for accessing the workstation via browser"
  value       = google_workstations_workstation.dev_workstation.host
  sensitive   = false
}

output "workstation_access_url" {
  description = "Complete HTTPS URL for accessing the workstation"
  value       = "https://${google_workstations_workstation.dev_workstation.host}"
  sensitive   = false
}

# Source repository outputs
output "source_repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.name
}

output "source_repository_url" {
  description = "URL for cloning the source repository"
  value       = google_sourcerepo_repository.app_repo.url
  sensitive   = false
}

output "source_repository_id" {
  description = "Full resource ID of the source repository"
  value       = google_sourcerepo_repository.app_repo.id
}

# Artifact Registry outputs
output "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_registry.repository_id
}

output "artifact_registry_id" {
  description = "Full resource ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_registry.id
}

output "container_registry_url" {
  description = "URL for pushing container images to Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}"
  sensitive   = false
}

# Cloud Build outputs
output "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.app_trigger.name
}

output "build_trigger_id" {
  description = "Full resource ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.app_trigger.id
}

output "private_build_pool_name" {
  description = "Name of the private Cloud Build worker pool"
  value       = google_cloudbuild_worker_pool.private_pool.name
}

output "private_build_pool_id" {
  description = "Full resource ID of the private build pool"
  value       = google_cloudbuild_worker_pool.private_pool.id
}

# Service account outputs
output "workstation_service_account_email" {
  description = "Email address of the workstation service account"
  value       = google_service_account.workstation_sa.email
  sensitive   = false
}

output "workstation_service_account_id" {
  description = "Full resource ID of the workstation service account"
  value       = google_service_account.workstation_sa.id
}

output "build_service_account_email" {
  description = "Email address of the Cloud Build service account"
  value       = google_service_account.build_sa.email
  sensitive   = false
}

output "build_service_account_id" {
  description = "Full resource ID of the Cloud Build service account"
  value       = google_service_account.build_sa.id
}

# Security and compliance outputs
output "audit_logging_enabled" {
  description = "Whether audit logging is enabled for workstations"
  value       = var.enable_audit_logs
}

output "public_ip_disabled" {
  description = "Whether public IP addresses are disabled for workstations"
  value       = var.disable_public_ip
}

output "private_google_access_enabled" {
  description = "Whether Private Google Access is enabled for the subnet"
  value       = var.enable_private_google_access
}

# Cost optimization outputs
output "workstation_idle_timeout" {
  description = "Idle timeout configuration for workstations (seconds)"
  value       = var.workstation_idle_timeout
}

output "workstation_machine_type" {
  description = "Machine type used for workstations"
  value       = var.workstation_machine_type
}

output "build_pool_machine_type" {
  description = "Machine type used for build pool workers"
  value       = var.build_pool_machine_type
}

# Quick start information
output "quick_start_commands" {
  description = "Commands to get started with the development environment"
  value = {
    access_workstation = "Navigate to: https://${google_workstations_workstation.dev_workstation.host}"
    clone_repository  = "git clone ${google_sourcerepo_repository.app_repo.url}"
    docker_registry   = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    view_builds       = "gcloud builds list --region=${var.region}"
  }
}

# Resource summary for monitoring and management
output "resource_summary" {
  description = "Summary of created resources for monitoring and cost tracking"
  value = {
    vpc_networks        = 1
    subnets            = 1
    workstation_clusters = 1
    workstation_configs = 1
    workstation_instances = 1
    source_repositories = 1
    artifact_registries = 1
    build_triggers     = 1
    build_pools        = 1
    service_accounts   = 2
    iam_bindings       = length(var.developer_emails) + length(var.developer_groups) + 6
  }
}

# Security configuration summary
output "security_configuration" {
  description = "Summary of security settings applied to the environment"
  value = {
    vpc_isolation           = "Enabled - All resources in private VPC"
    public_ip_access       = var.disable_public_ip ? "Disabled" : "Enabled"
    private_google_access  = var.enable_private_google_access ? "Enabled" : "Disabled"
    audit_logging         = var.enable_audit_logs ? "Enabled" : "Disabled"
    build_pool_isolation  = "Enabled - Private worker pool in VPC"
    container_image_scanning = "Available through Artifact Registry"
    iam_least_privilege   = "Enabled - Role-based access control"
  }
}
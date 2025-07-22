# Project and resource identification outputs
output "project_id" {
  description = "Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Cloud Workstations outputs
output "workstation_cluster_name" {
  description = "Name of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.debug_cluster.workstation_cluster_id
}

output "workstation_cluster_id" {
  description = "Full resource ID of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.debug_cluster.id
}

output "workstation_config_name" {
  description = "Name of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.debug_config.workstation_config_id
}

output "workstation_config_id" {
  description = "Full resource ID of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.debug_config.id
}

output "workstation_instance_name" {
  description = "Name of the Cloud Workstations instance"
  value       = google_workstations_workstation.debug_instance.workstation_id
}

output "workstation_instance_id" {
  description = "Full resource ID of the Cloud Workstations instance"
  value       = google_workstations_workstation.debug_instance.id
}

output "workstation_state" {
  description = "Current state of the Cloud Workstations instance"
  value       = google_workstations_workstation.debug_instance.state
}

output "workstation_host" {
  description = "Host URL for accessing the Cloud Workstations instance"
  value       = google_workstations_workstation.debug_instance.host
}

output "workstation_access_url" {
  description = "Full HTTPS URL for accessing the Cloud Workstations instance"
  value       = "https://${google_workstations_workstation.debug_instance.host}"
}

# Artifact Registry outputs
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.debug_tools_repo.repository_id
}

output "artifact_registry_repository_id" {
  description = "Full resource ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.debug_tools_repo.id
}

output "artifact_registry_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.debug_tools_repo.repository_id}"
}

output "debug_tools_image_uri" {
  description = "URI for the custom debug tools container image"
  value       = local.debug_tools_image_uri
}

# Cloud Run outputs
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.sample_app.name
}

output "cloud_run_service_id" {
  description = "Full resource ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.sample_app.id
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.sample_app.uri
}

output "cloud_run_service_status" {
  description = "Current status of the Cloud Run service"
  value       = google_cloud_run_v2_service.sample_app.conditions
}

# Service Account outputs
output "workstation_service_account_email" {
  description = "Email address of the Cloud Workstations service account"
  value       = google_service_account.workstation_sa.email
}

output "workstation_service_account_id" {
  description = "Full resource ID of the Cloud Workstations service account"
  value       = google_service_account.workstation_sa.id
}

output "cloud_run_service_account_email" {
  description = "Email address of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.email
}

output "cloud_run_service_account_id" {
  description = "Full resource ID of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.id
}

# Network outputs
output "network_name" {
  description = "Name of the VPC network used"
  value       = data.google_compute_network.default.name
}

output "network_id" {
  description = "Full resource ID of the VPC network used"
  value       = data.google_compute_network.default.id
}

output "subnet_name" {
  description = "Name of the subnet used"
  value       = data.google_compute_subnetwork.default.name
}

output "subnet_id" {
  description = "Full resource ID of the subnet used"
  value       = data.google_compute_subnetwork.default.id
}

# Firewall outputs
output "firewall_rule_name" {
  description = "Name of the firewall rule for workstation access"
  value       = google_compute_firewall.workstation_access.name
}

output "firewall_rule_id" {
  description = "Full resource ID of the firewall rule for workstation access"
  value       = google_compute_firewall.workstation_access.id
}

# Storage outputs
output "debug_artifacts_bucket_name" {
  description = "Name of the Cloud Storage bucket for debug artifacts"
  value       = google_storage_bucket.debug_artifacts.name
}

output "debug_artifacts_bucket_url" {
  description = "URL of the Cloud Storage bucket for debug artifacts"
  value       = google_storage_bucket.debug_artifacts.url
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.debug_dashboard[0].id : null
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.workstation_debug_sink[0].name : null
}

output "logging_sink_writer_identity" {
  description = "Writer identity of the Cloud Logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.workstation_debug_sink[0].writer_identity : null
}

# Scheduler outputs
output "auto_shutdown_job_name" {
  description = "Name of the Cloud Scheduler job for automatic shutdown (if enabled)"
  value       = var.enable_auto_shutdown ? google_cloud_scheduler_job.workstation_shutdown[0].name : null
}

output "auto_shutdown_job_id" {
  description = "Full resource ID of the Cloud Scheduler job for automatic shutdown (if enabled)"
  value       = var.enable_auto_shutdown ? google_cloud_scheduler_job.workstation_shutdown[0].id : null
}

# Configuration outputs
output "workstation_configuration" {
  description = "Summary of workstation configuration"
  value = {
    machine_type      = var.workstation_machine_type
    disk_size_gb      = var.workstation_disk_size_gb
    disk_type         = var.workstation_disk_type
    idle_timeout      = var.workstation_idle_timeout
    running_timeout   = var.workstation_running_timeout
    environment       = var.environment
  }
}

output "cloud_run_configuration" {
  description = "Summary of Cloud Run configuration"
  value = {
    cpu         = var.cloud_run_cpu
    memory      = var.cloud_run_memory
    port        = var.cloud_run_port
    image       = var.cloud_run_image
    environment = var.environment
  }
}

# Resource labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Access instructions
output "access_instructions" {
  description = "Instructions for accessing the debugging environment"
  value = {
    workstation_access = "Access the workstation at: https://${google_workstations_workstation.debug_instance.host}"
    sample_app_access  = "Access the sample application at: ${google_cloud_run_v2_service.sample_app.uri}"
    health_check       = "Check application health at: ${google_cloud_run_v2_service.sample_app.uri}/health"
    api_endpoint       = "Test API endpoint at: ${google_cloud_run_v2_service.sample_app.uri}/api/data"
  }
}

# CLI commands for management
output "management_commands" {
  description = "Useful CLI commands for managing the debugging environment"
  value = {
    start_workstation = "gcloud workstations start ${google_workstations_workstation.debug_instance.workstation_id} --location=${var.region} --cluster=${google_workstations_workstation_cluster.debug_cluster.workstation_cluster_id} --config=${google_workstations_workstation_config.debug_config.workstation_config_id}"
    stop_workstation  = "gcloud workstations stop ${google_workstations_workstation.debug_instance.workstation_id} --location=${var.region} --cluster=${google_workstations_workstation_cluster.debug_cluster.workstation_cluster_id} --config=${google_workstations_workstation_config.debug_config.workstation_config_id}"
    ssh_workstation   = "gcloud workstations ssh ${google_workstations_workstation.debug_instance.workstation_id} --location=${var.region} --cluster=${google_workstations_workstation_cluster.debug_cluster.workstation_cluster_id} --config=${google_workstations_workstation_config.debug_config.workstation_config_id}"
    view_logs         = "gcloud logging read 'resource.type=\"gce_instance\" AND resource.labels.instance_name:workstation' --limit=20"
    push_image        = "docker push ${local.debug_tools_image_uri}"
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Cost optimization features enabled"
  value = {
    auto_shutdown_enabled = var.enable_auto_shutdown
    auto_shutdown_schedule = var.auto_shutdown_schedule
    workstation_idle_timeout = "${var.workstation_idle_timeout} seconds"
    artifact_registry_cleanup = "Enabled - keeps 10 recent versions, deletes versions older than 30 days"
    storage_lifecycle = "${var.log_retention_days} days retention"
  }
}

# Security information
output "security_configuration" {
  description = "Security features configured"
  value = {
    workstation_service_account = google_service_account.workstation_sa.email
    cloud_run_service_account   = google_service_account.cloud_run_sa.email
    private_google_access       = var.enable_private_google_access
    allowed_ingress_cidr        = var.allowed_ingress_cidr_blocks
    firewall_rule               = google_compute_firewall.workstation_access.name
    uniform_bucket_access       = "Enabled"
  }
}

# API enablement status
output "enabled_apis" {
  description = "Google Cloud APIs enabled for this project"
  value       = var.enable_apis
}
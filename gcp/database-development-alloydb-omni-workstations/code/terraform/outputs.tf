# Outputs for GCP Database Development Workflow with AlloyDB Omni and Cloud Workstations
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Project and Region Information
output "project_id" {
  description = "The GCP project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique identifier for this deployment"
  value       = local.deployment_id
}

# Networking Information
output "vpc_network_name" {
  description = "Name of the VPC network created for workstations"
  value       = module.vpc_network.network_name
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network"
  value       = module.vpc_network.network_self_link
}

output "workstation_subnet_name" {
  description = "Name of the subnet for Cloud Workstations"
  value       = module.vpc_network.subnets_names[0]
}

output "workstation_subnet_cidr" {
  description = "CIDR range of the workstation subnet"
  value       = var.workstation_subnet_cidr
}

# Cloud Workstations Information
output "workstation_cluster_name" {
  description = "Name of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.database_development.workstation_cluster_id
}

output "workstation_cluster_self_link" {
  description = "Self-link of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.database_development.name
}

output "workstation_config_name" {
  description = "Name of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.database_development.workstation_config_id
}

output "sample_workstation_name" {
  description = "Name of the sample workstation instance"
  value       = google_workstations_workstation.sample_workstation.workstation_id
}

output "workstation_access_url" {
  description = "URL to access Cloud Workstations through Google Cloud Console"
  value       = "https://console.cloud.google.com/workstations/list?project=${var.project_id}&region=${var.region}"
}

# Service Account Information
output "workstation_service_account_email" {
  description = "Email address of the service account used by workstations"
  value       = google_service_account.workstation_sa.email
}

output "workstation_service_account_unique_id" {
  description = "Unique ID of the workstation service account"
  value       = google_service_account.workstation_sa.unique_id
}

output "cloudbuild_service_account_email" {
  description = "Email address of the service account used by Cloud Build"
  value       = google_service_account.cloudbuild_sa.email
}

# Cloud Source Repositories Information
output "source_repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.database_development.name
}

output "source_repository_url" {
  description = "HTTPS clone URL for the source repository"
  value       = google_sourcerepo_repository.database_development.url
}

output "source_repository_clone_command" {
  description = "Command to clone the source repository"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.database_development.name} --project=${var.project_id}"
}

# Artifact Registry Information
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_images.repository_id
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_images.repository_id}"
}

# Cloud Build Information
output "cloudbuild_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.database_testing.name
}

output "cloudbuild_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.database_testing.trigger_id
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for build notifications"
  value       = google_pubsub_topic.build_notifications.name
}

# Configuration Information
output "workstation_container_image" {
  description = "Container image used for workstations"
  value       = var.workstation_container_image
}

output "workstation_machine_type" {
  description = "Machine type used for workstations"
  value       = var.workstation_cluster_config.machine_type
}

output "workstation_persistent_disk_size" {
  description = "Size of persistent disk for workstations (GB)"
  value       = var.workstation_cluster_config.persistent_disk_size_gb
}

# AlloyDB Omni Configuration Information
output "alloydb_config_summary" {
  description = "Summary of AlloyDB Omni configuration for development"
  value = {
    database_name    = var.alloydb_config.database_name
    database_user    = var.alloydb_config.database_user
    enable_columnar  = var.alloydb_config.enable_columnar
    enable_vector    = var.alloydb_config.enable_vector
    backup_retention = var.alloydb_config.backup_retention
  }
}

# Security Configuration Summary
output "security_configuration" {
  description = "Summary of security configurations applied"
  value = {
    private_ip_only           = var.workstation_cluster_config.disable_public_ip_addresses
    os_login_enabled         = var.security_config.enable_os_login
    shielded_vm_enabled      = var.security_config.enable_shielded_vm
    secure_boot_enabled      = var.security_config.enable_secure_boot
    integrity_monitoring     = var.security_config.enable_integrity_monitoring
    private_google_access    = var.security_config.enable_private_google_access
  }
}

# Monitoring Configuration Summary
output "monitoring_configuration" {
  description = "Summary of monitoring and logging configurations"
  value = {
    flow_logs_enabled       = var.monitoring_config.enable_flow_logs
    workstation_logs_enabled = var.monitoring_config.enable_workstation_logs
    build_logs_enabled      = var.monitoring_config.enable_build_logs
    log_retention_days      = var.monitoring_config.log_retention_days
    notification_email      = var.monitoring_config.notification_email != "" ? var.monitoring_config.notification_email : "Not configured"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for using the development environment"
  value = {
    clone_repository = "gcloud source repos clone ${google_sourcerepo_repository.database_development.name} --project=${var.project_id}"
    start_workstation = "gcloud workstations start ${google_workstations_workstation.sample_workstation.workstation_id} --region=${var.region} --cluster=${google_workstations_workstation_cluster.database_development.workstation_cluster_id} --config=${google_workstations_workstation_config.database_development.workstation_config_id}"
    access_workstation = "gcloud workstations start-tcp-tunnel ${google_workstations_workstation.sample_workstation.workstation_id} 22 --region=${var.region} --cluster=${google_workstations_workstation_cluster.database_development.workstation_cluster_id} --config=${google_workstations_workstation_config.database_development.workstation_config_id}"
    list_workstations = "gcloud workstations list --region=${var.region} --cluster=${google_workstations_workstation_cluster.database_development.workstation_cluster_id} --config=${google_workstations_workstation_config.database_development.workstation_config_id}"
    view_builds = "gcloud builds list --project=${var.project_id} --region=${var.region}"
  }
}

# Docker Commands for AlloyDB Omni
output "alloydb_omni_setup" {
  description = "Commands to set up AlloyDB Omni development environment"
  value = {
    docker_compose_up = "cd alloydb-config && docker-compose up -d"
    docker_compose_down = "cd alloydb-config && docker-compose down -v"
    database_connection = "postgresql://dev_user:dev_password_123@localhost:5432/development_db"
    psql_connect = "PGPASSWORD=dev_password_123 psql -h localhost -U dev_user -d development_db"
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "Google Cloud Console URLs for accessing deployed resources"
  value = {
    workstations_console = "https://console.cloud.google.com/workstations/list?project=${var.project_id}&region=${var.region}"
    source_repos_console = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    cloud_build_console = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}&region=${var.region}"
    artifact_registry_console = "https://console.cloud.google.com/artifacts/browse/${var.project_id}?project=${var.project_id}&region=${var.region}"
    compute_console = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
    vpc_console = "https://console.cloud.google.com/networking/networks/list?project=${var.project_id}"
    iam_console = "https://console.cloud.google.com/iam-admin/iam?project=${var.project_id}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources (approximate)"
  value = {
    workstation_cluster = "~$0 (cluster itself is free)"
    sample_workstation = "~$50-80/month when running (${var.workstation_cluster_config.machine_type})"
    persistent_storage = "~$${var.workstation_cluster_config.persistent_disk_size_gb * 0.04}/month (${var.workstation_cluster_config.persistent_disk_size_gb}GB standard disk)"
    networking = "~$5-15/month (VPC, subnets, firewall rules)"
    cloud_build = "~$0-20/month (120 free minutes, then $0.003/minute)"
    artifact_registry = "~$0.10/GB/month for storage"
    logging_monitoring = "~$0.50/GB for logs ingestion and storage"
    total_estimated = "~$55-120/month depending on usage patterns"
    note = "Costs vary based on actual usage, region, and Google Cloud pricing changes"
  }
}

# Maintenance Information
output "maintenance_information" {
  description = "Important maintenance and operational information"
  value = {
    workstation_timeouts = {
      idle_timeout = var.workstation_cluster_config.idle_timeout
      running_timeout = var.workstation_cluster_config.running_timeout
    }
    cleanup_policies = {
      artifact_registry_cleanup = var.artifact_registry_config.cleanup_policy_enabled
      log_retention_days = var.monitoring_config.log_retention_days
    }
    backup_retention = "${var.alloydb_config.backup_retention} days"
    security_updates = "Workstation images are automatically updated by Google"
  }
}
# Outputs for ML Pipeline Governance Infrastructure
# This file defines outputs that provide important information about deployed resources

# Project and Location Information
output "project_id" {
  description = "Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where compute resources were deployed"
  value       = var.zone
}

# Storage Resources
output "training_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.name
}

output "training_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.url
}

output "training_data_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.self_link
}

# Hyperdisk ML Resources
output "hyperdisk_ml_name" {
  description = "Name of the Hyperdisk ML volume"
  value       = google_compute_disk.hyperdisk_ml.name
}

output "hyperdisk_ml_self_link" {
  description = "Self-link of the Hyperdisk ML volume"
  value       = google_compute_disk.hyperdisk_ml.self_link
}

output "hyperdisk_ml_size_gb" {
  description = "Size of the Hyperdisk ML volume in GB"
  value       = google_compute_disk.hyperdisk_ml.size
}

output "hyperdisk_ml_provisioned_throughput" {
  description = "Provisioned throughput of the Hyperdisk ML volume in MiB/s"
  value       = google_compute_disk.hyperdisk_ml.provisioned_throughput
}

# Compute Instance Information
output "ml_training_instance_name" {
  description = "Name of the ML training compute instance"
  value       = google_compute_instance.ml_training.name
}

output "ml_training_instance_self_link" {
  description = "Self-link of the ML training compute instance"
  value       = google_compute_instance.ml_training.self_link
}

output "ml_training_instance_external_ip" {
  description = "External IP address of the ML training instance"
  value       = google_compute_instance.ml_training.network_interface[0].access_config[0].nat_ip
}

output "ml_training_instance_internal_ip" {
  description = "Internal IP address of the ML training instance"
  value       = google_compute_instance.ml_training.network_interface[0].network_ip
}

output "ml_training_instance_machine_type" {
  description = "Machine type of the ML training instance"
  value       = google_compute_instance.ml_training.machine_type
}

# Service Account Information
output "ml_governance_service_account_email" {
  description = "Email address of the ML governance service account"
  value       = google_service_account.ml_governance.email
}

output "ml_governance_service_account_unique_id" {
  description = "Unique ID of the ML governance service account"
  value       = google_service_account.ml_governance.unique_id
}

# Vertex AI Model Registry
output "vertex_ai_model_name" {
  description = "Name of the Vertex AI model in Model Registry"
  value       = google_vertex_ai_model.governance_model.name
}

output "vertex_ai_model_id" {
  description = "Unique ID of the Vertex AI model"
  value       = google_vertex_ai_model.governance_model.id
}

output "vertex_ai_model_display_name" {
  description = "Display name of the Vertex AI model"
  value       = google_vertex_ai_model.governance_model.display_name
}

output "vertex_ai_model_artifact_uri" {
  description = "Artifact URI of the Vertex AI model"
  value       = google_vertex_ai_model.governance_model.artifact_uri
}

output "vertex_ai_model_version_aliases" {
  description = "Version aliases of the Vertex AI model"
  value       = google_vertex_ai_model.governance_model.version_aliases
}

# Cloud Workflows
output "governance_workflow_name" {
  description = "Name of the Cloud Workflow for ML governance"
  value       = google_workflows_workflow.ml_governance.name
}

output "governance_workflow_id" {
  description = "Unique ID of the Cloud Workflow"
  value       = google_workflows_workflow.ml_governance.id
}

output "governance_workflow_state" {
  description = "Current state of the Cloud Workflow"
  value       = google_workflows_workflow.ml_governance.state
}

# Monitoring Dashboard
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_advanced_monitoring ? google_monitoring_dashboard.ml_governance[0].id : null
}

# Cloud Scheduler (if enabled)
output "governance_scheduler_name" {
  description = "Name of the Cloud Scheduler job (if enabled)"
  value       = var.enable_workflow_scheduling ? google_cloud_scheduler_job.governance_scheduler[0].name : null
}

output "governance_scheduler_schedule" {
  description = "Schedule of the governance workflow (if enabled)"
  value       = var.enable_workflow_scheduling ? var.workflow_schedule : null
}

# Network and Security
output "firewall_rule_name" {
  description = "Name of the firewall rule for ML training instances"
  value       = google_compute_firewall.ml_training_access.name
}

output "allowed_source_ranges" {
  description = "Source IP ranges allowed to access ML training instances"
  value       = var.allowed_source_ranges
}

# Resource URLs for Quick Access
output "vertex_ai_console_url" {
  description = "URL to access Vertex AI Model Registry in Google Cloud Console"
  value       = "https://console.cloud.google.com/vertex-ai/models?project=${var.project_id}"
}

output "workflows_console_url" {
  description = "URL to access Cloud Workflows in Google Cloud Console"
  value       = "https://console.cloud.google.com/workflows?project=${var.project_id}"
}

output "monitoring_console_url" {
  description = "URL to access Cloud Monitoring dashboards in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
}

output "storage_console_url" {
  description = "URL to access Cloud Storage bucket in Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.training_data.name}?project=${var.project_id}"
}

output "compute_console_url" {
  description = "URL to access Compute Engine instances in Google Cloud Console"
  value       = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
}

# SSH Connection Information
output "ssh_command" {
  description = "Command to SSH into the ML training instance"
  value       = "gcloud compute ssh ${google_compute_instance.ml_training.name} --zone=${var.zone} --project=${var.project_id}"
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    hyperdisk_ml = {
      name               = google_compute_disk.hyperdisk_ml.name
      size_gb           = google_compute_disk.hyperdisk_ml.size
      throughput_mbps   = google_compute_disk.hyperdisk_ml.provisioned_throughput
    }
    compute_instance = {
      name         = google_compute_instance.ml_training.name
      machine_type = google_compute_instance.ml_training.machine_type
      external_ip  = google_compute_instance.ml_training.network_interface[0].access_config[0].nat_ip
    }
    storage_bucket = {
      name          = google_storage_bucket.training_data.name
      storage_class = google_storage_bucket.training_data.storage_class
    }
    vertex_ai_model = {
      name         = google_vertex_ai_model.governance_model.name
      display_name = google_vertex_ai_model.governance_model.display_name
    }
    governance_workflow = {
      name = google_workflows_workflow.ml_governance.name
    }
  }
}

# Labels Applied to Resources
output "applied_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Random Suffix Used
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    check_hyperdisk = "gcloud compute disks describe ${google_compute_disk.hyperdisk_ml.name} --zone=${var.zone} --project=${var.project_id}"
    check_instance  = "gcloud compute instances describe ${google_compute_instance.ml_training.name} --zone=${var.zone} --project=${var.project_id}"
    check_model     = "gcloud ai models describe ${split("/", google_vertex_ai_model.governance_model.name)[5]} --region=${var.region} --project=${var.project_id}"
    check_workflow  = "gcloud workflows describe ${google_workflows_workflow.ml_governance.name} --location=${var.region} --project=${var.project_id}"
    list_buckets    = "gsutil ls -p ${var.project_id}"
  }
}

# Cost Estimation Information
output "cost_estimation_notes" {
  description = "Notes about resource costs and optimization"
  value = {
    hyperdisk_ml_cost = "Hyperdisk ML pricing is based on provisioned throughput (${var.hyperdisk_provisioned_throughput} MiB/s) and storage size (${var.hyperdisk_size_gb} GB)"
    compute_cost      = "Compute instance cost is based on machine type (${var.machine_type}) and runtime hours"
    storage_cost      = "Cloud Storage cost is based on storage class (${var.storage_class}) and data volume"
    optimization_tip  = "Consider using preemptible instances for training workloads to reduce costs"
  }
}
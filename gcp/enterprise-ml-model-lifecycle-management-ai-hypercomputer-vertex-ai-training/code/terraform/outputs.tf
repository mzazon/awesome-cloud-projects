# Output Values for Enterprise ML Model Lifecycle Management
# This file defines all output values that will be displayed after deployment

# Project and Location Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources were created"
  value       = var.zone
}

# Cloud Workstations Information
output "workstation_cluster_name" {
  description = "Name of the Cloud Workstations cluster"
  value       = google_workstations_cluster.ml_workstations.name
}

output "workstation_cluster_id" {
  description = "Full resource ID of the Cloud Workstations cluster"
  value       = google_workstations_cluster.ml_workstations.id
}

output "workstation_config_name" {
  description = "Name of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.ml_config.name
}

output "workstation_config_id" {
  description = "Full resource ID of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.ml_config.id
}

output "workstation_instance_name" {
  description = "Name of the Cloud Workstations instance"
  value       = google_workstations_workstation.ml_dev_workstation.name
}

output "workstation_instance_id" {
  description = "Full resource ID of the Cloud Workstations instance"
  value       = google_workstations_workstation.ml_dev_workstation.id
}

output "workstation_access_url" {
  description = "URL to access the Cloud Workstations instance"
  value       = "https://console.cloud.google.com/workstations/instances?project=${var.project_id}"
}

# AI Hypercomputer Infrastructure
output "tpu_training_instance_name" {
  description = "Name of the TPU training instance"
  value       = var.enable_tpu_training ? google_tpu_v2_vm.ml_tpu_training[0].name : null
}

output "tpu_training_instance_id" {
  description = "Full resource ID of the TPU training instance"
  value       = var.enable_tpu_training ? google_tpu_v2_vm.ml_tpu_training[0].id : null
}

output "tpu_accelerator_type" {
  description = "Type of TPU accelerator provisioned"
  value       = var.enable_tpu_training ? var.tpu_accelerator_type : null
}

output "gpu_training_instance_name" {
  description = "Name of the GPU training instance"
  value       = var.enable_gpu_training ? google_compute_instance.ml_gpu_training[0].name : null
}

output "gpu_training_instance_id" {
  description = "Full resource ID of the GPU training instance"
  value       = var.enable_gpu_training ? google_compute_instance.ml_gpu_training[0].id : null
}

output "gpu_training_instance_internal_ip" {
  description = "Internal IP address of the GPU training instance"
  value       = var.enable_gpu_training ? google_compute_instance.ml_gpu_training[0].network_interface[0].network_ip : null
}

output "gpu_accelerator_configuration" {
  description = "GPU accelerator configuration"
  value = var.enable_gpu_training ? {
    type  = var.gpu_accelerator_type
    count = var.gpu_accelerator_count
  } : null
}

# Storage and Data Resources
output "ml_artifacts_bucket_name" {
  description = "Name of the ML artifacts Cloud Storage bucket"
  value       = google_storage_bucket.ml_artifacts.name
}

output "ml_artifacts_bucket_url" {
  description = "URL of the ML artifacts Cloud Storage bucket"
  value       = google_storage_bucket.ml_artifacts.url
}

output "ml_artifacts_bucket_self_link" {
  description = "Self-link of the ML artifacts Cloud Storage bucket"
  value       = google_storage_bucket.ml_artifacts.self_link
}

output "bigquery_dataset_name" {
  description = "Name of the BigQuery dataset for ML experiments"
  value       = google_bigquery_dataset.ml_experiments.dataset_id
}

output "bigquery_dataset_id" {
  description = "Full resource ID of the BigQuery dataset"
  value       = google_bigquery_dataset.ml_experiments.id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.ml_experiments.location
}

output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.ml_containers.name
}

output "artifact_registry_repository_id" {
  description = "Full resource ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.ml_containers.id
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ml_containers.name}"
}

# Vertex AI Resources
output "vertex_ai_metadata_store_name" {
  description = "Name of the Vertex AI metadata store"
  value       = google_vertex_ai_metadata_store.ml_metadata_store.name
}

output "vertex_ai_metadata_store_id" {
  description = "Full resource ID of the Vertex AI metadata store"
  value       = google_vertex_ai_metadata_store.ml_metadata_store.id
}

output "vertex_ai_tensorboard_name" {
  description = "Name of the Vertex AI Tensorboard instance"
  value       = google_vertex_ai_tensorboard.ml_tensorboard.name
}

output "vertex_ai_tensorboard_id" {
  description = "Full resource ID of the Vertex AI Tensorboard instance"
  value       = google_vertex_ai_tensorboard.ml_tensorboard.id
}

output "vertex_ai_tensorboard_web_access_uris" {
  description = "Web access URIs for the Vertex AI Tensorboard"
  value       = google_vertex_ai_tensorboard.ml_tensorboard.web_access_uris
}

# Service Accounts
output "workstation_service_account_email" {
  description = "Email address of the workstation service account"
  value       = google_service_account.workstation_sa.email
}

output "workstation_service_account_id" {
  description = "Full resource ID of the workstation service account"
  value       = google_service_account.workstation_sa.id
}

output "training_service_account_email" {
  description = "Email address of the training service account"
  value       = google_service_account.training_sa.email
}

output "training_service_account_id" {
  description = "Full resource ID of the training service account"
  value       = google_service_account.training_sa.id
}

# Networking Information
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.ml_network.name
}

output "vpc_network_id" {
  description = "Full resource ID of the VPC network"
  value       = google_compute_network.ml_network.id
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.ml_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.ml_subnet.name
}

output "subnet_id" {
  description = "Full resource ID of the subnet"
  value       = google_compute_subnetwork.ml_subnet.id
}

output "subnet_self_link" {
  description = "Self-link of the subnet"
  value       = google_compute_subnetwork.ml_subnet.self_link
}

output "subnet_cidr_range" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.ml_subnet.ip_cidr_range
}

# Firewall Rules
output "firewall_rules" {
  description = "List of firewall rules created"
  value = [
    google_compute_firewall.allow_internal.name,
    google_compute_firewall.allow_ssh.name,
    google_compute_firewall.allow_ml_ports.name
  ]
}

# IAM Information
output "workstation_service_account_roles" {
  description = "List of IAM roles assigned to the workstation service account"
  value       = var.workstation_service_account_roles
}

output "training_service_account_roles" {
  description = "List of IAM roles assigned to the training service account"
  value       = var.training_service_account_roles
}

# Security Configuration
output "binary_authorization_policy_name" {
  description = "Name of the Binary Authorization policy"
  value       = var.enable_binary_authorization ? google_binary_authorization_policy.ml_policy[0].name : null
}

# Monitoring and Logging
output "log_sink_name" {
  description = "Name of the Cloud Logging sink"
  value       = var.enable_logging ? google_logging_project_sink.ml_logs[0].name : null
}

output "monitoring_notification_channel_name" {
  description = "Name of the Cloud Monitoring notification channel"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.ml_alerts[0].name : null
}

# Cost Management
output "budget_name" {
  description = "Name of the budget for cost management"
  value       = var.enable_budget_alerts ? google_billing_budget.ml_budget[0].display_name : null
}

output "budget_amount" {
  description = "Budget amount in USD"
  value       = var.enable_budget_alerts ? var.budget_amount : null
}

# Resource Labels
output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for accessing the ML infrastructure"
  value = {
    "Access Workstation" = "gcloud workstations start-tcp-tunnel --project=${var.project_id} --cluster=${google_workstations_cluster.ml_workstations.name} --config=${google_workstations_workstation_config.ml_config.name} --workstation=${google_workstations_workstation.ml_dev_workstation.name} --region=${var.region} --local-host-port=localhost:8080 --port=22"
    "List TPU Instances" = var.enable_tpu_training ? "gcloud compute tpus tpu-vm list --project=${var.project_id} --zone=${var.zone}" : "TPU not enabled"
    "List GPU Instances" = var.enable_gpu_training ? "gcloud compute instances list --project=${var.project_id} --filter='name:${google_compute_instance.ml_gpu_training[0].name}'" : "GPU not enabled"
    "Access Storage Bucket" = "gsutil ls gs://${google_storage_bucket.ml_artifacts.name}/"
    "Access BigQuery Dataset" = "bq ls --project_id=${var.project_id} ${google_bigquery_dataset.ml_experiments.dataset_id}"
    "Access Vertex AI Console" = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    "Access Tensorboard" = "https://console.cloud.google.com/vertex-ai/tensorboard?project=${var.project_id}"
  }
}

# Infrastructure Summary
output "infrastructure_summary" {
  description = "Summary of deployed infrastructure components"
  value = {
    "Cloud Workstations" = {
      "cluster_name" = google_workstations_cluster.ml_workstations.name
      "config_name"  = google_workstations_workstation_config.ml_config.name
      "instance_name" = google_workstations_workstation.ml_dev_workstation.name
      "machine_type" = var.workstation_machine_type
      "disk_size_gb" = var.workstation_disk_size
    }
    "AI Hypercomputer" = {
      "tpu_enabled" = var.enable_tpu_training
      "tpu_type" = var.enable_tpu_training ? var.tpu_accelerator_type : null
      "gpu_enabled" = var.enable_gpu_training
      "gpu_type" = var.enable_gpu_training ? var.gpu_accelerator_type : null
      "gpu_count" = var.enable_gpu_training ? var.gpu_accelerator_count : null
    }
    "Storage" = {
      "bucket_name" = google_storage_bucket.ml_artifacts.name
      "storage_class" = var.storage_class
      "versioning_enabled" = var.enable_storage_versioning
    }
    "Data Analytics" = {
      "dataset_name" = google_bigquery_dataset.ml_experiments.dataset_id
      "dataset_location" = google_bigquery_dataset.ml_experiments.location
    }
    "Container Registry" = {
      "repository_name" = google_artifact_registry_repository.ml_containers.name
      "repository_format" = var.artifact_registry_format
      "repository_url" = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ml_containers.name}"
    }
    "Vertex AI" = {
      "metadata_store" = google_vertex_ai_metadata_store.ml_metadata_store.name
      "tensorboard" = google_vertex_ai_tensorboard.ml_tensorboard.name
      "region" = var.vertex_ai_region
    }
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Access the Cloud Workstations instance using the provided command",
    "2. Configure your development environment with required ML frameworks",
    "3. Upload your training data to the Cloud Storage bucket",
    "4. Create your first Vertex AI experiment using the provided infrastructure",
    "5. Monitor resource usage and costs using the provided dashboard links",
    "6. Review and customize the security settings based on your requirements"
  ]
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the ML infrastructure"
  value = [
    "Use preemptible instances for non-critical training workloads",
    "Enable automatic scaling for Vertex AI training jobs",
    "Set up lifecycle policies for Cloud Storage to automatically transition old data to cheaper storage classes",
    "Use spot instances for experimental workloads",
    "Monitor and optimize TPU/GPU utilization to avoid idle resources",
    "Set up budget alerts to track spending",
    "Use Cloud Scheduler to automatically start/stop training resources"
  ]
}

# Security Best Practices
output "security_best_practices" {
  description = "Security best practices for the ML infrastructure"
  value = [
    "Regularly rotate service account keys",
    "Use IAM conditions for fine-grained access control",
    "Enable audit logging for all ML operations",
    "Implement network security policies",
    "Use VPC Service Controls for additional security",
    "Enable Binary Authorization for container image security",
    "Regularly scan container images for vulnerabilities",
    "Use encryption at rest and in transit for all data"
  ]
}
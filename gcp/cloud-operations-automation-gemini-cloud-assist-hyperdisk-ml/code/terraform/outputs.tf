# Outputs for Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML

# Project and region information
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

# Hyperdisk ML outputs
output "hyperdisk_ml_name" {
  description = "Name of the Hyperdisk ML volume"
  value       = google_compute_disk.hyperdisk_ml.name
}

output "hyperdisk_ml_id" {
  description = "ID of the Hyperdisk ML volume"
  value       = google_compute_disk.hyperdisk_ml.id
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

# GKE cluster outputs
output "gke_cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.ml_ops_cluster.name
}

output "gke_cluster_id" {
  description = "ID of the GKE cluster"
  value       = google_container_cluster.ml_ops_cluster.id
}

output "gke_cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.ml_ops_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_master_version" {
  description = "Master version of the GKE cluster"
  value       = google_container_cluster.ml_ops_cluster.master_version
}

output "gke_cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.ml_ops_cluster.location
}

output "gke_cluster_node_count" {
  description = "Total node count across all node pools"
  value = {
    cpu_pool = google_container_node_pool.cpu_pool.node_count
    gpu_pool = "0 (autoscaling enabled)"
  }
}

# Service account outputs
output "vertex_ai_agent_email" {
  description = "Email of the Vertex AI agent service account"
  value       = google_service_account.vertex_ai_agent.email
}

output "vertex_ai_agent_unique_id" {
  description = "Unique ID of the Vertex AI agent service account"
  value       = google_service_account.vertex_ai_agent.unique_id
}

# Cloud Function outputs
output "ml_ops_function_name" {
  description = "Name of the ML operations automation function"
  value       = google_cloudfunctions_function.ml_ops_automation.name
}

output "ml_ops_function_url" {
  description = "URL of the ML operations automation function"
  value       = google_cloudfunctions_function.ml_ops_automation.https_trigger_url
  sensitive   = true
}

output "ml_ops_function_status" {
  description = "Status of the ML operations automation function"
  value       = google_cloudfunctions_function.ml_ops_automation.status
}

# Cloud Storage outputs
output "ml_datasets_bucket_name" {
  description = "Name of the ML datasets bucket"
  value       = google_storage_bucket.ml_datasets.name
}

output "ml_datasets_bucket_url" {
  description = "URL of the ML datasets bucket"
  value       = google_storage_bucket.ml_datasets.url
}

output "ml_datasets_bucket_self_link" {
  description = "Self-link of the ML datasets bucket"
  value       = google_storage_bucket.ml_datasets.self_link
}

# Cloud Scheduler outputs
output "scheduler_jobs" {
  description = "Information about Cloud Scheduler jobs"
  value = {
    ml_ops_scheduler = {
      name     = google_cloud_scheduler_job.ml_ops_scheduler.name
      schedule = google_cloud_scheduler_job.ml_ops_scheduler.schedule
      state    = google_cloud_scheduler_job.ml_ops_scheduler.state
    }
    performance_monitor = {
      name     = google_cloud_scheduler_job.performance_monitor.name
      schedule = google_cloud_scheduler_job.performance_monitor.schedule
      state    = google_cloud_scheduler_job.performance_monitor.state
    }
  }
}

# Monitoring outputs
output "log_metrics" {
  description = "Custom log-based metrics created"
  value = {
    ml_training_duration = google_logging_metric.ml_training_duration.name
    storage_throughput   = google_logging_metric.storage_throughput.name
  }
}

output "alert_policies" {
  description = "Monitoring alert policies created"
  value = var.enable_alerting_policies ? {
    ml_workload_performance = google_monitoring_alert_policy.ml_workload_performance[0].name
  } : {}
}

# Kubernetes configuration commands
output "kubectl_config_command" {
  description = "Command to configure kubectl for the GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.ml_ops_cluster.name} --zone=${var.zone} --project=${var.project_id}"
}

# Storage class information
output "kubernetes_storage_class" {
  description = "Kubernetes storage class for Hyperdisk ML"
  value       = kubernetes_storage_class.hyperdisk_ml.metadata[0].name
}

# Resource summary
output "resource_summary" {
  description = "Summary of deployed resources"
  value = {
    hyperdisk_ml = {
      name       = google_compute_disk.hyperdisk_ml.name
      size_gb    = google_compute_disk.hyperdisk_ml.size
      throughput = "${google_compute_disk.hyperdisk_ml.provisioned_throughput} MiB/s"
    }
    gke_cluster = {
      name     = google_container_cluster.ml_ops_cluster.name
      location = google_container_cluster.ml_ops_cluster.location
      version  = google_container_cluster.ml_ops_cluster.master_version
    }
    automation = {
      function_name = google_cloudfunctions_function.ml_ops_automation.name
      schedulers    = length([
        google_cloud_scheduler_job.ml_ops_scheduler.name,
        google_cloud_scheduler_job.performance_monitor.name
      ])
    }
    storage = {
      datasets_bucket = google_storage_bucket.ml_datasets.name
      lifecycle_rules = length(google_storage_bucket.ml_datasets.lifecycle_rule)
    }
  }
}

# Cost estimation guidance
output "cost_guidance" {
  description = "Guidance for cost estimation and optimization"
  value = {
    hyperdisk_ml_cost = "High-performance storage with premium pricing - monitor utilization"
    gke_cluster_cost  = "Autoscaling enabled - costs vary with workload demand"
    gpu_nodes_cost    = "GPU nodes are expensive - ensure proper workload scheduling"
    optimization_tips = [
      "Use preemptible instances for non-critical training workloads",
      "Monitor Hyperdisk ML throughput utilization for right-sizing",
      "Leverage Cloud Storage lifecycle policies for dataset cost optimization",
      "Set up budget alerts for ML workload spending"
    ]
  }
}

# Security recommendations
output "security_recommendations" {
  description = "Security best practices for the deployed infrastructure"
  value = {
    workload_identity = "Enabled for secure pod-to-service communication"
    private_cluster   = var.enable_private_cluster ? "Enabled" : "Consider enabling for production"
    network_policy    = var.enable_network_policy ? "Enabled" : "Consider enabling for network security"
    recommendations = [
      "Regularly rotate service account keys",
      "Monitor and audit access to ML datasets",
      "Use Binary Authorization for container image security",
      "Enable VPC Flow Logs for network monitoring"
    ]
  }
}

# Next steps guidance
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Configure kubectl: ${local.kubectl_config_command}",
    "Deploy sample ML workload to test Hyperdisk ML performance",
    "Set up monitoring dashboards for ML workload visibility",
    "Configure Gemini Cloud Assist (requires private preview access)",
    "Implement custom training pipelines using Vertex AI",
    "Set up CI/CD pipelines for ML model deployment"
  ]
}

# Local values for internal use
locals {
  kubectl_config_command = "gcloud container clusters get-credentials ${google_container_cluster.ml_ops_cluster.name} --zone=${var.zone} --project=${var.project_id}"
}
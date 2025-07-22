# ================================================================
# Outputs for Large Language Model Inference with TPU Ironwood
# 
# This file defines all output values that provide essential
# information about the deployed infrastructure, including
# connection details, resource identifiers, and configuration
# values needed for subsequent operations.
# ================================================================

# ----------------------------------------------------------------
# Project and Location Information
# ----------------------------------------------------------------
output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

# ----------------------------------------------------------------
# GKE Cluster Information
# ----------------------------------------------------------------
output "cluster_name" {
  description = "Name of the GKE cluster with TPU Ironwood support"
  value       = google_container_cluster.tpu_cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint for the GKE cluster API server"
  value       = google_container_cluster.tpu_cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 encoded public certificate for cluster access"
  value       = google_container_cluster.tpu_cluster.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location (zone) of the GKE cluster"
  value       = google_container_cluster.tpu_cluster.location
}

output "cluster_node_version" {
  description = "Current node version of the GKE cluster"
  value       = google_container_cluster.tpu_cluster.node_version
}

output "cluster_master_version" {
  description = "Current master version of the GKE cluster"
  value       = google_container_cluster.tpu_cluster.master_version
}

# ----------------------------------------------------------------
# kubectl Configuration Command
# ----------------------------------------------------------------
output "kubectl_config_command" {
  description = "Command to configure kubectl for accessing the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.tpu_cluster.name} --zone=${google_container_cluster.tpu_cluster.location} --project=${var.project_id}"
}

# ----------------------------------------------------------------
# Node Pool Information
# ----------------------------------------------------------------
output "standard_node_pool_name" {
  description = "Name of the standard node pool for system components"
  value       = google_container_node_pool.standard_pool.name
}

output "tpu_node_pool_name" {
  description = "Name of the TPU node pool for inference workloads"
  value       = google_container_node_pool.tpu_pool.name
}

output "tpu_accelerator_config" {
  description = "TPU accelerator configuration details"
  value = {
    type  = var.tpu_accelerator_type
    count = var.tpu_accelerator_count
  }
}

# ----------------------------------------------------------------
# Storage Resources
# ----------------------------------------------------------------
output "model_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for model artifacts"
  value       = google_storage_bucket.model_storage.name
}

output "model_storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for model artifacts"
  value       = google_storage_bucket.model_storage.url
}

output "model_storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.model_storage.location
}

output "parallelstore_instance_name" {
  description = "Name of the Parallelstore instance for high-performance storage"
  value       = google_parallelstore_instance.model_storage.instance_id
}

output "parallelstore_capacity" {
  description = "Capacity of the Parallelstore instance in GiB"
  value       = google_parallelstore_instance.model_storage.capacity_gib
}

output "parallelstore_performance_tier" {
  description = "Performance tier of the Parallelstore instance"
  value       = google_parallelstore_instance.model_storage.performance_tier
}

# ----------------------------------------------------------------
# IAM and Security
# ----------------------------------------------------------------
output "service_account_email" {
  description = "Email address of the TPU inference service account"
  value       = google_service_account.tpu_inference.email
}

output "service_account_name" {
  description = "Full resource name of the TPU inference service account"
  value       = google_service_account.tpu_inference.name
}

output "workload_identity_config" {
  description = "Workload Identity configuration for Kubernetes integration"
  value = {
    gcp_service_account = google_service_account.tpu_inference.email
    k8s_namespace       = var.k8s_namespace
    k8s_service_account = var.k8s_service_account
  }
}

# ----------------------------------------------------------------
# Monitoring and Observability
# ----------------------------------------------------------------
output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard for TPU inference metrics"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.tpu_inference_dashboard.id}?project=${var.project_id}"
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for TPU inference logs"
  value       = google_logging_project_sink.tpu_inference_logs.name
}

# ----------------------------------------------------------------
# Network Configuration
# ----------------------------------------------------------------
output "cluster_ipv4_cidr" {
  description = "CIDR block used for cluster pods"
  value       = var.cluster_ipv4_cidr
}

output "services_ipv4_cidr" {
  description = "CIDR block used for cluster services"
  value       = var.services_ipv4_cidr
}

# ----------------------------------------------------------------
# Model Configuration
# ----------------------------------------------------------------
output "model_configuration" {
  description = "Configuration details for the deployed model"
  value = {
    name    = var.model_name
    version = var.model_version
    path    = "gs://${google_storage_bucket.model_storage.name}/models/${var.model_name}/"
  }
}

# ----------------------------------------------------------------
# Resource Identifiers and Labels
# ----------------------------------------------------------------
output "resource_labels" {
  description = "Common labels applied to all resources"
  value = merge({
    environment = var.environment
    project     = "llm-inference"
    recipe      = "tpu-ironwood-inference"
    managed-by  = "terraform"
  }, var.custom_labels)
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# ----------------------------------------------------------------
# Cost and Resource Information
# ----------------------------------------------------------------
output "estimated_hourly_cost_info" {
  description = "Information about estimated hourly costs (for reference only)"
  value = {
    message = "TPU Ironwood costs vary by region and usage. Refer to Google Cloud pricing calculator for current rates."
    factors = [
      "TPU accelerator hours",
      "GKE cluster management",
      "Parallelstore capacity and performance tier",
      "Cloud Storage data storage and transfer",
      "Standard compute instances"
    ]
    cost_optimization = var.enable_cost_optimization ? "Enabled" : "Disabled"
  }
}

# ----------------------------------------------------------------
# Volume Populator Configuration
# ----------------------------------------------------------------
output "volume_populator_config" {
  description = "Configuration for GKE Volume Populator setup"
  value = {
    source_bucket      = google_storage_bucket.model_storage.name
    destination_store  = google_parallelstore_instance.model_storage.instance_id
    service_account    = google_service_account.tpu_inference.email
    parallelstore_name = google_parallelstore_instance.model_storage.instance_id
  }
}

# ----------------------------------------------------------------
# Deployment Commands
# ----------------------------------------------------------------
output "deployment_commands" {
  description = "Key commands for deploying and managing the inference workload"
  value = {
    configure_kubectl = "gcloud container clusters get-credentials ${google_container_cluster.tpu_cluster.name} --zone=${google_container_cluster.tpu_cluster.location} --project=${var.project_id}"
    upload_model      = "gsutil -m cp -r /path/to/model/* gs://${google_storage_bucket.model_storage.name}/models/${var.model_name}/"
    create_k8s_sa     = "kubectl create serviceaccount ${var.k8s_service_account} --namespace=${var.k8s_namespace}"
    annotate_k8s_sa   = "kubectl annotate serviceaccount ${var.k8s_service_account} --namespace=${var.k8s_namespace} iam.gke.io/gcp-service-account=${google_service_account.tpu_inference.email}"
  }
}

# ----------------------------------------------------------------
# Health Check and Validation
# ----------------------------------------------------------------
output "validation_commands" {
  description = "Commands for validating the deployed infrastructure"
  value = {
    check_cluster_status = "kubectl get nodes -o wide"
    check_tpu_nodes      = "kubectl get nodes -l cloud.google.com/gke-accelerator=${var.tpu_accelerator_type}"
    verify_storage       = "gsutil ls gs://${google_storage_bucket.model_storage.name}/"
    check_parallelstore  = "gcloud parallelstore instances describe ${google_parallelstore_instance.model_storage.instance_id} --location=${var.zone}"
    monitoring_dashboard = "echo 'Dashboard URL: https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.tpu_inference_dashboard.id}?project=${var.project_id}'"
  }
}

# ----------------------------------------------------------------
# Security and Compliance Information
# ----------------------------------------------------------------
output "security_config" {
  description = "Security configuration summary"
  value = {
    workload_identity_enabled = true
    network_policy_enabled    = var.enable_network_policy
    private_cluster          = false
    encryption_at_rest       = "Google-managed encryption keys"
    service_account_key_free = true
    least_privilege_iam      = true
  }
}

# ----------------------------------------------------------------
# Next Steps and Documentation
# ----------------------------------------------------------------
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = [
    "1. Configure kubectl using the provided command",
    "2. Upload your LLM model artifacts to the Cloud Storage bucket",
    "3. Create and annotate the Kubernetes service account for Workload Identity",
    "4. Deploy the TPU inference workload with Volume Populator configuration",
    "5. Verify model loading performance and inference latency",
    "6. Monitor performance metrics through the Cloud Monitoring dashboard",
    "7. Scale TPU resources based on inference demand",
    "8. Implement model versioning and A/B testing if needed"
  ]
}
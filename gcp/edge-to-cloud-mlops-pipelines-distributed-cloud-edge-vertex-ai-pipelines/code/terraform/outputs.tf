# =============================================================================
# OUTPUTS - Edge-to-Cloud MLOps Pipelines Infrastructure
# =============================================================================
# This file defines all output values from the MLOps pipeline infrastructure
# deployment, providing essential information for integration and management.

# =============================================================================
# PROJECT AND REGION INFORMATION
# =============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone used for zonal resources"
  value       = var.zone
}

output "environment" {
  description = "The environment designation for this deployment"
  value       = var.environment
}

# =============================================================================
# STORAGE OUTPUTS
# =============================================================================

output "mlops_artifacts_bucket_name" {
  description = "Name of the Cloud Storage bucket for MLOps artifacts and training data"
  value       = google_storage_bucket.mlops_artifacts.name
}

output "mlops_artifacts_bucket_url" {
  description = "URL of the Cloud Storage bucket for MLOps artifacts"
  value       = google_storage_bucket.mlops_artifacts.url
}

output "edge_models_bucket_name" {
  description = "Name of the Cloud Storage bucket for edge model deployment"
  value       = google_storage_bucket.edge_models.name
}

output "edge_models_bucket_url" {
  description = "URL of the Cloud Storage bucket for edge models"
  value       = google_storage_bucket.edge_models.url
}

output "telemetry_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for telemetry data collection"
  value       = google_storage_bucket.telemetry_data.name
}

output "telemetry_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for telemetry data"
  value       = google_storage_bucket.telemetry_data.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

# =============================================================================
# GKE CLUSTER OUTPUTS
# =============================================================================

output "gke_cluster_name" {
  description = "Name of the GKE cluster for edge simulation and inference workloads"
  value       = google_container_cluster.edge_simulation_cluster.name
}

output "gke_cluster_endpoint" {
  description = "Endpoint for the GKE cluster API server"
  value       = google_container_cluster.edge_simulation_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "Base64 encoded public certificate that is the root of trust for the cluster"
  value       = google_container_cluster.edge_simulation_cluster.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

output "gke_cluster_location" {
  description = "Location (region or zone) of the GKE cluster"
  value       = google_container_cluster.edge_simulation_cluster.location
}

output "gke_cluster_self_link" {
  description = "Self-link of the GKE cluster"
  value       = google_container_cluster.edge_simulation_cluster.self_link
}

output "gke_cluster_master_version" {
  description = "Current master version of the GKE cluster"
  value       = google_container_cluster.edge_simulation_cluster.master_version
}

output "gke_general_purpose_node_pool_name" {
  description = "Name of the general-purpose node pool"
  value       = google_container_node_pool.general_purpose_nodes.name
}

output "gke_ml_inference_node_pool_name" {
  description = "Name of the ML inference node pool"
  value       = google_container_node_pool.ml_inference_nodes.name
}

# =============================================================================
# NETWORK INFRASTRUCTURE OUTPUTS
# =============================================================================

output "vpc_network_name" {
  description = "Name of the VPC network created for MLOps infrastructure"
  value       = google_compute_network.mlops_network.name
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.mlops_network.self_link
}

output "mlops_subnet_name" {
  description = "Name of the subnet for MLOps infrastructure"
  value       = google_compute_subnetwork.mlops_subnet.name
}

output "mlops_subnet_cidr" {
  description = "CIDR range of the MLOps subnet"
  value       = google_compute_subnetwork.mlops_subnet.ip_cidr_range
}

output "pods_secondary_range_name" {
  description = "Name of the secondary IP range for Kubernetes pods"
  value       = google_compute_subnetwork.mlops_subnet.secondary_ip_range[0].range_name
}

output "services_secondary_range_name" {
  description = "Name of the secondary IP range for Kubernetes services"
  value       = google_compute_subnetwork.mlops_subnet.secondary_ip_range[1].range_name
}

output "cloud_router_name" {
  description = "Name of the Cloud Router for NAT gateway"
  value       = google_compute_router.mlops_router.name
}

output "cloud_nat_name" {
  description = "Name of the Cloud NAT gateway"
  value       = google_compute_router_nat.mlops_nat.name
}

# =============================================================================
# IAM SERVICE ACCOUNT OUTPUTS
# =============================================================================

output "mlops_pipeline_service_account_email" {
  description = "Email of the service account for MLOps pipeline operations"
  value       = google_service_account.mlops_pipeline_sa.email
}

output "mlops_pipeline_service_account_id" {
  description = "ID of the service account for MLOps pipeline operations"
  value       = google_service_account.mlops_pipeline_sa.account_id
}

output "edge_inference_service_account_email" {
  description = "Email of the service account for edge inference workloads"
  value       = google_service_account.edge_inference_sa.email
}

output "edge_inference_service_account_id" {
  description = "ID of the service account for edge inference workloads"
  value       = google_service_account.edge_inference_sa.account_id
}

output "telemetry_collector_service_account_email" {
  description = "Email of the service account for telemetry collection"
  value       = google_service_account.telemetry_collector_sa.email
}

output "telemetry_collector_service_account_id" {
  description = "ID of the service account for telemetry collection"
  value       = google_service_account.telemetry_collector_sa.account_id
}

# =============================================================================
# CLOUD FUNCTION OUTPUTS
# =============================================================================

output "model_updater_function_name" {
  description = "Name of the Cloud Function for automated model updates"
  value       = google_cloudfunctions_function.model_updater.name
}

output "model_updater_function_url" {
  description = "HTTP trigger URL for the model updater Cloud Function"
  value       = google_cloudfunctions_function.model_updater.https_trigger_url
  sensitive   = true
}

output "model_updater_function_source_archive_url" {
  description = "URL of the source archive for the model updater function"
  value       = "gs://${google_storage_bucket.function_source.name}/${google_storage_bucket_object.model_updater_source.name}"
}

# =============================================================================
# MONITORING AND ALERTING OUTPUTS
# =============================================================================

output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard for MLOps observability"
  value       = google_monitoring_dashboard.mlops_dashboard.id
}

output "alert_notification_channel_id" {
  description = "ID of the notification channel for monitoring alerts"
  value       = google_monitoring_notification_channel.email_channel.id
}

output "edge_service_health_alert_policy_id" {
  description = "ID of the alert policy for edge service health monitoring"
  value       = google_monitoring_alert_policy.edge_service_health.id
}

output "high_prediction_latency_alert_policy_id" {
  description = "ID of the alert policy for high prediction latency monitoring"
  value       = google_monitoring_alert_policy.high_prediction_latency.id
}

output "alert_email" {
  description = "Email address configured for monitoring alerts"
  value       = var.alert_email
  sensitive   = true
}

# =============================================================================
# KUBERNETES CONFIGURATION OUTPUTS
# =============================================================================

output "kubernetes_namespace_name" {
  description = "Name of the Kubernetes namespace for edge inference workloads"
  value       = kubernetes_namespace.edge_inference.metadata[0].name
}

output "kubernetes_service_account_name" {
  description = "Name of the Kubernetes service account with workload identity"
  value       = kubernetes_service_account.edge_inference_ksa.metadata[0].name
}

output "edge_inference_config_map_name" {
  description = "Name of the ConfigMap containing edge inference configuration"
  value       = kubernetes_config_map.edge_inference_config.metadata[0].name
}

# =============================================================================
# KUBECTL COMMANDS
# =============================================================================

output "kubectl_config_command" {
  description = "Command to configure kubectl for the created GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.edge_simulation_cluster.name} --region=${google_container_cluster.edge_simulation_cluster.location} --project=${var.project_id}"
}

output "kubectl_namespace_command" {
  description = "Command to switch kubectl to the edge inference namespace"
  value       = "kubectl config set-context --current --namespace=${kubernetes_namespace.edge_inference.metadata[0].name}"
}

# =============================================================================
# DEPLOYMENT VERIFICATION COMMANDS
# =============================================================================

output "verify_storage_buckets_command" {
  description = "Command to verify all storage buckets were created successfully"
  value       = "gsutil ls -p ${var.project_id}"
}

output "verify_gke_cluster_command" {
  description = "Command to verify GKE cluster status"
  value       = "gcloud container clusters describe ${google_container_cluster.edge_simulation_cluster.name} --region=${google_container_cluster.edge_simulation_cluster.location} --project=${var.project_id}"
}

output "verify_monitoring_dashboard_command" {
  description = "Command to open the monitoring dashboard in browser"
  value       = "gcloud monitoring dashboards list --filter='displayName:\"Edge MLOps Pipeline Dashboard\"' --project=${var.project_id}"
}

output "test_model_updater_function_command" {
  description = "Command to test the model updater Cloud Function"
  value       = "gcloud functions call ${google_cloudfunctions_function.model_updater.name} --region=${var.region} --data='{}'"
}

# =============================================================================
# INTEGRATION ENDPOINTS
# =============================================================================

output "vertex_ai_pipeline_root" {
  description = "Google Cloud Storage path for Vertex AI Pipeline artifacts"
  value       = "gs://${google_storage_bucket.mlops_artifacts.name}/pipeline-root"
}

output "model_registry_path" {
  description = "Path for model registry artifacts in Cloud Storage"
  value       = "gs://${google_storage_bucket.mlops_artifacts.name}/models"
}

output "training_data_path" {
  description = "Path for training data in Cloud Storage"
  value       = "gs://${google_storage_bucket.mlops_artifacts.name}/training-data"
}

output "telemetry_data_path" {
  description = "Path for telemetry data collection in Cloud Storage"
  value       = "gs://${google_storage_bucket.telemetry_data.name}/telemetry"
}

output "edge_model_deployment_path" {
  description = "Path for edge model deployment artifacts"
  value       = "gs://${google_storage_bucket.edge_models.name}/models"
}

# =============================================================================
# RESOURCE IDENTIFIERS
# =============================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "resource_names_summary" {
  description = "Summary of all major resource names created"
  value = {
    gke_cluster            = google_container_cluster.edge_simulation_cluster.name
    mlops_artifacts_bucket = google_storage_bucket.mlops_artifacts.name
    edge_models_bucket     = google_storage_bucket.edge_models.name
    telemetry_bucket       = google_storage_bucket.telemetry_data.name
    vpc_network           = google_compute_network.mlops_network.name
    model_updater_function = google_cloudfunctions_function.model_updater.name
    monitoring_dashboard   = google_monitoring_dashboard.mlops_dashboard.id
  }
}

# =============================================================================
# COST TRACKING
# =============================================================================

output "estimated_monthly_cost_factors" {
  description = "Key factors that contribute to monthly costs (for estimation purposes)"
  value = {
    gke_node_count                = var.gke_node_count
    general_purpose_machine_type  = var.general_purpose_machine_type
    ml_inference_machine_type     = var.ml_inference_machine_type
    use_preemptible_nodes        = var.use_preemptible_nodes
    storage_class                = var.storage_class
    enable_monitoring            = var.enable_monitoring
    function_max_instances       = var.function_max_instances
  }
}

# =============================================================================
# SECURITY INFORMATION
# =============================================================================

output "security_features_enabled" {
  description = "Summary of security features enabled in this deployment"
  value = {
    workload_identity           = var.enable_workload_identity
    network_policy             = var.enable_network_policy
    shielded_nodes             = var.enable_shielded_nodes
    private_nodes              = var.enable_private_nodes
    uniform_bucket_level_access = true
    service_account_separation  = true
  }
}

# =============================================================================
# NEXT STEPS
# =============================================================================

output "deployment_next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = [
    "1. Configure kubectl: ${local.kubectl_config_command}",
    "2. Verify storage buckets: gsutil ls -p ${var.project_id}",
    "3. Deploy edge inference workloads to Kubernetes namespace: ${kubernetes_namespace.edge_inference.metadata[0].name}",
    "4. Set up Vertex AI Pipeline workflows using bucket: ${google_storage_bucket.mlops_artifacts.name}",
    "5. Configure monitoring alerts using dashboard: ${google_monitoring_dashboard.mlops_dashboard.id}",
    "6. Test model update automation: gcloud functions call ${google_cloudfunctions_function.model_updater.name}",
    "7. Review security settings and adjust IAM permissions as needed"
  ]
}

# =============================================================================
# LOCAL VALUES FOR OUTPUT COMPUTATION
# =============================================================================

locals {
  kubectl_config_command = "gcloud container clusters get-credentials ${google_container_cluster.edge_simulation_cluster.name} --region=${google_container_cluster.edge_simulation_cluster.location} --project=${var.project_id}"
}
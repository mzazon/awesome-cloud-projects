# Outputs for high-frequency trading risk analytics infrastructure

# =============================================================================
# PROJECT AND IDENTITY OUTPUTS
# =============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "project_number" {
  description = "Google Cloud Project Number for service account references"
  value       = data.google_project.current.number
}

output "region" {
  description = "Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

# =============================================================================
# NETWORKING OUTPUTS
# =============================================================================

output "network_name" {
  description = "Name of the VPC network created for the trading infrastructure"
  value       = google_compute_network.hft_network.name
}

output "network_id" {
  description = "ID of the VPC network created for the trading infrastructure"
  value       = google_compute_network.hft_network.id
}

output "subnet_name" {
  description = "Name of the subnet created for the trading infrastructure"
  value       = google_compute_subnetwork.hft_subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet used by the trading infrastructure"
  value       = google_compute_subnetwork.hft_subnet.ip_cidr_range
}

# =============================================================================
# TPU IRONWOOD CLUSTER OUTPUTS
# =============================================================================

output "tpu_name" {
  description = "Name of the TPU Ironwood cluster for AI inference"
  value       = google_tpu_v2_vm.ironwood_cluster.name
}

output "tpu_id" {
  description = "Full resource ID of the TPU Ironwood cluster"
  value       = google_tpu_v2_vm.ironwood_cluster.id
}

output "tpu_state" {
  description = "Current operational state of the TPU cluster"
  value       = google_tpu_v2_vm.ironwood_cluster.state
}

output "tpu_health" {
  description = "Health status of the TPU cluster"
  value       = google_tpu_v2_vm.ironwood_cluster.health
}

output "tpu_accelerator_type" {
  description = "Accelerator type configuration of the TPU cluster"
  value       = var.tpu_accelerator_type
}

output "tpu_network_endpoints" {
  description = "Network endpoints for connecting to TPU workers"
  value = [
    for endpoint in google_tpu_v2_vm.ironwood_cluster.network_endpoints : {
      ip_address = endpoint.ip_address
      port       = endpoint.port
    }
  ]
  sensitive = true
}

output "tpu_service_account_email" {
  description = "Email of the service account used by the TPU cluster"
  value       = google_service_account.tpu_service_account.email
}

# =============================================================================
# DATASTREAM OUTPUTS
# =============================================================================

output "datastream_enabled" {
  description = "Whether Cloud Datastream is enabled for real-time replication"
  value       = var.enable_datastream
}

output "datastream_stream_name" {
  description = "Name of the Datastream pipeline for real-time data replication"
  value       = var.enable_datastream && var.source_database_host != "" ? google_datastream_stream.trading_data_stream[0].stream_id : null
}

output "datastream_stream_state" {
  description = "Current state of the Datastream pipeline"
  value       = var.enable_datastream && var.source_database_host != "" ? google_datastream_stream.trading_data_stream[0].state : null
}

output "datastream_source_profile_id" {
  description = "Connection profile ID for the source database"
  value       = var.enable_datastream && var.source_database_host != "" ? google_datastream_connection_profile.source_connection_profile[0].connection_profile_id : null
}

output "datastream_destination_profile_id" {
  description = "Connection profile ID for the BigQuery destination"
  value       = var.enable_datastream ? google_datastream_connection_profile.destination_connection_profile[0].connection_profile_id : null
}

# =============================================================================
# BIGQUERY ANALYTICS OUTPUTS
# =============================================================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for trading analytics data"
  value       = google_bigquery_dataset.trading_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.trading_dataset.location
}

output "trading_positions_table_id" {
  description = "Full table ID for the trading positions table"
  value       = "${var.project_id}.${google_bigquery_dataset.trading_dataset.dataset_id}.${google_bigquery_table.trading_positions.table_id}"
}

output "risk_metrics_table_id" {
  description = "Full table ID for the risk metrics table"
  value       = "${var.project_id}.${google_bigquery_dataset.trading_dataset.dataset_id}.${google_bigquery_table.risk_metrics.table_id}"
}

output "real_time_risk_view_id" {
  description = "Full view ID for the real-time risk dashboard"
  value       = "${var.project_id}.${google_bigquery_dataset.trading_dataset.dataset_id}.${google_bigquery_table.real_time_risk_view.table_id}"
}

# =============================================================================
# CLOUD RUN API OUTPUTS
# =============================================================================

output "risk_analytics_api_name" {
  description = "Name of the Cloud Run risk analytics API service"
  value       = google_cloud_run_v2_service.risk_analytics_api.name
}

output "risk_analytics_api_url" {
  description = "URL of the deployed risk analytics API service"
  value       = google_cloud_run_v2_service.risk_analytics_api.uri
}

output "risk_analytics_api_ready_condition" {
  description = "Ready condition status of the Cloud Run service"
  value = length(google_cloud_run_v2_service.risk_analytics_api.conditions) > 0 ? {
    for condition in google_cloud_run_v2_service.risk_analytics_api.conditions :
    condition.type => condition.state
    if condition.type == "Ready"
  } : {}
}

output "cloud_run_service_account_email" {
  description = "Email of the service account used by Cloud Run services"
  value       = google_service_account.cloud_run_service_account.email
}

output "container_registry_url" {
  description = "URL of the Artifact Registry repository for container images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}"
}

# =============================================================================
# STORAGE OUTPUTS
# =============================================================================

output "data_bucket_name" {
  description = "Name of the Cloud Storage bucket for model artifacts and data"
  value       = google_storage_bucket.hft_data_bucket.name
}

output "data_bucket_url" {
  description = "Full GCS URL of the data bucket"
  value       = google_storage_bucket.hft_data_bucket.url
}

# =============================================================================
# SECURITY AND ENCRYPTION OUTPUTS
# =============================================================================

output "encryption_enabled" {
  description = "Whether customer-managed encryption is enabled"
  value       = var.enable_encryption
}

output "kms_keyring_id" {
  description = "ID of the KMS keyring for encryption"
  value       = var.enable_encryption ? google_kms_key_ring.hft_keyring[0].id : null
}

output "kms_key_id" {
  description = "ID of the KMS encryption key"
  value       = var.enable_encryption ? google_kms_crypto_key.hft_encryption_key[0].id : null
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email_alerts[0].id : null
}

output "tpu_latency_alert_policy_id" {
  description = "ID of the TPU latency alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.tpu_latency_alert[0].id : null
}

output "api_response_time_alert_policy_id" {
  description = "ID of the API response time alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.api_response_time_alert[0].id : null
}

output "trading_error_metric_name" {
  description = "Name of the log-based metric for trading errors"
  value       = var.enable_monitoring ? google_logging_metric.trading_error_rate[0].name : null
}

# =============================================================================
# CONNECTION AND CONFIGURATION OUTPUTS
# =============================================================================

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "deletion_protection" {
  description = "Whether deletion protection is enabled for critical resources"
  value       = var.deletion_protection
}

# =============================================================================
# OPERATIONAL OUTPUTS
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed high-frequency trading infrastructure"
  value = {
    project_id           = var.project_id
    environment          = var.environment
    region               = var.region
    tpu_cluster_name     = google_tpu_v2_vm.ironwood_cluster.name
    tpu_accelerator_type = var.tpu_accelerator_type
    api_service_url      = google_cloud_run_v2_service.risk_analytics_api.uri
    bigquery_dataset     = google_bigquery_dataset.trading_dataset.dataset_id
    datastream_enabled   = var.enable_datastream
    monitoring_enabled   = var.enable_monitoring
    encryption_enabled   = var.enable_encryption
    deletion_protection  = var.deletion_protection
  }
}

output "next_steps" {
  description = "Next steps for completing the deployment"
  value = [
    "1. Verify TPU cluster is in READY state: gcloud compute tpus tpu-vm describe ${google_tpu_v2_vm.ironwood_cluster.name} --zone=${var.zone}",
    "2. Deploy risk analytics application to Cloud Run: gcloud run deploy ${google_cloud_run_v2_service.risk_analytics_api.name} --image=YOUR_IMAGE_URL --region=${var.region}",
    var.enable_datastream && var.source_database_host != "" ? "3. Start Datastream pipeline: gcloud datastream streams update ${google_datastream_stream.trading_data_stream[0].stream_id} --location=${var.region} --update-mask=desiredState --desired-state=RUNNING" : "3. Configure Datastream with your source database details and start the pipeline",
    "4. Load financial risk models onto TPU cluster using the network endpoints",
    "5. Configure trading data schemas in BigQuery tables",
    "6. Set up monitoring dashboards in Cloud Monitoring console",
    var.enable_encryption ? "7. Verify KMS encryption is properly configured for all data at rest" : "7. Consider enabling customer-managed encryption for production environments"
  ]
}

# =============================================================================
# TERRAFORM STATE OUTPUTS
# =============================================================================

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.name_suffix
}
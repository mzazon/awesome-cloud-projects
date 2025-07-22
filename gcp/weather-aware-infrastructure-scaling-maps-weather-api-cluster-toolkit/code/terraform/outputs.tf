# Network Infrastructure Outputs
output "network_name" {
  description = "Name of the VPC network created for HPC cluster"
  value       = google_compute_network.hpc_network.name
}

output "network_id" {
  description = "ID of the VPC network created for HPC cluster"
  value       = google_compute_network.hpc_network.id
}

output "subnet_name" {
  description = "Name of the subnet created for HPC cluster"
  value       = google_compute_subnetwork.hpc_subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet created for HPC cluster"
  value       = google_compute_subnetwork.hpc_subnet.ip_cidr_range
}

# Storage Infrastructure Outputs
output "weather_data_bucket" {
  description = "Name of the Cloud Storage bucket for weather data"
  value       = google_storage_bucket.weather_data.name
}

output "weather_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for weather data"
  value       = google_storage_bucket.weather_data.url
}

output "filestore_instance_name" {
  description = "Name of the Filestore instance for shared cluster storage"
  value       = google_filestore_instance.hpc_shared_storage.name
}

output "filestore_ip_address" {
  description = "IP address of the Filestore instance"
  value       = google_filestore_instance.hpc_shared_storage.networks[0].ip_addresses[0]
}

output "filestore_share_name" {
  description = "Name of the Filestore share"
  value       = google_filestore_instance.hpc_shared_storage.file_shares[0].name
}

output "filestore_mount_path" {
  description = "Mount path for the Filestore share"
  value       = "/mnt/shared"
}

# Messaging Infrastructure Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for weather scaling events"
  value       = google_pubsub_topic.weather_scaling.name
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for weather scaling events"
  value       = google_pubsub_subscription.weather_scaling_sub.name
}

output "pubsub_dlq_topic_name" {
  description = "Name of the dead letter queue topic for failed scaling messages"
  value       = google_pubsub_topic.weather_scaling_dlq.name
}

# Cloud Function Outputs
output "weather_function_name" {
  description = "Name of the Cloud Function for weather processing"
  value       = google_cloudfunctions_function.weather_processor.name
}

output "weather_function_url" {
  description = "HTTP trigger URL for the weather processing function"
  value       = google_cloudfunctions_function.weather_processor.https_trigger_url
}

output "weather_function_service_account" {
  description = "Service account email for the weather processing function"
  value       = google_service_account.weather_function_sa.email
}

# HPC Cluster Outputs
output "cluster_name" {
  description = "Full name of the HPC cluster deployment"
  value       = local.cluster_name_full
}

output "cluster_instance_template" {
  description = "Name of the instance template for HPC cluster nodes"
  value       = google_compute_instance_template.hpc_node_template.name
}

output "cluster_instance_group_manager" {
  description = "Name of the managed instance group for HPC cluster"
  value       = google_compute_region_instance_group_manager.hpc_cluster_igm.name
}

output "cluster_autoscaler_name" {
  description = "Name of the autoscaler for HPC cluster"
  value       = google_compute_region_autoscaler.hpc_cluster_autoscaler.name
}

output "cluster_service_account" {
  description = "Service account email for HPC cluster nodes"
  value       = google_service_account.hpc_cluster_sa.email
}

output "cluster_health_check" {
  description = "Name of the health check for HPC cluster nodes"
  value       = google_compute_health_check.hpc_health_check.name
}

# Security Outputs
output "kms_keyring_name" {
  description = "Name of the KMS keyring for encryption"
  value       = google_kms_key_ring.weather_keyring.name
}

output "kms_key_name" {
  description = "Name of the KMS key for storage encryption"
  value       = google_kms_crypto_key.storage_key.name
}

output "weather_api_secret_name" {
  description = "Name of the Secret Manager secret for Weather API key"
  value       = google_secret_manager_secret.weather_api_key.secret_id
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL to access the weather-aware HPC monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.weather_hpc_dashboard.id}?project=${var.project_id}"
}

output "alert_policy_name" {
  description = "Name of the alert policy for high scaling factors"
  value       = google_monitoring_alert_policy.high_scaling_factor.name
}

output "notification_channel_name" {
  description = "Name of the notification channel for alerts"
  value       = google_monitoring_notification_channel.email_alerts.name
}

# Scheduler Outputs
output "weather_check_job_name" {
  description = "Name of the regular weather check scheduler job"
  value       = google_cloud_scheduler_job.weather_check.name
}

output "storm_monitor_job_name" {
  description = "Name of the storm monitoring scheduler job"
  value       = google_cloud_scheduler_job.storm_monitor.name
}

output "weather_check_schedule" {
  description = "Cron schedule for regular weather checks"
  value       = google_cloud_scheduler_job.weather_check.schedule
}

output "storm_monitor_schedule" {
  description = "Cron schedule for storm monitoring"
  value       = google_cloud_scheduler_job.storm_monitor.schedule
}

# Cost Management Outputs
output "budget_name" {
  description = "Name of the budget for cost monitoring"
  value       = google_billing_budget.weather_hpc_budget.display_name
}

output "budget_amount" {
  description = "Budget amount in USD for monthly cost monitoring"
  value       = var.budget_amount
}

# Configuration Outputs
output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region for resource deployment"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone for zonal resources"
  value       = var.zone
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

# Weather Configuration Outputs
output "weather_monitoring_locations" {
  description = "List of geographic locations monitored for weather data"
  value       = var.weather_monitoring_locations
}

output "cluster_scaling_configuration" {
  description = "Configuration for cluster scaling parameters"
  value = {
    machine_type       = var.cluster_machine_type
    min_nodes         = var.cluster_min_nodes
    max_nodes         = var.cluster_max_nodes
    enable_spot       = var.enable_spot_instances
    filestore_size_gb = var.filestore_capacity_gb
    filestore_tier    = var.filestore_tier
  }
}

# Access Information
output "cluster_access_instructions" {
  description = "Instructions for accessing the HPC cluster"
  value = var.enable_iap ? {
    access_method = "Identity-Aware Proxy (IAP)"
    instructions = [
      "Use 'gcloud compute ssh' with --tunnel-through-iap flag",
      "Configure IAP access permissions for your user account",
      "SSH to cluster nodes using their internal IP addresses"
    ]
  } : {
    access_method = "Direct SSH"
    instructions = [
      "SSH directly to cluster nodes using their external IP addresses",
      "Ensure your IP is included in authorized_networks variable",
      "Use standard SSH key authentication"
    ]
  }
}

# Sample Commands for Operations
output "sample_commands" {
  description = "Sample commands for operating the weather-aware HPC system"
  value = {
    test_weather_function = "curl -X GET ${google_cloudfunctions_function.weather_processor.https_trigger_url}"
    list_weather_data     = "gsutil ls gs://${google_storage_bucket.weather_data.name}/weather-data/"
    view_scaling_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.weather_scaling_sub.name} --auto-ack"
    check_cluster_nodes   = "gcloud compute instances list --filter='name~\"hpc-node\"'"
    monitor_cluster       = "gcloud compute instance-groups managed describe ${google_compute_region_instance_group_manager.hpc_cluster_igm.name} --region=${var.region}"
  }
}

# Resource URLs
output "resource_urls" {
  description = "URLs to access key resources in Google Cloud Console"
  value = {
    compute_instances    = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
    cloud_functions      = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.weather_processor.name}?project=${var.project_id}"
    storage_buckets      = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.weather_data.name}?project=${var.project_id}"
    monitoring_dashboard = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.weather_hpc_dashboard.id}?project=${var.project_id}"
    pubsub_topics        = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.weather_scaling.name}?project=${var.project_id}"
    scheduler_jobs       = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    filestore_instances  = "https://console.cloud.google.com/filestore/instances?project=${var.project_id}"
  }
}
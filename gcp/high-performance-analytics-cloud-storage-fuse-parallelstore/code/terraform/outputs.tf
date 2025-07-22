# Project and deployment information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were deployed"
  value       = var.zone
}

output "deployment_id" {
  description = "Unique deployment identifier for resource tracking"
  value       = local.resource_suffix
}

# Storage resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket with hierarchical namespace"
  value       = google_storage_bucket.analytics_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.analytics_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.analytics_data.self_link
}

output "parallelstore_instance_name" {
  description = "Name of the Parallelstore instance"
  value       = google_parallelstore_instance.hpc_storage.instance_id
}

output "parallelstore_access_point_ip" {
  description = "IP address of the Parallelstore access point for NFS mounting"
  value       = google_parallelstore_instance.hpc_storage.access_points[0].access_point_ip
  sensitive   = false
}

output "parallelstore_mount_path" {
  description = "NFS mount path for the Parallelstore instance"
  value       = "/parallelstore"
}

output "parallelstore_capacity_gib" {
  description = "Capacity of the Parallelstore instance in GiB"
  value       = google_parallelstore_instance.hpc_storage.capacity_gib
}

# Compute resources
output "analytics_vm_name" {
  description = "Name of the analytics VM instance"
  value       = google_compute_instance.analytics_vm.name
}

output "analytics_vm_external_ip" {
  description = "External IP address of the analytics VM"
  value       = google_compute_instance.analytics_vm.network_interface[0].access_config[0].nat_ip
  sensitive   = false
}

output "analytics_vm_internal_ip" {
  description = "Internal IP address of the analytics VM"
  value       = google_compute_instance.analytics_vm.network_interface[0].network_ip
}

output "analytics_vm_self_link" {
  description = "Self-link of the analytics VM instance"
  value       = google_compute_instance.analytics_vm.self_link
}

output "analytics_vm_zone" {
  description = "Zone where the analytics VM is deployed"
  value       = google_compute_instance.analytics_vm.zone
}

# Dataproc cluster information
output "dataproc_cluster_name" {
  description = "Name of the Cloud Dataproc cluster"
  value       = google_dataproc_cluster.analytics_cluster.name
}

output "dataproc_cluster_bucket" {
  description = "Staging bucket used by the Dataproc cluster"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].staging_bucket
}

output "dataproc_master_instance_names" {
  description = "Names of the Dataproc master instances"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].master_config[0].instance_names
}

output "dataproc_worker_instance_names" {
  description = "Names of the Dataproc worker instances"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].worker_config[0].instance_names
}

# BigQuery resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.analytics_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.location
}

output "bigquery_table_id" {
  description = "ID of the BigQuery external table for sensor analytics"
  value       = google_bigquery_table.sensor_analytics.table_id
}

output "bigquery_table_reference" {
  description = "Full table reference for BigQuery queries"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.sensor_analytics.table_id}"
}

# Service account information
output "service_account_email" {
  description = "Email address of the created service account"
  value       = var.create_service_account ? google_service_account.analytics_sa[0].email : "N/A - using default service account"
}

output "service_account_id" {
  description = "ID of the created service account"
  value       = var.create_service_account ? google_service_account.analytics_sa[0].account_id : "N/A - using default service account"
}

# Monitoring resources
output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for Parallelstore performance"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.parallelstore_performance[0].name : "N/A - monitoring disabled"
}

output "monitoring_metric_name" {
  description = "Name of the custom monitoring metric for Parallelstore throughput"
  value       = var.enable_monitoring ? google_logging_metric.parallelstore_throughput[0].name : "N/A - monitoring disabled"
}

# Connection and access information
output "ssh_command" {
  description = "Command to SSH into the analytics VM"
  value       = "gcloud compute ssh ${google_compute_instance.analytics_vm.name} --zone=${google_compute_instance.analytics_vm.zone} --project=${var.project_id}"
}

output "cloud_storage_fuse_mount_path" {
  description = "Path where Cloud Storage FUSE is mounted on the analytics VM"
  value       = "/mnt/gcs-data"
}

output "parallelstore_mount_path_vm" {
  description = "Path where Parallelstore is mounted on the analytics VM"
  value       = "/mnt/parallel-store"
}

# Sample commands for testing
output "test_cloud_storage_fuse_command" {
  description = "Command to test Cloud Storage FUSE performance on the analytics VM"
  value       = "time ls -la /mnt/gcs-data/sample_data/raw/2024/01/ | head -10"
}

output "test_parallelstore_command" {
  description = "Command to test Parallelstore performance on the analytics VM"
  value       = "time dd if=/dev/zero of=/mnt/parallel-store/test_file bs=1M count=100 && time dd if=/mnt/parallel-store/test_file of=/dev/null bs=1M && rm /mnt/parallel-store/test_file"
}

output "bigquery_sample_query" {
  description = "Sample BigQuery query to test the external table"
  value       = "SELECT COUNT(*) as total_sensors, AVG(avg_value) as overall_avg FROM `${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.sensor_analytics.table_id}`"
}

# Resource URLs for console access
output "cloud_storage_console_url" {
  description = "URL to view the Cloud Storage bucket in the Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.analytics_data.name}?project=${var.project_id}"
}

output "parallelstore_console_url" {
  description = "URL to view the Parallelstore instance in the Google Cloud Console"
  value       = "https://console.cloud.google.com/compute/parallelstore/instances/details/${var.zone}/${google_parallelstore_instance.hpc_storage.instance_id}?project=${var.project_id}"
}

output "dataproc_console_url" {
  description = "URL to view the Dataproc cluster in the Google Cloud Console"
  value       = "https://console.cloud.google.com/dataproc/clusters/details/${var.region}/${google_dataproc_cluster.analytics_cluster.name}?project=${var.project_id}"
}

output "bigquery_console_url" {
  description = "URL to view the BigQuery dataset in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.analytics_dataset.dataset_id}"
}

output "vm_console_url" {
  description = "URL to view the analytics VM in the Google Cloud Console"
  value       = "https://console.cloud.google.com/compute/instancesDetail/zones/${google_compute_instance.analytics_vm.zone}/instances/${google_compute_instance.analytics_vm.name}?project=${var.project_id}"
}

# Performance optimization tips
output "performance_optimization_tips" {
  description = "Tips for optimizing performance of the high-performance analytics setup"
  value = [
    "Use 'gsutil -m' for parallel Cloud Storage operations",
    "Configure Spark with appropriate memory settings based on your data size",
    "Monitor Parallelstore throughput using Cloud Monitoring metrics",
    "Organize data in Cloud Storage hierarchically to match access patterns",
    "Use Parallelstore for frequently accessed data and Cloud Storage for archival",
    "Enable Cloud Storage Transfer Service for large dataset migrations",
    "Configure Dataproc preemptible instances for cost optimization on non-critical workloads"
  ]
}

# Cost optimization information
output "cost_optimization_recommendations" {
  description = "Recommendations for optimizing costs while maintaining performance"
  value = [
    "Monitor Parallelstore usage and scale down during off-peak hours",
    "Use Cloud Storage lifecycle policies to automatically move cold data to cheaper storage classes",
    "Consider using Dataproc preemptible workers for batch processing jobs",
    "Set up budget alerts to monitor spending on high-performance resources",
    "Review BigQuery slot usage and consider committed use discounts for predictable workloads",
    "Use sustained use discounts for long-running VM instances",
    "Clean up temporary data and intermediate files regularly"
  ]
}

# Next steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. SSH into the analytics VM and verify both storage mounts are working",
    "2. Upload sample data to Cloud Storage and test the analytics pipeline",
    "3. Submit a Spark job to the Dataproc cluster to test end-to-end performance",
    "4. Query the BigQuery external table to verify data accessibility",
    "5. Set up monitoring dashboards for performance tracking",
    "6. Configure alerting for performance thresholds and cost budgets",
    "7. Optimize data organization based on access patterns"
  ]
}
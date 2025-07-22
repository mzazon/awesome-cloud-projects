# Project and basic configuration outputs
output "project_id" {
  description = "Google Cloud Project ID used for the deployment"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone for zonal resources"
  value       = var.zone
}

# Bigtable instance outputs
output "bigtable_instance_id" {
  description = "ID of the Cloud Bigtable instance for supply chain data"
  value       = google_bigtable_instance.supply_chain.name
}

output "bigtable_instance_display_name" {
  description = "Display name of the Cloud Bigtable instance"
  value       = google_bigtable_instance.supply_chain.display_name
}

output "bigtable_connection_info" {
  description = "Connection information for the Bigtable instance"
  value = {
    instance_id = google_bigtable_instance.supply_chain.name
    project_id  = var.project_id
    table_name  = google_bigtable_table.sensor_data.name
  }
}

output "bigtable_console_url" {
  description = "URL to view the Bigtable instance in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigtable/instances/${google_bigtable_instance.supply_chain.name}/overview?project=${var.project_id}"
}

# Dataproc cluster outputs
output "dataproc_cluster_name" {
  description = "Name of the Dataproc cluster for analytics processing"
  value       = google_dataproc_cluster.analytics_cluster.name
}

output "dataproc_cluster_region" {
  description = "Region of the Dataproc cluster"
  value       = google_dataproc_cluster.analytics_cluster.region
}

output "dataproc_master_instance_names" {
  description = "Names of the Dataproc master instances"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].master_config[0].instance_names
}

output "dataproc_worker_instance_names" {
  description = "Names of the Dataproc worker instances"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].worker_config[0].instance_names
}

output "dataproc_console_url" {
  description = "URL to view the Dataproc cluster in Google Cloud Console"
  value       = "https://console.cloud.google.com/dataproc/clusters/${google_dataproc_cluster.analytics_cluster.name}?project=${var.project_id}&region=${var.region}"
}

# Cloud Storage outputs
output "analytics_bucket_name" {
  description = "Name of the Cloud Storage bucket for analytics data"
  value       = google_storage_bucket.analytics_bucket.name
}

output "analytics_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.analytics_bucket.url
}

output "analytics_bucket_console_url" {
  description = "URL to view the bucket in Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.analytics_bucket.name}?project=${var.project_id}"
}

# Pub/Sub topic outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for sensor data ingestion"
  value       = google_pubsub_topic.sensor_data.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.sensor_data.id
}

# Cloud Function outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function for sensor data processing"
  value       = google_cloudfunctions_function.sensor_processor.name
}

output "cloud_function_trigger" {
  description = "Trigger configuration for the Cloud Function"
  value = {
    event_type = google_cloudfunctions_function.sensor_processor.event_trigger[0].event_type
    resource   = google_cloudfunctions_function.sensor_processor.event_trigger[0].resource
  }
}

output "cloud_function_console_url" {
  description = "URL to view the Cloud Function in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.sensor_processor.name}?project=${var.project_id}"
}

# Cloud Scheduler outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for automated analytics"
  value       = google_cloud_scheduler_job.analytics_job.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the automated analytics job"
  value       = google_cloud_scheduler_job.analytics_job.schedule
}

output "scheduler_console_url" {
  description = "URL to view the Cloud Scheduler job in Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudscheduler/jobs/${google_cloud_scheduler_job.analytics_job.name}?project=${var.project_id}"
}

# Service Account outputs
output "service_account_email" {
  description = "Email address of the analytics service account"
  value       = var.create_service_account ? google_service_account.analytics_sa[0].email : null
}

output "service_account_name" {
  description = "Name of the analytics service account"
  value       = var.create_service_account ? google_service_account.analytics_sa[0].name : null
}

# Monitoring outputs
output "monitoring_dashboard_url" {
  description = "URL to view the supply chain analytics dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.supply_chain_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the low inventory alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.low_inventory_alert[0].name : null
}

# Connection strings and commands for testing
output "bigtable_cbt_commands" {
  description = "Sample cbt commands for interacting with the Bigtable instance"
  value = {
    list_tables = "cbt -project=${var.project_id} -instance=${google_bigtable_instance.supply_chain.name} ls"
    read_data   = "cbt -project=${var.project_id} -instance=${google_bigtable_instance.supply_chain.name} read ${google_bigtable_table.sensor_data.name} count=10"
  }
}

output "dataproc_job_submit_command" {
  description = "Command to manually submit analytics job to Dataproc"
  value = "gcloud dataproc jobs submit pyspark --cluster=${google_dataproc_cluster.analytics_cluster.name} --region=${var.region} gs://${google_storage_bucket.analytics_bucket.name}/jobs/supply_chain_analytics.py -- ${var.project_id} ${google_bigtable_instance.supply_chain.name}"
}

output "pubsub_publish_command" {
  description = "Command to publish test messages to Pub/Sub topic"
  value = "gcloud pubsub topics publish ${google_pubsub_topic.sensor_data.name} --message='{\"device_id\":\"test-sensor\",\"temperature\":25.5,\"humidity\":60.0,\"inventory_level\":75}'"
}

# Resource summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    bigtable_instance    = google_bigtable_instance.supply_chain.name
    dataproc_cluster     = google_dataproc_cluster.analytics_cluster.name
    storage_bucket       = google_storage_bucket.analytics_bucket.name
    pubsub_topic        = google_pubsub_topic.sensor_data.name
    cloud_function      = google_cloudfunctions_function.sensor_processor.name
    scheduler_job       = google_cloud_scheduler_job.analytics_job.name
    service_account     = var.create_service_account ? google_service_account.analytics_sa[0].email : "default"
  }
}

# Cost estimation guidance
output "cost_estimation_notes" {
  description = "Notes for cost estimation and optimization"
  value = {
    bigtable_nodes              = var.bigtable_cluster_num_nodes
    dataproc_worker_count      = var.dataproc_num_workers
    preemptible_worker_count   = var.dataproc_num_preemptible_workers
    storage_class              = var.storage_bucket_class
    estimated_monthly_cost_usd = "50-200 USD depending on usage patterns"
  }
}

# Next steps and usage instructions
output "getting_started_instructions" {
  description = "Instructions for getting started with the deployed infrastructure"
  value = {
    step_1 = "Verify deployment: ${join(" && ", [
      "gcloud bigtable instances describe ${google_bigtable_instance.supply_chain.name}",
      "gcloud dataproc clusters describe ${google_dataproc_cluster.analytics_cluster.name} --region=${var.region}"
    ])}"
    step_2 = "Test data ingestion: ${google_pubsub_topic.sensor_data.name}"
    step_3 = "Monitor dashboard: https://console.cloud.google.com/monitoring"
    step_4 = "View analytics results: gs://${google_storage_bucket.analytics_bucket.name}/analytics/"
  }
}
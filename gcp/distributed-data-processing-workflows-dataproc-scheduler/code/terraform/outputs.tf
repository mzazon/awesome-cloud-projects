# Outputs for distributed data processing workflows infrastructure

# Project information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

# Cloud Storage outputs
output "data_bucket_name" {
  description = "Name of the Cloud Storage bucket for input data"
  value       = google_storage_bucket.data_bucket.name
}

output "data_bucket_url" {
  description = "URL of the Cloud Storage bucket for input data"
  value       = google_storage_bucket.data_bucket.url
}

output "staging_bucket_name" {
  description = "Name of the Cloud Storage bucket for Dataproc staging"
  value       = google_storage_bucket.staging_bucket.name
}

output "staging_bucket_url" {
  description = "URL of the Cloud Storage bucket for Dataproc staging"
  value       = google_storage_bucket.staging_bucket.url
}

output "sample_data_path" {
  description = "Path to the uploaded sample data file"
  value       = "gs://${google_storage_bucket.data_bucket.name}/${google_storage_bucket_object.sample_data.name}"
}

output "spark_script_path" {
  description = "Path to the uploaded Spark processing script"
  value       = "gs://${google_storage_bucket.staging_bucket.name}/${google_storage_bucket_object.spark_script.name}"
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics results"
  value       = google_bigquery_dataset.analytics_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.location
}

output "bigquery_table_id" {
  description = "ID of the BigQuery table for sales summary"
  value       = google_bigquery_table.sales_summary.table_id
}

output "bigquery_table_reference" {
  description = "Full reference to the BigQuery table"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.sales_summary.table_id}"
}

# Service account outputs
output "service_account_email" {
  description = "Email address of the service account for Dataproc workflows"
  value       = google_service_account.dataproc_scheduler.email
}

output "service_account_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.dataproc_scheduler.unique_id
}

# Dataproc workflow template outputs
output "workflow_template_name" {
  description = "Name of the Dataproc workflow template"
  value       = google_dataproc_workflow_template.sales_analytics.name
}

output "workflow_template_id" {
  description = "Full resource ID of the workflow template"
  value       = google_dataproc_workflow_template.sales_analytics.id
}

output "cluster_name" {
  description = "Name of the managed cluster in the workflow template"
  value       = var.cluster_name
}

# Cloud Scheduler outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.sales_analytics_daily.name
}

output "scheduler_job_id" {
  description = "Full resource ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.sales_analytics_daily.id
}

output "schedule_expression" {
  description = "Cron expression for the scheduled job"
  value       = google_cloud_scheduler_job.sales_analytics_daily.schedule
}

output "scheduler_timezone" {
  description = "Timezone for the scheduled job"
  value       = google_cloud_scheduler_job.sales_analytics_daily.time_zone
}

# Useful commands and URLs
output "manual_workflow_execution_command" {
  description = "Command to manually execute the workflow template"
  value       = "gcloud dataproc workflow-templates instantiate ${google_dataproc_workflow_template.sales_analytics.name} --region=${var.region}"
}

output "bigquery_query_command" {
  description = "Command to query the results in BigQuery"
  value = <<-EOT
    bq query --use_legacy_sql=false "SELECT region, category, ROUND(total_sales, 2) as total_sales, transaction_count, ROUND(avg_order_value, 2) as avg_order_value, processing_timestamp FROM \`${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.sales_summary.table_id}\` ORDER BY total_sales DESC"
  EOT
}

output "scheduler_manual_trigger_command" {
  description = "Command to manually trigger the scheduled job"
  value       = "gcloud scheduler jobs run ${google_cloud_scheduler_job.sales_analytics_daily.name} --location=${var.region}"
}

output "google_cloud_console_urls" {
  description = "Useful Google Cloud Console URLs for monitoring"
  value = {
    dataproc_workflows = "https://console.cloud.google.com/dataproc/workflows?project=${var.project_id}"
    bigquery_dataset   = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.analytics_dataset.dataset_id}!3s${google_bigquery_table.sales_summary.table_id}"
    cloud_scheduler    = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    cloud_storage_data = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.data_bucket.name}?project=${var.project_id}"
    cloud_storage_staging = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.staging_bucket.name}?project=${var.project_id}"
  }
}

# Resource summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    storage_buckets = {
      data_bucket    = google_storage_bucket.data_bucket.name
      staging_bucket = google_storage_bucket.staging_bucket.name
    }
    bigquery = {
      dataset = google_bigquery_dataset.analytics_dataset.dataset_id
      table   = google_bigquery_table.sales_summary.table_id
    }
    dataproc = {
      workflow_template = google_dataproc_workflow_template.sales_analytics.name
      cluster_name      = var.cluster_name
    }
    scheduler = {
      job_name  = google_cloud_scheduler_job.sales_analytics_daily.name
      schedule  = google_cloud_scheduler_job.sales_analytics_daily.schedule
      timezone  = google_cloud_scheduler_job.sales_analytics_daily.time_zone
    }
    iam = {
      service_account = google_service_account.dataproc_scheduler.email
    }
  }
}

# Cost estimation information
output "cost_estimation_notes" {
  description = "Notes about cost estimation for the deployed resources"
  value = <<-EOT
    Cost estimation (approximate, varies by usage):
    - Cloud Storage: $0.020 per GB/month (Standard class)
    - BigQuery: $5 per TB processed, $0.020 per GB stored/month
    - Dataproc: Compute Engine pricing + $0.010 per vCPU/hour premium
    - Cloud Scheduler: First 3 jobs free, then $0.10 per job/month
    
    For detailed pricing, visit:
    - Cloud Storage: https://cloud.google.com/storage/pricing
    - BigQuery: https://cloud.google.com/bigquery/pricing
    - Dataproc: https://cloud.google.com/dataproc/pricing
    - Cloud Scheduler: https://cloud.google.com/scheduler/pricing
  EOT
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up resources and avoid ongoing costs"
  value = {
    delete_scheduler_job = "gcloud scheduler jobs delete ${google_cloud_scheduler_job.sales_analytics_daily.name} --location=${var.region} --quiet"
    delete_workflow_template = "gcloud dataproc workflow-templates delete ${google_dataproc_workflow_template.sales_analytics.name} --region=${var.region} --quiet"
    delete_bigquery_dataset = "bq rm -r -f ${google_bigquery_dataset.analytics_dataset.dataset_id}"
    delete_storage_buckets = "gsutil -m rm -r gs://${google_storage_bucket.data_bucket.name} gs://${google_storage_bucket.staging_bucket.name}"
    delete_service_account = "gcloud iam service-accounts delete ${google_service_account.dataproc_scheduler.email} --quiet"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}
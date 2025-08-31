# ==============================================================================
# TERRAFORM OUTPUTS FOR BIGQUERY SERVERLESS SPARK DATA PROCESSING
# ==============================================================================
# This file defines outputs that provide important information about the
# created infrastructure. These outputs can be used by other Terraform
# configurations, CI/CD pipelines, or for manual reference.
# ==============================================================================

# ==============================================================================
# PROJECT AND LOCATION OUTPUTS
# ==============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "random_suffix" {
  description = "The random suffix used for resource names to ensure uniqueness"
  value       = random_id.suffix.hex
}

# ==============================================================================
# CLOUD STORAGE OUTPUTS
# ==============================================================================

output "data_lake_bucket_name" {
  description = "Name of the Cloud Storage bucket used for the data lake"
  value       = google_storage_bucket.data_lake.name
}

output "data_lake_bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.url
}

output "data_lake_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.self_link
}

output "raw_data_path" {
  description = "Path to the raw data folder in the Cloud Storage bucket"
  value       = "gs://${google_storage_bucket.data_lake.name}/raw-data/"
}

output "processed_data_path" {
  description = "Path to the processed data folder in the Cloud Storage bucket"
  value       = "gs://${google_storage_bucket.data_lake.name}/processed-data/"
}

output "scripts_path" {
  description = "Path to the scripts folder in the Cloud Storage bucket"
  value       = "gs://${google_storage_bucket.data_lake.name}/scripts/"
}

output "sample_data_path" {
  description = "Path to the sample transaction data file"
  value       = "gs://${google_storage_bucket.data_lake.name}/raw-data/sample_transactions.csv"
}

# ==============================================================================
# BIGQUERY OUTPUTS
# ==============================================================================

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.analytics_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.location
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.self_link
}

output "customer_analytics_table" {
  description = "Full table reference for customer analytics table"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.customer_analytics.table_id}"
}

output "product_analytics_table" {
  description = "Full table reference for product analytics table"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.product_analytics.table_id}"
}

output "location_analytics_table" {
  description = "Full table reference for location analytics table"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.location_analytics.table_id}"
}

output "bigquery_console_url" {
  description = "URL to view the BigQuery dataset in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.analytics_dataset.dataset_id}"
}

# ==============================================================================
# IAM AND SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "spark_service_account_email" {
  description = "Email address of the Serverless Spark service account"
  value       = google_service_account.spark_service_account.email
}

output "spark_service_account_name" {
  description = "Full name of the Serverless Spark service account"
  value       = google_service_account.spark_service_account.name
}

output "spark_service_account_unique_id" {
  description = "Unique ID of the Serverless Spark service account"
  value       = google_service_account.spark_service_account.unique_id
  sensitive   = true
}

# ==============================================================================
# DATAPROC SERVERLESS OUTPUTS
# ==============================================================================

output "sample_batch_job_id" {
  description = "ID of the sample Dataproc Serverless batch job (if created)"
  value       = var.create_sample_batch ? google_dataproc_batch.spark_session_template[0].batch_id : null
}

output "sample_batch_job_name" {
  description = "Full name of the sample Dataproc Serverless batch job (if created)"
  value       = var.create_sample_batch ? google_dataproc_batch.spark_session_template[0].name : null
}

output "dataproc_console_url" {
  description = "URL to view Dataproc Serverless batches in the Google Cloud Console"
  value       = "https://console.cloud.google.com/dataproc/batches?project=${var.project_id}"
}

output "bigquery_studio_url" {
  description = "URL to access BigQuery Studio for interactive Spark development"
  value       = "https://console.cloud.google.com/bigquery/studio?project=${var.project_id}"
}

# ==============================================================================
# MONITORING AND ALERTING OUTPUTS
# ==============================================================================

output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if created)"
  value       = var.create_monitoring_dashboard ? google_monitoring_dashboard.spark_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to view the Cloud Monitoring dashboard"
  value       = var.create_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.spark_dashboard[0].id}?project=${var.project_id}" : null
}

output "log_success_metric_name" {
  description = "Name of the log-based metric for successful Spark jobs"
  value       = var.create_log_metrics ? google_logging_metric.spark_job_success[0].name : null
}

output "log_failure_metric_name" {
  description = "Name of the log-based metric for failed Spark jobs"
  value       = var.create_log_metrics ? google_logging_metric.spark_job_failure[0].name : null
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if created)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : null
  sensitive   = true
}

output "logging_console_url" {
  description = "URL to view logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/logs/query?project=${var.project_id}&query=resource.type%3D%22dataproc_batch%22"
}

# ==============================================================================
# SPARK CONFIGURATION OUTPUTS
# ==============================================================================

output "spark_config_path" {
  description = "Path to the Spark session configuration file in Cloud Storage"
  value       = "gs://${google_storage_bucket.data_lake.name}/scripts/spark_session_config.json"
}

output "spark_processing_script_path" {
  description = "Path to the Spark data processing script in Cloud Storage"
  value       = "gs://${google_storage_bucket.data_lake.name}/scripts/data_processing_spark.py"
}

output "bigquery_connector_jar" {
  description = "BigQuery Spark connector JAR file URI"
  value       = "gs://spark-lib/bigquery/spark-bigquery-with-dependencies_2.12-${var.bigquery_connector_version}.jar"
}

# ==============================================================================
# COMMAND EXAMPLES
# ==============================================================================

output "sample_spark_submit_command" {
  description = "Example gcloud command to submit a Serverless Spark job"
  value = <<-EOT
    gcloud dataproc batches submit pyspark \
        gs://${google_storage_bucket.data_lake.name}/scripts/data_processing_spark.py \
        --batch=${var.batch_job_prefix}-$(date +%s) \
        --region=${var.region} \
        --project=${var.project_id} \
        --jars=gs://spark-lib/bigquery/spark-bigquery-with-dependencies_2.12-${var.bigquery_connector_version}.jar \
        --properties="spark.executor.instances=${var.spark_executor_instances},spark.executor.memory=${var.spark_executor_memory},spark.executor.cores=${var.spark_executor_cores}" \
        --ttl=${var.batch_job_ttl} \
        --service-account=${google_service_account.spark_service_account.email}
  EOT
}

output "sample_bigquery_query" {
  description = "Example BigQuery query to analyze processed data"
  value = <<-EOT
    SELECT 
        customer_segment,
        COUNT(*) as customer_count,
        AVG(total_spent) as avg_spending,
        SUM(transaction_count) as total_transactions
    FROM `${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.customer_analytics`
    GROUP BY customer_segment
    ORDER BY avg_spending DESC
  EOT
}

output "upload_data_command" {
  description = "Example gsutil command to upload data to the bucket"
  value = "gsutil cp your_data_file.csv gs://${google_storage_bucket.data_lake.name}/raw-data/"
}

# ==============================================================================
# COST INFORMATION
# ==============================================================================

output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs for the infrastructure"
  value = {
    cloud_storage_standard = "~$0.020 per GB per month for Standard storage class"
    cloud_storage_nearline = "~$0.010 per GB per month for Nearline storage class (after lifecycle transition)"
    bigquery_storage       = "~$0.020 per GB per month for BigQuery table storage"
    bigquery_queries       = "~$5.00 per TB of data processed in queries"
    dataproc_serverless    = "Pricing based on vCPU-hour and memory usage, typically $0.10-0.50 per job"
    monitoring_logs        = "First 50 GiB per month free, then $0.50 per GiB"
  }
}

# ==============================================================================
# RESOURCE SUMMARY
# ==============================================================================

output "infrastructure_summary" {
  description = "Summary of all created infrastructure resources"
  value = {
    project_id                = var.project_id
    region                   = var.region
    bucket_name              = google_storage_bucket.data_lake.name
    dataset_id               = google_bigquery_dataset.analytics_dataset.dataset_id
    service_account_email    = google_service_account.spark_service_account.email
    analytics_tables_count   = 3
    enabled_apis_count       = 8
    created_iam_bindings     = 5
    monitoring_enabled       = var.create_monitoring_dashboard
    alerting_enabled         = var.create_alerts && var.notification_email != ""
  }
}
# ============================================================================
# Output Values for Data Pipeline Recovery Infrastructure
# ============================================================================
#
# This file defines output values that provide important information about
# the deployed infrastructure. These outputs are used for verification,
# integration with other systems, and operational monitoring.
#
# ============================================================================

# ============================================================================
# PROJECT AND RESOURCE IDENTIFICATION
# ============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# DATAFORM INFRASTRUCTURE OUTPUTS
# ============================================================================

output "dataform_repository_name" {
  description = "Name of the created Dataform repository"
  value       = google_dataform_repository.pipeline_repo.name
}

output "dataform_repository_id" {
  description = "Full resource ID of the Dataform repository"
  value       = google_dataform_repository.pipeline_repo.id
}

output "dataform_repository_region" {
  description = "Region where the Dataform repository is located"
  value       = google_dataform_repository.pipeline_repo.region
}

# ============================================================================
# BIGQUERY INFRASTRUCTURE OUTPUTS
# ============================================================================

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for pipeline data"
  value       = google_bigquery_dataset.pipeline_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.pipeline_dataset.location
}

output "source_table_id" {
  description = "Full table ID for the source data table"
  value       = "${var.project_id}.${google_bigquery_dataset.pipeline_dataset.dataset_id}.${google_bigquery_table.source_data.table_id}"
}

output "processed_table_id" {
  description = "Full table ID for the processed data table"
  value       = "${var.project_id}.${google_bigquery_dataset.pipeline_dataset.dataset_id}.${google_bigquery_table.processed_data.table_id}"
}

output "bigquery_dataset_url" {
  description = "Google Cloud Console URL for the BigQuery dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m1!1b1!2m1!1s${google_bigquery_dataset.pipeline_dataset.dataset_id}"
}

# ============================================================================
# CLOUD TASKS INFRASTRUCTURE OUTPUTS
# ============================================================================

output "cloud_tasks_queue_name" {
  description = "Name of the Cloud Tasks queue for recovery operations"
  value       = google_cloud_tasks_queue.recovery_queue.name
}

output "cloud_tasks_queue_id" {
  description = "Full resource ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.recovery_queue.id
}

output "cloud_tasks_queue_location" {
  description = "Location of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.recovery_queue.location
}

output "cloud_tasks_queue_url" {
  description = "Google Cloud Console URL for the Cloud Tasks queue"
  value       = "https://console.cloud.google.com/cloudtasks/queue/${google_cloud_tasks_queue.recovery_queue.location}/${google_cloud_tasks_queue.recovery_queue.name}?project=${var.project_id}"
}

# ============================================================================
# CLOUD FUNCTIONS OUTPUTS
# ============================================================================

output "pipeline_controller_function_name" {
  description = "Name of the pipeline controller Cloud Function"
  value       = google_cloudfunctions2_function.pipeline_controller_updated.name
}

output "pipeline_controller_function_url" {
  description = "HTTP trigger URL for the pipeline controller function"
  value       = google_cloudfunctions2_function.pipeline_controller_updated.service_config[0].uri
  sensitive   = false
}

output "recovery_worker_function_name" {
  description = "Name of the recovery worker Cloud Function"
  value       = google_cloudfunctions2_function.recovery_worker.name
}

output "recovery_worker_function_url" {
  description = "HTTP trigger URL for the recovery worker function"
  value       = google_cloudfunctions2_function.recovery_worker.service_config[0].uri
  sensitive   = false
}

output "notification_handler_function_name" {
  description = "Name of the notification handler Cloud Function"
  value       = google_cloudfunctions2_function.notification_handler.name
}

output "cloud_functions_console_url" {
  description = "Google Cloud Console URL for Cloud Functions"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

# ============================================================================
# PUB/SUB INFRASTRUCTURE OUTPUTS
# ============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for notifications"
  value       = google_pubsub_topic.pipeline_notifications.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.pipeline_notifications.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for notifications"
  value       = google_pubsub_subscription.notification_subscription.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter Pub/Sub topic"
  value       = google_pubsub_topic.dead_letter_topic.name
}

output "pubsub_console_url" {
  description = "Google Cloud Console URL for Pub/Sub topics"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

# ============================================================================
# MONITORING AND ALERTING OUTPUTS
# ============================================================================

output "monitoring_alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy"
  value       = google_monitoring_alert_policy.pipeline_failure_alert.display_name
}

output "monitoring_alert_policy_id" {
  description = "ID of the Cloud Monitoring alert policy"
  value       = google_monitoring_alert_policy.pipeline_failure_alert.name
}

output "webhook_notification_channel_id" {
  description = "ID of the webhook notification channel"
  value       = google_monitoring_notification_channel.webhook_channel.name
}

output "log_metric_name" {
  description = "Name of the log-based metric for pipeline failures"
  value       = google_logging_metric.pipeline_failure_metric.name
}

output "monitoring_console_url" {
  description = "Google Cloud Console URL for Cloud Monitoring"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

# ============================================================================
# IAM AND SECURITY OUTPUTS
# ============================================================================

output "pipeline_controller_service_account_email" {
  description = "Email address of the pipeline controller service account"
  value       = google_service_account.pipeline_controller_sa.email
}

output "pipeline_controller_service_account_id" {
  description = "ID of the pipeline controller service account"
  value       = google_service_account.pipeline_controller_sa.id
}

output "dataform_service_account_email" {
  description = "Email address of the Dataform service account"
  value       = local.dataform_sa_email
}

# ============================================================================
# STORAGE AND SOURCE CODE OUTPUTS
# ============================================================================

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

output "function_source_bucket_url" {
  description = "Google Cloud Console URL for the function source bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.function_source_bucket.name}?project=${var.project_id}"
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_pipeline_failure_command" {
  description = "curl command to test pipeline failure simulation"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.pipeline_controller_updated.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d '{
        "incident": {
          "resource": {
            "labels": {
              "pipeline_id": "test-pipeline-001"
            }
          },
          "condition_name": "sql_error",
          "state": "OPEN"
        }
      }'
  EOT
  sensitive = false
}

output "gcloud_tasks_list_command" {
  description = "gcloud command to list tasks in the recovery queue"
  value       = "gcloud tasks list --queue=${google_cloud_tasks_queue.recovery_queue.name} --location=${google_cloud_tasks_queue.recovery_queue.location}"
}

output "bigquery_insert_test_data_command" {
  description = "bq command to insert test data into the source table"
  value = <<-EOT
    bq query --use_legacy_sql=false \
      "INSERT INTO \`${var.project_id}.${google_bigquery_dataset.pipeline_dataset.dataset_id}.${google_bigquery_table.source_data.table_id}\`
       VALUES 
       (1, 'test_record_1', CURRENT_TIMESTAMP(), 'pending'),
       (2, 'test_record_2', CURRENT_TIMESTAMP(), 'pending'),
       (3, 'test_record_3', CURRENT_TIMESTAMP(), 'pending')"
  EOT
}

# ============================================================================
# OPERATIONAL INSIGHTS
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    dataform_repository = {
      name        = google_dataform_repository.pipeline_repo.name
      purpose     = "ELT workflow definitions and execution"
      console_url = "https://console.cloud.google.com/dataform/repositories?project=${var.project_id}"
    }
    bigquery_dataset = {
      name        = google_bigquery_dataset.pipeline_dataset.dataset_id
      purpose     = "Data storage and pipeline monitoring"
      console_url = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    }
    cloud_tasks_queue = {
      name        = google_cloud_tasks_queue.recovery_queue.name
      purpose     = "Reliable recovery task execution with retry logic"
      console_url = "https://console.cloud.google.com/cloudtasks?project=${var.project_id}"
    }
    cloud_functions = {
      controller  = google_cloudfunctions2_function.pipeline_controller_updated.name
      worker      = google_cloudfunctions2_function.recovery_worker.name
      notifier    = google_cloudfunctions2_function.notification_handler.name
      purpose     = "Pipeline orchestration, recovery execution, and notifications"
      console_url = "https://console.cloud.google.com/functions?project=${var.project_id}"
    }
    monitoring = {
      alert_policy = google_monitoring_alert_policy.pipeline_failure_alert.display_name
      purpose      = "Automated failure detection and recovery triggering"
      console_url  = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    }
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the pipeline failure simulation using the provided curl command",
    "2. Monitor Cloud Tasks queue for recovery task execution",
    "3. Check Cloud Functions logs for detailed execution information",
    "4. Verify BigQuery tables have sample data for testing",
    "5. Set up additional notification channels (Slack, PagerDuty) as needed",
    "6. Configure Dataform workflows using the repository workspace",
    "7. Customize retry strategies based on your specific pipeline requirements"
  ]
}

# ============================================================================
# COST ESTIMATION OUTPUTS
# ============================================================================

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the deployed infrastructure (approximate)"
  value = {
    cloud_functions = "5-20 USD (based on execution frequency)"
    cloud_tasks     = "1-5 USD (based on task volume)"
    bigquery        = "5-25 USD (based on data volume and queries)"
    cloud_monitoring = "1-10 USD (based on metrics and alerts)"
    cloud_storage   = "1-3 USD (function source code storage)"
    pubsub          = "1-5 USD (based on message volume)"
    total_estimate  = "14-68 USD per month"
    note            = "Actual costs depend on usage patterns, data volume, and execution frequency"
  }
}
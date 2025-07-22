# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Outputs for Data Quality Monitoring with Dataform and Cloud Scheduler
# This file defines outputs that provide important information about the deployed infrastructure

# Project and Location Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# BigQuery Information
output "sample_dataset_id" {
  description = "ID of the BigQuery dataset containing sample data"
  value       = google_bigquery_dataset.sample_dataset.dataset_id
}

output "sample_dataset_location" {
  description = "Location of the sample BigQuery dataset"
  value       = google_bigquery_dataset.sample_dataset.location
}

output "assertion_dataset_id" {
  description = "ID of the BigQuery dataset containing data quality assertions"
  value       = google_bigquery_dataset.assertion_dataset.dataset_id
}

output "assertion_dataset_location" {
  description = "Location of the assertion BigQuery dataset"
  value       = google_bigquery_dataset.assertion_dataset.location
}

output "sample_dataset_url" {
  description = "URL to view the sample dataset in BigQuery console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.sample_dataset.dataset_id}!3e1"
}

output "assertion_dataset_url" {
  description = "URL to view the assertion dataset in BigQuery console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.assertion_dataset.dataset_id}!3e1"
}

# Dataform Information
output "dataform_repository_name" {
  description = "Name of the Dataform repository"
  value       = google_dataform_repository.quality_repository.name
}

output "dataform_repository_url" {
  description = "URL to view the Dataform repository in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery/dataform/locations/${var.region}/repositories/${google_dataform_repository.quality_repository.name}?project=${var.project_id}"
}

output "dataform_release_config_name" {
  description = "Name of the Dataform release configuration"
  value       = google_dataform_repository_release_config.quality_release.name
}

# Cloud Scheduler Information
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.dataform_trigger.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.dataform_trigger.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.dataform_trigger.time_zone
}

output "scheduler_job_url" {
  description = "URL to view the Cloud Scheduler job in Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudscheduler/jobs/edit/${var.region}/${google_cloud_scheduler_job.dataform_trigger.name}?project=${var.project_id}"
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account used for Dataform and Cloud Scheduler"
  value       = google_service_account.dataform_scheduler.email
}

output "service_account_id" {
  description = "ID of the service account used for Dataform and Cloud Scheduler"
  value       = google_service_account.dataform_scheduler.account_id
}

# Monitoring Information (conditional outputs based on monitoring configuration)
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring integration is enabled"
  value       = var.enable_monitoring
}

output "log_metric_name" {
  description = "Name of the log-based metric for data quality failures (if monitoring enabled)"
  value       = var.enable_monitoring ? google_logging_metric.data_quality_failures[0].name : null
}

output "alert_policy_name" {
  description = "Name of the alert policy for data quality monitoring (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.data_quality_alert[0].display_name : null
}

output "notification_email" {
  description = "Email address configured for data quality alerts (if provided)"
  value       = var.notification_email != "" ? var.notification_email : null
  sensitive   = true
}

output "monitoring_dashboard_url" {
  description = "URL to view Cloud Monitoring dashboard (if monitoring enabled)"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}" : null
}

# Sample Data Information
output "sample_data_created" {
  description = "Whether sample data was created for testing"
  value       = var.create_sample_data
}

output "customers_table_name" {
  description = "Name of the customers table (if sample data created)"
  value       = var.create_sample_data ? "${local.dataset_id}.customers" : null
}

output "orders_table_name" {
  description = "Name of the orders table (if sample data created)"
  value       = var.create_sample_data ? "${local.dataset_id}.orders" : null
}

# Validation and Testing Queries
output "validation_queries" {
  description = "SQL queries to validate the data quality monitoring setup"
  value = {
    check_sample_data = var.create_sample_data ? "SELECT 'customers' as table_name, COUNT(*) as record_count FROM `${var.project_id}.${local.dataset_id}.customers` UNION ALL SELECT 'orders' as table_name, COUNT(*) as record_count FROM `${var.project_id}.${local.dataset_id}.orders`" : null
    
    check_datasets = "SELECT schema_name, catalog_name FROM `${var.project_id}.INFORMATION_SCHEMA.SCHEMATA` WHERE schema_name IN ('${local.dataset_id}', '${local.assertion_dataset_id}')"
    
    list_dataform_workflows = "This requires gcloud CLI: gcloud dataform workflow-invocations list --location=${var.region} --repository=${google_dataform_repository.quality_repository.name} --project=${var.project_id}"
  }
}

# Next Steps and Documentation
output "next_steps" {
  description = "Next steps to complete the data quality monitoring setup"
  value = {
    step_1 = "Create Dataform SQL files in the repository: ${google_dataform_repository.quality_repository.name}"
    step_2 = "Define data quality assertions using Dataform syntax"
    step_3 = "Trigger the scheduler job manually to test: gcloud scheduler jobs run ${google_cloud_scheduler_job.dataform_trigger.name} --location=${var.region}"
    step_4 = "Monitor execution in Dataform console: ${local.dataform_console_url}"
    step_5 = var.enable_monitoring ? "Check Cloud Monitoring for alerts and metrics" : "Configure monitoring by setting enable_monitoring = true"
  }
}

# Console URLs for Easy Access
locals {
  dataform_console_url = "https://console.cloud.google.com/bigquery/dataform/locations/${var.region}/repositories/${google_dataform_repository.quality_repository.name}?project=${var.project_id}"
}

output "console_urls" {
  description = "Direct URLs to Google Cloud Console for managing resources"
  value = {
    bigquery_console     = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    dataform_console     = local.dataform_console_url
    scheduler_console    = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    monitoring_console   = var.enable_monitoring ? "https://console.cloud.google.com/monitoring?project=${var.project_id}" : null
    logging_console      = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    iam_console         = "https://console.cloud.google.com/iam-admin/serviceaccounts?project=${var.project_id}"
  }
}

# Resource Names for Reference
output "resource_names" {
  description = "Names of all created resources for reference and management"
  value = {
    sample_dataset      = google_bigquery_dataset.sample_dataset.dataset_id
    assertion_dataset   = google_bigquery_dataset.assertion_dataset.dataset_id
    dataform_repository = google_dataform_repository.quality_repository.name
    release_config      = google_dataform_repository_release_config.quality_release.name
    scheduler_job       = google_cloud_scheduler_job.dataform_trigger.name
    service_account     = google_service_account.dataform_scheduler.email
    log_metric         = var.enable_monitoring ? google_logging_metric.data_quality_failures[0].name : null
    alert_policy       = var.enable_monitoring ? google_monitoring_alert_policy.data_quality_alert[0].display_name : null
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    scheduler_frequency    = var.scheduler_frequency
    scheduler_timezone     = var.scheduler_timezone
    dataset_location      = var.dataset_location
    monitoring_enabled    = var.enable_monitoring
    sample_data_created   = var.create_sample_data
    deletion_protection   = var.deletion_protection
    environment          = var.environment
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Information about potential costs for the deployed resources"
  value = {
    bigquery_storage = "BigQuery storage costs depend on data volume. Sample datasets are minimal cost."
    bigquery_queries = "BigQuery query costs depend on data processed. Assertions typically scan small datasets."
    cloud_scheduler  = "Cloud Scheduler: $0.10 per job per month (first 3 jobs free per month)"
    dataform        = "Dataform: No additional charges beyond BigQuery usage"
    cloud_monitoring = var.enable_monitoring ? "Cloud Monitoring: First 150 metrics free, then $0.258 per metric per month" : "Not enabled"
    note = "Actual costs depend on usage patterns and data volumes. Monitor billing console for accurate charges."
  }
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting steps and helpful commands"
  value = {
    check_apis = "Verify APIs are enabled: gcloud services list --enabled --project=${var.project_id}"
    check_permissions = "Verify service account permissions: gcloud projects get-iam-policy ${var.project_id}"
    check_scheduler = "Check scheduler job status: gcloud scheduler jobs describe ${google_cloud_scheduler_job.dataform_trigger.name} --location=${var.region}"
    check_dataform = "List Dataform workflows: gcloud dataform workflow-invocations list --location=${var.region} --repository=${google_dataform_repository.quality_repository.name} --project=${var.project_id}"
    view_logs = "View logs: gcloud logging read 'resource.type=\"cloud_scheduler_job\" OR resource.type=\"dataform_repository\"' --limit=50 --project=${var.project_id}"
  }
}
# outputs.tf
# Output values for the GCP Dynamic Delivery Route Optimization infrastructure

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for delivery analytics"
  value       = google_bigquery_dataset.delivery_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.delivery_analytics.location
}

output "delivery_history_table_id" {
  description = "Full table ID for delivery history table"
  value       = "${var.project_id}.${google_bigquery_dataset.delivery_analytics.dataset_id}.${google_bigquery_table.delivery_history.table_id}"
}

output "optimized_routes_table_id" {
  description = "Full table ID for optimized routes table"
  value       = "${var.project_id}.${google_bigquery_dataset.delivery_analytics.dataset_id}.${google_bigquery_table.optimized_routes.table_id}"
}

output "delivery_performance_view_id" {
  description = "Full view ID for delivery performance analytics"
  value       = "${var.project_id}.${google_bigquery_dataset.delivery_analytics.dataset_id}.${google_bigquery_table.delivery_performance_view.table_id}"
}

output "route_efficiency_view_id" {
  description = "Full view ID for route efficiency analytics"
  value       = "${var.project_id}.${google_bigquery_dataset.delivery_analytics.dataset_id}.${google_bigquery_table.route_efficiency_view.table_id}"
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for route data"
  value       = google_storage_bucket.route_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.route_data.url
}

output "function_name" {
  description = "Name of the Cloud Function for route optimization"
  value       = google_cloudfunctions2_function.route_optimizer.name
}

output "function_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.route_optimizer.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_service_account.email
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for automated optimization"
  value       = google_cloud_scheduler_job.route_optimization_scheduler.name
}

output "scheduler_job_schedule" {
  description = "Schedule of the automated route optimization job"
  value       = google_cloud_scheduler_job.route_optimization_scheduler.schedule
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the project"
  value       = local.required_apis
}

# Sample queries for testing BigQuery tables
output "sample_queries" {
  description = "Sample BigQuery queries for testing the analytics tables"
  value = {
    delivery_count = "SELECT COUNT(*) as total_deliveries FROM `${var.project_id}.${local.dataset_name}.${local.deliveries_table_name}`"
    route_count    = "SELECT COUNT(*) as total_routes FROM `${var.project_id}.${local.dataset_name}.${local.routes_table_name}`"
    performance_metrics = "SELECT * FROM `${var.project_id}.${local.dataset_name}.delivery_performance_view` LIMIT 10"
    efficiency_metrics  = "SELECT * FROM `${var.project_id}.${local.dataset_name}.route_efficiency_view` LIMIT 10"
  }
}

# Configuration for testing the function
output "test_function_config" {
  description = "Configuration for testing the route optimization function"
  value = {
    function_url = google_cloudfunctions2_function.route_optimizer.service_config[0].uri
    sample_payload = jsonencode({
      deliveries = [
        {
          delivery_id        = "TEST001"
          lat               = 37.7749
          lng               = -122.4194
          estimated_minutes = 20
          estimated_km      = 2.5
        },
        {
          delivery_id        = "TEST002"
          lat               = 37.7849
          lng               = -122.4094
          estimated_minutes = 25
          estimated_km      = 3.0
        }
      ]
      vehicle_id       = "TEST_VEH"
      driver_id        = "TEST_DRV"
      vehicle_capacity = 5
    })
    curl_command = "curl -X POST ${google_cloudfunctions2_function.route_optimizer.service_config[0].uri} -H 'Content-Type: application/json' -d '${jsonencode({
      deliveries = [
        {
          delivery_id        = "TEST001"
          lat               = 37.7749
          lng               = -122.4194
          estimated_minutes = 20
          estimated_km      = 2.5
        }
      ]
      vehicle_id       = "TEST_VEH"
      driver_id        = "TEST_DRV"
      vehicle_capacity = 5
    })}'"
  }
}

# Resource URLs for easy access
output "resource_urls" {
  description = "Direct URLs to access created resources in Google Cloud Console"
  value = {
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${local.dataset_name}"
    cloud_function   = "https://console.cloud.google.com/functions/details/${var.region}/${local.function_name}?project=${var.project_id}"
    storage_bucket   = "https://console.cloud.google.com/storage/browser/${local.bucket_name}?project=${var.project_id}"
    cloud_scheduler  = "https://console.cloud.google.com/cloudscheduler/jobs?project=${var.project_id}"
    monitoring       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    bigquery_storage_gb_month    = "~$0.02 per GB/month"
    bigquery_queries_tb          = "~$5.00 per TB processed"
    cloud_function_invocations   = "~$0.40 per 1M invocations + $0.0000025 per GB-second"
    cloud_storage_standard       = "~$0.020 per GB/month"
    cloud_scheduler_jobs         = "~$0.10 per job/month"
    maps_route_optimization      = "~$0.005 per optimization request"
    estimated_monthly_total      = "$15-25 for testing workloads"
  }
}

# Security and access information
output "security_info" {
  description = "Security and access control information"
  value = {
    function_service_account = google_service_account.function_service_account.email
    required_iam_roles = [
      "roles/bigquery.dataEditor",
      "roles/bigquery.jobUser", 
      "roles/storage.objectAdmin",
      "roles/routeoptimization.user",
      "roles/logging.logWriter"
    ]
    function_access = "Public (allUsers can invoke)"
    storage_access  = "Uniform bucket-level access enabled"
  }
}

# Validation commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    check_bigquery_data = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as total_records FROM `${var.project_id}.${local.dataset_name}.${local.deliveries_table_name}`'"
    check_function_logs = "gcloud functions logs read ${local.function_name} --region=${var.region} --limit=10"
    test_storage_access = "gsutil ls gs://${local.bucket_name}/"
    check_scheduler_job = "gcloud scheduler jobs describe ${local.scheduler_job_name} --location=${var.region}"
  }
}
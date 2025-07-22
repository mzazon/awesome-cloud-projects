# Project Information
output "project_id" {
  description = "The project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = local.suffix
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for cost optimization analytics"
  value       = google_bigquery_dataset.cost_optimization.dataset_id
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.cost_optimization.location
}

output "cost_analysis_table_id" {
  description = "BigQuery table ID for cost analysis data"
  value       = google_bigquery_table.cost_analysis.table_id
}

output "recommendations_table_id" {
  description = "BigQuery table ID for recommendations data"
  value       = google_bigquery_table.recommendations.table_id
}

output "bigquery_console_url" {
  description = "URL to view BigQuery dataset in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.cost_optimization.dataset_id}"
}

# Cloud Storage Resources
output "storage_bucket_name" {
  description = "Cloud Storage bucket name for cost optimization data"
  value       = google_storage_bucket.cost_optimization.name
}

output "storage_bucket_url" {
  description = "Cloud Storage bucket URL"
  value       = google_storage_bucket.cost_optimization.url
}

output "storage_console_url" {
  description = "URL to view Cloud Storage bucket in Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.cost_optimization.name}?project=${var.project_id}"
}

# Pub/Sub Resources
output "main_topic_name" {
  description = "Main Pub/Sub topic name for cost optimization events"
  value       = google_pubsub_topic.cost_optimization.name
}

output "pubsub_topics" {
  description = "All Pub/Sub topic names created for cost optimization"
  value = {
    main_topic              = google_pubsub_topic.cost_optimization.name
    cost_analysis_results   = google_pubsub_topic.cost_analysis_results.name
    recommendations_generated = google_pubsub_topic.recommendations_generated.name
    optimization_alerts     = google_pubsub_topic.optimization_alerts.name
  }
}

output "pubsub_subscriptions" {
  description = "All Pub/Sub subscription names created"
  value = {
    cost_analysis   = google_pubsub_subscription.cost_analysis.name
    recommendations = google_pubsub_subscription.recommendations.name
    alerts         = google_pubsub_subscription.alerts.name
  }
}

# Cloud Functions
output "cloud_functions" {
  description = "Information about deployed Cloud Functions"
  value = {
    analyze_costs = {
      name        = google_cloudfunctions_function.analyze_costs.name
      trigger     = "Pub/Sub: ${google_pubsub_topic.cost_optimization.name}"
      description = google_cloudfunctions_function.analyze_costs.description
    }
    generate_recommendations = {
      name        = google_cloudfunctions_function.generate_recommendations.name
      trigger     = "Pub/Sub: ${google_pubsub_topic.recommendations_generated.name}"
      description = google_cloudfunctions_function.generate_recommendations.description
    }
    optimize_resources = {
      name        = google_cloudfunctions_function.optimize_resources.name
      trigger     = "Pub/Sub: ${google_pubsub_topic.recommendations_generated.name}"
      description = google_cloudfunctions_function.optimize_resources.description
    }
  }
}

output "functions_console_url" {
  description = "URL to view Cloud Functions in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

# Service Account
output "service_account_email" {
  description = "Service account email for Cloud Functions"
  value       = google_service_account.cost_optimization_functions.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.cost_optimization_functions.unique_id
}

# Cloud Scheduler Jobs
output "scheduler_jobs" {
  description = "Information about Cloud Scheduler jobs"
  value = {
    daily_analysis = {
      name     = google_cloud_scheduler_job.daily_cost_analysis.name
      schedule = google_cloud_scheduler_job.daily_cost_analysis.schedule
      timezone = google_cloud_scheduler_job.daily_cost_analysis.time_zone
    }
    weekly_report = {
      name     = google_cloud_scheduler_job.weekly_cost_report.name
      schedule = google_cloud_scheduler_job.weekly_cost_report.schedule
      timezone = google_cloud_scheduler_job.weekly_cost_report.time_zone
    }
    monthly_review = {
      name     = google_cloud_scheduler_job.monthly_optimization_review.name
      schedule = google_cloud_scheduler_job.monthly_optimization_review.schedule
      timezone = google_cloud_scheduler_job.monthly_optimization_review.time_zone
    }
  }
}

output "scheduler_console_url" {
  description = "URL to view Cloud Scheduler jobs in Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
}

# Monitoring Resources
output "notification_channel_id" {
  description = "Monitoring notification channel ID (if email provided)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

output "alert_policy_id" {
  description = "Monitoring alert policy ID (if detailed monitoring enabled)"
  value       = var.enable_detailed_monitoring ? google_monitoring_alert_policy.high_cost_optimization[0].id : null
}

output "monitoring_console_url" {
  description = "URL to view Cloud Monitoring in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

# Cost Optimization Dashboards and Reports
output "cost_optimization_queries" {
  description = "Useful BigQuery queries for cost optimization analysis"
  value = {
    total_cost_by_project = "SELECT project_id, SUM(cost) as total_cost, SUM(optimization_potential) as total_savings FROM `${var.project_id}.${local.dataset_name}.cost_analysis` GROUP BY project_id ORDER BY total_cost DESC"
    recent_recommendations = "SELECT project_id, recommender_type, COUNT(*) as recommendation_count, AVG(potential_savings) as avg_savings FROM `${var.project_id}.${local.dataset_name}.recommendations` WHERE created_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY) GROUP BY project_id, recommender_type"
    high_value_opportunities = "SELECT * FROM `${var.project_id}.${local.dataset_name}.recommendations` WHERE potential_savings > ${var.cost_threshold} ORDER BY potential_savings DESC"
    cost_trends = "SELECT usage_date, SUM(cost) as daily_cost FROM `${var.project_id}.${local.dataset_name}.cost_analysis` WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) GROUP BY usage_date ORDER BY usage_date"
  }
}

# API Endpoints and Resource URLs
output "api_endpoints" {
  description = "API endpoints and resource identifiers for integration"
  value = {
    bigquery_dataset_path = "projects/${var.project_id}/datasets/${google_bigquery_dataset.cost_optimization.dataset_id}"
    storage_bucket_path   = "gs://${google_storage_bucket.cost_optimization.name}"
    main_topic_path       = "projects/${var.project_id}/topics/${google_pubsub_topic.cost_optimization.name}"
  }
}

# Manual Testing Commands
output "testing_commands" {
  description = "Commands for manual testing of the cost optimization system"
  value = {
    trigger_cost_analysis = "gcloud pubsub topics publish ${google_pubsub_topic.cost_optimization.name} --message='{\"test\": true, \"trigger\": \"manual_test\"}'"
    check_function_logs   = "gcloud functions logs read ${google_cloudfunctions_function.analyze_costs.name} --limit=10"
    query_cost_data      = "bq query --use_legacy_sql=false \"SELECT COUNT(*) as record_count FROM \\`${var.project_id}.${local.dataset_name}.cost_analysis\\`\""
    list_recommendations = "gsutil ls gs://${google_storage_bucket.cost_optimization.name}/recommendations/"
    run_daily_job        = "gcloud scheduler jobs run ${google_cloud_scheduler_job.daily_cost_analysis.name}"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands for manual cleanup if needed"
  value = {
    delete_scheduler_jobs = "gcloud scheduler jobs delete ${google_cloud_scheduler_job.daily_cost_analysis.name} --quiet && gcloud scheduler jobs delete ${google_cloud_scheduler_job.weekly_cost_report.name} --quiet && gcloud scheduler jobs delete ${google_cloud_scheduler_job.monthly_optimization_review.name} --quiet"
    delete_functions     = "gcloud functions delete ${google_cloudfunctions_function.analyze_costs.name} --quiet && gcloud functions delete ${google_cloudfunctions_function.generate_recommendations.name} --quiet && gcloud functions delete ${google_cloudfunctions_function.optimize_resources.name} --quiet"
    delete_pubsub        = "gcloud pubsub subscriptions delete ${google_pubsub_subscription.cost_analysis.name} --quiet && gcloud pubsub topics delete ${google_pubsub_topic.cost_optimization.name} --quiet"
    delete_bigquery      = "bq rm -r -f ${var.project_id}:${google_bigquery_dataset.cost_optimization.dataset_id}"
    delete_storage       = "gsutil -m rm -r gs://${google_storage_bucket.cost_optimization.name}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    bigquery_tables      = 2
    storage_buckets      = 1
    pubsub_topics        = 4
    pubsub_subscriptions = 3
    cloud_functions      = 3
    scheduler_jobs       = 3
    service_accounts     = 1
    monitoring_channels  = var.notification_email != "" ? 1 : 0
    alert_policies       = var.enable_detailed_monitoring ? 1 : 0
    log_sinks           = var.enable_detailed_monitoring ? 1 : 0
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    project_id           = var.project_id
    region              = var.region
    dataset_location    = var.dataset_location
    function_runtime    = var.function_runtime
    function_memory     = var.function_memory
    cost_threshold      = var.cost_threshold
    schedule_timezone   = var.schedule_timezone
    monitoring_enabled  = var.enable_detailed_monitoring
    notification_email  = var.notification_email != "" ? "configured" : "not_configured"
    slack_webhook       = var.slack_webhook_url != "" ? "configured" : "not_configured"
  }
}
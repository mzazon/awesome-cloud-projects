# Output values for intelligent retail inventory optimization infrastructure
# These outputs provide essential information for verification, integration,
# and accessing the deployed services and resources

#
# Project and Environment Information
#

output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The primary region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "The unique suffix applied to resource names"
  value       = local.resource_suffix
  sensitive   = false
}

output "deployment_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

#
# Service Account Information
#

output "service_account_email" {
  description = "Email address of the inventory optimization service account"
  value       = google_service_account.inventory_optimizer.email
}

output "service_account_unique_id" {
  description = "Unique ID of the inventory optimization service account"
  value       = google_service_account.inventory_optimizer.unique_id
}

output "service_account_member" {
  description = "IAM member string for the service account"
  value       = "serviceAccount:${google_service_account.inventory_optimizer.email}"
}

#
# Cloud Storage Information
#

output "data_bucket_name" {
  description = "Name of the primary data storage bucket"
  value       = google_storage_bucket.data_bucket.name
}

output "data_bucket_url" {
  description = "GS URL of the data storage bucket"
  value       = "gs://${google_storage_bucket.data_bucket.name}"
}

output "data_bucket_self_link" {
  description = "Self link to the data storage bucket"
  value       = google_storage_bucket.data_bucket.self_link
}

output "bucket_directories" {
  description = "List of directory structures created in the data bucket"
  value = [
    "raw-data/",
    "processed-data/",
    "ml-models/",
    "optimization-results/",
    "fleet-configs/"
  ]
}

#
# BigQuery Data Warehouse Information
#

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for retail analytics"
  value       = google_bigquery_dataset.retail_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.retail_analytics.location
}

output "bigquery_dataset_self_link" {
  description = "Self link to the BigQuery dataset"
  value       = google_bigquery_dataset.retail_analytics.self_link
}

output "bigquery_tables" {
  description = "Map of BigQuery table names and their purposes"
  value = {
    inventory_levels      = google_bigquery_table.inventory_levels.table_id
    sales_history        = google_bigquery_table.sales_history.table_id
    store_locations      = google_bigquery_table.store_locations.table_id
    demand_training_data = google_bigquery_table.demand_training_data.table_id
  }
}

output "bigquery_table_references" {
  description = "Full BigQuery table references for use in queries"
  value = {
    inventory_levels      = "${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.${google_bigquery_table.inventory_levels.table_id}"
    sales_history        = "${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.${google_bigquery_table.sales_history.table_id}"
    store_locations      = "${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.${google_bigquery_table.store_locations.table_id}"
    demand_training_data = "${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.${google_bigquery_table.demand_training_data.table_id}"
  }
}

#
# Vertex AI Infrastructure Information
#

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = var.vertex_ai_region
}

output "vertex_ai_metadata_store" {
  description = "Vertex AI Metadata Store information"
  value = var.enable_vertex_ai_metadata_store ? {
    name = google_vertex_ai_metadata_store.inventory_ml_store[0].name
    id   = google_vertex_ai_metadata_store.inventory_ml_store[0].id
  } : null
}

output "vertex_ai_tensorboard" {
  description = "Vertex AI Tensorboard information"
  value = var.enable_vertex_ai_tensorboard ? {
    name         = google_vertex_ai_tensorboard.inventory_tensorboard[0].name
    display_name = google_vertex_ai_tensorboard.inventory_tensorboard[0].display_name
    id           = google_vertex_ai_tensorboard.inventory_tensorboard[0].id
  } : null
}

#
# Cloud Run Services Information
#

output "analytics_service_name" {
  description = "Name of the Cloud Run analytics service"
  value       = google_cloud_run_v2_service.analytics_service.name
}

output "analytics_service_url" {
  description = "URL of the Cloud Run analytics service"
  value       = google_cloud_run_v2_service.analytics_service.uri
}

output "analytics_service_location" {
  description = "Location of the Cloud Run analytics service"
  value       = google_cloud_run_v2_service.analytics_service.location
}

output "optimizer_service_name" {
  description = "Name of the Cloud Run optimization service"
  value       = google_cloud_run_v2_service.optimizer_service.name
}

output "optimizer_service_url" {
  description = "URL of the Cloud Run optimization service"
  value       = google_cloud_run_v2_service.optimizer_service.uri
}

output "optimizer_service_location" {
  description = "Location of the Cloud Run optimization service"
  value       = google_cloud_run_v2_service.optimizer_service.location
}

output "cloud_run_services" {
  description = "Map of all Cloud Run services with their URLs"
  value = {
    analytics = {
      name     = google_cloud_run_v2_service.analytics_service.name
      url      = google_cloud_run_v2_service.analytics_service.uri
      location = google_cloud_run_v2_service.analytics_service.location
    }
    optimizer = {
      name     = google_cloud_run_v2_service.optimizer_service.name
      url      = google_cloud_run_v2_service.optimizer_service.uri
      location = google_cloud_run_v2_service.optimizer_service.location
    }
  }
}

#
# API Endpoints for Integration
#

output "api_endpoints" {
  description = "REST API endpoints for inventory optimization services"
  value = {
    analytics_health      = "${google_cloud_run_v2_service.analytics_service.uri}/health"
    analytics_forecast    = "${google_cloud_run_v2_service.analytics_service.uri}/demand-forecast"
    analytics_inventory   = "${google_cloud_run_v2_service.analytics_service.uri}/inventory-analysis"
    optimizer_health      = "${google_cloud_run_v2_service.optimizer_service.uri}/health"
    optimizer_optimize    = "${google_cloud_run_v2_service.optimizer_service.uri}/optimize-inventory"
  }
}

#
# Fleet Engine Information (if enabled)
#

output "fleet_engine_enabled" {
  description = "Whether Fleet Engine is enabled for this deployment"
  value       = var.enable_fleet_engine
}

output "fleet_engine_provider_id" {
  description = "Fleet Engine provider ID (if configured)"
  value       = var.enable_fleet_engine ? var.fleet_engine_provider_id : null
  sensitive   = true
}

#
# Monitoring and Logging Information
#

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled"
  value       = var.enable_cloud_monitoring
}

output "log_sink_name" {
  description = "Name of the Cloud Logging sink for Cloud Run services"
  value       = var.enable_cloud_monitoring ? google_logging_project_sink.cloud_run_logs[0].name : null
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel"
  value       = var.enable_cloud_monitoring && var.monitoring_notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

output "alert_policy_names" {
  description = "Names of monitoring alert policies"
  value = var.enable_cloud_monitoring ? [
    google_monitoring_alert_policy.cloud_run_errors[0].display_name
  ] : []
}

#
# Configuration for Post-Deployment Setup
#

output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = {
    step_1 = "Build and deploy Cloud Run services using: gcloud builds submit"
    step_2 = "Load sample data into BigQuery tables using provided CSV files"
    step_3 = "Create BigQuery ML demand forecasting model using provided SQL"
    step_4 = "Test API endpoints using the URLs provided in api_endpoints output"
    step_5 = "Configure Fleet Engine provider through Cloud Console (if enabled)"
    step_6 = "Set up monitoring dashboards using the monitoring resources"
  }
}

output "required_manual_steps" {
  description = "Manual configuration steps that cannot be automated via Terraform"
  value = {
    fleet_engine_setup = var.enable_fleet_engine ? "Fleet Engine requires manual provider setup through Google Cloud Console" : "Fleet Engine not enabled"
    image_deployment   = "Cloud Run services require container images to be built and deployed separately"
    ml_model_training  = "BigQuery ML models must be created after data is loaded"
    dashboard_import   = "Monitoring dashboards should be imported through Cloud Console"
  }
}

#
# Cost and Resource Information
#

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = {
    bigquery_storage   = "~$20-50 (depends on data volume)"
    cloud_storage     = "~$10-30 (depends on data volume and access patterns)"
    cloud_run         = "~$20-100 (depends on traffic and processing volume)"
    vertex_ai         = "~$50-200 (depends on model training and prediction volume)"
    monitoring        = "~$5-20 (depends on log volume and alerts)"
    total_estimate    = "~$105-400 per month (varies with usage)"
    note             = "Costs vary significantly based on data volume, traffic, and ML usage"
  }
}

output "resource_counts" {
  description = "Count of resources deployed by type"
  value = {
    bigquery_datasets      = 1
    bigquery_tables        = 4
    cloud_storage_buckets  = 1
    cloud_run_services     = 2
    service_accounts       = 1
    iam_bindings          = length(toset([
      "roles/bigquery.admin",
      "roles/aiplatform.user", 
      "roles/storage.admin",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter",
      "roles/run.invoker"
    ]))
    vertex_ai_resources   = (var.enable_vertex_ai_metadata_store ? 1 : 0) + (var.enable_vertex_ai_tensorboard ? 1 : 0)
    monitoring_resources  = var.enable_cloud_monitoring ? 2 : 0
  }
}

#
# Validation and Testing Information
#

output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    test_bigquery     = "bq ls ${google_bigquery_dataset.retail_analytics.dataset_id}"
    test_storage      = "gsutil ls gs://${google_storage_bucket.data_bucket.name}/"
    test_analytics    = "curl -X GET '${google_cloud_run_v2_service.analytics_service.uri}/health'"
    test_optimizer    = "curl -X GET '${google_cloud_run_v2_service.optimizer_service.uri}/health'"
    check_iam         = "gcloud projects get-iam-policy ${var.project_id} --flatten='bindings[].members' --filter='bindings.members:serviceAccount:${google_service_account.inventory_optimizer.email}'"
  }
}

output "troubleshooting_info" {
  description = "Information for troubleshooting common issues"
  value = {
    service_account_key = "Use workload identity instead of service account keys for security"
    api_enablement     = "Ensure all required APIs are enabled: ${join(", ", local.required_apis)}"
    permissions        = "Verify service account has required roles for all resources"
    region_consistency = "Ensure all resources are deployed in compatible regions"
    fleet_engine_note  = "Fleet Engine requires special approval from Google Cloud sales team"
  }
}
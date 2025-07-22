# Outputs for centralized data lake governance infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Project and Environment Information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Cloud Storage Data Lake
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket serving as the data lake"
  value       = google_storage_bucket.data_lake.name
}

output "storage_bucket_url" {
  description = "URL of the data lake storage bucket"
  value       = google_storage_bucket.data_lake.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the data lake storage bucket"
  value       = google_storage_bucket.data_lake.self_link
}

output "logs_bucket_name" {
  description = "Name of the logging storage bucket (if enabled)"
  value       = var.enable_logging ? google_storage_bucket.logs_bucket[0].name : null
}

# BigLake Metastore
output "metastore_service_name" {
  description = "Name of the BigLake Metastore service"
  value       = google_dataproc_metastore_service.governance_metastore.service_id
}

output "metastore_endpoint_uri" {
  description = "Endpoint URI for the BigLake Metastore service"
  value       = google_dataproc_metastore_service.governance_metastore.endpoint_uri
}

output "metastore_state" {
  description = "Current state of the BigLake Metastore service"
  value       = google_dataproc_metastore_service.governance_metastore.state
}

output "metastore_network_config" {
  description = "Network configuration of the BigLake Metastore service"
  value = {
    consumers = google_dataproc_metastore_service.governance_metastore.network_config
  }
}

# BigQuery Dataset and Tables
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for governance"
  value       = google_bigquery_dataset.governance_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.governance_dataset.location
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.governance_dataset.self_link
}

output "retail_data_table_id" {
  description = "ID of the external retail data table in BigQuery"
  value       = google_bigquery_table.retail_data_external.table_id
}

output "customer_summary_view_id" {
  description = "ID of the customer summary governance view"
  value       = google_bigquery_table.customer_summary_view.table_id
}

output "daily_sales_materialized_view_id" {
  description = "ID of the daily sales materialized view"
  value       = google_bigquery_table.daily_sales_materialized.table_id
}

# BigQuery Connection Strings
output "bigquery_connection_strings" {
  description = "Connection strings for BigQuery tables and views"
  value = {
    dataset         = "${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}"
    retail_data     = "${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.retail_data_external.table_id}"
    customer_summary = "${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.customer_summary_view.table_id}"
    daily_sales     = "${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.daily_sales_materialized.table_id}"
  }
}

# Dataproc Cluster
output "dataproc_cluster_name" {
  description = "Name of the Dataproc analytics cluster"
  value       = google_dataproc_cluster.analytics_cluster.name
}

output "dataproc_cluster_region" {
  description = "Region of the Dataproc cluster"
  value       = google_dataproc_cluster.analytics_cluster.region
}

output "dataproc_cluster_labels" {
  description = "Labels applied to the Dataproc cluster"
  value       = google_dataproc_cluster.analytics_cluster.labels
}

output "dataproc_master_instance_names" {
  description = "Instance names of Dataproc master nodes"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].master_config[0].instance_names
}

output "dataproc_worker_instance_names" {
  description = "Instance names of Dataproc worker nodes"
  value       = google_dataproc_cluster.analytics_cluster.cluster_config[0].worker_config[0].instance_names
}

# Service Account
output "dataproc_service_account_email" {
  description = "Email of the Dataproc service account"
  value       = google_service_account.dataproc_sa.email
}

output "dataproc_service_account_unique_id" {
  description = "Unique ID of the Dataproc service account"
  value       = google_service_account.dataproc_sa.unique_id
}

# Autoscaling Policy (if enabled)
output "autoscaling_policy_name" {
  description = "Name of the Dataproc autoscaling policy (if enabled)"
  value       = var.enable_autoscaling ? google_dataproc_autoscaling_policy.cluster_autoscaling[0].name : null
}

# Data Catalog (if enabled)
output "data_catalog_entry_group_name" {
  description = "Name of the Data Catalog entry group (if enabled)"
  value       = var.enable_data_catalog ? google_data_catalog_entry_group.governance_catalog[0].name : null
}

output "data_catalog_customer_analytics_entry" {
  description = "Name of the customer analytics Data Catalog entry (if enabled)"
  value       = var.enable_data_catalog ? google_data_catalog_entry.customer_analytics_entry[0].name : null
}

# KMS Encryption (if enabled)
output "kms_key_name" {
  description = "Name of the KMS key used for encryption (if enabled)"
  value       = var.enable_encryption ? local.kms_key_name : null
  sensitive   = true
}

output "kms_keyring_name" {
  description = "Name of the KMS keyring (if created)"
  value       = var.enable_encryption && var.kms_key_name == "" ? google_kms_key_ring.governance_keyring[0].name : null
}

# Monitoring (if enabled)
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.governance_dashboard[0].id : null
}

# Logging (if enabled)
output "logging_sink_name" {
  description = "Name of the governance audit logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.governance_audit_sink[0].name : null
}

output "logging_sink_writer_identity" {
  description = "Writer identity of the logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.governance_audit_sink[0].writer_identity : null
}

# Network Information
output "network_config" {
  description = "Network configuration used for the deployment"
  value = {
    network       = var.network
    subnetwork    = var.subnetwork
    region        = var.region
    zone          = var.zone
    private_cluster = var.enable_private_cluster
  }
}

# Resource URLs for easy access
output "resource_urls" {
  description = "URLs for accessing deployed resources in the GCP Console"
  value = {
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.data_lake.name}?project=${var.project_id}"
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.governance_dataset.dataset_id}"
    dataproc_cluster = "https://console.cloud.google.com/dataproc/clusters/${google_dataproc_cluster.analytics_cluster.name}/monitoring?region=${var.region}&project=${var.project_id}"
    metastore_service = "https://console.cloud.google.com/dataproc/metastore/locations/${var.region}/services/${google_dataproc_metastore_service.governance_metastore.service_id}?project=${var.project_id}"
    data_catalog = var.enable_data_catalog ? "https://console.cloud.google.com/datacatalog/entryGroups/${google_data_catalog_entry_group.governance_catalog[0].entry_group_id}/overview?project=${var.project_id}" : null
    monitoring_dashboard = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.governance_dashboard[0].id}?project=${var.project_id}" : null
  }
}

# Sample queries for testing the governance system
output "sample_bigquery_queries" {
  description = "Sample BigQuery queries to test the governance system"
  value = {
    list_external_table = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.retail_data_external.table_id}` LIMIT 10"
    customer_summary = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.customer_summary_view.table_id}` ORDER BY total_value DESC LIMIT 10"
    daily_sales = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.daily_sales_materialized.table_id}` ORDER BY transaction_date DESC LIMIT 10"
    table_metadata = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.INFORMATION_SCHEMA.TABLES`"
  }
}

# CLI commands for manual testing and validation
output "validation_commands" {
  description = "CLI commands for validating the deployment"
  value = {
    check_metastore_status = "gcloud dataproc metastore services describe ${google_dataproc_metastore_service.governance_metastore.service_id} --location=${var.region} --project=${var.project_id}"
    check_cluster_status = "gcloud dataproc clusters describe ${google_dataproc_cluster.analytics_cluster.name} --region=${var.region} --project=${var.project_id}"
    list_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.data_lake.name}/"
    query_external_table = "bq query --use_legacy_sql=false \"SELECT COUNT(*) as row_count FROM \\`${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.retail_data_external.table_id}\\`\""
    test_hive_access = "gcloud dataproc jobs submit hive --cluster=${google_dataproc_cluster.analytics_cluster.name} --region=${var.region} --project=${var.project_id} --execute=\"SHOW DATABASES;\""
  }
}

# Governance and compliance information
output "governance_info" {
  description = "Information about governance features and compliance"
  value = {
    encryption_enabled = var.enable_encryption
    monitoring_enabled = var.enable_monitoring
    logging_enabled = var.enable_logging
    data_catalog_enabled = var.enable_data_catalog
    versioning_enabled = google_storage_bucket.data_lake.versioning[0].enabled
    uniform_bucket_access = google_storage_bucket.data_lake.uniform_bucket_level_access
    metastore_tier = google_dataproc_metastore_service.governance_metastore.tier
    lifecycle_rules_count = length(google_storage_bucket.data_lake.lifecycle_rule)
  }
}

# Cost optimization information
output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    storage_lifecycle_management = length(google_storage_bucket.data_lake.lifecycle_rule) > 0
    preemptible_workers = var.preemptible_workers > 0
    autoscaling_enabled = var.enable_autoscaling
    auto_delete_cluster = var.auto_delete_cluster > 0
    materialized_views = "daily_sales materialized view enabled for query performance"
  }
}
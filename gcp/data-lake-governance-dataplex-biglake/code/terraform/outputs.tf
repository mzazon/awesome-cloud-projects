# Output values for GCP Data Lake Governance with Dataplex and BigLake
# These outputs provide important information for verification and integration

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique identifier for this deployment"
  value       = random_id.suffix.hex
}

# Cloud Storage outputs
output "data_lake_bucket_name" {
  description = "Name of the Cloud Storage bucket for the data lake"
  value       = google_storage_bucket.data_lake.name
}

output "data_lake_bucket_url" {
  description = "URL of the Cloud Storage bucket for the data lake"
  value       = google_storage_bucket.data_lake.url
}

output "data_lake_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket for the data lake"
  value       = google_storage_bucket.data_lake.self_link
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.governance_analytics.dataset_id
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.governance_analytics.self_link
}

output "biglake_connection_id" {
  description = "ID of the BigQuery connection for BigLake tables"
  value       = google_bigquery_connection.biglake_connection.connection_id
}

output "biglake_connection_name" {
  description = "Full name of the BigQuery connection for BigLake tables"
  value       = google_bigquery_connection.biglake_connection.name
}

output "biglake_service_account" {
  description = "Service account email for the BigLake connection"
  value       = google_bigquery_connection.biglake_connection.cloud_resource[0].service_account_id
}

# BigLake table outputs
output "customers_biglake_table_id" {
  description = "Full table ID for the customers BigLake table"
  value       = "${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.${google_bigquery_table.customers_biglake.table_id}"
}

output "transactions_biglake_table_id" {
  description = "Full table ID for the transactions BigLake table"
  value       = "${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.${google_bigquery_table.transactions_biglake.table_id}"
}

# Dataplex outputs
output "dataplex_lake_name" {
  description = "Name of the Dataplex lake"
  value       = google_dataplex_lake.enterprise_lake.name
}

output "dataplex_lake_id" {
  description = "Full ID of the Dataplex lake"
  value       = google_dataplex_lake.enterprise_lake.id
}

output "dataplex_lake_self_link" {
  description = "Self-link of the Dataplex lake"
  value       = google_dataplex_lake.enterprise_lake.id
}

output "dataplex_zone_name" {
  description = "Name of the Dataplex zone"
  value       = google_dataplex_zone.raw_data_zone.name
}

output "dataplex_zone_id" {
  description = "Full ID of the Dataplex zone"
  value       = google_dataplex_zone.raw_data_zone.id
}

output "dataplex_asset_name" {
  description = "Name of the Dataplex asset"
  value       = google_dataplex_asset.storage_asset.name
}

output "dataplex_asset_id" {
  description = "Full ID of the Dataplex asset"
  value       = google_dataplex_asset.storage_asset.id
}

# Cloud Function outputs
output "governance_function_name" {
  description = "Name of the Cloud Function for governance monitoring"
  value       = google_cloudfunctions2_function.governance_monitor.name
}

output "governance_function_url" {
  description = "HTTP trigger URL for the governance monitoring function"
  value       = google_cloudfunctions2_function.governance_monitor.service_config[0].uri
}

output "governance_function_service_account" {
  description = "Service account email for the governance monitoring function"
  value       = google_cloudfunctions2_function.governance_monitor.service_config[0].service_account_email
}

# Verification commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_dataplex_lake = "gcloud dataplex lakes describe ${google_dataplex_lake.enterprise_lake.name} --location=${var.region} --format='table(name,state,createTime)'"
    list_dataplex_entities = "gcloud dataplex entities list --location=${var.region} --lake=${google_dataplex_lake.enterprise_lake.name} --zone=${google_dataplex_zone.raw_data_zone.name} --format='table(name,type,system)'"
    query_customers = "bq query --use_legacy_sql=false \"SELECT country, COUNT(*) as customer_count FROM \\`${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.${google_bigquery_table.customers_biglake.table_id}\\` GROUP BY country ORDER BY customer_count DESC\""
    test_function = "curl -X POST \"${google_cloudfunctions2_function.governance_monitor.service_config[0].uri}\" -H \"Content-Type: application/json\" -d '{\"action\": \"monitor_quality\"}'"
  }
}

# Sample queries for testing
output "sample_queries" {
  description = "Sample BigQuery queries to test BigLake tables"
  value = {
    customer_analytics = "SELECT country, COUNT(*) as customer_count FROM `${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.customers_biglake` GROUP BY country ORDER BY customer_count DESC"
    transaction_analytics = "SELECT c.country, COUNT(t.transaction_id) as transaction_count, SUM(t.amount) as total_amount FROM `${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.customers_biglake` c JOIN `${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.transactions_biglake` t ON c.customer_id = t.customer_id GROUP BY c.country ORDER BY total_amount DESC"
    quality_check = "SELECT 'customers_biglake' as table_name, COUNT(*) as total_rows, COUNT(DISTINCT customer_id) as unique_customers, COUNTIF(email IS NULL OR email = '') as missing_emails FROM `${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.customers_biglake`"
  }
}

# URLs for Google Cloud Console
output "console_urls" {
  description = "URLs to view resources in the Google Cloud Console"
  value = {
    dataplex_lake = "https://console.cloud.google.com/dataplex/lakes?project=${var.project_id}"
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.governance_analytics.dataset_id}!3sfalse"
    cloud_storage = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.data_lake.name}?project=${var.project_id}"
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.governance_monitor.name}?project=${var.project_id}"
    cloud_logging = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Resource information for cleanup
output "cleanup_info" {
  description = "Information needed for proper resource cleanup"
  value = {
    resources_created = [
      "Cloud Storage bucket: ${google_storage_bucket.data_lake.name}",
      "BigQuery dataset: ${google_bigquery_dataset.governance_analytics.dataset_id}",
      "BigQuery connection: ${google_bigquery_connection.biglake_connection.connection_id}",
      "Dataplex lake: ${google_dataplex_lake.enterprise_lake.name}",
      "Dataplex zone: ${google_dataplex_zone.raw_data_zone.name}",
      "Dataplex asset: ${google_dataplex_asset.storage_asset.name}",
      "Cloud Function: ${google_cloudfunctions2_function.governance_monitor.name}"
    ]
    deletion_protection_enabled = var.deletion_protection
  }
}
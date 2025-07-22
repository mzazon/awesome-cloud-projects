# Outputs for Cross-Database Analytics Federation with AlloyDB Omni and BigQuery
# These outputs provide important information for accessing and managing the deployed infrastructure

# Project and Infrastructure Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for zonal resources"
  value       = var.zone
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the created service account for federation"
  value       = google_service_account.federation_sa.email
}

output "service_account_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.federation_sa.unique_id
}

# Cloud Storage Information
output "data_lake_bucket_name" {
  description = "Name of the Cloud Storage bucket used as data lake foundation"
  value       = google_storage_bucket.analytics_lake.name
}

output "data_lake_bucket_url" {
  description = "URL of the Cloud Storage data lake bucket"
  value       = google_storage_bucket.analytics_lake.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

# BigQuery Information
output "analytics_federation_dataset_id" {
  description = "ID of the BigQuery dataset for federated analytics"
  value       = google_bigquery_dataset.analytics_federation.dataset_id
}

output "cloud_analytics_dataset_id" {
  description = "ID of the BigQuery dataset for cloud-native analytics data"
  value       = google_bigquery_dataset.cloud_analytics.dataset_id
}

output "customers_table_id" {
  description = "Full table ID for the customers table (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.cloud_analytics.dataset_id}.${google_bigquery_table.customers.table_id}"
}

output "customer_lifetime_value_view_id" {
  description = "Full view ID for the customer lifetime value federated view"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_federation.dataset_id}.${google_bigquery_table.customer_lifetime_value_view.table_id}"
}

# AlloyDB Omni Simulation (Cloud SQL) Information
output "alloydb_instance_name" {
  description = "Name of the Cloud SQL instance simulating AlloyDB Omni"
  value       = google_sql_database_instance.alloydb_omni_sim.name
}

output "alloydb_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.alloydb_omni_sim.connection_name
}

output "alloydb_instance_ip_address" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.alloydb_omni_sim.public_ip_address
  sensitive   = true
}

output "alloydb_instance_private_ip_address" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.alloydb_omni_sim.private_ip_address
  sensitive   = true
}

output "transactions_database_name" {
  description = "Name of the transactions database in Cloud SQL"
  value       = google_sql_database.transactions.name
}

# BigQuery Federation Connection Information
output "bigquery_connection_id" {
  description = "ID of the BigQuery connection for AlloyDB federation"
  value       = google_bigquery_connection.alloydb_federation.connection_id
}

output "bigquery_connection_location" {
  description = "Location of the BigQuery connection"
  value       = google_bigquery_connection.alloydb_federation.location
}

output "bigquery_connection_friendly_name" {
  description = "Friendly name of the BigQuery connection"
  value       = google_bigquery_connection.alloydb_federation.friendly_name
}

# Dataplex Information
output "dataplex_lake_name" {
  description = "Name of the Dataplex lake for unified governance"
  value       = google_dataplex_lake.analytics_federation_lake.name
}

output "dataplex_lake_display_name" {
  description = "Display name of the Dataplex lake"
  value       = google_dataplex_lake.analytics_federation_lake.display_name
}

output "dataplex_zone_name" {
  description = "Name of the Dataplex analytics zone"
  value       = google_dataplex_zone.analytics_zone.name
}

output "dataplex_bigquery_asset_name" {
  description = "Name of the Dataplex asset for BigQuery datasets"
  value       = google_dataplex_asset.bigquery_analytics_asset.name
}

output "dataplex_storage_asset_name" {
  description = "Name of the Dataplex asset for Cloud Storage"
  value       = google_dataplex_asset.storage_lake_asset.name
}

# Cloud Function Information
output "cloud_function_name" {
  description = "Name of the Cloud Function for metadata synchronization"
  value       = google_cloudfunctions_function.federation_metadata_sync.name
}

output "cloud_function_url" {
  description = "HTTPS trigger URL for the metadata sync Cloud Function"
  value       = google_cloudfunctions_function.federation_metadata_sync.https_trigger_url
  sensitive   = true
}

output "cloud_function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.federation_metadata_sync.region
}

# Cloud Scheduler Information
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for metadata sync"
  value       = google_cloud_scheduler_job.metadata_sync_schedule.name
}

output "scheduler_job_schedule" {
  description = "Schedule for the metadata sync job"
  value       = google_cloud_scheduler_job.metadata_sync_schedule.schedule
}

# Connection and Access Information
output "psql_connection_command" {
  description = "Command to connect to the AlloyDB Omni simulation instance using psql"
  value       = "gcloud sql connect ${google_sql_database_instance.alloydb_omni_sim.name} --user=postgres --database=${google_sql_database.transactions.name}"
  sensitive   = true
}

output "bigquery_console_url" {
  description = "URL to access BigQuery console for the analytics federation dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.analytics_federation.dataset_id}"
}

output "dataplex_console_url" {
  description = "URL to access Dataplex console for the federation lake"
  value       = "https://console.cloud.google.com/dataplex/lakes/${google_dataplex_lake.analytics_federation_lake.name}/overview?project=${var.project_id}&region=${var.region}"
}

output "cloud_storage_console_url" {
  description = "URL to access Cloud Storage console for the data lake bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.analytics_lake.name}?project=${var.project_id}"
}

# Sample Data and Testing Information
output "sample_federated_query" {
  description = "Sample SQL query to test federated analytics capabilities"
  value = templatefile("${path.module}/sql/sample_query.sql.tpl", {
    project_id    = var.project_id
    region        = var.region
    connection_id = google_bigquery_connection.alloydb_federation.connection_id
  })
}

output "testing_instructions" {
  description = "Instructions for testing the federated analytics setup"
  value = <<-EOT
    1. Connect to Cloud SQL: ${google_sql_database_instance.alloydb_omni_sim.name}
    2. Create sample data in the transactions database
    3. Execute federated queries in BigQuery using connection: ${google_bigquery_connection.alloydb_federation.connection_id}
    4. View results in the customer_lifetime_value view
    5. Monitor metadata sync via Cloud Function logs
    6. Check Dataplex for automated data discovery
  EOT
}

# Cost and Resource Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the deployed resources (approximate)"
  value = {
    cloud_sql_instance = "~$50-100 (depending on usage and region)"
    bigquery          = "~$5-20 (query and storage costs)"
    cloud_storage     = "~$1-5 (standard storage)"
    cloud_functions   = "~$0-5 (depending on invocations)"
    dataplex          = "~$10-30 (depending on data volume)"
    total_estimated   = "~$66-160 per month"
    note             = "Costs vary based on usage patterns, data volume, and query frequency"
  }
}

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    service_account     = google_service_account.federation_sa.email
    cloud_sql_instance  = google_sql_database_instance.alloydb_omni_sim.name
    storage_buckets     = [google_storage_bucket.analytics_lake.name, google_storage_bucket.function_source.name]
    bigquery_datasets   = [google_bigquery_dataset.analytics_federation.dataset_id, google_bigquery_dataset.cloud_analytics.dataset_id]
    bigquery_connection = google_bigquery_connection.alloydb_federation.connection_id
    dataplex_lake      = google_dataplex_lake.analytics_federation_lake.name
    cloud_function     = google_cloudfunctions_function.federation_metadata_sync.name
    scheduler_job      = google_cloud_scheduler_job.metadata_sync_schedule.name
  }
}
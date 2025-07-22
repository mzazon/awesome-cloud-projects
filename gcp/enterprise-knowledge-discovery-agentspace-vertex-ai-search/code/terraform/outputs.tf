# Project and location outputs
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

# Storage outputs
output "document_bucket_name" {
  description = "Name of the Cloud Storage bucket for documents"
  value       = google_storage_bucket.document_repository.name
}

output "document_bucket_url" {
  description = "URL of the document storage bucket"
  value       = google_storage_bucket.document_repository.url
}

output "document_bucket_self_link" {
  description = "Self-link of the document storage bucket"
  value       = google_storage_bucket.document_repository.self_link
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.knowledge_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.knowledge_analytics.location
}

output "search_queries_table_id" {
  description = "ID of the search queries BigQuery table"
  value       = google_bigquery_table.search_queries.table_id
}

output "document_analytics_table_id" {
  description = "ID of the document analytics BigQuery table"
  value       = google_bigquery_table.document_analytics.table_id
}

# Discovery Engine outputs
output "discovery_engine_data_store_id" {
  description = "ID of the Discovery Engine data store"
  value       = google_discovery_engine_data_store.enterprise_search.data_store_id
}

output "discovery_engine_data_store_name" {
  description = "Full name of the Discovery Engine data store"
  value       = google_discovery_engine_data_store.enterprise_search.name
}

output "search_engine_id" {
  description = "ID of the Discovery Engine search engine"
  value       = google_discovery_engine_search_engine.knowledge_engine.engine_id
}

output "search_engine_name" {
  description = "Full name of the Discovery Engine search engine"
  value       = google_discovery_engine_search_engine.knowledge_engine.name
}

# IAM outputs
output "knowledge_reader_role" {
  description = "Custom IAM role for knowledge discovery readers"
  value       = google_project_iam_custom_role.knowledge_reader.name
}

output "knowledge_admin_role" {
  description = "Custom IAM role for knowledge discovery administrators"
  value       = google_project_iam_custom_role.knowledge_admin.name
}

output "service_account_email" {
  description = "Email of the knowledge discovery service account"
  value       = google_service_account.knowledge_discovery.email
}

output "service_account_name" {
  description = "Full name of the knowledge discovery service account"
  value       = google_service_account.knowledge_discovery.name
}

output "service_account_unique_id" {
  description = "Unique ID of the knowledge discovery service account"
  value       = google_service_account.knowledge_discovery.unique_id
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if created)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.knowledge_discovery[0].id : null
}

# Search testing outputs
output "search_test_command" {
  description = "Command to test the search engine using gcloud CLI"
  value = <<-EOT
    gcloud alpha discovery-engine search \
      --engine-id=${google_discovery_engine_search_engine.knowledge_engine.engine_id} \
      --location=${var.discovery_engine_location} \
      --project=${var.project_id} \
      --query="remote work policy"
  EOT
}

output "document_import_command" {
  description = "Command to import documents into the search engine"
  value = <<-EOT
    gcloud alpha discovery-engine documents import \
      --data-store=${google_discovery_engine_data_store.enterprise_search.data_store_id} \
      --location=${var.discovery_engine_location} \
      --project=${var.project_id} \
      --gcs-uri=gs://${google_storage_bucket.document_repository.name}/documents/* \
      --id-field=uri
  EOT
}

# BigQuery query examples
output "search_analytics_query" {
  description = "Sample BigQuery query to analyze search patterns"
  value = <<-EOT
    SELECT 
      query_text,
      COUNT(*) as query_count,
      AVG(results_count) as avg_results,
      AVG(click_through_rate) as avg_ctr
    FROM `${var.project_id}.${google_bigquery_dataset.knowledge_analytics.dataset_id}.search_queries`
    GROUP BY query_text
    ORDER BY query_count DESC
    LIMIT 10
  EOT
}

output "document_analytics_query" {
  description = "Sample BigQuery query to analyze document usage"
  value = <<-EOT
    SELECT 
      document_name,
      view_count,
      relevance_score,
      last_accessed
    FROM `${var.project_id}.${google_bigquery_dataset.knowledge_analytics.dataset_id}.document_analytics`
    ORDER BY view_count DESC
  EOT
}

# Resource URLs and links
output "bigquery_console_url" {
  description = "URL to view BigQuery dataset in Google Cloud Console"
  value = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.knowledge_analytics.dataset_id}!3sdefault"
}

output "storage_console_url" {
  description = "URL to view storage bucket in Google Cloud Console"
  value = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.document_repository.name}?project=${var.project_id}"
}

output "discovery_engine_console_url" {
  description = "URL to view Discovery Engine in Google Cloud Console"
  value = "https://console.cloud.google.com/gen-app-builder/engines?project=${var.project_id}"
}

# Configuration summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    project_id                = var.project_id
    region                   = var.region
    storage_bucket          = google_storage_bucket.document_repository.name
    bigquery_dataset        = google_bigquery_dataset.knowledge_analytics.dataset_id
    search_engine           = google_discovery_engine_search_engine.knowledge_engine.engine_id
    service_account         = google_service_account.knowledge_discovery.email
    monitoring_enabled      = var.enable_monitoring
    sample_docs_created     = var.create_sample_documents
  }
}

# Next steps guidance
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Wait 10-15 minutes for document indexing to complete",
    "2. Test search functionality using the provided search_test_command",
    "3. Upload additional documents to the storage bucket",
    "4. Configure user access using the knowledge_reader_role and knowledge_admin_role",
    "5. Monitor usage through BigQuery analytics tables and Cloud Monitoring dashboard",
    "6. Customize search engine settings based on your enterprise needs"
  ]
}
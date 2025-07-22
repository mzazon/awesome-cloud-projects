# Project and region information
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

# Resource naming outputs
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "name_prefix" {
  description = "Common prefix used for all resource names"
  value       = local.name_prefix
}

# Cloud Data Fusion outputs
output "data_fusion_instance_name" {
  description = "Name of the Cloud Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.name
}

output "data_fusion_instance_id" {
  description = "ID of the Cloud Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.id
}

output "data_fusion_service_endpoint" {
  description = "Service endpoint of the Cloud Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.service_endpoint
  sensitive   = false
}

output "data_fusion_api_endpoint" {
  description = "API endpoint of the Cloud Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.api_endpoint
  sensitive   = false
}

output "data_fusion_gcs_bucket" {
  description = "GCS bucket associated with the Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.gcs_bucket
}

output "data_fusion_state" {
  description = "Current state of the Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.state
}

output "data_fusion_edition" {
  description = "Edition of the Cloud Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.type
}

output "data_fusion_version" {
  description = "Version of the Cloud Data Fusion instance"
  value       = google_data_fusion_instance.pipeline_instance.version
}

# Cloud Storage outputs
output "data_bucket_name" {
  description = "Name of the primary data storage bucket"
  value       = google_storage_bucket.data_bucket.name
}

output "data_bucket_url" {
  description = "URL of the primary data storage bucket"
  value       = google_storage_bucket.data_bucket.url
}

output "staging_bucket_name" {
  description = "Name of the staging storage bucket"
  value       = google_storage_bucket.staging_bucket.name
}

output "staging_bucket_url" {
  description = "URL of the staging storage bucket"
  value       = google_storage_bucket.staging_bucket.url
}

output "data_bucket_location" {
  description = "Location of the data storage buckets"
  value       = google_storage_bucket.data_bucket.location
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery analytics dataset"
  value       = google_bigquery_dataset.analytics_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.location
}

output "bigquery_dataset_project" {
  description = "Project ID containing the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.project
}

output "customer_transactions_table_id" {
  description = "ID of the customer transactions table"
  value       = google_bigquery_table.customer_transactions.table_id
}

output "customer_transactions_table_reference" {
  description = "Full reference to the customer transactions table"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.customer_transactions.table_id}"
}

# Service Account outputs (conditional)
output "data_fusion_service_account_email" {
  description = "Email of the Data Fusion service account"
  value       = var.create_service_accounts ? google_service_account.data_fusion_sa[0].email : null
}

output "notebook_service_account_email" {
  description = "Email of the notebook service account"
  value       = var.create_service_accounts ? google_service_account.notebook_sa[0].email : null
}

output "data_fusion_service_account_id" {
  description = "ID of the Data Fusion service account"
  value       = var.create_service_accounts ? google_service_account.data_fusion_sa[0].account_id : null
}

output "notebook_service_account_id" {
  description = "ID of the notebook service account"
  value       = var.create_service_accounts ? google_service_account.notebook_sa[0].account_id : null
}

# Network outputs (conditional)
output "custom_network_name" {
  description = "Name of the custom VPC network (if created)"
  value       = var.create_custom_network ? google_compute_network.custom_network[0].name : null
}

output "custom_network_id" {
  description = "ID of the custom VPC network (if created)"
  value       = var.create_custom_network ? google_compute_network.custom_network[0].id : null
}

output "custom_subnet_name" {
  description = "Name of the custom subnet (if created)"
  value       = var.create_custom_network ? google_compute_subnetwork.custom_subnet[0].name : null
}

output "custom_subnet_id" {
  description = "ID of the custom subnet (if created)"
  value       = var.create_custom_network ? google_compute_subnetwork.custom_subnet[0].id : null
}

output "custom_subnet_cidr" {
  description = "CIDR range of the custom subnet (if created)"
  value       = var.create_custom_network ? google_compute_subnetwork.custom_subnet[0].ip_cidr_range : null
}

# Sample data outputs
output "sample_customer_data_path" {
  description = "Path to the sample customer data in Cloud Storage"
  value       = "gs://${google_storage_bucket.data_bucket.name}/${google_storage_bucket_object.customer_data.name}"
}

output "sample_transaction_data_path" {
  description = "Path to the sample transaction data in Cloud Storage"
  value       = "gs://${google_storage_bucket.data_bucket.name}/${google_storage_bucket_object.transaction_data.name}"
}

output "notebook_template_path" {
  description = "Path to the notebook template in Cloud Storage"
  value       = "gs://${google_storage_bucket.data_bucket.name}/${google_storage_bucket_object.notebook_template.name}"
}

output "pipeline_template_path" {
  description = "Path to the pipeline template in Cloud Storage"
  value       = "gs://${google_storage_bucket.staging_bucket.name}/${google_storage_bucket_object.pipeline_template.name}"
}

# Colab Enterprise connection information
output "colab_enterprise_notebook_url" {
  description = "URL to access Colab Enterprise notebooks"
  value       = "https://colab.research.google.com/github/googlecolab/colabtools/blob/master/notebooks/colab-github-demo.ipynb"
}

output "vertex_ai_workbench_url" {
  description = "URL to access Vertex AI Workbench"
  value       = "https://console.cloud.google.com/vertex-ai/workbench?project=${var.project_id}"
}

# Access URLs and connection information
output "data_fusion_ui_url" {
  description = "URL to access the Data Fusion web interface"
  value       = "https://${google_data_fusion_instance.pipeline_instance.service_endpoint}"
}

output "bigquery_console_url" {
  description = "URL to access BigQuery console for the dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.analytics_dataset.dataset_id}"
}

output "cloud_storage_console_url" {
  description = "URL to access Cloud Storage console for the data bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.data_bucket.name}?project=${var.project_id}"
}

# Environment configuration for CLI usage
output "environment_variables" {
  description = "Environment variables for CLI operations"
  value = {
    PROJECT_ID              = var.project_id
    REGION                  = var.region
    ZONE                    = var.zone
    DATA_FUSION_INSTANCE    = google_data_fusion_instance.pipeline_instance.name
    DATA_BUCKET_NAME        = google_storage_bucket.data_bucket.name
    STAGING_BUCKET_NAME     = google_storage_bucket.staging_bucket.name
    BIGQUERY_DATASET        = google_bigquery_dataset.analytics_dataset.dataset_id
    FUSION_ENDPOINT         = google_data_fusion_instance.pipeline_instance.api_endpoint
  }
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    data_fusion_instance = google_data_fusion_instance.pipeline_instance.name
    data_bucket         = google_storage_bucket.data_bucket.name
    staging_bucket      = google_storage_bucket.staging_bucket.name
    bigquery_dataset    = google_bigquery_dataset.analytics_dataset.dataset_id
    sample_data_files   = 2
    pipeline_templates  = 1
    notebook_templates  = 1
    service_accounts    = var.create_service_accounts ? 2 : 0
    custom_network      = var.create_custom_network ? 1 : 0
  }
}

# Next steps guidance
output "next_steps" {
  description = "Next steps for using the deployed infrastructure"
  value = [
    "1. Access Data Fusion UI at: ${google_data_fusion_instance.pipeline_instance.service_endpoint}",
    "2. Open Colab Enterprise and import the notebook template from: gs://${google_storage_bucket.data_bucket.name}/notebooks/pipeline_prototype.ipynb",
    "3. Import the pipeline template into Data Fusion from: gs://${google_storage_bucket.staging_bucket.name}/pipelines/pipeline_template.json",
    "4. Run the notebook to explore data and develop transformation logic",
    "5. Deploy and test the production pipeline in Data Fusion",
    "6. Monitor results in BigQuery dataset: ${google_bigquery_dataset.analytics_dataset.dataset_id}"
  ]
}
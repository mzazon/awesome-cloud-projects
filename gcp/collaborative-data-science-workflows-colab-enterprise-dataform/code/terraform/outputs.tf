# Outputs for collaborative data science workflows infrastructure
# These outputs provide essential information for accessing and using the deployed resources

# ============================================================================
# PROJECT AND BASIC INFORMATION
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name (dev, staging, prod)"
  value       = var.environment
}

# ============================================================================
# CLOUD STORAGE OUTPUTS
# ============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for the data lake"
  value       = google_storage_bucket.data_lake.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.url
}

output "storage_bucket_self_link" {
  description = "Self-link to the Cloud Storage bucket resource"
  value       = google_storage_bucket.data_lake.self_link
}

output "data_lake_folders" {
  description = "Organized folder structure created in the data lake"
  value       = [for obj in google_storage_bucket_object.folder_structure : obj.name]
}

# ============================================================================
# BIGQUERY OUTPUTS
# ============================================================================

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics.location
}

output "bigquery_dataset_self_link" {
  description = "Self-link to the BigQuery dataset resource"
  value       = google_bigquery_dataset.analytics.self_link
}

output "bigquery_customer_table" {
  description = "Full table reference for the customer data table"
  value       = var.enable_sample_data ? "${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.customer_data[0].table_id}" : null
}

output "bigquery_transaction_table" {
  description = "Full table reference for the transaction data table"
  value       = var.enable_sample_data ? "${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.transaction_data[0].table_id}" : null
}

output "bigquery_connection_string" {
  description = "Connection string for BigQuery from notebooks and external tools"
  value       = "bq://${var.project_id}/${google_bigquery_dataset.analytics.dataset_id}"
}

# ============================================================================
# DATAFORM OUTPUTS
# ============================================================================

output "dataform_repository_name" {
  description = "Name of the Dataform repository"
  value       = google_dataform_repository.analytics_repo.name
}

output "dataform_repository_region" {
  description = "Region where the Dataform repository is located"
  value       = google_dataform_repository.analytics_repo.region
}

output "dataform_workspace_name" {
  description = "Name of the Dataform development workspace"
  value       = var.enable_dataform_workspace ? google_dataform_repository_workspace.dev_workspace[0].name : null
}

output "dataform_console_url" {
  description = "URL to access Dataform in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery/dataform/locations/${var.region}/repositories/${google_dataform_repository.analytics_repo.name}"
}

# ============================================================================
# VERTEX AI / COLAB ENTERPRISE OUTPUTS
# ============================================================================

output "notebook_service_account_email" {
  description = "Email address of the service account for notebooks"
  value       = google_service_account.notebook_sa.email
}

output "runtime_template_name" {
  description = "Name of the Colab Enterprise runtime template"
  value       = google_notebooks_runtime_template.data_science_template.name
}

output "runtime_template_self_link" {
  description = "Self-link to the runtime template resource"
  value       = google_notebooks_runtime_template.data_science_template.self_link
}

output "colab_console_url" {
  description = "URL to access Colab Enterprise in the Google Cloud Console"
  value       = "https://console.cloud.google.com/vertex-ai/colab/runtimes?project=${var.project_id}"
}

output "vertex_ai_workbench_url" {
  description = "URL to access Vertex AI Workbench in the Google Cloud Console"
  value       = "https://console.cloud.google.com/vertex-ai/workbench/managed?project=${var.project_id}"
}

# ============================================================================
# IAM AND SECURITY OUTPUTS
# ============================================================================

output "data_scientists_with_access" {
  description = "List of data scientists granted access to the environment"
  value       = var.data_scientists
}

output "data_engineers_with_access" {
  description = "List of data engineers granted access to the environment"
  value       = var.data_engineers
}

output "analysts_with_access" {
  description = "List of analysts granted read access to the environment"
  value       = var.analysts
}

output "iam_roles_summary" {
  description = "Summary of IAM roles configured for the data science workflow"
  value = {
    data_scientists = [
      "roles/bigquery.dataEditor",
      "roles/notebooks.admin", 
      "roles/aiplatform.user",
      "roles/storage.objectAdmin"
    ]
    data_engineers = [
      "roles/bigquery.dataEditor",
      "roles/dataform.editor",
      "roles/storage.objectAdmin"
    ]
    analysts = [
      "roles/bigquery.dataViewer",
      "roles/storage.objectViewer"
    ]
  }
}

# ============================================================================
# QUICK START COMMANDS
# ============================================================================

output "gsutil_commands" {
  description = "Useful gsutil commands for accessing the data lake"
  value = {
    list_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.data_lake.name}/"
    upload_sample_data   = "gsutil cp your-data-file.csv gs://${google_storage_bucket.data_lake.name}/raw-data/"
    sync_local_folder    = "gsutil -m rsync -r ./local-data-folder gs://${google_storage_bucket.data_lake.name}/raw-data/"
  }
}

output "bq_commands" {
  description = "Useful BigQuery commands for working with the dataset"
  value = {
    list_tables       = "bq ls ${google_bigquery_dataset.analytics.dataset_id}"
    query_sample_data = var.enable_sample_data ? "bq query --use_legacy_sql=false \"SELECT COUNT(*) FROM \\`${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.customer_data\\`\"" : "# Enable sample data to see query examples"
    load_csv_data     = "bq load --source_format=CSV --skip_leading_rows=1 ${google_bigquery_dataset.analytics.dataset_id}.new_table gs://${google_storage_bucket.data_lake.name}/raw-data/your-file.csv"
  }
}

output "gcloud_commands" {
  description = "Useful gcloud commands for managing Dataform and notebooks"
  value = {
    list_dataform_repos      = "gcloud dataform repositories list --region=${var.region}"
    list_dataform_workspaces = "gcloud dataform workspaces list --repository=${google_dataform_repository.analytics_repo.name} --region=${var.region}"
    create_notebook_instance = "gcloud notebooks instances create my-notebook --location=${var.zone} --machine-type=${var.notebook_machine_type} --service-account=${google_service_account.notebook_sa.email}"
  }
}

# ============================================================================
# RESOURCE IDENTIFIERS
# ============================================================================

output "resource_labels" {
  description = "Common labels applied to all resources for governance"
  value       = local.common_labels
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "resource_names" {
  description = "Summary of all created resource names"
  value = {
    storage_bucket       = google_storage_bucket.data_lake.name
    bigquery_dataset     = google_bigquery_dataset.analytics.dataset_id
    dataform_repository  = google_dataform_repository.analytics_repo.name
    dataform_workspace   = var.enable_dataform_workspace ? google_dataform_repository_workspace.dev_workspace[0].name : null
    notebook_service_account = google_service_account.notebook_sa.account_id
    runtime_template     = google_notebooks_runtime_template.data_science_template.name
  }
}

# ============================================================================
# COST OPTIMIZATION INFORMATION
# ============================================================================

output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed infrastructure"
  value = {
    storage = "Use lifecycle policies to automatically move old data to cheaper storage classes (Nearline, Coldline, Archive)"
    bigquery = "Use partitioning and clustering on large tables to reduce query costs and improve performance"
    notebooks = "Stop notebook instances when not in use to avoid compute charges"
    dataform = "Dataform repositories have minimal costs; charges are primarily for BigQuery query execution"
  }
}

output "monitoring_recommendations" {
  description = "Recommendations for monitoring the data science environment"
  value = {
    billing_alerts = "Set up billing alerts to monitor spending on BigQuery queries and storage"
    audit_logs     = "Review BigQuery audit logs to track data access patterns and optimize permissions"
    usage_metrics  = "Monitor notebook instance usage to right-size machine types"
    data_quality   = "Implement data quality checks in Dataform to catch issues early"
  }
}
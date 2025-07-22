# Outputs for scientific workflow orchestration infrastructure
# These outputs provide essential information for accessing and managing the genomics research environment

# Project and Region Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources were created"
  value       = var.zone
}

# Cloud Storage Outputs
output "genomics_bucket_name" {
  description = "Name of the Cloud Storage bucket for genomic data"
  value       = google_storage_bucket.genomics_data.name
}

output "genomics_bucket_url" {
  description = "URL of the Cloud Storage bucket for genomic data"
  value       = google_storage_bucket.genomics_data.url
}

output "genomics_bucket_self_link" {
  description = "Self link of the Cloud Storage bucket for genomic data"
  value       = google_storage_bucket.genomics_data.self_link
  sensitive   = false
}

output "bucket_directory_structure" {
  description = "Directory structure created in the genomics bucket"
  value = [
    "raw-data/",
    "processed-data/",
    "results/",
    "scripts/",
    "notebooks/"
  ]
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for genomic analytics"
  value       = google_bigquery_dataset.genomics_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.genomics_dataset.location
}

output "bigquery_dataset_self_link" {
  description = "Self link of the BigQuery dataset"
  value       = google_bigquery_dataset.genomics_dataset.self_link
}

output "variant_calls_table_id" {
  description = "ID of the variant calls BigQuery table"
  value       = google_bigquery_table.variant_calls.table_id
}

output "analysis_results_table_id" {
  description = "ID of the analysis results BigQuery table"
  value       = google_bigquery_table.analysis_results.table_id
}

output "bigquery_query_examples" {
  description = "Example BigQuery queries for genomic data analysis"
  value = {
    variant_count = "SELECT COUNT(*) as variant_count FROM `${var.project_id}.${google_bigquery_dataset.genomics_dataset.dataset_id}.${google_bigquery_table.variant_calls.table_id}`"
    
    chromosome_distribution = "SELECT chromosome, COUNT(*) as count FROM `${var.project_id}.${google_bigquery_dataset.genomics_dataset.dataset_id}.${google_bigquery_table.variant_calls.table_id}` GROUP BY chromosome ORDER BY chromosome"
    
    high_quality_variants = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.genomics_dataset.dataset_id}.${google_bigquery_table.variant_calls.table_id}` WHERE quality > 30 LIMIT 100"
    
    analysis_summary = "SELECT clinical_significance, COUNT(*) as count FROM `${var.project_id}.${google_bigquery_dataset.genomics_dataset.dataset_id}.${google_bigquery_table.analysis_results.table_id}` GROUP BY clinical_significance"
  }
}

# Vertex AI Workbench Outputs
output "workbench_instance_name" {
  description = "Name of the Vertex AI Workbench instance"
  value       = google_notebooks_instance.genomics_workbench.name
}

output "workbench_instance_zone" {
  description = "Zone where the Vertex AI Workbench instance is located"
  value       = google_notebooks_instance.genomics_workbench.location
}

output "workbench_machine_type" {
  description = "Machine type of the Vertex AI Workbench instance"
  value       = google_notebooks_instance.genomics_workbench.machine_type
}

output "workbench_proxy_uri" {
  description = "Proxy URI for accessing the Vertex AI Workbench instance"
  value       = google_notebooks_instance.genomics_workbench.proxy_uri
  sensitive   = false
}

output "workbench_jupyter_url" {
  description = "Direct URL for accessing the Jupyter environment"
  value       = "https://${google_notebooks_instance.genomics_workbench.name}.googleusercontent.com/"
}

output "workbench_console_url" {
  description = "Google Cloud Console URL for the Workbench instance"
  value       = "https://console.cloud.google.com/ai-platform/notebooks/instances/details/${var.zone}/${google_notebooks_instance.genomics_workbench.name}?project=${var.project_id}"
}

output "workbench_service_account" {
  description = "Service account email used by the Workbench instance"
  value       = google_service_account.workbench_sa.email
}

# Cloud Batch Outputs
output "batch_job_name" {
  description = "Name of the Cloud Batch job for genomic processing"
  value       = google_batch_job.genomic_processing.name
}

output "batch_job_location" {
  description = "Location of the Cloud Batch job"
  value       = google_batch_job.genomic_processing.location
}

output "batch_job_uid" {
  description = "Unique identifier of the Cloud Batch job"
  value       = google_batch_job.genomic_processing.uid
}

output "batch_service_account" {
  description = "Service account email used by Cloud Batch jobs"
  value       = google_service_account.batch_sa.email
}

output "batch_monitoring_commands" {
  description = "Commands to monitor Cloud Batch job execution"
  value = {
    describe_job = "gcloud batch jobs describe ${google_batch_job.genomic_processing.name} --location=${google_batch_job.genomic_processing.location}"
    list_jobs    = "gcloud batch jobs list --location=${google_batch_job.genomic_processing.location}"
    view_logs    = "gcloud logging read 'resource.type=\"batch_job\" AND resource.labels.job_name=\"${google_batch_job.genomic_processing.name}\"' --limit=50 --format='table(timestamp,textPayload)'"
  }
}

# Service Account Outputs
output "service_accounts" {
  description = "Service accounts created for the genomics workflow"
  value = {
    workbench = {
      email        = google_service_account.workbench_sa.email
      display_name = google_service_account.workbench_sa.display_name
      unique_id    = google_service_account.workbench_sa.unique_id
    }
    batch = {
      email        = google_service_account.batch_sa.email
      display_name = google_service_account.batch_sa.display_name
      unique_id    = google_service_account.batch_sa.unique_id
    }
  }
}

# Resource URLs and Access Information
output "resource_access_urls" {
  description = "URLs for accessing various components of the genomics workflow"
  value = {
    workbench_jupyter = "https://${google_notebooks_instance.genomics_workbench.name}.googleusercontent.com/"
    
    bigquery_console = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.genomics_dataset.dataset_id}!3svariant_calls"
    
    storage_console = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.genomics_data.name}?project=${var.project_id}"
    
    batch_console = "https://console.cloud.google.com/batch/jobs?project=${var.project_id}"
    
    ai_platform_console = "https://console.cloud.google.com/ai-platform/notebooks?project=${var.project_id}"
  }
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed genomics workflow infrastructure"
  value = {
    project_id          = var.project_id
    environment         = var.environment
    bucket_name         = google_storage_bucket.genomics_data.name
    dataset_name        = google_bigquery_dataset.genomics_dataset.dataset_id
    workbench_name      = google_notebooks_instance.genomics_workbench.name
    batch_job_name      = google_batch_job.genomic_processing.name
    deployment_region   = var.region
    deployment_zone     = var.zone
    gpu_enabled         = var.enable_gpu
    preemptible_batch   = var.use_preemptible
    monitoring_enabled  = var.enable_monitoring
    timestamp          = timestamp()
  }
}

# Getting Started Commands
output "getting_started_commands" {
  description = "Commands to get started with the genomics workflow"
  value = {
    access_workbench = "Open ${google_notebooks_instance.genomics_workbench.proxy_uri} in your browser"
    
    download_notebook = "gsutil cp gs://${google_storage_bucket.genomics_data.name}/notebooks/genomic_ml_analysis.ipynb ."
    
    upload_data = "gsutil cp your-genomic-data.fastq gs://${google_storage_bucket.genomics_data.name}/raw-data/"
    
    query_variants = "bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `${var.project_id}.${google_bigquery_dataset.genomics_dataset.dataset_id}.variant_calls`'"
    
    check_batch_status = "gcloud batch jobs describe ${google_batch_job.genomic_processing.name} --location=${google_batch_job.genomic_processing.location}"
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    storage_lifecycle_enabled = true
    preemptible_instances    = var.use_preemptible
    gpu_enabled             = var.enable_gpu
    auto_scaling_batch      = true
    estimated_monthly_cost  = "Varies based on usage - use Google Cloud Pricing Calculator for estimates"
    cost_monitoring_tip     = "Enable budget alerts in Google Cloud Console to monitor spending"
  }
}

# Security and Compliance Information
output "security_info" {
  description = "Security and compliance features of the deployment"
  value = {
    bucket_uniform_access = true
    workbench_private_ip = var.enable_private_ip
    service_accounts_created = 2
    iam_least_privilege = true
    encryption_at_rest = "Google-managed encryption keys"
    audit_logging = "Enabled through Cloud Logging"
    vpc_network = var.network_name
  }
}

# Troubleshooting Information
output "troubleshooting_commands" {
  description = "Commands for troubleshooting the genomics workflow"
  value = {
    check_apis = "gcloud services list --enabled --filter='name:(batch.googleapis.com OR notebooks.googleapis.com OR bigquery.googleapis.com)'"
    
    workbench_status = "gcloud notebooks instances describe ${google_notebooks_instance.genomics_workbench.name} --location=${var.zone}"
    
    batch_logs = "gcloud logging read 'resource.type=\"batch_job\"' --limit=20 --format='table(timestamp,severity,textPayload)'"
    
    storage_permissions = "gsutil iam get gs://${google_storage_bucket.genomics_data.name}"
    
    bigquery_access = "bq show ${google_bigquery_dataset.genomics_dataset.dataset_id}"
  }
}
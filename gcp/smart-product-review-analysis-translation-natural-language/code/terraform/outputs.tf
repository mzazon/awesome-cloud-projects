# Outputs for smart product review analysis infrastructure
# This file defines all output values that will be displayed after deployment

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

# Cloud Function Outputs
output "cloud_function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.review_analyzer.name
}

output "cloud_function_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.review_analyzer.https_trigger_url
  sensitive   = false
}

output "cloud_function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.review_analyzer.region
}

output "cloud_function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions_function.review_analyzer.available_memory_mb
}

output "cloud_function_source_archive_url" {
  description = "URL of the Cloud Function source archive in Cloud Storage"
  value       = google_cloudfunctions_function.review_analyzer.source_archive_url
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for review analysis"
  value       = google_bigquery_dataset.review_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.review_dataset.location
}

output "bigquery_table_id" {
  description = "ID of the BigQuery table for storing review analysis results"
  value       = google_bigquery_table.review_analysis.table_id
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the GCP Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.review_dataset.dataset_id}"
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

output "function_source_object" {
  description = "Name of the function source code object in Cloud Storage"
  value       = google_storage_bucket_object.function_source_zip.name
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the service account used by Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "ID of the service account used by Cloud Function"
  value       = google_service_account.function_sa.account_id
}

# API Services Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis ? var.apis_to_enable : []
}

# Sample Usage Information
output "sample_curl_command" {
  description = "Sample curl command to test the Cloud Function"
  value = <<-EOT
    curl -X POST \
      -H "Content-Type: application/json" \
      -d '{
        "review_id": "test_001",
        "review_text": "Este producto es excelente!",
        "dataset_id": "${google_bigquery_dataset.review_dataset.dataset_id}"
      }' \
      "${google_cloudfunctions_function.review_analyzer.https_trigger_url}"
  EOT
}

output "bigquery_sample_query" {
  description = "Sample BigQuery query to analyze review sentiment"
  value = <<-EOT
    SELECT 
      sentiment_label,
      COUNT(*) as review_count,
      ROUND(AVG(sentiment_score), 3) as avg_sentiment_score
    FROM `${var.project_id}.${google_bigquery_dataset.review_dataset.dataset_id}.${google_bigquery_table.review_analysis.table_id}`
    GROUP BY sentiment_label
    ORDER BY review_count DESC;
  EOT
}

# Resource URLs for easy access
output "console_urls" {
  description = "URLs to access resources in Google Cloud Console"
  value = {
    cloud_functions = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    bigquery        = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    cloud_storage   = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    cloud_logs      = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    api_explorer    = "https://developers.google.com/apis-explorer/#p/translate/v2/"
  }
}

# Cost and Resource Management
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    cloud_function_invocations = "First 2M requests free, then $0.40 per 1M requests"
    cloud_function_compute     = "First 400K GB-seconds free, then $0.0000025 per GB-second"
    translation_api           = "First 500K characters free per month, then $20 per 1M characters"
    natural_language_api      = "First 5K units free per month, then $1.00 per 1K units"
    bigquery_storage         = "$0.02 per GB per month"
    bigquery_queries         = "First 1TB free per month, then $5 per TB"
    cloud_storage            = "$0.020 per GB per month (Standard class)"
    total_estimated          = "~$10-15 for typical testing workload"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    cloud_function    = "✅ Deployed with ${var.function_memory}MB memory, ${var.function_timeout}s timeout"
    bigquery_dataset  = "✅ Created in ${var.dataset_location} with ${var.table_expiration_days} day retention"
    storage_bucket    = "✅ Created with ${var.bucket_storage_class} storage class"
    service_account   = "✅ Created with minimal required permissions"
    apis_enabled      = "✅ ${length(var.apis_to_enable)} APIs enabled"
    monitoring        = var.enable_monitoring ? "✅ Enhanced monitoring enabled" : "⚠️ Basic monitoring only"
  }
}

# Security Information
output "security_notes" {
  description = "Important security considerations for the deployment"
  value = {
    authentication = var.require_authentication ? "✅ Function requires authentication" : "⚠️ Function allows unauthenticated access"
    ingress        = "Function ingress: ${var.function_ingress_settings}"
    iam_roles      = "Service account has minimal required permissions"
    data_encryption = "✅ All data encrypted at rest and in transit"
    api_keys       = "⚠️ Consider API key restrictions for production use"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the function with sample multilingual reviews",
    "2. Set up BigQuery scheduled queries for automated reporting",
    "3. Configure Cloud Monitoring alerts for function errors",
    "4. Review and adjust API quotas based on expected usage",
    "5. Implement authentication for production workloads",
    "6. Set up data lifecycle policies for long-term storage optimization"
  ]
}
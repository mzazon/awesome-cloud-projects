# Output Values for Document Validation Workflows Infrastructure
# These outputs provide important information about the created resources
# for verification, integration, and operational use.

# ================================
# PROJECT AND LOCATION OUTPUTS
# ================================

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "The random suffix used for unique resource names"
  value       = local.resource_suffix
}

# ================================
# DOCUMENT AI PROCESSOR OUTPUTS
# ================================

output "form_processor_id" {
  description = "The ID of the Form Parser processor"
  value       = google_document_ai_processor.form_parser.name
}

output "form_processor_display_name" {
  description = "The display name of the Form Parser processor"
  value       = google_document_ai_processor.form_parser.display_name
}

output "invoice_processor_id" {
  description = "The ID of the Invoice Parser processor"
  value       = google_document_ai_processor.invoice_parser.name
}

output "invoice_processor_display_name" {
  description = "The display name of the Invoice Parser processor"
  value       = google_document_ai_processor.invoice_parser.display_name
}

output "document_ai_location" {
  description = "The location of the Document AI processors"
  value       = var.document_ai_location
}

# ================================
# CLOUD STORAGE OUTPUTS
# ================================

output "input_bucket_name" {
  description = "Name of the input bucket for document uploads"
  value       = google_storage_bucket.input.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for document uploads"
  value       = google_storage_bucket.input.url
}

output "valid_bucket_name" {
  description = "Name of the bucket for valid documents"
  value       = google_storage_bucket.valid.name
}

output "valid_bucket_url" {
  description = "URL of the bucket for valid documents"
  value       = google_storage_bucket.valid.url
}

output "invalid_bucket_name" {
  description = "Name of the bucket for invalid documents"
  value       = google_storage_bucket.invalid.name
}

output "invalid_bucket_url" {
  description = "URL of the bucket for invalid documents"
  value       = google_storage_bucket.invalid.url
}

output "review_bucket_name" {
  description = "Name of the bucket for documents requiring review"
  value       = google_storage_bucket.review.name
}

output "review_bucket_url" {
  description = "URL of the bucket for documents requiring review"
  value       = google_storage_bucket.review.url
}

output "storage_buckets_summary" {
  description = "Summary of all storage buckets created"
  value = {
    input   = google_storage_bucket.input.name
    valid   = google_storage_bucket.valid.name
    invalid = google_storage_bucket.invalid.name
    review  = google_storage_bucket.review.name
  }
}

# ================================
# BIGQUERY OUTPUTS
# ================================

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for document analytics"
  value       = google_bigquery_dataset.document_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.document_analytics.location
}

output "bigquery_table_id" {
  description = "The ID of the processing results table"
  value       = google_bigquery_table.processing_results.table_id
}

output "bigquery_table_full_name" {
  description = "The full name of the processing results table"
  value       = "${var.project_id}.${google_bigquery_dataset.document_analytics.dataset_id}.${google_bigquery_table.processing_results.table_id}"
}

output "bigquery_analytics_url" {
  description = "URL to view the BigQuery dataset in the console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.document_analytics.dataset_id}"
}

# ================================
# CLOUD WORKFLOWS OUTPUTS
# ================================

output "workflow_name" {
  description = "The name of the Cloud Workflows workflow"
  value       = google_workflows_workflow.document_validation.name
}

output "workflow_id" {
  description = "The ID of the Cloud Workflows workflow"
  value       = google_workflows_workflow.document_validation.id
}

output "workflow_region" {
  description = "The region of the Cloud Workflows workflow"
  value       = google_workflows_workflow.document_validation.region
}

output "workflow_console_url" {
  description = "URL to view the workflow in the Google Cloud Console"
  value       = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.document_validation.name}?project=${var.project_id}"
}

# ================================
# EVENTARC OUTPUTS
# ================================

output "eventarc_trigger_name" {
  description = "The name of the Eventarc trigger"
  value       = google_eventarc_trigger.document_upload.name
}

output "eventarc_trigger_location" {
  description = "The location of the Eventarc trigger"
  value       = google_eventarc_trigger.document_upload.location
}

output "eventarc_service_account_email" {
  description = "The email of the service account used by Eventarc"
  value       = google_service_account.eventarc_sa.email
}

# ================================
# IAM OUTPUTS
# ================================

output "compute_service_account_email" {
  description = "The email of the Compute Engine default service account"
  value       = data.google_compute_default_service_account.default.email
}

output "service_accounts_summary" {
  description = "Summary of all service accounts used"
  value = {
    eventarc_sa = google_service_account.eventarc_sa.email
    compute_sa  = data.google_compute_default_service_account.default.email
  }
}

# ================================
# CONFIGURATION OUTPUTS
# ================================

output "confidence_threshold" {
  description = "The confidence threshold used for document validation"
  value       = var.confidence_threshold
}

output "max_validation_errors" {
  description = "The maximum number of validation errors before marking document as invalid"
  value       = var.max_validation_errors
}

output "workflow_environment_variables" {
  description = "Environment variables configured for the workflow"
  value = {
    FORM_PROCESSOR_ID     = google_document_ai_processor.form_parser.name
    INVOICE_PROCESSOR_ID  = google_document_ai_processor.invoice_parser.name
    VALID_BUCKET         = google_storage_bucket.valid.name
    INVALID_BUCKET       = google_storage_bucket.invalid.name
    REVIEW_BUCKET        = google_storage_bucket.review.name
    DATASET_NAME         = google_bigquery_dataset.document_analytics.dataset_id
    CONFIDENCE_THRESHOLD = var.confidence_threshold
    MAX_VALIDATION_ERRORS = var.max_validation_errors
  }
  sensitive = false
}

# ================================
# TESTING AND VALIDATION OUTPUTS
# ================================

output "testing_commands" {
  description = "Commands for testing the document validation pipeline"
  value = {
    upload_test_document = "gsutil cp your-test-document.pdf gs://${google_storage_bucket.input.name}/"
    list_workflow_executions = "gcloud workflows executions list ${google_workflows_workflow.document_validation.name} --location=${var.region}"
    query_processing_results = "bq query --use_legacy_sql=false \"SELECT * FROM \\`${var.project_id}.${google_bigquery_dataset.document_analytics.dataset_id}.${google_bigquery_table.processing_results.table_id}\\` ORDER BY processing_time DESC LIMIT 10\""
    check_valid_documents = "gsutil ls gs://${google_storage_bucket.valid.name}/"
    check_invalid_documents = "gsutil ls gs://${google_storage_bucket.invalid.name}/"
    check_review_documents = "gsutil ls gs://${google_storage_bucket.review.name}/"
  }
}

# ================================
# MONITORING AND LOGGING OUTPUTS
# ================================

output "monitoring_urls" {
  description = "URLs for monitoring the document validation pipeline"
  value = {
    workflow_executions = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.document_validation.name}/executions?project=${var.project_id}"
    eventarc_triggers = "https://console.cloud.google.com/eventarc/triggers?project=${var.project_id}"
    document_ai_processors = "https://console.cloud.google.com/ai/document-ai/processors?project=${var.project_id}"
    storage_buckets = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.document_analytics.dataset_id}"
  }
}

# ================================
# COST OPTIMIZATION OUTPUTS
# ================================

output "cost_optimization_notes" {
  description = "Important notes about cost optimization for the deployed resources"
  value = {
    document_ai_pricing = "Document AI charges per document page processed. Monitor usage to control costs."
    storage_lifecycle = "Lifecycle rules are ${var.enable_lifecycle_rules ? "enabled" : "disabled"} - documents will be deleted after ${var.lifecycle_age_days} days"
    bigquery_costs = "BigQuery charges for data storage and query processing. Consider partitioning and clustering for cost optimization."
    workflow_executions = "Cloud Workflows charges per execution and duration. Monitor execution frequency and duration."
    eventarc_costs = "Eventarc charges per event delivery. Monitor event volume for cost control."
  }
}

# ================================
# CLEANUP OUTPUTS
# ================================

output "cleanup_commands" {
  description = "Commands for cleaning up the deployed resources"
  value = {
    delete_buckets = "gsutil -m rm -r gs://${google_storage_bucket.input.name} gs://${google_storage_bucket.valid.name} gs://${google_storage_bucket.invalid.name} gs://${google_storage_bucket.review.name}"
    delete_bigquery_dataset = "bq rm -r -f ${var.project_id}:${google_bigquery_dataset.document_analytics.dataset_id}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# ================================
# RESOURCE SUMMARY
# ================================

output "deployment_summary" {
  description = "Summary of all deployed resources"
  value = {
    project_id = var.project_id
    region = var.region
    processors = {
      form_parser = {
        id = google_document_ai_processor.form_parser.name
        type = "FORM_PARSER_PROCESSOR"
        location = var.document_ai_location
      }
      invoice_parser = {
        id = google_document_ai_processor.invoice_parser.name
        type = "INVOICE_PROCESSOR"
        location = var.document_ai_location
      }
    }
    storage_buckets = {
      input = google_storage_bucket.input.name
      valid = google_storage_bucket.valid.name
      invalid = google_storage_bucket.invalid.name
      review = google_storage_bucket.review.name
    }
    workflow = {
      name = google_workflows_workflow.document_validation.name
      region = var.region
    }
    analytics = {
      dataset = google_bigquery_dataset.document_analytics.dataset_id
      table = google_bigquery_table.processing_results.table_id
    }
    eventarc_trigger = {
      name = google_eventarc_trigger.document_upload.name
      location = var.region
    }
    configuration = {
      confidence_threshold = var.confidence_threshold
      max_validation_errors = var.max_validation_errors
      lifecycle_age_days = var.lifecycle_age_days
    }
  }
}
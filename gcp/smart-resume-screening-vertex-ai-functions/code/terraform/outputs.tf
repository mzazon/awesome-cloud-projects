# Outputs for the smart resume screening infrastructure
# These outputs provide important information for integration and verification

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for resume uploads"
  value       = google_storage_bucket.resume_uploads.name
}

output "bucket_url" {
  description = "GS URL of the Cloud Storage bucket"
  value       = google_storage_bucket.resume_uploads.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.resume_uploads.self_link
}

output "function_name" {
  description = "Name of the Cloud Function for resume processing"
  value       = google_cloudfunctions2_function.resume_processor.name
}

output "function_url" {
  description = "URL of the Cloud Function"
  value       = google_cloudfunctions2_function.resume_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.candidates_db.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.candidates_db.location_id
}

output "candidates_collection_name" {
  description = "Name of the Firestore collection for candidate data"
  value       = local.firestore_collection_name
}

output "monitoring_dashboard_url" {
  description = "URL to the monitoring dashboard (if enabled)"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.resume_screening_dashboard[0].id}?project=${var.project_id}" : null
}

output "notification_channels" {
  description = "Notification channels for monitoring alerts"
  value = var.enable_monitoring && var.notification_email != "" ? [
    for channel in google_monitoring_notification_channel.email : {
      name  = channel.display_name
      type  = channel.type
      email = channel.labels.email_address
    }
  ] : []
}

output "enabled_apis" {
  description = "List of APIs enabled for this solution"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

output "upload_instructions" {
  description = "Instructions for uploading resumes to trigger processing"
  value = {
    cli_command = "gsutil cp your-resume.txt gs://${google_storage_bucket.resume_uploads.name}/"
    console_url = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.resume_uploads.name}?project=${var.project_id}"
    supported_formats = var.allowed_file_types
  }
}

output "firestore_query_examples" {
  description = "Example queries for retrieving candidate data from Firestore"
  value = {
    console_url = "https://console.cloud.google.com/firestore/data?project=${var.project_id}"
    python_example = "from google.cloud import firestore\ndb = firestore.Client()\ncandidates = db.collection('${local.firestore_collection_name}').order_by('screening_score', direction=firestore.Query.DESCENDING).stream()"
    gcloud_cli = "gcloud firestore export gs://${google_storage_bucket.resume_uploads.name}/firestore-backup --collection-ids=${local.firestore_collection_name}"
  }
}

output "security_information" {
  description = "Security configuration details"
  value = {
    bucket_public_access_prevention = google_storage_bucket.resume_uploads.public_access_prevention
    bucket_uniform_access = google_storage_bucket.resume_uploads.uniform_bucket_level_access
    function_ingress_settings = google_cloudfunctions2_function.resume_processor.service_config[0].ingress_settings
    service_account_email = google_service_account.function_sa.email
    audit_logs_enabled = var.enable_audit_logs
  }
}

output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    bucket_lifecycle_rules = var.lifecycle_rules
    bucket_versioning = var.enable_versioning
    function_min_instances = google_cloudfunctions2_function.resume_processor.service_config[0].min_instance_count
    function_max_instances = google_cloudfunctions2_function.resume_processor.service_config[0].max_instance_count
    storage_class = google_storage_bucket.resume_uploads.storage_class
  }
}

output "testing_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    create_test_resume = "echo 'John Doe - 5 years Python experience, Masters degree' > test-resume.txt"
    upload_test_resume = "gsutil cp test-resume.txt gs://${google_storage_bucket.resume_uploads.name}/"
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.resume_processor.name} --region=${var.region} --limit=10"
    view_firestore_data = "gcloud firestore export gs://${google_storage_bucket.resume_uploads.name}/backup --collection-ids=${local.firestore_collection_name}"
  }
}

output "resource_identifiers" {
  description = "Important resource identifiers for reference"
  value = {
    bucket_id = google_storage_bucket.resume_uploads.id
    function_id = google_cloudfunctions2_function.resume_processor.id
    service_account_id = google_service_account.function_sa.id
    firestore_database_id = google_firestore_database.candidates_db.id
    random_suffix = local.resource_suffix
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Upload test resume files to ${google_storage_bucket.resume_uploads.name}",
    "Monitor function execution in Cloud Logging",
    "Query candidate data in Firestore collection '${local.firestore_collection_name}'",
    "Review monitoring dashboard at: https://console.cloud.google.com/monitoring",
    "Configure additional IAM permissions if needed for end users",
    "Consider setting up Cloud CDN for the bucket if building a web interface",
    "Implement custom scoring algorithms based on your hiring criteria"
  ]
}
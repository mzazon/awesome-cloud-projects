# Cloud SQL Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL database instance"
  value       = google_sql_database_instance.productivity_instance.name
}

output "database_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.productivity_instance.connection_name
}

output "database_name" {
  description = "Name of the productivity database"
  value       = google_sql_database.productivity_db.name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.productivity_instance.private_ip_address
}

output "database_public_ip" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.productivity_instance.public_ip_address
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the workspace automation service account"
  value       = google_service_account.workspace_automation.email
}

output "service_account_id" {
  description = "ID of the workspace automation service account"
  value       = google_service_account.workspace_automation.id
}

output "service_account_unique_id" {
  description = "Unique ID of the workspace automation service account"
  value       = google_service_account.workspace_automation.unique_id
}

# Cloud Functions Outputs
output "email_processor_function_name" {
  description = "Name of the email processing Cloud Function"
  value       = google_cloudfunctions2_function.email_processor.name
}

output "email_processor_function_url" {
  description = "URL of the email processing Cloud Function"
  value       = google_cloudfunctions2_function.email_processor.service_config[0].uri
}

output "meeting_automation_function_name" {
  description = "Name of the meeting automation Cloud Function"
  value       = google_cloudfunctions2_function.meeting_automation.name
}

output "meeting_automation_function_url" {
  description = "URL of the meeting automation Cloud Function"
  value       = google_cloudfunctions2_function.meeting_automation.service_config[0].uri
}

output "document_organization_function_name" {
  description = "Name of the document organization Cloud Function"
  value       = google_cloudfunctions2_function.document_organization.name
}

output "document_organization_function_url" {
  description = "URL of the document organization Cloud Function"
  value       = google_cloudfunctions2_function.document_organization.service_config[0].uri
}

output "productivity_metrics_function_name" {
  description = "Name of the productivity metrics Cloud Function"
  value       = google_cloudfunctions2_function.productivity_metrics.name
}

output "productivity_metrics_function_url" {
  description = "URL of the productivity metrics Cloud Function"
  value       = google_cloudfunctions2_function.productivity_metrics.service_config[0].uri
}

# Cloud Scheduler Outputs
output "scheduler_jobs" {
  description = "List of Cloud Scheduler job names and schedules"
  value = var.enable_scheduler_jobs ? {
    email_processing = {
      name     = google_cloud_scheduler_job.email_processing[0].name
      schedule = google_cloud_scheduler_job.email_processing[0].schedule
    }
    meeting_automation = {
      name     = google_cloud_scheduler_job.meeting_automation[0].name
      schedule = google_cloud_scheduler_job.meeting_automation[0].schedule
    }
    document_organization = {
      name     = google_cloud_scheduler_job.document_organization[0].name
      schedule = google_cloud_scheduler_job.document_organization[0].schedule
    }
    productivity_metrics = {
      name     = google_cloud_scheduler_job.productivity_metrics[0].name
      schedule = google_cloud_scheduler_job.productivity_metrics[0].schedule
    }
  } : {}
}

# Storage Outputs
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether monitoring and logging are enabled"
  value       = var.enable_monitoring
}

output "log_sink_name" {
  description = "Name of the Cloud Logging sink for function logs"
  value       = var.enable_monitoring ? google_logging_project_sink.function_logs[0].name : null
}

output "alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy for function errors"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_errors[0].name : null
}

# Security and Authentication Outputs
output "database_password_secret" {
  description = "Note about database password storage"
  value       = "Database password is stored in Terraform state. Consider using Secret Manager for production deployments."
  sensitive   = false
}

output "workspace_api_configuration" {
  description = "Instructions for configuring Google Workspace APIs"
  value = {
    service_account_email = google_service_account.workspace_automation.email
    required_scopes = [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/calendar",
      "https://www.googleapis.com/auth/drive"
    ]
    domain_delegation_instructions = "Enable domain-wide delegation for the service account in Google Workspace Admin Console"
    oauth_consent_screen_setup = "Configure OAuth consent screen in Google Cloud Console"
  }
}

# Cost Estimation Outputs
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    cloud_sql = "~$7-15 (db-f1-micro instance with 20GB storage)"
    cloud_functions = "~$1-5 (depends on execution frequency and duration)"
    cloud_scheduler = "~$0.10 (4 jobs)"
    cloud_storage = "~$0.50-2 (function source code and logs)"
    total_estimated = "~$8.60-22.10 per month"
    note = "Costs vary based on usage patterns and data transfer"
  }
}

# Resource Information
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    cloud_sql_instance = google_sql_database_instance.productivity_instance.name
    database = google_sql_database.productivity_db.name
    service_account = google_service_account.workspace_automation.email
    functions = [
      google_cloudfunctions2_function.email_processor.name,
      google_cloudfunctions2_function.meeting_automation.name,
      google_cloudfunctions2_function.document_organization.name,
      google_cloudfunctions2_function.productivity_metrics.name
    ]
    scheduler_jobs_enabled = var.enable_scheduler_jobs
    monitoring_enabled = var.enable_monitoring
    region = var.region
    labels = local.common_labels
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps after Terraform deployment"
  value = {
    step_1 = "Configure Google Workspace API access in the Admin Console"
    step_2 = "Enable domain-wide delegation for the service account"
    step_3 = "Set up OAuth consent screen in Google Cloud Console"
    step_4 = "Test Cloud Functions manually or wait for scheduler jobs to run"
    step_5 = "Monitor function execution in Cloud Logging and Cloud Monitoring"
    step_6 = "Query productivity analytics data from Cloud SQL database"
  }
}

# Testing and Validation Outputs
output "testing_commands" {
  description = "Commands to test the deployed solution"
  value = {
    test_email_processor = "curl -X GET ${google_cloudfunctions2_function.email_processor.service_config[0].uri}"
    test_meeting_automation = "curl -X GET ${google_cloudfunctions2_function.meeting_automation.service_config[0].uri}"
    test_document_organization = "curl -X GET ${google_cloudfunctions2_function.document_organization.service_config[0].uri}"
    test_productivity_metrics = "curl -X GET ${google_cloudfunctions2_function.productivity_metrics.service_config[0].uri}"
    connect_to_database = "gcloud sql connect ${google_sql_database_instance.productivity_instance.name} --user=postgres --database=${google_sql_database.productivity_db.name}"
    view_scheduler_jobs = "gcloud scheduler jobs list --location=${var.region}"
  }
}
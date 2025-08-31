# Outputs for Smart Expense Processing Infrastructure
# Terraform outputs providing important resource information and connection details

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

# Storage Resources
output "expense_receipts_bucket_name" {
  description = "Name of the Cloud Storage bucket for receipt storage"
  value       = google_storage_bucket.expense_receipts.name
}

output "expense_receipts_bucket_url" {
  description = "URL of the Cloud Storage bucket for receipt storage"
  value       = google_storage_bucket.expense_receipts.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Database Information
output "database_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.expense_db.name
}

output "database_connection_name" {
  description = "Connection name for the Cloud SQL instance (for Cloud SQL Proxy)"
  value       = google_sql_database_instance.expense_db.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.expense_db.private_ip_address
}

output "database_public_ip" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.expense_db.public_ip_address
}

output "database_name" {
  description = "Name of the expenses database"
  value       = google_sql_database.expenses.name
}

output "database_user" {
  description = "Username for database application access"
  value       = google_sql_user.app_user.name
  sensitive   = true
}

# Document AI Information
output "document_ai_processor_id" {
  description = "ID of the Document AI expense processor"
  value       = var.document_ai_processor_id
}

output "document_ai_processor_endpoint" {
  description = "Endpoint URL for the Document AI processor"
  value       = "https://${var.region}-documentai.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/processors/${var.document_ai_processor_id}:process"
}

# Cloud Functions Information
output "expense_validator_function_name" {
  description = "Name of the expense validation Cloud Function"
  value       = google_cloudfunctions2_function.expense_validator.name
}

output "expense_validator_function_url" {
  description = "HTTP trigger URL for the expense validation Cloud Function"
  value       = google_cloudfunctions2_function.expense_validator.service_config[0].uri
}

output "report_generator_function_name" {
  description = "Name of the report generator Cloud Function"
  value       = google_cloudfunctions2_function.report_generator.name
}

output "report_generator_function_url" {
  description = "HTTP trigger URL for the report generator Cloud Function"
  value       = google_cloudfunctions2_function.report_generator.service_config[0].uri
}

# Workflow Information
output "expense_workflow_name" {
  description = "Name of the expense processing Cloud Workflow"
  value       = google_workflows_workflow.expense_processing.name
}

output "expense_workflow_id" {
  description = "ID of the expense processing Cloud Workflow"
  value       = google_workflows_workflow.expense_processing.id
}

# Service Account Information
output "service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.expense_functions_sa.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.expense_functions_sa.unique_id
}

# Security Information
output "db_credentials_secret_id" {
  description = "Secret Manager secret ID for database credentials"
  value       = google_secret_manager_secret.db_credentials.secret_id
}

output "db_credentials_secret_name" {
  description = "Full resource name of the database credentials secret"
  value       = google_secret_manager_secret.db_credentials.name
}

# Monitoring Information
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard"
  value       = google_monitoring_dashboard.expense_dashboard.id
}

# Scheduled Jobs Information
output "scheduled_reports_job_name" {
  description = "Name of the scheduled reports Cloud Scheduler job"
  value       = var.enable_scheduled_reports ? google_cloud_scheduler_job.weekly_reports[0].name : "Not enabled"
}

output "scheduled_reports_schedule" {
  description = "Cron schedule for automated expense reports"
  value       = var.enable_scheduled_reports ? var.report_schedule : "Not enabled"
}

# API Endpoints for Integration
output "api_endpoints" {
  description = "Important API endpoints for application integration"
  value = {
    document_ai_processor = "https://${var.region}-documentai.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/processors/${var.document_ai_processor_id}:process"
    expense_validator     = google_cloudfunctions2_function.expense_validator.service_config[0].uri
    report_generator      = google_cloudfunctions2_function.report_generator.service_config[0].uri
    workflow_trigger      = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.expense_processing.name}/executions"
  }
}

# Connection Information for Applications
output "database_connection_info" {
  description = "Database connection information for applications"
  value = {
    connection_name = google_sql_database_instance.expense_db.connection_name
    database_name   = google_sql_database.expenses.name
    username        = google_sql_user.app_user.name
    secret_name     = google_secret_manager_secret.db_credentials.name
    proxy_command   = "cloud_sql_proxy -instances=${google_sql_database_instance.expense_db.connection_name}=tcp:5432"
  }
  sensitive = true
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for major resources (USD)"
  value = {
    cloud_sql_instance    = "~$25-50 (depending on usage)"
    cloud_functions      = "~$5-15 (depending on invocations)"
    cloud_storage        = "~$1-5 (depending on storage and operations)"
    document_ai          = "~$10-30 (depending on documents processed)"
    vertex_ai_gemini     = "~$5-20 (depending on API calls)"
    cloud_workflows      = "~$1-3 (depending on executions)"
    monitoring_logging   = "~$2-8 (depending on log volume)"
    total_estimated      = "~$50-130 per month"
    note                 = "Actual costs depend on usage patterns and data volumes"
  }
}

# Useful Commands
output "useful_commands" {
  description = "Useful commands for managing the expense processing system"
  value = {
    connect_to_database = "gcloud sql connect ${google_sql_database_instance.expense_db.name} --user=${google_sql_user.app_user.name} --database=${google_sql_database.expenses.name}"
    test_validator_function = "curl -X POST '${google_cloudfunctions2_function.expense_validator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"vendor_name\":\"Test\",\"total_amount\":45.50,\"category\":\"meals\"}'"
    trigger_workflow = "gcloud workflows run ${google_workflows_workflow.expense_processing.name} --location=${var.region} --data='{\"employee_email\":\"test@company.com\"}'"
    view_logs = "gcloud logging read 'resource.type=\"cloud_function\"' --limit=50 --format='table(timestamp,severity,textPayload)'"
    generate_report = "curl -X POST '${google_cloudfunctions2_function.report_generator.service_config[0].uri}'"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    cloud_storage_buckets = [
      google_storage_bucket.expense_receipts.name,
      google_storage_bucket.function_source.name
    ]
    cloud_sql_instances = [google_sql_database_instance.expense_db.name]
    cloud_functions = [
      google_cloudfunctions2_function.expense_validator.name,
      google_cloudfunctions2_function.report_generator.name
    ]
    workflows = [google_workflows_workflow.expense_processing.name]
    service_accounts = [google_service_account.expense_functions_sa.email]
    secrets = [google_secret_manager_secret.db_credentials.secret_id]
    scheduled_jobs = var.enable_scheduled_reports ? [google_cloud_scheduler_job.weekly_reports[0].name] : []
    monitoring_dashboards = [google_monitoring_dashboard.expense_dashboard.id]
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = [
    "1. Create Document AI expense processor manually in the console or via API",
    "2. Update the document_ai_processor_id variable with the actual processor ID",
    "3. Create database tables using the schema provided in the recipe",
    "4. Test the expense validation function with sample data",
    "5. Configure notification emails for expense approvals",
    "6. Set up custom monitoring alerts based on your requirements",
    "7. Integrate with your existing HR or financial systems",
    "8. Train staff on using the new expense processing system"
  ]
}
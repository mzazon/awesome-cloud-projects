# Output values for the tax calculator API infrastructure
# These outputs provide important information about the deployed resources

# Project Information
output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

# Cloud Functions Information
output "tax_calculator_function_name" {
  description = "Name of the tax calculator Cloud Function"
  value       = google_cloudfunctions_function.tax_calculator.name
}

output "tax_calculator_function_url" {
  description = "HTTP trigger URL for the tax calculator function"
  value       = google_cloudfunctions_function.tax_calculator.https_trigger_url
  sensitive   = false
}

output "calculation_history_function_name" {
  description = "Name of the calculation history Cloud Function"
  value       = google_cloudfunctions_function.calculation_history.name
}

output "calculation_history_function_url" {
  description = "HTTP trigger URL for the calculation history function"
  value       = google_cloudfunctions_function.calculation_history.https_trigger_url
  sensitive   = false
}

# Firestore Information
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.tax_calculator_db.name
}

output "firestore_location_id" {
  description = "Location ID of the Firestore database"
  value       = google_firestore_database.tax_calculator_db.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.tax_calculator_db.type
}

# Storage Information
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Function Configuration Details
output "tax_calculator_function_config" {
  description = "Configuration details of the tax calculator function"
  value = {
    memory_mb     = google_cloudfunctions_function.tax_calculator.available_memory_mb
    timeout       = google_cloudfunctions_function.tax_calculator.timeout
    runtime       = google_cloudfunctions_function.tax_calculator.runtime
    max_instances = google_cloudfunctions_function.tax_calculator.max_instances
    min_instances = google_cloudfunctions_function.tax_calculator.min_instances
  }
}

output "calculation_history_function_config" {
  description = "Configuration details of the calculation history function"
  value = {
    memory_mb     = google_cloudfunctions_function.calculation_history.available_memory_mb
    timeout       = google_cloudfunctions_function.calculation_history.timeout
    runtime       = google_cloudfunctions_function.calculation_history.runtime
    max_instances = google_cloudfunctions_function.calculation_history.max_instances
    min_instances = google_cloudfunctions_function.calculation_history.min_instances
  }
}

# API Testing Information
output "test_commands" {
  description = "Sample commands for testing the deployed API"
  value = {
    calculate_tax = "curl -X POST ${google_cloudfunctions_function.tax_calculator.https_trigger_url} -H 'Content-Type: application/json' -d '{\"income\": 65000, \"filing_status\": \"single\", \"deductions\": 15000, \"user_id\": \"test_user\"}'"
    get_history   = "curl '${google_cloudfunctions_function.calculation_history.https_trigger_url}?user_id=test_user&limit=5'"
  }
}

# Resource Names with Random Suffix
output "resource_names" {
  description = "Names of created resources with random suffixes"
  value = {
    calculator_function = google_cloudfunctions_function.tax_calculator.name
    history_function    = google_cloudfunctions_function.calculation_history.name
    storage_bucket      = google_storage_bucket.function_source.name
    random_suffix       = random_id.suffix.hex
  }
}

# Monitoring and Logging
output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for function logs"
  value       = google_logging_project_sink.function_logs.name
}

output "logging_filter" {
  description = "Log filter used for capturing function logs"
  value       = google_logging_project_sink.function_logs.filter
}

# Security and Access Information
output "iam_configuration" {
  description = "IAM configuration for the deployed functions"
  value = {
    allow_unauthenticated = var.allow_unauthenticated
    firestore_role       = "roles/datastore.user"
    service_account      = "${var.project_id}@appspot.gserviceaccount.com"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed infrastructure"
  value = {
    functions_scale_to_zero = "Cloud Functions scale to zero when not in use"
    firestore_pricing      = "Firestore charges based on operations and storage"
    monitoring_dashboard   = "Use Cloud Monitoring to track function invocations and costs"
    budget_alerts         = "Set up budget alerts to monitor spending"
  }
}

# Next Steps for Users
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    test_api              = "Test the API using the provided curl commands"
    view_firestore_data   = "Check Firestore console to see stored calculations"
    monitor_functions     = "View function logs in Cloud Logging"
    setup_authentication = "Consider implementing authentication for production use"
    configure_custom_domain = "Set up a custom domain for the API endpoints"
  }
}
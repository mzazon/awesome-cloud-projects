# =============================================================================
# Outputs for Random Quote API with Cloud Functions and Firestore
# =============================================================================
# This file defines output values that provide important information about
# the deployed infrastructure, including URLs, resource identifiers, and
# configuration details needed for testing and integration.

# -----------------------------------------------------------------------------
# Cloud Function Outputs
# -----------------------------------------------------------------------------

output "function_url" {
  description = "The HTTPS URL of the deployed Cloud Function. Use this URL to make API requests to get random quotes."
  value       = google_cloudfunctions_function.random_quote_api.https_trigger_url
  sensitive   = false
}

output "function_name" {
  description = "The name of the deployed Cloud Function for reference in monitoring and management."
  value       = google_cloudfunctions_function.random_quote_api.name
  sensitive   = false
}

output "function_region" {
  description = "The Google Cloud region where the Cloud Function is deployed."
  value       = google_cloudfunctions_function.random_quote_api.region
  sensitive   = false
}

output "function_trigger_url" {
  description = "The complete trigger URL for the Cloud Function including region and project information."
  value       = google_cloudfunctions_function.random_quote_api.https_trigger_url
  sensitive   = false
}

output "function_status" {
  description = "The current status of the Cloud Function deployment (ACTIVE, FAILED, etc.)."
  value       = google_cloudfunctions_function.random_quote_api.status
  sensitive   = false
}

output "function_service_account_email" {
  description = "The email address of the service account used by the Cloud Function."
  value       = google_cloudfunctions_function.random_quote_api.service_account_email
  sensitive   = false
}

output "function_memory_mb" {
  description = "The amount of memory allocated to the Cloud Function in megabytes."
  value       = google_cloudfunctions_function.random_quote_api.available_memory_mb
  sensitive   = false
}

output "function_timeout_seconds" {
  description = "The maximum execution time allowed for the Cloud Function in seconds."
  value       = google_cloudfunctions_function.random_quote_api.timeout
  sensitive   = false
}

output "function_max_instances" {
  description = "The maximum number of concurrent instances allowed for the Cloud Function."
  value       = google_cloudfunctions_function.random_quote_api.max_instances
  sensitive   = false
}

output "function_runtime" {
  description = "The runtime environment used by the Cloud Function (e.g., nodejs20)."
  value       = google_cloudfunctions_function.random_quote_api.runtime
  sensitive   = false
}

# -----------------------------------------------------------------------------
# Firestore Database Outputs
# -----------------------------------------------------------------------------

output "firestore_database_id" {
  description = "The ID of the Firestore database used for storing quotes."
  value       = google_firestore_database.quotes_database.name
  sensitive   = false
}

output "firestore_database_location" {
  description = "The location (region) where the Firestore database is deployed."
  value       = google_firestore_database.quotes_database.location_id
  sensitive   = false
}

output "firestore_database_type" {
  description = "The type of Firestore database (FIRESTORE_NATIVE or DATASTORE_MODE)."
  value       = google_firestore_database.quotes_database.type
  sensitive   = false
}

output "firestore_database_uid" {
  description = "The unique identifier for the Firestore database instance."
  value       = google_firestore_database.quotes_database.uid
  sensitive   = false
}

output "firestore_database_create_time" {
  description = "The timestamp when the Firestore database was created."
  value       = google_firestore_database.quotes_database.create_time
  sensitive   = false
}

output "firestore_database_update_time" {
  description = "The timestamp when the Firestore database was last updated."
  value       = google_firestore_database.quotes_database.update_time
  sensitive   = false
}

# -----------------------------------------------------------------------------
# Cloud Storage Outputs
# -----------------------------------------------------------------------------

output "function_source_bucket_name" {
  description = "The name of the Cloud Storage bucket used to store the Cloud Function source code."
  value       = google_storage_bucket.function_source.name
  sensitive   = false
}

output "function_source_bucket_url" {
  description = "The URL of the Cloud Storage bucket containing the function source code."
  value       = google_storage_bucket.function_source.url
  sensitive   = false
}

output "function_source_bucket_location" {
  description = "The location where the function source code bucket is stored."
  value       = google_storage_bucket.function_source.location
  sensitive   = false
}

output "function_source_object_name" {
  description = "The name of the source code archive object in the Cloud Storage bucket."
  value       = google_storage_bucket_object.function_source.name
  sensitive   = false
}

output "function_source_object_md5" {
  description = "The MD5 hash of the function source code archive, useful for tracking changes."
  value       = google_storage_bucket_object.function_source.md5hash
  sensitive   = false
}

# -----------------------------------------------------------------------------
# Project and Configuration Outputs
# -----------------------------------------------------------------------------

output "project_id" {
  description = "The Google Cloud Project ID where the resources are deployed."
  value       = var.project_id
  sensitive   = false
}

output "project_number" {
  description = "The Google Cloud Project number for the current project."
  value       = data.google_project.current.number
  sensitive   = false
}

output "deployment_region" {
  description = "The Google Cloud region where regional resources are deployed."
  value       = var.region
  sensitive   = false
}

output "environment" {
  description = "The deployment environment (development, staging, production)."
  value       = var.environment
  sensitive   = false
}

# -----------------------------------------------------------------------------
# API Testing and Integration Outputs
# -----------------------------------------------------------------------------

output "api_endpoint" {
  description = "The complete API endpoint URL for making requests to get random quotes."
  value       = google_cloudfunctions_function.random_quote_api.https_trigger_url
  sensitive   = false
}

output "curl_test_command" {
  description = "A sample curl command to test the deployed API endpoint."
  value       = "curl -X GET '${google_cloudfunctions_function.random_quote_api.https_trigger_url}' -H 'Accept: application/json'"
  sensitive   = false
}

output "api_documentation" {
  description = "Basic API documentation for the random quote endpoint."
  value = {
    endpoint = google_cloudfunctions_function.random_quote_api.https_trigger_url
    method   = "GET"
    headers  = {
      Accept = "application/json"
    }
    response_format = {
      id        = "string - Unique document ID"
      quote     = "string - The quote text"
      author    = "string - Quote author"
      category  = "string - Quote category"
      timestamp = "string - ISO timestamp of request"
    }
    example_response = {
      id        = "abc123xyz"
      quote     = "The only way to do great work is to love what you do."
      author    = "Steve Jobs"
      category  = "motivation"
      timestamp = "2025-01-12T10:30:00.000Z"
    }
  }
  sensitive = false
}

# -----------------------------------------------------------------------------
# Monitoring and Management Outputs
# -----------------------------------------------------------------------------

output "cloud_console_function_url" {
  description = "URL to view the Cloud Function in the Google Cloud Console."
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.random_quote_api.name}?project=${var.project_id}"
  sensitive   = false
}

output "cloud_console_firestore_url" {
  description = "URL to view the Firestore database in the Google Cloud Console."
  value       = "https://console.cloud.google.com/firestore/databases/${google_firestore_database.quotes_database.name}/data?project=${var.project_id}"
  sensitive   = false
}

output "cloud_logging_url" {
  description = "URL to view Cloud Function logs in the Google Cloud Console."
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions_function.random_quote_api.name}%22?project=${var.project_id}"
  sensitive   = false
}

output "cloud_monitoring_url" {
  description = "URL to view Cloud Function metrics in the Google Cloud Console."
  value       = "https://console.cloud.google.com/monitoring/dashboards/resourceList/gce_instance?project=${var.project_id}&pageState=%7B%22resourceFilter%22:%22resource.type=%22cloud_function%22%22%7D"
  sensitive   = false
}

# -----------------------------------------------------------------------------
# Resource Summary Output
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "A comprehensive summary of all deployed resources and their key properties."
  value = {
    # Function details
    function = {
      name         = google_cloudfunctions_function.random_quote_api.name
      url          = google_cloudfunctions_function.random_quote_api.https_trigger_url
      region       = google_cloudfunctions_function.random_quote_api.region
      runtime      = google_cloudfunctions_function.random_quote_api.runtime
      memory_mb    = google_cloudfunctions_function.random_quote_api.available_memory_mb
      timeout_s    = google_cloudfunctions_function.random_quote_api.timeout
      max_instances = google_cloudfunctions_function.random_quote_api.max_instances
    }
    
    # Database details
    database = {
      id       = google_firestore_database.quotes_database.name
      type     = google_firestore_database.quotes_database.type
      location = google_firestore_database.quotes_database.location_id
      uid      = google_firestore_database.quotes_database.uid
    }
    
    # Storage details
    storage = {
      bucket_name     = google_storage_bucket.function_source.name
      bucket_location = google_storage_bucket.function_source.location
      source_object   = google_storage_bucket_object.function_source.name
      source_md5      = google_storage_bucket_object.function_source.md5hash
    }
    
    # Configuration details
    configuration = {
      project_id        = var.project_id
      environment       = var.environment
      region           = var.region
      public_access    = var.allow_public_access
      sample_data      = var.populate_sample_data
    }
  }
  sensitive = false
}

# -----------------------------------------------------------------------------
# Cost Estimation Outputs
# -----------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources (USD, approximate)."
  value = {
    cloud_functions = {
      description = "Pay-per-invocation pricing"
      free_tier   = "2 million invocations/month, 400,000 GB-seconds, 200,000 GHz-seconds"
      estimated   = "$0.00 - $5.00 (depending on usage)"
    }
    firestore = {
      description = "Document operations and storage pricing"
      free_tier   = "1 GB storage, 50,000 read/20,000 write/20,000 delete operations per day"
      estimated   = "$0.00 - $1.00 (depending on usage)"
    }
    cloud_storage = {
      description = "Storage for function source code"
      estimated   = "$0.01 - $0.05 (minimal usage)"
    }
    total_estimated = "$0.01 - $6.05 per month (mostly free tier)"
  }
  sensitive = false
}

# -----------------------------------------------------------------------------
# Next Steps and Recommendations
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Recommended next steps after deployment for testing, monitoring, and production readiness."
  value = {
    testing = [
      "Test the API using: curl -X GET '${google_cloudfunctions_function.random_quote_api.https_trigger_url}' -H 'Accept: application/json'",
      "Verify Firestore data in the console: https://console.cloud.google.com/firestore/databases/${google_firestore_database.quotes_database.name}/data?project=${var.project_id}",
      "Check function logs: https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions_function.random_quote_api.name}%22?project=${var.project_id}"
    ]
    monitoring = [
      "Set up Cloud Monitoring alerts for function errors and latency",
      "Configure log-based metrics for API usage patterns",
      "Enable uptime monitoring for the API endpoint"
    ]
    security = [
      "Consider adding API key authentication for production use",
      "Implement rate limiting if needed",
      "Review and restrict CORS origins for production environments"
    ]
    scaling = [
      "Monitor function performance and adjust memory allocation if needed",
      "Consider implementing caching for frequently accessed quotes",
      "Plan for database scaling as quote collection grows"
    ]
  }
  sensitive = false
}
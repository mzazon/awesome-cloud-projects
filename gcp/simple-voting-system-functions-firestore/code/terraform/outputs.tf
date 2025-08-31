# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

# Cloud Functions Information
output "submit_vote_function_name" {
  description = "Name of the vote submission Cloud Function"
  value       = google_cloudfunctions2_function.submit_vote.name
}

output "submit_vote_function_url" {
  description = "HTTP trigger URL for the vote submission function"
  value       = google_cloudfunctions2_function.submit_vote.service_config[0].uri
  sensitive   = false
}

output "get_results_function_name" {
  description = "Name of the results retrieval Cloud Function"
  value       = google_cloudfunctions2_function.get_results.name
}

output "get_results_function_url" {
  description = "HTTP trigger URL for the results function"
  value       = google_cloudfunctions2_function.get_results.service_config[0].uri
  sensitive   = false
}

# Firestore Information
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.voting_database.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.voting_database.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.voting_database.type
}

# Service Account Information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_unique_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.unique_id
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

# API Testing Information
output "curl_test_commands" {
  description = "Example curl commands for testing the API endpoints"
  value = {
    submit_vote = "curl -X POST '${google_cloudfunctions2_function.submit_vote.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"topicId\": \"test-topic\", \"option\": \"option-a\", \"userId\": \"test-user-123\"}'"
    get_results = "curl '${google_cloudfunctions2_function.get_results.service_config[0].uri}?topicId=test-topic'"
  }
}

# Web Interface Template
output "web_interface_template" {
  description = "HTML template for a simple web interface to test the voting system"
  value = templatefile("${path.module}/templates/voting-interface.html", {
    submit_url  = google_cloudfunctions2_function.submit_vote.service_config[0].uri
    results_url = google_cloudfunctions2_function.get_results.service_config[0].uri
  })
  sensitive = false
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cloud_functions = {
      submit_vote_function = {
        name     = google_cloudfunctions2_function.submit_vote.name
        url      = google_cloudfunctions2_function.submit_vote.service_config[0].uri
        runtime  = var.functions_runtime
        memory   = "${var.functions_memory}Mi"
        timeout  = "${var.functions_timeout}s"
      }
      get_results_function = {
        name     = google_cloudfunctions2_function.get_results.name
        url      = google_cloudfunctions2_function.get_results.service_config[0].uri
        runtime  = var.functions_runtime
        memory   = "${var.functions_memory}Mi"
        timeout  = "${var.functions_timeout}s"
      }
    }
    firestore = {
      database_name = google_firestore_database.voting_database.name
      location      = google_firestore_database.voting_database.location_id
      type          = google_firestore_database.voting_database.type
    }
    storage = {
      bucket_name = google_storage_bucket.function_source.name
    }
    service_account = {
      email = google_service_account.function_service_account.email
    }
  }
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD) for typical usage"
  value = {
    cloud_functions = {
      description = "Based on 10,000 invocations per month, 256MB memory, 1s average execution time"
      estimated_cost = "$0.50 - $2.00"
    }
    firestore = {
      description = "Based on 50,000 document reads/writes per month, 1GB storage"
      estimated_cost = "$1.00 - $3.00"
    }
    cloud_storage = {
      description = "Based on storing function source code (minimal usage)"
      estimated_cost = "$0.01 - $0.05"
    }
    total_estimated = "$1.51 - $5.05"
    note = "Actual costs may vary based on usage patterns. Google Cloud offers generous free tiers for many services."
  }
}

# Monitoring and Logging URLs
output "monitoring_urls" {
  description = "URLs for monitoring and debugging the deployed resources"
  value = {
    cloud_functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    firestore_console      = "https://console.cloud.google.com/firestore/databases?project=${var.project_id}"
    cloud_logging          = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    cloud_monitoring       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the API endpoints using the provided curl commands",
    "2. Create a web interface using the provided HTML template",
    "3. Monitor function performance in Cloud Console",
    "4. Set up Cloud Monitoring alerts for error rates and latency",
    "5. Consider implementing authentication for production use",
    "6. Review and adjust function memory and timeout settings based on usage patterns"
  ]
}
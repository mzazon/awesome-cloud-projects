# Output values for the Habit Tracker infrastructure
# These outputs provide important information for verification and integration

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.habit_tracker.name
}

output "function_url" {
  description = "The HTTPS URL of the Cloud Function endpoint for API calls"
  value       = google_cloudfunctions_function.habit_tracker.https_trigger_url
  sensitive   = false
}

output "function_status" {
  description = "The current status of the Cloud Function"
  value       = google_cloudfunctions_function.habit_tracker.status
}

output "firestore_database_name" {
  description = "The name of the Firestore database"
  value       = google_firestore_database.habit_tracker_db.name
}

output "firestore_location" {
  description = "The location of the Firestore database"
  value       = google_firestore_database.habit_tracker_db.location_id
}

output "firestore_collection_name" {
  description = "The Firestore collection name used by the application"
  value       = local.firestore_collection
}

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "service_account_email" {
  description = "The email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "random_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

output "api_endpoints" {
  description = "Available API endpoints and their usage"
  value = {
    base_url = google_cloudfunctions_function.habit_tracker.https_trigger_url
    endpoints = {
      create_habit = {
        method      = "POST"
        url         = google_cloudfunctions_function.habit_tracker.https_trigger_url
        description = "Create a new habit"
        example_body = jsonencode({
          name        = "Daily Exercise"
          description = "30 minutes of physical activity"
          completed   = false
        })
      }
      get_habits = {
        method      = "GET"
        url         = google_cloudfunctions_function.habit_tracker.https_trigger_url
        description = "Retrieve all habits"
      }
      get_habit = {
        method      = "GET"
        url         = "${google_cloudfunctions_function.habit_tracker.https_trigger_url}?id=HABIT_ID"
        description = "Retrieve a specific habit by ID"
      }
      update_habit = {
        method      = "PUT"
        url         = "${google_cloudfunctions_function.habit_tracker.https_trigger_url}?id=HABIT_ID"
        description = "Update an existing habit"
        example_body = jsonencode({
          completed = true
        })
      }
      delete_habit = {
        method      = "DELETE"
        url         = "${google_cloudfunctions_function.habit_tracker.https_trigger_url}?id=HABIT_ID"
        description = "Delete a habit"
      }
    }
  }
}

output "curl_examples" {
  description = "Example curl commands for testing the API"
  value = {
    create_habit = "curl -X POST '${google_cloudfunctions_function.habit_tracker.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"name\":\"Daily Exercise\",\"description\":\"30 minutes of activity\",\"completed\":false}'"
    get_habits   = "curl -X GET '${google_cloudfunctions_function.habit_tracker.https_trigger_url}'"
    update_habit = "curl -X PUT '${google_cloudfunctions_function.habit_tracker.https_trigger_url}?id=HABIT_ID' -H 'Content-Type: application/json' -d '{\"completed\":true}'"
    delete_habit = "curl -X DELETE '${google_cloudfunctions_function.habit_tracker.https_trigger_url}?id=HABIT_ID'"
  }
}

output "monitoring_urls" {
  description = "Google Cloud Console URLs for monitoring and management"
  value = {
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.habit_tracker.name}?project=${var.project_id}"
    firestore      = "https://console.cloud.google.com/firestore/data?project=${var.project_id}"
    logs           = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions_function.habit_tracker.name}%22?project=${var.project_id}"
    metrics        = "https://console.cloud.google.com/monitoring/dashboards-list?project=${var.project_id}"
  }
}

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Based on Google Cloud pricing as of 2025"
    cloud_functions = {
      invocations = "First 2 million invocations per month are free"
      compute_time = "First 400,000 GB-seconds per month are free"
      estimate = "$0.00 - $0.05 per month for typical usage"
    }
    firestore = {
      storage = "First 1 GB per month is free"
      operations = "50,000 reads, 20,000 writes, 20,000 deletes per day are free"
      estimate = "$0.00 - $0.02 per month for typical usage"
    }
    cloud_storage = {
      storage = "5 GB per month is free for regional storage"
      operations = "5,000 Class A operations per month are free"
      estimate = "$0.00 per month for function source storage"
    }
    total_estimate = "$0.00 - $0.07 per month (likely free tier coverage)"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the API endpoints using the provided curl examples",
    "View function logs in the Google Cloud Console",
    "Monitor function performance and usage metrics",
    "Configure Firestore security rules for production use",
    "Set up monitoring alerts for errors and performance",
    "Consider adding authentication for production deployment"
  ]
}
# Output values for BMI Calculator API Infrastructure
# This file defines the output values that will be displayed after deployment

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.bmi_calculator.name
}

output "function_url" {
  description = "The HTTP trigger URL for the BMI Calculator Cloud Function"
  value       = google_cloudfunctions2_function.bmi_calculator.service_config[0].uri
  sensitive   = false
}

output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for calculation history"
  value       = google_storage_bucket.bmi_history.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.bmi_history.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.bmi_history.self_link
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for calculation events"
  value       = google_pubsub_topic.calculation_events.name
}

output "monitoring_alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy for function errors"
  value       = google_monitoring_alert_policy.function_error_rate.display_name
}

# Useful information for testing and integration
output "curl_test_command" {
  description = "Sample curl command to test the BMI Calculator API"
  value = format(
    "curl -X POST %s -H 'Content-Type: application/json' -d '{\"height\": 1.75, \"weight\": 70}' | python3 -m json.tool",
    google_cloudfunctions2_function.bmi_calculator.service_config[0].uri
  )
}

output "api_documentation" {
  description = "API documentation and usage information"
  value = {
    endpoint = google_cloudfunctions2_function.bmi_calculator.service_config[0].uri
    method   = "POST"
    headers = {
      "Content-Type" = "application/json"
    }
    body_format = {
      height = "Height in meters (float)"
      weight = "Weight in kilograms (float)"
    }
    response_format = {
      timestamp = "ISO 8601 timestamp"
      height    = "Input height in meters"
      weight    = "Input weight in kilograms"
      bmi       = "Calculated BMI value (rounded to 2 decimal places)"
      category  = "BMI category (Underweight/Normal weight/Overweight/Obese)"
    }
    example_request = {
      height = 1.75
      weight = 70
    }
    example_response = {
      timestamp = "2024-01-01T12:00:00.000000"
      height    = 1.75
      weight    = 70
      bmi       = 22.86
      category  = "Normal weight"
    }
  }
}

# Resource information for monitoring and management
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    cloud_function = {
      name           = google_cloudfunctions2_function.bmi_calculator.name
      runtime        = var.function_runtime
      memory         = "${var.function_memory}M"
      timeout        = "${var.function_timeout}s"
      location       = var.region
      trigger_type   = "HTTP"
      authenticated  = !var.allow_unauthenticated
    }
    storage_bucket = {
      name           = google_storage_bucket.bmi_history.name
      location       = var.region
      storage_class  = var.storage_class
      versioning     = true
      uniform_access = true
    }
    service_account = {
      email = google_service_account.function_sa.email
      name  = google_service_account.function_sa.name
    }
    pubsub_topic = {
      name = google_pubsub_topic.calculation_events.name
    }
    monitoring = {
      alert_policy = google_monitoring_alert_policy.function_error_rate.display_name
    }
  }
}

# Cost estimation information
output "cost_estimate" {
  description = "Estimated monthly costs for typical usage"
  value = {
    cloud_functions = {
      description = "Based on 1000 requests/month, 256MB memory, 1s avg duration"
      free_tier   = "2M requests, 400,000 GB-seconds, 200,000 GHz-seconds per month"
      estimate    = "~$0.00 (within free tier)"
    }
    cloud_storage = {
      description = "Based on 1GB stored data"
      free_tier   = "5GB storage per month"
      estimate    = "~$0.00 (within free tier)"
    }
    cloud_monitoring = {
      description = "Basic monitoring and alerting"
      free_tier   = "First 150MB of logs per month"
      estimate    = "~$0.00 (within free tier)"
    }
    pubsub = {
      description = "Based on 1000 messages/month"
      free_tier   = "10GB per month"
      estimate    = "~$0.00 (within free tier)"
    }
    total_estimate = "~$0.00/month for typical development usage (within GCP free tier)"
  }
}

# Security and compliance information
output "security_summary" {
  description = "Security configuration summary"
  value = {
    iam = {
      function_service_account = google_service_account.function_sa.email
      storage_permissions      = "roles/storage.objectCreator"
      public_access           = var.allow_unauthenticated
    }
    storage = {
      uniform_bucket_level_access = true
      versioning_enabled         = true
      cors_enabled              = true
      lifecycle_rules_enabled   = length(var.bucket_lifecycle_rules) > 0
    }
    networking = {
      function_ingress = "ALLOW_ALL"
      vpc_egress      = "PRIVATE_RANGES_ONLY"
    }
    monitoring = {
      error_alerting = true
      logs_retention = "30 days (default)"
    }
  }
}

# Cleanup information
output "cleanup_commands" {
  description = "Commands to clean up resources manually if needed"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "gcloud functions delete ${google_cloudfunctions2_function.bmi_calculator.name} --region=${var.region} --quiet",
      "gsutil -m rm -r gs://${google_storage_bucket.bmi_history.name}",
      "gcloud iam service-accounts delete ${google_service_account.function_sa.email} --quiet",
      "gcloud pubsub topics delete ${google_pubsub_topic.calculation_events.name}",
      "gcloud alpha monitoring policies delete ${google_monitoring_alert_policy.function_error_rate.name} --quiet"
    ]
  }
}
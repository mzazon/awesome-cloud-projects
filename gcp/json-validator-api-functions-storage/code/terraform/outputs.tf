# Output values for GCP JSON Validator API infrastructure
# These outputs provide important information for using and monitoring the deployed resources

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.json_validator.name
}

output "function_url" {
  description = "HTTPS URL of the JSON validator API endpoint"
  value       = google_cloudfunctions2_function.json_validator.service_config[0].uri
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.json_validator.location
}

output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for JSON files"
  value       = google_storage_bucket.json_files.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.json_files.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.json_files.self_link
}

output "project_id" {
  description = "GCP Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# API Testing Information
output "test_endpoints" {
  description = "Information about API endpoints for testing"
  value = {
    health_check = "${google_cloudfunctions2_function.json_validator.service_config[0].uri}"
    json_validation = {
      url    = "${google_cloudfunctions2_function.json_validator.service_config[0].uri}"
      method = "POST"
      headers = {
        "Content-Type" = "application/json"
      }
    }
    storage_validation = {
      url_pattern = "${google_cloudfunctions2_function.json_validator.service_config[0].uri}?bucket=${google_storage_bucket.json_files.name}&file=FILENAME"
      method      = "GET"
    }
  }
}

# Sample Test Commands
output "sample_test_commands" {
  description = "Sample commands for testing the deployed API"
  value = {
    health_check = "curl -X GET '${google_cloudfunctions2_function.json_validator.service_config[0].uri}'"
    
    validate_json = "curl -X POST '${google_cloudfunctions2_function.json_validator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"test\": \"data\"}'"
    
    validate_invalid_json = "curl -X POST '${google_cloudfunctions2_function.json_validator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"test\": \"data\"'"
    
    validate_storage_file = "curl -X GET '${google_cloudfunctions2_function.json_validator.service_config[0].uri}?bucket=${google_storage_bucket.json_files.name}&file=samples/valid-sample.json'"
    
    validate_invalid_storage_file = "curl -X GET '${google_cloudfunctions2_function.json_validator.service_config[0].uri}?bucket=${google_storage_bucket.json_files.name}&file=samples/invalid-sample.json'"
  }
}

# Sample Files Information
output "sample_files" {
  description = "Information about sample files created for testing"
  value = {
    valid_json = {
      name = google_storage_bucket_object.sample_valid_json.name
      url  = "gs://${google_storage_bucket.json_files.name}/${google_storage_bucket_object.sample_valid_json.name}"
    }
    invalid_json = {
      name = google_storage_bucket_object.sample_invalid_json.name
      url  = "gs://${google_storage_bucket.json_files.name}/${google_storage_bucket_object.sample_invalid_json.name}"
    }
  }
}

# Cloud Console URLs
output "console_urls" {
  description = "Google Cloud Console URLs for managing resources"
  value = {
    function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.json_validator.name}?project=${var.project_id}"
    
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.json_files.name}?project=${var.project_id}"
    
    logs = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.json_validator.name}%22?project=${var.project_id}"
    
    monitoring = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
    
    service_account = "https://console.cloud.google.com/iam-admin/serviceaccounts/details/${google_service_account.function_sa.unique_id}?project=${var.project_id}"
  }
}

# Monitoring Information
output "monitoring_info" {
  description = "Information about monitoring and alerting setup"
  value = {
    dashboard_available = true
    alerting_enabled    = var.notification_email != ""
    log_retention       = "30 days (default)"
    metrics_available = [
      "cloudfunctions.googleapis.com/function/executions",
      "cloudfunctions.googleapis.com/function/execution_times",
      "cloudfunctions.googleapis.com/function/memory_utilization",
      "storage.googleapis.com/storage/object_count"
    ]
  }
}

# Cost Estimation
output "estimated_costs" {
  description = "Estimated monthly costs for typical usage patterns"
  value = {
    disclaimer = "Costs are estimates and may vary based on actual usage, region, and pricing changes"
    
    function_free_tier = {
      invocations = "2M requests/month"
      compute_time = "400K GB-seconds/month"
      networking = "5GB egress/month"
    }
    
    storage_free_tier = {
      storage = "5GB/month"
      class_a_operations = "20K operations/month"
      class_b_operations = "50K operations/month"
    }
    
    typical_usage = {
      "1K requests/month" = "$0.00 (within free tier)"
      "100K requests/month" = "$0.00-$0.10"
      "1M requests/month" = "$0.40-$2.00"
    }
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    cloud_function = {
      name         = google_cloudfunctions2_function.json_validator.name
      runtime      = "python311"
      memory       = "${var.function_memory}M"
      timeout      = "${var.function_timeout}s"
      max_instances = var.max_instances
      min_instances = var.min_instances
    }
    
    storage_bucket = {
      name           = google_storage_bucket.json_files.name
      location       = google_storage_bucket.json_files.location
      storage_class  = google_storage_bucket.json_files.storage_class
      versioning     = var.enable_versioning
      public_access  = var.enable_public_access
    }
    
    service_account = {
      email = google_service_account.function_sa.email
      roles = [
        "roles/storage.objectAdmin",
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter"
      ]
    }
    
    sample_files = {
      valid_json   = google_storage_bucket_object.sample_valid_json.name
      invalid_json = google_storage_bucket_object.sample_invalid_json.name
    }
  }
}
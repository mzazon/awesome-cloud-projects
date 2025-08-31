# Outputs for Website Screenshot API with Cloud Functions and Storage
# These outputs provide important information for using and integrating with the deployed infrastructure

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.screenshot_generator.name
}

output "function_url" {
  description = "HTTP trigger URL for the screenshot generation function"
  value       = google_cloudfunctions2_function.screenshot_generator.service_config[0].uri
}

output "function_status" {
  description = "Current status of the Cloud Function"
  value       = google_cloudfunctions2_function.screenshot_generator.state
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for storing screenshots"
  value       = google_storage_bucket.screenshots.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.screenshots.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.screenshots.self_link
}

output "function_service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_source_bucket" {
  description = "Name of the bucket containing the function source code"
  value       = google_storage_bucket.function_source.name
}

# API Usage Examples
output "api_usage_examples" {
  description = "Examples of how to use the screenshot API"
  value = {
    curl_post = "curl -X POST '${google_cloudfunctions2_function.screenshot_generator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"url\": \"https://www.example.com\"}'"
    curl_get  = "curl '${google_cloudfunctions2_function.screenshot_generator.service_config[0].uri}?url=https://www.example.com'"
    
    javascript = <<-EOF
// JavaScript fetch API example
const response = await fetch('${google_cloudfunctions2_function.screenshot_generator.service_config[0].uri}', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    url: 'https://www.example.com'
  })
});

const result = await response.json();
console.log('Screenshot URL:', result.screenshotUrl);
EOF
    
    python = <<-EOF
# Python requests example
import requests

response = requests.post('${google_cloudfunctions2_function.screenshot_generator.service_config[0].uri}', 
                        json={'url': 'https://www.example.com'})
result = response.json()
print(f"Screenshot URL: {result['screenshotUrl']}")
EOF
  }
}

# Resource Information
output "resource_info" {
  description = "Information about deployed resources"
  value = {
    function_memory_mb = var.function_memory
    function_timeout_s = var.function_timeout
    storage_class     = var.storage_class
    bucket_location   = google_storage_bucket.screenshots.location
    public_access     = var.enable_public_access
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated costs for the deployed resources"
  value = {
    function_cost_per_invocation = "$0.0000004 per invocation"
    function_cost_per_gb_second  = "$0.0000025 per GB-second"
    storage_cost_per_gb_month    = "$0.020 per GB per month (STANDARD class)"
    network_cost_per_gb          = "$0.12 per GB egress to internet"
    note                         = "Actual costs depend on usage patterns and data transfer"
  }
}

# Monitoring and Logging
output "monitoring_links" {
  description = "Links to monitoring and logging resources"
  value = {
    function_logs    = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.screenshot_generator.name}?project=${var.project_id}&tab=logs"
    function_metrics = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.screenshot_generator.name}?project=${var.project_id}&tab=metrics"
    storage_browser  = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.screenshots.name}?project=${var.project_id}"
    cloud_console    = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
  }
}

# Security Information
output "security_info" {
  description = "Security configuration details"
  value = {
    function_service_account = google_service_account.function_sa.email
    public_function_access   = "Enabled - function is publicly accessible"
    public_storage_access    = var.enable_public_access ? "Enabled - screenshots are publicly readable" : "Disabled - private access only"
    https_only              = "Enabled - all traffic uses HTTPS"
    cors_origins            = var.cors_origins
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_function = "curl '${google_cloudfunctions2_function.screenshot_generator.service_config[0].uri}?url=https://www.google.com'"
    list_buckets  = "gcloud storage ls --project=${var.project_id}"
    function_info = "gcloud functions describe ${google_cloudfunctions2_function.screenshot_generator.name} --region=${var.region} --project=${var.project_id} --gen2"
  }
}

# Cleanup Information
output "cleanup_info" {
  description = "Information about resource cleanup"
  value = {
    terraform_destroy = "Run 'terraform destroy' to remove all resources"
    manual_cleanup    = "Some resources may require manual cleanup if deletion protection is enabled"
    billing_stop      = "Resources will stop incurring charges immediately after deletion"
    data_retention    = "Screenshot data will be permanently deleted when the storage bucket is removed"
  }
}
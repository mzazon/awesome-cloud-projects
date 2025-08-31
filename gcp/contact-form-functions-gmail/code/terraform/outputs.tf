# Output values for GCP Contact Form with Cloud Functions and Gmail API
# These outputs provide important information about the deployed infrastructure

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

# Cloud Function Information
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.contact_form_handler.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function (use this in your contact form)"
  value       = google_cloudfunctions2_function.contact_form_handler.service_config[0].uri
  sensitive   = false
}

output "function_id" {
  description = "Full resource ID of the Cloud Function"
  value       = google_cloudfunctions2_function.contact_form_handler.id
}

output "function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.contact_form_handler.state
}

output "function_environment" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.contact_form_handler.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function (MB)"
  value       = "${google_cloudfunctions2_function.contact_form_handler.service_config[0].available_memory}MB"
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function (seconds)"
  value       = "${google_cloudfunctions2_function.contact_form_handler.service_config[0].timeout_seconds}s"
}

# Storage Information
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = local.bucket_name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = "gs://${local.bucket_name}"
}

output "source_archive_object" {
  description = "Name of the source code archive in Cloud Storage"
  value       = google_storage_bucket_object.function_source.name
}

# API Services
output "enabled_apis" {
  description = "List of GCP APIs that were enabled"
  value       = var.enable_apis ? [for api in google_project_service.required_apis : api.service] : []
}

# IAM Information
output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "Service account ID used by the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

# Security Configuration
output "allow_unauthenticated" {
  description = "Whether unauthenticated access is allowed to the function"
  value       = var.allow_unauthenticated
}

output "iam_policy_applied" {
  description = "Whether IAM policy for unauthenticated access was applied"
  value       = var.allow_unauthenticated ? "yes" : "no"
}

# Monitoring and Logging
output "function_logs_command" {
  description = "gcloud command to view function logs"
  value       = "gcloud functions logs read ${var.function_name} --gen2 --region=${var.region} --project=${var.project_id}"
}

output "cloud_console_function_url" {
  description = "URL to view the Cloud Function in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${var.function_name}?project=${var.project_id}"
}

output "cloud_console_logs_url" {
  description = "URL to view function logs in Google Cloud Console"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${var.function_name}%22?project=${var.project_id}"
}

# Configuration Information
output "gmail_recipient_email" {
  description = "Email address that will receive contact form submissions"
  value       = var.gmail_recipient_email
  sensitive   = true
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "labels" {
  description = "Labels applied to resources"
  value       = local.common_labels
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

# Testing Information
output "test_curl_command" {
  description = "Sample curl command to test the contact form function"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.contact_form_handler.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "Test User",
        "email": "test@example.com",
        "subject": "Test Contact Form",
        "message": "This is a test message from the contact form."
      }'
  EOT
}

output "html_form_integration" {
  description = "JavaScript fetch example for HTML form integration"
  value = <<-EOT
    fetch('${google_cloudfunctions2_function.contact_form_handler.service_config[0].uri}', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: 'User Name',
        email: 'user@example.com',
        subject: 'Contact Subject',
        message: 'Contact message content'
      })
    })
    .then(response => response.json())
    .then(data => console.log('Success:', data))
    .catch(error => console.error('Error:', error));
  EOT
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for typical contact form usage"
  value       = "Approximately $0.00 - $0.20 USD per month for typical usage (within Cloud Functions free tier)"
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    1. Verify deployment: Test the function URL with the provided curl command
    2. Configure Gmail: Ensure Gmail API credentials are properly set up
    3. Update HTML form: Use the function URL in your website's contact form
    4. Monitor logs: Use the provided gcloud command or Console URL to monitor function execution
    5. Test email delivery: Submit a test form and verify email receipt
    6. Set up monitoring: Consider setting up Cloud Monitoring alerts for function errors
  EOT
}
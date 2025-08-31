# Output values for the Solar Assessment infrastructure
# These outputs provide important information for testing, monitoring, and integration

# Project and environment information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Cloud Storage bucket information
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for uploading property CSV files"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for property CSV files"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket containing solar assessment results"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the output bucket for assessment results"
  value       = google_storage_bucket.output_bucket.url
}

# Cloud Function information
output "function_name" {
  description = "Name of the Cloud Function processing solar assessments"
  value       = google_cloudfunctions2_function.solar_processor.name
}

output "function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.solar_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = local.function_service_account_email
}

# API configuration
output "solar_api_key_name" {
  description = "Name of the Google Maps Platform API key for Solar API access"
  value       = google_apikeys_key.solar_api_key.name
}

# Security note: API key value is marked as sensitive
output "solar_api_key_id" {
  description = "ID of the Solar API key (key value is stored securely in function environment)"
  value       = google_apikeys_key.solar_api_key.uid
}

# Monitoring and logging information
output "storage_notification_topic" {
  description = "Pub/Sub topic for Cloud Storage notifications (if monitoring enabled)"
  value       = var.enable_monitoring ? google_pubsub_topic.storage_notifications[0].name : null
}

output "function_log_sink" {
  description = "Name of the log sink for function logs (if monitoring enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.function_logs[0].name : null
}

output "monitoring_alert_policy" {
  description = "Name of the monitoring alert policy for function errors (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].name : null
}

# Resource identifiers for reference
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Deployment validation information
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this solution"
  value       = local.required_apis
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using the deployed solar assessment solution"
  value = <<-EOT
    Solar Assessment Solution Deployed Successfully!
    
    To use this solution:
    
    1. Upload CSV files with property data to the input bucket:
       gsutil cp your-properties.csv gs://${google_storage_bucket.input_bucket.name}/
       
    2. CSV files should contain these columns:
       - address: Property address
       - latitude: Property latitude coordinates
       - longitude: Property longitude coordinates
       
    3. The Cloud Function will automatically process uploaded files and save results to:
       gs://${google_storage_bucket.output_bucket.name}/
       
    4. Download results:
       gsutil cp gs://${google_storage_bucket.output_bucket.name}/your-properties_solar_assessment_*.csv ./
       
    5. Monitor function execution:
       gcloud functions logs read ${google_cloudfunctions2_function.solar_processor.name} --region ${var.region}
       
    For more information, see the Cloud Function at:
    ${google_cloudfunctions2_function.solar_processor.service_config[0].uri}
  EOT
}

# Cost estimation information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for typical usage patterns"
  value = <<-EOT
    Estimated Monthly Costs (approximate):
    
    - Cloud Storage (both buckets): $0.02-0.10/GB stored
    - Cloud Functions: $0.40 per 1M invocations + $0.0000025 per GB-second
    - Solar API: $0.01-0.02 per property assessment
    - Monitoring and Logging: $0.50-2.00 per GB of logs
    
    Example for 1,000 property assessments per month:
    - Solar API: $10-20
    - Cloud Functions: $1-3
    - Storage: $0.10-0.50
    - Total: ~$11-24 per month
    
    Note: Costs vary by region and actual usage patterns.
    See Google Cloud Pricing Calculator for detailed estimates.
  EOT
}

# Integration endpoints for external systems
output "webhook_trigger_url" {
  description = "Cloud Storage trigger configuration for webhook integration"
  value = {
    bucket_name = google_storage_bucket.input_bucket.name
    event_type  = "google.cloud.storage.object.v1.finalized"
    filter      = "CSV files only"
  }
}

# Backup and disaster recovery information
output "backup_configuration" {
  description = "Backup and versioning configuration"
  value = {
    versioning_enabled     = var.enable_versioning
    lifecycle_age_days     = var.bucket_lifecycle_age_days
    deletion_protection    = var.deletion_protection
    input_bucket_location  = google_storage_bucket.input_bucket.location
    output_bucket_location = google_storage_bucket.output_bucket.location
  }
}

# Development and testing information
output "testing_commands" {
  description = "Commands for testing the deployed solution"
  value = <<-EOT
    Testing Commands:
    
    # Create sample CSV file
    echo "address,latitude,longitude" > test-properties.csv
    echo "1600 Amphitheatre Pkwy Mountain View CA,37.4220041,-122.0862515" >> test-properties.csv
    
    # Upload test file
    gsutil cp test-properties.csv gs://${google_storage_bucket.input_bucket.name}/
    
    # Monitor processing
    gcloud functions logs read ${google_cloudfunctions2_function.solar_processor.name} --region ${var.region} --limit 10
    
    # Check results
    gsutil ls gs://${google_storage_bucket.output_bucket.name}/
    
    # Download results
    gsutil cp gs://${google_storage_bucket.output_bucket.name}/test-properties_solar_assessment_*.csv ./results.csv
  EOT
}
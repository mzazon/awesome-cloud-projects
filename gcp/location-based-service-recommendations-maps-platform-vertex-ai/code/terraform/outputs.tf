# Output Values
# This file defines the output values that will be displayed after successful deployment

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "service_url" {
  description = "URL of the deployed Cloud Run service for the recommendation API"
  value       = google_cloud_run_v2_service.location_recommender.uri
  sensitive   = false
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.location_recommender.name
}

output "service_account_email" {
  description = "Email address of the service account used by the recommendation service"
  value       = google_service_account.location_ai_service.email
}

output "firestore_database_name" {
  description = "Name of the Firestore database for storing user preferences and recommendations"
  value       = google_firestore_database.recommendations_db.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.recommendations_db.location_id
}

output "maps_api_key_name" {
  description = "Name of the Google Maps Platform API key (use with caution)"
  value       = google_apikeys_key.maps_api_key.name
}

output "maps_api_key_id" {
  description = "ID of the Google Maps Platform API key"
  value       = google_apikeys_key.maps_api_key.id
}

output "maps_api_key_value" {
  description = "The actual API key value for Google Maps Platform (sensitive)"
  value       = google_apikeys_key.maps_api_key.key_string
  sensitive   = true
}

output "vpc_connector_name" {
  description = "Name of the VPC connector (if enabled)"
  value       = var.enable_vpc_connector ? google_vpc_access_connector.cloud_run_connector[0].name : null
}

output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled for this deployment"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

output "random_suffix" {
  description = "Random suffix used for resource naming to ensure uniqueness"
  value       = random_id.suffix.hex
}

output "deployment_labels" {
  description = "Common labels applied to all resources in this deployment"
  value       = local.common_labels
}

# Configuration Information
output "ai_configuration" {
  description = "Configuration details for Vertex AI integration"
  value = {
    model_name           = var.ai_model_name
    maps_grounding_enabled = var.enable_maps_grounding
    region              = var.region
  }
}

output "service_configuration" {
  description = "Configuration details for the Cloud Run service"
  value = {
    min_instances = var.min_instances
    max_instances = var.max_instances
    memory_limit  = var.memory_limit
    cpu_limit     = var.cpu_limit
    container_port = var.container_port
  }
}

# Testing and Validation Information
output "health_check_url" {
  description = "URL to check the health of the recommendation service"
  value       = "${google_cloud_run_v2_service.location_recommender.uri}/"
}

output "recommendation_endpoint" {
  description = "URL of the recommendation API endpoint"
  value       = "${google_cloud_run_v2_service.location_recommender.uri}/recommend"
}

output "sample_curl_command" {
  description = "Sample curl command to test the recommendation API"
  value = <<-EOT
curl -X POST "${google_cloud_run_v2_service.location_recommender.uri}/recommend" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test-user",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "preferences": {
      "category": "restaurant",
      "cuisine": "italian"
    },
    "radius": 2000
  }'
  EOT
}

# Resource Management Information
output "cleanup_commands" {
  description = "Commands to manually clean up resources if needed"
  value = {
    delete_service    = "gcloud run services delete ${google_cloud_run_v2_service.location_recommender.name} --region=${var.region} --project=${var.project_id}"
    delete_database   = "gcloud firestore databases delete ${google_firestore_database.recommendations_db.name} --project=${var.project_id}"
    delete_api_key    = "gcloud services api-keys delete ${google_apikeys_key.maps_api_key.id} --project=${var.project_id}"
    delete_sa         = "gcloud iam service-accounts delete ${google_service_account.location_ai_service.email} --project=${var.project_id}"
  }
}

# Cost Management Information  
output "cost_monitoring_info" {
  description = "Information about monitoring costs for this deployment"
  value = {
    cloud_run_pricing   = "https://cloud.google.com/run/pricing"
    maps_platform_pricing = "https://developers.google.com/maps/billing-and-pricing/pricing"
    vertex_ai_pricing   = "https://cloud.google.com/vertex-ai/pricing"
    firestore_pricing   = "https://cloud.google.com/firestore/pricing"
    billing_dashboard   = "https://console.cloud.google.com/billing"
  }
}

# Development and Integration Information
output "development_info" {
  description = "Information useful for development and integration"
  value = {
    firestore_console_url = "https://console.cloud.google.com/firestore/databases/${google_firestore_database.recommendations_db.name}/data"
    cloud_run_console_url = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.location_recommender.name}"
    logs_url             = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${google_cloud_run_v2_service.location_recommender.name}%22"
    monitoring_url       = "https://console.cloud.google.com/monitoring"
  }
}

# Security Information
output "security_notes" {
  description = "Important security considerations for this deployment"
  value = {
    api_key_security    = "Maps API key is restricted to specific APIs but allows all referrers. Restrict in production."
    service_access      = "Cloud Run service allows public access. Implement authentication for production."
    firestore_security  = "Firestore uses service account authentication. Implement security rules for client access."
    audit_logging       = var.enable_audit_logs ? "Audit logging is enabled" : "Audit logging is disabled"
  }
}
# Project and region information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

# Cloud Run service information
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.product_catalog.name
}

output "cloud_run_service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.product_catalog.uri
}

output "cloud_run_service_status" {
  description = "Status of the Cloud Run service"
  value       = google_cloud_run_v2_service.product_catalog.terminal_condition
}

# API endpoints for testing
output "search_endpoint" {
  description = "Search API endpoint for testing"
  value       = "${google_cloud_run_v2_service.product_catalog.uri}/search?q=headphones&page_size=3"
}

output "recommendation_endpoint" {
  description = "Recommendation API endpoint for testing"
  value       = "${google_cloud_run_v2_service.product_catalog.uri}/recommend?product_id=prod-001&page_size=3"
}

output "health_check_endpoint" {
  description = "Health check endpoint"
  value       = "${google_cloud_run_v2_service.product_catalog.uri}/health"
}

# Vertex AI Search information
output "search_engine_id" {
  description = "ID of the Vertex AI Search engine"
  value       = google_discovery_engine_search_engine.product_search.engine_id
}

output "search_engine_name" {
  description = "Full name of the Vertex AI Search engine"
  value       = google_discovery_engine_search_engine.product_search.name
}

output "datastore_id" {
  description = "ID of the Vertex AI Search data store"
  value       = google_discovery_engine_data_store.product_datastore.data_store_id
}

output "datastore_name" {
  description = "Full name of the Vertex AI Search data store"
  value       = google_discovery_engine_data_store.product_datastore.name
}

# Storage information
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for product data"
  value       = google_storage_bucket.product_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.product_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.product_data.self_link
}

# Firestore information
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.product_database.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.product_database.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.product_database.type
}

# Service Account information
output "cloud_run_service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.email
}

output "cloud_run_service_account_id" {
  description = "ID of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.unique_id
}

# Container and build information
output "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.name
}

output "container_image_url" {
  description = "Full URL of the container image"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/${local.cloud_run_service}:latest"
}

# Resource identifiers with suffix
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

output "name_prefix" {
  description = "Name prefix used for resource naming"
  value       = local.name_prefix
}

# Testing commands
output "test_commands" {
  description = "Commands to test the deployed application"
  value = {
    health_check = "curl '${google_cloud_run_v2_service.product_catalog.uri}/health'"
    search_test  = "curl '${google_cloud_run_v2_service.product_catalog.uri}/search?q=wireless%20headphones&page_size=3'"
    recommend_test = "curl '${google_cloud_run_v2_service.product_catalog.uri}/recommend?product_id=prod-001&page_size=3'"
  }
}

# Console URLs for easy access
output "console_urls" {
  description = "Google Cloud Console URLs for easy access to resources"
  value = {
    cloud_run_service = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.product_catalog.name}/metrics?project=${var.project_id}"
    vertex_ai_search  = "https://console.cloud.google.com/ai/search?project=${var.project_id}"
    firestore        = "https://console.cloud.google.com/firestore/databases?project=${var.project_id}"
    storage_bucket   = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.product_data.name}?project=${var.project_id}"
    logs             = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${google_cloud_run_v2_service.product_catalog.name}%22?project=${var.project_id}"
  }
}

# API configuration for client applications
output "api_configuration" {
  description = "API configuration details for client applications"
  value = {
    base_url     = google_cloud_run_v2_service.product_catalog.uri
    endpoints = {
      health        = "/health"
      search        = "/search"
      recommendations = "/recommend"
    }
    parameters = {
      search = {
        q         = "Search query string (required)"
        page_size = "Number of results to return (optional, default: 10)"
      }
      recommendations = {
        product_id = "Product ID for recommendations (required)"
        page_size  = "Number of recommendations to return (optional, default: 5)"
      }
    }
  }
}

# Monitoring and logging
output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
}

output "application_logs_url" {
  description = "URL to view application logs"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${google_cloud_run_v2_service.product_catalog.name}%22?project=${var.project_id}"
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Costs depend on actual usage. Visit https://cloud.google.com/products/calculator for detailed cost estimation."
    cloud_run = "Pay-per-use: $0.00002400/vCPU-second, $0.00000250/GiB-second"
    vertex_ai_search = "Varies by search volume and data size"
    firestore = "Free tier: 1 GiB storage, 50,000 reads, 20,000 writes, 20,000 deletes per day"
    storage = "$0.020/GB/month for Standard storage in us-central1"
  }
}

# Security information
output "security_notes" {
  description = "Important security considerations"
  value = {
    service_account = "Dedicated service account with minimal required permissions"
    api_access = var.allow_unauthenticated ? "WARNING: API is publicly accessible" : "API requires authentication"
    data_encryption = "All data encrypted at rest and in transit by default"
    recommendations = [
      "Review and adjust IAM permissions as needed",
      "Consider enabling API authentication for production",
      "Monitor access logs for suspicious activity",
      "Implement rate limiting for production workloads"
    ]
  }
}

# Next steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the API endpoints using the provided test commands",
    "Access the Cloud Console URLs to explore the deployed resources",
    "Add more product data to improve search and recommendation quality",
    "Configure monitoring alerts for production workloads",
    "Implement authentication if required for your use case",
    "Consider setting up CI/CD pipelines for application updates"
  ]
}
# Storage outputs
output "knowledge_base_bucket_name" {
  description = "Name of the Cloud Storage bucket containing knowledge base documents"
  value       = google_storage_bucket.knowledge_base.name
}

output "knowledge_base_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.knowledge_base.url
}

output "dashboard_bucket_name" {
  description = "Name of the Cloud Storage bucket hosting the agent dashboard"
  value       = google_storage_bucket.dashboard.name
}

output "dashboard_url" {
  description = "Public URL for the agent dashboard"
  value       = "https://storage.googleapis.com/${google_storage_bucket.dashboard.name}/index.html"
}

# Vertex AI Search outputs
output "search_data_store_id" {
  description = "ID of the Vertex AI Search data store"
  value       = google_discovery_engine_data_store.knowledge_base.data_store_id
}

output "search_data_store_name" {
  description = "Full resource name of the Vertex AI Search data store"
  value       = google_discovery_engine_data_store.knowledge_base.name
}

output "search_engine_id" {
  description = "ID of the Vertex AI Search engine"
  value       = google_discovery_engine_search_engine.customer_service_app.engine_id
}

output "search_engine_name" {
  description = "Full resource name of the Vertex AI Search engine"
  value       = google_discovery_engine_search_engine.customer_service_app.name
}

# Cloud Run outputs
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = local.cloud_run_service_name
}

output "cloud_run_service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = try(data.google_cloud_run_service.customer_service_api.status[0].url, "Service not yet deployed")
}

output "cloud_run_service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.email
}

# API endpoints for testing
output "api_endpoints" {
  description = "Available API endpoints for testing"
  value = {
    health_check         = try("${data.google_cloud_run_service.customer_service_api.status[0].url}/health", "Service not yet deployed")
    search_knowledge_base = try("${data.google_cloud_run_service.customer_service_api.status[0].url}/search", "Service not yet deployed")
    analyze_conversation = try("${data.google_cloud_run_service.customer_service_api.status[0].url}/analyze-conversation", "Service not yet deployed")
  }
}

# Project and configuration outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Resource naming outputs for reference
output "resource_names" {
  description = "Names of all created resources for reference"
  value = {
    knowledge_base_bucket    = google_storage_bucket.knowledge_base.name
    dashboard_bucket        = google_storage_bucket.dashboard.name
    search_data_store       = google_discovery_engine_data_store.knowledge_base.data_store_id
    search_engine          = google_discovery_engine_search_engine.customer_service_app.engine_id
    cloud_run_service      = local.cloud_run_service_name
    service_account        = google_service_account.cloud_run_sa.account_id
  }
}

# Security and monitoring outputs
output "audit_logging_enabled" {
  description = "Whether audit logging is enabled"
  value       = var.enable_audit_logs
}

output "contact_center_ai_enabled" {
  description = "Whether Contact Center AI features are enabled"
  value       = var.enable_contact_center_ai
}

# Cost estimation outputs
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    note                = "Costs are approximate and depend on usage patterns"
    cloud_storage      = "~$1-5/month for knowledge base storage"
    vertex_ai_search   = "~$10-50/month depending on search volume"
    cloud_run         = "~$5-20/month depending on traffic"
    contact_center_ai = "~$0.50-2.00 per analyzed conversation"
    total_estimated   = "~$16-77/month plus conversation analysis costs"
  }
}

# Quick start commands
output "quick_start_commands" {
  description = "Commands to test the deployed solution"
  value = {
    test_health_check = try("curl ${data.google_cloud_run_service.customer_service_api.status[0].url}/health", "Service not yet deployed")
    test_search = try("curl -X POST ${data.google_cloud_run_service.customer_service_api.status[0].url}/search -H 'Content-Type: application/json' -d '{\"query\": \"How do I reset my password?\"}'", "Service not yet deployed")
    test_conversation_analysis = try("curl -X POST ${data.google_cloud_run_service.customer_service_api.status[0].url}/analyze-conversation -H 'Content-Type: application/json' -d '{\"conversation\": \"Customer says they cannot login to their account and need help\"}'", "Service not yet deployed")
  }
}

# Documentation links
output "documentation_links" {
  description = "Relevant documentation links for the implemented services"
  value = {
    vertex_ai_search      = "https://cloud.google.com/generative-ai-app-builder/docs/enterprise-search-introduction"
    contact_center_ai     = "https://cloud.google.com/solutions/contact-center-ai-platform"
    cloud_run            = "https://cloud.google.com/run/docs"
    cloud_storage        = "https://cloud.google.com/storage/docs"
    discovery_engine_api  = "https://cloud.google.com/generative-ai-app-builder/docs/reference/rest"
  }
}

# Next steps recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the API endpoints using the provided curl commands",
    "2. Access the agent dashboard at the provided URL",
    "3. Upload additional knowledge base documents to the Cloud Storage bucket",
    "4. Configure Contact Center AI for production conversation analysis",
    "5. Set up monitoring and alerting using Cloud Monitoring",
    "6. Review and adjust Cloud Run scaling parameters based on usage patterns",
    "7. Implement authentication and authorization for production use"
  ]
}
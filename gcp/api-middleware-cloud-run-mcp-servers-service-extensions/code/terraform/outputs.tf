# Outputs for API Middleware with Cloud Run MCP Servers and Service Extensions
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Project and Region Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# MCP Server URLs
output "mcp_server_urls" {
  description = "URLs for all deployed MCP servers"
  value = {
    content_analyzer  = google_cloud_run_service.content_analyzer.status[0].url
    request_router    = google_cloud_run_service.request_router.status[0].url
    response_enhancer = google_cloud_run_service.response_enhancer.status[0].url
  }
}

output "content_analyzer_url" {
  description = "URL for the Content Analyzer MCP server"
  value       = google_cloud_run_service.content_analyzer.status[0].url
}

output "request_router_url" {
  description = "URL for the Request Router MCP server"
  value       = google_cloud_run_service.request_router.status[0].url
}

output "response_enhancer_url" {
  description = "URL for the Response Enhancer MCP server"
  value       = google_cloud_run_service.response_enhancer.status[0].url
}

# Main Middleware Service
output "api_middleware_url" {
  description = "URL for the main API middleware service"
  value       = google_cloud_run_service.api_middleware.status[0].url
}

output "api_middleware_service_name" {
  description = "Name of the main API middleware Cloud Run service"
  value       = google_cloud_run_service.api_middleware.name
}

# Cloud Endpoints
output "endpoints_service_name" {
  description = "Name of the Cloud Endpoints service"
  value       = google_endpoints_service.api_gateway.service_name
}

output "endpoints_url" {
  description = "URL for the Cloud Endpoints API Gateway"
  value       = "https://${google_endpoints_service.api_gateway.service_name}"
}

# Service Account Information
output "service_account_email" {
  description = "Email of the service account used by Cloud Run services"
  value       = var.create_service_account ? google_service_account.mcp_service_account[0].email : "Default Compute Service Account"
}

output "service_account_name" {
  description = "Name of the service account used by Cloud Run services"
  value       = var.create_service_account ? google_service_account.mcp_service_account[0].name : "Default Compute Service Account"
}

# MCP Server Service Names
output "mcp_service_names" {
  description = "Names of all MCP server Cloud Run services"
  value = {
    content_analyzer  = google_cloud_run_service.content_analyzer.name
    request_router    = google_cloud_run_service.request_router.name
    response_enhancer = google_cloud_run_service.response_enhancer.name
  }
}

# Health Check URLs
output "health_check_urls" {
  description = "Health check URLs for all services"
  value = {
    content_analyzer  = "${google_cloud_run_service.content_analyzer.status[0].url}/health"
    request_router    = "${google_cloud_run_service.request_router.status[0].url}/health"
    response_enhancer = "${google_cloud_run_service.response_enhancer.status[0].url}/health"
    api_middleware    = "${google_cloud_run_service.api_middleware.status[0].url}/health"
  }
}

# MCP Server Endpoint URLs
output "mcp_server_endpoints" {
  description = "Specific endpoint URLs for MCP server functions"
  value = {
    content_analyzer = {
      analyze_endpoint = "${google_cloud_run_service.content_analyzer.status[0].url}/analyze"
      health_endpoint  = "${google_cloud_run_service.content_analyzer.status[0].url}/health"
    }
    request_router = {
      route_endpoint  = "${google_cloud_run_service.request_router.status[0].url}/route"
      health_endpoint = "${google_cloud_run_service.request_router.status[0].url}/health"
    }
    response_enhancer = {
      enhance_endpoint = "${google_cloud_run_service.response_enhancer.status[0].url}/enhance"
      health_endpoint  = "${google_cloud_run_service.response_enhancer.status[0].url}/health"
    }
  }
}

# Vertex AI Configuration
output "vertex_ai_config" {
  description = "Vertex AI configuration used by MCP servers"
  value = {
    location = var.vertex_ai_location
    model    = var.gemini_model
    project  = var.project_id
  }
}

# Testing Information
output "testing_commands" {
  description = "Example commands for testing the deployed infrastructure"
  value = {
    test_content_analyzer = "curl -X POST '${google_cloud_run_service.content_analyzer.status[0].url}/analyze' -H 'Content-Type: application/json' -d '{\"content\": \"Sample API content\", \"content_type\": \"application/json\"}'"
    test_request_router   = "curl -X POST '${google_cloud_run_service.request_router.status[0].url}/route' -H 'Content-Type: application/json' -d '{\"original_request\": {\"method\": \"GET\", \"path\": \"/test\"}, \"analysis_result\": {\"complexity\": \"simple\"}}'"
    test_response_enhancer = "curl -X POST '${google_cloud_run_service.response_enhancer.status[0].url}/enhance' -H 'Content-Type: application/json' -d '{\"original_response\": {\"data\": \"test\"}, \"routing_context\": {\"complexity\": \"simple\"}}'"
    test_api_middleware   = "curl -X GET '${google_cloud_run_service.api_middleware.status[0].url}/api/test?query=sample' -H 'Content-Type: application/json'"
    test_endpoints_gateway = "curl -X GET 'https://${google_endpoints_service.api_gateway.service_name}/api/test?query=sample' -H 'Content-Type: application/json'"
    test_health_checks    = "curl -X GET '${google_cloud_run_service.api_middleware.status[0].url}/health'"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    total_cloud_run_services = 4
    mcp_servers_deployed     = 3
    endpoints_configured     = true
    vertex_ai_enabled        = true
    service_account_created  = var.create_service_account
    environment             = var.environment
    architecture_pattern   = "Model Context Protocol (MCP) with AI-powered middleware"
  }
}

# Resource Names for Management
output "resource_names" {
  description = "Names of all created resources for management purposes"
  value = {
    cloud_run_services = {
      content_analyzer  = google_cloud_run_service.content_analyzer.name
      request_router    = google_cloud_run_service.request_router.name
      response_enhancer = google_cloud_run_service.response_enhancer.name
      api_middleware    = google_cloud_run_service.api_middleware.name
    }
    endpoints_service = google_endpoints_service.api_gateway.service_name
    service_account   = var.create_service_account ? google_service_account.mcp_service_account[0].account_id : null
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs in this deployment"
  value = {
    serverless_benefits = "Cloud Run services automatically scale to zero when not in use"
    vertex_ai_usage    = "Vertex AI charges are based on actual API calls made by MCP servers"
    monitoring_tip     = "Use Cloud Monitoring to track usage and optimize resource allocation"
    cleanup_command    = "Run 'terraform destroy' to remove all resources when testing is complete"
  }
}

# Security Information
output "security_notes" {
  description = "Important security information about the deployment"
  value = {
    authentication_status = var.mcp_server_config.allow_unauthenticated ? "Services allow unauthenticated access for demo purposes" : "Services require authentication"
    recommended_actions   = [
      "Consider enabling authentication for production deployments",
      "Review and restrict CORS policies based on your requirements",
      "Monitor service logs for unusual activity",
      "Regularly update container images for security patches"
    ]
    service_account_roles = var.service_account_roles
  }
}

# Monitoring and Logging
output "monitoring_information" {
  description = "Information about monitoring and logging setup"
  value = {
    cloud_logging_enabled   = "Automatic logging enabled for all Cloud Run services"
    cloud_monitoring_enabled = "Automatic metrics collection enabled"
    health_check_endpoints  = "All services expose /health endpoints for monitoring"
    recommended_dashboards  = [
      "Cloud Run Dashboard in Cloud Monitoring",
      "Vertex AI Usage Dashboard",
      "Cloud Endpoints API Dashboard"
    ]
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test all health check endpoints to verify service availability",
    "Deploy actual container images for each MCP server",
    "Configure production authentication and authorization",
    "Set up monitoring alerts and notifications",
    "Test the complete API middleware pipeline with sample requests",
    "Review and adjust resource limits based on actual usage patterns"
  ]
}
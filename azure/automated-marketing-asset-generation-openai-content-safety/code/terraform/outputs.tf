# Outputs for Azure Marketing Asset Generation Infrastructure
# These outputs provide essential information for validation, integration, and post-deployment configuration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group containing all marketing automation resources"
  value       = azurerm_resource_group.marketing_rg.name
}

output "resource_group_location" {
  description = "Azure region where all resources are deployed"
  value       = azurerm_resource_group.marketing_rg.location
}

output "resource_group_id" {
  description = "Full resource ID of the resource group"
  value       = azurerm_resource_group.marketing_rg.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for marketing assets"
  value       = azurerm_storage_account.marketing_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint URL for marketing asset storage"
  value       = azurerm_storage_account.marketing_storage.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Primary connection string for storage account access"
  value       = azurerm_storage_account.marketing_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for storage account authentication"
  value       = azurerm_storage_account.marketing_storage.primary_access_key
  sensitive   = true
}

output "marketing_containers" {
  description = "List of created blob containers for marketing workflow"
  value = {
    for container_key, container in azurerm_storage_container.marketing_containers : container_key => {
      name         = container.name
      access_type  = container.container_access_type
      url          = "${azurerm_storage_account.marketing_storage.primary_blob_endpoint}${container.name}"
    }
  }
}

# Azure OpenAI Service Outputs
output "openai_service_name" {
  description = "Name of the Azure OpenAI service for content generation"
  value       = azurerm_cognitive_account.openai_service.name
}

output "openai_service_endpoint" {
  description = "Endpoint URL for Azure OpenAI service API access"
  value       = azurerm_cognitive_account.openai_service.endpoint
}

output "openai_service_primary_key" {
  description = "Primary API key for Azure OpenAI service authentication"
  value       = azurerm_cognitive_account.openai_service.primary_access_key
  sensitive   = true
}

output "openai_service_secondary_key" {
  description = "Secondary API key for Azure OpenAI service authentication"
  value       = azurerm_cognitive_account.openai_service.secondary_access_key
  sensitive   = true
}

output "openai_model_deployments" {
  description = "Information about deployed OpenAI models for content generation"
  value = {
    gpt4 = {
      name     = azurerm_cognitive_deployment.gpt4_deployment.name
      model    = azurerm_cognitive_deployment.gpt4_deployment.model[0].name
      version  = azurerm_cognitive_deployment.gpt4_deployment.model[0].version
      capacity = azurerm_cognitive_deployment.gpt4_deployment.scale[0].capacity
    }
    dalle3 = {
      name     = azurerm_cognitive_deployment.dalle3_deployment.name
      model    = azurerm_cognitive_deployment.dalle3_deployment.model[0].name
      version  = azurerm_cognitive_deployment.dalle3_deployment.model[0].version
      capacity = azurerm_cognitive_deployment.dalle3_deployment.scale[0].capacity
    }
  }
}

# Content Safety Service Outputs
output "content_safety_service_name" {
  description = "Name of the Azure Content Safety service for content moderation"
  value       = azurerm_cognitive_account.content_safety.name
}

output "content_safety_endpoint" {
  description = "Endpoint URL for Azure Content Safety service API access"
  value       = azurerm_cognitive_account.content_safety.endpoint
}

output "content_safety_primary_key" {
  description = "Primary API key for Azure Content Safety service authentication"
  value       = azurerm_cognitive_account.content_safety.primary_access_key
  sensitive   = true
}

output "content_safety_secondary_key" {
  description = "Secondary API key for Azure Content Safety service authentication"
  value       = azurerm_cognitive_account.content_safety.secondary_access_key
  sensitive   = true
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Azure Function App for marketing automation orchestration"
  value       = azurerm_linux_function_app.marketing_function.name
}

output "function_app_url" {
  description = "Default hostname URL for the Azure Function App"
  value       = "https://${azurerm_linux_function_app.marketing_function.default_hostname}"
}

output "function_app_hostname" {
  description = "Default hostname for the Azure Function App"
  value       = azurerm_linux_function_app.marketing_function.default_hostname
}

output "service_plan_name" {
  description = "Name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.marketing_plan.name
}

output "service_plan_sku" {
  description = "SKU configuration of the App Service Plan"
  value       = azurerm_service_plan.marketing_plan.sku_name
}

# Managed Identity Outputs (when enabled)
output "function_app_managed_identity" {
  description = "Managed identity information for the Function App (when enabled)"
  value = var.enable_managed_identity ? {
    principal_id = azurerm_linux_function_app.marketing_function.identity[0].principal_id
    tenant_id    = azurerm_linux_function_app.marketing_function.identity[0].tenant_id
    type         = azurerm_linux_function_app.marketing_function.identity[0].type
  } : null
}

# Application Insights Outputs (when enabled)
output "application_insights_name" {
  description = "Name of Application Insights instance for monitoring (when enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing_insights[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key for telemetry collection"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for telemetry collection"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing_insights[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID for API access"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing_insights[0].app_id : null
}

# Cost Management Outputs
output "budget_name" {
  description = "Name of the created budget for cost monitoring (when enabled)"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.marketing_budget[0].name : null
}

output "budget_amount" {
  description = "Monthly budget limit configured for cost monitoring"
  value       = var.enable_cost_alerts ? var.monthly_budget_limit : null
}

# Configuration and Testing Information
output "test_request_example" {
  description = "Example JSON request for testing the marketing content generation workflow"
  value = jsonencode({
    campaign_id      = "example-campaign-${random_string.suffix.result}"
    generate_text    = true
    text_prompt      = "Create an engaging social media post for a new product launch with relevant hashtags and call-to-action"
    generate_image   = true
    image_prompt     = "A professional marketing image showing a modern product in use, bright lighting, commercial photography style"
  })
}

output "deployment_instructions" {
  description = "Step-by-step instructions for post-deployment configuration and testing"
  value = {
    step_1 = "Upload test request JSON to the '${var.marketing_containers.requests.name}' container to trigger content generation"
    step_2 = "Monitor Function App logs in Azure Portal or Application Insights for processing status"
    step_3 = "Check the '${var.marketing_containers.assets.name}' container for approved marketing assets"
    step_4 = "Review the '${var.marketing_containers.rejected.name}' container for content that failed safety validation"
    step_5 = "Customize content safety thresholds and prompts based on your brand requirements"
  }
}

# Security and Access Information
output "api_access_information" {
  description = "Summary of API endpoints and authentication methods for service integration"
  value = {
    openai_api = {
      endpoint = azurerm_cognitive_account.openai_service.endpoint
      auth_method = "API Key or Managed Identity"
      models = {
        text_generation = azurerm_cognitive_deployment.gpt4_deployment.name
        image_generation = azurerm_cognitive_deployment.dalle3_deployment.name
      }
    }
    content_safety_api = {
      endpoint = azurerm_cognitive_account.content_safety.endpoint
      auth_method = "API Key or Managed Identity"
      threshold = var.content_safety_severity_threshold
    }
    storage_api = {
      endpoint = azurerm_storage_account.marketing_storage.primary_blob_endpoint
      auth_method = "Access Key, SAS Token, or Managed Identity"
      containers = [for container in azurerm_storage_container.marketing_containers : container.name]
    }
  }
}

# Resource Summary for Quick Reference
output "resource_summary" {
  description = "Complete summary of all deployed resources with key configuration details"
  value = {
    infrastructure = {
      resource_group = azurerm_resource_group.marketing_rg.name
      location = azurerm_resource_group.marketing_rg.location
      environment = var.environment
      project = var.project_name
    }
    storage = {
      account_name = azurerm_storage_account.marketing_storage.name
      tier = var.storage_account_tier
      replication = var.storage_replication_type
      containers = length(azurerm_storage_container.marketing_containers)
    }
    ai_services = {
      openai_service = azurerm_cognitive_account.openai_service.name
      content_safety = azurerm_cognitive_account.content_safety.name
      gpt4_capacity = var.gpt4_deployment_capacity
      dalle3_capacity = var.dalle3_deployment_capacity
    }
    compute = {
      function_app = azurerm_linux_function_app.marketing_function.name
      service_plan = azurerm_service_plan.marketing_plan.name
      runtime = "Python 3.11"
      plan_type = var.function_app_service_plan_sku
    }
    monitoring = {
      application_insights_enabled = var.enable_application_insights
      budget_monitoring_enabled = var.enable_cost_alerts
      managed_identity_enabled = var.enable_managed_identity
    }
  }
}
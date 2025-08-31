# outputs.tf
# Output values for the Simple Team Poll System infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.poll_system.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.poll_system.location
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.poll_functions.name
}

output "function_app_url" {
  description = "Base URL for the Function App (HTTPS endpoint)"
  value       = "https://${azurerm_linux_function_app.poll_functions.default_hostname}"
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.poll_functions.default_hostname
}

# API Endpoints
output "submit_vote_endpoint" {
  description = "HTTP endpoint for submitting votes (POST)"
  value       = "https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/SubmitVote"
}

output "get_results_endpoint" {
  description = "HTTP endpoint for retrieving poll results (GET)"
  value       = "https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/results/{pollId}"
}

output "get_results_endpoint_example" {
  description = "Example URL for retrieving poll results"
  value       = "https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/results/team-lunch"
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.poll_namespace.name
}

output "service_bus_queue_name" {
  description = "Name of the Service Bus queue for vote processing"
  value       = azurerm_servicebus_queue.votes_queue.name
}

output "service_bus_connection_string" {
  description = "Service Bus namespace connection string (sensitive)"
  value       = azurerm_servicebus_namespace.poll_namespace.default_primary_connection_string
  sensitive   = true
}

# Storage Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.poll_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.poll_storage.primary_blob_endpoint
}

output "poll_results_container_name" {
  description = "Name of the storage container for poll results"
  value       = azurerm_storage_container.poll_results.name
}

# Monitoring Information
output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.poll_insights.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (sensitive)"
  value       = azurerm_application_insights.poll_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = azurerm_application_insights.poll_insights.app_id
}

# Function App Service Plan Information  
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.poll_plan.name
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.poll_plan.sku_name
}

# System Information
output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.poll_functions.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.poll_functions.identity[0].tenant_id
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the poll system API"
  value = {
    submit_vote = {
      method = "POST"
      url    = "https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/SubmitVote"
      body   = {
        pollId  = "your-poll-id"
        option  = "Option A"
        voterId = "voter@example.com"
      }
      example = "curl -X POST https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/SubmitVote -H 'Content-Type: application/json' -d '{\"pollId\":\"team-lunch\",\"option\":\"Pizza\",\"voterId\":\"alice@company.com\"}'"
    }
    get_results = {
      method  = "GET"
      url     = "https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/results/{pollId}"
      example = "curl https://${azurerm_linux_function_app.poll_functions.default_hostname}/api/results/team-lunch"
    }
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD for typical usage (informational only)"
  value = {
    function_app_consumption = "~$5-15 for 1M executions"
    service_bus_basic       = "~$0.05 per million operations"
    storage_account         = "~$0.02 per GB stored"
    application_insights    = "~$2.30 per GB ingested"
    total_estimate          = "~$10-25 per month for moderate usage"
    note                    = "Costs vary based on actual usage. Consumption plan charges per execution and memory usage."
  }
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    terraform_version = "~> 1.0"
    azurerm_version  = "~> 3.0"
    deployment_date  = formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())
    resource_count   = 10
    primary_services = [
      "Azure Functions",
      "Service Bus",
      "Storage Account",
      "Application Insights"
    ]
  }
}
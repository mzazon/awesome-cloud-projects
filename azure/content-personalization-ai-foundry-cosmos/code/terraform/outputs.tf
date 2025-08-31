# ===================================================================
# Outputs for Azure Content Personalization Engine
# ===================================================================
# This file defines all output values that provide information about
# the deployed infrastructure for integration and management purposes.

# ===================================================================
# Resource Group Information
# ===================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# ===================================================================
# Azure Cosmos DB Outputs
# ===================================================================

output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_id" {
  description = "Resource ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_endpoint" {
  description = "Cosmos DB account endpoint URL"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.personalization.name
}

output "cosmos_user_profiles_container_name" {
  description = "Name of the user profiles container"
  value       = azurerm_cosmosdb_sql_container.user_profiles.name
}

output "cosmos_content_items_container_name" {
  description = "Name of the content items container"
  value       = azurerm_cosmosdb_sql_container.content_items.name
}

output "cosmos_primary_key" {
  description = "Primary access key for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_connection_string" {
  description = "Primary connection string for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings[0]
  sensitive   = true
}

output "cosmos_document_endpoint" {
  description = "Document endpoint for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

# ===================================================================
# Azure OpenAI Service Outputs
# ===================================================================

output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_id" {
  description = "Resource ID of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "Primary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_key" {
  description = "Secondary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

output "gpt4_deployment_name" {
  description = "Name of the GPT-4 model deployment"
  value       = azurerm_cognitive_deployment.gpt4_content.name
}

output "embedding_deployment_name" {
  description = "Name of the text embedding model deployment"
  value       = azurerm_cognitive_deployment.text_embedding.name
}

output "gpt4_deployment_id" {
  description = "Resource ID of the GPT-4 deployment"
  value       = azurerm_cognitive_deployment.gpt4_content.id
}

output "embedding_deployment_id" {
  description = "Resource ID of the embedding deployment"
  value       = azurerm_cognitive_deployment.text_embedding.id
}

# ===================================================================
# Azure Functions Outputs
# ===================================================================

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.personalization.name
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.personalization.id
}

output "function_app_hostname" {
  description = "Default hostname for the Function App"
  value       = azurerm_linux_function_app.personalization.default_hostname
}

output "function_app_url" {
  description = "Default URL for the Function App"
  value       = "https://${azurerm_linux_function_app.personalization.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.personalization.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.personalization.identity[0].tenant_id
}

output "storage_account_name" {
  description = "Name of the storage account used by Functions"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

output "service_plan_name" {
  description = "Name of the App Service Plan for Functions"
  value       = azurerm_service_plan.functions.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.functions.id
}

# ===================================================================
# AI Foundry Workspace Outputs
# ===================================================================

output "ai_foundry_workspace_name" {
  description = "Name of the AI Foundry workspace"
  value       = azurerm_machine_learning_workspace.ai_foundry.name
}

output "ai_foundry_workspace_id" {
  description = "Resource ID of the AI Foundry workspace"
  value       = azurerm_machine_learning_workspace.ai_foundry.id
}

output "ai_foundry_workspace_endpoint" {
  description = "Discovery URL for the AI Foundry workspace"
  value       = azurerm_machine_learning_workspace.ai_foundry.discovery_url
}

output "ai_foundry_identity_principal_id" {
  description = "Principal ID of the AI Foundry workspace's managed identity"
  value       = azurerm_machine_learning_workspace.ai_foundry.identity[0].principal_id
}

output "ai_foundry_identity_tenant_id" {
  description = "Tenant ID of the AI Foundry workspace's managed identity"
  value       = azurerm_machine_learning_workspace.ai_foundry.identity[0].tenant_id
}

# ===================================================================
# Key Vault Outputs
# ===================================================================

output "key_vault_name" {
  description = "Name of the Key Vault for AI Foundry workspace"
  value       = azurerm_key_vault.ml_workspace.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.ml_workspace.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.ml_workspace.vault_uri
}

# ===================================================================
# Application Insights Outputs
# ===================================================================

output "application_insights_name" {
  description = "Name of the Application Insights instance for Functions"
  value       = azurerm_application_insights.functions.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance"
  value       = azurerm_application_insights.functions.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.functions.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.functions.connection_string
  sensitive   = true
}

output "ml_workspace_application_insights_name" {
  description = "Name of the Application Insights instance for ML workspace"
  value       = azurerm_application_insights.ml_workspace.name
}

output "ml_workspace_application_insights_id" {
  description = "Resource ID of the ML workspace Application Insights instance"
  value       = azurerm_application_insights.ml_workspace.id
}

# ===================================================================
# Security and Access Information
# ===================================================================

output "current_tenant_id" {
  description = "Current Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "current_client_id" {
  description = "Current Azure AD client ID"
  value       = data.azurerm_client_config.current.client_id
}

output "current_object_id" {
  description = "Current Azure AD object ID"
  value       = data.azurerm_client_config.current.object_id
}

# ===================================================================
# API Endpoints and Connection Information
# ===================================================================

output "personalization_api_endpoint" {
  description = "Full URL for the personalization API endpoint"
  value       = "https://${azurerm_linux_function_app.personalization.default_hostname}/api/personalization"
}

output "function_app_scm_url" {
  description = "SCM URL for Function App management"
  value       = "https://${azurerm_linux_function_app.personalization.name}.scm.azurewebsites.net"
}

# ===================================================================
# Deployment Information
# ===================================================================

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "tags" {
  description = "Tags applied to resources"
  value       = var.tags
}

# ===================================================================
# Environment Configuration Summary
# ===================================================================

output "environment_summary" {
  description = "Summary of the deployed environment configuration"
  value = {
    environment                = var.environment
    location                  = var.location
    openai_location          = var.openai_location != "" ? var.openai_location : var.location
    cosmos_throughput        = var.cosmos_throughput
    function_app_sku         = var.function_app_sku
    gpt4_capacity           = var.gpt4_capacity
    embedding_capacity      = var.embedding_capacity
    vector_search_enabled   = var.enable_vector_search
    ai_foundry_enabled      = var.enable_ai_foundry
    monitoring_enabled      = var.enable_monitoring
    public_access_enabled   = var.public_network_access_enabled
  }
}

# ===================================================================
# Quick Start Information
# ===================================================================

output "quick_start_info" {
  description = "Quick start information for using the deployed resources"
  value = {
    function_app_url           = "https://${azurerm_linux_function_app.personalization.default_hostname}"
    cosmos_endpoint           = azurerm_cosmosdb_account.main.endpoint
    openai_endpoint           = azurerm_cognitive_account.openai.endpoint
    ai_foundry_workspace      = azurerm_machine_learning_workspace.ai_foundry.name
    sample_api_call           = "curl -X GET 'https://${azurerm_linux_function_app.personalization.default_hostname}/api/personalization?userId=user123'"
    azure_portal_links = {
      resource_group    = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"
      function_app      = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.personalization.id}"
      cosmos_db         = "https://portal.azure.com/#@/resource${azurerm_cosmosdb_account.main.id}"
      openai_service    = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.openai.id}"
      ai_foundry        = "https://portal.azure.com/#@/resource${azurerm_machine_learning_workspace.ai_foundry.id}"
    }
  }
}

# ===================================================================
# Configuration Files for Applications
# ===================================================================

output "application_config" {
  description = "Configuration values for application development"
  value = {
    cosmos_connection_string      = azurerm_cosmosdb_account.main.connection_strings[0]
    cosmos_database_name         = azurerm_cosmosdb_sql_database.personalization.name
    cosmos_user_container_name   = azurerm_cosmosdb_sql_container.user_profiles.name
    cosmos_content_container_name = azurerm_cosmosdb_sql_container.content_items.name
    openai_endpoint              = azurerm_cognitive_account.openai.endpoint
    openai_gpt4_deployment       = azurerm_cognitive_deployment.gpt4_content.name
    openai_embedding_deployment  = azurerm_cognitive_deployment.text_embedding.name
    ai_foundry_workspace_name    = azurerm_machine_learning_workspace.ai_foundry.name
    function_app_name            = azurerm_linux_function_app.personalization.name
  }
  sensitive = true
}

# ===================================================================
# Cost and Resource Information
# ===================================================================

output "resource_costs_info" {
  description = "Information about resource costs and optimization"
  value = {
    cosmos_throughput_cost_info  = "Current throughput: ${var.cosmos_throughput} RU/s. Consider using autoscale for variable workloads."
    openai_capacity_info        = "GPT-4: ${var.gpt4_capacity}K TPM, Embedding: ${var.embedding_capacity}K TPM. Monitor usage to optimize costs."
    function_app_plan_info      = "Plan: ${var.function_app_sku}. Y1 (Consumption) is most cost-effective for variable loads."
    monitoring_retention_info   = "Application Insights retention: ${var.application_insights_retention_days} days. Longer retention increases costs."
    cost_optimization_tips = [
      "Monitor OpenAI token usage and adjust model capacities",
      "Use Cosmos DB autoscale for variable workloads",
      "Consider reserved capacity for predictable workloads",
      "Set up cost alerts to track spending"
    ]
  }
}
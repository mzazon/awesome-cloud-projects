# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure OpenAI Service Outputs
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_id" {
  description = "ID of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_custom_subdomain" {
  description = "Custom subdomain for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

output "openai_primary_access_key" {
  description = "Primary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_access_key" {
  description = "Secondary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

# Model Deployment Outputs
output "deployed_models" {
  description = "Information about deployed AI models"
  value = {
    for k, v in azurerm_cognitive_deployment.models : k => {
      id           = v.id
      name         = v.name
      model_name   = v.model[0].name
      model_version = v.model[0].version
      model_format  = v.model[0].format
      sku_name     = v.sku[0].name
      sku_capacity = v.sku[0].capacity
    }
  }
}

output "model_deployment_names" {
  description = "List of deployed model names"
  value       = [for k, v in azurerm_cognitive_deployment.models : v.name]
}

# Machine Learning Workspace Outputs
output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace (AI Foundry project)"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_workspace_id" {
  description = "Immutable workspace ID"
  value       = azurerm_machine_learning_workspace.main.workspace_id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the ML workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_workspace_managed_identity" {
  description = "Managed identity information for the ML workspace"
  value = {
    principal_id = azurerm_machine_learning_workspace.main.identity[0].principal_id
    tenant_id    = azurerm_machine_learning_workspace.main.identity[0].tenant_id
    type         = azurerm_machine_learning_workspace.main.identity[0].type
  }
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_containers" {
  description = "Created storage containers for evaluation data"
  value = {
    evaluation_datasets = azurerm_storage_container.evaluation_datasets.name
    evaluation_results  = azurerm_storage_container.evaluation_results.name
    custom_flows       = azurerm_storage_container.custom_flows.name
  }
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of Application Insights"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Container Registry Outputs (conditional)
output "container_registry_name" {
  description = "Name of the Azure Container Registry (if enabled)"
  value       = var.container_registry_enabled ? azurerm_container_registry.main[0].name : null
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry (if enabled)"
  value       = var.container_registry_enabled ? azurerm_container_registry.main[0].id : null
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry (if enabled)"
  value       = var.container_registry_enabled ? azurerm_container_registry.main[0].login_server : null
}

# Environment and Configuration Outputs
output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = var.location
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Connection Information for Azure CLI Commands
output "azure_cli_connection_info" {
  description = "Connection information for Azure CLI commands"
  value = {
    subscription_id      = data.azurerm_client_config.current.subscription_id
    tenant_id           = data.azurerm_client_config.current.tenant_id
    resource_group_name = azurerm_resource_group.main.name
    openai_service_name = azurerm_cognitive_account.openai.name
    ml_workspace_name   = azurerm_machine_learning_workspace.main.name
    storage_account_name = azurerm_storage_account.main.name
  }
}

# Evaluation Setup Information
output "evaluation_setup_info" {
  description = "Information needed for setting up evaluation pipelines"
  value = {
    openai_endpoint          = azurerm_cognitive_account.openai.endpoint
    openai_subdomain        = azurerm_cognitive_account.openai.custom_subdomain_name
    ml_workspace_name       = azurerm_machine_learning_workspace.main.name
    available_models        = [for k, v in azurerm_cognitive_deployment.models : v.name]
    storage_containers = {
      datasets = azurerm_storage_container.evaluation_datasets.name
      results  = azurerm_storage_container.evaluation_results.name
      flows    = azurerm_storage_container.custom_flows.name
    }
    application_insights_key = azurerm_application_insights.main.instrumentation_key
  }
  sensitive = true
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation and monitoring"
  value = {
    openai_sku         = var.openai_sku_name
    ml_workspace_sku   = var.ml_workspace_sku
    storage_tier       = var.storage_account_tier
    storage_replication = var.storage_replication_type
    model_deployments = {
      for k, v in var.model_deployments : k => {
        model_name = v.model_name
        sku_name   = v.sku_name
        capacity   = v.sku_capacity
      }
    }
  }
}
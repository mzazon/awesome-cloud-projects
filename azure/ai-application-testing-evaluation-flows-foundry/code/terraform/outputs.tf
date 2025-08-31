# Output values for Azure AI Application Testing Infrastructure
# These outputs provide connection details and resource information for integration
# with Azure DevOps pipelines, applications, and monitoring systems

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.ai_testing.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.ai_testing.location
}

# AI Services Configuration
output "ai_services_name" {
  description = "Name of the Azure AI Services account"
  value       = azurerm_cognitive_account.ai_services.name
}

output "ai_services_endpoint" {
  description = "Endpoint URL for Azure AI Services"
  value       = azurerm_cognitive_account.ai_services.endpoint
}

output "ai_services_id" {
  description = "Resource ID of the Azure AI Services account"
  value       = azurerm_cognitive_account.ai_services.id
}

output "ai_services_custom_subdomain" {
  description = "Custom subdomain for AI Services (used for OpenAI endpoints)"
  value       = azurerm_cognitive_account.ai_services.custom_subdomain_name
}

# OpenAI Model Deployment Information
output "openai_deployment_name" {
  description = "Name of the OpenAI model deployment for evaluation"
  value       = azurerm_cognitive_deployment.openai_evaluation_model.name
}

output "openai_model_name" {
  description = "Name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.openai_evaluation_model.model[0].name
}

output "openai_model_version" {
  description = "Version of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.openai_evaluation_model.model[0].version
}

output "openai_endpoint" {
  description = "OpenAI endpoint URL for evaluation model access"
  value       = "https://${azurerm_cognitive_account.ai_services.custom_subdomain_name}.openai.azure.com/"
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for evaluation data"
  value       = azurerm_storage_account.evaluation_storage.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.evaluation_storage.id
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.evaluation_storage.primary_blob_endpoint
}

# Storage Container Information
output "test_datasets_container_name" {
  description = "Name of the container for test datasets"
  value       = azurerm_storage_container.test_datasets.name
}

output "evaluation_results_container_name" {
  description = "Name of the container for evaluation results"
  value       = azurerm_storage_container.evaluation_results.name
}

output "evaluation_flows_container_name" {
  description = "Name of the container for evaluation flows"
  value       = azurerm_storage_container.evaluation_flows.name
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secrets management"
  value       = azurerm_key_vault.ai_testing_vault.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.ai_testing_vault.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.ai_testing_vault.id
}

# Monitoring and Logging Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ai_testing_logs.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ai_testing_logs.id
}

output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.ai_testing_insights.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.ai_testing_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights telemetry"
  value       = azurerm_application_insights.ai_testing_insights.connection_string
  sensitive   = true
}

# Azure DevOps Integration Outputs
output "azure_devops_service_connection_config" {
  description = "Configuration values for Azure DevOps service connection"
  value = var.create_devops_service_connection ? {
    subscription_id                = data.azurerm_client_config.current.subscription_id
    subscription_name             = "AI-Testing-Subscription"
    tenant_id                     = data.azurerm_client_config.current.tenant_id
    resource_group_name           = azurerm_resource_group.ai_testing.name
    ai_services_name              = azurerm_cognitive_account.ai_services.name
    storage_account_name          = azurerm_storage_account.evaluation_storage.name
    key_vault_name               = azurerm_key_vault.ai_testing_vault.name
    openai_deployment_name       = azurerm_cognitive_deployment.openai_evaluation_model.name
  } : null
}

# Environment Variables for CI/CD Pipelines
output "pipeline_environment_variables" {
  description = "Environment variables for CI/CD pipeline configuration"
  value = {
    AZURE_SUBSCRIPTION_ID        = data.azurerm_client_config.current.subscription_id
    AZURE_TENANT_ID             = data.azurerm_client_config.current.tenant_id
    RESOURCE_GROUP              = azurerm_resource_group.ai_testing.name
    AI_SERVICES_NAME            = azurerm_cognitive_account.ai_services.name
    AI_SERVICES_ENDPOINT        = azurerm_cognitive_account.ai_services.endpoint
    OPENAI_DEPLOYMENT_NAME      = azurerm_cognitive_deployment.openai_evaluation_model.name
    OPENAI_ENDPOINT            = "https://${azurerm_cognitive_account.ai_services.custom_subdomain_name}.openai.azure.com/"
    STORAGE_ACCOUNT_NAME       = azurerm_storage_account.evaluation_storage.name
    TEST_DATASETS_CONTAINER    = azurerm_storage_container.test_datasets.name
    EVALUATION_RESULTS_CONTAINER = azurerm_storage_container.evaluation_results.name
    KEY_VAULT_NAME             = azurerm_key_vault.ai_testing_vault.name
    KEY_VAULT_URI              = azurerm_key_vault.ai_testing_vault.vault_uri
    APPLICATION_INSIGHTS_NAME   = azurerm_application_insights.ai_testing_insights.name
  }
}

# Security and Access Information
output "ai_services_managed_identity" {
  description = "Managed identity information for AI Services"
  value = {
    principal_id = azurerm_cognitive_account.ai_services.identity[0].principal_id
    tenant_id    = azurerm_cognitive_account.ai_services.identity[0].tenant_id
    type         = azurerm_cognitive_account.ai_services.identity[0].type
  }
}

# Quality Gates Configuration
output "evaluation_thresholds" {
  description = "Default quality thresholds for evaluation gates"
  value = {
    overall_score_threshold    = 3.0
    groundedness_threshold     = 3.0
    relevance_threshold       = 2.5
    coherence_threshold       = 2.5
    minimum_test_cases        = 3
    evaluation_timeout_minutes = 30
  }
}

# Cost Management Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    ai_services_sku          = var.ai_services_sku
    openai_deployment_capacity = var.openai_deployment_capacity
    storage_tier            = var.storage_account_tier
    estimated_total_usd     = "15-25"
    cost_factors = [
      "AI Services SKU: ${var.ai_services_sku}",
      "OpenAI deployment capacity: ${var.openai_deployment_capacity}K TPM",
      "Storage account tier: ${var.storage_account_tier}",
      "Evaluation runs frequency and volume"
    ]
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    set_environment_variables = "export AZURE_OPENAI_ENDPOINT='${azurerm_cognitive_account.ai_services.endpoint}' && export AZURE_OPENAI_DEPLOYMENT='${azurerm_cognitive_deployment.openai_evaluation_model.name}' && export STORAGE_ACCOUNT='${azurerm_storage_account.evaluation_storage.name}'"
    get_ai_services_key      = "az cognitiveservices account keys list --name ${azurerm_cognitive_account.ai_services.name} --resource-group ${azurerm_resource_group.ai_testing.name} --query 'key1' --output tsv"
    upload_test_data         = "az storage blob upload --file test_data.jsonl --container-name ${azurerm_storage_container.test_datasets.name} --name ai-test-dataset.jsonl --account-name ${azurerm_storage_account.evaluation_storage.name}"
    test_openai_endpoint     = "curl -H 'Content-Type: application/json' -H 'api-key: YOUR_API_KEY' 'https://${azurerm_cognitive_account.ai_services.custom_subdomain_name}.openai.azure.com/openai/deployments/${azurerm_cognitive_deployment.openai_evaluation_model.name}/chat/completions?api-version=2024-02-01' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
  }
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}
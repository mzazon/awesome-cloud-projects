# ==============================================================================
# OUTPUTS DEFINITION
# Azure Automated Content Generation with Prompt Flow and OpenAI
# ==============================================================================

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Machine Learning Workspace Outputs
output "ml_workspace_name" {
  description = "The name of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "The ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_discovery_url" {
  description = "The discovery URL of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_workspace_workspace_id" {
  description = "The workspace ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.workspace_id
}

# Azure OpenAI Service Outputs
output "openai_account_name" {
  description = "The name of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "The endpoint URL of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_account_id" {
  description = "The ID of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_custom_subdomain" {
  description = "The custom subdomain of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

# OpenAI Model Deployment Outputs
output "gpt4o_deployment_name" {
  description = "The deployment name for GPT-4o model"
  value       = azurerm_cognitive_deployment.gpt4o_content.name
}

output "gpt4o_model_version" {
  description = "The version of the deployed GPT-4o model"
  value       = azurerm_cognitive_deployment.gpt4o_content.model[0].version
}

output "embedding_deployment_name" {
  description = "The deployment name for text embedding model"
  value       = azurerm_cognitive_deployment.text_embedding.name
}

output "embedding_model_version" {
  description = "The version of the deployed text embedding model"
  value       = azurerm_cognitive_deployment.text_embedding.model[0].version
}

# Function App Outputs
output "function_app_name" {
  description = "The name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "The ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "The default hostname of the Azure Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "The base URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_possible_outbound_ip_addresses" {
  description = "The possible outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.main.possible_outbound_ip_addresses
}

output "function_app_principal_id" {
  description = "The principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_primary_blob_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_primary_web_endpoint" {
  description = "The primary web endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_web_endpoint
}

output "content_templates_container_name" {
  description = "The name of the content templates container"
  value       = azurerm_storage_container.content_templates.name
}

output "generated_content_container_name" {
  description = "The name of the generated content container"
  value       = azurerm_storage_container.generated_content.name
}

# Cosmos DB Outputs
output "cosmos_account_name" {
  description = "The name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_id" {
  description = "The ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_endpoint" {
  description = "The endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "The name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.content_generation.name
}

output "cosmos_container_name" {
  description = "The name of the Cosmos DB container"
  value       = azurerm_cosmosdb_sql_container.content_metadata.name
}

output "cosmos_read_endpoints" {
  description = "The read endpoints of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.read_endpoints
}

output "cosmos_write_endpoints" {
  description = "The write endpoints of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.write_endpoints
}

# Key Vault Outputs
output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.ml_workspace.name
}

output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.ml_workspace.id
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.ml_workspace.vault_uri
}

# Application Insights Outputs
output "ml_application_insights_name" {
  description = "The name of the ML workspace Application Insights"
  value       = azurerm_application_insights.ml_workspace.name
}

output "ml_application_insights_instrumentation_key" {
  description = "The instrumentation key of the ML workspace Application Insights"
  value       = azurerm_application_insights.ml_workspace.instrumentation_key
  sensitive   = true
}

output "ml_application_insights_app_id" {
  description = "The app ID of the ML workspace Application Insights"
  value       = azurerm_application_insights.ml_workspace.app_id
}

output "function_application_insights_name" {
  description = "The name of the Function App Application Insights"
  value       = azurerm_application_insights.function_app.name
}

output "function_application_insights_instrumentation_key" {
  description = "The instrumentation key of the Function App Application Insights"
  value       = azurerm_application_insights.function_app.instrumentation_key
  sensitive   = true
}

output "function_application_insights_app_id" {
  description = "The app ID of the Function App Application Insights"
  value       = azurerm_application_insights.function_app.app_id
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "The workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "The primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Service Plan Outputs
output "service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.function_app.name
}

output "service_plan_id" {
  description = "The ID of the App Service Plan"
  value       = azurerm_service_plan.function_app.id
}

output "service_plan_kind" {
  description = "The kind of the App Service Plan"
  value       = azurerm_service_plan.function_app.kind
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for integrating with the deployed services"
  value = {
    ml_workspace = {
      name                = azurerm_machine_learning_workspace.main.name
      resource_group      = azurerm_resource_group.main.name
      subscription_id     = data.azurerm_client_config.current.subscription_id
      discovery_url       = azurerm_machine_learning_workspace.main.discovery_url
    }
    openai = {
      endpoint            = azurerm_cognitive_account.openai.endpoint
      gpt4o_deployment    = azurerm_cognitive_deployment.gpt4o_content.name
      embedding_deployment = azurerm_cognitive_deployment.text_embedding.name
      api_version         = "2024-02-15-preview"
    }
    storage = {
      account_name        = azurerm_storage_account.main.name
      blob_endpoint       = azurerm_storage_account.main.primary_blob_endpoint
      templates_container = azurerm_storage_container.content_templates.name
      content_container   = azurerm_storage_container.generated_content.name
    }
    cosmos = {
      endpoint            = azurerm_cosmosdb_account.main.endpoint
      database_name       = azurerm_cosmosdb_sql_database.content_generation.name
      container_name      = azurerm_cosmosdb_sql_container.content_metadata.name
    }
    function_app = {
      name                = azurerm_linux_function_app.main.name
      url                 = "https://${azurerm_linux_function_app.main.default_hostname}"
      resource_group      = azurerm_resource_group.main.name
    }
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    region              = azurerm_resource_group.main.location
    openai_region       = azurerm_cognitive_account.openai.location
    resource_group      = azurerm_resource_group.main.name
    subscription_id     = data.azurerm_client_config.current.subscription_id
    tenant_id           = data.azurerm_client_config.current.tenant_id
    random_suffix       = random_string.suffix.result
    deployment_timestamp = timestamp()
  }
}

# Testing and Validation URLs
output "testing_urls" {
  description = "URLs for testing the deployed solution"
  value = {
    function_app_base_url     = "https://${azurerm_linux_function_app.main.default_hostname}"
    ml_workspace_studio_url   = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.main.workspace_id}/home"
    storage_web_endpoint      = azurerm_storage_account.main.primary_web_endpoint
    application_insights_url  = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.function_app.id}/overview"
    cosmos_data_explorer_url  = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cosmosdb_account.main.id}/dataExplorer"
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation and monitoring"
  value = {
    consumption_based_services = [
      "Azure Functions (Consumption Plan)",
      "Azure OpenAI Service (Pay-per-token)",
      "Cosmos DB (Provisioned throughput)",
      "Storage Account (Pay-per-use)",
      "Application Insights (Pay-per-GB)"
    ]
    fixed_cost_services = [
      "Log Analytics Workspace (Per-GB ingestion)"
    ]
    cost_optimization_tips = [
      "Monitor Azure OpenAI token usage to control costs",
      "Use Cosmos DB autoscale for variable workloads",
      "Enable storage lifecycle policies for long-term cost reduction",
      "Monitor Function App execution times and memory usage",
      "Review Application Insights sampling settings"
    ]
  }
}

# Security Information
output "security_info" {
  description = "Security-related information and managed identities"
  value = {
    function_app_managed_identity = azurerm_linux_function_app.main.identity[0].principal_id
    ml_workspace_managed_identity = azurerm_machine_learning_workspace.main.identity[0].principal_id
    key_vault_name               = azurerm_key_vault.ml_workspace.name
    rbac_assignments = [
      "Function App → ML Workspace (AzureML Data Scientist)",
      "Function App → OpenAI Service (Cognitive Services OpenAI User)",
      "Function App → Storage Account (Storage Blob Data Contributor)",
      "Function App → Cosmos DB (DocumentDB Account Contributor)",
      "ML Workspace → Storage Account (Storage Blob Data Contributor)"
    ]
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    immediate = [
      "1. Configure Prompt Flow connections in ML Studio",
      "2. Deploy function code to Azure Functions",
      "3. Test content generation endpoint",
      "4. Verify data storage in Cosmos DB and Blob Storage"
    ]
    optimization = [
      "1. Set up monitoring alerts for cost and performance",
      "2. Configure custom domains if needed",
      "3. Implement content validation rules",
      "4. Set up CI/CD pipelines for function deployment"
    ]
    scaling = [
      "1. Monitor OpenAI capacity and scale as needed",
      "2. Consider Cosmos DB autoscale for variable loads",
      "3. Implement caching strategies for frequently requested content",
      "4. Set up multi-region deployment for global access"
    ]
  }
}
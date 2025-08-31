# ==================================================================================================
# TERRAFORM OUTPUTS FOR AZURE DOCUMENT Q&A SOLUTION
# ==================================================================================================
# This file defines output values that provide important information about the deployed
# infrastructure, including endpoints, keys, and resource identifiers needed for application
# deployment, monitoring, and integration with external systems.
# ==================================================================================================

# ==================================================================================================
# RESOURCE GROUP AND GENERAL INFORMATION
# ==================================================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all Document Q&A resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Full resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "environment" {
  description = "Environment name used for resource deployment"
  value       = var.environment
}

# ==================================================================================================
# AZURE FUNCTIONS API ENDPOINTS
# ==================================================================================================

output "function_app_name" {
  description = "Name of the Azure Function App hosting the Q&A API"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Full resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Default hostname URL of the Function App for API access"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_api_url" {
  description = "Complete API endpoint URL for document Q&A requests"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/qa"
}

output "function_app_outbound_ip_addresses" {
  description = "List of possible outbound IP addresses from the Function App"
  value       = azurerm_linux_function_app.main.possible_outbound_ip_address_list
}

# ==================================================================================================
# AZURE AI SEARCH SERVICE INFORMATION
# ==================================================================================================

output "search_service_name" {
  description = "Name of the Azure AI Search service"
  value       = azurerm_search_service.main.name
}

output "search_service_id" {
  description = "Full resource ID of the Azure AI Search service"
  value       = azurerm_search_service.main.id
}

output "search_service_url" {
  description = "HTTPS endpoint URL for the Azure AI Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "search_service_sku" {
  description = "SKU tier of the deployed Azure AI Search service"
  value       = azurerm_search_service.main.sku
}

output "search_index_name" {
  description = "Name of the search index for document storage and querying"
  value       = var.search_index_name
}

# ==================================================================================================
# AZURE OPENAI SERVICE INFORMATION
# ==================================================================================================

output "openai_service_name" {
  description = "Name of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_id" {
  description = "Full resource ID of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "HTTPS endpoint URL for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_location" {
  description = "Azure region where OpenAI service is deployed"
  value       = azurerm_cognitive_account.openai.location
}

output "embedding_deployment_name" {
  description = "Name of the text embedding model deployment"
  value       = azurerm_cognitive_deployment.embedding.name
}

output "chat_deployment_name" {
  description = "Name of the chat completion model deployment"
  value       = azurerm_cognitive_deployment.chat.name
}

output "embedding_model_info" {
  description = "Information about the deployed embedding model"
  value = {
    name       = local.embedding_model.name
    version    = local.embedding_model.version
    dimensions = local.embedding_model.dimensions
    capacity   = local.embedding_model.capacity
  }
}

output "chat_model_info" {
  description = "Information about the deployed chat completion model"
  value = {
    name     = local.chat_model.name
    version  = local.chat_model.version
    capacity = local.chat_model.capacity
  }
}

# ==================================================================================================
# STORAGE ACCOUNT INFORMATION
# ==================================================================================================

output "storage_account_name" {
  description = "Name of the Azure Storage Account for document storage"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Full resource ID of the Azure Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_web_endpoint" {
  description = "Primary web endpoint URL for the storage account"
  value       = azurerm_storage_account.main.primary_web_endpoint
}

output "documents_container_name" {
  description = "Name of the blob container for document storage"
  value       = azurerm_storage_container.documents.name
}

output "documents_container_url" {
  description = "URL for accessing the documents container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.documents.name}"
}

# ==================================================================================================
# MONITORING AND LOGGING INFORMATION
# ==================================================================================================

output "application_insights_name" {
  description = "Name of the Application Insights instance for monitoring"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "Full resource ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights integration"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights integration"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Full resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# ==================================================================================================
# SECURITY AND ACCESS KEYS (SENSITIVE)
# ==================================================================================================

output "search_service_admin_key" {
  description = "Primary admin key for Azure AI Search service management operations"
  value       = azurerm_search_service.main.primary_key
  sensitive   = true
}

output "search_service_query_key" {
  description = "Query key for read-only search operations"
  value       = azurerm_search_service.main.query_keys[0].key
  sensitive   = true
}

output "openai_access_key" {
  description = "Primary access key for Azure OpenAI Service authentication"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for Azure Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Primary connection string for Azure Storage Account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# ==================================================================================================
# MANAGED IDENTITY INFORMATION
# ==================================================================================================

output "function_app_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

output "search_service_principal_id" {
  description = "Principal ID of the Search Service's system-assigned managed identity"
  value       = azurerm_search_service.main.identity[0].principal_id
}

output "openai_service_principal_id" {
  description = "Principal ID of the OpenAI Service's system-assigned managed identity"
  value       = azurerm_cognitive_account.openai.identity[0].principal_id
}

# ==================================================================================================
# NETWORK AND CONNECTIVITY INFORMATION
# ==================================================================================================

output "public_network_access_enabled" {
  description = "Map of public network access settings for all services"
  value = {
    function_app    = var.function_app_public_access_enabled
    search_service  = var.search_public_network_access_enabled
    openai_service  = var.openai_public_network_access_enabled
  }
}

output "service_urls" {
  description = "Complete list of all service URLs for easy reference"
  value = {
    function_app_api = "https://${azurerm_linux_function_app.main.default_hostname}/api/qa"
    function_app_health = "https://${azurerm_linux_function_app.main.default_hostname}/api/health"
    search_service   = "https://${azurerm_search_service.main.name}.search.windows.net"
    openai_service   = azurerm_cognitive_account.openai.endpoint
    storage_account  = azurerm_storage_account.main.primary_web_endpoint
    app_insights     = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
  }
}

# ==================================================================================================
# DEPLOYMENT CONFIGURATION SUMMARY
# ==================================================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their key configurations"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = var.location
    environment       = var.environment
    function_app_sku  = var.function_app_sku_name
    search_sku        = var.search_service_sku
    openai_sku        = var.openai_sku_name
    python_version    = var.python_version
    search_index      = var.search_index_name
    embedding_model   = local.embedding_model.name
    chat_model        = local.chat_model.name
    storage_replication = var.storage_replication_type
  }
}

# ==================================================================================================
# COST OPTIMIZATION INFORMATION
# ==================================================================================================

output "cost_optimization_info" {
  description = "Information to help optimize costs and monitor resource usage"
  value = {
    function_app_plan_type    = var.function_app_sku_name
    search_service_tier       = var.search_service_sku
    search_replica_count      = var.search_replica_count
    search_partition_count    = var.search_partition_count
    storage_replication       = var.storage_replication_type
    log_retention_days        = var.log_analytics_retention_days
    blob_retention_days       = var.blob_delete_retention_days
    auto_scaling_enabled      = var.enable_auto_scaling
  }
}

# ==================================================================================================
# NEXT STEPS AND INTEGRATION INFORMATION
# ==================================================================================================

output "next_steps" {
  description = "Guidance for next steps after infrastructure deployment"
  value = {
    upload_documents = "Upload documents to the '${azurerm_storage_container.documents.name}' container in storage account '${azurerm_storage_account.main.name}'"
    configure_search_index = "Create search index, skillset, data source, and indexer using the provided API keys and endpoints"
    deploy_function_code = "Deploy the Python function code to '${azurerm_linux_function_app.main.name}' using Azure Functions Core Tools or CI/CD pipeline"
    test_api = "Test the Q&A API at: https://${azurerm_linux_function_app.main.default_hostname}/api/qa"
    monitor_performance = "Monitor application performance and usage in Application Insights: ${azurerm_application_insights.main.name}"
  }
}

# ==================================================================================================
# AZURE PORTAL QUICK ACCESS LINKS
# ==================================================================================================

output "azure_portal_links" {
  description = "Direct links to Azure Portal resources for quick access and management"
  value = {
    resource_group      = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    function_app        = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}/overview"
    search_service      = "https://portal.azure.com/#@/resource${azurerm_search_service.main.id}/overview"
    openai_service      = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.openai.id}/overview"
    storage_account     = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    log_analytics       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
  }
}
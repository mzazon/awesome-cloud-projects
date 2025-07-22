# ==============================================================================
# Output Values for Azure AI-Powered Migration Assessment
# ==============================================================================

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the created storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_containers" {
  description = "Map of created storage containers"
  value = {
    assessment_data        = azurerm_storage_container.assessment_data.name
    ai_insights           = azurerm_storage_container.ai_insights.name
    modernization_reports = azurerm_storage_container.modernization_reports.name
  }
}

# Azure OpenAI Service Information
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_id" {
  description = "ID of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_service_endpoint" {
  description = "Endpoint URL of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_location" {
  description = "Location of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.location
}

output "openai_service_custom_domain" {
  description = "Custom domain of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.custom_domain
}

output "openai_primary_access_key" {
  description = "Primary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_access_key" {
  description = "Secondary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

# GPT Model Deployment Information
output "gpt_deployment_name" {
  description = "Name of the GPT model deployment"
  value       = azurerm_cognitive_deployment.gpt4_migration.name
}

output "gpt_deployment_id" {
  description = "ID of the GPT model deployment"
  value       = azurerm_cognitive_deployment.gpt4_migration.id
}

output "gpt_model_name" {
  description = "Name of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt4_migration.model[0].name
}

output "gpt_model_version" {
  description = "Version of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt4_migration.model[0].version
}

output "gpt_model_capacity" {
  description = "Capacity of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt4_migration.scale[0].capacity
}

# Azure Migrate Project Information
output "migrate_project_name" {
  description = "Name of the Azure Migrate project"
  value       = azurerm_migrate_project.main.name
}

output "migrate_project_id" {
  description = "ID of the Azure Migrate project"
  value       = azurerm_migrate_project.main.id
}

output "migrate_project_location" {
  description = "Location of the Azure Migrate project"
  value       = azurerm_migrate_project.main.location
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Function App Service Plan Information
output "function_service_plan_name" {
  description = "Name of the Function App service plan"
  value       = azurerm_service_plan.main.name
}

output "function_service_plan_id" {
  description = "ID of the Function App service plan"
  value       = azurerm_service_plan.main.id
}

output "function_service_plan_sku" {
  description = "SKU of the Function App service plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
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

output "application_insights_app_id" {
  description = "App ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_key" {
  description = "Primary key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# API Endpoints and URLs
output "ai_assessment_function_url" {
  description = "URL for the AI assessment function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/migrate-ai-assessment"
}

output "sample_assessment_blob_url" {
  description = "URL for the sample assessment data blob"
  value       = azurerm_storage_blob.sample_assessment.url
}

# Configuration Information
output "environment_variables" {
  description = "Environment variables for Function App configuration"
  value = {
    OPENAI_ENDPOINT           = azurerm_cognitive_account.openai.endpoint
    OPENAI_MODEL_DEPLOYMENT   = azurerm_cognitive_deployment.gpt4_migration.name
    MIGRATE_PROJECT          = azurerm_migrate_project.main.name
    STORAGE_ACCOUNT_NAME     = azurerm_storage_account.main.name
    RESOURCE_GROUP_NAME      = azurerm_resource_group.main.name
    LOCATION                 = azurerm_resource_group.main.location
  }
}

output "sensitive_environment_variables" {
  description = "Sensitive environment variables for Function App configuration"
  value = {
    OPENAI_KEY                = azurerm_cognitive_account.openai.primary_access_key
    STORAGE_CONNECTION_STRING = azurerm_storage_account.main.primary_connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.main.instrumentation_key
  }
  sensitive = true
}

# Resource Identifiers
output "resource_ids" {
  description = "Map of all resource IDs for reference"
  value = {
    resource_group      = azurerm_resource_group.main.id
    storage_account     = azurerm_storage_account.main.id
    openai_service      = azurerm_cognitive_account.openai.id
    gpt_deployment      = azurerm_cognitive_deployment.gpt4_migration.id
    migrate_project     = azurerm_migrate_project.main.id
    function_app        = azurerm_linux_function_app.main.id
    service_plan        = azurerm_service_plan.main.id
    application_insights = azurerm_application_insights.main.id
    log_analytics       = azurerm_log_analytics_workspace.main.id
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    deployment_time     = timestamp()
    terraform_version   = "~> 1.0"
    azurerm_provider_version = "~> 3.116"
    random_suffix       = random_string.suffix.result
    environment         = var.environment
  }
}

# Cost Management Information
output "cost_management_info" {
  description = "Cost management and optimization information"
  value = {
    estimated_monthly_cost = "Varies based on usage - approximately $50-500/month"
    cost_optimization_tips = [
      "Use consumption plan for Function App to minimize costs",
      "Monitor OpenAI token usage and set appropriate limits",
      "Configure storage lifecycle policies for long-term data retention",
      "Use Log Analytics data export for cost-effective long-term storage"
    ]
    resource_group_name = azurerm_resource_group.main.name
  }
}

# Security Information
output "security_info" {
  description = "Security configuration and recommendations"
  value = {
    managed_identity_enabled = true
    https_only_enabled      = true
    min_tls_version         = var.min_tls_version
    soft_delete_enabled     = var.enable_soft_delete
    private_endpoints_supported = true
    rbac_assignments_configured = true
  }
}

# Monitoring and Diagnostics Information
output "monitoring_info" {
  description = "Monitoring and diagnostics configuration"
  value = {
    application_insights_enabled = true
    log_analytics_enabled        = true
    diagnostic_settings_enabled  = true
    log_retention_days          = var.log_retention_days
    sampling_percentage         = var.application_insights_sampling_percentage
  }
}

# Integration Information
output "integration_info" {
  description = "Integration endpoints and configuration"
  value = {
    openai_integration_configured = true
    migrate_integration_configured = true
    storage_integration_configured = true
    function_app_ready = true
    sample_data_available = var.enable_sample_data
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for testing the deployment"
  value = [
    "# Test OpenAI service availability",
    "az cognitiveservices account show --name ${azurerm_cognitive_account.openai.name} --resource-group ${azurerm_resource_group.main.name}",
    "",
    "# Test Function App deployment",
    "az functionapp show --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}",
    "",
    "# List storage containers",
    "az storage container list --account-name ${azurerm_storage_account.main.name}",
    "",
    "# Test AI assessment function (requires function key)",
    "curl -X POST 'https://${azurerm_linux_function_app.main.default_hostname}/api/migrate-ai-assessment?code=FUNCTION_KEY' -H 'Content-Type: application/json' -d '{\"test\": true}'"
  ]
}
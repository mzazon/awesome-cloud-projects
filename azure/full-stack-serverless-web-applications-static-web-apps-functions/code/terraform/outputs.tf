# Outputs for Azure Static Web Apps and Azure Functions Infrastructure
# This file defines all output values that provide important information about the deployed resources

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group"
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
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "Secondary access key of the storage account"
  value       = azurerm_storage_account.main.secondary_access_key
  sensitive   = true
}

# Storage Table Outputs
output "storage_table_name" {
  description = "Name of the storage table for tasks"
  value       = azurerm_storage_table.tasks.name
}

output "storage_table_id" {
  description = "ID of the storage table for tasks"
  value       = azurerm_storage_table.tasks.id
}

# Static Web App Outputs
output "static_web_app_name" {
  description = "Name of the Azure Static Web App"
  value       = azurerm_static_web_app.main.name
}

output "static_web_app_id" {
  description = "ID of the Azure Static Web App"
  value       = azurerm_static_web_app.main.id
}

output "static_web_app_default_hostname" {
  description = "Default hostname of the Azure Static Web App"
  value       = azurerm_static_web_app.main.default_host_name
}

output "static_web_app_url" {
  description = "URL of the Azure Static Web App"
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "static_web_app_api_key" {
  description = "API key for the Azure Static Web App"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

output "static_web_app_identity_principal_id" {
  description = "Principal ID of the Static Web App managed identity"
  value       = try(azurerm_static_web_app.main.identity[0].principal_id, null)
}

output "static_web_app_identity_tenant_id" {
  description = "Tenant ID of the Static Web App managed identity"
  value       = try(azurerm_static_web_app.main.identity[0].tenant_id, null)
}

# Custom Domain Outputs (if enabled)
output "custom_domain_name" {
  description = "Custom domain name for the Static Web App"
  value       = try(azurerm_static_web_app_custom_domain.main[0].domain_name, null)
}

output "custom_domain_validation_token" {
  description = "Validation token for the custom domain"
  value       = try(azurerm_static_web_app_custom_domain.main[0].validation_token, null)
  sensitive   = true
}

# Application Insights Outputs (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = try(azurerm_application_insights.main[0].name, null)
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = try(azurerm_application_insights.main[0].id, null)
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = try(azurerm_application_insights.main[0].instrumentation_key, null)
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = try(azurerm_application_insights.main[0].connection_string, null)
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = try(azurerm_application_insights.main[0].app_id, null)
}

# Log Analytics Workspace Outputs (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.main[0].name, null)
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.main[0].id, null)
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.main[0].primary_shared_key, null)
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.main[0].secondary_shared_key, null)
  sensitive   = true
}

# Key Vault Outputs (if enabled for production)
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = try(azurerm_key_vault.main[0].name, null)
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = try(azurerm_key_vault.main[0].id, null)
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = try(azurerm_key_vault.main[0].vault_uri, null)
}

# GitHub Integration Outputs (if configured)
output "github_repository_url" {
  description = "GitHub repository URL"
  value       = var.github_repository_url
}

output "github_branch" {
  description = "GitHub branch being deployed"
  value       = var.github_branch
}

# Deployment Configuration Outputs
output "app_location" {
  description = "Application source code location"
  value       = var.app_location
}

output "api_location" {
  description = "API source code location"
  value       = var.api_location
}

output "output_location" {
  description = "Build output location"
  value       = var.output_location
}

# Environment Configuration Outputs
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

# API Configuration Outputs
output "api_base_url" {
  description = "Base URL for API endpoints"
  value       = "https://${azurerm_static_web_app.main.default_host_name}/api"
}

output "tasks_api_url" {
  description = "URL for tasks API endpoint"
  value       = "https://${azurerm_static_web_app.main.default_host_name}/api/tasks"
}

# Security Configuration Outputs
output "https_only_enabled" {
  description = "Whether HTTPS only is enabled"
  value       = var.enable_https_only
}

output "public_access_enabled" {
  description = "Whether public access is enabled for storage"
  value       = var.enable_public_access
}

# Monitoring Configuration Outputs
output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_application_insights
}

output "backup_enabled" {
  description = "Whether backup is enabled"
  value       = var.enable_backup
}

output "cost_optimization_enabled" {
  description = "Whether cost optimization is enabled"
  value       = var.enable_cost_optimization
}

# Network Security Group Outputs (if enabled for production)
output "network_security_group_name" {
  description = "Name of the Network Security Group"
  value       = try(azurerm_network_security_group.main[0].name, null)
}

output "network_security_group_id" {
  description = "ID of the Network Security Group"
  value       = try(azurerm_network_security_group.main[0].id, null)
}

# Function App Environment Variables
output "function_app_settings" {
  description = "Environment variables for Azure Functions"
  value = {
    STORAGE_CONNECTION_STRING = azurerm_storage_account.main.primary_connection_string
    NODE_VERSION             = var.node_version
    FUNCTIONS_WORKER_RUNTIME = "node"
    WEBSITE_NODE_DEFAULT_VERSION = "~${var.node_version}"
    APPINSIGHTS_INSTRUMENTATIONKEY = try(azurerm_application_insights.main[0].instrumentation_key, "")
    APPLICATIONINSIGHTS_CONNECTION_STRING = try(azurerm_application_insights.main[0].connection_string, "")
  }
  sensitive = true
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group_name     = azurerm_resource_group.main.name
    storage_account_name    = azurerm_storage_account.main.name
    static_web_app_name     = azurerm_static_web_app.main.name
    static_web_app_url      = "https://${azurerm_static_web_app.main.default_host_name}"
    api_url                 = "https://${azurerm_static_web_app.main.default_host_name}/api"
    monitoring_enabled      = var.enable_application_insights
    custom_domain_enabled   = var.enable_custom_domain
    environment             = var.environment
    location                = azurerm_resource_group.main.location
  }
}

# Quick Start Instructions
output "quick_start_instructions" {
  description = "Quick start instructions for using the deployed resources"
  value = <<-EOT
    1. Your Azure Static Web App is deployed at: https://${azurerm_static_web_app.main.default_host_name}
    2. API endpoints are available at: https://${azurerm_static_web_app.main.default_host_name}/api
    3. Storage account: ${azurerm_storage_account.main.name}
    4. Tasks table: ${azurerm_storage_table.tasks.name}
    ${var.enable_application_insights ? "5. Application Insights: ${azurerm_application_insights.main[0].name}" : ""}
    ${var.github_repository_url != "" ? "6. GitHub repository: ${var.github_repository_url}" : ""}
    
    To deploy your application:
    1. Push your code to the configured GitHub repository
    2. GitHub Actions will automatically build and deploy your app
    3. Visit the Static Web App URL to see your application
  EOT
}
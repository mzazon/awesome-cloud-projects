# Outputs for the Azure Playwright Testing infrastructure

#####################################
# Resource Group Information
#####################################

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.playwright_testing.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.playwright_testing.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.playwright_testing.id
}

#####################################
# Application Insights Information
#####################################

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.playwright.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.playwright.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.playwright.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.playwright.app_id
}

#####################################
# Key Vault Information
#####################################

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.playwright.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.playwright.vault_uri
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.playwright.id
}

#####################################
# Log Analytics Workspace Information
#####################################

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.playwright.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.playwright.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.playwright.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.playwright.primary_shared_key
  sensitive   = true
}

#####################################
# Storage Account Information
#####################################

output "storage_account_name" {
  description = "Name of the storage account for test artifacts"
  value       = azurerm_storage_account.playwright_artifacts.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.playwright_artifacts.primary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.playwright_artifacts.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.playwright_artifacts.primary_blob_endpoint
}

#####################################
# Storage Container Information
#####################################

output "storage_containers" {
  description = "Storage container information"
  value = {
    screenshots = {
      name = azurerm_storage_container.screenshots.name
      url  = "${azurerm_storage_account.playwright_artifacts.primary_blob_endpoint}${azurerm_storage_container.screenshots.name}"
    }
    videos = {
      name = azurerm_storage_container.videos.name
      url  = "${azurerm_storage_account.playwright_artifacts.primary_blob_endpoint}${azurerm_storage_container.videos.name}"
    }
    reports = {
      name = azurerm_storage_container.reports.name
      url  = "${azurerm_storage_account.playwright_artifacts.primary_blob_endpoint}${azurerm_storage_container.reports.name}"
    }
  }
}

#####################################
# Monitoring Information
#####################################

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.playwright_alerts.name
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = azurerm_monitor_action_group.playwright_alerts.id
}

output "metric_alert_name" {
  description = "Name of the high failure rate metric alert"
  value       = azurerm_monitor_metric_alert.high_failure_rate.name
}

#####################################
# Test Configuration Information
#####################################

output "test_configuration" {
  description = "Test configuration information"
  value = {
    app_url                    = var.test_app_url
    username                   = var.test_username
    key_vault_name            = azurerm_key_vault.playwright.name
    application_insights_name = azurerm_application_insights.playwright.name
    storage_account_name      = azurerm_storage_account.playwright_artifacts.name
  }
  sensitive = true
}

#####################################
# Environment Variables for CI/CD
#####################################

output "environment_variables" {
  description = "Environment variables for CI/CD pipeline configuration"
  value = {
    AZURE_RESOURCE_GROUP           = azurerm_resource_group.playwright_testing.name
    AZURE_LOCATION                = azurerm_resource_group.playwright_testing.location
    KEYVAULT_NAME                 = azurerm_key_vault.playwright.name
    KEYVAULT_URI                  = azurerm_key_vault.playwright.vault_uri
    APPLICATION_INSIGHTS_NAME     = azurerm_application_insights.playwright.name
    LOG_ANALYTICS_WORKSPACE_ID    = azurerm_log_analytics_workspace.playwright.workspace_id
    STORAGE_ACCOUNT_NAME          = azurerm_storage_account.playwright_artifacts.name
    ACTION_GROUP_ID               = azurerm_monitor_action_group.playwright_alerts.id
  }
}

#####################################
# Azure CLI Commands for Setup
#####################################

output "setup_commands" {
  description = "Azure CLI commands for additional setup"
  value = {
    login_command = "az login"
    set_subscription = "az account set --subscription ${data.azurerm_client_config.current.subscription_id}"
    get_ai_connection_string = "az monitor app-insights component show --app ${azurerm_application_insights.playwright.name} --resource-group ${azurerm_resource_group.playwright_testing.name} --query connectionString -o tsv"
    get_keyvault_secret = "az keyvault secret show --vault-name ${azurerm_key_vault.playwright.name} --name AppInsightsConnectionString --query value -o tsv"
  }
}

#####################################
# Playwright Testing Service Information
#####################################

output "playwright_service_info" {
  description = "Information for configuring Azure Playwright Testing service"
  value = {
    supported_regions = [
      "eastus",
      "westus3", 
      "eastasia",
      "westeurope"
    ]
    current_region = lower(replace(azurerm_resource_group.playwright_testing.location, " ", ""))
    service_endpoint_format = "https://{region}.api.playwright.microsoft.com"
    portal_url = "https://aka.ms/mpt/portal"
    documentation_url = "https://docs.microsoft.com/en-us/azure/playwright-testing/"
  }
}

#####################################
# Resource Costs Estimation
#####################################

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    application_insights = "~$2-10 (based on data ingestion)"
    log_analytics = "~$2-15 (based on data retention and queries)"
    key_vault = "~$0.03 per 10,000 operations"
    storage_account = "~$1-5 (based on storage usage)"
    playwright_testing = "Preview pricing TBD"
    total_estimated = "~$5-30/month (excluding Playwright Testing)"
    note = "Costs vary based on usage patterns and data volume"
  }
}

#####################################
# Next Steps
#####################################

output "next_steps" {
  description = "Next steps for setting up Playwright Testing"
  value = {
    step_1 = "Navigate to https://aka.ms/mpt/portal to create Playwright Testing workspace"
    step_2 = "Configure workspace in the same region: ${azurerm_resource_group.playwright_testing.location}"
    step_3 = "Copy the service endpoint URL from the workspace"
    step_4 = "Set PLAYWRIGHT_SERVICE_URL environment variable"
    step_5 = "Install @azure/microsoft-playwright-testing npm package"
    step_6 = "Configure playwright.config.ts with Azure service integration"
    step_7 = "Run tests with: npm run test:azure"
  }
}
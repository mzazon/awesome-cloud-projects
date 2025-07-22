# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.main.location
}

# API Center Information
output "api_center_name" {
  description = "Name of the Azure API Center instance"
  value       = azurerm_api_center.main.name
}

output "api_center_id" {
  description = "ID of the Azure API Center instance"
  value       = azurerm_api_center.main.id
}

output "api_center_portal_url" {
  description = "URL of the API Center portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_api_center.main.id}"
}

output "api_center_metadata_schema_id" {
  description = "ID of the API lifecycle metadata schema"
  value       = azurerm_api_center_metadata_schema.lifecycle.id
}

# Sample APIs Information
output "sample_apis" {
  description = "Information about registered sample APIs"
  value = {
    for api_id, api in azurerm_api_center_api.sample_apis : api_id => {
      id          = api.id
      name        = api.name
      title       = api.title
      description = api.description
      kind        = api.kind
    }
  }
}

output "api_versions" {
  description = "Information about API versions"
  value = {
    for version_key, version in azurerm_api_center_api_version.sample_versions : version_key => {
      id              = version.id
      name            = version.name
      title           = version.title
      lifecycle_stage = version.lifecycle_stage
    }
  }
}

# Azure OpenAI Information
output "openai_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_id" {
  description = "ID of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "Endpoint URL of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_model_deployments" {
  description = "Information about OpenAI model deployments"
  value = {
    for deployment_name, deployment in azurerm_cognitive_deployment.openai_models : deployment_name => {
      id           = deployment.id
      name         = deployment.name
      model_name   = deployment.model[0].name
      model_version = deployment.model[0].version
      scale_type   = deployment.scale[0].type
      scale_capacity = deployment.scale[0].capacity
    }
  }
}

# Anomaly Detector Information
output "anomaly_detector_name" {
  description = "Name of the Anomaly Detector service"
  value       = azurerm_cognitive_account.anomaly_detector.name
}

output "anomaly_detector_id" {
  description = "ID of the Anomaly Detector service"
  value       = azurerm_cognitive_account.anomaly_detector.id
}

output "anomaly_detector_endpoint" {
  description = "Endpoint URL of the Anomaly Detector service"
  value       = azurerm_cognitive_account.anomaly_detector.endpoint
}

# API Management Information (if created)
output "api_management_name" {
  description = "Name of the Azure API Management instance"
  value       = var.create_api_management ? azurerm_api_management.main[0].name : null
}

output "api_management_id" {
  description = "ID of the Azure API Management instance"
  value       = var.create_api_management ? azurerm_api_management.main[0].id : null
}

output "api_management_gateway_url" {
  description = "Gateway URL of the API Management instance"
  value       = var.create_api_management ? azurerm_api_management.main[0].gateway_url : null
}

output "api_management_portal_url" {
  description = "Developer portal URL of the API Management instance"
  value       = var.create_api_management ? azurerm_api_management.main[0].portal_url : null
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

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

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.portal.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.portal.id
}

output "storage_account_primary_web_endpoint" {
  description = "Primary web endpoint of the storage account"
  value       = azurerm_storage_account.portal.primary_web_endpoint
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App for automation"
  value       = azurerm_logic_app_workflow.documentation_automation.name
}

output "logic_app_id" {
  description = "ID of the Logic App for automation"
  value       = azurerm_logic_app_workflow.documentation_automation.id
}

# Alert Configuration Information
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.main[0].id : null
}

output "metric_alert_name" {
  description = "Name of the API anomaly metric alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.api_anomaly[0].name : null
}

output "metric_alert_id" {
  description = "ID of the API anomaly metric alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.api_anomaly[0].id : null
}

# Authentication Information
output "current_tenant_id" {
  description = "Current Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "current_client_id" {
  description = "Current Azure client ID"
  value       = data.azurerm_client_config.current.client_id
}

output "current_subscription_id" {
  description = "Current Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

# CLI Commands for Post-Deployment Configuration
output "cli_commands" {
  description = "Useful CLI commands for post-deployment configuration"
  value = {
    view_api_center = "az apic service show --name ${azurerm_api_center.main.name} --resource-group ${azurerm_resource_group.main.name}"
    list_apis = "az apic api list --service-name ${azurerm_api_center.main.name} --resource-group ${azurerm_resource_group.main.name}"
    test_openai = "curl -X POST ${azurerm_cognitive_account.openai.endpoint}/openai/deployments/gpt-4/completions -H 'Content-Type: application/json' -H 'api-key: [API_KEY]' -d '{\"prompt\": \"Hello world\", \"max_tokens\": 100}'"
    view_storage_web = "az storage blob service-properties show --account-name ${azurerm_storage_account.portal.name} --properties staticWebsite"
  }
}

# Environment Variables for Local Development
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    AZURE_RESOURCE_GROUP     = azurerm_resource_group.main.name
    AZURE_LOCATION          = azurerm_resource_group.main.location
    API_CENTER_NAME         = azurerm_api_center.main.name
    OPENAI_ENDPOINT         = azurerm_cognitive_account.openai.endpoint
    ANOMALY_DETECTOR_ENDPOINT = azurerm_cognitive_account.anomaly_detector.endpoint
    APPLICATION_INSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    STORAGE_ACCOUNT_NAME    = azurerm_storage_account.portal.name
    LOG_ANALYTICS_WORKSPACE_ID = azurerm_log_analytics_workspace.main.id
  }
  sensitive = true
}

# Cost Information
output "cost_information" {
  description = "Estimated monthly cost information for deployed resources"
  value = {
    api_center_sku = var.api_center_sku
    openai_sku = var.openai_sku
    anomaly_detector_sku = var.anomaly_detector_sku
    api_management_sku = var.create_api_management ? var.api_management_sku : "Not created"
    storage_tier = var.storage_account_tier
    log_analytics_retention = "${var.log_analytics_retention_days} days"
    note = "Actual costs depend on usage patterns. Monitor Azure Cost Management for accurate billing."
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure API Center portal with custom branding and developer documentation",
    "2. Set up API import from existing API Management instances or third-party gateways",
    "3. Configure OpenAI models for automated documentation generation",
    "4. Set up anomaly detection rules based on your API traffic patterns",
    "5. Create custom Logic Apps workflows for API lifecycle automation",
    "6. Configure additional monitoring dashboards in Azure Monitor",
    "7. Set up API governance policies and approval workflows",
    "8. Test the complete API discovery and documentation pipeline"
  ]
}
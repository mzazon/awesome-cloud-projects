# Outputs for Azure Load Testing and Azure DevOps Performance Testing Infrastructure
# These outputs provide essential information for integration with Azure DevOps pipelines
# and configuration of performance testing automation

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group containing all performance testing resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Azure Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Azure Load Testing Outputs
output "load_test_name" {
  description = "Name of the Azure Load Testing resource for use in Azure DevOps pipelines"
  value       = azurerm_load_test.main.name
}

output "load_test_id" {
  description = "Azure Resource ID of the Load Testing service"
  value       = azurerm_load_test.main.id
}

output "load_test_data_plane_uri" {
  description = "Data plane URI for the Azure Load Testing service"
  value       = azurerm_load_test.main.dataplane_uri
}

output "load_test_managed_identity" {
  description = "Managed identity details for the Load Testing resource"
  value = var.enable_managed_identity ? {
    principal_id = azurerm_load_test.main.identity[0].principal_id
    tenant_id    = azurerm_load_test.main.identity[0].tenant_id
    type         = azurerm_load_test.main.identity[0].type
  } : null
}

# Application Insights Outputs
output "app_insights_name" {
  description = "Name of the Application Insights resource for performance monitoring"
  value       = azurerm_application_insights.main.name
}

output "app_insights_id" {
  description = "Azure Resource ID of the Application Insights resource"
  value       = azurerm_application_insights.main.id
}

output "app_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (legacy)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "Connection string for Application Insights (recommended for new integrations)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "app_insights_app_id" {
  description = "Application ID for Application Insights API access"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace for centralized logging"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Azure Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_resource_id" {
  description = "Full resource ID for Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics Workspace authentication"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Service Principal Outputs for Azure DevOps Integration
output "service_principal_application_id" {
  description = "Application (Client) ID of the service principal for Azure DevOps service connection"
  value       = azuread_application.devops_sp.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.devops_sp.object_id
}

output "service_principal_tenant_id" {
  description = "Azure AD Tenant ID for the service principal"
  value       = azuread_service_principal.devops_sp.application_tenant_id
}

output "service_principal_client_secret" {
  description = "Client secret for the service principal (use in Azure DevOps service connection)"
  value       = azuread_application_password.devops_sp.value
  sensitive   = true
}

output "service_principal_client_secret_key_id" {
  description = "Key ID of the client secret"
  value       = azuread_application_password.devops_sp.key_id
}

# Azure DevOps Service Connection Configuration
output "azure_devops_service_connection_config" {
  description = "Complete configuration for Azure DevOps service connection (JSON format)"
  value = jsonencode({
    servicePrincipalId  = azuread_application.devops_sp.client_id
    servicePrincipalKey = azuread_application_password.devops_sp.value
    tenantId           = azuread_service_principal.devops_sp.application_tenant_id
    subscriptionId     = data.azurerm_client_config.current.subscription_id
    subscriptionName   = data.azurerm_subscription.current.display_name
    environment        = "AzureCloud"
    scopeLevel         = "Subscription"
    creationMode       = "Manual"
  })
  sensitive = true
}

# Monitoring and Alerting Outputs
output "action_group_name" {
  description = "Name of the Action Group for performance alerts"
  value       = azurerm_monitor_action_group.performance_alerts.name
}

output "action_group_id" {
  description = "Azure Resource ID of the Action Group"
  value       = azurerm_monitor_action_group.performance_alerts.id
}

output "response_time_alert_id" {
  description = "Azure Resource ID of the response time metric alert"
  value       = azurerm_monitor_metric_alert.high_response_time.id
}

output "error_rate_alert_id" {
  description = "Azure Resource ID of the error rate metric alert"
  value       = azurerm_monitor_metric_alert.high_error_rate.id
}

# Performance Testing Configuration Outputs
output "performance_testing_config" {
  description = "Configuration object for performance testing automation"
  value = {
    load_test_resource_name     = azurerm_load_test.main.name
    load_test_resource_group    = azurerm_resource_group.main.name
    load_test_data_plane_uri    = azurerm_load_test.main.dataplane_uri
    app_insights_name          = azurerm_application_insights.main.name
    log_analytics_workspace    = azurerm_log_analytics_workspace.main.name
    response_time_threshold    = var.response_time_threshold_ms
    error_rate_threshold       = var.error_rate_threshold_percent
    alert_evaluation_frequency = var.alert_evaluation_frequency
    alert_window_size          = var.alert_window_size
    environment               = var.environment
    project                   = var.project
  }
}

# Azure CLI Commands for Quick Reference
output "azure_cli_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    list_load_tests = "az load test list --resource-group ${azurerm_resource_group.main.name}"
    create_test_run = "az load test create --test-id 'performance-test' --load-test-resource ${azurerm_load_test.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_app_insights = "az monitor app-insights component show --app ${azurerm_application_insights.main.name} --resource-group ${azurerm_resource_group.main.name}"
    query_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.main.workspace_id} --analytics-query 'LoadTestRuns | take 10'"
  }
}

# Resource Tags Output
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for estimating costs of deployed resources"
  value = {
    load_testing_pricing_note = "Azure Load Testing charges per virtual user hour (VUH). Pricing varies by region and test engine type."
    app_insights_pricing_note = "Application Insights charges based on data ingestion volume and retention period."
    log_analytics_pricing_note = "Log Analytics charges based on data ingestion and retention. ${var.log_analytics_sku} pricing tier selected."
    estimated_monthly_cost_range = "$50-200 USD depending on test frequency and data retention"
    cost_optimization_tips = [
      "Use appropriate retention periods for logs and metrics",
      "Monitor test execution frequency to control VUH usage",
      "Consider using Azure Cost Management for detailed cost tracking"
    ]
  }
}

# Data Sources for Current Azure Context
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Security and Compliance Information
output "security_considerations" {
  description = "Security and compliance information for the deployed solution"
  value = {
    rbac_roles_assigned = [
      "Load Test Contributor - Service Principal can manage load tests",
      "Monitoring Contributor - Service Principal can access monitoring data",
      "Application Insights Component Contributor - Service Principal can access App Insights"
    ]
    managed_identity_enabled = var.enable_managed_identity
    diagnostic_settings_enabled = var.enable_diagnostic_settings
    data_residency = "All data is stored in ${var.location} region"
    encryption_at_rest = "All services use Azure-managed encryption by default"
    network_security = "Consider implementing private endpoints for enhanced security in production environments"
  }
}

# Next Steps and Integration Guidance
output "integration_guidance" {
  description = "Next steps for integrating with Azure DevOps pipelines"
  value = {
    azure_devops_setup_steps = [
      "1. Create Azure DevOps service connection using the provided service principal details",
      "2. Import the JMeter test scripts into your repository",
      "3. Configure the Azure DevOps pipeline YAML with the load test resource details",
      "4. Set up pipeline variables for test configuration",
      "5. Run initial test to validate integration"
    ]
    required_pipeline_variables = {
      loadTestResource = azurerm_load_test.main.name
      loadTestResourceGroup = azurerm_resource_group.main.name
      appInsightsConnectionString = azurerm_application_insights.main.connection_string
      subscriptionId = data.azurerm_client_config.current.subscription_id
    }
    documentation_links = [
      "Azure Load Testing documentation: https://docs.microsoft.com/en-us/azure/load-testing/",
      "Azure DevOps integration guide: https://docs.microsoft.com/en-us/azure/load-testing/how-to-use-load-testing-in-devops",
      "JMeter test scripting: https://jmeter.apache.org/usermanual/"
    ]
  }
}
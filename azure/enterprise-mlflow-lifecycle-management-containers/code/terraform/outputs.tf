# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Machine Learning Workspace Outputs
output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the ML workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "mlflow_tracking_uri" {
  description = "MLflow tracking URI for the workspace"
  value       = "${azurerm_machine_learning_workspace.main.discovery_url}/mlflow"
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

# Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server URL for the container registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the container registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

# Container Apps Environment Outputs
output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_environment_default_domain" {
  description = "Default domain for the Container Apps environment"
  value       = azurerm_container_app_environment.main.default_domain
}

# Container App Outputs
output "container_app_name" {
  description = "Name of the Container App"
  value       = azurerm_container_app.model_serving.name
}

output "container_app_id" {
  description = "ID of the Container App"
  value       = azurerm_container_app.model_serving.id
}

output "container_app_fqdn" {
  description = "Fully qualified domain name of the Container App"
  value       = azurerm_container_app.model_serving.latest_revision_fqdn
}

output "container_app_url" {
  description = "Public URL of the Container App"
  value       = "https://${azurerm_container_app.model_serving.latest_revision_fqdn}"
}

# Model Serving Endpoints
output "model_serving_health_endpoint" {
  description = "Health check endpoint for the model serving app"
  value       = "https://${azurerm_container_app.model_serving.latest_revision_fqdn}/health"
}

output "model_serving_predict_endpoint" {
  description = "Prediction endpoint for the model serving app"
  value       = "https://${azurerm_container_app.model_serving.latest_revision_fqdn}/predict"
}

output "model_serving_info_endpoint" {
  description = "Model info endpoint for the model serving app"
  value       = "https://${azurerm_container_app.model_serving.latest_revision_fqdn}/model-info"
}

# Log Analytics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights instance"
  value       = azurerm_application_insights.main.app_id
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

# Security and Access Outputs
output "service_principal_id" {
  description = "ID of the service principal for the ML workspace"
  value       = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

output "service_principal_tenant_id" {
  description = "Tenant ID of the service principal"
  value       = azurerm_machine_learning_workspace.main.identity[0].tenant_id
}

# Monitoring Alert Outputs
output "alert_rule_names" {
  description = "Names of the created alert rules"
  value = var.enable_monitoring_alerts ? [
    azurerm_monitor_metric_alert.high_latency[0].name,
    azurerm_monitor_metric_alert.container_app_unhealthy[0].name,
    azurerm_monitor_metric_alert.low_model_accuracy[0].name
  ] : []
}

# Configuration Values for Client Setup
output "azure_configuration" {
  description = "Configuration values for Azure ML SDK setup"
  value = {
    subscription_id      = data.azurerm_client_config.current.subscription_id
    resource_group_name  = azurerm_resource_group.main.name
    workspace_name       = azurerm_machine_learning_workspace.main.name
    location            = azurerm_resource_group.main.location
  }
}

# Model Deployment Configuration
output "model_deployment_config" {
  description = "Configuration for model deployment"
  value = {
    model_name                  = var.model_name
    model_version              = var.model_version
    container_registry_server  = azurerm_container_registry.main.login_server
    container_app_environment  = azurerm_container_app_environment.main.name
    container_app_name         = azurerm_container_app.model_serving.name
  }
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    ml_workspace            = azurerm_machine_learning_workspace.main.name
    container_app_url       = "https://${azurerm_container_app.model_serving.latest_revision_fqdn}"
    container_registry      = azurerm_container_registry.main.login_server
    monitoring_enabled      = var.enable_monitoring_alerts
    private_endpoints       = var.enable_private_endpoints
    environment            = var.environment
    location               = var.location
  }
}
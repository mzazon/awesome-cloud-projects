# Output values for Azure Edge-Based Healthcare Analytics Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "The name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

# IoT Hub Information
output "iot_hub_name" {
  description = "The name of the IoT Hub"
  value       = azurerm_iothub.main.name
}

output "iot_hub_hostname" {
  description = "The hostname of the IoT Hub"
  value       = azurerm_iothub.main.hostname
}

output "iot_hub_connection_string" {
  description = "IoT Hub connection string for iothubowner policy"
  value       = "HostName=${azurerm_iothub.main.hostname};SharedAccessKeyName=iothubowner;SharedAccessKey=${azurerm_iothub.main.shared_access_policy[0].primary_key}"
  sensitive   = true
}

# IoT Edge Device Information
output "edge_device_id" {
  description = "The ID of the IoT Edge device"
  value       = azurerm_iothub_device.edge_device.name
}

output "edge_device_connection_string" {
  description = "Connection string for the IoT Edge device"
  value       = "HostName=${azurerm_iothub.main.hostname};DeviceId=${azurerm_iothub_device.edge_device.name};SharedAccessKey=${azurerm_iothub_device.edge_device.primary_key}"
  sensitive   = true
}

# Azure Health Data Services Information
output "health_workspace_name" {
  description = "The name of the Azure Health Data Services workspace"
  value       = azurerm_healthcare_workspace.main.name
}

output "fhir_service_name" {
  description = "The name of the FHIR service"
  value       = azurerm_healthcare_fhir_service.main.name
}

output "fhir_service_url" {
  description = "The URL of the FHIR service"
  value       = "https://${azurerm_healthcare_workspace.main.name}-${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
}

output "fhir_service_audience" {
  description = "The audience for FHIR service authentication"
  value       = "https://azurehealthcareapis.com"
}

# Function App Information
output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "The default hostname of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "The principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Account Information
output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# Key Vault Information
output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "The workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "The primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# SQL Edge Configuration Information
output "sql_edge_connection_info" {
  description = "Information for connecting to SQL Edge on the IoT Edge device"
  value = {
    server_name = "localhost,1433"
    username    = "sa"
    note        = "Password is stored in Key Vault secret: sql-edge-sa-password"
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps for completing the deployment"
  value = {
    edge_runtime_setup = "Configure IoT Edge runtime on your edge device using the edge device connection string"
    sql_edge_deployment = "Deploy SQL Edge module to the edge device using the provided deployment manifest"
    function_deployment = "Deploy function code to the Function App for FHIR transformation and alerting"
    fhir_configuration = "Configure FHIR service permissions and test connectivity"
    monitoring_setup = "Review Log Analytics workspace for monitoring and diagnostics"
  }
}

# Important Security Notes
output "security_notes" {
  description = "Important security considerations for production deployment"
  value = {
    key_vault_access = "Review and restrict Key Vault access policies for production use"
    network_security = "Configure network restrictions and private endpoints for production"
    fhir_authentication = "Set up proper authentication and authorization for FHIR service access"
    device_certificates = "Consider using X.509 certificates for device authentication in production"
    audit_compliance = "Enable all necessary audit logs for healthcare compliance requirements"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Recommendations for optimizing costs"
  value = {
    iot_hub_scaling = "Monitor IoT Hub usage and adjust SKU based on message volume"
    function_app_plan = "Consider Premium plan for consistent workloads or keep Consumption for sporadic loads"
    log_analytics_retention = "Adjust log retention period based on compliance requirements"
    storage_lifecycle = "Implement storage lifecycle policies for long-term medical data archival"
  }
}
# Output values for FHIR-compliant healthcare API orchestration infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.healthcare.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.healthcare.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.healthcare.id
}

# Healthcare Workspace and FHIR Service Information
output "healthcare_workspace_name" {
  description = "Name of the Azure Health Data Services workspace"
  value       = azurerm_healthcare_workspace.main.name
}

output "healthcare_workspace_id" {
  description = "ID of the Azure Health Data Services workspace"
  value       = azurerm_healthcare_workspace.main.id
}

output "fhir_service_name" {
  description = "Name of the FHIR service"
  value       = azurerm_healthcare_fhir_service.main.name
}

output "fhir_service_endpoint" {
  description = "FHIR service endpoint URL for healthcare applications"
  value       = "https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
}

output "fhir_service_id" {
  description = "ID of the FHIR service"
  value       = azurerm_healthcare_fhir_service.main.id
}

output "fhir_service_authentication_audience" {
  description = "Authentication audience for FHIR service"
  value       = azurerm_healthcare_fhir_service.main.authentication[0].audience
}

output "fhir_service_authentication_authority" {
  description = "Authentication authority for FHIR service"
  value       = azurerm_healthcare_fhir_service.main.authentication[0].authority
}

# Container Apps Environment Information
output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.healthcare.name
}

output "container_app_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.healthcare.id
}

output "container_app_environment_default_domain" {
  description = "Default domain for Container Apps environment"
  value       = azurerm_container_app_environment.healthcare.default_domain
}

# Container Apps Service Information
output "patient_service_name" {
  description = "Name of the patient management service"
  value       = azurerm_container_app.patient_service.name
}

output "patient_service_fqdn" {
  description = "Fully qualified domain name of the patient service"
  value       = azurerm_container_app.patient_service.latest_revision_fqdn
}

output "patient_service_url" {
  description = "URL of the patient management service"
  value       = "https://${azurerm_container_app.patient_service.latest_revision_fqdn}"
}

output "provider_notification_service_name" {
  description = "Name of the provider notification service"
  value       = azurerm_container_app.provider_notification_service.name
}

output "provider_notification_service_fqdn" {
  description = "Fully qualified domain name of the provider notification service"
  value       = azurerm_container_app.provider_notification_service.latest_revision_fqdn
}

output "provider_notification_service_url" {
  description = "URL of the provider notification service"
  value       = "https://${azurerm_container_app.provider_notification_service.latest_revision_fqdn}"
}

output "workflow_orchestration_service_name" {
  description = "Name of the workflow orchestration service"
  value       = azurerm_container_app.workflow_orchestration_service.name
}

output "workflow_orchestration_service_fqdn" {
  description = "Fully qualified domain name of the workflow orchestration service"
  value       = azurerm_container_app.workflow_orchestration_service.latest_revision_fqdn
}

output "workflow_orchestration_service_url" {
  description = "URL of the workflow orchestration service"
  value       = "https://${azurerm_container_app.workflow_orchestration_service.latest_revision_fqdn}"
}

# Communication Services Information
output "communication_service_name" {
  description = "Name of the Communication Services resource"
  value       = azurerm_communication_service.healthcare.name
}

output "communication_service_id" {
  description = "ID of the Communication Services resource"
  value       = azurerm_communication_service.healthcare.id
}

output "communication_service_primary_connection_string" {
  description = "Primary connection string for Communication Services"
  value       = azurerm_communication_service.healthcare.primary_connection_string
  sensitive   = true
}

output "communication_service_data_location" {
  description = "Data location for Communication Services"
  value       = azurerm_communication_service.healthcare.data_location
}

# API Management Information
output "api_management_name" {
  description = "Name of the API Management instance"
  value       = azurerm_api_management.healthcare.name
}

output "api_management_id" {
  description = "ID of the API Management instance"
  value       = azurerm_api_management.healthcare.id
}

output "api_management_gateway_url" {
  description = "Gateway URL for API Management"
  value       = azurerm_api_management.healthcare.gateway_url
}

output "api_management_developer_portal_url" {
  description = "Developer portal URL for API Management"
  value       = azurerm_api_management.healthcare.developer_portal_url
}

output "api_management_management_api_url" {
  description = "Management API URL for API Management"
  value       = azurerm_api_management.healthcare.management_api_url
}

output "api_management_identity_principal_id" {
  description = "Principal ID of the API Management managed identity"
  value       = azurerm_api_management.healthcare.identity[0].principal_id
}

# API Endpoints
output "patient_api_url" {
  description = "URL for the Patient Management API"
  value       = "${azurerm_api_management.healthcare.gateway_url}/patient"
}

output "provider_notification_api_url" {
  description = "URL for the Provider Notification API"
  value       = "${azurerm_api_management.healthcare.gateway_url}/notifications"
}

output "workflow_api_url" {
  description = "URL for the Workflow Orchestration API"
  value       = "${azurerm_api_management.healthcare.gateway_url}/workflows"
}

# Monitoring and Logging Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.healthcare.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.healthcare.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.healthcare.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.healthcare.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.healthcare.id
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights instance"
  value       = azurerm_application_insights.healthcare.app_id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.healthcare.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.healthcare.connection_string
  sensitive   = true
}

# Security and Compliance Information
output "tenant_id" {
  description = "Azure tenant ID for authentication"
  value       = data.azurerm_client_config.current.tenant_id
}

output "client_id" {
  description = "Azure client ID for authentication"
  value       = data.azurerm_client_config.current.client_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed healthcare infrastructure"
  value = {
    resource_group                = azurerm_resource_group.healthcare.name
    healthcare_workspace          = azurerm_healthcare_workspace.main.name
    fhir_service                 = azurerm_healthcare_fhir_service.main.name
    fhir_endpoint                = "https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
    container_apps_environment   = azurerm_container_app_environment.healthcare.name
    patient_service              = azurerm_container_app.patient_service.name
    provider_notification_service = azurerm_container_app.provider_notification_service.name
    workflow_orchestration_service = azurerm_container_app.workflow_orchestration_service.name
    communication_service        = azurerm_communication_service.healthcare.name
    api_management               = azurerm_api_management.healthcare.name
    api_gateway_url              = azurerm_api_management.healthcare.gateway_url
    log_analytics_workspace      = azurerm_log_analytics_workspace.healthcare.name
    application_insights         = azurerm_application_insights.healthcare.name
    environment                  = var.environment
    location                     = var.location
    compliance                   = "hipaa-hitrust"
    deployment_time              = timestamp()
  }
}

# Healthcare-specific Configuration
output "healthcare_configuration" {
  description = "Healthcare-specific configuration details"
  value = {
    fhir_version                 = var.fhir_version
    smart_proxy_enabled          = var.enable_smart_proxy
    rbac_enabled                 = var.enable_rbac
    diagnostic_logs_enabled      = var.enable_diagnostic_logs
    log_retention_days           = var.log_retention_days
    organization_name            = var.organization_name
    data_classification          = "phi"
    compliance_frameworks        = ["hipaa", "hitrust"]
    authentication_provider      = "azure-ad"
    communication_data_location  = var.communication_data_location
  }
}

# Service URLs for Healthcare Applications
output "service_urls" {
  description = "Service URLs for healthcare applications and integrations"
  value = {
    fhir_service              = "https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
    patient_api              = "${azurerm_api_management.healthcare.gateway_url}/patient"
    provider_notification_api = "${azurerm_api_management.healthcare.gateway_url}/notifications"
    workflow_api             = "${azurerm_api_management.healthcare.gateway_url}/workflows"
    api_management_portal    = azurerm_api_management.healthcare.developer_portal_url
    direct_patient_service   = "https://${azurerm_container_app.patient_service.latest_revision_fqdn}"
    direct_notification_service = "https://${azurerm_container_app.provider_notification_service.latest_revision_fqdn}"
    direct_workflow_service  = "https://${azurerm_container_app.workflow_orchestration_service.latest_revision_fqdn}"
  }
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}
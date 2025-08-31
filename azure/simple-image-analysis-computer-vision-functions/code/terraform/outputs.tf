# =============================================================================
# OUTPUTS FOR AZURE IMAGE ANALYSIS INFRASTRUCTURE
# =============================================================================
# These outputs provide essential information for deploying, testing, and 
# managing the image analysis solution.
# =============================================================================

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
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

# Computer Vision Service Information
output "computer_vision_name" {
  description = "Name of the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.name
}

output "computer_vision_endpoint" {
  description = "Endpoint URL for the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.endpoint
}

output "computer_vision_id" {
  description = "ID of the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.id
}

output "computer_vision_sku" {
  description = "SKU of the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.sku_name
}

# Computer Vision Keys (Sensitive)
output "computer_vision_primary_key" {
  description = "Primary access key for Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.primary_access_key
  sensitive   = true
}

output "computer_vision_secondary_key" {
  description = "Secondary access key for Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.secondary_access_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

output "storage_account_tier" {
  description = "Performance tier of the storage account"
  value       = azurerm_storage_account.functions.account_tier
}

# Storage Account Keys (Sensitive)
output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.functions.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.functions.primary_connection_string
  sensitive   = true
}

# App Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.functions.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.functions.id
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.functions.sku_name
}

output "service_plan_os_type" {
  description = "Operating system type of the App Service Plan"
  value       = azurerm_service_plan.functions.os_type
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_kind" {
  description = "Kind of the Function App"
  value       = azurerm_linux_function_app.main.kind
}

# Function Endpoints
output "analyze_function_url" {
  description = "URL for the image analysis function endpoint"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/analyze"
}

output "health_check_url" {
  description = "URL for the health check endpoint"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/health"
}

# Function App Identity
output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Application Insights Information (if enabled)
output "application_insights_name" {
  description = "Name of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.functions[0].name : null
}

output "application_insights_id" {
  description = "ID of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.functions[0].id : null
}

output "application_insights_app_id" {
  description = "Application ID of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.functions[0].app_id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.functions[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.functions[0].connection_string : null
  sensitive   = true
}

# Testing and Validation Information
output "curl_test_command" {
  description = "cURL command to test the health check endpoint"
  value       = "curl -X GET https://${azurerm_linux_function_app.main.default_hostname}/api/health"
}

output "postman_collection_url" {
  description = "URL to import Postman collection for testing"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/analyze"
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    resource_group      = azurerm_resource_group.main.name
    computer_vision    = azurerm_cognitive_account.computer_vision.name
    storage_account    = azurerm_storage_account.functions.name
    service_plan       = azurerm_service_plan.functions.name
    function_app       = azurerm_linux_function_app.main.name
    application_insights = var.enable_application_insights ? azurerm_application_insights.functions[0].name : "Not enabled"
  }
}

# Cost and Management Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate)"
  value = {
    computer_vision_f0 = var.computer_vision_sku == "F0" ? "Free (5,000 transactions/month)" : "Paid tier"
    storage_account   = "~$1-2 USD (minimal usage)"
    function_app_consumption = "~$0-5 USD (1M executions free)"
    application_insights = var.enable_application_insights ? "~$0-2 USD (5GB free)" : "Not enabled"
    total_estimate   = "~$1-10 USD/month for development usage"
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps for deploying the Function App code"
  value = {
    step_1 = "Install Azure Functions Core Tools: npm install -g azure-functions-core-tools@4 --unsafe-perm true"
    step_2 = "Initialize local project: func init --worker-runtime python --model V2"
    step_3 = "Create requirements.txt with: azure-functions>=1.20.0, azure-ai-vision-imageanalysis>=1.0.0"
    step_4 = "Deploy with: func azure functionapp publish ${azurerm_linux_function_app.main.name}"
    step_5 = "Test with: curl -X GET ${output.health_check_url.value}"
  }
}

# Security Configuration Summary
output "security_summary" {
  description = "Summary of security configurations applied"
  value = {
    https_only             = azurerm_linux_function_app.main.https_only
    minimum_tls_version    = var.minimum_tls_version
    managed_identity       = "SystemAssigned"
    storage_https_only     = azurerm_storage_account.functions.enable_https_traffic_only
    rbac_assignments      = "Cognitive Services User, Storage Blob Data Contributor"
  }
}
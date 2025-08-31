# Outputs for Azure Intelligent Product Catalog Infrastructure
# These outputs provide important information about the deployed resources

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

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint URL"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_container_urls" {
  description = "URLs of the created blob containers"
  value = {
    for name, container in azurerm_storage_container.containers :
    name => "${azurerm_storage_account.main.primary_blob_endpoint}${name}"
  }
}

# Azure OpenAI Service Information
output "openai_account_name" {
  description = "Name of the OpenAI cognitive account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_account_id" {
  description = "ID of the OpenAI cognitive account"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "Endpoint URL for the OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_access_key" {
  description = "Primary access key for the OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "Name of the deployed GPT-4o model"
  value       = azurerm_cognitive_deployment.gpt4o.name
}

output "openai_deployment_id" {
  description = "ID of the deployed GPT-4o model"
  value       = azurerm_cognitive_deployment.gpt4o.id
}

output "openai_model_info" {
  description = "Information about the deployed OpenAI model"
  value = {
    name    = azurerm_cognitive_deployment.gpt4o.model[0].name
    version = azurerm_cognitive_deployment.gpt4o.model[0].version
    format  = azurerm_cognitive_deployment.gpt4o.model[0].format
  }
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

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "ID of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Deployment Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed intelligent product catalog solution"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    storage_account   = azurerm_storage_account.main.name
    function_app      = azurerm_linux_function_app.main.name
    openai_service    = azurerm_cognitive_account.openai.name
    openai_deployment = azurerm_cognitive_deployment.gpt4o.name
    containers = [
      for container in var.blob_containers : container.name
    ]
    function_runtime = "${var.function_app_runtime} ${var.function_app_runtime_version}"
    openai_model     = "${var.openai_model_name}:${var.openai_model_version}"
    app_insights_enabled = var.enable_application_insights
  }
}

# Testing and Validation URLs
output "blob_upload_endpoints" {
  description = "Blob container endpoints for uploading product images"
  value = {
    product_images_container = "${azurerm_storage_account.main.primary_blob_endpoint}product-images"
    catalog_results_container = "${azurerm_storage_account.main.primary_blob_endpoint}catalog-results"
  }
}

# Azure CLI Commands for Testing
output "azure_cli_test_commands" {
  description = "Azure CLI commands for testing the deployment"
  value = {
    upload_test_image = "az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name product-images --name test-product.jpg --file ./test-product.jpg"
    list_catalog_results = "az storage blob list --account-name ${azurerm_storage_account.main.name} --container-name catalog-results --output table"
    download_result = "az storage blob download --account-name ${azurerm_storage_account.main.name} --container-name catalog-results --name test-product.jpg.json --file ./catalog-result.json"
    view_function_logs = "az functionapp logs tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Cost Estimation Information
output "cost_estimation_notes" {
  description = "Cost estimation information for the deployed resources"
  value = {
    storage_account = "Standard LRS storage: ~$0.021/GB/month for blob storage"
    function_app = var.function_app_plan_sku == "Y1" ? "Consumption plan: First 1M executions free, then $0.20 per million executions" : "Premium plan: Based on allocated vCPU and memory"
    openai_service = "OpenAI Service: Pay-per-token pricing varies by model and region"
    application_insights = var.enable_application_insights ? "Application Insights: First 5GB free per month, then $2.30/GB" : "Not enabled"
    estimated_monthly_cost = "Estimated $5-20/month for development workloads with moderate usage"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    storage_https_only = azurerm_storage_account.main.enable_https_traffic_only
    storage_min_tls_version = azurerm_storage_account.main.min_tls_version
    function_https_only = azurerm_linux_function_app.main.https_only
    managed_identity_enabled = length(azurerm_linux_function_app.main.identity) > 0
    rbac_assignments = [
      "Function App -> Storage Account: Storage Blob Data Contributor",
      "Function App -> OpenAI Service: Cognitive Services OpenAI User"
    ]
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Deploy the Function App code using Azure Functions Core Tools or VS Code",
    "2. Upload test product images to the 'product-images' container",
    "3. Monitor function execution logs to verify processing",
    "4. Check the 'catalog-results' container for generated catalog JSON files",
    "5. Configure any additional security policies or networking rules as needed",
    "6. Set up monitoring alerts in Application Insights for production use"
  ]
}
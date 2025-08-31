# Outputs for Azure Maps Store Locator Infrastructure
# These outputs provide essential information for configuring the store locator web application
# and verifying successful deployment of Azure resources

# Resource Group Information
output "resource_group_name" {
  description = "The name of the created resource group"
  value       = azurerm_resource_group.store_locator.name
}

output "resource_group_id" {
  description = "The Azure resource ID of the resource group"
  value       = azurerm_resource_group.store_locator.id
}

output "location" {
  description = "The Azure region where resources were deployed"
  value       = azurerm_resource_group.store_locator.location
}

# Azure Maps Account Information
output "maps_account_name" {
  description = "The name of the Azure Maps account"
  value       = azurerm_maps_account.store_locator.name
}

output "maps_account_id" {
  description = "The Azure resource ID of the Maps account"
  value       = azurerm_maps_account.store_locator.id
}

output "maps_sku_name" {
  description = "The pricing tier (SKU) of the Azure Maps account"
  value       = azurerm_maps_account.store_locator.sku_name
}

# Authentication Keys for Web Application
output "maps_primary_access_key" {
  description = "The primary subscription key for Azure Maps authentication"
  value       = azurerm_maps_account.store_locator.primary_access_key
  sensitive   = true
}

output "maps_secondary_access_key" {
  description = "The secondary subscription key for Azure Maps authentication (backup)"
  value       = azurerm_maps_account.store_locator.secondary_access_key
  sensitive   = true
}

# Client Identifier for Advanced Authentication
output "maps_client_id" {
  description = "The unique client identifier for the Azure Maps account"
  value       = azurerm_maps_account.store_locator.x_ms_client_id
}

# Managed Identity Information (if enabled)
output "maps_identity_principal_id" {
  description = "The principal ID of the system-assigned managed identity"
  value       = var.enable_system_managed_identity ? azurerm_maps_account.store_locator.identity[0].principal_id : null
}

output "maps_identity_tenant_id" {
  description = "The tenant ID of the system-assigned managed identity"
  value       = var.enable_system_managed_identity ? azurerm_maps_account.store_locator.identity[0].tenant_id : null
}

# Configuration Information for Web Application
output "web_application_config" {
  description = "Configuration object for the store locator web application"
  value = {
    subscription_key = azurerm_maps_account.store_locator.primary_access_key
    client_id        = azurerm_maps_account.store_locator.x_ms_client_id
    maps_account     = azurerm_maps_account.store_locator.name
    resource_group   = azurerm_resource_group.store_locator.name
    region          = azurerm_resource_group.store_locator.location
  }
  sensitive = true
}

# Resource Tags for Tracking
output "applied_tags" {
  description = "The tags applied to all resources"
  value       = local.common_tags
}

# Cost and Usage Information
output "deployment_summary" {
  description = "Summary of deployed resources and their configuration"
  value = {
    resource_group_name    = azurerm_resource_group.store_locator.name
    maps_account_name      = azurerm_maps_account.store_locator.name
    pricing_tier          = azurerm_maps_account.store_locator.sku_name
    location              = azurerm_resource_group.store_locator.location
    local_auth_enabled    = azurerm_maps_account.store_locator.local_authentication_enabled
    managed_identity      = var.enable_system_managed_identity
    estimated_monthly_cost = "Free tier: 1,000 transactions/month included"
  }
}

# Instructions for Next Steps
output "next_steps" {
  description = "Instructions for configuring and deploying the store locator web application"
  value = <<-EOT
    
    🎉 Azure Maps infrastructure deployed successfully!
    
    Next steps to deploy your store locator:
    
    1. Retrieve your Azure Maps subscription key:
       az maps account keys list --resource-group ${azurerm_resource_group.store_locator.name} --account-name ${azurerm_maps_account.store_locator.name}
    
    2. Update your web application with the subscription key:
       - Replace 'YOUR_AZURE_MAPS_KEY' in app.js with the primary access key
    
    3. Deploy your web application files (index.html, app.js, styles.css, stores.json) to a web server
    
    4. Test the store locator functionality:
       - Interactive map with store markers
       - Search functionality for locations
       - Clustering of nearby stores
       - Responsive mobile design
    
    5. Monitor usage in Azure portal to track API calls and costs
    
    📊 Free tier includes 1,000 transactions per month
    📍 Additional transactions: Pay-as-you-go pricing
    
    For production deployments, consider:
    - Using Microsoft Entra ID authentication instead of subscription keys
    - Implementing rate limiting and usage monitoring
    - Adding custom domains and SSL certificates
    - Integrating with Azure Monitor for application insights
    
  EOT
}
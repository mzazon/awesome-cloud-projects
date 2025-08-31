# Output values for Azure Weather Dashboard Infrastructure
# These outputs provide important information for accessing and managing
# the deployed weather dashboard application

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.weather_dashboard.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.weather_dashboard.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.weather_dashboard.location
}

# Static Web App Information
output "static_web_app_name" {
  description = "Name of the Azure Static Web App"
  value       = azurerm_static_web_app.weather_dashboard.name
}

output "static_web_app_id" {
  description = "ID of the Azure Static Web App"
  value       = azurerm_static_web_app.weather_dashboard.id
}

output "default_hostname" {
  description = "Default hostname of the Static Web App (primary URL)"
  value       = azurerm_static_web_app.weather_dashboard.default_host_name
}

output "static_web_app_url" {
  description = "Complete HTTPS URL of the weather dashboard"
  value       = "https://${azurerm_static_web_app.weather_dashboard.default_host_name}"
}

output "api_key" {
  description = "API key for the Static Web App (for deployments and management)"
  value       = azurerm_static_web_app.weather_dashboard.api_key
  sensitive   = true
}

# SKU and Configuration Information
output "sku_tier" {
  description = "SKU tier of the Static Web App"
  value       = azurerm_static_web_app.weather_dashboard.sku_tier
}

output "sku_size" {
  description = "SKU size of the Static Web App"
  value       = azurerm_static_web_app.weather_dashboard.sku_size
}

# Feature Configuration Status
output "preview_environments_enabled" {
  description = "Whether preview environments are enabled"
  value       = azurerm_static_web_app.weather_dashboard.preview_environments_enabled
}

output "configuration_file_changes_enabled" {
  description = "Whether configuration file changes are enabled"
  value       = azurerm_static_web_app.weather_dashboard.configuration_file_changes_enabled
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  value       = azurerm_static_web_app.weather_dashboard.public_network_access_enabled
}

# Repository Configuration (if configured)
output "repository_url" {
  description = "GitHub repository URL (if configured)"
  value       = var.repository_url != "" ? var.repository_url : "Not configured"
}

output "repository_branch" {
  description = "GitHub repository branch (if configured)"
  value       = var.repository_url != "" ? var.repository_branch : "Not configured"
}

# Deployment Information
output "deployment_instructions" {
  description = "Instructions for deploying the weather dashboard application"
  value = <<-EOT
    
    🌤️ Weather Dashboard Deployment Ready!
    
    1. Application URL: https://${azurerm_static_web_app.weather_dashboard.default_host_name}
    2. Static Web App Name: ${azurerm_static_web_app.weather_dashboard.name}
    3. Resource Group: ${azurerm_resource_group.weather_dashboard.name}
    
    Next Steps:
    1. Deploy your application code:
       - Frontend code should be in the 'src' directory
       - API code should be in the 'api' directory
       
    2. Using Azure CLI for deployment:
       az staticwebapp create --name ${azurerm_static_web_app.weather_dashboard.name} \
         --resource-group ${azurerm_resource_group.weather_dashboard.name} \
         --source https://github.com/yourusername/weather-dashboard \
         --location "${azurerm_resource_group.weather_dashboard.location}" \
         --branch main
    
    3. Or use the Azure Static Web Apps CLI:
       npm install -g @azure/static-web-apps-cli
       swa deploy --app-name ${azurerm_static_web_app.weather_dashboard.name} \
         --resource-group ${azurerm_resource_group.weather_dashboard.name}
    
    4. Configure your OpenWeatherMap API key in the Azure portal:
       - Navigate to the Static Web App
       - Go to Configuration
       - Add/update OPENWEATHER_API_KEY setting
    
    Resources Created:
    - Resource Group: ${azurerm_resource_group.weather_dashboard.name}
    - Static Web App: ${azurerm_static_web_app.weather_dashboard.name}
    - Integrated Azure Functions (serverless API)
    - Application Insights (monitoring)
    
    EOT
}

# Azure CLI Commands
output "useful_commands" {
  description = "Useful Azure CLI commands for managing the weather dashboard"
  value = {
    view_app = "az staticwebapp show --name ${azurerm_static_web_app.weather_dashboard.name} --resource-group ${azurerm_resource_group.weather_dashboard.name}"
    
    list_functions = "az staticwebapp functions list --name ${azurerm_static_web_app.weather_dashboard.name} --resource-group ${azurerm_resource_group.weather_dashboard.name}"
    
    view_settings = "az staticwebapp appsettings list --name ${azurerm_static_web_app.weather_dashboard.name} --resource-group ${azurerm_resource_group.weather_dashboard.name}"
    
    set_api_key = "az staticwebapp appsettings set --name ${azurerm_static_web_app.weather_dashboard.name} --resource-group ${azurerm_resource_group.weather_dashboard.name} --setting-names OPENWEATHER_API_KEY='your-api-key-here'"
    
    view_logs = "az staticwebapp logs show --name ${azurerm_static_web_app.weather_dashboard.name} --resource-group ${azurerm_resource_group.weather_dashboard.name}"
    
    delete_app = "az staticwebapp delete --name ${azurerm_static_web_app.weather_dashboard.name} --resource-group ${azurerm_resource_group.weather_dashboard.name} --yes"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the weather dashboard (Free tier)"
  value = var.static_web_app_sku_tier == "Free" ? "Free (within limits: 100 GB bandwidth, 0.5 GB storage)" : "Standard tier pricing applies - see Azure pricing calculator"
}

# Random suffix used in resource naming
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}
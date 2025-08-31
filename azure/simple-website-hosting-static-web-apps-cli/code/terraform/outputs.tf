# Output Values for Azure Static Web Apps Infrastructure
# These outputs provide essential information for deployment verification, integration, and management

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created Azure Resource Group containing all static web app resources"
  value       = azurerm_resource_group.static_web_app.name
}

output "resource_group_id" {
  description = "Full Azure Resource Manager ID of the resource group"
  value       = azurerm_resource_group.static_web_app.id
}

output "resource_group_location" {
  description = "Azure region where the resource group and resources are deployed"
  value       = azurerm_resource_group.static_web_app.location
}

# Static Web App Core Information
output "static_web_app_name" {
  description = "Name of the Azure Static Web App resource"
  value       = azurerm_static_web_app.main.name
}

output "static_web_app_id" {
  description = "Full Azure Resource Manager ID of the Static Web App"
  value       = azurerm_static_web_app.main.id
}

output "static_web_app_resource_id" {
  description = "Static Web App resource identifier for API operations"
  value       = azurerm_static_web_app.main.id
}

# URLs and Endpoints
output "default_hostname" {
  description = "Default hostname provided by Azure Static Web Apps for accessing the website"
  value       = azurerm_static_web_app.main.default_host_name
}

output "website_url" {
  description = "Complete HTTPS URL for accessing the deployed static website"
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "custom_domain_url" {
  description = "Custom domain URL if configured, otherwise null"
  value       = var.custom_domain != null ? "https://${var.custom_domain}" : null
}

# Deployment and Integration Information
output "deployment_token" {
  description = "Deployment token for Static Web App (sensitive - use for CI/CD configuration)"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

output "github_repository_url" {
  description = "GitHub repository URL configured for automated deployments"
  value       = var.github_repository_url
}

output "github_branch" {
  description = "GitHub branch configured for automated deployments"
  value       = var.github_repository_url != null ? var.github_branch : null
}

# Configuration Information
output "sku_tier" {
  description = "Pricing tier of the Static Web App (Free or Standard)"
  value       = azurerm_static_web_app.main.sku_tier
}

output "sku_size" {
  description = "SKU size of the Static Web App"
  value       = azurerm_static_web_app.main.sku_size
}

output "preview_environments_enabled" {
  description = "Whether preview environments are enabled for pull request testing"
  value       = azurerm_static_web_app.main.preview_environments_enabled
}

# Security and SSL Information
output "ssl_certificate_managed" {
  description = "Indicates that SSL certificates are automatically managed by Azure"
  value       = true
}

output "cdn_enabled" {
  description = "Indicates that global CDN distribution is enabled by default"
  value       = true
}

# Application Settings
output "app_settings_configured" {
  description = "Whether application settings (environment variables) are configured"
  value       = length(var.app_settings) > 0
}

# Custom Domain Information
output "custom_domain_configured" {
  description = "Whether a custom domain is configured for the Static Web App"
  value       = var.custom_domain != null
}

output "custom_domain_name" {
  description = "Custom domain name if configured"
  value       = var.custom_domain
}

output "custom_domain_validation_type" {
  description = "Domain validation type used for custom domain (if configured)"
  value       = var.custom_domain != null ? "cname-delegation" : null
}

# Monitoring and Diagnostics
output "monitoring_configured" {
  description = "Whether Azure Monitor diagnostic settings are configured"
  value       = var.static_web_app_sku_tier == "Standard"
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to the Static Web App resources for organization and cost management"
  value       = local.common_tags
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for deploying content to the Static Web App"
  value = {
    swa_cli = {
      login_command = "swa login --resource-group ${azurerm_resource_group.static_web_app.name} --app-name ${azurerm_static_web_app.main.name}"
      deploy_command = "swa deploy . --env production --resource-group ${azurerm_resource_group.static_web_app.name} --app-name ${azurerm_static_web_app.main.name}"
    }
    azure_cli = {
      show_command = "az staticwebapp show --name ${azurerm_static_web_app.main.name} --resource-group ${azurerm_resource_group.static_web_app.name}"
      list_environments = "az staticwebapp environment list --name ${azurerm_static_web_app.main.name} --resource-group ${azurerm_resource_group.static_web_app.name}"
    }
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost based on the selected SKU tier"
  value = var.static_web_app_sku_tier == "Free" ? {
    sku_tier = "Free"
    cost = "$0 USD/month"
    bandwidth_included = "100 GB/month"
    storage_included = "250 MB per app"
    custom_domains = "2 per app"
    staging_environments = "3 per app"
    note = "Free tier includes production-ready hosting with global CDN"
  } : {
    sku_tier = "Standard"
    cost = "~$9 USD/month"
    bandwidth_included = "100 GB/month (additional usage charged)"
    storage_included = "250 MB per app"
    custom_domains = "Unlimited"
    staging_environments = "Unlimited"
    additional_features = "Private endpoints, enhanced authentication, increased storage"
    note = "Standard tier provides enterprise features and higher limits"
  }
}

# Next Steps and Integration Points
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = {
    deployment = [
      "Install Azure Static Web Apps CLI: npm install -g @azure/static-web-apps-cli@latest",
      "Authenticate with Azure: swa login --resource-group ${azurerm_resource_group.static_web_app.name} --app-name ${azurerm_static_web_app.main.name}",
      "Deploy your static website: swa deploy . --env production",
      "Access your website at: https://${azurerm_static_web_app.main.default_host_name}"
    ]
    optional_configurations = [
      "Configure custom domain if needed",
      "Set up GitHub repository integration for automated deployments",
      "Configure application settings for dynamic content",
      "Enable Azure Functions API if backend functionality is required",
      "Set up monitoring and alerts for production environments"
    ]
    documentation_links = [
      "Azure Static Web Apps documentation: https://docs.microsoft.com/en-us/azure/static-web-apps/",
      "SWA CLI documentation: https://azure.github.io/static-web-apps-cli/",
      "Custom domain setup: https://docs.microsoft.com/en-us/azure/static-web-apps/custom-domain"
    ]
  }
}
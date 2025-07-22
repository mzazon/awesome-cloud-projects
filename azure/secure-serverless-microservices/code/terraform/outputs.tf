# ========================================
# Core Infrastructure Outputs
# ========================================

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources were created"
  value       = azurerm_resource_group.main.location
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ========================================
# Container Registry Outputs
# ========================================

output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for Container Registry (if admin enabled)"
  value       = var.container_registry_admin_enabled ? azurerm_container_registry.main.admin_username : null
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for Container Registry (if admin enabled)"
  value       = var.container_registry_admin_enabled ? azurerm_container_registry.main.admin_password : null
  sensitive   = true
}

# ========================================
# Key Vault Outputs
# ========================================

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_tenant_id" {
  description = "Tenant ID associated with the Key Vault"
  value       = azurerm_key_vault.main.tenant_id
}

output "key_vault_secrets" {
  description = "List of secrets stored in Key Vault"
  value = {
    database_connection = azurerm_key_vault_secret.database_connection.name
    api_key            = azurerm_key_vault_secret.api_key.name
    service_bus_connection = azurerm_key_vault_secret.service_bus_connection.name
  }
}

# ========================================
# Container Apps Environment Outputs
# ========================================

output "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_default_domain" {
  description = "Default domain for the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "container_apps_environment_static_ip" {
  description = "Static IP address of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}

# ========================================
# API Service Container App Outputs
# ========================================

output "api_service_name" {
  description = "Name of the API service Container App"
  value       = azurerm_container_app.api_service.name
}

output "api_service_id" {
  description = "ID of the API service Container App"
  value       = azurerm_container_app.api_service.id
}

output "api_service_url" {
  description = "Public URL of the API service Container App"
  value       = azurerm_container_app.api_service.ingress != null ? "https://${azurerm_container_app.api_service.ingress[0].fqdn}" : null
}

output "api_service_fqdn" {
  description = "Fully qualified domain name of the API service"
  value       = azurerm_container_app.api_service.ingress != null ? azurerm_container_app.api_service.ingress[0].fqdn : null
}

output "api_service_identity_principal_id" {
  description = "Principal ID of the API service managed identity"
  value       = azurerm_user_assigned_identity.api_service.principal_id
}

output "api_service_identity_client_id" {
  description = "Client ID of the API service managed identity"
  value       = azurerm_user_assigned_identity.api_service.client_id
}

output "api_service_latest_revision_name" {
  description = "Name of the latest revision of the API service"
  value       = azurerm_container_app.api_service.latest_revision_name
}

output "api_service_latest_revision_fqdn" {
  description = "FQDN of the latest revision of the API service"
  value       = azurerm_container_app.api_service.latest_revision_fqdn
}

# ========================================
# Worker Service Container App Outputs
# ========================================

output "worker_service_name" {
  description = "Name of the worker service Container App"
  value       = azurerm_container_app.worker_service.name
}

output "worker_service_id" {
  description = "ID of the worker service Container App"
  value       = azurerm_container_app.worker_service.id
}

output "worker_service_url" {
  description = "Internal URL of the worker service Container App"
  value       = azurerm_container_app.worker_service.ingress != null ? "https://${azurerm_container_app.worker_service.ingress[0].fqdn}" : null
}

output "worker_service_fqdn" {
  description = "Fully qualified domain name of the worker service"
  value       = azurerm_container_app.worker_service.ingress != null ? azurerm_container_app.worker_service.ingress[0].fqdn : null
}

output "worker_service_identity_principal_id" {
  description = "Principal ID of the worker service managed identity"
  value       = azurerm_user_assigned_identity.worker_service.principal_id
}

output "worker_service_identity_client_id" {
  description = "Client ID of the worker service managed identity"
  value       = azurerm_user_assigned_identity.worker_service.client_id
}

output "worker_service_latest_revision_name" {
  description = "Name of the latest revision of the worker service"
  value       = azurerm_container_app.worker_service.latest_revision_name
}

output "worker_service_latest_revision_fqdn" {
  description = "FQDN of the latest revision of the worker service"
  value       = azurerm_container_app.worker_service.latest_revision_fqdn
}

# ========================================
# Monitoring Outputs
# ========================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
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

output "application_insights_app_id" {
  description = "App ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# ========================================
# Security and Identity Outputs
# ========================================

output "managed_identities" {
  description = "Information about managed identities created"
  value = {
    api_service = {
      name         = azurerm_user_assigned_identity.api_service.name
      principal_id = azurerm_user_assigned_identity.api_service.principal_id
      client_id    = azurerm_user_assigned_identity.api_service.client_id
    }
    worker_service = {
      name         = azurerm_user_assigned_identity.worker_service.name
      principal_id = azurerm_user_assigned_identity.worker_service.principal_id
      client_id    = azurerm_user_assigned_identity.worker_service.client_id
    }
  }
}

output "current_user_object_id" {
  description = "Object ID of the current user/service principal"
  value       = data.azurerm_client_config.current.object_id
}

output "current_tenant_id" {
  description = "Tenant ID of the current Azure AD tenant"
  value       = data.azurerm_client_config.current.tenant_id
}

# ========================================
# Configuration and Deployment Outputs
# ========================================

output "deployment_information" {
  description = "Summary of deployed resources and their configuration"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    environment       = var.environment
    project_name      = var.project_name
    
    container_registry = {
      name         = azurerm_container_registry.main.name
      login_server = azurerm_container_registry.main.login_server
      sku          = azurerm_container_registry.main.sku
    }
    
    key_vault = {
      name = azurerm_key_vault.main.name
      uri  = azurerm_key_vault.main.vault_uri
    }
    
    container_apps = {
      environment = azurerm_container_app_environment.main.name
      api_service = {
        name = azurerm_container_app.api_service.name
        url  = azurerm_container_app.api_service.ingress != null ? "https://${azurerm_container_app.api_service.ingress[0].fqdn}" : null
      }
      worker_service = {
        name = azurerm_container_app.worker_service.name
        url  = azurerm_container_app.worker_service.ingress != null ? "https://${azurerm_container_app.worker_service.ingress[0].fqdn}" : null
      }
    }
    
    monitoring = {
      log_analytics      = azurerm_log_analytics_workspace.main.name
      application_insights = azurerm_application_insights.main.name
    }
  }
}

# ========================================
# Verification Commands
# ========================================

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_resource_group = "az group show --name ${azurerm_resource_group.main.name}"
    check_container_registry = "az acr show --name ${azurerm_container_registry.main.name}"
    check_key_vault = "az keyvault show --name ${azurerm_key_vault.main.name}"
    check_container_apps_environment = "az containerapp env show --name ${azurerm_container_app_environment.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_api_service = "az containerapp show --name ${azurerm_container_app.api_service.name} --resource-group ${azurerm_resource_group.main.name}"
    check_worker_service = "az containerapp show --name ${azurerm_container_app.worker_service.name} --resource-group ${azurerm_resource_group.main.name}"
    view_api_service_logs = "az containerapp logs show --name ${azurerm_container_app.api_service.name} --resource-group ${azurerm_resource_group.main.name} --tail 50"
    view_worker_service_logs = "az containerapp logs show --name ${azurerm_container_app.worker_service.name} --resource-group ${azurerm_resource_group.main.name} --tail 50"
  }
}

# ========================================
# Next Steps
# ========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the API service by visiting: ${azurerm_container_app.api_service.ingress != null ? "https://${azurerm_container_app.api_service.ingress[0].fqdn}" : "URL not available"}",
    "Check container logs using the Azure CLI commands provided in verification_commands output",
    "Monitor application performance in Application Insights: https://portal.azure.com/#resource${azurerm_application_insights.main.id}",
    "Review Key Vault secrets: https://portal.azure.com/#resource${azurerm_key_vault.main.id}",
    "Configure custom domains and SSL certificates for production use",
    "Set up CI/CD pipelines for automated container deployments",
    "Configure additional monitoring alerts based on your requirements",
    "Implement network security groups and private endpoints for enhanced security"
  ]
}
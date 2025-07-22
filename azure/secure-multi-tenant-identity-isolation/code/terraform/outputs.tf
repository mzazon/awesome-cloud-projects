# Outputs for Multi-Tenant Customer Identity Isolation Infrastructure
# These outputs provide essential information for post-deployment configuration and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the main resource group containing the multi-tenant infrastructure"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "management_resource_group_name" {
  description = "Name of the management resource group for administrative services"
  value       = azurerm_resource_group.management.name
}

# Networking Information
output "virtual_network_id" {
  description = "Resource ID of the virtual network for private connectivity"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet"
  value       = azurerm_subnet.private_endpoints.id
}

output "api_management_subnet_id" {
  description = "Resource ID of the API Management subnet"
  value       = azurerm_subnet.api_management.id
}

# API Management Information
output "api_management_name" {
  description = "Name of the API Management instance"
  value       = azurerm_api_management.main.name
}

output "api_management_id" {
  description = "Resource ID of the API Management instance"
  value       = azurerm_api_management.main.id
}

output "api_management_gateway_url" {
  description = "Gateway URL for the API Management instance"
  value       = azurerm_api_management.main.gateway_url
}

output "api_management_private_ip_addresses" {
  description = "Private IP addresses of the API Management instance"
  value       = azurerm_api_management.main.private_ip_addresses
}

output "api_management_principal_id" {
  description = "Principal ID of the API Management managed identity"
  value       = azurerm_api_management.main.identity[0].principal_id
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for tenant secret management"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for API access"
  value       = azurerm_key_vault.main.vault_uri
}

# Tenant Configuration Information
output "tenant_secret_names" {
  description = "Names of the tenant-specific secrets stored in Key Vault"
  value       = { for k, v in azurerm_key_vault_secret.tenant_secrets : k => v.name }
}

output "configured_tenants" {
  description = "List of configured tenant identifiers"
  value       = keys(var.tenant_configurations)
}

# Private Endpoint Information
output "key_vault_private_endpoint_id" {
  description = "Resource ID of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.key_vault.id
}

output "api_management_private_endpoint_id" {
  description = "Resource ID of the API Management private endpoint"
  value       = azurerm_private_endpoint.api_management.id
}

output "monitor_private_endpoint_id" {
  description = "Resource ID of the Azure Monitor private endpoint (if enabled)"
  value       = var.enable_private_link_monitoring ? azurerm_private_endpoint.monitor[0].id : null
}

# Monitoring and Logging Information
output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (Workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Storage Account Information
output "audit_storage_account_name" {
  description = "Name of the storage account for audit logs"
  value       = azurerm_storage_account.audit.name
}

output "audit_storage_account_id" {
  description = "Resource ID of the audit storage account"
  value       = azurerm_storage_account.audit.id
}

output "audit_storage_primary_blob_endpoint" {
  description = "Primary blob endpoint for the audit storage account"
  value       = azurerm_storage_account.audit.primary_blob_endpoint
}

# Security and Compliance Information
output "key_vault_soft_delete_enabled" {
  description = "Whether soft delete is enabled on the Key Vault"
  value       = azurerm_key_vault.main.soft_delete_retention_days > 0
}

output "key_vault_purge_protection_enabled" {
  description = "Whether purge protection is enabled on the Key Vault"
  value       = azurerm_key_vault.main.purge_protection_enabled
}

output "rbac_authorization_enabled" {
  description = "Whether RBAC authorization is enabled for Key Vault"
  value       = azurerm_key_vault.main.enable_rbac_authorization
}

# Alert Configuration
output "tenant_isolation_alert_id" {
  description = "Resource ID of the tenant isolation violation alert (if enabled)"
  value       = var.alert_enabled ? azurerm_monitor_metric_alert.tenant_isolation_violations[0].id : null
}

# API Configuration
output "tenant_isolation_api_name" {
  description = "Name of the tenant isolation API in API Management"
  value       = azurerm_api_management_api.tenant_isolation.name
}

output "tenant_isolation_api_path" {
  description = "Path of the tenant isolation API"
  value       = azurerm_api_management_api.tenant_isolation.path
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_string.suffix.result
}

# Configuration Summary for External ID Setup
output "external_id_setup_instructions" {
  description = "Instructions for completing the Azure External ID tenant setup"
  value = {
    message = "Manual setup required for Azure External ID customer tenants"
    tenants = {
      for k, v in var.tenant_configurations : k => {
        display_name = v.display_name
        description  = v.description
        setup_url    = "https://portal.azure.com/#create/Microsoft.ExternalIdentity"
      }
    }
    next_steps = [
      "1. Navigate to Azure Portal and create External ID customer tenants",
      "2. Configure each tenant with external configuration for customer identity management",
      "3. Set up user flows and custom policies for each customer tenant",
      "4. Configure tenant-specific branding and user experience",
      "5. Test cross-tenant isolation by attempting authentication between tenants"
    ]
  }
}

# Connection Strings and URLs for Integration Testing
output "test_endpoints" {
  description = "Endpoints for testing tenant isolation functionality"
  value = {
    api_gateway_test_url = "${azurerm_api_management.main.gateway_url}/api/test"
    required_headers = {
      "X-Tenant-ID" = "One of: ${join(", ", keys(var.tenant_configurations))}"
      "Content-Type" = "application/json"
    }
    example_curl_commands = {
      for tenant_id in keys(var.tenant_configurations) :
      tenant_id => "curl -X GET '${azurerm_api_management.main.gateway_url}/api/test' -H 'X-Tenant-ID: ${tenant_id}' -H 'Content-Type: application/json'"
    }
  }
}

# KQL Queries for Monitoring
output "monitoring_queries" {
  description = "Sample KQL queries for monitoring tenant isolation"
  value = {
    tenant_isolation_violations = <<-EOT
      ApiManagementGatewayLogs
      | where TimeGenerated > ago(24h)
      | extend TenantId = tostring(parse_json(RequestHeaders)["X-Tenant-ID"])
      | where isempty(TenantId) or TenantId !in (${jsonencode(keys(var.tenant_configurations))})
      | project TimeGenerated, TenantId, Method, Url, ResponseCode, ClientIP
      | order by TimeGenerated desc
    EOT
    
    cross_tenant_access_attempts = <<-EOT
      ApiManagementGatewayLogs
      | where TimeGenerated > ago(24h)
      | extend TenantId = tostring(parse_json(RequestHeaders)["X-Tenant-ID"])
      | extend RequestedTenant = extract(@"tenant-([ab])", 1, Url)
      | where TenantId != RequestedTenant and isnotempty(RequestedTenant)
      | project TimeGenerated, TenantId, RequestedTenant, Method, Url, ResponseCode
    EOT
  }
}
# Multi-Tenant Customer Identity Isolation Infrastructure
# This Terraform configuration deploys a comprehensive multi-tenant solution using Azure External ID,
# Azure Resource Manager Private Link, API Management, and Key Vault for complete tenant isolation

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

# Local values for computed configurations
locals {
  # Resource naming with consistent patterns
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}"
  vnet_name          = "vnet-${var.project_name}-isolation"
  apim_name          = "apim-${var.project_name}-${random_string.suffix.result}"
  key_vault_name     = "kv-${var.project_name}-${random_string.suffix.result}"
  storage_name       = "st${var.project_name}${random_string.suffix.result}"
  workspace_name     = "law-${var.project_name}-isolation"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    DeployedBy    = "terraform"
    ProjectName   = var.project_name
    Environment   = var.environment
    LastModified  = timestamp()
  })
}

# Main Resource Group for the multi-tenant infrastructure
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  
  tags = merge(local.common_tags, {
    Purpose = "multi-tenant-identity-isolation"
  })
}

# Secondary Resource Group for management services
resource "azurerm_resource_group" "management" {
  name     = "rg-${var.project_name}-management"
  location = var.location
  
  tags = merge(local.common_tags, {
    Purpose = "tenant-management"
    Scope   = "private-management"
  })
}

# Virtual Network with dedicated subnets for isolation
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  
  tags = merge(local.common_tags, {
    Purpose = "private-network-isolation"
  })
}

# Subnet for private endpoints - critical for network-level isolation
resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoint_subnet_address_prefix]
  
  # Disable network policies for private endpoints
  private_endpoint_network_policies_enabled = false
}

# Subnet for API Management with specific networking requirements
resource "azurerm_subnet" "api_management" {
  name                 = "api-management"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.api_management_subnet_address_prefix]
}

# Log Analytics Workspace for centralized monitoring and tenant isolation tracking
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Purpose = "tenant-isolation-monitoring"
  })
}

# Azure Monitor Private Link Scope for secure management operations
resource "azurerm_monitor_private_link_scope" "main" {
  count = var.enable_private_link_monitoring ? 1 : 0
  
  name                = "pls-arm-management"
  resource_group_name = azurerm_resource_group.management.name
  
  tags = merge(local.common_tags, {
    Purpose = "private-management-monitoring"
  })
}

# Private Endpoint for Azure Monitor management
resource "azurerm_private_endpoint" "monitor" {
  count = var.enable_private_link_monitoring ? 1 : 0
  
  name                = "pe-arm-management"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "arm-management-connection"
    private_connection_resource_id = azurerm_monitor_private_link_scope.main[0].id
    is_manual_connection           = false
    subresource_names              = ["azuremonitor"]
  }
  
  tags = merge(local.common_tags, {
    Purpose = "secure-management-endpoint"
  })
}

# Key Vault for tenant-specific secret isolation with enhanced security
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = var.soft_delete_retention_days
  
  # Enhanced security configuration for enterprise multi-tenant environments
  enable_rbac_authorization = var.enable_rbac_authorization
  purge_protection_enabled  = var.enable_purge_protection
  
  # Network access restrictions for private endpoint only access
  public_network_access_enabled = false
  
  tags = merge(local.common_tags, {
    Purpose       = "tenant-secret-isolation"
    SecurityLevel = "high"
  })
}

# Private Endpoint for Key Vault ensuring secure secret access
resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-keyvault"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "keyvault-private-connection"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
  
  tags = merge(local.common_tags, {
    Purpose = "secure-secret-access"
  })
}

# API Management instance with managed identity for secure Key Vault access
resource "azurerm_api_management" "main" {
  name                = local.apim_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name
  
  # Enable managed identity for secure Azure service integration
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "tenant-api-gateway"
  })
}

# Private Endpoint for API Management gateway ensuring private connectivity
resource "azurerm_private_endpoint" "api_management" {
  name                = "pe-apim-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "apim-private-connection"
    private_connection_resource_id = azurerm_api_management.main.id
    is_manual_connection           = false
    subresource_names              = ["gateway"]
  }
  
  tags = merge(local.common_tags, {
    Purpose = "private-api-gateway"
  })
}

# Role assignment for API Management to access Key Vault secrets
resource "azurerm_role_assignment" "apim_key_vault" {
  count = var.enable_rbac_authorization ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.main.identity[0].principal_id
}

# Tenant-specific secrets in Key Vault with logical separation
resource "azurerm_key_vault_secret" "tenant_secrets" {
  for_each = var.tenant_configurations
  
  name         = "${each.key}-api-key"
  value        = "secure-api-key-${each.key}-${random_string.suffix.result}"
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.common_tags, {
    TenantId = each.key
    Purpose  = "tenant-api-authentication"
  })
  
  depends_on = [azurerm_role_assignment.apim_key_vault]
}

# API Management Policy for tenant isolation enforcement
resource "azurerm_api_management_api" "tenant_isolation" {
  name                = "tenant-isolation-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Tenant Isolation API"
  path                = "api"
  protocols           = ["https"]
  
  service_url = "https://backend.internal.com"
  
  # API specification for tenant-aware operations
  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.1"
      info = {
        title   = "Tenant Isolation API"
        version = "1.0"
      }
      paths = {
        "/test" = {
          get = {
            summary = "Test tenant isolation"
            parameters = [
              {
                name     = "X-Tenant-ID"
                in       = "header"
                required = true
                schema = {
                  type = "string"
                  enum = keys(var.tenant_configurations)
                }
              }
            ]
          }
        }
      }
    })
  }
  
  tags = merge(local.common_tags, {
    Purpose = "tenant-isolation-enforcement"
  })
}

# API Management Policy for comprehensive tenant isolation
resource "azurerm_api_management_api_policy" "tenant_isolation" {
  api_name            = azurerm_api_management_api.tenant_isolation.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  xml_content = templatefile("${path.module}/policies/tenant-isolation-policy.xml", {
    key_vault_name = azurerm_key_vault.main.name
    tenant_list    = jsonencode(keys(var.tenant_configurations))
  })
}

# Diagnostic Settings for API Management monitoring
resource "azurerm_monitor_diagnostic_setting" "api_management" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name               = "apim-tenant-isolation-logs"
  target_resource_id = azurerm_api_management.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "GatewayLogs"
  }
  
  metric {
    category = "Gateway Requests"
    enabled  = true
  }
}

# Alert Rules for tenant isolation violations
resource "azurerm_monitor_metric_alert" "tenant_isolation_violations" {
  count = var.alert_enabled ? 1 : 0
  
  name                = "tenant-isolation-violation-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_api_management.main.id]
  description         = "Alert when API Management returns 403 responses indicating potential tenant isolation violations"
  severity            = var.alert_severity
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.ApiManagement/service"
    metric_name      = "Requests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 1
    
    dimension {
      name     = "GatewayResponseCode"
      operator = "Include"
      values   = ["403"]
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose   = "security-monitoring"
    AlertType = "tenant-isolation"
  })
}

# Storage Account for audit logs and compliance (optional enhancement)
resource "azurerm_storage_account" "audit" {
  name                     = local.storage_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Enhanced security for audit data
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  tags = merge(local.common_tags, {
    Purpose = "audit-logs"
  })
}

# Private Endpoint for Storage Account
resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-audit"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "storage-audit-connection"
    private_connection_resource_id = azurerm_storage_account.audit.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
  
  tags = merge(local.common_tags, {
    Purpose = "secure-audit-storage"
  })
}
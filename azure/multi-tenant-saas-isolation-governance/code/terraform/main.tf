# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  resource_suffix = random_string.suffix.result
  common_tags = merge(var.tags, {
    Environment = var.environment
    CreatedBy   = "Terraform"
    Purpose     = "Multi-Tenant SaaS Platform"
  })
}

# Control plane resource group
resource "azurerm_resource_group" "control_plane" {
  name     = "rg-${var.resource_prefix}-control-plane-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Key Vault for centralized secret management
resource "azurerm_key_vault" "saas_platform" {
  name                = "kv-${var.resource_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.control_plane.location
  resource_group_name = azurerm_resource_group.control_plane.name
  
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  purge_protection_enabled    = true
  enable_rbac_authorization   = true
  
  public_network_access_enabled = var.enable_public_network_access
  
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = local.common_tags
}

# Managed identity for deployment operations
resource "azurerm_user_assigned_identity" "deployment_identity" {
  name                = "mi-deployment-${var.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.control_plane.name
  location            = azurerm_resource_group.control_plane.location
  
  tags = local.common_tags
}

# Log Analytics workspace for platform monitoring
resource "azurerm_log_analytics_workspace" "platform_workspace" {
  name                = "law-${var.resource_prefix}-platform-${local.resource_suffix}"
  location            = azurerm_resource_group.control_plane.location
  resource_group_name = azurerm_resource_group.control_plane.name
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Application Insights for platform monitoring
resource "azurerm_application_insights" "platform_insights" {
  name                = "ai-${var.resource_prefix}-platform-${local.resource_suffix}"
  location            = azurerm_resource_group.control_plane.location
  resource_group_name = azurerm_resource_group.control_plane.name
  
  workspace_id     = azurerm_log_analytics_workspace.platform_workspace.id
  application_type = "web"
  
  tags = local.common_tags
}

# Azure AD application for workload identity
resource "azuread_application" "workload_identity" {
  display_name     = "SaaS-Tenant-Workload-${var.resource_prefix}-${local.resource_suffix}"
  sign_in_audience = "AzureADMyOrg"
  
  owners = [data.azuread_client_config.current.object_id]
  
  tags = ["terraform", "multi-tenant", "saas", "workload-identity"]
}

# Service principal for workload identity
resource "azuread_service_principal" "workload_identity" {
  application_id = azuread_application.workload_identity.application_id
  
  owners = [data.azuread_client_config.current.object_id]
  
  tags = ["terraform", "multi-tenant", "saas", "workload-identity"]
}

# Federated identity credential for workload identity
resource "azuread_application_federated_identity_credential" "workload_federation" {
  application_object_id = azuread_application.workload_identity.object_id
  display_name          = "tenant-workload-federation"
  description           = "Federated identity for tenant workload"
  
  issuer    = "${var.workload_identity_issuer}${data.azurerm_client_config.current.tenant_id}/"
  subject   = var.workload_identity_subject
  audiences = [var.workload_identity_audience]
}

# Custom role definition for tenant administrators
resource "azurerm_role_definition" "tenant_admin" {
  name        = "Tenant Administrator - ${var.resource_prefix}-${local.resource_suffix}"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Full control over tenant-specific resources"
  
  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
      "Microsoft.Storage/storageAccounts/*",
      "Microsoft.Network/virtualNetworks/*",
      "Microsoft.Network/networkSecurityGroups/*",
      "Microsoft.Compute/virtualMachines/*",
      "Microsoft.KeyVault/vaults/read",
      "Microsoft.KeyVault/vaults/secrets/read"
    ]
    
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/*"
    ]
  }
  
  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

# Custom role definition for tenant users
resource "azurerm_role_definition" "tenant_user" {
  name        = "Tenant User - ${var.resource_prefix}-${local.resource_suffix}"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Read-only access to tenant-specific resources"
  
  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/networkSecurityGroups/read"
    ]
    
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
    ]
  }
  
  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

# Azure Policy definition for tenant resource tagging
resource "azurerm_policy_definition" "tenant_tagging" {
  name         = "require-tenant-tags-${local.resource_suffix}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require Tenant Tags"
  description  = "Ensures all resources have required tenant identification tags"
  
  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field = "type"
          notIn = [
            "Microsoft.Resources/resourceGroups",
            "Microsoft.Resources/subscriptions"
          ]
        },
        {
          anyOf = [
            {
              field  = "tags['TenantId']"
              exists = "false"
            },
            {
              field  = "tags['Environment']"
              exists = "false"
            }
          ]
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

# Azure Policy definition for network security groups
resource "azurerm_policy_definition" "network_security_groups" {
  name         = "require-network-security-groups-${local.resource_suffix}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require Network Security Groups"
  description  = "Ensures all virtual networks have network security groups"
  
  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/virtualNetworks"
        },
        {
          field  = "Microsoft.Network/virtualNetworks/subnets[*].networkSecurityGroup.id"
          exists = "false"
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

# Role assignment for deployment identity
resource "azurerm_role_assignment" "deployment_identity_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deployment_identity.principal_id
}

# Role assignment for workload identity
resource "azurerm_role_assignment" "workload_identity_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.workload_identity.object_id
}

# Key Vault access policy for deployment identity
resource "azurerm_role_assignment" "deployment_identity_keyvault" {
  scope                = azurerm_key_vault.saas_platform.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.deployment_identity.principal_id
}

# Key Vault access policy for workload identity
resource "azurerm_role_assignment" "workload_identity_keyvault" {
  scope                = azurerm_key_vault.saas_platform.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.workload_identity.object_id
}

# Tenant resource groups
resource "azurerm_resource_group" "tenant" {
  for_each = var.sample_tenants
  
  name     = "rg-tenant-${each.key}-${local.resource_suffix}"
  location = var.location
  
  tags = merge(local.common_tags, {
    TenantId    = each.key
    TenantName  = each.value.name
    Environment = each.value.environment
  })
}

# Tenant storage accounts
resource "azurerm_storage_account" "tenant" {
  for_each = var.sample_tenants
  
  name                = "st${each.key}${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.tenant[each.key].name
  location            = azurerm_resource_group.tenant[each.key].location
  
  account_tier             = var.tenant_storage_account_tier
  account_replication_type = var.tenant_storage_replication_type
  account_kind             = "StorageV2"
  
  https_traffic_only_enabled = true
  min_tls_version           = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
  
  tags = merge(local.common_tags, {
    TenantId    = each.key
    TenantName  = each.value.name
    Environment = each.value.environment
  })
}

# Tenant network security groups
resource "azurerm_network_security_group" "tenant" {
  for_each = var.sample_tenants
  
  name                = "nsg-tenant-${each.key}-${local.resource_suffix}"
  location            = azurerm_resource_group.tenant[each.key].location
  resource_group_name = azurerm_resource_group.tenant[each.key].name
  
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = merge(local.common_tags, {
    TenantId    = each.key
    TenantName  = each.value.name
    Environment = each.value.environment
  })
}

# Tenant virtual networks
resource "azurerm_virtual_network" "tenant" {
  for_each = var.sample_tenants
  
  name                = "vnet-tenant-${each.key}-${local.resource_suffix}"
  location            = azurerm_resource_group.tenant[each.key].location
  resource_group_name = azurerm_resource_group.tenant[each.key].name
  
  address_space = [var.tenant_vnet_address_space]
  
  tags = merge(local.common_tags, {
    TenantId    = each.key
    TenantName  = each.value.name
    Environment = each.value.environment
  })
}

# Tenant subnets
resource "azurerm_subnet" "tenant" {
  for_each = var.sample_tenants
  
  name                 = "subnet-tenant-${each.key}"
  resource_group_name  = azurerm_resource_group.tenant[each.key].name
  virtual_network_name = azurerm_virtual_network.tenant[each.key].name
  address_prefixes     = [var.tenant_subnet_address_prefix]
}

# Associate NSG with subnets
resource "azurerm_subnet_network_security_group_association" "tenant" {
  for_each = var.sample_tenants
  
  subnet_id                 = azurerm_subnet.tenant[each.key].id
  network_security_group_id = azurerm_network_security_group.tenant[each.key].id
}

# Tenant Log Analytics workspaces
resource "azurerm_log_analytics_workspace" "tenant" {
  for_each = var.sample_tenants
  
  name                = "law-tenant-${each.key}-${local.resource_suffix}"
  location            = azurerm_resource_group.tenant[each.key].location
  resource_group_name = azurerm_resource_group.tenant[each.key].name
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    TenantId    = each.key
    TenantName  = each.value.name
    Environment = each.value.environment
  })
}

# Policy assignments for tenant resource groups
resource "azurerm_resource_group_policy_assignment" "tenant_tagging" {
  for_each = var.sample_tenants
  
  name                 = "tenant-${each.key}-tagging-${local.resource_suffix}"
  resource_group_id    = azurerm_resource_group.tenant[each.key].id
  policy_definition_id = azurerm_policy_definition.tenant_tagging.id
  display_name         = "Tenant ${each.key} Tagging Policy"
  description          = "Enforce tagging policy for tenant ${each.key}"
  
  enforcement_mode = var.policy_assignment_enforcement_mode
}

resource "azurerm_resource_group_policy_assignment" "tenant_network_security" {
  for_each = var.sample_tenants
  
  name                 = "tenant-${each.key}-network-security-${local.resource_suffix}"
  resource_group_id    = azurerm_resource_group.tenant[each.key].id
  policy_definition_id = azurerm_policy_definition.network_security_groups.id
  display_name         = "Tenant ${each.key} Network Security Policy"
  description          = "Enforce network security policy for tenant ${each.key}"
  
  enforcement_mode = var.policy_assignment_enforcement_mode
}

# Store tenant configurations in Key Vault
resource "azurerm_key_vault_secret" "tenant_config" {
  for_each = var.sample_tenants
  
  name         = "tenant-${each.key}-config"
  value        = jsonencode({
    tenantId    = each.key
    tenantName  = each.value.name
    adminEmail  = each.value.admin_email
    status      = "active"
    environment = each.value.environment
    resourceGroup = azurerm_resource_group.tenant[each.key].name
    storageAccount = azurerm_storage_account.tenant[each.key].name
    virtualNetwork = azurerm_virtual_network.tenant[each.key].name
  })
  key_vault_id = azurerm_key_vault.saas_platform.id
  
  depends_on = [
    azurerm_role_assignment.deployment_identity_keyvault
  ]
}

# Diagnostic settings for tenant storage accounts
resource "azurerm_monitor_diagnostic_setting" "tenant_storage" {
  for_each = var.sample_tenants
  
  name                       = "tenant-${each.key}-storage-diagnostics"
  target_resource_id         = azurerm_storage_account.tenant[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform_workspace.id
  
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }
  
  metric {
    category = "Transaction"
    enabled  = true
  }
}

# Role assignments for tenant-specific access
resource "azurerm_role_assignment" "tenant_storage_access" {
  for_each = var.sample_tenants
  
  scope                = azurerm_storage_account.tenant[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.workload_identity.object_id
}
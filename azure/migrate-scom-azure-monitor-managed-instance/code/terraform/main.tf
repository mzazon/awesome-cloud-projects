# Main Terraform configuration for SCOM Migration to Azure Monitor SCOM Managed Instance
# This configuration creates the complete infrastructure required for migrating 
# on-premises SCOM to Azure Monitor SCOM Managed Instance

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "main" {
  byte_length = 3
}

# Create locals for computed values
locals {
  # Generate unique resource names using random suffix
  resource_suffix = random_id.main.hex
  
  # Computed resource names
  sql_mi_name          = var.sql_managed_instance_name != null ? var.sql_managed_instance_name : "sql-mi-${local.resource_suffix}"
  scom_mi_name         = var.scom_managed_instance_name != null ? var.scom_managed_instance_name : "scom-mi-${local.resource_suffix}"
  key_vault_name       = var.key_vault_name != null ? var.key_vault_name : "kv-scom-${local.resource_suffix}"
  log_analytics_name   = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "law-scom-${local.resource_suffix}"
  storage_account_name = var.storage_account_name != null ? var.storage_account_name : "scommigration${local.resource_suffix}"
  
  # Network configuration
  vnet_name            = "vnet-scom-${local.resource_suffix}"
  scom_subnet_name     = "scom-mi-subnet"
  sql_subnet_name      = "sql-mi-subnet"
  
  # Security configuration
  scom_nsg_name        = "nsg-scom-mi"
  sql_nsg_name         = "nsg-sql-mi"
  
  # Generate secure passwords if not provided
  sql_admin_password = var.sql_admin_password != null ? var.sql_admin_password : random_password.sql_admin_password.result
  domain_user_password = var.scom_domain_user_password != null ? var.scom_domain_user_password : random_password.domain_user_password.result
  
  # Common tags
  common_tags = merge(var.common_tags, {
    Environment   = var.environment
    Project       = var.project_name
    CreatedBy     = "Terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Generate random passwords if not provided
resource "random_password" "sql_admin_password" {
  length  = 16
  special = true
}

resource "random_password" "domain_user_password" {
  length  = 16
  special = true
}

# Resource Group for SCOM Migration
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual Network for SCOM Infrastructure
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Subnet for SCOM Managed Instance
resource "azurerm_subnet" "scom_mi" {
  name                 = local.scom_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.scom_subnet_address_prefix]
  
  # Service endpoints for SCOM MI
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.AzureMonitor"
  ]
}

# Subnet for SQL Managed Instance
resource "azurerm_subnet" "sql_mi" {
  name                 = local.sql_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.sql_subnet_address_prefix]
  
  # Delegation for SQL Managed Instance
  delegation {
    name = "sql-mi-delegation"
    
    service_delegation {
      name    = "Microsoft.Sql/managedInstances"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

# Network Security Group for SCOM Managed Instance
resource "azurerm_network_security_group" "scom_mi" {
  name                = local.scom_nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Security rules for SCOM MI
resource "azurerm_network_security_rule" "scom_agent_inbound" {
  name                        = "Allow-SCOM-Agents"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5723"
  source_address_prefixes     = var.allowed_source_ip_ranges
  destination_address_prefix  = var.scom_subnet_address_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.scom_mi.name
}

resource "azurerm_network_security_rule" "scom_console_inbound" {
  name                        = "Allow-SCOM-Console"
  priority                    = 1100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5724"
  source_address_prefixes     = var.allowed_source_ip_ranges
  destination_address_prefix  = var.scom_subnet_address_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.scom_mi.name
}

resource "azurerm_network_security_rule" "scom_web_console_inbound" {
  name                        = "Allow-SCOM-Web-Console"
  priority                    = 1200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefixes     = var.allowed_source_ip_ranges
  destination_address_prefix  = var.scom_subnet_address_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.scom_mi.name
}

resource "azurerm_network_security_rule" "scom_sql_outbound" {
  name                        = "Allow-SQL-MI-Access"
  priority                    = 1000
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["1433", "3342"]
  source_address_prefix       = var.scom_subnet_address_prefix
  destination_address_prefix  = var.sql_subnet_address_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.scom_mi.name
}

# Network Security Group for SQL Managed Instance
resource "azurerm_network_security_group" "sql_mi" {
  name                = local.sql_nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Security rules for SQL MI
resource "azurerm_network_security_rule" "sql_mi_inbound" {
  name                        = "Allow-SCOM-MI-Access"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["1433", "3342"]
  source_address_prefix       = var.scom_subnet_address_prefix
  destination_address_prefix  = var.sql_subnet_address_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.sql_mi.name
}

# Associate NSG with SCOM subnet
resource "azurerm_subnet_network_security_group_association" "scom_mi" {
  subnet_id                 = azurerm_subnet.scom_mi.id
  network_security_group_id = azurerm_network_security_group.scom_mi.id
}

# Associate NSG with SQL subnet
resource "azurerm_subnet_network_security_group_association" "sql_mi" {
  subnet_id                 = azurerm_subnet.sql_mi.id
  network_security_group_id = azurerm_network_security_group.sql_mi.id
}

# Route table for SQL Managed Instance
resource "azurerm_route_table" "sql_mi" {
  name                = "rt-sql-mi-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Associate route table with SQL subnet
resource "azurerm_subnet_route_table_association" "sql_mi" {
  subnet_id      = azurerm_subnet.sql_mi.id
  route_table_id = azurerm_route_table.sql_mi.id
}

# User Assigned Managed Identity for SCOM MI
resource "azurerm_user_assigned_identity" "scom_mi" {
  name                = "scom-mi-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = var.key_vault_sku_name
  tags                        = local.common_tags
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

# Key Vault access policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
  ]
  
  certificate_permissions = [
    "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
  ]
}

# Key Vault access policy for SCOM MI managed identity
resource "azurerm_key_vault_access_policy" "scom_mi" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.scom_mi.principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
  
  depends_on = [azurerm_user_assigned_identity.scom_mi]
}

# Store SQL admin password in Key Vault
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = local.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Store domain user password in Key Vault
resource "azurerm_key_vault_secret" "domain_user_password" {
  name         = "domain-user-password"
  value        = local.domain_user_password
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# SQL Managed Instance
resource "azurerm_mssql_managed_instance" "main" {
  name                = local.sql_mi_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Basic configuration
  administrator_login          = var.sql_admin_username
  administrator_login_password = local.sql_admin_password
  license_type                 = var.sql_license_type
  subnet_id                    = azurerm_subnet.sql_mi.id
  sku_name                     = var.sql_sku_name
  vcores                       = var.sql_vcores
  storage_size_in_gb           = var.sql_storage_size_gb
  
  # Network configuration
  public_data_endpoint_enabled = true
  proxy_override              = "Proxy"
  minimum_tls_version         = "1.2"
  
  # Backup configuration
  storage_account_type = "GRS"
  
  # Time zone configuration
  timezone_id = "UTC"
  
  # Collation
  collation = "SQL_Latin1_General_CP1_CI_AS"
  
  # Tags
  tags = local.common_tags
  
  # Depends on network configuration
  depends_on = [
    azurerm_subnet_network_security_group_association.sql_mi,
    azurerm_subnet_route_table_association.sql_mi
  ]
  
  # This resource can take 4-6 hours to create
  timeouts {
    create = "6h"
    update = "6h"
    delete = "6h"
  }
}

# Add delay after SQL MI creation to ensure it's fully ready
resource "time_sleep" "sql_mi_ready" {
  depends_on      = [azurerm_mssql_managed_instance.main]
  create_duration = "5m"
}

# Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Storage account for management pack migration
resource "azurerm_storage_account" "migration" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configuration
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Network configuration
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Storage container for management packs
resource "azurerm_storage_container" "management_packs" {
  name                  = "management-packs"
  storage_account_name  = azurerm_storage_account.migration.name
  container_access_type = "private"
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "main" {
  name                = var.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "SCOMAlerts"
  tags                = local.common_tags
  
  # Email receivers
  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email
    }
  }
}

# Note: SCOM Managed Instance is currently in preview and may not have 
# a direct Terraform provider. This is a placeholder for the actual implementation.
# For now, we'll create the supporting infrastructure and document the SCOM MI creation process.

# Create a placeholder resource that documents the SCOM MI creation
resource "azurerm_resource_group_template_deployment" "scom_mi_placeholder" {
  name                = "scom-mi-deployment-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  deployment_mode     = "Incremental"
  
  # This template creates a placeholder for SCOM MI
  template_content = jsonencode({
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "resources": [
      {
        "type": "Microsoft.Resources/deployments",
        "apiVersion": "2021-04-01",
        "name": "scom-mi-placeholder",
        "properties": {
          "mode": "Incremental",
          "template": {
            "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
            "contentVersion": "1.0.0.0",
            "resources": []
          }
        }
      }
    ],
    "outputs": {
      "scomMiInstructions": {
        "type": "string",
        "value": "SCOM Managed Instance must be created manually using Azure CLI or portal. See deployment instructions in outputs."
      }
    }
  })
  
  # Include all required parameters as template parameters
  parameters_content = jsonencode({
    "scomMiName": {
      "value": local.scom_mi_name
    },
    "sqlMiId": {
      "value": azurerm_mssql_managed_instance.main.id
    },
    "subnetId": {
      "value": azurerm_subnet.scom_mi.id
    },
    "managedIdentityId": {
      "value": azurerm_user_assigned_identity.scom_mi.id
    },
    "keyVaultUri": {
      "value": azurerm_key_vault.main.vault_uri
    },
    "logAnalyticsWorkspaceId": {
      "value": azurerm_log_analytics_workspace.main.workspace_id
    }
  })
  
  tags = local.common_tags
  
  depends_on = [
    time_sleep.sql_mi_ready,
    azurerm_subnet_network_security_group_association.scom_mi,
    azurerm_key_vault_access_policy.scom_mi
  ]
}

# Diagnostic settings for SQL Managed Instance
resource "azurerm_monitor_diagnostic_setting" "sql_mi" {
  count              = var.enable_diagnostics ? 1 : 0
  name               = "diag-sql-mi-${local.resource_suffix}"
  target_resource_id = azurerm_mssql_managed_instance.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available log categories
  enabled_log {
    category = "ResourceUsageStats"
  }
  
  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
  
  enabled_log {
    category = "InstanceAndAppAdvanced"
  }
  
  # Enable all available metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count              = var.enable_diagnostics ? 1 : 0
  name               = "diag-kv-${local.resource_suffix}"
  target_resource_id = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable audit logs
  enabled_log {
    category = "AuditEvent"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Store SQL connection string in Key Vault
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=${azurerm_mssql_managed_instance.main.fqdn},3342;Database=master;User ID=${var.sql_admin_username};Password=${local.sql_admin_password};Encrypt=true;TrustServerCertificate=false;"
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    time_sleep.sql_mi_ready
  ]
}
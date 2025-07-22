# Azure Network Security Orchestration Infrastructure
# This file contains the main infrastructure resources for automated network security orchestration
# using Azure Logic Apps, Network Security Groups, Azure Monitor, and Azure Key Vault

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate unique suffix for resource names
  suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Common naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with suffix
  resource_group_name     = var.resource_group_name
  key_vault_name         = "kv-${substr(replace("${local.resource_prefix}-${local.suffix}", "-", ""), 0, 24)}"
  storage_account_name   = "st${substr(replace("${local.resource_prefix}${local.suffix}", "-", ""), 0, 24)}"
  logic_app_name         = "la-${local.resource_prefix}-${local.suffix}"
  log_analytics_name     = "law-${local.resource_prefix}-${local.suffix}"
  vnet_name             = "vnet-${local.resource_prefix}-${local.suffix}"
  nsg_name              = "nsg-${local.resource_prefix}-${local.suffix}"
  action_group_name     = "ag-${local.resource_prefix}-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for monitoring and compliance
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Create Azure Key Vault for secure credential management
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Enable advanced security features
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  enable_rbac_authorization       = false
  
  # Soft delete configuration
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = false
  
  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = local.common_tags
}

# Create access policy for current user/service principal
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

# Store threat intelligence API key in Key Vault
resource "azurerm_key_vault_secret" "threat_intel_api_key" {
  name         = "ThreatIntelApiKey"
  value        = var.threat_intel_api_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Create Storage Account for workflow state management
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable security features
  enable_https_traffic_only      = true
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning and change feed
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Enable soft delete for blobs
    delete_retention_policy {
      days = 7
    }
    
    # Enable soft delete for containers
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create storage containers for security data
resource "azurerm_storage_container" "security_events" {
  name                  = "security-events"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "compliance_reports" {
  name                  = "compliance-reports"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create Virtual Network for security infrastructure
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

# Create subnets for different security zones
resource "azurerm_subnet" "protected" {
  name                 = "protected-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefixes["protected"]]
}

resource "azurerm_subnet" "management" {
  name                 = "management-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefixes["management"]]
}

# Create Network Security Group with baseline rules
resource "azurerm_network_security_group" "main" {
  name                = local.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create default security rules
resource "azurerm_network_security_rule" "default_rules" {
  for_each = var.default_security_rules
  
  name                        = each.key
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  description                 = each.value.description
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# Associate NSG with protected subnet
resource "azurerm_subnet_network_security_group_association" "protected" {
  subnet_id                 = azurerm_subnet.protected.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Create managed identity for Logic Apps
resource "azurerm_user_assigned_identity" "logic_apps" {
  name                = "mi-${local.resource_prefix}-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
}

# Grant managed identity permissions to modify Network Security Groups
resource "azurerm_role_assignment" "logic_apps_network_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_apps.principal_id
}

# Grant managed identity permissions to Key Vault
resource "azurerm_key_vault_access_policy" "logic_apps" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.logic_apps.principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Create Logic Apps workflow for security orchestration
resource "azurerm_logic_app_workflow" "main" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Associate managed identity
  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_apps.id]
  }
  
  # Enable or disable the workflow
  enabled = var.logic_app_state == "Enabled"
  
  # Workflow definition with security orchestration logic
  workflow_schema   = "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json"
  workflow_version  = "1.0.0.0"
  
  parameters = {
    "$connections" = jsonencode({
      keyvault = {
        connectionId   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/connections/keyvault"
        connectionName = "keyvault"
        id             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/keyvault"
      }
    })
  }
  
  tags = local.common_tags
}

# Create Action Group for Azure Monitor alerts
resource "azurerm_monitor_action_group" "security_orchestration" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "SecOrch"
  
  # Logic Apps webhook trigger
  logic_app_receiver {
    name                    = "LogicAppsTrigger"
    resource_id            = azurerm_logic_app_workflow.main.id
    callback_url           = "https://logic-apps-trigger-url"
    use_common_alert_schema = true
  }
  
  tags = local.common_tags
}

# Create metric alert for suspicious network activity
resource "azurerm_monitor_metric_alert" "suspicious_activity" {
  name                = "SuspiciousNetworkActivity"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_network_security_group.main.id]
  description         = "Alert on suspicious network activity patterns"
  
  criteria {
    metric_namespace = "Microsoft.Network/networkSecurityGroups"
    metric_name      = "PacketCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1000
    
    dimension {
      name     = "Direction"
      operator = "Include"
      values   = ["Inbound"]
    }
  }
  
  # Alert frequency and evaluation
  window_size        = "PT5M"
  frequency          = "PT1M"
  severity           = 2
  
  action {
    action_group_id = azurerm_monitor_action_group.security_orchestration.id
  }
  
  tags = local.common_tags
}

# Create diagnostic settings for Logic Apps if enabled
resource "azurerm_monitor_diagnostic_setting" "logic_apps" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "SecurityOrchestrationLogs"
  target_resource_id         = azurerm_logic_app_workflow.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Network Security Group if enabled
resource "azurerm_monitor_diagnostic_setting" "nsg" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "NetworkSecurityGroupLogs"
  target_resource_id         = azurerm_network_security_group.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }
  
  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

# Create diagnostic settings for Key Vault if enabled
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "KeyVaultLogs"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "AuditEvent"
  }
  
  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Storage Account if enabled
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "StorageAccountLogs"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Create custom Log Analytics table for security orchestration events
resource "azurerm_log_analytics_data_export_rule" "security_events" {
  count                   = var.enable_diagnostic_settings ? 1 : 0
  name                    = "SecurityOrchestrationEvents"
  resource_group_name     = azurerm_resource_group.main.name
  workspace_resource_id   = azurerm_log_analytics_workspace.main.id
  destination_resource_id = azurerm_storage_account.main.id
  table_names             = ["SecurityEvent", "CommonSecurityLog"]
  enabled                 = true
}

# Create Activity Log Alert for NSG modifications
resource "azurerm_monitor_activity_log_alert" "nsg_modifications" {
  name                = "NSGModificationAlert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_resource_group.main.id]
  description         = "Alert when Network Security Group rules are modified"
  
  criteria {
    resource_id    = azurerm_network_security_group.main.id
    operation_name = "Microsoft.Network/networkSecurityGroups/securityRules/write"
    category       = "Administrative"
    level          = "Informational"
    status         = "Succeeded"
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.security_orchestration.id
  }
  
  tags = local.common_tags
}
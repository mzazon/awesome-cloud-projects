# Main Terraform Configuration for Azure Confidential Ledger Audit Trail
# This file creates a tamper-proof audit trail system using Azure Confidential Ledger,
# Logic Apps, Key Vault, Event Hubs, and Storage Account

# Data sources for current client configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "audit_trail" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Key Vault for secure credential storage
resource "azurerm_key_vault" "audit_trail" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Enable soft delete and purge protection for compliance
  soft_delete_retention_days = var.key_vault_retention_days
  purge_protection_enabled   = true

  # Enable RBAC for access control
  enable_rbac_authorization = true

  tags = var.tags
}

# Create Azure Confidential Ledger for immutable audit trails
resource "azurerm_confidential_ledger" "audit_trail" {
  name                = "acl-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  ledger_type         = var.ledger_type

  # Configure AAD-based security principals
  azuread_based_service_principal {
    principal_id     = data.azurerm_client_config.current.object_id
    ledger_role_name = "Administrator"
  }

  # Add additional admin users if specified
  dynamic "azuread_based_service_principal" {
    for_each = var.admin_object_ids
    content {
      principal_id     = azuread_based_service_principal.value
      ledger_role_name = "Administrator"
    }
  }

  # Add reader users if specified
  dynamic "azuread_based_service_principal" {
    for_each = var.reader_object_ids
    content {
      principal_id     = azuread_based_service_principal.value
      ledger_role_name = "Reader"
    }
  }

  tags = var.tags
}

# Create Event Hub Namespace for high-volume event ingestion
resource "azurerm_eventhub_namespace" "audit_trail" {
  name                = "eh-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  sku                 = var.event_hub_sku
  capacity            = var.event_hub_capacity

  # Enable auto-inflate for Standard SKU
  auto_inflate_enabled     = var.event_hub_sku == "Standard" ? true : false
  maximum_throughput_units = var.event_hub_sku == "Standard" ? 20 : null

  tags = var.tags
}

# Create Event Hub for audit events
resource "azurerm_eventhub" "audit_events" {
  name                = "audit-events"
  namespace_name      = azurerm_eventhub_namespace.audit_trail.name
  resource_group_name = azurerm_resource_group.audit_trail.name
  partition_count     = var.event_hub_partition_count
  message_retention   = var.event_hub_retention_days
}

# Create consumer group for Logic Apps
resource "azurerm_eventhub_consumer_group" "logic_apps" {
  name                = "logic-apps-consumer"
  namespace_name      = azurerm_eventhub_namespace.audit_trail.name
  eventhub_name       = azurerm_eventhub.audit_events.name
  resource_group_name = azurerm_resource_group.audit_trail.name
}

# Create authorization rule for Event Hub access
resource "azurerm_eventhub_authorization_rule" "audit_events_rule" {
  name                = "audit-events-rule"
  namespace_name      = azurerm_eventhub_namespace.audit_trail.name
  eventhub_name       = azurerm_eventhub.audit_events.name
  resource_group_name = azurerm_resource_group.audit_trail.name
  listen              = true
  send                = true
  manage              = false
}

# Create Storage Account for long-term archive
resource "azurerm_storage_account" "audit_trail" {
  name                = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.audit_trail.name
  location            = azurerm_resource_group.audit_trail.location
  account_tier        = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind        = "StorageV2"

  # Enable hierarchical namespace for Data Lake Storage Gen2
  is_hns_enabled = true

  # Enable versioning for additional protection
  blob_properties {
    versioning_enabled = true
    change_feed_enabled = true
  }

  tags = var.tags
}

# Create storage container for audit archives
resource "azurerm_storage_container" "audit_archive" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.audit_trail.name
  container_access_type = "private"
}

# Create Logic App for workflow orchestration
resource "azurerm_logic_app_workflow" "audit_trail" {
  name                = "la-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name

  # Basic workflow definition (can be customized via variable)
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  workflow_parameters = jsonencode({
    "$connections" = {
      "value" = {}
    }
  })

  tags = var.tags
}

# Enable managed identity for Logic App
resource "azurerm_logic_app_workflow" "audit_trail_identity" {
  name                = azurerm_logic_app_workflow.audit_trail.name
  location            = azurerm_logic_app_workflow.audit_trail.location
  resource_group_name = azurerm_logic_app_workflow.audit_trail.resource_group_name

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Store Confidential Ledger endpoint in Key Vault
resource "azurerm_key_vault_secret" "ledger_endpoint" {
  name         = "ledger-endpoint"
  value        = azurerm_confidential_ledger.audit_trail.ledger_uri
  key_vault_id = azurerm_key_vault.audit_trail.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Store Event Hub connection string in Key Vault
resource "azurerm_key_vault_secret" "eventhub_connection" {
  name         = "eventhub-connection"
  value        = azurerm_eventhub_authorization_rule.audit_events_rule.primary_connection_string
  key_vault_id = azurerm_key_vault.audit_trail.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Store Storage Account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection" {
  name         = "storage-connection"
  value        = azurerm_storage_account.audit_trail.primary_connection_string
  key_vault_id = azurerm_key_vault.audit_trail.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# RBAC Assignments for secure access

# Grant current user Key Vault Administrator role
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_key_vault.audit_trail.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant Logic App access to Key Vault secrets
resource "azurerm_role_assignment" "logic_app_keyvault" {
  scope                = azurerm_key_vault.audit_trail.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
}

# Grant Logic App access to Event Hub
resource "azurerm_role_assignment" "logic_app_eventhub" {
  scope                = azurerm_eventhub_namespace.audit_trail.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
}

# Grant Logic App access to Storage Account
resource "azurerm_role_assignment" "logic_app_storage" {
  scope                = azurerm_storage_account.audit_trail.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
}

# Grant Logic App access to Confidential Ledger
resource "azurerm_role_assignment" "logic_app_ledger" {
  scope                = azurerm_confidential_ledger.audit_trail.id
  role_definition_name = "Confidential Ledger User"
  principal_id         = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
}

# Optional: Create Log Analytics Workspace for diagnostic settings
resource "azurerm_log_analytics_workspace" "audit_trail" {
  count               = var.enable_diagnostic_settings && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "log-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Diagnostic settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_key_vault.audit_trail.name}"
  target_resource_id         = azurerm_key_vault.audit_trail.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.audit_trail[0].id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Event Hub Namespace
resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_eventhub_namespace.audit_trail.name}"
  target_resource_id         = azurerm_eventhub_namespace.audit_trail.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.audit_trail[0].id

  enabled_log {
    category = "ArchiveLogs"
  }

  enabled_log {
    category = "OperationalLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_storage_account.audit_trail.name}"
  target_resource_id         = azurerm_storage_account.audit_trail.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.audit_trail[0].id

  metric {
    category = "Transaction"
    enabled  = true
  }
}

# Diagnostic settings for Logic App
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_logic_app_workflow.audit_trail.name}"
  target_resource_id         = azurerm_logic_app_workflow.audit_trail.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.audit_trail[0].id

  enabled_log {
    category = "WorkflowRuntime"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Optional: Private endpoints for enhanced security
resource "azurerm_private_endpoint" "keyvault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_key_vault.audit_trail.name}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${azurerm_key_vault.audit_trail.name}"
    private_connection_resource_id = azurerm_key_vault.audit_trail.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.audit_trail.name}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${azurerm_storage_account.audit_trail.name}"
    private_connection_resource_id = azurerm_storage_account.audit_trail.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "eventhub" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_eventhub_namespace.audit_trail.name}"
  location            = azurerm_resource_group.audit_trail.location
  resource_group_name = azurerm_resource_group.audit_trail.name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${azurerm_eventhub_namespace.audit_trail.name}"
    private_connection_resource_id = azurerm_eventhub_namespace.audit_trail.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }

  tags = var.tags
}
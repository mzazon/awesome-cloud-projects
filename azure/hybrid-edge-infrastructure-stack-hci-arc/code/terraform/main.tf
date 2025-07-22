# Main Terraform configuration for Azure Stack HCI and Azure Arc edge computing infrastructure
# This configuration deploys a complete edge computing solution with centralized management

# Data sources for existing Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  
  # Resource names with defaults if not provided
  hci_cluster_name            = var.hci_cluster_name != "" ? var.hci_cluster_name : "hci-cluster-${local.resource_suffix}"
  arc_resource_name           = var.arc_resource_name != "" ? var.arc_resource_name : "arc-hci-${local.resource_suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "la-edge-${local.resource_suffix}"
  storage_account_name        = var.storage_account_name != "" ? var.storage_account_name : "edgestorage${local.resource_suffix}"
  custom_location_name        = var.custom_location_name != "" ? var.custom_location_name : "cl-${local.resource_suffix}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    DeployedBy    = "Terraform"
    LastModified  = timestamp()
  })
}

# Resource Group for edge computing infrastructure
resource "azurerm_resource_group" "edge_infrastructure" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "edge_monitoring" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.edge_infrastructure.location
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring (if enabled)
resource "azurerm_application_insights" "edge_monitoring" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "ai-edge-${local.resource_suffix}"
  location            = azurerm_resource_group.edge_infrastructure.location
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  workspace_id        = azurerm_log_analytics_workspace.edge_monitoring.id
  application_type    = "web"
  
  tags = local.common_tags
}

# Storage Account for edge data synchronization
resource "azurerm_storage_account" "edge_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.edge_infrastructure.name
  location                 = azurerm_resource_group.edge_infrastructure.location
  account_tier             = var.storage_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable hierarchical namespace for Data Lake Storage Gen2
  is_hns_enabled = var.enable_hierarchical_namespace
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning and change feed
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage container for edge synchronization
resource "azurerm_storage_container" "edge_sync" {
  name                  = "edge-sync"
  storage_account_name  = azurerm_storage_account.edge_storage.name
  container_access_type = "private"
}

# Storage file share for edge file synchronization
resource "azurerm_storage_share" "edge_file_sync" {
  name                 = "edge-file-sync"
  storage_account_name = azurerm_storage_account.edge_storage.name
  quota                = 1024
}

# Key Vault for secrets management (if enabled)
resource "azurerm_key_vault" "edge_secrets" {
  count                       = var.enable_key_vault ? 1 : 0
  name                        = "kv-edge-${local.resource_suffix}"
  location                    = azurerm_resource_group.edge_infrastructure.location
  resource_group_name         = azurerm_resource_group.edge_infrastructure.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  
  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover", "Purge"
    ]
    
    key_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover"
    ]
    
    certificate_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover"
    ]
  }
  
  tags = local.common_tags
}

# Virtual Network for edge infrastructure
resource "azurerm_virtual_network" "edge_network" {
  name                = "vnet-edge-${local.resource_suffix}"
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.edge_infrastructure.location
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  
  tags = local.common_tags
}

# Subnet for edge infrastructure
resource "azurerm_subnet" "edge_subnet" {
  name                 = "snet-edge-${local.resource_suffix}"
  resource_group_name  = azurerm_resource_group.edge_infrastructure.name
  virtual_network_name = azurerm_virtual_network.edge_network.name
  address_prefixes     = [var.subnet_address_prefix]
  
  # Enable service endpoints for storage and key vault
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault"
  ]
}

# Network Security Group for edge subnet
resource "azurerm_network_security_group" "edge_nsg" {
  name                = "nsg-edge-${local.resource_suffix}"
  location            = azurerm_resource_group.edge_infrastructure.location
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  
  # Allow HTTPS inbound
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Allow Azure Arc agent communication
  security_rule {
    name                       = "AllowArcAgent"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "edge_nsg_association" {
  subnet_id                 = azurerm_subnet.edge_subnet.id
  network_security_group_id = azurerm_network_security_group.edge_nsg.id
}

# Azure AD Application for Azure Stack HCI cluster
resource "azuread_application" "hci_cluster_app" {
  display_name = "HCI-Cluster-${local.resource_suffix}"
  
  # Required resource access for Azure Stack HCI
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  
  tags = ["terraform", "azure-stack-hci", "edge-computing"]
}

# Service Principal for HCI cluster application
resource "azuread_service_principal" "hci_cluster_sp" {
  application_id = azuread_application.hci_cluster_app.application_id
  
  tags = ["terraform", "azure-stack-hci", "edge-computing"]
}

# Azure Stack HCI Cluster resource
resource "azurerm_stack_hci_cluster" "edge_cluster" {
  name                = local.hci_cluster_name
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  location            = azurerm_resource_group.edge_infrastructure.location
  client_id           = azuread_application.hci_cluster_app.application_id
  tenant_id           = data.azuread_client_config.current.tenant_id
  
  tags = local.common_tags
}

# Azure AD Application for Azure Arc service principal
resource "azuread_application" "arc_app" {
  display_name = "Arc-Servers-${local.resource_suffix}"
  
  # Required resource access for Azure Arc
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  
  tags = ["terraform", "azure-arc", "edge-computing"]
}

# Service Principal for Azure Arc
resource "azuread_service_principal" "arc_sp" {
  application_id = azuread_application.arc_app.application_id
  
  tags = ["terraform", "azure-arc", "edge-computing"]
}

# Service Principal password for Azure Arc authentication
resource "azuread_service_principal_password" "arc_sp_password" {
  service_principal_id = azuread_service_principal.arc_sp.object_id
  display_name         = "Arc Agent Password"
}

# Role assignment for Azure Arc service principal
resource "azurerm_role_assignment" "arc_onboarding" {
  scope                = azurerm_resource_group.edge_infrastructure.id
  role_definition_name = "Azure Connected Machine Onboarding"
  principal_id         = azuread_service_principal.arc_sp.object_id
}

# Role assignment for Azure Arc resource provider
resource "azurerm_role_assignment" "arc_resource_provider" {
  scope                = azurerm_resource_group.edge_infrastructure.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.arc_sp.object_id
}

# Data Collection Rule for Azure Monitor
resource "azurerm_monitor_data_collection_rule" "hci_monitoring" {
  name                = "dcr-hci-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  location            = azurerm_resource_group.edge_infrastructure.location
  
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.edge_monitoring.id
      name                  = "destination-log"
    }
  }
  
  data_flow {
    streams      = ["Microsoft-Event", "Microsoft-WindowsEvent", "Microsoft-Perf"]
    destinations = ["destination-log"]
  }
  
  data_sources {
    windows_event_log {
      streams        = ["Microsoft-WindowsEvent"]
      x_path_queries = ["System!*[System[Level=1 or Level=2 or Level=3]]", "Application!*[System[Level=1 or Level=2 or Level=3]]"]
      name           = "eventLogsDataSource"
    }
    
    performance_counter {
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers           = ["\\Processor(_Total)\\% Processor Time", "\\Memory\\Available Bytes", "\\LogicalDisk(_Total)\\% Free Space"]
      name                         = "perfCountersDataSource"
    }
  }
  
  tags = local.common_tags
}

# Azure Policy Definition for HCI Security Baseline
resource "azurerm_policy_definition" "hci_security_baseline" {
  count        = var.enable_azure_policy ? 1 : 0
  name         = "HCI-Security-Baseline-${local.resource_suffix}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Azure Stack HCI Security Baseline"
  description  = "Ensures HCI clusters meet security requirements"
  
  policy_rule = jsonencode({
    if = {
      allOf = [{
        field  = "type"
        equals = "Microsoft.AzureStackHCI/clusters"
      }]
    }
    then = {
      effect = "audit"
    }
  })
  
  parameters = jsonencode({
    effect = {
      type         = "String"
      defaultValue = "Audit"
      allowedValues = ["Audit", "Deny", "Disabled"]
    }
  })
}

# Azure Policy Assignment for HCI Security
resource "azurerm_resource_group_policy_assignment" "hci_security" {
  count                = var.enable_azure_policy ? 1 : 0
  name                 = "hci-security-assignment"
  display_name         = "HCI Security Compliance"
  resource_group_id    = azurerm_resource_group.edge_infrastructure.id
  policy_definition_id = azurerm_policy_definition.hci_security_baseline[0].id
  
  parameters = jsonencode({
    effect = {
      value = "Audit"
    }
  })
}

# Storage Sync Service for file synchronization
resource "azurerm_storage_sync" "edge_sync_service" {
  name                = "sync-service-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  location            = azurerm_resource_group.edge_infrastructure.location
  
  tags = local.common_tags
}

# Storage Sync Group
resource "azurerm_storage_sync_group" "edge_sync_group" {
  name            = "edge-sync-group"
  storage_sync_id = azurerm_storage_sync.edge_sync_service.id
}

# Recovery Services Vault for backup (if enabled)
resource "azurerm_recovery_services_vault" "edge_backup" {
  count               = var.enable_backup ? 1 : 0
  name                = "rsv-edge-${local.resource_suffix}"
  location            = azurerm_resource_group.edge_infrastructure.location
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  sku                 = "Standard"
  
  soft_delete_enabled = true
  
  tags = local.common_tags
}

# Backup Policy for Azure Stack HCI
resource "azurerm_backup_policy_vm" "hci_backup_policy" {
  count               = var.enable_backup ? 1 : 0
  name                = "hci-backup-policy"
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  recovery_vault_name = azurerm_recovery_services_vault.edge_backup[0].name
  
  policy_type = var.backup_policy_type
  
  backup {
    frequency = "Daily"
    time      = "23:00"
  }
  
  retention_daily {
    count = 30
  }
  
  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }
  
  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
  
  retention_yearly {
    count    = 5
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }
}

# Budget for cost management (if enabled)
resource "azurerm_consumption_budget_resource_group" "edge_budget" {
  count           = var.enable_cost_management ? 1 : 0
  name            = "budget-edge-${local.resource_suffix}"
  resource_group_id = azurerm_resource_group.edge_infrastructure.id
  
  amount     = var.budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h")) # 1 year from now
  }
  
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = ["admin@example.com"] # Update with actual email
  }
  
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = ["admin@example.com"] # Update with actual email
  }
}

# Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "edge_alerts" {
  name                = "ag-edge-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  short_name          = "edgealerts"
  
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com" # Update with actual email
  }
  
  tags = local.common_tags
}

# Metric Alert for HCI cluster health
resource "azurerm_monitor_metric_alert" "hci_health" {
  name                = "alert-hci-health-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.edge_infrastructure.name
  scopes              = [azurerm_stack_hci_cluster.edge_cluster.id]
  description         = "Alert when HCI cluster health degrades"
  
  criteria {
    metric_namespace = "Microsoft.AzureStackHCI/clusters"
    metric_name      = "ClusterHealth"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.edge_alerts.id
  }
  
  tags = local.common_tags
}

# Output values for reference
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.edge_infrastructure.name
}

output "hci_cluster_name" {
  description = "Name of the Azure Stack HCI cluster"
  value       = azurerm_stack_hci_cluster.edge_cluster.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.edge_monitoring.workspace_id
}

output "storage_account_name" {
  description = "Name of the edge storage account"
  value       = azurerm_storage_account.edge_storage.name
}

output "arc_service_principal_id" {
  description = "Service Principal ID for Azure Arc onboarding"
  value       = azuread_service_principal.arc_sp.application_id
  sensitive   = true
}

output "arc_service_principal_secret" {
  description = "Service Principal secret for Azure Arc onboarding"
  value       = azuread_service_principal_password.arc_sp_password.value
  sensitive   = true
}
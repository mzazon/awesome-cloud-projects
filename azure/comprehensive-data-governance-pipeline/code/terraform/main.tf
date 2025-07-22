# Azure Data Governance Solution with Purview and Data Lake Storage
# This Terraform configuration creates a comprehensive data governance infrastructure
# using Azure Purview, Data Lake Storage Gen2, and Azure Synapse Analytics

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed resource names and configurations
locals {
  # Generate unique resource names with random suffix
  purview_account_name = var.purview_account_name != "" ? var.purview_account_name : "${var.name_prefix}-purview-${random_id.suffix.hex}"
  storage_account_name = var.storage_account_name != "" ? var.storage_account_name : "${var.name_prefix}dl${random_id.suffix.hex}"
  synapse_workspace_name = var.synapse_workspace_name != "" ? var.synapse_workspace_name : "${var.name_prefix}-synapse-${random_id.suffix.hex}"
  
  # Managed resource group name for Purview
  purview_managed_rg_name = var.purview_managed_resource_group_name != "" ? var.purview_managed_resource_group_name : "managed-rg-${local.purview_account_name}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    DeployedBy   = "terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Create the main resource group for all governance resources
resource "azurerm_resource_group" "governance" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Data Lake Storage Gen2 Account
# This serves as the primary data repository with hierarchical namespace
# enabled for POSIX-compliant file system operations
resource "azurerm_storage_account" "data_lake" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.governance.name
  location                 = azurerm_resource_group.governance.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable hierarchical namespace for Data Lake Storage Gen2
  is_hns_enabled = true
  
  # Enable advanced security features
  enable_https_traffic_only      = true
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob features for data governance
  blob_properties {
    versioning_enabled  = var.enable_versioning
    change_feed_enabled = var.enable_change_feed
    
    # Configure container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
    
    # Configure blob delete retention policy
    delete_retention_policy {
      days = 7
    }
  }

  # Network access rules for security
  network_rules {
    default_action             = "Allow"  # Set to "Deny" for production with proper network setup
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_addresses
  }

  tags = merge(local.common_tags, {
    Type        = "DataLake"
    Purpose     = "PrimaryDataStorage"
    Governance  = "Enabled"
  })
}

# Data Lake Storage Containers
# Create containers for different data classification levels
resource "azurerm_storage_container" "data_containers" {
  for_each = var.data_containers

  name                  = each.key
  storage_account_name  = azurerm_storage_account.data_lake.name
  container_access_type = each.value.access_type
  metadata             = each.value.metadata
}

# Create sample data files for governance testing
resource "azurerm_storage_blob" "sample_customer_data" {
  name                   = "customers/customers.csv"
  storage_account_name   = azurerm_storage_account.data_lake.name
  storage_container_name = azurerm_storage_container.data_containers["sensitive-data"].name
  type                   = "Block"
  source_content         = "customer_id,name,email,phone,address\n1,John Doe,john@company.com,555-0123,123 Main St\n2,Jane Smith,jane@company.com,555-0124,456 Oak Ave\n"
  content_type          = "text/csv"
  
  metadata = {
    classification = "sensitive"
    data_type     = "customer_pii"
    created_by    = "terraform"
  }
}

resource "azurerm_storage_blob" "sample_order_data" {
  name                   = "orders/orders.csv"
  storage_account_name   = azurerm_storage_account.data_lake.name
  storage_container_name = azurerm_storage_container.data_containers["raw-data"].name
  type                   = "Block"
  source_content         = "order_id,customer_id,product,amount,date\n101,1,Laptop,999.99,2024-01-15\n102,2,Mouse,29.99,2024-01-16\n"
  content_type          = "text/csv"
  
  metadata = {
    classification = "internal"
    data_type     = "transactional"
    created_by    = "terraform"
  }
}

# Azure Purview Account
# Central data governance service for automated discovery and classification
resource "azurerm_purview_account" "governance" {
  name                         = local.purview_account_name
  resource_group_name          = azurerm_resource_group.governance.name
  location                     = azurerm_resource_group.governance.location
  managed_resource_group_name  = local.purview_managed_rg_name
  public_network_enabled       = var.purview_public_network_access

  # Configure managed identity for secure resource access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.common_tags, {
    Type       = "DataGovernance"
    Purpose    = "DataCatalogAndLineage"
    Service    = "AzurePurview"
  })
}

# Role assignment: Grant Purview managed identity Storage Blob Data Reader access to Data Lake
resource "azurerm_role_assignment" "purview_storage_reader" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_purview_account.governance.identity[0].principal_id
}

# Role assignment: Grant current user Purview Data Curator role
resource "azurerm_role_assignment" "purview_data_curator" {
  scope                = azurerm_purview_account.governance.id
  role_definition_name = "Purview Data Curator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignment: Grant current user Purview Data Reader role
resource "azurerm_role_assignment" "purview_data_reader" {
  scope                = azurerm_purview_account.governance.id
  role_definition_name = "Purview Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure Synapse Analytics Workspace (Optional)
# Provides advanced analytics capabilities with integrated data lineage tracking
resource "azurerm_synapse_workspace" "analytics" {
  count = var.enable_synapse_workspace ? 1 : 0

  name                                 = local.synapse_workspace_name
  resource_group_name                  = azurerm_resource_group.governance.name
  location                            = azurerm_resource_group.governance.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse[0].id
  sql_administrator_login             = var.synapse_sql_admin_login
  sql_administrator_login_password    = var.synapse_sql_admin_password
  
  # Configure managed identity for Purview integration
  identity {
    type = "SystemAssigned"
  }

  # Enable Purview integration for automatic lineage tracking
  purview_id = azurerm_purview_account.governance.id

  tags = merge(local.common_tags, {
    Type      = "Analytics"
    Purpose   = "DataProcessingAndLineage"
    Service   = "AzureSynapseAnalytics"
  })
}

# Create dedicated filesystem for Synapse workspace
resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  count = var.enable_synapse_workspace ? 1 : 0

  name               = "synapse"
  storage_account_id = azurerm_storage_account.data_lake.id
  
  properties = {
    purpose     = "synapse-workspace"
    environment = var.environment
  }
}

# Synapse firewall rule to allow Azure services
resource "azurerm_synapse_firewall_rule" "azure_services" {
  count = var.enable_synapse_workspace ? 1 : 0

  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.analytics[0].id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Data source to get current public IP for firewall rules
data "http" "current_ip" {
  count = var.enable_synapse_workspace && length(var.allowed_ip_addresses) == 0 ? 1 : 0
  url   = "https://api.ipify.org"
}

# Synapse firewall rule for current client IP
resource "azurerm_synapse_firewall_rule" "current_ip" {
  count = var.enable_synapse_workspace && length(var.allowed_ip_addresses) == 0 ? 1 : 0

  name                 = "AllowCurrentIP"
  synapse_workspace_id = azurerm_synapse_workspace.analytics[0].id
  start_ip_address     = chomp(data.http.current_ip[0].response_body)
  end_ip_address       = chomp(data.http.current_ip[0].response_body)
}

# Synapse firewall rules for allowed IP addresses
resource "azurerm_synapse_firewall_rule" "allowed_ips" {
  for_each = var.enable_synapse_workspace ? toset(var.allowed_ip_addresses) : toset([])

  name                 = "AllowIP-${replace(each.value, ".", "-")}"
  synapse_workspace_id = azurerm_synapse_workspace.analytics[0].id
  start_ip_address     = each.value
  end_ip_address       = each.value
}

# Role assignment: Grant Synapse managed identity access to Purview
resource "azurerm_role_assignment" "synapse_purview_access" {
  count = var.enable_synapse_workspace ? 1 : 0

  scope                = azurerm_purview_account.governance.id
  role_definition_name = "Purview Data Curator"
  principal_id         = azurerm_synapse_workspace.analytics[0].identity[0].principal_id
}

# Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "governance" {
  count = var.enable_diagnostic_logs ? 1 : 0

  name                = "${var.name_prefix}-logs-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.governance.name
  location            = azurerm_resource_group.governance.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(local.common_tags, {
    Type    = "Monitoring"
    Purpose = "CentralizedLogging"
  })
}

# Diagnostic settings for Purview account
resource "azurerm_monitor_diagnostic_setting" "purview" {
  count = var.enable_diagnostic_logs ? 1 : 0

  name                       = "purview-diagnostics"
  target_resource_id         = azurerm_purview_account.governance.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.governance[0].id

  # Enable all available log categories
  enabled_log {
    category = "ScanStatusLogEvent"
  }

  # Enable all available metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count = var.enable_diagnostic_logs ? 1 : 0

  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.data_lake.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.governance[0].id

  # Enable storage metrics
  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Diagnostic settings for Synapse workspace
resource "azurerm_monitor_diagnostic_setting" "synapse" {
  count = var.enable_synapse_workspace && var.enable_diagnostic_logs ? 1 : 0

  name                       = "synapse-diagnostics"
  target_resource_id         = azurerm_synapse_workspace.analytics[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.governance[0].id

  # Enable Synapse log categories
  enabled_log {
    category = "SynapseRbacOperations"
  }

  enabled_log {
    category = "GatewayApiRequests"
  }

  # Enable Synapse metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Time delay to ensure resources are fully provisioned before access attempts
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_purview_account.governance,
    azurerm_storage_account.data_lake,
    azurerm_role_assignment.purview_storage_reader
  ]
  
  create_duration = "60s"
}
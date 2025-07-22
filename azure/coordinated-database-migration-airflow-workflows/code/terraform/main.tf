# ===================================================================================
# Terraform Main Configuration: Intelligent Database Migration Orchestration
# Description: Deploys Azure Data Factory with Workflow Orchestration Manager,
#              Database Migration Service, and comprehensive monitoring infrastructure
# Version: 1.0
# ===================================================================================

# ===================================================================================
# DATA SOURCES
# ===================================================================================

# Current Azure client configuration
data "azurerm_client_config" "current" {}

# Current resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# ===================================================================================
# RANDOM RESOURCES FOR UNIQUE NAMING
# ===================================================================================

# Generate a random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ===================================================================================
# LOCAL VALUES FOR RESOURCE NAMING
# ===================================================================================

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # Resource names with auto-generation fallback
  data_factory_name     = var.data_factory_name != "" ? var.data_factory_name : "adf-${local.name_prefix}-${local.name_suffix}"
  dms_name             = var.dms_name != "" ? var.dms_name : "dms-${local.name_prefix}-${local.name_suffix}"
  storage_account_name = var.storage_account_name != "" ? var.storage_account_name : "st${replace(local.name_suffix, "-", "")}migration"
  log_analytics_name   = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${local.name_prefix}-${local.name_suffix}"
  action_group_name    = var.action_group_name != "" ? var.action_group_name : "ag-${local.name_prefix}-${local.name_suffix}"
  
  # Combined tags
  common_tags = merge(var.tags, {
    environment   = var.environment
    deployedBy    = "terraform"
    deployedDate  = timestamp()
  })
}

# ===================================================================================
# LOG ANALYTICS WORKSPACE
# ===================================================================================

# Log Analytics workspace for centralized monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  daily_quota_gb      = var.log_analytics_daily_quota_gb
  
  # Enhanced security and access settings
  internet_ingestion_enabled = true
  internet_query_enabled     = true
  
  tags = local.common_tags
}

# ===================================================================================
# STORAGE ACCOUNT FOR AIRFLOW AND MIGRATION ARTIFACTS
# ===================================================================================

# Storage account for Airflow DAGs, migration artifacts, and logs
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.storage_access_tier
  
  # Security settings
  min_tls_version           = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled = true
  https_traffic_only_enabled = true
  
  # Network access settings
  public_network_access_enabled = var.enable_private_endpoints ? false : true
  
  # Blob properties for enhanced data management
  blob_properties {
    versioning_enabled       = var.enable_storage_versioning
    change_feed_enabled      = var.enable_storage_change_feed
    change_feed_retention_in_days = var.enable_storage_change_feed ? 7 : null
    last_access_time_enabled = true
    
    container_delete_retention_policy {
      days = var.storage_container_delete_retention_days
    }
    
    delete_retention_policy {
      days = var.storage_container_delete_retention_days
    }
  }
  
  # Network rules for secure access
  network_rules {
    default_action             = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
  
  tags = local.common_tags
}

# Storage containers for organized data management
resource "azurerm_storage_container" "containers" {
  for_each = toset(var.storage_container_names)
  
  name                  = each.value
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# ===================================================================================
# AZURE DATA FACTORY
# ===================================================================================

# Azure Data Factory for orchestrating migration workflows
resource "azurerm_data_factory" "main" {
  name                = local.data_factory_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  
  # Managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }
  
  # Git integration configuration (if enabled)
  dynamic "github_configuration" {
    for_each = var.enable_git_integration && var.git_configuration.type == "FactoryGitHubConfiguration" ? [1] : []
    content {
      account_name         = var.git_configuration.account_name
      repository_name      = var.git_configuration.repository_name
      branch_name          = var.git_configuration.collaboration_branch
      root_folder          = var.git_configuration.root_folder
      git_url              = "https://github.com"
    }
  }
  
  # Enhanced security settings
  public_network_enabled = true
  
  tags = local.common_tags
}

# Managed Virtual Network for Data Factory (if enabled)
resource "azurerm_data_factory_managed_virtual_network" "main" {
  count           = var.enable_managed_vnet ? 1 : 0
  name            = "default"
  data_factory_id = azurerm_data_factory.main.id
}

# Self-hosted Integration Runtime for on-premises connectivity
resource "azurerm_data_factory_integration_runtime_self_hosted" "main" {
  name            = "OnPremisesIR"
  data_factory_id = azurerm_data_factory.main.id
  description     = "Self-hosted Integration Runtime for on-premises database connectivity"
}

# Linked Service for Storage Account
resource "azurerm_data_factory_linked_service_azure_blob_storage" "airflow_storage" {
  name            = "AirflowStorage"
  data_factory_id = azurerm_data_factory.main.id
  description     = "Azure Blob Storage for Airflow DAGs and migration artifacts"
  
  integration_runtime_name = azurerm_data_factory_integration_runtime_self_hosted.main.name
  
  connection_string = azurerm_storage_account.main.primary_connection_string
  
  depends_on = [azurerm_storage_account.main]
}

# ===================================================================================
# DATABASE MIGRATION SERVICE
# ===================================================================================

# Database Migration Service for handling database migrations
resource "azurerm_database_migration_service" "main" {
  name                = local.dms_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = var.dms_subnet_id != "" ? var.dms_subnet_id : null
  sku_name            = var.dms_sku
  
  tags = local.common_tags
}

# ===================================================================================
# MONITORING AND ALERTING
# ===================================================================================

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.action_group_name
  resource_group_name = data.azurerm_resource_group.main.name
  short_name          = "migration"
  
  email_receiver {
    name          = "migration-team"
    email_address = var.alert_notification_email
  }
  
  tags = local.common_tags
}

# Metric alerts for proactive monitoring
resource "azurerm_monitor_metric_alert" "alerts" {
  for_each = var.enable_monitoring ? { for alert in var.alert_rules : alert.name => alert } : {}
  
  name                = "${each.value.name}-${local.name_suffix}"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [azurerm_database_migration_service.main.id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = each.value.evaluation_frequency
  window_size         = each.value.window_size
  
  criteria {
    metric_namespace = each.value.metric_namespace
    metric_name      = each.value.metric_name
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
  
  depends_on = [azurerm_database_migration_service.main]
}

# ===================================================================================
# DIAGNOSTIC SETTINGS
# ===================================================================================

# Diagnostic settings for Data Factory
resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "adf-diagnostics"
  target_resource_id = azurerm_data_factory.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all log categories
  enabled_log {
    category_group = "allLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Database Migration Service
resource "azurerm_monitor_diagnostic_setting" "dms" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "dms-diagnostics"
  target_resource_id = azurerm_database_migration_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all log categories
  enabled_log {
    category_group = "allLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "storage-diagnostics"
  target_resource_id = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable storage metrics
  metric {
    category = "Transaction"
    enabled  = true
  }
}

# ===================================================================================
# RBAC ASSIGNMENTS
# ===================================================================================

# Data Factory Managed Identity -> Storage Blob Data Contributor
resource "azurerm_role_assignment" "data_factory_storage" {
  count                = var.enable_rbac_assignments ? 1 : 0
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
  
  depends_on = [azurerm_data_factory.main, azurerm_storage_account.main]
}

# Data Factory Managed Identity -> Log Analytics Contributor
resource "azurerm_role_assignment" "data_factory_monitoring" {
  count                = var.enable_rbac_assignments ? 1 : 0
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
  
  depends_on = [azurerm_data_factory.main, azurerm_log_analytics_workspace.main]
}

# ===================================================================================
# PRIVATE ENDPOINTS (OPTIONAL)
# ===================================================================================

# Private endpoint for Storage Account Blob service
resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.storage_account_name}-blob-pe"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = var.private_endpoint_subnet_id
  
  private_service_connection {
    name                           = "${local.storage_account_name}-blob-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

# Private DNS zone for storage blob private endpoint
resource "azurerm_private_dns_zone" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Private DNS zone virtual network link
resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "storage-blob-dns-link"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = var.virtual_network_id
  
  tags = local.common_tags
}

# Private DNS A record for storage blob endpoint
resource "azurerm_private_dns_a_record" "storage_blob" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = local.storage_account_name
  zone_name           = azurerm_private_dns_zone.storage_blob[0].name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_blob[0].private_service_connection[0].private_ip_address]
  
  tags = local.common_tags
}

# ===================================================================================
# ADDITIONAL MONITORING RESOURCES
# ===================================================================================

# Application Insights for enhanced monitoring (optional)
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${local.name_prefix}-${local.name_suffix}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  # Enhanced telemetry settings
  retention_in_days   = var.log_analytics_retention_days
  daily_data_cap_in_gb = 10
  
  tags = local.common_tags
}

# ===================================================================================
# WAIT RESOURCES FOR DEPLOYMENT COORDINATION
# ===================================================================================

# Wait for role assignments to propagate before proceeding
resource "time_sleep" "rbac_propagation" {
  count           = var.enable_rbac_assignments ? 1 : 0
  create_duration = "60s"
  
  depends_on = [
    azurerm_role_assignment.data_factory_storage,
    azurerm_role_assignment.data_factory_monitoring
  ]
}
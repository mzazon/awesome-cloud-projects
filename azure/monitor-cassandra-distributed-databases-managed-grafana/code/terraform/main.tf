# Generate unique suffix for resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent resource naming
locals {
  suffix = random_string.suffix.result
  
  # Resource names with consistent naming convention
  resource_group_name     = "rg-${var.project_name}-${local.suffix}"
  vnet_name              = "vnet-${var.project_name}-${local.suffix}"
  cassandra_cluster_name = "cassandra-${local.suffix}"
  datacenter_name        = "dc1"
  grafana_name           = "grafana-${local.suffix}"
  law_name               = "law-${var.project_name}-${local.suffix}"
  action_group_name      = "ag-${var.project_name}-alerts"
  
  # Merged tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Location    = var.location
    CreatedBy   = "terraform"
    Timestamp   = timestamp()
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual Network for Cassandra deployment
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.main]
}

# Subnet dedicated for Cassandra nodes
resource "azurerm_subnet" "cassandra" {
  name                 = "cassandra-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.cassandra_subnet_address_prefix]

  # Enable subnet delegation for Cassandra Managed Instance
  delegation {
    name = "cassandra-delegation"
    service_delegation {
      name = "Microsoft.DocumentDB/cassandraClusters"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }

  depends_on = [azurerm_virtual_network.main]
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.law_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.main]
}

# Azure Managed Instance for Apache Cassandra Cluster
resource "azurerm_cosmosdb_cassandra_cluster" "main" {
  name                           = local.cassandra_cluster_name
  resource_group_name            = azurerm_resource_group.main.name
  location                       = azurerm_resource_group.main.location
  delegated_management_subnet_id = azurerm_subnet.cassandra.id
  default_admin_password         = var.cassandra_admin_password
  
  # Enable authentication via client certificates for enhanced security
  authentication_method = "Cassandra"
  version              = var.cassandra_version
  
  # Configure automatic repair and backup
  repair_enabled               = true
  client_certificate_pems      = []
  
  tags = local.common_tags

  depends_on = [
    azurerm_subnet.cassandra,
    azurerm_log_analytics_workspace.main
  ]
}

# Cassandra Data Center with specified node configuration
resource "azurerm_cosmosdb_cassandra_datacenter" "main" {
  name                           = local.datacenter_name
  cassandra_cluster_id           = azurerm_cosmosdb_cassandra_cluster.main.id
  location                       = azurerm_resource_group.main.location
  delegated_management_subnet_id = azurerm_subnet.cassandra.id
  node_count                     = var.datacenter_node_count
  sku_name                       = var.datacenter_sku
  
  # Configure availability zones for high availability
  availability_zones_enabled = true
  
  # Configure disk and backup settings
  disk_count     = 4
  disk_sku       = "P30"
  backup_storage_customer_key_uri = null
  managed_disk_customer_key_uri   = null

  depends_on = [azurerm_cosmosdb_cassandra_cluster.main]
}

# Azure Managed Grafana for visualization and dashboards
resource "azurerm_dashboard_grafana" "main" {
  name                = local.grafana_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.grafana_sku

  # Configure authentication and access
  api_key_enabled                     = var.grafana_api_key_enabled
  deterministic_outbound_ip_enabled   = var.grafana_deterministic_outbound_ip_enabled
  public_network_access_enabled       = var.grafana_public_network_access_enabled

  # Configure Azure Monitor integration
  azure_monitor_workspace_integrations {
    resource_id = azurerm_log_analytics_workspace.main.id
  }

  # Use system-assigned managed identity for Azure Monitor access
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

  depends_on = [azurerm_log_analytics_workspace.main]
}

# Monitor Diagnostic Settings for Cassandra cluster
resource "azurerm_monitor_diagnostic_setting" "cassandra" {
  name                       = "cassandra-diagnostics"
  target_resource_id         = azurerm_cosmosdb_cassandra_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable all available log categories
  enabled_log {
    category = "CassandraLogs"
  }

  enabled_log {
    category = "CassandraAudit"
  }

  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azurerm_cosmosdb_cassandra_cluster.main,
    azurerm_log_analytics_workspace.main
  ]
}

# Role assignment for Grafana to access Azure Monitor data
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id

  depends_on = [azurerm_dashboard_grafana.main]
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.alert_enabled ? 1 : 0
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "CassAlert"

  # Email notification configuration
  email_receiver {
    name          = "ops-team"
    email_address = var.notification_email
  }

  tags = local.common_tags

  depends_on = [azurerm_resource_group.main]
}

# Metric Alert for high CPU usage
resource "azurerm_monitor_metric_alert" "high_cpu" {
  count               = var.alert_enabled ? 1 : 0
  name                = "cassandra-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cosmosdb_cassandra_cluster.main.id]
  description         = "Alert when Cassandra CPU usage exceeds ${var.cpu_alert_threshold}%"
  severity            = 2
  enabled             = true
  
  # Alert evaluation settings
  frequency                = var.alert_evaluation_frequency
  window_size             = var.alert_window_size
  auto_mitigate           = true

  # CPU usage criteria
  criteria {
    metric_namespace = "Microsoft.DocumentDB/cassandraClusters"
    metric_name      = "CPUUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  # Action to take when alert fires
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags

  depends_on = [
    azurerm_cosmosdb_cassandra_cluster.main,
    azurerm_monitor_action_group.main
  ]
}

# Metric Alert for high memory usage
resource "azurerm_monitor_metric_alert" "high_memory" {
  count               = var.alert_enabled ? 1 : 0
  name                = "cassandra-high-memory"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cosmosdb_cassandra_cluster.main.id]
  description         = "Alert when Cassandra memory usage exceeds 85%"
  severity            = 2
  enabled             = true
  
  frequency                = var.alert_evaluation_frequency
  window_size             = var.alert_window_size
  auto_mitigate           = true

  criteria {
    metric_namespace = "Microsoft.DocumentDB/cassandraClusters"
    metric_name      = "MemoryUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags

  depends_on = [
    azurerm_cosmosdb_cassandra_cluster.main,
    azurerm_monitor_action_group.main
  ]
}

# Metric Alert for low disk space
resource "azurerm_monitor_metric_alert" "low_disk_space" {
  count               = var.alert_enabled ? 1 : 0
  name                = "cassandra-low-disk-space"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cosmosdb_cassandra_cluster.main.id]
  description         = "Alert when available disk space is below 20%"
  severity            = 1
  enabled             = true
  
  frequency                = var.alert_evaluation_frequency
  window_size             = var.alert_window_size
  auto_mitigate           = true

  criteria {
    metric_namespace = "Microsoft.DocumentDB/cassandraClusters"
    metric_name      = "DiskUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80  # Alert when disk usage exceeds 80% (less than 20% free)
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags

  depends_on = [
    azurerm_cosmosdb_cassandra_cluster.main,
    azurerm_monitor_action_group.main
  ]
}
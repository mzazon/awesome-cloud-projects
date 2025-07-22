# Main Terraform Configuration for Azure Stateful Workload Monitoring
# This file creates the complete infrastructure for monitoring stateful workloads
# using Azure Container Storage and Azure Managed Prometheus

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and tagging
locals {
  suffix = random_id.suffix.hex
  
  # Resource naming
  resource_group_name           = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${local.suffix}"
  container_app_environment_name = var.container_app_environment_name != "" ? var.container_app_environment_name : "cae-${var.project_name}-${local.suffix}"
  container_app_name            = var.container_app_name != "" ? var.container_app_name : "ca-${var.project_name}-${local.suffix}"
  storage_account_name          = "st${replace(var.project_name, "-", "")}${local.suffix}"
  monitor_workspace_name        = var.monitor_workspace_name != "" ? var.monitor_workspace_name : "amw-${var.project_name}-${local.suffix}"
  log_analytics_workspace_name  = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-${local.suffix}"
  grafana_instance_name         = var.grafana_instance_name != "" ? var.grafana_instance_name : "grafana-${var.project_name}-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.common_tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "Terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  
  tags = merge(local.common_tags, {
    Description = "Resource group for stateful workload monitoring solution"
  })
}

# Create Virtual Network for Container Apps (if enabled)
resource "azurerm_virtual_network" "main" {
  count = var.enable_vnet_integration ? 1 : 0
  
  name                = "vnet-${var.project_name}-${local.suffix}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    Description = "Virtual network for container apps environment"
  })
}

# Create subnet for Container Apps
resource "azurerm_subnet" "container_apps" {
  count = var.enable_vnet_integration ? 1 : 0
  
  name                 = "snet-container-apps"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.container_subnet_address_prefix]
  
  delegation {
    name = "container-apps-delegation"
    
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Create Log Analytics Workspace for Container Apps and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    Description = "Log Analytics workspace for container apps and monitoring"
  })
}

# Create Azure Monitor Workspace for Prometheus
resource "azurerm_monitor_workspace" "main" {
  name                = local.monitor_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    Description = "Azure Monitor workspace for Prometheus metrics"
  })
}

# Create Storage Account for Container Storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security settings
  https_traffic_only_enabled      = var.enable_https_only
  allow_nested_items_to_be_public = var.enable_blob_public_access
  
  # Network rules for storage firewall
  dynamic "network_rules" {
    for_each = var.enable_storage_firewall ? [1] : []
    
    content {
      default_action = "Deny"
      bypass         = ["AzureServices"]
      
      # Allow access from Container Apps subnet if VNet integration is enabled
      virtual_network_subnet_ids = var.enable_vnet_integration ? [azurerm_subnet.container_apps[0].id] : []
    }
  }
  
  tags = merge(local.common_tags, {
    Description = "Storage account for container persistent storage"
  })
}

# Create storage share for PostgreSQL data
resource "azurerm_storage_share" "postgresql_data" {
  name                 = "postgresql-data"
  storage_account_name = azurerm_storage_account.main.name
  quota                = var.storage_share_quota
  
  depends_on = [azurerm_storage_account.main]
}

# Create Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_app_environment_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # VNet integration if enabled
  infrastructure_subnet_id = var.enable_vnet_integration ? azurerm_subnet.container_apps[0].id : null
  
  tags = merge(local.common_tags, {
    Description = "Container Apps environment for stateful workloads"
  })
}

# Create Container Apps Environment Storage for persistent volumes
resource "azurerm_container_app_environment_storage" "main" {
  name                         = "postgresql-storage"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.postgresql_data.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

# Create main stateful application (PostgreSQL)
resource "azurerm_container_app" "main" {
  name                         = local.container_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  template {
    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas
    
    # Volume configuration for persistent storage
    volume {
      name         = "data-volume"
      storage_name = azurerm_container_app_environment_storage.main.name
      storage_type = "AzureFile"
    }
    
    # Main PostgreSQL container
    container {
      name   = "postgresql"
      image  = var.container_app_image
      cpu    = var.container_app_cpu
      memory = var.container_app_memory
      
      # Environment variables for PostgreSQL
      env {
        name  = "POSTGRES_DB"
        value = var.postgres_database_name
      }
      
      env {
        name  = "POSTGRES_USER"
        value = var.postgres_username
      }
      
      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-password"
      }
      
      # Volume mount for data persistence
      volume_mounts {
        name = "data-volume"
        path = "/var/lib/postgresql/data"
      }
      
      # Readiness probe
      readiness_probe {
        transport = "TCP"
        port      = 5432
        
        initial_delay_seconds = 10
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 3
        success_threshold     = 1
      }
      
      # Liveness probe
      liveness_probe {
        transport = "TCP"
        port      = 5432
        
        initial_delay_seconds = 30
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3
        success_threshold     = 1
      }
    }
  }
  
  # Ingress configuration
  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 5432
    transport                  = "tcp"
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  
  # Secrets configuration
  secret {
    name  = "postgres-password"
    value = var.postgres_password
  }
  
  tags = merge(local.common_tags, {
    Description = "Main stateful application with PostgreSQL"
  })
  
  depends_on = [azurerm_container_app_environment_storage.main]
}

# Create monitoring sidecar container app (if enabled)
resource "azurerm_container_app" "monitoring_sidecar" {
  count = var.enable_monitoring_sidecar ? 1 : 0
  
  name                         = "monitoring-sidecar-${local.suffix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  template {
    min_replicas = 1
    max_replicas = 1
    
    container {
      name   = "node-exporter"
      image  = var.monitoring_sidecar_image
      cpu    = var.monitoring_sidecar_cpu
      memory = var.monitoring_sidecar_memory
      
      args = [
        "--path.rootfs=/host",
        "--web.listen-address=0.0.0.0:9100"
      ]
      
      # Health check
      readiness_probe {
        transport = "HTTP"
        port      = 9100
        path      = "/metrics"
        
        initial_delay_seconds = 5
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 3
        success_threshold     = 1
      }
    }
  }
  
  # Internal ingress for metrics scraping
  ingress {
    allow_insecure_connections = false
    external_enabled           = false
    target_port                = 9100
    transport                  = "http"
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  
  tags = merge(local.common_tags, {
    Description = "Monitoring sidecar for system metrics collection"
  })
}

# Create Azure Managed Grafana instance
resource "azurerm_dashboard_grafana" "main" {
  name                          = local.grafana_instance_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  api_key_enabled               = true
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled = true
  sku                           = var.grafana_sku
  
  # Azure Monitor integration
  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.main.id
  }
  
  # Identity configuration for accessing Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    Description = "Azure Managed Grafana for monitoring dashboards"
  })
}

# Grant Grafana access to Monitor Workspace
resource "azurerm_role_assignment" "grafana_monitor_reader" {
  scope                = azurerm_monitor_workspace.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id
}

# Create Data Collection Endpoint for Prometheus
resource "azurerm_monitor_data_collection_endpoint" "main" {
  name                          = "dce-${var.project_name}-${local.suffix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  kind                          = "Linux"
  public_network_access_enabled = true
  
  tags = merge(local.common_tags, {
    Description = "Data collection endpoint for Prometheus metrics"
  })
}

# Create Data Collection Rule for Container Apps monitoring
resource "azurerm_monitor_data_collection_rule" "main" {
  name                = "dcr-${var.project_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Data collection endpoint
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.main.id
  
  # Destinations - Azure Monitor Workspace
  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.main.id
      name               = "MonitoringAccount1"
    }
  }
  
  # Data flow for Prometheus metrics
  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }
  
  # Data sources for Prometheus scraping
  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }
  
  tags = merge(local.common_tags, {
    Description = "Data collection rule for Container Apps Prometheus metrics"
  })
}

# Create Action Group for alerts (if alerts are enabled)
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "ag-${var.project_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "stateful"
  
  # Email notification (example - customize as needed)
  email_receiver {
    name                    = "admin-email"
    email_address           = "admin@example.com"
    use_common_alert_schema = true
  }
  
  tags = merge(local.common_tags, {
    Description = "Action group for monitoring alerts"
  })
}

# Create CPU usage alert
resource "azurerm_monitor_metric_alert" "cpu_usage" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "cpu-usage-high-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.main.id]
  description         = "Alert when CPU usage exceeds threshold"
  
  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_threshold_percent
  }
  
  # Alert frequency and window
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  severity    = 2
  
  # Action group for notifications
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Description = "CPU usage alert for container apps"
  })
}

# Create memory usage alert
resource "azurerm_monitor_metric_alert" "memory_usage" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "memory-usage-high-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.main.id]
  description         = "Alert when memory usage exceeds threshold"
  
  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.memory_threshold_percent
  }
  
  # Alert frequency and window
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  severity    = 2
  
  # Action group for notifications
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Description = "Memory usage alert for container apps"
  })
}

# Create storage utilization alert
resource "azurerm_monitor_metric_alert" "storage_usage" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "storage-usage-high-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.main.id]
  description         = "Alert when storage usage exceeds threshold"
  
  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "UsedCapacity"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = (var.storage_share_quota * 1024 * 1024 * 1024) * (var.storage_threshold_percent / 100)
  }
  
  # Alert frequency and window
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  severity    = 2
  
  # Action group for notifications
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Description = "Storage usage alert for storage account"
  })
}

# Create Application Insights for additional monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    Description = "Application Insights for container apps monitoring"
  })
}

# Create a diagnostic setting for Container Apps Environment
resource "azurerm_monitor_diagnostic_setting" "container_env" {
  name               = "containerenv-diagnostics"
  target_resource_id = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available logs
  enabled_log {
    category = "ContainerAppSystemLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create a diagnostic setting for the main Container App
resource "azurerm_monitor_diagnostic_setting" "container_app" {
  name               = "containerapp-diagnostics"
  target_resource_id = azurerm_container_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available logs
  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create wait time for resources to be fully provisioned
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_container_app.main,
    azurerm_monitor_workspace.main,
    azurerm_dashboard_grafana.main
  ]
  
  create_duration = "30s"
}
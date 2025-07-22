# Azure Quantum Financial Trading Algorithm Infrastructure
# This Terraform configuration deploys a complete quantum-enhanced financial trading system
# combining Azure Quantum, Elastic SAN, and Machine Learning services

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create locals for consistent resource naming and tagging
locals {
  # Resource naming convention
  resource_suffix = random_string.suffix.result
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-quantum-trading-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Purpose         = "quantum-trading"
    CostCenter      = "financial-technology"
    DeployedBy      = "terraform"
    CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
    QuantumEnabled  = "true"
    Workload        = "financial-algorithms"
  }, var.additional_tags)
  
  # Resource names with consistent naming convention
  elastic_san_name           = "esan-trading-${local.resource_suffix}"
  quantum_workspace_name     = "quantum-trading-${local.resource_suffix}"
  ml_workspace_name          = "mlws-quantum-trading-${local.resource_suffix}"
  storage_account_name       = "stquantum${local.resource_suffix}"
  key_vault_name            = "kv-quantum-${local.resource_suffix}"
  log_analytics_name        = "log-quantum-trading-${local.resource_suffix}"
  app_insights_name         = "ai-quantum-trading-${local.resource_suffix}"
  data_factory_name         = "df-market-data-${local.resource_suffix}"
  event_hub_namespace_name  = "eh-market-${local.resource_suffix}"
  stream_analytics_name     = "sa-quantum-trading-${local.resource_suffix}"
  
  # Network configuration for private endpoints
  vnet_address_space    = ["10.0.0.0/16"]
  subnet_address_prefix = "10.0.1.0/24"
}

# Resource Group for all quantum trading resources
resource "azurerm_resource_group" "quantum_trading" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual Network for secure connectivity
resource "azurerm_virtual_network" "quantum_trading" {
  name                = "vnet-quantum-trading-${local.resource_suffix}"
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  address_space       = local.vnet_address_space
  tags                = local.common_tags
}

# Subnet for private endpoints and secure connectivity
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.quantum_trading.name
  virtual_network_name = azurerm_virtual_network.quantum_trading.name
  address_prefixes     = [local.subnet_address_prefix]
  
  # Enable private endpoint network policies
  private_endpoint_network_policies_enabled = false
}

# Network Security Group for subnet protection
resource "azurerm_network_security_group" "quantum_trading" {
  name                = "nsg-quantum-trading-${local.resource_suffix}"
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  tags                = local.common_tags
  
  # Allow HTTPS traffic for Azure services
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
  
  # Allow management traffic from Azure
  security_rule {
    name                       = "AllowAzureManagement"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "quantum_trading" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.quantum_trading.id
}

# Key Vault for secure credential management
resource "azurerm_key_vault" "quantum_trading" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = "premium"
  
  # Enable advanced security features
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  enabled_for_deployment          = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  
  # Network access configuration
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = local.common_tags
}

# Current Azure client configuration for tenant ID
data "azurerm_client_config" "current" {}

# Key Vault access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.quantum_trading.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Import", "Backup", "Restore", "Recover"
  ]
  
  secret_permissions = [
    "Set", "Get", "Delete", "List", "Purge", "Backup", "Restore", "Recover"
  ]
  
  certificate_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Import", "Backup", "Restore", "Recover"
  ]
}

# Storage Account for Quantum workspace and general storage
resource "azurerm_storage_account" "quantum_trading" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.quantum_trading.name
  location                 = azurerm_resource_group.quantum_trading.location
  account_tier             = "Standard"
  account_replication_type = var.enable_geo_redundancy ? "GRS" : "LRS"
  account_kind             = "StorageV2"
  
  # Security configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob configuration
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 7
    
    # Container delete retention
    container_delete_retention_policy {
      days = var.backup_retention_days
    }
    
    # Blob delete retention
    delete_retention_policy {
      days = var.backup_retention_days
    }
  }
  
  tags = local.common_tags
}

# Azure Elastic SAN for ultra-high-performance storage
resource "azurerm_elastic_san" "quantum_trading" {
  name                = local.elastic_san_name
  resource_group_name = azurerm_resource_group.quantum_trading.name
  location            = azurerm_resource_group.quantum_trading.location
  
  base_size_in_tib              = var.elastic_san_base_size_tib
  extended_capacity_size_in_tib = var.elastic_san_extended_capacity_tib
  
  sku {
    name = "Premium_LRS"
    tier = "Premium"
  }
  
  tags = merge(local.common_tags, {
    Performance = "ultra-high"
    Workload   = "trading"
  })
}

# Elastic SAN Volume Group for market data
resource "azurerm_elastic_san_volume_group" "market_data" {
  name           = "vg-market-data"
  elastic_san_id = azurerm_elastic_san.quantum_trading.id
  
  # Network access rules for security
  dynamic "network_rule" {
    for_each = var.allowed_ip_ranges
    content {
      subnet_id = azurerm_subnet.private_endpoints.id
      action    = "Allow"
    }
  }
  
  tags = local.common_tags
}

# Elastic SAN Volume for real-time market data
resource "azurerm_elastic_san_volume" "realtime_data" {
  name            = "vol-realtime-data"
  volume_group_id = azurerm_elastic_san_volume_group.market_data.id
  size_in_gib     = var.market_data_volume_size_gib
  
  tags = merge(local.common_tags, {
    DataType = "market-realtime"
    Critical = "true"
  })
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "quantum_trading" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "quantum_trading" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  workspace_id        = azurerm_log_analytics_workspace.quantum_trading.id
  application_type    = "web"
  
  tags = local.common_tags
}

# Azure Quantum Workspace
resource "azurerm_quantum_workspace" "quantum_trading" {
  name                = local.quantum_workspace_name
  resource_group_name = azurerm_resource_group.quantum_trading.name
  location            = azurerm_resource_group.quantum_trading.location
  storage_account_id  = azurerm_storage_account.quantum_trading.id
  
  tags = merge(local.common_tags, {
    Service     = "quantum-computing"
    UseCases    = "portfolio-optimization"
    Algorithms  = "quantum-annealing,variational-quantum"
  })
}

# Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "quantum_trading" {
  name                    = local.ml_workspace_name
  location                = azurerm_resource_group.quantum_trading.location
  resource_group_name     = azurerm_resource_group.quantum_trading.name
  application_insights_id = var.enable_application_insights ? azurerm_application_insights.quantum_trading[0].id : null
  key_vault_id           = azurerm_key_vault.quantum_trading.id
  storage_account_id     = azurerm_storage_account.quantum_trading.id
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  # Public network access configuration
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = merge(local.common_tags, {
    MLFramework = "hybrid-quantum-classical"
    Purpose     = "trading-algorithms"
  })
}

# Machine Learning Compute Cluster for hybrid algorithm execution
resource "azurerm_machine_learning_compute_cluster" "quantum_compute" {
  name                          = "quantum-compute-cluster"
  location                      = azurerm_resource_group.quantum_trading.location
  vm_priority                   = "Dedicated"
  vm_size                       = var.ml_compute_instances.vm_size
  machine_learning_workspace_id = azurerm_machine_learning_workspace.quantum_trading.id
  
  scale_settings {
    min_node_count                       = var.ml_compute_instances.min_nodes
    max_node_count                       = var.ml_compute_instances.max_nodes
    scale_down_nodes_after_idle_duration = "PT30M" # 30 minutes
  }
  
  # Auto-shutdown configuration for cost optimization
  dynamic "schedule" {
    for_each = var.enable_auto_shutdown ? [1] : []
    content {
      compute_start_stop {
        start_time = "0800"
        stop_time  = var.auto_shutdown_time
        time_zone  = "UTC"
        
        # Schedule for business days only
        recurrence {
          frequency = "Week"
          interval  = 1
          week_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        }
      }
    }
  }
  
  tags = merge(local.common_tags, {
    ComputeType = "quantum-hybrid"
    AutoShutdown = var.enable_auto_shutdown ? "enabled" : "disabled"
  })
}

# Event Hub Namespace for real-time market data streaming
resource "azurerm_eventhub_namespace" "market_data" {
  name                = local.event_hub_namespace_name
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  sku                 = "Standard"
  capacity            = var.event_hub_throughput_units
  
  # Auto-inflate for handling traffic bursts
  auto_inflate_enabled     = true
  maximum_throughput_units = var.event_hub_throughput_units * 2
  
  tags = merge(local.common_tags, {
    DataFlow = "market-streaming"
    Capacity = "high-throughput"
  })
}

# Event Hub for market data stream
resource "azurerm_eventhub" "market_data_stream" {
  name                = "market-data-stream"
  namespace_name      = azurerm_eventhub_namespace.market_data.name
  resource_group_name = azurerm_resource_group.quantum_trading.name
  partition_count     = 4
  message_retention   = 1
  
  # Capture configuration for data lake storage
  capture_description {
    enabled  = true
    encoding = "Avro"
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.market_data_archive.name
      storage_account_id  = azurerm_storage_account.quantum_trading.id
    }
  }
}

# Storage container for market data archive
resource "azurerm_storage_container" "market_data_archive" {
  name                  = "market-data-archive"
  storage_account_name  = azurerm_storage_account.quantum_trading.name
  container_access_type = "private"
}

# Data Factory for market data ingestion and processing
resource "azurerm_data_factory" "market_data" {
  name                = local.data_factory_name
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  
  # Managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  # Git configuration if enabled
  dynamic "github_configuration" {
    for_each = var.data_factory_git_config.enabled ? [1] : []
    content {
      account_name    = split("/", var.data_factory_git_config.repository_url)[3]
      repository_name = split("/", var.data_factory_git_config.repository_url)[4]
      branch_name     = var.data_factory_git_config.collaboration_branch
      root_folder     = var.data_factory_git_config.root_folder
    }
  }
  
  tags = merge(local.common_tags, {
    DataPipeline = "market-ingestion"
    Integration  = "real-time"
  })
}

# Stream Analytics Job for real-time market data processing
resource "azurerm_stream_analytics_job" "quantum_trading" {
  name                = local.stream_analytics_name
  resource_group_name = azurerm_resource_group.quantum_trading.name
  location            = azurerm_resource_group.quantum_trading.location
  
  transformation_query = <<QUERY
SELECT 
    symbol,
    price,
    volume,
    timestamp,
    System.Timestamp() AS processing_time
INTO
    [processed-market-data]
FROM
    [market-data-input]
WHERE
    price IS NOT NULL AND volume > 0
QUERY
  
  streaming_units = var.stream_analytics_streaming_units
  
  tags = merge(local.common_tags, {
    StreamProcessing = "real-time"
    DataTransform    = "market-preparation"
  })
}

# Role assignments for service integrations

# Assign Storage Blob Data Contributor to ML workspace
resource "azurerm_role_assignment" "ml_storage_access" {
  scope                = azurerm_storage_account.quantum_trading.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.quantum_trading.identity[0].principal_id
}

# Assign Quantum Workspace Contributor to ML workspace for hybrid algorithms
resource "azurerm_role_assignment" "ml_quantum_access" {
  scope                = azurerm_quantum_workspace.quantum_trading.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_machine_learning_workspace.quantum_trading.identity[0].principal_id
}

# Assign Event Hub Data Receiver to Data Factory
resource "azurerm_role_assignment" "df_eventhub_access" {
  scope                = azurerm_eventhub.market_data_stream.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_data_factory.market_data.identity[0].principal_id
}

# Monitor action group for alerting
resource "azurerm_monitor_action_group" "quantum_trading" {
  name                = "ag-quantum-trading-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.quantum_trading.name
  short_name          = "quantalert"
  
  # Email notification for critical alerts
  email_receiver {
    name          = "trading-team"
    email_address = "trading-alerts@company.com"
  }
  
  tags = local.common_tags
}

# Metric alert for quantum optimization latency
resource "azurerm_monitor_metric_alert" "quantum_latency" {
  name                = "quantum-optimization-latency"
  resource_group_name = azurerm_resource_group.quantum_trading.name
  scopes              = [azurerm_quantum_workspace.quantum_trading.id]
  description         = "Alert when quantum optimization exceeds latency threshold"
  
  criteria {
    metric_namespace = "Microsoft.Quantum/workspaces"
    metric_name      = "JobDuration"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000 # 5 seconds
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.quantum_trading.id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2
  
  tags = local.common_tags
}

# Diagnostic settings for comprehensive logging
resource "azurerm_monitor_diagnostic_setting" "quantum_workspace" {
  name                       = "quantum-diagnostics"
  target_resource_id         = azurerm_quantum_workspace.quantum_trading.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.quantum_trading.id
  
  enabled_log {
    category = "AuditEvent"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "ml_workspace" {
  name                       = "ml-diagnostics"
  target_resource_id         = azurerm_machine_learning_workspace.quantum_trading.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.quantum_trading.id
  
  enabled_log {
    category = "AmlComputeClusterEvent"
  }
  
  enabled_log {
    category = "AmlComputeJobEvent"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Private endpoints for enhanced security (if enabled)
resource "azurerm_private_endpoint" "storage" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "pe-storage-${local.resource_suffix}"
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "storage-connection"
    private_connection_resource_id = azurerm_storage_account.quantum_trading.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "pe-keyvault-${local.resource_suffix}"
  location            = azurerm_resource_group.quantum_trading.location
  resource_group_name = azurerm_resource_group.quantum_trading.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  
  private_service_connection {
    name                           = "keyvault-connection"
    private_connection_resource_id = azurerm_key_vault.quantum_trading.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}
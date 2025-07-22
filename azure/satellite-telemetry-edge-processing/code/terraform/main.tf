# Main Terraform configuration for Azure Orbital and Azure Local edge-to-orbit data processing
# This file creates the complete infrastructure for satellite data processing at scale

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Merge default and additional tags
locals {
  common_tags = merge(var.tags, var.additional_tags, {
    DeploymentId = random_string.suffix.result
    LastUpdated  = timestamp()
  })
  
  # Generate unique resource names
  resource_group_name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  spacecraft_name         = "${var.spacecraft_name}-${random_string.suffix.result}"
  iot_hub_name           = "iot-${var.project_name}-${random_string.suffix.result}"
  event_grid_topic_name  = "orbital-events-${random_string.suffix.result}"
  storage_account_name   = "stor${var.project_name}${random_string.suffix.result}"
  function_app_name      = "func-${var.project_name}-${random_string.suffix.result}"
  azure_local_name       = var.azure_local_cluster_name != null ? var.azure_local_cluster_name : "local-${var.project_name}-${random_string.suffix.result}"
  log_analytics_name     = "law-${var.project_name}-${random_string.suffix.result}"
  key_vault_name         = "kv-${var.project_name}-${random_string.suffix.result}"
  virtual_network_name   = "vnet-${var.project_name}-${random_string.suffix.result}"
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Virtual Network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = local.virtual_network_name
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create subnets for different services
resource "azurerm_subnet" "orbital" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "orbital-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes.orbital_subnet]
  
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "function" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "function-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes.function_subnet]
  
  delegation {
    name = "serverfarm-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "storage" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "storage-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes.storage_subnet]
  
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "local" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "local-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes.local_subnet]
  
  private_endpoint_network_policies_enabled = false
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = merge(local.common_tags, { Service = "monitoring" })
}

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = merge(local.common_tags, { Service = "monitoring" })
}

# Create Azure Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  count                       = var.enable_key_vault ? 1 : 0
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  enabled_for_disk_encryption = true
  enabled_for_deployment      = true
  enabled_for_template_deployment = true
  purge_protection_enabled    = false
  soft_delete_retention_days  = 7
  
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Purge"
    ]
    
    key_permissions = [
      "Get", "List", "Create", "Delete", "Recover", "Purge"
    ]
  }
  
  tags = merge(local.common_tags, { Service = "security" })
}

# Create Storage Account for satellite data
resource "azurerm_storage_account" "main" {
  name                      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_replication_type
  access_tier               = var.storage_access_tier
  is_hns_enabled           = var.enable_hierarchical_namespace
  
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = var.satellite_data_retention_days
    
    container_delete_retention_policy {
      days = var.satellite_data_retention_days
    }
    
    delete_retention_policy {
      days = var.satellite_data_retention_days
    }
  }
  
  network_rules {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
  }
  
  tags = merge(local.common_tags, { Service = "storage" })
}

# Create storage containers for different data types
resource "azurerm_storage_container" "telemetry" {
  name                  = "satellite-telemetry"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "imagery" {
  name                  = "processed-imagery"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "analytics" {
  name                  = "analytics-results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create private endpoint for storage account (if enabled)
resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-storage-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.storage[0].id
  
  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = azurerm_storage_account.main.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
  
  tags = merge(local.common_tags, { Service = "storage" })
}

# Create IoT Hub for satellite telemetry ingestion
resource "azurerm_iothub" "main" {
  name                = local.iot_hub_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_capacity
  }
  
  event_hub_partition_count   = var.iot_hub_partition_count
  event_hub_retention_in_days = 1
  
  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.main.primary_connection_string
    name                       = "satellite-telemetry-endpoint"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.telemetry.name
    encoding                   = "JSON"
    file_name_format           = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"
  }
  
  route {
    name           = "satellite-telemetry-route"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["satellite-telemetry-endpoint"]
    enabled        = true
  }
  
  tags = merge(local.common_tags, { Service = "iot" })
}

# Create Event Grid Topic for orbital event orchestration
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = "EventGridSchema"
  
  tags = merge(local.common_tags, { Service = "event-grid" })
}

# Create Event Grid System Topic for IoT Hub integration
resource "azurerm_eventgrid_system_topic" "iothub" {
  name                   = "iot-orbital-system-topic"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  source_arm_resource_id = azurerm_iothub.main.id
  topic_type             = "Microsoft.Devices.IoTHubs"
  
  tags = merge(local.common_tags, { Service = "event-grid" })
}

# Create Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "sp-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = merge(local.common_tags, { Service = "compute" })
}

# Create Function App for satellite data processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  site_config {
    always_on = var.function_app_service_plan_sku != "Y1"
    
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = var.function_app_runtime
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : ""
    "IOT_HUB_CONNECTION_STRING"      = azurerm_iothub.main.primary_connection_string
    "EVENT_GRID_TOPIC_ENDPOINT"      = azurerm_eventgrid_topic.main.endpoint
    "EVENT_GRID_TOPIC_KEY"           = azurerm_eventgrid_topic.main.primary_access_key
    "STORAGE_CONNECTION_STRING"      = azurerm_storage_account.main.primary_connection_string
    "AZURE_LOCAL_CLUSTER_NAME"       = local.azure_local_name
    "PROJECT_NAME"                   = var.project_name
    "ENVIRONMENT"                    = var.environment
  }
  
  dynamic "virtual_network_subnet_id" {
    for_each = var.enable_private_endpoints ? [1] : []
    content {
      virtual_network_subnet_id = azurerm_subnet.function[0].id
    }
  }
  
  tags = merge(local.common_tags, { Service = "compute" })
}

# Create Event Grid Subscription for IoT Hub events
resource "azurerm_eventgrid_event_subscription" "iothub" {
  name  = "iot-orbital-subscription"
  scope = azurerm_iothub.main.id
  
  azure_function_endpoint {
    function_id = "${azurerm_linux_function_app.main.id}/functions/SatelliteDataProcessor"
  }
  
  included_event_types = [
    "Microsoft.Devices.DeviceTelemetry",
    "Microsoft.Devices.DeviceConnected",
    "Microsoft.Devices.DeviceDisconnected"
  ]
  
  subject_filter {
    subject_begins_with = "satellite/"
  }
  
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }
  
  depends_on = [azurerm_linux_function_app.main]
}

# Create Azure Stack HCI Cluster for Azure Local (if enabled)
resource "azurerm_stack_hci_cluster" "main" {
  count               = var.enable_azure_local ? 1 : 0
  name                = local.azure_local_name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.azure_local_location
  client_id           = data.azurerm_client_config.current.client_id
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, { Service = "azure-local" })
}

# Create Orbital Spacecraft registration
resource "azurerm_orbital_spacecraft" "main" {
  name                = local.spacecraft_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  norad_id            = var.norad_id
  title               = "Earth Observation Satellite"
  
  links {
    bandwidth_mhz        = var.bandwidth_mhz
    center_frequency_mhz = var.center_frequency_mhz
    direction            = "Downlink"
    name                 = "downlink"
    polarization         = "LHCP"
  }
  
  two_line_elements = [
    var.tle_line1,
    var.tle_line2
  ]
  
  tags = merge(local.common_tags, { Service = "orbital" })
}

# Create Orbital Contact Profile
resource "azurerm_orbital_contact_profile" "main" {
  name                              = "earth-obs-profile"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = azurerm_resource_group.main.location
  minimum_viable_contact_duration   = "PT${var.minimum_contact_duration}M"
  minimum_elevation_degrees         = var.minimum_elevation_degrees
  auto_tracking_configuration       = "X_Band"
  event_hub_uri                     = azurerm_iothub.main.event_hub_events_endpoint
  network_configuration_subnet_id   = var.enable_private_endpoints ? azurerm_subnet.orbital[0].id : null
  
  links {
    channels {
      name                 = "channel1"
      bandwidth_mhz        = var.bandwidth_mhz
      center_frequency_mhz = var.center_frequency_mhz
      end_point {
        end_point_name = "satellite-endpoint"
        ip_address     = "10.0.1.100"
        port           = "50000"
        protocol       = "TCP"
      }
    }
    direction            = "Downlink"
    name                 = "downlink"
    polarization         = "LHCP"
  }
  
  tags = merge(local.common_tags, { Service = "orbital" })
}

# Create diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "iothub" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "orbital-diagnostics"
  target_resource_id = azurerm_iothub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "Connections"
  }
  
  enabled_log {
    category = "DeviceTelemetry"
  }
  
  enabled_log {
    category = "C2DCommands"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create metric alerts for satellite communication failures
resource "azurerm_monitor_metric_alert" "satellite_connection_failure" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "satellite-connection-failure"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_iothub.main.id]
  description         = "Alert when satellite connection failures exceed threshold"
  
  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "d2c.telemetry.egress.dropped"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  window_size        = "PT15M"
  frequency          = "PT5M"
  severity           = 2
  
  tags = merge(local.common_tags, { Service = "monitoring" })
}

# Create action group for alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "orbital-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "orbital"
  
  email_receiver {
    name          = "orbital-team"
    email_address = "orbital-team@example.com"
  }
  
  tags = merge(local.common_tags, { Service = "monitoring" })
}

# Create Azure AI Services for satellite data analysis (if enabled)
resource "azurerm_cognitive_account" "main" {
  count               = var.enable_ai_services ? 1 : 0
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "CognitiveServices"
  sku_name            = "S0"
  
  tags = merge(local.common_tags, { Service = "ai" })
}

# Create Data Factory for data orchestration (if enabled)
resource "azurerm_data_factory" "main" {
  count               = var.enable_data_lake_analytics ? 1 : 0
  name                = "df-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, { Service = "analytics" })
}

# Create Key Vault secrets for sensitive configuration
resource "azurerm_key_vault_secret" "iot_connection_string" {
  count        = var.enable_key_vault ? 1 : 0
  name         = "iot-hub-connection-string"
  value        = azurerm_iothub.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main[0].id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  count        = var.enable_key_vault ? 1 : 0
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main[0].id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "event_grid_key" {
  count        = var.enable_key_vault ? 1 : 0
  name         = "event-grid-topic-key"
  value        = azurerm_eventgrid_topic.main.primary_access_key
  key_vault_id = azurerm_key_vault.main[0].id
  
  depends_on = [azurerm_key_vault.main]
}

# Create backup vault and policy (if disaster recovery is enabled)
resource "azurerm_data_protection_backup_vault" "main" {
  count               = var.enable_disaster_recovery ? 1 : 0
  name                = "bv-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  datastore_type      = "VaultStore"
  redundancy          = "LocallyRedundant"
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, { Service = "backup" })
}

# Create lifecycle management policy for storage
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id
  
  rule {
    name    = "satellite-data-lifecycle"
    enabled = true
    
    filters {
      prefix_match = ["satellite-telemetry/", "processed-imagery/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = var.satellite_data_retention_days
      }
      
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
}
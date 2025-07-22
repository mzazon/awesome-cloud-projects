# Main Terraform configuration for Smart Factory Carbon Footprint Monitoring
# This creates a comprehensive IoT and analytics solution for sustainability monitoring

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all smart factory resources
resource "azurerm_resource_group" "smart_factory" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  
  tags = merge(var.tags, {
    Name = "Smart Factory Carbon Monitoring Resource Group"
  })
}

# Create Storage Account for Function App and data storage
resource "azurerm_storage_account" "factory_storage" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.smart_factory.name
  location                 = azurerm_resource_group.smart_factory.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configurations
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable blob storage features
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = merge(var.tags, {
    Name        = "Factory Storage Account"
    Component   = "Storage"
    CostCenter  = "SmartFactory"
  })
}

# Create IoT Hub for industrial device connectivity
resource "azurerm_iothub" "factory_iot_hub" {
  name                = "iothub-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.smart_factory.name
  location            = azurerm_resource_group.smart_factory.location
  
  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_capacity
  }
  
  # Configure device-to-cloud messaging
  endpoint {
    type                       = "AzureIotHub.EventHub"
    connection_string          = azurerm_eventhub_authorization_rule.carbon_data.primary_connection_string
    name                       = "carbon-telemetry-endpoint"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes   = 10485760
    container_name            = azurerm_storage_container.carbon_data.name
    encoding                  = "Avro"
    file_name_format         = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }
  
  # Configure message routing for carbon monitoring
  route {
    name           = "CarbonDataRoute"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["carbon-telemetry-endpoint"]
    enabled        = true
  }
  
  # Enable cloud-to-device messaging
  cloud_to_device {
    max_delivery_count = 30
    default_ttl        = "PT1H"
    
    feedback {
      time_to_live       = "PT1H10M"
      max_delivery_count = 10
      lock_duration      = "PT30S"
    }
  }
  
  # Enable file upload capabilities
  file_upload {
    connection_string  = azurerm_storage_account.factory_storage.primary_blob_connection_string
    container_name     = azurerm_storage_container.file_uploads.name
    default_ttl        = "PT1H"
    max_delivery_count = 10
    
    notifications {
      enabled         = true
      max_delivery_count = 10
      time_to_live       = "PT1H"
    }
  }
  
  tags = merge(var.tags, {
    Name       = "Factory IoT Hub"
    Component  = "IoT"
    CostCenter = "SmartFactory"
  })
}

# Create Event Hubs Namespace for high-throughput event ingestion
resource "azurerm_eventhub_namespace" "carbon_events" {
  name                = "ehns-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.smart_factory.location
  resource_group_name = azurerm_resource_group.smart_factory.name
  sku                 = var.eventhub_sku
  capacity            = var.eventhub_capacity
  
  # Enable auto-inflate for dynamic scaling
  auto_inflate_enabled     = var.eventhub_sku == "Standard" ? true : false
  maximum_throughput_units = var.eventhub_sku == "Standard" ? 20 : null
  
  tags = merge(var.tags, {
    Name       = "Carbon Events Namespace"
    Component  = "EventHub"
    CostCenter = "SmartFactory"
  })
}

# Create Event Hub for carbon telemetry data
resource "azurerm_eventhub" "carbon_telemetry" {
  name                = "carbon-telemetry"
  namespace_name      = azurerm_eventhub_namespace.carbon_events.name
  resource_group_name = azurerm_resource_group.smart_factory.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention
  
  # Configure capture for long-term storage
  capture_description {
    enabled  = true
    encoding = "Avro"
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "carbon-data/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.carbon_archive.name
      storage_account_id  = azurerm_storage_account.factory_storage.id
    }
    
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
  }
  
  depends_on = [azurerm_storage_container.carbon_archive]
}

# Create authorization rule for Event Hub access
resource "azurerm_eventhub_authorization_rule" "carbon_data" {
  name                = "CarbonDataAccess"
  namespace_name      = azurerm_eventhub_namespace.carbon_events.name
  eventhub_name       = azurerm_eventhub.carbon_telemetry.name
  resource_group_name = azurerm_resource_group.smart_factory.name
  
  listen = true
  send   = true
  manage = false
}

# Create Event Grid Topic for event-driven architecture
resource "azurerm_eventgrid_topic" "carbon_monitoring" {
  name                = "evtgrid-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.smart_factory.location
  resource_group_name = azurerm_resource_group.smart_factory.name
  
  # Configure input schema and public network access
  input_schema                 = "EventGridSchema"
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = merge(var.tags, {
    Name       = "Carbon Monitoring Event Grid"
    Component  = "EventGrid"
    CostCenter = "SmartFactory"
  })
}

# Create Data Explorer (Kusto) cluster for advanced analytics
resource "azurerm_kusto_cluster" "carbon_analytics" {
  name                = "adx-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.smart_factory.location
  resource_group_name = azurerm_resource_group.smart_factory.name
  
  sku {
    name     = var.kusto_sku_name
    capacity = var.kusto_capacity
  }
  
  # Security and access configurations
  trusted_external_tenants                = [data.azurerm_client_config.current.tenant_id]
  optimized_auto_scale_enabled           = true
  disk_encryption_enabled                = true
  streaming_ingestion_enabled           = true
  purge_enabled                         = true
  
  # Configure optimized auto-scale
  optimized_auto_scale {
    minimum_instances = var.kusto_capacity
    maximum_instances = var.kusto_capacity * 2
  }
  
  tags = merge(var.tags, {
    Name       = "Carbon Analytics Cluster"
    Component  = "DataExplorer"
    CostCenter = "SmartFactory"
  })
}

# Create Data Explorer database for carbon monitoring data
resource "azurerm_kusto_database" "carbon_monitoring" {
  name                = "CarbonMonitoring"
  resource_group_name = azurerm_resource_group.smart_factory.name
  location            = azurerm_resource_group.smart_factory.location
  cluster_name        = azurerm_kusto_cluster.carbon_analytics.name
  
  hot_cache_period   = var.kusto_database_cache_period
  soft_delete_period = var.kusto_database_retention_period
  
  depends_on = [azurerm_kusto_cluster.carbon_analytics]
}

# Create Data Explorer Event Hub data connection
resource "azurerm_kusto_eventhub_data_connection" "carbon_ingestion" {
  name                = "carbon-ingestion"
  resource_group_name = azurerm_resource_group.smart_factory.name
  location            = azurerm_resource_group.smart_factory.location
  cluster_name        = azurerm_kusto_cluster.carbon_analytics.name
  database_name       = azurerm_kusto_database.carbon_monitoring.name
  
  eventhub_id    = azurerm_eventhub.carbon_telemetry.id
  consumer_group = azurerm_eventhub_consumer_group.kusto_ingestion.name
  
  # Configure data format and mapping
  table_name        = "CarbonTelemetry"
  mapping_rule_name = "CarbonTelemetryMapping"
  data_format       = "JSON"
  compression       = "None"
  
  depends_on = [
    azurerm_kusto_database.carbon_monitoring,
    azurerm_eventhub_consumer_group.kusto_ingestion
  ]
}

# Create Event Hub consumer group for Data Explorer
resource "azurerm_eventhub_consumer_group" "kusto_ingestion" {
  name                = "kusto-ingestion"
  namespace_name      = azurerm_eventhub_namespace.carbon_events.name
  eventhub_name       = azurerm_eventhub.carbon_telemetry.name
  resource_group_name = azurerm_resource_group.smart_factory.name
}

# Create Application Service Plan for Function App
resource "azurerm_service_plan" "carbon_functions" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.smart_factory.name
  location            = azurerm_resource_group.smart_factory.location
  os_type             = "Linux"
  sku_name           = var.function_app_sku_size
  
  tags = merge(var.tags, {
    Name       = "Carbon Functions Service Plan"
    Component  = "Compute"
    CostCenter = "SmartFactory"
  })
}

# Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "carbon_monitoring" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.smart_factory.location
  resource_group_name = azurerm_resource_group.smart_factory.name
  application_type    = "web"
  
  tags = merge(var.tags, {
    Name       = "Carbon Monitoring Insights"
    Component  = "Monitoring"
    CostCenter = "SmartFactory"
  })
}

# Create Function App for carbon calculation logic
resource "azurerm_linux_function_app" "carbon_calculator" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.smart_factory.name
  location            = azurerm_resource_group.smart_factory.location
  
  storage_account_name       = azurerm_storage_account.factory_storage.name
  storage_account_access_key = azurerm_storage_account.factory_storage.primary_access_key
  service_plan_id           = azurerm_service_plan.carbon_functions.id
  
  # Configure runtime and features
  site_config {
    always_on = var.function_app_sku_tier != "Dynamic"
    
    application_stack {
      python_version = "3.9"
    }
    
    # Enable CORS for web access
    cors {
      allowed_origins = ["*"]
    }
    
    # Security configurations
    ftps_state        = "Disabled"
    http2_enabled     = true
    minimum_tls_version = "1.2"
  }
  
  # Application settings for carbon calculations
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "WEBSITE_RUN_FROM_PACKAGE"      = "1"
    "CARBON_EMISSION_FACTOR"        = var.carbon_emission_factor
    "IOT_HUB_CONNECTION_STRING"     = azurerm_iothub.factory_iot_hub.event_hub_events_endpoint
    "EVENT_GRID_ENDPOINT"           = azurerm_eventgrid_topic.carbon_monitoring.endpoint
    "EVENT_GRID_ACCESS_KEY"         = azurerm_eventgrid_topic.carbon_monitoring.primary_access_key
    "DATA_EXPLORER_CLUSTER_URI"     = azurerm_kusto_cluster.carbon_analytics.uri
    "EVENTHUB_CONNECTION_STRING"    = azurerm_eventhub_authorization_rule.carbon_data.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_monitoring ? azurerm_application_insights.carbon_monitoring[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_monitoring ? azurerm_application_insights.carbon_monitoring[0].connection_string : ""
  }
  
  # Configure identity for managed service authentication
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Name       = "Carbon Calculator Function"
    Component  = "Functions"
    CostCenter = "SmartFactory"
  })
  
  depends_on = [
    azurerm_storage_account.factory_storage,
    azurerm_service_plan.carbon_functions
  ]
}

# Create storage containers for different data types
resource "azurerm_storage_container" "carbon_data" {
  name                  = "carbon-data"
  storage_account_name  = azurerm_storage_account.factory_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "carbon_archive" {
  name                  = "carbon-archive"
  storage_account_name  = azurerm_storage_account.factory_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "file_uploads" {
  name                  = "file-uploads"
  storage_account_name  = azurerm_storage_account.factory_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "sustainability_reports" {
  name                  = "sustainability-reports"
  storage_account_name  = azurerm_storage_account.factory_storage.name
  container_access_type = "private"
}

# Create Event Grid subscription for Function App trigger
resource "azurerm_eventgrid_event_subscription" "carbon_processing" {
  name  = "carbon-processing-subscription"
  scope = azurerm_iothub.factory_iot_hub.id
  
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.carbon_calculator.default_hostname}/api/ProcessCarbonData"
  }
  
  included_event_types = [
    "Microsoft.Devices.DeviceTelemetry"
  ]
  
  # Configure retry policy
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }
  
  # Configure dead letter storage
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.factory_storage.id
    storage_blob_container_name = azurerm_storage_container.carbon_data.name
  }
  
  depends_on = [azurerm_linux_function_app.carbon_calculator]
}

# Create sample IoT device for testing
resource "azurerm_iothub_device" "factory_sensor" {
  name                = "factory-sensor-001"
  iothub_name         = azurerm_iothub.factory_iot_hub.name
  resource_group_name = azurerm_resource_group.smart_factory.name
  
  authentication {
    type = "sas"
  }
  
  tags = merge(var.tags, {
    Name       = "Factory Test Sensor"
    Component  = "IoT"
    DeviceType = "EnergyMeter"
  })
}

# Role assignments for Function App managed identity
resource "azurerm_role_assignment" "function_eventhub_reader" {
  scope                = azurerm_eventhub_namespace.carbon_events.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_linux_function_app.carbon_calculator.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_eventgrid_contributor" {
  scope                = azurerm_eventgrid_topic.carbon_monitoring.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.carbon_calculator.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_kusto_admin" {
  scope                = azurerm_kusto_cluster.carbon_analytics.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.carbon_calculator.identity[0].principal_id
}

# Recovery Services Vault for backup (if enabled)
resource "azurerm_recovery_services_vault" "factory_backup" {
  count               = var.enable_backup ? 1 : 0
  name                = "rsv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.smart_factory.location
  resource_group_name = azurerm_resource_group.smart_factory.name
  sku                 = "Standard"
  
  soft_delete_enabled = true
  
  tags = merge(var.tags, {
    Name       = "Factory Backup Vault"
    Component  = "Backup"
    CostCenter = "SmartFactory"
  })
}
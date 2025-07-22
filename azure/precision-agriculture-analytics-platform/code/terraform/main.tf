# Main Terraform configuration for Azure precision agriculture analytics platform
# This configuration deploys a comprehensive precision agriculture solution using
# Azure Data Manager for Agriculture, IoT Hub, AI Services, Maps, and Stream Analytics

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Use provided suffix or generated one
locals {
  suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_string.suffix.result
  
  # Combine common tags with additional tags
  common_tags = merge(var.common_tags, var.additional_tags, {
    "deployment-time" = timestamp()
  })
  
  # Resource naming conventions
  resource_group_name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${local.suffix}"
  adma_name              = "adma-${var.project_name}-${local.suffix}"
  iot_hub_name           = "iothub-${var.project_name}-${local.suffix}"
  storage_account_name   = "st${replace(var.project_name, "-", "")}${local.suffix}"
  ai_services_name       = "ai-${var.project_name}-${local.suffix}"
  maps_account_name      = "maps-${var.project_name}-${local.suffix}"
  stream_analytics_name  = "stream-${var.project_name}-${local.suffix}"
  function_app_name      = "func-${var.project_name}-${local.suffix}"
  app_service_plan_name  = "asp-${var.project_name}-${local.suffix}"
  log_analytics_name     = "log-${var.project_name}-${local.suffix}"
}

# Create the main resource group for all precision agriculture resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location

  tags = merge(local.common_tags, {
    "resource-type" = "resource-group"
    "description"   = "Resource group for precision agriculture analytics platform"
  })
}

# Create Log Analytics workspace for monitoring and diagnostics (if enabled)
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = "PerGB2018"
  retention_in_days   = var.log_analytics_workspace_retention_days

  tags = merge(local.common_tags, {
    "resource-type" = "log-analytics-workspace"
    "purpose"       = "monitoring-diagnostics"
  })
}

# Create storage account for agricultural imagery and data
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier            = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind            = "StorageV2"
  access_tier             = var.storage_access_tier

  # Enable blob versioning and change feed for data lineage
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure retention policies for agricultural data
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }

  # Configure network access rules for security
  network_rules {
    default_action = "Allow"  # Set to "Deny" for production with specific IP allowlists
    bypass         = ["AzureServices"]
  }

  tags = merge(local.common_tags, {
    "resource-type" = "storage-account"
    "data-type"     = "agricultural-data"
    "purpose"       = "imagery-sensor-data-storage"
  })
}

# Create storage containers for different types of agricultural data
resource "azurerm_storage_container" "agricultural_data" {
  count                = length(var.storage_containers)
  name                 = var.storage_containers[count.index]
  storage_account_name = azurerm_storage_account.main.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.main]
}

# Enable Advanced Threat Protection for storage account (if enabled)
resource "azurerm_advanced_threat_protection" "storage" {
  count              = var.enable_advanced_threat_protection ? 1 : 0
  target_resource_id = azurerm_storage_account.main.id
  enabled           = true
}

# Create Azure Data Manager for Agriculture instance
# Note: This resource type may need to be updated based on the actual Terraform provider support
resource "azurerm_template_deployment" "adma" {
  name                = "adma-deployment"
  resource_group_name = azurerm_resource_group.main.name
  deployment_mode     = "Incremental"
  
  # ARM template for Azure Data Manager for Agriculture
  # This uses ARM template deployment until native Terraform support is available
  template_body = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      admaName = {
        type = "string"
        defaultValue = local.adma_name
      }
      location = {
        type = "string"
        defaultValue = var.location
      }
      sku = {
        type = "string"
        defaultValue = var.adma_sku
      }
    }
    resources = [
      {
        type = "Microsoft.AgFoodPlatform/farmBeats"
        apiVersion = "2021-09-01-preview"
        name = "[parameters('admaName')]"
        location = "[parameters('location')]"
        properties = {
          publicNetworkAccess = "Enabled"
        }
        tags = merge(local.common_tags, {
          "resource-type" = "data-manager-agriculture"
          "farm-type"     = var.farm_metadata.farming_method
          "season"        = var.farm_metadata.season
        })
      }
    ]
    outputs = {
      admaEndpoint = {
        type = "string"
        value = "[reference(parameters('admaName')).instanceUri]"
      }
    }
  })

  parameters = {
    admaName = local.adma_name
    location = var.location
    sku      = var.adma_sku
  }
}

# Create IoT Hub for sensor data ingestion
resource "azurerm_iothub" "main" {
  name                = local.iot_hub_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location

  sku {
    name     = var.iot_hub_sku.name
    capacity = var.iot_hub_sku.capacity
  }

  # Configure event hub endpoints
  event_hub_partition_count   = var.iot_hub_partition_count
  event_hub_retention_in_days = var.iot_hub_retention_days

  # Configure routing to storage for raw data archival
  route {
    name           = "storage-route"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["storage-endpoint"]
    enabled        = true
  }

  # Configure storage endpoint for message routing
  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.main.primary_blob_connection_string
    name                       = "storage-endpoint"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes   = 10485760
    container_name            = azurerm_storage_container.agricultural_data[index(var.storage_containers, "analytics-results")].name
    encoding                  = "JSON"
    file_name_format          = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"
  }

  tags = merge(local.common_tags, {
    "resource-type" = "iot-hub"
    "purpose"       = "farm-sensors"
    "data-type"     = "telemetry"
  })

  depends_on = [azurerm_storage_container.agricultural_data]
}

# Create sample IoT device for demonstration
resource "azurerm_iothub_device" "sample_sensor" {
  name                = var.iot_device_id
  iothub_name        = azurerm_iothub.main.name
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.common_tags, {
    "device-type" = "soil-sensor"
    "field-id"    = "field-01"
    "location"    = "north-field"
  })
}

# Create Azure AI Services (Cognitive Services) for computer vision
resource "azurerm_cognitive_account" "main" {
  name                = local.ai_services_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind               = var.ai_services_kind
  sku_name           = var.ai_services_sku

  # Enable custom subdomain for consistent endpoint URLs
  custom_question_answering_search_service_id = null
  
  # Configure network access
  network_acls {
    default_action = "Allow"  # Set to "Deny" for production with specific IP allowlists
  }

  tags = merge(local.common_tags, {
    "resource-type" = "cognitive-services"
    "purpose"       = "crop-analysis"
    "service"       = "computer-vision"
  })
}

# Create Azure Maps account for geospatial visualization
resource "azurerm_maps_account" "main" {
  name                = local.maps_account_name
  resource_group_name = azurerm_resource_group.main.name
  sku_name           = var.maps_sku

  tags = merge(local.common_tags, {
    "resource-type" = "maps-account"
    "purpose"       = "field-mapping"
    "service"       = "geospatial"
  })
}

# Create App Service Plan for Azure Functions
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  os_type            = "Linux"
  sku_name           = var.function_app_service_plan_sku

  tags = merge(local.common_tags, {
    "resource-type" = "app-service-plan"
    "purpose"       = "serverless-functions"
  })
}

# Create Azure Function App for automated image processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Configure CORS for web applications
    cors {
      allowed_origins = ["*"]  # Restrict in production
    }
  }

  # Configure application settings for AI Services integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "AI_SERVICES_ENDPOINT"         = azurerm_cognitive_account.main.endpoint
    "AI_SERVICES_KEY"              = azurerm_cognitive_account.main.primary_access_key
    "STORAGE_CONNECTION_STRING"    = azurerm_storage_account.main.primary_connection_string
    "ADMA_ENDPOINT"                = azurerm_template_deployment.adma.outputs["admaEndpoint"]
    "IOT_HUB_CONNECTION_STRING"    = azurerm_iothub.main.shared_access_policy[0].connection_string
    "MAPS_SUBSCRIPTION_KEY"        = azurerm_maps_account.main.primary_access_key
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_diagnostic_settings ? azurerm_application_insights.main[0].instrumentation_key : ""
  }

  tags = merge(local.common_tags, {
    "resource-type" = "function-app"
    "purpose"       = "image-analysis"
    "automation"    = "crop-health"
  })

  depends_on = [
    azurerm_storage_account.main,
    azurerm_cognitive_account.main,
    azurerm_template_deployment.adma,
    azurerm_maps_account.main
  ]
}

# Create Application Insights for monitoring (if diagnostic settings enabled)
resource "azurerm_application_insights" "main" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = "appi-${var.project_name}-${local.suffix}"
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id       = azurerm_log_analytics_workspace.main[0].id
  application_type   = "web"

  tags = merge(local.common_tags, {
    "resource-type" = "application-insights"
    "purpose"       = "function-monitoring"
  })
}

# Create Stream Analytics job for real-time data processing
resource "azurerm_stream_analytics_job" "main" {
  name                                     = local.stream_analytics_name
  resource_group_name                      = azurerm_resource_group.main.name
  location                                = azurerm_resource_group.main.location
  compatibility_level                      = "1.2"
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = var.stream_analytics_late_arrival_max_delay
  events_out_of_order_max_delay_in_seconds = var.stream_analytics_out_of_order_max_delay
  events_out_of_order_policy              = var.stream_analytics_events_policy
  output_error_policy                     = "Stop"
  streaming_units                         = var.stream_analytics_streaming_units

  tags = merge(local.common_tags, {
    "resource-type" = "stream-analytics-job"
    "purpose"       = "real-time-processing"
    "data-type"     = "sensor-telemetry"
  })

  depends_on = [azurerm_iothub.main]
}

# Configure IoT Hub as input for Stream Analytics
resource "azurerm_stream_analytics_stream_input_iothub" "main" {
  name                         = "SensorInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.main.name
  resource_group_name          = azurerm_resource_group.main.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  iothub_namespace             = azurerm_iothub.main.name
  shared_access_policy_key     = azurerm_iothub.main.shared_access_policy[0].primary_key
  shared_access_policy_name    = azurerm_iothub.main.shared_access_policy[0].name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Configure Blob storage as output for Stream Analytics
resource "azurerm_stream_analytics_output_blob" "main" {
  name                      = "ProcessedSensorData"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name       = azurerm_resource_group.main.name
  storage_account_name      = azurerm_storage_account.main.name
  storage_account_key       = azurerm_storage_account.main.primary_access_key
  storage_container_name    = azurerm_storage_container.agricultural_data[index(var.storage_containers, "analytics-results")].name
  path_pattern             = "processed/{date}/{time}"
  date_format              = "yyyy/MM/dd"
  time_format              = "HH"

  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# Create budget and cost alert (if enabled)
resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.enable_cost_alerts ? 1 : 0
  
  name              = "budget-${var.project_name}-${local.suffix}"
  resource_group_id = azurerm_resource_group.main.id

  amount     = var.monthly_budget_limit
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01T00:00:00Z", timestamp())
    end_date   = formatdate("YYYY-MM-01T00:00:00Z", timeadd(timestamp(), "8760h")) # 1 year from now
  }

  notification {
    enabled   = true
    threshold = 80
    operator  = "GreaterThan"
    contact_emails = [
      "admin@example.com"  # Update with actual email addresses
    ]
  }

  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"
    contact_emails = [
      "admin@example.com"  # Update with actual email addresses
    ]
  }
}

# Configure diagnostic settings for key resources (if enabled)
resource "azurerm_monitor_diagnostic_setting" "iot_hub" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "iot-hub-diagnostics"
  target_resource_id         = azurerm_iothub.main.id
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

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Capacity"
    enabled  = true
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "stream_analytics" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "stream-analytics-diagnostics"
  target_resource_id         = azurerm_stream_analytics_job.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "Execution"
  }

  enabled_log {
    category = "Authoring"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
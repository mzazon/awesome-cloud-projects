# Main Terraform configuration for Azure Energy Grid Analytics
# This configuration deploys a comprehensive energy grid analytics platform
# using Azure Data Manager for Energy, Digital Twins, and AI Services

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Get current subscription information
data "azurerm_subscription" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "energy_analytics" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for comprehensive monitoring
resource "azurerm_log_analytics_workspace" "energy_analytics" {
  name                = "law-energy-${random_string.suffix.result}"
  location            = azurerm_resource_group.energy_analytics.location
  resource_group_name = azurerm_resource_group.energy_analytics.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    purpose = "monitoring"
  })
}

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "energy_analytics" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appi-energy-${random_string.suffix.result}"
  location            = azurerm_resource_group.energy_analytics.location
  resource_group_name = azurerm_resource_group.energy_analytics.name
  workspace_id        = azurerm_log_analytics_workspace.energy_analytics.id
  application_type    = "web"
  
  tags = merge(var.tags, {
    purpose = "application-monitoring"
  })
}

# Create Storage Account for data storage and Function App
resource "azurerm_storage_account" "energy_analytics" {
  name                     = "stenergy${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.energy_analytics.name
  location                 = azurerm_resource_group.energy_analytics.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable advanced security features
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for optimization
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }
  
  tags = merge(var.tags, {
    purpose = "data-storage"
  })
}

# Create storage containers for different data types
resource "azurerm_storage_container" "analytics_config" {
  name                  = "analytics-config"
  storage_account_name  = azurerm_storage_account.energy_analytics.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "dtdl_models" {
  name                  = "dtdl-models"
  storage_account_name  = azurerm_storage_account.energy_analytics.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "ml_artifacts" {
  name                  = "ml-artifacts"
  storage_account_name  = azurerm_storage_account.energy_analytics.name
  container_access_type = "private"
}

# Create IoT Hub for device data ingestion
resource "azurerm_iothub" "energy_analytics" {
  name                = "iot-energy-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  location            = azurerm_resource_group.energy_analytics.location
  
  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_capacity
  }
  
  # Configure message routing and endpoints
  endpoint {
    type              = "AzureIotHub.StorageContainer"
    connection_string = azurerm_storage_account.energy_analytics.primary_blob_connection_string
    name              = "storage-endpoint"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = "iot-data"
    encoding                   = "Avro"
    file_name_format          = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"
  }
  
  route {
    name           = "storage-route"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["storage-endpoint"]
    enabled        = true
  }
  
  tags = merge(var.tags, {
    purpose = "iot-data-ingestion"
  })
}

# Create additional storage container for IoT data
resource "azurerm_storage_container" "iot_data" {
  name                  = "iot-data"
  storage_account_name  = azurerm_storage_account.energy_analytics.name
  container_access_type = "private"
}

# Create Time Series Insights Environment
resource "azurerm_iot_time_series_insights_gen2_environment" "energy_analytics" {
  name                = "tsi-energy-${random_string.suffix.result}"
  location            = azurerm_resource_group.energy_analytics.location
  resource_group_name = azurerm_resource_group.energy_analytics.name
  sku_name            = var.time_series_insights_sku
  id_properties       = ["deviceId"]
  
  storage {
    name = azurerm_storage_account.energy_analytics.name
    key  = azurerm_storage_account.energy_analytics.primary_access_key
  }
  
  warm_store_data_retention_time = "P${var.time_series_data_retention_days}D"
  
  tags = merge(var.tags, {
    purpose = "time-series-analytics"
  })
}

# Create Time Series Insights Event Source
resource "azurerm_iot_time_series_insights_event_source_iothub" "energy_analytics" {
  name                     = "grid-data-source"
  location                 = azurerm_resource_group.energy_analytics.location
  resource_group_name      = azurerm_resource_group.energy_analytics.name
  environment_id           = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.id
  iothub_name              = azurerm_iothub.energy_analytics.name
  shared_access_key_name   = "iothubowner"
  shared_access_key        = azurerm_iothub.energy_analytics.shared_access_policy[0].primary_key
  consumer_group_name      = "$Default"
  timestamp_property_name  = "timestamp"
  
  tags = merge(var.tags, {
    purpose = "time-series-data-source"
  })
}

# Create Digital Twins Instance
resource "azurerm_digital_twins_instance" "energy_analytics" {
  name                = var.digital_twins_instance_name != "" ? var.digital_twins_instance_name : "adt-grid-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  location            = azurerm_resource_group.energy_analytics.location
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    purpose = "digital-twins"
  })
}

# Create role assignment for Digital Twins access
resource "azurerm_role_assignment" "digital_twins_data_owner" {
  scope                = azurerm_digital_twins_instance.energy_analytics.id
  role_definition_name = "Azure Digital Twins Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Create Cognitive Services Account for AI capabilities
resource "azurerm_cognitive_account" "energy_analytics" {
  name                = "ai-energy-${random_string.suffix.result}"
  location            = azurerm_resource_group.energy_analytics.location
  resource_group_name = azurerm_resource_group.energy_analytics.name
  kind                = "CognitiveServices"
  sku_name            = var.cognitive_services_sku
  
  # Configure network access rules if IP ranges are specified
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = merge(var.tags, {
    purpose = "ai-analytics"
  })
}

# Create Event Grid Topic for real-time alerting
resource "azurerm_eventgrid_topic" "energy_analytics" {
  name                = "egt-energy-alerts-${random_string.suffix.result}"
  location            = azurerm_resource_group.energy_analytics.location
  resource_group_name = azurerm_resource_group.energy_analytics.name
  
  tags = merge(var.tags, {
    purpose = "event-alerting"
  })
}

# Create Service Plan for Function App
resource "azurerm_service_plan" "energy_analytics" {
  name                = "asp-energy-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  location            = azurerm_resource_group.energy_analytics.location
  os_type             = var.function_app_os_type
  sku_name            = "Y1"  # Consumption plan
  
  tags = merge(var.tags, {
    purpose = "function-hosting"
  })
}

# Create Function App for data integration
resource "azurerm_linux_function_app" "energy_analytics" {
  count = var.function_app_os_type == "linux" ? 1 : 0
  
  name                = "func-energy-integration-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  location            = azurerm_resource_group.energy_analytics.location
  service_plan_id     = azurerm_service_plan.energy_analytics.id
  
  storage_account_name       = azurerm_storage_account.energy_analytics.name
  storage_account_access_key = azurerm_storage_account.energy_analytics.primary_access_key
  
  site_config {
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      python_version = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
    }
    
    # Enable Application Insights if configured
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].connection_string : null
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].instrumentation_key : null
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"          = var.function_app_runtime
    "DIGITAL_TWINS_ENDPOINT"           = "https://${azurerm_digital_twins_instance.energy_analytics.host_name}"
    "COGNITIVE_SERVICES_ENDPOINT"      = azurerm_cognitive_account.energy_analytics.endpoint
    "COGNITIVE_SERVICES_KEY"           = azurerm_cognitive_account.energy_analytics.primary_access_key
    "STORAGE_CONNECTION_STRING"        = azurerm_storage_account.energy_analytics.primary_connection_string
    "EVENTGRID_TOPIC_ENDPOINT"         = azurerm_eventgrid_topic.energy_analytics.endpoint
    "EVENTGRID_TOPIC_KEY"              = azurerm_eventgrid_topic.energy_analytics.primary_access_key
    "IOT_HUB_CONNECTION_STRING"        = azurerm_iothub.energy_analytics.shared_access_policy[0].connection_string
    "TIME_SERIES_INSIGHTS_ENVIRONMENT" = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.name
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    purpose = "data-integration"
  })
}

# Create Windows Function App if specified
resource "azurerm_windows_function_app" "energy_analytics" {
  count = var.function_app_os_type == "windows" ? 1 : 0
  
  name                = "func-energy-integration-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  location            = azurerm_resource_group.energy_analytics.location
  service_plan_id     = azurerm_service_plan.energy_analytics.id
  
  storage_account_name       = azurerm_storage_account.energy_analytics.name
  storage_account_access_key = azurerm_storage_account.energy_analytics.primary_access_key
  
  site_config {
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      python_version = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
      dotnet_version = var.function_app_runtime == "dotnet" ? var.function_app_runtime_version : null
      java_version = var.function_app_runtime == "java" ? var.function_app_runtime_version : null
    }
    
    # Enable Application Insights if configured
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].connection_string : null
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].instrumentation_key : null
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"          = var.function_app_runtime
    "DIGITAL_TWINS_ENDPOINT"           = "https://${azurerm_digital_twins_instance.energy_analytics.host_name}"
    "COGNITIVE_SERVICES_ENDPOINT"      = azurerm_cognitive_account.energy_analytics.endpoint
    "COGNITIVE_SERVICES_KEY"           = azurerm_cognitive_account.energy_analytics.primary_access_key
    "STORAGE_CONNECTION_STRING"        = azurerm_storage_account.energy_analytics.primary_connection_string
    "EVENTGRID_TOPIC_ENDPOINT"         = azurerm_eventgrid_topic.energy_analytics.endpoint
    "EVENTGRID_TOPIC_KEY"              = azurerm_eventgrid_topic.energy_analytics.primary_access_key
    "IOT_HUB_CONNECTION_STRING"        = azurerm_iothub.energy_analytics.shared_access_policy[0].connection_string
    "TIME_SERIES_INSIGHTS_ENVIRONMENT" = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.name
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    purpose = "data-integration"
  })
}

# Create role assignment for Function App to access Digital Twins
resource "azurerm_role_assignment" "function_app_digital_twins" {
  scope                = azurerm_digital_twins_instance.energy_analytics.id
  role_definition_name = "Azure Digital Twins Data Contributor"
  principal_id         = var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].identity[0].principal_id : azurerm_windows_function_app.energy_analytics[0].identity[0].principal_id
}

# Create Azure Data Manager for Energy (requires AzAPI provider due to preview status)
resource "azapi_resource" "energy_data_manager" {
  type      = "Microsoft.EnergyDataServices/dataManagers@2023-11-01-preview"
  name      = "adm-energy-${random_string.suffix.result}"
  location  = azurerm_resource_group.energy_analytics.location
  parent_id = azurerm_resource_group.energy_analytics.id
  
  body = jsonencode({
    properties = {
      dataPartitionCount = var.energy_data_manager_partition_count
      sku = {
        name = var.energy_data_manager_sku
      }
    }
  })
  
  tags = merge(var.tags, {
    purpose = "energy-data-management"
  })
}

# Upload sample analytics configuration to storage
resource "azurerm_storage_blob" "analytics_config" {
  name                   = "analytics-config.json"
  storage_account_name   = azurerm_storage_account.energy_analytics.name
  storage_container_name = azurerm_storage_container.analytics_config.name
  type                   = "Block"
  
  source_content = jsonencode({
    predictionModels = {
      demandForecast = {
        type             = "time-series-regression"
        inputFeatures    = ["historical_consumption", "weather_data", "day_of_week"]
        predictionHorizon = "24h"
        updateFrequency  = "1h"
      }
      renewableGeneration = {
        type             = "weather-correlation"
        inputFeatures    = ["solar_irradiance", "wind_speed", "cloud_cover"]
        predictionHorizon = "6h"
        updateFrequency  = "15m"
      }
    }
    anomalyDetection = {
      gridStability = {
        metrics   = ["voltage", "frequency", "power_factor"]
        threshold = "3_sigma"
        alerting  = true
      }
      equipmentHealth = {
        metrics              = ["temperature", "vibration", "efficiency"]
        threshold           = "statistical"
        predictiveMaintenance = true
      }
    }
  })
  
  depends_on = [azurerm_storage_container.analytics_config]
}

# Upload sample DTDL models to storage
resource "azurerm_storage_blob" "power_generator_model" {
  count = var.create_sample_dtdl_models ? 1 : 0
  
  name                   = "PowerGenerator.json"
  storage_account_name   = azurerm_storage_account.energy_analytics.name
  storage_container_name = azurerm_storage_container.dtdl_models.name
  type                   = "Block"
  
  source_content = jsonencode({
    "@context" = "dtmi:dtdl:context;3"
    "@id"      = "dtmi:energygrid:PowerGenerator;1"
    "@type"    = "Interface"
    displayName = "Power Generator"
    description = "Digital twin model for power generation facilities"
    contents = [
      {
        "@type"     = "Property"
        name        = "generatorType"
        schema      = "string"
        description = "Type of power generator (solar, wind, hydro, nuclear, gas)"
      },
      {
        "@type"     = "Telemetry"
        name        = "currentOutput"
        schema      = "double"
        description = "Current power output in MW"
      },
      {
        "@type"     = "Telemetry"
        name        = "capacity"
        schema      = "double"
        description = "Maximum generation capacity in MW"
      },
      {
        "@type"     = "Telemetry"
        name        = "efficiency"
        schema      = "double"
        description = "Current operational efficiency percentage"
      },
      {
        "@type" = "Property"
        name    = "location"
        schema = {
          "@type" = "Object"
          fields = [
            { name = "latitude", schema = "double" },
            { name = "longitude", schema = "double" }
          ]
        }
      }
    ]
  })
  
  depends_on = [azurerm_storage_container.dtdl_models]
}

resource "azurerm_storage_blob" "grid_node_model" {
  count = var.create_sample_dtdl_models ? 1 : 0
  
  name                   = "GridNode.json"
  storage_account_name   = azurerm_storage_account.energy_analytics.name
  storage_container_name = azurerm_storage_container.dtdl_models.name
  type                   = "Block"
  
  source_content = jsonencode({
    "@context" = "dtmi:dtdl:context;3"
    "@id"      = "dtmi:energygrid:GridNode;1"
    "@type"    = "Interface"
    displayName = "Grid Node"
    description = "Digital twin model for grid distribution nodes"
    contents = [
      {
        "@type"     = "Telemetry"
        name        = "voltage"
        schema      = "double"
        description = "Current voltage level in kV"
      },
      {
        "@type"     = "Telemetry"
        name        = "frequency"
        schema      = "double"
        description = "Grid frequency in Hz"
      },
      {
        "@type"     = "Telemetry"
        name        = "powerFlow"
        schema      = "double"
        description = "Power flow through node in MW"
      },
      {
        "@type"     = "Property"
        name        = "nodeType"
        schema      = "string"
        description = "Type of grid node (transmission, distribution, substation)"
      },
      {
        "@type"     = "Relationship"
        name        = "connectedTo"
        target      = "dtmi:energygrid:GridNode;1"
        description = "Connected grid nodes"
      }
    ]
  })
  
  depends_on = [azurerm_storage_container.dtdl_models]
}

# Upload dashboard configuration to storage
resource "azurerm_storage_blob" "dashboard_config" {
  name                   = "dashboard-config.json"
  storage_account_name   = azurerm_storage_account.energy_analytics.name
  storage_container_name = azurerm_storage_container.analytics_config.name
  type                   = "Block"
  
  source_content = jsonencode({
    dashboards = {
      gridOverview = {
        widgets = [
          "real_time_generation",
          "current_demand",
          "renewable_percentage",
          "grid_stability_metrics"
        ]
      }
      predictiveAnalytics = {
        widgets = [
          "demand_forecast_24h",
          "renewable_generation_forecast",
          "optimization_recommendations",
          "cost_savings_tracker"
        ]
      }
      operationalHealth = {
        widgets = [
          "equipment_status",
          "maintenance_alerts",
          "performance_trends",
          "carbon_footprint_tracking"
        ]
      }
    }
  })
  
  depends_on = [azurerm_storage_container.analytics_config]
}

# Configure diagnostic settings for Digital Twins if enabled
resource "azurerm_monitor_diagnostic_setting" "digital_twins" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name               = "dt-diagnostics"
  target_resource_id = azurerm_digital_twins_instance.energy_analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.energy_analytics.id
  
  enabled_log {
    category = "DigitalTwinsOperation"
  }
  
  enabled_log {
    category = "EventRoutesOperation"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for IoT Hub if enabled
resource "azurerm_monitor_diagnostic_setting" "iot_hub" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name               = "iot-diagnostics"
  target_resource_id = azurerm_iothub.energy_analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.energy_analytics.id
  
  enabled_log {
    category = "Connections"
  }
  
  enabled_log {
    category = "DeviceTelemetry"
  }
  
  enabled_log {
    category = "C2DCommands"
  }
  
  enabled_log {
    category = "DeviceIdentityOperations"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Cognitive Services if enabled
resource "azurerm_monitor_diagnostic_setting" "cognitive_services" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name               = "ai-diagnostics"
  target_resource_id = azurerm_cognitive_account.energy_analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.energy_analytics.id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Key Vault for secret management
resource "azurerm_key_vault" "energy_analytics" {
  name                = "kv-energy-${random_string.suffix.result}"
  location            = azurerm_resource_group.energy_analytics.location
  resource_group_name = azurerm_resource_group.energy_analytics.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
    ]
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
  }
  
  # Grant access to Function App
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].identity[0].principal_id : azurerm_windows_function_app.energy_analytics[0].identity[0].principal_id
    
    secret_permissions = [
      "Get", "List"
    ]
  }
  
  tags = merge(var.tags, {
    purpose = "secret-management"
  })
}

# Store important connection strings and keys in Key Vault
resource "azurerm_key_vault_secret" "iot_hub_connection_string" {
  name         = "iot-hub-connection-string"
  value        = azurerm_iothub.energy_analytics.shared_access_policy[0].connection_string
  key_vault_id = azurerm_key_vault.energy_analytics.id
  
  depends_on = [azurerm_key_vault.energy_analytics]
}

resource "azurerm_key_vault_secret" "cognitive_services_key" {
  name         = "cognitive-services-key"
  value        = azurerm_cognitive_account.energy_analytics.primary_access_key
  key_vault_id = azurerm_key_vault.energy_analytics.id
  
  depends_on = [azurerm_key_vault.energy_analytics]
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.energy_analytics.primary_connection_string
  key_vault_id = azurerm_key_vault.energy_analytics.id
  
  depends_on = [azurerm_key_vault.energy_analytics]
}

resource "azurerm_key_vault_secret" "eventgrid_access_key" {
  name         = "eventgrid-access-key"
  value        = azurerm_eventgrid_topic.energy_analytics.primary_access_key
  key_vault_id = azurerm_key_vault.energy_analytics.id
  
  depends_on = [azurerm_key_vault.energy_analytics]
}

# Create monitoring alerts for critical metrics
resource "azurerm_monitor_metric_alert" "digital_twins_api_errors" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = "digital-twins-api-errors"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  scopes              = [azurerm_digital_twins_instance.energy_analytics.id]
  description         = "Alert when Digital Twins API errors exceed threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.DigitalTwins/digitalTwinsInstances"
    metric_name      = "ApiRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    
    dimension {
      name     = "ResultType"
      operator = "Include"
      values   = ["ClientError", "ServerError"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.energy_analytics[0].id
  }
  
  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "iot_hub_throttling" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = "iot-hub-throttling"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  scopes              = [azurerm_iothub.energy_analytics.id]
  description         = "Alert when IoT Hub throttling occurs"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "ThrottledRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.energy_analytics[0].id
  }
  
  tags = var.tags
}

# Create action group for alert notifications
resource "azurerm_monitor_action_group" "energy_analytics" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = "ag-energy-alerts"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  short_name          = "energyalert"
  
  tags = merge(var.tags, {
    purpose = "alerting"
  })
}

# Create scheduled query rule for custom log analytics
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "energy_anomaly_detection" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = "energy-anomaly-detection"
  resource_group_name = azurerm_resource_group.energy_analytics.name
  location            = azurerm_resource_group.energy_analytics.location
  
  evaluation_frequency = "PT15M"
  window_duration      = "PT30M"
  scopes               = [azurerm_log_analytics_workspace.energy_analytics.id]
  severity             = 2
  
  criteria {
    query = <<-QUERY
      let threshold = 3.0;
      DigitalTwinsOperation
      | where TimeGenerated > ago(30m)
      | where OperationName contains "telemetry"
      | extend TelemetryValue = toreal(Properties.telemetryValue)
      | summarize avg(TelemetryValue), stdev(TelemetryValue) by bin(TimeGenerated, 5m)
      | where stdev_TelemetryValue > threshold
    QUERY
    
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.energy_analytics[0].id]
  }
  
  tags = var.tags
}

# Add a time delay to allow for proper resource provisioning
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_digital_twins_instance.energy_analytics,
    azurerm_cognitive_account.energy_analytics,
    azurerm_storage_account.energy_analytics
  ]
  
  create_duration = "60s"
}
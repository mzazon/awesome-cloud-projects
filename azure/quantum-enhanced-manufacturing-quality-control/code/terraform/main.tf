# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create resource group for quantum manufacturing infrastructure
resource "azurerm_resource_group" "quantum_manufacturing" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.common_tags, {
    Component = "resource-group"
  })
}

# Create storage account for data lake and ML workspace
resource "azurerm_storage_account" "quantum_storage" {
  name                     = "${var.storage_account_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.quantum_manufacturing.name
  location                 = azurerm_resource_group.quantum_manufacturing.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Enable hierarchical namespace for data lake
  access_tier              = "Hot"

  blob_properties {
    versioning_enabled = true
  }

  tags = merge(var.common_tags, {
    Component = "storage"
  })
}

# Create storage containers for different data types
resource "azurerm_storage_container" "ml_inference" {
  name                  = "ml-inference"
  storage_account_name  = azurerm_storage_account.quantum_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "quality_data" {
  name                  = "quality-data"
  storage_account_name  = azurerm_storage_account.quantum_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "quantum_results" {
  name                  = "quantum-results"
  storage_account_name  = azurerm_storage_account.quantum_storage.name
  container_access_type = "private"
}

# Create Key Vault for secrets management
resource "azurerm_key_vault" "quantum_kv" {
  name                = "${var.key_vault_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "Set",
      "Delete",
      "List",
      "Recover",
      "Backup",
      "Restore",
      "Purge"
    ]
  }

  tags = merge(var.common_tags, {
    Component = "key-vault"
  })
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "quantum_insights" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-quantum-${random_string.suffix.result}"
  location            = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  application_type    = "web"

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create Azure Machine Learning workspace
resource "azurerm_machine_learning_workspace" "quantum_ml" {
  name                    = "${var.ml_workspace_name}-${random_string.suffix.result}"
  location                = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name     = azurerm_resource_group.quantum_manufacturing.name
  storage_account_id      = azurerm_storage_account.quantum_storage.id
  key_vault_id           = azurerm_key_vault.quantum_kv.id
  application_insights_id = var.enable_application_insights ? azurerm_application_insights.quantum_insights[0].id : null

  identity {
    type = "SystemAssigned"
  }

  description          = "Quantum-enhanced manufacturing quality control workspace"
  friendly_name        = "Quantum Manufacturing ML Workspace"
  public_network_access_enabled = true

  tags = merge(var.common_tags, {
    Component = "machine-learning"
  })
}

# Create ML compute cluster for training workloads
resource "azurerm_machine_learning_compute_cluster" "quantum_cluster" {
  name                          = var.ml_compute_cluster_name
  location                      = azurerm_resource_group.quantum_manufacturing.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.quantum_ml.id
  vm_priority                   = "Dedicated"
  vm_size                       = var.ml_compute_instance_size

  scale_settings {
    min_node_count                       = 0
    max_node_count                      = var.ml_compute_max_instances
    scale_down_nodes_after_idle_duration = "PT5M" # 5 minutes
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.common_tags, {
    Component = "ml-compute"
  })
}

# Create ML compute instance for development
resource "azurerm_machine_learning_compute_instance" "quantum_dev" {
  name                          = "quantum-dev-instance-${random_string.suffix.result}"
  location                      = azurerm_resource_group.quantum_manufacturing.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.quantum_ml.id
  virtual_machine_size          = var.ml_compute_instance_size

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.common_tags, {
    Component = "ml-development"
  })
}

# Create Azure Quantum workspace
resource "azurerm_quantum_workspace" "manufacturing_quantum" {
  count               = var.enable_quantum_workspace ? 1 : 0
  name                = "${var.quantum_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  storage_account     = azurerm_storage_account.quantum_storage.name

  tags = merge(var.common_tags, {
    Component = "quantum-computing"
  })
}

# Create IoT Hub for manufacturing sensor data
resource "azurerm_iothub" "manufacturing_iot" {
  name                = "${var.iot_hub_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  location            = azurerm_resource_group.quantum_manufacturing.location

  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_capacity
  }

  endpoint {
    type                       = "AzureIotHub.EventHub"
    connection_string          = azurerm_eventhub_authorization_rule.iot_hub_listen.primary_connection_string
    name                       = "quality-control-endpoint"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.ml_inference.name
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }

  route {
    name           = "QualityControlRoute"
    source         = "DeviceMessages"
    condition      = "messageType = 'qualityControl'"
    endpoint_names = ["quality-control-endpoint"]
    enabled        = true
  }

  tags = merge(var.common_tags, {
    Component = "iot-hub"
  })
}

# Create Event Hub for IoT Hub routing
resource "azurerm_eventhub_namespace" "iot_events" {
  name                = "ehns-iot-${random_string.suffix.result}"
  location            = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  sku                 = "Standard"
  capacity            = 1

  tags = merge(var.common_tags, {
    Component = "event-hub"
  })
}

resource "azurerm_eventhub" "quality_events" {
  name                = "eh-quality-events"
  namespace_name      = azurerm_eventhub_namespace.iot_events.name
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  partition_count     = var.iot_hub_partition_count
  message_retention   = 1
}

resource "azurerm_eventhub_authorization_rule" "iot_hub_listen" {
  name                = "iot-hub-listen"
  namespace_name      = azurerm_eventhub_namespace.iot_events.name
  eventhub_name       = azurerm_eventhub.quality_events.name
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  listen              = true
  send                = true
  manage              = false
}

# Create Stream Analytics job for real-time processing
resource "azurerm_stream_analytics_job" "quality_control" {
  count                                = var.enable_stream_analytics ? 1 : 0
  name                                 = "${var.stream_analytics_job_name}-${random_string.suffix.result}"
  resource_group_name                  = azurerm_resource_group.quantum_manufacturing.name
  location                             = azurerm_resource_group.quantum_manufacturing.location
  compatibility_level                  = "1.2"
  data_locale                          = "en-GB"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy           = "Adjust"
  output_error_policy                  = "Drop"
  streaming_units                      = var.stream_analytics_streaming_units

  tags = merge(var.common_tags, {
    Component = "stream-analytics"
  })

  transformation_query = <<QUERY
    SELECT
        System.Timestamp AS WindowEnd,
        IoTHub.ConnectionDeviceId AS DeviceId,
        AVG(temperature) AS avg_temperature,
        AVG(pressure) AS avg_pressure,
        AVG(speed) AS avg_speed,
        AVG(quality_score) AS avg_quality_score,
        COUNT(*) AS message_count
    INTO
        [MLOutput]
    FROM
        [ManufacturingInput] TIMESTAMP BY EventProcessedUtcTime
    GROUP BY
        IoTHub.ConnectionDeviceId,
        TumblingWindow(second, 30)
QUERY
}

# Create Stream Analytics input for IoT Hub
resource "azurerm_stream_analytics_stream_input_iothub" "manufacturing_input" {
  count                         = var.enable_stream_analytics ? 1 : 0
  name                          = "ManufacturingInput"
  stream_analytics_job_name     = azurerm_stream_analytics_job.quality_control[0].name
  resource_group_name           = azurerm_resource_group.quantum_manufacturing.name
  endpoint                      = "messages/events"
  eventhub_consumer_group_name  = "$Default"
  iothub_namespace              = azurerm_iothub.manufacturing_iot.name
  shared_access_policy_key      = azurerm_iothub.manufacturing_iot.shared_access_policy[0].primary_key
  shared_access_policy_name     = azurerm_iothub.manufacturing_iot.shared_access_policy[0].key_name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Create Stream Analytics output to blob storage
resource "azurerm_stream_analytics_output_blob" "ml_output" {
  count                     = var.enable_stream_analytics ? 1 : 0
  name                      = "MLOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.quality_control[0].name
  resource_group_name       = azurerm_resource_group.quantum_manufacturing.name
  storage_account_name      = azurerm_storage_account.quantum_storage.name
  storage_account_key       = azurerm_storage_account.quantum_storage.primary_access_key
  storage_container_name    = azurerm_storage_container.ml_inference.name
  path_pattern              = "quality-control/{date}/{time}"
  date_format               = "yyyy/MM/dd"
  time_format               = "HH"

  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# Create Cosmos DB for dashboard data
resource "azurerm_cosmosdb_account" "quality_dashboard" {
  count               = var.enable_cosmos_db ? 1 : 0
  name                = "${var.cosmos_account_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = var.cosmos_consistency_level
  }

  geo_location {
    location          = azurerm_resource_group.quantum_manufacturing.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = merge(var.common_tags, {
    Component = "cosmos-db"
  })
}

# Create Cosmos DB database
resource "azurerm_cosmosdb_sql_database" "quality_control_db" {
  count               = var.enable_cosmos_db ? 1 : 0
  name                = "QualityControlDB"
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  account_name        = azurerm_cosmosdb_account.quality_dashboard[0].name
}

# Create Cosmos DB container for quality metrics
resource "azurerm_cosmosdb_sql_container" "quality_metrics" {
  count               = var.enable_cosmos_db ? 1 : 0
  name                = "QualityMetrics"
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  account_name        = azurerm_cosmosdb_account.quality_dashboard[0].name
  database_name       = azurerm_cosmosdb_sql_database.quality_control_db[0].name
  partition_key_path  = "/productionLineId"
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  count               = var.enable_function_app ? 1 : 0
  name                = "plan-func-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  location            = azurerm_resource_group.quantum_manufacturing.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = merge(var.common_tags, {
    Component = "app-service-plan"
  })
}

# Create Function App for dashboard API
resource "azurerm_linux_function_app" "dashboard_api" {
  count               = var.enable_function_app ? 1 : 0
  name                = "${var.function_app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  location            = azurerm_resource_group.quantum_manufacturing.location

  storage_account_name       = azurerm_storage_account.quantum_storage.name
  storage_account_access_key = azurerm_storage_account.quantum_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan[0].id

  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"        = var.function_app_runtime
    "COSMOS_CONNECTION_STRING"        = var.enable_cosmos_db ? azurerm_cosmosdb_account.quality_dashboard[0].connection_strings[0] : ""
    "APPINSIGHTS_INSTRUMENTATIONKEY"  = var.enable_application_insights ? azurerm_application_insights.quantum_insights[0].instrumentation_key : ""
    "QUANTUM_WORKSPACE_NAME"          = var.enable_quantum_workspace ? azurerm_quantum_workspace.manufacturing_quantum[0].name : ""
    "ML_WORKSPACE_NAME"               = azurerm_machine_learning_workspace.quantum_ml.name
    "IOT_HUB_CONNECTION_STRING"       = azurerm_iothub.manufacturing_iot.shared_access_policy[0].primary_connection_string
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.common_tags, {
    Component = "function-app"
  })
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "quantum_logs" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "log-quantum-${random_string.suffix.result}"
  location            = azurerm_resource_group.quantum_manufacturing.location
  resource_group_name = azurerm_resource_group.quantum_manufacturing.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(var.common_tags, {
    Component = "log-analytics"
  })
}

# Create role assignments for ML workspace identity
resource "azurerm_role_assignment" "ml_storage_blob_contributor" {
  scope                = azurerm_storage_account.quantum_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.quantum_ml.identity[0].principal_id
}

resource "azurerm_role_assignment" "ml_key_vault_secrets_user" {
  scope                = azurerm_key_vault.quantum_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_machine_learning_workspace.quantum_ml.identity[0].principal_id
}

# Create role assignments for Function App identity
resource "azurerm_role_assignment" "func_cosmos_contributor" {
  count                = var.enable_function_app && var.enable_cosmos_db ? 1 : 0
  scope                = azurerm_cosmosdb_account.quality_dashboard[0].id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = azurerm_linux_function_app.dashboard_api[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "func_storage_blob_reader" {
  count                = var.enable_function_app ? 1 : 0
  scope                = azurerm_storage_account.quantum_storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_function_app.dashboard_api[0].identity[0].principal_id
}

# Store connection strings in Key Vault
resource "azurerm_key_vault_secret" "cosmos_connection_string" {
  count        = var.enable_cosmos_db ? 1 : 0
  name         = "cosmos-connection-string"
  value        = azurerm_cosmosdb_account.quality_dashboard[0].connection_strings[0]
  key_vault_id = azurerm_key_vault.quantum_kv.id
}

resource "azurerm_key_vault_secret" "iot_hub_connection_string" {
  name         = "iot-hub-connection-string"
  value        = azurerm_iothub.manufacturing_iot.shared_access_policy[0].primary_connection_string
  key_vault_id = azurerm_key_vault.quantum_kv.id
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.quantum_storage.primary_connection_string
  key_vault_id = azurerm_key_vault.quantum_kv.id
}

# Configure diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "iot_hub_diagnostics" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "iot-hub-diagnostics"
  target_resource_id         = azurerm_iothub.manufacturing_iot.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.quantum_logs[0].id

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

resource "azurerm_monitor_diagnostic_setting" "ml_workspace_diagnostics" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "ml-workspace-diagnostics"
  target_resource_id         = azurerm_machine_learning_workspace.quantum_ml.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.quantum_logs[0].id

  enabled_log {
    category = "AmlComputeClusterEvent"
  }

  enabled_log {
    category = "AmlComputeClusterNodeEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Wait for resources to be ready
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_machine_learning_workspace.quantum_ml,
    azurerm_iothub.manufacturing_iot,
    azurerm_storage_account.quantum_storage
  ]
  
  create_duration = "30s"
}
# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = merge(var.tags, var.additional_tags)
}

# Create Storage Account with Data Lake Gen2
resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name != null ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  is_hns_enabled          = var.enable_data_lake
  
  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Network rules for enhanced security
  network_rules {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    ip_rules       = var.allowed_ip_ranges
  }
  
  # Blob properties for lifecycle management
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = var.data_retention_days
    }
    
    container_delete_retention_policy {
      days = var.data_retention_days
    }
    
    lifecycle_policy {
      rule {
        name    = "environmental-data-lifecycle"
        enabled = true
        
        filters {
          prefix_match = ["environmental-data/"]
          blob_types   = ["blockBlob"]
        }
        
        actions {
          base_blob {
            tier_to_cool_after_days_since_modification_greater_than    = 30
            tier_to_archive_after_days_since_modification_greater_than = 90
            delete_after_days_since_modification_greater_than          = var.data_retention_days
          }
        }
      }
    }
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Storage"
  })
}

# Create containers for environmental data
resource "azurerm_storage_container" "environmental_data" {
  name                  = "environmental-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processed_data" {
  name                  = "processed-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "archive_data" {
  name                  = "archive-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create Key Vault for secure secrets management
resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name != null ? var.key_vault_name : "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = var.key_vault_sku
  
  enabled_for_disk_encryption     = var.key_vault_enabled_for_disk_encryption
  enabled_for_deployment          = var.key_vault_enabled_for_deployment
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  purge_protection_enabled       = false
  soft_delete_retention_days     = var.key_vault_soft_delete_retention_days
  
  # Network access rules
  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Security"
  })
}

# Grant Key Vault access to current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey"
  ]
  
  secret_permissions = [
    "Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"
  ]
  
  certificate_permissions = [
    "Backup", "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers", "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers", "Purge", "Recover", "Restore", "SetIssuers", "Update"
  ]
}

# Store storage account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Secret"
  })
}

# Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "log-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Monitoring"
  })
}

# Create Application Insights
resource "azurerm_application_insights" "main" {
  name                = var.application_insights_name != null ? var.application_insights_name : "appi-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Monitoring"
  })
}

# Create Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Compute"
  })
}

# Create Function App for data transformation
resource "azurerm_linux_function_app" "main" {
  name                = var.function_app_name != null ? var.function_app_name : "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                 = var.function_app_runtime
    "FUNCTIONS_WORKER_RUNTIME_VERSION"         = var.function_app_runtime_version
    "APPINSIGHTS_INSTRUMENTATIONKEY"           = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"    = azurerm_application_insights.main.connection_string
    "STORAGE_CONNECTION_STRING"                = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.storage_connection_string.id})"
    "WEBSITE_RUN_FROM_PACKAGE"                = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"         = "true"
    "WEBSITE_CONTENTOVERVNET"                 = "1"
    "AzureWebJobsFeatureFlags"                = "EnableWorkerIndexing"
  }
  
  # Site configuration
  site_config {
    always_on                              = var.function_app_service_plan_sku != "Y1"
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS settings for development
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }
  
  # Identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Compute"
  })
}

# Grant Function App access to Key Vault
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Create Azure Data Factory
resource "azurerm_data_factory" "main" {
  name                = var.data_factory_name != null ? var.data_factory_name : "adf-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  managed_virtual_network_enabled = var.data_factory_managed_vnet_enabled
  public_network_enabled          = var.data_factory_public_network_enabled
  
  # Identity for accessing other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  # Global parameters for pipeline configuration
  global_parameter {
    name  = "environment"
    type  = "String"
    value = var.environment
  }
  
  global_parameter {
    name  = "data_retention_days"
    type  = "Int"
    value = var.data_retention_days
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "DataFactory"
  })
}

# Grant Data Factory access to storage account
resource "azurerm_role_assignment" "adf_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

# Grant Data Factory access to Key Vault
resource "azurerm_key_vault_access_policy" "data_factory" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_data_factory.main.identity[0].tenant_id
  object_id    = azurerm_data_factory.main.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Create Data Factory Linked Service for Storage
resource "azurerm_data_factory_linked_service_azure_blob_storage" "main" {
  name            = "StorageLinkedService"
  data_factory_id = azurerm_data_factory.main.id
  
  # Use system-assigned managed identity for authentication
  use_managed_identity = true
  service_endpoint     = azurerm_storage_account.main.primary_blob_endpoint
  
  depends_on = [azurerm_role_assignment.adf_storage_contributor]
}

# Create Data Factory Linked Service for Function App
resource "azurerm_data_factory_linked_service_azure_function" "main" {
  name            = "FunctionLinkedService"
  data_factory_id = azurerm_data_factory.main.id
  url             = "https://${azurerm_linux_function_app.main.name}.azurewebsites.net"
  
  # Use system-assigned managed identity for authentication
  authentication = "MSI"
  resource       = "https://management.azure.com"
}

# Create Data Factory Dataset for Environmental Data
resource "azurerm_data_factory_dataset_delimited_text" "environmental_data" {
  name            = "EnvironmentalDataSet"
  data_factory_id = azurerm_data_factory.main.id
  
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.main.name
  
  azure_blob_storage_location {
    container = azurerm_storage_container.environmental_data.name
    filename  = "*.csv"
  }
  
  column_delimiter    = ","
  row_delimiter      = "\n"
  encoding           = "UTF-8"
  first_row_as_header = true
  
  schema_column {
    name = "timestamp"
    type = "DateTime"
  }
  
  schema_column {
    name = "sensor_id"
    type = "String"
  }
  
  schema_column {
    name = "metric_type"
    type = "String"
  }
  
  schema_column {
    name = "value"
    type = "Decimal"
  }
  
  schema_column {
    name = "unit"
    type = "String"
  }
  
  schema_column {
    name = "location"
    type = "String"
  }
}

# Create Data Factory Dataset for Processed Data
resource "azurerm_data_factory_dataset_delimited_text" "processed_data" {
  name            = "ProcessedDataSet"
  data_factory_id = azurerm_data_factory.main.id
  
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.main.name
  
  azure_blob_storage_location {
    container = azurerm_storage_container.processed_data.name
    filename  = "processed_data.csv"
  }
  
  column_delimiter    = ","
  row_delimiter      = "\n"
  encoding           = "UTF-8"
  first_row_as_header = true
}

# Create Data Factory Pipeline for Environmental Data Processing
resource "azurerm_data_factory_pipeline" "environmental_pipeline" {
  name            = "EnvironmentalDataPipeline"
  data_factory_id = azurerm_data_factory.main.id
  
  activities_json = jsonencode([
    {
      name = "CopyEnvironmentalData"
      type = "Copy"
      dependsOn = []
      policy = {
        timeout = "0.12:00:00"
        retry   = 0
        retryIntervalInSeconds = 30
        secureOutput = false
        secureInput  = false
      }
      userProperties = []
      typeProperties = {
        source = {
          type = "DelimitedTextSource"
          storeSettings = {
            type = "AzureBlobStorageReadSettings"
            recursive = true
            wildcardFolderPath = "raw"
            wildcardFileName = "*.csv"
            enablePartitionDiscovery = false
          }
          formatSettings = {
            type = "DelimitedTextReadSettings"
          }
        }
        sink = {
          type = "DelimitedTextSink"
          storeSettings = {
            type = "AzureBlobStorageWriteSettings"
          }
          formatSettings = {
            type = "DelimitedTextWriteSettings"
            quoteAllText = false
            fileExtension = ".csv"
          }
        }
        enableStaging = false
        translator = {
          type = "TabularTranslator"
          typeConversion = true
          typeConversionSettings = {
            allowDataTruncation = true
            treatBooleanAsNumber = false
          }
        }
      }
      inputs = [{
        referenceName = azurerm_data_factory_dataset_delimited_text.environmental_data.name
        type = "DatasetReference"
      }]
      outputs = [{
        referenceName = azurerm_data_factory_dataset_delimited_text.processed_data.name
        type = "DatasetReference"
      }]
    },
    {
      name = "ProcessEnvironmentalMetrics"
      type = "AzureFunctionActivity"
      dependsOn = [{
        activity = "CopyEnvironmentalData"
        dependencyConditions = ["Succeeded"]
      }]
      policy = {
        timeout = "0.12:00:00"
        retry   = 0
        retryIntervalInSeconds = 30
        secureOutput = false
        secureInput  = false
      }
      userProperties = []
      typeProperties = {
        functionName = "ProcessEnvironmentalData"
        method       = "POST"
        headers      = {}
        body = {
          message = "Environmental data processing request"
          timestamp = "@utcNow()"
        }
      }
      linkedServiceName = {
        referenceName = azurerm_data_factory_linked_service_azure_function.main.name
        type = "LinkedServiceReference"
      }
    }
  ])
  
  parameters = {
    "source_container" = azurerm_storage_container.environmental_data.name
    "sink_container"   = azurerm_storage_container.processed_data.name
  }
}

# Create Data Factory Trigger for Scheduled Pipeline Execution
resource "azurerm_data_factory_trigger_schedule" "daily_trigger" {
  name            = "DailyEnvironmentalDataTrigger"
  data_factory_id = azurerm_data_factory.main.id
  
  frequency = var.pipeline_schedule_frequency
  interval  = var.pipeline_schedule_interval
  
  start_time = formatdate("YYYY-MM-DD'T'${var.pipeline_schedule_start_time}:00Z", timeadd(timestamp(), "24h"))
  
  pipeline_name = azurerm_data_factory_pipeline.environmental_pipeline.name
  
  activated = true
  
  annotations = [
    "Environmental Data Processing",
    "Automated Pipeline"
  ]
}

# Create Action Group for Monitoring Alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "EnvironmentalAlerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "EnvAlerts"
  
  email_receiver {
    name          = "admin"
    email_address = var.alert_email_address
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Monitoring"
  })
}

# Create Alert Rule for Pipeline Failures
resource "azurerm_monitor_metric_alert" "pipeline_failures" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "EnvironmentalPipelineFailures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_data_factory.main.id]
  description         = "Alert when environmental data pipeline fails"
  
  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    
    dimension {
      name     = "Name"
      operator = "Include"
      values   = [azurerm_data_factory_pipeline.environmental_pipeline.name]
    }
  }
  
  window_size        = "PT5M"
  frequency          = "PT1M"
  severity           = 2
  auto_mitigate      = true
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Monitoring"
  })
}

# Create Alert Rule for Data Processing Delays
resource "azurerm_monitor_metric_alert" "processing_delays" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "EnvironmentalDataProcessingDelay"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_data_factory.main.id]
  description         = "Alert when environmental data processing is delayed"
  
  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineElapsedTimeRuns"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1800 # 30 minutes in seconds
  }
  
  window_size        = "PT15M"
  frequency          = "PT5M"
  severity           = 3
  auto_mitigate      = true
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(var.tags, var.additional_tags, {
    ResourceType = "Monitoring"
  })
}

# Create Diagnostic Settings for Data Factory
resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "EnvironmentalDataFactoryDiagnostics"
  target_resource_id         = azurerm_data_factory.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "PipelineRuns"
  }
  
  enabled_log {
    category = "TriggerRuns"
  }
  
  enabled_log {
    category = "ActivityRuns"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Create Diagnostic Settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "EnvironmentalFunctionAppDiagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Create Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "EnvironmentalStorageDiagnostics"
  target_resource_id         = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
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
    category = "Transaction"
  }
}

# Create Budget Alert for Cost Management
resource "azurerm_consumption_budget_resource_group" "main" {
  count               = var.enable_cost_alerts ? 1 : 0
  name                = "EnvironmentalDataPipelineBudget"
  resource_group_id   = azurerm_resource_group.main.id
  
  amount     = var.monthly_budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01T00:00:00Z", timestamp())
    end_date   = formatdate("YYYY-MM-01T00:00:00Z", timeadd(timestamp(), "8760h")) # 1 year from now
  }
  
  filter {
    dimension {
      name = "ResourceGroupName"
      values = [azurerm_resource_group.main.name]
    }
  }
  
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = [var.alert_email_address]
  }
  
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = [var.alert_email_address]
  }
}
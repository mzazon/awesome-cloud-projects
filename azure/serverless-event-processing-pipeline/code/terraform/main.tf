# Main Terraform configuration for Azure real-time data processing with Event Hubs and Functions

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource group to contain all resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}

# Storage account for Function App backend and checkpointing
resource "azurerm_storage_account" "function_storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable advanced security features
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Enable blob versioning and change feed for better data management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure blob retention policy
    delete_retention_policy {
      days = 7
    }
    
    # Configure container deletion retention policy
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules for security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = merge(var.tags, {
    Purpose = "Function App storage and Event Hub checkpointing"
  })
}

# Event Hubs namespace for event ingestion
resource "azurerm_eventhub_namespace" "main" {
  name                = "eh-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.eventhub_namespace_sku
  capacity            = var.eventhub_namespace_sku == "Basic" ? 1 : 2
  
  # Enable auto-inflate for Standard and Premium SKUs
  auto_inflate_enabled     = var.enable_auto_scale && var.eventhub_namespace_sku != "Basic"
  maximum_throughput_units = var.enable_auto_scale && var.eventhub_namespace_sku != "Basic" ? var.maximum_throughput_units : null
  
  # Enable zone redundancy for Premium SKU
  zone_redundant = var.eventhub_namespace_sku == "Premium"
  
  # Network security configuration
  network_rulesets {
    default_action = "Allow"
    
    trusted_service_access_enabled = true
    
    # IP rules can be added here for additional security
    ip_rule = []
    
    # Virtual network rules can be added here
    virtual_network_rule = []
  }
  
  tags = merge(var.tags, {
    Purpose = "Event ingestion and streaming"
  })
}

# Event Hub for receiving events
resource "azurerm_eventhub" "events" {
  name                = "events-hub"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention
  
  # Enable capture for long-term storage (optional)
  capture_description {
    enabled  = false
    encoding = "Avro"
    
    # Configure capture destination when enabled
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "eventhub-capture"
      storage_account_id  = azurerm_storage_account.function_storage.id
    }
  }
  
  depends_on = [azurerm_eventhub_namespace.main]
}

# Event Hub authorization rule for Function App access
resource "azurerm_eventhub_authorization_rule" "function_access" {
  name                = "FunctionAppAccess"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.events.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Grant listen permissions for function triggers
  listen = true
  send   = false
  manage = false
  
  depends_on = [azurerm_eventhub.events]
}

# Event Hub authorization rule for sending test events
resource "azurerm_eventhub_authorization_rule" "sender_access" {
  name                = "SenderAccess"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.events.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Grant send permissions for event producers
  listen = false
  send   = true
  manage = false
  
  depends_on = [azurerm_eventhub.events]
}

# Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  
  # Configure data retention
  retention_in_days = var.application_insights_retention_days
  
  # Disable automatic rule generation to avoid conflicts
  disable_ip_masking = false
  
  tags = merge(var.tags, {
    Purpose = "Application monitoring and telemetry"
  })
}

# Log Analytics workspace for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "log-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = merge(var.tags, {
    Purpose = "Log analytics and monitoring"
  })
}

# App Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_size
  
  tags = merge(var.tags, {
    Purpose = "Function App hosting"
  })
}

# Function App for event processing
resource "azurerm_linux_function_app" "processor" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Function App configuration
  functions_extension_version = "~4"
  https_only                  = var.enable_https_only
  
  # Site configuration
  site_config {
    always_on                               = var.function_app_service_plan_tier != "Dynamic" ? var.function_app_always_on : false
    use_32_bit_worker                      = var.function_app_32bit
    ftps_state                             = "Disabled"
    http2_enabled                          = true
    minimum_tls_version                    = "1.2"
    remote_debugging_enabled               = false
    scm_use_main_ip_restriction           = false
    
    # Application stack configuration
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      python_version = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
      java_version = var.function_app_runtime == "java" ? var.function_app_runtime_version : null
      dotnet_version = var.function_app_runtime == "dotnet" ? var.function_app_runtime_version : null
    }
    
    # CORS configuration
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }
    
    # Enable Application Insights if configured
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  }
  
  # Application settings
  app_settings = {
    "AzureWebJobsStorage"           = azurerm_storage_account.function_storage.primary_connection_string
    "FUNCTIONS_EXTENSION_VERSION"   = "~4"
    "FUNCTIONS_WORKER_RUNTIME"      = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"  = var.function_app_runtime == "node" ? "~${var.function_app_runtime_version}" : null
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
    "ENABLE_ORYX_BUILD"             = "false"
    
    # Event Hub connection configuration
    "EventHubConnectionString" = azurerm_eventhub_authorization_rule.function_access.primary_connection_string
    "EventHubName"            = azurerm_eventhub.events.name
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    
    # Runtime configuration
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
    # Security headers
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS" = "3"
    "WEBSITE_LOAD_CERTIFICATES" = "*"
  }
  
  # Connection strings for additional data sources
  connection_string {
    name  = "EventHubConnection"
    type  = "EventHub"
    value = azurerm_eventhub_authorization_rule.function_access.primary_connection_string
  }
  
  # Sticky settings that should not be swapped during deployments
  sticky_settings {
    app_setting_names = [
      "APPINSIGHTS_INSTRUMENTATIONKEY",
      "APPLICATIONINSIGHTS_CONNECTION_STRING",
      "EventHubConnectionString"
    ]
  }
  
  # Identity for secure access to other Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Purpose = "Event processing and real-time data handling"
  })
  
  depends_on = [
    azurerm_service_plan.function_plan,
    azurerm_storage_account.function_storage,
    azurerm_eventhub_authorization_rule.function_access
  ]
}

# Consumer group for the Function App
resource "azurerm_eventhub_consumer_group" "function_consumer" {
  name                = "function-consumer-group"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.events.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Consumer group specific settings
  user_metadata = "Function App consumer group for real-time processing"
  
  depends_on = [azurerm_eventhub.events]
}

# Container for Event Hub capture (if enabled)
resource "azurerm_storage_container" "eventhub_capture" {
  name                  = "eventhub-capture"
  storage_account_name  = azurerm_storage_account.function_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.function_storage]
}

# Role assignment for Function App to access Event Hub
resource "azurerm_role_assignment" "function_eventhub_access" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.processor]
}

# Role assignment for Function App to access Storage Account
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.function_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.processor]
}

# Monitor action group for alerts (optional)
resource "azurerm_monitor_action_group" "alerts" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "ag-${var.project_name}-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "AlertGroup"
  
  tags = merge(var.tags, {
    Purpose = "Alert notifications"
  })
}

# Metric alert for Function App errors
resource "azurerm_monitor_metric_alert" "function_errors" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "Function App High Error Rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.processor.id]
  description         = "Alert when Function App error rate exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    
    dimension {
      name     = "Instance"
      operator = "Include"
      values   = ["*"]
    }
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  
  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
  
  tags = merge(var.tags, {
    Purpose = "Function App error monitoring"
  })
}

# Diagnostic settings for Event Hub namespace
resource "azurerm_monitor_diagnostic_setting" "eventhub_diagnostics" {
  count = var.enable_application_insights ? 1 : 0
  
  name                       = "eventhub-diagnostics"
  target_resource_id         = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "ArchiveLogs"
  }
  
  enabled_log {
    category = "OperationalLogs"
  }
  
  enabled_log {
    category = "AutoScaleLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_diagnostics" {
  count = var.enable_application_insights ? 1 : 0
  
  name                       = "function-diagnostics"
  target_resource_id         = azurerm_linux_function_app.processor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
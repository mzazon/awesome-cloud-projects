# Main Terraform configuration for Azure Real-Time Data Validation Workflows
# This file creates the complete infrastructure for orchestrating real-time data validation
# using Azure Table Storage, Event Grid, Logic Apps, and Azure Functions

# ============================================================================
# Data Sources and Local Values
# ============================================================================

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  
  # Common tags merged with user-defined tags
  common_tags = merge(var.tags, {
    Terraform   = "true"
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Resource names with consistent naming convention
  resource_group_name         = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name        = "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
  event_grid_topic_name       = "${var.event_grid_topic_name}-${var.environment}-${local.resource_suffix}"
  function_app_name           = "${var.function_app_name}-${var.environment}-${local.resource_suffix}"
  logic_app_name              = "${var.logic_app_name}-${var.environment}-${local.resource_suffix}"
  log_analytics_workspace_name = "${var.log_analytics_workspace_name}-${var.environment}-${local.resource_suffix}"
  application_insights_name   = "${var.application_insights_name}-${var.environment}-${local.resource_suffix}"
  
  # Service plan names
  function_service_plan_name = "asp-${var.function_app_name}-${var.environment}-${local.resource_suffix}"
  logic_app_service_plan_name = "asp-${var.logic_app_name}-${var.environment}-${local.resource_suffix}"
}

# ============================================================================
# Resource Group
# ============================================================================

# Create the main resource group for all resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ============================================================================
# Storage Account and Table Storage
# ============================================================================

# Create storage account for table storage and function app storage
resource "azurerm_storage_account" "main" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Storage account configuration
  account_tier                    = var.storage_account_tier
  account_replication_type        = var.storage_account_replication_type
  access_tier                     = var.storage_account_access_tier
  account_kind                    = "StorageV2"
  enable_https_traffic_only       = var.enable_https_only
  min_tls_version                 = var.minimum_tls_version
  allow_nested_items_to_be_public = false
  
  # Security and compliance settings
  infrastructure_encryption_enabled = var.enable_storage_encryption
  
  # Blob properties configuration
  blob_properties {
    # Enable versioning for blob storage
    versioning_enabled = true
    
    # Configure container delete retention
    delete_retention_policy {
      days = 7
    }
    
    # Configure change feed for audit trail
    change_feed_enabled = true
  }
  
  # Network rules for security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Create tables in the storage account
resource "azurerm_storage_table" "tables" {
  for_each = toset(var.table_names)
  
  name                 = each.value
  storage_account_name = azurerm_storage_account.main.name
  
  depends_on = [azurerm_storage_account.main]
}

# ============================================================================
# Event Grid Topic
# ============================================================================

# Create Event Grid topic for custom events
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Event Grid configuration
  local_auth_enabled = var.enable_event_grid_local_auth
  
  # Input schema configuration
  input_schema = "EventGridSchema"
  
  tags = local.common_tags
}

# ============================================================================
# Log Analytics Workspace
# ============================================================================

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Workspace configuration
  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_in_days
  
  tags = local.common_tags
}

# ============================================================================
# Application Insights
# ============================================================================

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Application Insights configuration
  application_type    = var.application_insights_type
  workspace_id        = azurerm_log_analytics_workspace.main.id
  retention_in_days   = var.log_analytics_retention_in_days
  
  tags = local.common_tags
}

# ============================================================================
# Function App Service Plan
# ============================================================================

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = local.function_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Service plan configuration
  os_type  = "Linux"
  sku_name = var.function_app_sku_name
  
  tags = local.common_tags
}

# ============================================================================
# Function App
# ============================================================================

# Create Function App for data validation
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Function App configuration
  service_plan_id            = azurerm_service_plan.function_app.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function App settings
  https_only                 = var.enable_https_only
  functions_extension_version = "~4"
  
  # Site configuration
  site_config {
    # Runtime configuration
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Security settings
    ftps_state             = "Disabled"
    http2_enabled          = true
    minimum_tls_version    = var.minimum_tls_version
    use_32_bit_worker      = false
    
    # CORS configuration
    cors {
      allowed_origins = ["*"]
    }
    
    # Application insights integration
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Application settings
  app_settings = {
    # Storage connection string
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    
    # Event Grid configuration
    "EVENT_GRID_TOPIC_ENDPOINT" = azurerm_eventgrid_topic.main.endpoint
    "EVENT_GRID_TOPIC_KEY"      = azurerm_eventgrid_topic.main.primary_access_key
    
    # Function configuration
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
    # Monitoring settings
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Custom validation settings
    "HIGH_VALUE_ORDER_THRESHOLD" = var.high_value_order_threshold
    "NOTIFICATION_EMAIL"         = var.notification_email
    
    # Performance settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                      = "${local.function_app_name}-content"
  }
  
  # Identity configuration for managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_application_insights.main,
    azurerm_eventgrid_topic.main
  ]
}

# ============================================================================
# Logic App Service Plan
# ============================================================================

# Create App Service Plan for Logic App
resource "azurerm_service_plan" "logic_app" {
  name                = local.logic_app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Service plan configuration
  os_type  = "Windows"
  sku_name = "WS1"  # Logic App Standard requires WorkflowStandard SKU
  
  tags = local.common_tags
}

# ============================================================================
# Logic App (Standard)
# ============================================================================

# Create Logic App for complex validation workflows
resource "azurerm_logic_app_standard" "main" {
  name                       = local.logic_app_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  app_service_plan_id        = azurerm_service_plan.logic_app.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Logic App configuration
  https_only                 = var.enable_https_only
  version                    = "~4"
  
  # Application settings
  app_settings = {
    # Storage connection string
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    
    # Event Grid configuration
    "EVENT_GRID_TOPIC_ENDPOINT" = azurerm_eventgrid_topic.main.endpoint
    "EVENT_GRID_TOPIC_KEY"      = azurerm_eventgrid_topic.main.primary_access_key
    
    # Monitoring settings
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Custom validation settings
    "HIGH_VALUE_ORDER_THRESHOLD" = var.high_value_order_threshold
    "NOTIFICATION_EMAIL"         = var.notification_email
    
    # Logic App runtime settings
    "FUNCTIONS_EXTENSION_VERSION" = "~4"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    
    # Content storage settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE" = "${local.logic_app_name}-content"
  }
  
  # Site configuration
  site_config {
    # Security settings
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version
    
    # CORS configuration
    cors {
      allowed_origins = ["*"]
    }
  }
  
  # Identity configuration for managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_application_insights.main,
    azurerm_eventgrid_topic.main
  ]
}

# ============================================================================
# Event Grid System Topic for Storage Events
# ============================================================================

# Create Event Grid system topic for storage account events
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "storage-events-${local.resource_suffix}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.main.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  
  tags = local.common_tags
}

# ============================================================================
# Event Grid Subscriptions
# ============================================================================

# Create Event Grid subscription for Function App
resource "azurerm_eventgrid_system_topic_event_subscription" "function_subscription" {
  name                = "function-validation-subscription"
  system_topic        = azurerm_eventgrid_system_topic.storage.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Event subscription configuration
  event_delivery_schema = "EventGridSchema"
  
  # Event types to subscribe to
  included_event_types = [
    "Microsoft.Storage.BlobCreated",
    "Microsoft.Storage.BlobDeleted"
  ]
  
  # Subject filter for table data
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/tabledata"
  }
  
  # Azure Function endpoint
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/DataValidationFunction"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Retry policy
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }
  
  # Dead letter configuration
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "dead-letters"
  }
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_eventgrid_system_topic.storage
  ]
}

# Create Event Grid subscription for Logic App
resource "azurerm_eventgrid_event_subscription" "logic_app_subscription" {
  name  = "logicapp-validation-subscription"
  scope = azurerm_eventgrid_topic.main.id
  
  # Event subscription configuration
  event_delivery_schema = "EventGridSchema"
  
  # Webhook endpoint for Logic App
  webhook_endpoint {
    url                               = "https://${azurerm_logic_app_standard.main.default_hostname}/runtime/webhooks/workflow/api/management/workflows/ValidationWorkflow/triggers/When_a_HTTP_request_is_received/listCallbackUrl?api-version=2020-05-01-preview"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Retry policy
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }
  
  # Dead letter configuration
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "dead-letters"
  }
  
  depends_on = [
    azurerm_logic_app_standard.main,
    azurerm_eventgrid_topic.main
  ]
}

# ============================================================================
# Storage Container for Dead Letter Queue
# ============================================================================

# Create storage container for dead letter queue
resource "azurerm_storage_container" "dead_letters" {
  name                  = "dead-letters"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ============================================================================
# Role Assignments for Managed Identities
# ============================================================================

# Assign Storage Blob Data Contributor role to Function App
resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Assign Storage Table Data Contributor role to Function App
resource "azurerm_role_assignment" "function_storage_table" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Assign EventGrid Data Sender role to Function App
resource "azurerm_role_assignment" "function_eventgrid" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Assign Storage Blob Data Contributor role to Logic App
resource "azurerm_role_assignment" "logic_app_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
}

# Assign Storage Table Data Contributor role to Logic App
resource "azurerm_role_assignment" "logic_app_storage_table" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
}

# ============================================================================
# Function App Code Deployment (Placeholder)
# ============================================================================

# Create a placeholder zip file for function deployment
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function-app.zip"
  
  source {
    content = jsonencode({
      "version" : "2.0",
      "functionTimeout" : "00:0${var.function_timeout}:00",
      "extensions" : {
        "eventGrid" : {
          "maxBatchSize" : 10,
          "prefetchCount" : 100
        }
      }
    })
    filename = "host.json"
  }
  
  source {
    content = "azure-functions\nazure-storage-table\nazure-eventgrid\nazure-functions-worker"
    filename = "requirements.txt"
  }
}

# ============================================================================
# Monitoring Alerts
# ============================================================================

# Create action group for notifications
resource "azurerm_monitor_action_group" "main" {
  name                = "validation-alerts-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "valalerts"
  
  email_receiver {
    name          = "admin"
    email_address = var.notification_email
  }
  
  tags = local.common_tags
}

# Create alert rule for Function App failures
resource "azurerm_monitor_metric_alert" "function_failures" {
  name                = "function-failures-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when Function App has high failure rate"
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  window_size = "PT5M"
  frequency   = "PT1M"
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

# Create alert rule for Event Grid delivery failures
resource "azurerm_monitor_metric_alert" "eventgrid_failures" {
  name                = "eventgrid-failures-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_eventgrid_topic.main.id]
  description         = "Alert when Event Grid has delivery failures"
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.EventGrid/topics"
    metric_name      = "DeadLetteredCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  window_size = "PT5M"
  frequency   = "PT1M"
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}
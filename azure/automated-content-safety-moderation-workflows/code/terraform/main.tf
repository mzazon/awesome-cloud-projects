# Main Terraform configuration for Azure Content Moderation with AI Content Safety and Logic Apps

# Generate random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  # Resource naming
  resource_suffix = random_string.suffix.result
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}"
  
  # Storage account name (must be globally unique, lowercase, no hyphens)
  storage_account_name = "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
  
  # AI Content Safety service name
  ai_content_safety_name = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Logic App name
  logic_app_name = "logic-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Event Grid topic name
  event_grid_topic_name = "eg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Function App name
  function_app_name = "func-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Log Analytics workspace name
  log_analytics_name = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Environment   = var.environment
      Project       = var.project_name
      Purpose       = "content-moderation"
      ManagedBy     = "terraform"
      DeployedDate  = formatdate("YYYY-MM-DD", timestamp())
    },
    var.tags
  )
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for content storage
resource "azurerm_storage_account" "content_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security settings
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  
  # Blob properties
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create storage containers for content management
resource "azurerm_storage_container" "uploads" {
  name                  = "uploads"
  storage_account_name  = azurerm_storage_account.content_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.content_storage]
}

resource "azurerm_storage_container" "quarantine" {
  name                  = "quarantine"
  storage_account_name  = azurerm_storage_account.content_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.content_storage]
}

resource "azurerm_storage_container" "approved" {
  name                  = "approved"
  storage_account_name  = azurerm_storage_account.content_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.content_storage]
}

# Create storage queue for content processing
resource "azurerm_storage_queue" "content_processing" {
  name                 = "content-processing"
  storage_account_name = azurerm_storage_account.content_storage.name
  
  depends_on = [azurerm_storage_account.content_storage]
}

# Create Azure AI Content Safety service
resource "azurerm_cognitive_account" "content_safety" {
  name                = local.ai_content_safety_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ContentSafety"
  sku_name            = var.ai_content_safety_sku
  
  # Custom subdomain for API access
  custom_subdomain_name = local.ai_content_safety_name
  
  # Enable local authentication
  local_auth_enabled = true
  
  tags = local.common_tags
}

# Create Event Grid topic for event routing
resource "azurerm_eventgrid_topic" "content_events" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  input_schema = var.event_grid_topic_input_schema
  
  tags = local.common_tags
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  
  tags = local.common_tags
}

# Create Application Insights for function monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Connect to Log Analytics workspace if monitoring is enabled
  workspace_id = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
  
  tags = local.common_tags
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_plan_sku
  
  tags = local.common_tags
}

# Create Function App for content processing
resource "azurerm_linux_function_app" "content_processor" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  storage_account_name       = azurerm_storage_account.content_storage.name
  storage_account_access_key = azurerm_storage_account.content_storage.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.9"
    }
    
    # Enable application insights
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }
  
  # Configure application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "AI_CONTENT_SAFETY_ENDPOINT"     = azurerm_cognitive_account.content_safety.endpoint
    "AI_CONTENT_SAFETY_KEY"          = azurerm_cognitive_account.content_safety.primary_access_key
    "STORAGE_CONNECTION_STRING"      = azurerm_storage_account.content_storage.primary_connection_string
    "EVENT_GRID_ENDPOINT"            = azurerm_eventgrid_topic.content_events.endpoint
    "EVENT_GRID_KEY"                 = azurerm_eventgrid_topic.content_events.primary_access_key
    "CONTENT_SAFETY_CATEGORIES"      = join(",", var.content_safety_categories)
    "CONTENT_SAFETY_THRESHOLD"       = var.content_safety_severity_threshold
    "NOTIFICATION_EMAIL"             = var.notification_email
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Logic App for workflow orchestration
resource "azurerm_logic_app_workflow" "content_moderation" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Event Grid subscription for blob storage events
resource "azurerm_eventgrid_event_subscription" "blob_events" {
  name  = "content-upload-subscription"
  scope = azurerm_storage_account.content_storage.id
  
  # Filter for blob created events in uploads container
  included_event_types = ["Microsoft.Storage.BlobCreated"]
  
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/uploads/"
  }
  
  # Send events to Logic App
  webhook_endpoint {
    url = "https://${azurerm_logic_app_workflow.content_moderation.access_endpoint}/triggers/When_a_blob_is_added/run"
  }
  
  depends_on = [
    azurerm_storage_account.content_storage,
    azurerm_logic_app_workflow.content_moderation
  ]
}

# Create role assignment for Function App to access Storage
resource "azurerm_role_assignment" "function_storage_contributor" {
  scope                = azurerm_storage_account.content_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.content_processor.identity[0].principal_id
}

# Create role assignment for Function App to access Cognitive Services
resource "azurerm_role_assignment" "function_cognitive_user" {
  scope                = azurerm_cognitive_account.content_safety.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.content_processor.identity[0].principal_id
}

# Create role assignment for Logic App to access Storage
resource "azurerm_role_assignment" "logic_app_storage_contributor" {
  scope                = azurerm_storage_account.content_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.content_moderation.identity[0].principal_id
}

# Create role assignment for Logic App to access Event Grid
resource "azurerm_role_assignment" "logic_app_eventgrid_contributor" {
  scope                = azurerm_eventgrid_topic.content_events.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_logic_app_workflow.content_moderation.identity[0].principal_id
}

# Create diagnostic settings for Logic App (if monitoring is enabled)
resource "azurerm_monitor_diagnostic_setting" "logic_app_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "logic-app-diagnostics"
  target_resource_id         = azurerm_logic_app_workflow.content_moderation.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Create diagnostic settings for Function App (if monitoring is enabled)
resource "azurerm_monitor_diagnostic_setting" "function_app_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.content_processor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Create diagnostic settings for Storage Account (if monitoring is enabled)
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "storage-diagnostics"
  target_resource_id         = "${azurerm_storage_account.content_storage.id}/blobServices/default"
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
    category = "Transaction"
  }
}

# Create Action Group for alerts (if monitoring is enabled and email is provided)
resource "azurerm_monitor_action_group" "content_moderation_alerts" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  name                = "content-moderation-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "contentmod"
  
  email_receiver {
    name          = "moderator"
    email_address = var.notification_email
  }
  
  tags = local.common_tags
}

# Create metric alert for high content safety violations (if monitoring is enabled)
resource "azurerm_monitor_metric_alert" "high_violations" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  name                = "high-content-violations"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_logic_app_workflow.content_moderation.id]
  description         = "Alert when content safety violations are high"
  
  criteria {
    metric_namespace = "Microsoft.Logic/workflows"
    metric_name      = "RunsFailed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.content_moderation_alerts[0].id
  }
  
  frequency   = "PT5M"
  window_size = "PT15M"
  
  tags = local.common_tags
}
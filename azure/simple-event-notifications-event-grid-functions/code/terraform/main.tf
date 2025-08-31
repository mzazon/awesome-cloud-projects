# Azure Event Grid and Functions Infrastructure
# This configuration creates a complete event-driven notification system

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and configuration
locals {
  # Naming convention: prefix-purpose-suffix
  resource_suffix           = random_string.suffix.result
  resource_group_name      = "${var.resource_name_prefix}-${var.environment}-${local.resource_suffix}"
  event_grid_topic_name    = "topic-notifications-${local.resource_suffix}"
  function_app_name        = "func-processor-${local.resource_suffix}"
  storage_account_name     = "stg${local.resource_suffix}func"
  app_service_plan_name    = "asp-${var.resource_name_prefix}-${local.resource_suffix}"
  app_insights_name        = "ai-${var.resource_name_prefix}-${local.resource_suffix}"
  event_subscription_name  = "sub-event-processor"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    resource_group = local.resource_group_name
    created_date   = formatdate("YYYY-MM-DD", timestamp())
    recipe_name    = "simple-event-notifications-event-grid-functions"
  })
}

# Resource Group
# Container for all resources in this solution
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account for Function App
# Required for Azure Functions to store metadata and logs
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  
  # Network access rules for security
  network_rules {
    default_action = "Allow" # Set to "Deny" for production with specific IP ranges
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Application Insights for monitoring and logging
# Provides comprehensive observability for the Function App
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  
  # Workspace-based Application Insights (recommended)
  workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  tags = local.common_tags
}

# Log Analytics Workspace for Application Insights
# Centralized logging and monitoring workspace
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "law-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.application_insights_retention_days
  
  tags = local.common_tags
}

# App Service Plan for Function App
# Defines the compute resources for Azure Functions
resource "azurerm_service_plan" "main" {
  count = var.enable_function_app ? 1 : 0
  
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for event processing
# Serverless compute platform for executing event processing logic
resource "azurerm_linux_function_app" "main" {
  count = var.enable_function_app ? 1 : 0
  
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main[0].id
  
  # Storage account configuration for Function App metadata
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Function App configuration
  site_config {
    # Runtime configuration for Node.js
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # CORS configuration for web applications
    cors {
      allowed_origins = ["*"] # Restrict this in production
    }
    
    # Enable Application Insights integration
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  }
  
  # Application settings for Function App
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~${var.function_app_runtime_version}"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "functionTimeout"                = var.function_timeout_duration
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Event Grid specific settings
    "EVENTGRID_TOPIC_ENDPOINT" = azurerm_eventgrid_topic.main.endpoint
    "EVENTGRID_TOPIC_KEY"      = azurerm_eventgrid_topic.main.primary_access_key
  }
  
  # Function App identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # Ensure storage account is created before Function App
  depends_on = [azurerm_storage_account.function_storage]
}

# Event Grid Topic for custom events
# Fully managed event routing service for publishing and subscribing to events
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Input schema configuration for event format
  input_schema = var.event_grid_input_schema
  
  # Public network access configuration
  public_network_access_enabled = true
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Event Grid System Topic for Azure service events (optional)
# Enables subscription to Azure service events like storage account changes
resource "azurerm_eventgrid_system_topic" "storage_events" {
  name                   = "systopic-storage-${local.resource_suffix}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.function_storage.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  
  # Identity for secure access to Event Grid
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Event Grid Event Subscription
# Routes events from the custom topic to the Azure Function
resource "azurerm_eventgrid_event_subscription" "function_subscription" {
  count = var.enable_function_app ? 1 : 0
  
  name  = local.event_subscription_name
  scope = azurerm_eventgrid_topic.main.id
  
  # Azure Function webhook endpoint configuration
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.main[0].default_hostname}/runtime/webhooks/eventgrid?functionName=eventProcessor"
    
    # Additional webhook properties for reliability
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Event delivery schema matching the topic configuration
  event_delivery_schema = var.event_grid_input_schema == "CloudEventSchemaV1_0" ? "CloudEventSchemaV1_0" : "EventGridSchema"
  
  # Retry policy for failed event delivery
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440 # 24 hours in minutes
  }
  
  # Dead letter endpoint for failed events (optional)
  # Uncomment and configure for production scenarios
  # dead_letter_identity {
  #   type = "SystemAssigned"
  # }
  
  # Advanced filtering (optional)
  # Can filter events by subject, event type, or data fields
  advanced_filter {
    string_contains {
      key    = "subject"
      values = ["demo/", "system/", "user/"]
    }
  }
  
  # Labels for event subscription management
  labels = ["terraform", "demo", "event-processing"]
  
  depends_on = [azurerm_linux_function_app.main]
}

# Storage Account Event Subscription (optional)
# Demonstrates subscribing to Azure service events
resource "azurerm_eventgrid_event_subscription" "storage_subscription" {
  count = var.enable_function_app ? 1 : 0
  
  name  = "sub-storage-events"
  scope = azurerm_eventgrid_system_topic.storage_events.id
  
  # Azure Function webhook endpoint for storage events
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.main[0].default_hostname}/runtime/webhooks/eventgrid?functionName=storageEventProcessor"
  }
  
  # Filter for specific storage events
  included_event_types = [
    "Microsoft.Storage.BlobCreated",
    "Microsoft.Storage.BlobDeleted"
  ]
  
  # Retry policy for storage events
  retry_policy {
    max_delivery_attempts = 10
    event_time_to_live    = 720 # 12 hours in minutes
  }
  
  depends_on = [azurerm_linux_function_app.main]
}

# Role Assignment for Event Grid to Function App
# Grants Event Grid permission to invoke the Function App
resource "azurerm_role_assignment" "eventgrid_function_invoker" {
  count = var.enable_function_app ? 1 : 0
  
  scope                = azurerm_linux_function_app.main[0].id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_eventgrid_topic.main.identity[0].principal_id
}

# Role Assignment for Function App to Event Grid
# Allows Function App to publish events back to Event Grid if needed
resource "azurerm_role_assignment" "function_eventgrid_publisher" {
  count = var.enable_function_app ? 1 : 0
  
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.main[0].identity[0].principal_id
}

# Function App Slot (optional, for staging deployments)
# Enables blue-green deployments and testing in production scenarios
resource "azurerm_linux_function_app_slot" "staging" {
  count = var.enable_function_app && var.environment == "production" ? 1 : 0
  
  name            = "staging"
  function_app_id = azurerm_linux_function_app.main[0].id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Same configuration as production slot
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  }
  
  # Staging-specific app settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~${var.function_app_runtime_version}"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "ENVIRONMENT"                    = "staging"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
  }
  
  tags = merge(local.common_tags, { slot = "staging" })
}
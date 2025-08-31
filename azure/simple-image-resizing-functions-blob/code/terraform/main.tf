# Azure Simple Image Resizing Infrastructure
# This Terraform configuration creates a serverless image resizing solution using
# Azure Functions and Blob Storage with Event Grid triggers

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group
# Container for all resources related to the image resizing solution
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  
  tags = var.resource_tags
}

# Storage Account
# Stores original images, processed images, and Function App metadata
resource "azurerm_storage_account" "main" {
  name                = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Performance and replication configuration
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.blob_access_tier
  
  # Security and access configuration
  allow_nested_items_to_be_public = var.blob_public_access_enabled
  shared_access_key_enabled       = true
  
  # Enable blob versioning for better data protection
  blob_properties {
    versioning_enabled = true
    
    # Configure blob lifecycle management for cost optimization
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.resource_tags
}

# Storage Container for Original Images
# Container where users upload original images that trigger processing
resource "azurerm_storage_container" "original_images" {
  name                  = "original-images"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.blob_public_access_enabled ? "blob" : "private"
}

# Storage Container for Thumbnail Images
# Container for processed thumbnail images (150x150)
resource "azurerm_storage_container" "thumbnails" {
  name                  = "thumbnails"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.blob_public_access_enabled ? "blob" : "private"
}

# Storage Container for Medium Images
# Container for processed medium-sized images (800x600)
resource "azurerm_storage_container" "medium_images" {
  name                  = "medium-images"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.blob_public_access_enabled ? "blob" : "private"
}

# Log Analytics Workspace
# Centralized logging and monitoring for Function App
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days
  
  tags = var.resource_tags
}

# Application Insights
# Application performance monitoring and logging for Function App
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  workspace_id     = azurerm_log_analytics_workspace.main.id
  application_type = var.application_insights_type
  
  tags = var.resource_tags
}

# Service Plan for Function App
# Consumption plan provides serverless hosting with automatic scaling
resource "azurerm_service_plan" "main" {
  name                = "plan-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Consumption plan for serverless hosting
  os_type  = var.function_app_os_type
  sku_name = "Y1"
  
  tags = var.resource_tags
}

# Linux Function App
# Serverless compute platform for image processing logic
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function runtime configuration
  site_config {
    # Enable Application Insights monitoring
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    
    # Configure Node.js runtime
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable CORS for web applications
    cors {
      allowed_origins = ["*"]
    }
  }
  
  # Application settings for function configuration
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = "~${var.function_app_runtime_version}"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    
    # Storage connection strings
    "AzureWebJobsStorage"                        = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"  = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                       = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
    "StorageConnection"                          = azurerm_storage_account.main.primary_connection_string
    
    # Image processing configuration
    "THUMBNAIL_WIDTH"  = var.thumbnail_width
    "THUMBNAIL_HEIGHT" = var.thumbnail_height
    "MEDIUM_WIDTH"     = var.medium_width
    "MEDIUM_HEIGHT"    = var.medium_height
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Performance and reliability settings
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
  }
  
  # Configure identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.resource_tags
  
  # Ensure storage containers are created before Function App
  depends_on = [
    azurerm_storage_container.original_images,
    azurerm_storage_container.thumbnails,
    azurerm_storage_container.medium_images,
    azurerm_application_insights.main
  ]
}

# Event Grid System Topic
# Manages blob storage events for triggering image processing
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "evgt-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.main.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  
  tags = var.resource_tags
}

# Event Grid Subscription
# Routes blob creation events to Function App for processing
resource "azurerm_eventgrid_event_subscription" "blob_trigger" {
  name  = "evgs-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  scope = azurerm_storage_account.main.id
  
  # Filter events to only blob creation in original-images container
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/original-images/blobs/"
  }
  
  # Only trigger on blob creation events
  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]
  
  # Configure Function App as the event destination
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/ImageResize"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Configure retry policy for failed events
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }
  
  # Configure dead letter destination for failed events
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "deadletter"
  }
  
  depends_on = [
    azurerm_eventgrid_system_topic.storage,
    azurerm_linux_function_app.main
  ]
}

# Dead Letter Storage Container
# Container for events that failed processing after all retries
resource "azurerm_storage_container" "deadletter" {
  name                  = "deadletter"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Role Assignment for Function App
# Grants Function App permissions to read/write blobs in storage account
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment for Event Grid
# Grants Event Grid permissions to invoke Function App
resource "azurerm_role_assignment" "eventgrid_function" {
  scope                = azurerm_linux_function_app.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_eventgrid_system_topic.storage.identity[0].principal_id
}
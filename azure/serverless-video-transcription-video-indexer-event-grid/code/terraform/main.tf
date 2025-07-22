# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Storage Account for video uploads and results
resource "azurerm_storage_account" "video_storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.blob_access_tier
  
  # Security settings
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Blob properties
  blob_properties {
    # Enable soft delete for blobs
    dynamic "delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }
    
    # Enable versioning if specified
    versioning_enabled = var.enable_versioning
    
    # Container delete retention policy
    dynamic "container_delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }
  }
  
  tags = var.tags
}

# Storage containers for videos and results
resource "azurerm_storage_container" "videos" {
  name                  = "videos"
  storage_account_name  = azurerm_storage_account.video_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "results" {
  name                  = "results"
  storage_account_name  = azurerm_storage_account.video_storage.name
  container_access_type = "private"
}

# Storage lifecycle management policy
resource "azurerm_storage_management_policy" "lifecycle" {
  count              = var.storage_lifecycle_management_enabled ? 1 : 0
  storage_account_id = azurerm_storage_account.video_storage.id

  rule {
    name    = "video-lifecycle"
    enabled = true
    
    filters {
      prefix_match = ["videos/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.cool_storage_days
        tier_to_archive_after_days_since_modification_greater_than = var.archive_storage_days
        delete_after_days_since_modification_greater_than          = var.delete_storage_days
      }
    }
  }
  
  rule {
    name    = "results-lifecycle"
    enabled = true
    
    filters {
      prefix_match = ["results/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = var.cool_storage_days
        delete_after_days_since_modification_greater_than       = var.delete_storage_days
      }
    }
  }
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = 30
  tags                = var.tags
}

# Application Insights for Function App monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = var.application_insights_type
  tags                = var.tags
}

# Cosmos DB Account for metadata storage
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Serverless capacity mode
  capabilities {
    name = var.cosmos_enable_serverless ? "EnableServerless" : "EnableTable"
  }
  
  consistency_policy {
    consistency_level = var.cosmos_consistency_level
  }
  
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Enable automatic failover if specified
  enable_automatic_failover = var.cosmos_enable_automatic_failover
  
  tags = var.tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "video_analytics" {
  name                = "VideoAnalytics"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB SQL Container for video metadata
resource "azurerm_cosmosdb_sql_container" "video_metadata" {
  name                = "VideoMetadata"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.video_analytics.name
  partition_key_path  = "/videoId"
  
  # Indexing policy for optimal query performance
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

# Event Grid System Topic for blob storage events
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "egt-storage-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.video_storage.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  tags                   = var.tags
}

# Event Grid Custom Topic for Video Indexer events
resource "azurerm_eventgrid_topic" "video_indexer" {
  name                         = "egt-videoindexer-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  public_network_access_enabled = var.event_grid_enable_public_network_access
  local_auth_enabled           = var.event_grid_local_auth_enabled
  tags                         = var.tags
}

# App Service Plan for Function Apps
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = title(var.function_app_os_type)
  sku_name            = "Y1" # Consumption plan
  tags                = var.tags
}

# Function App for video processing
resource "azurerm_linux_function_app" "video_processor" {
  count               = var.function_app_os_type == "linux" ? 1 : 0
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.video_storage.name
  storage_account_access_key = azurerm_storage_account.video_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id
  
  site_config {
    always_on = var.function_app_always_on
    
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      python_version = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
      dotnet_version = var.function_app_runtime == "dotnet" ? var.function_app_runtime_version : null
      java_version = var.function_app_runtime == "java" ? var.function_app_runtime_version : null
    }
    
    # CORS configuration for potential web interfaces
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
  }
  
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"         = var.function_app_runtime
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
    "FUNCTIONS_EXTENSION_VERSION"      = "~4"
    
    # Storage connection
    "STORAGE_CONNECTION_STRING"        = azurerm_storage_account.video_storage.primary_connection_string
    
    # Cosmos DB connection
    "COSMOS_CONNECTION_STRING"         = azurerm_cosmosdb_account.main.primary_sql_connection_string
    
    # Video Indexer configuration
    "VIDEO_INDEXER_ACCOUNT_ID"         = var.video_indexer_account_id
    "VIDEO_INDEXER_API_KEY"            = var.video_indexer_api_key
    "VIDEO_INDEXER_LOCATION"           = var.video_indexer_location
    
    # Event Grid configuration
    "EVENT_GRID_TOPIC_ENDPOINT"        = azurerm_eventgrid_topic.video_indexer.endpoint
    "EVENT_GRID_TOPIC_KEY"             = azurerm_eventgrid_topic.video_indexer.primary_access_key
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY"   = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Additional settings for optimal performance
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.video_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE"             = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  }
  
  tags = var.tags
}

# Windows Function App (alternative if Windows is selected)
resource "azurerm_windows_function_app" "video_processor" {
  count               = var.function_app_os_type == "windows" ? 1 : 0
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.video_storage.name
  storage_account_access_key = azurerm_storage_account.video_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id
  
  site_config {
    always_on = var.function_app_always_on
    
    application_stack {
      node_version = var.function_app_runtime == "node" ? "~${var.function_app_runtime_version}" : null
      python_version = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
      dotnet_version = var.function_app_runtime == "dotnet" ? "v${var.function_app_runtime_version}" : null
      java_version = var.function_app_runtime == "java" ? var.function_app_runtime_version : null
    }
  }
  
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"         = var.function_app_runtime
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
    "FUNCTIONS_EXTENSION_VERSION"      = "~4"
    
    # Storage connection
    "STORAGE_CONNECTION_STRING"        = azurerm_storage_account.video_storage.primary_connection_string
    
    # Cosmos DB connection
    "COSMOS_CONNECTION_STRING"         = azurerm_cosmosdb_account.main.primary_sql_connection_string
    
    # Video Indexer configuration
    "VIDEO_INDEXER_ACCOUNT_ID"         = var.video_indexer_account_id
    "VIDEO_INDEXER_API_KEY"            = var.video_indexer_api_key
    "VIDEO_INDEXER_LOCATION"           = var.video_indexer_location
    
    # Event Grid configuration
    "EVENT_GRID_TOPIC_ENDPOINT"        = azurerm_eventgrid_topic.video_indexer.endpoint
    "EVENT_GRID_TOPIC_KEY"             = azurerm_eventgrid_topic.video_indexer.primary_access_key
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY"   = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
  }
  
  tags = var.tags
}

# Event Grid Subscription for blob uploads (triggers upload processor function)
resource "azurerm_eventgrid_event_subscription" "blob_upload" {
  name  = "video-upload-subscription"
  scope = azurerm_eventgrid_system_topic.storage.id
  
  azure_function_endpoint {
    function_id = var.function_app_os_type == "linux" ? "${azurerm_linux_function_app.video_processor[0].id}/functions/ProcessVideoUpload" : "${azurerm_windows_function_app.video_processor[0].id}/functions/ProcessVideoUpload"
  }
  
  included_event_types = ["Microsoft.Storage.BlobCreated"]
  
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/videos/"
  }
  
  depends_on = [
    azurerm_linux_function_app.video_processor,
    azurerm_windows_function_app.video_processor
  ]
}

# Event Grid Subscription for Video Indexer results (triggers results processor function)
resource "azurerm_eventgrid_event_subscription" "video_results" {
  name  = "video-results-subscription"
  scope = azurerm_eventgrid_topic.video_indexer.id
  
  azure_function_endpoint {
    function_id = var.function_app_os_type == "linux" ? "${azurerm_linux_function_app.video_processor[0].id}/functions/ProcessVideoResults" : "${azurerm_windows_function_app.video_processor[0].id}/functions/ProcessVideoResults"
  }
  
  included_event_types = ["VideoIndexer.VideoProcessed", "VideoIndexer.VideoIndexingComplete"]
  
  depends_on = [
    azurerm_linux_function_app.video_processor,
    azurerm_windows_function_app.video_processor
  ]
}

# Role assignment for Function App to access storage
resource "azurerm_role_assignment" "function_storage_contributor" {
  scope                = azurerm_storage_account.video_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.function_app_os_type == "linux" ? azurerm_linux_function_app.video_processor[0].identity[0].principal_id : azurerm_windows_function_app.video_processor[0].identity[0].principal_id
  
  depends_on = [
    azurerm_linux_function_app.video_processor,
    azurerm_windows_function_app.video_processor
  ]
}

# Role assignment for Function App to access Cosmos DB
resource "azurerm_role_assignment" "function_cosmos_contributor" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = var.function_app_os_type == "linux" ? azurerm_linux_function_app.video_processor[0].identity[0].principal_id : azurerm_windows_function_app.video_processor[0].identity[0].principal_id
  
  depends_on = [
    azurerm_linux_function_app.video_processor,
    azurerm_windows_function_app.video_processor
  ]
}

# Enable system assigned identity for Function App
resource "azurerm_linux_function_app" "video_processor_identity" {
  count = var.function_app_os_type == "linux" ? 1 : 0
  
  # This block ensures the Function App has a system assigned identity
  identity {
    type = "SystemAssigned"
  }
  
  # Reference the existing Function App resource
  name                = azurerm_linux_function_app.video_processor[0].name
  resource_group_name = azurerm_linux_function_app.video_processor[0].resource_group_name
  location            = azurerm_linux_function_app.video_processor[0].location
  service_plan_id     = azurerm_linux_function_app.video_processor[0].service_plan_id
  
  storage_account_name       = azurerm_linux_function_app.video_processor[0].storage_account_name
  storage_account_access_key = azurerm_linux_function_app.video_processor[0].storage_account_access_key
  
  site_config {
    always_on = azurerm_linux_function_app.video_processor[0].site_config[0].always_on
    
    application_stack {
      node_version   = azurerm_linux_function_app.video_processor[0].site_config[0].application_stack[0].node_version
      python_version = azurerm_linux_function_app.video_processor[0].site_config[0].application_stack[0].python_version
      dotnet_version = azurerm_linux_function_app.video_processor[0].site_config[0].application_stack[0].dotnet_version
      java_version   = azurerm_linux_function_app.video_processor[0].site_config[0].application_stack[0].java_version
    }
  }
  
  app_settings = azurerm_linux_function_app.video_processor[0].app_settings
  
  tags = var.tags
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to app_settings as they are managed by the original resource
      app_settings,
      site_config,
    ]
  }
}

# Enable system assigned identity for Windows Function App
resource "azurerm_windows_function_app" "video_processor_identity" {
  count = var.function_app_os_type == "windows" ? 1 : 0
  
  # This block ensures the Function App has a system assigned identity
  identity {
    type = "SystemAssigned"
  }
  
  # Reference the existing Function App resource attributes
  name                = azurerm_windows_function_app.video_processor[0].name
  resource_group_name = azurerm_windows_function_app.video_processor[0].resource_group_name
  location            = azurerm_windows_function_app.video_processor[0].location
  service_plan_id     = azurerm_windows_function_app.video_processor[0].service_plan_id
  
  storage_account_name       = azurerm_windows_function_app.video_processor[0].storage_account_name
  storage_account_access_key = azurerm_windows_function_app.video_processor[0].storage_account_access_key
  
  site_config {
    always_on = azurerm_windows_function_app.video_processor[0].site_config[0].always_on
    
    application_stack {
      node_version   = azurerm_windows_function_app.video_processor[0].site_config[0].application_stack[0].node_version
      python_version = azurerm_windows_function_app.video_processor[0].site_config[0].application_stack[0].python_version
      dotnet_version = azurerm_windows_function_app.video_processor[0].site_config[0].application_stack[0].dotnet_version
      java_version   = azurerm_windows_function_app.video_processor[0].site_config[0].application_stack[0].java_version
    }
  }
  
  app_settings = azurerm_windows_function_app.video_processor[0].app_settings
  
  tags = var.tags
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to app_settings as they are managed by the original resource
      app_settings,
      site_config,
    ]
  }
}
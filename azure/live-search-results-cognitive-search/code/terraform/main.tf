# main.tf
# Main Terraform configuration for Azure real-time search application

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed names and configurations
locals {
  # Combine prefix with random suffix for unique naming
  name_suffix = var.prefix != "" ? "${var.prefix}${random_string.suffix.result}" : random_string.suffix.result
  
  # Resource names with consistent naming convention
  search_service_name      = "search-${local.name_suffix}"
  signalr_service_name     = "signalr-${local.name_suffix}"
  storage_account_name     = "storage${local.name_suffix}"
  function_app_name        = "func-${local.name_suffix}"
  cosmos_account_name      = "cosmos-${local.name_suffix}"
  event_grid_topic_name    = "topic-${local.name_suffix}"
  app_service_plan_name    = "plan-${local.name_suffix}"
  app_insights_name        = "insights-${local.name_suffix}"
  log_analytics_name       = "logs-${local.name_suffix}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    DeployedBy = "terraform"
    CreatedAt  = timestamp()
  })
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Create the main resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

#------------------------------------------------------------
# Log Analytics Workspace for centralized logging
#------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Application Insights for monitoring and diagnostics
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

#------------------------------------------------------------
# Azure Cognitive Search Service
#------------------------------------------------------------

resource "azurerm_search_service" "main" {
  name                          = local.search_service_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                          = var.search_service_sku
  replica_count                = var.search_replica_count
  partition_count              = var.search_partition_count
  public_network_access_enabled = !var.enable_private_endpoints
  
  # Enable semantic search capabilities (available in Standard tier and above)
  semantic_search_sku = var.search_service_sku != "free" && var.search_service_sku != "basic" ? "standard" : null
  
  tags = local.common_tags
}

#------------------------------------------------------------
# Azure SignalR Service
#------------------------------------------------------------

resource "azurerm_signalr_service" "main" {
  name                = local.signalr_service_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  sku {
    name     = var.signalr_sku
    capacity = var.signalr_capacity
  }
  
  service_mode                   = var.signalr_service_mode
  public_network_access_enabled  = !var.enable_private_endpoints
  
  # CORS configuration for web clients
  cors {
    allowed_origins = ["*"]  # In production, specify your domains
  }
  
  # Enable upstream authentication for serverless mode
  upstream_endpoint {
    category_pattern = "*"
    event_pattern    = "*"
    hub_pattern      = "*"
    url_template     = "https://${local.function_app_name}.azurewebsites.net/runtime/webhooks/signalr"
  }
  
  tags = local.common_tags
}

#------------------------------------------------------------
# Azure Cosmos DB Account and Database
#------------------------------------------------------------

resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  enable_free_tier    = var.cosmos_enable_free_tier
  
  consistency_policy {
    consistency_level       = var.cosmos_consistency_level
    max_interval_in_seconds = var.cosmos_consistency_level == "BoundedStaleness" ? 300 : null
    max_staleness_prefix    = var.cosmos_consistency_level == "BoundedStaleness" ? 100000 : null
  }
  
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Enable automatic failover
  enable_automatic_failover = true
  
  # Enable change feed for real-time updates
  capabilities {
    name = "EnableServerless"
  }
  
  # Public access configuration
  public_network_access_enabled = !var.enable_private_endpoints
  
  # IP firewall rules
  dynamic "ip_range_filter" {
    for_each = var.enable_private_endpoints ? [] : var.allowed_ip_ranges
    content {
      ip_range_filter = ip_range_filter.value
    }
  }
  
  tags = local.common_tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "SearchDatabase"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB SQL Container for Products
resource "azurerm_cosmosdb_sql_container" "products" {
  name                  = "Products"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/category"
  partition_key_version = 1
  throughput            = var.cosmos_throughput
  
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
  
  # Unique key constraints
  unique_key {
    paths = ["/id"]
  }
}

#------------------------------------------------------------
# Azure Storage Account
#------------------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = var.storage_account_tier
  account_replication_type        = var.storage_replication_type
  account_kind                    = "StorageV2"
  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties for security
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  tags = local.common_tags
}

#------------------------------------------------------------
# Event Grid Topic and System Topic
#------------------------------------------------------------

resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable authentication using managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# System topic for storage account events
resource "azurerm_eventgrid_system_topic" "storage" {
  count               = var.enable_event_grid_system_topic ? 1 : 0
  name                = "storage-events-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  source_arm_resource_id = azurerm_storage_account.main.id
  topic_type          = "Microsoft.Storage.StorageAccounts"
  
  tags = local.common_tags
}

#------------------------------------------------------------
# Azure Function App and App Service Plan
#------------------------------------------------------------

resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = title(var.function_app_os_type)
  sku_name            = "Y1"  # Consumption plan for serverless
  
  tags = local.common_tags
}

resource "azurerm_linux_function_app" "main" {
  count               = var.function_app_os_type == "linux" ? 1 : 0
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id
  
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable CORS for web clients
    cors {
      allowed_origins = ["*"]  # In production, specify your domains
    }
  }
  
  # Application settings for service connections
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"             = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"         = "~${var.function_app_runtime_version}"
    "APPINSIGHTS_INSTRUMENTATIONKEY"       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Azure Cognitive Search configuration
    "SearchEndpoint"    = "https://${azurerm_search_service.main.name}.search.windows.net"
    "SearchAdminKey"    = azurerm_search_service.main.primary_key
    
    # Azure SignalR Service configuration
    "SignalRConnection" = azurerm_signalr_service.main.primary_connection_string
    
    # Azure Cosmos DB configuration
    "CosmosDBConnection" = azurerm_cosmosdb_account.main.primary_sql_connection_string
    
    # Azure Event Grid configuration
    "EventGridEndpoint" = azurerm_eventgrid_topic.main.endpoint
    "EventGridKey"      = azurerm_eventgrid_topic.main.primary_access_key
    
    # Additional Function App settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                     = "${local.function_app_name}-content"
    "AzureWebJobsStorage"                      = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"                 = "1"
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

resource "azurerm_windows_function_app" "main" {
  count               = var.function_app_os_type == "windows" ? 1 : 0
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id
  
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable CORS for web clients
    cors {
      allowed_origins = ["*"]  # In production, specify your domains
    }
  }
  
  # Application settings for service connections
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"             = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"         = "~${var.function_app_runtime_version}"
    "APPINSIGHTS_INSTRUMENTATIONKEY"       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Azure Cognitive Search configuration
    "SearchEndpoint"    = "https://${azurerm_search_service.main.name}.search.windows.net"
    "SearchAdminKey"    = azurerm_search_service.main.primary_key
    
    # Azure SignalR Service configuration
    "SignalRConnection" = azurerm_signalr_service.main.primary_connection_string
    
    # Azure Cosmos DB configuration
    "CosmosDBConnection" = azurerm_cosmosdb_account.main.primary_sql_connection_string
    
    # Azure Event Grid configuration
    "EventGridEndpoint" = azurerm_eventgrid_topic.main.endpoint
    "EventGridKey"      = azurerm_eventgrid_topic.main.primary_access_key
    
    # Additional Function App settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                     = "${local.function_app_name}-content"
    "AzureWebJobsStorage"                      = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"                 = "1"
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

#------------------------------------------------------------
# RBAC Role Assignments for Function App Managed Identity
#------------------------------------------------------------

# Get the Function App managed identity
locals {
  function_app_principal_id = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
}

# Grant Function App access to Cosmos DB
resource "azurerm_cosmosdb_sql_role_assignment" "function_app" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"  # Cosmos DB Built-in Data Contributor
  principal_id        = local.function_app_principal_id
  scope               = azurerm_cosmosdb_account.main.id
}

# Grant Function App access to Event Grid Topic
resource "azurerm_role_assignment" "function_app_eventgrid" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = local.function_app_principal_id
}

# Grant Function App access to SignalR Service
resource "azurerm_role_assignment" "function_app_signalr" {
  scope                = azurerm_signalr_service.main.id
  role_definition_name = "SignalR App Server"
  principal_id         = local.function_app_principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_app_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.function_app_principal_id
}

#------------------------------------------------------------
# Event Grid Subscriptions
#------------------------------------------------------------

# Event Grid subscription for Cosmos DB changes to trigger index updates
resource "azurerm_eventgrid_event_subscription" "cosmos_to_function" {
  name  = "cosmos-to-index-update"
  scope = azurerm_cosmosdb_account.main.id
  
  azure_function_endpoint {
    function_id                       = var.function_app_os_type == "linux" ? "${azurerm_linux_function_app.main[0].id}/functions/IndexUpdateFunction" : "${azurerm_windows_function_app.main[0].id}/functions/IndexUpdateFunction"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }
  
  included_event_types = [
    "Microsoft.DocumentDB.DatabaseAccountCreated",
    "Microsoft.DocumentDB.DatabaseAccountModified"
  ]
  
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440  # 24 hours
  }
}

# Event Grid subscription for search updates to trigger notifications
resource "azurerm_eventgrid_event_subscription" "search_to_notification" {
  name  = "search-to-notification"
  scope = azurerm_eventgrid_topic.main.id
  
  azure_function_endpoint {
    function_id                       = var.function_app_os_type == "linux" ? "${azurerm_linux_function_app.main[0].id}/functions/NotificationFunction" : "${azurerm_windows_function_app.main[0].id}/functions/NotificationFunction"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }
  
  subject_filter {
    subject_begins_with = "products/"
  }
  
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440  # 24 hours
  }
}

#------------------------------------------------------------
# Private Endpoints (optional)
#------------------------------------------------------------

# Create private endpoints if enabled
resource "azurerm_private_endpoint" "search" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_search_service.main.name}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "${azurerm_search_service.main.name}-psc"
    private_connection_resource_id = azurerm_search_service.main.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

resource "azurerm_private_endpoint" "signalr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_signalr_service.main.name}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "${azurerm_signalr_service.main.name}-psc"
    private_connection_resource_id = azurerm_signalr_service.main.id
    subresource_names              = ["signalr"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

resource "azurerm_private_endpoint" "cosmos" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${azurerm_cosmosdb_account.main.name}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "${azurerm_cosmosdb_account.main.name}-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

#------------------------------------------------------------
# Virtual Network for Private Endpoints (optional)
#------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${local.name_suffix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

resource "azurerm_subnet" "private_endpoints" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]
  
  # Disable network policies for private endpoints
  private_endpoint_network_policies_enabled = false
}

#------------------------------------------------------------
# Diagnostic Settings for Monitoring
#------------------------------------------------------------

# Diagnostic settings for Cognitive Search
resource "azurerm_monitor_diagnostic_setting" "search" {
  count                      = var.enable_application_insights ? 1 : 0
  name                       = "search-diagnostics"
  target_resource_id         = azurerm_search_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "OperationLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for SignalR Service
resource "azurerm_monitor_diagnostic_setting" "signalr" {
  count                      = var.enable_application_insights ? 1 : 0
  name                       = "signalr-diagnostics"
  target_resource_id         = azurerm_signalr_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "AllLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Cosmos DB
resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  count                      = var.enable_application_insights ? 1 : 0
  name                       = "cosmos-diagnostics"
  target_resource_id         = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "DataPlaneRequests"
  }
  
  enabled_log {
    category = "QueryRuntimeStatistics"
  }
  
  metric {
    category = "Requests"
    enabled  = true
  }
}
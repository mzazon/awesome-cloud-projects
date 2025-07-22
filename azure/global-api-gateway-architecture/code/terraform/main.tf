# Generate random suffix for globally unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Log Analytics workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Create Application Insights for distributed tracing
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# Create Cosmos DB account with multi-region configuration
resource "azurerm_cosmosdb_account" "main" {
  name                          = "cosmos-${var.project_name}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  enable_free_tier              = var.cosmos_enable_free_tier
  enable_multiple_write_locations = var.cosmos_enable_multi_region_writes
  enable_automatic_failover     = true
  
  # Consistency policy
  consistency_policy {
    consistency_level       = var.cosmos_consistency_level
    max_interval_in_seconds = var.cosmos_consistency_level == "BoundedStaleness" ? 300 : null
    max_staleness_prefix    = var.cosmos_consistency_level == "BoundedStaleness" ? 100000 : null
  }
  
  # Primary region configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = true
  }
  
  # Secondary regions configuration
  dynamic "geo_location" {
    for_each = var.secondary_regions
    content {
      location          = geo_location.value
      failover_priority = geo_location.key + 1
      zone_redundant    = true
    }
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
  
  # Lifecycle management to prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}

# Create Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "api_configuration" {
  name                = "APIConfiguration"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Create Cosmos DB SQL Container for Rate Limits
resource "azurerm_cosmosdb_sql_container" "rate_limits" {
  name                = "RateLimits"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.api_configuration.name
  partition_key_path  = "/apiId"
  throughput          = var.cosmos_throughput
  
  # Configure indexing policy for optimal performance
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Configure default TTL for automatic cleanup of old rate limit data
  default_ttl = 3600  # 1 hour
}

# Create Cosmos DB SQL Container for API Configuration
resource "azurerm_cosmosdb_sql_container" "api_config" {
  name                = "APIConfig"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.api_configuration.name
  partition_key_path  = "/configType"
  throughput          = 1000  # Lower throughput for configuration data
  
  # Configure indexing policy
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

# Create API Management instance
resource "azurerm_api_management" "main" {
  name                = "apim-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "${var.apim_sku_name}_${var.apim_sku_capacity}"
  
  # Enable system-assigned managed identity
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }
  
  # Configure client certificate if enabled
  client_certificate_enabled = var.enable_client_certificate
  
  # Configure virtual network integration if specified
  virtual_network_type = var.virtual_network_type
  
  tags = var.tags
  
  # This resource takes a long time to create
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Add secondary regions to API Management
resource "azurerm_api_management_region" "secondary" {
  count = length(var.secondary_regions)
  
  api_management_id = azurerm_api_management.main.id
  location          = var.secondary_regions[count.index]
  capacity          = var.apim_sku_capacity
  zone_redundant    = var.apim_enable_zone_redundancy
  
  tags = var.tags
  
  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}

# Wait for API Management deployment to complete before configuring RBAC
resource "time_sleep" "wait_for_apim" {
  depends_on = [azurerm_api_management.main]
  create_duration = "60s"
}

# Grant Cosmos DB access to API Management managed identity
resource "azurerm_cosmosdb_sql_role_assignment" "apim_cosmos_access" {
  count = var.cosmos_enable_rbac && var.enable_managed_identity ? 1 : 0
  
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Built-in Data Contributor
  principal_id        = azurerm_api_management.main.identity[0].principal_id
  scope               = "${azurerm_cosmosdb_account.main.id}/dbs/${azurerm_cosmosdb_sql_database.api_configuration.name}"
  
  depends_on = [time_sleep.wait_for_apim]
}

# Create a sample API in API Management
resource "azurerm_api_management_api" "weather_api" {
  name                = "weather-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Global Weather API"
  path                = "weather"
  protocols           = ["https"]
  subscription_required = true
  
  # Import OpenAPI specification
  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.1"
      info = {
        title   = "Global Weather API"
        version = "1.0"
      }
      servers = [
        {
          url = "https://api.openweathermap.org/data/2.5"
        }
      ]
      paths = {
        "/weather" = {
          get = {
            summary = "Get current weather"
            parameters = [
              {
                name     = "q"
                in       = "query"
                required = true
                schema = {
                  type = "string"
                }
              }
            ]
            responses = {
              "200" = {
                description = "Success"
              }
            }
          }
        }
      }
    })
  }
  
  depends_on = [azurerm_api_management.main]
}

# Create a global rate limiting policy using Cosmos DB
resource "azurerm_api_management_api_policy" "weather_api_policy" {
  api_name            = azurerm_api_management_api.weather_api.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  xml_content = templatefile("${path.module}/templates/rate-limit-policy.xml.tpl", {
    cosmos_endpoint = azurerm_cosmosdb_account.main.endpoint
    database_name   = azurerm_cosmosdb_sql_database.api_configuration.name
    container_name  = azurerm_cosmosdb_sql_container.rate_limits.name
  })
  
  depends_on = [
    azurerm_api_management_api.weather_api,
    azurerm_cosmosdb_sql_role_assignment.apim_cosmos_access
  ]
}

# Create Traffic Manager profile for global load balancing
resource "azurerm_traffic_manager_profile" "main" {
  name                   = "tm-${var.project_name}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  traffic_routing_method = var.traffic_manager_routing_method
  
  dns_config {
    relative_name = "tm-${var.project_name}-${random_string.suffix.result}"
    ttl           = var.traffic_manager_ttl
  }
  
  monitor_config {
    protocol                     = "HTTPS"
    port                        = 443
    path                        = "/status-0123456789abcdef"
    interval_in_seconds         = 30
    timeout_in_seconds          = 10
    tolerated_number_of_failures = 3
  }
  
  tags = var.tags
}

# Create Traffic Manager endpoint for primary region
resource "azurerm_traffic_manager_azure_endpoint" "primary" {
  name               = "endpoint-${replace(lower(var.location), " ", "-")}"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target_resource_id = azurerm_api_management.main.id
  priority           = 1
  weight             = 100
  
  depends_on = [azurerm_api_management.main]
}

# Create Traffic Manager endpoints for secondary regions
resource "azurerm_traffic_manager_external_endpoint" "secondary" {
  count = length(var.secondary_regions)
  
  name       = "endpoint-${replace(lower(var.secondary_regions[count.index]), " ", "-")}"
  profile_id = azurerm_traffic_manager_profile.main.id
  target     = "${azurerm_api_management.main.name}-${replace(lower(var.secondary_regions[count.index]), " ", "")}-01.regional.azure-api.net"
  priority   = count.index + 2
  weight     = 100
  
  geo_mappings = var.traffic_manager_routing_method == "Geographic" ? [
    var.secondary_regions[count.index] == "West Europe" ? "GQ" : 
    var.secondary_regions[count.index] == "Southeast Asia" ? "GU" : "GH"
  ] : []
  
  depends_on = [azurerm_api_management_region.secondary]
}

# Configure diagnostic settings for API Management
resource "azurerm_monitor_diagnostic_setting" "apim_diagnostics" {
  name                       = "apim-diagnostics"
  target_resource_id         = azurerm_api_management.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = ["GatewayLogs", "WebSocketConnectionLogs"]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Cosmos DB
resource "azurerm_monitor_diagnostic_setting" "cosmos_diagnostics" {
  name                       = "cosmos-diagnostics"
  target_resource_id         = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = ["DataPlaneRequests", "PartitionKeyStatistics", "PartitionKeyRUConsumption"]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "Requests"
    enabled  = true
  }
}

# Create Application Insights logger in API Management
resource "azurerm_api_management_logger" "app_insights" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appinsights-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  application_insights {
    connection_string = azurerm_application_insights.main[0].connection_string
  }
  
  depends_on = [azurerm_api_management.main]
}

# Create alert rules for monitoring
resource "azurerm_monitor_metric_alert" "apim_failed_requests" {
  name                = "apim-failed-requests-${var.project_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_api_management.main.id]
  description         = "Alert when API Management has high number of failed requests"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.ApiManagement/service"
    metric_name      = "FailedRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 100
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = var.tags
}

# Create action group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project_name}-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "apim-alerts"
  
  email_receiver {
    name          = "admin"
    email_address = var.apim_publisher_email
  }
  
  tags = var.tags
}


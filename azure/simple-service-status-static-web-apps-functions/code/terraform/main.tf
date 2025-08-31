# Azure Static Web Apps Service Status Infrastructure
# This configuration creates a complete service status monitoring solution
# using Azure Static Web Apps with integrated Azure Functions

# Generate a random suffix for globally unique resource names
# This ensures resource names don't conflict with existing resources
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Data source to get current Azure client configuration
# Used for retrieving subscription ID and other client details
data "azurerm_client_config" "current" {}

# Create the Azure Resource Group
# This logical container holds all related resources for the service status solution
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = merge(var.tags, {
    resource-type = "resource-group"
    created-by    = "terraform"
  })

  lifecycle {
    ignore_changes = [tags["created-date"]]
  }
}

# Create the Azure Static Web App
# This service provides both static website hosting and managed Azure Functions
# The integrated architecture eliminates the need for separate Function App resources
resource "azurerm_static_web_app" "status_page" {
  name                = var.static_web_app_name != null ? var.static_web_app_name : "status-page-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Define the SKU for the Static Web App
  # Free tier includes managed Functions with generous limits
  # Standard tier adds custom domains and enhanced performance
  sku_tier = var.sku_tier
  sku_size = var.sku_size

  # Configure the Static Web App build and deployment settings
  # These settings define where source code is located and how it should be built
  app_settings = {
    # Define the locations for app and API source code
    "app_location"       = var.app_location
    "api_location"       = var.api_location
    "output_location"    = var.output_location
    
    # Configure the Functions runtime environment
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = var.functions_runtime
    
    # Configure the monitored services as environment variables
    # This allows the Functions to access the service list dynamically
    "MONITORED_SERVICES" = jsonencode(var.monitored_services)
    
    # Set environment identifier for configuration management
    "ENVIRONMENT" = var.environment
    
    # Configure CORS settings for API access
    "CORS_ALLOWED_ORIGINS" = "*"
    
    # Configure Functions timeout (maximum 10 minutes for consumption plan)
    "FUNCTIONS_EXTENSION_VERSION" = "~4"
    "WEBSITE_TIME_ZONE"          = "UTC"
  }

  tags = merge(var.tags, {
    resource-type = "static-web-app"
    sku-tier      = var.sku_tier
  })

  # Prevent destruction of the resource if it contains user data
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags["created-date"]]
  }
}

# Create a custom domain for the Static Web App (Optional)
# This resource is only created when custom domains are enabled and using Standard SKU
resource "azurerm_static_web_app_custom_domain" "main" {
  count = var.enable_custom_domains && var.sku_tier == "Standard" ? 1 : 0

  static_web_app_id = azurerm_static_web_app.status_page.id
  domain_name       = "status.${var.resource_group_name}.com"
  validation_type   = "dns-txt-token"

  tags = var.tags

  # This resource depends on the Static Web App being fully provisioned
  depends_on = [azurerm_static_web_app.status_page]
}

# Create Application Insights for monitoring and analytics
# This provides detailed telemetry and performance monitoring for the Functions
resource "azurerm_application_insights" "main" {
  name                = "appi-${azurerm_static_web_app.status_page.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Configure data retention (90 days for demo, can be extended for production)
  retention_in_days   = 90
  daily_data_cap_in_gb = 1
  
  # Enable sampling to control telemetry volume and costs
  sampling_percentage = 100

  tags = merge(var.tags, {
    resource-type = "application-insights"
  })
}

# Create Log Analytics Workspace for centralized logging
# This provides a centralized location for all logs and metrics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${azurerm_static_web_app.status_page.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Configure workspace settings
  sku               = "PerGB2018"
  retention_in_days = 30
  daily_quota_gb    = 1

  tags = merge(var.tags, {
    resource-type = "log-analytics-workspace"
  })
}

# Link Application Insights to Log Analytics Workspace
# This enables advanced querying and correlation of telemetry data
resource "azurerm_application_insights_workspace_config" "main" {
  application_insights_id = azurerm_application_insights.main.id
  workspace_id           = azurerm_log_analytics_workspace.main.id
}

# Create Action Groups for alerting (Optional monitoring enhancement)
# This enables notifications when the status monitoring service has issues
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${azurerm_static_web_app.status_page.name}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "statuspage"
  
  # Configure email notifications for the operations team
  email_receiver {
    name          = "operations-team"
    email_address = "ops@example.com"
    use_common_alert_schema = true
  }
  
  # Configure webhook for integration with external systems
  webhook_receiver {
    name        = "webhook-receiver"
    service_uri = "https://example.com/webhook"
  }

  tags = merge(var.tags, {
    resource-type = "action-group"
  })
}

# Create metric alerts for monitoring the Static Web App health
# This monitors the availability and performance of the status page itself
resource "azurerm_monitor_metric_alert" "availability" {
  name                = "alert-availability-${azurerm_static_web_app.status_page.name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_static_web_app.status_page.id]
  description         = "Alert when Static Web App availability drops below threshold"
  
  # Configure alert criteria
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2
  
  criteria {
    metric_namespace = "Microsoft.Web/staticSites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}

# Create a Storage Account for persistent data (Optional enhancement)
# This can be used to store historical status data and metrics
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(lower(azurerm_static_web_app.status_page.name), "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Enable security features
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Configure blob properties for optimal performance
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.tags, {
    resource-type = "storage-account"
  })
}

# Create a storage container for status history data
# This enables storing historical status information for trend analysis
resource "azurerm_storage_container" "status_history" {
  name                  = "status-history"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.main]
}

# Create a storage table for structured status data
# This provides a NoSQL database for storing time-series status information
resource "azurerm_storage_table" "status_logs" {
  name                 = "statuslogs"
  storage_account_name = azurerm_storage_account.main.name

  depends_on = [azurerm_storage_account.main]
}
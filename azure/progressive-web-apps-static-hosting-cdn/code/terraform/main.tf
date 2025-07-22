# Main Terraform configuration for Azure Progressive Web App infrastructure
# This configuration deploys a complete PWA solution with Static Web Apps, CDN, and Application Insights

# Generate a random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Define local values for consistent resource naming and tagging
locals {
  # Resource naming convention: {project_name}-{resource_type}-{environment}-{suffix}
  resource_suffix = random_string.suffix.result
  
  # Common resource names
  resource_group_name         = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  static_web_app_name        = "swa-${var.project_name}-${var.environment}-${local.resource_suffix}"
  cdn_profile_name           = "cdn-${var.project_name}-${var.environment}-${local.resource_suffix}"
  cdn_endpoint_name          = "cdne-${var.project_name}-${var.environment}-${local.resource_suffix}"
  application_insights_name  = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  log_analytics_workspace_name = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Progressive Web App"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create the resource group to contain all PWA resources
resource "azurerm_resource_group" "pwa" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for Application Insights
# This workspace provides centralized logging and monitoring capabilities
resource "azurerm_log_analytics_workspace" "pwa" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.pwa.location
  resource_group_name = azurerm_resource_group.pwa.name
  
  # Configure workspace settings
  sku               = "PerGB2018"
  retention_in_days = var.application_insights_retention_days
  
  # Enable daily quota and cap
  daily_quota_gb = 10
  
  tags = merge(local.common_tags, {
    ResourceType = "Log Analytics Workspace"
    Purpose      = "Application Insights Backend"
  })
}

# Create Application Insights for comprehensive PWA monitoring
# This provides real-time performance monitoring, user analytics, and error tracking
resource "azurerm_application_insights" "pwa" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.pwa.location
  resource_group_name = azurerm_resource_group.pwa.name
  workspace_id        = azurerm_log_analytics_workspace.pwa.id
  
  # Configure Application Insights for web applications
  application_type = "web"
  
  # Enable sampling to manage costs while maintaining visibility
  sampling_percentage = 100
  
  # Disable IP masking for better geographic insights
  disable_ip_masking = false
  
  # Enable local authentication for backward compatibility
  local_authentication_disabled = false
  
  tags = merge(local.common_tags, {
    ResourceType = "Application Insights"
    Purpose      = "PWA Performance Monitoring"
  })
}

# Create Azure Static Web App for PWA hosting
# This provides serverless hosting with integrated CI/CD and global distribution
resource "azurerm_static_web_app" "pwa" {
  name                = local.static_web_app_name
  resource_group_name = azurerm_resource_group.pwa.name
  location            = var.location
  
  # Configure the Static Web App SKU
  sku_tier = var.static_web_app_sku
  sku_size = var.static_web_app_sku
  
  # Configure source control integration (GitHub)
  dynamic "source_control" {
    for_each = var.github_repository_url != "" ? [1] : []
    content {
      repo_url                   = var.github_repository_url
      branch                     = var.github_branch
      manual_integration         = false
      use_mercurial             = false
      rollback_enabled          = true
      
      # Configure build settings for PWA
      build_config {
        build_command           = "npm run build"
        app_location           = var.app_location
        api_location           = var.api_location
        output_location        = var.output_location
      }
    }
  }
  
  # Configure app settings for PWA functionality
  app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.pwa.connection_string
    "WEBSITE_NODE_DEFAULT_VERSION"         = "18-lts"
    "WEBSITE_RUN_FROM_PACKAGE"            = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"      = "false"
    "ENABLE_ORYX_BUILD"                   = "false"
    "PWA_CACHE_STRATEGY"                  = "cache-first"
    "PWA_OFFLINE_FALLBACK"                = "/offline.html"
  }
  
  # Configure staging environments (only available with Standard SKU)
  preview_environments_enabled = var.enable_staging_environments && var.static_web_app_sku == "Standard"
  
  tags = merge(local.common_tags, {
    ResourceType = "Static Web App"
    Purpose      = "PWA Hosting"
  })
}

# Create CDN Profile for global content distribution
# This improves PWA performance through global edge caching
resource "azurerm_cdn_profile" "pwa" {
  name                = local.cdn_profile_name
  location            = azurerm_resource_group.pwa.location
  resource_group_name = azurerm_resource_group.pwa.name
  
  # Configure CDN SKU for optimal performance
  sku = var.cdn_sku
  
  tags = merge(local.common_tags, {
    ResourceType = "CDN Profile"
    Purpose      = "Global Content Distribution"
  })
}

# Create CDN Endpoint for the Static Web App
# This provides caching and global distribution for PWA assets
resource "azurerm_cdn_endpoint" "pwa" {
  name                = local.cdn_endpoint_name
  profile_name        = azurerm_cdn_profile.pwa.name
  location            = azurerm_resource_group.pwa.location
  resource_group_name = azurerm_resource_group.pwa.name
  
  # Configure origin to point to Static Web App
  origin {
    name       = "StaticWebApp"
    host_name  = azurerm_static_web_app.pwa.default_host_name
    http_port  = 80
    https_port = 443
  }
  
  # Enable compression for better performance
  is_compression_enabled = var.enable_compression
  
  # Configure compression content types for PWA assets
  content_types_to_compress = [
    "application/javascript",
    "application/json",
    "application/x-javascript",
    "text/css",
    "text/html",
    "text/javascript",
    "text/plain",
    "text/xml",
    "application/xml",
    "application/xml+rss",
    "image/svg+xml",
    "application/font-woff",
    "application/font-woff2"
  ]
  
  # Configure caching behavior for PWA assets
  delivery_rule {
    name  = "PWAAssetsCaching"
    order = 1
    
    # Match static assets (CSS, JS, images)
    conditions {
      url_path_condition {
        operator         = "BeginsWith"
        match_values     = ["/css/", "/js/", "/images/", "/fonts/"]
        transforms       = ["Lowercase"]
        negate_condition = false
      }
    }
    
    # Set cache expiration for static assets
    actions {
      cache_expiration_action {
        behavior = "Override"
        duration = "1.00:00:00"  # 1 day
      }
    }
  }
  
  # Configure caching for PWA manifest and service worker
  delivery_rule {
    name  = "PWAManifestCaching"
    order = 2
    
    # Match PWA-specific files
    conditions {
      url_file_extension_condition {
        operator         = "Equal"
        match_values     = ["json", "js"]
        transforms       = ["Lowercase"]
        negate_condition = false
      }
    }
    
    # Set shorter cache for dynamic PWA files
    actions {
      cache_expiration_action {
        behavior = "Override"
        duration = "0.01:00:00"  # 1 hour
      }
    }
  }
  
  # Configure HTTPS redirect for PWA security requirements
  delivery_rule {
    name  = "HTTPSRedirect"
    order = 3
    
    conditions {
      request_scheme_condition {
        operator         = "Equal"
        match_values     = ["HTTP"]
        negate_condition = false
      }
    }
    
    actions {
      url_redirect_action {
        redirect_type = "Found"
        protocol      = "Https"
      }
    }
  }
  
  # Configure custom domain if enabled
  dynamic "custom_domain" {
    for_each = var.enable_custom_domain && var.custom_domain_name != "" ? [1] : []
    content {
      name      = replace(var.custom_domain_name, ".", "-")
      host_name = var.custom_domain_name
    }
  }
  
  # Configure geo-filtering (optional)
  geo_filter {
    relative_path = "/"
    action        = "Allow"
    country_codes = ["US", "CA", "GB", "DE", "FR", "JP", "AU", "BR", "IN", "SG"]
  }
  
  # Configure origin host header
  origin_host_header = azurerm_static_web_app.pwa.default_host_name
  
  # Enable query string caching for better performance
  querystring_caching_behaviour = "IgnoreQueryString"
  
  # Configure optimization for web applications
  optimization_type = "GeneralWebDelivery"
  
  tags = merge(local.common_tags, {
    ResourceType = "CDN Endpoint"
    Purpose      = "PWA Content Delivery"
  })
}

# Create custom domain configuration for Static Web App (if enabled)
resource "azurerm_static_web_app_custom_domain" "pwa" {
  count = var.enable_custom_domain && var.custom_domain_name != "" ? 1 : 0
  
  static_web_app_id = azurerm_static_web_app.pwa.id
  domain_name       = var.custom_domain_name
  validation_type   = "cname-delegation"
  
  depends_on = [azurerm_cdn_endpoint.pwa]
}

# Create Function App for advanced PWA features (optional)
# This can be used for background processing, push notifications, etc.
resource "azurerm_service_plan" "pwa" {
  name                = "sp-${var.project_name}-${var.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.pwa.name
  location            = azurerm_resource_group.pwa.location
  
  # Configure for serverless consumption
  os_type  = "Linux"
  sku_name = "Y1"  # Consumption plan
  
  tags = merge(local.common_tags, {
    ResourceType = "Service Plan"
    Purpose      = "Function App Backend"
  })
}

# Create storage account for Function App
resource "azurerm_storage_account" "pwa_functions" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
  resource_group_name      = azurerm_resource_group.pwa.name
  location                 = azurerm_resource_group.pwa.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Enable secure transfer for security
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for PWA assets
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT", "DELETE"]
      allowed_origins    = var.allowed_origins
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Storage Account"
    Purpose      = "Function App Storage"
  })
}

# Create Function App for extended PWA functionality
resource "azurerm_linux_function_app" "pwa" {
  name                = "func-${var.project_name}-${var.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.pwa.name
  location            = azurerm_resource_group.pwa.location
  
  storage_account_name       = azurerm_storage_account.pwa_functions.name
  storage_account_access_key = azurerm_storage_account.pwa_functions.primary_access_key
  service_plan_id           = azurerm_service_plan.pwa.id
  
  # Configure Function App settings
  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.pwa.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.pwa.connection_string
    "FUNCTIONS_WORKER_RUNTIME"             = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"         = "~18"
    "WEBSITE_RUN_FROM_PACKAGE"            = "1"
    "AzureWebJobsDisableHomepage"         = "true"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.pwa_functions.primary_connection_string
    "WEBSITE_CONTENTSHARE"                = "pwa-functions-${local.resource_suffix}"
  }
  
  # Configure site configuration
  site_config {
    always_on = false  # Not needed for consumption plan
    
    # Configure CORS for PWA
    cors {
      allowed_origins     = var.allowed_origins
      support_credentials = true
    }
    
    # Configure application insights
    application_insights_key               = azurerm_application_insights.pwa.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.pwa.connection_string
    
    # Configure application stack
    application_stack {
      node_version = "18"
    }
  }
  
  # Configure identity for accessing other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Function App"
    Purpose      = "PWA Extended Functionality"
  })
}

# Create Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "pwa" {
  name                = "ag-${var.project_name}-${var.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.pwa.name
  short_name          = "PWAAlerts"
  
  # Configure email notifications
  email_receiver {
    name          = "PWA Admin"
    email_address = "admin@${var.project_name}.com"
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Action Group"
    Purpose      = "PWA Monitoring Alerts"
  })
}

# Create metric alerts for PWA performance monitoring
resource "azurerm_monitor_metric_alert" "pwa_response_time" {
  name                = "PWA Response Time Alert"
  resource_group_name = azurerm_resource_group.pwa.name
  scopes              = [azurerm_application_insights.pwa.id]
  
  description = "Alert when PWA response time exceeds threshold"
  severity    = 2
  frequency   = "PT1M"
  window_size = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/duration"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000  # 5 seconds
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.pwa.id
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Metric Alert"
    Purpose      = "PWA Performance Monitoring"
  })
}

# Create availability test for PWA uptime monitoring
resource "azurerm_application_insights_web_test" "pwa" {
  name                    = "PWA Availability Test"
  location                = azurerm_resource_group.pwa.location
  resource_group_name     = azurerm_resource_group.pwa.name
  application_insights_id = azurerm_application_insights.pwa.id
  
  kind                    = "ping"
  frequency               = 300  # 5 minutes
  timeout                 = 30   # 30 seconds
  enabled                 = true
  retry_enabled           = true
  
  geo_locations = [
    "us-ca-sjc-azr",  # US West (California)
    "us-tx-sn1-azr",  # US South Central (Texas)
    "us-il-ch1-azr",  # US Central (Illinois)
    "us-va-ash-azr",  # US East (Virginia)
    "us-fl-mia-edge", # US Southeast (Florida)
    "emea-nl-ams-azr", # Europe (Netherlands)
    "emea-gb-db3-azr", # Europe (UK)
    "apac-jp-kaw-edge", # Asia Pacific (Japan)
    "apac-sg-sin-azr",  # Asia Pacific (Singapore)
    "apac-hk-hkn-azr"   # Asia Pacific (Hong Kong)
  ]
  
  configuration = <<XML
<WebTest Name="PWA Availability Test" Id="ABD48585-0831-40CB-9069-682A6A7B2B9C" Enabled="True" CssProjectStructure="" CssIteration="" Timeout="30" WorkItemIds="" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010" Description="" CredentialUserName="" CredentialPassword="" PreAuthenticate="True" Proxy="default" StopOnError="False" RecordedResultFile="" ResultsLocale="">
  <Items>
    <Request Method="GET" Guid="a5f10126-e4cd-570d-961c-cea43999a200" Version="1.1" Url="https://${azurerm_static_web_app.pwa.default_host_name}" ThinkTime="0" Timeout="30" ParseDependentRequests="True" FollowRedirects="True" RecordResult="True" Cache="False" ResponseTimeGoal="0" Encoding="utf-8" ExpectedHttpStatusCode="200" ExpectedResponseUrl="" ReportingName="" IgnoreHttpStatusCode="False" />
  </Items>
</WebTest>
XML
  
  tags = merge(local.common_tags, {
    ResourceType = "Web Test"
    Purpose      = "PWA Availability Monitoring"
  })
}

# Wait for Static Web App to be fully provisioned
resource "time_sleep" "wait_for_static_web_app" {
  depends_on = [azurerm_static_web_app.pwa]
  
  create_duration = "60s"
}
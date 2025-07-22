# main.tf
# Main Terraform configuration for Azure Static Web Apps with Front Door WAF

# Generate random suffix for globally unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      Purpose     = "Secure Global Web Application"
      CreatedBy   = "Terraform"
      Recipe      = "securing-global-web-applications-with-azure-static-web-apps-and-azure-front-door-waf"
    },
    var.tags
  )
}

# Create Log Analytics Workspace for diagnostic logging (if enabled and not provided)
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_diagnostic_logs && var.log_analytics_workspace_name == null ? 1 : 0

  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = azurerm_resource_group.main.tags
}

# Data source for existing Log Analytics Workspace (if provided)
data "azurerm_log_analytics_workspace" "existing" {
  count = var.enable_diagnostic_logs && var.log_analytics_workspace_name != null ? 1 : 0

  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.main.name
}

# Create Azure Static Web App
resource "azurerm_static_web_app" "main" {
  name                = "swa-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_tier            = var.static_web_app_sku_tier
  sku_size            = var.static_web_app_sku_tier

  # Configuration for GitHub integration
  # Note: In production, you would typically configure this through the Azure portal or GitHub Actions
  # for proper authentication and webhook setup
  source_control {
    type   = "GitHub"
    repo   = var.static_web_app_source_repo
    branch = var.static_web_app_branch
  }

  # Build configuration
  app_settings = {
    "app_location"    = var.static_web_app_app_location
    "output_location" = var.static_web_app_output_location
  }

  tags = azurerm_resource_group.main.tags
}

# Create WAF Policy with comprehensive security rules
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                              = "wafpolicy${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.main.name
  sku_name                          = var.front_door_sku_name
  enabled                           = true
  mode                              = var.waf_mode
  redirect_url                      = "https://www.microsoft.com"
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("Access denied by Web Application Firewall")

  # Microsoft Default Rule Set (OWASP protection)
  dynamic "managed_rule" {
    for_each = var.enable_owasp_protection ? [1] : []
    content {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.1"
      action  = "Block"

      # Override specific rules if needed
      override {
        rule_group_name = "REQUEST-942-APPLICATION-ATTACK-SQLI"
        rule {
          rule_id = "942100"
          enabled = true
          action  = "Block"
        }
      }

      override {
        rule_group_name = "REQUEST-931-APPLICATION-ATTACK-RFI"
        rule {
          rule_id = "931130"
          enabled = true
          action  = "Block"
        }
      }
    }
  }

  # Bot Manager Rule Set for bot protection
  dynamic "managed_rule" {
    for_each = var.enable_bot_protection ? [1] : []
    content {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
      action  = "Block"

      # Override for known good bots
      override {
        rule_group_name = "GoodBots"
        rule {
          rule_id = "100100"
          enabled = true
          action  = "Allow"
        }
      }
    }
  }

  # Custom rate limiting rule
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 1
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = var.rate_limit_threshold
    type                           = "RateLimitRule"
    action                         = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0", "::/0"]
    }
  }

  # Geo-filtering rule for allowed countries
  custom_rule {
    name     = "GeoFilterRule"
    enabled  = true
    priority = 2
    type     = "MatchRule"
    action   = "Allow"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "GeoMatch"
      negation_condition = false
      match_values       = var.allowed_countries
    }
  }

  # Block requests from non-allowed countries
  custom_rule {
    name     = "BlockNonAllowedCountries"
    enabled  = true
    priority = 3
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "GeoMatch"
      negation_condition = true
      match_values       = var.allowed_countries
    }
  }

  tags = azurerm_resource_group.main.tags
}

# Create Front Door Profile
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "afd-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.front_door_sku_name

  response_timeout_seconds = 60

  tags = azurerm_resource_group.main.tags
}

# Create Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "endpoint-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  enabled                  = true

  tags = azurerm_resource_group.main.tags
}

# Create Origin Group for Static Web App
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "og-staticwebapp"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  # Health probe configuration
  health_probe {
    interval_in_seconds = var.health_probe_interval
    path                = var.health_probe_path
    protocol            = "Https"
    request_type        = "GET"
  }

  # Load balancing configuration
  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = var.successful_samples_required
  }
}

# Create Origin for Static Web App
resource "azurerm_cdn_frontdoor_origin" "main" {
  name                          = "origin-swa"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id

  enabled                        = true
  host_name                      = azurerm_static_web_app.main.default_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_static_web_app.main.default_host_name
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true

  # Private link configuration (for Premium tier Static Web Apps)
  # Uncomment if using Premium Static Web Apps with private endpoints
  # private_link {
  #   request_message        = "Please approve this private endpoint connection"
  #   target_type           = "sites"
  #   location              = azurerm_resource_group.main.location
  #   private_link_target_id = azurerm_static_web_app.main.id
  # }
}

# Create Route for Static Web App traffic
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "route-secure"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true

  # URL patterns to match
  patterns_to_match = ["/*"]

  # Supported protocols
  supported_protocols = ["Http", "Https"]

  # HTTPS redirect configuration
  https_redirect_enabled = var.enable_https_redirect

  # Origin forwarding protocol
  forwarding_protocol = var.forwarding_protocol

  # Link to default domain
  link_to_default_domain = true

  # Cache configuration for dynamic content
  cache {
    query_string_caching_behavior = "UseQueryString"
    query_strings                 = []
    compression_enabled           = var.enable_compression
    content_types_to_compress = [
      "application/eot",
      "application/font",
      "application/font-sfnt",
      "application/javascript",
      "application/json",
      "application/opentype",
      "application/otf",
      "application/pkcs7-mime",
      "application/truetype",
      "application/ttf",
      "application/vnd.ms-fontobject",
      "application/xhtml+xml",
      "application/xml",
      "application/xml+rss",
      "application/x-font-opentype",
      "application/x-font-truetype",
      "application/x-font-ttf",
      "application/x-httpd-cgi",
      "application/x-javascript",
      "application/x-mpegurl",
      "application/x-opentype",
      "application/x-otf",
      "application/x-perl",
      "application/x-ttf",
      "font/eot",
      "font/ttf",
      "font/otf",
      "font/opentype",
      "image/svg+xml",
      "text/css",
      "text/csv",
      "text/html",
      "text/javascript",
      "text/js",
      "text/plain",
      "text/richtext",
      "text/tab-separated-values",
      "text/xml",
      "text/x-script",
      "text/x-component",
      "text/x-java-source"
    ]
  }
}

# Create Rule Set for caching optimization
resource "azurerm_cdn_frontdoor_rule_set" "caching" {
  name                     = "ruleset-caching"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

# Create caching rule for static assets
resource "azurerm_cdn_frontdoor_rule" "cache_static" {
  depends_on = [azurerm_cdn_frontdoor_route.main]

  name                      = "rule-cache-static"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.caching.id
  order                     = 1
  behavior_on_match         = "Continue"

  # Conditions for static file extensions
  conditions {
    request_uri_condition {
      operator         = "Contains"
      negate_condition = false
      match_values     = [".css", ".js", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".woff", ".woff2", ".ttf", ".eot", ".ico"]
      transforms       = ["Lowercase"]
    }
  }

  # Actions to cache static assets
  actions {
    response_header_action {
      header_action = "Overwrite"
      header_name   = "Cache-Control"
      value         = "public, max-age=604800"
    }
  }

  actions {
    route_configuration_override_action {
      cache_duration                = var.static_cache_duration
      cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
      forwarding_protocol           = var.forwarding_protocol
      query_string_caching_behavior = "IgnoreQueryString"
      compression_enabled           = var.enable_compression
    }
  }
}

# Create Rule Set for compression
resource "azurerm_cdn_frontdoor_rule_set" "compression" {
  name                     = "ruleset-compression"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

# Create compression rule
resource "azurerm_cdn_frontdoor_rule" "compression" {
  depends_on = [azurerm_cdn_frontdoor_route.main]

  name                      = "rule-compression"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.compression.id
  order                     = 1
  behavior_on_match         = "Continue"

  # Conditions for compressible content
  conditions {
    request_header_condition {
      header_name      = "Accept-Encoding"
      operator         = "Contains"
      negate_condition = false
      match_values     = ["gzip"]
      transforms       = ["Lowercase"]
    }
  }

  # Actions to enable compression
  actions {
    response_header_action {
      header_action = "Overwrite"
      header_name   = "Content-Encoding"
      value         = "gzip"
    }
  }
}

# Associate WAF Policy with Front Door Endpoint
resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "security-policy-waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

# Diagnostic settings for Front Door (if enabled)
resource "azurerm_monitor_diagnostic_setting" "front_door" {
  count = var.enable_diagnostic_logs ? 1 : 0

  name                       = "diag-front-door"
  target_resource_id         = azurerm_cdn_frontdoor_profile.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_name != null ? data.azurerm_log_analytics_workspace.existing[0].id : azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Output important information for verification and integration
locals {
  # Generate configuration for Static Web App integration
  static_web_app_config = {
    networking = {
      allowedIpRanges = ["AzureFrontDoor.Backend"]
    }
    forwardingGateway = {
      requiredHeaders = {
        "X-Azure-FDID" = azurerm_cdn_frontdoor_profile.main.resource_guid
      }
      allowedForwardedHosts = [
        azurerm_cdn_frontdoor_endpoint.main.host_name
      ]
    }
    routes = [
      {
        route = "/.auth/*"
        headers = {
          "Cache-Control" = "no-store"
        }
      }
    ]
  }
}
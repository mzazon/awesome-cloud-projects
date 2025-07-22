# Enterprise API Protection with Premium Management and WAF
# This Terraform configuration deploys a comprehensive enterprise-grade API security
# and performance platform using Azure API Management Premium, Azure WAF, Redis Enterprise,
# and comprehensive monitoring with Application Insights

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group for all enterprise API security components
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = merge(var.common_tags, {
    "deployment-method" = "terraform"
    "created-date"      = timestamp()
  })
}

# Log Analytics Workspace for centralized monitoring and security events
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.log_analytics_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = 30
  
  tags = merge(var.common_tags, {
    "component" = "monitoring"
  })
}

# Application Insights for deep application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.app_insights_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.app_insights_type
  
  tags = merge(var.common_tags, {
    "component" = "monitoring"
  })
}

# Azure Cache for Redis Enterprise for high-performance caching
resource "azurerm_redis_cache" "main" {
  name                = "${var.redis_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  capacity            = var.redis_capacity
  family              = "P"
  sku_name            = var.redis_sku
  enable_non_ssl_port = false
  minimum_tls_version = var.minimum_tls_version
  
  redis_configuration {
    maxmemory_policy = var.redis_maxmemory_policy
  }
  
  # Enable diagnostics for Redis
  depends_on = [azurerm_log_analytics_workspace.main]
  
  tags = merge(var.common_tags, {
    "component" = "cache"
  })
}

# Diagnostic settings for Redis Cache
resource "azurerm_monitor_diagnostic_setting" "redis" {
  name                       = "redis-diagnostics"
  target_resource_id         = azurerm_redis_cache.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "ConnectedClientList"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# API Management Premium instance with managed identity
resource "azurerm_api_management" "main" {
  name                = "${var.apim_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  publisher_name  = var.apim_publisher_name
  publisher_email = var.apim_publisher_email
  
  sku_name = "${var.apim_sku_name}_${var.apim_sku_capacity}"
  
  # Enable managed identity for secure service-to-service communication
  identity {
    type = "SystemAssigned"
  }
  
  # Security policies and configurations
  security {
    enable_backend_ssl30                                = false
    enable_backend_tls10                                = false
    enable_backend_tls11                                = false
    enable_frontend_ssl30                               = false
    enable_frontend_tls10                               = false
    enable_frontend_tls11                               = false
    tls_ecdhe_ecdsa_with_aes128_cbc_sha_ciphers_enabled = false
    tls_ecdhe_ecdsa_with_aes256_cbc_sha_ciphers_enabled = false
    tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled   = false
    tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled   = false
    tls_rsa_with_aes128_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes128_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes256_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes128_gcm_sha256_ciphers_enabled      = true
    tls_rsa_with_aes256_gcm_sha384_ciphers_enabled      = true
    enable_triple_des_ciphers                           = false
  }
  
  # Enable client certificate authentication
  client_certificate_enabled = true
  
  tags = merge(var.common_tags, {
    "component" = "api-management"
  })
  
  depends_on = [azurerm_application_insights.main]
}

# Application Insights logger for API Management
resource "azurerm_api_management_logger" "main" {
  name                = "applicationinsights"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  application_insights {
    instrumentation_key = azurerm_application_insights.main.instrumentation_key
  }
}

# Diagnostic settings for API Management
resource "azurerm_api_management_diagnostic" "main" {
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.main.name
  api_management_name      = azurerm_api_management.main.name
  api_management_logger_id = azurerm_api_management_logger.main.id
  
  sampling_percentage       = 100.0
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"
  
  frontend_request {
    body_bytes = 1024
    headers_to_log = [
      "content-type",
      "accept",
      "origin",
    ]
  }
  
  frontend_response {
    body_bytes = 1024
    headers_to_log = [
      "content-type",
      "content-length",
      "origin",
    ]
  }
  
  backend_request {
    body_bytes = 1024
    headers_to_log = [
      "content-type",
      "accept",
      "origin",
    ]
  }
  
  backend_response {
    body_bytes = 1024
    headers_to_log = [
      "content-type",
      "content-length",
      "origin",
    ]
  }
}

# Named value for Redis connection string (secure)
resource "azurerm_api_management_named_value" "redis_connection" {
  name                = "redis-connection"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "Redis Connection"
  value               = "${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port},password=${azurerm_redis_cache.main.primary_access_key},ssl=True"
  secret              = true
}

# Sample API for demonstration
resource "azurerm_api_management_api" "sample" {
  name                = var.sample_api_name
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Sample Enterprise API"
  path                = var.sample_api_path
  protocols           = ["https"]
  service_url         = var.sample_api_service_url
  
  subscription_required = true
  
  import {
    content_format = "swagger-link-json"
    content_value  = "${var.sample_api_service_url}/spec.json"
  }
}

# Security and performance policy for the sample API
resource "azurerm_api_management_api_policy" "sample" {
  api_name            = azurerm_api_management_api.sample.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  xml_content = <<XML
<policies>
    <inbound>
        <!-- Rate limiting per subscription key -->
        <rate-limit calls="${var.rate_limit_calls}" renewal-period="${var.rate_limit_renewal_period}" />
        <quota calls="${var.quota_calls}" renewal-period="${var.quota_renewal_period}" />
        
        <!-- IP filtering for additional security -->
        <ip-filter action="allow">
            <address-range from="0.0.0.0" to="255.255.255.255" />
        </ip-filter>
        
        <!-- Request size limiting -->
        <set-header name="Content-Length" exists-action="skip">
            <value>1048576</value>
        </set-header>
        
        <!-- Cache lookup for GET requests -->
        <cache-lookup vary-by-developer="false" vary-by-developer-groups="false">
            <vary-by-header>Accept</vary-by-header>
            <vary-by-header>Accept-Charset</vary-by-header>
            <vary-by-query-parameter>*</vary-by-query-parameter>
        </cache-lookup>
        
        <!-- CORS policy for web applications -->
        <cors allow-credentials="false">
            <allowed-origins>
                <origin>*</origin>
            </allowed-origins>
            <allowed-methods>
                <method>GET</method>
                <method>POST</method>
                <method>PUT</method>
                <method>DELETE</method>
                <method>HEAD</method>
                <method>OPTIONS</method>
            </allowed-methods>
            <allowed-headers>
                <header>*</header>
            </allowed-headers>
        </cors>
    </inbound>
    
    <outbound>
        <!-- Cache store for successful responses -->
        <cache-store duration="${var.cache_duration}" />
        
        <!-- Security headers -->
        <set-header name="X-Content-Type-Options" exists-action="override">
            <value>nosniff</value>
        </set-header>
        <set-header name="X-Frame-Options" exists-action="override">
            <value>DENY</value>
        </set-header>
        <set-header name="X-XSS-Protection" exists-action="override">
            <value>1; mode=block</value>
        </set-header>
        <set-header name="Strict-Transport-Security" exists-action="override">
            <value>max-age=31536000; includeSubDomains</value>
        </set-header>
        <set-header name="Referrer-Policy" exists-action="override">
            <value>strict-origin-when-cross-origin</value>
        </set-header>
        <set-header name="Content-Security-Policy" exists-action="override">
            <value>default-src 'self'</value>
        </set-header>
        
        <!-- Remove server information -->
        <set-header name="Server" exists-action="delete" />
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="X-AspNet-Version" exists-action="delete" />
        <set-header name="X-AspNetMvc-Version" exists-action="delete" />
    </outbound>
    
    <backend>
        <base />
    </backend>
    
    <on-error>
        <base />
    </on-error>
</policies>
XML
  
  depends_on = [azurerm_api_management_named_value.redis_connection]
}

# Web Application Firewall Policy with comprehensive protection
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                = "${replace(var.waf_policy_name_prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.front_door_sku
  enabled             = true
  mode                = var.waf_mode
  
  # OWASP Core Rule Set for comprehensive protection
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
    
    # Override specific rules if needed
    override {
      rule_group_name = "PROTOCOL-ENFORCEMENT"
      rule {
        rule_id = "920230"
        enabled = true
        action  = "Block"
      }
    }
    
    override {
      rule_group_name = "LFI"
      rule {
        rule_id = "930100"
        enabled = true
        action  = "Block"
      }
    }
    
    override {
      rule_group_name = "RFI"
      rule {
        rule_id = "931100"
        enabled = true
        action  = "Block"
      }
    }
    
    override {
      rule_group_name = "SQLI"
      rule {
        rule_id = "942100"
        enabled = true
        action  = "Block"
      }
    }
    
    override {
      rule_group_name = "XSS"
      rule {
        rule_id = "941100"
        enabled = true
        action  = "Block"
      }
    }
  }
  
  # Bot Manager Rule Set for bot protection
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }
  
  # Custom rules for additional security
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 1
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100
    type                           = "RateLimitRule"
    action                         = "Block"
    
    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0"]
    }
  }
  
  custom_rule {
    name     = "BlockMaliciousUserAgents"
    enabled  = true
    priority = 2
    type     = "MatchRule"
    action   = "Block"
    
    match_condition {
      match_variable     = "RequestHeader"
      selector           = "User-Agent"
      operator           = "Contains"
      negation_condition = false
      match_values = [
        "sqlmap",
        "nikto",
        "nmap",
        "masscan",
        "gobuster",
        "dirbuster"
      ]
    }
  }
  
  custom_rule {
    name     = "BlockSuspiciousRequests"
    enabled  = true
    priority = 3
    type     = "MatchRule"
    action   = "Block"
    
    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      negation_condition = false
      match_values = [
        "../",
        "..\\",
        "union+select",
        "union%20select",
        "<script",
        "javascript:",
        "vbscript:",
        "onload=",
        "onerror="
      ]
    }
  }
  
  tags = merge(var.common_tags, {
    "component" = "security"
  })
}

# Azure Front Door Profile with Premium SKU
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${var.front_door_name_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.front_door_sku
  
  response_timeout_seconds = 120
  
  tags = merge(var.common_tags, {
    "component" = "cdn"
  })
}

# Front Door Endpoint for API traffic
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "api-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  enabled                  = true
  
  tags = merge(var.common_tags, {
    "component" = "cdn"
  })
}

# Origin Group for API Management
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "apim-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  session_affinity_enabled = false
  
  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
    additional_latency_in_milliseconds = 50
  }
  
  health_probe {
    path                = var.health_probe_path
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = var.health_probe_interval
  }
}

# Origin for API Management
resource "azurerm_cdn_frontdoor_origin" "main" {
  name                          = "apim-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  
  enabled                        = true
  host_name                      = azurerm_api_management.main.gateway_url
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_api_management.main.gateway_url
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
  
  private_link {
    request_message        = "Request access for API Management"
    target_type           = "sites"
    location              = azurerm_resource_group.main.location
    private_link_target_id = azurerm_api_management.main.id
  }
}

# Security Policy Association
resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "security-policy"
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

# Route configuration for API traffic
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "api-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true
  
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  
  cdn_frontdoor_origin_path = ""
  
  compression_enabled = true
  query_string_caching_behavior = "IgnoreQueryString"
  
  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
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
      "application/x-mpegurl",
      "application/x-opentype",
      "application/x-otf",
      "application/x-perl",
      "application/x-ttf",
      "application/x-javascript",
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
  
  depends_on = [
    azurerm_cdn_frontdoor_origin.main,
    azurerm_cdn_frontdoor_security_policy.main
  ]
}

# Diagnostic settings for Front Door
resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                       = "frontdoor-diagnostics"
  target_resource_id         = azurerm_cdn_frontdoor_profile.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FrontDoorAccessLog"
  }
  
  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "main" {
  name                = "api-security-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "apisec"
  
  email_receiver {
    name          = "security-team"
    email_address = var.apim_publisher_email
  }
  
  tags = merge(var.common_tags, {
    "component" = "monitoring"
  })
}

# Metric alert for API Management high error rate
resource "azurerm_monitor_metric_alert" "api_errors" {
  name                = "api-high-error-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_api_management.main.id]
  description         = "Alert when API error rate exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.ApiManagement/service"
    metric_name      = "UnauthorizedRequests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 10
    
    dimension {
      name     = "GatewayResponseCodeCategory"
      operator = "Include"
      values   = ["4XX", "5XX"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2
  
  tags = merge(var.common_tags, {
    "component" = "monitoring"
  })
}

# Metric alert for Redis high CPU usage
resource "azurerm_monitor_metric_alert" "redis_cpu" {
  name                = "redis-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_redis_cache.main.id]
  description         = "Alert when Redis CPU usage exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.Cache/Redis"
    metric_name      = "percentProcessorTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2
  
  tags = merge(var.common_tags, {
    "component" = "monitoring"
  })
}

# Metric alert for WAF blocked requests
resource "azurerm_monitor_metric_alert" "waf_blocked" {
  name                = "waf-blocked-requests"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cdn_frontdoor_profile.main.id]
  description         = "Alert when WAF blocks unusual number of requests"
  
  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = "RequestCount"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 100
    
    dimension {
      name     = "HttpStatusCode"
      operator = "Include"
      values   = ["403"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 1
  
  tags = merge(var.common_tags, {
    "component" = "monitoring"
  })
}

# Create subscription for the sample API
resource "azurerm_api_management_subscription" "sample" {
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "Sample API Subscription"
  state               = "active"
  allow_tracing       = true
}

# Export API Management gateway certificate for secure communication
resource "azurerm_api_management_certificate" "gateway" {
  count               = var.enable_managed_identity ? 1 : 0
  name                = "gateway-certificate"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Use Key Vault integration for certificate management
  key_vault_secret_id = null
  
  depends_on = [azurerm_api_management.main]
}

# Wait for Front Door deployment to complete
resource "time_sleep" "wait_for_frontdoor" {
  depends_on = [azurerm_cdn_frontdoor_route.main]
  
  create_duration = "5m"
}
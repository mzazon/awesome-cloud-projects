# Generate unique suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Local values for resource naming and configuration
locals {
  # Resource naming with unique suffix
  resource_suffix = random_string.suffix.result
  
  # Resource names
  resource_group_name     = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  vnet_name              = "vnet-${var.project_name}-${var.environment}-${local.resource_suffix}"
  apim_name              = "apim-${var.project_name}-${var.environment}-${local.resource_suffix}"
  agw_name               = "agw-${var.project_name}-${var.environment}-${local.resource_suffix}"
  waf_policy_name        = "waf-${var.project_name}-${var.environment}-${local.resource_suffix}"
  log_workspace_name     = "log-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_insights_name      = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  public_ip_name         = "pip-${var.project_name}-${var.environment}-${local.resource_suffix}"
  private_endpoint_name  = "pe-${var.project_name}-${var.environment}-${local.resource_suffix}"
  private_dns_zone_name  = "privatelink.azure-api.net"
  
  # Merged tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Suffix      = local.resource_suffix
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual Network with security-segmented subnets
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Application Gateway subnet
resource "azurerm_subnet" "agw" {
  name                 = "agw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.agw_subnet_prefix]
}

# API Management subnet
resource "azurerm_subnet" "apim" {
  name                 = "apim-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.apim_subnet_prefix]
}

# Private Endpoint subnet
resource "azurerm_subnet" "pe" {
  name                 = "pe-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.pe_subnet_prefix]
  
  # Disable private endpoint network policies
  private_endpoint_network_policies_enabled = false
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Application Insights for API monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# API Management service with virtual network integration
resource "azurerm_api_management" "main" {
  name                 = local.apim_name
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  publisher_name       = var.apim_publisher_name
  publisher_email      = var.apim_publisher_email
  sku_name             = var.apim_sku_name
  tags                 = local.common_tags
  
  # Enable managed identity for secure integrations
  identity {
    type = "SystemAssigned"
  }
  
  # Internal virtual network integration for zero-trust
  virtual_network_type = "Internal"
  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }
  
  # Security configuration
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
  }
}

# Application Insights logger for API Management
resource "azurerm_api_management_logger" "appinsights" {
  name                = "appInsights"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  resource_id         = azurerm_application_insights.main.id
  
  application_insights {
    instrumentation_key = azurerm_application_insights.main.instrumentation_key
  }
}

# Diagnostic settings for API Management
resource "azurerm_api_management_diagnostic" "main" {
  identifier          = "applicationinsights"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id
  
  sampling_percentage       = 100.0
  always_log_errors        = true
  log_client_ip            = true
  verbosity                = "information"
  http_correlation_protocol = "W3C"
  
  frontend_request {
    body_bytes = 8192
    headers_to_log = [
      "User-Agent",
      "Authorization"
    ]
  }
  
  frontend_response {
    body_bytes = 8192
    headers_to_log = [
      "Content-Type"
    ]
  }
  
  backend_request {
    body_bytes = 8192
    headers_to_log = [
      "User-Agent"
    ]
  }
  
  backend_response {
    body_bytes = 8192
    headers_to_log = [
      "Content-Type"
    ]
  }
}

# Web Application Firewall Policy with OWASP rules
resource "azurerm_web_application_firewall_policy" "main" {
  name                = local.waf_policy_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
  
  # WAF policy settings for zero-trust security
  policy_settings {
    enabled                     = true
    mode                       = var.waf_mode
    request_body_check         = true
    file_upload_limit_in_mb    = 100
    max_request_body_size_in_kb = 128
  }
  
  # OWASP Core Rule Set for comprehensive threat protection
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = var.waf_rule_set_version
    }
  }
  
  # Custom rate limiting rule
  custom_rules {
    name      = "RateLimitRule"
    priority  = 100
    rule_type = "RateLimitRule"
    action    = "Block"
    
    rate_limit_duration = "OneMin"
    rate_limit_threshold = var.rate_limit_threshold
    
    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0"]
    }
  }
  
  # Custom rule to block common attack patterns
  custom_rules {
    name      = "BlockMaliciousUserAgents"
    priority  = 200
    rule_type = "MatchRule"
    action    = "Block"
    
    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "User-Agent"
      }
      operator           = "Contains"
      negation_condition = false
      match_values = [
        "<script>",
        "javascript:",
        "vbscript:",
        "onload=",
        "onerror="
      ]
    }
  }
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "agw" {
  name                = local.public_ip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Application Gateway with WAF integration
resource "azurerm_application_gateway" "main" {
  name                = local.agw_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  enable_http2        = true
  firewall_policy_id  = azurerm_web_application_firewall_policy.main.id
  tags                = local.common_tags
  
  # SKU configuration for WAF v2
  sku {
    name     = var.agw_sku.name
    tier     = var.agw_sku.tier
    capacity = var.agw_sku.capacity
  }
  
  # Gateway IP configuration
  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.agw.id
  }
  
  # Frontend port configuration
  frontend_port {
    name = "http-port"
    port = 80
  }
  
  frontend_port {
    name = "https-port"
    port = 443
  }
  
  # Frontend IP configuration
  frontend_ip_configuration {
    name                 = "public-frontend-ip"
    public_ip_address_id = azurerm_public_ip.agw.id
  }
  
  # Backend address pool pointing to API Management
  backend_address_pool {
    name  = "apim-backend-pool"
    fqdns = [replace(azurerm_api_management.main.gateway_url, "https://", "")]
  }
  
  # Backend HTTP settings for API Management
  backend_http_settings {
    name                  = "apim-backend-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 60
    probe_name            = "apim-health-probe"
    
    # Host name override for API Management
    pick_host_name_from_backend_address = true
  }
  
  # Health probe for API Management
  probe {
    name                                      = "apim-health-probe"
    protocol                                  = "Https"
    path                                      = "/status-0123456789abcdef"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }
  
  # HTTP listener
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "public-frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }
  
  # Request routing rule
  request_routing_rule {
    name                       = "api-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "apim-backend-pool"
    backend_http_settings_name = "apim-backend-settings"
    priority                   = 100
  }
  
  # Depends on API Management for proper ordering
  depends_on = [azurerm_api_management.main]
}

# Sample API with comprehensive security policies (optional)
resource "azurerm_api_management_api" "sample" {
  count               = var.enable_sample_api ? 1 : 0
  name                = "sample-secure-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Sample Secure API"
  path                = "secure"
  protocols           = ["https"]
  service_url         = var.sample_api_backend_url
  
  # Import from OpenAPI for better structure
  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.0"
      info = {
        title   = "Sample Secure API"
        version = "1.0.0"
      }
      paths = {
        "/data" = {
          get = {
            summary     = "Get secure data"
            operationId = "getSecureData"
            responses = {
              "200" = {
                description = "Successful response"
              }
            }
          }
        }
      }
    })
  }
}

# Sample API operation
resource "azurerm_api_management_api_operation" "sample_get" {
  count               = var.enable_sample_api ? 1 : 0
  operation_id        = "get-secure-data"
  api_name            = azurerm_api_management_api.sample[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Get Secure Data"
  method              = "GET"
  url_template        = "/data"
  description         = "Retrieves secure data with zero-trust validation"
}

# Comprehensive security policy for sample API
resource "azurerm_api_management_api_policy" "sample_security" {
  count               = var.enable_sample_api ? 1 : 0
  api_name            = azurerm_api_management_api.sample[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  xml_content = <<XML
<policies>
    <inbound>
        <base />
        <!-- Zero-trust authentication validation -->
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized access denied">
            <openid-config url="https://login.microsoftonline.com/common/v2.0/.well-known/openid_configuration" />
            <required-claims>
                <claim name="aud" match="any">
                    <value>api://your-api-id</value>
                </claim>
            </required-claims>
        </validate-jwt>
        
        <!-- Global rate limiting -->
        <rate-limit calls="${var.api_rate_limit_calls}" renewal-period="60" />
        
        <!-- Per-IP rate limiting -->
        <rate-limit-by-key calls="${var.api_rate_limit_per_ip}" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
        
        <!-- IP filtering for additional security -->
        <ip-filter action="allow">
            %{for ip_range in var.allowed_ip_ranges}
            <address-range from="${cidrhost(ip_range, 0)}" to="${cidrhost(ip_range, pow(2, 32 - split("/", ip_range)[1]) - 1)}" />
            %{endfor}
        </ip-filter>
        
        <!-- Security logging for audit trail -->
        <log-to-eventhub logger-id="appInsights" partition-id="0">
            @{
                return new JObject(
                    new JProperty("timestamp", DateTime.UtcNow.ToString()),
                    new JProperty("operation", context.Operation.Name),
                    new JProperty("clientIp", context.Request.IpAddress),
                    new JProperty("userAgent", context.Request.Headers.GetValueOrDefault("User-Agent", "")),
                    new JProperty("requestId", context.RequestId),
                    new JProperty("userId", context.User?.Id ?? "anonymous")
                ).ToString();
            }
        </log-to-eventhub>
        
        <!-- Request validation -->
        <validate-headers specified-header-action="ignore" unspecified-header-action="ignore" errors-variable-name="headerErrors" />
        
        <!-- CORS policy for browser-based clients -->
        <cors allow-credentials="false">
            <allowed-origins>
                <origin>*</origin>
            </allowed-origins>
            <allowed-methods>
                <method>GET</method>
                <method>POST</method>
                <method>PUT</method>
                <method>DELETE</method>
                <method>OPTIONS</method>
            </allowed-methods>
            <allowed-headers>
                <header>Content-Type</header>
                <header>Authorization</header>
            </allowed-headers>
        </cors>
    </inbound>
    <backend>
        <base />
        <!-- Backend timeout and retry policy -->
        <retry condition="@(context.Response.StatusCode >= 500)" count="2" interval="1" />
    </backend>
    <outbound>
        <base />
        <!-- Remove server headers for security -->
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="Server" exists-action="delete" />
        <set-header name="X-AspNet-Version" exists-action="delete" />
        
        <!-- Add security headers -->
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
        <set-header name="Content-Security-Policy" exists-action="override">
            <value>default-src 'self'</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
        <!-- Error logging -->
        <log-to-eventhub logger-id="appInsights" partition-id="0">
            @{
                return new JObject(
                    new JProperty("timestamp", DateTime.UtcNow.ToString()),
                    new JProperty("operation", context.Operation.Name),
                    new JProperty("error", context.LastError.Message),
                    new JProperty("clientIp", context.Request.IpAddress),
                    new JProperty("requestId", context.RequestId)
                ).ToString();
            }
        </log-to-eventhub>
    </on-error>
</policies>
XML
}

# Private DNS zone for API Management private link
resource "azurerm_private_dns_zone" "apim" {
  name                = local.private_dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Link private DNS zone to virtual network
resource "azurerm_private_dns_zone_virtual_network_link" "apim" {
  name                  = "dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# Private endpoint for API Management (for future backend services)
resource "azurerm_private_endpoint" "apim" {
  name                = local.private_endpoint_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.common_tags
  
  private_service_connection {
    name                           = "apim-private-connection"
    private_connection_resource_id = azurerm_api_management.main.id
    subresource_names             = ["Gateway"]
    is_manual_connection          = false
  }
  
  private_dns_zone_group {
    name                 = "apim-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.apim.id]
  }
}

# Diagnostic settings for Application Gateway
resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "agw-diagnostics"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "ApplicationGatewayAccessLog"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  enabled_log {
    category = "ApplicationGatewayFirewallLog"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Diagnostic settings for API Management
resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                       = "apim-diagnostics"
  target_resource_id         = azurerm_api_management.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "GatewayLogs"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}
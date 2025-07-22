# Main Terraform configuration for Azure Front Door Premium and Azure NetApp Files

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  suffix = random_id.suffix.hex
  
  # Resource naming conventions
  resource_names = {
    resource_group      = "${var.resource_group_name}-${local.suffix}"
    anf_account_primary = "anf-primary-${local.suffix}"
    anf_account_secondary = "anf-secondary-${local.suffix}"
    front_door_profile  = "fd-content-${local.suffix}"
    vnet_primary        = "vnet-primary-${local.suffix}"
    vnet_secondary      = "vnet-secondary-${local.suffix}"
    lb_primary          = "lb-content-primary-${local.suffix}"
    lb_secondary        = "lb-content-secondary-${local.suffix}"
    waf_policy          = "waf-content-${local.suffix}"
    log_analytics       = "law-content-${local.suffix}"
  }
  
  # Common tags
  common_tags = merge(var.tags, {
    DeployedBy = "terraform"
    CreatedAt  = timestamp()
  })
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location_primary
  tags     = local.common_tags
}

# Create Virtual Network in Primary Region
resource "azurerm_virtual_network" "primary" {
  name                = local.resource_names.vnet_primary
  address_space       = var.vnet_address_space_primary
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create Virtual Network in Secondary Region
resource "azurerm_virtual_network" "secondary" {
  name                = local.resource_names.vnet_secondary
  address_space       = var.vnet_address_space_secondary
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create Azure NetApp Files subnet in Primary Region
resource "azurerm_subnet" "anf_primary" {
  name                 = "anf-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.primary.name
  address_prefixes     = [var.anf_subnet_address_prefix_primary]
  
  delegation {
    name = "netapp"
    service_delegation {
      name    = "Microsoft.NetApp/volumes"
      actions = ["Microsoft.Network/networkinterfaces/*", "Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Create Azure NetApp Files subnet in Secondary Region
resource "azurerm_subnet" "anf_secondary" {
  name                 = "anf-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = [var.anf_subnet_address_prefix_secondary]
  
  delegation {
    name = "netapp"
    service_delegation {
      name    = "Microsoft.NetApp/volumes"
      actions = ["Microsoft.Network/networkinterfaces/*", "Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Create Private Endpoint subnet in Primary Region
resource "azurerm_subnet" "pe_primary" {
  name                 = "pe-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.primary.name
  address_prefixes     = [var.pe_subnet_address_prefix_primary]
}

# Create Private Endpoint subnet in Secondary Region
resource "azurerm_subnet" "pe_secondary" {
  name                 = "pe-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = [var.pe_subnet_address_prefix_secondary]
}

# Create Azure NetApp Files Account in Primary Region
resource "azurerm_netapp_account" "primary" {
  name                = local.resource_names.anf_account_primary
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create Azure NetApp Files Account in Secondary Region
resource "azurerm_netapp_account" "secondary" {
  name                = local.resource_names.anf_account_secondary
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create Capacity Pool in Primary Region
resource "azurerm_netapp_pool" "primary" {
  name                = "pool-premium"
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_netapp_account.primary.name
  service_level       = var.anf_service_level
  size_in_tb          = var.anf_capacity_pool_size
  tags                = local.common_tags
}

# Create Capacity Pool in Secondary Region
resource "azurerm_netapp_pool" "secondary" {
  name                = "pool-premium"
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_netapp_account.secondary.name
  service_level       = var.anf_service_level
  size_in_tb          = var.anf_capacity_pool_size
  tags                = local.common_tags
}

# Create NetApp Files Volume in Primary Region
resource "azurerm_netapp_volume" "primary" {
  name                = "content-volume"
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_netapp_account.primary.name
  pool_name           = azurerm_netapp_pool.primary.name
  volume_path         = "${var.anf_volume_path}-primary"
  service_level       = var.anf_service_level
  subnet_id           = azurerm_subnet.anf_primary.id
  storage_quota_in_gb = var.anf_volume_size
  protocols           = var.anf_protocol_types
  tags                = local.common_tags
  
  export_policy_rule {
    rule_index        = 1
    allowed_clients   = ["0.0.0.0/0"]
    protocols_enabled = ["NFSv3"]
    unix_read_only    = false
    unix_read_write   = true
  }
}

# Create NetApp Files Volume in Secondary Region
resource "azurerm_netapp_volume" "secondary" {
  name                = "content-volume"
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_netapp_account.secondary.name
  pool_name           = azurerm_netapp_pool.secondary.name
  volume_path         = "${var.anf_volume_path}-secondary"
  service_level       = var.anf_service_level
  subnet_id           = azurerm_subnet.anf_secondary.id
  storage_quota_in_gb = var.anf_volume_size
  protocols           = var.anf_protocol_types
  tags                = local.common_tags
  
  export_policy_rule {
    rule_index        = 1
    allowed_clients   = ["0.0.0.0/0"]
    protocols_enabled = ["NFSv3"]
    unix_read_only    = false
    unix_read_write   = true
  }
}

# Create Load Balancer in Primary Region
resource "azurerm_lb" "primary" {
  name                = local.resource_names.lb_primary
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = local.common_tags
  
  frontend_ip_configuration {
    name                          = "frontend-ip"
    subnet_id                     = azurerm_subnet.anf_primary.id
    private_ip_address            = var.lb_private_ip_primary
    private_ip_address_allocation = "Static"
  }
}

# Create Load Balancer in Secondary Region
resource "azurerm_lb" "secondary" {
  name                = local.resource_names.lb_secondary
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = local.common_tags
  
  frontend_ip_configuration {
    name                          = "frontend-ip"
    subnet_id                     = azurerm_subnet.anf_secondary.id
    private_ip_address            = var.lb_private_ip_secondary
    private_ip_address_allocation = "Static"
  }
}

# Create Backend Pool for Primary Load Balancer
resource "azurerm_lb_backend_address_pool" "primary" {
  loadbalancer_id = azurerm_lb.primary.id
  name            = "backend-pool"
}

# Create Backend Pool for Secondary Load Balancer
resource "azurerm_lb_backend_address_pool" "secondary" {
  loadbalancer_id = azurerm_lb.secondary.id
  name            = "backend-pool"
}

# Create Health Probe for Primary Load Balancer
resource "azurerm_lb_probe" "primary" {
  loadbalancer_id = azurerm_lb.primary.id
  name            = "health-probe"
  protocol        = "Tcp"
  port            = 80
}

# Create Health Probe for Secondary Load Balancer
resource "azurerm_lb_probe" "secondary" {
  loadbalancer_id = azurerm_lb.secondary.id
  name            = "health-probe"
  protocol        = "Tcp"
  port            = 80
}

# Create Load Balancing Rule for Primary Load Balancer
resource "azurerm_lb_rule" "primary" {
  loadbalancer_id                = azurerm_lb.primary.id
  name                           = "content-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.primary.id]
  probe_id                       = azurerm_lb_probe.primary.id
}

# Create Load Balancing Rule for Secondary Load Balancer
resource "azurerm_lb_rule" "secondary" {
  loadbalancer_id                = azurerm_lb.secondary.id
  name                           = "content-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.secondary.id]
  probe_id                       = azurerm_lb_probe.secondary.id
}

# Create WAF Policy for Front Door
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                = local.resource_names.waf_policy
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.front_door_sku
  enabled             = true
  mode                = var.waf_mode
  tags                = local.common_tags
  
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = var.waf_managed_rule_set_version
    action  = "Block"
  }
  
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 100
    rate_limit_duration_in_minutes = var.rate_limit_duration
    rate_limit_threshold           = var.rate_limit_threshold
    type                           = "RateLimitRule"
    action                         = "Block"
    
    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      match_values       = ["*"]
      transforms         = ["Lowercase"]
    }
  }
}

# Create Front Door Profile
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = local.resource_names.front_door_profile
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.front_door_sku
  tags                = local.common_tags
  
  depends_on = [azurerm_cdn_frontdoor_firewall_policy.main]
}

# Create Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = var.front_door_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  enabled                  = true
  tags                     = local.common_tags
}

# Create Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "content-origins"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  session_affinity_enabled = false
  
  health_probe {
    interval_in_seconds = 60
    path                = "/"
    protocol            = "Http"
    request_type        = "GET"
  }
  
  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

# Create Primary Origin
resource "azurerm_cdn_frontdoor_origin" "primary" {
  name                          = "primary-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true
  host_name                     = var.lb_private_ip_primary
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = var.origin_host_header
  priority                      = 1
  weight                        = 1000
  certificate_name_check_enabled = false
  
  # Configure as Private Link origin
  private_link {
    location               = var.location_primary
    private_link_target_id = azurerm_lb.primary.id
    request_message        = "Front Door Private Link request"
  }
}

# Create Secondary Origin
resource "azurerm_cdn_frontdoor_origin" "secondary" {
  name                          = "secondary-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true
  host_name                     = var.lb_private_ip_secondary
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = var.origin_host_header
  priority                      = 2
  weight                        = 1000
  certificate_name_check_enabled = false
  
  # Configure as Private Link origin
  private_link {
    location               = var.location_secondary
    private_link_target_id = azurerm_lb.secondary.id
    request_message        = "Front Door Private Link request"
  }
}

# Create Route
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "content-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true
  forwarding_protocol           = var.forwarding_protocol
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  
  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress = [
      "text/html",
      "text/css",
      "text/javascript",
      "application/javascript",
      "application/json"
    ]
  }
}

# Create Rule Set for Caching
resource "azurerm_cdn_frontdoor_rule_set" "main" {
  name                     = "caching-rules"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

# Create Caching Rule for Static Content
resource "azurerm_cdn_frontdoor_rule" "static_content" {
  name                      = "static-content"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.main.id
  order                     = 1
  
  conditions {
    url_file_extension_condition {
      operator     = "Equal"
      match_values = ["jpg", "jpeg", "png", "gif", "css", "js", "pdf", "mp4", "mp3"]
      transforms   = ["Lowercase"]
    }
  }
  
  actions {
    response_header_action {
      header_action = "Overwrite"
      header_name   = "Cache-Control"
      value         = "public, max-age=31536000"
    }
  }
}

# Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.resource_names.log_analytics
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Create Diagnostic Settings for Front Door
resource "azurerm_monitor_diagnostic_setting" "front_door" {
  name                       = "fd-diagnostics"
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
    enabled  = true
  }
}

# Create Diagnostic Settings for NetApp Files Primary
resource "azurerm_monitor_diagnostic_setting" "netapp_primary" {
  name                       = "anf-primary-diagnostics"
  target_resource_id         = azurerm_netapp_account.primary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Diagnostic Settings for NetApp Files Secondary
resource "azurerm_monitor_diagnostic_setting" "netapp_secondary" {
  name                       = "anf-secondary-diagnostics"
  target_resource_id         = azurerm_netapp_account.secondary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Alert Rule for High Request Count
resource "azurerm_monitor_metric_alert" "high_request_count" {
  name                = "high-request-count-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cdn_frontdoor_profile.main.id]
  description         = "Alert when request count exceeds threshold"
  enabled             = true
  auto_mitigate       = true
  frequency           = "PT1M"
  severity            = 2
  window_size         = "PT5M"
  tags                = local.common_tags
  
  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = "RequestCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1000
  }
}

# Create Alert Rule for High Response Time
resource "azurerm_monitor_metric_alert" "high_response_time" {
  name                = "high-response-time-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cdn_frontdoor_profile.main.id]
  description         = "Alert when response time exceeds threshold"
  enabled             = true
  auto_mitigate       = true
  frequency           = "PT1M"
  severity            = 2
  window_size         = "PT5M"
  tags                = local.common_tags
  
  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = "TotalLatency"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1000
  }
}
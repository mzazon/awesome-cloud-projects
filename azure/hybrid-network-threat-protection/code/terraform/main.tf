# Azure Hybrid Network Security Infrastructure with Firewall Premium and ExpressRoute
# This Terraform configuration creates a comprehensive hybrid network security solution

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group for all hybrid network security resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.resource_prefix}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.tags, {
    CreatedBy = "Terraform"
    Purpose   = "HybridNetworkSecurity"
  })
}

# Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "laws-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    Service = "LogAnalytics"
  })
}

# Hub Virtual Network - Central hub for hybrid connectivity
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.hub_vnet_address_space
  
  tags = merge(var.tags, {
    Service = "VirtualNetwork"
    Type    = "Hub"
  })
}

# Azure Firewall Subnet - Required subnet for Azure Firewall
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_address_prefix]
}

# Gateway Subnet - Required subnet for ExpressRoute Gateway
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_address_prefix]
}

# Management Subnet - Optional subnet for forced tunneling scenarios
resource "azurerm_subnet" "management" {
  count                = var.create_management_subnet ? 1 : 0
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.management_subnet_address_prefix]
}

# Spoke Virtual Network - Workload network
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.spoke_vnet_address_space
  
  tags = merge(var.tags, {
    Service = "VirtualNetwork"
    Type    = "Spoke"
  })
}

# Workload Subnet in Spoke Network
resource "azurerm_subnet" "workload" {
  name                 = "snet-workload-${var.resource_prefix}-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.workload_subnet_address_prefix]
}

# Virtual Network Peering: Hub to Spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-spoke"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

# Virtual Network Peering: Spoke to Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-spoke-to-hub"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true
  
  depends_on = [
    azurerm_virtual_network_gateway.expressroute
  ]
}

# Public IP for Azure Firewall
resource "azurerm_public_ip" "firewall" {
  name                = "pip-azfw-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(var.tags, {
    Service = "AzureFirewall"
  })
}

# Public IP for Firewall Management (if forced tunneling is enabled)
resource "azurerm_public_ip" "firewall_management" {
  count               = var.enable_forced_tunneling ? 1 : 0
  name                = "pip-azfw-mgmt-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(var.tags, {
    Service = "AzureFirewall"
    Purpose = "Management"
  })
}

# Public IP for ExpressRoute Gateway
resource "azurerm_public_ip" "expressroute_gateway" {
  name                = "pip-ergw-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(var.tags, {
    Service = "ExpressRouteGateway"
  })
}

# Azure Firewall Policy for Premium features
resource "azurerm_firewall_policy" "main" {
  name                = "azfw-policy-${var.resource_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.firewall_sku_tier
  
  # Threat Intelligence configuration
  threat_intelligence_mode = var.firewall_threat_intel_mode
  
  # DNS configuration
  dns {
    proxy_enabled = var.firewall_dns_proxy_enabled
  }
  
  # IDPS configuration for Premium tier
  dynamic "intrusion_detection" {
    for_each = var.firewall_sku_tier == "Premium" ? [1] : []
    content {
      mode = var.firewall_idps_mode
    }
  }
  
  tags = merge(var.tags, {
    Service = "AzureFirewall"
  })
}

# Firewall Policy Rule Collection Group for Network Rules
resource "azurerm_firewall_policy_rule_collection_group" "network_rules" {
  name               = "NetworkRules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 1000
  
  # Network rule collection for hybrid connectivity
  network_rule_collection {
    name     = "HybridNetworkRules"
    priority = 1100
    action   = "Allow"
    
    # Allow on-premises to spoke network traffic
    rule {
      name             = "AllowOnPremToSpoke"
      description      = "Allow on-premises traffic to spoke networks"
      protocols        = ["TCP", "UDP"]
      source_addresses = var.on_premises_address_space
      destination_addresses = var.spoke_vnet_address_space
      destination_ports = var.allowed_ports
    }
    
    # Allow spoke to on-premises traffic
    rule {
      name             = "AllowSpokeToOnPrem"
      description      = "Allow spoke network traffic to on-premises"
      protocols        = ["TCP", "UDP"]
      source_addresses = var.spoke_vnet_address_space
      destination_addresses = var.on_premises_address_space
      destination_ports = var.allowed_ports
    }
  }
}

# Firewall Policy Rule Collection Group for Application Rules
resource "azurerm_firewall_policy_rule_collection_group" "application_rules" {
  name               = "ApplicationRules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 1200
  
  # Application rule collection for web traffic
  application_rule_collection {
    name     = "WebTrafficRules"
    priority = 1200
    action   = "Allow"
    
    # Allow web traffic with inspection
    rule {
      name        = "AllowWebTraffic"
      description = "Allow web traffic with TLS inspection"
      
      protocols {
        type = "Https"
        port = 443
      }
      
      protocols {
        type = "Http"
        port = 80
      }
      
      source_addresses = concat(var.spoke_vnet_address_space, var.on_premises_address_space)
      destination_fqdns = var.allowed_web_fqdns
    }
  }
}

# Azure Firewall Premium instance
resource "azurerm_firewall" "main" {
  name                = "azfw-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.main.id
  
  # Standard IP configuration
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  
  # Management IP configuration for forced tunneling
  dynamic "management_ip_configuration" {
    for_each = var.enable_forced_tunneling ? [1] : []
    content {
      name                 = "management"
      subnet_id            = azurerm_subnet.management[0].id
      public_ip_address_id = azurerm_public_ip.firewall_management[0].id
    }
  }
  
  tags = merge(var.tags, {
    Service = "AzureFirewall"
  })
}

# ExpressRoute Virtual Network Gateway
resource "azurerm_virtual_network_gateway" "expressroute" {
  name                = "ergw-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  type     = "ExpressRoute"
  vpn_type = "RouteBased"
  
  sku           = var.expressroute_gateway_sku
  generation    = "Generation1"
  active_active = false
  enable_bgp    = false
  
  ip_configuration {
    name                          = "gw-ip-config"
    public_ip_address_id          = azurerm_public_ip.expressroute_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
  
  tags = merge(var.tags, {
    Service = "ExpressRouteGateway"
  })
}

# ExpressRoute Connection (optional, requires existing circuit)
resource "azurerm_virtual_network_gateway_connection" "expressroute" {
  count               = var.create_expressroute_connection && var.expressroute_circuit_resource_id != "" ? 1 : 0
  name                = "conn-expressroute-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  type                       = "ExpressRoute"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.expressroute.id
  express_route_circuit_id   = var.expressroute_circuit_resource_id
  
  tags = merge(var.tags, {
    Service = "ExpressRouteConnection"
  })
}

# Route Table for spoke network traffic steering
resource "azurerm_route_table" "spoke" {
  name                = "rt-spoke-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  disable_bgp_route_propagation = var.disable_bgp_route_propagation
  
  tags = merge(var.tags, {
    Service = "RouteTable"
  })
}

# Route to direct on-premises traffic through Azure Firewall
resource "azurerm_route" "spoke_to_onprem" {
  name                   = "route-to-onprem"
  resource_group_name    = azurerm_resource_group.main.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = var.on_premises_address_space[0]
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

# Default route to internet through Azure Firewall
resource "azurerm_route" "spoke_default" {
  count                  = var.create_default_route_to_internet ? 1 : 0
  name                   = "route-default"
  resource_group_name    = azurerm_resource_group.main.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

# Associate route table with workload subnet
resource "azurerm_subnet_route_table_association" "workload" {
  subnet_id      = azurerm_subnet.workload.id
  route_table_id = azurerm_route_table.spoke.id
}

# Diagnostic settings for Azure Firewall
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-${azurerm_firewall.main.name}"
  target_resource_id = azurerm_firewall.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable specified log categories
  dynamic "enabled_log" {
    for_each = var.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
  }
}

# Diagnostic settings for ExpressRoute Gateway
resource "azurerm_monitor_diagnostic_setting" "expressroute_gateway" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-${azurerm_virtual_network_gateway.expressroute.name}"
  target_resource_id = azurerm_virtual_network_gateway.expressroute.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable gateway logs
  enabled_log {
    category = "GatewayDiagnosticLog"
  }
  
  enabled_log {
    category = "TunnelDiagnosticLog"
  }
  
  enabled_log {
    category = "RouteDiagnosticLog"
  }
  
  enabled_log {
    category = "IKEDiagnosticLog"
  }
  
  enabled_log {
    category = "P2SDiagnosticLog"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
  }
}

# Network Security Group for additional workload protection
resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-${var.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Allow inbound traffic from on-premises
  security_rule {
    name                       = "AllowOnPremisesInbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = var.allowed_ports
    source_address_prefixes    = var.on_premises_address_space
    destination_address_prefix = "*"
  }
  
  # Allow outbound traffic to on-premises
  security_rule {
    name                       = "AllowOnPremisesOutbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefixes = var.on_premises_address_space
  }
  
  tags = merge(var.tags, {
    Service = "NetworkSecurityGroup"
  })
}

# Associate NSG with workload subnet
resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

# Time delay to ensure proper resource deployment order
resource "time_sleep" "wait_for_firewall_policy" {
  depends_on = [
    azurerm_firewall_policy_rule_collection_group.network_rules,
    azurerm_firewall_policy_rule_collection_group.application_rules
  ]
  
  create_duration = "30s"
}
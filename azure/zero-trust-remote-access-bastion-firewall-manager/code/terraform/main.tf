# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  
  # Merge default and additional tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    DeployedBy = "terraform"
    Timestamp  = timestamp()
  })
  
  # Network security rules for zero-trust access
  nsg_rules = {
    bastion_rdp = {
      name                       = "AllowBastionRDP"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.bastion_subnet_address_prefix
      destination_address_prefix = "*"
    }
    bastion_ssh = {
      name                       = "AllowBastionSSH"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.bastion_subnet_address_prefix
      destination_address_prefix = "*"
    }
    deny_all_inbound = {
      name                       = "DenyAllInbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

# Data sources for current subscription context
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Resource Group for all zero-trust infrastructure
resource "azurerm_resource_group" "zerotrust" {
  name     = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "zerotrust" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Hub Virtual Network - Central security and shared services
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  address_space       = var.hub_vnet_address_space
  tags                = local.common_tags
}

# Azure Bastion Subnet - Must be named exactly "AzureBastionSubnet"
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.zerotrust.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

# Azure Firewall Subnet - Must be named exactly "AzureFirewallSubnet"
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.zerotrust.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_address_prefix]
}

# Public IP for Azure Bastion
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Azure Bastion Host for secure remote access
resource "azurerm_bastion_host" "zerotrust" {
  name                   = "bastion-${var.environment}-${local.resource_suffix}"
  location               = azurerm_resource_group.zerotrust.location
  resource_group_name    = azurerm_resource_group.zerotrust.name
  sku                    = var.bastion_sku
  scale_units            = var.bastion_sku == "Standard" ? var.bastion_scale_units : null
  copy_paste_enabled     = var.bastion_sku == "Standard" ? true : null
  file_copy_enabled      = var.bastion_sku == "Standard" ? true : null
  ip_connect_enabled     = var.bastion_sku == "Standard" ? true : null
  shareable_link_enabled = var.bastion_sku == "Standard" ? false : null
  tunneling_enabled      = var.bastion_sku == "Standard" ? true : null
  tags                   = local.common_tags
  
  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# Public IP for Azure Firewall
resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Azure Firewall Policy for centralized security management
resource "azurerm_firewall_policy" "zerotrust" {
  name                = "fwpolicy-${var.project_name}-${var.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.zerotrust.name
  location            = azurerm_resource_group.zerotrust.location
  sku                 = var.firewall_sku_tier
  tags                = local.common_tags
  
  # Threat intelligence configuration
  threat_intelligence_mode = var.firewall_threat_intel_mode
  
  # DNS configuration for secure name resolution
  dns {
    proxy_enabled = true
    servers       = []
  }
  
  # Intrusion detection and prevention (Premium SKU only)
  dynamic "intrusion_detection" {
    for_each = var.firewall_sku_tier == "Premium" && var.enable_intrusion_detection ? [1] : []
    content {
      mode = "Alert"
    }
  }
}

# Firewall Policy Rule Collection Group for zero-trust rules
resource "azurerm_firewall_policy_rule_collection_group" "zerotrust" {
  name               = "rcg-zerotrust"
  firewall_policy_id = azurerm_firewall_policy.zerotrust.id
  priority           = 100
  
  # Application Rules - Allow essential Windows Updates and Azure services
  application_rule_collection {
    name     = "app-rules-windows"
    priority = 100
    action   = "Allow"
    
    rule {
      name = "AllowWindowsUpdate"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [for vnet in var.spoke_vnets : vnet.address_space[0]]
      destination_fqdns = [
        "*.update.microsoft.com",
        "*.windowsupdate.com",
        "*.microsoft.com"
      ]
    }
    
    rule {
      name = "AllowAzureServices"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [for vnet in var.spoke_vnets : vnet.address_space[0]]
      destination_fqdns = [
        "*.azure.com",
        "*.azure.net",
        "*.azureedge.net",
        "*.microsoftonline.com"
      ]
    }
  }
  
  # Network Rules - Allow specific Azure service communication
  network_rule_collection {
    name     = "net-rules-azure"
    priority = 200
    action   = "Allow"
    
    rule {
      name      = "AllowAzureCloud"
      protocols = ["TCP"]
      source_addresses = [for vnet in var.spoke_vnets : vnet.address_space[0]]
      destination_addresses = ["AzureCloud"]
      destination_ports     = ["443", "80"]
    }
    
    rule {
      name      = "AllowDNS"
      protocols = ["UDP"]
      source_addresses = [for vnet in var.spoke_vnets : vnet.address_space[0]]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }
}

# Azure Firewall for centralized security inspection
resource "azurerm_firewall" "zerotrust" {
  name                = "fw-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.zerotrust.id
  tags                = local.common_tags
  
  ip_configuration {
    name                 = "firewall-ip-config"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

# Spoke Virtual Networks for workload isolation
resource "azurerm_virtual_network" "spoke" {
  for_each = var.spoke_vnets
  
  name                = "vnet-spoke-${each.key}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  address_space       = each.value.address_space
  tags                = local.common_tags
}

# Spoke subnets for workload deployment
resource "azurerm_subnet" "spoke" {
  for_each = {
    for combo in flatten([
      for vnet_key, vnet_config in var.spoke_vnets : [
        for subnet_key, subnet_config in vnet_config.subnets : {
          vnet_key    = vnet_key
          subnet_key  = subnet_key
          subnet_config = subnet_config
        }
      ]
    ]) : "${combo.vnet_key}-${combo.subnet_key}" => combo
  }
  
  name                 = "snet-${each.value.vnet_key}-${each.value.subnet_key}"
  resource_group_name  = azurerm_resource_group.zerotrust.name
  virtual_network_name = azurerm_virtual_network.spoke[each.value.vnet_key].name
  address_prefixes     = [each.value.subnet_config.address_prefix]
}

# VNet Peering from Hub to Spokes
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spoke_vnets
  
  name                      = "hub-to-spoke-${each.key}"
  resource_group_name       = azurerm_resource_group.zerotrust.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

# VNet Peering from Spokes to Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spoke_vnets
  
  name                      = "spoke-${each.key}-to-hub"
  resource_group_name       = azurerm_resource_group.zerotrust.name
  virtual_network_name      = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

# Network Security Groups for defense-in-depth
resource "azurerm_network_security_group" "spoke_workload" {
  for_each = var.spoke_vnets
  
  name                = "nsg-${each.key}-workload"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  tags                = local.common_tags
}

# NSG Security Rules for zero-trust access
resource "azurerm_network_security_rule" "spoke_workload" {
  for_each = {
    for combo in flatten([
      for vnet_key in keys(var.spoke_vnets) : [
        for rule_key, rule_config in local.nsg_rules : {
          vnet_key = vnet_key
          rule_key = rule_key
          rule_config = rule_config
        }
      ]
    ]) : "${combo.vnet_key}-${combo.rule_key}" => combo
  }
  
  name                        = each.value.rule_config.name
  priority                    = each.value.rule_config.priority
  direction                   = each.value.rule_config.direction
  access                      = each.value.rule_config.access
  protocol                    = each.value.rule_config.protocol
  source_port_range           = each.value.rule_config.source_port_range
  destination_port_range      = each.value.rule_config.destination_port_range
  source_address_prefix       = each.value.rule_config.source_address_prefix
  destination_address_prefix  = each.value.rule_config.destination_address_prefix
  resource_group_name         = azurerm_resource_group.zerotrust.name
  network_security_group_name = azurerm_network_security_group.spoke_workload[each.value.vnet_key].name
}

# Associate NSGs with spoke subnets
resource "azurerm_subnet_network_security_group_association" "spoke_workload" {
  for_each = {
    for combo in flatten([
      for vnet_key, vnet_config in var.spoke_vnets : [
        for subnet_key, subnet_config in vnet_config.subnets : {
          vnet_key   = vnet_key
          subnet_key = subnet_key
        }
      ]
    ]) : "${combo.vnet_key}-${combo.subnet_key}" => combo
  }
  
  subnet_id                 = azurerm_subnet.spoke["${each.value.vnet_key}-${each.value.subnet_key}"].id
  network_security_group_id = azurerm_network_security_group.spoke_workload[each.value.vnet_key].id
}

# Route Table for forced tunneling through firewall
resource "azurerm_route_table" "spoke_workloads" {
  name                = "rt-spoke-workloads"
  location            = azurerm_resource_group.zerotrust.location
  resource_group_name = azurerm_resource_group.zerotrust.name
  tags                = local.common_tags
  
  route {
    name                   = "route-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.zerotrust.ip_configuration[0].private_ip_address
  }
}

# Associate route table with spoke subnets
resource "azurerm_subnet_route_table_association" "spoke_workload" {
  for_each = {
    for combo in flatten([
      for vnet_key, vnet_config in var.spoke_vnets : [
        for subnet_key, subnet_config in vnet_config.subnets : {
          vnet_key   = vnet_key
          subnet_key = subnet_key
        }
      ]
    ]) : "${combo.vnet_key}-${combo.subnet_key}" => combo
  }
  
  subnet_id      = azurerm_subnet.spoke["${each.value.vnet_key}-${each.value.subnet_key}"].id
  route_table_id = azurerm_route_table.spoke_workloads.id
}

# Azure Policy Definition for NSG requirement
resource "azurerm_policy_definition" "require_nsg_on_subnet" {
  count = var.enforce_nsg_policy ? 1 : 0
  
  name         = "require-nsg-on-subnet-${local.resource_suffix}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require NSG on Subnets"
  description  = "Require Network Security Group on all subnets except AzureBastionSubnet and AzureFirewallSubnet"
  
  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/virtualNetworks/subnets"
        },
        {
          field   = "Microsoft.Network/virtualNetworks/subnets/networkSecurityGroup.id"
          exists  = "false"
        },
        {
          field = "name"
          notIn = ["AzureBastionSubnet", "AzureFirewallSubnet"]
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
  
  metadata = jsonencode({
    category = "Network"
  })
}

# Azure Policy Assignment for NSG enforcement
resource "azurerm_resource_group_policy_assignment" "nsg_enforcement" {
  count = var.enforce_nsg_policy ? 1 : 0
  
  name                 = "nsg-enforcement"
  resource_group_id    = azurerm_resource_group.zerotrust.id
  policy_definition_id = azurerm_policy_definition.require_nsg_on_subnet[0].id
  display_name         = "Enforce NSG on Subnets"
  description          = "Enforce Network Security Group requirement on all subnets"
}

# Diagnostic Settings for Azure Bastion
resource "azurerm_monitor_diagnostic_setting" "bastion" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "diag-bastion"
  target_resource_id         = azurerm_bastion_host.zerotrust.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.zerotrust[0].id
  
  enabled_log {
    category = "BastionAuditLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Diagnostic Settings for Azure Firewall
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "diag-firewall"
  target_resource_id         = azurerm_firewall.zerotrust.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.zerotrust[0].id
  
  enabled_log {
    category = "AzureFirewallApplicationRule"
  }
  
  enabled_log {
    category = "AzureFirewallNetworkRule"
  }
  
  enabled_log {
    category = "AzureFirewallDnsProxy"
  }
  
  metric {
    category = "AllMetrics"
  }
}
# Azure Adaptive Network Security Infrastructure
# This Terraform configuration creates a comprehensive network security solution
# combining Azure DDoS Protection and Azure Route Server for intelligent threat response

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent resource naming and tagging
locals {
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Project         = var.project_name
    Purpose         = "adaptive-network-security"
    Tier           = "production"
    ManagedBy      = "terraform"
    LastUpdated    = timestamp()
  }, var.additional_tags)
  
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  
  # Resource names
  hub_vnet_name           = "vnet-hub-${local.resource_suffix}"
  spoke_vnet_name         = "vnet-spoke-${local.resource_suffix}"
  ddos_plan_name          = "ddos-plan-${local.resource_suffix}"
  route_server_name       = "rs-adaptive-${local.resource_suffix}"
  firewall_name           = "fw-adaptive-${local.resource_suffix}"
  log_analytics_name      = "law-adaptive-${local.resource_suffix}"
  storage_account_name    = "stflowlogs${local.resource_suffix}"
  action_group_name       = "ddos-alerts-${local.resource_suffix}"
  
  # Public IP names
  route_server_pip_name = "pip-${local.route_server_name}"
  firewall_pip_name     = "pip-${local.firewall_name}"
}

# Create the main resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create DDoS Protection Plan for advanced threat protection
resource "azurerm_network_ddos_protection_plan" "main" {
  count               = var.enable_ddos_protection ? 1 : 0
  name                = local.ddos_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = merge(local.common_tags, {
    Purpose = "ddos-protection"
    Tier    = "standard"
  })
}

# Create hub virtual network with DDoS Protection
resource "azurerm_virtual_network" "hub" {
  name                = local.hub_vnet_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = var.hub_vnet_address_space
  
  # Enable DDoS Protection if plan is created
  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.main[0].id
      enable = true
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose     = "hub-network"
    NetworkType = "hub"
  })
}

# Create Route Server subnet (required name: RouteServerSubnet, minimum /27)
resource "azurerm_subnet" "route_server" {
  name                 = "RouteServerSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.route_server_subnet_prefix]
}

# Create Azure Firewall subnet (required name: AzureFirewallSubnet, minimum /26)
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

# Create management subnet for network appliances
resource "azurerm_subnet" "management" {
  name                 = "ManagementSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.management_subnet_prefix]
}

# Create spoke virtual network for application workloads
resource "azurerm_virtual_network" "spoke" {
  name                = local.spoke_vnet_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = var.spoke_vnet_address_space
  
  tags = merge(local.common_tags, {
    Purpose     = "spoke-network"
    NetworkType = "spoke"
    Tier        = "application"
  })
}

# Create application subnet in spoke VNet
resource "azurerm_subnet" "application" {
  name                 = "ApplicationSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.application_subnet_prefix]
}

# Create database subnet in spoke VNet
resource "azurerm_subnet" "database" {
  name                 = "DatabaseSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.database_subnet_prefix]
}

# Create VNet peering from hub to spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-spoke"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways         = false
}

# Create VNet peering from spoke to hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways         = false
}

# Create public IP for Route Server
resource "azurerm_public_ip" "route_server" {
  name                = local.route_server_pip_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  sku_tier           = "Regional"
  
  tags = merge(local.common_tags, {
    Purpose = "route-server"
    Service = "azure-route-server"
  })
}

# Create Azure Route Server for dynamic BGP routing
resource "azurerm_route_server" "main" {
  name                             = local.route_server_name
  resource_group_name              = azurerm_resource_group.main.name
  location                         = azurerm_resource_group.main.location
  sku                             = "Standard"
  public_ip_address_id            = azurerm_public_ip.route_server.id
  subnet_id                       = azurerm_subnet.route_server.id
  branch_to_branch_traffic_enabled = true
  
  tags = merge(local.common_tags, {
    Purpose = "dynamic-routing"
    Service = "azure-route-server"
    Tier    = "production"
  })
}

# Create public IP for Azure Firewall
resource "azurerm_public_ip" "firewall" {
  name                = local.firewall_pip_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  sku_tier           = "Regional"
  
  tags = merge(local.common_tags, {
    Purpose = "azure-firewall"
    Service = "network-security"
  })
}

# Create Azure Firewall for traffic inspection and filtering
resource "azurerm_firewall" "main" {
  name                = local.firewall_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  threat_intel_mode   = var.firewall_threat_intel_mode
  
  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  
  tags = merge(local.common_tags, {
    Purpose = "network-security"
    Service = "azure-firewall"
    Tier    = "production"
  })
}

# Create network rule collection for Azure Firewall
resource "azurerm_firewall_network_rule_collection" "adaptive_security" {
  name                = "adaptive-security-rules"
  azure_firewall_name = azurerm_firewall.main.name
  resource_group_name = azurerm_resource_group.main.name
  priority            = 100
  action              = "Allow"
  
  rule {
    name = "allow-web-traffic"
    source_addresses = [
      var.spoke_vnet_address_space[0]
    ]
    destination_ports = [
      "80",
      "443"
    ]
    destination_addresses = ["*"]
    protocols = ["TCP"]
  }
  
  rule {
    name = "allow-dns"
    source_addresses = [
      var.spoke_vnet_address_space[0]
    ]
    destination_ports = [
      "53"
    ]
    destination_addresses = ["*"]
    protocols = ["UDP"]
  }
}

# Create Log Analytics workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    Purpose = "security-monitoring"
    Service = "log-analytics"
  })
}

# Enable Network Watcher for network monitoring and diagnostics
resource "azurerm_network_watcher" "main" {
  count               = var.enable_network_watcher ? 1 : 0
  name                = "NetworkWatcher_${azurerm_resource_group.main.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    Purpose = "network-monitoring"
    Service = "network-watcher"
  })
}

# Create storage account for flow logs
resource "azurerm_storage_account" "flow_logs" {
  count                    = var.enable_flow_logs ? 1 : 0
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind            = "StorageV2"
  
  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for security
  blob_properties {
    delete_retention_policy {
      days = var.flow_logs_retention_days
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "flow-logs"
    Service = "storage"
  })
}

# Create Network Security Group for spoke network
resource "azurerm_network_security_group" "spoke" {
  name                = "nsg-${local.spoke_vnet_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Allow HTTP traffic
  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Allow HTTPS traffic
  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Deny all other inbound traffic
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "network-security"
    Service = "network-security-group"
  })
}

# Associate NSG with application subnet
resource "azurerm_subnet_network_security_group_association" "application" {
  subnet_id                 = azurerm_subnet.application.id
  network_security_group_id = azurerm_network_security_group.spoke.id
}

# Create NSG flow logs
resource "azurerm_network_watcher_flow_log" "spoke" {
  count                     = var.enable_flow_logs && var.enable_network_watcher ? 1 : 0
  name                      = "flowlog-${local.resource_suffix}"
  network_watcher_name      = azurerm_network_watcher.main[0].name
  resource_group_name       = azurerm_resource_group.main.name
  network_security_group_id = azurerm_network_security_group.spoke.id
  storage_account_id        = azurerm_storage_account.flow_logs[0].id
  enabled                   = true
  version                   = 2
  
  retention_policy {
    enabled = true
    days    = var.flow_logs_retention_days
  }
  
  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = 10
  }
  
  tags = merge(local.common_tags, {
    Purpose = "flow-logs"
    Service = "network-monitoring"
  })
}

# Create action group for DDoS alerts
resource "azurerm_monitor_action_group" "ddos_alerts" {
  count               = var.enable_ddos_alerts ? 1 : 0
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ddos-ag"
  
  # Add email receivers if email addresses are provided
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "ddos-alerting"
    Service = "monitoring"
  })
}

# Create DDoS attack detection alert
resource "azurerm_monitor_metric_alert" "ddos_attack" {
  count               = var.enable_ddos_alerts && var.enable_ddos_protection ? 1 : 0
  name                = "DDoS-Attack-Alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_network_ddos_protection_plan.main[0].id]
  description         = "Alert when DDoS attack is detected"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Network/ddosProtectionPlans"
    metric_name      = "DDoSAttack"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.ddos_alerts[0].id
  }
  
  tags = merge(local.common_tags, {
    Purpose = "ddos-monitoring"
    Service = "alerting"
  })
}

# Create high traffic volume alert
resource "azurerm_monitor_metric_alert" "high_traffic" {
  count               = var.enable_ddos_alerts && var.enable_ddos_protection ? 1 : 0
  name                = "High-Traffic-Volume-Alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_network_ddos_protection_plan.main[0].id]
  description         = "Alert when traffic volume exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Network/ddosProtectionPlans"
    metric_name      = "PacketsInboundTotal"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.high_traffic_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.ddos_alerts[0].id
  }
  
  tags = merge(local.common_tags, {
    Purpose = "traffic-monitoring"
    Service = "alerting"
  })
}

# Configure diagnostic settings for DDoS Protection Plan
resource "azurerm_monitor_diagnostic_setting" "ddos_plan" {
  count                      = var.enable_ddos_protection ? 1 : 0
  name                       = "ddos-diagnostics"
  target_resource_id         = azurerm_network_ddos_protection_plan.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "DDoSMitigationFlowLogs"
  }
  
  enabled_log {
    category = "DDoSMitigationReports"
  }
  
  enabled_log {
    category = "DDoSProtectionNotifications"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Configure diagnostic settings for Azure Firewall
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "firewall-diagnostics"
  target_resource_id         = azurerm_firewall.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
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

# Configure diagnostic settings for Route Server
resource "azurerm_monitor_diagnostic_setting" "route_server" {
  name                       = "route-server-diagnostics"
  target_resource_id         = azurerm_route_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "RouteServerLog"
  }
  
  metric {
    category = "AllMetrics"
  }
}
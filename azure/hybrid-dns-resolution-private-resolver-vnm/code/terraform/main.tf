# Azure Hybrid DNS Resolution with DNS Private Resolver and Virtual Network Manager
# This Terraform configuration deploys a complete hybrid DNS solution for Azure environments

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Data source to get current subscription
data "azurerm_subscription" "current" {}

# Local values for resource naming and common configurations
locals {
  # Generate resource names with consistent naming convention
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Network resource names
  hub_vnet_name    = "vnet-hub-${var.project_name}-${random_string.suffix.result}"
  spoke1_vnet_name = "vnet-spoke1-${var.project_name}-${random_string.suffix.result}"
  spoke2_vnet_name = "vnet-spoke2-${var.project_name}-${random_string.suffix.result}"
  
  # DNS resolver resource names
  dns_resolver_name = "dns-resolver-${var.project_name}-${random_string.suffix.result}"
  
  # Virtual Network Manager resource names
  network_manager_name = "avnm-${var.project_name}-${random_string.suffix.result}"
  
  # Storage account name (must be globally unique)
  storage_account_name = "st${var.project_name}${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    Location      = var.location
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    ManagedBy     = "Terraform"
  })
}

# Resource Group
# Central container for all hybrid DNS solution resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Hub Virtual Network
# Central network hosting the DNS Private Resolver and connectivity services
resource "azurerm_virtual_network" "hub" {
  name                = local.hub_vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.hub_vnet_address_space
  tags                = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# DNS Inbound Subnet
# Dedicated subnet for DNS Private Resolver inbound endpoint
resource "azurerm_subnet" "dns_inbound" {
  name                 = "dns-inbound-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.dns_inbound_subnet_address_prefix]

  # Delegate subnet to Microsoft.Network/dnsResolvers for DNS Private Resolver
  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

# DNS Outbound Subnet
# Dedicated subnet for DNS Private Resolver outbound endpoint
resource "azurerm_subnet" "dns_outbound" {
  name                 = "dns-outbound-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.dns_outbound_subnet_address_prefix]

  # Delegate subnet to Microsoft.Network/dnsResolvers for DNS Private Resolver
  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

# Spoke Virtual Network 1
# First spoke network for testing DNS resolution and connectivity
resource "azurerm_virtual_network" "spoke1" {
  name                = local.spoke1_vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.spoke1_vnet_address_space
  tags                = local.common_tags
}

# Spoke 1 Default Subnet
resource "azurerm_subnet" "spoke1_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke1.name
  address_prefixes     = [var.spoke1_subnet_address_prefix]
}

# Spoke Virtual Network 2
# Second spoke network for testing DNS resolution and connectivity
resource "azurerm_virtual_network" "spoke2" {
  name                = local.spoke2_vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.spoke2_vnet_address_space
  tags                = local.common_tags
}

# Spoke 2 Default Subnet
resource "azurerm_subnet" "spoke2_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke2.name
  address_prefixes     = [var.spoke2_subnet_address_prefix]
}

# Azure DNS Private Resolver
# Fully managed DNS service for hybrid DNS resolution
resource "azurerm_private_dns_resolver" "main" {
  name                = local.dns_resolver_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = local.common_tags

  depends_on = [
    azurerm_subnet.dns_inbound,
    azurerm_subnet.dns_outbound
  ]
}

# DNS Private Resolver Inbound Endpoint
# Receives DNS queries from on-premises environments
resource "azurerm_private_dns_resolver_inbound_endpoint" "main" {
  name                    = "inbound-endpoint"
  private_dns_resolver_id = azurerm_private_dns_resolver.main.id
  location                = azurerm_resource_group.main.location
  tags                    = local.common_tags

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns_inbound.id
  }
}

# DNS Private Resolver Outbound Endpoint
# Forwards DNS queries from Azure to on-premises DNS servers
resource "azurerm_private_dns_resolver_outbound_endpoint" "main" {
  name                    = "outbound-endpoint"
  private_dns_resolver_id = azurerm_private_dns_resolver.main.id
  location                = azurerm_resource_group.main.location
  subnet_id               = azurerm_subnet.dns_outbound.id
  tags                    = local.common_tags
}

# DNS Forwarding Ruleset
# Defines conditional forwarding rules for on-premises domain resolution
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "main" {
  name                                       = "onprem-forwarding-ruleset"
  resource_group_name                        = azurerm_resource_group.main.name
  location                                   = azurerm_resource_group.main.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.main.id]
  tags                                       = local.common_tags
}

# DNS Forwarding Rule for On-Premises Domain
# Routes queries for on-premises domain to on-premises DNS servers
resource "azurerm_private_dns_resolver_forwarding_rule" "onprem" {
  name                      = "contoso-com-rule"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
  domain_name               = var.onprem_domain_name
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = var.onprem_dns_servers
    content {
      ip_address = target_dns_servers.value.ip_address
      port       = target_dns_servers.value.port
    }
  }
}

# Virtual Network Links for DNS Forwarding Ruleset
# Connect virtual networks to the DNS forwarding ruleset
resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  name                      = "hub-vnet-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
  virtual_network_id        = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "spoke1" {
  name                      = "spoke1-vnet-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
  virtual_network_id        = azurerm_virtual_network.spoke1.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "spoke2" {
  name                      = "spoke2-vnet-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
  virtual_network_id        = azurerm_virtual_network.spoke2.id
}

# Private DNS Zone for Azure Resources
# Provides DNS resolution for Azure private endpoints and services
resource "azurerm_private_dns_zone" "main" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Virtual Network Links for Private DNS Zone
# Enable DNS resolution from virtual networks to the private DNS zone
resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  name                  = "hub-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke1" {
  name                  = "spoke1-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.spoke1.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke2" {
  name                  = "spoke2-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.spoke2.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# Test DNS Records in Private DNS Zone
# Provide test targets for DNS resolution validation
resource "azurerm_private_dns_a_record" "test_vm" {
  name                = "test-vm"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["10.20.0.100"]
  tags                = local.common_tags
}

resource "azurerm_private_dns_a_record" "app_server" {
  name                = "app-server"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["10.30.0.50"]
  tags                = local.common_tags
}

# Azure Virtual Network Manager
# Provides centralized network connectivity management across subscriptions
resource "azurerm_network_manager" "main" {
  name                = local.network_manager_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Centralized network management for hybrid DNS"
  tags                = local.common_tags

  scope {
    subscription_ids = [data.azurerm_subscription.current.subscription_id]
  }

  scope_accesses = [
    "Connectivity"
  ]
}

# Network Manager Network Group
# Logical container for organizing virtual networks in the hub-spoke topology
resource "azurerm_network_manager_network_group" "hub_spoke" {
  name               = "hub-spoke-group"
  network_manager_id = azurerm_network_manager.main.id
  description        = "Network group for hub-spoke DNS topology"
}

# Static Members for Network Group
# Add virtual networks as static members of the network group
resource "azurerm_network_manager_static_member" "hub" {
  name                      = "hub-member"
  network_group_id          = azurerm_network_manager_network_group.hub_spoke.id
  target_virtual_network_id = azurerm_virtual_network.hub.id
}

resource "azurerm_network_manager_static_member" "spoke1" {
  name                      = "spoke1-member"
  network_group_id          = azurerm_network_manager_network_group.hub_spoke.id
  target_virtual_network_id = azurerm_virtual_network.spoke1.id
}

resource "azurerm_network_manager_static_member" "spoke2" {
  name                      = "spoke2-member"
  network_group_id          = azurerm_network_manager_network_group.hub_spoke.id
  target_virtual_network_id = azurerm_virtual_network.spoke2.id
}

# Network Manager Connectivity Configuration
# Defines hub-and-spoke network topology for optimized DNS resolution
resource "azurerm_network_manager_connectivity_configuration" "hub_spoke" {
  name               = "hub-spoke-connectivity"
  network_manager_id = azurerm_network_manager.main.id
  description        = "Hub-spoke connectivity for DNS resolution"
  connectivity_topology = "HubAndSpoke"

  applies_to_group {
    group_id                  = azurerm_network_manager_network_group.hub_spoke.id
    global_mesh_enabled       = false
    use_hub_gateway           = var.use_hub_gateway
    group_connectivity        = var.enable_direct_connectivity ? "DirectlyConnected" : "None"
  }

  hub {
    resource_id   = azurerm_virtual_network.hub.id
    resource_type = "Microsoft.Network/virtualNetworks"
  }

  depends_on = [
    azurerm_network_manager_static_member.hub,
    azurerm_network_manager_static_member.spoke1,
    azurerm_network_manager_static_member.spoke2
  ]
}

# Network Manager Deployment
# Deploy the connectivity configuration to establish network topology
resource "azurerm_network_manager_deployment" "main" {
  network_manager_id = azurerm_network_manager.main.id
  location           = azurerm_resource_group.main.location
  scope_access       = "Connectivity"
  configuration_ids  = [azurerm_network_manager_connectivity_configuration.hub_spoke.id]

  depends_on = [
    azurerm_network_manager_connectivity_configuration.hub_spoke
  ]
}

# Storage Account for Private Endpoint Demonstration
# Demonstrates private endpoint integration with hybrid DNS resolution
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = "TLS1_2"
  
  # Disable public network access for security
  public_network_access_enabled = false
  
  # Enable blob versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Private DNS Zone for Storage Account
# Required for private endpoint DNS resolution
resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Virtual Network Links for Storage Private DNS Zone
resource "azurerm_private_dns_zone_virtual_network_link" "storage_hub" {
  name                  = "storage-hub-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_spoke1" {
  name                  = "storage-spoke1-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.spoke1.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_spoke2" {
  name                  = "storage-spoke2-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.spoke2.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# Private Endpoint for Storage Account
# Provides secure, private access to storage account via private network
resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.spoke1_default.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "storage-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "storage-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  depends_on = [
    azurerm_storage_account.main,
    azurerm_private_dns_zone.storage_blob
  ]
}

# Network Security Group for Test VM
# Basic security rules for test virtual machine
resource "azurerm_network_security_group" "test_vm" {
  count               = var.create_test_vm ? 1 : 0
  name                = "nsg-test-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Allow SSH access from virtual network
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# Network Interface for Test VM
resource "azurerm_network_interface" "test_vm" {
  count               = var.create_test_vm ? 1 : 0
  name                = "nic-test-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke1_default.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate Network Security Group with Network Interface
resource "azurerm_network_interface_security_group_association" "test_vm" {
  count                     = var.create_test_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.test_vm[0].id
  network_security_group_id = azurerm_network_security_group.test_vm[0].id
}

# SSH Key Pair for Test VM
resource "tls_private_key" "test_vm" {
  count     = var.create_test_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Test Virtual Machine for DNS Validation
# Ubuntu VM for testing DNS resolution functionality
resource "azurerm_linux_virtual_machine" "test_vm" {
  count                           = var.create_test_vm ? 1 : 0
  name                            = "vm-test-${random_string.suffix.result}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  tags                            = local.common_tags

  network_interface_ids = [
    azurerm_network_interface.test_vm[0].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.test_vm[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Install DNS utilities for testing
  custom_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y dnsutils nmap netcat-openbsd
              EOF
  )

  depends_on = [
    azurerm_network_manager_deployment.main
  ]
}
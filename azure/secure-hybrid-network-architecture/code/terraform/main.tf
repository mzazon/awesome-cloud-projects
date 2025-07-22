# Data sources for current Azure context
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group for all hybrid network resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge({
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "hybrid-network-security"
    Recipe      = "vpn-gateway-private-link"
    ManagedBy   = "terraform"
  }, var.additional_tags)
}

# ============================================================================
# HUB VIRTUAL NETWORK AND VPN GATEWAY
# ============================================================================

# Create Hub Virtual Network for centralized connectivity
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.hub_vnet_address_space

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Hub Virtual Network"
    Purpose = "hub-network"
  })
}

# Create Gateway Subnet for VPN Gateway (required name: GatewaySubnet)
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_address_prefix]
}

# Create Public IP for VPN Gateway with Standard SKU
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "pip-vpngw-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "VPN Gateway Public IP"
    Purpose = "vpn-gateway"
  })
}

# Create VPN Gateway for secure site-to-site connectivity
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "vpngw-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  type     = "Vpn"
  vpn_type = var.vpn_type
  sku      = var.vpn_gateway_sku

  enable_bgp                = var.enable_bgp
  active_active             = false
  default_local_network_gateway_id = var.create_local_network_gateway ? azurerm_local_network_gateway.onpremises[0].id : null

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "VPN Gateway"
    Purpose = "hybrid-connectivity"
  })
}

# Create Local Network Gateway for on-premises simulation (optional)
resource "azurerm_local_network_gateway" "onpremises" {
  count               = var.create_local_network_gateway ? 1 : 0
  name                = "lng-onprem-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  gateway_address     = var.on_premises_gateway_ip != null ? var.on_premises_gateway_ip : "203.0.113.1"
  address_space       = var.on_premises_address_space

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "On-Premises Local Network Gateway"
    Purpose = "onpremises-representation"
  })
}

# ============================================================================
# SPOKE VIRTUAL NETWORK AND SUBNETS
# ============================================================================

# Create Spoke Virtual Network for application workloads
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.spoke_vnet_address_space

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Spoke Virtual Network"
    Purpose = "spoke-network"
  })
}

# Create Application Subnet for virtual machines and applications
resource "azurerm_subnet" "application" {
  name                 = "ApplicationSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.application_subnet_address_prefix]
}

# Create Private Endpoint Subnet with network policies disabled
resource "azurerm_subnet" "private_endpoint" {
  name                 = "PrivateEndpointSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.private_endpoint_subnet_address_prefix]
  
  # Disable network security group and route table policies for private endpoints
  private_endpoint_network_policies_enabled = false
}

# ============================================================================
# VNET PEERING BETWEEN HUB AND SPOKE
# ============================================================================

# Create VNet peering from Hub to Spoke with gateway transit
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "HubToSpoke"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id

  allow_gateway_transit        = true
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_gateway.vpn]
}

# Create VNet peering from Spoke to Hub with remote gateway usage
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "SpokeToHub"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_gateway_transit        = false
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = true

  depends_on = [azurerm_virtual_network_gateway.vpn]
}

# ============================================================================
# AZURE KEY VAULT FOR SECURE SECRET MANAGEMENT
# ============================================================================

# Create Key Vault for centralized secret and key management
resource "azurerm_key_vault" "main" {
  name                = "kv-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Security and access configuration
  enable_rbac_authorization   = var.enable_rbac_authorization
  purge_protection_enabled    = false
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  enabled_for_disk_encryption = true
  enabled_for_deployment      = true
  enabled_for_template_deployment = true

  # Network access rules - restrict to virtual networks
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    
    virtual_network_subnet_ids = [
      azurerm_subnet.application.id,
      azurerm_subnet.private_endpoint.id
    ]
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Key Vault"
    Purpose = "secret-management"
  })
}

# Assign Key Vault Administrator role to current user for management
resource "azurerm_role_assignment" "key_vault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Create test secret in Key Vault for validation
resource "azurerm_key_vault_secret" "test_secret" {
  name         = "test-secret"
  value        = "Hello from private endpoint connection"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.key_vault_admin]

  tags = merge(azurerm_resource_group.main.tags, {
    Purpose = "testing"
  })
}

# ============================================================================
# AZURE STORAGE ACCOUNT FOR PRIVATE LINK TESTING
# ============================================================================

# Create Storage Account with security hardening
resource "azurerm_storage_account" "main" {
  name                = "st${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = var.storage_account_kind
  
  # Security configuration
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Network access rules - deny public access by default
  public_network_access_enabled = false

  # Blob properties for enhanced security
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Storage Account"
    Purpose = "private-endpoint-demo"
  })
}

# ============================================================================
# PRIVATE DNS ZONES FOR SERVICE RESOLUTION
# ============================================================================

# Create Private DNS Zone for Key Vault service resolution
resource "azurerm_private_dns_zone" "keyvault" {
  count               = var.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Key Vault Private DNS Zone"
    Purpose = "private-dns"
  })
}

# Create Private DNS Zone for Storage Account blob service
resource "azurerm_private_dns_zone" "storage_blob" {
  count               = var.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Storage Blob Private DNS Zone"
    Purpose = "private-dns"
  })
}

# Link Key Vault Private DNS Zone to Hub VNet
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_hub" {
  count                 = var.enable_private_dns_zones ? 1 : 0
  name                  = "hub-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false

  tags = azurerm_resource_group.main.tags
}

# Link Key Vault Private DNS Zone to Spoke VNet
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_spoke" {
  count                 = var.enable_private_dns_zones ? 1 : 0
  name                  = "spoke-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false

  tags = azurerm_resource_group.main.tags
}

# Link Storage Blob Private DNS Zone to Hub VNet
resource "azurerm_private_dns_zone_virtual_network_link" "storage_hub" {
  count                 = var.enable_private_dns_zones ? 1 : 0
  name                  = "hub-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false

  tags = azurerm_resource_group.main.tags
}

# Link Storage Blob Private DNS Zone to Spoke VNet
resource "azurerm_private_dns_zone_virtual_network_link" "storage_spoke" {
  count                 = var.enable_private_dns_zones ? 1 : 0
  name                  = "spoke-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false

  tags = azurerm_resource_group.main.tags
}

# ============================================================================
# PRIVATE ENDPOINTS FOR AZURE PAAS SERVICES
# ============================================================================

# Create Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-keyvault-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "keyvault-connection"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.enable_private_dns_zones ? [1] : []
    content {
      name                 = "keyvault-dns-zone-group"
      private_dns_zone_ids = [azurerm_private_dns_zone.keyvault[0].id]
    }
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Key Vault Private Endpoint"
    Purpose = "private-connectivity"
  })
}

# Create Private Endpoint for Storage Account Blob service
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-storage-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "storage-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.enable_private_dns_zones ? [1] : []
    content {
      name                 = "storage-dns-zone-group"
      private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob[0].id]
    }
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Storage Account Private Endpoint"
    Purpose = "private-connectivity"
  })
}

# ============================================================================
# TEST VIRTUAL MACHINE FOR VALIDATION (OPTIONAL)
# ============================================================================

# Generate SSH key pair for VM authentication
resource "tls_private_key" "vm_ssh" {
  count     = var.enable_test_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create Network Security Group for test VM
resource "azurerm_network_security_group" "vm" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "nsg-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow SSH access from VNet
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = concat(var.hub_vnet_address_space, var.spoke_vnet_address_space)
    destination_address_prefix = "*"
  }

  # Allow HTTPS outbound for Azure services
  security_rule {
    name                       = "HTTPS_Outbound"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "VM Network Security Group"
    Purpose = "vm-security"
  })
}

# Create Network Interface for test VM
resource "azurerm_network_interface" "vm" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "nic-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.application.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "VM Network Interface"
    Purpose = "vm-networking"
  })
}

# Associate Network Security Group with VM Network Interface
resource "azurerm_network_interface_security_group_association" "vm" {
  count                     = var.enable_test_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.vm[0].id
  network_security_group_id = azurerm_network_security_group.vm[0].id
}

# Create test Virtual Machine with managed identity
resource "azurerm_linux_virtual_machine" "test" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "vm-test-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username

  # Disable password authentication for enhanced security
  disable_password_authentication = var.vm_disable_password_authentication

  network_interface_ids = [
    azurerm_network_interface.vm[0].id,
  ]

  # Configure OS disk
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # Use Ubuntu 22.04 LTS image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Configure SSH key authentication
  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = tls_private_key.vm_ssh[0].public_key_openssh
  }

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  tags = merge(azurerm_resource_group.main.tags, {
    Name    = "Test Virtual Machine"
    Purpose = "testing-validation"
  })
}

# Assign Key Vault Secrets User role to VM managed identity
resource "azurerm_role_assignment" "vm_key_vault_access" {
  count                = var.enable_test_vm ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.test[0].identity[0].principal_id
}

# Assign Storage Blob Data Reader role to VM managed identity
resource "azurerm_role_assignment" "vm_storage_access" {
  count                = var.enable_test_vm ? 1 : 0
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_virtual_machine.test[0].identity[0].principal_id
}
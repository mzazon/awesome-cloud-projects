# ================================================================================================
# Azure Virtual Desktop with Azure Bastion Infrastructure
# 
# This Terraform configuration deploys a secure multi-session virtual desktop infrastructure
# using Azure Virtual Desktop and Azure Bastion for secure administrative access.
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------------------------

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Get current Azure AD user for Key Vault access
data "azuread_client_config" "current" {}

# ------------------------------------------------------------------------------------------------
# Random Resources
# ------------------------------------------------------------------------------------------------

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Generate secure password for session host VMs
resource "random_password" "admin_password" {
  count   = var.session_host_admin_password == null ? 1 : 0
  length  = 24
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# ------------------------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------------------------

locals {
  # Resource naming with prefix and random suffix
  resource_suffix = random_string.suffix.result
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    CreatedBy     = "Terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    ResourceGroup = var.resource_group_name != null ? var.resource_group_name : "rg-${var.name_prefix}-${local.resource_suffix}"
  })
  
  # Certificate subject with dynamic FQDN
  certificate_subject = var.certificate_subject != null ? var.certificate_subject : "CN=${var.name_prefix}-${local.resource_suffix}.${var.location}.cloudapp.azure.com"
  
  # Session host admin password from variable or generated
  admin_password = var.session_host_admin_password != null ? var.session_host_admin_password : random_password.admin_password[0].result
}

# ------------------------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------------------------

# Create resource group for all AVD infrastructure
resource "azurerm_resource_group" "avd" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.name_prefix}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# ------------------------------------------------------------------------------------------------
# Networking Infrastructure
# ------------------------------------------------------------------------------------------------

# Create virtual network for AVD infrastructure
resource "azurerm_virtual_network" "avd" {
  name                = "vnet-${var.name_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

# Create subnet for AVD session hosts
resource "azurerm_subnet" "avd_hosts" {
  name                 = "subnet-avd-hosts"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = [var.avd_subnet_address_prefix]
}

# Create subnet for Azure Bastion (must be named AzureBastionSubnet)
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

# ------------------------------------------------------------------------------------------------
# Network Security Groups
# ------------------------------------------------------------------------------------------------

# Create NSG for AVD session hosts subnet
resource "azurerm_network_security_group" "avd_hosts" {
  name                = "nsg-avd-hosts"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = local.common_tags

  # Allow Azure Virtual Desktop service traffic outbound
  security_rule {
    name                       = "AllowAVDServiceTraffic"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "WindowsVirtualDesktop"
  }

  # Allow Azure Bastion inbound communication
  security_rule {
    name                       = "AllowBastionInbound"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3389", "22"]
    source_address_prefix      = var.bastion_subnet_address_prefix
    destination_address_prefix = "*"
  }

  # Allow internal subnet communication
  security_rule {
    name                       = "AllowInternalSubnet"
    priority                   = 1200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.avd_subnet_address_prefix
    destination_address_prefix = var.avd_subnet_address_prefix
  }

  # Allow Azure AD DS synchronization (if domain joined)
  security_rule {
    name                       = "AllowAzureADDSSync"
    priority                   = 1300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureActiveDirectoryDomainServices"
  }
}

# Associate NSG with AVD hosts subnet
resource "azurerm_subnet_network_security_group_association" "avd_hosts" {
  subnet_id                 = azurerm_subnet.avd_hosts.id
  network_security_group_id = azurerm_network_security_group.avd_hosts.id
}

# ------------------------------------------------------------------------------------------------
# Azure Key Vault
# ------------------------------------------------------------------------------------------------

# Create Key Vault for certificate and secret management
resource "azurerm_key_vault" "avd" {
  name                          = "kv-${var.name_prefix}-${local.resource_suffix}"
  location                      = azurerm_resource_group.avd.location
  resource_group_name           = azurerm_resource_group.avd.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku_name
  soft_delete_retention_days    = var.key_vault_soft_delete_retention_days
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  enabled_for_disk_encryption   = var.key_vault_enabled_for_disk_encryption
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  enable_rbac_authorization     = true
  tags                         = local.common_tags
}

# Grant current user access to Key Vault for certificate management
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = azurerm_key_vault.avd.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azuread_client_config.current.object_id
}

# Store session host admin password in Key Vault
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "avd-admin-password"
  value        = local.admin_password
  key_vault_id = azurerm_key_vault.avd.id
  tags         = local.common_tags

  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

# Create SSL certificate for AVD services
resource "azurerm_key_vault_certificate" "avd_ssl" {
  name         = "avd-ssl-cert"
  key_vault_id = azurerm_key_vault.avd.id
  tags         = local.common_tags

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = local.certificate_subject
      validity_in_months = var.certificate_validity_months

      extended_key_usage = [
        "1.3.6.1.5.5.7.3.1", # Server Authentication
        "1.3.6.1.5.5.7.3.2"  # Client Authentication
      ]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment"
      ]
    }
  }

  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

# ------------------------------------------------------------------------------------------------
# Azure Bastion
# ------------------------------------------------------------------------------------------------

# Create public IP for Azure Bastion
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${local.resource_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Deploy Azure Bastion for secure VM access
resource "azurerm_bastion_host" "avd" {
  name                   = "bastion-${var.name_prefix}-${local.resource_suffix}"
  location               = azurerm_resource_group.avd.location
  resource_group_name    = azurerm_resource_group.avd.name
  sku                    = var.bastion_sku
  copy_paste_enabled     = var.bastion_copy_paste_enabled
  file_copy_enabled      = var.bastion_sku == "Standard" ? var.bastion_file_copy_enabled : null
  ip_connect_enabled     = var.bastion_sku == "Standard" ? var.bastion_ip_connect_enabled : null
  shareable_link_enabled = var.bastion_sku == "Standard" ? var.bastion_shareable_link_enabled : null
  tunneling_enabled      = var.bastion_sku == "Standard" ? var.bastion_tunneling_enabled : null
  tags                   = local.common_tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# ------------------------------------------------------------------------------------------------
# Azure Virtual Desktop Host Pool
# ------------------------------------------------------------------------------------------------

# Create AVD host pool for multi-session desktops
resource "azurerm_virtual_desktop_host_pool" "avd" {
  name                     = "hp-${var.name_prefix}-${local.resource_suffix}"
  location                 = azurerm_resource_group.avd.location
  resource_group_name      = azurerm_resource_group.avd.name
  type                     = var.host_pool_type
  load_balancer_type       = var.host_pool_type == "Pooled" ? var.load_balancer_type : null
  maximum_sessions_allowed = var.host_pool_type == "Pooled" ? var.max_session_limit : null
  start_vm_on_connect      = var.start_vm_on_connect
  preferred_app_group_type = var.preferred_app_group_type
  validate_environment     = false
  description              = "Multi-session virtual desktop host pool managed by Terraform"
  tags                     = local.common_tags
}

# Generate registration token for session hosts
resource "azurerm_virtual_desktop_host_pool_registration_info" "avd" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.avd.id
  expiration_date = timeadd(timestamp(), "48h")
}

# ------------------------------------------------------------------------------------------------
# Azure Virtual Desktop Application Group
# ------------------------------------------------------------------------------------------------

# Create desktop application group
resource "azurerm_virtual_desktop_application_group" "avd" {
  name                = "ag-${var.name_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.avd.id
  friendly_name       = "Desktop Application Group"
  description         = "Desktop application group for multi-session virtual desktops"
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------------------------
# Azure Virtual Desktop Workspace
# ------------------------------------------------------------------------------------------------

# Create AVD workspace for user access
resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = "ws-${var.name_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  friendly_name       = "Remote Desktop Workspace"
  description         = "Workspace for accessing virtual desktop sessions"
  tags                = local.common_tags
}

# Associate application group with workspace
resource "azurerm_virtual_desktop_workspace_application_group_association" "avd" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.avd.id
}

# ------------------------------------------------------------------------------------------------
# Session Host Virtual Machines
# ------------------------------------------------------------------------------------------------

# Network interfaces for session host VMs
resource "azurerm_network_interface" "session_hosts" {
  count               = var.session_host_count
  name                = "nic-avd-host-${format("%02d", count.index + 1)}-${local.resource_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.avd_hosts.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Session host virtual machines
resource "azurerm_windows_virtual_machine" "session_hosts" {
  count               = var.session_host_count
  name                = "vm-avd-host-${format("%02d", count.index + 1)}-${local.resource_suffix}"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  size                = var.session_host_vm_size
  admin_username      = var.session_host_admin_username
  admin_password      = local.admin_password
  tags                = merge(local.common_tags, {
    Role = "SessionHost"
    HostIndex = count.index + 1
  })

  # Disable password authentication for enhanced security
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.session_hosts[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = var.session_host_image.publisher
    offer     = var.session_host_image.offer
    sku       = var.session_host_image.sku
    version   = var.session_host_image.version
  }

  # Enable system-assigned managed identity for Azure services access
  identity {
    type = "SystemAssigned"
  }

  # Ensure Key Vault is created before VMs
  depends_on = [azurerm_key_vault_secret.admin_password]
}

# ------------------------------------------------------------------------------------------------
# Session Host AVD Agent Installation
# ------------------------------------------------------------------------------------------------

# Install AVD agent and register session hosts with host pool
resource "azurerm_virtual_machine_extension" "avd_agent" {
  count                      = var.session_host_count
  name                       = "AVD-Agent"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_hosts[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.77"
  auto_upgrade_minor_version = true
  tags                       = local.common_tags

  settings = jsonencode({
    modulesUrl = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02507.240.zip"
    configurationFunction = "Configuration.ps1\\Configuration"
    properties = {
      RegistrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.avd.token
      aadJoin               = false
    }
  })

  # Ensure host pool registration token is available
  depends_on = [azurerm_virtual_desktop_host_pool_registration_info.avd]
}

# Grant session host VMs access to Key Vault for certificate retrieval
resource "azurerm_role_assignment" "session_hosts_kv_reader" {
  count                = var.session_host_count
  scope                = azurerm_key_vault.avd.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_virtual_machine.session_hosts[count.index].identity[0].principal_id
}

# ------------------------------------------------------------------------------------------------
# Optional: Domain Join Configuration
# ------------------------------------------------------------------------------------------------

# Domain join extension for session hosts (optional)
resource "azurerm_virtual_machine_extension" "domain_join" {
  count                      = var.domain_name != null ? var.session_host_count : 0
  name                       = "DomainJoin"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_hosts[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  tags                       = local.common_tags

  settings = jsonencode({
    Name = var.domain_name
    OUPath = var.ou_path
    User = var.domain_user_upn
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = var.domain_password
  })

  # Ensure AVD agent is installed before domain join
  depends_on = [azurerm_virtual_machine_extension.avd_agent]
}
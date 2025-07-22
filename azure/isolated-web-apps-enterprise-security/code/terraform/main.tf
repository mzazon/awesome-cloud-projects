# ---------------------------------------------------------------------------------------------------------------------
# AZURE APP SERVICE ENVIRONMENT v3 WITH PRIVATE DNS - MAIN CONFIGURATION
# 
# This Terraform configuration deploys an enterprise-grade isolated web application hosting solution
# using Azure App Service Environment v3, Azure Private DNS, and Azure NAT Gateway.
# 
# Architecture includes:
# - Azure App Service Environment v3 with internal load balancer
# - Azure Private DNS zone for internal service discovery
# - Azure NAT Gateway for predictable outbound connectivity
# - Azure Bastion for secure management access
# - Management VM for administrative tasks
# - Complete network isolation with proper subnet segmentation
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# RANDOM SUFFIX FOR UNIQUE RESOURCE NAMES
# ---------------------------------------------------------------------------------------------------------------------

resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate random suffix if enabled
  random_suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Create resource names with optional random suffix
  resource_group_name = "${var.resource_prefix}-${var.environment}${local.random_suffix != "" ? "-${local.random_suffix}" : ""}"
  
  # Merge common tags with additional tags
  common_tags = merge(var.common_tags, var.additional_tags, {
    Environment = var.environment
    Location    = var.location
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_group_name}"
  location = var.location
  
  tags = merge(local.common_tags, {
    Purpose = "enterprise-isolation"
    Tier    = "resource-management"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# VIRTUAL NETWORK WITH ENTERPRISE SUBNET SEGMENTATION
# ---------------------------------------------------------------------------------------------------------------------

# Main virtual network for enterprise isolation
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.resource_group_name}"
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    Purpose = "enterprise-isolation"
    Tier    = "network"
  })
}

# App Service Environment subnet - requires /24 minimum for proper scaling
resource "azurerm_subnet" "ase" {
  name                 = "snet-ase-${local.random_suffix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.ase_subnet_address_prefix]
  
  # Enable service endpoints for ASE requirements
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault"
  ]
  
  # Delegate subnet to App Service Environment
  delegation {
    name = "ase-delegation"
    service_delegation {
      name    = "Microsoft.Web/hostingEnvironments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

# NAT Gateway subnet for outbound connectivity
resource "azurerm_subnet" "nat" {
  name                 = "snet-nat-${local.random_suffix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.nat_subnet_address_prefix]
}

# Support subnet for management services
resource "azurerm_subnet" "support" {
  name                 = "snet-support-${local.random_suffix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.support_subnet_address_prefix]
}

# Azure Bastion subnet - must be named AzureBastionSubnet
resource "azurerm_subnet" "bastion" {
  count                = var.enable_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

# ---------------------------------------------------------------------------------------------------------------------
# NAT GATEWAY FOR PREDICTABLE OUTBOUND CONNECTIVITY
# ---------------------------------------------------------------------------------------------------------------------

# Public IP for NAT Gateway with static allocation
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(local.common_tags, {
    Purpose = "nat-gateway"
    Tier    = "network"
  })
}

# NAT Gateway for enterprise-grade outbound connectivity
resource "azurerm_nat_gateway" "main" {
  name                    = "nat-gateway-${local.random_suffix}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout
  
  tags = merge(local.common_tags, {
    Purpose = "outbound-connectivity"
    Tier    = "network"
  })
}

# Associate public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with ASE subnet
resource "azurerm_subnet_nat_gateway_association" "ase" {
  subnet_id      = azurerm_subnet.ase.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE PRIVATE DNS ZONE FOR INTERNAL SERVICE DISCOVERY
# ---------------------------------------------------------------------------------------------------------------------

# Private DNS zone for enterprise internal domain
resource "azurerm_private_dns_zone" "main" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    Purpose = "internal-dns"
    Tier    = "network"
  })
}

# Link private DNS zone to virtual network
resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "link-${azurerm_virtual_network.main.name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  
  tags = merge(local.common_tags, {
    Purpose = "dns-link"
    Tier    = "network"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE APP SERVICE ENVIRONMENT V3
# ---------------------------------------------------------------------------------------------------------------------

# App Service Environment v3 with internal load balancer for complete isolation
resource "azurerm_app_service_environment_v3" "main" {
  name                         = "ase-${local.random_suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  subnet_id                    = azurerm_subnet.ase.id
  internal_load_balancing_mode = "Web, Publishing"
  zone_redundant               = var.ase_zone_redundant
  
  # Configure cluster settings for enterprise requirements
  cluster_setting {
    name  = "DisableTls1.0"
    value = "1"
  }
  
  cluster_setting {
    name  = "FrontEndSSLCipherSuiteOrder"
    value = "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
  }
  
  cluster_setting {
    name  = "InternalEncryption"
    value = "true"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "enterprise-isolation"
    Tier    = "compute"
  })
  
  # ASE deployment takes 60-90 minutes, so increase timeout
  timeouts {
    create = "2h"
    update = "1h"
    delete = "1h"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# APP SERVICE PLAN IN ASE
# ---------------------------------------------------------------------------------------------------------------------

# App Service Plan with Isolated v2 SKU for dedicated resources
resource "azurerm_service_plan" "main" {
  name                       = "asp-${local.random_suffix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  os_type                    = "Windows"
  sku_name                   = var.app_service_plan_sku
  app_service_environment_id = azurerm_app_service_environment_v3.main.id
  worker_count               = var.app_service_plan_capacity
  
  tags = merge(local.common_tags, {
    Purpose = "enterprise-app"
    Tier    = "compute"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# WEB APPLICATION
# ---------------------------------------------------------------------------------------------------------------------

# Enterprise web application with enhanced security configuration
resource "azurerm_windows_web_app" "main" {
  name                = "webapp-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = var.web_app_https_only
  
  # Configure site settings for enterprise requirements
  site_config {
    always_on                         = var.web_app_always_on
    ftps_state                       = "Disabled"
    http2_enabled                    = true
    minimum_tls_version              = "1.2"
    use_32_bit_worker                = false
    websockets_enabled               = false
    managed_pipeline_mode            = "Integrated"
    default_document_type            = "index.html"
    
    # Configure application stack
    application_stack {
      current_stack  = "dotnet"
      dotnet_version = "v8.0"
    }
    
    # IP restrictions for enhanced security
    ip_restriction {
      action      = "Allow"
      ip_address  = var.virtual_network_address_space[0]
      name        = "AllowVNetTraffic"
      priority    = 100
    }
  }
  
  # Application settings for enterprise configuration
  app_settings = {
    "WEBSITE_DNS_SERVER"                = "168.63.129.16"
    "WEBSITE_VNET_ROUTE_ALL"           = "1"
    "ASPNETCORE_ENVIRONMENT"           = "Production"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"  = "true"
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
  }
  
  # Connection strings for database connectivity
  connection_string {
    name  = "DefaultConnection"
    type  = "SQLServer"
    value = "Data Source=tcp:sql-server.${var.private_dns_zone_name},1433;Initial Catalog=AppDatabase;Integrated Security=false;"
  }
  
  # Configure backup settings
  backup {
    name     = "enterprise-backup"
    enabled  = true
    schedule {
      frequency_interval       = 1
      frequency_unit          = "Day"
      keep_at_least_one_backup = true
      retention_period_days    = 30
    }
  }
  
  # Configure logs
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    
    application_logs {
      file_system_level = "Information"
    }
    
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "enterprise-app"
    Tier    = "application"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# PRIVATE DNS RECORDS FOR SERVICE DISCOVERY
# ---------------------------------------------------------------------------------------------------------------------

# DNS A record for web application
resource "azurerm_private_dns_a_record" "webapp" {
  name                = "webapp"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_app_service_environment_v3.main.internal_inbound_ip_addresses[0]]
  
  tags = merge(local.common_tags, {
    Purpose = "dns-record"
    Tier    = "network"
  })
}

# DNS A record for API services
resource "azurerm_private_dns_a_record" "api" {
  name                = "api"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_app_service_environment_v3.main.internal_inbound_ip_addresses[0]]
  
  tags = merge(local.common_tags, {
    Purpose = "dns-record"
    Tier    = "network"
  })
}

# Wildcard DNS record for subdomain routing
resource "azurerm_private_dns_a_record" "wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_app_service_environment_v3.main.internal_inbound_ip_addresses[0]]
  
  tags = merge(local.common_tags, {
    Purpose = "dns-record"
    Tier    = "network"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE BASTION FOR SECURE MANAGEMENT ACCESS
# ---------------------------------------------------------------------------------------------------------------------

# Public IP for Azure Bastion
resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-bastion-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(local.common_tags, {
    Purpose = "bastion"
    Tier    = "management"
  })
}

# Azure Bastion for secure management access
resource "azurerm_bastion_host" "main" {
  count               = var.enable_bastion ? 1 : 0
  name                = "bastion-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.bastion_sku
  
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
  
  tags = merge(local.common_tags, {
    Purpose = "secure-management"
    Tier    = "management"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# MANAGEMENT VIRTUAL MACHINE
# ---------------------------------------------------------------------------------------------------------------------

# Network interface for management VM
resource "azurerm_network_interface" "management_vm" {
  count               = var.enable_management_vm ? 1 : 0
  name                = "nic-vm-management-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.support.id
    private_ip_address_allocation = "Dynamic"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "management"
    Tier    = "compute"
  })
}

# Network security group for management VM
resource "azurerm_network_security_group" "management_vm" {
  count               = var.enable_management_vm ? 1 : 0
  name                = "nsg-vm-management-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Allow RDP from Bastion subnet
  security_rule {
    name                       = "AllowBastionRDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.bastion_subnet_address_prefix
    destination_address_prefix = "*"
  }
  
  # Allow HTTP/HTTPS outbound for management tasks
  security_rule {
    name                       = "AllowHTTPSOutbound"
    priority                   = 1010
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "management"
    Tier    = "security"
  })
}

# Associate NSG with network interface
resource "azurerm_network_interface_security_group_association" "management_vm" {
  count                     = var.enable_management_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.management_vm[0].id
  network_security_group_id = azurerm_network_security_group.management_vm[0].id
}

# Management virtual machine
resource "azurerm_windows_virtual_machine" "management" {
  count               = var.enable_management_vm ? 1 : 0
  name                = "vm-management-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.management_vm_size
  admin_username      = var.management_vm_admin_username
  admin_password      = var.management_vm_admin_password
  
  # Disable password authentication for enhanced security
  disable_password_authentication = false
  
  network_interface_ids = [
    azurerm_network_interface.management_vm[0].id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "management"
    Tier    = "compute"
  })
}

# VM extension for management tools installation
resource "azurerm_virtual_machine_extension" "management_tools" {
  count                      = var.enable_management_vm ? 1 : 0
  name                       = "install-management-tools"
  virtual_machine_id         = azurerm_windows_virtual_machine.management[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name Web-Server -IncludeManagementTools; Install-WindowsFeature -Name RSAT-DNS-Server; Install-WindowsFeature -Name RSAT-AD-Tools\""
    }
SETTINGS
  
  tags = merge(local.common_tags, {
    Purpose = "management-tools"
    Tier    = "compute"
  })
}
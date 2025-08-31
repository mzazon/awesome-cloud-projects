# Main Terraform Configuration for Automated Server Patching with Update Manager
# This configuration creates all necessary resources for demonstrating Azure Update Manager
# with automated patching schedules and email notifications

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and common configurations
locals {
  resource_suffix = random_string.suffix.result
  common_tags = merge(var.tags, {
    Environment = var.environment
    CreatedDate = timestamp()
  })
  
  # Resource names with consistent naming convention
  resource_group_name         = "rg-${var.resource_prefix}-${local.resource_suffix}"
  vm_name                    = "vm-${var.resource_prefix}-${local.resource_suffix}"
  action_group_name          = "ag-${var.resource_prefix}-${local.resource_suffix}"
  maintenance_config_name    = "mc-${var.resource_prefix}-${local.resource_suffix}"
  vnet_name                 = "vnet-${var.resource_prefix}-${local.resource_suffix}"
  subnet_name               = "subnet-${var.resource_prefix}-${local.resource_suffix}"
  nsg_name                  = "nsg-${var.resource_prefix}-${local.resource_suffix}"
  public_ip_name            = "pip-${var.resource_prefix}-${local.resource_suffix}"
  nic_name                  = "nic-${var.resource_prefix}-${local.resource_suffix}"
  
  # Maintenance window configuration
  maintenance_duration = "0${var.maintenance_window_duration}:00"
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all patching demo resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Virtual Network for VM networking
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Create Subnet for virtual machine
resource "azurerm_subnet" "main" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create Network Security Group for basic VM protection
resource "azurerm_network_security_group" "main" {
  name                = local.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Allow RDP access for Windows VM management (restrict in production)
  security_rule {
    name                       = "AllowRDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP outbound for Windows Updates
  security_rule {
    name                       = "AllowHTTPOutbound"
    priority                   = 1001
    direction                  = "Outbound"  
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS outbound for Windows Updates
  security_rule {
    name                       = "AllowHTTPSOutbound"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate Network Security Group with Subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Create Public IP for virtual machine access
resource "azurerm_public_ip" "main" {
  name                = local.public_ip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                = "Standard"
  tags               = local.common_tags
}

# Create Network Interface for virtual machine
resource "azurerm_network_interface" "main" {
  name                = local.nic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Create Windows Virtual Machine for patching demonstration
resource "azurerm_windows_virtual_machine" "main" {
  name                = local.vm_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = local.common_tags

  # Disable password authentication for better security (when using SSH keys)
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  os_disk {
    name                 = "${local.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  # Configure patch settings for Azure Update Manager
  patch_mode                                             = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  patch_assessment_mode                                  = "AutomaticByPlatform"

  # Ensure VM is created before other dependent resources
  lifecycle {
    create_before_destroy = false
  }
}

# Create Action Group for patch deployment notifications
resource "azurerm_monitor_action_group" "main" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "PatchAlert"
  tags                = local.common_tags

  # Configure email notification receiver
  email_receiver {
    name          = "PatchNotificationEmail"
    email_address = var.notification_email
  }
}

# Create Maintenance Configuration for scheduled patching
resource "azurerm_maintenance_configuration" "main" {
  name                = local.maintenance_config_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  scope               = "InGuestPatch"
  tags                = local.common_tags

  # Configure maintenance window timing
  window {
    start_date_time      = var.maintenance_window_start_time
    duration             = local.maintenance_duration
    time_zone            = var.maintenance_window_time_zone
    recur_every          = "1${var.maintenance_recurrence}"
    week_days            = var.maintenance_recurrence == "Week" ? var.maintenance_week_days : null
  }

  # Configure Windows patching parameters
  install_patches {
    reboot = var.reboot_setting

    windows {
      classifications_to_include = var.patch_classifications
      kb_numbers_to_exclude     = []
      kb_numbers_to_include     = []
    }
  }

  # Ensure maintenance configuration is created after VM
  depends_on = [azurerm_windows_virtual_machine.main]
}

# Assign Virtual Machine to Maintenance Configuration
resource "azurerm_maintenance_assignment_virtual_machine" "main" {
  location                     = azurerm_resource_group.main.location
  maintenance_configuration_id = azurerm_maintenance_configuration.main.id
  virtual_machine_id          = azurerm_windows_virtual_machine.main.id
}

# Create Activity Log Alert for maintenance configuration operations
resource "azurerm_monitor_activity_log_alert" "maintenance_config" {
  name                = "alert-maintenance-config-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_resource_group.main.id]
  description         = "Alert when maintenance configuration operations occur"
  tags                = local.common_tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Maintenance/maintenanceConfigurations/write"
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Create Activity Log Alert for maintenance assignment operations  
resource "azurerm_monitor_activity_log_alert" "maintenance_assignment" {
  name                = "alert-maintenance-assignment-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_resource_group.main.id]
  description         = "Alert when maintenance assignments are created or updated"
  tags                = local.common_tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Maintenance/configurationAssignments/write"
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Create Activity Log Alert for virtual machine patch operations
resource "azurerm_monitor_activity_log_alert" "vm_patch_operations" {
  name                = "alert-vm-patch-ops-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_windows_virtual_machine.main.id]
  description         = "Alert when VM patch operations are performed"
  tags                = local.common_tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/assessPatches/action"
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
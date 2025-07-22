# Local values for consistent naming and tagging
locals {
  # Generate a random suffix for unique resource names
  random_suffix = random_string.suffix.result
  
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment         = var.environment
    Project            = var.project_name
    Purpose            = "migration-demo"
    CreatedBy          = "terraform"
    ManagedBy          = "terraform"
    LastUpdated        = formatdate("YYYY-MM-DD", timestamp())
    SourceRegion       = var.source_region
    TargetRegion       = var.target_region
  }, var.additional_tags)
  
  # Resource naming with random suffix
  resource_group_source_name = "rg-${local.name_prefix}-source-${local.random_suffix}"
  resource_group_target_name = "rg-${local.name_prefix}-target-${local.random_suffix}"
  log_analytics_name         = "law-${local.name_prefix}-${local.random_suffix}"
  move_collection_name       = "mc-${local.name_prefix}-${local.random_suffix}"
  maintenance_config_name    = "maint-${local.name_prefix}-${local.random_suffix}"
  workbook_name             = "wb-migration-${local.random_suffix}"
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate SSH key pair for Linux VM if public key path doesn't exist
resource "local_file" "ssh_private_key" {
  count           = var.vm_admin_password == null && !fileexists(var.ssh_public_key_path) ? 1 : 0
  filename        = "${path.module}/ssh_private_key"
  content         = tls_private_key.ssh[0].private_key_pem
  file_permission = "0600"
}

resource "tls_private_key" "ssh" {
  count     = var.vm_admin_password == null && !fileexists(var.ssh_public_key_path) ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "ssh_public_key" {
  count           = var.vm_admin_password == null && !fileexists(var.ssh_public_key_path) ? 1 : 0
  filename        = "${path.module}/ssh_public_key.pub"
  content         = tls_private_key.ssh[0].public_key_openssh
  file_permission = "0644"
}

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Source region resource group
resource "azurerm_resource_group" "source" {
  name     = local.resource_group_source_name
  location = var.source_region
  tags     = local.common_tags
}

# Target region resource group
resource "azurerm_resource_group" "target" {
  name     = local.resource_group_target_name
  location = var.target_region
  tags     = local.common_tags
}

# Log Analytics workspace for monitoring and logging
resource "azurerm_log_analytics_workspace" "migration" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Virtual network in source region
resource "azurerm_virtual_network" "source" {
  name                = "vnet-${local.name_prefix}-source"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  tags                = local.common_tags
}

# Subnet in source virtual network
resource "azurerm_subnet" "source" {
  name                 = "subnet-default"
  resource_group_name  = azurerm_resource_group.source.name
  virtual_network_name = azurerm_virtual_network.source.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network security group for source region
resource "azurerm_network_security_group" "source" {
  name                = "nsg-${local.name_prefix}-source"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  tags                = local.common_tags

  # Allow SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP access for testing
  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "source" {
  subnet_id                 = azurerm_subnet.source.id
  network_security_group_id = azurerm_network_security_group.source.id
}

# Public IP for virtual machine
resource "azurerm_public_ip" "vm" {
  name                = "pip-vm-${local.name_prefix}-source"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network interface for virtual machine
resource "azurerm_network_interface" "vm" {
  name                = "nic-vm-${local.name_prefix}-source"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.source.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

# Virtual machine for migration testing
resource "azurerm_linux_virtual_machine" "test" {
  name                = "vm-${local.name_prefix}-test"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  tags                = local.common_tags

  # Disable password authentication if SSH keys are used
  disable_password_authentication = var.vm_admin_password == null

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  # OS disk configuration
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    name                 = "osdisk-vm-${local.name_prefix}-test"
  }

  # Ubuntu 22.04 LTS image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Authentication configuration
  dynamic "admin_ssh_key" {
    for_each = var.vm_admin_password == null ? [1] : []
    content {
      username = var.vm_admin_username
      public_key = fileexists(var.ssh_public_key_path) ? file(var.ssh_public_key_path) : (
        length(local_file.ssh_public_key) > 0 ? local_file.ssh_public_key[0].content : ""
      )
    }
  }

  # Use password authentication if SSH key is not provided
  admin_password = var.vm_admin_password

  # Identity configuration for Update Manager
  identity {
    type = "SystemAssigned"
  }

  # Custom data for initial VM setup
  custom_data = base64encode(<<-EOF
#!/bin/bash
apt-get update
apt-get install -y curl wget htop
systemctl enable ssh
systemctl start ssh

# Install Azure CLI for demonstration purposes
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Create a simple web server for testing
echo "<html><body><h1>Migration Test VM</h1><p>This VM is ready for Azure Resource Mover migration.</p></body></html>" > /var/www/html/index.html
systemctl enable apache2 2>/dev/null || apt-get install -y apache2
systemctl start apache2 2>/dev/null || systemctl restart apache2
EOF
  )
}

# Data disk for virtual machine to demonstrate storage migration
resource "azurerm_managed_disk" "data" {
  name                 = "datadisk-vm-${local.name_prefix}-test"
  location             = azurerm_resource_group.source.location
  resource_group_name  = azurerm_resource_group.source.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.common_tags
}

# Attach data disk to virtual machine
resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.test.id
  lun                = "0"
  caching            = "ReadWrite"
}

# Maintenance configuration for Update Manager
resource "azurerm_maintenance_configuration" "vm_updates" {
  name                = local.maintenance_config_name
  location            = azurerm_resource_group.target.location
  resource_group_name = azurerm_resource_group.target.name
  scope               = "InGuestPatch"
  tags                = local.common_tags

  # Maintenance window configuration
  window {
    start_date_time      = "2024-01-15 ${var.maintenance_window_start_time}:00"
    duration             = "${format("%02d", var.maintenance_window_duration)}:00"
    time_zone            = "UTC"
    recur_every          = "1Week"
    expiration_date_time = "2025-01-15 ${var.maintenance_window_start_time}:00"
  }

  # Install patches configuration for Linux
  install_patches {
    linux {
      classifications_to_include = var.patch_classifications
      package_names_mask_to_exclude = ["test*"]
      package_names_mask_to_include = ["*"]
    }
    reboot = var.reboot_setting
  }

  # Enable visibility into maintenance operations
  visibility = "Public"
}

# VM Extension for Azure Monitor Agent (if monitoring is enabled)
resource "azurerm_virtual_machine_extension" "monitor_agent" {
  count = var.enable_monitoring ? 1 : 0

  name                 = "AzureMonitorLinuxAgent"
  virtual_machine_id   = azurerm_linux_virtual_machine.test.id
  publisher            = "Microsoft.Azure.Monitor"
  type                 = "AzureMonitorLinuxAgent"
  type_handler_version = "1.0"
  tags                 = local.common_tags

  settings = jsonencode({
    workspaceId = azurerm_log_analytics_workspace.migration.workspace_id
  })

  protected_settings = jsonencode({
    workspaceKey = azurerm_log_analytics_workspace.migration.primary_shared_key
  })
}

# Data Collection Rule for Azure Monitor (if monitoring is enabled)
resource "azurerm_monitor_data_collection_rule" "vm_monitoring" {
  count = var.enable_monitoring ? 1 : 0

  name                = "dcr-${local.name_prefix}-vm"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  tags                = local.common_tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.migration.id
      name                  = "destination-log"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf"]
    destinations = ["destination-log"]
  }

  data_sources {
    syslog {
      facility_names = ["*"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
      name           = "datasource-syslog"
    }

    performance_counter {
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\Memory\\% Used Memory",
        "\\Logical Disk(_Total)\\% Used Space"
      ]
      name = "datasource-perfcounter"
    }
  }
}

# Associate Data Collection Rule with VM (if monitoring is enabled)
resource "azurerm_monitor_data_collection_rule_association" "vm_monitoring" {
  count = var.enable_monitoring ? 1 : 0

  name                    = "dcra-${local.name_prefix}-vm"
  target_resource_id      = azurerm_linux_virtual_machine.test.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vm_monitoring[0].id
}

# Azure Workbook for migration monitoring
resource "azurerm_application_insights_workbook" "migration_monitoring" {
  name                = local.workbook_name
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  display_name        = "Infrastructure Migration Monitoring"
  tags                = local.common_tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Infrastructure Migration Dashboard\n\nThis workbook provides comprehensive monitoring for Azure Resource Mover migration workflows and Update Manager compliance status.\n\n## Overview\n\n- **Source Region**: ${var.source_region}\n- **Target Region**: ${var.target_region}\n- **Project**: ${var.project_name}\n- **Environment**: ${var.environment}"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AzureActivity\n| where TimeGenerated > ago(24h)\n| where ResourceProvider == \"Microsoft.Migrate\"\n| summarize OperationCount = count() by OperationName, ResourceType\n| order by OperationCount desc"
          size = 0
          title = "Migration Operations by Resource Type (24h)"
          timeContext = {
            durationMs = 86400000
          }
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.migration.id]
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "Update\n| where TimeGenerated > ago(7d)\n| where Computer != \"\"\n| summarize ComplianceCount = count() by Classification\n| order by ComplianceCount desc"
          size = 0
          title = "Update Compliance by Classification (7d)"
          timeContext = {
            durationMs = 604800000
          }
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.migration.id]
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "Heartbeat\n| where TimeGenerated > ago(1h)\n| where ResourceGroup contains \"${var.project_name}\"\n| summarize by Computer, ResourceGroup, RemoteIPLatitude, RemoteIPLongitude\n| project Computer, ResourceGroup, Location=strcat(RemoteIPLatitude, \",\", RemoteIPLongitude)"
          size = 0
          title = "Active VMs by Region"
          timeContext = {
            durationMs = 3600000
          }
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.migration.id]
        }
      }
    ]
  })
}

# Output important information for user reference
output "migration_info" {
  description = "Important information about the migration setup"
  value = {
    source_resource_group    = azurerm_resource_group.source.name
    target_resource_group    = azurerm_resource_group.target.name
    log_analytics_workspace = azurerm_log_analytics_workspace.migration.name
    maintenance_configuration = azurerm_maintenance_configuration.vm_updates.name
    vm_name                  = azurerm_linux_virtual_machine.test.name
    vm_public_ip            = azurerm_public_ip.vm.ip_address
    workbook_name           = azurerm_application_insights_workbook.migration_monitoring.display_name
  }
}
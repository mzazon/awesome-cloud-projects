# Main Terraform Configuration for Azure Chaos Studio and Application Insights Recipe
# This file creates all the infrastructure components needed for chaos engineering testing

# Generate random suffixes for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all chaos testing resources
resource "azurerm_resource_group" "chaos_testing" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-chaos-testing-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Resource Group"
    Description = "Resource group for Azure Chaos Studio and Application Insights testing"
  })
}

# Create Log Analytics Workspace for Application Insights backend
resource "azurerm_log_analytics_workspace" "chaos_workspace" {
  name                = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "log-chaos-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Log Analytics Workspace"
    Description = "Log Analytics workspace for chaos engineering telemetry"
  })
}

# Create Application Insights for monitoring chaos experiments
resource "azurerm_application_insights" "chaos_insights" {
  name                = var.application_insights_name != "" ? var.application_insights_name : "appi-chaos-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name
  workspace_id        = azurerm_log_analytics_workspace.chaos_workspace.id
  application_type    = var.application_insights_type

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Application Insights"
    Description = "Application Insights for monitoring chaos experiments"
  })
}

# Create Virtual Network for VM resources
resource "azurerm_virtual_network" "chaos_vnet" {
  name                = var.vnet_name != "" ? var.vnet_name : "vnet-chaos-${random_string.suffix.result}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Virtual Network"
    Description = "Virtual network for chaos testing VM resources"
  })
}

# Create Subnet for virtual machines
resource "azurerm_subnet" "chaos_subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.chaos_testing.name
  virtual_network_name = azurerm_virtual_network.chaos_vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# Create Network Security Group with SSH access
resource "azurerm_network_security_group" "chaos_nsg" {
  name                = var.network_security_group_name != "" ? var.network_security_group_name : "nsg-chaos-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name

  # Allow SSH access from specified CIDR blocks
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidr_blocks
    destination_address_prefix = "*"
    description                = "Allow SSH access for chaos testing VM management"
  }

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Network Security Group"
    Description = "Network security group for chaos testing VM"
  })
}

# Associate Network Security Group with Subnet
resource "azurerm_subnet_network_security_group_association" "chaos_nsg_association" {
  subnet_id                 = azurerm_subnet.chaos_subnet.id
  network_security_group_id = azurerm_network_security_group.chaos_nsg.id
}

# Create Public IP for VM
resource "azurerm_public_ip" "chaos_vm_pip" {
  name                = "pip-chaos-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing VM Public IP"
    Description = "Public IP address for chaos testing virtual machine"
  })
}

# Create Network Interface for VM
resource "azurerm_network_interface" "chaos_vm_nic" {
  name                = "nic-chaos-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.chaos_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.chaos_vm_pip.id
  }

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing VM Network Interface"
    Description = "Network interface for chaos testing virtual machine"
  })
}

# Generate SSH Key Pair for VM access
resource "azurerm_ssh_public_key" "chaos_vm_ssh" {
  name                = "ssh-chaos-vm-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.chaos_testing.name
  location            = azurerm_resource_group.chaos_testing.location
  public_key          = file("~/.ssh/id_rsa.pub")

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing VM SSH Key"
    Description = "SSH public key for chaos testing virtual machine"
  })

  lifecycle {
    ignore_changes = [public_key]
  }
}

# Create Virtual Machine for chaos testing target
resource "azurerm_linux_virtual_machine" "chaos_vm" {
  name                = var.vm_name != "" ? var.vm_name : "vm-target-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username

  disable_password_authentication = var.vm_disable_password_authentication

  network_interface_ids = [
    azurerm_network_interface.chaos_vm_nic.id,
  ]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = azurerm_ssh_public_key.chaos_vm_ssh.public_key
  }

  os_disk {
    caching              = var.vm_os_disk_caching
    storage_account_type = var.vm_os_disk_storage_account_type
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Target VM"
    Description = "Virtual machine target for chaos engineering experiments"
  })
}

# Create User-Assigned Managed Identity for Chaos Studio
resource "azurerm_user_assigned_identity" "chaos_identity" {
  name                = var.managed_identity_name != "" ? var.managed_identity_name : "id-chaos-${random_string.suffix.result}"
  location            = azurerm_resource_group.chaos_testing.location
  resource_group_name = azurerm_resource_group.chaos_testing.name

  tags = merge(var.common_tags, {
    Name        = "Chaos Studio Managed Identity"
    Description = "User-assigned managed identity for Chaos Studio experiments"
  })
}

# Assign Virtual Machine Contributor role to managed identity
resource "azurerm_role_assignment" "chaos_vm_contributor" {
  scope                = azurerm_linux_virtual_machine.chaos_vm.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.chaos_identity.principal_id
}

# Register Microsoft.Chaos resource provider (using azapi for better control)
resource "azapi_resource" "chaos_provider_registration" {
  type      = "Microsoft.Resources/providers@2021-04-01"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  name      = "Microsoft.Chaos"
  
  lifecycle {
    ignore_changes = all
  }
}

# Enable Chaos Studio on the VM (service-direct target)
resource "azapi_resource" "chaos_vm_target" {
  type      = "Microsoft.Chaos/targets@2024-01-01"
  parent_id = azurerm_linux_virtual_machine.chaos_vm.id
  name      = "Microsoft-VirtualMachine"

  body = jsonencode({
    properties = {}
  })

  depends_on = [azapi_resource.chaos_provider_registration]

  tags = merge(var.common_tags, {
    Name        = "Chaos Studio VM Target"
    Description = "Chaos Studio target configuration for virtual machine"
  })
}

# Install and configure Chaos Agent on VM
resource "azurerm_virtual_machine_extension" "chaos_agent" {
  name                 = "ChaosAgent"
  virtual_machine_id   = azurerm_linux_virtual_machine.chaos_vm.id
  publisher            = "Microsoft.Azure.Chaos"
  type                 = "ChaosAgent"
  type_handler_version = "1.0"

  settings = jsonencode({
    profile = "Node"
    auth = {
      msi = {
        clientId = azurerm_user_assigned_identity.chaos_identity.client_id
      }
    }
    appInsightsSettings = {
      isEnabled          = true
      instrumentationKey = azurerm_application_insights.chaos_insights.instrumentation_key
      logLevel          = "Information"
    }
  })

  tags = merge(var.common_tags, {
    Name        = "Chaos Agent Extension"
    Description = "Chaos Agent extension for in-guest fault injection"
  })

  depends_on = [azapi_resource.chaos_vm_target]
}

# Create Chaos Experiment
resource "azapi_resource" "chaos_experiment" {
  count     = var.chaos_experiment_enabled ? 1 : 0
  type      = "Microsoft.Chaos/experiments@2024-01-01"
  parent_id = azurerm_resource_group.chaos_testing.id
  name      = var.chaos_experiment_name != "" ? var.chaos_experiment_name : "exp-vm-shutdown-${random_string.suffix.result}"
  location  = azurerm_resource_group.chaos_testing.location

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.chaos_identity.id]
  }

  body = jsonencode({
    properties = {
      steps = [
        {
          name = "Step 1"
          branches = [
            {
              name = "Branch 1"
              actions = [
                {
                  type       = "continuous"
                  name       = "VM Shutdown"
                  selectorId = "Selector1"
                  duration   = var.chaos_experiment_duration
                  parameters = [
                    {
                      key   = "abruptShutdown"
                      value = "true"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
      selectors = [
        {
          id   = "Selector1"
          type = "List"
          targets = [
            {
              type = "ChaosTarget"
              id   = "${azurerm_linux_virtual_machine.chaos_vm.id}/providers/Microsoft.Chaos/targets/Microsoft-VirtualMachine"
            }
          ]
        }
      ]
    }
  })

  tags = merge(var.common_tags, {
    Name        = "VM Shutdown Chaos Experiment"
    Description = "Chaos experiment for testing VM shutdown resilience"
  })

  depends_on = [
    azapi_resource.chaos_vm_target,
    azurerm_role_assignment.chaos_vm_contributor
  ]
}

# Create Action Group for chaos experiment alerts
resource "azurerm_monitor_action_group" "chaos_alerts" {
  name                = var.action_group_name != "" ? var.action_group_name : "ag-chaos-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.chaos_testing.name
  short_name          = "ChaosAlert"

  email_receiver {
    name          = "admin-email"
    email_address = var.alert_email
  }

  tags = merge(var.common_tags, {
    Name        = "Chaos Testing Action Group"
    Description = "Action group for chaos experiment notifications"
  })
}

# Create CPU alert rule for chaos experiment monitoring
resource "azurerm_monitor_metric_alert" "chaos_cpu_alert" {
  name                = "Chaos Experiment CPU Alert"
  resource_group_name = azurerm_resource_group.chaos_testing.name
  scopes              = [azurerm_linux_virtual_machine.chaos_vm.id]
  description         = "Alert when chaos experiment affects VM CPU performance"
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_threshold_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.chaos_alerts.id
  }

  tags = merge(var.common_tags, {
    Name        = "Chaos CPU Alert Rule"
    Description = "Monitor VM CPU during chaos experiments"
  })
}
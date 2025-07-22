# Main Terraform Configuration for Azure Infrastructure Lifecycle Management
# This file implements Azure Deployment Stacks and Azure Update Manager

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-infra-lifecycle-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-monitoring-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Create Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-webtier-${random_id.suffix.hex}"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create Subnet for web tier
resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Create Network Security Group for web tier
resource "azurerm_network_security_group" "web" {
  name                = "nsg-webtier-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # Allow HTTP traffic
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow SSH traffic
  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS traffic
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate Network Security Group with Subnet
resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# Create Public IP for Load Balancer
resource "azurerm_public_ip" "lb" {
  name                = "pip-webtier-lb-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Create Load Balancer
resource "azurerm_lb" "main" {
  name                = "lb-webtier-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "LoadBalancerFrontEnd"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

# Create Load Balancer Backend Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "BackendPool"
}

# Create Load Balancer Health Probe
resource "azurerm_lb_probe" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "tcpProbe"
  protocol        = "Tcp"
  port            = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

# Create Load Balancer Rule
resource "azurerm_lb_rule" "main" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "HTTPRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.main.id
  enable_floating_ip             = false
  idle_timeout_in_minutes        = 5
}

# Create Virtual Machine Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                            = "vmss-webtier-${random_id.suffix.hex}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  sku                             = var.vm_size
  instances                       = var.vm_instances
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  tags                            = var.tags

  # Custom data script to install and configure nginx
  custom_data = base64encode(templatefile("${path.module}/scripts/init.sh", {
    custom_script_uri = var.custom_script_uri
  }))

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic-webtier"
    primary = true

    ip_configuration {
      name                                   = "ipconfig1"
      primary                                = true
      subnet_id                              = azurerm_subnet.web.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
    }
  }

  # Enable auto-scaling if specified
  dynamic "automatic_instance_repair" {
    for_each = var.enable_auto_scale ? [1] : []
    content {
      enabled      = true
      grace_period = "PT30M"
    }
  }

  # Identity for monitoring and management
  identity {
    type = "SystemAssigned"
  }

  # Enable Azure Monitor Agent extension
  dynamic "extension" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      name                       = "AzureMonitorLinuxAgent"
      publisher                  = "Microsoft.Azure.Monitor"
      type                       = "AzureMonitorLinuxAgent"
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
    }
  }

  # Custom script extension for application setup
  extension {
    name                       = "CustomScript"
    publisher                  = "Microsoft.Azure.Extensions"
    type                       = "CustomScript"
    type_handler_version       = "2.1"
    auto_upgrade_minor_version = true

    settings = jsonencode({
      commandToExecute = "apt-get update && apt-get install -y nginx && systemctl enable nginx && systemctl start nginx && echo '<h1>Welcome to Infrastructure Lifecycle Management Demo</h1><p>Server: '$(hostname)'</p>' > /var/www/html/index.html"
    })
  }

  upgrade_mode = "Manual"

  lifecycle {
    ignore_changes = [instances]
  }
}

# Create Auto Scaling Profile (if enabled)
resource "azurerm_monitor_autoscale_setting" "main" {
  count               = var.enable_auto_scale ? 1 : 0
  name                = "autoscale-vmss-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id
  tags                = var.tags

  profile {
    name = "defaultProfile"

    capacity {
      default = var.vm_instances
      minimum = var.min_capacity
      maximum = var.max_capacity
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}

# Create Maintenance Configuration for Update Manager
resource "azurerm_maintenance_configuration" "main" {
  name                = "mc-weekly-updates-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  scope               = "InGuestPatch"
  tags                = var.tags

  window {
    start_date_time      = var.maintenance_window_start_time
    duration             = var.maintenance_window_duration
    time_zone            = "UTC"
    recur_every          = "1Week"
    expiration_date_time = "2025-12-31 00:00"
  }

  install_patches {
    linux {
      classifications_to_include = var.linux_patch_classification
      package_names_mask_to_include = ["*"]
    }
    reboot = "IfRequired"
  }

  # Target specific properties for Linux
  properties = {
    "maintenanceScope" = "InGuestPatch"
  }
}

# Create Maintenance Assignment for VMSS
resource "azurerm_maintenance_assignment_virtual_machine_scale_set" "main" {
  location                     = azurerm_resource_group.main.location
  maintenance_configuration_id = azurerm_maintenance_configuration.main.id
  virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.main.id
}

# Create Azure Policy Definition for Deployment Stack Governance
resource "azurerm_policy_definition" "deployment_stack_governance" {
  name         = "enforce-deployment-stack-deny-settings-${random_id.suffix.hex}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Enforce Deployment Stack Deny Settings"
  description  = "Ensures all deployment stacks have appropriate deny settings configured"

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Resources/deploymentStacks"
        },
        {
          field    = "Microsoft.Resources/deploymentStacks/denySettings.mode"
          notEquals = "denyWriteAndDelete"
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

# Create Policy Assignment
resource "azurerm_resource_group_policy_assignment" "deployment_stack_governance" {
  name                 = "deployment-stack-governance-${random_id.suffix.hex}"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.deployment_stack_governance.id
  description          = "Enforce deployment stack governance policies"
  display_name         = "Deployment Stack Governance"
}

# Create Deployment Stack using azapi provider
resource "azapi_resource" "deployment_stack" {
  count = var.enable_deployment_stack_protection ? 1 : 0
  
  type      = "Microsoft.Resources/deploymentStacks@2024-03-01"
  name      = "stack-web-tier-${random_id.suffix.hex}"
  parent_id = azurerm_resource_group.main.id
  
  body = jsonencode({
    properties = {
      template = {
        "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        parameters = {}
        variables = {}
        resources = [
          {
            type = "Microsoft.Network/virtualNetworks"
            apiVersion = "2023-09-01"
            name = azurerm_virtual_network.main.name
            location = azurerm_resource_group.main.location
            properties = {
              addressSpace = {
                addressPrefixes = [var.vnet_address_space]
              }
              subnets = [
                {
                  name = "subnet-web"
                  properties = {
                    addressPrefix = var.subnet_address_prefix
                  }
                }
              ]
            }
          }
        ]
        outputs = {}
      }
      parameters = {}
      denySettings = {
        mode = "denyWriteAndDelete"
        applyToChildScopes = true
        excludedPrincipals = []
        excludedActions = []
      }
      actionOnUnmanage = {
        resources = "delete"
        resourceGroups = "delete"
        managementGroups = "delete"
      }
    }
  })

  depends_on = [
    azurerm_virtual_network.main,
    azurerm_subnet.web
  ]
}

# Create Diagnostic Settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "vmss" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "diag-vmss-${random_id.suffix.hex}"
  target_resource_id         = azurerm_linux_virtual_machine_scale_set.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "Administrative"
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "lb" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "diag-lb-${random_id.suffix.hex}"
  target_resource_id         = azurerm_lb.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "LoadBalancerAlertEvent"
  }

  enabled_log {
    category = "LoadBalancerProbeHealthStatus"
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Create Azure Workbook for Infrastructure Monitoring
resource "azapi_resource" "monitoring_workbook" {
  count = var.enable_monitoring ? 1 : 0
  
  type      = "Microsoft.Insights/workbooks@2023-06-01"
  name      = "infrastructure-lifecycle-dashboard-${random_id.suffix.hex}"
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  
  body = jsonencode({
    properties = {
      displayName = "Infrastructure Lifecycle Management Dashboard"
      serializedData = jsonencode({
        version = "Notebook/1.0"
        items = [
          {
            type = 1
            content = {
              json = "# Infrastructure Lifecycle Management Dashboard\n\nThis dashboard provides insights into deployment stack status and update compliance across your infrastructure."
            }
          },
          {
            type = 3
            content = {
              version = "KqlItem/1.0"
              query = "Heartbeat\n| where TimeGenerated >= ago(24h)\n| summarize LastHeartbeat = max(TimeGenerated) by Computer\n| extend Status = case(LastHeartbeat >= ago(5m), \"Online\", \"Offline\")\n| summarize OnlineCount = countif(Status == \"Online\"), OfflineCount = countif(Status == \"Offline\")"
              size = 0
              title = "VM Health Status"
              timeContext = {
                durationMs = 86400000
              }
              queryType = 0
              resourceType = "microsoft.operationalinsights/workspaces"
            }
          }
        ]
      })
      category = "workbook"
      kind = "shared"
      sourceId = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
    }
  })
}
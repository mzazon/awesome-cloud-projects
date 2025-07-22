# Main Terraform configuration for Azure auto-scaling web application
# This configuration creates a complete auto-scaling web application infrastructure
# using Azure Virtual Machine Scale Sets and Azure Load Balancer

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Generate SSH key pair for VM access
resource "tls_private_key" "vm_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Local values for consistent naming and tagging
locals {
  suffix = random_id.suffix.hex
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "deploying-auto-scaling-web-applications"
  })
  
  # Resource names with unique suffix
  resource_names = {
    resource_group    = var.resource_group_name
    vnet             = "vnet-${var.project_name}-${local.suffix}"
    subnet           = "subnet-${var.project_name}"
    nsg              = "nsg-${var.project_name}-${local.suffix}"
    public_ip        = "pip-${var.project_name}-${local.suffix}"
    load_balancer    = "lb-${var.project_name}-${local.suffix}"
    vmss             = "vmss-${var.project_name}-${local.suffix}"
    app_insights     = "${var.project_name}-insights-${local.suffix}"
    autoscale_profile = "autoscale-profile-${local.suffix}"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = local.resource_names.vnet
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Subnet for VMSS instances
resource "azurerm_subnet" "internal" {
  name                 = local.resource_names.subnet
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group with web traffic rules
resource "azurerm_network_security_group" "main" {
  name                = local.resource_names.nsg
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

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

  # Allow SSH traffic (for management)
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate Network Security Group to Subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "main" {
  name                = local.resource_names.public_ip
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = var.load_balancer_sku
  tags                = local.common_tags
}

# Azure Load Balancer
resource "azurerm_lb" "main" {
  name                = local.resource_names.load_balancer
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.load_balancer_sku
  tags                = local.common_tags

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

# Backend Address Pool for Load Balancer
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "backend-pool"
}

# Health Probe for HTTP traffic
resource "azurerm_lb_probe" "http" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "http-probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/"
  interval_in_seconds         = var.health_probe_interval
  number_of_probes           = var.health_probe_threshold
}

# Load Balancing Rule for HTTP traffic
resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.main.id
  name                          = "http-rule"
  protocol                      = "Tcp"
  frontend_port                 = 80
  backend_port                  = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids      = [azurerm_lb_backend_address_pool.main.id]
  probe_id                      = azurerm_lb_probe.http.id
  load_distribution             = "Default"
  enable_floating_ip            = false
  disable_outbound_snat         = false
}

# Cloud-init script for web server setup
locals {
  cloud_init_data = base64encode(templatefile("${path.module}/cloud-init.yml", {
    hostname_prefix = var.project_name
  }))
}

# Create cloud-init configuration file
resource "local_file" "cloud_init" {
  content = <<-EOF
#cloud-config
package_upgrade: true
packages:
  - nginx
runcmd:
  - systemctl start nginx
  - systemctl enable nginx
  - echo "<h1>Web Server $(hostname)</h1><p>Server Time: $(date)</p><p>Instance: $(hostname)</p>" > /var/www/html/index.html
  - systemctl restart nginx
EOF
  filename = "${path.module}/cloud-init.yml"
}

# Virtual Machine Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                = local.resource_names.vmss
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.vm_sku
  instances           = var.vmss_initial_capacity
  admin_username      = var.admin_username
  upgrade_mode        = "Automatic"
  
  # Disable password authentication and use SSH keys
  disable_password_authentication = true

  tags = local.common_tags

  # Custom data for web server setup
  custom_data = local.cloud_init_data

  # Source image for VM instances
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # OS disk configuration
  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  # Network interface configuration
  network_interface {
    name    = "internal"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                               = true
      subnet_id                            = azurerm_subnet.internal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
    }
  }

  # SSH key configuration
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vm_ssh.public_key_openssh
  }

  # Health extension for proper load balancer integration
  extension {
    name                 = "health-extension"
    publisher            = "Microsoft.ManagedServices"
    type                 = "ApplicationHealthLinux"
    type_handler_version = "1.0"
    settings = jsonencode({
      protocol    = "http"
      port        = 80
      requestPath = "/"
    })
  }

  depends_on = [
    azurerm_lb_rule.http,
    local_file.cloud_init
  ]
}

# Auto-scaling profile
resource "azurerm_monitor_autoscale_setting" "main" {
  name                = local.resource_names.autoscale_profile
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id
  tags                = local.common_tags

  profile {
    name = "default-profile"

    capacity {
      default = var.vmss_initial_capacity
      minimum = var.vmss_min_capacity
      maximum = var.vmss_max_capacity
    }

    # Scale-out rule (CPU > threshold)
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_out_cpu_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = var.scale_out_capacity_change
        cooldown  = var.cooldown_duration
      }
    }

    # Scale-in rule (CPU < threshold)
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.scale_in_cpu_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = var.scale_in_capacity_change
        cooldown  = var.cooldown_duration
      }
    }
  }
}

# Application Insights for monitoring (optional)
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.resource_names.app_insights
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  tags                = local.common_tags
}

# Metric Alert for high CPU usage (optional)
resource "azurerm_monitor_metric_alert" "high_cpu" {
  count               = var.enable_auto_scaling_alerts ? 1 : 0
  name                = "high-cpu-alert-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.main.id]
  description         = "Alert when CPU usage exceeds 80%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
}
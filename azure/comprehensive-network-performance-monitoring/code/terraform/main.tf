# main.tf
# Main Terraform configuration for Azure Network Performance Monitoring solution

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source for subscription information
data "azurerm_subscription" "current" {}

# ====================================================================
# RESOURCE GROUP
# ====================================================================

# Create resource group for all monitoring resources
resource "azurerm_resource_group" "monitoring" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# ====================================================================
# NETWORKING RESOURCES
# ====================================================================

# Create virtual network for monitoring infrastructure
resource "azurerm_virtual_network" "monitoring" {
  name                = "vnet-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Create subnet for monitoring VMs
resource "azurerm_subnet" "monitoring" {
  name                 = "subnet-${var.project_name}-${var.environment}"
  resource_group_name  = azurerm_resource_group.monitoring.name
  virtual_network_name = azurerm_virtual_network.monitoring.name
  address_prefixes     = var.subnet_address_prefixes
}

# Create Network Security Group for monitoring subnet
resource "azurerm_network_security_group" "monitoring" {
  name                = "nsg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  tags                = var.tags
}

# Network Security Group rules for monitoring
resource "azurerm_network_security_rule" "allow_ssh" {
  count                       = var.enable_network_security_group_rules ? 1 : 0
  name                        = "AllowSSH"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.monitoring.name
  network_security_group_name = azurerm_network_security_group.monitoring.name
}

resource "azurerm_network_security_rule" "allow_http" {
  count                       = var.enable_network_security_group_rules ? 1 : 0
  name                        = "AllowHTTP"
  priority                    = 1002
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.monitoring.name
  network_security_group_name = azurerm_network_security_group.monitoring.name
}

resource "azurerm_network_security_rule" "allow_https" {
  count                       = var.enable_network_security_group_rules ? 1 : 0
  name                        = "AllowHTTPS"
  priority                    = 1003
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.monitoring.name
  network_security_group_name = azurerm_network_security_group.monitoring.name
}

resource "azurerm_network_security_rule" "allow_icmp" {
  count                       = var.enable_network_security_group_rules ? 1 : 0
  name                        = "AllowICMP"
  priority                    = 1004
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.monitoring.name
  network_security_group_name = azurerm_network_security_group.monitoring.name
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "monitoring" {
  subnet_id                 = azurerm_subnet.monitoring.id
  network_security_group_id = azurerm_network_security_group.monitoring.id
}

# ====================================================================
# MONITORING INFRASTRUCTURE
# ====================================================================

# Create Log Analytics workspace for network monitoring data
resource "azurerm_log_analytics_workspace" "monitoring" {
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create Application Insights for application performance monitoring
resource "azurerm_application_insights" "monitoring" {
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  workspace_id        = azurerm_log_analytics_workspace.monitoring.id
  application_type    = "other"
  tags                = var.tags
}

# ====================================================================
# STORAGE ACCOUNT FOR FLOW LOGS
# ====================================================================

# Create storage account for NSG flow logs and diagnostic data
resource "azurerm_storage_account" "monitoring" {
  name                     = "sta${var.project_name}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.monitoring.name
  location                 = azurerm_resource_group.monitoring.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable blob versioning for better data management
  blob_properties {
    versioning_enabled = true
    
    # Configure lifecycle management for cost optimization
    delete_retention_policy {
      days = var.flow_log_retention_days
    }
  }
  
  tags = var.tags
}

# Create storage container for flow logs
resource "azurerm_storage_container" "flow_logs" {
  count                 = var.enable_flow_logs ? 1 : 0
  name                  = "flow-logs"
  storage_account_name  = azurerm_storage_account.monitoring.name
  container_access_type = "private"
}

# Create storage container for packet captures
resource "azurerm_storage_container" "packet_captures" {
  name                  = "packet-captures"
  storage_account_name  = azurerm_storage_account.monitoring.name
  container_access_type = "private"
}

# ====================================================================
# VIRTUAL MACHINES FOR MONITORING
# ====================================================================

# Generate SSH key pair if not provided
resource "tls_private_key" "monitoring" {
  count     = var.vm_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create public IP for source VM
resource "azurerm_public_ip" "source_vm" {
  name                = "pip-source-vm-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Create network interface for source VM
resource "azurerm_network_interface" "source_vm" {
  name                = "nic-source-vm-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.monitoring.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.source_vm.id
  }
}

# Create source VM for connection monitoring
resource "azurerm_linux_virtual_machine" "source_vm" {
  name                = "vm-source-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  tags                = var.tags

  # Disable password authentication and use SSH keys
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.source_vm.id,
  ]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.vm_public_key != "" ? var.vm_public_key : tls_private_key.monitoring[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Create public IP for destination VM
resource "azurerm_public_ip" "dest_vm" {
  name                = "pip-dest-vm-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Create network interface for destination VM
resource "azurerm_network_interface" "dest_vm" {
  name                = "nic-dest-vm-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.monitoring.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.dest_vm.id
  }
}

# Create destination VM for connection monitoring
resource "azurerm_linux_virtual_machine" "dest_vm" {
  name                = "vm-dest-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  tags                = var.tags

  # Disable password authentication and use SSH keys
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.dest_vm.id,
  ]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.vm_public_key != "" ? var.vm_public_key : tls_private_key.monitoring[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# ====================================================================
# NETWORK WATCHER EXTENSIONS
# ====================================================================

# Install Network Watcher extension on source VM
resource "azurerm_virtual_machine_extension" "network_watcher_source" {
  name                 = "NetworkWatcherAgentLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.source_vm.id
  publisher            = "Microsoft.Azure.NetworkWatcher"
  type                 = "NetworkWatcherAgentLinux"
  type_handler_version = "1.4"
  tags                 = var.tags

  depends_on = [azurerm_linux_virtual_machine.source_vm]
}

# Install Network Watcher extension on destination VM
resource "azurerm_virtual_machine_extension" "network_watcher_dest" {
  name                 = "NetworkWatcherAgentLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.dest_vm.id
  publisher            = "Microsoft.Azure.NetworkWatcher"
  type                 = "NetworkWatcherAgentLinux"
  type_handler_version = "1.4"
  tags                 = var.tags

  depends_on = [azurerm_linux_virtual_machine.dest_vm]
}

# ====================================================================
# NETWORK WATCHER CONFIGURATION
# ====================================================================

# Get the Network Watcher resource (automatically created)
data "azurerm_network_watcher" "main" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

# Create NSG flow logs
resource "azurerm_network_watcher_flow_log" "monitoring" {
  count                     = var.enable_flow_logs ? 1 : 0
  name                      = "flow-log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  network_watcher_name      = data.azurerm_network_watcher.main.name
  resource_group_name       = data.azurerm_network_watcher.main.resource_group_name
  network_security_group_id = azurerm_network_security_group.monitoring.id
  storage_account_id        = azurerm_storage_account.monitoring.id
  enabled                   = true
  version                   = var.flow_log_version
  
  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.monitoring.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.monitoring.location
    workspace_resource_id = azurerm_log_analytics_workspace.monitoring.id
    interval_in_minutes   = 10
  }

  tags = var.tags
}

# ====================================================================
# CONNECTION MONITOR CONFIGURATION
# ====================================================================

# Create connection monitor for network performance monitoring
resource "azurerm_network_connection_monitor" "monitoring" {
  name                 = "cm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  network_watcher_name = data.azurerm_network_watcher.main.name
  resource_group_name  = data.azurerm_network_watcher.main.resource_group_name
  location             = var.location
  tags                 = var.tags

  # Source endpoint configuration
  endpoint {
    name               = "source-endpoint"
    target_resource_id = azurerm_linux_virtual_machine.source_vm.id
  }

  # Destination endpoint configuration
  endpoint {
    name               = "dest-endpoint"
    target_resource_id = azurerm_linux_virtual_machine.dest_vm.id
  }

  # External endpoint configuration
  endpoint {
    name    = "external-endpoint"
    address = var.external_endpoint_address
  }

  # TCP test configuration
  test_configuration {
    name                      = "tcp-test"
    protocol                  = "Tcp"
    test_frequency_in_seconds = var.connection_monitor_test_frequency

    tcp_configuration {
      port                = 80
      disable_trace_route = false
    }

    success_threshold {
      checks_failed_percent = var.connection_monitor_success_threshold_failed_percent
      round_trip_time_ms    = var.connection_monitor_success_threshold_latency
    }
  }

  # ICMP test configuration
  test_configuration {
    name                      = "icmp-test"
    protocol                  = "Icmp"
    test_frequency_in_seconds = 60

    icmp_configuration {
      disable_trace_route = false
    }

    success_threshold {
      checks_failed_percent = 10
      round_trip_time_ms    = 500
    }
  }

  # Test group for VM-to-VM connectivity
  test_group {
    name                     = "vm-to-vm-tests"
    source_endpoints         = ["source-endpoint"]
    destination_endpoints    = ["dest-endpoint"]
    test_configuration_names = ["tcp-test", "icmp-test"]
  }

  # Test group for VM-to-external connectivity
  test_group {
    name                     = "vm-to-external-tests"
    source_endpoints         = ["source-endpoint"]
    destination_endpoints    = ["external-endpoint"]
    test_configuration_names = ["tcp-test", "icmp-test"]
  }

  # Output configuration to Log Analytics workspace
  output_workspace_resource_ids = [azurerm_log_analytics_workspace.monitoring.id]

  depends_on = [
    azurerm_virtual_machine_extension.network_watcher_source,
    azurerm_virtual_machine_extension.network_watcher_dest,
    azurerm_log_analytics_workspace.monitoring
  ]
}

# ====================================================================
# MONITORING ALERTS
# ====================================================================

# Create action group for alert notifications
resource "azurerm_monitor_action_group" "monitoring" {
  count               = var.enable_alerts ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.monitoring.name
  short_name          = "NetAlert"
  tags                = var.tags

  email_receiver {
    name          = "Admin"
    email_address = var.alert_email_address
  }
}

# Create alert rule for high network latency
resource "azurerm_monitor_metric_alert" "high_latency" {
  count               = var.enable_alerts ? 1 : 0
  name                = "High Network Latency Alert"
  resource_group_name = azurerm_resource_group.monitoring.name
  scopes              = [azurerm_log_analytics_workspace.monitoring.id]
  description         = "Alert when network latency exceeds threshold"
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 2
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    metric_name      = "Average_ResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.high_latency_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.monitoring[0].id
  }

  depends_on = [azurerm_log_analytics_workspace.monitoring]
}

# Create alert rule for network connectivity failure
resource "azurerm_monitor_metric_alert" "connectivity_failure" {
  count               = var.enable_alerts ? 1 : 0
  name                = "Network Connectivity Failure"
  resource_group_name = azurerm_resource_group.monitoring.name
  scopes              = [azurerm_log_analytics_workspace.monitoring.id]
  description         = "Alert when network connectivity drops below threshold"
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 1
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    metric_name      = "Average_SuccessRate"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.connectivity_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.monitoring[0].id
  }

  depends_on = [azurerm_log_analytics_workspace.monitoring]
}

# ====================================================================
# OPTIONAL: AZURE BASTION FOR SECURE ACCESS
# ====================================================================

# Create subnet for Azure Bastion (if enabled)
resource "azurerm_subnet" "bastion" {
  count                = var.create_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.monitoring.name
  virtual_network_name = azurerm_virtual_network.monitoring.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create public IP for Azure Bastion
resource "azurerm_public_ip" "bastion" {
  count               = var.create_bastion ? 1 : 0
  name                = "pip-bastion-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Create Azure Bastion for secure VM access
resource "azurerm_bastion_host" "monitoring" {
  count               = var.create_bastion ? 1 : 0
  name                = "bastion-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
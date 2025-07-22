# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Current Azure client configuration
data "azurerm_client_config" "current" {}

# Get MSP administrator group
data "azuread_group" "msp_administrators" {
  display_name = var.msp_admin_group_name
}

# Get MSP engineer group
data "azuread_group" "msp_engineers" {
  display_name = var.msp_engineer_group_name
}

# ==============================================================================
# MSP TENANT RESOURCES
# ==============================================================================

# MSP Resource Group for management resources
resource "azurerm_resource_group" "msp_management" {
  name     = var.msp_resource_group_name
  location = var.location
  
  tags = merge(var.common_tags, var.msp_tags, {
    ResourceType = "ResourceGroup"
    Description  = "MSP management resources for Azure Lighthouse"
  })
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "lighthouse_monitoring" {
  name                = "law-lighthouse-${random_string.suffix.result}"
  location            = azurerm_resource_group.msp_management.location
  resource_group_name = azurerm_resource_group.msp_management.name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.common_tags, var.msp_tags, {
    ResourceType = "LogAnalytics"
    Description  = "Centralized monitoring for cross-tenant resources"
  })
}

# Azure Automanage Configuration Profile
resource "azurerm_automanage_configuration" "lighthouse_profile" {
  name                = "${var.automanage_profile_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.msp_management.name
  location            = azurerm_resource_group.msp_management.location
  
  # Configuration settings based on variables
  antimalware_enabled                 = var.enable_antimalware
  azure_security_center_enabled      = var.enable_azure_security_center
  backup_enabled                      = var.enable_backup
  boot_diagnostics_enabled            = var.enable_boot_diagnostics
  change_tracking_enabled             = var.enable_change_tracking
  guest_configuration_enabled         = var.enable_guest_configuration
  log_analytics_enabled               = true
  log_analytics_workspace_id          = azurerm_log_analytics_workspace.lighthouse_monitoring.id
  status_change_alert_enabled         = true
  update_management_enabled           = var.enable_update_management
  vm_insights_enabled                 = var.enable_vm_insights
  
  tags = merge(var.common_tags, var.msp_tags, {
    ResourceType = "AutomanageConfiguration"
    Description  = "Standard configuration profile for managed VMs"
  })
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "lighthouse_alerts" {
  name                = "ag-lighthouse-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.msp_management.name
  short_name          = "LighthouseAlerts"
  
  email_receiver {
    name          = "MSP-Ops"
    email_address = var.alert_email_address
  }
  
  tags = merge(var.common_tags, var.msp_tags, {
    ResourceType = "MonitorActionGroup"
    Description  = "Alert notifications for cross-tenant monitoring"
  })
}

# ==============================================================================
# AZURE LIGHTHOUSE DELEGATION
# ==============================================================================

# Lighthouse Registration Definition
resource "azurerm_lighthouse_definition" "cross_tenant_governance" {
  name               = var.lighthouse_offer_name
  description        = var.lighthouse_offer_description
  managing_tenant_id = var.msp_tenant_id
  scope              = "/subscriptions/${var.customer_subscription_id}"
  
  # MSP Administrators - Contributor role
  authorization {
    principal_id           = data.azuread_group.msp_administrators.object_id
    principal_display_name = "MSP Administrators"
    role_definition_id     = "b24988ac-6180-42a0-ab88-20f7382dd24c" # Contributor
  }
  
  # MSP Engineers - Virtual Machine Contributor role
  authorization {
    principal_id           = data.azuread_group.msp_engineers.object_id
    principal_display_name = "MSP Engineers"
    role_definition_id     = "9980e02c-c2be-4d73-94e8-173b1dc7cf3c" # Virtual Machine Contributor
  }
  
  # MSP Administrators - Automanage Contributor role
  authorization {
    principal_id           = data.azuread_group.msp_administrators.object_id
    principal_display_name = "MSP Administrators - Automanage"
    role_definition_id     = "cdfd5644-ae35-4c17-bb47-ac720c1b0b59" # Automanage Contributor
  }
  
  # MSP Administrators - Log Analytics Contributor role
  authorization {
    principal_id           = data.azuread_group.msp_administrators.object_id
    principal_display_name = "MSP Administrators - Log Analytics"
    role_definition_id     = "92aaf0da-9dab-42b6-94a3-d43ce8d16293" # Log Analytics Contributor
  }
  
  # MSP Engineers - Monitoring Reader role
  authorization {
    principal_id           = data.azuread_group.msp_engineers.object_id
    principal_display_name = "MSP Engineers - Monitoring"
    role_definition_id     = "43d0d8ad-25c7-4714-9337-8ba259a9fe05" # Monitoring Reader
  }
}

# Lighthouse Assignment
resource "azurerm_lighthouse_assignment" "cross_tenant_governance" {
  scope                    = "/subscriptions/${var.customer_subscription_id}"
  lighthouse_definition_id = azurerm_lighthouse_definition.cross_tenant_governance.id
  
  depends_on = [
    azurerm_lighthouse_definition.cross_tenant_governance
  ]
}

# ==============================================================================
# CUSTOMER TENANT RESOURCES
# ==============================================================================

# Customer Resource Group for workload resources
resource "azurerm_resource_group" "customer_workloads" {
  name     = var.customer_resource_group_name
  location = var.location
  
  tags = merge(var.common_tags, var.customer_tags, {
    ResourceType = "ResourceGroup"
    Description  = "Customer workload resources managed by MSP"
  })
  
  depends_on = [
    azurerm_lighthouse_assignment.cross_tenant_governance
  ]
}

# Virtual Network for customer VMs
resource "azurerm_virtual_network" "customer_vnet" {
  name                = "vnet-customer-${random_string.suffix.result}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.customer_workloads.location
  resource_group_name = azurerm_resource_group.customer_workloads.name
  
  tags = merge(var.common_tags, var.customer_tags, {
    ResourceType = "VirtualNetwork"
    Description  = "Customer virtual network for workload VMs"
  })
}

# Subnet for customer VMs
resource "azurerm_subnet" "customer_subnet" {
  name                 = "subnet-default"
  resource_group_name  = azurerm_resource_group.customer_workloads.name
  virtual_network_name = azurerm_virtual_network.customer_vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# Network Security Group for customer VMs
resource "azurerm_network_security_group" "customer_nsg" {
  name                = "nsg-customer-${random_string.suffix.result}"
  location            = azurerm_resource_group.customer_workloads.location
  resource_group_name = azurerm_resource_group.customer_workloads.name
  
  # Allow RDP from within the subnet
  security_rule {
    name                       = "AllowRDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
  
  # Allow HTTP for monitoring
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
  
  # Allow HTTPS for monitoring
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
  
  tags = merge(var.common_tags, var.customer_tags, {
    ResourceType = "NetworkSecurityGroup"
    Description  = "Security rules for customer VMs"
  })
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "customer_subnet_nsg" {
  subnet_id                 = azurerm_subnet.customer_subnet.id
  network_security_group_id = azurerm_network_security_group.customer_nsg.id
}

# Public IP for customer VM
resource "azurerm_public_ip" "customer_vm_pip" {
  name                = "pip-customer-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.customer_workloads.location
  resource_group_name = azurerm_resource_group.customer_workloads.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(var.common_tags, var.customer_tags, {
    ResourceType = "PublicIP"
    Description  = "Public IP for customer VM"
  })
}

# Network Interface for customer VM
resource "azurerm_network_interface" "customer_vm_nic" {
  name                = "nic-customer-vm-${random_string.suffix.result}"
  location            = azurerm_resource_group.customer_workloads.location
  resource_group_name = azurerm_resource_group.customer_workloads.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.customer_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.customer_vm_pip.id
  }
  
  tags = merge(var.common_tags, var.customer_tags, {
    ResourceType = "NetworkInterface"
    Description  = "Network interface for customer VM"
  })
}

# Customer Virtual Machine
resource "azurerm_windows_virtual_machine" "customer_vm" {
  name                = "vm-customer-${random_string.suffix.result}"
  location            = azurerm_resource_group.customer_workloads.location
  resource_group_name = azurerm_resource_group.customer_workloads.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password
  
  # Disable password authentication and use SSH keys in production
  disable_password_authentication = false
  
  network_interface_ids = [
    azurerm_network_interface.customer_vm_nic.id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = var.vm_image_publisher
    offer     = var.vm_image_offer
    sku       = var.vm_image_sku
    version   = var.vm_image_version
  }
  
  # Enable automatic updates
  enable_automatic_updates = true
  
  # Enable boot diagnostics
  boot_diagnostics {
    storage_account_uri = null # Uses managed storage account
  }
  
  tags = merge(var.common_tags, var.customer_tags, {
    ResourceType = "VirtualMachine"
    Description  = "Customer workload VM managed by MSP"
    Automanage   = "Enabled"
  })
}

# ==============================================================================
# AZURE AUTOMANAGE ASSIGNMENT
# ==============================================================================

# Automanage Assignment for customer VM
resource "azurerm_automanage_configuration_assignment" "customer_vm_automanage" {
  virtual_machine_id   = azurerm_windows_virtual_machine.customer_vm.id
  configuration_profile_id = azurerm_automanage_configuration.lighthouse_profile.id
  
  depends_on = [
    azurerm_windows_virtual_machine.customer_vm,
    azurerm_automanage_configuration.lighthouse_profile
  ]
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

# VM Availability Alert Rule
resource "azurerm_monitor_metric_alert" "vm_availability" {
  name                = "vm-availability-cross-tenant-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.msp_management.name
  scopes              = [azurerm_windows_virtual_machine.customer_vm.id]
  description         = "Alert when VMs are unavailable across customer tenants"
  severity            = var.alert_severity
  frequency           = "PT${var.alert_evaluation_frequency}M"
  window_size         = "PT${var.alert_window_size}M"
  
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_threshold_percentage
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.lighthouse_alerts.id
  }
  
  tags = merge(var.common_tags, var.msp_tags, {
    ResourceType = "MonitorAlert"
    Description  = "VM availability monitoring across tenants"
  })
}

# VM Heartbeat Alert Rule
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "vm_heartbeat" {
  name                = "vm-heartbeat-cross-tenant-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.msp_management.name
  location            = azurerm_resource_group.msp_management.location
  
  evaluation_frequency = "PT${var.alert_evaluation_frequency}M"
  window_duration      = "PT${var.alert_window_size}M"
  scopes               = [azurerm_log_analytics_workspace.lighthouse_monitoring.id]
  severity             = var.alert_severity
  
  criteria {
    query = <<-QUERY
      Heartbeat
      | where TimeGenerated > ago(5m)
      | summarize LastHeartbeat = max(TimeGenerated) by Computer
      | extend Status = case(LastHeartbeat > ago(2m), "Healthy", "Unhealthy")
      | where Status == "Unhealthy"
      | count
    QUERY
    
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.lighthouse_alerts.id]
  }
  
  tags = merge(var.common_tags, var.msp_tags, {
    ResourceType = "MonitorScheduledQueryRule"
    Description  = "VM heartbeat monitoring across tenants"
  })
}

# ==============================================================================
# DIAGNOSTIC SETTINGS
# ==============================================================================

# Diagnostic Settings for customer VM
resource "azurerm_monitor_diagnostic_setting" "customer_vm_diagnostics" {
  name                       = "vm-diagnostics-${random_string.suffix.result}"
  target_resource_id         = azurerm_windows_virtual_machine.customer_vm.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lighthouse_monitoring.id
  
  enabled_log {
    category = "Administrative"
  }
  
  enabled_log {
    category = "Security"
  }
  
  enabled_log {
    category = "ServiceHealth"
  }
  
  enabled_log {
    category = "Alert"
  }
  
  enabled_log {
    category = "Recommendation"
  }
  
  enabled_log {
    category = "Policy"
  }
  
  enabled_log {
    category = "Autoscale"
  }
  
  enabled_log {
    category = "ResourceHealth"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for NSG
resource "azurerm_monitor_diagnostic_setting" "customer_nsg_diagnostics" {
  name                       = "nsg-diagnostics-${random_string.suffix.result}"
  target_resource_id         = azurerm_network_security_group.customer_nsg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lighthouse_monitoring.id
  
  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }
  
  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}
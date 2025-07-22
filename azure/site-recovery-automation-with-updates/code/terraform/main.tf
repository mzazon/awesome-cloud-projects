# Main Terraform Configuration for Azure Disaster Recovery Solution
# This configuration implements automated disaster recovery using Azure Site Recovery
# and Azure Update Manager for comprehensive business continuity

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# ==============================================================================
# RESOURCE GROUPS
# ==============================================================================

# Primary resource group for production resources
resource "azurerm_resource_group" "primary" {
  name     = "${var.project_name}-primary-${var.environment}-${random_string.suffix.result}"
  location = var.primary_location
  
  tags = merge(var.tags, {
    Region = "Primary"
    Role   = "Production"
  })
}

# Secondary resource group for disaster recovery resources
resource "azurerm_resource_group" "secondary" {
  name     = "${var.project_name}-secondary-${var.environment}-${random_string.suffix.result}"
  location = var.secondary_location
  
  tags = merge(var.tags, {
    Region = "Secondary"
    Role   = "DisasterRecovery"
  })
}

# ==============================================================================
# VIRTUAL NETWORKS
# ==============================================================================

# Primary virtual network for production workloads
resource "azurerm_virtual_network" "primary" {
  name                = "vnet-${var.project_name}-primary-${random_string.suffix.result}"
  address_space       = var.primary_vnet_address_space
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  
  tags = merge(var.tags, {
    Region = "Primary"
    Type   = "Production"
  })
}

# Secondary virtual network for disaster recovery
resource "azurerm_virtual_network" "secondary" {
  name                = "vnet-${var.project_name}-secondary-${random_string.suffix.result}"
  address_space       = var.secondary_vnet_address_space
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  
  tags = merge(var.tags, {
    Region = "Secondary"
    Type   = "DisasterRecovery"
  })
}

# Primary subnet for production VMs
resource "azurerm_subnet" "primary" {
  name                 = "subnet-${var.project_name}-primary"
  resource_group_name  = azurerm_resource_group.primary.name
  virtual_network_name = azurerm_virtual_network.primary.name
  address_prefixes     = [var.primary_subnet_address_prefix]
}

# Secondary subnet for disaster recovery VMs
resource "azurerm_subnet" "secondary" {
  name                 = "subnet-${var.project_name}-secondary"
  resource_group_name  = azurerm_resource_group.secondary.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = [var.secondary_subnet_address_prefix]
}

# ==============================================================================
# NETWORK SECURITY GROUPS
# ==============================================================================

# Network Security Group for primary environment
resource "azurerm_network_security_group" "primary" {
  name                = "nsg-${var.project_name}-primary-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  
  tags = merge(var.tags, {
    Region = "Primary"
    Type   = "Security"
  })
}

# Network Security Group for secondary environment
resource "azurerm_network_security_group" "secondary" {
  name                = "nsg-${var.project_name}-secondary-${random_string.suffix.result}"
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  
  tags = merge(var.tags, {
    Region = "Secondary"
    Type   = "Security"
  })
}

# Security rules for primary NSG
resource "azurerm_network_security_rule" "primary_rules" {
  count = length(var.network_security_rules)
  
  name                        = var.network_security_rules[count.index].name
  priority                    = var.network_security_rules[count.index].priority
  direction                   = var.network_security_rules[count.index].direction
  access                      = var.network_security_rules[count.index].access
  protocol                    = var.network_security_rules[count.index].protocol
  source_port_range           = var.network_security_rules[count.index].source_port_range
  destination_port_range      = var.network_security_rules[count.index].destination_port_range
  source_address_prefix       = var.network_security_rules[count.index].source_address_prefix
  destination_address_prefix  = var.network_security_rules[count.index].destination_address_prefix
  resource_group_name         = azurerm_resource_group.primary.name
  network_security_group_name = azurerm_network_security_group.primary.name
}

# Security rules for secondary NSG
resource "azurerm_network_security_rule" "secondary_rules" {
  count = length(var.network_security_rules)
  
  name                        = var.network_security_rules[count.index].name
  priority                    = var.network_security_rules[count.index].priority
  direction                   = var.network_security_rules[count.index].direction
  access                      = var.network_security_rules[count.index].access
  protocol                    = var.network_security_rules[count.index].protocol
  source_port_range           = var.network_security_rules[count.index].source_port_range
  destination_port_range      = var.network_security_rules[count.index].destination_port_range
  source_address_prefix       = var.network_security_rules[count.index].source_address_prefix
  destination_address_prefix  = var.network_security_rules[count.index].destination_address_prefix
  resource_group_name         = azurerm_resource_group.secondary.name
  network_security_group_name = azurerm_network_security_group.secondary.name
}

# Associate NSG with primary subnet
resource "azurerm_subnet_network_security_group_association" "primary" {
  subnet_id                 = azurerm_subnet.primary.id
  network_security_group_id = azurerm_network_security_group.primary.id
}

# Associate NSG with secondary subnet
resource "azurerm_subnet_network_security_group_association" "secondary" {
  subnet_id                 = azurerm_subnet.secondary.id
  network_security_group_id = azurerm_network_security_group.secondary.id
}

# ==============================================================================
# RECOVERY SERVICES VAULT
# ==============================================================================

# Recovery Services Vault for Azure Site Recovery and backup
resource "azurerm_recovery_services_vault" "main" {
  name                = "rsv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  sku                 = "Standard"
  storage_mode_type   = var.vault_storage_model_type
  
  cross_region_restore_enabled = var.vault_cross_region_restore_enabled
  soft_delete_enabled         = var.vault_soft_delete_enabled
  
  tags = merge(var.tags, {
    Service = "Recovery"
    Region  = "Secondary"
  })
}

# ==============================================================================
# BACKUP POLICY
# ==============================================================================

# Backup policy for virtual machines
resource "azurerm_backup_policy_vm" "main" {
  name                = "policy-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.secondary.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  
  timezone = "UTC"
  
  backup {
    frequency = var.backup_frequency
    time      = var.backup_time
  }
  
  retention_daily {
    count = var.backup_retention_daily
  }
  
  retention_weekly {
    count    = var.backup_retention_weekly
    weekdays = ["Sunday", "Wednesday", "Friday", "Saturday"]
  }
  
  retention_monthly {
    count    = var.backup_retention_monthly
    weekdays = ["Sunday", "Wednesday"]
    weeks    = ["First", "Last"]
  }
  
  retention_yearly {
    count    = var.backup_retention_yearly
    weekdays = ["Sunday"]
    weeks    = ["Last"]
    months   = ["January"]
  }
  
  tags = merge(var.tags, {
    Service = "Backup"
    Type    = "Policy"
  })
}

# ==============================================================================
# VIRTUAL MACHINE CONFIGURATION
# ==============================================================================

# Public IP for primary VM
resource "azurerm_public_ip" "primary_vm" {
  name                = "pip-${var.project_name}-primary-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(var.tags, {
    Service = "Compute"
    Region  = "Primary"
  })
}

# Network interface for primary VM
resource "azurerm_network_interface" "primary_vm" {
  name                = "nic-${var.project_name}-primary-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.primary.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.primary_vm.id
  }
  
  tags = merge(var.tags, {
    Service = "Compute"
    Region  = "Primary"
  })
}

# Primary Windows VM
resource "azurerm_windows_virtual_machine" "primary" {
  name                = "vm-${var.project_name}-primary-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password
  
  # Disable password authentication for security
  disable_password_authentication = false
  
  network_interface_ids = [
    azurerm_network_interface.primary_vm.id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_storage_account_type
  }
  
  source_image_reference {
    publisher = var.vm_image_publisher
    offer     = var.vm_image_offer
    sku       = var.vm_image_sku
    version   = var.vm_image_version
  }
  
  # Enable Azure extensions
  depends_on = [
    azurerm_subnet_network_security_group_association.primary
  ]
  
  tags = merge(var.tags, {
    Service = "Compute"
    Region  = "Primary"
    Role    = "Production"
  })
}

# ==============================================================================
# BACKUP CONFIGURATION
# ==============================================================================

# Backup protection for primary VM
resource "azurerm_backup_protected_vm" "primary" {
  resource_group_name = azurerm_resource_group.secondary.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = azurerm_windows_virtual_machine.primary.id
  backup_policy_id    = azurerm_backup_policy_vm.main.id
  
  depends_on = [
    azurerm_windows_virtual_machine.primary
  ]
  
  tags = merge(var.tags, {
    Service = "Backup"
    VM      = "Primary"
  })
}

# ==============================================================================
# LOG ANALYTICS WORKSPACE
# ==============================================================================

# Log Analytics workspace for monitoring and update management
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    Service = "Monitoring"
    Type    = "LogAnalytics"
  })
}

# ==============================================================================
# AUTOMATION ACCOUNT
# ==============================================================================

# Azure Automation Account for update management
resource "azurerm_automation_account" "main" {
  name                = "auto-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  sku_name            = var.automation_sku
  
  tags = merge(var.tags, {
    Service = "Automation"
    Type    = "UpdateManagement"
  })
}

# Link Log Analytics workspace to Automation Account
resource "azurerm_log_analytics_linked_service" "main" {
  resource_group_name = azurerm_resource_group.primary.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  read_access_id      = azurerm_automation_account.main.id
  
  depends_on = [
    azurerm_log_analytics_workspace.main,
    azurerm_automation_account.main
  ]
}

# ==============================================================================
# UPDATE MANAGEMENT SOLUTION
# ==============================================================================

# Update Management solution for Log Analytics workspace
resource "azurerm_log_analytics_solution" "update_management" {
  count = var.enable_update_management ? 1 : 0
  
  solution_name         = "Updates"
  location              = azurerm_resource_group.primary.location
  resource_group_name   = azurerm_resource_group.primary.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Updates"
  }
  
  depends_on = [
    azurerm_log_analytics_workspace.main
  ]
  
  tags = merge(var.tags, {
    Service = "UpdateManagement"
    Type    = "Solution"
  })
}

# Change Tracking solution for Log Analytics workspace
resource "azurerm_log_analytics_solution" "change_tracking" {
  count = var.enable_change_tracking ? 1 : 0
  
  solution_name         = "ChangeTracking"
  location              = azurerm_resource_group.primary.location
  resource_group_name   = azurerm_resource_group.primary.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ChangeTracking"
  }
  
  depends_on = [
    azurerm_log_analytics_workspace.main
  ]
  
  tags = merge(var.tags, {
    Service = "ChangeTracking"
    Type    = "Solution"
  })
}

# ==============================================================================
# VIRTUAL MACHINE EXTENSIONS
# ==============================================================================

# Microsoft Monitoring Agent extension for update management
resource "azurerm_virtual_machine_extension" "mma" {
  name                 = "MMAExtension"
  virtual_machine_id   = azurerm_windows_virtual_machine.primary.id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "MicrosoftMonitoringAgent"
  type_handler_version = "1.0"
  
  settings = jsonencode({
    "workspaceId" = azurerm_log_analytics_workspace.main.workspace_id
  })
  
  protected_settings = jsonencode({
    "workspaceKey" = azurerm_log_analytics_workspace.main.primary_shared_key
  })
  
  depends_on = [
    azurerm_windows_virtual_machine.primary,
    azurerm_log_analytics_workspace.main
  ]
  
  tags = merge(var.tags, {
    Service = "Monitoring"
    Type    = "Extension"
  })
}

# Dependency Agent extension for service mapping
resource "azurerm_virtual_machine_extension" "dependency_agent" {
  name                 = "DependencyAgentWindows"
  virtual_machine_id   = azurerm_windows_virtual_machine.primary.id
  publisher            = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                 = "DependencyAgentWindows"
  type_handler_version = "9.5"
  
  depends_on = [
    azurerm_virtual_machine_extension.mma
  ]
  
  tags = merge(var.tags, {
    Service = "Monitoring"
    Type    = "Extension"
  })
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

# Action group for disaster recovery alerts
resource "azurerm_monitor_action_group" "dr_alerts" {
  name                = "ag-${var.project_name}-dr-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  short_name          = "DR-Alerts"
  
  email_receiver {
    name          = "admin-email"
    email_address = var.alert_email_address
  }
  
  tags = merge(var.tags, {
    Service = "Monitoring"
    Type    = "ActionGroup"
  })
}

# Metric alert for VM CPU usage
resource "azurerm_monitor_metric_alert" "vm_cpu" {
  name                = "alert-vm-cpu-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  scopes              = [azurerm_windows_virtual_machine.primary.id]
  description         = "Alert when VM CPU usage exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.dr_alerts.id
  }
  
  depends_on = [
    azurerm_windows_virtual_machine.primary
  ]
  
  tags = merge(var.tags, {
    Service = "Monitoring"
    Type    = "Alert"
  })
}

# Metric alert for backup job failures
resource "azurerm_monitor_metric_alert" "backup_failure" {
  name                = "alert-backup-failure-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.secondary.name
  scopes              = [azurerm_recovery_services_vault.main.id]
  description         = "Alert when backup job fails"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.RecoveryServices/vaults"
    metric_name      = "BackupJobFailureCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.dr_alerts.id
  }
  
  depends_on = [
    azurerm_recovery_services_vault.main
  ]
  
  tags = merge(var.tags, {
    Service = "Monitoring"
    Type    = "Alert"
  })
}

# ==============================================================================
# NETWORK WATCHER (OPTIONAL)
# ==============================================================================

# Network Watcher for primary region
resource "azurerm_network_watcher" "primary" {
  count = var.enable_network_watcher ? 1 : 0
  
  name                = "nw-${var.project_name}-primary-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  
  tags = merge(var.tags, {
    Service = "NetworkWatcher"
    Region  = "Primary"
  })
}

# Network Watcher for secondary region
resource "azurerm_network_watcher" "secondary" {
  count = var.enable_network_watcher ? 1 : 0
  
  name                = "nw-${var.project_name}-secondary-${random_string.suffix.result}"
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  
  tags = merge(var.tags, {
    Service = "NetworkWatcher"
    Region  = "Secondary"
  })
}

# ==============================================================================
# AUTOMATION RUNBOOKS
# ==============================================================================

# Disaster recovery orchestration runbook
resource "azurerm_automation_runbook" "dr_orchestration" {
  name                    = "DR-Orchestration"
  location                = azurerm_resource_group.primary.location
  resource_group_name     = azurerm_resource_group.primary.name
  automation_account_name = azurerm_automation_account.main.name
  log_verbose             = true
  log_progress            = true
  description             = "Orchestrates disaster recovery failover process"
  runbook_type            = "PowerShell"
  
  content = <<-CONTENT
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$VaultName,
        
        [Parameter(Mandatory=$true)]
        [string]$VMName
    )
    
    Write-Output "Starting disaster recovery orchestration for VM: $VMName"
    
    # Import Azure modules
    Import-Module Az.Profile
    Import-Module Az.RecoveryServices
    
    try {
        # Connect to Azure using managed identity
        Connect-AzAccount -Identity
        
        # Set context for Recovery Services Vault
        $Vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName
        Set-AzRecoveryServicesVaultContext -Vault $Vault
        
        # Get backup item
        $BackupItem = Get-AzRecoveryServicesBackupItem -Container $VMName -WorkloadType AzureVM
        
        if ($BackupItem) {
            Write-Output "Backup item found for VM: $VMName"
            Write-Output "Latest recovery point: $($BackupItem.LastBackupTime)"
        } else {
            Write-Error "No backup item found for VM: $VMName"
            exit 1
        }
        
        Write-Output "Disaster recovery orchestration completed successfully"
    }
    catch {
        Write-Error "Error during disaster recovery orchestration: $($_.Exception.Message)"
        exit 1
    }
    CONTENT
  
  depends_on = [
    azurerm_automation_account.main
  ]
  
  tags = merge(var.tags, {
    Service = "Automation"
    Type    = "Runbook"
  })
}

# ==============================================================================
# SITE RECOVERY CONFIGURATION
# ==============================================================================

# Site Recovery fabric for primary region
resource "azurerm_site_recovery_fabric" "primary" {
  name                = "fabric-${var.project_name}-primary"
  resource_group_name = azurerm_resource_group.secondary.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  location            = azurerm_resource_group.primary.location
  
  depends_on = [
    azurerm_recovery_services_vault.main
  ]
  
  tags = merge(var.tags, {
    Service = "SiteRecovery"
    Region  = "Primary"
  })
}

# Site Recovery fabric for secondary region
resource "azurerm_site_recovery_fabric" "secondary" {
  name                = "fabric-${var.project_name}-secondary"
  resource_group_name = azurerm_resource_group.secondary.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  location            = azurerm_resource_group.secondary.location
  
  depends_on = [
    azurerm_recovery_services_vault.main
  ]
  
  tags = merge(var.tags, {
    Service = "SiteRecovery"
    Region  = "Secondary"
  })
}

# Site Recovery protection container for primary region
resource "azurerm_site_recovery_protection_container" "primary" {
  name                 = "container-${var.project_name}-primary"
  resource_group_name  = azurerm_resource_group.secondary.name
  recovery_vault_name  = azurerm_recovery_services_vault.main.name
  recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
  
  depends_on = [
    azurerm_site_recovery_fabric.primary
  ]
  
  tags = merge(var.tags, {
    Service = "SiteRecovery"
    Region  = "Primary"
  })
}

# Site Recovery protection container for secondary region
resource "azurerm_site_recovery_protection_container" "secondary" {
  name                 = "container-${var.project_name}-secondary"
  resource_group_name  = azurerm_resource_group.secondary.name
  recovery_vault_name  = azurerm_recovery_services_vault.main.name
  recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
  
  depends_on = [
    azurerm_site_recovery_fabric.secondary
  ]
  
  tags = merge(var.tags, {
    Service = "SiteRecovery"
    Region  = "Secondary"
  })
}

# Storage account for cache storage in primary region
resource "azurerm_storage_account" "cache" {
  name                     = "cache${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.primary.name
  location                 = azurerm_resource_group.primary.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = merge(var.tags, {
    Service = "Storage"
    Type    = "Cache"
  })
}

# ==============================================================================
# COST MANAGEMENT (OPTIONAL)
# ==============================================================================

# Budget for cost management
resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.enable_cost_alerts ? 1 : 0
  
  name              = "budget-${var.project_name}-${random_string.suffix.result}"
  resource_group_id = azurerm_resource_group.primary.id
  
  amount     = var.monthly_budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h"))
  }
  
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = [var.alert_email_address]
  }
  
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = [var.alert_email_address]
  }
  
  depends_on = [
    azurerm_resource_group.primary
  ]
}
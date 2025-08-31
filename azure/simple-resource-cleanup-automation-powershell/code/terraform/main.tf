# Azure Resource Cleanup Automation Infrastructure
# This Terraform configuration creates an automated resource cleanup solution
# using Azure Automation Account with PowerShell runbooks and scheduled execution

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Calculate start time for schedule (tomorrow at specified hour)
resource "time_offset" "schedule_start" {
  offset_days = 1
}

locals {
  # Generate unique names for resources
  automation_account_name = var.automation_account_name != null ? var.automation_account_name : "aa-cleanup-${random_string.suffix.result}"
  test_resource_group_name = var.test_resource_group_name != null ? var.test_resource_group_name : "rg-cleanup-test-${random_string.suffix.result}"
  
  # Calculate schedule start time (tomorrow at specified hour in UTC)
  schedule_start_time = formatdate("YYYY-MM-DD'T'${format("%02d", var.schedule_start_hour)}:00:00Z", timeadd(timestamp(), "24h"))
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    Purpose = "ResourceCleanupAutomation"
    CreatedBy = "Terraform"
    CreatedOn = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group for automation resources
resource "azurerm_resource_group" "automation" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure Automation Account with system-assigned managed identity
resource "azurerm_automation_account" "cleanup" {
  name                          = local.automation_account_name
  location                      = azurerm_resource_group.automation.location
  resource_group_name           = azurerm_resource_group.automation.name
  sku_name                      = var.automation_account_sku
  public_network_access_enabled = var.enable_public_network_access
  local_authentication_enabled  = var.enable_local_authentication
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "AutomationAccount"
    Purpose      = "ResourceCleanup"
  })
}

# Role assignment to grant Contributor permissions to the managed identity
# This allows the automation account to manage resources across the subscription
resource "azurerm_role_assignment" "automation_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.cleanup.identity[0].principal_id
  
  depends_on = [azurerm_automation_account.cleanup]
}

# PowerShell runbook for automated resource cleanup
resource "azurerm_automation_runbook" "cleanup" {
  name                    = var.runbook_name
  location                = azurerm_resource_group.automation.location
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.cleanup.name
  log_verbose             = true
  log_progress            = true
  description             = "Automated cleanup of Azure resources based on tags and age criteria"
  runbook_type            = "PowerShell"
  
  # PowerShell script content for resource cleanup
  content = templatefile("${path.module}/cleanup-runbook.ps1", {
    default_days_old = var.default_cleanup_days_old
    default_environment = var.default_environment_filter
    default_dry_run = var.enable_dry_run_by_default
  })
  
  tags = merge(local.common_tags, {
    ResourceType = "AutomationRunbook"
    RunbookType  = "PowerShell"
  })
  
  depends_on = [azurerm_automation_account.cleanup]
}

# Schedule for automated cleanup execution
resource "azurerm_automation_schedule" "cleanup" {
  name                    = var.schedule_name
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.cleanup.name
  frequency               = var.schedule_frequency
  interval                = var.schedule_interval
  timezone                = var.schedule_timezone
  start_time              = local.schedule_start_time
  description             = "Weekly schedule for automated resource cleanup"
  
  # Set week days only if frequency is "Week"
  week_days = var.schedule_frequency == "Week" ? var.schedule_week_days : null
  
  depends_on = [azurerm_automation_account.cleanup]
}

# Link the runbook to the schedule with default parameters
resource "azurerm_automation_job_schedule" "cleanup" {
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.cleanup.name
  runbook_name            = azurerm_automation_runbook.cleanup.name
  schedule_name           = azurerm_automation_schedule.cleanup.name
  
  # Default parameters for the runbook execution
  parameters = {
    daysold     = tostring(var.default_cleanup_days_old)
    environment = var.default_environment_filter
    dryrun      = tostring(var.enable_dry_run_by_default)
  }
  
  depends_on = [
    azurerm_automation_runbook.cleanup,
    azurerm_automation_schedule.cleanup
  ]
}

# Optional: Create test resource group for demonstrating cleanup functionality
resource "azurerm_resource_group" "test" {
  count    = var.create_test_resources ? 1 : 0
  name     = local.test_resource_group_name
  location = var.location
  
  tags = merge(local.common_tags, {
    Environment   = var.default_environment_filter
    AutoCleanup   = "true"
    Project       = "Testing"
    CreatedBy     = "Terraform"
    ResourceType  = "TestResourceGroup"
  })
}

# Optional: Create test storage account that will be subject to cleanup
resource "azurerm_storage_account" "test_cleanup" {
  count                    = var.create_test_resources ? 1 : 0
  name                     = "sttest${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.test[0].name
  location                 = azurerm_resource_group.test[0].location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = merge(local.common_tags, {
    Environment   = var.default_environment_filter
    AutoCleanup   = "true"
    Purpose       = "Testing"
    ResourceType  = "TestStorageAccount"
  })
  
  depends_on = [azurerm_resource_group.test]
}

# Optional: Create protected storage account that will NOT be cleaned up
resource "azurerm_storage_account" "test_protected" {
  count                    = var.create_test_resources ? 1 : 0
  name                     = "stprotected${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.test[0].name
  location                 = azurerm_resource_group.test[0].location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = merge(local.common_tags, {
    Environment   = var.default_environment_filter
    DoNotDelete   = "true"
    Purpose       = "Production"
    ResourceType  = "ProtectedStorageAccount"
  })
  
  depends_on = [azurerm_resource_group.test]
}
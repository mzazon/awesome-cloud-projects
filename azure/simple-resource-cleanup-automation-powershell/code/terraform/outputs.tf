# Outputs for Azure resource cleanup automation infrastructure
# These outputs provide essential information for verification and integration

output "resource_group_name" {
  description = "The name of the resource group containing automation resources"
  value       = azurerm_resource_group.automation.name
}

output "resource_group_id" {
  description = "The ID of the resource group containing automation resources"
  value       = azurerm_resource_group.automation.id
}

output "automation_account_name" {
  description = "The name of the Azure Automation account"
  value       = azurerm_automation_account.cleanup.name
}

output "automation_account_id" {
  description = "The ID of the Azure Automation account"
  value       = azurerm_automation_account.cleanup.id
}

output "automation_account_dsc_server_endpoint" {
  description = "The DSC server endpoint for the automation account"
  value       = azurerm_automation_account.cleanup.dsc_server_endpoint
  sensitive   = true
}

output "managed_identity_principal_id" {
  description = "The principal ID of the automation account's managed identity"
  value       = azurerm_automation_account.cleanup.identity[0].principal_id
}

output "managed_identity_tenant_id" {
  description = "The tenant ID of the automation account's managed identity"
  value       = azurerm_automation_account.cleanup.identity[0].tenant_id
}

output "runbook_name" {
  description = "The name of the PowerShell cleanup runbook"
  value       = azurerm_automation_runbook.cleanup.name
}

output "runbook_id" {
  description = "The ID of the PowerShell cleanup runbook"
  value       = azurerm_automation_runbook.cleanup.id
}

output "schedule_name" {
  description = "The name of the automation schedule"
  value       = azurerm_automation_schedule.cleanup.name
}

output "schedule_id" {
  description = "The ID of the automation schedule"
  value       = azurerm_automation_schedule.cleanup.id
}

output "schedule_next_run_time" {
  description = "The next scheduled run time for the cleanup automation"
  value       = azurerm_automation_schedule.cleanup.start_time
}

output "job_schedule_id" {
  description = "The ID of the job schedule linking the runbook and schedule"
  value       = azurerm_automation_job_schedule.cleanup.id
}

output "job_schedule_uuid" {
  description = "The UUID of the automation job schedule"
  value       = azurerm_automation_job_schedule.cleanup.job_schedule_id
}

# Test resources outputs (conditional)
output "test_resource_group_name" {
  description = "The name of the test resource group (if created)"
  value       = var.create_test_resources ? azurerm_resource_group.test[0].name : null
}

output "test_resource_group_id" {
  description = "The ID of the test resource group (if created)"
  value       = var.create_test_resources ? azurerm_resource_group.test[0].id : null
}

output "test_storage_account_name" {
  description = "The name of the test storage account that will be cleaned up (if created)"
  value       = var.create_test_resources ? azurerm_storage_account.test_cleanup[0].name : null
}

output "protected_storage_account_name" {
  description = "The name of the protected storage account that will NOT be cleaned up (if created)"
  value       = var.create_test_resources ? azurerm_storage_account.test_protected[0].name : null
}

# Configuration outputs for verification
output "cleanup_configuration" {
  description = "Summary of cleanup configuration parameters"
  value = {
    default_days_old               = var.default_cleanup_days_old
    default_environment_filter     = var.default_environment_filter
    dry_run_enabled_by_default    = var.enable_dry_run_by_default
    schedule_frequency            = var.schedule_frequency
    schedule_interval             = var.schedule_interval
    schedule_week_days            = var.schedule_frequency == "Week" ? var.schedule_week_days : null
    schedule_timezone             = var.schedule_timezone
    automation_account_sku        = var.automation_account_sku
  }
}

# Azure portal URLs for easy access
output "azure_portal_urls" {
  description = "Direct links to Azure portal for managing the automation resources"
  value = {
    automation_account = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_automation_account.cleanup.id}"
    runbook           = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_automation_runbook.cleanup.id}"
    schedule          = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_automation_schedule.cleanup.id}"
    resource_group    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.automation.id}"
  }
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group = {
      name     = azurerm_resource_group.automation.name
      location = azurerm_resource_group.automation.location
      purpose  = "Container for automation resources"
    }
    automation_account = {
      name     = azurerm_automation_account.cleanup.name
      sku      = azurerm_automation_account.cleanup.sku_name
      identity = "SystemAssigned"
      purpose  = "Hosts runbooks and schedules for automation"
    }
    runbook = {
      name     = azurerm_automation_runbook.cleanup.name
      type     = azurerm_automation_runbook.cleanup.runbook_type
      purpose  = "PowerShell script for automated resource cleanup"
    }
    schedule = {
      name      = azurerm_automation_schedule.cleanup.name
      frequency = azurerm_automation_schedule.cleanup.frequency
      interval  = azurerm_automation_schedule.cleanup.interval
      timezone  = azurerm_automation_schedule.cleanup.timezone
      purpose   = "Triggers automated cleanup execution"
    }
    permissions = {
      scope = "Subscription-wide Contributor access"
      type  = "Managed Identity RBAC assignment"
      purpose = "Allows automation account to manage Azure resources"
    }
  }
}

# Cost estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the automation infrastructure (USD)"
  value = {
    automation_account_basic_sku = "~$5-10 (includes 500 minutes of runbook execution)"
    runbook_execution_minutes   = "Included in Basic SKU (first 500 minutes free)"
    storage_for_logs           = "~$1-2 (for automation logs and job history)"
    total_estimated            = "~$6-12 per month"
    note                       = "Actual costs may vary based on usage patterns and execution frequency"
  }
}

# Next steps and usage instructions
output "usage_instructions" {
  description = "Instructions for using and managing the deployed automation"
  value = {
    manual_execution = "Run the runbook manually from Azure portal or use Start-AzAutomationRunbook PowerShell command"
    modify_schedule  = "Update schedule frequency and timing through Azure portal or Terraform variables"
    view_logs       = "Check runbook execution logs in Azure portal under Automation Account > Jobs"
    customize_logic = "Modify the PowerShell script in the runbook to adjust cleanup criteria"
    test_safely     = "Always test with DryRun=true parameter before running actual cleanup"
    monitor_costs   = "Set up cost alerts to monitor savings from automated cleanup"
  }
}
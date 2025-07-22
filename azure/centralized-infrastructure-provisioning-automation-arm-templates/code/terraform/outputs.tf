# Resource Group outputs
output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.automation.name
}

output "resource_group_id" {
  description = "ID of the main resource group"
  value       = azurerm_resource_group.automation.id
}

output "target_resource_group_name" {
  description = "Name of the target resource group for deployments"
  value       = azurerm_resource_group.target.name
}

output "target_resource_group_id" {
  description = "ID of the target resource group for deployments"
  value       = azurerm_resource_group.target.id
}

# Azure Automation Account outputs
output "automation_account_name" {
  description = "Name of the Azure Automation Account"
  value       = azurerm_automation_account.main.name
}

output "automation_account_id" {
  description = "ID of the Azure Automation Account"
  value       = azurerm_automation_account.main.id
}

output "automation_account_dsc_server_endpoint" {
  description = "DSC server endpoint for the Automation Account"
  value       = azurerm_automation_account.main.dsc_server_endpoint
}

output "automation_account_dsc_primary_access_key" {
  description = "DSC primary access key for the Automation Account"
  value       = azurerm_automation_account.main.dsc_primary_access_key
  sensitive   = true
}

output "automation_account_dsc_secondary_access_key" {
  description = "DSC secondary access key for the Automation Account"
  value       = azurerm_automation_account.main.dsc_secondary_access_key
  sensitive   = true
}

# Managed Identity outputs
output "managed_identity_principal_id" {
  description = "Principal ID of the Automation Account's managed identity"
  value       = var.enable_managed_identity ? azurerm_automation_account.main.identity[0].principal_id : null
}

output "managed_identity_tenant_id" {
  description = "Tenant ID of the Automation Account's managed identity"
  value       = var.enable_managed_identity ? azurerm_automation_account.main.identity[0].tenant_id : null
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account for ARM templates"
  value       = azurerm_storage_account.arm_templates.name
}

output "storage_account_id" {
  description = "ID of the storage account for ARM templates"
  value       = azurerm_storage_account.arm_templates.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.arm_templates.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.arm_templates.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "Secondary access key of the storage account"
  value       = azurerm_storage_account.arm_templates.secondary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account"
  value       = azurerm_storage_account.arm_templates.primary_connection_string
  sensitive   = true
}

# File Share outputs
output "file_share_name" {
  description = "Name of the file share for ARM templates"
  value       = azurerm_storage_share.arm_templates.name
}

output "file_share_id" {
  description = "ID of the file share for ARM templates"
  value       = azurerm_storage_share.arm_templates.id
}

output "file_share_url" {
  description = "URL of the file share for ARM templates"
  value       = azurerm_storage_share.arm_templates.url
}

# Runbook outputs
output "runbook_name" {
  description = "Name of the PowerShell runbook"
  value       = azurerm_automation_runbook.deploy_infrastructure.name
}

output "runbook_id" {
  description = "ID of the PowerShell runbook"
  value       = azurerm_automation_runbook.deploy_infrastructure.id
}

output "runbook_type" {
  description = "Type of the PowerShell runbook"
  value       = azurerm_automation_runbook.deploy_infrastructure.runbook_type
}

# Log Analytics outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.automation.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.automation.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.automation.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.automation.secondary_shared_key
  sensitive   = true
}

# PowerShell Modules outputs
output "installed_powershell_modules" {
  description = "List of installed PowerShell modules"
  value = {
    for module_name, module in azurerm_automation_module.powershell_modules : module_name => {
      name = module.name
      id   = module.id
    }
  }
}

# Role Assignment outputs
output "role_assignments" {
  description = "Information about role assignments for the managed identity"
  value = {
    main_resource_group_contributor = {
      id         = azurerm_role_assignment.automation_contributor_main.id
      scope      = azurerm_role_assignment.automation_contributor_main.scope
      role       = azurerm_role_assignment.automation_contributor_main.role_definition_name
      principal_id = azurerm_role_assignment.automation_contributor_main.principal_id
    }
    target_resource_group_contributor = {
      id         = azurerm_role_assignment.automation_contributor_target.id
      scope      = azurerm_role_assignment.automation_contributor_target.scope
      role       = azurerm_role_assignment.automation_contributor_target.role_definition_name
      principal_id = azurerm_role_assignment.automation_contributor_target.principal_id
    }
    storage_blob_contributor = {
      id         = azurerm_role_assignment.automation_storage_contributor.id
      scope      = azurerm_role_assignment.automation_storage_contributor.scope
      role       = azurerm_role_assignment.automation_storage_contributor.role_definition_name
      principal_id = azurerm_role_assignment.automation_storage_contributor.principal_id
    }
  }
}

# Monitoring outputs
output "action_group_id" {
  description = "ID of the action group for automation alerts"
  value       = azurerm_monitor_action_group.automation_alerts.id
}

output "runbook_failure_alert_id" {
  description = "ID of the runbook failure alert rule"
  value       = azurerm_monitor_metric_alert.runbook_failures.id
}

# Deployment configuration outputs
output "deployment_configuration" {
  description = "Configuration values for ARM template deployments"
  value = {
    storage_account_type = var.arm_template_storage_account_type
    environment         = var.arm_template_environment
    location           = var.location
  }
}

# Runbook execution parameters template
output "runbook_execution_parameters" {
  description = "Template for runbook execution parameters"
  value = {
    ResourceGroupName   = azurerm_resource_group.target.name
    StorageAccountName  = azurerm_storage_account.arm_templates.name
    TemplateName       = "infrastructure-template.json"
    Environment        = var.arm_template_environment
    StorageAccountType = var.arm_template_storage_account_type
  }
}

# Azure CLI commands for runbook execution
output "azure_cli_commands" {
  description = "Azure CLI commands for managing the automation infrastructure"
  value = {
    start_runbook = "az automation runbook start --resource-group ${azurerm_resource_group.automation.name} --automation-account-name ${azurerm_automation_account.main.name} --name ${azurerm_automation_runbook.deploy_infrastructure.name} --parameters resourceGroupName=${azurerm_resource_group.target.name} storageAccountName=${azurerm_storage_account.arm_templates.name} templateName=infrastructure-template.json environment=${var.arm_template_environment}"
    
    list_jobs = "az automation job list --resource-group ${azurerm_resource_group.automation.name} --automation-account-name ${azurerm_automation_account.main.name}"
    
    show_job_output = "az automation job output --resource-group ${azurerm_resource_group.automation.name} --automation-account-name ${azurerm_automation_account.main.name} --job-id <JOB_ID>"
    
    list_deployments = "az deployment group list --resource-group ${azurerm_resource_group.target.name}"
    
    show_deployment = "az deployment group show --resource-group ${azurerm_resource_group.target.name} --name <DEPLOYMENT_NAME>"
  }
}

# Resource creation summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    resource_groups = {
      automation = azurerm_resource_group.automation.name
      target     = azurerm_resource_group.target.name
    }
    automation_account = azurerm_automation_account.main.name
    storage_account    = azurerm_storage_account.arm_templates.name
    file_share        = azurerm_storage_share.arm_templates.name
    runbook           = azurerm_automation_runbook.deploy_infrastructure.name
    log_analytics     = azurerm_log_analytics_workspace.automation.name
    powershell_modules = length(var.powershell_modules)
    role_assignments  = 3
    monitoring_alerts = 1
  }
}

# Security and compliance outputs
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    managed_identity_enabled     = var.enable_managed_identity
    public_network_access       = var.enable_public_network_access
    storage_https_only          = var.enable_storage_https_only
    storage_blob_public_access  = var.enable_storage_blob_public_access
    diagnostics_enabled         = var.enable_diagnostics
    tls_version                 = "1.2"
    encryption_at_rest         = "Enabled"
  }
}

# Cost optimization outputs
output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    storage_access_tier           = var.storage_access_tier
    automation_account_sku        = var.automation_account_sku
    log_analytics_sku            = var.log_analytics_sku
    log_retention_days           = var.log_analytics_retention_days
    diagnostic_retention_days    = var.diagnostic_retention_days
    cost_optimization_enabled    = var.enable_cost_optimization
  }
}

# Terraform configuration outputs
output "terraform_configuration" {
  description = "Terraform configuration information"
  value = {
    random_suffix = random_string.suffix.result
    subscription_id = data.azurerm_subscription.current.subscription_id
    tenant_id = data.azurerm_client_config.current.tenant_id
    client_id = data.azurerm_client_config.current.client_id
  }
}

# Validation outputs
output "validation_endpoints" {
  description = "Endpoints for validating the deployment"
  value = {
    automation_account_endpoint = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_automation_account.main.id}"
    storage_account_endpoint = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.arm_templates.id}"
    log_analytics_endpoint = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.automation.id}"
  }
}
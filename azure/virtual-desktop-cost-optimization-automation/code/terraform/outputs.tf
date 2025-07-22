# Outputs for Azure Virtual Desktop Cost Optimization Infrastructure
# This file defines all output values that can be used for verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all AVD resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where all resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the main resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Virtual Desktop Information
output "avd_workspace_name" {
  description = "Name of the Azure Virtual Desktop workspace"
  value       = azurerm_virtual_desktop_workspace.main.name
}

output "avd_workspace_id" {
  description = "Resource ID of the AVD workspace"
  value       = azurerm_virtual_desktop_workspace.main.id
}

output "avd_host_pool_name" {
  description = "Name of the AVD host pool"
  value       = azurerm_virtual_desktop_host_pool.main.name
}

output "avd_host_pool_id" {
  description = "Resource ID of the AVD host pool"
  value       = azurerm_virtual_desktop_host_pool.main.id
}

output "avd_application_group_name" {
  description = "Name of the AVD desktop application group"
  value       = azurerm_virtual_desktop_application_group.main.name
}

output "avd_application_group_id" {
  description = "Resource ID of the AVD application group"
  value       = azurerm_virtual_desktop_application_group.main.id
}

# VM Scale Set Information
output "vmss_name" {
  description = "Name of the VM Scale Set hosting AVD session hosts"
  value       = azurerm_windows_virtual_machine_scale_set.avd_hosts.name
}

output "vmss_id" {
  description = "Resource ID of the VM Scale Set"
  value       = azurerm_windows_virtual_machine_scale_set.avd_hosts.id
}

output "vmss_instance_count" {
  description = "Current number of instances in the VM Scale Set"
  value       = azurerm_windows_virtual_machine_scale_set.avd_hosts.instances
}

output "vmss_sku" {
  description = "VM SKU used for the scale set instances"
  value       = azurerm_windows_virtual_machine_scale_set.avd_hosts.sku
}

# Auto-scaling Configuration
output "autoscale_setting_name" {
  description = "Name of the auto-scale setting for the VM Scale Set"
  value       = azurerm_monitor_autoscale_setting.avd_autoscale.name
}

output "autoscale_setting_id" {
  description = "Resource ID of the auto-scale setting"
  value       = azurerm_monitor_autoscale_setting.avd_autoscale.id
}

output "autoscale_min_capacity" {
  description = "Minimum capacity configured for auto-scaling"
  value       = var.autoscale_min_capacity
}

output "autoscale_max_capacity" {
  description = "Maximum capacity configured for auto-scaling"
  value       = var.autoscale_max_capacity
}

# Networking Information
output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "avd_subnet_name" {
  description = "Name of the AVD subnet"
  value       = azurerm_subnet.avd_subnet.name
}

output "avd_subnet_id" {
  description = "Resource ID of the AVD subnet"
  value       = azurerm_subnet.avd_subnet.id
}

output "avd_subnet_address_prefix" {
  description = "Address prefix of the AVD subnet"
  value       = azurerm_subnet.avd_subnet.address_prefixes[0]
}

# Storage and Monitoring
output "storage_account_name" {
  description = "Name of the storage account for cost reports"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

# Cost Management and Automation
output "logic_app_name" {
  description = "Name of the Logic App for cost optimization (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.cost_optimizer[0].name : null
}

output "logic_app_id" {
  description = "Resource ID of the Logic App (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.cost_optimizer[0].id : null
}

output "function_app_name" {
  description = "Name of the Function App for RI analysis (if enabled)"
  value       = var.function_app_enabled ? azurerm_linux_function_app.ri_analyzer[0].name : null
}

output "function_app_id" {
  description = "Resource ID of the Function App (if enabled)"
  value       = var.function_app_enabled ? azurerm_linux_function_app.ri_analyzer[0].id : null
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App (if enabled)"
  value       = var.function_app_enabled ? azurerm_linux_function_app.ri_analyzer[0].default_hostname : null
}

# Department Budget Information
output "department_budgets" {
  description = "Information about department-specific budgets"
  value = {
    for idx, dept in var.departments : dept.name => {
      budget_name   = azurerm_consumption_budget_resource_group.department_budgets[idx].name
      budget_id     = azurerm_consumption_budget_resource_group.department_budgets[idx].id
      budget_amount = azurerm_consumption_budget_resource_group.department_budgets[idx].amount
      cost_center   = dept.cost_center
    }
  }
}

# Cost Attribution Tags
output "cost_attribution_tags" {
  description = "Standard tags applied for cost attribution across all resources"
  value = {
    Project     = var.tags.Project
    Environment = var.tags.Environment
    Purpose     = var.tags.Purpose
    ManagedBy   = var.tags.ManagedBy
  }
}

# Security Configuration
output "network_security_group_name" {
  description = "Name of the network security group for AVD subnet"
  value       = azurerm_network_security_group.avd_nsg.name
}

output "network_security_group_id" {
  description = "Resource ID of the network security group"
  value       = azurerm_network_security_group.avd_nsg.id
}

# Azure Subscription Information
output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Random Suffix for Resource Uniqueness
output "resource_suffix" {
  description = "Random suffix used to ensure resource name uniqueness"
  value       = random_string.suffix.result
}

# Cost Optimization Configuration Summary
output "cost_optimization_summary" {
  description = "Summary of cost optimization features enabled"
  value = {
    auto_scaling_enabled       = true
    logic_app_enabled         = var.logic_app_enabled
    function_app_enabled      = var.function_app_enabled
    department_budgets_count  = length(var.departments)
    vm_scale_set_sku         = var.vmss_sku
    host_pool_type           = var.avd_host_pool_type
    max_sessions_per_vm      = var.avd_max_session_limit
    budget_alert_thresholds  = {
      actual_percent    = var.budget_alert_threshold_actual
      forecast_percent  = var.budget_alert_threshold_forecast
    }
  }
}

# Connection Information for Users
output "avd_connection_info" {
  description = "Information needed to connect to Azure Virtual Desktop"
  value = {
    workspace_name = azurerm_virtual_desktop_workspace.main.name
    workspace_url  = "https://rdweb.wvd.microsoft.com/arm/webclient/index.html"
    feed_url      = "https://rdweb.wvd.microsoft.com/api/arm/feeddiscovery"
  }
}

# Monitoring and Alerting URLs
output "monitoring_urls" {
  description = "URLs for accessing monitoring and cost management tools"
  value = {
    log_analytics_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}"
    cost_management_url = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview"
    application_insights_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}"
  }
}
# Outputs for Azure Self-Healing Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Traffic Manager Information
output "traffic_manager_profile_name" {
  description = "Name of the Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.main.name
}

output "traffic_manager_fqdn" {
  description = "FQDN of the Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.main.fqdn
}

output "traffic_manager_id" {
  description = "ID of the Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.main.id
}

output "traffic_manager_endpoints" {
  description = "Information about Traffic Manager endpoints"
  value = {
    for region in var.web_app_regions : region => {
      name        = azurerm_traffic_manager_azure_endpoint.main[region].name
      id          = azurerm_traffic_manager_azure_endpoint.main[region].id
      priority    = azurerm_traffic_manager_azure_endpoint.main[region].priority
      weight      = azurerm_traffic_manager_azure_endpoint.main[region].weight
      target_url  = azurerm_linux_web_app.main[region].default_hostname
    }
  }
}

# Web Application Information
output "web_apps" {
  description = "Information about deployed web applications"
  value = {
    for region in var.web_app_regions : region => {
      name              = azurerm_linux_web_app.main[region].name
      id                = azurerm_linux_web_app.main[region].id
      default_hostname  = azurerm_linux_web_app.main[region].default_hostname
      location          = azurerm_linux_web_app.main[region].location
      service_plan_id   = azurerm_linux_web_app.main[region].service_plan_id
      site_config       = azurerm_linux_web_app.main[region].site_config
    }
  }
}

output "web_app_urls" {
  description = "URLs of the deployed web applications"
  value = {
    for region in var.web_app_regions : region => "https://${azurerm_linux_web_app.main[region].default_hostname}"
  }
}

# App Service Plans Information
output "app_service_plans" {
  description = "Information about App Service plans"
  value = {
    for region in var.web_app_regions : region => {
      name     = azurerm_service_plan.main[region].name
      id       = azurerm_service_plan.main[region].id
      location = azurerm_service_plan.main[region].location
      sku_name = azurerm_service_plan.main[region].sku_name
    }
  }
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity" {
  description = "Managed identity information for the Function App"
  value = {
    principal_id = azurerm_linux_function_app.main.identity[0].principal_id
    tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
  }
}

# Load Testing Information
output "load_testing_resource" {
  description = "Information about Azure Load Testing resource"
  value = var.enable_load_testing ? {
    name     = azurerm_load_test.main[0].name
    id       = azurerm_load_test.main[0].id
    location = azurerm_load_test.main[0].location
  } : null
}

# Monitoring Information
output "log_analytics_workspace" {
  description = "Information about Log Analytics workspace"
  value = {
    name          = azurerm_log_analytics_workspace.main.name
    id            = azurerm_log_analytics_workspace.main.id
    workspace_id  = azurerm_log_analytics_workspace.main.workspace_id
    location      = azurerm_log_analytics_workspace.main.location
  }
}

output "application_insights" {
  description = "Information about Application Insights"
  value = var.enable_application_insights ? {
    name                = azurerm_application_insights.main[0].name
    id                  = azurerm_application_insights.main[0].id
    instrumentation_key = azurerm_application_insights.main[0].instrumentation_key
    connection_string   = azurerm_application_insights.main[0].connection_string
    app_id             = azurerm_application_insights.main[0].app_id
  } : null
}

# Alert Information
output "action_group" {
  description = "Information about the action group"
  value = {
    name       = azurerm_monitor_action_group.main.name
    id         = azurerm_monitor_action_group.main.id
    short_name = azurerm_monitor_action_group.main.short_name
  }
}

output "response_time_alerts" {
  description = "Information about response time alerts"
  value = {
    for region in var.web_app_regions : region => {
      name = azurerm_monitor_metric_alert.response_time[region].name
      id   = azurerm_monitor_metric_alert.response_time[region].id
    }
  }
}

output "availability_alerts" {
  description = "Information about availability alerts"
  value = {
    for region in var.web_app_regions : region => {
      name = azurerm_monitor_metric_alert.availability[region].name
      id   = azurerm_monitor_metric_alert.availability[region].id
    }
  }
}

# Auto-scaling Information
output "autoscale_settings" {
  description = "Information about auto-scaling settings"
  value = var.enable_auto_scaling ? {
    for region in var.web_app_regions : region => {
      name = azurerm_monitor_autoscale_setting.main[region].name
      id   = azurerm_monitor_autoscale_setting.main[region].id
    }
  } : null
}

# Storage Information
output "storage_account" {
  description = "Information about the storage account"
  value = {
    name                     = azurerm_storage_account.function_storage.name
    id                       = azurerm_storage_account.function_storage.id
    primary_blob_endpoint    = azurerm_storage_account.function_storage.primary_blob_endpoint
    primary_access_key       = azurerm_storage_account.function_storage.primary_access_key
  }
  sensitive = true
}

# Role Assignments Information
output "role_assignments" {
  description = "Information about role assignments for the Function App"
  value = {
    traffic_manager_contributor = azurerm_role_assignment.function_traffic_manager.id
    monitoring_reader          = azurerm_role_assignment.function_monitoring.id
    load_test_contributor      = var.enable_load_testing ? azurerm_role_assignment.function_load_test[0].id : null
  }
}

# Deployment Information
output "deployment_info" {
  description = "General deployment information"
  value = {
    environment           = var.environment
    project_name         = var.project_name
    random_suffix        = random_string.suffix.result
    regions_deployed     = var.web_app_regions
    traffic_routing      = var.traffic_manager_routing_method
    application_insights = var.enable_application_insights
    load_testing        = var.enable_load_testing
    auto_scaling        = var.enable_auto_scaling
  }
}

# Connection Information
output "connection_info" {
  description = "Connection information for services"
  value = {
    traffic_manager_url = "https://${azurerm_traffic_manager_profile.main.fqdn}"
    function_app_url    = "https://${azurerm_linux_function_app.main.default_hostname}"
    web_app_urls = {
      for region in var.web_app_regions : region => "https://${azurerm_linux_web_app.main[region].default_hostname}"
    }
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    traffic_manager_status = "az network traffic-manager profile show --name ${azurerm_traffic_manager_profile.main.name} --resource-group ${azurerm_resource_group.main.name}"
    endpoint_health       = "az network traffic-manager endpoint list --profile-name ${azurerm_traffic_manager_profile.main.name} --resource-group ${azurerm_resource_group.main.name} --type azureEndpoints"
    function_app_status   = "az functionapp show --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    load_test_status     = var.enable_load_testing ? "az load test show --name ${azurerm_load_test.main[0].name} --resource-group ${azurerm_resource_group.main.name}" : null
  }
}

# Security Information
output "security_info" {
  description = "Security-related information"
  value = {
    function_app_identity = {
      type         = azurerm_linux_function_app.main.identity[0].type
      principal_id = azurerm_linux_function_app.main.identity[0].principal_id
      tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
    }
    web_app_identities = {
      for region in var.web_app_regions : region => {
        type         = azurerm_linux_web_app.main[region].identity[0].type
        principal_id = azurerm_linux_web_app.main[region].identity[0].principal_id
        tenant_id    = azurerm_linux_web_app.main[region].identity[0].tenant_id
      }
    }
  }
}
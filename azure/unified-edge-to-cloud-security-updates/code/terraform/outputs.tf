# Output values for the IoT Edge-to-Cloud Security Updates infrastructure
# These outputs provide important information for verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# IoT Hub Outputs
output "iot_hub_name" {
  description = "Name of the Azure IoT Hub"
  value       = azurerm_iothub.main.name
}

output "iot_hub_hostname" {
  description = "Hostname of the Azure IoT Hub"
  value       = azurerm_iothub.main.hostname
}

output "iot_hub_connection_string" {
  description = "Connection string for the IoT Hub (sensitive)"
  value       = "HostName=${azurerm_iothub.main.hostname};SharedAccessKeyName=${azurerm_iothub.main.shared_access_policy[0].key_name};SharedAccessKey=${azurerm_iothub.main.shared_access_policy[0].primary_key}"
  sensitive   = true
}

output "iot_hub_resource_id" {
  description = "Resource ID of the IoT Hub"
  value       = azurerm_iothub.main.id
}

# Device Update Outputs
output "device_update_account_name" {
  description = "Name of the Device Update account"
  value       = azurerm_iothub_device_update_account.main.name
}

output "device_update_instance_name" {
  description = "Name of the Device Update instance"
  value       = azurerm_iothub_device_update_instance.main.name
}

output "device_update_account_resource_id" {
  description = "Resource ID of the Device Update account"
  value       = azurerm_iothub_device_update_account.main.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for update artifacts"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Virtual Machine Outputs (conditional)
output "test_vm_name" {
  description = "Name of the test virtual machine (if created)"
  value       = var.enable_test_vm ? azurerm_linux_virtual_machine.test_vm[0].name : null
}

output "test_vm_public_ip" {
  description = "Public IP address of the test VM (if created)"
  value       = var.enable_test_vm ? azurerm_public_ip.test_vm[0].ip_address : null
}

output "test_vm_resource_id" {
  description = "Resource ID of the test virtual machine (if created)"
  value       = var.enable_test_vm ? azurerm_linux_virtual_machine.test_vm[0].id : null
}

# Simulated Device Outputs (conditional)
output "simulated_device_ids" {
  description = "List of simulated device IDs (if created)"
  value       = var.enable_device_simulation ? [for device in azurerm_iothub_device : device.device_id] : []
}

output "simulated_device_connection_strings" {
  description = "Connection strings for simulated devices (sensitive)"
  value = var.enable_device_simulation ? [
    for device in azurerm_iothub_device :
    "HostName=${azurerm_iothub.main.hostname};DeviceId=${device.device_id};SharedAccessKey=${device.primary_key}"
  ] : []
  sensitive = true
}

# Logic App Workflow Outputs
output "logic_app_workflow_name" {
  description = "Name of the update orchestration Logic App workflow"
  value       = azurerm_logic_app_workflow.update_orchestration.name
}

output "logic_app_workflow_endpoint" {
  description = "Trigger endpoint URL for the Logic App workflow"
  value       = azurerm_logic_app_trigger_http_request.update_trigger.callback_url
  sensitive   = true
}

# Monitoring Outputs
output "action_group_name" {
  description = "Name of the action group for alerts (if monitoring enabled)"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "metric_alert_names" {
  description = "Names of the metric alerts (if monitoring enabled)"
  value       = var.enable_monitoring_alerts ? [azurerm_monitor_metric_alert.device_update_failures[0].name] : []
}

# Networking Outputs (conditional)
output "virtual_network_name" {
  description = "Name of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "subnet_name" {
  description = "Name of the subnet (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_subnet.main[0].name : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}

# Cost Management
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    iot_hub_s1            = var.iot_hub_sku == "S1" ? var.iot_hub_capacity * 25.0 : 0
    iot_hub_f1            = var.iot_hub_sku == "F1" ? 0 : 0
    storage_account       = 5.0
    log_analytics         = 10.0
    test_vm               = var.enable_test_vm ? 30.0 : 0
    device_update_account = 0
    logic_app             = 5.0
    total_estimated       = (var.iot_hub_sku == "S1" ? var.iot_hub_capacity * 25.0 : 0) + 5.0 + 10.0 + (var.enable_test_vm ? 30.0 : 0) + 5.0
  }
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_iot_hub = "az iot hub show --name ${azurerm_iothub.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_device_update = "az iot du account show --account ${azurerm_iothub_device_update_account.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_storage = "az storage account show --name ${azurerm_storage_account.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_vm_patches = var.enable_test_vm ? "az vm assess-patches --name ${azurerm_linux_virtual_machine.test_vm[0].name} --resource-group ${azurerm_resource_group.main.name}" : null
    list_devices = var.enable_device_simulation ? "az iot hub device-identity list --hub-name ${azurerm_iothub.main.name}" : null
  }
}
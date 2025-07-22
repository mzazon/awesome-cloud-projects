# Output values for Azure auto-scaling web application infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "load_balancer_public_ip" {
  description = "Public IP address of the load balancer"
  value       = azurerm_public_ip.main.ip_address
}

output "load_balancer_fqdn" {
  description = "Fully qualified domain name of the load balancer"
  value       = azurerm_public_ip.main.fqdn
}

output "web_application_url" {
  description = "URL to access the web application"
  value       = "http://${azurerm_public_ip.main.ip_address}"
}

output "virtual_machine_scale_set_id" {
  description = "ID of the Virtual Machine Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.main.id
}

output "virtual_machine_scale_set_name" {
  description = "Name of the Virtual Machine Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.main.name
}

output "current_instance_count" {
  description = "Current number of instances in the scale set"
  value       = azurerm_linux_virtual_machine_scale_set.main.instances
}

output "auto_scaling_profile_id" {
  description = "ID of the auto-scaling profile"
  value       = azurerm_monitor_autoscale_setting.main.id
}

output "auto_scaling_profile_name" {
  description = "Name of the auto-scaling profile"
  value       = azurerm_monitor_autoscale_setting.main.name
}

output "load_balancer_id" {
  description = "ID of the Azure Load Balancer"
  value       = azurerm_lb.main.id
}

output "load_balancer_name" {
  description = "Name of the Azure Load Balancer"
  value       = azurerm_lb.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = azurerm_subnet.internal.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = azurerm_subnet.internal.name
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.main.id
}

output "network_security_group_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.main.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "ssh_private_key" {
  description = "Private SSH key for VM access (save this securely)"
  value       = tls_private_key.vm_ssh.private_key_pem
  sensitive   = true
}

output "ssh_public_key" {
  description = "Public SSH key for VM access"
  value       = tls_private_key.vm_ssh.public_key_openssh
}

output "admin_username" {
  description = "Administrator username for VM instances"
  value       = var.admin_username
}

output "scaling_configuration" {
  description = "Auto-scaling configuration summary"
  value = {
    min_capacity           = var.vmss_min_capacity
    max_capacity           = var.vmss_max_capacity
    current_capacity       = var.vmss_initial_capacity
    scale_out_threshold    = var.scale_out_cpu_threshold
    scale_in_threshold     = var.scale_in_cpu_threshold
    scale_out_change       = var.scale_out_capacity_change
    scale_in_change        = var.scale_in_capacity_change
    cooldown_duration      = var.cooldown_duration
  }
}

output "health_probe_configuration" {
  description = "Health probe configuration summary"
  value = {
    protocol        = "HTTP"
    port           = 80
    path           = "/"
    interval       = var.health_probe_interval
    threshold      = var.health_probe_threshold
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    location                = var.location
    load_balancer_ip        = azurerm_public_ip.main.ip_address
    vmss_name              = azurerm_linux_virtual_machine_scale_set.main.name
    initial_instance_count  = var.vmss_initial_capacity
    vm_sku                 = var.vm_sku
    application_insights   = var.enable_application_insights
    auto_scaling_alerts    = var.enable_auto_scaling_alerts
  }
}

# Instructions for accessing the deployed infrastructure
output "access_instructions" {
  description = "Instructions for accessing and managing the deployed infrastructure"
  value = <<-EOT
    
    =================================================================
    Azure Auto-Scaling Web Application Deployment Complete!
    =================================================================
    
    🌐 Web Application URL: http://${azurerm_public_ip.main.ip_address}
    
    📊 Management Commands:
    
    # View current scale set instances
    az vmss list-instances --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_virtual_machine_scale_set.main.name} --output table
    
    # Check auto-scaling rules
    az monitor autoscale show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_monitor_autoscale_setting.main.name}
    
    # Monitor CPU usage
    az monitor metrics list --resource ${azurerm_linux_virtual_machine_scale_set.main.id} --metric "Percentage CPU" --interval PT1M
    
    # Scale manually (if needed)
    az vmss scale --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_virtual_machine_scale_set.main.name} --new-capacity 5
    
    🔑 SSH Access:
    Save the private SSH key from the 'ssh_private_key' output to a file and use:
    ssh -i <private_key_file> ${var.admin_username}@<instance_ip>
    
    🔍 Monitoring:
    ${var.enable_application_insights ? "Application Insights: ${azurerm_application_insights.main[0].name}" : "Application Insights: Disabled"}
    ${var.enable_auto_scaling_alerts ? "Auto-scaling alerts: Enabled" : "Auto-scaling alerts: Disabled"}
    
    📈 Load Testing:
    Use tools like Apache Bench or Artillery to generate load and test auto-scaling:
    ab -n 10000 -c 100 http://${azurerm_public_ip.main.ip_address}/
    
    =================================================================
    
  EOT
}
# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all resources"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORKING OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_address_space" {
  description = "Address space of the virtual network"
  value       = azurerm_virtual_network.main.address_space
}

output "ase_subnet_id" {
  description = "ID of the App Service Environment subnet"
  value       = azurerm_subnet.ase.id
}

output "ase_subnet_address_prefix" {
  description = "Address prefix of the App Service Environment subnet"
  value       = azurerm_subnet.ase.address_prefixes[0]
}

output "nat_subnet_id" {
  description = "ID of the NAT Gateway subnet"
  value       = azurerm_subnet.nat.id
}

output "support_subnet_id" {
  description = "ID of the support services subnet"
  value       = azurerm_subnet.support.id
}

output "bastion_subnet_id" {
  description = "ID of the Azure Bastion subnet"
  value       = var.enable_bastion ? azurerm_subnet.bastion[0].id : null
}

# ---------------------------------------------------------------------------------------------------------------------
# NAT GATEWAY OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "nat_gateway_name" {
  description = "Name of the NAT Gateway"
  value       = azurerm_nat_gateway.main.name
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = azurerm_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway for outbound traffic"
  value       = azurerm_public_ip.nat.ip_address
}

output "nat_gateway_public_ip_id" {
  description = "ID of the NAT Gateway public IP"
  value       = azurerm_public_ip.nat.id
}

# ---------------------------------------------------------------------------------------------------------------------
# PRIVATE DNS OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "private_dns_zone_name" {
  description = "Name of the private DNS zone"
  value       = azurerm_private_dns_zone.main.name
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone"
  value       = azurerm_private_dns_zone.main.id
}

output "private_dns_zone_max_number_of_records" {
  description = "Maximum number of records in the private DNS zone"
  value       = azurerm_private_dns_zone.main.max_number_of_records
}

output "webapp_fqdn" {
  description = "Fully qualified domain name for the web application"
  value       = "webapp.${azurerm_private_dns_zone.main.name}"
}

output "api_fqdn" {
  description = "Fully qualified domain name for API services"
  value       = "api.${azurerm_private_dns_zone.main.name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# APP SERVICE ENVIRONMENT OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "app_service_environment_name" {
  description = "Name of the App Service Environment"
  value       = azurerm_app_service_environment_v3.main.name
}

output "app_service_environment_id" {
  description = "ID of the App Service Environment"
  value       = azurerm_app_service_environment_v3.main.id
}

output "app_service_environment_internal_ip" {
  description = "Internal IP address of the App Service Environment"
  value       = azurerm_app_service_environment_v3.main.internal_inbound_ip_addresses[0]
}

output "app_service_environment_external_ip" {
  description = "External IP address of the App Service Environment"
  value       = azurerm_app_service_environment_v3.main.external_inbound_ip_addresses
}

output "app_service_environment_dns_suffix" {
  description = "DNS suffix for the App Service Environment"
  value       = azurerm_app_service_environment_v3.main.dns_suffix
}

output "app_service_environment_zone_redundant" {
  description = "Zone redundancy status of the App Service Environment"
  value       = azurerm_app_service_environment_v3.main.zone_redundant
}

# ---------------------------------------------------------------------------------------------------------------------
# APP SERVICE PLAN OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

output "app_service_plan_worker_count" {
  description = "Number of workers in the App Service Plan"
  value       = azurerm_service_plan.main.worker_count
}

# ---------------------------------------------------------------------------------------------------------------------
# WEB APPLICATION OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "web_app_name" {
  description = "Name of the web application"
  value       = azurerm_windows_web_app.main.name
}

output "web_app_id" {
  description = "ID of the web application"
  value       = azurerm_windows_web_app.main.id
}

output "web_app_default_hostname" {
  description = "Default hostname of the web application"
  value       = azurerm_windows_web_app.main.default_hostname
}

output "web_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the web application"
  value       = azurerm_windows_web_app.main.outbound_ip_addresses
}

output "web_app_possible_outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the web application"
  value       = azurerm_windows_web_app.main.possible_outbound_ip_addresses
}

output "web_app_site_credential" {
  description = "Site credential for the web application"
  value       = azurerm_windows_web_app.main.site_credential
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE BASTION OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "bastion_name" {
  description = "Name of the Azure Bastion host"
  value       = var.enable_bastion ? azurerm_bastion_host.main[0].name : null
}

output "bastion_id" {
  description = "ID of the Azure Bastion host"
  value       = var.enable_bastion ? azurerm_bastion_host.main[0].id : null
}

output "bastion_public_ip" {
  description = "Public IP address of the Azure Bastion host"
  value       = var.enable_bastion ? azurerm_public_ip.bastion[0].ip_address : null
}

output "bastion_fqdn" {
  description = "Fully qualified domain name of the Azure Bastion host"
  value       = var.enable_bastion ? azurerm_public_ip.bastion[0].fqdn : null
}

# ---------------------------------------------------------------------------------------------------------------------
# MANAGEMENT VM OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "management_vm_name" {
  description = "Name of the management virtual machine"
  value       = var.enable_management_vm ? azurerm_windows_virtual_machine.management[0].name : null
}

output "management_vm_id" {
  description = "ID of the management virtual machine"
  value       = var.enable_management_vm ? azurerm_windows_virtual_machine.management[0].id : null
}

output "management_vm_private_ip" {
  description = "Private IP address of the management virtual machine"
  value       = var.enable_management_vm ? azurerm_network_interface.management_vm[0].private_ip_address : null
}

output "management_vm_size" {
  description = "Size of the management virtual machine"
  value       = var.enable_management_vm ? azurerm_windows_virtual_machine.management[0].size : null
}

output "management_vm_admin_username" {
  description = "Admin username for the management virtual machine"
  value       = var.enable_management_vm ? var.management_vm_admin_username : null
}

# ---------------------------------------------------------------------------------------------------------------------
# SECURITY OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "network_security_group_id" {
  description = "ID of the management VM network security group"
  value       = var.enable_management_vm ? azurerm_network_security_group.management_vm[0].id : null
}

# ---------------------------------------------------------------------------------------------------------------------
# COST ESTIMATION OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    app_service_environment = "~$1,000 (base cost for dedicated infrastructure)"
    app_service_plan        = "~$150-400 (based on ${var.app_service_plan_sku} SKU)"
    nat_gateway            = "~$45 (fixed cost plus data processing)"
    bastion                = var.enable_bastion ? "~$140-200 (based on ${var.bastion_sku} SKU)" : "$0"
    management_vm          = var.enable_management_vm ? "~$70-150 (based on ${var.management_vm_size})" : "$0"
    networking             = "~$10-20 (VNet, DNS, public IPs)"
    total_estimated        = "~$1,415-1,815 per month"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOYMENT INFORMATION
# ---------------------------------------------------------------------------------------------------------------------

output "deployment_info" {
  description = "Important deployment information and next steps"
  value = {
    deployment_time     = "App Service Environment deployment takes 60-90 minutes"
    access_method      = var.enable_bastion ? "Use Azure Bastion to connect to management VM" : "Direct network access required"
    webapp_access      = "Web application accessible internally via ${azurerm_private_dns_zone.main.name}"
    outbound_ip        = "All outbound traffic uses static IP: ${azurerm_public_ip.nat.ip_address}"
    dns_resolution     = "Internal DNS resolution for ${azurerm_private_dns_zone.main.name}"
    security_features  = "Complete network isolation, internal load balancer, TLS 1.2 minimum"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# VALIDATION OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_ase_status = "az appservice ase show --name ${azurerm_app_service_environment_v3.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_webapp     = "az webapp show --name ${azurerm_windows_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_dns        = "az network private-dns record-set list --resource-group ${azurerm_resource_group.main.name} --zone-name ${azurerm_private_dns_zone.main.name}"
    check_nat        = "az network nat gateway show --name ${azurerm_nat_gateway.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# TROUBLESHOOTING OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "troubleshooting_info" {
  description = "Troubleshooting information and common issues"
  value = {
    ase_deployment_issues = "ASE deployment can take up to 2 hours. Check Azure Activity Log for progress."
    connectivity_issues   = "Ensure all subnets are properly associated with NSGs and route tables."
    dns_resolution       = "Test DNS resolution from management VM using nslookup webapp.${azurerm_private_dns_zone.main.name}"
    outbound_connectivity = "Verify NAT Gateway association with ASE subnet for outbound traffic."
    bastion_access       = var.enable_bastion ? "Connect to management VM via Azure Bastion in Azure Portal" : "Bastion not enabled"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# RANDOM SUFFIX OUTPUT
# ---------------------------------------------------------------------------------------------------------------------

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}
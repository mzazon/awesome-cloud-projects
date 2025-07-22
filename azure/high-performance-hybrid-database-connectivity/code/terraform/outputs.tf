# Outputs for Azure hybrid database connectivity infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Virtual Network Information
output "virtual_network_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "virtual_network_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "virtual_network_address_space" {
  description = "Address space of the hub virtual network"
  value       = azurerm_virtual_network.hub.address_space
}

# Subnet Information
output "gateway_subnet_id" {
  description = "ID of the Gateway subnet"
  value       = azurerm_subnet.gateway.id
}

output "application_gateway_subnet_id" {
  description = "ID of the Application Gateway subnet"
  value       = azurerm_subnet.application_gateway.id
}

output "database_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "management_subnet_id" {
  description = "ID of the management subnet"
  value       = azurerm_subnet.management.id
}

output "bastion_subnet_id" {
  description = "ID of the Azure Bastion subnet (if enabled)"
  value       = var.enable_bastion ? azurerm_subnet.bastion[0].id : null
}

# ExpressRoute Gateway Information
output "expressroute_gateway_id" {
  description = "ID of the ExpressRoute Gateway"
  value       = azurerm_virtual_network_gateway.expressroute.id
}

output "expressroute_gateway_name" {
  description = "Name of the ExpressRoute Gateway"
  value       = azurerm_virtual_network_gateway.expressroute.name
}

output "expressroute_gateway_public_ip" {
  description = "Public IP address of the ExpressRoute Gateway"
  value       = azurerm_public_ip.expressroute_gateway.ip_address
}

output "expressroute_gateway_fqdn" {
  description = "FQDN of the ExpressRoute Gateway"
  value       = azurerm_public_ip.expressroute_gateway.fqdn
}

output "expressroute_connection_id" {
  description = "ID of the ExpressRoute connection (if configured)"
  value       = var.expressroute_circuit_id != "" ? azurerm_virtual_network_gateway_connection.expressroute[0].id : null
}

output "expressroute_connection_status" {
  description = "Status of the ExpressRoute connection (if configured)"
  value       = var.expressroute_circuit_id != "" ? "Connection configured - check Azure portal for actual status" : "No ExpressRoute circuit provided"
}

# PostgreSQL Information
output "postgresql_server_id" {
  description = "ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "postgresql_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_server_private_fqdn" {
  description = "Private FQDN of the PostgreSQL Flexible Server"
  value       = "${azurerm_postgresql_flexible_server.main.name}.${azurerm_private_dns_zone.postgresql.name}"
}

output "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "postgresql_admin_password" {
  description = "Administrator password for PostgreSQL server"
  value       = var.postgresql_admin_password != null ? "Password provided via variable" : "Auto-generated password - check Terraform state or Azure Key Vault"
  sensitive   = true
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string for applications"
  value       = "postgresql://${azurerm_postgresql_flexible_server.main.administrator_login}:<password>@${azurerm_postgresql_flexible_server.main.fqdn}:5432/postgres?sslmode=require"
  sensitive   = true
}

output "postgresql_private_connection_string" {
  description = "PostgreSQL private connection string for internal applications"
  value       = "postgresql://${azurerm_postgresql_flexible_server.main.administrator_login}:<password>@${azurerm_postgresql_flexible_server.main.name}.${azurerm_private_dns_zone.postgresql.name}:5432/postgres?sslmode=require"
  sensitive   = true
}

# Private DNS Zone Information
output "private_dns_zone_id" {
  description = "ID of the PostgreSQL private DNS zone"
  value       = azurerm_private_dns_zone.postgresql.id
}

output "private_dns_zone_name" {
  description = "Name of the PostgreSQL private DNS zone"
  value       = azurerm_private_dns_zone.postgresql.name
}

# Application Gateway Information
output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.application_gateway.ip_address
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway"
  value       = azurerm_public_ip.application_gateway.fqdn
}

output "application_gateway_backend_pools" {
  description = "Backend address pools configured in Application Gateway"
  value = {
    postgresql_pool = {
      name  = "PostgreSQLBackendPool"
      fqdns = [azurerm_postgresql_flexible_server.main.fqdn]
    }
  }
}

# WAF Policy Information
output "waf_policy_id" {
  description = "ID of the Web Application Firewall policy"
  value       = azurerm_web_application_firewall_policy.main.id
}

output "waf_policy_name" {
  description = "Name of the Web Application Firewall policy"
  value       = azurerm_web_application_firewall_policy.main.name
}

# Security Information
output "database_nsg_id" {
  description = "ID of the database subnet Network Security Group"
  value       = azurerm_network_security_group.database.id
}

output "database_route_table_id" {
  description = "ID of the database subnet route table"
  value       = azurerm_route_table.database.id
}

# Azure Bastion Information (if enabled)
output "bastion_host_id" {
  description = "ID of the Azure Bastion host (if enabled)"
  value       = var.enable_bastion ? azurerm_bastion_host.main[0].id : null
}

output "bastion_host_name" {
  description = "Name of the Azure Bastion host (if enabled)"
  value       = var.enable_bastion ? azurerm_bastion_host.main[0].name : null
}

output "bastion_public_ip" {
  description = "Public IP address of the Azure Bastion (if enabled)"
  value       = var.enable_bastion ? azurerm_public_ip.bastion[0].ip_address : null
}

output "bastion_dns_name" {
  description = "DNS name of the Azure Bastion (if enabled)"
  value       = var.enable_bastion ? azurerm_public_ip.bastion[0].fqdn : null
}

# Monitoring Information
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for the Log Analytics Workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# DDoS Protection Information
output "ddos_protection_plan_id" {
  description = "ID of the DDoS Protection Plan (if enabled)"
  value       = var.enable_ddos_protection ? azurerm_network_ddos_protection_plan.main[0].id : null
}

# Random Suffix for Unique Naming
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    resource_group          = azurerm_resource_group.main.name
    location               = azurerm_resource_group.main.location
    virtual_network        = azurerm_virtual_network.hub.name
    expressroute_gateway   = azurerm_virtual_network_gateway.expressroute.name
    postgresql_server      = azurerm_postgresql_flexible_server.main.name
    application_gateway    = azurerm_application_gateway.main.name
    bastion_enabled        = var.enable_bastion
    ddos_protection_enabled = var.enable_ddos_protection
    diagnostic_logs_enabled = var.enable_diagnostic_logs
    expressroute_connected = var.expressroute_circuit_id != "" ? true : false
  }
}

# Connection Information for Applications
output "application_connection_endpoints" {
  description = "Connection endpoints for applications"
  value = {
    application_gateway_https = "https://${azurerm_public_ip.application_gateway.ip_address}"
    application_gateway_fqdn  = azurerm_public_ip.application_gateway.fqdn != null ? "https://${azurerm_public_ip.application_gateway.fqdn}" : null
    postgresql_direct         = azurerm_postgresql_flexible_server.main.fqdn
    postgresql_private        = "${azurerm_postgresql_flexible_server.main.name}.${azurerm_private_dns_zone.postgresql.name}"
  }
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = var.common_tags
}

# Validation Information
output "validation_checks" {
  description = "Commands to validate the deployment"
  value = {
    check_expressroute_gateway = "az network vnet-gateway show --name ${azurerm_virtual_network_gateway.expressroute.name} --resource-group ${azurerm_resource_group.main.name} --query 'provisioningState'"
    check_postgresql_status    = "az postgres flexible-server show --name ${azurerm_postgresql_flexible_server.main.name} --resource-group ${azurerm_resource_group.main.name} --query 'state'"
    check_application_gateway  = "az network application-gateway show --name ${azurerm_application_gateway.main.name} --resource-group ${azurerm_resource_group.main.name} --query 'operationalState'"
    test_connectivity         = "Use Azure Bastion or jump box in management subnet to test database connectivity"
  }
}
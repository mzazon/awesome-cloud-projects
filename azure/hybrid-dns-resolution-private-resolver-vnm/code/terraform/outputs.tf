# Outputs for Azure Hybrid DNS Resolution Infrastructure
# This file defines output values for monitoring and integration purposes

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Virtual Network Information
output "hub_virtual_network_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "hub_virtual_network_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "hub_virtual_network_address_space" {
  description = "Address space of the hub virtual network"
  value       = azurerm_virtual_network.hub.address_space
}

output "spoke1_virtual_network_id" {
  description = "ID of the first spoke virtual network"
  value       = azurerm_virtual_network.spoke1.id
}

output "spoke1_virtual_network_name" {
  description = "Name of the first spoke virtual network"
  value       = azurerm_virtual_network.spoke1.name
}

output "spoke2_virtual_network_id" {
  description = "ID of the second spoke virtual network"
  value       = azurerm_virtual_network.spoke2.id
}

output "spoke2_virtual_network_name" {
  description = "Name of the second spoke virtual network"
  value       = azurerm_virtual_network.spoke2.name
}

# DNS Private Resolver Information
output "dns_private_resolver_id" {
  description = "ID of the DNS Private Resolver"
  value       = azurerm_private_dns_resolver.main.id
}

output "dns_private_resolver_name" {
  description = "Name of the DNS Private Resolver"
  value       = azurerm_private_dns_resolver.main.name
}

output "dns_inbound_endpoint_id" {
  description = "ID of the DNS Private Resolver inbound endpoint"
  value       = azurerm_private_dns_resolver_inbound_endpoint.main.id
}

output "dns_inbound_endpoint_ip" {
  description = "IP address of the DNS Private Resolver inbound endpoint"
  value       = azurerm_private_dns_resolver_inbound_endpoint.main.ip_configurations[0].private_ip_address
  sensitive   = false
}

output "dns_outbound_endpoint_id" {
  description = "ID of the DNS Private Resolver outbound endpoint"
  value       = azurerm_private_dns_resolver_outbound_endpoint.main.id
}

output "dns_forwarding_ruleset_id" {
  description = "ID of the DNS forwarding ruleset"
  value       = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
}

output "dns_forwarding_ruleset_name" {
  description = "Name of the DNS forwarding ruleset"
  value       = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.name
}

# Private DNS Zone Information
output "private_dns_zone_id" {
  description = "ID of the private DNS zone"
  value       = azurerm_private_dns_zone.main.id
}

output "private_dns_zone_name" {
  description = "Name of the private DNS zone"
  value       = azurerm_private_dns_zone.main.name
}

output "storage_private_dns_zone_id" {
  description = "ID of the storage account private DNS zone"
  value       = azurerm_private_dns_zone.storage_blob.id
}

output "storage_private_dns_zone_name" {
  description = "Name of the storage account private DNS zone"
  value       = azurerm_private_dns_zone.storage_blob.name
}

# Azure Virtual Network Manager Information
output "network_manager_id" {
  description = "ID of the Azure Virtual Network Manager"
  value       = azurerm_network_manager.main.id
}

output "network_manager_name" {
  description = "Name of the Azure Virtual Network Manager"
  value       = azurerm_network_manager.main.name
}

output "network_group_id" {
  description = "ID of the network manager network group"
  value       = azurerm_network_manager_network_group.hub_spoke.id
}

output "connectivity_configuration_id" {
  description = "ID of the network manager connectivity configuration"
  value       = azurerm_network_manager_connectivity_configuration.hub_spoke.id
}

# Storage Account Information
output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_private_endpoint_id" {
  description = "ID of the storage account private endpoint"
  value       = azurerm_private_endpoint.storage.id
}

output "storage_private_endpoint_fqdn" {
  description = "FQDN of the storage account private endpoint"
  value       = azurerm_private_endpoint.storage.custom_dns_configs[0].fqdn
}

output "storage_private_endpoint_ip" {
  description = "Private IP address of the storage account private endpoint"
  value       = azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address
}

# Test VM Information (conditional outputs)
output "test_vm_id" {
  description = "ID of the test virtual machine (if created)"
  value       = var.create_test_vm ? azurerm_linux_virtual_machine.test_vm[0].id : null
}

output "test_vm_name" {
  description = "Name of the test virtual machine (if created)"
  value       = var.create_test_vm ? azurerm_linux_virtual_machine.test_vm[0].name : null
}

output "test_vm_private_ip" {
  description = "Private IP address of the test virtual machine (if created)"
  value       = var.create_test_vm ? azurerm_network_interface.test_vm[0].private_ip_address : null
}

output "test_vm_ssh_private_key" {
  description = "SSH private key for the test virtual machine (if created)"
  value       = var.create_test_vm ? tls_private_key.test_vm[0].private_key_pem : null
  sensitive   = true
}

output "test_vm_public_key" {
  description = "SSH public key for the test virtual machine (if created)"
  value       = var.create_test_vm ? tls_private_key.test_vm[0].public_key_openssh : null
}

# DNS Testing Information
output "test_dns_records" {
  description = "List of test DNS records created in the private DNS zone"
  value = {
    test_vm = {
      name    = azurerm_private_dns_a_record.test_vm.name
      fqdn    = "${azurerm_private_dns_a_record.test_vm.name}.${azurerm_private_dns_zone.main.name}"
      ip      = azurerm_private_dns_a_record.test_vm.records[0]
    }
    app_server = {
      name    = azurerm_private_dns_a_record.app_server.name
      fqdn    = "${azurerm_private_dns_a_record.app_server.name}.${azurerm_private_dns_zone.main.name}"
      ip      = azurerm_private_dns_a_record.app_server.records[0]
    }
  }
}

# Configuration Information for External Systems
output "onprem_dns_configuration" {
  description = "Configuration information for on-premises DNS setup"
  value = {
    inbound_endpoint_ip = azurerm_private_dns_resolver_inbound_endpoint.main.ip_configurations[0].private_ip_address
    azure_dns_zone     = azurerm_private_dns_zone.main.name
    forwarding_domain  = var.onprem_domain_name
    onprem_dns_servers = var.onprem_dns_servers
  }
}

# Subnet Information
output "dns_inbound_subnet_id" {
  description = "ID of the DNS inbound subnet"
  value       = azurerm_subnet.dns_inbound.id
}

output "dns_outbound_subnet_id" {
  description = "ID of the DNS outbound subnet"
  value       = azurerm_subnet.dns_outbound.id
}

output "spoke1_subnet_id" {
  description = "ID of the first spoke subnet"
  value       = azurerm_subnet.spoke1_default.id
}

output "spoke2_subnet_id" {
  description = "ID of the second spoke subnet"
  value       = azurerm_subnet.spoke2_default.id
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed hybrid DNS solution"
  value = {
    resource_group      = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    dns_resolver_name  = azurerm_private_dns_resolver.main.name
    network_manager    = azurerm_network_manager.main.name
    hub_vnet           = azurerm_virtual_network.hub.name
    spoke_vnets        = [azurerm_virtual_network.spoke1.name, azurerm_virtual_network.spoke2.name]
    private_dns_zones  = [azurerm_private_dns_zone.main.name, azurerm_private_dns_zone.storage_blob.name]
    storage_account    = azurerm_storage_account.main.name
    test_vm_created    = var.create_test_vm
    random_suffix      = random_string.suffix.result
  }
}

# Connection Strings and Commands for Testing
output "dns_testing_commands" {
  description = "Commands for testing DNS resolution"
  value = {
    test_azure_records = [
      "nslookup test-vm.${azurerm_private_dns_zone.main.name}",
      "nslookup app-server.${azurerm_private_dns_zone.main.name}",
      "nslookup ${azurerm_storage_account.main.name}.blob.core.windows.net"
    ]
    test_onprem_records = [
      "nslookup server.${var.onprem_domain_name}",
      "nslookup workstation.${var.onprem_domain_name}"
    ]
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the deployed resources (USD)"
  value = {
    dns_private_resolver = "~$30-40"
    virtual_network_manager = "~$10-15"
    storage_account = "~$5-10"
    test_vm = var.create_test_vm ? "~$15-25" : "$0"
    networking = "~$5-10"
    total_estimated = var.create_test_vm ? "~$65-100" : "~$50-75"
    note = "Costs may vary based on usage, region, and current Azure pricing"
  }
}
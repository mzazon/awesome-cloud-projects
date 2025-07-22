# ============================================================================
# RESOURCE GROUP AND GENERAL OUTPUTS
# ============================================================================

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# NETWORK INFRASTRUCTURE OUTPUTS
# ============================================================================

output "hub_virtual_network" {
  description = "Hub virtual network information"
  value = {
    id            = azurerm_virtual_network.hub.id
    name          = azurerm_virtual_network.hub.name
    address_space = azurerm_virtual_network.hub.address_space
  }
}

output "spoke_virtual_network" {
  description = "Spoke virtual network information"
  value = {
    id            = azurerm_virtual_network.spoke.id
    name          = azurerm_virtual_network.spoke.name
    address_space = azurerm_virtual_network.spoke.address_space
  }
}

output "gateway_subnet" {
  description = "Gateway subnet information"
  value = {
    id               = azurerm_subnet.gateway.id
    name             = azurerm_subnet.gateway.name
    address_prefixes = azurerm_subnet.gateway.address_prefixes
  }
}

output "application_subnet" {
  description = "Application subnet information"
  value = {
    id               = azurerm_subnet.application.id
    name             = azurerm_subnet.application.name
    address_prefixes = azurerm_subnet.application.address_prefixes
  }
}

output "private_endpoint_subnet" {
  description = "Private endpoint subnet information"
  value = {
    id               = azurerm_subnet.private_endpoint.id
    name             = azurerm_subnet.private_endpoint.name
    address_prefixes = azurerm_subnet.private_endpoint.address_prefixes
  }
}

# ============================================================================
# VPN GATEWAY OUTPUTS
# ============================================================================

output "vpn_gateway" {
  description = "VPN Gateway information for on-premises configuration"
  value = {
    id                = azurerm_virtual_network_gateway.vpn.id
    name              = azurerm_virtual_network_gateway.vpn.name
    public_ip_address = azurerm_public_ip.vpn_gateway.ip_address
    sku               = azurerm_virtual_network_gateway.vpn.sku
    vpn_type          = azurerm_virtual_network_gateway.vpn.vpn_type
    bgp_enabled       = azurerm_virtual_network_gateway.vpn.enable_bgp
  }
  sensitive = false
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway for on-premises configuration"
  value       = azurerm_public_ip.vpn_gateway.ip_address
}

output "local_network_gateway" {
  description = "Local network gateway information (if created)"
  value = var.create_local_network_gateway ? {
    id              = azurerm_local_network_gateway.onpremises[0].id
    name            = azurerm_local_network_gateway.onpremises[0].name
    gateway_address = azurerm_local_network_gateway.onpremises[0].gateway_address
    address_space   = azurerm_local_network_gateway.onpremises[0].address_space
  } : null
}

# ============================================================================
# AZURE KEY VAULT OUTPUTS
# ============================================================================

output "key_vault" {
  description = "Key Vault information"
  value = {
    id                = azurerm_key_vault.main.id
    name              = azurerm_key_vault.main.name
    vault_uri         = azurerm_key_vault.main.vault_uri
    sku_name          = azurerm_key_vault.main.sku_name
    rbac_enabled      = azurerm_key_vault.main.enable_rbac_authorization
    purge_protection  = azurerm_key_vault.main.purge_protection_enabled
  }
}

output "key_vault_uri" {
  description = "URI of the Key Vault for application configuration"
  value       = azurerm_key_vault.main.vault_uri
}

output "test_secret_name" {
  description = "Name of the test secret created in Key Vault"
  value       = azurerm_key_vault_secret.test_secret.name
}

# ============================================================================
# STORAGE ACCOUNT OUTPUTS
# ============================================================================

output "storage_account" {
  description = "Storage account information"
  value = {
    id                     = azurerm_storage_account.main.id
    name                   = azurerm_storage_account.main.name
    primary_blob_endpoint  = azurerm_storage_account.main.primary_blob_endpoint
    account_tier           = azurerm_storage_account.main.account_tier
    replication_type       = azurerm_storage_account.main.account_replication_type
    public_access_enabled  = azurerm_storage_account.main.public_network_access_enabled
  }
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# ============================================================================
# PRIVATE DNS ZONE OUTPUTS
# ============================================================================

output "private_dns_zones" {
  description = "Private DNS zones information"
  value = var.enable_private_dns_zones ? {
    key_vault = {
      id   = azurerm_private_dns_zone.keyvault[0].id
      name = azurerm_private_dns_zone.keyvault[0].name
    }
    storage_blob = {
      id   = azurerm_private_dns_zone.storage_blob[0].id
      name = azurerm_private_dns_zone.storage_blob[0].name
    }
  } : null
}

# ============================================================================
# PRIVATE ENDPOINT OUTPUTS
# ============================================================================

output "private_endpoints" {
  description = "Private endpoints information"
  value = {
    key_vault = {
      id                = azurerm_private_endpoint.keyvault.id
      name              = azurerm_private_endpoint.keyvault.name
      private_ip_address = azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address
      fqdn              = azurerm_private_endpoint.keyvault.custom_dns_configs[0].fqdn
    }
    storage_blob = {
      id                = azurerm_private_endpoint.storage_blob.id
      name              = azurerm_private_endpoint.storage_blob.name
      private_ip_address = azurerm_private_endpoint.storage_blob.private_service_connection[0].private_ip_address
      fqdn              = azurerm_private_endpoint.storage_blob.custom_dns_configs[0].fqdn
    }
  }
}

# ============================================================================
# TEST VM OUTPUTS (CONDITIONAL)
# ============================================================================

output "test_vm" {
  description = "Test virtual machine information (if created)"
  value = var.enable_test_vm ? {
    id                 = azurerm_linux_virtual_machine.test[0].id
    name               = azurerm_linux_virtual_machine.test[0].name
    private_ip_address = azurerm_network_interface.vm[0].private_ip_address
    admin_username     = azurerm_linux_virtual_machine.test[0].admin_username
    managed_identity_principal_id = azurerm_linux_virtual_machine.test[0].identity[0].principal_id
  } : null
}

output "vm_ssh_private_key" {
  description = "Private SSH key for VM access (keep secure)"
  value       = var.enable_test_vm ? tls_private_key.vm_ssh[0].private_key_pem : null
  sensitive   = true
}

output "vm_ssh_connection_command" {
  description = "SSH command to connect to the test VM"
  value = var.enable_test_vm ? "ssh -i vm_private_key.pem ${var.vm_admin_username}@${azurerm_network_interface.vm[0].private_ip_address}" : null
}

# ============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ============================================================================

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    key_vault_rbac_enabled        = azurerm_key_vault.main.enable_rbac_authorization
    key_vault_purge_protection    = azurerm_key_vault.main.purge_protection_enabled
    storage_public_access_disabled = !azurerm_storage_account.main.public_network_access_enabled
    vm_password_auth_disabled     = var.enable_test_vm ? azurerm_linux_virtual_machine.test[0].disable_password_authentication : null
    private_endpoints_enabled     = true
    private_dns_zones_enabled     = var.enable_private_dns_zones
  }
}

# ============================================================================
# DEPLOYMENT VALIDATION OUTPUTS
# ============================================================================

output "deployment_validation" {
  description = "Information for validating the deployment"
  value = {
    vpn_gateway_provisioning_state = azurerm_virtual_network_gateway.vpn.id != null ? "Check Azure portal for current state" : "Not deployed"
    private_endpoints_count        = 2
    dns_zones_configured          = var.enable_private_dns_zones
    test_vm_deployed              = var.enable_test_vm
    
    validation_steps = [
      "1. Verify VPN Gateway is in 'Succeeded' provisioning state",
      "2. Test private endpoint DNS resolution from test VM",
      "3. Validate Key Vault access through private endpoint",
      "4. Confirm storage account access through private endpoint",
      "5. Check VNet peering status between hub and spoke"
    ]
  }
}

# ============================================================================
# NETWORK TOPOLOGY OUTPUTS
# ============================================================================

output "network_topology" {
  description = "Network topology summary for architecture documentation"
  value = {
    hub_vnet = {
      name          = azurerm_virtual_network.hub.name
      address_space = azurerm_virtual_network.hub.address_space
      subnets = {
        gateway = azurerm_subnet.gateway.address_prefixes
      }
    }
    spoke_vnet = {
      name          = azurerm_virtual_network.spoke.name
      address_space = azurerm_virtual_network.spoke.address_space
      subnets = {
        application       = azurerm_subnet.application.address_prefixes
        private_endpoints = azurerm_subnet.private_endpoint.address_prefixes
      }
    }
    connectivity = {
      vnet_peering_configured = true
      vpn_gateway_deployed    = true
      private_endpoints_count = 2
    }
  }
}

# ============================================================================
# COST OPTIMIZATION OUTPUTS
# ============================================================================

output "cost_optimization_info" {
  description = "Cost optimization information and recommendations"
  value = {
    vpn_gateway_sku = azurerm_virtual_network_gateway.vpn.sku
    storage_tier    = azurerm_storage_account.main.account_tier
    vm_size         = var.enable_test_vm ? azurerm_linux_virtual_machine.test[0].size : "N/A"
    
    cost_optimization_tips = [
      "Consider using VPN Gateway Basic SKU for development/testing",
      "Use Standard storage tier for non-critical workloads",
      "Implement lifecycle policies for storage account",
      "Monitor and optimize VM sizes based on actual usage",
      "Use Azure Reservations for production VPN Gateways"
    ]
  }
}

# ============================================================================
# TERRAFORM STATE OUTPUTS
# ============================================================================

output "terraform_state_info" {
  description = "Terraform state and management information"
  value = {
    resource_count     = "Check 'terraform show' for complete resource inventory"
    provider_versions  = "Check 'terraform version' for current provider versions"
    state_file_warning = "Keep terraform.tfstate secure - contains sensitive information"
  }
}
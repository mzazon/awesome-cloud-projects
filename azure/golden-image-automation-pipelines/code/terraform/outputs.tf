# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Network Configuration
output "hub_virtual_network_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "hub_virtual_network_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "build_virtual_network_id" {
  description = "ID of the build virtual network"
  value       = azurerm_virtual_network.build.id
}

output "build_virtual_network_name" {
  description = "Name of the build virtual network"
  value       = azurerm_virtual_network.build.name
}

output "build_subnet_id" {
  description = "ID of the build subnet"
  value       = azurerm_subnet.build.id
}

output "build_subnet_name" {
  description = "Name of the build subnet"
  value       = azurerm_subnet.build.name
}

# DNS Resolver Configuration
output "private_dns_resolver_id" {
  description = "ID of the Azure Private DNS Resolver"
  value       = azurerm_private_dns_resolver.main.id
}

output "private_dns_resolver_name" {
  description = "Name of the Azure Private DNS Resolver"
  value       = azurerm_private_dns_resolver.main.name
}

output "dns_resolver_inbound_endpoint_id" {
  description = "ID of the DNS resolver inbound endpoint"
  value       = azurerm_private_dns_resolver_inbound_endpoint.main.id
}

output "dns_resolver_inbound_endpoint_ip" {
  description = "IP address of the DNS resolver inbound endpoint"
  value       = azurerm_private_dns_resolver_inbound_endpoint.main.ip_configurations[0].private_ip_address
}

output "dns_resolver_outbound_endpoint_id" {
  description = "ID of the DNS resolver outbound endpoint"
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

# Azure Compute Gallery Configuration
output "compute_gallery_id" {
  description = "ID of the Azure Compute Gallery"
  value       = azurerm_shared_image_gallery.main.id
}

output "compute_gallery_name" {
  description = "Name of the Azure Compute Gallery"
  value       = azurerm_shared_image_gallery.main.name
}

output "compute_gallery_unique_name" {
  description = "Unique name of the Azure Compute Gallery"
  value       = azurerm_shared_image_gallery.main.unique_name
}

output "gallery_image_definition_id" {
  description = "ID of the gallery image definition"
  value       = azurerm_shared_image.ubuntu_hardened.id
}

output "gallery_image_definition_name" {
  description = "Name of the gallery image definition"
  value       = azurerm_shared_image.ubuntu_hardened.name
}

# Managed Identity Configuration
output "image_builder_identity_id" {
  description = "ID of the VM Image Builder managed identity"
  value       = azurerm_user_assigned_identity.image_builder.id
}

output "image_builder_identity_name" {
  description = "Name of the VM Image Builder managed identity"
  value       = azurerm_user_assigned_identity.image_builder.name
}

output "image_builder_identity_principal_id" {
  description = "Principal ID of the VM Image Builder managed identity"
  value       = azurerm_user_assigned_identity.image_builder.principal_id
}

output "image_builder_identity_client_id" {
  description = "Client ID of the VM Image Builder managed identity"
  value       = azurerm_user_assigned_identity.image_builder.client_id
}

# Custom Role Configuration
output "image_builder_gallery_role_id" {
  description = "ID of the custom gallery role for VM Image Builder"
  value       = azurerm_role_definition.image_builder_gallery.role_definition_resource_id
}

output "image_builder_gallery_role_name" {
  description = "Name of the custom gallery role for VM Image Builder"
  value       = azurerm_role_definition.image_builder_gallery.name
}

# Image Template Configuration
output "image_template_name" {
  description = "Name of the VM Image Builder template"
  value       = "template-ubuntu-${random_string.suffix.result}"
}

output "image_template_file_path" {
  description = "Path to the generated image template JSON file"
  value       = local_file.image_template.filename
}

# DevOps Pipeline Configuration
output "azure_pipelines_file_path" {
  description = "Path to the generated Azure DevOps pipeline YAML file"
  value       = local_file.azure_pipelines.filename
}

# Network Configuration Details
output "network_configuration" {
  description = "Network configuration details for the golden image pipeline"
  value = {
    hub_vnet = {
      name          = azurerm_virtual_network.hub.name
      address_space = azurerm_virtual_network.hub.address_space
    }
    build_vnet = {
      name          = azurerm_virtual_network.build.name
      address_space = azurerm_virtual_network.build.address_space
    }
    subnets = {
      resolver_inbound = {
        name             = azurerm_subnet.resolver_inbound.name
        address_prefixes = azurerm_subnet.resolver_inbound.address_prefixes
      }
      resolver_outbound = {
        name             = azurerm_subnet.resolver_outbound.name
        address_prefixes = azurerm_subnet.resolver_outbound.address_prefixes
      }
      build = {
        name             = azurerm_subnet.build.name
        address_prefixes = azurerm_subnet.build.address_prefixes
      }
    }
    peering = {
      build_to_hub = azurerm_virtual_network_peering.build_to_hub.name
      hub_to_build = azurerm_virtual_network_peering.hub_to_build.name
    }
  }
}

# DNS Configuration Details
output "dns_configuration" {
  description = "DNS configuration details for hybrid resolution"
  value = {
    resolver = {
      name = azurerm_private_dns_resolver.main.name
      id   = azurerm_private_dns_resolver.main.id
    }
    endpoints = {
      inbound = {
        name = azurerm_private_dns_resolver_inbound_endpoint.main.name
        ip   = azurerm_private_dns_resolver_inbound_endpoint.main.ip_configurations[0].private_ip_address
      }
      outbound = {
        name = azurerm_private_dns_resolver_outbound_endpoint.main.name
        id   = azurerm_private_dns_resolver_outbound_endpoint.main.id
      }
    }
    forwarding = {
      ruleset_name = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.name
      ruleset_id   = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
    }
  }
}

# Image Builder Configuration Details
output "image_builder_configuration" {
  description = "VM Image Builder configuration details"
  value = {
    identity = {
      name         = azurerm_user_assigned_identity.image_builder.name
      principal_id = azurerm_user_assigned_identity.image_builder.principal_id
      client_id    = azurerm_user_assigned_identity.image_builder.client_id
    }
    gallery = {
      name       = azurerm_shared_image_gallery.main.name
      unique_name = azurerm_shared_image_gallery.main.unique_name
    }
    image_definition = {
      name = azurerm_shared_image.ubuntu_hardened.name
      id   = azurerm_shared_image.ubuntu_hardened.id
    }
    template_name = "template-ubuntu-${random_string.suffix.result}"
    build_settings = {
      timeout_minutes = var.vm_image_builder_build_timeout
      vm_size        = var.vm_image_builder_vm_size
      os_disk_size   = var.vm_image_builder_os_disk_size
    }
  }
}

# CLI Commands for Manual Operations
output "cli_commands" {
  description = "Useful CLI commands for managing the golden image pipeline"
  value = {
    deploy_image_template = "az deployment group create --resource-group ${azurerm_resource_group.main.name} --template-file image-template.json --parameters imageTemplateName=template-ubuntu-${random_string.suffix.result}"
    start_image_build    = "az image builder run --name template-ubuntu-${random_string.suffix.result} --resource-group ${azurerm_resource_group.main.name}"
    check_build_status   = "az image builder show --name template-ubuntu-${random_string.suffix.result} --resource-group ${azurerm_resource_group.main.name} --query properties.lastRunStatus.runState --output tsv"
    list_gallery_images  = "az sig image-version list --gallery-name ${azurerm_shared_image_gallery.main.name} --gallery-image-definition ${azurerm_shared_image.ubuntu_hardened.name} --resource-group ${azurerm_resource_group.main.name}"
    test_dns_resolution  = "nslookup <domain> ${azurerm_private_dns_resolver_inbound_endpoint.main.ip_configurations[0].private_ip_address}"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    resource_group    = azurerm_resource_group.main.name
    location         = azurerm_resource_group.main.location
    random_suffix    = random_string.suffix.result
    virtual_networks = {
      hub   = azurerm_virtual_network.hub.name
      build = azurerm_virtual_network.build.name
    }
    dns_resolver     = azurerm_private_dns_resolver.main.name
    compute_gallery  = azurerm_shared_image_gallery.main.name
    managed_identity = azurerm_user_assigned_identity.image_builder.name
    created_at       = timestamp()
  }
}
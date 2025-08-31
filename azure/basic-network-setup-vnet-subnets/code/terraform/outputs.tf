# Output values for the Basic Network Setup Terraform configuration
# These outputs provide essential information for verification, integration, and troubleshooting

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Azure resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Azure region where the resource group was created"
  value       = azurerm_resource_group.main.location
}

# Virtual Network Information
output "virtual_network_name" {
  description = "Name of the created virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "Azure resource ID of the created virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_address_space" {
  description = "Address space(s) of the virtual network"
  value       = azurerm_virtual_network.main.address_space
}

# Frontend Subnet Information
output "frontend_subnet_name" {
  description = "Name of the frontend subnet"
  value       = azurerm_subnet.frontend.name
}

output "frontend_subnet_id" {
  description = "Azure resource ID of the frontend subnet"
  value       = azurerm_subnet.frontend.id
}

output "frontend_subnet_address_prefix" {
  description = "Address prefix of the frontend subnet"
  value       = azurerm_subnet.frontend.address_prefixes[0]
}

# Backend Subnet Information
output "backend_subnet_name" {
  description = "Name of the backend subnet"
  value       = azurerm_subnet.backend.name
}

output "backend_subnet_id" {
  description = "Azure resource ID of the backend subnet"
  value       = azurerm_subnet.backend.id
}

output "backend_subnet_address_prefix" {
  description = "Address prefix of the backend subnet"
  value       = azurerm_subnet.backend.address_prefixes[0]
}

# Database Subnet Information
output "database_subnet_name" {
  description = "Name of the database subnet"
  value       = azurerm_subnet.database.name
}

output "database_subnet_id" {
  description = "Azure resource ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "database_subnet_address_prefix" {
  description = "Address prefix of the database subnet"
  value       = azurerm_subnet.database.address_prefixes[0]
}

# Network Security Group Information
output "frontend_nsg_name" {
  description = "Name of the frontend network security group"
  value       = azurerm_network_security_group.frontend.name
}

output "frontend_nsg_id" {
  description = "Azure resource ID of the frontend network security group"
  value       = azurerm_network_security_group.frontend.id
}

output "backend_nsg_name" {
  description = "Name of the backend network security group"
  value       = azurerm_network_security_group.backend.name
}

output "backend_nsg_id" {
  description = "Azure resource ID of the backend network security group"
  value       = azurerm_network_security_group.backend.id
}

output "database_nsg_name" {
  description = "Name of the database network security group"
  value       = azurerm_network_security_group.database.name
}

output "database_nsg_id" {
  description = "Azure resource ID of the database network security group"
  value       = azurerm_network_security_group.database.id
}

# Network Architecture Summary - Useful for documentation and integration
output "network_architecture_summary" {
  description = "Summary of the created network architecture"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    virtual_network = {
      name          = azurerm_virtual_network.main.name
      address_space = azurerm_virtual_network.main.address_space
    }
    subnets = {
      frontend = {
        name           = azurerm_subnet.frontend.name
        address_prefix = azurerm_subnet.frontend.address_prefixes[0]
        nsg_name      = azurerm_network_security_group.frontend.name
      }
      backend = {
        name           = azurerm_subnet.backend.name
        address_prefix = azurerm_subnet.backend.address_prefixes[0]
        nsg_name      = azurerm_network_security_group.backend.name
      }
      database = {
        name           = azurerm_subnet.database.name
        address_prefix = azurerm_subnet.database.address_prefixes[0]
        nsg_name      = azurerm_network_security_group.database.name
      }
    }
  }
}

# Security Configuration Summary
output "security_configuration" {
  description = "Summary of network security group configurations"
  value = {
    frontend_allowed_ports    = var.frontend_allowed_ports
    backend_application_port = var.backend_application_port
    database_port           = var.database_port
    security_rules = {
      frontend_to_internet = "Allow HTTP/HTTPS from Internet"
      frontend_to_backend  = "Allow application traffic from frontend to backend"
      backend_to_database  = "Allow database traffic from backend to database"
    }
  }
}

# Connection Information for Application Deployment
output "deployment_guidance" {
  description = "Guidance for deploying resources to the created subnets"
  value = {
    frontend = {
      subnet_id   = azurerm_subnet.frontend.id
      description = "Deploy load balancers, web servers, and public-facing resources here"
      security    = "Allows inbound HTTP/HTTPS traffic from Internet"
    }
    backend = {
      subnet_id   = azurerm_subnet.backend.id
      description = "Deploy application servers, APIs, and business logic here"
      security    = "Allows inbound traffic only from frontend subnet on configured port"
    }
    database = {
      subnet_id   = azurerm_subnet.database.id
      description = "Deploy databases and data stores here"
      security    = "Allows inbound traffic only from backend subnet on database port"
    }
  }
}

# Random suffix used for unique naming (useful for integration with other resources)
output "random_suffix" {
  description = "Random suffix used for resource naming (if enabled)"
  value       = var.use_random_suffix ? random_hex.suffix.result : "disabled"
}
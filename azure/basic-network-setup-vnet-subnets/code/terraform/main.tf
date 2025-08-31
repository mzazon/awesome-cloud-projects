# Azure Basic Network Setup with Virtual Network and Subnets
# This configuration creates a three-tier network architecture with proper security controls
# following Azure Well-Architected Framework networking best practices

# Generate random suffix for unique resource naming
resource "random_hex" "suffix" {
  length = 3
}

# Local values for consistent resource naming and tagging
locals {
  # Generate unique names with optional random suffix
  resource_group_name = var.use_random_suffix && var.resource_group_name == "" ? "rg-basic-network-${random_hex.suffix.result}" : (var.resource_group_name != "" ? var.resource_group_name : "rg-basic-network")
  vnet_name          = var.use_random_suffix && var.virtual_network_name == "" ? "vnet-basic-network-${random_hex.suffix.result}" : (var.virtual_network_name != "" ? var.virtual_network_name : "vnet-basic-network")

  # Common tags applied to all resources for consistent resource management
  common_tags = merge(var.tags, {
    environment         = var.environment
    managed_by         = "terraform"
    recipe_id          = "a3f2b8e1"
    recipe_name        = "basic-network-setup-vnet-subnets"
    creation_date      = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group - Container for all networking resources
# Resource groups provide lifecycle management and access control boundaries
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location

  tags = merge(local.common_tags, {
    resource_type = "resource-group"
    description   = "Resource group for basic network setup demonstration"
  })
}

# Virtual Network - Primary network container providing isolation and segmentation
# VNets create private network spaces within Azure with automatic routing between subnets
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.virtual_network_address_space

  tags = merge(local.common_tags, {
    resource_type = "virtual-network"
    description   = "Main virtual network for three-tier application architecture"
    address_space = join(",", var.virtual_network_address_space)
  })
}

# Frontend Subnet - Public-facing resources like load balancers and web servers
# This subnet typically allows inbound internet traffic through controlled entry points
resource "azurerm_subnet" "frontend" {
  name                 = var.frontend_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.frontend_subnet_address_prefix]

  # Delegate subnet management to the virtual network to ensure proper routing
  depends_on = [azurerm_virtual_network.main]
}

# Backend Subnet - Application servers and middleware components
# This subnet should not have direct internet access, only receiving traffic from frontend
resource "azurerm_subnet" "backend" {
  name                 = var.backend_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.backend_subnet_address_prefix]

  depends_on = [azurerm_virtual_network.main]
}

# Database Subnet - Data tier with most restrictive access controls
# This subnet implements the highest security controls, allowing only necessary database traffic
resource "azurerm_subnet" "database" {
  name                 = var.database_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.database_subnet_address_prefix]

  depends_on = [azurerm_virtual_network.main]
}

# Network Security Group for Frontend Subnet
# Allows HTTP/HTTPS traffic from internet while blocking unauthorized access
resource "azurerm_network_security_group" "frontend" {
  name                = "nsg-${var.frontend_subnet_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.common_tags, {
    resource_type = "network-security-group"
    tier          = "frontend"
    description   = "NSG for frontend subnet allowing web traffic"
  })
}

# Frontend NSG Rules - Allow HTTP and HTTPS traffic from internet
resource "azurerm_network_security_rule" "frontend_allow_web" {
  count                      = length(var.frontend_allowed_ports)
  name                       = "Allow-HTTP-${var.frontend_allowed_ports[count.index]}"
  priority                   = 1000 + count.index
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = var.frontend_allowed_ports[count.index]
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  resource_group_name        = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.frontend.name
}

# Network Security Group for Backend Subnet
# Restricts access to only allow traffic from frontend subnet on application ports
resource "azurerm_network_security_group" "backend" {
  name                = "nsg-${var.backend_subnet_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.common_tags, {
    resource_type = "network-security-group"
    tier          = "backend"
    description   = "NSG for backend subnet allowing only frontend traffic"
  })
}

# Backend NSG Rule - Allow application traffic from frontend subnet only
resource "azurerm_network_security_rule" "backend_allow_frontend" {
  name                        = "Allow-From-Frontend"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range          = "*"
  destination_port_range     = var.backend_application_port
  source_address_prefix      = var.frontend_subnet_address_prefix
  destination_address_prefix = "*"
  resource_group_name        = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.backend.name
}

# Network Security Group for Database Subnet
# Most restrictive policy allowing only database traffic from backend subnet
resource "azurerm_network_security_group" "database" {
  name                = "nsg-${var.database_subnet_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(local.common_tags, {
    resource_type = "network-security-group"
    tier          = "database"
    description   = "NSG for database subnet allowing only backend traffic"
  })
}

# Database NSG Rule - Allow database traffic from backend subnet only
resource "azurerm_network_security_rule" "database_allow_backend" {
  name                        = "Allow-Database-From-Backend"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range          = "*"
  destination_port_range     = var.database_port
  source_address_prefix      = var.backend_subnet_address_prefix
  destination_address_prefix = "*"
  resource_group_name        = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.database.name
}

# Associate Frontend NSG with Frontend Subnet
# This applies the security rules to all resources deployed in the frontend subnet
resource "azurerm_subnet_network_security_group_association" "frontend" {
  subnet_id                 = azurerm_subnet.frontend.id
  network_security_group_id = azurerm_network_security_group.frontend.id

  # Ensure NSG rules are created before association
  depends_on = [
    azurerm_network_security_rule.frontend_allow_web
  ]
}

# Associate Backend NSG with Backend Subnet
# This enforces backend security policies on all subnet resources
resource "azurerm_subnet_network_security_group_association" "backend" {
  subnet_id                 = azurerm_subnet.backend.id
  network_security_group_id = azurerm_network_security_group.backend.id

  depends_on = [
    azurerm_network_security_rule.backend_allow_frontend
  ]
}

# Associate Database NSG with Database Subnet
# This provides the highest level of network security for data tier resources
resource "azurerm_subnet_network_security_group_association" "database" {
  subnet_id                 = azurerm_subnet.database.id
  network_security_group_id = azurerm_network_security_group.database.id

  depends_on = [
    azurerm_network_security_rule.database_allow_backend
  ]
}
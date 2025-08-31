# Main Terraform configuration for Azure Infrastructure Inventory with Resource Graph
# This file deploys sample infrastructure resources for inventory demonstration
# and configures supporting services for Resource Graph queries

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  # Resource naming convention: project-environment-resource-suffix
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge(var.resource_tags, {
    Environment   = var.environment
    Project       = var.project_name
    Owner        = var.owner
    CostCenter   = var.cost_center
    CreatedBy    = "Terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
    Purpose      = "Infrastructure Inventory and Governance Demo"
  })
  
  # Sample KQL queries for Resource Graph demonstrations
  sample_queries = {
    basic_inventory = "Resources | project name, type, location, resourceGroup, subscriptionId | order by type asc, name asc"
    resource_counts = "Resources | summarize count() by type | order by count_ desc"
    location_analysis = "Resources | where location != '' | summarize ResourceCount=count() by Location=location | order by ResourceCount desc"
    tagging_compliance = "Resources | extend TagCount = array_length(todynamic(tags)) | extend HasTags = case(TagCount > 0, 'Tagged', 'Untagged') | summarize count() by HasTags, type | order by type asc"
    untagged_resources = "Resources | where tags !has 'Environment' or tags !has 'Owner' | project name, type, resourceGroup, location, tags | limit 20"
    security_analysis = "Resources | where type contains 'publicIPAddresses' or type contains 'networkSecurityGroups' | project name, type, location, properties"
  }
}

# Create primary resource group for inventory demonstration
resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

# Create additional resource group for multi-group inventory testing
resource "azurerm_resource_group" "secondary" {
  count    = var.create_sample_resources ? 1 : 0
  name     = "${local.resource_prefix}-secondary-rg-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(local.common_tags, {
    ResourceGroup = "Secondary"
    TestingScope  = "Multi-Group-Inventory"
  })
}

# Storage account for inventory report exports and diagnostics
resource "azurerm_storage_account" "inventory_storage" {
  name                     = "${replace(local.resource_prefix, "-", "")}sa${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Enable blob versioning for report history
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.retention_days
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Inventory Report Storage"
    DataType = "Governance Reports"
  })
}

# Container for storing inventory reports
resource "azurerm_storage_container" "inventory_reports" {
  name                  = "inventory-reports"
  storage_account_name  = azurerm_storage_account.inventory_storage.name
  container_access_type = "private"
}

# Log Analytics Workspace for monitoring and alerting
resource "azurerm_log_analytics_workspace" "inventory_workspace" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "${local.resource_prefix}-law-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days
  
  tags = merge(local.common_tags, {
    Purpose = "Infrastructure Monitoring"
    Service = "Log Analytics"
  })
}

# Virtual Network for sample infrastructure
resource "azurerm_virtual_network" "sample_vnet" {
  count               = var.create_sample_resources ? 1 : 0
  name                = "${local.resource_prefix}-vnet-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    ResourceType = "Networking"
    Tier        = "Infrastructure"
  })
}

# Subnet for sample resources
resource "azurerm_subnet" "sample_subnet" {
  count                = var.create_sample_resources ? 1 : 0
  name                 = "${local.resource_prefix}-subnet-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.sample_vnet[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group with sample rules
resource "azurerm_network_security_group" "sample_nsg" {
  count               = var.create_sample_resources ? 1 : 0
  name                = "${local.resource_prefix}-nsg-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Sample security rule for HTTP traffic
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_ip_ranges
    destination_address_prefix = "*"
  }
  
  # Sample security rule for HTTPS traffic
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.allowed_ip_ranges
    destination_address_prefix = "*"
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Security"
    Purpose     = "Network Protection"
  })
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "sample_nsg_association" {
  count                     = var.create_sample_resources ? 1 : 0
  subnet_id                 = azurerm_subnet.sample_subnet[0].id
  network_security_group_id = azurerm_network_security_group.sample_nsg[0].id
}

# Public IP for sample virtual machine
resource "azurerm_public_ip" "sample_vm_pip" {
  count               = var.create_sample_resources ? 1 : 0
  name                = "${local.resource_prefix}-vm-pip-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(local.common_tags, {
    ResourceType = "Networking"
    Purpose     = "VM Connectivity"
  })
}

# Network Interface for sample virtual machine
resource "azurerm_network_interface" "sample_vm_nic" {
  count               = var.create_sample_resources ? 1 : 0
  name                = "${local.resource_prefix}-vm-nic-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sample_subnet[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.sample_vm_pip[0].id
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Networking"
    Purpose     = "VM Network Interface"
  })
}

# Sample Virtual Machine for inventory demonstration
resource "azurerm_linux_virtual_machine" "sample_vm" {
  count                           = var.create_sample_resources ? 1 : 0
  name                            = "${local.resource_prefix}-vm-${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.sample_vm_size
  disable_password_authentication = true
  
  network_interface_ids = [
    azurerm_network_interface.sample_vm_nic[0].id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  
  admin_username = "azureuser"
  
  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7S+9FHmUyeO7SAMPLE+KEY+FOR+DEMO+PURPOSE+ONLY+DO+NOT+USE+IN+PRODUCTION"
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Compute"
    OS          = "Linux"
    Purpose     = "Sample VM for Inventory"
  })
}

# Key Vault for secrets management demonstration
resource "azurerm_key_vault" "sample_keyvault" {
  count                       = var.create_sample_resources ? 1 : 0
  name                        = "${local.resource_prefix}-kv-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  
  tags = merge(local.common_tags, {
    ResourceType = "Security"
    Purpose     = "Secrets Management"
  })
}

# SQL Database for multi-resource type inventory
resource "azurerm_mssql_server" "sample_sql_server" {
  count                        = var.create_sample_resources ? 1 : 0
  name                         = "${local.resource_prefix}-sql-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "P@ssw0rd123!" # Note: Use Key Vault in production
  
  tags = merge(local.common_tags, {
    ResourceType = "Database"
    Engine      = "SQL Server"
  })
}

# SQL Database
resource "azurerm_mssql_database" "sample_database" {
  count           = var.create_sample_resources ? 1 : 0
  name            = "${local.resource_prefix}-db-${random_string.suffix.result}"
  server_id       = azurerm_mssql_server.sample_sql_server[0].id
  collation       = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb     = 20
  sku_name        = "Basic"
  zone_redundant  = false
  
  tags = merge(local.common_tags, {
    ResourceType = "Database"
    Tier        = "Basic"
  })
}

# Application Insights for monitoring
resource "azurerm_application_insights" "sample_appinsights" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "${local.resource_prefix}-ai-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.inventory_workspace[0].id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    ResourceType = "Monitoring"
    Purpose     = "Application Insights"
  })
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Get current subscription details for Resource Graph queries
data "azurerm_subscription" "current" {}

# Automation Account for scheduled inventory queries (optional)
resource "azurerm_automation_account" "inventory_automation" {
  count               = var.inventory_schedule.enabled ? 1 : 0
  name                = "${local.resource_prefix}-aa-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"
  
  tags = merge(local.common_tags, {
    ResourceType = "Automation"
    Purpose     = "Scheduled Inventory"
  })
}

# Logic App for automated inventory reporting (placeholder)
resource "azurerm_logic_app_workflow" "inventory_workflow" {
  count               = var.inventory_schedule.enabled ? 1 : 0
  name                = "${local.resource_prefix}-logic-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    ResourceType = "Integration"
    Purpose     = "Automated Reporting"
  })
}

# Action Group for alerts (if monitoring is enabled)
resource "azurerm_monitor_action_group" "inventory_alerts" {
  count               = var.enable_monitoring && var.inventory_schedule.alert_on_changes ? 1 : 0
  name                = "${local.resource_prefix}-ag-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "InvAlert"
  
  tags = merge(local.common_tags, {
    ResourceType = "Monitoring"
    Purpose     = "Alerting"
  })
}
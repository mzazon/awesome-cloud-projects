# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate SSH key pair for cluster access
resource "tls_private_key" "hpc_ssh_key" {
  count     = var.enable_ssh_key_authentication ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create resource group for HPC environment
resource "azurerm_resource_group" "hpc" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-hpc-lustre-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    component = "hpc-infrastructure"
  })
}

#
# NETWORK INFRASTRUCTURE
#

# Create virtual network with optimized address space for HPC workloads
resource "azurerm_virtual_network" "hpc_vnet" {
  name                = "vnet-hpc-${random_string.suffix.result}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name

  tags = merge(var.tags, {
    component = "network"
  })
}

# Create compute subnet for HPC cluster nodes
resource "azurerm_subnet" "compute_subnet" {
  name                 = "compute-subnet"
  resource_group_name  = azurerm_resource_group.hpc.name
  virtual_network_name = azurerm_virtual_network.hpc_vnet.name
  address_prefixes     = [var.compute_subnet_address_prefix]

  # Disable private endpoint network policies for HPC networking
  private_endpoint_network_policies_enabled = false
}

# Create management subnet for CycleCloud server
resource "azurerm_subnet" "management_subnet" {
  name                 = "management-subnet"
  resource_group_name  = azurerm_resource_group.hpc.name
  virtual_network_name = azurerm_virtual_network.hpc_vnet.name
  address_prefixes     = [var.management_subnet_address_prefix]

  # Enable private endpoint network policies for management security
  private_endpoint_network_policies_enabled = true
}

# Create storage subnet for Azure Managed Lustre
resource "azurerm_subnet" "storage_subnet" {
  name                 = "storage-subnet"
  resource_group_name  = azurerm_resource_group.hpc.name
  virtual_network_name = azurerm_virtual_network.hpc_vnet.name
  address_prefixes     = [var.storage_subnet_address_prefix]

  # Configure delegation for Azure Managed Lustre
  delegation {
    name = "lustre-delegation"
    service_delegation {
      name = "Microsoft.StorageCache/amlFilesystems"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }

  # Disable private endpoint network policies for storage access
  private_endpoint_network_policies_enabled = false
}

# Create network security group for compute nodes
resource "azurerm_network_security_group" "compute_nsg" {
  name                = "nsg-compute-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name

  # Allow SSH access from management subnet
  security_rule {
    name                       = "Allow-SSH-Management"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.management_subnet_address_prefix
    destination_address_prefix = "*"
  }

  # Allow InfiniBand traffic for HPC communication
  security_rule {
    name                       = "Allow-InfiniBand"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.compute_subnet_address_prefix
    destination_address_prefix = "*"
  }

  # Allow Lustre client traffic
  security_rule {
    name                       = "Allow-Lustre-Client"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "988"
    source_address_prefix      = var.storage_subnet_address_prefix
    destination_address_prefix = "*"
  }

  tags = merge(var.tags, {
    component = "network-security"
  })
}

# Create network security group for management subnet
resource "azurerm_network_security_group" "management_nsg" {
  name                = "nsg-management-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name

  # Allow SSH access from allowed CIDR blocks
  security_rule {
    name                       = "Allow-SSH-Admin"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_ssh_cidrs
    destination_address_prefix = "*"
  }

  # Allow HTTPS access for CycleCloud web interface
  security_rule {
    name                       = "Allow-HTTPS-CycleCloud"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.allowed_ssh_cidrs
    destination_address_prefix = "*"
  }

  # Allow HTTP access for CycleCloud web interface
  security_rule {
    name                       = "Allow-HTTP-CycleCloud"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_ssh_cidrs
    destination_address_prefix = "*"
  }

  tags = merge(var.tags, {
    component = "network-security"
  })
}

# Associate network security groups with subnets
resource "azurerm_subnet_network_security_group_association" "compute_nsg_association" {
  subnet_id                 = azurerm_subnet.compute_subnet.id
  network_security_group_id = azurerm_network_security_group.compute_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "management_nsg_association" {
  subnet_id                 = azurerm_subnet.management_subnet.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id
}

#
# STORAGE INFRASTRUCTURE
#

# Create storage account for CycleCloud and data staging
resource "azurerm_storage_account" "hpc_storage" {
  name                     = "sthpc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.hpc.name
  location                 = azurerm_resource_group.hpc.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"

  # Enable hierarchical namespace for Data Lake capabilities
  is_hns_enabled = true

  # Enable blob versioning and change feed for data protection
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
  }

  tags = merge(var.tags, {
    component = "storage"
  })
}

# Create Azure Managed Lustre file system
resource "azurerm_managed_lustre_file_system" "hpc_lustre" {
  name                = "lustre-hpc-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.hpc.name
  location            = azurerm_resource_group.hpc.location

  # Configure high-performance Lustre settings
  sku_name                   = var.lustre_file_system_type
  storage_capacity_in_tb     = var.lustre_storage_capacity_tib
  zones                      = ["1", "2", "3"] # Multi-zone deployment for HA
  subnet_id                  = azurerm_subnet.storage_subnet.id

  # Configure maintenance window for system updates
  maintenance_window {
    day_of_week        = "Sunday"
    time_of_day_in_utc = "03:00"
  }

  # Configure encryption settings for data at rest
  encryption_key {
    source_vault_id = azurerm_key_vault.hpc_kv.id
    key_url         = azurerm_key_vault_key.lustre_encryption_key.id
  }

  tags = merge(var.tags, {
    component = "lustre-storage"
  })

  depends_on = [
    azurerm_subnet.storage_subnet,
    azurerm_key_vault_access_policy.lustre_access_policy
  ]
}

#
# SECURITY INFRASTRUCTURE
#

# Create Key Vault for storing encryption keys and secrets
resource "azurerm_key_vault" "hpc_kv" {
  name                       = "kv-hpc-${random_string.suffix.result}"
  location                   = azurerm_resource_group.hpc.location
  resource_group_name        = azurerm_resource_group.hpc.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  # Enable Key Vault for disk encryption
  enabled_for_disk_encryption = true
  enabled_for_deployment      = true

  tags = merge(var.tags, {
    component = "security"
  })
}

# Create access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.hpc_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Decrypt", "Encrypt", "Sign", "Verify"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete"
  ]
}

# Create access policy for Azure Managed Lustre
resource "azurerm_key_vault_access_policy" "lustre_access_policy" {
  key_vault_id = azurerm_key_vault.hpc_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = "b60d3c60-3181-4d3b-a446-a5d6b69be7d0" # Azure Managed Lustre service principal

  key_permissions = [
    "Get", "WrapKey", "UnwrapKey"
  ]
}

# Create encryption key for Lustre file system
resource "azurerm_key_vault_key" "lustre_encryption_key" {
  name         = "lustre-encryption-key"
  key_vault_id = azurerm_key_vault.hpc_kv.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"
  ]

  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}

#
# CYCLECLOUD INFRASTRUCTURE
#

# Create public IP for CycleCloud management server
resource "azurerm_public_ip" "cyclecloud_public_ip" {
  name                = "pip-cyclecloud-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(var.tags, {
    component = "cyclecloud"
  })
}

# Create network interface for CycleCloud server
resource "azurerm_network_interface" "cyclecloud_nic" {
  name                = "nic-cyclecloud-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.management_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cyclecloud_public_ip.id
  }

  tags = merge(var.tags, {
    component = "cyclecloud"
  })
}

# Create CycleCloud initialization script
locals {
  cyclecloud_init_script = base64encode(templatefile("${path.module}/cyclecloud-init.sh", {
    storage_account_name = azurerm_storage_account.hpc_storage.name
    storage_account_key  = azurerm_storage_account.hpc_storage.primary_access_key
    lustre_mount_ip      = azurerm_managed_lustre_file_system.hpc_lustre.client_endpoints[0]
    cluster_name         = var.hpc_cluster_name
  }))
}

# Create CycleCloud management server
resource "azurerm_linux_virtual_machine" "cyclecloud_server" {
  name                = "vm-cyclecloud-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name
  size                = var.cyclecloud_vm_size

  # Disable password authentication for security
  disable_password_authentication = var.enable_ssh_key_authentication

  network_interface_ids = [
    azurerm_network_interface.cyclecloud_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.cyclecloud_os_disk_size_gb
  }

  # Use CycleCloud marketplace image
  source_image_reference {
    publisher = "microsoft-ads"
    offer     = "azure-cyclecloud"
    sku       = "cyclecloud81"
    version   = "latest"
  }

  admin_username = var.cyclecloud_admin_username

  # Configure SSH key authentication
  dynamic "admin_ssh_key" {
    for_each = var.enable_ssh_key_authentication ? [1] : []
    content {
      username   = var.cyclecloud_admin_username
      public_key = var.enable_ssh_key_authentication ? tls_private_key.hpc_ssh_key[0].public_key_openssh : file(var.ssh_public_key_path)
    }
  }

  # Configure custom data for initialization
  custom_data = local.cyclecloud_init_script

  # Configure boot diagnostics
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.hpc_storage.primary_blob_endpoint
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    component = "cyclecloud"
  })
}

# Create role assignment for CycleCloud managed identity
resource "azurerm_role_assignment" "cyclecloud_contributor" {
  scope                = azurerm_resource_group.hpc.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.cyclecloud_server.identity[0].principal_id
}

#
# MONITORING INFRASTRUCTURE
#

# Create Log Analytics workspace for HPC monitoring
resource "azurerm_log_analytics_workspace" "hpc_monitoring" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-hpc-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days

  tags = merge(var.tags, {
    component = "monitoring"
  })
}

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "hpc_app_insights" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-hpc-${random_string.suffix.result}"
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name
  workspace_id        = azurerm_log_analytics_workspace.hpc_monitoring[0].id
  application_type    = "other"

  tags = merge(var.tags, {
    component = "monitoring"
  })
}

# Create action group for HPC alerts
resource "azurerm_monitor_action_group" "hpc_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ag-hpc-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.hpc.name
  short_name          = "hpc-alerts"

  email_receiver {
    name          = "admin-email"
    email_address = "admin@example.com"
  }

  tags = merge(var.tags, {
    component = "monitoring"
  })
}

# Create metric alert for high CPU utilization
resource "azurerm_monitor_metric_alert" "high_cpu_alert" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "HPC-High-CPU-Utilization"
  resource_group_name = azurerm_resource_group.hpc.name
  scopes              = [azurerm_resource_group.hpc.id]
  description         = "Alert when cluster CPU utilization exceeds 90%"
  target_resource_type = "Microsoft.Compute/virtualMachines"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90

    dimension {
      name     = "VMName"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.hpc_alerts[0].id
  }

  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2

  tags = merge(var.tags, {
    component = "monitoring"
  })
}

# Create diagnostic settings for CycleCloud VM
resource "azurerm_monitor_diagnostic_setting" "cyclecloud_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "cyclecloud-diagnostics"
  target_resource_id = azurerm_linux_virtual_machine.cyclecloud_server.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hpc_monitoring[0].id

  enabled_log {
    category = "VMSetupEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Lustre file system
resource "azurerm_monitor_diagnostic_setting" "lustre_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "lustre-diagnostics"
  target_resource_id = azurerm_managed_lustre_file_system.hpc_lustre.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hpc_monitoring[0].id

  enabled_log {
    category = "LustreAuditLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
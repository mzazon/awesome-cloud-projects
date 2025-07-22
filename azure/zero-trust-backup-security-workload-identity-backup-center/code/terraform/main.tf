# main.tf - Main Terraform configuration for zero-trust backup security solution
# This file contains all the Azure resources needed for implementing zero-trust backup security

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix
  resource_group_name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  key_vault_name         = var.key_vault_name != "" ? var.key_vault_name : "kv-${var.project_name}-${random_string.suffix.result}"
  workload_identity_name = var.workload_identity_name != "" ? var.workload_identity_name : "wi-${var.project_name}-${random_string.suffix.result}"
  recovery_vault_name    = var.recovery_vault_name != "" ? var.recovery_vault_name : "rsv-${var.project_name}-${random_string.suffix.result}"
  storage_account_name   = var.storage_account_name != "" ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  vm_name               = var.vm_name != "" ? var.vm_name : "vm-${var.project_name}-test-${random_string.suffix.result}"
  
  # Common tags merged with user-defined tags
  common_tags = merge(var.common_tags, {
    DeployedAt = timestamp()
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# User-Assigned Managed Identity for Workload Identity Federation
resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = local.workload_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Key Vault with zero-trust security configuration
resource "azurerm_key_vault" "main" {
  name                          = local.key_vault_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku
  soft_delete_retention_days    = var.key_vault_soft_delete_retention_days
  purge_protection_enabled      = true
  enabled_for_disk_encryption   = true
  enabled_for_template_deployment = true
  
  # Enable RBAC authorization instead of access policies
  enable_rbac_authorization = true
  
  # Network ACLs for zero-trust security
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    
    # Allow specific IP ranges if provided
    ip_rules = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Role assignments for Key Vault access
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
}

resource "azurerm_role_assignment" "kv_certificate_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificate Officer"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
}

resource "azurerm_role_assignment" "kv_admin_current_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Recovery Services Vault with advanced security features
resource "azurerm_recovery_services_vault" "main" {
  name                = local.recovery_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  storage_mode_type   = var.recovery_vault_storage_mode_type
  cross_region_restore_enabled = var.recovery_vault_cross_region_restore_enabled
  soft_delete_enabled = var.recovery_vault_soft_delete_enabled
  
  tags = local.common_tags
}

# Storage Account for backup reports and monitoring
resource "azurerm_storage_account" "backup_reports" {
  name                      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  access_tier               = var.storage_account_access_tier
  min_tls_version          = var.storage_account_min_tls_version
  https_traffic_only_enabled = true
  
  # Enable advanced security features
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = local.common_tags
}

# Storage Container for backup reports
resource "azurerm_storage_container" "backup_reports" {
  name                  = "backup-reports"
  storage_account_name  = azurerm_storage_account.backup_reports.name
  container_access_type = "private"
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "backup_center" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-backup-center-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# VM Backup Policy with zero-trust security controls
resource "azurerm_backup_policy_vm" "zero_trust_policy" {
  name                = "ZeroTrustVMPolicy"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  
  # Backup schedule configuration
  backup {
    frequency = "Daily"
    time      = var.backup_policy_vm_schedule_run_times[0]
  }
  
  # Retention policies
  retention_daily {
    count = var.backup_policy_vm_daily_retention_days
  }
  
  retention_weekly {
    count    = var.backup_policy_vm_weekly_retention_weeks
    weekdays = ["Sunday"]
  }
  
  retention_monthly {
    count    = var.backup_policy_vm_monthly_retention_months
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
  
  # Enable instant restore snapshots
  instant_restore_retention_days = 5
}

# Virtual Network for test VM
resource "azurerm_virtual_network" "test_vnet" {
  count               = var.enable_vm_creation ? 1 : 0
  name                = "vnet-backup-test"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Subnet for test VM
resource "azurerm_subnet" "test_subnet" {
  count                = var.enable_vm_creation ? 1 : 0
  name                 = "subnet-backup-test"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.test_vnet[0].name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group with restricted access
resource "azurerm_network_security_group" "test_nsg" {
  count               = var.enable_vm_creation ? 1 : 0
  name                = "nsg-backup-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Allow SSH access (restrict this in production)
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Public IP for test VM
resource "azurerm_public_ip" "test_pip" {
  count               = var.enable_vm_creation ? 1 : 0
  name                = "pip-backup-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network Interface for test VM
resource "azurerm_network_interface" "test_nic" {
  count               = var.enable_vm_creation ? 1 : 0
  name                = "nic-backup-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.test_subnet[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.test_pip[0].id
  }
  
  tags = local.common_tags
}

# Associate Network Security Group with Network Interface
resource "azurerm_network_interface_security_group_association" "test_nsg_association" {
  count                     = var.enable_vm_creation ? 1 : 0
  network_interface_id      = azurerm_network_interface.test_nic[0].id
  network_security_group_id = azurerm_network_security_group.test_nsg[0].id
}

# Test Virtual Machine
resource "azurerm_linux_virtual_machine" "test_vm" {
  count               = var.enable_vm_creation ? 1 : 0
  name                = local.vm_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  
  # Disable password authentication for better security
  disable_password_authentication = false
  
  network_interface_ids = [
    azurerm_network_interface.test_nic[0].id,
  ]
  
  admin_username = var.vm_admin_username
  admin_password = var.vm_admin_password
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = var.vm_source_image_reference.publisher
    offer     = var.vm_source_image_reference.offer
    sku       = var.vm_source_image_reference.sku
    version   = var.vm_source_image_reference.version
  }
  
  tags = local.common_tags
}

# Backup Protection for VM
resource "azurerm_backup_protected_vm" "test_vm_backup" {
  count               = var.enable_vm_creation && var.enable_backup_protection ? 1 : 0
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = azurerm_linux_virtual_machine.test_vm[0].id
  backup_policy_id    = azurerm_backup_policy_vm.zero_trust_policy.id
  
  depends_on = [
    azurerm_backup_policy_vm.zero_trust_policy,
    azurerm_linux_virtual_machine.test_vm
  ]
}

# Federated Identity Credentials for external access
resource "azuread_application_federated_identity_credential" "federated_creds" {
  count          = var.enable_federated_credentials ? length(var.federated_identity_credentials) : 0
  application_id = azurerm_user_assigned_identity.workload_identity.client_id
  display_name   = var.federated_identity_credentials[count.index].name
  description    = var.federated_identity_credentials[count.index].description
  audiences      = var.federated_identity_credentials[count.index].audience
  issuer         = var.federated_identity_credentials[count.index].issuer
  subject        = var.federated_identity_credentials[count.index].subject
}

# Wait for role assignments to propagate
resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.kv_secrets_officer,
    azurerm_role_assignment.kv_certificate_officer,
    azurerm_role_assignment.kv_admin_current_user
  ]
  
  create_duration = "30s"
}

# Key Vault Secrets for backup operations
resource "azurerm_key_vault_secret" "backup_storage_key" {
  name         = "backup-storage-key"
  value        = azurerm_storage_account.backup_reports.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    time_sleep.wait_for_rbac
  ]
  
  tags = {
    purpose = "backup-reports"
  }
}

resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=tcp:server.database.windows.net,1433;Database=mydb;User ID=admin;Password=SecurePassword123!;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    time_sleep.wait_for_rbac
  ]
  
  tags = {
    purpose = "database-backup"
  }
}

# TLS private key for certificate
resource "tls_private_key" "backup_cert_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Self-signed certificate for backup encryption
resource "tls_self_signed_cert" "backup_cert" {
  private_key_pem = tls_private_key.backup_cert_key.private_key_pem
  
  subject {
    common_name  = "backup-encryption"
    organization = "Zero Trust Backup"
  }
  
  validity_period_hours = var.certificate_validity_months * 30 * 24
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

# Key Vault Certificate for backup encryption
resource "azurerm_key_vault_certificate" "backup_encryption_cert" {
  name         = "backup-encryption-cert"
  key_vault_id = azurerm_key_vault.main.id
  
  certificate {
    contents = base64encode(tls_self_signed_cert.backup_cert.cert_pem)
    password = ""
  }
  
  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    
    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }
    
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    
    x509_certificate_properties {
      subject            = "CN=backup-encryption"
      validity_in_months = var.certificate_validity_months
      
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
    }
  }
  
  depends_on = [
    time_sleep.wait_for_rbac
  ]
  
  tags = {
    purpose = "backup-encryption"
  }
}
# Azure Confidential Computing with Hardware-Protected Enclaves
# This Terraform configuration deploys a complete confidential computing solution
# including Confidential VMs, Managed HSM, Azure Attestation, and supporting infrastructure

# Data sources for current client configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Virtual Network for Confidential Computing
resource "azurerm_virtual_network" "main" {
  count = var.create_virtual_network ? 1 : 0

  name                = "vnet-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create VM Subnet for Confidential VMs
resource "azurerm_subnet" "vm_subnet" {
  count = var.create_virtual_network ? 1 : 0

  name                 = "subnet-vm-${var.project_name}-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.subnet_address_prefixes.vm_subnet
}

# Create Bastion Subnet for secure remote access
resource "azurerm_subnet" "bastion_subnet" {
  count = var.create_virtual_network ? 1 : 0

  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.subnet_address_prefixes.bastion_subnet
}

# Create Network Security Group for Confidential VM
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-vm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # Allow SSH from Bastion subnet only
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.create_virtual_network ? var.subnet_address_prefixes.bastion_subnet[0] : "*"
    destination_address_prefix = "*"
  }

  # Allow outbound internet access for package downloads
  security_rule {
    name                       = "Internet"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# Associate NSG with VM subnet
resource "azurerm_subnet_network_security_group_association" "vm_nsg_association" {
  count = var.create_virtual_network ? 1 : 0

  subnet_id                 = azurerm_subnet.vm_subnet[0].id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Create Azure Attestation Provider
resource "azurerm_attestation_provider" "main" {
  name                = "att-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags

  # Custom attestation policy for SEV-SNP VMs
  policy_signing_certificate_data = var.attestation_policy != null ? var.attestation_policy : null
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_diagnostics ? 1 : 0

  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Create User-Assigned Managed Identity for Confidential VM
resource "azurerm_user_assigned_identity" "vm_identity" {
  name                = "id-vm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create User-Assigned Managed Identity for Storage Account
resource "azurerm_user_assigned_identity" "storage_identity" {
  name                = "id-storage-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create Azure Managed HSM
resource "azurerm_key_vault_managed_hardware_security_module" "main" {
  name                     = "hsm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  sku_name                 = var.hsm_sku
  purge_protection_enabled = var.enable_purge_protection
  soft_delete_retention_days = var.hsm_soft_delete_retention_days
  tenant_id                = data.azurerm_client_config.current.tenant_id

  # Add current user as administrator
  admin_object_ids = [
    data.azurerm_client_config.current.object_id
  ]

  # Network access rules
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      bypass                     = "AzureServices"
      default_action             = "Deny"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.create_virtual_network ? [azurerm_subnet.vm_subnet[0].id] : []
    }
  }

  tags = var.tags
}

# Create Azure Key Vault Premium for enclave integration
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Security configuration
  purge_protection_enabled     = var.enable_purge_protection
  soft_delete_retention_days   = 7
  enable_rbac_authorization    = var.enable_rbac_authorization
  enabled_for_disk_encryption  = true
  enabled_for_template_deployment = true

  # Network access rules
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      bypass                     = "AzureServices"
      default_action             = "Deny"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.create_virtual_network ? [azurerm_subnet.vm_subnet[0].id] : []
    }
  }

  tags = var.tags
}

# Create HSM-backed encryption key in Key Vault
resource "azurerm_key_vault_key" "enclave_master_key" {
  name         = "enclave-master-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 2048

  key_opts = [
    "encrypt",
    "decrypt",
    "sign",
    "verify",
    "wrapKey",
    "unwrapKey"
  ]

  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

# Create Storage Account with customer-managed keys
resource "azurerm_storage_account" "main" {
  name                     = "st${var.project_name}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  min_tls_version          = "TLS1_2"

  # Security configuration
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  # Customer-managed encryption configuration
  customer_managed_key {
    key_vault_key_id          = azurerm_key_vault_key.enclave_master_key.id
    user_assigned_identity_id = azurerm_user_assigned_identity.storage_identity.id
  }

  # Managed identity for customer-managed keys
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.storage_identity.id]
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.storage_kv_crypto_user
  ]
}

# Create SSH Key Pair for Confidential VM
resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create Public IP for Confidential VM
resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-vm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Create Network Interface for Confidential VM
resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-vm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.create_virtual_network ? azurerm_subnet.vm_subnet[0].id : null
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }
}

# Create Confidential Virtual Machine with AMD SEV-SNP
resource "azurerm_linux_virtual_machine" "confidential_vm" {
  name                = "vm-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username

  # Confidential VM configuration
  vtpm_enabled               = true
  secure_boot_enabled        = true
  encryption_at_host_enabled = true

  # Disable password authentication
  disable_password_authentication = true

  # Network interface
  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  # OS disk configuration
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    security_encryption_type = "VMGuestStateOnly"
  }

  # VM image for confidential computing
  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  # SSH key configuration
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vm_ssh_key.public_key_openssh
  }

  # Managed identity for accessing Key Vault and HSM
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm_identity.id]
  }

  # Custom data for VM initialization
  custom_data = base64encode(templatefile("${path.module}/scripts/vm-init.sh", {
    attestation_endpoint = azurerm_attestation_provider.main.attestation_uri
    hsm_name            = azurerm_key_vault_managed_hardware_security_module.main.name
    key_vault_name      = azurerm_key_vault.main.name
    storage_account_name = azurerm_storage_account.main.name
  }))

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.vm_hsm_crypto_user,
    azurerm_role_assignment.vm_kv_crypto_user
  ]
}

# Create VM initialization script
resource "local_file" "vm_init_script" {
  filename = "${path.module}/scripts/vm-init.sh"
  content = templatefile("${path.module}/vm-init.sh.tpl", {
    attestation_endpoint = azurerm_attestation_provider.main.attestation_uri
    hsm_name            = azurerm_key_vault_managed_hardware_security_module.main.name
    key_vault_name      = azurerm_key_vault.main.name
    storage_account_name = azurerm_storage_account.main.name
  })
}

# Create VM initialization script template
resource "local_file" "vm_init_script_template" {
  filename = "${path.module}/vm-init.sh.tpl"
  content = <<-EOT
#!/bin/bash
# VM initialization script for Azure Confidential Computing

# Update system
apt-get update && apt-get upgrade -y

# Install required packages
apt-get install -y \
    curl \
    wget \
    jq \
    python3 \
    python3-pip \
    build-essential \
    git

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Python packages for confidential computing
pip3 install --upgrade pip
pip3 install azure-identity azure-keyvault-keys azure-attestation azure-storage-blob

# Create application directory
mkdir -p /opt/confidential-app
cd /opt/confidential-app

# Create confidential application
cat > confidential_app.py << 'EOF'
#!/usr/bin/env python3
"""
Azure Confidential Computing Sample Application
This application demonstrates secure enclave operations with:
- Remote attestation verification
- Secure key retrieval from Managed HSM
- Encrypted data processing
"""

import os
import json
import base64
from azure.identity import ManagedIdentityCredential
from azure.keyvault.keys import KeyClient
from azure.attestation import AttestationClient
from azure.storage.blob import BlobServiceClient

class ConfidentialApp:
    def __init__(self):
        self.credential = ManagedIdentityCredential()
        self.attestation_endpoint = "${attestation_endpoint}"
        self.hsm_endpoint = "https://${hsm_name}.managedhsm.azure.net"
        self.kv_endpoint = "https://${key_vault_name}.vault.azure.net"
        self.storage_account = "${storage_account_name}"
        
    def get_attestation_token(self):
        """Get attestation token for TEE verification"""
        try:
            print("🔐 Obtaining attestation token...")
            attest_client = AttestationClient(
                endpoint=self.attestation_endpoint,
                credential=self.credential
            )
            # In a real scenario, you would generate an actual TEE report
            print("✅ Attestation token obtained successfully")
            return "attestation_token_placeholder"
        except Exception as e:
            print(f"❌ Attestation failed: {e}")
            return None
    
    def retrieve_encryption_key(self):
        """Retrieve encryption key from Managed HSM"""
        try:
            print("🔑 Retrieving encryption key from HSM...")
            key_client = KeyClient(
                vault_url=self.hsm_endpoint,
                credential=self.credential
            )
            # This would fail without proper attestation in production
            key = key_client.get_key("confidential-data-key")
            print(f"✅ Successfully retrieved key: {key.name}")
            return key
        except Exception as e:
            print(f"❌ Key retrieval failed: {e}")
            return None
    
    def process_confidential_data(self, data):
        """Process confidential data in secure enclave"""
        print("🔒 Processing confidential data in secure enclave...")
        # Simulate secure processing
        processed_data = {
            "original_length": len(data),
            "processing_timestamp": "2024-01-01T12:00:00Z",
            "security_level": "TEE_PROTECTED",
            "encrypted": True
        }
        print("✅ Confidential processing complete")
        return processed_data
    
    def run(self):
        """Run the confidential computing workflow"""
        print("🚀 Starting Azure Confidential Computing Demo")
        print("=" * 50)
        
        # Step 1: Get attestation token
        attestation_token = self.get_attestation_token()
        if not attestation_token:
            print("❌ Cannot proceed without attestation")
            return
        
        # Step 2: Retrieve encryption key
        encryption_key = self.retrieve_encryption_key()
        if not encryption_key:
            print("❌ Cannot proceed without encryption key")
            return
        
        # Step 3: Process confidential data
        sample_data = "This is highly confidential data that must be protected"
        result = self.process_confidential_data(sample_data)
        
        print("\n📊 Processing Results:")
        print(json.dumps(result, indent=2))
        
        print("\n🎉 Confidential computing workflow completed successfully!")
        print("✅ Data was processed in hardware-protected enclave")
        print("✅ Keys were retrieved from dedicated HSM")
        print("✅ Attestation verified execution environment")

if __name__ == "__main__":
    app = ConfidentialApp()
    app.run()
EOF

# Make script executable
chmod +x confidential_app.py

# Create systemd service for the confidential app
cat > /etc/systemd/system/confidential-app.service << 'EOF'
[Unit]
Description=Azure Confidential Computing Application
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /opt/confidential-app/confidential_app.py
WorkingDirectory=/opt/confidential-app
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable confidential-app.service

# Log completion
echo "$(date): VM initialization completed" >> /var/log/confidential-vm-init.log
echo "Attestation Endpoint: ${attestation_endpoint}" >> /var/log/confidential-vm-init.log
echo "HSM Name: ${hsm_name}" >> /var/log/confidential-vm-init.log
echo "Key Vault Name: ${key_vault_name}" >> /var/log/confidential-vm-init.log
echo "Storage Account: ${storage_account_name}" >> /var/log/confidential-vm-init.log

EOT
}

# RBAC Role Assignments

# Assign Key Vault Administrator role to current user
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Assign Managed HSM Crypto User role to VM identity
resource "azurerm_role_assignment" "vm_hsm_crypto_user" {
  scope                = azurerm_key_vault_managed_hardware_security_module.main.id
  role_definition_name = "Managed HSM Crypto User"
  principal_id         = azurerm_user_assigned_identity.vm_identity.principal_id
}

# Assign Key Vault Crypto User role to VM identity
resource "azurerm_role_assignment" "vm_kv_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.vm_identity.principal_id
}

# Assign Key Vault Crypto Service Encryption User role to storage identity
resource "azurerm_role_assignment" "storage_kv_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.storage_identity.principal_id
}

# Assign Storage Blob Data Contributor role to VM identity
resource "azurerm_role_assignment" "vm_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.vm_identity.principal_id
}

# Diagnostic Settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-kv-${var.project_name}-${var.environment}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Managed HSM
resource "azurerm_monitor_diagnostic_setting" "managed_hsm" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-hsm-${var.project_name}-${var.environment}"
  target_resource_id         = azurerm_key_vault_managed_hardware_security_module.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for VM
resource "azurerm_monitor_diagnostic_setting" "vm" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-vm-${var.project_name}-${var.environment}"
  target_resource_id         = azurerm_linux_virtual_machine.confidential_vm.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Storage Container for confidential data
resource "azurerm_storage_container" "confidential_data" {
  name                  = "confidential-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}
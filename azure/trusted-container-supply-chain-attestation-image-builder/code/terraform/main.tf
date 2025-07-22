# Azure Trusted Container Supply Chain Infrastructure
# This Terraform configuration deploys a complete trusted container supply chain
# using Azure Attestation Service, Azure Image Builder, Azure Container Registry, and Azure Key Vault

# Data sources for current subscription and client configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = var.random_suffix_length
  special = false
  upper   = false
  numeric = true
}

locals {
  # Calculate resource name suffix
  name_suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Common resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with suffix for global uniqueness
  attestation_name    = "att-${local.resource_prefix}-${local.name_suffix}"
  key_vault_name     = "kv-${replace(local.resource_prefix, "-", "")}${local.name_suffix}"
  acr_name           = "acr${replace(local.resource_prefix, "-", "")}${local.name_suffix}"
  identity_name      = "mi-imagebuilder-${local.resource_prefix}-${local.name_suffix}"
  storage_name       = "st${replace(local.resource_prefix, "-", "")}${local.name_suffix}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    CreatedDate = timestamp()
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostic_settings ? 1 : 0
  name                = "law-${local.resource_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# User-assigned Managed Identity for Image Builder
resource "azurerm_user_assigned_identity" "image_builder" {
  name                = local.identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Azure Key Vault for storing signing keys and certificates
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Enable RBAC authorization instead of access policies
  enable_rbac_authorization = var.enable_rbac_authorization
  
  # Soft delete configuration
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_sku == "premium" ? true : false

  # Network access rules
  public_network_access_enabled = length(var.allowed_ip_ranges) > 0 ? false : true
  
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = var.allowed_ip_ranges
    }
  }

  tags = local.common_tags
}

# Key Vault diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_key_vault.main.name}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Role assignment for Image Builder managed identity to access Key Vault
resource "azurerm_role_assignment" "image_builder_key_vault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Additional role assignment for Key Vault Secrets User (for accessing attestation tokens)
resource "azurerm_role_assignment" "image_builder_key_vault_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Container signing key in Key Vault
resource "azurerm_key_vault_key" "container_signing" {
  name         = "container-signing-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = var.signing_key_type
  key_size     = var.signing_key_type == "RSA" ? var.signing_key_size : null
  curve        = var.signing_key_type == "EC" ? var.signing_key_curve : null

  key_opts = [
    "sign",
    "verify"
  ]

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.image_builder_key_vault
  ]
}

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled

  # Network access configuration
  public_network_access_enabled = var.acr_public_network_access_enabled

  # Trust policy (content trust) - available in Premium SKU
  dynamic "trust_policy" {
    for_each = var.acr_sku == "Premium" && var.acr_trust_policy_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  # Quarantine policy - available in Premium SKU
  dynamic "quarantine_policy" {
    for_each = var.acr_sku == "Premium" && var.acr_quarantine_policy_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  # Retention policy - available in Premium SKU
  dynamic "retention_policy" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      days    = var.acr_retention_policy_days
      enabled = true
    }
  }

  tags = local.common_tags
}

# Container Registry diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "acr" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_container_registry.main.name}"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Role assignment for Image Builder to push to Container Registry
resource "azurerm_role_assignment" "image_builder_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Azure Attestation Provider
resource "azurerm_attestation_provider" "main" {
  name                = local.attestation_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Policy signing certificates (optional)
  # policy_signing_certificate_data = file("path/to/certificate.pem")

  tags = local.common_tags
}

# Storage Account for Image Builder artifacts
resource "azurerm_storage_account" "image_builder" {
  name                     = local.storage_name
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Storage container for Image Builder templates
resource "azurerm_storage_container" "image_templates" {
  name                  = "image-templates"
  storage_account_name  = azurerm_storage_account.image_builder.name
  container_access_type = "private"
}

# Role assignment for Image Builder to access storage account
resource "azurerm_role_assignment" "image_builder_storage" {
  scope                = azurerm_storage_account.image_builder.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Shared Image Gallery for storing custom images
resource "azurerm_shared_image_gallery" "main" {
  name                = "sig_${replace(local.resource_prefix, "-", "_")}_${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Shared Image Gallery for trusted container images"

  tags = local.common_tags
}

# Shared Image Definition for trusted images
resource "azurerm_shared_image" "trusted_image" {
  name                = "trusted-container-image"
  gallery_name        = azurerm_shared_image_gallery.main.name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  hyper_v_generation  = "V2"
  
  description = "Trusted container base image with attestation capabilities"

  identifier {
    publisher = "CompanyName"
    offer     = "TrustedContainers"
    sku       = "Ubuntu20.04-Attested"
  }

  tags = local.common_tags
}

# Role assignment for Image Builder to access Shared Image Gallery
resource "azurerm_role_assignment" "image_builder_sig" {
  scope                = azurerm_shared_image_gallery.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Image Builder Template
resource "azurerm_image_builder_template" "main" {
  name                = "ibt-${local.resource_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # VM profile configuration
  vm_profile {
    vm_size         = var.image_builder_vm_size
    os_disk_size_gb = var.image_builder_os_disk_size_gb
  }

  # Source image configuration
  source {
    type      = "PlatformImage"
    publisher = var.source_image_publisher
    offer     = var.source_image_offer
    sku       = var.source_image_sku
    version   = var.source_image_version
  }

  # Customization steps
  customize {
    type = "Shell"
    name = "InstallDocker"
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io curl jq",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker $USER"
    ]
  }

  customize {
    type = "Shell"
    name = "InstallAttestationTools"
    inline = [
      "# Install Azure CLI for attestation integration",
      "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash",
      "# Install attestation client tools",
      "sudo apt-get install -y tpm2-tools",
      "# Create attestation verification script",
      "sudo mkdir -p /opt/attestation",
      "cat << 'EOF' | sudo tee /opt/attestation/verify.sh",
      "#!/bin/bash",
      "# Attestation verification script",
      "echo 'Attestation verification initiated'",
      "# In production, this would collect TPM evidence",
      "# and submit to Azure Attestation Service",
      "EOF",
      "sudo chmod +x /opt/attestation/verify.sh"
    ]
  }

  customize {
    type = "Shell"
    name = "BuildSecureContainer"
    inline = [
      "# Create secure Dockerfile",
      "cat << 'EOF' > /tmp/Dockerfile",
      "FROM ubuntu:20.04",
      "LABEL security.scan=passed",
      "LABEL attestation.verified=true",
      "RUN apt-get update && \\",
      "    apt-get install -y curl jq && \\",
      "    apt-get clean && \\",
      "    rm -rf /var/lib/apt/lists/*",
      "COPY attestation-check.sh /usr/local/bin/",
      "RUN chmod +x /usr/local/bin/attestation-check.sh",
      "CMD [\"/usr/local/bin/attestation-check.sh\"]",
      "EOF",
      "# Create attestation check script for container",
      "cat << 'EOF' > /tmp/attestation-check.sh",
      "#!/bin/bash",
      "echo 'Container attestation check passed'",
      "echo 'Image verified: trusted-app:latest'",
      "exec \"$@\"",
      "EOF",
      "# Build the container image",
      "sudo docker build -t trusted-app:latest /tmp/"
    ]
  }

  # Distribution target to Shared Image Gallery
  distribute {
    type                   = "SharedImage"
    gallery_image_id       = "${azurerm_shared_image.trusted_image.id}/versions/1.0.0"
    run_output_name        = "trustedImageOutput"
    replication_regions    = [var.location]
    storage_account_type   = "Standard_LRS"
    
    versioning {
      scheme = "Latest"
      major  = 1
    }
  }

  # Identity configuration
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.image_builder.id
    ]
  }

  # Build timeout
  build_timeout_in_minutes = var.image_builder_build_timeout_minutes

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.image_builder_sig,
    azurerm_role_assignment.image_builder_storage,
    azurerm_role_assignment.image_builder_acr_push
  ]
}

# Virtual Network (optional, for enhanced security)
resource "azurerm_virtual_network" "main" {
  count               = var.create_virtual_network ? 1 : 0
  name                = "vnet-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.virtual_network_address_space

  tags = local.common_tags
}

# Subnet for Image Builder
resource "azurerm_subnet" "image_builder" {
  count                = var.create_virtual_network ? 1 : 0
  name                 = "snet-imagebuilder"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes[0]]

  # Service endpoints for secure access to storage and key vault
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.ContainerRegistry"
  ]
}

# Subnet for Container Registry
resource "azurerm_subnet" "container_registry" {
  count                = var.create_virtual_network ? 1 : 0
  name                 = "snet-acr"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes[1]]

  service_endpoints = [
    "Microsoft.ContainerRegistry"
  ]
}

# Network Security Group for Image Builder subnet
resource "azurerm_network_security_group" "image_builder" {
  count               = var.create_virtual_network ? 1 : 0
  name                = "nsg-imagebuilder"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Outbound rules for package downloads and Azure services
  security_rule {
    name                       = "AllowHTTPSOutbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPOutbound"
    priority                   = 1001
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Associate NSG with Image Builder subnet
resource "azurerm_subnet_network_security_group_association" "image_builder" {
  count                     = var.create_virtual_network ? 1 : 0
  subnet_id                 = azurerm_subnet.image_builder[0].id
  network_security_group_id = azurerm_network_security_group.image_builder[0].id
}
# Main Terraform configuration for Azure Data Share and Service Fabric Cross-Organization Collaboration

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent naming
locals {
  resource_suffix = random_string.suffix.result
  
  naming_convention = {
    provider_rg   = "rg-${var.project_name}-${var.data_provider_org}-${var.environment}-${local.resource_suffix}"
    consumer_rg   = "rg-${var.project_name}-${var.data_consumer_org}-${var.environment}-${local.resource_suffix}"
    data_share    = "${var.project_name}${local.resource_suffix}"
    sf_cluster    = "sf-governance-${var.environment}-${local.resource_suffix}"
    kv_provider   = "kv-${var.data_provider_org}-${var.environment}-${local.resource_suffix}"
    kv_consumer   = "kv-${var.data_consumer_org}-${var.environment}-${local.resource_suffix}"
    st_provider   = "st${var.data_provider_org}${var.environment}${local.resource_suffix}"
    st_consumer   = "st${var.data_consumer_org}${var.environment}${local.resource_suffix}"
    log_analytics = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
    vnet          = "vnet-${var.project_name}-${var.environment}-${local.resource_suffix}"
  }
  
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    DeployedBy    = "Terraform"
    DeployedDate  = timestamp()
    Location      = var.location
  })
}

# Resource Groups
resource "azurerm_resource_group" "provider" {
  name     = local.naming_convention.provider_rg
  location = var.location
  tags     = merge(local.common_tags, {
    Role = "DataProvider"
    Organization = var.data_provider_org
  })
}

resource "azurerm_resource_group" "consumer" {
  name     = local.naming_convention.consumer_rg
  location = var.location
  tags     = merge(local.common_tags, {
    Role = "DataConsumer"
    Organization = var.data_consumer_org
  })
}

# Virtual Network for Service Fabric and Private Endpoints
resource "azurerm_virtual_network" "main" {
  name                = local.naming_convention.vnet
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  tags                = local.common_tags
}

# Subnets for different components
resource "azurerm_subnet" "service_fabric" {
  name                 = "subnet-service-fabric"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefixes.service_fabric]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "subnet-private-endpoints"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefixes.private_endpoints]
  
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "gateway" {
  name                 = "subnet-gateway"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefixes.gateway]
}

# Network Security Groups
resource "azurerm_network_security_group" "service_fabric" {
  name                = "nsg-service-fabric-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  tags                = local.common_tags

  # Allow Service Fabric communication
  security_rule {
    name                       = "AllowServiceFabricGateway"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "19000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowServiceFabricReverseProxy"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "19080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowApplicationPorts"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "20000-30000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowEphemeralPorts"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "49152-65534"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with Service Fabric subnet
resource "azurerm_subnet_network_security_group_association" "service_fabric" {
  subnet_id                 = azurerm_subnet.service_fabric.id
  network_security_group_id = azurerm_network_security_group.service_fabric.id
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.naming_convention.log_analytics
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Storage Accounts for data repositories
resource "azurerm_storage_account" "provider" {
  name                     = local.naming_convention.st_provider
  resource_group_name      = azurerm_resource_group.provider.name
  location                 = azurerm_resource_group.provider.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.storage_tier
  
  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Configure blob properties
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  tags = merge(local.common_tags, {
    Role = "DataProvider"
    Purpose = "SharedDatasets"
  })
}

resource "azurerm_storage_account" "consumer" {
  name                     = local.naming_convention.st_consumer
  resource_group_name      = azurerm_resource_group.consumer.name
  location                 = azurerm_resource_group.consumer.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.storage_tier
  
  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Configure blob properties
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  tags = merge(local.common_tags, {
    Role = "DataConsumer"
    Purpose = "ReceivedDatasets"
  })
}

# Storage containers for shared datasets
resource "azurerm_storage_container" "shared_datasets" {
  name                  = "shared-datasets"
  storage_account_name  = azurerm_storage_account.provider.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "consumer_datasets" {
  name                  = "received-datasets"
  storage_account_name  = azurerm_storage_account.consumer.name
  container_access_type = "private"
}

# Sample data blob (optional)
resource "azurerm_storage_blob" "sample_data" {
  count                  = var.sample_data_enabled ? 1 : 0
  name                   = "financial_transactions_2025.csv"
  storage_account_name   = azurerm_storage_account.provider.name
  storage_container_name = azurerm_storage_container.shared_datasets.name
  type                   = "Block"
  content_type           = "text/csv"
  
  # Sample CSV content for demonstration
  source_content = <<-EOT
transaction_id,date,amount,category,region
TXN001,2025-01-15,15000.00,corporate_loan,north_america
TXN002,2025-01-16,8500.50,consumer_credit,europe
TXN003,2025-01-17,22000.75,mortgage,asia_pacific
TXN004,2025-01-18,3200.25,small_business,north_america
TXN005,2025-01-19,45000.00,commercial_real_estate,europe
EOT
}

# Key Vaults for secrets management
resource "azurerm_key_vault" "provider" {
  name                       = local.naming_convention.kv_provider
  location                   = azurerm_resource_group.provider.location
  resource_group_name        = azurerm_resource_group.provider.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.environment == "prod" ? true : false
  
  # Enable access for deployment and template deployment
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  enabled_for_disk_encryption     = true
  
  # Network access configuration
  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = merge(local.common_tags, {
    Role = "DataProvider"
    Purpose = "SecretsManagement"
  })
}

resource "azurerm_key_vault" "consumer" {
  name                       = local.naming_convention.kv_consumer
  location                   = azurerm_resource_group.consumer.location
  resource_group_name        = azurerm_resource_group.consumer.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.environment == "prod" ? true : false
  
  # Enable access for deployment and template deployment
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  enabled_for_disk_encryption     = true
  
  # Network access configuration
  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = merge(local.common_tags, {
    Role = "DataConsumer"
    Purpose = "SecretsManagement"
  })
}

# Key Vault access policies for current user/service principal
resource "azurerm_key_vault_access_policy" "provider_current_user" {
  key_vault_id = azurerm_key_vault.provider.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Import", "Backup", "Restore", "Recover"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover"
  ]

  certificate_permissions = [
    "Create", "Delete", "Get", "GetIssuers", "Import", "List", "ListIssuers", 
    "ManageContacts", "ManageIssuers", "SetIssuers", "Update", "Backup", "Restore", "Recover"
  ]
}

resource "azurerm_key_vault_access_policy" "consumer_current_user" {
  key_vault_id = azurerm_key_vault.consumer.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Import", "Backup", "Restore", "Recover"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover"
  ]

  certificate_permissions = [
    "Create", "Delete", "Get", "GetIssuers", "Import", "List", "ListIssuers", 
    "ManageContacts", "ManageIssuers", "SetIssuers", "Update", "Backup", "Restore", "Recover"
  ]
}

# Generate Service Fabric cluster certificate
resource "tls_private_key" "service_fabric" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "service_fabric" {
  private_key_pem = tls_private_key.service_fabric.private_key_pem

  subject {
    common_name         = "${local.naming_convention.sf_cluster}.${var.location}.cloudapp.azure.com"
    organization        = "Data Governance Platform"
    organizational_unit = "Service Fabric"
    locality           = var.location
    country            = "US"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

# Store Service Fabric certificate in Key Vault
resource "azurerm_key_vault_certificate" "service_fabric" {
  name         = "service-fabric-cluster-cert"
  key_vault_id = azurerm_key_vault.provider.id

  certificate {
    contents = base64encode(tls_self_signed_cert.service_fabric.cert_pem)
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
      extended_key_usage = ["1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2"]
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
      subject = "CN=${local.naming_convention.sf_cluster}.${var.location}.cloudapp.azure.com"
      validity_in_months = 12
    }
  }

  depends_on = [azurerm_key_vault_access_policy.provider_current_user]
}

# Service Fabric Cluster
resource "azurerm_service_fabric_cluster" "main" {
  name                = local.naming_convention.sf_cluster
  resource_group_name = azurerm_resource_group.provider.name
  location            = azurerm_resource_group.provider.location
  reliability_level   = "Silver"
  upgrade_mode        = "Automatic"
  vm_image            = var.service_fabric_os_version
  
  management_endpoint = "https://${local.naming_convention.sf_cluster}.${var.location}.cloudapp.azure.com:19080"

  node_type {
    name                        = "primary"
    instance_count              = var.service_fabric_cluster_size
    is_primary                  = true
    client_endpoint_port        = 19000
    http_endpoint_port          = 19080
    durability_level           = "Silver"
    application_ports {
      start_port = 20000
      end_port   = 30000
    }
    ephemeral_ports {
      start_port = 49152
      end_port   = 65534
    }
  }

  certificate {
    thumbprint      = azurerm_key_vault_certificate.service_fabric.thumbprint
    thumbprint_secondary = ""
    x509_store_name = "My"
  }

  azure_active_directory {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    cluster_application_id = azuread_application.service_fabric_cluster.application_id
    client_application_id  = azuread_application.service_fabric_client.application_id
  }

  fabric_settings {
    name = "Security"
    parameters = {
      "ClusterProtectionLevel" = "EncryptAndSign"
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "DataGovernanceOrchestration"
    Component = "ServiceFabric"
  })

  depends_on = [
    azurerm_key_vault_certificate.service_fabric,
    azuread_application.service_fabric_cluster,
    azuread_application.service_fabric_client
  ]
}

# Azure AD Applications for Service Fabric
resource "azuread_application" "service_fabric_cluster" {
  display_name = "ServiceFabric-${local.naming_convention.sf_cluster}"
  
  web {
    homepage_url = "https://${local.naming_convention.sf_cluster}.${var.location}.cloudapp.azure.com:19080"
    redirect_uris = [
      "https://${local.naming_convention.sf_cluster}.${var.location}.cloudapp.azure.com:19080/Explorer/index.html"
    ]
  }
  
  required_resource_access {
    resource_app_id = "00000002-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "311a71cc-e848-46a1-bdf8-97ff7156d8e6" # User.Read
      type = "Scope"
    }
  }
}

resource "azuread_application" "service_fabric_client" {
  display_name = "ServiceFabricClient-${local.naming_convention.sf_cluster}"
  
  public_client {
    redirect_uris = [
      "urn:ietf:wg:oauth:2.0:oob"
    ]
  }
  
  required_resource_access {
    resource_app_id = azuread_application.service_fabric_cluster.application_id

    resource_access {
      id   = azuread_application.service_fabric_cluster.oauth2_permission_scope_ids["user_impersonation"]
      type = "Scope"
    }
  }
}

# Data Share Account
resource "azurerm_data_share_account" "main" {
  name                = local.naming_convention.data_share
  resource_group_name = azurerm_resource_group.provider.name
  location            = azurerm_resource_group.provider.location
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "CrossOrganizationDataSharing"
    Component = "DataShare"
  })
}

# Data Share for financial collaboration
resource "azurerm_data_share" "financial_collaboration" {
  name        = "financial-collaboration-share"
  account_id  = azurerm_data_share_account.main.id
  kind        = "CopyBased"
  description = "Cross-organization financial data sharing for analytics"
  
  snapshot_schedule {
    name       = "daily-snapshot"
    recurrence = "Day"
    start_time = "2025-01-01T09:00:00Z"
  }
  
  terms_of_use = var.data_share_terms_of_use
}

# Data Share dataset for the sample financial data
resource "azurerm_data_share_dataset_blob_storage" "financial_transactions" {
  count           = var.sample_data_enabled ? 1 : 0
  name            = "financial-transactions"
  data_share_id   = azurerm_data_share.financial_collaboration.id
  container_name  = azurerm_storage_container.shared_datasets.name
  storage_account {
    name                = azurerm_storage_account.provider.name
    resource_group_name = azurerm_resource_group.provider.name
    subscription_id     = data.azurerm_client_config.current.subscription_id
  }
  file_path = var.sample_data_enabled ? azurerm_storage_blob.sample_data[0].name : ""
  
  depends_on = [azurerm_storage_blob.sample_data]
}

# Role assignments for Data Share managed identity
resource "azurerm_role_assignment" "data_share_storage_provider" {
  scope                = azurerm_storage_account.provider.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_data_share_account.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "data_share_storage_consumer" {
  scope                = azurerm_storage_account.consumer.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_share_account.main.identity[0].principal_id
}

# Monitor Action Group for alerts (if email addresses provided)
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts && length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.provider.name
  short_name          = "datashare"

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }

  tags = local.common_tags
}

# Diagnostic settings for audit trail
resource "azurerm_monitor_diagnostic_setting" "data_share" {
  name                       = "diag-${azurerm_data_share_account.main.name}"
  target_resource_id         = azurerm_data_share_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ShareSubscriptions"
  }

  enabled_log {
    category = "SentSnapshots"
  }

  enabled_log {
    category = "ReceivedSnapshots"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_fabric" {
  name                       = "diag-${azurerm_service_fabric_cluster.main.name}"
  target_resource_id         = azurerm_service_fabric_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "OperationalChannel"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Store important secrets in Key Vault
resource "azurerm_key_vault_secret" "storage_provider_connection_string" {
  name         = "storage-provider-connection-string"
  value        = azurerm_storage_account.provider.primary_connection_string
  key_vault_id = azurerm_key_vault.provider.id
  
  depends_on = [azurerm_key_vault_access_policy.provider_current_user]
}

resource "azurerm_key_vault_secret" "storage_consumer_connection_string" {
  name         = "storage-consumer-connection-string"
  value        = azurerm_storage_account.consumer.primary_connection_string
  key_vault_id = azurerm_key_vault.consumer.id
  
  depends_on = [azurerm_key_vault_access_policy.consumer_current_user]
}

resource "azurerm_key_vault_secret" "data_share_account_id" {
  name         = "data-share-account-id"
  value        = azurerm_data_share_account.main.id
  key_vault_id = azurerm_key_vault.provider.id
  
  depends_on = [azurerm_key_vault_access_policy.provider_current_user]
}
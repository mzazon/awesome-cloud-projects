# Azure Healthcare Chatbot Infrastructure - Main Configuration
# This Terraform configuration deploys a complete healthcare chatbot solution
# using Azure Health Bot, Azure Personalizer, and supporting services

# Data sources for current configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate secure password for SQL Managed Instance if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_admin_password == null ? 1 : 0
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Local values for common configurations
locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # SQL Admin Password - use provided or generated
  sql_admin_password = var.sql_admin_password != null ? var.sql_admin_password : random_password.sql_admin_password[0].result
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment       = var.environment
    Project          = var.project_name
    Organization     = var.organization_name
    Purpose          = "healthcare-chatbot"
    Compliance       = var.enable_hipaa_compliance ? "hipaa" : "standard"
    DataClassification = var.data_classification
    ManagedBy        = "terraform"
    CreatedDate      = formatdate("YYYY-MM-DD", timestamp())
  }, var.additional_tags)
}

# Resource Group for all healthcare chatbot resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}-${local.name_suffix}"
  location = var.location
  
  tags = local.common_tags
}

# Virtual Network for SQL Managed Instance and private endpoints
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.name_prefix}-${local.name_suffix}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Subnet for SQL Managed Instance with delegation
resource "azurerm_subnet" "sql_mi" {
  name                 = "subnet-sqlmi-${local.name_suffix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
  
  delegation {
    name = "sql-managed-instance-delegation"
    
    service_delegation {
      name    = "Microsoft.Sql/managedInstances"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

# Network Security Group for SQL Managed Instance subnet
resource "azurerm_network_security_group" "sql_mi" {
  name                = "nsg-sqlmi-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Inbound rules for SQL Managed Instance
  security_rule {
    name                       = "allow_management_inbound"
    priority                   = 106
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["9000", "9003", "1438", "1440", "1452"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "allow_health_probe_inbound"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  
  # Outbound rules for SQL Managed Instance
  security_rule {
    name                       = "allow_management_outbound"
    priority                   = 102
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "12000"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Associate NSG with SQL MI subnet
resource "azurerm_subnet_network_security_group_association" "sql_mi" {
  subnet_id                 = azurerm_subnet.sql_mi.id
  network_security_group_id = azurerm_network_security_group.sql_mi.id
}

# Route table for SQL Managed Instance
resource "azurerm_route_table" "sql_mi" {
  name                = "rt-sqlmi-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Associate route table with SQL MI subnet
resource "azurerm_subnet_route_table_association" "sql_mi" {
  subnet_id      = azurerm_subnet.sql_mi.id
  route_table_id = azurerm_route_table.sql_mi.id
}

# Key Vault for secure credential storage
resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.name_prefix}-${local.name_suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.environment == "prod" ? true : false
  
  # RBAC-based access control for enhanced security
  enable_rbac_authorization = true
  
  # Network access configuration
  dynamic "network_acls" {
    for_each = var.enable_private_endpoints ? [1] : []
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = local.common_tags
}

# Store SQL admin password in Key Vault
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = local.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
  
  tags = local.common_tags
}

# Azure Health Bot instance
resource "azurerm_healthbot" "main" {
  name                = "healthbot-${local.name_prefix}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = var.health_bot_sku
  
  tags = local.common_tags
}

# Cognitive Services account for Personalizer
resource "azurerm_cognitive_account" "personalizer" {
  name                = "personalizer-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "Personalizer"
  sku_name            = var.personalizer_sku
  
  # Custom subdomain for enhanced security
  custom_question_answering_search_service_id = null
  custom_subdomain_name                       = "personalizer-${local.name_prefix}-${local.name_suffix}"
  
  # Network access configuration
  dynamic "network_acls" {
    for_each = var.enable_private_endpoints ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = local.common_tags
}

# Store Personalizer key in Key Vault
resource "azurerm_key_vault_secret" "personalizer_key" {
  name         = "personalizer-key"
  value        = azurerm_cognitive_account.personalizer.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
  
  tags = local.common_tags
}

# SQL Managed Instance for patient data storage
resource "azurerm_mssql_managed_instance" "main" {
  name                = "sqlmi-${local.name_prefix}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Authentication configuration
  administrator_login          = var.sql_admin_username
  administrator_login_password = local.sql_admin_password
  
  # Network configuration
  subnet_id = azurerm_subnet.sql_mi.id
  
  # Compute configuration
  sku_name = var.sql_sku_name
  vcores   = var.sql_vcores
  
  # Storage configuration
  storage_size_in_gb = var.sql_storage_size_gb
  
  # Security configuration for healthcare compliance
  minimum_tls_version = "1.2"
  
  # Identity configuration for Azure AD integration
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # This resource takes a long time to create (4-6 hours)
  timeouts {
    create = "6h"
    update = "6h"
    delete = "6h"
  }
  
  depends_on = [
    azurerm_subnet_network_security_group_association.sql_mi,
    azurerm_subnet_route_table_association.sql_mi
  ]
}

# Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "function_app" {
  name                     = "st${replace(local.name_prefix, "-", "")}${local.name_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security configuration for healthcare compliance
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "sp-${local.name_prefix}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Windows"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for integration logic
resource "azurerm_windows_function_app" "main" {
  name                = "func-${local.name_prefix}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.function_app.name
  storage_account_access_key = azurerm_storage_account.function_app.primary_access_key
  service_plan_id            = azurerm_service_plan.function_app.id
  
  # Runtime configuration
  site_config {
    application_stack {
      dotnet_version = "v6.0"
    }
    
    # CORS configuration for web clients
    cors {
      allowed_origins = ["*"]
    }
    
    # Enhanced security
    ftps_state        = "Disabled"
    http2_enabled     = true
    minimum_tls_version = "1.2"
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
    "PersonalizerEndpoint"         = azurerm_cognitive_account.personalizer.endpoint
    "PersonalizerKey"              = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=personalizer-key)"
    "SqlConnectionString"          = "Server=${azurerm_mssql_managed_instance.main.fqdn};Database=HealthBotDB;User Id=${var.sql_admin_username};Password=@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=sql-admin-password);Encrypt=true;TrustServerCertificate=false;"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : ""
  }
  
  # Managed identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_key_vault_secret.personalizer_key,
    azurerm_key_vault_secret.sql_admin_password
  ]
}

# API Management service for secure API gateway
resource "azurerm_api_management" "main" {
  name                = "apim-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name
  
  # Managed identity for secure access to other resources
  identity {
    type = "SystemAssigned"
  }
  
  # Security policy configuration
  policy {
    xml_content = <<XML
<policies>
  <inbound>
    <rate-limit calls="100" renewal-period="60" />
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
      </allowed-methods>
    </cors>
    <set-header name="X-Healthcare-Disclaimer" exists-action="override">
      <value>This chatbot provides general information only. Consult healthcare professionals for medical advice.</value>
    </set-header>
  </inbound>
  <outbound>
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
  </outbound>
</policies>
XML
  }
  
  tags = local.common_tags
  
  # APIM can take significant time to deploy
  timeouts {
    create = "3h"
    update = "3h"
    delete = "3h"
  }
}

# Key Vault access policy for Function App
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_function_app.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Key Vault access policy for API Management
resource "azurerm_key_vault_access_policy" "apim" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_api_management.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Private endpoint for Key Vault (if enabled)
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-kv-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.sql_mi.id
  
  private_service_connection {
    name                           = "psc-kv-${local.name_prefix}-${local.name_suffix}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

# Private endpoint for Personalizer (if enabled)
resource "azurerm_private_endpoint" "personalizer" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-personalizer-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.sql_mi.id
  
  private_service_connection {
    name                           = "psc-personalizer-${local.name_prefix}-${local.name_suffix}"
    private_connection_resource_id = azurerm_cognitive_account.personalizer.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}
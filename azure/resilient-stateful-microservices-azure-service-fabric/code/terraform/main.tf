# Main Terraform configuration for Azure Stateful Microservices Orchestration
# This configuration deploys Service Fabric cluster, Durable Functions, and supporting infrastructure

# Data sources for current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate random password for Service Fabric admin if not provided
resource "random_password" "service_fabric_admin_password" {
  count   = var.service_fabric_admin_password == "" ? 1 : 0
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Generate random password for SQL admin if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_admin_password == "" ? 1 : 0
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Local values for resource naming and configuration
locals {
  # Resource naming with consistent prefix and suffix
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # Computed resource names
  service_fabric_cluster_name     = var.service_fabric_cluster_name != "" ? var.service_fabric_cluster_name : "${local.name_prefix}-sf-${local.name_suffix}"
  sql_server_name                 = var.sql_server_name != "" ? var.sql_server_name : "${local.name_prefix}-sql-${local.name_suffix}"
  function_app_name               = var.function_app_name != "" ? var.function_app_name : "${local.name_prefix}-func-${local.name_suffix}"
  storage_account_name            = var.storage_account_name != "" ? var.storage_account_name : "${replace(local.name_prefix, "-", "")}st${local.name_suffix}"
  application_insights_name       = var.application_insights_name != "" ? var.application_insights_name : "${local.name_prefix}-ai-${local.name_suffix}"
  log_analytics_workspace_name    = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "${local.name_prefix}-law-${local.name_suffix}"
  key_vault_name                  = var.key_vault_name != "" ? var.key_vault_name : "${local.name_prefix}-kv-${local.name_suffix}"
  
  # Password resolution
  service_fabric_admin_password = var.service_fabric_admin_password != "" ? var.service_fabric_admin_password : random_password.service_fabric_admin_password[0].result
  sql_admin_password           = var.sql_admin_password != "" ? var.sql_admin_password : random_password.sql_admin_password[0].result
  
  # Combined tags
  common_tags = merge(var.common_tags, var.additional_tags, {
    CreatedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  
  tags = local.common_tags
}

# Key Vault for secure storage of secrets and certificates
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = var.key_vault_sku
  
  # Enable soft delete and purge protection for production use
  soft_delete_retention_days = var.enable_key_vault_soft_delete ? 7 : null
  purge_protection_enabled   = var.enable_key_vault_soft_delete
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    certificate_permissions = [
      "Backup", "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers",
      "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers",
      "Purge", "Recover", "Restore", "SetIssuers", "Update"
    ]
    
    key_permissions = [
      "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import",
      "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update",
      "Verify", "WrapKey"
    ]
    
    secret_permissions = [
      "Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"
    ]
  }
  
  tags = local.common_tags
}

# Virtual Network for Service Fabric cluster
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Subnet for Service Fabric cluster
resource "azurerm_subnet" "service_fabric" {
  name                 = "service-fabric-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.service_fabric_subnet_address_prefix]
}

# Subnet for Function App VNet integration
resource "azurerm_subnet" "function_app" {
  name                 = "function-app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.function_app_subnet_address_prefix]
  
  delegation {
    name = "function-app-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

# Network Security Group for Service Fabric
resource "azurerm_network_security_group" "service_fabric" {
  name                = "${local.name_prefix}-sf-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Service Fabric management endpoint
  security_rule {
    name                       = "ServiceFabricManagement"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "19080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Service Fabric client endpoint
  security_rule {
    name                       = "ServiceFabricClient"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "19000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # HTTP endpoint for applications
  security_rule {
    name                       = "HTTP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # HTTPS endpoint for applications
  security_rule {
    name                       = "HTTPS"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Application ports
  security_rule {
    name                       = "ApplicationPorts"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080-8090"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Associate NSG with Service Fabric subnet
resource "azurerm_subnet_network_security_group_association" "service_fabric" {
  subnet_id                 = azurerm_subnet.service_fabric.id
  network_security_group_id = azurerm_network_security_group.service_fabric.id
}

# Self-signed certificate for Service Fabric cluster
resource "azurerm_key_vault_certificate" "service_fabric" {
  name         = "service-fabric-cluster-cert"
  key_vault_id = azurerm_key_vault.main.id
  
  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    
    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }
    
    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      
      trigger {
        days_before_expiry = 30
      }
    }
    
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    
    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
      
      subject            = "CN=${local.service_fabric_cluster_name}.${var.location}.cloudapp.azure.com"
      validity_in_months = 12
      
      subject_alternative_names {
        dns_names = [
          "${local.service_fabric_cluster_name}.${var.location}.cloudapp.azure.com"
        ]
      }
    }
  }
  
  tags = local.common_tags
}

# Service Fabric Cluster
resource "azurerm_service_fabric_cluster" "main" {
  name                = local.service_fabric_cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  reliability_level   = var.service_fabric_reliability_level
  upgrade_mode        = var.service_fabric_upgrade_mode
  vm_image            = "Windows"
  
  # Management endpoint
  management_endpoint = "https://${local.service_fabric_cluster_name}.${var.location}.cloudapp.azure.com:19080"
  
  # Node type configuration
  node_type {
    name                        = "primary"
    instance_count              = var.service_fabric_node_count
    is_primary                  = true
    client_endpoint_port        = 19000
    http_endpoint_port          = 19080
    durability_level            = var.service_fabric_durability_level
    application_ports_start     = 8080
    application_ports_end       = 8090
    ephemeral_ports_start       = 49152
    ephemeral_ports_end         = 65534
    
    placement_properties = {
      "NodeType" = "primary"
    }
  }
  
  # Certificate configuration
  certificate {
    thumbprint      = azurerm_key_vault_certificate.service_fabric.thumbprint
    x509_store_name = "My"
  }
  
  # Fabric settings for monitoring integration
  fabric_settings {
    name = "Setup"
    parameters = {
      "FabricDataRoot"        = "C:\\\\SvcFab"
      "FabricLogRoot"         = "C:\\\\SvcFab\\\\Log"
      "ServiceRunAsAccountName" = "NT AUTHORITY\\NetworkService"
      "ServiceRunAsAccountType" = "NetworkService"
    }
  }
  
  dynamic "fabric_settings" {
    for_each = var.enable_service_fabric_monitoring ? [1] : []
    content {
      name = "ApplicationInsights"
      parameters = {
        "InstrumentationKey" = azurerm_application_insights.main.instrumentation_key
      }
    }
  }
  
  tags = local.common_tags
}

# SQL Server for state management
resource "azurerm_mssql_server" "main" {
  name                         = local.sql_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = local.sql_admin_password
  
  # Security configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Azure AD authentication
  azuread_administrator {
    login_username = "sqladmin"
    object_id      = data.azurerm_client_config.current.object_id
  }
  
  tags = local.common_tags
}

# SQL Database for microservices state
resource "azurerm_mssql_database" "main" {
  name           = var.sql_database_name
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb    = var.sql_database_max_size_gb
  sku_name       = var.sql_database_sku
  
  # Backup configuration
  short_term_retention_policy {
    retention_days = 7
  }
  
  long_term_retention_policy {
    weekly_retention  = "P1W"
    monthly_retention = "P1M"
    yearly_retention  = "P1Y"
    week_of_year      = 1
  }
  
  tags = local.common_tags
}

# SQL Server firewall rule to allow Azure services
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Advanced Threat Protection for SQL Database
resource "azurerm_mssql_server_security_alert_policy" "main" {
  count                      = var.enable_sql_threat_detection ? 1 : 0
  resource_group_name        = azurerm_resource_group.main.name
  server_name                = azurerm_mssql_server.main.name
  state                      = "Enabled"
  storage_endpoint           = azurerm_storage_account.main.primary_blob_endpoint
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  disabled_alerts = []
  
  retention_days = 30
  
  email_account_admins = true
}

# Storage Account for Function App and audit logs
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configuration
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = var.enable_public_network_access
  
  # Enable blob encryption
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# App Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "${local.name_prefix}-func-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  os_type  = "Windows"
  sku_name = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for Durable Functions orchestration
resource "azurerm_windows_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.function_app.id
  
  # Runtime configuration
  site_config {
    application_stack {
      dotnet_version = var.function_app_dotnet_version
    }
    
    # Enable Application Insights
    application_insights_key = azurerm_application_insights.main.instrumentation_key
    
    # Security configuration
    ftps_state = "Disabled"
    
    # CORS configuration for development
    cors {
      allowed_origins = ["*"]
    }
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
    "FUNCTIONS_EXTENSION_VERSION"  = var.function_app_runtime_version
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Connection strings for microservices integration
    "SqlConnectionString" = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.main.name};User ID=${var.sql_admin_login};Password=${local.sql_admin_password};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
    "ServiceFabricConnectionString" = "https://${azurerm_service_fabric_cluster.main.management_endpoint}"
    
    # Durable Functions configuration
    "AzureWebJobsStorage" = azurerm_storage_account.main.primary_connection_string
    "AzureWebJobsDashboard" = azurerm_storage_account.main.primary_connection_string
  }
  
  # VNet integration
  virtual_network_subnet_id = azurerm_subnet.function_app.id
  
  tags = local.common_tags
}

# Store sensitive configuration in Key Vault
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.main.name};User ID=${var.sql_admin_login};Password=${local.sql_admin_password};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "service_fabric_admin_password" {
  name         = "service-fabric-admin-password"
  value        = local.service_fabric_admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = local.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
}

# Diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "service_fabric" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "service-fabric-diagnostics"
  target_resource_id         = azurerm_service_fabric_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "OperationalChannel"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "sql_database" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "sql-database-diagnostics"
  target_resource_id         = azurerm_mssql_database.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "SQLInsights"
  }
  
  enabled_log {
    category = "AutomaticTuning"
  }
  
  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }
  
  enabled_log {
    category = "QueryStoreWaitStatistics"
  }
  
  enabled_log {
    category = "Errors"
  }
  
  enabled_log {
    category = "DatabaseWaitStatistics"
  }
  
  enabled_log {
    category = "Timeouts"
  }
  
  enabled_log {
    category = "Blocks"
  }
  
  enabled_log {
    category = "Deadlocks"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_windows_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "main" {
  name                = "${local.name_prefix}-action-group"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "AlertGroup"
  
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
  }
  
  tags = local.common_tags
}

# Metric alert for order processing failures
resource "azurerm_monitor_metric_alert" "order_processing_failures" {
  name                = "order-processing-failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when order processing failures exceed threshold"
  
  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "customEvents/count"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
    
    dimension {
      name     = "customEvent/name"
      operator = "Include"
      values   = ["OrderProcessingFailure"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  
  tags = local.common_tags
}
# Main Terraform configuration for Azure Service Discovery with Service Connector and Azure Tables

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Local values for resource naming and configuration
locals {
  # Generate unique resource names using project name, environment, and random suffix
  resource_suffix      = "${var.environment}-${random_string.suffix.result}"
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${local.resource_suffix}"
  storage_account_name = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  function_app_name    = "func-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name = "plan-${var.project_name}-${local.resource_suffix}"
  web_app_name         = "app-${var.project_name}-${local.resource_suffix}"
  sql_server_name      = "sql-${var.project_name}-${local.resource_suffix}"
  redis_cache_name     = "redis-${var.project_name}-${local.resource_suffix}"
  
  # Merge default tags with user-provided tags
  common_tags = merge(var.tags, {
    DeployedBy    = "terraform"
    ResourceGroup = local.resource_group_name
    Location      = var.location
  })
  
  # SQL Server admin password - generate if not provided
  sql_admin_password = var.sql_server_admin_password != null ? var.sql_server_admin_password : random_password.sql_admin_password[0].result
}

# Generate SQL admin password if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_server_admin_password == null ? 1 : 0
  length  = 16
  special = true
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for Azure Tables and Function Apps
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable minimum TLS version for security
  min_tls_version = "TLS1_2"
  
  # Enable secure transfer
  enable_https_traffic_only = true
  
  # Configure blob properties for security
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create Azure Tables for Service Registry
resource "azurerm_storage_table" "service_registry" {
  count                = length(var.service_registry_tables)
  name                 = var.service_registry_tables[count.index]
  storage_account_name = azurerm_storage_account.main.name
}

# Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = local.common_tags
}

# Create App Service Plan for Function Apps and Web Apps
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  
  tags = local.common_tags
}

# Create Function App for health monitoring and service registration
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Configure Function App settings
  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"       = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"   = var.function_app_runtime_version
    "STORAGE_CONNECTION_STRING"      = azurerm_storage_account.main.primary_connection_string
    "HEALTH_CHECK_INTERVAL_MINUTES"  = var.health_check_interval
    "ENABLE_LOGGING"                 = var.enable_logging
  }, var.enable_monitoring ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  site_config {
    # Configure runtime settings
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
    }
    
    # Enable CORS for service discovery API
    cors {
      allowed_origins = var.allowed_origins
    }
    
    # Enable detailed error logging
    detailed_error_logging_enabled = var.enable_logging
    http_logs_enabled             = var.enable_logging
  }
  
  # Configure identity for Service Connector
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Web App for service discovery demonstration
resource "azurerm_linux_web_app" "main" {
  name                = local.web_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Configure web app settings
  app_settings = merge({
    "STORAGE_CONNECTION_STRING"      = azurerm_storage_account.main.primary_connection_string
    "FUNCTION_APP_URL"               = "https://${azurerm_linux_function_app.main.default_hostname}"
    "SERVICE_DISCOVERY_ENABLED"      = "true"
  }, var.enable_monitoring ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  site_config {
    # Configure runtime stack
    application_stack {
      node_version = "18-lts"
    }
    
    # Enable detailed error logging
    detailed_error_logging_enabled = var.enable_logging
    http_logs_enabled             = var.enable_logging
  }
  
  # Configure identity for Service Connector
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Azure SQL Server for target service
resource "azurerm_mssql_server" "main" {
  name                         = local.sql_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_server_admin_username
  administrator_login_password = local.sql_admin_password
  
  # Security configurations
  minimum_tls_version = "1.2"
  
  # Configure Azure AD authentication
  azuread_administrator {
    login_username = "sqladmin"
    object_id      = data.azurerm_client_config.current.object_id
  }
  
  tags = local.common_tags
}

# Create Azure SQL Database
resource "azurerm_mssql_database" "main" {
  name         = "ServiceRegistry"
  server_id    = azurerm_mssql_server.main.id
  sku_name     = var.sql_database_sku
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  
  # Configure backup and retention
  short_term_retention_policy {
    retention_days = 7
  }
  
  tags = local.common_tags
}

# Create SQL Server firewall rule for Azure services
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create Azure Cache for Redis
resource "azurerm_redis_cache" "main" {
  name                = local.redis_cache_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = var.redis_sku_capacity
  family              = var.redis_sku_family
  sku_name            = var.redis_sku_name
  
  # Security configurations
  minimum_tls_version = "1.2"
  
  # Enable non-SSL port only for development
  enable_non_ssl_port = var.environment == "dev"
  
  # Configure Redis settings
  redis_configuration {
    enable_authentication = true
  }
  
  tags = local.common_tags
}

# Create Service Bus Namespace for messaging
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  
  tags = local.common_tags
}

# Create Service Bus Queue
resource "azurerm_servicebus_queue" "main" {
  name         = "service-discovery-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Configure queue properties
  enable_partitioning = false
  max_delivery_count  = 10
  
  # Message TTL settings
  default_message_ttl = "P14D" # 14 days
}

# Create Key Vault for secure configuration storage
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Security configurations
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false
  enable_rbac_authorization       = true
  purge_protection_enabled        = false
  
  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = local.common_tags
}

# Assign Key Vault access to Function App
resource "azurerm_role_assignment" "function_app_kv_access" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Assign Key Vault access to Web App
resource "azurerm_role_assignment" "web_app_kv_access" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Store SQL connection string in Key Vault
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.sql_server_admin_username};Password=${local.sql_admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_kv_access]
}

# Store Redis connection string in Key Vault
resource "azurerm_key_vault_secret" "redis_connection_string" {
  name         = "redis-connection-string"
  value        = "${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port},password=${azurerm_redis_cache.main.primary_access_key},ssl=True,abortConnect=False"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_kv_access]
}

# Store Service Bus connection string in Key Vault
resource "azurerm_key_vault_secret" "servicebus_connection_string" {
  name         = "servicebus-connection-string"
  value        = azurerm_servicebus_namespace.main.default_primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_kv_access]
}

# Service Connector: Function App to Storage Tables
resource "azurerm_app_service_connection" "function_to_storage" {
  name               = "StorageConnection"
  app_service_id     = azurerm_linux_function_app.main.id
  target_resource_id = azurerm_storage_account.main.id
  
  authentication {
    type = "systemAssignedIdentity"
  }
  
  depends_on = [azurerm_linux_function_app.main]
}

# Service Connector: Web App to Storage Tables
resource "azurerm_app_service_connection" "webapp_to_storage" {
  name               = "ServiceRegistryConnection"
  app_service_id     = azurerm_linux_web_app.main.id
  target_resource_id = azurerm_storage_account.main.id
  
  authentication {
    type = "systemAssignedIdentity"
  }
  
  depends_on = [azurerm_linux_web_app.main]
}

# Service Connector: Web App to SQL Database
resource "azurerm_app_service_connection" "webapp_to_sql" {
  name               = "DatabaseConnection"
  app_service_id     = azurerm_linux_web_app.main.id
  target_resource_id = azurerm_mssql_database.main.id
  
  authentication {
    type   = "secret"
    name   = var.sql_server_admin_username
    secret = local.sql_admin_password
  }
  
  depends_on = [azurerm_linux_web_app.main, azurerm_mssql_database.main]
}

# Service Connector: Web App to Redis Cache
resource "azurerm_app_service_connection" "webapp_to_redis" {
  name               = "CacheConnection"
  app_service_id     = azurerm_linux_web_app.main.id
  target_resource_id = azurerm_redis_cache.main.id
  
  authentication {
    type   = "secret"
    secret = azurerm_redis_cache.main.primary_access_key
  }
  
  depends_on = [azurerm_linux_web_app.main, azurerm_redis_cache.main]
}

# Service Connector: Web App to Service Bus
resource "azurerm_app_service_connection" "webapp_to_servicebus" {
  name               = "ServiceBusConnection"
  app_service_id     = azurerm_linux_web_app.main.id
  target_resource_id = azurerm_servicebus_namespace.main.id
  
  authentication {
    type = "systemAssignedIdentity"
  }
  
  depends_on = [azurerm_linux_web_app.main, azurerm_servicebus_namespace.main]
}

# Service Connector: Function App to Key Vault
resource "azurerm_app_service_connection" "function_to_keyvault" {
  name               = "KeyVaultConnection"
  app_service_id     = azurerm_linux_function_app.main.id
  target_resource_id = azurerm_key_vault.main.id
  
  authentication {
    type = "systemAssignedIdentity"
  }
  
  depends_on = [azurerm_linux_function_app.main, azurerm_key_vault.main]
}

# Role assignment for Storage Table access (Function App)
resource "azurerm_role_assignment" "function_storage_table_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role assignment for Storage Table access (Web App)
resource "azurerm_role_assignment" "webapp_storage_table_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Reader"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Role assignment for Service Bus access (Web App)
resource "azurerm_role_assignment" "webapp_servicebus_access" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}
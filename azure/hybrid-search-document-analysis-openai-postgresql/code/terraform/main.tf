# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Create Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "storage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type

  # Security configuration
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  min_tls_version                = "TLS1_2"

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Function Storage"
  })
}

# Create Document Storage Account
resource "azurerm_storage_account" "document_storage" {
  name                     = "docstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type

  # Security configuration
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  min_tls_version                = "TLS1_2"

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Document Storage"
  })
}

# Create container for documents
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.document_storage.name
  container_access_type = "private"
}

# Create Azure Cognitive Services Account for OpenAI
resource "azurerm_cognitive_account" "openai" {
  name                = "openai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name

  # Custom subdomain is required for OpenAI
  custom_subdomain_name = "openai-${var.project_name}-${random_string.suffix.result}"

  # Network access configuration
  dynamic "network_acls" {
    for_each = var.enable_private_endpoints ? [1] : []
    content {
      default_action = "Deny"
      
      dynamic "ip_rules" {
        for_each = var.allowed_ip_ranges
        content {
          ip_range = ip_rules.value
        }
      }
    }
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "OpenAI Service"
  })
}

# Deploy text embedding model to OpenAI service
resource "azurerm_cognitive_deployment" "text_embedding" {
  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_deployment_model
    version = var.openai_deployment_version
  }

  scale {
    type     = "Standard"
    capacity = var.openai_deployment_capacity
  }

  depends_on = [azurerm_cognitive_account.openai]
}

# Create PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "postgres-${var.project_name}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = var.postgresql_version
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password

  # Server configuration
  sku_name   = var.postgresql_sku_name
  storage_mb = var.postgresql_storage_mb

  # Backup configuration
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # Security configuration
  create_mode = "Default"
  
  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "PostgreSQL Database"
  })
}

# Configure PostgreSQL server parameters for pgvector
resource "azurerm_postgresql_flexible_server_configuration" "pgvector" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "vector"

  depends_on = [azurerm_postgresql_flexible_server.main]
}

# Create PostgreSQL firewall rule for Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"

  depends_on = [azurerm_postgresql_flexible_server.main]
}

# Create additional firewall rules for allowed IP ranges
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  count = length(var.allowed_ip_ranges) > 0 && var.allowed_ip_ranges[0] != "0.0.0.0/0" ? length(var.allowed_ip_ranges) : 0
  
  name             = "allowed-ip-range-${count.index}"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = split("/", var.allowed_ip_ranges[count.index])[0]
  end_ip_address   = split("/", var.allowed_ip_ranges[count.index])[0]

  depends_on = [azurerm_postgresql_flexible_server.main]
}

# Create Azure AI Search Service
resource "azurerm_search_service" "main" {
  name                = "search-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.search_sku

  # Search service configuration
  replica_count   = var.search_replica_count
  partition_count = var.search_partition_count

  # Security configuration
  public_network_access_enabled = !var.enable_private_endpoints

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "AI Search Service"
  })
}

# Create Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Function App Service Plan"
  })
}

# Create Linux Function App
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan.id

  # Enable managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }

  # Runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_version
    }

    # Enable CORS for web applications
    cors {
      allowed_origins = ["*"]
    }

    # Function app settings
    always_on = var.function_app_service_plan_sku != "Y1"
    
    # Security configurations
    ftps_state = "Disabled"
    http2_enabled = true
    minimum_tls_version = "1.2"
  }

  # Application settings with connection strings and configuration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # OpenAI configuration
    "OPENAI_ENDPOINT"              = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"                   = azurerm_cognitive_account.openai.primary_access_key
    
    # PostgreSQL configuration
    "POSTGRES_HOST"                = azurerm_postgresql_flexible_server.main.fqdn
    "POSTGRES_USER"                = var.postgresql_admin_username
    "POSTGRES_PASSWORD"            = var.postgresql_admin_password
    "POSTGRES_DATABASE"            = "postgres"
    "POSTGRES_SSL_MODE"            = "require"
    
    # Azure AI Search configuration
    "SEARCH_ENDPOINT"              = "https://${azurerm_search_service.main.name}.search.windows.net"
    "SEARCH_KEY"                   = azurerm_search_service.main.primary_key
    "SEARCH_INDEX_NAME"            = "documents-index"
    
    # Storage configuration
    "DOCUMENT_STORAGE_CONNECTION"  = azurerm_storage_account.document_storage.primary_connection_string
    "DOCUMENT_CONTAINER_NAME"      = azurerm_storage_container.documents.name
    
    # Application settings
    "ENVIRONMENT"                  = var.environment
    "PROJECT_NAME"                 = var.project_name
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Function App"
  })

  depends_on = [
    azurerm_storage_account.function_storage,
    azurerm_cognitive_account.openai,
    azurerm_postgresql_flexible_server.main,
    azurerm_search_service.main,
    azurerm_storage_account.document_storage
  ]
}

# Create Log Analytics Workspace (if monitoring is enabled)
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Log Analytics"
  })
}

# Create Application Insights (if monitoring is enabled)
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Application Insights"
  })
}

# Update Function App with Application Insights (if monitoring is enabled)
resource "azurerm_linux_function_app" "monitoring_update" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = azurerm_linux_function_app.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan.id

  # Runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_version
    }

    cors {
      allowed_origins = ["*"]
    }

    always_on = var.function_app_service_plan_sku != "Y1"
  }

  # Application settings with monitoring
  app_settings = merge(azurerm_linux_function_app.main.app_settings, {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  })

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Function App with Monitoring"
  })
  
  lifecycle {
    replace_triggered_by = [azurerm_linux_function_app.main]
  }
}

# Create Key Vault for secure storage of secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  sku_name = "standard"

  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Recover", "Purge"
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Purge"
    ]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Key Vault"
  })
}

# Store PostgreSQL connection string in Key Vault
resource "azurerm_key_vault_secret" "postgres_connection" {
  name         = "postgres-connection-string"
  value        = "host=${azurerm_postgresql_flexible_server.main.fqdn} port=5432 dbname=postgres user=${var.postgresql_admin_username} password=${var.postgresql_admin_password} sslmode=require"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_postgresql_flexible_server.main]
}

# Store OpenAI key in Key Vault
resource "azurerm_key_vault_secret" "openai_key" {
  name         = "openai-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_cognitive_account.openai]
}

# Store Search service key in Key Vault
resource "azurerm_key_vault_secret" "search_key" {
  name         = "search-key"
  value        = azurerm_search_service.main.primary_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_search_service.main]
}

# Optional: Create Virtual Network for private endpoints
resource "azurerm_virtual_network" "main" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "vnet-${var.project_name}-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "Virtual Network"
  })
}

# Optional: Create subnet for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                 = "subnet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]

  private_endpoint_network_policies_enabled = false
}

# Optional: Create private endpoint for OpenAI
resource "azurerm_private_endpoint" "openai" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "pe-openai-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "psc-openai-${random_string.suffix.result}"
    private_connection_resource_id = azurerm_cognitive_account.openai.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "OpenAI Private Endpoint"
  })
}
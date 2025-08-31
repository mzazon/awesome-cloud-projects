# Azure Data Collection API with Functions and Cosmos DB
# This Terraform configuration creates a serverless REST API using Azure Functions
# with HTTP triggers and Cosmos DB for data persistence.

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Storage Account for Azure Functions
# Azure Functions requires a storage account for internal operations including
# storing function metadata, managing triggers, and logging
resource "azurerm_storage_account" "functions" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"

  # Enable secure transfer to ensure all data in transit is encrypted
  enable_https_traffic_only = true
  
  # Set minimum TLS version for enhanced security
  min_tls_version = "TLS1_2"

  tags = var.tags
}

# Create Application Insights for monitoring and logging
# Provides comprehensive monitoring, performance tracking, and debugging capabilities
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = var.tags
}

# Create Cosmos DB Account with NoSQL API
# Provides globally distributed, multi-model database capabilities with automatic scaling
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Configure consistency policy for optimal performance and data integrity
  consistency_policy {
    consistency_level       = var.cosmos_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  # Configure geo-replication settings
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Enable automatic failover for high availability
  enable_automatic_failover = false
  
  # Enable multiple write locations for global distribution (optional)
  enable_multiple_write_locations = false

  # Configure backup policy for data protection
  dynamic "backup" {
    for_each = var.enable_backup ? [1] : []
    content {
      type                = "Periodic"
      interval_in_minutes = var.backup_interval_in_minutes
      retention_in_hours  = var.backup_retention_in_hours
      storage_redundancy  = "Local"
    }
  }

  tags = var.tags
}

# Create Cosmos DB SQL Database
# Container for organizing related collections and stored procedures
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = var.cosmos_database_name
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Create Cosmos DB SQL Container for storing records
# Provides schema-flexible document storage with automatic indexing
resource "azurerm_cosmosdb_sql_container" "records" {
  name                   = var.cosmos_container_name
  resource_group_name    = azurerm_resource_group.main.name
  account_name           = azurerm_cosmosdb_account.main.name
  database_name          = azurerm_cosmosdb_sql_database.main.name
  partition_key_path     = "/id"
  partition_key_version  = 1
  throughput             = var.cosmos_throughput

  # Configure automatic indexing for optimal query performance
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  # Configure unique key constraints (optional)
  unique_key {
    paths = ["/id"]
  }
}

# Create Service Plan for Azure Functions
# Defines the pricing tier and compute resources for the Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan for serverless scaling
  
  tags = var.tags
}

# Create Azure Function App
# Serverless compute platform that automatically scales based on demand
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id

  # Configure the Function App runtime stack
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable CORS for API access from web applications
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    
    # Configure security settings
    use_32_bit_worker = false
    ftps_state        = "FtpsOnly"
  }

  # Configure application settings for Cosmos DB integration
  app_settings = {
    # Cosmos DB connection configuration
    "COSMOS_DB_CONNECTION_STRING" = azurerm_cosmosdb_account.main.primary_sql_connection_string
    "COSMOS_DB_DATABASE_NAME"     = azurerm_cosmosdb_sql_database.main.name
    "COSMOS_DB_CONTAINER_NAME"    = azurerm_cosmosdb_sql_container.records.name
    
    # Application Insights configuration for monitoring
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"               = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"            = "~4"
    "AzureWebJobsDisableHomepage"           = "true"
    
    # Enable detailed logging for debugging
    "APPINSIGHTS_SAMPLING_PERCENTAGE" = "100"
  }

  # Configure Function App identity for secure access to Azure resources
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  # Ensure storage account is created before Function App
  depends_on = [
    azurerm_storage_account.functions,
    azurerm_application_insights.main,
    azurerm_cosmosdb_sql_container.records
  ]
}

# Configure network access rules for enhanced security (optional)
# Uncomment to restrict access to specific IP ranges or virtual networks
/*
resource "azurerm_function_app_function" "crud_functions" {
  name            = "dataApi"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "TypeScript"
  
  file {
    name    = "index.ts"
    content = file("${path.module}/function-code/index.ts")
  }
  
  config_json = jsonencode({
    "bindings" = [
      {
        "authLevel" = "anonymous"
        "type"      = "httpTrigger"
        "direction" = "in"
        "name"      = "req"
        "methods"   = ["get", "post", "put", "delete"]
        "route"     = "records/{id?}"
      },
      {
        "type"      = "http"
        "direction" = "out"
        "name"      = "res"
      }
    ]
  })
}
*/

# Role assignment for Function App to access Cosmos DB
# Grants the Function App's managed identity necessary permissions
resource "azurerm_role_assignment" "function_cosmos_access" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}
# Azure Expense Tracker Infrastructure
# This file defines the main infrastructure components for a serverless expense tracking application

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and tagging
locals {
  # Generate unique names for resources if not provided
  resource_group_name   = coalesce(var.resource_group_name, "rg-${var.project_name}-${var.environment}-${random_id.suffix.hex}")
  cosmos_account_name   = coalesce(var.cosmos_db_account_name, "cosmos-${var.project_name}-${random_id.suffix.hex}")
  function_app_name     = coalesce(var.function_app_name, "func-${var.project_name}-${random_id.suffix.hex}")
  storage_account_name  = coalesce(var.storage_account_name, "st${var.project_name}${random_id.suffix.hex}")
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment     = var.environment
      Project         = var.project_name
      ManagedBy      = "Terraform"
      Purpose        = "ExpenseTracker"
      CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
      Recipe         = "simple-expense-tracker-cosmos-functions"
    },
    var.tags
  )
}

# Resource Group - Container for all Azure resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Cosmos DB Account - Serverless NoSQL database for expense storage
resource "azurerm_cosmosdb_account" "expenses" {
  name                = local.cosmos_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Enable serverless capacity mode for cost-effective scaling
  capabilities {
    name = "EnableServerless"
  }

  # Configure consistency level for optimal performance
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_level
    max_interval_in_seconds = var.cosmos_db_consistency_level == "BoundedStaleness" ? 300 : null
    max_staleness_prefix    = var.cosmos_db_consistency_level == "BoundedStaleness" ? 100000 : null
  }

  # Configure geo-location for the primary region
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Security and backup configurations
  automatic_failover_enabled = false
  
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Local"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Cosmos DB SQL Database - Container for expense data
resource "azurerm_cosmosdb_sql_database" "expenses_db" {
  name                = var.cosmos_db_database_name
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.expenses.name
  
  # Serverless databases don't require throughput configuration
}

# Cosmos DB SQL Container - Collection for expense documents
resource "azurerm_cosmosdb_sql_container" "expenses_container" {
  name                  = var.cosmos_db_container_name
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.expenses.name
  database_name         = azurerm_cosmosdb_sql_database.expenses_db.name
  partition_key_path    = "/userId"
  partition_key_version = 1

  # Indexing policy optimized for expense tracking queries
  indexing_policy {
    indexing_mode = "consistent"

    # Include all paths for flexible querying
    included_path {
      path = "/*"
    }

    # Exclude paths that don't need indexing to reduce costs
    excluded_path {
      path = "/\"_etag\"/?"
    }

    # Composite indexes for efficient multi-property queries
    composite_index {
      index {
        path  = "/userId"
        order = "ascending"
      }
      index {
        path  = "/createdAt"
        order = "descending"
      }
    }

    composite_index {
      index {
        path  = "/userId"
        order = "ascending"
      }
      index {
        path  = "/category"
        order = "ascending"
      }
      index {
        path  = "/createdAt"
        order = "descending"
      }
    }
  }

  # Time-to-live policy (disabled by default)
  default_ttl = -1
}

# Storage Account - Required for Azure Functions runtime
resource "azurerm_storage_account" "functions" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"

  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Network access rules
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Service Plan - Consumption plan for serverless Azure Functions
resource "azurerm_service_plan" "functions" {
  name                = "asp-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan SKU

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Application Insights - Monitoring and telemetry for Function App
resource "azurerm_application_insights" "functions" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Cost management configuration
  daily_data_cap_in_gb = var.daily_quota_gb > 0 ? var.daily_quota_gb : null
  
  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Linux Function App - Serverless compute for expense tracking APIs
resource "azurerm_linux_function_app" "expenses" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  service_plan_id            = azurerm_service_plan.functions.id

  # Site configuration for Node.js runtime
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }

    # CORS configuration for client applications
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }

    # Security headers
    use_32_bit_worker = false
    
    # Application Insights integration
    application_insights_key               = var.enable_monitoring ? azurerm_application_insights.functions[0].instrumentation_key : null
    application_insights_connection_string = var.enable_monitoring ? azurerm_application_insights.functions[0].connection_string : null
  }

  # Application settings and environment variables
  app_settings = {
    # Azure Functions runtime configuration
    "FUNCTIONS_EXTENSION_VERSION" = var.functions_extension_version
    "FUNCTIONS_WORKER_RUNTIME"    = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    
    # Cosmos DB connection configuration
    "CosmosDBConnection" = azurerm_cosmosdb_account.expenses.primary_sql_connection_string
    "COSMOS_DB_ENDPOINT" = azurerm_cosmosdb_account.expenses.endpoint
    "COSMOS_DB_DATABASE" = azurerm_cosmosdb_sql_database.expenses_db.name
    "COSMOS_DB_CONTAINER" = azurerm_cosmosdb_sql_container.expenses_container.name
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_monitoring ? azurerm_application_insights.functions[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_monitoring ? azurerm_application_insights.functions[0].connection_string : ""
    
    # Function App specific settings
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
    "ENABLE_ORYX_BUILD" = "false"
  }

  # Identity configuration for Azure AD authentication
  identity {
    type = "SystemAssigned"
  }

  # Security and networking
  https_only = true

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      tags["CreatedDate"],
      app_settings["WEBSITE_ENABLE_SYNC_UPDATE_SITE"],
      app_settings["WEBSITE_RUN_FROM_PACKAGE"]
    ]
  }

  depends_on = [
    azurerm_cosmosdb_sql_container.expenses_container,
    azurerm_storage_account.functions
  ]
}

# Role Assignment - Grant Function App access to Cosmos DB
resource "azurerm_cosmosdb_sql_role_assignment" "function_app" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.expenses.name
  role_definition_id  = "${azurerm_cosmosdb_account.expenses.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Cosmos DB Built-in Data Contributor
  principal_id        = azurerm_linux_function_app.expenses.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.expenses.id
}
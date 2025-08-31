# Azure Smart Writing Feedback System Infrastructure
# This file creates all necessary Azure resources for the writing feedback system

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  # Generate resource group name if not provided
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Resource naming convention
  openai_name     = "openai-${var.project_name}-${random_string.suffix.result}"
  cosmos_name     = "cosmos-${var.project_name}-${random_string.suffix.result}"
  function_name   = "func-${var.project_name}-${random_string.suffix.result}"
  storage_name    = "st${var.project_name}${random_string.suffix.result}"
  appinsights_name = "ai-${var.project_name}-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "writing-feedback"
    CreatedBy   = "terraform"
    Recipe      = "smart-writing-feedback-openai-cosmos"
  }, var.tags)
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Application Insights for monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.appinsights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Create Azure OpenAI Service for intelligent text analysis
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Enable public network access for development
  public_network_access_enabled = true
  
  tags = merge(local.common_tags, {
    Service = "azure-openai"
    Purpose = "text-analysis"
  })
}

# Deploy GPT model for writing analysis
resource "azurerm_cognitive_deployment" "gpt_model" {
  name                 = "gpt-4-writing-analysis"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.gpt_model_name
    version = var.gpt_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.gpt_deployment_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Create Azure Cosmos DB for feedback data persistence
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Enable automatic failover if specified
  enable_automatic_failover = var.enable_automatic_failover
  
  # Configure consistency policy for optimal performance
  consistency_policy {
    consistency_level       = var.cosmos_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
  
  # Configure primary geo location
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Enable server-side encryption
  is_virtual_network_filter_enabled = false
  public_network_access_enabled     = true
  
  tags = merge(local.common_tags, {
    Service = "cosmos-db"
    Purpose = "feedback-storage"
  })
}

# Create Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "WritingFeedbackDB"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = var.cosmos_database_throughput
}

# Create Cosmos DB SQL Container for feedback documents
resource "azurerm_cosmosdb_sql_container" "feedback" {
  name                  = "FeedbackContainer"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/userId"
  partition_key_version = 1
  throughput            = var.cosmos_container_throughput
  
  # Configure indexing policy for optimal query performance
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Configure unique key policy
  unique_key {
    paths = ["/id", "/userId"]
  }
}

# Create Storage Account for Azure Functions runtime
resource "azurerm_storage_account" "functions" {
  name                     = local.storage_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable blob public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  tags = merge(local.common_tags, {
    Service = "storage"
    Purpose = "functions-runtime"
  })
}

# Create App Service Plan for Azure Functions (Consumption Plan)
resource "azurerm_service_plan" "functions" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan
  
  tags = merge(local.common_tags, {
    Service = "app-service-plan"
    Purpose = "functions-hosting"
  })
}

# Create Azure Function App for serverless orchestration
resource "azurerm_linux_function_app" "main" {
  name                = local.function_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.functions.id
  
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  
  # Configure runtime settings
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable Application Insights if configured
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    
    # Security configurations
    ftps_state = "Disabled"
    http2_enabled = true
    
    # CORS configuration for web applications
    cors {
      allowed_origins = ["*"]
    }
  }
  
  # Configure application settings for service integrations
  app_settings = {
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = "~${var.function_app_runtime_version}"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    
    # Azure OpenAI Service configuration
    "OPENAI_ENDPOINT" = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"      = azurerm_cognitive_account.openai.primary_access_key
    
    # Cosmos DB configuration
    "COSMOS_ENDPOINT"   = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_KEY"        = azurerm_cosmosdb_account.main.primary_key
    "COSMOS_DATABASE"   = azurerm_cosmosdb_sql_database.main.name
    "COSMOS_CONTAINER"  = azurerm_cosmosdb_sql_container.feedback.name
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING"  = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    Service = "azure-functions"
    Purpose = "writing-feedback-api"
  })
  
  depends_on = [
    azurerm_cognitive_account.openai,
    azurerm_cosmosdb_account.main,
    azurerm_cosmosdb_sql_database.main,
    azurerm_cosmosdb_sql_container.feedback
  ]
}

# Create role assignments for Function App managed identity
resource "azurerm_role_assignment" "openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "cosmos_contributor" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}
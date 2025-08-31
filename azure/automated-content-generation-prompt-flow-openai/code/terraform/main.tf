# ==============================================================================
# Azure Automated Content Generation with Prompt Flow and OpenAI
# Infrastructure as Code using Terraform
# 
# This configuration deploys a complete serverless content generation system
# using Azure AI Prompt Flow, OpenAI Service, Functions, and supporting services
# ==============================================================================

# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.112.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault (security best practice)
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    # Enable soft delete for Cognitive Services
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_prefix}-content-gen-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.common_tags, {
    Purpose = "Content Generation with AI"
  })
}

# ==============================================================================
# STORAGE ACCOUNT
# ==============================================================================

# Create Storage Account for content assets and function app
resource "azurerm_storage_account" "main" {
  name                     = "${var.storage_prefix}contentgen${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable hierarchical namespace for Data Lake capabilities
  is_hns_enabled = true

  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

  # Enable blob versioning and change feed for content management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.common_tags
}

# Create storage containers for content workflow
resource "azurerm_storage_container" "content_templates" {
  name                  = "content-templates"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "generated_content" {
  name                  = "generated-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ==============================================================================
# AZURE MACHINE LEARNING WORKSPACE
# ==============================================================================

# Create Application Insights for ML Workspace
resource "azurerm_application_insights" "ml_workspace" {
  name                = "${var.resource_prefix}-ai-ml-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id

  tags = var.common_tags
}

# Create Key Vault for ML Workspace
resource "azurerm_key_vault" "ml_workspace" {
  name                = "${var.resource_prefix}-kv-ml-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Security configurations
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.common_tags
}

# Grant Key Vault access to current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.ml_workspace.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Recover", "Backup", "Restore"
  ]

  secret_permissions = [
    "Set", "Get", "Delete", "List", "Recover", "Backup", "Restore"
  ]

  certificate_permissions = [
    "Create", "Delete", "Get", "List", "Update", "Recover", "Backup", "Restore"
  ]
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_prefix}-logs-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.common_tags
}

# Create Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "main" {
  name                    = "${var.resource_prefix}-ml-contentgen-${random_string.suffix.result}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.ml_workspace.id
  key_vault_id            = azurerm_key_vault.ml_workspace.id
  storage_account_id      = azurerm_storage_account.main.id

  # Identity configuration for managed identity
  identity {
    type = "SystemAssigned"
  }

  # ML workspace configuration
  friendly_name       = "Content Generation ML Workspace"
  description         = "Azure ML workspace for automated content generation using Prompt Flow"
  high_business_impact = false

  tags = var.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}

# ==============================================================================
# AZURE OPENAI SERVICE
# ==============================================================================

# Create Azure OpenAI Cognitive Services Account
resource "azurerm_cognitive_account" "openai" {
  name                = "${var.resource_prefix}-aoai-contentgen-${random_string.suffix.result}"
  location            = var.openai_location # OpenAI has limited region availability
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = "S0"

  # Custom subdomain is required for OpenAI
  custom_subdomain_name = "${var.resource_prefix}-aoai-contentgen-${random_string.suffix.result}"

  # Network access configuration
  public_network_access_enabled = true

  tags = var.common_tags
}

# Deploy GPT-4o model for content generation
resource "azurerm_cognitive_deployment" "gpt4o_content" {
  name                 = "gpt-4o-content"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  sku {
    name     = "Standard"
    capacity = var.gpt4o_capacity
  }
}

# Deploy text embedding model for content analysis
resource "azurerm_cognitive_deployment" "text_embedding" {
  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  sku {
    name     = "Standard"
    capacity = var.embedding_capacity
  }
}

# ==============================================================================
# COSMOS DB
# ==============================================================================

# Create Cosmos DB Account for content metadata
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.resource_prefix}-cosmos-contentgen-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Consistency policy for content metadata
  consistency_policy {
    consistency_level       = "Eventual"
    max_interval_in_seconds = 10
    max_staleness_prefix    = 200
  }

  # Geographic configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Security and backup configurations
  automatic_failover_enabled      = false
  multiple_write_locations_enabled = false
  public_network_access_enabled   = true

  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Geo"
  }

  tags = var.common_tags
}

# Create Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "content_generation" {
  name                = "ContentGeneration"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Create Cosmos DB SQL Container for content metadata
resource "azurerm_cosmosdb_sql_container" "content_metadata" {
  name                   = "ContentMetadata"
  resource_group_name    = azurerm_resource_group.main.name
  account_name           = azurerm_cosmosdb_account.main.name
  database_name          = azurerm_cosmosdb_sql_database.content_generation.name
  partition_key_path     = "/campaignId"
  partition_key_version  = 1
  throughput             = 400

  # Indexing policy for efficient queries
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  # Unique key for content deduplication
  unique_key {
    paths = ["/content_hash"]
  }
}

# ==============================================================================
# APPLICATION INSIGHTS
# ==============================================================================

# Create Application Insights for Function App monitoring
resource "azurerm_application_insights" "function_app" {
  name                = "${var.resource_prefix}-ai-func-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id

  tags = var.common_tags
}

# ==============================================================================
# AZURE FUNCTIONS
# ==============================================================================

# Create App Service Plan for Function App (Consumption plan)
resource "azurerm_service_plan" "function_app" {
  name                = "${var.resource_prefix}-plan-func-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan for serverless scaling
}

# Create Function App for content generation orchestration
resource "azurerm_linux_function_app" "main" {
  name                = "${var.resource_prefix}-func-contentgen-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.function_app.id

  # Function App configuration
  site_config {
    application_insights_key               = azurerm_application_insights.function_app.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.function_app.connection_string

    # Application stack configuration
    application_stack {
      python_version = "3.11"
    }

    # CORS configuration for web access
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }

    # Security headers
    use_32_bit_worker_process = false
    ftps_state                = "FtpsOnly"
    http2_enabled             = true
  }

  # Application settings for service integrations
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "PYTHON_ENABLE_WORKER_EXTENSIONS" = "1"
    
    # ML Workspace configuration
    "ML_WORKSPACE_NAME"    = azurerm_machine_learning_workspace.main.name
    "RESOURCE_GROUP"       = azurerm_resource_group.main.name
    "SUBSCRIPTION_ID"      = data.azurerm_client_config.current.subscription_id
    
    # Azure OpenAI configuration
    "OPENAI_ENDPOINT"      = azurerm_cognitive_account.openai.endpoint
    "OPENAI_API_KEY"       = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_API_VERSION"   = "2024-02-15-preview"
    
    # Cosmos DB configuration
    "COSMOS_ENDPOINT"      = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_KEY"           = azurerm_cosmosdb_account.main.primary_key
    "COSMOS_DATABASE"      = azurerm_cosmosdb_sql_database.content_generation.name
    "COSMOS_CONTAINER"     = azurerm_cosmosdb_sql_container.content_metadata.name
    
    # Storage configuration
    "STORAGE_CONNECTION"   = azurerm_storage_account.main.primary_connection_string
    "CONTENT_CONTAINER"    = azurerm_storage_container.generated_content.name
    "TEMPLATE_CONTAINER"   = azurerm_storage_container.content_templates.name
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.function_app.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.function_app.connection_string
  }

  # Managed identity for secure service access
  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
}

# ==============================================================================
# ROLE ASSIGNMENTS
# ==============================================================================

# Grant Function App access to Machine Learning Workspace
resource "azurerm_role_assignment" "function_ml_contributor" {
  scope                = azurerm_machine_learning_workspace.main.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Cognitive Services
resource "azurerm_role_assignment" "function_cognitive_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Cosmos DB
resource "azurerm_role_assignment" "function_cosmos_contributor" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant ML Workspace managed identity access to storage
resource "azurerm_role_assignment" "ml_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Grant ML Workspace access to Key Vault
resource "azurerm_key_vault_access_policy" "ml_workspace" {
  key_vault_id = azurerm_key_vault.ml_workspace.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_machine_learning_workspace.main.identity[0].principal_id

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete"
  ]

  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update"
  ]
}
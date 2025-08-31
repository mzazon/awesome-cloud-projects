# ===================================================================
# Azure Content Personalization Engine with AI Foundry and Cosmos
# ===================================================================
# This Terraform configuration deploys a complete content personalization
# solution using Azure AI Foundry, Cosmos DB with vector search, Azure
# OpenAI, and Azure Functions for serverless processing.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
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

# ===================================================================
# Data Sources
# ===================================================================

# Get current client configuration
data "azurerm_client_config" "current" {}

# ===================================================================
# Resource Group
# ===================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-personalization-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Purpose     = "Content Personalization Engine"
    Environment = var.environment
    CreatedBy   = "Terraform"
  })
}

# ===================================================================
# Storage Account for Azure Functions
# ===================================================================

resource "azurerm_storage_account" "functions" {
  name                     = var.storage_account_name != "" ? var.storage_account_name : "stpers${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # Security configurations
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  tags = var.tags
}

# ===================================================================
# Azure Cosmos DB Account with Vector Search
# ===================================================================

resource "azurerm_cosmosdb_account" "main" {
  name                = var.cosmos_account_name != "" ? var.cosmos_account_name : "cosmos-personalization-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Enable automatic failover for high availability
  enable_automatic_failover = true

  # Consistency level for balanced performance and consistency
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 10
    max_staleness_prefix    = 200
  }

  # Primary location configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Enable vector search capabilities
  capabilities {
    name = "EnableNoSQLVectorSearch"
  }

  # Security configurations
  public_network_access_enabled = true
  network_acl_bypass_for_azure_services = true

  tags = var.tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "personalization" {
  name                = "PersonalizationDB"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Container for user profiles
resource "azurerm_cosmosdb_sql_container" "user_profiles" {
  name                = "UserProfiles"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.personalization.name
  partition_key_paths = ["/userId"]
  throughput          = var.cosmos_throughput

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

# Container for content items with vector search configuration
resource "azurerm_cosmosdb_sql_container" "content_items" {
  name                = "ContentItems"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.personalization.name
  partition_key_paths = ["/category"]
  throughput          = var.cosmos_throughput

  # Vector search indexing policy
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    # Exclude vector embedding paths from default indexing for performance
    excluded_path {
      path = "/contentEmbedding/*"
    }

    excluded_path {
      path = "/userPreferenceEmbedding/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }

    # Vector indexes for semantic search
    vector_index {
      path = "/contentEmbedding"
      type = "quantizedFlat"
    }

    vector_index {
      path = "/userPreferenceEmbedding"
      type = "quantizedFlat"
    }
  }

  # Vector embedding policy for OpenAI embeddings
  vector_embedding_policy {
    vector_embedding {
      path               = "/contentEmbedding"
      data_type          = "float32"
      dimensions         = 1536
      distance_function  = "cosine"
    }

    vector_embedding {
      path               = "/userPreferenceEmbedding"
      data_type          = "float32"
      dimensions         = 1536
      distance_function  = "cosine"
    }
  }
}

# ===================================================================
# Azure OpenAI Service
# ===================================================================

resource "azurerm_cognitive_account" "openai" {
  name                = var.openai_service_name != "" ? var.openai_service_name : "openai-personalization-${random_string.suffix.result}"
  location            = var.openai_location != "" ? var.openai_location : azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"

  sku_name = var.openai_sku

  # Custom subdomain for API access
  custom_question_answering_search_service_id = null
  dynamic_throttling_enabled                  = false
  fqdns                                      = []
  local_auth_enabled                         = true
  outbound_network_access_restricted         = false
  public_network_access_enabled              = true

  tags = var.tags
}

# GPT-4 deployment for content generation
resource "azurerm_cognitive_deployment" "gpt4_content" {
  name                 = "gpt-4-content"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4"
    version = "0613"
  }

  scale {
    type     = "Standard"
    capacity = var.gpt4_capacity
  }

  rai_policy_name = null
}

# Text embedding deployment for vector search
resource "azurerm_cognitive_deployment" "text_embedding" {
  name                 = "text-embedding"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  scale {
    type     = "Standard"
    capacity = var.embedding_capacity
  }

  rai_policy_name = null
}

# ===================================================================
# Azure Machine Learning Workspace (AI Foundry)
# ===================================================================

# Application Insights for ML workspace
resource "azurerm_application_insights" "ml_workspace" {
  name                = "appi-ai-foundry-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 30

  tags = var.tags
}

# Key Vault for ML workspace secrets
resource "azurerm_key_vault" "ml_workspace" {
  name                = "kv-ai-foundry-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable access for Azure services
  enable_rbac_authorization = true

  tags = var.tags
}

# Storage account for ML workspace
resource "azurerm_storage_account" "ml_workspace" {
  name                     = "stmlws${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags
}

# Azure Machine Learning Workspace (AI Foundry foundation)
resource "azurerm_machine_learning_workspace" "ai_foundry" {
  name                    = var.ai_foundry_workspace_name != "" ? var.ai_foundry_workspace_name : "ai-personalization-${random_string.suffix.result}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.ml_workspace.id
  key_vault_id            = azurerm_key_vault.ml_workspace.id
  storage_account_id      = azurerm_storage_account.ml_workspace.id

  identity {
    type = "SystemAssigned"
  }

  description                   = "AI Foundry workspace for content personalization"
  friendly_name                = "Content Personalization AI Foundry"
  high_business_impact         = false
  public_network_access_enabled = true

  tags = var.tags
}

# ===================================================================
# Service Plan for Azure Functions
# ===================================================================

resource "azurerm_service_plan" "functions" {
  name                = "plan-personalization-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku

  tags = var.tags
}

# ===================================================================
# Azure Function App
# ===================================================================

resource "azurerm_linux_function_app" "personalization" {
  name                = var.function_app_name != "" ? var.function_app_name : "func-personalization-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  service_plan_id           = azurerm_service_plan.functions.id

  site_config {
    application_stack {
      python_version = "3.12"
    }

    # CORS configuration for web applications
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    # Security configurations
    ftps_state        = "FtpsOnly"
    http2_enabled     = true
    minimum_tls_version = "1.2"
  }

  # Application settings for AI service connections
  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    FUNCTIONS_EXTENSION_VERSION    = "~4"
    COSMOS_CONNECTION_STRING       = azurerm_cosmosdb_account.main.connection_strings[0]
    OPENAI_ENDPOINT               = azurerm_cognitive_account.openai.endpoint
    OPENAI_API_KEY                = azurerm_cognitive_account.openai.primary_access_key
    AI_FOUNDRY_WORKSPACE          = azurerm_machine_learning_workspace.ai_foundry.name
    COSMOS_DATABASE_NAME          = azurerm_cosmosdb_sql_database.personalization.name
    COSMOS_USER_CONTAINER_NAME    = azurerm_cosmosdb_sql_container.user_profiles.name
    COSMOS_CONTENT_CONTAINER_NAME = azurerm_cosmosdb_sql_container.content_items.name
    
    # OpenAI model deployment names
    OPENAI_GPT4_DEPLOYMENT_NAME     = azurerm_cognitive_deployment.gpt4_content.name
    OPENAI_EMBEDDING_DEPLOYMENT_NAME = azurerm_cognitive_deployment.text_embedding.name
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  # Ensure deployments are created before the function app
  depends_on = [
    azurerm_cognitive_deployment.gpt4_content,
    azurerm_cognitive_deployment.text_embedding
  ]
}

# ===================================================================
# RBAC Assignments
# ===================================================================

# Function App access to Cosmos DB
resource "azurerm_role_assignment" "function_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = azurerm_linux_function_app.personalization.identity[0].principal_id
}

# Function App access to Cognitive Services
resource "azurerm_role_assignment" "function_cognitive" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.personalization.identity[0].principal_id
}

# AI Foundry workspace access to Cognitive Services
resource "azurerm_role_assignment" "ai_foundry_cognitive" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_machine_learning_workspace.ai_foundry.identity[0].principal_id
}

# AI Foundry workspace access to Cosmos DB
resource "azurerm_role_assignment" "ai_foundry_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = azurerm_machine_learning_workspace.ai_foundry.identity[0].principal_id
}

# Key Vault access for current user (for deployment)
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_key_vault.ml_workspace.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Key Vault access for AI Foundry workspace
resource "azurerm_role_assignment" "ai_foundry_keyvault" {
  scope                = azurerm_key_vault.ml_workspace.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_machine_learning_workspace.ai_foundry.identity[0].principal_id
}

# ===================================================================
# Application Insights for Function App Monitoring
# ===================================================================

resource "azurerm_application_insights" "functions" {
  name                = "appi-personalization-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 30

  tags = var.tags
}
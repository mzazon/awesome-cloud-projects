# ==================================================================================================
# AZURE DOCUMENT Q&A WITH AI SEARCH AND OPENAI
# ==================================================================================================
# This Terraform configuration deploys a complete document Q&A solution using:
# - Azure AI Search for semantic vector indexing and hybrid search capabilities
# - Azure OpenAI Service for natural language understanding and response generation
# - Azure Functions for serverless Q&A API orchestration using RAG pattern
# - Azure Blob Storage for document storage and processing pipeline
# ==================================================================================================

terraform {
  required_version = ">= 1.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete purging for faster testing cleanup
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ==================================================================================================
# DATA SOURCES AND LOCALS
# ==================================================================================================

# Get current client configuration for tenant and subscription information
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix to ensure uniqueness
  resource_prefix = "docqa-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Purpose      = "Document Q&A System"
    CreatedBy    = "Terraform"
    CreatedDate  = timestamp()
  })

  # OpenAI model configurations for embedding and chat completion
  embedding_model = {
    name       = "text-embedding-3-large"
    version    = "1"
    format     = "OpenAI"
    dimensions = 3072
    capacity   = 30
  }

  chat_model = {
    name     = "gpt-4o"
    version  = "2024-11-20"
    format   = "OpenAI"
    capacity = 10
  }

  # Function app configuration settings
  function_app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"     = "~4"
    "FUNCTIONS_WORKER_RUNTIME"        = "python"
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
    "SEARCH_SERVICE_NAME"             = azurerm_search_service.main.name
    "SEARCH_INDEX_NAME"               = var.search_index_name
    "OPENAI_ENDPOINT"                 = azurerm_cognitive_account.openai.endpoint
    "SEARCH_ADMIN_KEY"                = azurerm_search_service.main.primary_key
    "OPENAI_KEY"                      = azurerm_cognitive_account.openai.primary_access_key
    "EMBEDDING_DEPLOYMENT_NAME"       = local.embedding_model.name
    "CHAT_DEPLOYMENT_NAME"            = local.chat_model.name
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "AzureWebJobsStorage"             = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"            = azurerm_storage_share.function_content.name
  }
}

# ==================================================================================================
# RESOURCE GROUP
# ==================================================================================================

# Resource group to contain all resources for the document Q&A solution
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${local.resource_prefix}"
  location = var.location
  tags     = local.common_tags
}

# ==================================================================================================
# STORAGE ACCOUNT AND CONTAINERS
# ==================================================================================================

# Storage account for document storage, function app content, and Azure Functions runtime
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(local.resource_prefix, "-", "")}"
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  
  # Security configuration following Azure best practices
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning and change feed for document management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure blob retention for cost optimization
    delete_retention_policy {
      days = var.blob_delete_retention_days
    }
    
    container_delete_retention_policy {
      days = var.blob_delete_retention_days
    }
  }

  tags = local.common_tags
}

# Blob container for storing documents to be processed by AI Search indexer
resource "azurerm_storage_container" "documents" {
  name                  = var.documents_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# File share for Azure Functions app content storage
resource "azurerm_storage_share" "function_content" {
  name                 = "${local.resource_prefix}-function-content"
  storage_account_name = azurerm_storage_account.main.name
  quota                = 5120 # 5GB quota for function app content
}

# ==================================================================================================
# AZURE OPENAI SERVICE AND MODEL DEPLOYMENTS
# ==================================================================================================

# Azure OpenAI Service for embedding generation and chat completion
resource "azurerm_cognitive_account" "openai" {
  name                = "oai-${local.resource_prefix}"
  location            = var.openai_location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name

  # Enable custom subdomain required for OpenAI service integration
  custom_subdomain_name = "oai-${local.resource_prefix}"
  
  # Network access configuration
  public_network_access_enabled = var.openai_public_network_access_enabled
  
  # Managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

  # Ensure proper deletion order
  lifecycle {
    prevent_destroy = false
  }
}

# Text embedding model deployment for document vectorization and query processing
resource "azurerm_cognitive_deployment" "embedding" {
  name                 = local.embedding_model.name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = local.embedding_model.format
    name    = local.embedding_model.name
    version = local.embedding_model.version
  }

  sku {
    name     = "Standard"
    capacity = local.embedding_model.capacity
  }

  # Ensure OpenAI service is fully provisioned before deployment
  depends_on = [azurerm_cognitive_account.openai]
}

# GPT-4o model deployment for natural language response generation
resource "azurerm_cognitive_deployment" "chat" {
  name                 = local.chat_model.name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = local.chat_model.format
    name    = local.chat_model.name
    version = local.chat_model.version
  }

  sku {
    name     = "Standard"
    capacity = local.chat_model.capacity
  }

  # Ensure embedding deployment completes first to avoid quota conflicts
  depends_on = [azurerm_cognitive_deployment.embedding]
}

# ==================================================================================================
# AZURE AI SEARCH SERVICE
# ==================================================================================================

# AI Search service with semantic search capabilities for vector and hybrid search
resource "azurerm_search_service" "main" {
  name                = "srch-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.search_service_sku
  
  # Enable semantic search for enhanced query understanding
  semantic_search_sku = var.search_semantic_sku
  
  # Configure replica and partition count based on performance requirements
  replica_count   = var.search_replica_count
  partition_count = var.search_partition_count
  
  # Network access configuration
  public_network_access_enabled = var.search_public_network_access_enabled
  
  # Enable managed identity for secure service-to-service communication
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# ==================================================================================================
# APPLICATION INSIGHTS FOR MONITORING
# ==================================================================================================

# Log Analytics workspace for Application Insights data storage
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = local.common_tags
}

# Application Insights for monitoring function app performance and usage
resource "azurerm_application_insights" "main" {
  name                = "ai-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = local.common_tags
}

# ==================================================================================================
# AZURE FUNCTION APP FOR Q&A API
# ==================================================================================================

# App Service Plan for hosting the Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku_name

  tags = local.common_tags
}

# Linux Function App for the Q&A API endpoint implementing RAG pattern
resource "azurerm_linux_function_app" "main" {
  name                = "func-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Link to App Service Plan and storage account
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  # Function runtime and application settings
  app_settings = local.function_app_settings

  # Security and networking configuration
  https_only                    = true
  public_network_access_enabled = var.function_app_public_access_enabled

  # Managed identity for secure access to Azure services
  identity {
    type = "SystemAssigned"
  }

  # Site configuration with Python runtime
  site_config {
    # Python runtime configuration
    application_stack {
      python_version = var.python_version
    }

    # Application Insights integration
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key              = azurerm_application_insights.main.instrumentation_key

    # CORS configuration for web client access
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    # Security and performance settings
    ftps_state        = "Disabled"
    http2_enabled     = true
    minimum_tls_version = "1.2"

    # Health check configuration
    health_check_path                 = "/api/health"
    health_check_eviction_time_in_min = 2
  }

  tags = local.common_tags

  # Ensure all dependencies are created before function app
  depends_on = [
    azurerm_storage_account.main,
    azurerm_application_insights.main,
    azurerm_cognitive_deployment.embedding,
    azurerm_cognitive_deployment.chat,
    azurerm_search_service.main
  ]
}

# ==================================================================================================
# ROLE ASSIGNMENTS FOR MANAGED IDENTITY ACCESS
# ==================================================================================================

# Grant Function App access to Search Service as Search Service Contributor
resource "azurerm_role_assignment" "function_to_search" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to OpenAI Service as Cognitive Services OpenAI User
resource "azurerm_role_assignment" "function_to_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Storage Account as Storage Blob Data Contributor
resource "azurerm_role_assignment" "function_to_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Search Service access to Storage Account for indexing documents
resource "azurerm_role_assignment" "search_to_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}

# Grant Search Service access to OpenAI Service for embedding generation
resource "azurerm_role_assignment" "search_to_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}
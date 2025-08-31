# ==============================================================================
# Simple Text Translation with Functions and Translator - Main Configuration
# ==============================================================================
# This Terraform configuration creates a serverless text translation API using
# Azure Functions and Azure AI Translator service. The solution provides instant
# text translation between multiple languages with pay-per-use pricing.

# Resource Group
# Creates a resource group to contain all translation service resources
resource "azurerm_resource_group" "translation" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    Purpose     = "text-translation-api"
    ManagedBy   = "terraform"
  }
}

# Random ID for unique resource naming
# Generates a random suffix to ensure resource names are globally unique
resource "random_id" "suffix" {
  byte_length = 3
}

# Storage Account
# Required by Azure Functions for triggers, logging, and function execution state
resource "azurerm_storage_account" "function_storage" {
  name                     = "${var.storage_account_prefix}${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.translation.name
  location                 = azurerm_resource_group.translation.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable minimum TLS version for security
  min_tls_version = "TLS1_2"

  tags = {
    Environment = var.environment
    Purpose     = "function-app-storage"
    ManagedBy   = "terraform"
  }
}

# Application Insights
# Provides comprehensive monitoring and logging for the Function App
resource "azurerm_application_insights" "translation_insights" {
  name                = "${var.function_app_prefix}-insights-${random_id.suffix.hex}"
  location            = azurerm_resource_group.translation.location
  resource_group_name = azurerm_resource_group.translation.name
  application_type    = "web"

  tags = {
    Environment = var.environment
    Purpose     = "function-app-monitoring"
    ManagedBy   = "terraform"
  }
}

# Azure AI Translator Service
# Provides text translation capabilities across 100+ languages
resource "azurerm_cognitive_account" "translator" {
  name                = "${var.translator_prefix}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.translation.location
  resource_group_name = azurerm_resource_group.translation.name
  kind                = "TextTranslation"
  sku_name            = var.translator_sku

  # Enable custom subdomain for enhanced security
  custom_subdomain_name = "${var.translator_prefix}-${random_id.suffix.hex}"

  tags = {
    Environment = var.environment
    Purpose     = "text-translation-service"
    ManagedBy   = "terraform"
  }
}

# Service Plan for Function App
# Consumption plan provides true serverless execution with automatic scaling
resource "azurerm_service_plan" "translation_plan" {
  name                = "${var.function_app_prefix}-plan-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.translation.name
  location            = azurerm_resource_group.translation.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku

  tags = {
    Environment = var.environment
    Purpose     = "function-app-hosting"
    ManagedBy   = "terraform"
  }
}

# Function App
# Serverless compute service that hosts the translation function
resource "azurerm_linux_function_app" "translation_app" {
  name                = "${var.function_app_prefix}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.translation.name
  location            = azurerm_resource_group.translation.location

  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.translation_plan.id

  # Function runtime configuration
  site_config {
    application_stack {
      node_version = var.node_version
    }

    # Enable CORS for web applications
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    # Security configuration
    ftps_state = "Disabled"
    
    # Enable Application Insights integration
    application_insights_key               = azurerm_application_insights.translation_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.translation_insights.connection_string
  }

  # Application settings for function configuration
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~20"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    
    # Azure AI Translator configuration
    "TRANSLATOR_ENDPOINT" = azurerm_cognitive_account.translator.endpoint
    "TRANSLATOR_KEY"      = azurerm_cognitive_account.translator.primary_access_key
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.translation_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.translation_insights.connection_string
    
    # Security and performance settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.function_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE"                      = "${var.function_app_prefix}-${random_id.suffix.hex}"
    "AzureWebJobsDisableHomepage"               = "true"
  }

  # Enable system-assigned managed identity for secure access to Azure services
  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = var.environment
    Purpose     = "text-translation-function"
    ManagedBy   = "terraform"
  }

  depends_on = [
    azurerm_storage_account.function_storage,
    azurerm_application_insights.translation_insights,
    azurerm_cognitive_account.translator
  ]
}

# Function App Slot for staging deployments (optional)
# Provides blue-green deployment capabilities for zero-downtime updates
resource "azurerm_linux_function_app_slot" "staging" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "staging"
  function_app_id            = azurerm_linux_function_app.translation_app.id
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key

  site_config {
    application_stack {
      node_version = var.node_version
    }

    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    ftps_state = "Disabled"
    
    application_insights_key               = azurerm_application_insights.translation_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.translation_insights.connection_string
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~20"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "TRANSLATOR_ENDPOINT"          = azurerm_cognitive_account.translator.endpoint
    "TRANSLATOR_KEY"               = azurerm_cognitive_account.translator.primary_access_key
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.translation_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.translation_insights.connection_string
    "WEBSITE_CONTENTAZUREfileconnectionstring" = azurerm_storage_account.function_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE"                      = "${var.function_app_prefix}-staging-${random_id.suffix.hex}"
    "AzureWebJobsDisableHomepage"               = "true"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "${var.environment}-staging"
    Purpose     = "text-translation-function-staging"
    ManagedBy   = "terraform"
  }
}

# Function for the translation logic (placeholder - actual function code deployed separately)
# Note: Function code deployment is typically handled through CI/CD pipelines or Azure CLI
# This resource documents the expected function configuration
locals {
  function_config = {
    name = "translate"
    config = {
      bindings = [
        {
          authLevel = "function"
          type      = "httpTrigger"
          direction = "in"
          name      = "req"
          methods   = ["post"]
        },
        {
          type      = "http"
          direction = "out"
          name      = "res"
        }
      ]
    }
  }
}
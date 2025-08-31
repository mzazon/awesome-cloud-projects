# Terraform configuration for Customer Support Assistant with OpenAI Assistants and Functions
# This configuration deploys the complete infrastructure for an intelligent customer support
# assistant using Azure OpenAI Assistants API with Azure Functions for custom actions

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Microsoft Azure Provider
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
  upper   = false
  special = false
}

# Resource Group for all customer support assistant resources
resource "azurerm_resource_group" "main" {
  name     = "rg-support-assistant-${random_string.suffix.result}"
  location = var.location

  tags = {
    purpose     = "recipe"
    environment = "demo"
    recipe      = "customer-support-assistant-openai-functions"
  }
}

# Storage Account for support data (Table, Blob, Queue)
resource "azurerm_storage_account" "support_data" {
  name                     = "supportdata${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Enable all storage services needed for the support system
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = {
    purpose     = "recipe"
    environment = "demo"
    service     = "support-data-storage"
  }
}

# Storage Table for tickets data
resource "azurerm_storage_table" "tickets" {
  name                 = "tickets"
  storage_account_name = azurerm_storage_account.support_data.name
}

# Storage Table for customer data
resource "azurerm_storage_table" "customers" {
  name                 = "customers"
  storage_account_name = azurerm_storage_account.support_data.name
}

# Storage Container for FAQ documents
resource "azurerm_storage_container" "faqs" {
  name                  = "faqs"
  storage_account_name  = azurerm_storage_account.support_data.name
  container_access_type = "private"
}

# Storage Queue for escalations
resource "azurerm_storage_queue" "escalations" {
  name                 = "escalations"
  storage_account_name = azurerm_storage_account.support_data.name
}

# Azure OpenAI Service for the customer support assistant
resource "azurerm_cognitive_account" "openai" {
  name                          = "support-openai-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  kind                         = "OpenAI"
  sku_name                     = "S0"
  custom_subdomain_name        = "support-openai-${random_string.suffix.result}"
  public_network_access_enabled = true

  tags = {
    purpose     = "recipe"
    environment = "demo"
    service     = "openai-assistant"
  }
}

# GPT-4o Model Deployment for the assistant
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  scale {
    type = "Standard"
  }
}

# Application Insights for Function App monitoring
resource "azurerm_application_insights" "function_insights" {
  name                = "ai-support-functions-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "Node.JS"

  tags = {
    purpose     = "recipe"
    environment = "demo"
    service     = "function-monitoring"
  }
}

# Service Plan for Function App (Consumption plan)
resource "azurerm_service_plan" "function_plan" {
  name                = "asp-support-functions-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan

  tags = {
    purpose     = "recipe"
    environment = "demo"
    service     = "function-plan"
  }
}

# Function App for customer support operations
resource "azurerm_linux_function_app" "support_functions" {
  name                       = "support-functions-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id           = azurerm_service_plan.function_plan.id
  storage_account_name      = azurerm_storage_account.support_data.name
  storage_account_access_key = azurerm_storage_account.support_data.primary_access_key

  # Function App configuration
  site_config {
    application_stack {
      node_version = "20"
    }

    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.function_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.function_insights.connection_string

    # CORS configuration for web clients
    cors {
      allowed_origins = ["*"]
    }
  }

  # Application settings for the Function App
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~20"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    
    # Storage connection string for support data access
    "STORAGE_CONNECTION" = azurerm_storage_account.support_data.primary_connection_string
    
    # OpenAI configuration for assistant integration
    "OPENAI_ENDPOINT" = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"      = azurerm_cognitive_account.openai.primary_access_key
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.function_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.function_insights.connection_string
  }

  # Enable system-assigned managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }

  tags = {
    purpose     = "recipe"
    environment = "demo"
    service     = "support-functions"
  }

  # Ensure OpenAI service is created before Function App
  depends_on = [
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.gpt4o
  ]
}

# Role assignment for Function App to access Storage Account
resource "azurerm_role_assignment" "function_storage_contributor" {
  scope                = azurerm_storage_account.support_data.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_linux_function_app.support_functions.identity[0].principal_id
}

# Role assignment for Function App to access OpenAI service
resource "azurerm_role_assignment" "function_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.support_functions.identity[0].principal_id
}

# Log Analytics Workspace for advanced monitoring (optional)
resource "azurerm_log_analytics_workspace" "support_logs" {
  name                = "law-support-assistant-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    purpose     = "recipe"
    environment = "demo"  
    service     = "logging"
  }
}

# Connect Application Insights to Log Analytics
resource "azurerm_application_insights_analytics_item" "function_queries" {
  name                    = "SupportFunctionQueries"
  application_insights_id = azurerm_application_insights.function_insights.id
  content                 = <<QUERY
requests
| where timestamp > ago(24h)
| where name contains "ticket" or name contains "faq"
| summarize count() by name, bin(timestamp, 1h)
| render timechart
QUERY
  scope                   = "shared"
  type                    = "query"
}
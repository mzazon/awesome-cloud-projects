# Main Terraform configuration for Azure Tutorial Generator
# This configuration deploys an intelligent tutorial generation system using
# Azure OpenAI, Azure Functions, and Azure Blob Storage

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and configuration
locals {
  # Generate consistent naming convention
  resource_suffix       = random_string.suffix.result
  resource_group_name   = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name  = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  openai_account_name   = "${var.project_name}-openai-${local.resource_suffix}"
  function_app_name     = "${var.project_name}-func-${local.resource_suffix}"
  service_plan_name     = "asp-${var.project_name}-${local.resource_suffix}"
  app_insights_name     = "ai-${var.project_name}-${local.resource_suffix}"
  
  # Merge provided tags with required tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    CreatedBy     = "Terraform"
    LastModified  = timestamp()
  })
}

# Create Resource Group for all tutorial generator resources
resource "azurerm_resource_group" "tutorial_generator" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for tutorial content and function app storage
resource "azurerm_storage_account" "tutorial_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.tutorial_generator.name
  location                 = azurerm_resource_group.tutorial_generator.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.storage_access_tier
  
  # Security and access configuration
  public_network_access_enabled   = var.enable_public_access
  allow_nested_items_to_be_public = var.enable_public_access
  
  # Enable blob storage features
  blob_properties {
    # Enable versioning for tutorial content management
    versioning_enabled = true
    
    # Configure change feed for audit trail
    change_feed_enabled = true
    
    # Set default service version
    last_access_time_enabled = true
    
    # Configure container delete retention
    container_delete_retention_policy {
      days = 7
    }
    
    # Configure blob delete retention
    delete_retention_policy {
      days = 7
    }
  }
  
  # Configure network rules for security
  network_rules {
    default_action = var.enable_public_access ? "Allow" : "Deny"
    ip_rules       = var.enable_public_access ? [] : ["127.0.0.1"] # Restrict if public access is disabled
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Create storage container for tutorial content (publicly accessible)
resource "azurerm_storage_container" "tutorials" {
  name                  = "tutorials"
  storage_account_name  = azurerm_storage_account.tutorial_storage.name
  container_access_type = var.enable_public_access ? "blob" : "private"
  
  depends_on = [azurerm_storage_account.tutorial_storage]
}

# Create storage container for tutorial metadata (private)
resource "azurerm_storage_container" "metadata" {
  name                  = "metadata"
  storage_account_name  = azurerm_storage_account.tutorial_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.tutorial_storage]
}

# Create Azure OpenAI Service for tutorial content generation
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_account_name
  location            = azurerm_resource_group.tutorial_generator.location
  resource_group_name = azurerm_resource_group.tutorial_generator.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Custom domain configuration for API access
  custom_subdomain_name = local.openai_account_name
  
  # Network access configuration
  public_network_access_enabled = true
  
  # Configure network ACLs for security
  network_acls {
    default_action = "Allow"
    
    # Allow Azure services to access
    virtual_network_rules {
      subnet_id                            = null
      ignore_missing_vnet_service_endpoint = false
    }
  }
  
  tags = local.common_tags
}

# Deploy GPT model for tutorial generation
resource "azurerm_cognitive_deployment" "gpt_model" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.openai_deployment_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Create Application Insights for Function App monitoring (conditional)
resource "azurerm_application_insights" "tutorial_insights" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.tutorial_generator.location
  resource_group_name = azurerm_resource_group.tutorial_generator.name
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "tutorial_plan" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.tutorial_generator.name
  location            = azurerm_resource_group.tutorial_generator.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Create Function App for tutorial generation and retrieval
resource "azurerm_linux_function_app" "tutorial_generator" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.tutorial_generator.name
  location            = azurerm_resource_group.tutorial_generator.location
  service_plan_id     = azurerm_service_plan.tutorial_plan.id
  
  # Storage account configuration for function app
  storage_account_name       = azurerm_storage_account.tutorial_storage.name
  storage_account_access_key = azurerm_storage_account.tutorial_storage.primary_access_key
  
  # Enable public network access
  public_network_access_enabled = true
  
  # Function app configuration
  site_config {
    # Enable Always On for Premium plans
    always_on = var.function_app_service_plan_sku != "Y1"
    
    # Configure Python runtime
    application_stack {
      python_version = var.python_version
    }
    
    # Enable CORS for web applications
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }
    
    # Configure function app settings
    use_32_bit_worker = false
    
    # Enable Application Insights if configured
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        application_insights_connection_string = azurerm_application_insights.tutorial_insights[0].connection_string
      }
    }
    
    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        application_insights_key = azurerm_application_insights.tutorial_insights[0].instrumentation_key
      }
    }
  }
  
  # Application settings for OpenAI and Storage integration
  app_settings = {
    # Azure Functions runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "FUNCTIONS_EXTENSION_VERSION"  = var.function_runtime_version
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
    
    # Azure OpenAI configuration
    "OPENAI_ENDPOINT"     = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"          = azurerm_cognitive_account.openai.primary_access_key
    "DEPLOYMENT_NAME"     = azurerm_cognitive_deployment.gpt_model.name
    
    # Storage account configuration
    "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.tutorial_storage.name
    "STORAGE_ACCOUNT_KEY"  = azurerm_storage_account.tutorial_storage.primary_access_key
    
    # Application Insights configuration (conditional)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.tutorial_insights[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.tutorial_insights[0].connection_string : ""
    
    # Additional configuration
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
    "ENABLE_ORYX_BUILD" = "false"
  }
  
  # Configure authentication if needed
  auth_settings_v2 {
    auth_enabled = false
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_service_plan.tutorial_plan,
    azurerm_storage_account.tutorial_storage,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.gpt_model
  ]
}

# Create a storage account for function app deployment (separate from content storage)
resource "azurerm_storage_account" "function_storage" {
  name                     = "${substr(local.storage_account_name, 0, 18)}func"
  resource_group_name      = azurerm_resource_group.tutorial_generator.name
  location                 = azurerm_resource_group.tutorial_generator.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
  
  # Minimal configuration for function storage
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Role assignment for Function App to access OpenAI service
resource "azurerm_role_assignment" "function_openai_access" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.tutorial_generator.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.tutorial_generator]
}

# Role assignment for Function App to access Storage Account
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.tutorial_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.tutorial_generator.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.tutorial_generator]
}
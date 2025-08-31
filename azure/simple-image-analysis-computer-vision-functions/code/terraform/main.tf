# =============================================================================
# AZURE IMAGE ANALYSIS WITH COMPUTER VISION AND FUNCTIONS
# =============================================================================
# This Terraform configuration creates a serverless image analysis solution
# using Azure Functions and Azure Computer Vision services.
# =============================================================================

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  # Generate unique suffix if not provided
  suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Compute resource names with fallbacks
  resource_group_name   = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.suffix}"
  computer_vision_name  = var.computer_vision_name != "" ? var.computer_vision_name : "cv-${var.project_name}-${local.suffix}"
  storage_account_name  = var.storage_account_name != "" ? var.storage_account_name : "sa${local.suffix}${replace(var.project_name, "-", "")}"
  function_app_name     = var.function_app_name != "" ? var.function_app_name : "func-${var.project_name}-${local.suffix}"
  
  # App Service Plan name
  service_plan_name = "asp-${var.project_name}-${local.suffix}"
  
  # Application Insights name
  app_insights_name = "appi-${var.project_name}-${local.suffix}"
  
  # Merge default and custom tags
  merged_tags = merge(var.common_tags, {
    Environment   = var.environment
    Location      = var.location
    CreatedDate   = timestamp()
    LastUpdated   = timestamp()
  })
}

# =============================================================================
# RESOURCE GROUP
# =============================================================================
# Create resource group to contain all resources for this recipe
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.merged_tags
}

# =============================================================================
# COGNITIVE SERVICES - COMPUTER VISION
# =============================================================================
# Create Computer Vision service for image analysis capabilities
resource "azurerm_cognitive_account" "computer_vision" {
  name                = local.computer_vision_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ComputerVision"
  sku_name            = var.computer_vision_sku
  
  # Enable custom subdomain for Computer Vision service
  custom_question_answering_search_service_id = null
  dynamic_throttling_enabled                  = false
  fqdns                                      = []
  local_auth_enabled                         = true
  outbound_network_access_restricted         = false
  public_network_access_enabled              = true
  
  tags = merge(local.merged_tags, {
    Service = "ComputerVision"
    Purpose = "Image analysis and AI capabilities"
  })
}

# =============================================================================
# STORAGE ACCOUNT
# =============================================================================
# Create storage account required for Azure Functions runtime and storage
resource "azurerm_storage_account" "functions" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  enable_https_traffic_only       = true
  min_tls_version                 = var.minimum_tls_version
  allow_nested_items_to_be_public = false
  
  # Advanced threat protection
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = false
  }
  
  tags = merge(local.merged_tags, {
    Service = "Storage"
    Purpose = "Function App storage and runtime dependencies"
  })
}

# =============================================================================
# APPLICATION INSIGHTS (OPTIONAL)
# =============================================================================
# Create Application Insights for monitoring and diagnostics
resource "azurerm_application_insights" "functions" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = var.application_insights_type
  
  # Retention and sampling configurations
  retention_in_days   = 90
  daily_data_cap_in_gb = 1
  
  tags = merge(local.merged_tags, {
    Service = "ApplicationInsights"
    Purpose = "Function App monitoring and diagnostics"
  })
}

# =============================================================================
# APP SERVICE PLAN
# =============================================================================
# Create App Service Plan for hosting Azure Functions
resource "azurerm_service_plan" "functions" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku_name
  
  tags = merge(local.merged_tags, {
    Service = "AppServicePlan"
    Purpose = "Hosting plan for Azure Functions"
  })
}

# =============================================================================
# AZURE FUNCTION APP
# =============================================================================
# Create Linux Function App for serverless compute
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.functions.id
  
  # Storage account connection
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  
  # Function App configuration
  functions_extension_version = var.functions_extension_version
  https_only                  = var.enable_https_only
  
  # Site configuration
  site_config {
    # Always on is not supported for Consumption plans
    always_on = var.service_plan_sku_name != "Y1" ? var.always_on : false
    
    # Runtime configuration
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration
    dynamic "cors" {
      for_each = var.enable_cors ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = false
      }
    }
    
    # Security configurations
    ftps_state        = "Disabled"
    minimum_tls_version = var.minimum_tls_version
    
    # Application Insights integration
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.functions[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.functions[0].connection_string : null
  }
  
  # Application settings for Computer Vision integration
  app_settings = {
    # Computer Vision configuration
    COMPUTER_VISION_ENDPOINT = azurerm_cognitive_account.computer_vision.endpoint
    COMPUTER_VISION_KEY      = azurerm_cognitive_account.computer_vision.primary_access_key
    
    # Python specific settings
    ENABLE_ORYX_BUILD              = "true"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    
    # Function runtime settings
    FUNCTIONS_WORKER_RUNTIME     = var.function_app_runtime
    FUNCTIONS_WORKER_RUNTIME_VERSION = var.function_app_runtime_version
    
    # Application Insights (if enabled)
    APPINSIGHTS_INSTRUMENTATIONKEY        = var.enable_application_insights ? azurerm_application_insights.functions[0].instrumentation_key : ""
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_application_insights ? azurerm_application_insights.functions[0].connection_string : ""
    
    # Additional settings for optimization
    WEBSITE_RUN_FROM_PACKAGE = "1"
    WEBSITE_ENABLE_SYNC_UPDATE_SITE = "true"
  }
  
  # Identity configuration for managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.merged_tags, {
    Service = "FunctionApp"
    Purpose = "Serverless image analysis API"
    Runtime = "${var.function_app_runtime}-${var.function_app_runtime_version}"
  })
  
  # Lifecycle management
  lifecycle {
    ignore_changes = [
      # Ignore changes to app_settings that might be modified during deployment
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
      # Ignore changes to tags that might be added by Azure
      tags["hidden-related:/subscriptions"]
    ]
  }
}

# =============================================================================
# RBAC ASSIGNMENTS (OPTIONAL)
# =============================================================================
# Assign Cognitive Services User role to Function App managed identity
resource "azurerm_role_assignment" "function_to_cognitive_services" {
  scope                = azurerm_cognitive_account.computer_vision.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_cognitive_account.computer_vision
  ]
}

# Assign Storage Blob Data Contributor role for Function App
resource "azurerm_role_assignment" "function_to_storage" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_storage_account.functions
  ]
}
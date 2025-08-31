# =============================================================================
# Simple Todo API with Azure Functions and Table Storage
# =============================================================================
# This Terraform configuration deploys a complete serverless Todo API using
# Azure Functions for compute and Azure Table Storage for data persistence.
# The infrastructure follows Azure Well-Architected Framework principles
# with security, scalability, and cost optimization built-in.

# =============================================================================
# Data Sources
# =============================================================================

# Get current Azure subscription and tenant information
data "azurerm_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# =============================================================================
# Resource Group
# =============================================================================

# Create resource group to contain all Todo API resources
resource "azurerm_resource_group" "todo_api" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    ResourceType = "Resource Group"
    Purpose      = "Container for Todo API resources"
    Environment  = var.environment
  })

  lifecycle {
    # Prevent accidental deletion of resource group
    prevent_destroy = false
  }
}

# =============================================================================
# Storage Account
# =============================================================================

# Create storage account for both Function App storage and Table Storage
resource "azurerm_storage_account" "todo_api" {
  name                = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.todo_api.name
  location           = azurerm_resource_group.todo_api.location

  # Storage configuration optimized for cost and performance
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind            = "StorageV2"
  access_tier             = var.storage_access_tier

  # Security configuration following Azure best practices
  min_tls_version                   = var.min_tls_version
  https_traffic_only_enabled        = var.https_only
  public_network_access_enabled     = var.public_network_access_enabled
  shared_access_key_enabled         = var.shared_access_key_enabled
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  default_to_oauth_authentication   = true

  # Enable versioning and soft delete for blob protection
  blob_properties {
    versioning_enabled        = true
    change_feed_enabled       = false
    last_access_time_enabled  = false

    delete_retention_policy {
      days                     = 7
      permanent_delete_enabled = false
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  # Configure Table Storage encryption
  table_encryption_key_type = "Service"
  queue_encryption_key_type = "Service"

  tags = merge(var.tags, {
    ResourceType = "Storage Account"
    Purpose      = "Function App storage and Table Storage for Todo data"
    CostCenter   = "Development"
  })

  lifecycle {
    # Prevent accidental deletion of storage account
    prevent_destroy = false
    
    # Ignore changes to access keys as they may be rotated externally
    ignore_changes = [
      primary_access_key,
      secondary_access_key
    ]
  }
}

# =============================================================================
# Table Storage
# =============================================================================

# Create storage table for todo items with optimized configuration
resource "azurerm_storage_table" "todos" {
  name                 = var.table_name
  storage_account_name = azurerm_storage_account.todo_api.name

  # Add access control lists for enhanced security (optional)
  # acl {
  #   id = "todo-api-policy"
  #   access_policy {
  #     expiry      = "2025-12-31T23:59:59.0000000Z"
  #     permissions = "raud"
  #     start       = "2024-01-01T00:00:00.0000000Z"
  #   }
  # }

  depends_on = [
    azurerm_storage_account.todo_api
  ]

  lifecycle {
    # Prevent accidental deletion of table data
    prevent_destroy = false
  }
}

# =============================================================================
# Application Insights (Optional)
# =============================================================================

# Create Log Analytics workspace for Application Insights
resource "azurerm_log_analytics_workspace" "todo_api" {
  count = var.enable_application_insights ? 1 : 0

  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.todo_api.name
  location           = azurerm_resource_group.todo_api.location
  sku                = "PerGB2018"
  retention_in_days  = var.application_insights_retention_days

  tags = merge(var.tags, {
    ResourceType = "Log Analytics Workspace"
    Purpose      = "Application Insights backend storage"
  })
}

# Create Application Insights for Function App monitoring
resource "azurerm_application_insights" "todo_api" {
  count = var.enable_application_insights ? 1 : 0

  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.todo_api.name
  location           = azurerm_resource_group.todo_api.location
  workspace_id       = azurerm_log_analytics_workspace.todo_api[0].id
  application_type   = "web"

  # Configure sampling to optimize costs while maintaining visibility
  daily_data_cap_in_gb                  = 1
  daily_data_cap_notifications_disabled = false
  retention_in_days                     = var.application_insights_retention_days

  tags = merge(var.tags, {
    ResourceType = "Application Insights"
    Purpose      = "Function App monitoring and diagnostics"
  })
}

# =============================================================================
# App Service Plan
# =============================================================================

# Create App Service Plan for Azure Functions
# Uses Consumption plan (Y1) by default for cost optimization
resource "azurerm_service_plan" "todo_api" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.todo_api.name
  location           = azurerm_resource_group.todo_api.location
  
  # Configure OS and SKU based on requirements
  os_type  = "Windows"
  sku_name = var.function_app_service_plan_sku

  # Enable per-site scaling for better resource utilization
  per_site_scaling_enabled = var.function_app_service_plan_sku != "Y1" ? true : null

  tags = merge(var.tags, {
    ResourceType = "App Service Plan"
    Purpose      = "Hosting plan for Function App"
    PlanType     = var.function_app_service_plan_sku == "Y1" ? "Consumption" : "Dedicated/Premium"
  })
}

# =============================================================================
# Azure Function App
# =============================================================================

# Create Windows Function App with comprehensive configuration
resource "azurerm_windows_function_app" "todo_api" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.todo_api.name
  location           = azurerm_resource_group.todo_api.location
  service_plan_id    = azurerm_service_plan.todo_api.id

  # Storage configuration for Function App
  storage_account_name       = azurerm_storage_account.todo_api.name
  storage_account_access_key = azurerm_storage_account.todo_api.primary_access_key

  # Function App configuration
  functions_extension_version = var.functions_extension_version
  builtin_logging_enabled    = var.enable_builtin_logging
  client_certificate_enabled = var.client_certificate_enabled
  https_only                 = var.https_only
  
  # Consumption plan specific settings
  daily_memory_time_quota = var.function_app_service_plan_sku == "Y1" ? var.daily_memory_time_quota : null

  # Configure Function App settings
  app_settings = merge(
    {
      # Azure Functions runtime configuration
      "FUNCTIONS_WORKER_RUNTIME"              = "node"
      "WEBSITE_NODE_DEFAULT_VERSION"          = var.node_version
      "FUNCTIONS_EXTENSION_VERSION"           = var.functions_extension_version
      
      # Storage connection for todo data
      "AZURE_STORAGE_CONNECTION_STRING"       = azurerm_storage_account.todo_api.primary_connection_string
      
      # Table Storage configuration
      "TODO_TABLE_NAME"                       = azurerm_storage_table.todos.name
      
      # Performance and reliability settings
      "WEBSITE_RUN_FROM_PACKAGE"              = "1"
      "WEBSITE_ENABLE_SYNC_UPDATE_SITE"       = "true"
      "WEBSITE_TIME_ZONE"                     = "UTC"
      
      # Security headers
      "WEBSITE_HTTPLOGGING_RETENTION_DAYS"    = "7"
      
      # Environment identification
      "ENVIRONMENT"                           = var.environment
      "PROJECT_NAME"                          = var.project_name
    },
    # Add Application Insights configuration if enabled
    var.enable_application_insights ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.todo_api[0].connection_string
      "APPINSIGHTS_INSTRUMENTATIONKEY"       = azurerm_application_insights.todo_api[0].instrumentation_key
    } : {},
    # Add custom zip deploy setting if specified
    var.function_app_zip_deploy_file != null ? {
      "WEBSITE_RUN_FROM_PACKAGE" = "1"
    } : {}
  )

  # Configure site settings
  site_config {
    # Runtime configuration
    always_on = var.function_app_service_plan_sku != "Y1" ? var.always_on : false
    
    # Application stack configuration
    application_stack {
      node_version = var.node_version
    }
    
    # Security configuration
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version              = "1.2"
    scm_minimum_tls_version          = "1.2"
    use_32_bit_worker                = false
    
    # CORS configuration for cross-origin requests
    cors {
      allowed_origins      = var.cors_allowed_origins
      support_credentials  = var.cors_support_credentials
    }
    
    # Health check configuration (if specified)
    health_check_path                = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    
    # Application Insights integration
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.todo_api[0].connection_string : null
    application_insights_key              = var.enable_application_insights ? azurerm_application_insights.todo_api[0].instrumentation_key : null
  }

  # Optional: Deploy function code from ZIP file
  zip_deploy_file = var.function_app_zip_deploy_file

  # System-assigned managed identity for secure Azure resource access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    ResourceType    = "Function App"
    Purpose         = "Serverless Todo API"
    Runtime         = "Node.js ${var.node_version}"
    PlanType        = var.function_app_service_plan_sku == "Y1" ? "Consumption" : "Dedicated/Premium"
    APIVersion      = "v1"
  })

  # Dependencies
  depends_on = [
    azurerm_service_plan.todo_api,
    azurerm_storage_account.todo_api,
    azurerm_storage_table.todos,
    azurerm_application_insights.todo_api
  ]

  lifecycle {
    # Ignore changes to app settings that may be updated by deployments
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
      zip_deploy_file
    ]
    
    # Prevent accidental deletion
    prevent_destroy = false
  }
}

# =============================================================================
# Storage Account IAM (Optional - for enhanced security)
# =============================================================================

# Grant Function App managed identity access to storage account
resource "azurerm_role_assignment" "function_app_storage" {
  scope                = azurerm_storage_account.todo_api.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_windows_function_app.todo_api.identity[0].principal_id

  depends_on = [
    azurerm_windows_function_app.todo_api
  ]
}

# =============================================================================
# Resource Monitoring and Diagnostics
# =============================================================================

# Configure diagnostic settings for Function App (if Application Insights is enabled)
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count = var.enable_application_insights ? 1 : 0

  name                       = "diag-${azurerm_windows_function_app.todo_api.name}"
  target_resource_id         = azurerm_windows_function_app.todo_api.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.todo_api[0].id

  # Configure logs to collect
  enabled_log {
    category = "FunctionAppLogs"
  }

  # Configure metrics to collect
  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azurerm_windows_function_app.todo_api,
    azurerm_log_analytics_workspace.todo_api
  ]
}
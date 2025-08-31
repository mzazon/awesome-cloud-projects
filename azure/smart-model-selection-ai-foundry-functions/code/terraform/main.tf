# Smart Model Selection with AI Foundry and Functions - Main Infrastructure
# This Terraform configuration deploys a complete smart model selection system
# using Azure AI Foundry Model Router, Functions, and Storage analytics

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = var.tags
}

# Create Azure AI Services (AI Foundry) resource
resource "azurerm_cognitive_account" "ai_foundry" {
  name                = var.custom_domain_name != null ? var.custom_domain_name : "${var.project_name}-ai-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "AIServices"
  sku_name            = var.ai_services_sku
  
  # Enable custom domain for Model Router functionality
  custom_question_answering_search_service_id = null
  
  # Configure public network access
  public_network_access_enabled = var.enable_private_endpoints ? false : true
  
  # Configure local authentication
  local_auth_enabled = true
  
  tags = merge(var.tags, {
    service = "ai-foundry"
  })
}

# Deploy Model Router to AI Services
resource "azurerm_cognitive_deployment" "model_router" {
  name                 = "model-router"
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id
  
  model {
    format  = "OpenAI"
    name    = "model-router"
    version = "2025-05-19"
  }
  
  scale {
    type     = "GlobalStandard"
    capacity = var.model_router_capacity
  }
  
  depends_on = [azurerm_cognitive_account.ai_foundry]
}

# Create Storage Account for analytics and function storage
resource "azurerm_storage_account" "main" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable blob versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Configure minimum TLS version for security
  min_tls_version = "TLS1_2"
  
  tags = merge(var.tags, {
    service = "storage"
  })
}

# Create Storage Tables for analytics data
resource "azurerm_storage_table" "model_metrics" {
  name                 = "modelmetrics"
  storage_account_name = azurerm_storage_account.main.name
}

resource "azurerm_storage_table" "cost_tracking" {
  name                 = "costtracking"
  storage_account_name = azurerm_storage_account.main.name
}

# Create Application Insights for monitoring (conditional)
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  
  tags = merge(var.tags, {
    service = "monitoring"
  })
}

# Create Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "plan-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_plan_sku
  
  tags = merge(var.tags, {
    service = "compute"
  })
}

# Create Function App
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Configure Function App settings
  site_config {
    always_on = var.function_app_plan_sku != "Y1" ? var.function_app_always_on : false
    
    application_stack {
      python_version = "3.11"
    }
    
    # Configure CORS if needed
    cors {
      allowed_origins = var.allowed_origins
    }
    
    # Enable Application Insights if configured
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  }
  
  # Configure application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "AI_FOUNDRY_ENDPOINT"         = azurerm_cognitive_account.ai_foundry.endpoint
    "AI_FOUNDRY_KEY"              = azurerm_cognitive_account.ai_foundry.primary_access_key
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    "ENABLE_ORYX_BUILD"           = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }
  
  # Enable system-assigned managed identity if configured
  dynamic "identity" {
    for_each = var.enable_system_assigned_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  # Configure VNet integration if subnet provided
  dynamic "site_config" {
    for_each = var.subnet_id != null ? [1] : []
    content {
      vnet_route_all_enabled = true
    }
  }
  
  tags = merge(var.tags, {
    service = "serverless"
  })
  
  depends_on = [
    azurerm_cognitive_deployment.model_router,
    azurerm_storage_table.model_metrics,
    azurerm_storage_table.cost_tracking
  ]
}

# Configure VNet integration if subnet provided
resource "azurerm_app_service_virtual_network_swift_connection" "main" {
  count          = var.subnet_id != null ? 1 : 0
  app_service_id = azurerm_linux_function_app.main.id
  subnet_id      = var.subnet_id
}

# Create backup configuration if enabled
resource "azurerm_app_service_backup" "main" {
  count               = var.enable_backup ? 1 : 0
  name                = "backup-${var.project_name}"
  app_service_name    = azurerm_linux_function_app.main.name
  resource_group_name = azurerm_resource_group.main.name
  storage_account_url = "https://${azurerm_storage_account.main.name}.blob.core.windows.net/backups?${azurerm_storage_account.main.primary_access_key}"
  
  schedule {
    frequency_interval       = 1
    frequency_unit          = "Day"
    keep_at_least_one_backup = true
    retention_period_in_days = var.backup_retention_days
  }
}

# Create private endpoint for AI Services if enabled
resource "azurerm_private_endpoint" "ai_foundry" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_cognitive_account.ai_foundry.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.subnet_id
  
  private_service_connection {
    name                           = "psc-ai-foundry"
    private_connection_resource_id = azurerm_cognitive_account.ai_foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }
  
  tags = merge(var.tags, {
    service = "networking"
  })
}

# Create private endpoint for Storage Account if enabled
resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.main.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.subnet_id
  
  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  
  tags = merge(var.tags, {
    service = "networking"
  })
}

# Create diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count              = var.enable_application_insights ? 1 : 0
  name               = "diag-${azurerm_linux_function_app.main.name}"
  target_resource_id = azurerm_linux_function_app.main.id
  
  log_analytics_workspace_id = azurerm_application_insights.main[0].id
  
  log {
    category = "FunctionAppLogs"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Create diagnostic settings for AI Services
resource "azurerm_monitor_diagnostic_setting" "ai_foundry" {
  count              = var.enable_application_insights ? 1 : 0
  name               = "diag-${azurerm_cognitive_account.ai_foundry.name}"
  target_resource_id = azurerm_cognitive_account.ai_foundry.id
  
  log_analytics_workspace_id = azurerm_application_insights.main[0].id
  
  log {
    category = "Audit"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  log {
    category = "RequestResponse"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Output values for verification and integration
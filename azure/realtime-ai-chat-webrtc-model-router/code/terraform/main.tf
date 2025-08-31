# Real-time AI Chat with WebRTC and Model Router - Main Infrastructure

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "${local.resource_prefix}-rg-${local.random_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "st${replace(local.resource_prefix, "-", "")}${local.random_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Minimum TLS version for security
  min_tls_version = "TLS1_2"
  
  tags = local.common_tags
}

# Create Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                = "${local.resource_prefix}-openai-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Custom subdomain required for OpenAI service
  custom_subdomain_name = "${local.resource_prefix}-openai-${local.random_suffix}"
  
  # Enable local authentication for API key access
  local_auth_enabled = true
  
  # Enable public network access (can be restricted in production)
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Deploy GPT-4o-mini-realtime model for cost-effective interactions
resource "azurerm_cognitive_deployment" "gpt_4o_mini_realtime" {
  name                 = "gpt-4o-mini-realtime"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini-realtime-preview"
    version = "2024-12-17"
  }
  
  sku {
    name     = "GlobalStandard"
    capacity = var.gpt_4o_mini_capacity
  }
}

# Deploy GPT-4o-realtime model for complex interactions
resource "azurerm_cognitive_deployment" "gpt_4o_realtime" {
  name                 = "gpt-4o-realtime"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = "gpt-4o-realtime-preview"
    version = "2024-12-17"
  }
  
  sku {
    name     = "GlobalStandard"
    capacity = var.gpt_4o_capacity
  }
  
  # Ensure mini model is deployed first for dependency management
  depends_on = [azurerm_cognitive_deployment.gpt_4o_mini_realtime]
}

# Create Azure SignalR Service for real-time communication
resource "azurerm_signalr_service" "main" {
  name                = "${local.resource_prefix}-signalr-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku {
    name     = var.signalr_sku.name
    capacity = var.signalr_sku.capacity
  }
  
  # Serverless mode for Azure Functions integration
  service_mode = "Serverless"
  
  # Enable message logs for debugging and monitoring
  features {
    flag  = "ServiceMode"
    value = "Serverless"
  }
  
  features {
    flag  = "EnableMessagingLogs"
    value = "true"
  }
  
  tags = local.common_tags
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  name                = "${local.resource_prefix}-plan-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Use Linux OS for better Node.js support and cost efficiency
  os_type = "Linux"
  
  # Set SKU based on variable (Y1 for Consumption, EP1-EP3 for Premium)
  sku_name = var.function_app_plan_sku
  
  tags = local.common_tags
}

# Create Function App for model routing and SignalR management
resource "azurerm_linux_function_app" "router" {
  name                = "${local.resource_prefix}-func-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  # Connect to storage account for function execution
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Enable system-assigned managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  # Configure Node.js 18 runtime for latest features
  site_config {
    application_stack {
      node_version = "18"
    }
    
    # Enable CORS for web client access
    cors {
      allowed_origins = ["*"]  # Restrict in production
      support_credentials = false
    }
    
    # Enable Application Insights for monitoring
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key              = azurerm_application_insights.main.instrumentation_key
  }
  
  # Application settings for function configuration
  app_settings = {
    # SignalR Service connection
    "AzureSignalRConnectionString" = azurerm_signalr_service.main.primary_connection_string
    
    # Azure OpenAI configuration
    "AZURE_OPENAI_ENDPOINT" = azurerm_cognitive_account.openai.endpoint
    "AZURE_OPENAI_KEY"      = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_API_VERSION"    = "2025-04-01-preview"
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME" = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    
    # Enable detailed logging for debugging
    "AZURE_FUNCTIONS_ENVIRONMENT" = var.environment
  }
  
  tags = local.common_tags
  
  # Ensure dependencies are created first
  depends_on = [
    azurerm_cognitive_deployment.gpt_4o_realtime,
    azurerm_signalr_service.main
  ]
}

# Create Application Insights for monitoring and analytics
resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-ai-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  
  # Set retention policy for logs
  retention_in_days = var.log_retention_days
  
  # Disable IP masking for better analytics (consider privacy implications)
  disable_ip_masking = false
  
  tags = local.common_tags
}

# Create Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostic_logs ? 1 : 0
  name                = "${local.resource_prefix}-law-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Configure diagnostic settings for Azure OpenAI
resource "azurerm_monitor_diagnostic_setting" "openai" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "openai-diagnostics"
  target_resource_id = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable all available log categories
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  # Enable all available metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for SignalR Service
resource "azurerm_monitor_diagnostic_setting" "signalr" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "signalr-diagnostics"
  target_resource_id = azurerm_signalr_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable SignalR-specific log categories
  enabled_log {
    category = "AllLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "function-app-diagnostics"
  target_resource_id = azurerm_linux_function_app.router.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable Function App log categories
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
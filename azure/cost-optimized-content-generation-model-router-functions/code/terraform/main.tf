# Main Terraform configuration for cost-optimized content generation solution
# This file creates the complete Azure infrastructure for AI-powered content generation
# using Model Router for cost optimization and Azure Functions for serverless processing

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create the main resource group for all resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.tags, {
    CreatedBy     = "Terraform"
    LastModified  = timestamp()
    ResourceType  = "ResourceGroup"
  })
}

# Create Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.application_insights_retention_days
  
  tags = merge(var.tags, {
    ResourceType = "LogAnalyticsWorkspace"
    Purpose      = "Monitoring and Diagnostics"
  })
}

# Create Application Insights for Function App monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  
  tags = merge(var.tags, {
    ResourceType = "ApplicationInsights"
    Purpose      = "Function App Monitoring"
  })
}

# Create Azure AI Foundry (Cognitive Services) resource for Model Router
resource "azurerm_cognitive_account" "ai_foundry" {
  name                = "aif-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "AIServices"
  sku_name            = var.ai_foundry_sku
  
  # Enable custom subdomain for API access
  custom_question_answering_search_service_id = null
  custom_question_answering_search_service_key = null
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    # In production, consider restricting to specific IP ranges
    ip_rules       = []
    virtual_network_rules {
      subnet_id                            = null
      ignore_missing_vnet_service_endpoint = false
    }
  }
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    ResourceType = "CognitiveServices"
    Purpose      = "AI Foundry with Model Router"
  })
}

# Deploy Model Router for cost-optimized model selection
resource "azurerm_cognitive_deployment" "model_router" {
  name                 = "model-router-deployment"
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id
  
  model {
    format  = "OpenAI"
    name    = "model-router"
    version = "2025-01-25"
  }
  
  scale {
    type     = "Standard"
    capacity = var.model_router_capacity
  }
  
  depends_on = [azurerm_cognitive_account.ai_foundry]
}

# Create storage account for content processing and storage
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.storage_access_tier
  
  # Security configurations
  min_tls_version                = var.minimum_tls_version
  enable_https_traffic_only      = var.enable_https_only
  allow_nested_items_to_be_public = false
  
  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  # Identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    ResourceType = "StorageAccount"
    Purpose      = "Content Processing Storage"
  })
}

# Create blob containers for content workflow
resource "azurerm_storage_container" "content_requests" {
  name                  = "content-requests"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "generated_content" {
  name                  = "generated-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create Service Plan for Function Apps (Consumption plan)
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_os_type
  sku_name            = "Y1" # Consumption plan for serverless execution
  
  tags = merge(var.tags, {
    ResourceType = "ServicePlan"
    Purpose      = "Serverless Function Hosting"
  })
}

# Create Function App for content processing
resource "azurerm_linux_function_app" "main" {
  count               = var.function_app_os_type == "Linux" ? 1 : 0
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function runtime configuration
  site_config {
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      python_version = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
      dotnet_version = var.function_app_runtime == "dotnet" ? var.function_app_runtime_version : null
      java_version = var.function_app_runtime == "java" ? var.function_app_runtime_version : null
    }
    
    # Performance and scaling configuration
    app_scale_limit                = var.enable_auto_scaling ? 200 : 10
    elastic_instance_minimum       = 0
    pre_warmed_instance_count      = 1
    runtime_scale_monitoring_enabled = var.enable_auto_scaling
    
    # Security configuration
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version
    
    # CORS configuration for web access
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    }
  }
  
  # Application settings for AI integration and configuration
  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"     = "~4"
    "FUNCTIONS_WORKER_RUNTIME"        = var.function_app_runtime
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"  = "false"
    
    # Application Insights integration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # AI Foundry configuration
    "AI_FOUNDRY_ENDPOINT"        = azurerm_cognitive_account.ai_foundry.endpoint
    "AI_FOUNDRY_KEY"            = azurerm_cognitive_account.ai_foundry.primary_access_key
    "MODEL_DEPLOYMENT_NAME"     = azurerm_cognitive_deployment.model_router.name
    
    # Storage configuration
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    "AzureWebJobsStorage"      = azurerm_storage_account.main.primary_connection_string
    
    # Function timeout configuration
    "WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT" = var.enable_auto_scaling ? "200" : "10"
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS"        = "7"
    "WEBSITE_CONTENTOVERVNET"                   = "0"
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # HTTPS-only configuration
  https_only = var.enable_https_only
  
  tags = merge(var.tags, {
    ResourceType = "FunctionApp"
    Purpose      = "Content Processing Functions"
  })
  
  depends_on = [
    azurerm_application_insights.main,
    azurerm_cognitive_account.ai_foundry,
    azurerm_storage_account.main
  ]
}

# Create Windows Function App if specified
resource "azurerm_windows_function_app" "main" {
  count               = var.function_app_os_type == "Windows" ? 1 : 0
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function runtime configuration
  site_config {
    application_stack {
      node_version               = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      python_version            = var.function_app_runtime == "python" ? var.function_app_runtime_version : null
      dotnet_version            = var.function_app_runtime == "dotnet" ? var.function_app_runtime_version : null
      java_version              = var.function_app_runtime == "java" ? var.function_app_runtime_version : null
      use_dotnet_isolated_runtime = var.function_app_runtime == "dotnet" ? true : false
    }
    
    # Performance and scaling configuration
    app_scale_limit                = var.enable_auto_scaling ? 200 : 10
    elastic_instance_minimum       = 0
    pre_warmed_instance_count      = 1
    runtime_scale_monitoring_enabled = var.enable_auto_scaling
    
    # Security configuration
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version
    
    # CORS configuration
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    }
  }
  
  # Application settings (same as Linux Function App)
  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"     = "~4"
    "FUNCTIONS_WORKER_RUNTIME"        = var.function_app_runtime
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"  = "false"
    
    # Application Insights integration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # AI Foundry configuration
    "AI_FOUNDRY_ENDPOINT"        = azurerm_cognitive_account.ai_foundry.endpoint
    "AI_FOUNDRY_KEY"            = azurerm_cognitive_account.ai_foundry.primary_access_key
    "MODEL_DEPLOYMENT_NAME"     = azurerm_cognitive_deployment.model_router.name
    
    # Storage configuration
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    "AzureWebJobsStorage"      = azurerm_storage_account.main.primary_connection_string
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # HTTPS-only configuration
  https_only = var.enable_https_only
  
  tags = merge(var.tags, {
    ResourceType = "FunctionApp"
    Purpose      = "Content Processing Functions"
  })
  
  depends_on = [
    azurerm_application_insights.main,
    azurerm_cognitive_account.ai_foundry,
    azurerm_storage_account.main
  ]
}

# Get the correct Function App resource based on OS type
locals {
  function_app = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0] : azurerm_windows_function_app.main[0]
}

# Create Event Grid System Topic for storage events
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "egt-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.main.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  
  tags = merge(var.tags, {
    ResourceType = "EventGridSystemTopic"
    Purpose      = "Storage Event Processing"
  })
}

# Create Event Grid subscription for blob created events
resource "azurerm_eventgrid_event_subscription" "content_processing" {
  name  = "content-processing-subscription"
  scope = azurerm_eventgrid_system_topic.storage.id
  
  # Configure Azure Function as the event handler
  azure_function_endpoint {
    function_id                       = "${local.function_app.id}/functions/ContentAnalyzer"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Filter events to content-requests container only
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/content-requests/"
    case_sensitive      = false
  }
  
  # Include specific event types
  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]
  
  # Retry policy configuration
  retry_policy {
    max_delivery_attempts = var.event_grid_retry_policy.max_delivery_attempts
    event_time_to_live    = var.event_grid_retry_policy.event_time_to_live
  }
  
  # Dead letter configuration (optional)
  # dead_letter_identity {
  #   type = "SystemAssigned"
  # }
  
  depends_on = [
    azurerm_eventgrid_system_topic.storage,
    local.function_app
  ]
}

# Role assignments for secure resource access
# Grant Function App access to AI Foundry
resource "azurerm_role_assignment" "function_ai_foundry" {
  scope                = azurerm_cognitive_account.ai_foundry.id
  role_definition_name = "Cognitive Services User"
  principal_id         = local.function_app.identity[0].principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.function_app.identity[0].principal_id
}

# Create Action Group for budget alerts
resource "azurerm_monitor_action_group" "budget_alerts" {
  name                = "ag-budget-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "budgetalert"
  
  email_receiver {
    name                    = "budget-alert-email"
    email_address          = var.admin_email
    use_common_alert_schema = true
  }
  
  tags = merge(var.tags, {
    ResourceType = "ActionGroup"
    Purpose      = "Budget Alert Notifications"
  })
}

# Create budget for cost monitoring
resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${var.project_name}-${var.environment}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = var.budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h")) # 1 year from now
  }
  
  notification {
    enabled        = true
    threshold      = var.budget_alert_threshold
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = [var.admin_email]
  }
  
  notification {
    enabled        = true
    threshold      = var.budget_alert_threshold - 10 # 10% before main threshold
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = [var.admin_email]
  }
}

# Create diagnostic settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "diag-${local.function_app.name}"
  target_resource_id         = local.function_app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = [
      "FunctionAppLogs",
      "AppServiceHTTPLogs",
      "AppServiceConsoleLogs",
      "AppServiceAppLogs",
      "AppServiceAuditLogs",
      "AppServiceIPSecAuditLogs",
      "AppServicePlatformLogs"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "diag-${azurerm_storage_account.main.name}"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = [
      "StorageRead",
      "StorageWrite",
      "StorageDelete"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "ai_foundry" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "diag-${azurerm_cognitive_account.ai_foundry.name}"
  target_resource_id         = azurerm_cognitive_account.ai_foundry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = [
      "Audit",
      "RequestResponse",
      "Trace"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
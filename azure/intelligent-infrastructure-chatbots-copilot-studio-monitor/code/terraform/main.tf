# Azure Infrastructure Chatbot Solution - Main Terraform Configuration
# This configuration deploys Azure resources for an intelligent infrastructure monitoring chatbot
# using Azure Copilot Studio, Azure Monitor, and Azure Functions

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all chatbot infrastructure
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.tags, {
    Component = "Infrastructure Chatbot"
  })
}

# Create Log Analytics Workspace for centralized monitoring and query processing
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    Component = "Monitoring and Analytics"
    Purpose   = "Query processing and log aggregation"
  })
}

# Create Application Insights for Function App monitoring and telemetry
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = var.application_insights_name != "" ? var.application_insights_name : "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = merge(var.tags, {
    Component = "Application Monitoring"
    Purpose   = "Function App telemetry and performance monitoring"
  })
}

# Create Storage Account for Azure Functions runtime and deployment packages
resource "azurerm_storage_account" "functions" {
  name                     = var.storage_account_name != "" ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Configure blob properties for optimal Function App performance
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(var.tags, {
    Component = "Function Storage"
    Purpose   = "Azure Functions runtime and deployment storage"
  })
}

# Create Service Plan for Azure Functions (Consumption plan for cost optimization)
resource "azurerm_service_plan" "functions" {
  name                = "sp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_plan_sku
  
  tags = merge(var.tags, {
    Component = "Compute Plan"
    Purpose   = "Serverless compute for query processing"
  })
}

# Create Azure Functions App for query processing and Azure Monitor integration
resource "azurerm_linux_function_app" "main" {
  name                = var.function_app_name != "" ? var.function_app_name : "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.functions.id
  
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  
  # Configure Function App settings for Python runtime and Azure Monitor integration
  site_config {
    application_stack {
      python_version = var.python_version
    }
    
    # Enable CORS for Copilot Studio integration
    cors {
      allowed_origins     = ["https://powerva.microsoft.com", "https://web.powerva.microsoft.com"]
      support_credentials = true
    }
    
    # Security and performance optimizations
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"
  }
  
  # Configure application settings for Azure Monitor integration
  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"        = "python"
    "FUNCTIONS_EXTENSION_VERSION"     = var.function_runtime_version
    "LOG_ANALYTICS_WORKSPACE_ID"      = azurerm_log_analytics_workspace.main.workspace_id
    "AZURE_CLIENT_ID"                 = var.enable_managed_identity ? "system" : ""
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "1"
    "ENABLE_ORYX_BUILD"               = "true"
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
  }, var.enable_application_insights ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  # Enable system-assigned managed identity for secure Azure Monitor access
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = merge(var.tags, {
    Component = "Query Processor"
    Purpose   = "Natural language to KQL query processing"
  })
  
  depends_on = [
    azurerm_service_plan.functions,
    azurerm_storage_account.functions,
    azurerm_log_analytics_workspace.main
  ]
}

# Create custom role for Log Analytics Reader with specific permissions
resource "azurerm_role_definition" "log_analytics_query_reader" {
  count = var.enable_managed_identity ? 1 : 0
  
  name  = "Log Analytics Query Reader - ${random_string.suffix.result}"
  scope = azurerm_resource_group.main.id
  
  description = "Custom role for Function App to read Log Analytics workspace data for chatbot queries"
  
  permissions {
    actions = [
      "Microsoft.OperationalInsights/workspaces/read",
      "Microsoft.OperationalInsights/workspaces/query/read",
      "Microsoft.OperationalInsights/workspaces/search/read"
    ]
    not_actions = []
  }
  
  assignable_scopes = [
    azurerm_resource_group.main.id
  ]
}

# Assign Log Analytics Reader role to Function App managed identity
resource "azurerm_role_assignment" "function_log_analytics" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_id   = azurerm_role_definition.log_analytics_query_reader[0].role_definition_resource_id
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_role_definition.log_analytics_query_reader
  ]
}

# Assign Monitoring Reader role for broader Azure Monitor access
resource "azurerm_role_assignment" "function_monitoring_reader" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope              = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Reader"
  principal_id       = azurerm_linux_function_app.main.identity[0].principal_id
  principal_type     = "ServicePrincipal"
  
  depends_on = [azurerm_linux_function_app.main]
}

# Create Function App deployment package with query processing code
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function_app.zip"
  
  source {
    content = templatefile("${path.module}/function_code/QueryProcessor/__init__.py", {
      workspace_id = azurerm_log_analytics_workspace.main.workspace_id
    })
    filename = "QueryProcessor/__init__.py"
  }
  
  source {
    content  = file("${path.module}/function_code/QueryProcessor/function.json")
    filename = "QueryProcessor/function.json"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
  
  source {
    content  = file("${path.module}/function_code/host.json")
    filename = "host.json"
  }
}

# Create storage container for function deployment
resource "azurerm_storage_container" "deployments" {
  name                  = "function-deployments"
  storage_account_name  = azurerm_storage_account.functions.name
  container_access_type = "private"
}

# Upload function code to storage blob
resource "azurerm_storage_blob" "function_code" {
  name                   = "function-${formatdate("YYYYMMDD-hhmmss", timestamp())}.zip"
  storage_account_name   = azurerm_storage_account.functions.name
  storage_container_name = azurerm_storage_container.deployments.name
  type                   = "Block"
  source                 = data.archive_file.function_code.output_path
  
  depends_on = [
    azurerm_storage_container.deployments,
    data.archive_file.function_code
  ]
}

# Create sample monitoring alerts for demonstration
resource "azurerm_monitor_action_group" "chatbot_alerts" {
  name                = "ag-${var.project_name}-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "chatbot"
  
  # Configure webhook notification for Function App integration
  webhook_receiver {
    name                    = "chatbot-webhook"
    service_uri             = "https://${azurerm_linux_function_app.main.default_hostname}/api/AlertProcessor"
    use_common_alert_schema = true
  }
  
  tags = merge(var.tags, {
    Component = "Alert Management"
    Purpose   = "Proactive alert processing for chatbot integration"
  })
}

# Create sample metric alert for high CPU usage
resource "azurerm_monitor_metric_alert" "high_cpu_usage" {
  name                = "High CPU Usage Alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_resource_group.main.id]
  description         = "Alert when CPU usage exceeds 80% for infrastructure resources"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.chatbot_alerts.id
  }
  
  tags = merge(var.tags, {
    Component = "Monitoring Alerts"
    AlertType = "Performance"
  })
}
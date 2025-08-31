# Main Terraform configuration for Azure Marketing Asset Generation
# This configuration creates a complete automated marketing content generation system
# using Azure OpenAI, Content Safety, Functions, and Blob Storage

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent resource naming and tagging
locals {
  # Resource naming with unique suffix
  resource_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    CreatedOn   = timestamp()
  })
  
  # Storage account name (must be globally unique and alphanumeric)
  storage_account_name = "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all marketing automation resources
resource "azurerm_resource_group" "marketing_rg" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${local.resource_prefix}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for marketing assets and workflow data
resource "azurerm_storage_account" "marketing_storage" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.marketing_rg.name
  location            = azurerm_resource_group.marketing_rg.location
  
  # Storage configuration for marketing assets
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier             = var.storage_access_tier
  
  # Security and compliance settings
  min_tls_version                 = var.minimum_tls_version
  https_traffic_only_enabled      = var.enable_https_only
  allow_nested_items_to_be_public = true
  
  # Enable blob versioning for content management
  blob_properties {
    versioning_enabled = true
    
    # Configure container delete retention
    delete_retention_policy {
      days = 7
    }
    
    # Configure blob delete retention
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create blob containers for marketing content workflow
resource "azurerm_storage_container" "marketing_containers" {
  for_each = var.marketing_containers
  
  name                  = each.value.name
  storage_account_name  = azurerm_storage_account.marketing_storage.name
  container_access_type = each.value.access_type
}

# Create Azure OpenAI Service for content generation
resource "azurerm_cognitive_account" "openai_service" {
  name                = "openai-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.marketing_rg.name
  location            = azurerm_resource_group.marketing_rg.location
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Enable custom subdomain for API access
  custom_subdomain_name = "openai-${local.resource_prefix}-${local.resource_suffix}"
  
  # Network access and security settings
  public_network_access_enabled = true
  
  tags = merge(local.common_tags, {
    Service = "OpenAI"
    Purpose = "Content Generation"
  })
  
  depends_on = [azurerm_resource_group.marketing_rg]
}

# Wait for OpenAI service to be fully provisioned before deploying models
resource "time_sleep" "wait_for_openai" {
  depends_on      = [azurerm_cognitive_account.openai_service]
  create_duration = "60s"
}

# Deploy GPT-4 model for text content generation
resource "azurerm_cognitive_deployment" "gpt4_deployment" {
  name                 = "gpt-4-marketing"
  cognitive_account_id = azurerm_cognitive_account.openai_service.id
  
  model {
    format  = "OpenAI"
    name    = "gpt-4"
    version = "0613"
  }
  
  scale {
    type     = "Standard"
    capacity = var.gpt4_deployment_capacity
  }
  
  depends_on = [time_sleep.wait_for_openai]
}

# Deploy DALL-E 3 model for image generation
resource "azurerm_cognitive_deployment" "dalle3_deployment" {
  name                 = "dalle-3-marketing"
  cognitive_account_id = azurerm_cognitive_account.openai_service.id
  
  model {
    format  = "OpenAI"
    name    = "dall-e-3"
    version = "3.0"
  }
  
  scale {
    type     = "Standard"
    capacity = var.dalle3_deployment_capacity
  }
  
  depends_on = [time_sleep.wait_for_openai]
}

# Create Azure Content Safety service for content moderation
resource "azurerm_cognitive_account" "content_safety" {
  name                = "cs-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.marketing_rg.name
  location            = azurerm_resource_group.marketing_rg.location
  kind                = "ContentSafety"
  sku_name            = var.content_safety_sku_name
  
  # Network access settings
  public_network_access_enabled = true
  
  tags = merge(local.common_tags, {
    Service = "Content Safety"
    Purpose = "Content Moderation"
  })
  
  depends_on = [azurerm_resource_group.marketing_rg]
}

# Create Application Insights for Function App monitoring
resource "azurerm_application_insights" "marketing_insights" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appi-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.marketing_rg.name
  location            = azurerm_resource_group.marketing_rg.location
  application_type    = "web"
  
  # Configure retention policy
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Service = "Application Insights"
    Purpose = "Monitoring"
  })
}

# Create Service Plan for Azure Functions (Consumption Plan)
resource "azurerm_service_plan" "marketing_plan" {
  name                = "asp-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.marketing_rg.name
  location            = azurerm_resource_group.marketing_rg.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = merge(local.common_tags, {
    Service = "App Service Plan"
    Purpose = "Serverless Hosting"
  })
}

# Create Linux Function App for marketing content orchestration
resource "azurerm_linux_function_app" "marketing_function" {
  name                = "func-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.marketing_rg.name
  location            = azurerm_resource_group.marketing_rg.location
  service_plan_id     = azurerm_service_plan.marketing_plan.id
  
  # Storage account for function runtime
  storage_account_name       = azurerm_storage_account.marketing_storage.name
  storage_account_access_key = azurerm_storage_account.marketing_storage.primary_access_key
  
  # Security and networking configuration
  https_only = var.enable_https_only
  
  # Function runtime configuration
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    # Function execution timeout
    function_app_scale_limit = 10
    
    # Enable Application Insights integration
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.marketing_insights[0].connection_string
      }
    }
    
    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.marketing_insights[0].instrumentation_key
      }
    }
  }
  
  # Application settings for service connections
  app_settings = {
    # Runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # Azure OpenAI configuration
    "AZURE_OPENAI_ENDPOINT" = azurerm_cognitive_account.openai_service.endpoint
    "AZURE_OPENAI_KEY"      = azurerm_cognitive_account.openai_service.primary_access_key
    
    # Content Safety configuration
    "CONTENT_SAFETY_ENDPOINT" = azurerm_cognitive_account.content_safety.endpoint
    "CONTENT_SAFETY_KEY"      = azurerm_cognitive_account.content_safety.primary_access_key
    
    # Storage configuration
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.marketing_storage.primary_connection_string
    
    # Content safety threshold
    "CONTENT_SAFETY_THRESHOLD" = var.content_safety_severity_threshold
    
    # Model deployment names
    "GPT4_DEPLOYMENT_NAME"   = azurerm_cognitive_deployment.gpt4_deployment.name
    "DALLE3_DEPLOYMENT_NAME" = azurerm_cognitive_deployment.dalle3_deployment.name
    
    # Function timeout configuration
    "FUNCTIONS_TIMEOUT" = "${var.function_timeout_minutes}:00"
    
    # Application Insights settings
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.marketing_insights[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.marketing_insights[0].connection_string : ""
  }
  
  # Enable managed identity for secure service access
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = merge(local.common_tags, {
    Service = "Azure Functions"
    Purpose = "Content Generation Orchestration"
  })
  
  depends_on = [
    azurerm_storage_account.marketing_storage,
    azurerm_cognitive_account.openai_service,
    azurerm_cognitive_account.content_safety,
    azurerm_cognitive_deployment.gpt4_deployment,
    azurerm_cognitive_deployment.dalle3_deployment
  ]
}

# Create RBAC assignments for managed identity (if enabled)
resource "azurerm_role_assignment" "storage_blob_contributor" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope                = azurerm_storage_account.marketing_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.marketing_function.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.marketing_function]
}

resource "azurerm_role_assignment" "cognitive_services_user" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope                = azurerm_resource_group.marketing_rg.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.marketing_function.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.marketing_function]
}

# Create budget for cost monitoring (if enabled)
resource "azurerm_consumption_budget_resource_group" "marketing_budget" {
  count = var.enable_cost_alerts ? 1 : 0
  
  name              = "budget-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_id = azurerm_resource_group.marketing_rg.id
  
  amount     = var.monthly_budget_limit
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h")) # 1 year from now
  }
  
  # Cost threshold notifications
  notification {
    enabled   = true
    threshold = 80
    operator  = "GreaterThan"
    
    contact_emails = []
  }
  
  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"
    
    contact_emails = []
  }
  
  depends_on = [azurerm_resource_group.marketing_rg]
}

# Create diagnostic settings for monitoring (if Application Insights is enabled)
resource "azurerm_monitor_diagnostic_setting" "function_diagnostics" {
  count = var.enable_application_insights ? 1 : 0
  
  name               = "diagnostics-${local.resource_prefix}-${local.resource_suffix}"
  target_resource_id = azurerm_linux_function_app.marketing_function.id
  
  log_analytics_workspace_id = azurerm_application_insights.marketing_insights[0].workspace_id
  
  # Function App specific logs
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Performance metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
  
  depends_on = [
    azurerm_linux_function_app.marketing_function,
    azurerm_application_insights.marketing_insights
  ]
}

# Output important resource information for validation and integration
output "deployment_summary" {
  description = "Summary of deployed marketing automation infrastructure"
  value = {
    resource_group_name = azurerm_resource_group.marketing_rg.name
    location           = azurerm_resource_group.marketing_rg.location
    
    storage_account = {
      name               = azurerm_storage_account.marketing_storage.name
      primary_endpoint   = azurerm_storage_account.marketing_storage.primary_blob_endpoint
      connection_string  = azurerm_storage_account.marketing_storage.primary_connection_string
    }
    
    openai_service = {
      name     = azurerm_cognitive_account.openai_service.name
      endpoint = azurerm_cognitive_account.openai_service.endpoint
    }
    
    content_safety = {
      name     = azurerm_cognitive_account.content_safety.name
      endpoint = azurerm_cognitive_account.content_safety.endpoint
    }
    
    function_app = {
      name = azurerm_linux_function_app.marketing_function.name
      url  = "https://${azurerm_linux_function_app.marketing_function.name}.azurewebsites.net"
    }
    
    containers = [for container in azurerm_storage_container.marketing_containers : container.name]
  }
}
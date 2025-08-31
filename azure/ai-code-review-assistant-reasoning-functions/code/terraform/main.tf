# Main Terraform configuration for AI Code Review Assistant with Reasoning and Functions
# This file creates all the Azure resources required for the code review system

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    ResourceType = "ResourceGroup"
  })
}

# Create Storage Account for code files and review reports
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Configure blob properties for versioning and soft delete
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.tags, {
    ResourceType = "StorageAccount"
    Purpose      = "CodeFilesAndReports"
  })
}

# Create blob container for code files
resource "azurerm_storage_container" "code_files" {
  name                  = "code-files"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.blob_container_access_type

  depends_on = [azurerm_storage_account.main]
}

# Create blob container for review reports
resource "azurerm_storage_container" "review_reports" {
  name                  = "review-reports"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.blob_container_access_type

  depends_on = [azurerm_storage_account.main]
}

# Create Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                = var.custom_domain_name != null ? var.custom_domain_name : "oai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name

  # Configure custom subdomain for API access
  custom_question_answering_search_service_id = null
  
  # Enable public network access (required for Function App integration)
  public_network_access_enabled = true
  
  # Configure network access rules
  network_acls {
    default_action = "Allow"
  }

  tags = merge(var.tags, {
    ResourceType = "CognitiveServices"
    ServiceType  = "OpenAI"
    Model        = "o1-mini"
  })
}

# Deploy o1-mini model for code analysis
resource "azurerm_cognitive_deployment" "o1_mini" {
  name                 = "o1-mini-code-review"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = "o1-mini"
    version = var.o1_mini_model_version
  }

  scale {
    type     = "Standard"
    capacity = var.o1_mini_deployment_capacity
  }

  depends_on = [azurerm_cognitive_account.openai]
}

# Create Application Insights for Function App monitoring (optional)
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 30

  tags = merge(var.tags, {
    ResourceType = "ApplicationInsights"
    Purpose      = "FunctionAppMonitoring"
  })
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku

  tags = merge(var.tags, {
    ResourceType = "AppServicePlan"
    Purpose      = "FunctionAppHosting"
  })
}

# Create Function App for code review processing
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id

  # Configure Function App settings
  site_config {
    always_on                              = var.function_app_service_plan_sku != "Y1" ? true : false
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null

    # Configure Python runtime
    application_stack {
      python_version = var.function_app_runtime_version
    }

    # Enable CORS for development (configure as needed for production)
    cors {
      allowed_origins = ["*"]
    }
  }

  # Configure application settings for OpenAI and Storage integration
  app_settings = {
    "AZURE_OPENAI_ENDPOINT"           = azurerm_cognitive_account.openai.endpoint
    "AZURE_OPENAI_KEY"               = azurerm_cognitive_account.openai.primary_access_key
    "AZURE_STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    "OPENAI_DEPLOYMENT_NAME"         = azurerm_cognitive_deployment.o1_mini.name
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
    
    # Application Insights settings (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
  }

  # Configure identity for secure access to other Azure resources
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    ResourceType = "FunctionApp"
    Runtime      = "Python"
    Purpose      = "CodeReviewProcessing"
  })

  depends_on = [
    azurerm_storage_account.main,
    azurerm_service_plan.main,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.o1_mini
  ]
}

# Grant Function App access to Storage Account (using system-assigned managed identity)
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# Grant Function App access to OpenAI Service (using system-assigned managed identity)
resource "azurerm_role_assignment" "function_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# Create diagnostic settings for Storage Account (optional)
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count              = var.enable_storage_logging ? 1 : 0
  name               = "diag-storage-${var.project_name}"
  target_resource_id = "${azurerm_storage_account.main.id}/blobServices/default"

  # Configure log analytics workspace if Application Insights is enabled
  log_analytics_workspace_id = var.enable_application_insights ? azurerm_application_insights.main[0].workspace_data_id : null

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }

  depends_on = [azurerm_storage_account.main]
}
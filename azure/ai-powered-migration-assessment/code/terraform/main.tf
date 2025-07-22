# ==============================================================================
# Azure AI-Powered Migration Assessment Infrastructure
# ==============================================================================

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# Resource Group
# ==============================================================================

# Primary resource group for all migration assessment resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.tags, {
    "Purpose"     = "AI-Powered Migration Assessment"
    "Environment" = var.environment
  })
}

# ==============================================================================
# Storage Account
# ==============================================================================

# Storage account for function app and assessment data
resource "azurerm_storage_account" "main" {
  name                     = "${var.storage_account_prefix}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Enable blob versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  # Enable secure transfer and TLS 1.2
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true

  # Network access configuration
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = merge(var.tags, {
    "Purpose" = "Migration Assessment Data Storage"
  })
}

# Storage containers for assessment data and AI insights
resource "azurerm_storage_container" "assessment_data" {
  name                  = "assessment-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "ai_insights" {
  name                  = "ai-insights"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "modernization_reports" {
  name                  = "modernization-reports"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ==============================================================================
# Azure OpenAI Service
# ==============================================================================

# Azure OpenAI Cognitive Services account
resource "azurerm_cognitive_account" "openai" {
  name                = "${var.openai_service_prefix}-${random_string.suffix.result}"
  location            = var.openai_location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = "S0"

  # Custom domain required for OpenAI
  custom_domain = "${var.openai_service_prefix}-${random_string.suffix.result}"

  # Network access configuration
  network_acls {
    default_action = "Allow"
    ip_rules       = var.openai_allowed_ips
  }

  # Enable public network access
  public_network_access_enabled = true

  tags = merge(var.tags, {
    "Purpose" = "AI Analysis for Migration Assessment"
  })
}

# GPT-4 model deployment for migration analysis
resource "azurerm_cognitive_deployment" "gpt4_migration" {
  name                 = "gpt-4-migration-analysis"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4"
    version = "0613"
  }

  scale {
    type     = "Standard"
    capacity = 20
  }

  # Ensure deployment happens after the cognitive account is ready
  depends_on = [azurerm_cognitive_account.openai]
}

# ==============================================================================
# Azure Migrate Project
# ==============================================================================

# Azure Migrate project for workload assessment
resource "azurerm_migrate_project" "main" {
  name                = "${var.migrate_project_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = merge(var.tags, {
    "Purpose" = "Workload Discovery and Assessment"
  })
}

# ==============================================================================
# Application Insights (for Function App monitoring)
# ==============================================================================

# Application Insights for function app monitoring and diagnostics
resource "azurerm_application_insights" "main" {
  name                = "${var.function_app_name}-insights-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"

  # Configure retention and sampling
  retention_in_days = 30
  sampling_percentage = 100

  tags = merge(var.tags, {
    "Purpose" = "Function App Monitoring"
  })
}

# ==============================================================================
# Azure Functions App Service Plan
# ==============================================================================

# App Service Plan for Function App (using consumption plan)
resource "azurerm_service_plan" "main" {
  name                = "${var.function_app_name}-plan-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan

  tags = merge(var.tags, {
    "Purpose" = "Serverless Function Hosting"
  })
}

# ==============================================================================
# Azure Function App
# ==============================================================================

# Function App for AI-powered assessment processing
resource "azurerm_linux_function_app" "main" {
  name                = "${var.function_app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id

  # Function app configuration
  site_config {
    application_stack {
      python_version = "3.11"
    }

    # Enable CORS for development
    cors {
      allowed_origins = ["*"]
    }

    # Configure function app settings
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }

  # Application settings for OpenAI integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "OPENAI_ENDPOINT"             = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"                  = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_MODEL_DEPLOYMENT"     = azurerm_cognitive_deployment.gpt4_migration.name
    "MIGRATE_PROJECT"             = azurerm_migrate_project.main.name
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
  }

  # Identity configuration for Azure resource access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    "Purpose" = "AI Assessment Processing"
  })
}

# ==============================================================================
# Function App Code Deployment
# ==============================================================================

# Create function app code package
data "archive_file" "function_app" {
  type        = "zip"
  output_path = "${path.module}/function-app.zip"
  
  source {
    content  = file("${path.module}/function_code/__init__.py")
    filename = "migrate-ai-assessment/__init__.py"
  }

  source {
    content  = file("${path.module}/function_code/function.json.tpl")
    filename = "migrate-ai-assessment/function.json"
  }

  source {
    content  = file("${path.module}/function_code/requirements.txt.tpl")
    filename = "requirements.txt"
  }

  source {
    content  = file("${path.module}/function_code/host.json.tpl")
    filename = "host.json"
  }
}

# Note: Function code deployment is handled through the archive_file data source
# The actual deployment can be done via Azure DevOps, GitHub Actions, or manually
# using the Azure CLI: az functionapp deployment source config-zip

# ==============================================================================
# RBAC Role Assignments
# ==============================================================================

# Grant Function App access to storage account
resource "azurerm_role_assignment" "function_storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Azure OpenAI
resource "azurerm_role_assignment" "function_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Azure Migrate
resource "azurerm_role_assignment" "function_migrate_contributor" {
  scope                = azurerm_migrate_project.main.id
  role_definition_name = "Migrate Project Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# ==============================================================================
# Monitoring and Diagnostics
# ==============================================================================

# Diagnostic settings for storage account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

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

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.function_app_name}-logs-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(var.tags, {
    "Purpose" = "Centralized Logging and Monitoring"
  })
}

# Diagnostic settings for OpenAI service
resource "azurerm_monitor_diagnostic_setting" "openai_diagnostics" {
  name                       = "openai-diagnostics"
  target_resource_id         = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "RequestResponse"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ==============================================================================
# Sample Assessment Data (for testing)
# ==============================================================================

# Upload sample assessment data for testing
resource "azurerm_storage_blob" "sample_assessment" {
  name                   = "sample-assessment.json"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.assessment_data.name
  type                   = "Block"
  source_content = jsonencode({
    "timestamp" = "2025-07-12T10:00:00Z"
    "project"   = azurerm_migrate_project.main.name
    "servers" = [
      {
        "name"                = "web-server-01"
        "os"                  = "Windows Server 2016"
        "cpu_cores"           = 4
        "memory_gb"           = 16
        "storage_gb"          = 500
        "network_utilization" = "medium"
        "applications"        = ["IIS", "ASP.NET"]
        "dependencies"        = ["sql-server-01", "file-server-01"]
        "performance_data" = {
          "cpu_utilization"     = 45
          "memory_utilization"  = 60
          "storage_utilization" = 70
        }
      },
      {
        "name"                = "sql-server-01"
        "os"                  = "Windows Server 2019"
        "cpu_cores"           = 8
        "memory_gb"           = 32
        "storage_gb"          = 1000
        "network_utilization" = "high"
        "applications"        = ["SQL Server 2019"]
        "dependencies"        = ["backup-server-01"]
        "performance_data" = {
          "cpu_utilization"     = 65
          "memory_utilization"  = 80
          "storage_utilization" = 85
        }
      }
    ]
    "assessment_recommendations" = {
      "azure_readiness"        = "Ready"
      "estimated_monthly_cost" = 2500
      "recommended_vm_sizes" = {
        "web-server-01" = "Standard_D4s_v3"
        "sql-server-01" = "Standard_E8s_v3"
      }
    }
  })
}
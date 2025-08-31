# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create Storage Account for Function App and conversation storage
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = var.minimum_tls_version
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable blob properties for lifecycle management
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT"]
      allowed_origins    = var.allowed_origins
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
    
    versioning_enabled = true
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "AI Assistant Storage"
  })
}

# Create blob containers for conversation data
resource "azurerm_storage_container" "conversations" {
  name                  = "conversations"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_container" "sessions" {
  name                  = "sessions"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_container" "assistant_data" {
  name                  = "assistant-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.main]
}

# Create Application Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_os_type
  sku_name            = "Y1" # Consumption plan for cost optimization

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "Function App Hosting"
  })
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = var.application_insights_type
  retention_in_days   = var.log_retention_days

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "Function App Monitoring"
  })
}

# Create Azure OpenAI Cognitive Services Account
resource "azurerm_cognitive_account" "openai" {
  name                          = "cog-openai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  kind                          = "OpenAI"
  sku_name                      = var.openai_sku_name
  custom_subdomain_name         = "openai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  public_network_access_enabled = true

  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }

  # Network security configuration
  network_acls {
    default_action = "Allow"
    virtual_network_rules {
      subnet_id                            = null
      ignore_missing_vnet_service_endpoint = false
    }
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "AI Assistant OpenAI Service"
  })
}

# Deploy GPT model for the assistant
resource "azurerm_cognitive_deployment" "gpt_model" {
  name                 = "gpt-4-assistant"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.gpt_model_name
    version = var.gpt_model_version
  }

  scale {
    type     = "Standard"
    capacity = var.gpt_model_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Create Function App for custom business logic
resource "azurerm_linux_function_app" "main" {
  name                          = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  service_plan_id               = azurerm_service_plan.main.id
  storage_account_name          = azurerm_storage_account.main.name
  storage_account_access_key    = azurerm_storage_account.main.primary_access_key
  functions_extension_version   = var.functions_extension_version
  https_only                    = var.enable_https_only
  public_network_access_enabled = true

  # Enable auto-scaling if specified
  dynamic "auto_scale_settings" {
    for_each = var.enable_auto_scale ? [1] : []
    content {
      enabled = true
    }
  }

  # Application settings for OpenAI and storage integration
  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"             = "python"
    "PYTHON_VERSION"                       = var.python_version
    "AzureWebJobsFeatureFlags"            = "EnableWorkerIndexing"
    "OPENAI_ENDPOINT"                     = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"                          = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_DEPLOYMENT_NAME"              = azurerm_cognitive_deployment.gpt_model.name
    "STORAGE_CONNECTION_STRING"           = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"            = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"     = "true"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  }, var.enable_application_insights ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})

  # Site configuration for security and performance
  site_config {
    minimum_tls_version = var.minimum_tls_version
    http2_enabled       = true
    
    # Application stack configuration
    application_stack {
      python_version = var.python_version
    }

    # CORS configuration for web applications
    cors {
      allowed_origins     = var.allowed_origins
      support_credentials = false
    }

    # Set daily memory time quota if specified
    daily_memory_time_quota = var.daily_memory_time_quota

    # Application Insights integration
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  }

  # Managed identity for secure Azure service access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "AI Assistant Function App"
  })

  depends_on = [
    azurerm_service_plan.main,
    azurerm_storage_account.main,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.gpt_model
  ]
}

# Create additional storage queue for function communication (if needed)
resource "azurerm_storage_queue" "function_queue" {
  name                 = "assistant-tasks"
  storage_account_name = azurerm_storage_account.main.name
}

# Create storage table for session management (if needed)
resource "azurerm_storage_table" "sessions" {
  name                 = "assistantsessions"
  storage_account_name = azurerm_storage_account.main.name
}

# RBAC: Grant Function App access to OpenAI service
resource "azurerm_role_assignment" "function_openai_access" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_cognitive_account.openai
  ]
}

# RBAC: Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_storage_account.main
  ]
}

# Create Log Analytics Workspace for advanced monitoring (optional)
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "Advanced Monitoring"
  })
}

# Connect Application Insights to Log Analytics Workspace
resource "azurerm_application_insights_workbook" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "workbook-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "AI Assistant Workbook"
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [{
      type = 1
      content = {
        json = "# AI Assistant Monitoring Dashboard\n\nThis workbook provides monitoring insights for the AI Assistant solution."
      }
    }]
  })

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "Monitoring Dashboard"
  })
}

# Create Key Vault for secure secrets management (optional but recommended)
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Network security
  public_network_access_enabled = true
  
  # Access policies
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
      "List",
      "Update",
      "Delete",
      "Purge",
      "Recover"
    ]

    secret_permissions = [
      "Set",
      "Get",
      "List",
      "Delete",
      "Purge",
      "Recover"
    ]
  }

  # Grant Function App access to Key Vault
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_linux_function_app.main.identity[0].principal_id

    secret_permissions = [
      "Get",
      "List"
    ]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "Secure Secrets Storage"
  })

  depends_on = [azurerm_linux_function_app.main]
}

# Store OpenAI key in Key Vault
resource "azurerm_key_vault_secret" "openai_key" {
  name         = "openai-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

# Store storage connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}
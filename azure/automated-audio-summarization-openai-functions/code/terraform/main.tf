# Azure Audio Summarization Infrastructure
# This configuration creates a complete serverless audio processing solution using:
# - Azure Functions for serverless compute
# - Azure OpenAI for transcription (Whisper) and summarization (GPT)
# - Azure Blob Storage for input/output file handling
# - Application Insights for monitoring

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed resource names and configuration
locals {
  # Resource naming with consistent patterns
  resource_suffix        = random_id.suffix.hex
  resource_group_name   = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name  = "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
  function_app_name     = "func-${var.project_name}-${var.environment}-${local.resource_suffix}"
  openai_account_name   = "aoai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  service_plan_name     = "asp-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_insights_name     = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Computed tags combining defaults with user-provided tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    CreatedBy     = "Terraform"
    LastModified = timestamp()
  })
  
  # Custom subdomain name for OpenAI (required for certain configurations)
  openai_subdomain = var.custom_subdomain_name != null ? var.custom_subdomain_name : "${var.project_name}-${var.environment}-${local.resource_suffix}"
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for Function App and blob containers
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = var.storage_public_access_enabled
  allow_nested_items_to_be_public = false
  
  # Blob properties with versioning and lifecycle management
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 200
    }
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
    
    versioning_enabled       = true
    last_access_time_enabled = true
  }
  
  tags = local.common_tags
}

# Create blob containers for audio input and output
resource "azurerm_storage_container" "audio_input" {
  name                  = "audio-input"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_container" "audio_output" {
  name                  = "audio-output"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = local.common_tags
}

# Create Azure OpenAI Cognitive Services Account
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Custom subdomain required for OpenAI service
  custom_subdomain_name = local.openai_subdomain
  
  # Security settings
  public_network_access_enabled = var.enable_public_network_access
  local_auth_enabled            = true
  
  tags = local.common_tags
}

# Deploy Whisper model for audio transcription
resource "azurerm_cognitive_deployment" "whisper" {
  name                 = "whisper-1"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = "whisper"
    version = var.whisper_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.model_sku_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Deploy GPT model for text summarization
resource "azurerm_cognitive_deployment" "gpt" {
  name                 = "gpt-4"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.gpt_model_name
    version = var.gpt_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.model_sku_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku_name
  
  tags = local.common_tags
}

# Create Linux Function App with Python runtime
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Link to storage and service plan
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id
  
  # Security settings
  https_only                      = var.function_https_only
  public_network_access_enabled   = true
  
  # Function runtime configuration
  functions_extension_version = var.functions_extension_version
  daily_memory_time_quota     = var.daily_memory_quota_gb * 1024 # Convert GB to MB
  
  # Site configuration with Python runtime
  site_config {
    # Python application stack configuration
    application_stack {
      python_version = var.function_runtime_version
    }
    
    # CORS configuration for web access
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    
    # Security settings
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version          = "1.2"
    use_32_bit_worker                = false
    
    # Application Insights integration
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        application_insights_connection_string = azurerm_application_insights.main[0].connection_string
      }
    }
    
    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        application_insights_key = azurerm_application_insights.main[0].instrumentation_key
      }
    }
  }
  
  # Application settings with secure environment variables
  app_settings = merge({
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"                = "python"
    "PYTHON_THREADPOOL_THREAD_COUNT"         = "1"
    "WEBSITE_RUN_FROM_PACKAGE"               = "1"
    
    # Azure OpenAI configuration
    "AZURE_OPENAI_ENDPOINT"                  = azurerm_cognitive_account.openai.endpoint
    "AZURE_OPENAI_KEY"                       = azurerm_cognitive_account.openai.primary_access_key
    "AZURE_OPENAI_API_VERSION"               = "2024-02-01"
    
    # Storage connection for blob trigger
    "STORAGE_CONNECTION_STRING"              = azurerm_storage_account.main.primary_connection_string
    "AzureWebJobsStorage"                    = azurerm_storage_account.main.primary_connection_string
    
    # Model deployment names
    "WHISPER_DEPLOYMENT_NAME"                = azurerm_cognitive_deployment.whisper.name
    "GPT_DEPLOYMENT_NAME"                    = azurerm_cognitive_deployment.gpt.name
    
    # Container names
    "AUDIO_INPUT_CONTAINER"                  = azurerm_storage_container.audio_input.name
    "AUDIO_OUTPUT_CONTAINER"                 = azurerm_storage_container.audio_output.name
    
    # Monitoring settings
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"       = "true"
    "WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT" = "5"
    
  }, var.enable_application_insights ? {
    # Application Insights settings (only if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
  } : {})
  
  # Identity configuration for secure access to other Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # Ensure proper resource creation order
  depends_on = [
    azurerm_service_plan.main,
    azurerm_storage_account.main,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.whisper,
    azurerm_cognitive_deployment.gpt
  ]
}
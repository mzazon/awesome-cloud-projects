# Azure Voice Recording Analysis - Main Infrastructure Configuration
# This file defines the core infrastructure resources for the voice analysis solution

locals {
  # Generate a random suffix for unique resource naming
  random_suffix = random_string.suffix.result
  
  # Resource naming convention with environment and random suffix
  resource_prefix = "${var.project_name}-${var.environment}-${local.random_suffix}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Deployment  = "terraform"
    CreatedDate = timestamp()
  })
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${local.resource_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for audio files and transcripts
resource "azurerm_storage_account" "voice_storage" {
  name                     = "st${replace(local.resource_prefix, "-", "")}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable HTTPS traffic only for security
  enable_https_traffic_only = true
  
  # Minimum TLS version for security
  min_tls_version = "TLS1_2"
  
  # Enable blob versioning for data protection
  blob_properties {
    versioning_enabled = true
    
    # Configure blob lifecycle management
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create container for input audio files
resource "azurerm_storage_container" "audio_input" {
  name                  = "audio-input"
  storage_account_name  = azurerm_storage_account.voice_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.voice_storage]
}

# Create container for output transcripts
resource "azurerm_storage_container" "transcripts" {
  name                  = "transcripts"
  storage_account_name  = azurerm_storage_account.voice_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.voice_storage]
}

# Create Azure AI Speech Service (Cognitive Services)
resource "azurerm_cognitive_account" "speech_service" {
  name                = "cog-speech-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "SpeechServices"
  sku_name            = var.speech_service_sku
  
  # Enable custom subdomain for enhanced security
  custom_subdomain_name = "speech-${local.random_suffix}"
  
  # Configure network access rules
  network_acls {
    default_action = "Allow"
    
    # In production, restrict to specific IP ranges or virtual networks
    # ip_rules       = ["x.x.x.x"]
    # virtual_network_rules = []
  }
  
  tags = local.common_tags
}

# Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appi-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Configure retention policy
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Create Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "log-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  name                = "asp-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Create Linux Function App for voice processing
resource "azurerm_linux_function_app" "voice_processor" {
  name                = "func-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  # Configure storage account connection
  storage_account_name       = azurerm_storage_account.voice_storage.name
  storage_account_access_key = azurerm_storage_account.voice_storage.primary_access_key
  
  # Configure site configuration
  site_config {
    # Set Python runtime version
    application_stack {
      python_version = var.function_app_python_version
    }
    
    # Configure CORS for web application integration
    cors {
      allowed_origins     = var.allowed_origins
      support_credentials = false
    }
    
    # Enable Application Insights if configured
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  }
  
  # Configure application settings with service connections
  app_settings = {
    # Azure AI Speech Service configuration
    "SPEECH_KEY"        = azurerm_cognitive_account.speech_service.primary_access_key
    "SPEECH_REGION"     = azurerm_resource_group.main.location
    "SPEECH_ENDPOINT"   = azurerm_cognitive_account.speech_service.endpoint
    "SPEECH_LANGUAGE"   = var.speech_language
    
    # Storage Account configuration
    "STORAGE_CONNECTION" = azurerm_storage_account.voice_storage.primary_connection_string
    "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.voice_storage.name
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # Application Insights configuration (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Python specific settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.voice_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE" = "voice-function-content"
    
    # Performance and reliability settings
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    "WEBSITE_RUN_FROM_PACKAGE_BLOB"   = ""
  }
  
  # Configure authentication settings
  auth_settings_v2 {
    auth_enabled = false
    # In production, enable authentication:
    # auth_enabled                            = true
    # require_authentication                  = true
    # unauthenticated_client_action          = "RedirectToLoginPage"
    # default_provider                       = "azureactivedirectory"
  }
  
  # Configure identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_service_plan.function_plan,
    azurerm_storage_account.voice_storage,
    azurerm_cognitive_account.speech_service
  ]
}

# Create backup configuration for Function App (if enabled)
resource "azurerm_function_app_backup" "main" {
  count = var.enable_backup ? 1 : 0
  
  name                = "backup-${local.resource_prefix}"
  function_app_id     = azurerm_linux_function_app.voice_processor.id
  storage_account_url = "https://${azurerm_storage_account.voice_storage.name}.blob.core.windows.net/backups"
  
  schedule {
    frequency_interval       = 1
    frequency_unit          = "Day"
    keep_at_least_one_backup = true
    retention_period_days    = var.backup_retention_days
    start_time              = "2023-01-01T00:00:00Z"
  }
}

# Role assignment for Function App to access Speech Service
resource "azurerm_role_assignment" "function_speech_access" {
  scope                = azurerm_cognitive_account.speech_service.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.voice_processor.identity[0].principal_id
}

# Role assignment for Function App to access Storage Account
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.voice_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.voice_processor.identity[0].principal_id
}

# Create a sample audio file (for testing purposes)
resource "azurerm_storage_blob" "sample_readme" {
  name                   = "README.txt"
  storage_account_name   = azurerm_storage_account.voice_storage.name
  storage_container_name = azurerm_storage_container.audio_input.name
  type                   = "Block"
  
  source_content = <<-EOT
    Voice Recording Analysis - Audio Input Container
    
    This container is configured to receive audio files for processing.
    
    Supported formats:
    - WAV (recommended)
    - MP3
    - FLAC
    - OGG
    
    Upload your audio files to this container and call the Azure Function
    with the filename to process them through Azure AI Speech Services.
    
    The processed transcripts will be available in the 'transcripts' container.
    EOT
  
  depends_on = [azurerm_storage_container.audio_input]
}
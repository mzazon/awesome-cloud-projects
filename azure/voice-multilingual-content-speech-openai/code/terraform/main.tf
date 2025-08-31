# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Local values for resource naming and tagging
locals {
  # Resource naming with consistent pattern
  resource_suffix = random_string.suffix.result
  
  # Resource names with fallback to generated names
  resource_group_name   = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name  = var.storage_account_name != "" ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
  
  # Service names
  speech_service_name     = "speech-${var.project_name}-${var.environment}-${local.resource_suffix}"
  openai_service_name     = "openai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  translator_service_name = "translator-${var.project_name}-${var.environment}-${local.resource_suffix}"
  function_app_name       = "func-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_service_plan_name   = "asp-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Application Insights (conditional)
  app_insights_name = var.enable_application_insights ? "appi-${var.project_name}-${var.environment}-${local.resource_suffix}" : null
  
  # Default tags merged with user-provided tags
  default_tags = {
    Environment    = var.environment
    Project        = var.project_name
    Purpose        = "voice-multilingual-pipeline"
    ManagedBy      = "terraform"
    DeploymentDate = formatdate("YYYY-MM-DD", timestamp())
  }
  
  tags = merge(local.default_tags, var.tags)
  
  # Target languages as comma-separated string for Function App settings
  target_languages_string = join(",", var.target_languages)
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# Storage Account for audio files and processed content
resource "azurerm_storage_account" "main" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind            = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  
  # Advanced threat protection
  blob_properties {
    change_feed_enabled = true
    versioning_enabled  = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules
  dynamic "network_rules" {
    for_each = var.network_access_rules.default_action == "Deny" ? [1] : []
    content {
      default_action = var.network_access_rules.default_action
      bypass         = var.network_access_rules.bypass
      ip_rules       = var.network_access_rules.ip_rules
    }
  }
  
  tags = local.tags
}

# Storage Containers for audio input and content output
resource "azurerm_storage_container" "audio_input" {
  name                  = "audio-input"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_container" "content_output" {
  name                  = "content-output"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Azure Speech Service for audio transcription
resource "azurerm_cognitive_account" "speech" {
  name                = local.speech_service_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "SpeechServices"
  sku_name            = var.speech_service_sku
  
  # Custom subdomain for enhanced security and features
  custom_question_answering_search_service_id = null
  dynamic_throttling_enabled                  = true
  fqdns                                      = []
  local_auth_enabled                         = true
  outbound_network_access_restricted         = false
  public_network_access_enabled              = var.enable_public_network_access
  
  # Custom domain configuration
  dynamic "custom_subdomain_name" {
    for_each = var.custom_domain_enabled ? [1] : []
    content {
      custom_subdomain_name = local.speech_service_name
    }
  }
  
  tags = local.tags
}

# Azure OpenAI Service for content enhancement
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_service_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_service_sku
  
  # Enhanced security and compliance settings
  custom_question_answering_search_service_id = null
  dynamic_throttling_enabled                  = true
  fqdns                                      = []
  local_auth_enabled                         = true
  outbound_network_access_restricted         = false
  public_network_access_enabled              = var.enable_public_network_access
  
  # Custom domain configuration
  dynamic "custom_subdomain_name" {
    for_each = var.custom_domain_enabled ? [1] : []
    content {
      custom_subdomain_name = local.openai_service_name
    }
  }
  
  tags = local.tags
}

# OpenAI Model Deployments
resource "azurerm_cognitive_deployment" "openai_models" {
  for_each = { for deployment in var.openai_deployments : deployment.name => deployment }
  
  name                 = each.value.name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }
  
  scale {
    type     = each.value.scale_type
    capacity = lookup(each.value, "scale_capacity", 1)
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Azure Translator Service for multilingual processing
resource "azurerm_cognitive_account" "translator" {
  name                = local.translator_service_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "TextTranslation"
  sku_name            = var.translator_service_sku
  
  # Security and compliance settings
  custom_question_answering_search_service_id = null
  dynamic_throttling_enabled                  = true
  fqdns                                      = []
  local_auth_enabled                         = true
  outbound_network_access_restricted         = false
  public_network_access_enabled              = var.enable_public_network_access
  
  # Custom domain configuration
  dynamic "custom_subdomain_name" {
    for_each = var.custom_domain_enabled ? [1] : []
    content {
      custom_subdomain_name = local.translator_service_name
    }
  }
  
  tags = local.tags
}

# Application Insights for monitoring (conditional)
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  retention_in_days = var.log_retention_days
  
  tags = local.tags
}

# App Service Plan for Azure Functions
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  os_type  = "Linux"
  sku_name = var.function_app_plan_sku
  
  tags = local.tags
}

# Azure Function App for pipeline orchestration
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function App runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime == "python" ? var.function_app_version : null
    }
    
    # Security and performance settings
    always_on                         = var.function_app_plan_sku != "Y1" ? true : false
    use_32_bit_worker                = false
    ftps_state                       = "Disabled"
    http2_enabled                    = true
    minimum_tls_version              = "1.2"
    scm_minimum_tls_version          = "1.2"
    remote_debugging_enabled         = false
    
    # CORS configuration for development
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    }
    
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
  
  # Application settings for AI services and configuration
  app_settings = {
    # Azure Functions runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # Storage connection
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    
    # Speech Service configuration
    "SPEECH_KEY"      = azurerm_cognitive_account.speech.primary_access_key
    "SPEECH_ENDPOINT" = azurerm_cognitive_account.speech.endpoint
    "SPEECH_REGION"   = azurerm_resource_group.main.location
    
    # OpenAI Service configuration
    "OPENAI_KEY"         = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_ENDPOINT"    = azurerm_cognitive_account.openai.endpoint
    "OPENAI_API_TYPE"    = "azure"
    "OPENAI_API_VERSION" = "2024-02-01"
    
    # Translator Service configuration
    "TRANSLATOR_KEY"      = azurerm_cognitive_account.translator.primary_access_key
    "TRANSLATOR_ENDPOINT" = azurerm_cognitive_account.translator.endpoint
    "TRANSLATOR_REGION"   = azurerm_resource_group.main.location
    
    # Processing configuration
    "TARGET_LANGUAGES" = local.target_languages_string
    
    # Application Insights (conditional)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Python-specific settings
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
  }
  
  # Identity configuration for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_cognitive_account.speech,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_account.translator
  ]
}

# Role assignments for Function App managed identity

# Storage Blob Data Contributor role for Function App
resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Cognitive Services User role for Function App (Speech Service)
resource "azurerm_role_assignment" "function_speech" {
  scope                = azurerm_cognitive_account.speech.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Cognitive Services OpenAI User role for Function App
resource "azurerm_role_assignment" "function_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Cognitive Services User role for Function App (Translator Service)
resource "azurerm_role_assignment" "function_translator" {
  scope                = azurerm_cognitive_account.translator.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Account Keys for legacy authentication (if needed)
data "azurerm_storage_account_blob_container_sas" "audio_input" {
  connection_string = azurerm_storage_account.main.primary_connection_string
  container_name    = azurerm_storage_container.audio_input.name
  https_only        = true
  
  start  = timestamp()
  expiry = timeadd(timestamp(), "8760h") # 1 year
  
  permissions {
    read   = true
    add    = true
    create = true
    write  = true
    delete = false
    list   = true
  }
}

# Log Analytics Workspace for enhanced monitoring (conditional)
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.tags
}

# Key Vault for storing sensitive configuration (optional enhancement)
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${substr(local.resource_suffix, 0, 4)}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Security settings
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  purge_protection_enabled        = false
  soft_delete_retention_days      = 7
  
  # Network access
  public_network_access_enabled = var.enable_public_network_access
  
  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Create", "Delete", "Get", "List", "Update"
    ]
    
    secret_permissions = [
      "Delete", "Get", "List", "Set"
    ]
  }
  
  # Access policy for Function App managed identity
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_linux_function_app.main.identity[0].principal_id
    
    secret_permissions = [
      "Get", "List"
    ]
  }
  
  tags = local.tags
}

# Store sensitive keys in Key Vault
resource "azurerm_key_vault_secret" "speech_key" {
  name         = "speech-service-key"
  value        = azurerm_cognitive_account.speech.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "openai_key" {
  name         = "openai-service-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "translator_key" {
  name         = "translator-service-key"
  value        = azurerm_cognitive_account.translator.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {}
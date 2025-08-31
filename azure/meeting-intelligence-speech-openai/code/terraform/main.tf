# Azure Meeting Intelligence Infrastructure with Speech Services and OpenAI
# This Terraform configuration creates a complete serverless meeting intelligence solution
# including transcription, AI analysis, and notification capabilities

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and tagging
locals {
  # Generate unique suffix for resources
  suffix = random_id.suffix.hex
  
  # Common resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Project         = var.project_name
    Purpose         = "meeting-intelligence"
    DeployedBy      = "terraform"
    CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
    Solution        = "azure-meeting-intelligence"
    CostCenter      = var.environment
    Owner           = "platform-team"
  }, var.additional_tags)
  
  # Resource names with unique suffix
  storage_account_name     = "meetingstorage${local.suffix}"
  speech_service_name      = "${local.resource_prefix}-speech-${local.suffix}"
  openai_service_name      = "${local.resource_prefix}-openai-${local.suffix}"
  servicebus_namespace     = "${local.resource_prefix}-sb-${local.suffix}"
  function_app_name        = "${local.resource_prefix}-func-${local.suffix}"
  app_service_plan_name    = "${local.resource_prefix}-plan-${local.suffix}"
  app_insights_name        = "${local.resource_prefix}-insights-${local.suffix}"
  log_analytics_name       = "${local.resource_prefix}-logs-${local.suffix}"
  
  # OpenAI deployment name
  openai_deployment_name = "gpt-4-meeting-analysis"
}

# Create the main resource group for all meeting intelligence resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Create Application Insights for Function App monitoring and analytics
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  tags                = local.common_tags
}

# Storage Account for meeting recordings and Function App backend
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security and access configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = var.enable_public_access
  public_network_access_enabled   = var.enable_public_access
  
  # Enable blob properties for versioning and soft delete
  blob_properties {
    versioning_enabled            = true
    last_access_time_enabled      = true
    change_feed_enabled           = true
    change_feed_retention_in_days = 7
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules (if IP ranges are specified)
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
      bypass         = ["AzureServices"]
    }
  }
  
  tags = local.common_tags
}

# Blob container for meeting recordings
resource "azurerm_storage_container" "meeting_recordings" {
  name                  = var.blob_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Azure Speech Services for audio transcription with speaker diarization
resource "azurerm_cognitive_account" "speech" {
  name                = local.speech_service_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "SpeechServices"
  sku_name            = var.speech_service_sku
  
  # Enable custom subdomain for API access
  custom_subdomain_name = local.speech_service_name
  
  # Network access configuration
  public_network_access_enabled = true
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Azure OpenAI Service for intelligent meeting analysis
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_service_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "OpenAI"
  sku_name            = var.openai_service_sku
  
  # Enable custom subdomain for API access
  custom_subdomain_name = local.openai_service_name
  
  # Network access configuration
  public_network_access_enabled = true
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Add delay to ensure OpenAI service is ready before deploying model
resource "time_sleep" "wait_for_openai" {
  create_duration = "60s"
  depends_on      = [azurerm_cognitive_account.openai]
}

# Deploy GPT-4 model for meeting analysis
resource "azurerm_cognitive_deployment" "gpt4" {
  name                 = local.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.openai_deployment_capacity
  }
  
  depends_on = [time_sleep.wait_for_openai]
}

# Service Bus Namespace for reliable message processing
resource "azurerm_servicebus_namespace" "main" {
  name                = local.servicebus_namespace
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.service_bus_sku
  
  # Enable zone redundancy for Premium SKU
  zone_redundant = var.service_bus_sku == "Premium" ? true : false
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Service Bus Queue for transcript processing workflow
resource "azurerm_servicebus_queue" "transcript_processing" {
  name         = var.transcript_queue_name
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Configure queue properties for reliable processing
  enable_partitioning                   = false
  max_delivery_count                    = 10
  default_message_ttl                   = "P14D"  # 14 days
  dead_lettering_on_message_expiration  = true
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes
  enable_express                        = false
  lock_duration                         = "PT5M"   # 5 minutes
  max_size_in_megabytes                 = 1024
  requires_duplicate_detection          = true
  requires_session                      = false
  
  depends_on = [azurerm_servicebus_namespace.main]
}

# Service Bus Topic for distributing meeting insights
resource "azurerm_servicebus_topic" "meeting_insights" {
  name         = var.results_topic_name
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Configure topic properties
  default_message_ttl                   = "P14D"  # 14 days
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes
  enable_batched_operations             = true
  enable_express                        = false
  enable_partitioning                   = false
  max_size_in_megabytes                 = 1024
  requires_duplicate_detection          = true
  support_ordering                      = true
  
  depends_on = [azurerm_servicebus_namespace.main]
}

# Service Bus Subscription for notification processing
resource "azurerm_servicebus_subscription" "notifications" {
  name               = var.notification_subscription_name
  topic_id           = azurerm_servicebus_topic.meeting_insights.id
  max_delivery_count = 10
  
  # Configure subscription properties
  default_message_ttl                   = "P14D"  # 14 days
  lock_duration                         = "PT5M"  # 5 minutes
  dead_lettering_on_message_expiration  = true
  dead_lettering_on_filter_evaluation_error = true
  enable_batched_operations             = true
  requires_session                      = false
  
  depends_on = [azurerm_servicebus_topic.meeting_insights]
}

# App Service Plan for Azure Functions (Consumption Plan)
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_plan_sku
  
  tags = local.common_tags
}

# Azure Function App for serverless meeting processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage configuration
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function App configuration
  functions_extension_version = var.functions_extension_version
  
  # Enable Application Insights
  app_settings = {
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Speech Services configuration
    "SPEECH_KEY"      = azurerm_cognitive_account.speech.primary_access_key
    "SPEECH_ENDPOINT" = azurerm_cognitive_account.speech.endpoint
    
    # OpenAI Service configuration
    "OPENAI_KEY"       = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_ENDPOINT"  = azurerm_cognitive_account.openai.endpoint
    "DEPLOYMENT_NAME"  = azurerm_cognitive_deployment.gpt4.name
    
    # Service Bus configuration
    "SERVICE_BUS_CONNECTION" = azurerm_servicebus_namespace.main.default_primary_connection_string
    "TRANSCRIPT_QUEUE"       = azurerm_servicebus_queue.transcript_processing.name
    "RESULTS_TOPIC"          = azurerm_servicebus_topic.meeting_insights.name
    
    # Storage configuration
    "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.main.name
    "STORAGE_CONNECTION"   = azurerm_storage_account.main.primary_connection_string
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
    "WEBSITE_USE_PLACEHOLDER"      = "0"
  }
  
  # Site configuration
  site_config {
    # Python runtime configuration
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Performance and security settings
    always_on                         = var.function_app_plan_sku != "Y1"
    ftps_state                       = "FtpsOnly"
    http2_enabled                    = true
    minimum_tls_version              = "1.2"
    remote_debugging_enabled         = false
    scm_minimum_tls_version         = "1.2"
    use_32_bit_worker               = false
    
    # CORS configuration for web interfaces
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    }
    
    # Application settings for optimal performance
    app_command_line = ""
  }
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_service_plan.main,
    azurerm_storage_account.main,
    azurerm_application_insights.main,
    azurerm_cognitive_account.speech,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.gpt4,
    azurerm_servicebus_namespace.main
  ]
}

# Storage Blob Data Contributor role assignment for Function App
resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Service Bus Data Owner role assignment for Function App
resource "azurerm_role_assignment" "function_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Cognitive Services User role assignment for Function App (Speech Services)
resource "azurerm_role_assignment" "function_speech" {
  scope                = azurerm_cognitive_account.speech.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Cognitive Services User role assignment for Function App (OpenAI)
resource "azurerm_role_assignment" "function_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Diagnostic Settings for Storage Account (if enabled)
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available metrics
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
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "Capacity"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  depends_on = [azurerm_storage_account.main, azurerm_log_analytics_workspace.main]
}

# Diagnostic Settings for Function App (if enabled)
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable Function App logs
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  depends_on = [azurerm_linux_function_app.main, azurerm_log_analytics_workspace.main]
}

# Diagnostic Settings for Service Bus (if enabled)
resource "azurerm_monitor_diagnostic_setting" "servicebus" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "servicebus-diagnostics"
  target_resource_id         = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable Service Bus logs
  enabled_log {
    category = "OperationalLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  depends_on = [azurerm_servicebus_namespace.main, azurerm_log_analytics_workspace.main]
}
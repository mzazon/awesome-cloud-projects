# Main Terraform configuration for Azure Voice-Enabled Business Process Automation
# This file creates the complete infrastructure for voice automation with Azure Speech Services and Power Platform integration

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all voice automation resources
resource "azurerm_resource_group" "voice_automation" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.tags, {
    Component = "Resource Group"
  })
}

# Create Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "voice_automation" {
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.voice_automation.location
  resource_group_name = azurerm_resource_group.voice_automation.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "voice_automation" {
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.voice_automation.location
  resource_group_name = azurerm_resource_group.voice_automation.name
  workspace_id        = azurerm_log_analytics_workspace.voice_automation.id
  application_type    = "web"
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create Storage Account for Logic Apps and general storage needs
resource "azurerm_storage_account" "voice_automation" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.voice_automation.name
  location                 = azurerm_resource_group.voice_automation.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  
  # Advanced threat protection
  blob_properties {
    delete_retention_policy {
      days = var.backup_retention_days
    }
    versioning_enabled = true
  }
  
  tags = merge(var.tags, {
    Component = "Storage"
  })
}

# Create storage container for Logic Apps artifacts
resource "azurerm_storage_container" "logic_apps" {
  name                  = "logic-apps-artifacts"
  storage_account_name  = azurerm_storage_account.voice_automation.name
  container_access_type = "private"
}

# Create Azure Cognitive Services Account for Speech Services
resource "azurerm_cognitive_account" "speech_service" {
  name                = "cs-speech-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.voice_automation.location
  resource_group_name = azurerm_resource_group.voice_automation.name
  kind                = "SpeechServices"
  sku_name            = var.speech_service_sku
  
  # Enable custom domain if specified
  custom_domain_name = var.speech_custom_domain_enabled ? "speech-${var.project_name}-${random_string.suffix.result}" : null
  
  # Network access restrictions
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = merge(var.tags, {
    Component = "AI Services"
  })
}

# Create Service Plan for Logic Apps (Consumption plan)
resource "azurerm_service_plan" "logic_apps" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.voice_automation.name
  location            = azurerm_resource_group.voice_automation.location
  os_type             = "Windows"
  sku_name            = "WS1" # Workflow Standard plan for Logic Apps
  
  tags = merge(var.tags, {
    Component = "App Service Plan"
  })
}

# Create Logic App for speech processing and Power Platform integration
resource "azurerm_logic_app_standard" "voice_processor" {
  name                       = "${var.logic_app_name}-${var.environment}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.voice_automation.location
  resource_group_name        = azurerm_resource_group.voice_automation.name
  app_service_plan_id        = azurerm_service_plan.logic_apps.id
  storage_account_name       = azurerm_storage_account.voice_automation.name
  storage_account_access_key = azurerm_storage_account.voice_automation.primary_access_key
  
  # Application settings for Speech Service integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "SPEECH_SERVICE_KEY"           = azurerm_cognitive_account.speech_service.primary_access_key
    "SPEECH_SERVICE_ENDPOINT"      = azurerm_cognitive_account.speech_service.endpoint
    "SPEECH_SERVICE_REGION"        = azurerm_resource_group.voice_automation.location
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.voice_automation.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.voice_automation.connection_string
  }
  
  # Enable HTTPS only
  https_only = true
  
  # Site configuration
  site_config {
    always_on = false # Not required for Logic Apps Standard
    
    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.voice_automation.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.voice_automation.connection_string
  }
  
  tags = merge(var.tags, {
    Component = "Logic Apps"
  })
}

# Create Key Vault for storing sensitive configuration
resource "azurerm_key_vault" "voice_automation" {
  name                        = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.voice_automation.location
  resource_group_name         = azurerm_resource_group.voice_automation.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  
  # Enable diagnostic logs if specified
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
      bypass         = "AzureServices"
    }
  }
  
  tags = merge(var.tags, {
    Component = "Security"
  })
}

# Grant Key Vault access to current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.voice_automation.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore"
  ]
}

# Grant Key Vault access to Logic App managed identity
resource "azurerm_key_vault_access_policy" "logic_app" {
  key_vault_id = azurerm_key_vault.voice_automation.id
  tenant_id    = azurerm_logic_app_standard.voice_processor.identity[0].tenant_id
  object_id    = azurerm_logic_app_standard.voice_processor.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
  
  depends_on = [azurerm_logic_app_standard.voice_processor]
}

# Store Speech Service key in Key Vault
resource "azurerm_key_vault_secret" "speech_service_key" {
  name         = "speech-service-key"
  value        = azurerm_cognitive_account.speech_service.primary_access_key
  key_vault_id = azurerm_key_vault.voice_automation.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(var.tags, {
    Component = "Security"
  })
}

# Store Speech Service endpoint in Key Vault
resource "azurerm_key_vault_secret" "speech_service_endpoint" {
  name         = "speech-service-endpoint"
  value        = azurerm_cognitive_account.speech_service.endpoint
  key_vault_id = azurerm_key_vault.voice_automation.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(var.tags, {
    Component = "Security"
  })
}

# Optional: Create Private Endpoint for Speech Service (if enabled)
resource "azurerm_private_endpoint" "speech_service" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-speech-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.voice_automation.location
  resource_group_name = azurerm_resource_group.voice_automation.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "psc-speech-${var.project_name}-${var.environment}"
    private_connection_resource_id = azurerm_cognitive_account.speech_service.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }
  
  tags = merge(var.tags, {
    Component = "Networking"
  })
}

# Virtual Network for private endpoints (if enabled)
resource "azurerm_virtual_network" "voice_automation" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.voice_automation.location
  resource_group_name = azurerm_resource_group.voice_automation.name
  
  tags = merge(var.tags, {
    Component = "Networking"
  })
}

# Subnet for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.voice_automation.name
  virtual_network_name = azurerm_virtual_network.voice_automation[0].name
  address_prefixes     = ["10.0.1.0/24"]
  
  private_endpoint_network_policies_enabled = false
}

# Configure diagnostic settings for Speech Service
resource "azurerm_monitor_diagnostic_setting" "speech_service" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-speech-${var.project_name}"
  target_resource_id = azurerm_cognitive_account.speech_service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.voice_automation.id
  
  dynamic "enabled_log" {
    for_each = ["Audit", "RequestResponse"]
    content {
      category = enabled_log.value
      
      retention_policy {
        enabled = true
        days    = var.log_analytics_retention_days
      }
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Configure diagnostic settings for Logic App
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-logic-app-${var.project_name}"
  target_resource_id = azurerm_logic_app_standard.voice_processor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.voice_automation.id
  
  dynamic "enabled_log" {
    for_each = ["FunctionAppLogs", "AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServiceAppLogs", "AppServiceAuditLogs"]
    content {
      category = enabled_log.value
      
      retention_policy {
        enabled = true
        days    = var.log_analytics_retention_days
      }
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Create Action Group for alerting
resource "azurerm_monitor_action_group" "voice_automation" {
  name                = "ag-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.voice_automation.name
  short_name          = "voiceauto"
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create alert rule for Speech Service errors
resource "azurerm_monitor_metric_alert" "speech_service_errors" {
  count               = var.enable_diagnostic_logs ? 1 : 0
  name                = "alert-speech-errors-${var.project_name}"
  resource_group_name = azurerm_resource_group.voice_automation.name
  scopes              = [azurerm_cognitive_account.speech_service.id]
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "ClientErrors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.voice_automation.id
  }
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}
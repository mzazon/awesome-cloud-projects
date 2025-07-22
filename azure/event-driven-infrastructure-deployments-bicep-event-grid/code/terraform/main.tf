# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Storage Account for Bicep Templates
resource "azurerm_storage_account" "bicep_templates" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security settings
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled      = true
  https_traffic_only_enabled     = true
  
  # Enable blob versioning and soft delete
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Create container for Bicep templates
resource "azurerm_storage_container" "bicep_templates" {
  name                  = "bicep-templates"
  storage_account_name  = azurerm_storage_account.bicep_templates.name
  container_access_type = "private"
}

# Create storage account for Function App
resource "azurerm_storage_account" "function_app" {
  name                     = "stfunc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  # Security settings
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled     = true
  
  tags = var.tags
}

# Create Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  
  # Enable content trust for Premium SKU
  dynamic "trust_policy" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Enable retention policy for Premium SKU
  dynamic "retention_policy" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      days    = 7
      enabled = true
    }
  }
  
  tags = var.tags
}

# Create Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # RBAC authorization
  enable_rbac_authorization       = true
  enabled_for_deployment          = var.key_vault_enabled_for_deployment
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  purge_protection_enabled        = var.key_vault_purge_protection_enabled
  
  # Network access rules
  network_acls {
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = var.tags
}

# Create Event Grid Topic
resource "azurerm_eventgrid_topic" "deployments" {
  name                = "egt-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = var.event_grid_topic_input_schema
  
  # Enable local authentication
  local_auth_enabled = true
  
  tags = var.tags
}

# Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = var.tags
}

# Create Application Insights
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  
  tags = var.tags
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = var.tags
}

# Create Function App for event processing
resource "azurerm_linux_function_app" "event_processor" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_app.id
  
  storage_account_name       = azurerm_storage_account.function_app.name
  storage_account_access_key = azurerm_storage_account.function_app.primary_access_key
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    # Enable Always On for non-consumption plans
    always_on = var.function_app_service_plan_sku != "Y1" ? true : false
    
    # Application stack configuration
    application_stack {
      dotnet_version = var.function_app_dotnet_version
    }
    
    # CORS configuration for development
    cors {
      allowed_origins = ["*"]
    }
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
    "FUNCTIONS_EXTENSION_VERSION"  = var.function_app_runtime_version
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Storage and registry settings
    "STORAGE_ACCOUNT_NAME"         = azurerm_storage_account.bicep_templates.name
    "STORAGE_ACCOUNT_KEY"          = azurerm_storage_account.bicep_templates.primary_access_key
    "CONTAINER_REGISTRY_NAME"      = azurerm_container_registry.main.name
    "CONTAINER_REGISTRY_USERNAME"  = azurerm_container_registry.main.admin_username
    "CONTAINER_REGISTRY_PASSWORD"  = azurerm_container_registry.main.admin_password
    
    # Event Grid settings
    "EVENT_GRID_TOPIC_ENDPOINT"    = azurerm_eventgrid_topic.deployments.endpoint
    "EVENT_GRID_TOPIC_KEY"         = azurerm_eventgrid_topic.deployments.primary_access_key
    
    # Key Vault settings
    "KEY_VAULT_NAME"               = azurerm_key_vault.main.name
  }
  
  tags = var.tags
  
  depends_on = [
    azurerm_storage_account.function_app,
    azurerm_application_insights.main
  ]
}

# Grant Function App access to Key Vault
resource "azurerm_role_assignment" "function_app_key_vault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.event_processor.identity[0].principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_app_storage" {
  scope                = azurerm_storage_account.bicep_templates.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.event_processor.identity[0].principal_id
}

# Grant Function App access to Container Registry
resource "azurerm_role_assignment" "function_app_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_function_app.event_processor.identity[0].principal_id
}

# Store Event Grid key in Key Vault
resource "azurerm_key_vault_secret" "event_grid_key" {
  name         = "EventGridKey"
  value        = azurerm_eventgrid_topic.deployments.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_key_vault]
}

# Store Storage Account key in Key Vault
resource "azurerm_key_vault_secret" "storage_key" {
  name         = "StorageKey"
  value        = azurerm_storage_account.bicep_templates.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_key_vault]
}

# Store Container Registry password in Key Vault
resource "azurerm_key_vault_secret" "acr_password" {
  name         = "ACRPassword"
  value        = azurerm_container_registry.main.admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_key_vault]
}

# Create Event Grid subscription to Function App
resource "azurerm_eventgrid_event_subscription" "deployment_subscription" {
  name  = "deployment-subscription"
  scope = azurerm_eventgrid_topic.deployments.id
  
  # Configure webhook endpoint to Function App
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.event_processor.default_hostname}/api/DeploymentHandler"
  }
  
  # Event filtering
  subject_filter {
    subject_begins_with = "/deployments/"
  }
  
  included_event_types = ["Microsoft.EventGrid.CustomEvent"]
  
  # Retry policy
  retry_policy {
    max_delivery_attempts = 10
    event_time_to_live    = 1440
  }
  
  depends_on = [azurerm_linux_function_app.event_processor]
}

# Upload sample Bicep template (optional)
resource "azurerm_storage_blob" "sample_bicep_template" {
  count                  = var.deploy_sample_bicep_template ? 1 : 0
  name                   = "storage-account.bicep"
  storage_account_name   = azurerm_storage_account.bicep_templates.name
  storage_container_name = azurerm_storage_container.bicep_templates.name
  type                   = "Block"
  
  # Sample Bicep template content
  source_content = <<-EOT
@description('Storage account name')
param storageAccountName string

@description('Location for resources')
param location string = resourceGroup().location

@allowed([
  'Standard_LRS'
  'Standard_GRS'
])
@description('Storage SKU')
param storageSku string = 'Standard_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

output storageAccountId string = storageAccount.id
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
EOT
}

# Diagnostic settings for Event Grid Topic
resource "azurerm_monitor_diagnostic_setting" "eventgrid_topic" {
  name                       = "eventgrid-diagnostics"
  target_resource_id         = azurerm_eventgrid_topic.deployments.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "DeliveryFailures"
  }
  
  enabled_log {
    category = "PublishFailures"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.event_processor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.bicep_templates.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}
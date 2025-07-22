# Azure Infrastructure Health Monitoring with Functions Flex Consumption and Update Manager
# This Terraform configuration deploys a complete serverless infrastructure health monitoring solution

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent resource naming and tagging
locals {
  # Resource naming with random suffix for uniqueness
  function_app_name     = "${var.function_app_name_prefix}-${random_string.suffix.result}"
  storage_account_name  = "${var.storage_account_name_prefix}${random_string.suffix.result}"
  log_analytics_name    = "la-${var.project_name}-${random_string.suffix.result}"
  event_grid_topic_name = "egt-health-updates-${random_string.suffix.result}"
  key_vault_name        = "kv-${var.project_name}-${random_string.suffix.result}"
  vnet_name            = "vnet-${var.project_name}"
  subnet_name          = "subnet-functions"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project      = var.project_name
    DeployedBy   = "Terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group - Container for all infrastructure health monitoring resources
resource "azurerm_resource_group" "health_monitor" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace - Centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "health_monitor" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.health_monitor.location
  resource_group_name = azurerm_resource_group.health_monitor.name
  sku                = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Virtual Network - Secure networking for Function App hybrid connectivity
resource "azurerm_virtual_network" "health_monitor" {
  count               = var.enable_vnet_integration ? 1 : 0
  name                = local.vnet_name
  location            = azurerm_resource_group.health_monitor.location
  resource_group_name = azurerm_resource_group.health_monitor.name
  address_space       = [var.vnet_address_space]
  
  tags = local.common_tags
}

# Subnet for Function App integration with delegation for Azure Functions
resource "azurerm_subnet" "functions" {
  count                = var.enable_vnet_integration ? 1 : 0
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.health_monitor.name
  virtual_network_name = azurerm_virtual_network.health_monitor[0].name
  address_prefixes     = [var.function_subnet_address_prefix]
  
  # Delegation required for Azure Functions Flex Consumption integration
  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Storage Account - Required for Azure Functions runtime and logs
resource "azurerm_storage_account" "health_monitor" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.health_monitor.name
  location                 = azurerm_resource_group.health_monitor.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security configurations following Azure best practices
  min_tls_version                = "TLS1_2"
  enable_https_traffic_only      = true
  allow_nested_items_to_be_public = false
  
  # Advanced threat protection
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Key Vault - Secure storage for application secrets and configuration
resource "azurerm_key_vault" "health_monitor" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.health_monitor.location
  resource_group_name        = azurerm_resource_group.health_monitor.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # Enable template deployment for Function App integration
  enabled_for_template_deployment = true
  
  tags = local.common_tags
}

# Key Vault Access Policy - Grant current user full access for initial setup
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.health_monitor.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  # Full permissions for deployment user
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover", "Purge"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover"
  ]
}

# Store Storage Account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "StorageConnectionString"
  value        = azurerm_storage_account.health_monitor.primary_connection_string
  key_vault_id = azurerm_key_vault.health_monitor.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

# Event Grid Topic - Event distribution hub for health monitoring events
resource "azurerm_eventgrid_topic" "health_updates" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.health_monitor.location
  resource_group_name = azurerm_resource_group.health_monitor.name
  input_schema        = "EventGridSchema"
  
  tags = local.common_tags
}

# Store Event Grid endpoint and key in Key Vault
resource "azurerm_key_vault_secret" "event_grid_endpoint" {
  name         = "EventGridEndpoint"
  value        = azurerm_eventgrid_topic.health_updates.endpoint
  key_vault_id = azurerm_key_vault.health_monitor.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "event_grid_key" {
  name         = "EventGridKey"
  value        = azurerm_eventgrid_topic.health_updates.primary_access_key
  key_vault_id = azurerm_key_vault.health_monitor.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

# Application Insights - Application performance monitoring
resource "azurerm_application_insights" "health_monitor" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitor.location
  resource_group_name = azurerm_resource_group.health_monitor.name
  workspace_id        = azurerm_log_analytics_workspace.health_monitor.id
  application_type    = "web"
  
  tags = local.common_tags
}

# Service Plan for Azure Functions Flex Consumption
resource "azurerm_service_plan" "health_monitor" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.health_monitor.name
  location            = azurerm_resource_group.health_monitor.location
  os_type             = "Linux"
  sku_name            = "FC1"  # Flex Consumption SKU
  
  tags = local.common_tags
}

# Linux Function App with Flex Consumption plan and VNet integration
resource "azurerm_linux_function_app" "health_monitor" {
  name                       = local.function_app_name
  resource_group_name        = azurerm_resource_group.health_monitor.name
  location                   = azurerm_resource_group.health_monitor.location
  service_plan_id           = azurerm_service_plan.health_monitor.id
  storage_account_name       = azurerm_storage_account.health_monitor.name
  storage_account_access_key = azurerm_storage_account.health_monitor.primary_access_key
  functions_extension_version = var.function_runtime_version
  
  # VNet integration for secure hybrid connectivity
  virtual_network_subnet_id = var.enable_vnet_integration ? azurerm_subnet.functions[0].id : null
  
  # System-assigned managed identity for secure Azure service access
  identity {
    type = var.enable_system_assigned_identity ? "SystemAssigned" : "None"
  }
  
  # Site configuration for Python runtime
  site_config {
    application_stack {
      python_version = var.function_python_version
    }
    
    # Enable Application Insights if configured
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.health_monitor[0].connection_string : null
    application_insights_key              = var.enable_application_insights ? azurerm_application_insights.health_monitor[0].instrumentation_key : null
    
    # Security configurations
    ftps_state = "Disabled"
    http2_enabled = true
    minimum_tls_version = "1.2"
    
    # CORS configuration for Event Grid webhooks
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }
  
  # Application settings for Function App configuration
  app_settings = {
    # Azure Functions runtime settings
    "AzureWebJobsFeatureFlags"              = "EnableWorkerIndexing"
    "FUNCTIONS_WORKER_RUNTIME"              = "python"
    "WEBSITE_PYTHON_DEFAULT_VERSION"        = var.function_python_version
    
    # Key Vault integration
    "KEY_VAULT_NAME"                        = azurerm_key_vault.health_monitor.name
    
    # Event Grid configuration
    "EVENT_GRID_TOPIC_NAME"                 = azurerm_eventgrid_topic.health_updates.name
    
    # Log Analytics configuration
    "LOG_ANALYTICS_WORKSPACE"               = azurerm_log_analytics_workspace.health_monitor.name
    "LOG_ANALYTICS_WORKSPACE_ID"            = azurerm_log_analytics_workspace.health_monitor.workspace_id
    
    # Health check configuration
    "HEALTH_CHECK_SCHEDULE"                 = var.health_check_schedule
    "NOTIFICATION_CHANNELS"                 = join(",", var.notification_channels)
    
    # Application Insights connection
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.health_monitor[0].connection_string : ""
    
    # Environment and project settings
    "ENVIRONMENT"                          = var.environment
    "PROJECT_NAME"                         = var.project_name
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.health_monitor,
    azurerm_key_vault.health_monitor
  ]
}

# Key Vault Access Policy for Function App Managed Identity
resource "azurerm_key_vault_access_policy" "function_app" {
  count        = var.enable_system_assigned_identity ? 1 : 0
  key_vault_id = azurerm_key_vault.health_monitor.id
  tenant_id    = azurerm_linux_function_app.health_monitor.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.health_monitor.identity[0].principal_id
  
  # Minimal required permissions for function operations
  secret_permissions = [
    "Get", "List"
  ]
  
  depends_on = [azurerm_linux_function_app.health_monitor]
}

# Role assignment for Function App to access Event Grid
resource "azurerm_role_assignment" "function_eventgrid_contributor" {
  count                = var.enable_system_assigned_identity ? 1 : 0
  scope                = azurerm_resource_group.health_monitor.id
  role_definition_name = "EventGrid Contributor"
  principal_id         = azurerm_linux_function_app.health_monitor.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.health_monitor]
}

# Role assignment for Function App to access Log Analytics
resource "azurerm_role_assignment" "function_log_analytics_reader" {
  count                = var.enable_system_assigned_identity ? 1 : 0
  scope                = azurerm_log_analytics_workspace.health_monitor.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_linux_function_app.health_monitor.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.health_monitor]
}

# Role assignment for Function App to access Update Manager (Automation Contributor)
resource "azurerm_role_assignment" "function_automation_contributor" {
  count                = var.enable_system_assigned_identity ? 1 : 0
  scope                = azurerm_resource_group.health_monitor.id
  role_definition_name = "Automation Contributor"
  principal_id         = azurerm_linux_function_app.health_monitor.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.health_monitor]
}

# Wait for Function App deployment to complete before creating Event Grid subscription
resource "time_sleep" "wait_for_function_app" {
  depends_on = [azurerm_linux_function_app.health_monitor]
  create_duration = "60s"
}

# Event Grid Subscription for Update Manager events to Function App
resource "azurerm_eventgrid_event_subscription" "update_manager_events" {
  name  = "update-manager-events-${random_string.suffix.result}"
  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  
  # Webhook endpoint for the UpdateEventHandler function
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.health_monitor.default_hostname}/runtime/webhooks/eventgrid?functionName=UpdateEventHandler"
  }
  
  # Filter for Update Manager specific events
  included_event_types = [
    "Microsoft.Automation.UpdateManagement.AssessmentCompleted",
    "Microsoft.Automation.UpdateManagement.InstallationCompleted"
  ]
  
  # Advanced filtering for relevant Update Manager operations
  advanced_filter {
    string_begins_with {
      key    = "subject"
      values = ["Microsoft.Automation"]
    }
  }
  
  # Retry policy for webhook delivery
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440  # 24 hours
  }
  
  depends_on = [
    azurerm_linux_function_app.health_monitor,
    time_sleep.wait_for_function_app
  ]
  
  labels = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Event Grid Subscription for custom health events within the topic
resource "azurerm_eventgrid_event_subscription" "health_events" {
  name               = "health-events-${random_string.suffix.result}"
  scope              = azurerm_eventgrid_topic.health_updates.id
  
  # Webhook endpoint for the UpdateEventHandler function
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.health_monitor.default_hostname}/runtime/webhooks/eventgrid?functionName=UpdateEventHandler"
  }
  
  # Filter for infrastructure health events
  included_event_types = [
    "Infrastructure.HealthCheck.Critical",
    "Infrastructure.HealthCheck.Warning",
    "Infrastructure.Alert.CRITICAL",
    "Infrastructure.Alert.WARNING"
  ]
  
  # Retry policy for webhook delivery
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440  # 24 hours
  }
  
  depends_on = [
    azurerm_linux_function_app.health_monitor,
    time_sleep.wait_for_function_app
  ]
  
  labels = {
    Environment = var.environment
    Project     = var.project_name
  }
}
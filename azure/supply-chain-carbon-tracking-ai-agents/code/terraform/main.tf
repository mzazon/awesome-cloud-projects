# Data sources for current client and subscription
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  
  # Resource names with consistent naming convention
  resource_group_name         = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  ai_foundry_project_name     = var.ai_foundry_project_name != null ? var.ai_foundry_project_name : "aif-${var.project_name}-${local.resource_suffix}"
  service_bus_namespace_name  = var.service_bus_namespace_name != null ? var.service_bus_namespace_name : "sb-${var.project_name}-${local.resource_suffix}"
  function_app_name           = var.function_app_name != null ? var.function_app_name : "func-${var.project_name}-${local.resource_suffix}"
  storage_account_name        = var.storage_account_name != null ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  key_vault_name              = var.key_vault_name != null ? var.key_vault_name : "kv-${var.project_name}-${local.resource_suffix}"
  cognitive_services_name     = var.cognitive_services_name != null ? var.cognitive_services_name : "cs-${var.project_name}-${local.resource_suffix}"
  power_platform_env_name     = var.power_platform_environment_name != null ? var.power_platform_environment_name : "pp-${var.project_name}-${local.resource_suffix}"
  
  # Combined tags
  common_tags = merge(var.tags, {
    ResourceGroup = local.resource_group_name
    CreatedBy     = "terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  retention_in_days   = var.application_insights_retention_in_days
  tags                = local.common_tags
}

# Storage Account for Function App and data storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Enable blob versioning for data protection
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = var.backup_retention_days
    }
    
    container_delete_retention_policy {
      days = var.backup_retention_days
    }
  }
  
  tags = local.common_tags
}

# Storage containers for different data types
resource "azurerm_storage_container" "containers" {
  for_each = {
    for container in var.storage_containers : container.name => container
  }
  
  name                  = each.value.name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = each.value.container_access_type
}

# Key Vault for secure secrets management
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Enable soft delete and purge protection
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = true
  
  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = local.common_tags
}

# Key Vault access policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Create", "Get", "List", "Update", "Delete", "Purge", "Recover"
  ]
  
  secret_permissions = [
    "Set", "Get", "List", "Delete", "Purge", "Recover"
  ]
  
  certificate_permissions = [
    "Create", "Get", "List", "Update", "Delete", "Purge", "Recover"
  ]
}

# Cognitive Services for AI capabilities
resource "azurerm_cognitive_account" "main" {
  name                = local.cognitive_services_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = var.cognitive_services_kind
  sku_name            = var.cognitive_services_sku
  
  # Enable custom subdomain for enhanced security
  custom_subdomain_name = "${var.project_name}-${local.resource_suffix}"
  
  tags = local.common_tags
}

# Machine Learning Workspace for AI Foundry
resource "azurerm_machine_learning_workspace" "main" {
  name                = local.ai_foundry_project_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Required resources for ML workspace
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id           = azurerm_key_vault.main.id
  storage_account_id     = azurerm_storage_account.main.id
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  # Enhanced security settings
  public_network_access_enabled = !var.enable_private_endpoints
  
  description      = var.ai_foundry_description
  friendly_name    = var.ai_foundry_friendly_name
  
  tags = local.common_tags
}

# Service Bus Namespace for event-driven architecture
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_namespace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  
  # Set capacity for Premium SKU
  capacity = var.service_bus_sku == "Premium" ? var.service_bus_capacity : null
  
  tags = local.common_tags
}

# Service Bus Queue for carbon data processing
resource "azurerm_servicebus_queue" "carbon_data" {
  name         = "carbon-data-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Queue configuration
  max_size_in_megabytes                = var.carbon_data_queue_settings.max_size_in_megabytes
  default_message_ttl                  = var.carbon_data_queue_settings.default_message_ttl
  dead_lettering_on_message_expiration = var.carbon_data_queue_settings.dead_lettering_on_message_expiration
  duplicate_detection_history_time_window = var.carbon_data_queue_settings.duplicate_detection_history_time_window
  enable_batched_operations            = var.carbon_data_queue_settings.enable_batched_operations
  enable_express                       = var.carbon_data_queue_settings.enable_express
  enable_partitioning                  = var.carbon_data_queue_settings.enable_partitioning
  lock_duration                        = var.carbon_data_queue_settings.lock_duration
  max_delivery_count                   = var.carbon_data_queue_settings.max_delivery_count
  requires_duplicate_detection         = var.carbon_data_queue_settings.requires_duplicate_detection
  requires_session                     = var.carbon_data_queue_settings.requires_session
}

# Service Bus Queue for analysis results
resource "azurerm_servicebus_queue" "analysis_results" {
  name         = "analysis-results-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Queue configuration
  max_size_in_megabytes                = var.analysis_results_queue_settings.max_size_in_megabytes
  default_message_ttl                  = var.analysis_results_queue_settings.default_message_ttl
  dead_lettering_on_message_expiration = var.analysis_results_queue_settings.dead_lettering_on_message_expiration
  duplicate_detection_history_time_window = var.analysis_results_queue_settings.duplicate_detection_history_time_window
  enable_batched_operations            = var.analysis_results_queue_settings.enable_batched_operations
  enable_express                       = var.analysis_results_queue_settings.enable_express
  enable_partitioning                  = var.analysis_results_queue_settings.enable_partitioning
  lock_duration                        = var.analysis_results_queue_settings.lock_duration
  max_delivery_count                   = var.analysis_results_queue_settings.max_delivery_count
  requires_duplicate_detection         = var.analysis_results_queue_settings.requires_duplicate_detection
  requires_session                     = var.analysis_results_queue_settings.requires_session
}

# Service Bus authorization rule for Function App access
resource "azurerm_servicebus_namespace_authorization_rule" "function_app" {
  name         = "function-app-access"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  listen = true
  send   = true
  manage = false
}

# Store Service Bus connection string in Key Vault
resource "azurerm_key_vault_secret" "service_bus_connection_string" {
  name         = "service-bus-connection-string"
  value        = azurerm_servicebus_namespace_authorization_rule.function_app.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Store Cognitive Services key in Key Vault
resource "azurerm_key_vault_secret" "cognitive_services_key" {
  name         = "cognitive-services-key"
  value        = azurerm_cognitive_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# App Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "plan-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for carbon data processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_app.id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Site configuration
  site_config {
    # Runtime configuration
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Application Insights integration
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    
    # Enhanced security
    ftps_state        = "Disabled"
    http2_enabled     = true
    minimum_tls_version = "1.2"
    
    # Performance optimization
    always_on = var.function_app_service_plan_sku != "Y1"
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "ServiceBusConnection"         = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.service_bus_connection_string.id})"
    "CognitiveServicesKey"         = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.cognitive_services_key.id})"
    "CognitiveServicesEndpoint"    = azurerm_cognitive_account.main.endpoint
    "MLWorkspaceId"                = azurerm_machine_learning_workspace.main.id
    "StorageAccountConnectionString" = azurerm_storage_account.main.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  tags = local.common_tags
}

# Key Vault access policy for Function App
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# Virtual Network for enhanced security (optional)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.virtual_network_address_space
  
  tags = local.common_tags
}

# Subnet for Function App
resource "azurerm_subnet" "functions" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "subnet-functions"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.subnet_address_prefixes.functions
  
  # Delegate subnet to Function App
  delegation {
    name = "function-app-delegation"
    
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Subnet for AI services
resource "azurerm_subnet" "ai" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "subnet-ai"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.subnet_address_prefixes.ai
}

# Subnet for data services
resource "azurerm_subnet" "data" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "subnet-data"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.subnet_address_prefixes.data
}

# Network Security Group for Function App subnet
resource "azurerm_network_security_group" "functions" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "nsg-functions-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Allow HTTPS traffic
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Allow HTTP traffic for Function App
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Associate NSG with Function App subnet
resource "azurerm_subnet_network_security_group_association" "functions" {
  count                     = var.enable_private_endpoints ? 1 : 0
  subnet_id                 = azurerm_subnet.functions[0].id
  network_security_group_id = azurerm_network_security_group.functions[0].id
}

# Budget alert for cost management
resource "azurerm_consumption_budget_resource_group" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "budget-${var.project_name}-${local.resource_suffix}"
  resource_group_id   = azurerm_resource_group.main.id
  
  amount     = var.monthly_budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h"))
  }
  
  dynamic "notification" {
    for_each = var.alert_email_addresses
    content {
      enabled         = true
      threshold       = var.budget_alert_threshold
      operator        = "GreaterThan"
      threshold_type  = "Actual"
      contact_emails  = [notification.value]
    }
  }
}

# Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "ag-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "carbonalert"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = local.common_tags
}

# Metric alert for Function App errors
resource "azurerm_monitor_metric_alert" "function_app_errors" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-function-errors-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when Function App error rate exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  dynamic "action" {
    for_each = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  
  tags = local.common_tags
}

# Metric alert for Service Bus dead letter queue
resource "azurerm_monitor_metric_alert" "service_bus_dead_letters" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-dead-letters-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_servicebus_namespace.main.id]
  description         = "Alert when messages are sent to dead letter queue"
  
  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "DeadletteredMessages"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
    
    dimension {
      name     = "EntityName"
      operator = "Include"
      values   = ["carbon-data-queue", "analysis-results-queue"]
    }
  }
  
  dynamic "action" {
    for_each = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  
  tags = local.common_tags
}

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "diag-function-app"
  target_resource_id = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Service Bus
resource "azurerm_monitor_diagnostic_setting" "service_bus" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "diag-service-bus"
  target_resource_id = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "OperationalLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Machine Learning Workspace
resource "azurerm_monitor_diagnostic_setting" "ml_workspace" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "diag-ml-workspace"
  target_resource_id = azurerm_machine_learning_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "AmlComputeClusterEvent"
  }
  
  enabled_log {
    category = "AmlComputeClusterNodeEvent"
  }
  
  enabled_log {
    category = "AmlComputeJobEvent"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
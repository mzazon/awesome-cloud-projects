# Event-Driven Configuration Management with Azure App Configuration and Azure Service Bus
# This Terraform configuration deploys a complete event-driven configuration management solution

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
  numeric = true
}

# Current Azure client configuration for resource references
data "azurerm_client_config" "current" {}

# Resource Group
# Centralized container for all configuration management resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = merge(var.tags, {
    "Resource Type" = "Resource Group"
    "Created By"    = "Terraform"
  })
}

# Azure App Configuration Store
# Centralized configuration management service with versioning and feature flags
resource "azurerm_app_configuration" "main" {
  name                       = "appconfig-${var.project_name}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  sku                        = var.app_configuration_sku
  public_network_access      = var.enable_public_network_access ? "Enabled" : "Disabled"
  purge_protection_enabled   = var.environment == "prod" ? true : false
  soft_delete_retention_days = var.environment == "prod" ? 7 : 1
  
  tags = merge(var.tags, {
    "Resource Type" = "App Configuration"
    "Service Role"  = "Configuration Store"
  })
}

# Sample Configuration Keys
# Initialize App Configuration with sample application settings
resource "azurerm_app_configuration_key" "sample_keys" {
  for_each = var.sample_configuration_keys
  
  configuration_store_id = azurerm_app_configuration.main.id
  key                   = each.key
  value                 = each.value.value
  content_type          = each.value.content_type
  
  depends_on = [azurerm_role_assignment.current_user_data_owner]
}

# Sample Feature Flags
# Initialize App Configuration with sample feature flags
resource "azurerm_app_configuration_feature" "sample_features" {
  for_each = var.feature_flags
  
  configuration_store_id = azurerm_app_configuration.main.id
  name                  = each.key
  enabled               = each.value.enabled
  description           = each.value.description
  
  depends_on = [azurerm_role_assignment.current_user_data_owner]
}

# Role Assignment for Current User
# Grant App Configuration Data Owner role to the current user for managing configuration
resource "azurerm_role_assignment" "current_user_data_owner" {
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Service Bus Namespace
# Messaging infrastructure for reliable event routing and processing
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  capacity            = var.service_bus_sku == "Premium" ? 1 : null
  
  tags = merge(var.tags, {
    "Resource Type" = "Service Bus Namespace"
    "Service Role"  = "Message Routing"
  })
}

# Service Bus Topic
# Publish-subscribe messaging pattern for configuration change events
resource "azurerm_servicebus_topic" "configuration_changes" {
  name                         = "configuration-changes"
  namespace_id                 = azurerm_servicebus_namespace.main.id
  max_size_in_megabytes       = var.service_bus_topic_max_size_in_megabytes
  enable_duplicate_detection   = true
  duplicate_detection_history_time_window = "PT10M"
  enable_partitioning         = var.service_bus_sku == "Premium" ? false : true
  enable_express              = var.service_bus_sku != "Premium" ? true : false
}

# Service Bus Subscriptions
# Filtered message consumption for different service categories
resource "azurerm_servicebus_subscription" "web_services" {
  name                                 = "web-services"
  topic_id                            = azurerm_servicebus_topic.configuration_changes.id
  max_delivery_count                  = var.service_bus_subscription_max_delivery_count
  lock_duration                       = var.service_bus_subscription_lock_duration
  enable_batched_operations           = true
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
}

resource "azurerm_servicebus_subscription" "api_services" {
  name                                 = "api-services"
  topic_id                            = azurerm_servicebus_topic.configuration_changes.id
  max_delivery_count                  = var.service_bus_subscription_max_delivery_count
  lock_duration                       = var.service_bus_subscription_lock_duration
  enable_batched_operations           = true
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
}

resource "azurerm_servicebus_subscription" "worker_services" {
  name                                 = "worker-services"
  topic_id                            = azurerm_servicebus_topic.configuration_changes.id
  max_delivery_count                  = var.service_bus_subscription_max_delivery_count
  lock_duration                       = var.service_bus_subscription_lock_duration
  enable_batched_operations           = true
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
}

# Storage Account for Azure Functions
# Backend storage for Function App metadata and execution context
resource "azurerm_storage_account" "functions" {
  name                     = "stfunc${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(var.tags, {
    "Resource Type" = "Storage Account"
    "Service Role"  = "Function App Backend"
  })
}

# App Service Plan for Azure Functions
# Compute infrastructure for serverless configuration processing
resource "azurerm_service_plan" "functions" {
  name                = "plan-${var.project_name}-func-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = merge(var.tags, {
    "Resource Type" = "App Service Plan"
    "Service Role"  = "Function Compute"
  })
}

# Azure Function App
# Serverless event processing for configuration change events
resource "azurerm_linux_function_app" "config_processor" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.functions.id
  
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  
  site_config {
    application_stack {
      node_version = var.function_app_node_version
    }
    
    # Security and performance configurations
    always_on                = var.function_app_service_plan_sku != "Y1" ? true : false
    ftps_state              = "Disabled"
    http2_enabled           = true
    minimum_tls_version     = "1.2"
    use_32_bit_worker       = false
    
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }
  
  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"     = var.function_app_runtime_version
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~${var.function_app_node_version}"
    "ServiceBusConnection"           = azurerm_servicebus_namespace.main.default_primary_connection_string
    "AppConfigConnection"            = azurerm_app_configuration.main.primary_read_key[0].connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.functions.primary_connection_string
    "WEBSITE_CONTENTSHARE"           = "func-${var.project_name}-${random_string.suffix.result}"
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    "Resource Type" = "Function App"
    "Service Role"  = "Configuration Processor"
  })
}

# Application Insights for Monitoring
# Observability and monitoring for Function App execution
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  
  tags = merge(var.tags, {
    "Resource Type" = "Application Insights"
    "Service Role"  = "Monitoring"
  })
}

# Azure Logic Apps for Complex Workflows (Optional)
# Visual workflow orchestration for complex configuration management scenarios
resource "azurerm_logic_app_workflow" "config_workflow" {
  count = var.logic_app_enabled ? 1 : 0
  
  name                = "logic-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    "Resource Type" = "Logic App"
    "Service Role"  = "Workflow Orchestration"
  })
}

# Event Grid System Topic for App Configuration
# Event routing infrastructure for configuration change notifications
resource "azurerm_eventgrid_system_topic" "app_config" {
  name                   = "eg-appconfig-${random_string.suffix.result}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  source_arm_resource_id = azurerm_app_configuration.main.id
  topic_type            = "Microsoft.AppConfiguration.ConfigurationStores"
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    "Resource Type" = "Event Grid System Topic"
    "Service Role"  = "Event Routing"
  })
}

# Event Grid Subscription
# Connect App Configuration events to Service Bus for processing
resource "azurerm_eventgrid_event_subscription" "config_changes_to_servicebus" {
  name  = "config-changes-to-servicebus"
  scope = azurerm_app_configuration.main.id
  
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.configuration_changes.id
  
  included_event_types = [
    "Microsoft.AppConfiguration.KeyValueModified",
    "Microsoft.AppConfiguration.KeyValueDeleted"
  ]
  
  subject_filter {
    subject_begins_with = "config/"
  }
  
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }
  
  depends_on = [azurerm_role_assignment.eventgrid_servicebus]
  
  labels = ["configuration-management", "event-driven"]
}

# Role Assignment for Event Grid to Service Bus
# Grant Event Grid permission to send messages to Service Bus topic
resource "azurerm_role_assignment" "eventgrid_servicebus" {
  scope                = azurerm_servicebus_topic.configuration_changes.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_system_topic.app_config.identity[0].principal_id
}

# Role Assignment for Function App to App Configuration
# Grant Function App permission to read configuration values
resource "azurerm_role_assignment" "function_app_config_reader" {
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_linux_function_app.config_processor.identity[0].principal_id
}

# Role Assignment for Function App to Service Bus
# Grant Function App permission to receive messages from Service Bus
resource "azurerm_role_assignment" "function_servicebus_receiver" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_linux_function_app.config_processor.identity[0].principal_id
}

# Role Assignment for Logic App to Service Bus (if enabled)
# Grant Logic App permission to receive messages from Service Bus
resource "azurerm_role_assignment" "logic_app_servicebus_receiver" {
  count = var.logic_app_enabled ? 1 : 0
  
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_logic_app_workflow.config_workflow[0].identity[0].principal_id
}
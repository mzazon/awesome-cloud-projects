# Main Terraform configuration for SMS notifications with Azure Communication Services and Functions
# This creates a complete serverless SMS notification system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix           = random_id.suffix.hex
  resource_group_name       = "${var.project_name}-rg-${var.environment}-${local.resource_suffix}"
  communication_name        = "${var.project_name}-acs-${var.environment}-${local.resource_suffix}"
  storage_account_name      = replace("${var.project_name}sa${var.environment}${local.resource_suffix}", "-", "")
  service_plan_name         = "${var.project_name}-plan-${var.environment}-${local.resource_suffix}"
  function_app_name         = "${var.project_name}-func-${var.environment}-${local.resource_suffix}"
  application_insights_name = "${var.project_name}-ai-${var.environment}-${local.resource_suffix}"
  log_analytics_name        = "${var.project_name}-la-${var.environment}-${local.resource_suffix}"

  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    ResourceGroup = local.resource_group_name
    DeployedBy    = "Terraform"
    CreatedDate   = timestamp()
  })
}

# Resource Group - Container for all SMS notification resources
resource "azurerm_resource_group" "sms_rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Log Analytics Workspace - Required for Application Insights
resource "azurerm_log_analytics_workspace" "sms_workspace" {
  count = var.enable_application_insights ? 1 : 0

  name                = local.log_analytics_name
  location            = azurerm_resource_group.sms_rg.location
  resource_group_name = azurerm_resource_group.sms_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.application_insights_retention_days
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Application Insights - Monitoring and telemetry for Function App
resource "azurerm_application_insights" "sms_insights" {
  count = var.enable_application_insights ? 1 : 0

  name                = local.application_insights_name
  location            = azurerm_resource_group.sms_rg.location
  resource_group_name = azurerm_resource_group.sms_rg.name
  workspace_id        = azurerm_log_analytics_workspace.sms_workspace[0].id
  application_type    = "Node.JS"
  retention_in_days   = var.application_insights_retention_days
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Azure Communication Services - Provides SMS functionality
resource "azurerm_communication_service" "sms_communication" {
  name                = local.communication_name
  resource_group_name = azurerm_resource_group.sms_rg.name
  data_location       = var.communication_data_location
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Storage Account - Required for Azure Functions runtime and triggers
resource "azurerm_storage_account" "sms_storage" {
  name                     = substr(local.storage_account_name, 0, 24) # Storage account names must be <= 24 chars
  resource_group_name      = azurerm_resource_group.sms_rg.name
  location                 = azurerm_resource_group.sms_rg.location
  account_tier             = "Standard"
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  https_traffic_only_enabled      = var.enable_https_only
  min_tls_version                 = var.minimum_tls_version
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Required for Function App
  
  # Blob properties with versioning and change feed for production monitoring
  blob_properties {
    versioning_enabled = true
    change_feed_enabled = true
    
    # Delete retention policy for blob recovery
    delete_retention_policy {
      days = 7
    }
    
    # Container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# App Service Plan - Consumption plan for serverless compute
resource "azurerm_service_plan" "sms_plan" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.sms_rg.name
  location            = azurerm_resource_group.sms_rg.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku_name

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Linux Function App - Hosts the SMS sending functions
resource "azurerm_linux_function_app" "sms_function" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.sms_rg.name
  location            = azurerm_resource_group.sms_rg.location
  service_plan_id     = azurerm_service_plan.sms_plan.id

  # Storage configuration
  storage_account_name       = azurerm_storage_account.sms_storage.name
  storage_account_access_key = azurerm_storage_account.sms_storage.primary_access_key

  # Function App settings
  functions_extension_version = var.function_runtime_version
  builtin_logging_enabled     = var.enable_builtin_logging
  https_only                  = var.enable_https_only
  daily_memory_time_quota     = var.daily_memory_time_quota

  # Application settings - Environment variables for the Function App
  app_settings = merge({
    # Azure Communication Services configuration
    "ACS_CONNECTION_STRING" = azurerm_communication_service.sms_communication.primary_connection_string

    # Function runtime configuration  
    "FUNCTIONS_WORKER_RUNTIME"         = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"     = "~${var.node_version}"
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"  = "true"
    
    # Performance and scaling configuration
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.sms_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE"                      = "${local.function_app_name}-content"
    
    # Security and logging configuration
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS" = "7"
    "APPINSIGHTS_SAMPLING_PERCENTAGE"    = "100"
  }, var.enable_application_insights ? {
    # Application Insights configuration (only if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.sms_insights[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.sms_insights[0].connection_string
  } : {})

  # Site configuration
  site_config {
    # Application stack configuration
    application_stack {
      node_version = var.node_version
    }

    # Performance and scaling settings
    always_on                         = var.service_plan_sku_name != "Y1" # Always On not supported on Consumption plan
    use_32_bit_worker                 = false
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = var.minimum_tls_version
    remote_debugging_enabled          = false
    
    # CORS configuration for cross-origin requests
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    # IP restrictions (if configured)
    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.ip_address
        priority   = ip_restriction.value.priority
        action     = ip_restriction.value.action
      }
    }

    # Application Insights integration (if enabled)
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.sms_insights[0].connection_string
      }
    }

    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.sms_insights[0].instrumentation_key
      }
    }
  }

  # Managed identity for secure access to Azure resources
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

  # Ensure proper dependency ordering
  depends_on = [
    azurerm_service_plan.sms_plan,
    azurerm_storage_account.sms_storage,
    azurerm_communication_service.sms_communication
  ]

  lifecycle {
    ignore_changes = [
      tags["CreatedDate"],
      app_settings["WEBSITE_CONTENTSHARE"] # This is managed by Azure
    ]
  }
}
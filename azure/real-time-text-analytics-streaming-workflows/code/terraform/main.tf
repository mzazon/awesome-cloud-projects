# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

# Local variables for resource naming
locals {
  suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Resource names with optional random suffix
  storage_account_name     = "st${replace(var.project_name, "-", "")}${local.suffix}"
  event_hub_namespace_name = "eh-${var.project_name}-${local.suffix}"
  cognitive_service_name   = "cs-${var.project_name}-${local.suffix}"
  logic_app_name          = "la-${var.project_name}-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project = var.project_name
    Environment = var.environment
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Cognitive Services Language Resource
resource "azurerm_cognitive_account" "text_analytics" {
  name                = local.cognitive_service_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "TextAnalytics"
  sku_name            = var.cognitive_services_sku
  
  # Enable custom subdomain for enhanced security
  custom_subdomain_name = local.cognitive_service_name
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    # In production, consider restricting to specific IP ranges
    # ip_rules       = ["123.456.789.0/24"]
  }
  
  tags = local.common_tags
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "main" {
  name                     = local.event_hub_namespace_name
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  sku                      = var.event_hub_sku
  capacity                 = var.event_hub_capacity
  auto_inflate_enabled     = var.event_hub_auto_inflate_enabled
  maximum_throughput_units = var.event_hub_auto_inflate_enabled ? var.event_hub_maximum_throughput_units : null
  
  # Enable zone redundancy for high availability (Standard SKU and above)
  zone_redundant = var.event_hub_sku != "Basic"
  
  tags = local.common_tags
}

# Event Hub for content streaming
resource "azurerm_eventhub" "content_stream" {
  name                = "content-stream"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.event_hub_partition_count
  message_retention   = var.event_hub_message_retention
  
  # Enable capture for long-term storage (optional)
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.raw_content.name
      storage_account_id  = azurerm_storage_account.main.id
    }
  }
}

# Event Hub Authorization Rule for sending events
resource "azurerm_eventhub_authorization_rule" "send_policy" {
  name                = "SendPolicy"
  eventhub_name       = azurerm_eventhub.content_stream.name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  listen = false
  send   = true
  manage = false
}

# Event Hub Authorization Rule for Logic Apps (listen and send)
resource "azurerm_eventhub_authorization_rule" "logic_app_policy" {
  name                = "LogicAppPolicy"
  eventhub_name       = azurerm_eventhub.content_stream.name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  listen = true
  send   = true
  manage = false
}

# Storage Account for processed results and archives
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  account_kind             = "StorageV2"
  
  # Enable secure transfer and blob versioning
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Enable blob versioning for data protection
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage Container for processed insights
resource "azurerm_storage_container" "processed_insights" {
  name                  = "processed-insights"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Storage Container for raw content archives
resource "azurerm_storage_container" "raw_content" {
  name                  = "raw-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Storage Container for sentiment archives
resource "azurerm_storage_container" "sentiment_archives" {
  name                  = "sentiment-archives"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Logic App for workflow orchestration
resource "azurerm_logic_app_workflow" "content_processor" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable workflow diagnostics
  enabled = true
  
  tags = local.common_tags
}

# API Connection for Event Hub
resource "azurerm_api_connection" "eventhub" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = "eventhub-connection"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/eventhubs"
  
  parameter_values = {
    connectionString = azurerm_eventhub_authorization_rule.logic_app_policy.primary_connection_string
  }
  
  tags = local.common_tags
}

# API Connection for Cognitive Services
resource "azurerm_api_connection" "cognitive_services" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = "cognitiveservices-connection"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/cognitiveservicestextanalytics"
  
  parameter_values = {
    apiKey  = azurerm_cognitive_account.text_analytics.primary_access_key
    siteUrl = azurerm_cognitive_account.text_analytics.endpoint
  }
  
  tags = local.common_tags
}

# API Connection for Azure Blob Storage
resource "azurerm_api_connection" "azureblob" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = "azureblob-connection"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/azureblob"
  
  parameter_values = {
    connectionString = azurerm_storage_account.main.primary_connection_string
  }
  
  tags = local.common_tags
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Logic App Workflow Definition (comprehensive content processing)
resource "azurerm_logic_app_trigger_http_request" "content_trigger" {
  count        = var.logic_app_enabled ? 1 : 0
  name         = "content-processing-trigger"
  logic_app_id = azurerm_logic_app_workflow.content_processor[0].id
  
  schema = jsonencode({
    type = "object"
    properties = {
      content = {
        type = "string"
      }
      source = {
        type = "string"
      }
      timestamp = {
        type = "string"
      }
    }
  })
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Enable web app monitoring
  workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = local.common_tags
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "alerts" {
  name                = "ag-${var.project_name}-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "contentproc"
  
  email_receiver {
    name                    = "admin"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
  
  tags = local.common_tags
}

# Metric Alert for Event Hub throttling
resource "azurerm_monitor_metric_alert" "eventhub_throttling" {
  name                = "eventhub-throttling-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_eventhub_namespace.main.id]
  description         = "Alert when Event Hub is being throttled"
  
  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ThrottledRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }
  
  tags = local.common_tags
}

# Metric Alert for Cognitive Services quota
resource "azurerm_monitor_metric_alert" "cognitive_quota" {
  name                = "cognitive-services-quota-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cognitive_account.text_analytics.id]
  description         = "Alert when Cognitive Services quota is near limit"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "TotalCalls"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 8000  # Adjust based on your quota
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }
  
  tags = local.common_tags
}

# Key Vault for secure storage of connection strings and keys
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = "standard"
  
  # Enable soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false  # Set to true for production
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = local.common_tags
}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore"
  ]
}

# Store Cognitive Services key in Key Vault
resource "azurerm_key_vault_secret" "cognitive_key" {
  name         = "cognitive-services-key"
  value        = azurerm_cognitive_account.text_analytics.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = local.common_tags
}

# Store Event Hub connection string in Key Vault
resource "azurerm_key_vault_secret" "eventhub_connection" {
  name         = "eventhub-connection-string"
  value        = azurerm_eventhub_authorization_rule.send_policy.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = local.common_tags
}

# Store Storage Account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current]
  
  tags = local.common_tags
}
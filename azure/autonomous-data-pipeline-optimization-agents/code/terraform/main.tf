# Data source for current Azure subscription
data "azurerm_client_config" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for resource naming
locals {
  suffix                      = random_string.suffix.result
  resource_group_name         = var.resource_group_name != "" ? var.resource_group_name : "rg-intelligent-pipeline-${local.suffix}"
  ai_foundry_hub_name         = var.ai_foundry_hub_name != "" ? var.ai_foundry_hub_name : "ai-hub-${local.suffix}"
  ai_foundry_project_name     = var.ai_foundry_project_name != "" ? var.ai_foundry_project_name : "ai-project-${local.suffix}"
  data_factory_name           = var.data_factory_name != "" ? var.data_factory_name : "adf-intelligent-${local.suffix}"
  storage_account_name        = var.storage_account_name != "" ? var.storage_account_name : "stintelligent${local.suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "la-intelligent-${local.suffix}"
  event_grid_topic_name       = var.event_grid_topic_name != "" ? var.event_grid_topic_name : "eg-pipeline-events-${local.suffix}"
  key_vault_name             = var.key_vault_name != "" ? var.key_vault_name : "kv-intelligent-${local.suffix}"
  cognitive_services_name     = var.cognitive_services_name != "" ? var.cognitive_services_name : "cs-intelligent-${local.suffix}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    ResourceGroup = local.resource_group_name
    Deployment    = "autonomous-data-pipeline-optimization"
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

# Log Analytics Workspace - Created first as it's required by other resources
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.common_tags
}

# Storage Account for Azure AI Foundry and Data Factory
resource "azurerm_storage_account" "main" {
  name                      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_replication_type
  account_kind              = "StorageV2"
  is_hns_enabled           = var.enable_hierarchical_namespace
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    versioning_enabled       = true
    last_access_time_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage containers for different data types
resource "azurerm_storage_container" "data_source" {
  name                  = "data-source"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "data_sink" {
  name                  = "data-sink"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "agent_artifacts" {
  name                  = "agent-artifacts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "pipeline_logs" {
  name                  = "pipeline-logs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Key Vault for secure credential management
resource "azurerm_key_vault" "main" {
  name                         = local.key_vault_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  sku_name                     = var.key_vault_sku
  soft_delete_retention_days   = var.key_vault_soft_delete_retention_days
  purge_protection_enabled     = false
  enable_rbac_authorization    = true
  enabled_for_disk_encryption  = true
  enabled_for_deployment       = true
  enabled_for_template_deployment = true
  
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }
  
  tags = local.common_tags
}

# Cognitive Services Account for AI capabilities
resource "azurerm_cognitive_account" "main" {
  name                = local.cognitive_services_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "CognitiveServices"
  sku_name            = var.cognitive_services_sku
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Azure Machine Learning Workspace (for AI Foundry Hub)
resource "azurerm_machine_learning_workspace" "ai_foundry_hub" {
  name                    = local.ai_foundry_hub_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id           = azurerm_key_vault.main.id
  storage_account_id     = azurerm_storage_account.main.id
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-insights-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = local.common_tags
}

# Azure Data Factory
resource "azurerm_data_factory" "main" {
  name                            = local.data_factory_name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  public_network_enabled          = var.data_factory_public_network_enabled
  managed_virtual_network_enabled = true
  
  dynamic "identity" {
    for_each = var.data_factory_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
}

# Azure Data Factory Linked Service for Storage
resource "azurerm_data_factory_linked_service_azure_blob_storage" "main" {
  name              = "AzureBlobStorage"
  data_factory_id   = azurerm_data_factory.main.id
  connection_string = azurerm_storage_account.main.primary_connection_string
}

# Azure Data Factory Dataset for source data
resource "azurerm_data_factory_dataset_azure_blob" "source" {
  name                = "SourceDataset"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.main.name
  path                = "data-source"
  filename            = "*.csv"
}

# Azure Data Factory Dataset for sink data
resource "azurerm_data_factory_dataset_azure_blob" "sink" {
  name                = "SinkDataset"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.main.name
  path                = "data-sink"
  filename            = "output.csv"
}

# Sample Data Factory Pipeline
resource "azurerm_data_factory_pipeline" "sample" {
  name            = "SampleDataPipeline"
  data_factory_id = azurerm_data_factory.main.id
  
  parameters = {
    sourceContainer = "data-source"
    sinkContainer   = "data-sink"
  }
  
  activities_json = jsonencode([
    {
      name = "CopyData"
      type = "Copy"
      typeProperties = {
        source = {
          type = "BlobSource"
        }
        sink = {
          type = "BlobSink"
        }
      }
      inputs = [
        {
          referenceName = azurerm_data_factory_dataset_azure_blob.source.name
          type          = "DatasetReference"
        }
      ]
      outputs = [
        {
          referenceName = azurerm_data_factory_dataset_azure_blob.sink.name
          type          = "DatasetReference"
        }
      ]
    }
  ])
}

# Event Grid Topic for pipeline events
resource "azurerm_eventgrid_topic" "pipeline_events" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = var.event_grid_input_schema
  
  tags = local.common_tags
}

# Event Grid System Topic for Data Factory
resource "azurerm_eventgrid_system_topic" "data_factory" {
  name                   = "datafactory-system-topic"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  source_arm_resource_id = azurerm_data_factory.main.id
  topic_type             = "Microsoft.DataFactory.Factories"
  
  tags = local.common_tags
}

# Function App for event processing (placeholder for AI agents)
resource "azurerm_service_plan" "agent_service_plan" {
  name                = "plan-agents-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1"
  
  tags = local.common_tags
}

resource "azurerm_linux_function_app" "agent_processor" {
  name                       = "func-agent-processor-${local.suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id            = azurerm_service_plan.agent_service_plan.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    always_on = false
    
    application_stack {
      python_version = "3.9"
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "AzureWebJobsFeatureFlags"     = "EnableWorkerIndexing"
    "COGNITIVE_SERVICES_ENDPOINT"  = azurerm_cognitive_account.main.endpoint
    "COGNITIVE_SERVICES_KEY"       = azurerm_cognitive_account.main.primary_access_key
    "EVENT_GRID_TOPIC_ENDPOINT"    = azurerm_eventgrid_topic.pipeline_events.endpoint
    "EVENT_GRID_TOPIC_KEY"         = azurerm_eventgrid_topic.pipeline_events.primary_access_key
    "LOG_ANALYTICS_WORKSPACE_ID"   = azurerm_log_analytics_workspace.main.workspace_id
    "LOG_ANALYTICS_WORKSPACE_KEY"  = azurerm_log_analytics_workspace.main.primary_shared_key
    "DATA_FACTORY_NAME"            = azurerm_data_factory.main.name
    "STORAGE_ACCOUNT_NAME"         = azurerm_storage_account.main.name
    "KEY_VAULT_URL"                = azurerm_key_vault.main.vault_uri
  }
  
  tags = local.common_tags
}

# Event Grid subscription for pipeline events
resource "azurerm_eventgrid_event_subscription" "pipeline_events" {
  name  = "pipeline-events-subscription"
  scope = azurerm_eventgrid_system_topic.data_factory.id
  
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.agent_processor.default_hostname}/api/pipeline-events"
  }
  
  included_event_types = [
    "Microsoft.DataFactory.PipelineRun",
    "Microsoft.DataFactory.ActivityRun",
    "Microsoft.DataFactory.TriggerRun"
  ]
  
  advanced_filter {
    string_in {
      key    = "data.status"
      values = ["Started", "Succeeded", "Failed", "Cancelled"]
    }
  }
  
  depends_on = [azurerm_linux_function_app.agent_processor]
}

# Diagnostic Settings for Data Factory
resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "datafactory-diagnostics"
  target_resource_id         = azurerm_data_factory.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = var.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }
  
  dynamic "metric" {
    for_each = var.diagnostic_metric_categories
    content {
      category = metric.value
      enabled  = true
    }
  }
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
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
    category = "AllMetrics"
    enabled  = true
  }
}

# Azure Monitor Action Group for alerts
resource "azurerm_monitor_action_group" "agent_alerts" {
  name                = "agent-alerts-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "agentalerts"
  
  webhook_receiver {
    name                    = "agent-webhook"
    service_uri             = "https://${azurerm_linux_function_app.agent_processor.default_hostname}/api/alerts"
    use_common_alert_schema = true
  }
  
  tags = local.common_tags
}

# Azure Monitor Alert Rule for agent failures
resource "azurerm_monitor_metric_alert" "agent_failures" {
  name                = "agent-failure-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.agent_processor.id]
  description         = "Alert when agent processing fails"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.agent_alerts.id
  }
  
  tags = local.common_tags
}

# Azure Monitor Alert Rule for pipeline failures
resource "azurerm_monitor_metric_alert" "pipeline_failures" {
  name                = "pipeline-failure-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_data_factory.main.id]
  description         = "Alert when Data Factory pipeline fails"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.agent_alerts.id
  }
  
  tags = local.common_tags
}

# Role assignments for managed identities
resource "azurerm_role_assignment" "data_factory_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.agent_processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_keyvault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.agent_processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_data_factory" {
  scope                = azurerm_data_factory.main.id
  role_definition_name = "Data Factory Contributor"
  principal_id         = azurerm_linux_function_app.agent_processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_monitor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_linux_function_app.agent_processor.identity[0].principal_id
}

# Store sensitive configuration in Key Vault
resource "azurerm_key_vault_secret" "cognitive_services_key" {
  name         = "cognitive-services-key"
  value        = azurerm_cognitive_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_keyvault]
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_keyvault]
}

resource "azurerm_key_vault_secret" "event_grid_key" {
  name         = "event-grid-key"
  value        = azurerm_eventgrid_topic.pipeline_events.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.function_app_keyvault]
}

# Azure Monitor Workbook for comprehensive monitoring
resource "azurerm_application_insights_workbook" "agent_monitoring" {
  name                = "agent-monitoring-workbook"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Intelligent Pipeline Agent Monitoring"
  
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Intelligent Pipeline Agent Monitoring Dashboard\n\nThis workbook provides comprehensive monitoring for autonomous data pipeline optimization agents."
        }
      }
    ]
  })
  
  tags = local.common_tags
}
# Terraform configuration for Intelligent Alert Response System with Azure Monitor Workbooks and Azure Functions
# This configuration creates a comprehensive intelligent alert response system using Azure Monitor Workbooks,
# Azure Functions, Event Grid, Logic Apps, and supporting services for automated alert processing and response.

# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
    project     = "alert-response-system"
  }
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Storage Account for Azure Functions
resource "azurerm_storage_account" "functions" {
  name                     = "${var.storage_account_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  https_traffic_only_enabled = true

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Key Vault for secure configuration
resource "azurerm_key_vault" "main" {
  name                        = "${var.key_vault_name}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  enable_rbac_authorization   = true

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Cosmos DB Account for alert state management
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.cosmos_db_account_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  enable_free_tier = false

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "AlertDatabase"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Create Cosmos DB SQL Container for alert states
resource "azurerm_cosmosdb_sql_container" "alert_states" {
  name                  = "AlertStates"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/alertId"
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

# Create Event Grid Topic for alert orchestration
resource "azurerm_eventgrid_topic" "main" {
  name                = "${var.event_grid_topic_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Application Insights for Functions monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.application_insights_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create App Service Plan for Functions
resource "azurerm_service_plan" "main" {
  name                = "${var.function_app_name}-plan-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Azure Function App for alert processing
resource "azurerm_linux_function_app" "main" {
  name                = "${var.function_app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "COSMOS_DB_CONNECTION_STRING"    = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/cosmos-connection/)"
    "EVENT_GRID_ENDPOINT"            = azurerm_eventgrid_topic.main.endpoint
    "EVENT_GRID_KEY"                 = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/eventgrid-key/)"
    "LOG_ANALYTICS_WORKSPACE_ID"     = azurerm_log_analytics_workspace.main.workspace_id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Logic App for notification orchestration
resource "azurerm_logic_app_workflow" "main" {
  name                = "${var.logic_app_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  workflow_schema = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"

  parameters = {
    "$connections" = {
      "defaultValue" = {}
      "type"         = "Object"
    }
  }

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Monitor Workbook for alert dashboard
resource "azurerm_application_insights_workbook" "main" {
  name                = "${var.workbook_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Intelligent Alert Response Dashboard"
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Intelligent Alert Response Dashboard\n\nThis workbook provides real-time insights into alert patterns, response effectiveness, and system health."
        }
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AlertsManagementResources\n| where type == \"microsoft.alertsmanagement/alerts\"\n| summarize AlertCount = count() by tostring(properties.severity)\n| order by AlertCount desc"
          size         = 1
          title        = "Alert Count by Severity"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "piechart"
        }
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "AlertsManagementResources\n| where type == \"microsoft.alertsmanagement/alerts\"\n| extend AlertTime = todatetime(properties.essentials.startDateTime)\n| where AlertTime > ago(24h)\n| summarize AlertCount = count() by bin(AlertTime, 1h)\n| order by AlertTime asc"
          size         = 0
          title        = "Alert Trends (24 Hours)"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "timechart"
        }
      }
    ]
  })

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create Action Group for testing
resource "azurerm_monitor_action_group" "test" {
  name                = "test-alert-actions-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "testalert"

  webhook_receiver {
    name                    = "eventgrid"
    service_uri             = azurerm_eventgrid_topic.main.endpoint
    use_common_alert_schema = true
  }

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Create test metric alert rule
resource "azurerm_monitor_metric_alert" "test" {
  name                = "test-cpu-alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_resource_group.main.id]
  description         = "Test alert rule for intelligent response system"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.test.id
  }

  tags = {
    purpose     = "intelligent-alerts"
    environment = var.environment
  }
}

# Store Cosmos DB connection string in Key Vault
resource "azurerm_key_vault_secret" "cosmos_connection" {
  name         = "cosmos-connection"
  value        = azurerm_cosmosdb_account.main.connection_strings[0]
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Store Event Grid access key in Key Vault
resource "azurerm_key_vault_secret" "eventgrid_key" {
  name         = "eventgrid-key"
  value        = azurerm_eventgrid_topic.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Create Event Grid subscription for Function App
resource "azurerm_eventgrid_event_subscription" "function_subscription" {
  name  = "alerts-to-function"
  scope = azurerm_eventgrid_topic.main.id

  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/ProcessAlert"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  included_event_types = [
    "Microsoft.AlertManagement.Alert.Activated",
    "Microsoft.AlertManagement.Alert.Resolved"
  ]

  depends_on = [azurerm_linux_function_app.main]
}

# Create Event Grid subscription for Logic App
resource "azurerm_eventgrid_event_subscription" "logic_subscription" {
  name  = "alerts-to-logic"
  scope = azurerm_eventgrid_topic.main.id

  webhook_endpoint {
    url                               = azurerm_logic_app_workflow.main.access_endpoint
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  included_event_types = [
    "Microsoft.AlertManagement.Alert.Activated"
  ]

  advanced_filter {
    string_in {
      key    = "data.severity"
      values = ["high", "critical"]
    }
  }

  depends_on = [azurerm_logic_app_workflow.main]
}

# Role assignments for Key Vault access
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant Function App access to Key Vault
resource "azurerm_role_assignment" "function_keyvault_access" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Cosmos DB
resource "azurerm_role_assignment" "function_cosmos_access" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Event Grid
resource "azurerm_role_assignment" "function_eventgrid_access" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}
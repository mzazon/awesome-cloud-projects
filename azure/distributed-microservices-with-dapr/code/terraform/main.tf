# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace for monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_in_days
  tags                = var.tags
}

# Application Insights for distributed tracing
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = var.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# Service Bus Namespace for pub/sub messaging
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  tags                = var.tags
}

# Service Bus Topic for order events
resource "azurerm_servicebus_topic" "orders" {
  name         = var.service_bus_topic_name
  namespace_id = azurerm_servicebus_namespace.main.id

  # Configure message retention and sizing
  default_message_ttl                     = "P14D"    # 14 days
  max_message_size_in_kilobytes          = 256
  requires_duplicate_detection           = false
  support_ordering                       = true
  auto_delete_on_idle                    = "P10675199DT2H48M5.4775807S"  # Max value
  enable_batched_operations              = true
  enable_express                         = false
  enable_partitioning                    = false
}

# Service Bus Authorization Rule for Dapr access
resource "azurerm_servicebus_namespace_authorization_rule" "dapr" {
  name         = "DaprAccess"
  namespace_id = azurerm_servicebus_namespace.main.id
  listen       = true
  send         = true
  manage       = false
}

# Cosmos DB Account for state management
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = var.cosmos_db_offer_type
  kind                = "GlobalDocumentDB"

  # Enable serverless capacity mode for cost optimization
  capabilities {
    name = "EnableServerless"
  }

  # Consistency policy configuration
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  # Geographic location configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Security and backup configuration
  public_network_access_enabled   = true
  is_virtual_network_filter_enabled = false
  enable_automatic_failover       = false
  enable_multiple_write_locations = false

  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Geo"
  }

  tags = var.tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = var.cosmos_db_database_name
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB SQL Container for state storage
resource "azurerm_cosmosdb_sql_container" "statestore" {
  name                   = var.cosmos_db_container_name
  resource_group_name    = azurerm_resource_group.main.name
  account_name           = azurerm_cosmosdb_account.main.name
  database_name          = azurerm_cosmosdb_sql_database.main.name
  partition_key_path     = var.cosmos_db_partition_key_path
  partition_key_version  = 1

  # Indexing policy for optimal performance
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

# Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                        = "kv-${var.project_name}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  purge_protection_enabled    = false
  sku_name                    = var.key_vault_sku_name
  
  # Enable RBAC authorization
  enable_rbac_authorization = true

  tags = var.tags
}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
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

# Store Service Bus connection string in Key Vault
resource "azurerm_key_vault_secret" "servicebus_connection" {
  name         = "servicebus-connectionstring"
  value        = azurerm_servicebus_namespace_authorization_rule.dapr.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]
  tags         = var.tags
}

# Store Cosmos DB URL in Key Vault
resource "azurerm_key_vault_secret" "cosmosdb_url" {
  name         = "cosmosdb-url"
  value        = azurerm_cosmosdb_account.main.endpoint
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]
  tags         = var.tags
}

# Store Cosmos DB primary key in Key Vault
resource "azurerm_key_vault_secret" "cosmosdb_key" {
  name         = "cosmosdb-key"
  value        = azurerm_cosmosdb_account.main.primary_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]
  tags         = var.tags
}

# Container Apps Environment with Dapr enabled
resource "azurerm_container_app_environment" "main" {
  name                       = var.container_apps_environment_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.tags

  # Enable Dapr for the environment
  dapr_application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
}

# Dapr Component: Service Bus Pub/Sub
resource "azurerm_container_app_environment_dapr_component" "pubsub" {
  name                         = "pubsub"
  container_app_environment_id = azurerm_container_app_environment.main.id
  component_type               = "pubsub.azure.servicebus"
  version                      = "v1"

  metadata {
    name  = "connectionString"
    value = azurerm_servicebus_namespace_authorization_rule.dapr.primary_connection_string
  }

  # Scope to specific services
  scopes = [var.order_service_name, var.inventory_service_name]
}

# Dapr Component: Cosmos DB State Store
resource "azurerm_container_app_environment_dapr_component" "statestore" {
  name                         = "statestore"
  container_app_environment_id = azurerm_container_app_environment.main.id
  component_type               = "state.azure.cosmosdb"
  version                      = "v1"

  metadata {
    name  = "url"
    value = azurerm_cosmosdb_account.main.endpoint
  }

  metadata {
    name  = "masterKey"
    value = azurerm_cosmosdb_account.main.primary_key
  }

  metadata {
    name  = "database"
    value = var.cosmos_db_database_name
  }

  metadata {
    name  = "collection"
    value = var.cosmos_db_container_name
  }

  # Scope to specific services
  scopes = [var.order_service_name, var.inventory_service_name]
}

# Container App: Order Service
resource "azurerm_container_app" "order_service" {
  name                         = var.order_service_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = var.tags

  # Dapr configuration
  dapr {
    app_id       = var.order_service_name
    app_port     = 80
    app_protocol = "http"
  }

  # Template configuration
  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "order-service"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # Environment variables for Dapr integration
      env {
        name  = "DAPR_HTTP_PORT"
        value = "3500"
      }

      env {
        name  = "PUBSUB_NAME"
        value = "pubsub"
      }

      env {
        name  = "TOPIC_NAME"
        value = var.service_bus_topic_name
      }

      env {
        name  = "STATE_STORE_NAME"
        value = "statestore"
      }

      # Application Insights connection string (if enabled)
      dynamic "env" {
        for_each = var.enable_application_insights ? [1] : []
        content {
          name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
          value = azurerm_application_insights.main[0].connection_string
        }
      }
    }
  }

  # Ingress configuration for external access
  ingress {
    external_enabled = true
    target_port      = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_container_app_environment_dapr_component.pubsub,
    azurerm_container_app_environment_dapr_component.statestore
  ]
}

# Container App: Inventory Service
resource "azurerm_container_app" "inventory_service" {
  name                         = var.inventory_service_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = var.tags

  # Dapr configuration
  dapr {
    app_id       = var.inventory_service_name
    app_port     = 80
    app_protocol = "http"
  }

  # Template configuration
  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "inventory-service"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # Environment variables for Dapr integration
      env {
        name  = "DAPR_HTTP_PORT"
        value = "3500"
      }

      env {
        name  = "PUBSUB_NAME"
        value = "pubsub"
      }

      env {
        name  = "TOPIC_NAME"
        value = var.service_bus_topic_name
      }

      env {
        name  = "STATE_STORE_NAME"
        value = "statestore"
      }

      # Application Insights connection string (if enabled)
      dynamic "env" {
        for_each = var.enable_application_insights ? [1] : []
        content {
          name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
          value = azurerm_application_insights.main[0].connection_string
        }
      }
    }
  }

  # Ingress configuration for internal access only
  ingress {
    external_enabled = false
    target_port      = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_container_app_environment_dapr_component.pubsub,
    azurerm_container_app_environment_dapr_component.statestore
  ]
}
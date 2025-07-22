# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current client configuration
data "azurerm_client_config" "current" {}

# Get subscription information
data "azurerm_subscription" "current" {}

# ==============================================================================
# RANDOM RESOURCES
# ==============================================================================

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  # Generate unique names for resources
  resource_suffix = random_string.suffix.result
  
  # Resource names with suffix
  ai_foundry_name            = "aif-${var.project_name}-${local.resource_suffix}"
  storage_account_name       = "st${var.project_name}${local.resource_suffix}"
  cosmos_account_name        = "cosmos-${var.project_name}-${local.resource_suffix}"
  container_environment_name = var.container_apps_environment_name != "" ? var.container_apps_environment_name : "cae-${var.project_name}-${local.resource_suffix}"
  event_grid_topic_name      = var.event_grid_topic_name != "" ? var.event_grid_topic_name : "egt-${var.project_name}-${local.resource_suffix}"
  app_insights_name          = var.application_insights_name != "" ? var.application_insights_name : "ai-${var.project_name}-${local.resource_suffix}"
  log_analytics_name         = var.container_apps_log_analytics_workspace_name != "" ? var.container_apps_log_analytics_workspace_name : "log-${var.project_name}-${local.resource_suffix}"
  key_vault_name             = var.key_vault_name != "" ? var.key_vault_name : "kv-${var.project_name}-${local.resource_suffix}"
  container_registry_name    = var.container_registry_name != "" ? var.container_registry_name : "cr${var.project_name}${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Create resource group for all resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ==============================================================================
# LOG ANALYTICS WORKSPACE
# ==============================================================================

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_analytics_workspace_retention
  tags                = local.common_tags
}

# ==============================================================================
# APPLICATION INSIGHTS
# ==============================================================================

# Create Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  tags                = local.common_tags
}

# ==============================================================================
# KEY VAULT
# ==============================================================================

# Create Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                            = local.key_vault_name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  enabled_for_disk_encryption     = var.key_vault_enabled_for_disk_encryption
  enabled_for_deployment          = var.key_vault_enabled_for_deployment
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days      = var.key_vault_soft_delete_retention_days
  purge_protection_enabled        = var.key_vault_purge_protection_enabled
  sku_name                        = var.key_vault_sku
  tags                            = local.common_tags

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "List",
      "Update",
      "Create",
      "Import",
      "Delete",
      "Recover",
      "Backup",
      "Restore",
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Backup",
      "Restore",
    ]

    certificate_permissions = [
      "Get",
      "List",
      "Update",
      "Create",
      "Import",
      "Delete",
      "Recover",
      "Backup",
      "Restore",
      "ManageContacts",
      "ManageIssuers",
      "GetIssuers",
      "ListIssuers",
      "SetIssuers",
      "DeleteIssuers",
    ]
  }
}

# ==============================================================================
# CONTAINER REGISTRY
# ==============================================================================

# Create Container Registry for storing agent images
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  tags                = local.common_tags

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
}

# ==============================================================================
# STORAGE ACCOUNT
# ==============================================================================

# Create storage account for agent data and dead letter queues
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  tags                     = local.common_tags

  # Enable blob versioning and soft delete
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
}

# Create storage container for dead letter events
resource "azurerm_storage_container" "deadletter" {
  name                  = "deadletter-events"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create storage container for agent data
resource "azurerm_storage_container" "agent_data" {
  name                  = "agent-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ==============================================================================
# COSMOS DB
# ==============================================================================

# Create Cosmos DB account for agent state management
resource "azurerm_cosmosdb_account" "main" {
  name                      = local.cosmos_account_name
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  offer_type                = var.cosmos_db_offer_type
  kind                      = var.cosmos_db_kind
  enable_automatic_failover = var.cosmos_db_enable_automatic_failover
  tags                      = local.common_tags

  # Configure consistency policy
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_policy.consistency_level
    max_interval_in_seconds = var.cosmos_db_consistency_policy.max_interval_in_seconds
    max_staleness_prefix    = var.cosmos_db_consistency_policy.max_staleness_prefix
  }

  # Configure geographic location
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Enable backup
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
  }
}

# Create Cosmos DB database for agent state
resource "azurerm_cosmosdb_sql_database" "agent_state" {
  name                = "agent-state"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = 400
}

# Create Cosmos DB container for conversation state
resource "azurerm_cosmosdb_sql_container" "conversations" {
  name                  = "conversations"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.agent_state.name
  partition_key_path    = "/conversationId"
  partition_key_version = 1
  throughput            = 400
}

# Create Cosmos DB container for workflow state
resource "azurerm_cosmosdb_sql_container" "workflows" {
  name                  = "workflows"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.agent_state.name
  partition_key_path    = "/workflowId"
  partition_key_version = 1
  throughput            = 400
}

# ==============================================================================
# AZURE AI FOUNDRY (COGNITIVE SERVICES)
# ==============================================================================

# Create Azure AI Foundry resource for AI capabilities
resource "azurerm_cognitive_services_account" "main" {
  name                = local.ai_foundry_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = var.ai_foundry_kind
  sku_name            = var.ai_foundry_sku
  tags                = local.common_tags

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Configure network access
  network_acls {
    default_action = "Allow"
  }
}

# Deploy GPT-4 model for agents
resource "azurerm_cognitive_services_account_deployment" "gpt4" {
  name                   = "gpt-4-deployment"
  cognitive_services_account_id = azurerm_cognitive_services_account.main.id
  model {
    format  = var.gpt_model_deployment.model_format
    name    = var.gpt_model_deployment.model_name
    version = var.gpt_model_deployment.model_version
  }
  
  sku {
    name     = var.gpt_model_deployment.sku_name
    capacity = var.gpt_model_deployment.sku_capacity
  }
}

# Store AI Foundry connection string in Key Vault
resource "azurerm_key_vault_secret" "ai_foundry_connection" {
  name         = "ai-foundry-connection-string"
  value        = azurerm_cognitive_services_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

# ==============================================================================
# EVENT GRID
# ==============================================================================

# Create Event Grid topic for agent communication
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = var.event_grid_input_schema
  tags                = local.common_tags

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
}

# Store Event Grid connection details in Key Vault
resource "azurerm_key_vault_secret" "event_grid_endpoint" {
  name         = "event-grid-endpoint"
  value        = azurerm_eventgrid_topic.main.endpoint
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

resource "azurerm_key_vault_secret" "event_grid_key" {
  name         = "event-grid-key"
  value        = azurerm_eventgrid_topic.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

# ==============================================================================
# CONTAINER APPS ENVIRONMENT
# ==============================================================================

# Create Container Apps environment for hosting agents
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_environment_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.common_tags

  # Configure workload profile for consumption-based scaling
  workload_profile {
    name                  = var.container_apps_workload_profile.name
    workload_profile_type = var.container_apps_workload_profile.workload_profile_type
    minimum_count         = var.container_apps_workload_profile.minimum_count
    maximum_count         = var.container_apps_workload_profile.maximum_count
  }
}

# ==============================================================================
# CONTAINER APPS - COORDINATOR AGENT
# ==============================================================================

# Create coordinator agent container app
resource "azurerm_container_app" "coordinator" {
  name                         = "coordinator-agent"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  # Configure template for coordinator agent
  template {
    min_replicas = var.coordinator_agent_config.min_replicas
    max_replicas = var.coordinator_agent_config.max_replicas

    container {
      name   = "coordinator-agent"
      image  = var.coordinator_agent_config.image
      cpu    = var.coordinator_agent_config.cpu
      memory = var.coordinator_agent_config.memory

      # Environment variables for coordinator agent
      env {
        name  = "AI_FOUNDRY_ENDPOINT"
        value = azurerm_cognitive_services_account.main.endpoint
      }
      
      env {
        name        = "AI_FOUNDRY_KEY"
        secret_name = "ai-foundry-key"
      }
      
      env {
        name        = "EVENT_GRID_ENDPOINT"
        secret_name = "event-grid-endpoint"
      }
      
      env {
        name        = "EVENT_GRID_KEY"
        secret_name = "event-grid-key"
      }
      
      env {
        name        = "COSMOS_CONNECTION_STRING"
        secret_name = "cosmos-connection-string"
      }
      
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
    }
  }

  # Configure ingress for coordinator agent
  ingress {
    external_enabled = var.coordinator_agent_config.ingress_type == "external"
    target_port      = var.coordinator_agent_config.target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # Configure secrets for coordinator agent
  secret {
    name  = "ai-foundry-key"
    value = azurerm_cognitive_services_account.main.primary_access_key
  }
  
  secret {
    name  = "event-grid-endpoint"
    value = azurerm_eventgrid_topic.main.endpoint
  }
  
  secret {
    name  = "event-grid-key"
    value = azurerm_eventgrid_topic.main.primary_access_key
  }
  
  secret {
    name  = "cosmos-connection-string"
    value = azurerm_cosmosdb_account.main.connection_strings[0]
  }
  
  secret {
    name  = "app-insights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }
}

# ==============================================================================
# CONTAINER APPS - DOCUMENT AGENT
# ==============================================================================

# Create document processing agent container app
resource "azurerm_container_app" "document" {
  name                         = "document-agent"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  # Configure template for document agent
  template {
    min_replicas = var.document_agent_config.min_replicas
    max_replicas = var.document_agent_config.max_replicas

    container {
      name   = "document-agent"
      image  = var.document_agent_config.image
      cpu    = var.document_agent_config.cpu
      memory = var.document_agent_config.memory

      # Environment variables for document agent
      env {
        name  = "AI_FOUNDRY_ENDPOINT"
        value = azurerm_cognitive_services_account.main.endpoint
      }
      
      env {
        name        = "AI_FOUNDRY_KEY"
        secret_name = "ai-foundry-key"
      }
      
      env {
        name        = "EVENT_GRID_ENDPOINT"
        secret_name = "event-grid-endpoint"
      }
      
      env {
        name        = "EVENT_GRID_KEY"
        secret_name = "event-grid-key"
      }
      
      env {
        name        = "STORAGE_CONNECTION_STRING"
        secret_name = "storage-connection-string"
      }
      
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
    }
  }

  # Configure ingress for document agent
  ingress {
    external_enabled = var.document_agent_config.ingress_type == "external"
    target_port      = var.document_agent_config.target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # Configure secrets for document agent
  secret {
    name  = "ai-foundry-key"
    value = azurerm_cognitive_services_account.main.primary_access_key
  }
  
  secret {
    name  = "event-grid-endpoint"
    value = azurerm_eventgrid_topic.main.endpoint
  }
  
  secret {
    name  = "event-grid-key"
    value = azurerm_eventgrid_topic.main.primary_access_key
  }
  
  secret {
    name  = "storage-connection-string"
    value = azurerm_storage_account.main.primary_connection_string
  }
  
  secret {
    name  = "app-insights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }
}

# ==============================================================================
# CONTAINER APPS - DATA ANALYSIS AGENT
# ==============================================================================

# Create data analysis agent container app
resource "azurerm_container_app" "data_analysis" {
  name                         = "data-analysis-agent"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  # Configure template for data analysis agent
  template {
    min_replicas = var.data_analysis_agent_config.min_replicas
    max_replicas = var.data_analysis_agent_config.max_replicas

    container {
      name   = "data-analysis-agent"
      image  = var.data_analysis_agent_config.image
      cpu    = var.data_analysis_agent_config.cpu
      memory = var.data_analysis_agent_config.memory

      # Environment variables for data analysis agent
      env {
        name  = "AI_FOUNDRY_ENDPOINT"
        value = azurerm_cognitive_services_account.main.endpoint
      }
      
      env {
        name        = "AI_FOUNDRY_KEY"
        secret_name = "ai-foundry-key"
      }
      
      env {
        name        = "EVENT_GRID_ENDPOINT"
        secret_name = "event-grid-endpoint"
      }
      
      env {
        name        = "EVENT_GRID_KEY"
        secret_name = "event-grid-key"
      }
      
      env {
        name        = "STORAGE_CONNECTION_STRING"
        secret_name = "storage-connection-string"
      }
      
      env {
        name        = "COSMOS_CONNECTION_STRING"
        secret_name = "cosmos-connection-string"
      }
      
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
    }
  }

  # Configure ingress for data analysis agent
  ingress {
    external_enabled = var.data_analysis_agent_config.ingress_type == "external"
    target_port      = var.data_analysis_agent_config.target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # Configure secrets for data analysis agent
  secret {
    name  = "ai-foundry-key"
    value = azurerm_cognitive_services_account.main.primary_access_key
  }
  
  secret {
    name  = "event-grid-endpoint"
    value = azurerm_eventgrid_topic.main.endpoint
  }
  
  secret {
    name  = "event-grid-key"
    value = azurerm_eventgrid_topic.main.primary_access_key
  }
  
  secret {
    name  = "storage-connection-string"
    value = azurerm_storage_account.main.primary_connection_string
  }
  
  secret {
    name  = "cosmos-connection-string"
    value = azurerm_cosmosdb_account.main.connection_strings[0]
  }
  
  secret {
    name  = "app-insights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }
}

# ==============================================================================
# CONTAINER APPS - CUSTOMER SERVICE AGENT
# ==============================================================================

# Create customer service agent container app
resource "azurerm_container_app" "customer_service" {
  name                         = "customer-service-agent"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  # Configure template for customer service agent
  template {
    min_replicas = var.customer_service_agent_config.min_replicas
    max_replicas = var.customer_service_agent_config.max_replicas

    container {
      name   = "customer-service-agent"
      image  = var.customer_service_agent_config.image
      cpu    = var.customer_service_agent_config.cpu
      memory = var.customer_service_agent_config.memory

      # Environment variables for customer service agent
      env {
        name  = "AI_FOUNDRY_ENDPOINT"
        value = azurerm_cognitive_services_account.main.endpoint
      }
      
      env {
        name        = "AI_FOUNDRY_KEY"
        secret_name = "ai-foundry-key"
      }
      
      env {
        name        = "EVENT_GRID_ENDPOINT"
        secret_name = "event-grid-endpoint"
      }
      
      env {
        name        = "EVENT_GRID_KEY"
        secret_name = "event-grid-key"
      }
      
      env {
        name        = "COSMOS_CONNECTION_STRING"
        secret_name = "cosmos-connection-string"
      }
      
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
    }
  }

  # Configure ingress for customer service agent
  ingress {
    external_enabled = var.customer_service_agent_config.ingress_type == "external"
    target_port      = var.customer_service_agent_config.target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # Configure secrets for customer service agent
  secret {
    name  = "ai-foundry-key"
    value = azurerm_cognitive_services_account.main.primary_access_key
  }
  
  secret {
    name  = "event-grid-endpoint"
    value = azurerm_eventgrid_topic.main.endpoint
  }
  
  secret {
    name  = "event-grid-key"
    value = azurerm_eventgrid_topic.main.primary_access_key
  }
  
  secret {
    name  = "cosmos-connection-string"
    value = azurerm_cosmosdb_account.main.connection_strings[0]
  }
  
  secret {
    name  = "app-insights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }
}

# ==============================================================================
# CONTAINER APPS - API GATEWAY
# ==============================================================================

# Create API gateway container app
resource "azurerm_container_app" "api_gateway" {
  name                         = "api-gateway"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  # Configure template for API gateway
  template {
    min_replicas = var.api_gateway_config.min_replicas
    max_replicas = var.api_gateway_config.max_replicas

    container {
      name   = "api-gateway"
      image  = var.api_gateway_config.image
      cpu    = var.api_gateway_config.cpu
      memory = var.api_gateway_config.memory

      # Environment variables for API gateway
      env {
        name  = "COORDINATOR_ENDPOINT"
        value = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}"
      }
      
      env {
        name        = "EVENT_GRID_ENDPOINT"
        secret_name = "event-grid-endpoint"
      }
      
      env {
        name        = "EVENT_GRID_KEY"
        secret_name = "event-grid-key"
      }
      
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
    }
  }

  # Configure ingress for API gateway
  ingress {
    external_enabled = var.api_gateway_config.ingress_type == "external"
    target_port      = var.api_gateway_config.target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # Configure secrets for API gateway
  secret {
    name  = "event-grid-endpoint"
    value = azurerm_eventgrid_topic.main.endpoint
  }
  
  secret {
    name  = "event-grid-key"
    value = azurerm_eventgrid_topic.main.primary_access_key
  }
  
  secret {
    name  = "app-insights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }
}

# ==============================================================================
# EVENT GRID SUBSCRIPTIONS
# ==============================================================================

# Create Event Grid subscription for document agent
resource "azurerm_eventgrid_event_subscription" "document_agent" {
  name  = "document-agent-subscription"
  scope = azurerm_eventgrid_topic.main.id

  # Configure webhook endpoint
  webhook_endpoint {
    url = "https://${azurerm_container_app.document.ingress[0].fqdn}/api/events"
  }

  # Configure event types and filtering
  included_event_types = var.event_grid_subscriptions.document_agent.included_event_types
  
  subject_filter {
    subject_begins_with = var.event_grid_subscriptions.document_agent.subject_filter
  }

  # Configure retry and dead letter policies
  retry_policy {
    max_delivery_attempts = var.event_grid_subscriptions.document_agent.max_delivery_attempts
    event_time_to_live    = var.event_grid_subscriptions.document_agent.event_ttl
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  depends_on = [azurerm_container_app.document]
}

# Create Event Grid subscription for data analysis agent
resource "azurerm_eventgrid_event_subscription" "data_analysis_agent" {
  name  = "data-analysis-subscription"
  scope = azurerm_eventgrid_topic.main.id

  # Configure webhook endpoint
  webhook_endpoint {
    url = "https://${azurerm_container_app.data_analysis.ingress[0].fqdn}/api/events"
  }

  # Configure event types and filtering
  included_event_types = var.event_grid_subscriptions.data_analysis.included_event_types
  
  subject_filter {
    subject_begins_with = var.event_grid_subscriptions.data_analysis.subject_filter
  }

  # Configure retry and dead letter policies
  retry_policy {
    max_delivery_attempts = var.event_grid_subscriptions.data_analysis.max_delivery_attempts
    event_time_to_live    = var.event_grid_subscriptions.data_analysis.event_ttl
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  depends_on = [azurerm_container_app.data_analysis]
}

# Create Event Grid subscription for customer service agent
resource "azurerm_eventgrid_event_subscription" "customer_service_agent" {
  name  = "customer-service-subscription"
  scope = azurerm_eventgrid_topic.main.id

  # Configure webhook endpoint
  webhook_endpoint {
    url = "https://${azurerm_container_app.customer_service.ingress[0].fqdn}/api/events"
  }

  # Configure event types and filtering
  included_event_types = var.event_grid_subscriptions.customer_service.included_event_types
  
  subject_filter {
    subject_begins_with = var.event_grid_subscriptions.customer_service.subject_filter
  }

  # Configure retry and dead letter policies
  retry_policy {
    max_delivery_attempts = var.event_grid_subscriptions.customer_service.max_delivery_attempts
    event_time_to_live    = var.event_grid_subscriptions.customer_service.event_ttl
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  depends_on = [azurerm_container_app.customer_service]
}

# Create Event Grid subscription for workflow orchestration
resource "azurerm_eventgrid_event_subscription" "workflow_orchestration" {
  name  = "workflow-orchestration"
  scope = azurerm_eventgrid_topic.main.id

  # Configure webhook endpoint
  webhook_endpoint {
    url = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}/api/orchestration"
  }

  # Configure event types and filtering
  included_event_types = var.event_grid_subscriptions.workflow_orchestration.included_event_types
  
  subject_filter {
    subject_begins_with = var.event_grid_subscriptions.workflow_orchestration.subject_filter
  }

  # Configure retry and dead letter policies
  retry_policy {
    max_delivery_attempts = var.event_grid_subscriptions.workflow_orchestration.max_delivery_attempts
    event_time_to_live    = var.event_grid_subscriptions.workflow_orchestration.event_ttl
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  depends_on = [azurerm_container_app.coordinator]
}

# Create Event Grid subscription for agent health monitoring
resource "azurerm_eventgrid_event_subscription" "health_monitoring" {
  name  = "agent-health-monitoring"
  scope = azurerm_eventgrid_topic.main.id

  # Configure webhook endpoint
  webhook_endpoint {
    url = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}/api/health"
  }

  # Configure event types and filtering
  included_event_types = var.event_grid_subscriptions.health_monitoring.included_event_types
  
  subject_filter {
    subject_begins_with = var.event_grid_subscriptions.health_monitoring.subject_filter
  }

  # Configure retry and dead letter policies
  retry_policy {
    max_delivery_attempts = var.event_grid_subscriptions.health_monitoring.max_delivery_attempts
    event_time_to_live    = var.event_grid_subscriptions.health_monitoring.event_ttl
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }

  depends_on = [azurerm_container_app.coordinator]
}

# ==============================================================================
# MONITORING ALERTS
# ==============================================================================

# Create metric alert for agent response time
resource "azurerm_monitor_metric_alert" "agent_response_time" {
  name                = "agent-response-time-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.coordinator.id]
  description         = "Alert when agent response time exceeds 5 seconds"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000

    dimension {
      name     = "RevisionName"
      operator = "Include"
      values   = ["*"]
    }
  }

  # Configure alert action (can be extended with action groups)
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Create action group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  name                = "multi-agent-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "AgentAlerts"
  tags                = local.common_tags

  # Add webhook action for alert notifications
  webhook_receiver {
    name                    = "webhook-alert"
    service_uri             = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}/api/alerts"
    use_common_alert_schema = true
  }
}
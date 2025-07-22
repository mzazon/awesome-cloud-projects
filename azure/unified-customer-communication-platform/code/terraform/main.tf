# Multi-Channel Customer Communication Platform with Azure Communication Services and Event Grid
# This Terraform configuration deploys a complete multi-channel communication platform
# using Azure Communication Services, Event Grid, Functions, and Cosmos DB

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_string.suffix.result
  
  # Standardized resource names
  communication_service_name = "acs-${var.project_name}-${local.resource_suffix}"
  eventgrid_topic_name       = "egt-${var.project_name}-${local.resource_suffix}"
  function_app_name          = "func-${var.project_name}-${local.resource_suffix}"
  storage_account_name       = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  cosmos_account_name        = "cosmos-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name      = "asp-${var.project_name}-${local.resource_suffix}"
  app_insights_name          = "appi-${var.project_name}-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    DeployedBy    = "terraform"
    LastModified  = timestamp()
  })
}

# Resource Group for all communication platform resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure Communication Services resource for multi-channel messaging
# Provides unified APIs for email, SMS, and WhatsApp communications
resource "azurerm_communication_service" "main" {
  name                = local.communication_service_name
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.communication_services_data_location
  tags                = local.common_tags
  
  # Communication Services requires explicit dependencies
  depends_on = [azurerm_resource_group.main]
}

# Storage Account for Azure Functions runtime and message artifacts
# Configured with secure defaults and lifecycle management
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  
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

# Azure Cosmos DB Account for conversation and message storage
# Configured with session consistency for optimal performance
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Consistency policy optimized for messaging applications
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_level
    max_interval_in_seconds = var.cosmos_db_max_interval_in_seconds
    max_staleness_prefix    = var.cosmos_db_max_staleness_prefix
  }
  
  # Primary geo-location
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Backup configuration for data protection
  dynamic "backup" {
    for_each = var.enable_cosmos_db_backup ? [1] : []
    content {
      type                = "Periodic"
      interval_in_minutes = var.cosmos_db_backup_interval_in_minutes
      retention_in_hours  = var.cosmos_db_backup_retention_in_hours
    }
  }
  
  # Security configurations
  public_network_access_enabled = true
  is_virtual_network_filter_enabled = false
  
  tags = local.common_tags
}

# Cosmos DB SQL Database for communication platform data
resource "azurerm_cosmosdb_sql_database" "communication_db" {
  name                = "CommunicationPlatform"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  
  # Auto-scaling configuration
  autoscale_settings {
    max_throughput = 4000
  }
}

# Cosmos DB Container for conversation metadata and customer information
resource "azurerm_cosmosdb_sql_container" "conversations" {
  name                  = "Conversations"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.communication_db.name
  partition_key_path    = "/customerId"
  partition_key_version = 1
  
  # Indexing policy optimized for conversation queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Auto-scaling configuration
  autoscale_settings {
    max_throughput = 4000
  }
}

# Cosmos DB Container for individual messages across all channels
resource "azurerm_cosmosdb_sql_container" "messages" {
  name                  = "Messages"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.communication_db.name
  partition_key_path    = "/conversationId"
  partition_key_version = 1
  
  # Indexing policy optimized for message queries and filtering
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
    
    # Composite indexes for efficient querying
    composite_index {
      index {
        path  = "/conversationId"
        order = "ascending"
      }
      index {
        path  = "/timestamp"
        order = "descending"
      }
    }
    
    composite_index {
      index {
        path  = "/channel"
        order = "ascending"
      }
      index {
        path  = "/status"
        order = "ascending"
      }
    }
  }
  
  # Auto-scaling configuration
  autoscale_settings {
    max_throughput = 4000
  }
  
  # TTL for automatic message cleanup (optional)
  default_ttl = -1 # Disabled by default, can be enabled per document
}

# Event Grid Topic for communication event publishing and routing
resource "azurerm_eventgrid_topic" "communication_events" {
  name                = local.eventgrid_topic_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Security configurations
  public_network_access_enabled = true
  local_auth_enabled            = true
  
  # Input schema for event validation
  input_schema         = "EventGridSchema"
  input_mapping_fields = {}
  
  tags = local.common_tags
}

# Application Insights for Function App monitoring and analytics
resource "azurerm_application_insights" "function_insights" {
  count               = var.enable_function_app_insights ? 1 : 0
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  
  # Retention configuration
  retention_in_days = 90
  
  tags = local.common_tags
}

# App Service Plan for Azure Functions (Consumption plan for cost optimization)
resource "azurerm_service_plan" "function_plan" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_plan_sku
  
  tags = local.common_tags
}

# Azure Function App for message processing and workflow orchestration
resource "azurerm_linux_function_app" "message_processor" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Runtime configuration for Node.js
  site_config {
    always_on = var.function_app_always_on
    
    application_stack {
      node_version = "18"
    }
    
    # CORS configuration for web-based administration
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    }
    
    # Security headers
    app_service_logs {
      disk_quota_mb         = 25
      retention_period_days = 7
    }
    
    # IP restrictions for enhanced security
    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        ip_address = ip_restriction.value
        action     = "Allow"
        priority   = 100 + ip_restriction.key
        name       = "AllowedIP${ip_restriction.key}"
      }
    }
  }
  
  # Application settings with connection strings and configuration
  app_settings = {
    # Azure Functions runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    
    # Communication Services configuration
    "COMMUNICATION_SERVICES_CONNECTION_STRING" = azurerm_communication_service.main.primary_connection_string
    
    # Cosmos DB configuration
    "COSMOS_DB_CONNECTION_STRING" = azurerm_cosmosdb_account.main.connection_strings[0]
    "COSMOS_DB_DATABASE_NAME"     = azurerm_cosmosdb_sql_database.communication_db.name
    "COSMOS_DB_CONVERSATIONS_CONTAINER" = azurerm_cosmosdb_sql_container.conversations.name
    "COSMOS_DB_MESSAGES_CONTAINER"      = azurerm_cosmosdb_sql_container.messages.name
    
    # Event Grid configuration
    "EVENTGRID_TOPIC_ENDPOINT" = azurerm_eventgrid_topic.communication_events.endpoint
    "EVENTGRID_ACCESS_KEY"     = azurerm_eventgrid_topic.communication_events.primary_access_key
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_function_app_insights ? azurerm_application_insights.function_insights[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_function_app_insights ? azurerm_application_insights.function_insights[0].connection_string : ""
    
    # Additional configuration
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.function_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE" = "${local.function_app_name}-content"
    
    # Custom application settings for message processing
    "MESSAGE_PROCESSING_BATCH_SIZE" = "100"
    "MESSAGE_RETRY_ATTEMPTS"        = "3"
    "MESSAGE_TIMEOUT_SECONDS"       = "30"
  }
  
  # Enable managed identity for secure Azure service authentication
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # Ensure Function App waits for dependencies
  depends_on = [
    azurerm_service_plan.function_plan,
    azurerm_storage_account.function_storage,
    azurerm_communication_service.main,
    azurerm_cosmosdb_account.main,
    azurerm_eventgrid_topic.communication_events
  ]
}

# Event Grid Subscription to connect communication events to Function App
resource "azurerm_eventgrid_event_subscription" "function_subscription" {
  name  = "communication-events-subscription"
  scope = azurerm_eventgrid_topic.communication_events.id
  
  # Azure Function endpoint configuration
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.message_processor.id}/functions/MessageProcessor"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Event filtering for relevant communication events
  included_event_types = [
    "Microsoft.Communication.MessageReceived",
    "Microsoft.Communication.MessageDelivered",
    "Microsoft.Communication.MessageFailed",
    "Microsoft.Communication.MessageDeliveryReport"
  ]
  
  # Advanced filtering for specific channels or priorities
  advanced_filter {
    string_contains {
      key    = "data.channel"
      values = ["email", "sms", "whatsapp"]
    }
  }
  
  # Retry policy for reliable event delivery
  retry_policy {
    max_delivery_attempts = 5
    event_time_to_live    = 1440 # 24 hours
  }
  
  # Dead letter configuration for failed events
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.function_storage.id
    storage_blob_container_name = "dead-letter-events"
  }
  
  depends_on = [
    azurerm_linux_function_app.message_processor,
    azurerm_eventgrid_topic.communication_events
  ]
}

# Storage Container for dead letter events
resource "azurerm_storage_container" "dead_letter_events" {
  name                  = "dead-letter-events"
  storage_account_name  = azurerm_storage_account.function_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.function_storage]
}

# Role assignment for Function App to access Cosmos DB
resource "azurerm_cosmosdb_sql_role_assignment" "function_cosmos_access" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Cosmos DB Built-in Data Contributor
  principal_id        = azurerm_linux_function_app.message_processor.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.main.id
}

# Role assignment for Function App to publish to Event Grid
resource "azurerm_role_assignment" "function_eventgrid_access" {
  scope                = azurerm_eventgrid_topic.communication_events.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.message_processor.identity[0].principal_id
}
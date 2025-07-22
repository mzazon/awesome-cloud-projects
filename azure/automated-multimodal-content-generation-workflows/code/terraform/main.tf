# Main Terraform configuration for Azure Multi-Modal Content Generation Infrastructure

# Data sources for current configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for resource naming and configuration
locals {
  # Generate unique resource names using random suffix
  resource_suffix = random_string.suffix.result
  
  # Resource names with fallback to generated names
  ai_foundry_hub_name     = var.ai_foundry_hub_name != "" ? var.ai_foundry_hub_name : "aif-hub-${local.resource_suffix}"
  ai_foundry_project_name = var.ai_foundry_project_name != "" ? var.ai_foundry_project_name : "aif-project-${local.resource_suffix}"
  container_registry_name = var.container_registry_name != "" ? var.container_registry_name : "acr${local.resource_suffix}"
  storage_account_name    = var.storage_account_name != "" ? var.storage_account_name : "stcontent${local.resource_suffix}"
  key_vault_name         = var.key_vault_name != "" ? var.key_vault_name : "kv-content-${local.resource_suffix}"
  event_grid_topic_name  = var.event_grid_topic_name != "" ? var.event_grid_topic_name : "egt-content-${local.resource_suffix}"
  function_app_name      = var.function_app_name != "" ? var.function_app_name : "func-content-${local.resource_suffix}"
  
  # Service plan name for Function App
  service_plan_name = "plan-${local.function_app_name}"
  
  # Application Insights name
  app_insights_name = "appi-${var.project_name}-${local.resource_suffix}"
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    "Environment"   = var.environment
    "Project"       = var.project_name
    "DeployedBy"    = "Terraform"
    "ResourceGroup" = var.resource_group_name
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account for content output and AI Foundry storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = !var.enable_private_endpoints
  
  # Advanced threat protection
  enable_https_traffic_only = true
  
  # Network rules if IP ranges are specified
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
      bypass         = ["AzureServices"]
    }
  }
  
  # Blob properties for content storage
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 300
    }
    
    # Enable soft delete for blob recovery
    delete_retention_policy {
      days = 7
    }
    
    # Enable versioning for content management
    versioning_enabled = true
  }
  
  tags = local.common_tags
}

# Storage containers for different content types
resource "azurerm_storage_container" "generated_content" {
  name                  = "generated-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "text_content" {
  name                  = "text-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "image_content" {
  name                  = "image-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "audio_content" {
  name                  = "audio-content"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Key Vault for secure credential storage
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # RBAC authorization instead of access policies
  enable_rbac_authorization = true
  
  # Network access rules
  public_network_access_enabled = !var.enable_private_endpoints
  
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = local.common_tags
}

# Key Vault Administrator role assignment for current user
resource "azurerm_role_assignment" "key_vault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure Container Registry for AI model containers
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = false
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Network access rules for Premium tier
  dynamic "network_rule_set" {
    for_each = var.container_registry_sku == "Premium" && length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      
      dynamic "ip_rule" {
        for_each = var.allowed_ip_ranges
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }
  
  # Enable vulnerability scanning for Premium tier
  dynamic "trust_policy" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      trust_enabled = true
    }
  }
  
  # Enable geo-replication for Premium tier (optional)
  dynamic "georeplications" {
    for_each = var.container_registry_sku == "Premium" && var.environment == "prod" ? ["West US 2"] : []
    content {
      location                = georeplications.value
      zone_redundancy_enabled = true
    }
  }
  
  tags = local.common_tags
}

# Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 90
  
  tags = local.common_tags
}

# Azure AI Foundry Hub (Machine Learning Workspace - Hub type)
resource "azurerm_machine_learning_workspace" "hub" {
  name                          = local.ai_foundry_hub_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  storage_account_id            = azurerm_storage_account.main.id
  key_vault_id                  = azurerm_key_vault.main.id
  container_registry_id         = azurerm_container_registry.main.id
  application_insights_id       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
  kind                          = "Hub"
  public_network_access_enabled = !var.enable_private_endpoints
  
  # System-assigned managed identity for Azure AI services
  identity {
    type = "SystemAssigned"
  }
  
  # High business impact for enhanced security
  high_business_impact = var.environment == "prod"
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_role_assignment.key_vault_admin
  ]
}

# Azure AI Foundry Project (Machine Learning Workspace - Project type)
resource "azurerm_machine_learning_workspace" "project" {
  name                          = local.ai_foundry_project_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  storage_account_id            = azurerm_storage_account.main.id
  key_vault_id                  = azurerm_key_vault.main.id
  container_registry_id         = azurerm_container_registry.main.id
  application_insights_id       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
  kind                          = "Project"
  public_network_access_enabled = !var.enable_private_endpoints
  
  # Link to the hub workspace
  hub_workspace_id = azurerm_machine_learning_workspace.hub.id
  
  # System-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_machine_learning_workspace.hub
  ]
}

# Event Grid Topic for workflow orchestration
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Use Cloud Events schema for modern event-driven architecture
  input_schema = "CloudEventSchemaV1_0"
  
  # Network access rules
  public_network_access_enabled = !var.enable_private_endpoints
  
  dynamic "input_mapping_fields" {
    for_each = []  # Use default mapping for Cloud Events
    content {}
  }
  
  tags = local.common_tags
}

# Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for content generation orchestration
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # System-assigned managed identity for secure access to other services
  identity {
    type = "SystemAssigned"
  }
  
  # Application settings for AI Foundry integration
  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "PYTHON_VERSION"               = "3.9"
    "AI_FOUNDRY_ENDPOINT"          = azurerm_machine_learning_workspace.project.workspace_url
    "STORAGE_CONNECTION_STRING"    = azurerm_storage_account.main.primary_connection_string
    "KEY_VAULT_URL"               = azurerm_key_vault.main.vault_uri
    "EVENTGRID_TOPIC_ENDPOINT"    = azurerm_eventgrid_topic.main.endpoint
    "CONTAINER_REGISTRY_SERVER"   = azurerm_container_registry.main.login_server
    "CONTENT_COORDINATION_CONFIG" = jsonencode(var.content_coordination_config)
  }, var.enable_monitoring ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  # Site configuration
  site_config {
    application_stack {
      python_version = "3.9"
    }
    
    # CORS configuration for web access
    cors {
      allowed_origins = ["*"]
    }
    
    # Enable detailed error messages for debugging
    detailed_error_logging_enabled = true
    http_logging_enabled           = true
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_key_vault.main,
    azurerm_eventgrid_topic.main
  ]
}

# Event Grid subscription for Function App
resource "azurerm_eventgrid_event_subscription" "function_subscription" {
  name  = "content-generation-subscription"
  scope = azurerm_eventgrid_topic.main.id
  
  # Azure Function endpoint
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/ContentGenerationOrchestrator"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Event types filter
  included_event_types = [
    "content.generation.requested",
    "content.generation.test"
  ]
  
  # Retry policy
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440  # 24 hours
  }
  
  # Dead letter configuration using storage account
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "dead-letter-events"
  }
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_storage_container.generated_content
  ]
}

# Dead letter container for failed events
resource "azurerm_storage_container" "dead_letter_events" {
  name                  = "dead-letter-events"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Role assignments for Function App to access other services

# Storage Blob Data Contributor role for Function App
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Key Vault Secrets User role for Function App
resource "azurerm_role_assignment" "function_key_vault_access" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# AcrPull role for Function App to access Container Registry
resource "azurerm_role_assignment" "function_acr_access" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Azure Machine Learning Data Scientist role for Function App
resource "azurerm_role_assignment" "function_ml_access" {
  scope                = azurerm_machine_learning_workspace.project.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Store Event Grid access key in Key Vault
resource "azurerm_key_vault_secret" "eventgrid_key" {
  name         = "eventgrid-key"
  value        = azurerm_eventgrid_topic.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.key_vault_admin
  ]
}

# Store Event Grid endpoint in Key Vault
resource "azurerm_key_vault_secret" "eventgrid_endpoint" {
  name         = "eventgrid-endpoint"
  value        = azurerm_eventgrid_topic.main.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.key_vault_admin
  ]
}

# Store content coordination configuration in Key Vault
resource "azurerm_key_vault_secret" "content_coordination_config" {
  name         = "content-coordination-config"
  value        = base64encode(jsonencode(var.content_coordination_config))
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.key_vault_admin
  ]
}

# Store storage connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.key_vault_admin
  ]
}

# Private endpoints (if enabled)
# Note: Private endpoints require additional networking setup not included in this basic template

# Virtual Network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${var.project_name}-${local.resource_suffix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Subnet for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]
  
  # Disable network policies for private endpoints
  private_endpoint_network_policies_enabled = false
}

# Private DNS zone for Key Vault (if private endpoints enabled)
resource "azurerm_private_dns_zone" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Link private DNS zone to virtual network
resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "key-vault-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = azurerm_virtual_network.main[0].id
  
  tags = local.common_tags
}
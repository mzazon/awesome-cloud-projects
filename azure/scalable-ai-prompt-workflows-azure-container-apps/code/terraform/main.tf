# Main Terraform configuration for Azure AI Studio Prompt Flow and Container Apps
# This file creates the complete infrastructure for serverless AI prompt workflows

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Current Azure client configuration
data "azurerm_client_config" "current" {}

# Local values for resource naming and configuration
locals {
  # Resource naming with fallbacks to generated names
  resource_group_name         = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  ai_hub_name                = var.ai_hub_name != "" ? var.ai_hub_name : "hub-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  ai_project_name            = var.ai_project_name != "" ? var.ai_project_name : "proj-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  openai_account_name        = var.openai_account_name != "" ? var.openai_account_name : "aoai-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  container_registry_name    = var.container_registry_name != "" ? var.container_registry_name : "acr${var.project_name}${var.environment}${random_id.suffix.hex}"
  container_app_env_name     = var.container_app_env_name != "" ? var.container_app_env_name : "env-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  container_app_name         = var.container_app_name != "" ? var.container_app_name : "app-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  application_insights_name  = var.application_insights_name != "" ? var.application_insights_name : "appi-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  storage_account_name       = "st${var.project_name}${var.environment}${random_id.suffix.hex}"
  
  # Merged tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "Terraform"
    CreatedOn   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group
# Creates the main resource group that will contain all infrastructure resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account for AI Hub
# Required for Azure AI Hub to store models, datasets, and experiment artifacts
resource "azurerm_storage_account" "ai_hub" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled      = true
  
  # Enable versioning and soft delete for data protection
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

# Log Analytics Workspace
# Provides centralized logging and monitoring for all Azure resources
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Application Insights
# Provides application performance monitoring and telemetry collection
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  
  tags = local.common_tags
}

# Azure OpenAI Service
# Provides access to OpenAI models for prompt flow operations
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku
  
  # Security and access configuration
  custom_domain_name           = local.openai_account_name
  public_network_access_enabled = var.network_access_tier == "Public" || var.network_access_tier == "Hybrid"
  
  # Identity configuration for secure access
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
}

# Azure OpenAI Model Deployment
# Deploys the specified language model for use in prompt flows
resource "azurerm_cognitive_deployment" "openai_model" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.openai_model_capacity
  }
}

# Azure Container Registry
# Stores containerized prompt flow applications for deployment
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  
  # Enable advanced security features for higher SKUs
  dynamic "georeplications" {
    for_each = var.container_registry_sku == "Premium" ? ["enabled"] : []
    content {
      location = "West US 2"
      tags     = local.common_tags
    }
  }
  
  # Network access rules
  public_network_access_enabled = var.network_access_tier == "Public" || var.network_access_tier == "Hybrid"
  
  # Enable system-assigned managed identity
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
}

# Azure AI Hub (Machine Learning Workspace)
# Provides the foundational workspace for AI development and collaboration
resource "azurerm_machine_learning_workspace" "ai_hub" {
  name                          = local.ai_hub_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  application_insights_id       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
  key_vault_id                  = azurerm_key_vault.main.id
  storage_account_id            = azurerm_storage_account.ai_hub.id
  container_registry_id         = azurerm_container_registry.main.id
  
  # Workspace configuration
  sku_name                      = var.ai_hub_sku
  public_network_access_enabled = var.network_access_tier == "Public" || var.network_access_tier == "Hybrid"
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Key Vault for secure credential storage
# Stores secrets, keys, and certificates for the AI Hub and related services
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Security configurations
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  enabled_for_disk_encryption = true
  
  # Access policy for the current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Create", "Delete", "Get", "List", "Update", "Purge", "Recover"
    ]
    
    secret_permissions = [
      "Set", "Get", "Delete", "List", "Purge", "Recover"
    ]
    
    certificate_permissions = [
      "Create", "Delete", "Get", "List", "Update", "Purge", "Recover"
    ]
  }
  
  tags = local.common_tags
}

# Store OpenAI credentials in Key Vault
resource "azurerm_key_vault_secret" "openai_endpoint" {
  name         = "openai-endpoint"
  value        = azurerm_cognitive_account.openai.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "openai_key" {
  name         = "openai-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Azure AI Project (Child workspace for specific prompt flow projects)
resource "azurerm_machine_learning_workspace" "ai_project" {
  name                          = local.ai_project_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  application_insights_id       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
  key_vault_id                  = azurerm_key_vault.main.id
  storage_account_id            = azurerm_storage_account.ai_hub.id
  container_registry_id         = azurerm_container_registry.main.id
  
  # Project-specific configuration
  sku_name                      = "Basic"
  public_network_access_enabled = var.network_access_tier == "Public" || var.network_access_tier == "Hybrid"
  
  # Link to parent AI Hub (if supported by provider)
  friendly_name = "Prompt Flow Project"
  description   = "AI project for prompt flow development and deployment"
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    WorkspaceType = "Project"
    ParentHub     = local.ai_hub_name
  })
  
  depends_on = [azurerm_machine_learning_workspace.ai_hub]
}

# Container Apps Environment
# Provides the serverless platform for running containerized prompt flows
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_app_env_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
  
  tags = local.common_tags
}

# Container App for Prompt Flow
# Deploys the prompt flow as a serverless container application
resource "azurerm_container_app" "promptflow" {
  name                         = local.container_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  # Template configuration for the container app
  template {
    # Container specification
    container {
      name   = "promptflow-container"
      image  = "${azurerm_container_registry.main.login_server}/promptflow-app:latest"
      cpu    = var.container_app_cpu
      memory = var.container_app_memory
      
      # Environment variables for Azure OpenAI integration
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = azurerm_cognitive_account.openai.endpoint
      }
      
      env {
        name        = "AZURE_OPENAI_API_KEY"
        secret_name = "openai-api-key"
      }
      
      # Application Insights integration (if monitoring is enabled)
      dynamic "env" {
        for_each = var.enable_monitoring ? [1] : []
        content {
          name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
          value = azurerm_application_insights.main[0].connection_string
        }
      }
    }
    
    # Scaling configuration
    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas
  }
  
  # Registry configuration for pulling container images
  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }
  
  # Secret configuration for secure credential storage
  secret {
    name  = "openai-api-key"
    value = azurerm_cognitive_account.openai.primary_access_key
  }
  
  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }
  
  # Ingress configuration for external access
  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = var.container_app_target_port
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  
  # Enable system-assigned managed identity
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
  
  # Ensure proper creation order
  depends_on = [
    azurerm_container_registry.main,
    azurerm_cognitive_account.openai,
    azurerm_container_app_environment.main
  ]
}

# Role Assignment: Container App to Container Registry
# Allows the Container App to pull images from the Container Registry
resource "azurerm_role_assignment" "container_app_acr_pull" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.promptflow.identity[0].principal_id
}

# Role Assignment: Container App to Key Vault
# Allows the Container App to read secrets from Key Vault
resource "azurerm_role_assignment" "container_app_kv_reader" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.promptflow.identity[0].principal_id
}

# Role Assignment: Container App to Cognitive Services
# Allows the Container App to access Azure OpenAI services
resource "azurerm_role_assignment" "container_app_cognitive_user" {
  count = var.enable_managed_identity ? 1 : 0
  
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_container_app.promptflow.identity[0].principal_id
}

# Azure Monitor Alert Rules (if monitoring is enabled)
# Creates alerts for important performance and availability metrics
resource "azurerm_monitor_metric_alert" "container_app_response_time" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "${local.container_app_name}-response-time-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.promptflow.id]
  description         = "Alert when average response time exceeds 1 second"
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "ResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1000
  }
  
  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "container_app_http_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "${local.container_app_name}-http-errors-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.promptflow.id]
  description         = "Alert when HTTP 5xx error rate exceeds 5%"
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
    
    dimension {
      name     = "ResponseCode"
      operator = "Include"
      values   = ["5xx"]
    }
  }
  
  tags = local.common_tags
}
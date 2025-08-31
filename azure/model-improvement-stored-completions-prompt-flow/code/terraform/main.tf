# Model Improvement Pipeline with Stored Completions and Prompt Flow
# This Terraform configuration deploys a complete model improvement pipeline using:
# - Azure OpenAI Service with stored completions capability
# - Azure Machine Learning workspace for Prompt Flow
# - Azure Functions for pipeline automation
# - Azure Storage for data persistence
# - Log Analytics for monitoring and observability

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {
    # Enable automatic deletion of resources when resource group is deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account features
    storage {
      # Allow deletion of storage containers with content
      virtual_network_enabled = true
    }
    
    # Configure cognitive services features
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and configuration
locals {
  # Resource naming convention
  resource_prefix = var.resource_prefix
  random_suffix   = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Recipe      = "model-improvement-stored-completions-prompt-flow"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "ai-model-improvement-pipeline"
  })
}

#------------------------------------------------------------------------------
# RESOURCE GROUP
#------------------------------------------------------------------------------

# Primary resource group for all pipeline resources
resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg-${local.random_suffix}"
  location = var.location
  tags     = local.common_tags
}

#------------------------------------------------------------------------------
# AZURE OPENAI SERVICE
#------------------------------------------------------------------------------

# Azure OpenAI Service for model deployments and stored completions
resource "azurerm_cognitive_account" "openai" {
  name                = "${local.resource_prefix}-openai-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku

  # Enable custom subdomain for API access
  custom_subdomain_name = "${local.resource_prefix}-openai-${local.random_suffix}"

  # Configure network access rules
  network_acls {
    default_action                = var.openai_public_network_access_enabled ? "Allow" : "Deny"
    ip_rules                      = var.openai_allowed_ip_ranges
    virtual_network_subnet_ids    = []
  }

  # Enable local authentication for API key access
  local_auth_enabled = true

  # Disable outbound network access unless required
  outbound_network_access_restricted = var.openai_restrict_outbound_network_access

  tags = local.common_tags
}

# GPT-4o model deployment for conversation capture and analysis
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o-deployment"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = var.gpt4o_model_version
  }

  scale {
    type     = "Standard"
    capacity = var.gpt4o_capacity
  }

  # Version policy for automatic model updates
  version_upgrade_option = var.model_version_upgrade_option

  depends_on = [azurerm_cognitive_account.openai]
}

#------------------------------------------------------------------------------
# AZURE MACHINE LEARNING WORKSPACE
#------------------------------------------------------------------------------

# Application Insights for ML workspace monitoring
resource "azurerm_application_insights" "ml_insights" {
  name                = "${local.resource_prefix}-ai-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Configure data retention
  retention_in_days = var.application_insights_retention_days

  tags = local.common_tags
}

# Key Vault for ML workspace secrets and credentials
resource "azurerm_key_vault" "ml_keyvault" {
  name                = "${local.resource_prefix}-kv-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Configure access policies for ML workspace
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

  # Enable soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = local.common_tags
}

# Container Registry for ML workspace custom environments
resource "azurerm_container_registry" "ml_acr" {
  name                = "${local.resource_prefix}acr${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = false

  # Configure network access
  public_network_access_enabled = var.container_registry_public_access_enabled

  tags = local.common_tags
}

# Azure Machine Learning workspace for Prompt Flow and model management
resource "azurerm_machine_learning_workspace" "main" {
  name                          = "${local.resource_prefix}-mlw-${local.random_suffix}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  application_insights_id       = azurerm_application_insights.ml_insights.id
  key_vault_id                  = azurerm_key_vault.ml_keyvault.id
  storage_account_id            = azurerm_storage_account.ml_storage.id
  container_registry_id         = azurerm_container_registry.ml_acr.id

  # Configure workspace identity
  identity {
    type = "SystemAssigned"
  }

  # Configure public network access
  public_network_access_enabled = var.ml_workspace_public_access_enabled

  # Configure workspace features
  description         = "ML workspace for model improvement pipeline with Prompt Flow"
  friendly_name       = "Model Improvement Pipeline"
  high_business_impact = var.ml_workspace_high_business_impact

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# STORAGE ACCOUNTS
#------------------------------------------------------------------------------

# Storage account for ML workspace (required for ML workspace)
resource "azurerm_storage_account" "ml_storage" {
  name                     = "${local.resource_prefix}mlst${local.random_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  
  # Configure security features
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Configure blob properties
  blob_properties {
    # Enable versioning for data protection
    versioning_enabled = true
    
    # Configure container delete retention
    delete_retention_policy {
      days = var.storage_delete_retention_days
    }
    
    # Configure blob delete retention
    container_delete_retention_policy {
      days = var.storage_delete_retention_days
    }
  }

  tags = local.common_tags
}

# Primary storage account for pipeline data and function app
resource "azurerm_storage_account" "pipeline_storage" {
  name                     = "${local.resource_prefix}pipeline${local.random_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type

  # Configure security features
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Configure blob properties
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = var.storage_delete_retention_days
    }
    
    container_delete_retention_policy {
      days = var.storage_delete_retention_days
    }
  }

  tags = local.common_tags
}

# Storage containers for pipeline data organization
resource "azurerm_storage_container" "conversations" {
  name                  = "conversations"
  storage_account_name  = azurerm_storage_account.pipeline_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "insights" {
  name                  = "insights"
  storage_account_name  = azurerm_storage_account.pipeline_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "flow_artifacts" {
  name                  = "flow-artifacts"
  storage_account_name  = azurerm_storage_account.pipeline_storage.name
  container_access_type = "private"
}

#------------------------------------------------------------------------------
# LOG ANALYTICS AND MONITORING
#------------------------------------------------------------------------------

# Log Analytics workspace for comprehensive monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-law-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  # Configure workspace features
  daily_quota_gb = var.log_analytics_daily_quota_gb

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# SERVICE PLAN AND FUNCTION APP
#------------------------------------------------------------------------------

# Service plan for Function App (consumption plan for cost optimization)
resource "azurerm_service_plan" "function_plan" {
  name                = "${local.resource_prefix}-plan-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku_name

  tags = local.common_tags
}

# Function App for pipeline automation and orchestration
resource "azurerm_linux_function_app" "pipeline_functions" {
  name                = "${local.resource_prefix}-func-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.pipeline_storage.name
  storage_account_access_key = azurerm_storage_account.pipeline_storage.primary_access_key
  service_plan_id           = azurerm_service_plan.function_plan.id

  # Configure Function App settings
  site_config {
    # Configure Python runtime
    application_stack {
      python_version = var.function_app_python_version
    }

    # Configure application insights
    application_insights_key               = azurerm_application_insights.ml_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.ml_insights.connection_string

    # Configure CORS for development
    cors {
      allowed_origins     = var.function_app_allowed_origins
      support_credentials = false
    }

    # Configure runtime settings
    app_scale_limit                = var.function_app_scale_limit
    elastic_instance_minimum       = var.function_app_min_instances
    pre_warmed_instance_count     = var.function_app_prewarmed_instances
  }

  # Configure application settings
  app_settings = {
    # Azure OpenAI configuration
    OPENAI_ENDPOINT                    = azurerm_cognitive_account.openai.endpoint
    OPENAI_API_KEY                    = azurerm_cognitive_account.openai.primary_access_key
    OPENAI_API_VERSION                = var.openai_api_version
    OPENAI_DEPLOYMENT_NAME            = azurerm_cognitive_deployment.gpt4o.name

    # ML workspace configuration
    ML_WORKSPACE_NAME                 = azurerm_machine_learning_workspace.main.name
    ML_WORKSPACE_RESOURCE_GROUP       = azurerm_resource_group.main.name
    ML_WORKSPACE_SUBSCRIPTION_ID      = data.azurerm_client_config.current.subscription_id

    # Storage configuration
    STORAGE_CONNECTION_STRING         = azurerm_storage_account.pipeline_storage.primary_connection_string
    CONVERSATIONS_CONTAINER_NAME      = azurerm_storage_container.conversations.name
    INSIGHTS_CONTAINER_NAME           = azurerm_storage_container.insights.name
    FLOW_ARTIFACTS_CONTAINER_NAME     = azurerm_storage_container.flow_artifacts.name

    # Pipeline configuration
    ANALYSIS_FREQUENCY                = var.pipeline_analysis_frequency
    BATCH_SIZE                        = var.pipeline_batch_size
    QUALITY_THRESHOLD                 = var.pipeline_quality_threshold
    ALERT_QUALITY_THRESHOLD           = var.pipeline_alert_quality_threshold

    # Azure Functions runtime configuration
    FUNCTIONS_WORKER_RUNTIME          = "python"
    FUNCTIONS_EXTENSION_VERSION       = "~4"
    PYTHON_ISOLATE_WORKER_DEPENDENCIES = "1"
    SCM_DO_BUILD_DURING_DEPLOYMENT    = "true"

    # Monitoring and logging
    APPINSIGHTS_INSTRUMENTATIONKEY    = azurerm_application_insights.ml_insights.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ml_insights.connection_string
    
    # Azure Resource Manager configuration
    AZURE_SUBSCRIPTION_ID             = data.azurerm_client_config.current.subscription_id
    AZURE_TENANT_ID                   = data.azurerm_client_config.current.tenant_id
  }

  # Configure managed identity for Azure service access
  identity {
    type = "SystemAssigned"
  }

  # Configure authentication settings
  auth_settings_v2 {
    auth_enabled = false  # Enable if AAD authentication is required
  }

  tags = local.common_tags

  depends_on = [
    azurerm_storage_account.pipeline_storage,
    azurerm_application_insights.ml_insights,
    azurerm_cognitive_account.openai,
    azurerm_machine_learning_workspace.main
  ]
}

#------------------------------------------------------------------------------
# ROLE ASSIGNMENTS AND PERMISSIONS
#------------------------------------------------------------------------------

# Get current client configuration for role assignments
data "azurerm_client_config" "current" {}

# Role assignment: Function App system identity -> Cognitive Services Contributor
resource "azurerm_role_assignment" "function_cognitive_services" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services Contributor"
  principal_id         = azurerm_linux_function_app.pipeline_functions.identity[0].principal_id
}

# Role assignment: Function App system identity -> Storage Blob Data Contributor
resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = azurerm_storage_account.pipeline_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.pipeline_functions.identity[0].principal_id
}

# Role assignment: Function App system identity -> ML workspace Contributor
resource "azurerm_role_assignment" "function_ml_workspace" {
  scope                = azurerm_machine_learning_workspace.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.pipeline_functions.identity[0].principal_id
}

# Role assignment: ML workspace system identity -> Storage Blob Data Contributor
resource "azurerm_role_assignment" "ml_workspace_storage" {
  scope                = azurerm_storage_account.ml_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Role assignment: ML workspace system identity -> Key Vault Contributor
resource "azurerm_role_assignment" "ml_workspace_keyvault" {
  scope                = azurerm_key_vault.ml_keyvault.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

#------------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
#------------------------------------------------------------------------------

# Diagnostic settings for Function App logs
resource "azurerm_monitor_diagnostic_setting" "function_app_diagnostics" {
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.pipeline_functions.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Configure log categories
  enabled_log {
    category = "FunctionAppLogs"
  }

  # Configure metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for OpenAI service
resource "azurerm_monitor_diagnostic_setting" "openai_diagnostics" {
  name                       = "openai-diagnostics"
  target_resource_id         = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Configure log categories
  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "RequestResponse"
  }

  # Configure metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for ML workspace
resource "azurerm_monitor_diagnostic_setting" "ml_workspace_diagnostics" {
  name                       = "ml-workspace-diagnostics"
  target_resource_id         = azurerm_machine_learning_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Configure log categories
  enabled_log {
    category = "AmlComputeClusterEvent"
  }

  enabled_log {
    category = "AmlComputeJobEvent"
  }

  # Configure metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
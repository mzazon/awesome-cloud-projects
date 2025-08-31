# Data sources for current Azure context
data "azurerm_client_config" "current" {}

# Generate random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  base_name       = "${var.application_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment     = var.environment
    Application     = var.application_name
    DeployedBy      = "Terraform"
    DeploymentDate  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # OpenAI custom subdomain for token-based authentication
  openai_custom_subdomain = "openai-${local.base_name}"
  
  # Storage account name (must be globally unique and alphanumeric only)
  storage_name = "st${replace(local.base_name, "-", "")}eval"
  
  # Key Vault name (must be globally unique)
  key_vault_name = "kv-${local.base_name}"
  
  # AI project name
  ai_project_name = "${var.project_name}-${local.resource_suffix}"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Storage Account for ML workspace and dataset storage
resource "azurerm_storage_account" "main" {
  name                     = substr(local.storage_name, 0, min(24, length(local.storage_name)))
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable blob versioning and change feed for ML workspace requirements
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Lifecycle management for cost optimization
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Key Vault for secure credential storage
resource "azurerm_key_vault" "main" {
  name                = substr(local.key_vault_name, 0, min(24, length(local.key_vault_name)))
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Security and compliance settings
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  soft_delete_retention_days = 7
  
  # Network access configuration
  public_network_access_enabled = var.public_network_access_enabled
  
  tags = local.common_tags
}

# Key Vault access policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  # Comprehensive permissions for workspace administration
  key_permissions = [
    "Get", "Create", "Delete", "List", "Update", "Import", 
    "Backup", "Restore", "Recover", "Purge", "GetRotationPolicy"
  ]
  
  secret_permissions = [
    "Get", "Set", "Delete", "List", "Backup", 
    "Restore", "Recover", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "Create", "Delete", "List", "Update", "Import",
    "Backup", "Restore", "Recover", "Purge", "ManageContacts", 
    "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers"
  ]
}

# Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "main" {
  name                = "ai-${local.base_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = var.application_insights_type
  
  # Retention and sampling configuration
  retention_in_days   = 90
  daily_data_cap_in_gb = 1
  
  tags = local.common_tags
}

# Azure OpenAI Service for model hosting
resource "azurerm_cognitive_account" "openai" {
  name                = "openai-${local.base_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Custom subdomain required for OpenAI service
  custom_subdomain_name = local.openai_custom_subdomain
  
  # Security and access configuration
  local_auth_enabled                = var.local_auth_enabled
  public_network_access_enabled     = var.public_network_access_enabled
  outbound_network_access_restricted = false
  
  tags = local.common_tags
}

# Model Deployments for evaluation comparison
resource "azurerm_cognitive_deployment" "models" {
  for_each = var.model_deployments
  
  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = each.value.model_format
    name    = each.value.model_name
    version = each.value.model_version
  }
  
  sku {
    name     = each.value.sku_name
    capacity = each.value.sku_capacity
  }
  
  # Version upgrade configuration
  version_upgrade_option = "OnceNewDefaultVersionAvailable"
  
  # RAI policy configuration (if needed)
  # rai_policy_name = "default"
}

# Azure Machine Learning Workspace (AI Foundry Project)
resource "azurerm_machine_learning_workspace" "main" {
  name                = local.ai_project_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Required associated services
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id           = azurerm_key_vault.main.id
  storage_account_id     = azurerm_storage_account.main.id
  
  # Workspace configuration
  description    = var.ml_workspace_description
  friendly_name  = "AI Model Evaluation Workspace"
  sku_name      = var.ml_workspace_sku
  kind          = "Default"
  
  # Security and compliance settings
  public_network_access_enabled = var.public_network_access_enabled
  high_business_impact          = var.enable_high_business_impact
  v1_legacy_mode_enabled        = false
  
  # Managed identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Dependencies to ensure proper setup order
  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_storage_account.main,
    azurerm_application_insights.main
  ]
  
  tags = local.common_tags
}

# Key Vault access policy for ML workspace managed identity
resource "azurerm_key_vault_access_policy" "ml_workspace" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_machine_learning_workspace.main.identity[0].tenant_id
  object_id    = azurerm_machine_learning_workspace.main.identity[0].principal_id
  
  # Minimal required permissions for ML workspace operation
  key_permissions = [
    "Get", "List", "WrapKey", "UnwrapKey"
  ]
  
  secret_permissions = [
    "Get", "List", "Set"
  ]
  
  depends_on = [azurerm_machine_learning_workspace.main]
}

# Storage account blob contributor role for ML workspace
resource "azurerm_role_assignment" "ml_workspace_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
  
  depends_on = [azurerm_machine_learning_workspace.main]
}

# Application Insights contributor role for ML workspace
resource "azurerm_role_assignment" "ml_workspace_insights" {
  scope                = azurerm_application_insights.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
  
  depends_on = [azurerm_machine_learning_workspace.main]
}

# Container Registry (optional)
resource "azurerm_container_registry" "main" {
  count               = var.container_registry_enabled ? 1 : 0
  name                = "cr${replace(local.base_name, "-", "")}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = true
  
  # Security configuration
  public_network_access_enabled = var.public_network_access_enabled
  
  tags = local.common_tags
}

# Update ML workspace with container registry if enabled
resource "azurerm_machine_learning_workspace" "main_with_acr" {
  count = var.container_registry_enabled ? 1 : 0
  
  name                = local.ai_project_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Required associated services
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id           = azurerm_key_vault.main.id
  storage_account_id     = azurerm_storage_account.main.id
  container_registry_id  = azurerm_container_registry.main[0].id
  
  # Workspace configuration
  description    = var.ml_workspace_description
  friendly_name  = "AI Model Evaluation Workspace"
  sku_name      = var.ml_workspace_sku
  kind          = "Default"
  
  # Security and compliance settings
  public_network_access_enabled = var.public_network_access_enabled
  high_business_impact          = var.enable_high_business_impact
  v1_legacy_mode_enabled        = false
  
  # Managed identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Dependencies to ensure proper setup order
  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_storage_account.main,
    azurerm_application_insights.main,
    azurerm_container_registry.main
  ]
  
  tags = local.common_tags
}

# Storage containers for organizing evaluation data
resource "azurerm_storage_container" "evaluation_datasets" {
  name                  = "evaluation-datasets"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "evaluation_results" {
  name                  = "evaluation-results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "custom_flows" {
  name                  = "custom-flows"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}
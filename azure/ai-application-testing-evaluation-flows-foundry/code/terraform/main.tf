# Azure AI Application Testing with Evaluation Flows and AI Foundry
# This Terraform configuration creates the infrastructure for systematic AI application testing
# using Azure AI Foundry's evaluation flows and Prompt Flow integration

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Resource Group to contain all AI testing resources
resource "azurerm_resource_group" "ai_testing" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure AI Services account (formerly Cognitive Services)
# This provides the foundation for AI Foundry projects and OpenAI model deployments
resource "azurerm_cognitive_account" "ai_services" {
  name                = local.ai_services_name
  location            = azurerm_resource_group.ai_testing.location
  resource_group_name = azurerm_resource_group.ai_testing.name
  kind                = "AIServices"
  sku_name            = var.ai_services_sku
  
  # Enable custom subdomain for OpenAI model deployments
  custom_subdomain_name = local.ai_services_name
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Advanced threat protection and monitoring
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    "Service" = "AI-Services"
    "Purpose" = "Evaluation-Foundation"
  })
  
  lifecycle {
    prevent_destroy = false
  }
}

# OpenAI Model Deployment for AI-assisted evaluation
# GPT-4O-mini provides cost-effective evaluation capabilities for quality assessment
resource "azurerm_cognitive_deployment" "openai_evaluation_model" {
  name                 = local.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.ai_services.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.openai_deployment_capacity
  }
  
  depends_on = [azurerm_cognitive_account.ai_services]
}

# Storage Account for test datasets and evaluation results
# Provides secure storage for test data, ground truth, and evaluation outputs
resource "azurerm_storage_account" "evaluation_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.ai_testing.name
  location                 = azurerm_resource_group.ai_testing.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  
  # Security configurations
  min_tls_version           = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Advanced security features
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled     = false
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules
  public_network_access_enabled = var.enable_public_network_access
  
  tags = merge(local.common_tags, {
    "Service" = "Storage"
    "Purpose" = "Evaluation-Data"
  })
}

# Container for test datasets
resource "azurerm_storage_container" "test_datasets" {
  name                  = "test-datasets"
  storage_account_name  = azurerm_storage_account.evaluation_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.evaluation_storage]
}

# Container for evaluation results and logs
resource "azurerm_storage_container" "evaluation_results" {
  name                  = "evaluation-results"
  storage_account_name  = azurerm_storage_account.evaluation_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.evaluation_storage]
}

# Container for evaluation flows and prompt flows
resource "azurerm_storage_container" "evaluation_flows" {
  name                  = "evaluation-flows"
  storage_account_name  = azurerm_storage_account.evaluation_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.evaluation_storage]
}

# Role assignment for AI Services to access Storage Account
# Enables AI Foundry to read test data and write evaluation results
resource "azurerm_role_assignment" "ai_services_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.evaluation_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_cognitive_account.ai_services.identity[0].principal_id
  
  depends_on = [
    azurerm_cognitive_account.ai_services,
    azurerm_storage_account.evaluation_storage
  ]
}

# Log Analytics Workspace for monitoring evaluation flows
# Provides centralized logging and monitoring for AI application testing
resource "azurerm_log_analytics_workspace" "ai_testing_logs" {
  name                = "log-${local.naming_prefix}-${local.unique_suffix}"
  location            = azurerm_resource_group.ai_testing.location
  resource_group_name = azurerm_resource_group.ai_testing.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = merge(local.common_tags, {
    "Service" = "Monitoring"
    "Purpose" = "Evaluation-Logs"
  })
}

# Application Insights for evaluation flow telemetry
# Monitors evaluation performance, success rates, and quality metrics
resource "azurerm_application_insights" "ai_testing_insights" {
  name                = "appi-${local.naming_prefix}-${local.unique_suffix}"
  location            = azurerm_resource_group.ai_testing.location
  resource_group_name = azurerm_resource_group.ai_testing.name
  workspace_id        = azurerm_log_analytics_workspace.ai_testing_logs.id
  application_type    = "other"
  
  tags = merge(local.common_tags, {
    "Service" = "Monitoring"
    "Purpose" = "Evaluation-Telemetry"
  })
}

# Key Vault for storing AI service keys and connection strings
# Provides secure storage for sensitive configuration values
resource "azurerm_key_vault" "ai_testing_vault" {
  name                       = "kv-${local.naming_prefix}-${local.unique_suffix}"
  location                   = azurerm_resource_group.ai_testing.location
  resource_group_name        = azurerm_resource_group.ai_testing.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  
  # Access policies for the current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge"
    ]
  }
  
  # Access policy for AI Services managed identity
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_cognitive_account.ai_services.identity[0].principal_id
    
    secret_permissions = [
      "Get", "List"
    ]
  }
  
  tags = merge(local.common_tags, {
    "Service" = "Security"
    "Purpose" = "Secret-Management"
  })
  
  depends_on = [azurerm_cognitive_account.ai_services]
}

# Store AI Services primary key in Key Vault
resource "azurerm_key_vault_secret" "ai_services_key" {
  name         = "ai-services-primary-key"
  value        = azurerm_cognitive_account.ai_services.primary_access_key
  key_vault_id = azurerm_key_vault.ai_testing_vault.id
  
  tags = {
    "Service" = "AI-Services"
    "Type"    = "Access-Key"
  }
  
  depends_on = [azurerm_key_vault.ai_testing_vault]
}

# Store Storage Account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.evaluation_storage.primary_connection_string
  key_vault_id = azurerm_key_vault.ai_testing_vault.id
  
  tags = {
    "Service" = "Storage"
    "Type"    = "Connection-String"
  }
  
  depends_on = [azurerm_key_vault.ai_testing_vault]
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Output values for integration with Azure DevOps and other services
# These outputs provide connection details for CI/CD pipeline configuration
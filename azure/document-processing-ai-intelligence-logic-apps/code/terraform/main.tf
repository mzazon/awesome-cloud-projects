# Main Terraform configuration for intelligent document processing with Azure AI Document Intelligence and Logic Apps

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  # Generate resource names with consistent naming convention
  resource_suffix = random_string.suffix.result
  
  # Resource names
  resource_group_name          = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name         = "st${var.project_name}${var.environment}${local.resource_suffix}"
  key_vault_name              = "kv-${var.project_name}-${var.environment}-${local.resource_suffix}"
  document_intelligence_name  = "doc-${var.project_name}-${var.environment}-${local.resource_suffix}"
  logic_app_name              = "logic-${var.project_name}-${var.environment}-${local.resource_suffix}"
  service_bus_namespace_name  = "sb-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_insights_name           = "appi-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Container names
  input_container_name     = "input-documents"
  processed_container_name = "processed-documents"
  
  # Queue names
  processed_docs_queue_name = "processed-docs-queue"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    DeployedBy  = "terraform"
    CreatedOn   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for document storage
resource "azurerm_storage_account" "documents" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  
  # Security configuration
  public_network_access_enabled   = var.enable_public_access
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable blob service properties
  blob_properties {
    versioning_enabled = true
    
    # Configure container delete retention
    delete_retention_policy {
      days = 7
    }
    
    # Configure blob delete retention
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network rules if IP restrictions are specified
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
      bypass         = ["AzureServices"]
    }
  }
  
  tags = local.common_tags
}

# Create storage containers
resource "azurerm_storage_container" "input" {
  name                  = local.input_container_name
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.documents]
}

resource "azurerm_storage_container" "processed" {
  name                  = local.processed_container_name
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.documents]
}

# Create Azure AI Document Intelligence (Form Recognizer) service
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = local.document_intelligence_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku
  
  # Security configuration
  public_network_access_enabled = true
  
  # Configure identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Key Vault for secure credential storage
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = var.key_vault_sku
  
  # Security configuration
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = false
  
  # Enable Azure services to access Key Vault
  enabled_for_template_deployment = true
  
  # Default access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Backup",
      "Restore",
      "Purge"
    ]
  }
  
  tags = local.common_tags
}

# Create Service Bus namespace for reliable messaging
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_namespace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.service_bus_sku
  
  # Configure identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Service Bus queue for processed documents
resource "azurerm_servicebus_queue" "processed_docs" {
  name         = local.processed_docs_queue_name
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Queue configuration
  max_size_in_megabytes                = var.service_bus_queue_max_size
  default_message_ttl                  = var.service_bus_message_ttl
  dead_lettering_on_message_expiration = true
  
  # Enable duplicate detection
  duplicate_detection_history_time_window = "PT10M"
  requires_duplicate_detection            = true
  
  # Enable sessions for ordered processing
  requires_session = false
  
  # Enable partitioning for higher throughput (Standard/Premium only)
  partitioning_enabled = var.service_bus_sku != "Basic"
}

# Create Application Insights for monitoring (optional)
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = var.application_insights_type
  
  tags = local.common_tags
}

# Create Logic App workflow
resource "azurerm_logic_app_workflow" "main" {
  name                = local.logic_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Enable workflow
  enabled = var.logic_app_workflow_enabled
  
  # Configure identity for secure access to Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Grant Logic App access to Key Vault
resource "azurerm_key_vault_access_policy" "logic_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_logic_app_workflow.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
  
  depends_on = [azurerm_logic_app_workflow.main]
}

# Store storage account key in Key Vault
resource "azurerm_key_vault_secret" "storage_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.documents.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Store Document Intelligence key in Key Vault
resource "azurerm_key_vault_secret" "doc_intelligence_key" {
  name         = "doc-intelligence-key"
  value        = azurerm_cognitive_account.document_intelligence.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Store Document Intelligence endpoint in Key Vault
resource "azurerm_key_vault_secret" "doc_intelligence_endpoint" {
  name         = "doc-intelligence-endpoint"
  value        = azurerm_cognitive_account.document_intelligence.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Store Service Bus connection string in Key Vault
resource "azurerm_key_vault_secret" "service_bus_connection" {
  name         = "servicebus-connection"
  value        = azurerm_servicebus_namespace.main.default_primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Create API connections for Logic App

# API Connection for Azure Blob Storage
resource "azurerm_api_connection" "blob_storage" {
  name                = "${local.logic_app_name}-blob-connection"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/azureblob"
  display_name        = "Blob Storage Connection"
  
  parameter_values = {
    accountName = azurerm_storage_account.documents.name
    accessKey   = azurerm_storage_account.documents.primary_access_key
  }
  
  tags = local.common_tags
}

# API Connection for Azure Key Vault
resource "azurerm_api_connection" "key_vault" {
  name                = "${local.logic_app_name}-keyvault-connection"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/keyvault"
  display_name        = "Key Vault Connection"
  
  parameter_values = {
    vaultName = azurerm_key_vault.main.name
  }
  
  tags = local.common_tags
}

# API Connection for Service Bus
resource "azurerm_api_connection" "service_bus" {
  name                = "${local.logic_app_name}-servicebus-connection"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/servicebus"
  display_name        = "Service Bus Connection"
  
  parameter_values = {
    connectionString = azurerm_servicebus_namespace.main.default_primary_connection_string
  }
  
  tags = local.common_tags
}

# Grant Logic App access to storage account
resource "azurerm_role_assignment" "logic_app_storage" {
  scope                = azurerm_storage_account.documents.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.main.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.main]
}

# Grant Logic App access to Document Intelligence
resource "azurerm_role_assignment" "logic_app_cognitive" {
  scope                = azurerm_cognitive_account.document_intelligence.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_logic_app_workflow.main.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.main]
}

# Grant Logic App access to Service Bus
resource "azurerm_role_assignment" "logic_app_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_logic_app_workflow.main.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.main]
}
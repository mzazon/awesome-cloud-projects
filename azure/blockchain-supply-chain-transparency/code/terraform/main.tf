# ==============================================================================
# Blockchain Supply Chain Transparency with Confidential Ledger and Cosmos DB
# ==============================================================================
# This Terraform configuration creates a complete blockchain-powered supply chain
# transparency solution using Azure Confidential Ledger and Cosmos DB.

terraform {
  required_version = ">= 1.0"
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

# Configure the Azure Provider
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.tags, {
    Purpose     = "supply-chain"
    Environment = var.environment
  })
}

# ==============================================================================
# AZURE AD APPLICATION FOR CONFIDENTIAL LEDGER
# ==============================================================================

# Create Azure AD Application for Confidential Ledger access
resource "azuread_application" "ledger_app" {
  display_name = "SupplyChainLedgerApp-${random_string.suffix.result}"
  
  # Optional: Add specific permissions if needed
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

# Create service principal for the application
resource "azuread_service_principal" "ledger_sp" {
  application_id = azuread_application.ledger_app.application_id
}

# ==============================================================================
# MANAGED IDENTITY FOR LOGIC APPS
# ==============================================================================

resource "azurerm_user_assigned_identity" "logic_app_identity" {
  name                = "logic-app-identity-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = var.tags
}

# ==============================================================================
# AZURE CONFIDENTIAL LEDGER
# ==============================================================================

resource "azurerm_confidential_ledger" "main" {
  name                = "scledger${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  ledger_type         = "Public"

  # Configure AAD-based security principals
  azuread_based_service_principal {
    principal_id     = azuread_service_principal.ledger_sp.object_id
    tenant_id        = data.azurerm_client_config.current.tenant_id
    ledger_role_name = "Administrator"
  }

  # Additional managed identity access for Logic Apps
  azuread_based_service_principal {
    principal_id     = azurerm_user_assigned_identity.logic_app_identity.principal_id
    tenant_id        = data.azurerm_client_config.current.tenant_id
    ledger_role_name = "Contributor"
  }

  tags = var.tags
}

# ==============================================================================
# AZURE COSMOS DB
# ==============================================================================

resource "azurerm_cosmosdb_account" "main" {
  name                      = "sccosmos${random_string.suffix.result}"
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  offer_type                = "Standard"
  kind                      = "GlobalDocumentDB"
  enable_multiple_write_locations = true
  enable_analytical_storage = true

  # Configure consistency policy
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  # Configure geo-location
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Add secondary region for global distribution
  geo_location {
    location          = var.secondary_location
    failover_priority = 1
  }

  # Enable automatic failover
  enable_automatic_failover = true

  tags = var.tags
}

# Create Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "supply_chain_db" {
  name                = "SupplyChainDB"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Create container for product tracking
resource "azurerm_cosmosdb_sql_container" "products" {
  name                  = "Products"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.supply_chain_db.name
  partition_key_path    = "/productId"
  partition_key_version = 1
  throughput            = 1000

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  unique_key {
    paths = ["/productId"]
  }
}

# Create container for transaction records
resource "azurerm_cosmosdb_sql_container" "transactions" {
  name                  = "Transactions"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.supply_chain_db.name
  partition_key_path    = "/transactionId"
  partition_key_version = 1
  throughput            = 1000

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  unique_key {
    paths = ["/transactionId"]
  }
}

# ==============================================================================
# AZURE KEY VAULT
# ==============================================================================

resource "azurerm_key_vault" "main" {
  name                        = "sckv${random_string.suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  enable_rbac_authorization   = true

  tags = var.tags
}

# Grant Key Vault access to Logic Apps managed identity
resource "azurerm_role_assignment" "logic_app_keyvault_access" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

# Store Cosmos DB connection string in Key Vault
resource "azurerm_key_vault_secret" "cosmos_connection_string" {
  name         = "CosmosDBConnectionString"
  value        = "AccountEndpoint=${azurerm_cosmosdb_account.main.endpoint};AccountKey=${azurerm_cosmosdb_account.main.primary_key};"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.logic_app_keyvault_access]
}

# Store Ledger endpoint in Key Vault
resource "azurerm_key_vault_secret" "ledger_endpoint" {
  name         = "LedgerEndpoint"
  value        = azurerm_confidential_ledger.main.ledger_endpoint
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.logic_app_keyvault_access]
}

# ==============================================================================
# EVENT GRID
# ==============================================================================

resource "azurerm_eventgrid_topic" "main" {
  name                = "sc-events-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = "EventGridSchema"

  # Configure public network access
  public_network_access_enabled = true

  tags = var.tags
}

# ==============================================================================
# STORAGE ACCOUNT
# ==============================================================================

resource "azurerm_storage_account" "main" {
  name                     = "scstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable versioning and change feed for audit trail
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
  }

  tags = var.tags
}

# Create container for supply chain documents
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create container for quality certificates
resource "azurerm_storage_container" "certificates" {
  name                  = "certificates"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Configure lifecycle management for cost optimization
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "archiveOldDocuments"
    enabled = true

    filters {
      prefix_match = ["documents/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_archive_after_days_since_modification_greater_than = 90
      }
    }
  }
}

# ==============================================================================
# LOGIC APP WORKFLOW
# ==============================================================================

resource "azurerm_logic_app_workflow" "main" {
  name                = "sc-logic-app-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Assign managed identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app_identity.id]
  }

  # Workflow definition for supply chain orchestration
  workflow_schema      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version     = "1.0.0.0"
  workflow_parameters  = jsonencode({
    "$connections" = {
      "defaultValue" = {}
      "type"         = "Object"
    }
    "ledgerEndpoint" = {
      "defaultValue" = azurerm_confidential_ledger.main.ledger_endpoint
      "type"         = "String"
    }
    "eventGridEndpoint" = {
      "defaultValue" = azurerm_eventgrid_topic.main.endpoint
      "type"         = "String"
    }
    "eventGridKey" = {
      "defaultValue" = azurerm_eventgrid_topic.main.primary_access_key
      "type"         = "String"
    }
  })

  tags = var.tags
}

# ==============================================================================
# API MANAGEMENT
# ==============================================================================

resource "azurerm_api_management" "main" {
  name                = "sc-apim-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "SupplyChainDemo"
  publisher_email     = var.publisher_email
  sku_name            = "Consumption_0"

  tags = var.tags
}

# Create API for supply chain operations
resource "azurerm_api_management_api" "supply_chain" {
  name                = "supply-chain-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Supply Chain API"
  path                = "supply-chain"
  protocols           = ["https"]

  import {
    content_format = "swagger-json"
    content_value = jsonencode({
      swagger = "2.0"
      info = {
        title   = "Supply Chain API"
        version = "1.0"
      }
      paths = {
        "/transactions" = {
          post = {
            operationId = "submit-transaction"
            summary     = "Submit Transaction"
            parameters = [
              {
                name     = "body"
                in       = "body"
                required = true
                schema = {
                  type = "object"
                  properties = {
                    transactionId = { type = "string" }
                    productId     = { type = "string" }
                    action        = { type = "string" }
                    timestamp     = { type = "string" }
                    location      = { type = "string" }
                    participant   = { type = "string" }
                    metadata      = { type = "object" }
                  }
                }
              }
            ]
            responses = {
              "200" = {
                description = "Success"
              }
            }
          }
        }
      }
    })
  }
}

# Configure API policy for rate limiting and security
resource "azurerm_api_management_api_policy" "supply_chain_policy" {
  api_name            = azurerm_api_management_api.supply_chain.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<XML
<policies>
  <inbound>
    <rate-limit-by-key calls="100" renewal-period="60" 
        counter-key="@(context.Subscription?.Key ?? "anonymous")" />
    <validate-jwt header-name="Authorization" 
        failed-validation-httpcode="401" 
        failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>api://supply-chain-api</audience>
      </audiences>
    </validate-jwt>
  </inbound>
  <backend>
    <forward-request />
  </backend>
  <outbound />
  <on-error />
</policies>
XML
}

# ==============================================================================
# MONITORING AND ANALYTICS
# ==============================================================================

# Create Log Analytics workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "supply-chain-logs-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Create Application Insights
resource "azurerm_application_insights" "main" {
  name                = "supply-chain-insights-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = var.tags
}

# Configure diagnostic settings for Cosmos DB
resource "azurerm_monitor_diagnostic_setting" "cosmos_diagnostics" {
  name                       = "cosmos-diagnostics"
  target_resource_id         = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "QueryRuntimeStatistics"
  }

  enabled_log {
    category = "PartitionKeyStatistics"
  }

  metric {
    category = "Requests"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Configure diagnostic settings for Event Grid
resource "azurerm_monitor_diagnostic_setting" "eventgrid_diagnostics" {
  name                       = "eventgrid-diagnostics"
  target_resource_id         = azurerm_eventgrid_topic.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "DeliveryFailures"
  }

  enabled_log {
    category = "PublishFailures"
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Create alert rule for high transaction volume
resource "azurerm_monitor_metric_alert" "high_transaction_volume" {
  name                = "high-transaction-volume"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cosmosdb_account.main.id]
  description         = "Alert when transaction volume exceeds normal threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "TotalRequests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 1000
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}

# Create action group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "supply-chain-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "sc-alerts"

  # Configure email notifications
  email_receiver {
    name          = "admin"
    email_address = var.alert_email
  }

  tags = var.tags
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "confidential_ledger_endpoint" {
  description = "The endpoint URL of the Confidential Ledger"
  value       = azurerm_confidential_ledger.main.ledger_endpoint
}

output "cosmos_db_endpoint" {
  description = "The endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_primary_key" {
  description = "The primary master key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "event_grid_endpoint" {
  description = "The endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_primary_key" {
  description = "The primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "logic_app_workflow_name" {
  description = "The name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.name
}

output "api_management_gateway_url" {
  description = "The gateway URL of the API Management instance"
  value       = azurerm_api_management.main.gateway_url
}

output "application_insights_app_id" {
  description = "The application ID of Application Insights"
  value       = azurerm_application_insights.main.app_id
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "The workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "managed_identity_principal_id" {
  description = "The principal ID of the managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

output "azure_ad_application_id" {
  description = "The application ID of the Azure AD application"
  value       = azuread_application.ledger_app.application_id
}
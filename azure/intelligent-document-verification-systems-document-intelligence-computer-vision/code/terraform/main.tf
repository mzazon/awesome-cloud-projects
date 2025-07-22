# Main Terraform configuration for Azure Document Verification System
# This configuration deploys a complete intelligent document verification system
# using Azure Document Intelligence, Computer Vision, and supporting services

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for resource naming and configuration
locals {
  # Resource naming
  resource_suffix = random_string.suffix.result
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "${var.project_name}-${var.environment}-rg"
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    Environment    = var.environment
    Project        = var.project_name
    CreatedBy      = "Terraform"
    ResourceSuffix = local.resource_suffix
  })
  
  # Resource names
  storage_account_name       = "${var.project_name}sa${local.resource_suffix}"
  doc_intelligence_name      = "${var.project_name}-docintel-${local.resource_suffix}"
  computer_vision_name       = "${var.project_name}-vision-${local.resource_suffix}"
  function_app_name          = "${var.project_name}-func-${local.resource_suffix}"
  cosmos_db_name             = "${var.project_name}-cosmos-${local.resource_suffix}"
  logic_app_name             = "${var.project_name}-logic-${local.resource_suffix}"
  api_management_name        = "${var.project_name}-apim-${local.resource_suffix}"
  app_insights_name          = "${var.project_name}-appinsights-${local.resource_suffix}"
  log_analytics_name         = "${var.project_name}-logs-${local.resource_suffix}"
  key_vault_name             = "${var.project_name}-kv-${local.resource_suffix}"
  
  # Storage container names
  storage_containers = [
    "incoming-docs",
    "processed-docs",
    "function-deployments"
  ]
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Key Vault for secure storage of secrets
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # Enable access for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Create", "Delete", "Get", "List", "Update", "Recover", "Backup", "Restore"
    ]
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
  }
  
  tags = local.common_tags
}

# Storage Account for document processing
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable blob versioning for audit trail
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

# Storage containers for document processing
resource "azurerm_storage_container" "containers" {
  count                 = length(local.storage_containers)
  name                  = local.storage_containers[count.index]
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Azure Document Intelligence (Form Recognizer) Service
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = local.doc_intelligence_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku
  
  # Identity for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  # Network access rules
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = local.common_tags
}

# Azure Computer Vision Service
resource "azurerm_cognitive_account" "computer_vision" {
  name                = local.computer_vision_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ComputerVision"
  sku_name            = var.computer_vision_sku
  
  # Identity for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  # Network access rules
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = local.common_tags
}

# Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "${var.project_name}-plan-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  tags                = local.common_tags
}

# Function App for document processing logic
resource "azurerm_linux_function_app" "main" {
  name                       = local.function_app_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id            = azurerm_service_plan.function_app.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Identity for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  # Site configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration for web access
    cors {
      allowed_origins = ["*"]
    }
    
    # Application Insights integration
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.main[0].connection_string
      }
    }
    
    # Enable logging
    application_logs {
      file_system_level = "Information"
    }
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "DOCUMENT_INTELLIGENCE_ENDPOINT" = azurerm_cognitive_account.document_intelligence.endpoint
    "DOCUMENT_INTELLIGENCE_KEY"     = azurerm_cognitive_account.document_intelligence.primary_access_key
    "COMPUTER_VISION_ENDPOINT"     = azurerm_cognitive_account.computer_vision.endpoint
    "COMPUTER_VISION_KEY"          = azurerm_cognitive_account.computer_vision.primary_access_key
    "STORAGE_CONNECTION_STRING"    = azurerm_storage_account.main.primary_connection_string
    "COSMOS_CONNECTION_STRING"     = azurerm_cosmosdb_account.main.connection_strings[0]
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD" = "true"
  }
  
  tags = local.common_tags
}

# Cosmos DB Account for audit trail storage
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_db_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = var.cosmos_db_offer_type
  kind                = var.cosmos_db_kind
  
  # Enable automatic failover
  enable_automatic_failover = true
  
  # Consistency policy
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_level
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }
  
  # Geographic locations
  geo_location {
    location          = var.location
    failover_priority = 0
  }
  
  # Backup policy
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
  }
  
  tags = local.common_tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "DocumentVerification"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB SQL Container for verification results
resource "azurerm_cosmosdb_sql_container" "verification_results" {
  name                = "VerificationResults"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/documentId"
  throughput          = var.cosmos_db_throughput
  
  # Indexing policy for efficient queries
  indexing_policy {
    indexing_mode = "Consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Unique key policy for document ID
  unique_key {
    paths = ["/documentId"]
  }
}

# Logic App for workflow orchestration
resource "azurerm_logic_app_workflow" "main" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Identity for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  # Workflow definition with blob trigger and AI service integration
  workflow_definition = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#"
    contentVersion = "1.0.0.0"
    
    parameters = {
      "$connections" = {
        defaultValue = {}
        type = "Object"
      }
    }
    
    triggers = {
      "When_a_blob_is_added_or_modified" = {
        type = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "get"
          path = "/triggers/batch/onupdatedfile"
          queries = {
            folderId = "L2luY29taW5nLWRvY3M="  # Base64 encoded "/incoming-docs"
          }
        }
      }
    }
    
    actions = {
      "Process_Document" = {
        type = "Http"
        inputs = {
          method = "POST"
          uri = "https://${local.function_app_name}.azurewebsites.net/api/DocumentVerificationFunction"
          headers = {
            "Content-Type" = "application/json"
          }
          body = {
            document_url = "@triggerBody()?['Path']"
          }
        }
      }
      
      "Store_Result" = {
        runAfter = {
          "Process_Document" = ["Succeeded"]
        }
        type = "Http"
        inputs = {
          method = "POST"
          uri = "https://${local.cosmos_db_name}.documents.azure.com:443/dbs/DocumentVerification/colls/VerificationResults/docs"
          headers = {
            "Content-Type" = "application/json"
            "Authorization" = "@concat('type=master&ver=1.0&sig=', variables('cosmosAuthToken'))"
          }
          body = "@outputs('Process_Document')['body']"
        }
      }
    }
    
    outputs = {}
  })
  
  tags = local.common_tags
}

# API Management Service for secure API access
resource "azurerm_api_management" "main" {
  count               = var.api_management_enabled ? 1 : 0
  name                = local.api_management_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.api_management_publisher_name
  publisher_email     = var.api_management_publisher_email
  sku_name            = var.api_management_sku
  
  # Identity for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  # Security policy
  security {
    enable_backend_ssl30  = false
    enable_backend_tls10  = false
    enable_backend_tls11  = false
    enable_frontend_ssl30 = false
    enable_frontend_tls10 = false
    enable_frontend_tls11 = false
    
    tls_ecdhe_ecdsa_with_aes128_cbc_sha_ciphers_enabled = false
    tls_ecdhe_ecdsa_with_aes256_cbc_sha_ciphers_enabled = false
    tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled   = false
    tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled   = false
    tls_rsa_with_aes128_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes128_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes256_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_3des_ede_cbc_sha_ciphers_enabled       = false
  }
  
  tags = local.common_tags
}

# API Management API for document verification
resource "azurerm_api_management_api" "document_verification" {
  count               = var.api_management_enabled ? 1 : 0
  name                = "document-verification-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main[0].name
  revision            = "1"
  display_name        = "Document Verification API"
  path                = "verification"
  protocols           = ["https"]
  service_url         = "https://${local.function_app_name}.azurewebsites.net/api"
  
  description = "API for intelligent document verification using Azure AI services"
  
  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.0"
      info = {
        title = "Document Verification API"
        version = "1.0"
        description = "API for intelligent document verification"
      }
      paths = {
        "/DocumentVerificationFunction" = {
          post = {
            summary = "Verify document authenticity and extract data"
            requestBody = {
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      document_url = {
                        type = "string"
                        description = "URL of the document to verify"
                      }
                    }
                    required = ["document_url"]
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "Verification completed successfully"
                content = {
                  "application/json" = {
                    schema = {
                      type = "object"
                      properties = {
                        document_id = { type = "string" }
                        verification_status = { type = "string" }
                        confidence_score = { type = "number" }
                        extracted_data = { type = "object" }
                        fraud_indicators = { type = "array" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })
  }
}

# Role assignments for managed identities
resource "azurerm_role_assignment" "function_app_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_cognitive" {
  scope                = azurerm_cognitive_account.document_intelligence.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_vision" {
  scope                = azurerm_cognitive_account.computer_vision.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Store secrets in Key Vault
resource "azurerm_key_vault_secret" "document_intelligence_key" {
  name         = "document-intelligence-key"
  value        = azurerm_cognitive_account.document_intelligence.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "computer_vision_key" {
  name         = "computer-vision-key"
  value        = azurerm_cognitive_account.computer_vision.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "cosmos_connection_string" {
  name         = "cosmos-connection-string"
  value        = azurerm_cosmosdb_account.main.connection_strings[0]
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault.main]
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source for current Azure subscription
data "azurerm_subscription" "current" {}
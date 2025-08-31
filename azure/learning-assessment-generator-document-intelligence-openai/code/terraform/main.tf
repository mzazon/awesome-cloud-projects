# Learning Assessment Generator with Document Intelligence and OpenAI
# This Terraform configuration deploys a complete serverless solution for
# generating educational assessments from documents using Azure AI services.

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Generate a random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and tagging
locals {
  # Resource naming with random suffix for uniqueness
  base_name = "${var.project_name}-${var.environment}"
  suffix    = var.resource_group_name == "" ? random_string.suffix.result : ""
  
  # Resource names with length validation for Azure limits
  resource_group_name       = var.resource_group_name != "" ? var.resource_group_name : "rg-${local.base_name}-${local.suffix}"
  storage_account_name      = lower(replace("sa${var.project_name}${local.suffix}", "-", ""))
  cosmosdb_account_name     = "cosmos-${local.base_name}-${local.suffix}"
  function_app_name         = "func-${local.base_name}-${local.suffix}"
  app_service_plan_name     = "asp-${local.base_name}-${local.suffix}"
  document_intelligence_name = "doc-intel-${local.base_name}-${local.suffix}"
  openai_account_name       = "openai-${local.base_name}-${local.suffix}"
  app_insights_name         = "appi-${local.base_name}-${local.suffix}"
  
  # Standardized tags for all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    CreatedBy     = "terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    ResourceGroup = local.resource_group_name
  })
}

# Resource Group
# Creates the container for all Azure resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account
# Provides blob storage for document upload and processing
resource "azurerm_storage_account" "main" {
  name                     = substr(local.storage_account_name, 0, 24) # Azure limit
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  https_traffic_only_enabled = var.enable_https_only
  min_tls_version           = var.minimum_tls_version
  
  # Enable blob versioning and change feed for document tracking
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Automatically delete old versions after 30 days
    delete_retention_policy {
      days = 30
    }
    
    # Container delete retention for accidental deletion protection
    container_delete_retention_policy {
      days = 30
    }
  }
  
  # Network access rules
  network_rules {
    default_action = var.enable_public_network_access ? "Allow" : "Deny"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Storage Container for Documents
# Dedicated container for educational document uploads
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  # Container metadata for organization
  metadata = {
    purpose = "educational-document-storage"
    version = "1.0"
  }
}

# Azure AI Document Intelligence Service
# Provides advanced OCR and document analysis capabilities
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = local.document_intelligence_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku
  
  # Custom subdomain for API access
  custom_subdomain_name = lower(local.document_intelligence_name)
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Network ACLs for security
  network_acls {
    default_action = var.enable_public_network_access ? "Allow" : "Deny"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Azure OpenAI Service
# Provides GPT models for intelligent assessment generation
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku
  
  # Custom subdomain for API access
  custom_subdomain_name = lower(local.openai_account_name)
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Network ACLs for security
  network_acls {
    default_action = var.enable_public_network_access ? "Allow" : "Deny"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Azure OpenAI Model Deployment
# Deploys the GPT model for content generation
resource "azurerm_cognitive_deployment" "gpt_model" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  scale {
    type     = "Standard"
    capacity = var.openai_deployment_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Azure Cosmos DB Account
# Provides NoSQL storage for documents and generated assessments
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmosdb_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Enable serverless mode for cost optimization
  capabilities {
    name = "EnableServerless"
  }
  
  # Consistency policy for data reliability
  consistency_policy {
    consistency_level       = var.cosmosdb_consistency_level
    max_interval_in_seconds = var.cosmosdb_max_interval_in_seconds
    max_staleness_prefix    = var.cosmosdb_max_staleness_prefix
  }
  
  # Geographic replication configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Security configurations
  public_network_access_enabled = var.enable_public_network_access
  
  # Network access rules
  dynamic "ip_range_filter" {
    for_each = var.enable_public_network_access ? var.allowed_ip_ranges : []
    content {
      ip_range_filter = ip_range_filter.value
    }
  }
  
  tags = local.common_tags
}

# Cosmos DB SQL Database
# Database container for assessment application data
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "AssessmentDB"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB Container for Documents
# Stores extracted document content and metadata
resource "azurerm_cosmosdb_sql_container" "documents" {
  name                = "Documents"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/documentId"
  
  # Automatic indexing for efficient queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    # Optimize indexing for common query patterns
    excluded_path {
      path = "/extractedText/*"
    }
  }
  
  # TTL for automatic cleanup of old documents (90 days)
  default_ttl = 7776000
}

# Cosmos DB Container for Assessments
# Stores generated assessment questions and metadata
resource "azurerm_cosmosdb_sql_container" "assessments" {
  name                = "Assessments"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/documentId"
  
  # Automatic indexing for efficient queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    # Composite indexes for common query patterns
    composite_index {
      index {
        path  = "/documentId"
        order = "ascending"
      }
      index {
        path  = "/generatedDate"
        order = "descending"
      }
    }
  }
  
  # TTL for automatic cleanup of old assessments (180 days)
  default_ttl = 15552000
}

# Application Insights
# Provides monitoring and diagnostics for the Function App
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = var.application_insights_type
  
  # Retention period for telemetry data
  retention_in_days = 90
  
  tags = local.common_tags
}

# App Service Plan
# Provides the compute infrastructure for Azure Functions
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_os_type
  sku_name            = "Y1"  # Consumption plan for serverless
  
  tags = local.common_tags
}

# Azure Function App
# Serverless compute for document processing and assessment generation
resource "azurerm_linux_function_app" "main" {
  count                      = var.function_app_os_type == "Linux" ? 1 : 0
  name                       = local.function_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Security headers and configurations
    http2_enabled                     = true
    minimum_tls_version              = var.minimum_tls_version
    scm_minimum_tls_version          = var.minimum_tls_version
    ftps_state                       = "Disabled"
    remote_debugging_enabled         = false
    
    # CORS configuration for web access
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    
    # Application insights integration
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        application_insights_connection_string = azurerm_application_insights.main[0].connection_string
      }
    }
    
    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        application_insights_key = azurerm_application_insights.main[0].instrumentation_key
      }
    }
  }
  
  # Application settings for service integration
  app_settings = {
    # Azure Functions runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # Document Intelligence configuration
    "DOC_INTEL_ENDPOINT" = azurerm_cognitive_account.document_intelligence.endpoint
    "DOC_INTEL_KEY"      = azurerm_cognitive_account.document_intelligence.primary_access_key
    
    # Azure OpenAI configuration
    "OPENAI_ENDPOINT" = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"      = azurerm_cognitive_account.openai.primary_access_key
    
    # Cosmos DB configuration
    "COSMOS_ENDPOINT"  = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_KEY"       = azurerm_cosmosdb_account.main.primary_key
    "COSMOS_DATABASE"  = azurerm_cosmosdb_sql_database.main.name
    
    # Storage account connection string
    "AzureWebJobsStorage" = azurerm_storage_account.main.primary_connection_string
    
    # Application Insights (conditional)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
  }
  
  # Enable HTTPS only
  https_only = var.enable_https_only
  
  # Enable managed identity for secure service-to-service authentication
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_cognitive_account.document_intelligence,
    azurerm_cognitive_account.openai,
    azurerm_cosmosdb_account.main,
    azurerm_storage_account.main
  ]
}

# Windows Function App (alternative implementation)
resource "azurerm_windows_function_app" "main" {
  count                      = var.function_app_os_type == "Windows" ? 1 : 0
  name                       = local.function_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Security configurations
    http2_enabled                = true
    minimum_tls_version         = var.minimum_tls_version
    scm_minimum_tls_version     = var.minimum_tls_version
    ftps_state                  = "Disabled"
    remote_debugging_enabled    = false
    
    # CORS configuration
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
  }
  
  # Application settings (same as Linux version)
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "DOC_INTEL_ENDPOINT"          = azurerm_cognitive_account.document_intelligence.endpoint
    "DOC_INTEL_KEY"               = azurerm_cognitive_account.document_intelligence.primary_access_key
    "OPENAI_ENDPOINT"             = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"                  = azurerm_cognitive_account.openai.primary_access_key
    "COSMOS_ENDPOINT"             = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_KEY"                  = azurerm_cosmosdb_account.main.primary_key
    "COSMOS_DATABASE"             = azurerm_cosmosdb_sql_database.main.name
    "AzureWebJobsStorage"         = azurerm_storage_account.main.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
  }
  
  https_only = var.enable_https_only
  
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
}

# Role Assignment for Managed Identity (if enabled)
# Provides the Function App with necessary permissions to access other Azure services
resource "azurerm_role_assignment" "function_app_storage" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_cognitive_services" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "function_app_cosmos" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
}
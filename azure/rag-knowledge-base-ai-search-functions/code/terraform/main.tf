# Azure RAG Knowledge Base with AI Search and Functions
# This Terraform configuration deploys a complete RAG solution using:
# - Azure Blob Storage for document storage
# - Azure AI Search for intelligent indexing and retrieval
# - Azure OpenAI Service for language model capabilities
# - Azure Functions for serverless API layer

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.84"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
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
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group for all RAG Knowledge Base resources
resource "azurerm_resource_group" "rag_kb" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-rag-kb-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.common_tags, {
    purpose     = "recipe"
    environment = "demo"
    recipe      = "rag-knowledge-base-ai-search-functions"
  })
}

# Storage Account for document storage with Data Lake capabilities
resource "azurerm_storage_account" "rag_kb" {
  name                     = var.storage_account_name != "" ? var.storage_account_name : "ragkbstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rag_kb.name
  location                 = azurerm_resource_group.rag_kb.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable hierarchical namespace for Data Lake capabilities
  is_hns_enabled = true

  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.common_tags
}

# Storage Container for documents
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.rag_kb.name
  container_access_type = "private"
}

# Application Insights for Function App monitoring
resource "azurerm_application_insights" "rag_kb" {
  name                = "appi-rag-kb-${random_string.suffix.result}"
  location            = azurerm_resource_group.rag_kb.location
  resource_group_name = azurerm_resource_group.rag_kb.name
  application_type    = "web"

  tags = var.common_tags
}

# Azure AI Search Service
resource "azurerm_search_service" "rag_kb" {
  name                = var.search_service_name != "" ? var.search_service_name : "rag-kb-search-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rag_kb.name
  location            = azurerm_resource_group.rag_kb.location
  sku                 = var.search_service_sku
  replica_count       = var.search_replica_count
  partition_count     = var.search_partition_count

  # Enable semantic search for enhanced RAG capabilities
  semantic_search_sku = var.search_service_sku == "basic" ? "standard" : null

  # Public network access can be restricted in production
  public_network_access_enabled = var.search_public_access

  tags = var.common_tags
}

# Azure OpenAI Service for language model capabilities
resource "azurerm_cognitive_account" "openai" {
  name                = var.openai_service_name != "" ? var.openai_service_name : "rag-kb-openai-${random_string.suffix.result}"
  location            = var.openai_location
  resource_group_name = azurerm_resource_group.rag_kb.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku

  # Custom subdomain is required for OpenAI
  custom_subdomain_name = var.openai_service_name != "" ? var.openai_service_name : "rag-kb-openai-${random_string.suffix.result}"

  # Disable public network access for production
  public_network_access_enabled = var.openai_public_access

  tags = var.common_tags
}

# Deploy GPT-4o model for chat completions
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = var.openai_deployment_name
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

# Service Plan for Function App (Consumption plan)
resource "azurerm_service_plan" "rag_kb" {
  name                = "asp-rag-kb-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rag_kb.name
  location            = azurerm_resource_group.rag_kb.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = var.common_tags
}

# Function App for RAG API
resource "azurerm_linux_function_app" "rag_kb" {
  name                = var.function_app_name != "" ? var.function_app_name : "rag-kb-func-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rag_kb.name
  location            = azurerm_resource_group.rag_kb.location

  storage_account_name       = azurerm_storage_account.rag_kb.name
  storage_account_access_key = azurerm_storage_account.rag_kb.primary_access_key
  service_plan_id            = azurerm_service_plan.rag_kb.id

  # Function runtime configuration
  site_config {
    application_stack {
      python_version = var.function_python_version
    }

    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.rag_kb.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.rag_kb.connection_string

    # CORS configuration for web clients
    cors {
      allowed_origins = var.function_cors_origins
    }
  }

  # Application settings for AI services integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "SEARCH_ENDPOINT"                = "https://${azurerm_search_service.rag_kb.name}.search.windows.net"
    "SEARCH_API_KEY"                 = azurerm_search_service.rag_kb.primary_key
    "OPENAI_ENDPOINT"                = azurerm_cognitive_account.openai.endpoint
    "OPENAI_API_KEY"                 = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_DEPLOYMENT"              = azurerm_cognitive_deployment.gpt4o.name
    "SEARCH_INDEX_NAME"              = var.search_index_name
    "SEARCH_DATASOURCE_NAME"         = var.search_datasource_name
    "SEARCH_INDEXER_NAME"            = var.search_indexer_name
    "STORAGE_CONNECTION_STRING"      = azurerm_storage_account.rag_kb.primary_connection_string
    "DOCUMENTS_CONTAINER_NAME"       = azurerm_storage_container.documents.name
  }

  # Enable managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
}

# Role assignment to allow Function App to access Search Service
resource "azurerm_role_assignment" "function_search_reader" {
  scope                = azurerm_search_service.rag_kb.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_linux_function_app.rag_kb.identity[0].principal_id
}

# Role assignment to allow Function App to access OpenAI Service
resource "azurerm_role_assignment" "function_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.rag_kb.identity[0].principal_id
}

# Role assignment to allow Function App to access Storage Account
resource "azurerm_role_assignment" "function_storage_reader" {
  scope                = azurerm_storage_account.rag_kb.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.rag_kb.identity[0].principal_id
}

# Local file for search index definition (used by null_resource)
resource "local_file" "search_index_definition" {
  filename = "${path.module}/search-index.json"
  content = jsonencode({
    name = var.search_index_name
    fields = [
      {
        name         = "id"
        type         = "Edm.String"
        searchable   = false
        filterable   = true
        retrievable  = true
        sortable     = false
        facetable    = false
        key          = true
      },
      {
        name         = "content"
        type         = "Edm.String"
        searchable   = true
        filterable   = false
        retrievable  = true
        sortable     = false
        facetable    = false
      },
      {
        name         = "title"
        type         = "Edm.String"
        searchable   = true
        filterable   = true
        retrievable  = true
        sortable     = true
        facetable    = false
      },
      {
        name         = "metadata_storage_path"
        type         = "Edm.String"
        searchable   = false
        filterable   = true
        retrievable  = true
        sortable     = false
        facetable    = false
      }
    ]
    semantic = {
      configurations = [
        {
          name = "semantic-config"
          prioritizedFields = {
            titleField = {
              fieldName = "title"
            }
            prioritizedContentFields = [
              {
                fieldName = "content"
              }
            ]
          }
        }
      ]
    }
  })
}

# Local file for data source definition
resource "local_file" "search_datasource_definition" {
  filename = "${path.module}/data-source.json"
  content = jsonencode({
    name = var.search_datasource_name
    type = "azureblob"
    credentials = {
      connectionString = azurerm_storage_account.rag_kb.primary_connection_string
    }
    container = {
      name = azurerm_storage_container.documents.name
    }
  })
}

# Local file for indexer definition
resource "local_file" "search_indexer_definition" {
  filename = "${path.module}/indexer.json"
  content = jsonencode({
    name            = var.search_indexer_name
    dataSourceName  = var.search_datasource_name
    targetIndexName = var.search_index_name
    fieldMappings = [
      {
        sourceFieldName = "metadata_storage_path"
        targetFieldName = "id"
        mappingFunction = {
          name = "base64Encode"
        }
      },
      {
        sourceFieldName = "content"
        targetFieldName = "content"
      },
      {
        sourceFieldName = "metadata_storage_name"
        targetFieldName = "title"
      },
      {
        sourceFieldName = "metadata_storage_path"
        targetFieldName = "metadata_storage_path"
      }
    ]
    schedule = {
      interval = var.search_indexer_schedule
    }
  })
}

# Create AI Search Index using REST API
resource "null_resource" "create_search_index" {
  depends_on = [
    azurerm_search_service.rag_kb,
    local_file.search_index_definition
  ]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X POST "https://${azurerm_search_service.rag_kb.name}.search.windows.net/indexes?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "api-key: ${azurerm_search_service.rag_kb.primary_key}" \
        -d @${local_file.search_index_definition.filename}
    EOT
  }

  # Trigger recreation if index definition changes
  triggers = {
    index_definition = local_file.search_index_definition.content
  }
}

# Create AI Search Data Source using REST API
resource "null_resource" "create_search_datasource" {
  depends_on = [
    azurerm_search_service.rag_kb,
    azurerm_storage_account.rag_kb,
    azurerm_storage_container.documents,
    local_file.search_datasource_definition
  ]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X POST "https://${azurerm_search_service.rag_kb.name}.search.windows.net/datasources?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "api-key: ${azurerm_search_service.rag_kb.primary_key}" \
        -d @${local_file.search_datasource_definition.filename}
    EOT
  }

  # Trigger recreation if datasource definition changes
  triggers = {
    datasource_definition = local_file.search_datasource_definition.content
  }
}

# Create AI Search Indexer using REST API
resource "null_resource" "create_search_indexer" {
  depends_on = [
    null_resource.create_search_index,
    null_resource.create_search_datasource,
    local_file.search_indexer_definition
  ]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X POST "https://${azurerm_search_service.rag_kb.name}.search.windows.net/indexers?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "api-key: ${azurerm_search_service.rag_kb.primary_key}" \
        -d @${local_file.search_indexer_definition.filename}
    EOT
  }

  # Trigger recreation if indexer definition changes
  triggers = {
    indexer_definition = local_file.search_indexer_definition.content
  }
}

# Sample documents for testing (optional)
resource "azurerm_storage_blob" "sample_doc1" {
  count                  = var.create_sample_documents ? 1 : 0
  name                   = "azure-functions-overview.txt"
  storage_account_name   = azurerm_storage_account.rag_kb.name
  storage_container_name = azurerm_storage_container.documents.name
  type                   = "Block"
  source_content         = var.sample_document_1_content
}

resource "azurerm_storage_blob" "sample_doc2" {
  count                  = var.create_sample_documents ? 1 : 0
  name                   = "azure-search-overview.txt"
  storage_account_name   = azurerm_storage_account.rag_kb.name
  storage_container_name = azurerm_storage_container.documents.name
  type                   = "Block"
  source_content         = var.sample_document_2_content
}
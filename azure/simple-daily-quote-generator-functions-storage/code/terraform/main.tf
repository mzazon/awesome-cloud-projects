#
# Main Terraform configuration for Azure simple daily quote generator
# This creates an Azure Function App with HTTP trigger and Table Storage for quotes
#

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and configuration
locals {
  # Generate unique resource names with project name and random suffix
  resource_suffix       = random_string.suffix.result
  storage_account_name  = replace("st${var.project_name}${local.resource_suffix}", "-", "")
  function_app_name     = "${var.project_name}-func-${local.resource_suffix}"
  app_service_plan_name = "${var.project_name}-plan-${local.resource_suffix}"
  
  # Ensure storage account name meets Azure requirements (3-24 chars, alphanumeric only)
  storage_account_name_clean = substr(replace(local.storage_account_name, "/[^a-z0-9]/", ""), 0, 24)
  
  # Merge default and user-provided tags
  common_tags = merge(var.tags, {
    ManagedBy        = "Terraform"
    ResourceSuffix   = local.resource_suffix
    CreationDate     = timestamp()
  })
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for Function App and Table Storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name_clean
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties for optimization
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create Table Storage for quotes
resource "azurerm_storage_table" "quotes" {
  name                 = "quotes"
  storage_account_name = azurerm_storage_account.main.name
  
  depends_on = [azurerm_storage_account.main]
}

# Create Table Storage entities for sample quotes
resource "azurerm_storage_table_entity" "sample_quotes" {
  count = length(var.sample_quotes)
  
  storage_account_name = azurerm_storage_account.main.name
  table_name          = azurerm_storage_table.quotes.name
  
  partition_key = "inspiration"
  row_key      = format("%03d", count.index + 1)
  
  entity = {
    quote    = var.sample_quotes[count.index].quote
    author   = var.sample_quotes[count.index].author
    category = var.sample_quotes[count.index].category
  }
  
  depends_on = [azurerm_storage_table.quotes]
}

# Create App Service Plan for Function App (Consumption plan)
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Consumption plan for serverless execution
  os_type  = "Linux"
  sku_name = "Y1"  # Consumption plan SKU
  
  tags = local.common_tags
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-ai-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# Create Linux Function App
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage account connection for Function App runtime
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function App configuration
  functions_extension_version = "~4"
  
  # Application settings for function configuration
  app_settings = {
    # Runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"               = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"           = var.function_app_runtime == "node" ? "~${var.function_app_runtime_version}" : null
    
    # Application Insights integration
    "APPINSIGHTS_INSTRUMENTATIONKEY"         = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"  = azurerm_application_insights.main.connection_string
    
    # Storage connection string for table access
    "AzureWebJobsStorage"                    = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                   = "${var.project_name}-content-${local.resource_suffix}"
    
    # Function-specific settings
    "FUNCTIONS_EXTENSION_VERSION"            = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
    
    # Enable logging
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"       = "true"
    "WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED" = "1"
  }
  
  # Site configuration for the Function App
  site_config {
    # Runtime stack configuration
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
    }
    
    # CORS configuration
    dynamic "cors" {
      for_each = var.enable_cors ? [1] : []
      content {
        allowed_origins     = var.cors_allowed_origins
        support_credentials = false
      }
    }
    
    # Security and performance settings
    always_on                         = false  # Not available in consumption plan
    use_32_bit_worker                = false
    http2_enabled                    = true
    ftps_state                       = "Disabled"
    remote_debugging_enabled         = false
    
    # Application insights configuration
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Authentication settings (anonymous access for public API)
  auth_settings_v2 {
    auth_enabled = false
  }
  
  # Connection strings for external services
  connection_string {
    name  = "DefaultConnection"
    type  = "Custom"
    value = azurerm_storage_account.main.primary_connection_string
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_service_plan.main,
    azurerm_storage_account.main,
    azurerm_application_insights.main
  ]
}

# Create local function code archive
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function-app.zip"
  
  source {
    content = jsonencode({
      "bindings" = [
        {
          "authLevel" = "anonymous"
          "type"      = "httpTrigger"
          "direction" = "in"
          "name"      = "req"
          "methods"   = ["get"]
        },
        {
          "type"      = "http"
          "direction" = "out"
          "name"      = "res"
        }
      ]
    })
    filename = "quote-function/function.json"
  }
  
  source {
    content = jsonencode({
      "name"         = "quote-generator-function"
      "version"      = "1.0.0"
      "description"  = "Azure Function for serving random inspirational quotes"
      "main"         = "index.js"
      "dependencies" = {
        "@azure/data-tables" = "^13.3.1"
      }
    })
    filename = "quote-function/package.json"
  }
  
  source {
    content = <<-EOT
const { TableClient } = require("@azure/data-tables");

module.exports = async function (context, req) {
    try {
        // Initialize Table Storage client
        const connectionString = process.env.AzureWebJobsStorage;
        const tableClient = TableClient.fromConnectionString(connectionString, "quotes");
        
        // Query all quotes from the inspiration partition
        const quotes = [];
        const entities = tableClient.listEntities({
            filter: "PartitionKey eq 'inspiration'"
        });
        
        for await (const entity of entities) {
            quotes.push({
                id: entity.rowKey,
                quote: entity.quote,
                author: entity.author,
                category: entity.category
            });
        }
        
        if (quotes.length === 0) {
            context.res = {
                status: 404,
                headers: { "Content-Type": "application/json" },
                body: { error: "No quotes found" }
            };
            return;
        }
        
        // Select random quote
        const randomIndex = Math.floor(Math.random() * quotes.length);
        const selectedQuote = quotes[randomIndex];
        
        // Return successful response
        context.res = {
            status: 200,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=300"
            },
            body: {
                success: true,
                data: selectedQuote,
                timestamp: new Date().toISOString(),
                total_quotes: quotes.length
            }
        };
        
    } catch (error) {
        context.log.error('Error retrieving quote:', error);
        context.res = {
            status: 500,
            headers: { "Content-Type": "application/json" },
            body: { 
                success: false,
                error: "Internal server error",
                message: "Unable to retrieve quote at this time"
            }
        };
    }
};
EOT
    filename = "quote-function/index.js"
  }
  
  source {
    content = jsonencode({
      "version"      = "2.0"
      "functionApp"  = false
    })
    filename = "host.json"
  }
}

# Deploy function code to Function App
resource "azurerm_function_app_function" "quote_function" {
  name            = "quote-function"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "Javascript"
  
  config_json = jsonencode({
    "bindings" = [
      {
        "authLevel" = "anonymous"
        "type"      = "httpTrigger"
        "direction" = "in"
        "name"      = "req"
        "methods"   = ["get"]
      },
      {
        "type"      = "http"
        "direction" = "out"
        "name"      = "res"
      }
    ]
  })
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_storage_table_entity.sample_quotes
  ]
}
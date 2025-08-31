# Main Terraform configuration for Azure URL Shortener
# This file creates the complete infrastructure for a serverless URL shortener
# using Azure Functions and Table Storage

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = lower(random_id.suffix.hex)
  
  # Computed resource names following Azure naming conventions
  resource_group_name    = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name   = "${var.project_name}${local.resource_suffix}"
  function_app_name      = "${var.project_name}-${var.environment}-${local.resource_suffix}"
  service_plan_name      = "plan-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_insights_name      = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Merge default tags with user-provided tags
  common_tags = merge(var.tags, {
    ManagedBy     = "Terraform"
    CreatedDate   = timestamp()
    ResourceGroup = local.resource_group_name
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group - Container for all related resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account - Provides both Function App storage and Table Storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = var.minimum_tls_version
  enable_https_traffic_only       = var.enable_https_only
  allow_nested_items_to_be_public = false
  
  # Advanced threat protection for production environments
  infrastructure_encryption_enabled = true
  
  # Blob properties for optimized performance
  blob_properties {
    # Enable versioning for blob storage (useful for Function App packages)
    versioning_enabled = true
    
    # Configure delete retention policy
    delete_retention_policy {
      days = 7
    }
    
    # Configure container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage Table - NoSQL storage for URL mappings
resource "azurerm_storage_table" "url_mappings" {
  name                 = var.table_name
  storage_account_name = azurerm_storage_account.main.name
  
  depends_on = [azurerm_storage_account.main]
}

# Application Insights - Monitoring and telemetry for Functions
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Configure sampling and retention
  retention_in_days   = 90
  daily_data_cap_in_gb = 1
  
  tags = local.common_tags
}

# Service Plan - Defines the hosting plan for Azure Functions
resource "azurerm_service_plan" "main" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Linux Function App - Serverless compute for URL shortener functions
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Security configurations
  https_only                    = var.enable_https_only
  public_network_access_enabled = true
  
  # Site configuration for Node.js runtime
  site_config {
    # Application stack configuration
    application_stack {
      node_version = var.function_runtime_version
    }
    
    # CORS configuration for web clients
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }
    
    # Security headers
    http2_enabled                = true
    minimum_tls_version         = var.minimum_tls_version
    scm_minimum_tls_version     = var.minimum_tls_version
    ftps_state                  = "Disabled"
    
    # Function app specific settings
    use_32_bit_worker        = false
    always_on                = false  # Not available for consumption plan
    application_insights_key = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  }
  
  # Application settings - Environment variables for functions
  app_settings = merge({
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"         = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"     = var.function_runtime_version
    "FUNCTIONS_EXTENSION_VERSION"      = "~4"
    
    # Storage connection string for Table Storage access
    "STORAGE_CONNECTION_STRING"        = azurerm_storage_account.main.primary_connection_string
    
    # Table name for URL mappings
    "TABLE_NAME"                       = var.table_name
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"   = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Function timeout configuration
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"   = "false"
    
    # Additional performance settings
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"  = "true"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"             = "${local.function_app_name}-content"
    
  }, var.tags)
  
  # Function app identity for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # Ensure storage account and table are created before function app
  depends_on = [
    azurerm_storage_account.main,
    azurerm_storage_table.url_mappings,
    azurerm_service_plan.main
  ]
}

# Function App Function - Shorten URL endpoint
resource "azurerm_function_app_function" "shorten" {
  name            = "shorten"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "Javascript"
  
  # Function configuration as JSON
  config_json = jsonencode({
    "bindings" = [
      {
        "authLevel" = "anonymous"
        "type"      = "httpTrigger"
        "direction" = "in"
        "name"      = "req"
        "methods"   = ["post"]
        "route"     = "shorten"
      },
      {
        "type"      = "http"
        "direction" = "out"
        "name"      = "res"
      }
    ]
  })
  
  # Function code - URL shortening logic
  file {
    name    = "index.js"
    content = <<-EOT
const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');

app.http('shorten', {
    methods: ['POST'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        try {
            const body = await request.json();
            const originalUrl = body.url;

            if (!originalUrl) {
                return {
                    status: 400,
                    jsonBody: { error: 'URL is required' }
                };
            }

            // Validate URL format
            try {
                new URL(originalUrl);
            } catch {
                return {
                    status: 400,
                    jsonBody: { error: 'Invalid URL format' }
                };
            }

            // Generate short code (6 characters)
            const shortCode = Math.random().toString(36).substring(2, 8);

            // Initialize Table client
            const tableClient = TableClient.fromConnectionString(
                process.env.STORAGE_CONNECTION_STRING,
                process.env.TABLE_NAME || 'urlmappings'
            );

            // Store URL mapping
            const entity = {
                partitionKey: shortCode,
                rowKey: shortCode,
                originalUrl: originalUrl,
                createdAt: new Date().toISOString(),
                clickCount: 0
            };

            await tableClient.createEntity(entity);

            return {
                status: 201,
                jsonBody: {
                    shortCode: shortCode,
                    shortUrl: `https://$${request.headers.get('host')}/api/$${shortCode}`,
                    originalUrl: originalUrl
                }
            };
        } catch (error) {
            context.error('Error in shorten function:', error);
            return {
                status: 500,
                jsonBody: { error: 'Internal server error' }
            };
        }
    }
});
EOT
  }
  
  # Package.json for dependencies
  file {
    name    = "package.json"
    content = jsonencode({
      "name"         = "url-shortener-functions"
      "version"      = "1.0.0"
      "main"         = "index.js"
      "dependencies" = {
        "@azure/functions"    = "^4.5.1"
        "@azure/data-tables" = "^13.3.1"
      }
    })
  }
}

# Function App Function - Redirect endpoint
resource "azurerm_function_app_function" "redirect" {
  name            = "redirect"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "Javascript"
  
  # Function configuration as JSON
  config_json = jsonencode({
    "bindings" = [
      {
        "authLevel" = "anonymous"
        "type"      = "httpTrigger"
        "direction" = "in"
        "name"      = "req"
        "methods"   = ["get"]
        "route"     = "{shortCode}"
      },
      {
        "type"      = "http"
        "direction" = "out"
        "name"      = "res"
      }
    ]
  })
  
  # Function code - URL redirection logic
  file {
    name    = "index.js"
    content = <<-EOT
const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');

app.http('redirect', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: '{shortCode}',
    handler: async (request, context) => {
        try {
            const shortCode = request.params.shortCode;

            if (!shortCode) {
                return {
                    status: 400,
                    jsonBody: { error: 'Short code is required' }
                };
            }

            // Initialize Table client
            const tableClient = TableClient.fromConnectionString(
                process.env.STORAGE_CONNECTION_STRING,
                process.env.TABLE_NAME || 'urlmappings'
            );

            // Lookup URL mapping
            const entity = await tableClient.getEntity(shortCode, shortCode);

            if (!entity) {
                return {
                    status: 404,
                    jsonBody: { error: 'Short URL not found' }
                };
            }

            // Increment click count (optional analytics)
            entity.clickCount = (entity.clickCount || 0) + 1;
            await tableClient.updateEntity(entity, 'Replace');

            // Redirect to original URL
            return {
                status: 302,
                headers: {
                    'Location': entity.originalUrl,
                    'Cache-Control': 'no-cache'
                }
            };
        } catch (error) {
            if (error.statusCode === 404) {
                return {
                    status: 404,
                    jsonBody: { error: 'Short URL not found' }
                };
            }
            
            context.error('Error in redirect function:', error);
            return {
                status: 500,
                jsonBody: { error: 'Internal server error' }
            };
        }
    }
});
EOT
  }
  
  # Package.json for dependencies
  file {
    name    = "package.json"
    content = jsonencode({
      "name"         = "url-redirect-function"
      "version"      = "1.0.0"
      "main"         = "index.js"  
      "dependencies" = {
        "@azure/functions"    = "^4.5.1"
        "@azure/data-tables" = "^13.3.1"
      }
    })
  }
  
  depends_on = [azurerm_function_app_function.shorten]
}

# Role Assignment - Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_storage_account.main
  ]
}
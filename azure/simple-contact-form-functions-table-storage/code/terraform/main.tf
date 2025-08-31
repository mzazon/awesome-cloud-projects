# Simple Contact Form with Azure Functions and Table Storage
# This configuration creates a serverless contact form processing system
# that automatically scales based on demand and provides cost-effective storage

# Generate a random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent resource naming and configuration
locals {
  # Generate unique names with consistent naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result

  # Resource names with proper length limits and uniqueness
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "rg-${local.resource_prefix}-${local.resource_suffix}"
  storage_account_name = "st${replace(var.project_name, "-", "")}${var.environment}${local.resource_suffix}"
  function_app_name    = "func-${local.resource_prefix}-${local.resource_suffix}"
  service_plan_name    = "asp-${local.resource_prefix}-${local.resource_suffix}"
  app_insights_name    = "appi-${local.resource_prefix}-${local.resource_suffix}"

  # Merge common tags with environment-specific tags
  tags = merge(var.common_tags, {
    Environment = var.environment
    Location    = var.location
    CreatedBy   = "Terraform"
    Recipe      = "simple-contact-form-functions-table-storage"
  })
}

# Create the resource group for all related resources
resource "azurerm_resource_group" "contact_form" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# Create storage account for Function App backend and Table Storage
# This single storage account serves dual purposes to reduce costs
resource "azurerm_storage_account" "contact_form" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.contact_form.name
  location                 = azurerm_resource_group.contact_form.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  # Security and performance settings
  https_traffic_only_enabled   = true
  min_tls_version             = var.minimum_tls_version
  allow_nested_items_to_be_public = false
  shared_access_key_enabled   = true

  # Enable blob storage features
  blob_properties {
    # Disable anonymous blob access for security
    anonymous_access_level = "None"
    
    # Configure CORS for blob storage if needed
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST", "PUT"]
      allowed_origins    = var.cors_allowed_origins
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }

  # Network access rules for security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = local.tags
}

# Create Azure Storage Table for contact form submissions
# Table Storage provides low-cost NoSQL storage perfect for contact data
resource "azurerm_storage_table" "contacts" {
  name                 = var.contact_table_name
  storage_account_name = azurerm_storage_account.contact_form.name

  depends_on = [azurerm_storage_account.contact_form]
}

# Create Application Insights for Function App monitoring and logging
# This provides comprehensive observability for the serverless application
resource "azurerm_application_insights" "contact_form" {
  count = var.enable_application_insights ? 1 : 0

  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.contact_form.name
  location            = azurerm_resource_group.contact_form.location
  application_type    = "web"
  
  # Data retention for cost optimization
  retention_in_days = 90
  
  # Disable local authentication for enhanced security
  disable_ip_masking = false

  tags = local.tags
}

# Create App Service Plan for the Function App
# Consumption plan provides automatic scaling and pay-per-execution pricing
resource "azurerm_service_plan" "contact_form" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.contact_form.name
  location            = azurerm_resource_group.contact_form.location
  os_type             = "Windows"
  sku_name            = var.function_app_sku

  tags = local.tags
}

# Create the Azure Function App for processing contact form submissions
# This serverless compute service handles HTTP requests and stores data
resource "azurerm_windows_function_app" "contact_form" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.contact_form.name
  location            = azurerm_resource_group.contact_form.location
  service_plan_id     = azurerm_service_plan.contact_form.id

  # Storage configuration using the same storage account
  storage_account_name       = azurerm_storage_account.contact_form.name
  storage_account_access_key = azurerm_storage_account.contact_form.primary_access_key

  # Function runtime configuration
  functions_extension_version = var.functions_extension_version
  
  # Security settings
  https_only                    = var.https_only
  public_network_access_enabled = var.enable_public_network_access
  
  # Enable built-in logging for basic diagnostics
  builtin_logging_enabled = true
  
  # Daily quota for consumption plan cost control
  daily_memory_time_quota = var.daily_memory_time_quota_gb

  # Application settings for Function App configuration
  app_settings = merge({
    # Functions runtime settings
    "FUNCTIONS_WORKER_RUNTIME" = var.function_runtime
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    
    # Storage connection string for table binding
    "AzureWebJobsStorage" = azurerm_storage_account.contact_form.primary_connection_string
    
    # Table Storage configuration
    "CONTACT_TABLE_NAME" = azurerm_storage_table.contacts.name
    
    # CORS configuration
    "WEBSITE_CORS_ALLOWED_ORIGINS" = join(",", var.cors_allowed_origins)
    "WEBSITE_CORS_SUPPORT_CREDENTIALS" = "false"
    
    # Security headers
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS" = "7"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
  }, var.enable_application_insights ? {
    # Application Insights configuration (conditional)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.contact_form[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.contact_form[0].connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
  } : {})

  # Site configuration for the Function App
  site_config {
    # Application stack configuration
    application_stack {
      node_version = var.function_runtime_version
    }

    # Always On should be false for consumption plan
    always_on = var.function_app_sku == "Y1" ? false : true

    # Security settings
    minimum_tls_version = var.minimum_tls_version
    ftps_state         = "FtpsOnly"
    
    # HTTP settings
    http2_enabled = true
    
    # CORS configuration for web integration
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    # Application Insights integration
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.contact_form[0].connection_string
      }
    }

    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.contact_form[0].instrumentation_key
      }
    }
  }

  # System-assigned managed identity for secure access to Azure resources
  identity {
    type = "SystemAssigned"
  }

  tags = local.tags

  depends_on = [
    azurerm_storage_account.contact_form,
    azurerm_storage_table.contacts,
    azurerm_service_plan.contact_form
  ]
}

# Data source to get the current Azure client configuration
data "azurerm_client_config" "current" {}

# Create a sample function for contact form processing
# This demonstrates the function structure and configuration
resource "azurerm_function_app_function" "contact_processor" {
  name            = "ContactProcessor"
  function_app_id = azurerm_windows_function_app.contact_form.id
  language        = "Javascript"

  # Function configuration with HTTP trigger and Table Storage binding
  config_json = jsonencode({
    "bindings" = [
      {
        "authLevel" = "function"
        "type"      = "httpTrigger"
        "direction" = "in"
        "name"      = "req"
        "methods"   = ["post", "options"]
        "route"     = "contact"
      },
      {
        "type"      = "http"
        "direction" = "out"
        "name"      = "res"
      },
      {
        "type"       = "table"
        "direction"  = "out"
        "name"       = "tableBinding"
        "tableName"  = var.contact_table_name
        "connection" = "AzureWebJobsStorage"
      }
    ]
  })

  # Function implementation with validation and CORS support
  file {
    name = "index.js"
    content = <<-EOT
module.exports = async function (context, req) {
    // Enable CORS for web requests
    context.res.headers = {
        'Access-Control-Allow-Origin': '${join(",", var.cors_allowed_origins)}',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    };

    // Handle preflight OPTIONS request
    if (req.method === 'OPTIONS') {
        context.res = {
            status: 200,
            headers: context.res.headers
        };
        return;
    }

    try {
        // Validate required fields
        const { name, email, message } = req.body || {};
        
        if (!name || !email || !message) {
            context.res = {
                status: 400,
                headers: context.res.headers,
                body: { 
                    error: "Missing required fields: name, email, message" 
                }
            };
            return;
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            context.res = {
                status: 400,
                headers: context.res.headers,
                body: { error: "Invalid email format" }
            };
            return;
        }

        // Create contact entity for Table Storage
        const contactEntity = {
            PartitionKey: "contacts",
            RowKey: `$${Date.now()}-$${Math.random().toString(36).substr(2, 9)}`,
            Name: name.substring(0, 100), // Limit field length
            Email: email.substring(0, 100),
            Message: message.substring(0, 1000),
            SubmittedAt: new Date().toISOString(),
            IPAddress: req.headers['x-forwarded-for'] || 'unknown'
        };

        // Store in Table Storage using output binding
        context.bindings.tableBinding = contactEntity;

        // Return success response
        context.res = {
            status: 200,
            headers: context.res.headers,
            body: { 
                message: "Contact form submitted successfully",
                id: contactEntity.RowKey
            }
        };

    } catch (error) {
        context.log.error('Function error:', error);
        context.res = {
            status: 500,
            headers: context.res.headers,
            body: { error: "Internal server error" }
        };
    }
};
EOT
  }

  depends_on = [azurerm_windows_function_app.contact_form]
}
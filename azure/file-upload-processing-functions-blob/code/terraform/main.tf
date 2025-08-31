# Azure File Upload Processing Infrastructure with Functions and Blob Storage
# This Terraform configuration deploys a complete serverless file processing solution

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Resource Group - Container for all Azure resources
resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Data source for existing resource group (if not creating new one)
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.existing_resource_group_name
}

# Local values for resource group reference
locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.main[0].name : data.azurerm_resource_group.existing[0].name
  location            = var.create_resource_group ? azurerm_resource_group.main[0].location : data.azurerm_resource_group.existing[0].location
}

# Storage Account - Provides blob storage for file uploads and function app storage
resource "azurerm_storage_account" "main" {
  name                      = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name       = local.resource_group_name
  location                  = local.location
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_replication_type
  account_kind              = "StorageV2"
  access_tier               = var.storage_access_tier
  enable_https_traffic_only = var.enable_https_traffic_only
  min_tls_version          = var.min_tls_version

  # Enable blob storage encryption with Microsoft-managed keys
  encryption {
    services {
      blob {
        enabled = var.enable_storage_encryption
      }
      file {
        enabled = var.enable_storage_encryption
      }
    }
    type = "Microsoft.Storage"
  }

  # Network access rules for security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = merge(var.tags, {
    Name = "st${var.project_name}${random_string.suffix.result}"
    Type = "Storage"
  })
}

# Blob Container - Container for uploaded files that trigger processing
resource "azurerm_storage_container" "uploads" {
  name                  = var.blob_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.blob_container_access_type

  depends_on = [azurerm_storage_account.main]
}

# Application Insights - Monitoring and telemetry for function execution
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = local.resource_group_name
  location            = local.location
  application_type    = var.application_insights_type
  retention_in_days   = var.retention_in_days

  tags = merge(var.tags, {
    Name = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
    Type = "Monitoring"
  })
}

# Service Plan - Consumption plan for serverless Azure Functions
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = local.resource_group_name
  location            = local.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan for serverless execution

  tags = merge(var.tags, {
    Name = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
    Type = "ServicePlan"
  })
}

# Function App - Serverless compute for file processing logic
resource "azurerm_linux_function_app" "main" {
  name                        = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name         = local.resource_group_name
  location                    = local.location
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  functions_extension_version = var.function_app_version

  # Application settings for function configuration
  app_settings = merge({
    # Storage connection string for blob trigger
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME" = var.function_app_runtime
    
    # Application Insights instrumentation key (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    
    # Application Insights connection string (if enabled)
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Container name for blob trigger path
    "BLOB_CONTAINER_NAME" = var.blob_container_name
    
    # Enable detailed error messages
    "AzureWebJobsDisableHomepage" = "true"
    
    # Enable dashboard for function monitoring
    "AzureWebJobsDashboard" = azurerm_storage_account.main.primary_connection_string
  }, var.tags)

  # Site configuration for function runtime
  site_config {
    # Enable always on for consistent performance (not applicable for consumption plan)
    always_on = false
    
    # Application stack configuration
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
      
      dynamic "python_version" {
        for_each = var.function_app_runtime == "python" ? [1] : []
        content {
          version = var.function_app_runtime_version
        }
      }
      
      dynamic "dotnet_version" {
        for_each = var.function_app_runtime == "dotnet" ? [1] : []
        content {
          version = var.function_app_runtime_version
        }
      }
      
      dynamic "java_version" {
        for_each = var.function_app_runtime == "java" ? [1] : []
        content {
          version = var.function_app_runtime_version
        }
      }
      
      dynamic "powershell_core_version" {
        for_each = var.function_app_runtime == "powershell" ? [1] : []
        content {
          version = var.function_app_runtime_version
        }
      }
    }

    # Enable CORS for web-based testing
    cors {
      allowed_origins = ["*"]
    }

    # Application logging configuration
    application_logs {
      file_system_level = "Information"
    }

    # HTTP logging configuration
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  # Function app identity for secure access to Azure resources
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Name = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
    Type = "Function"
  })

  depends_on = [
    azurerm_service_plan.main,
    azurerm_storage_account.main,
    azurerm_application_insights.main
  ]
}

# Storage Blob Data Contributor role assignment for Function App managed identity
resource "azurerm_role_assignment" "function_storage_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# Storage Account Contributor role assignment for Function App to manage containers
resource "azurerm_role_assignment" "function_storage_account_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# Local file for function code deployment preparation
resource "local_file" "function_json" {
  filename = "${path.module}/function-code/function.json"
  content = jsonencode({
    bindings = [
      {
        name       = "myBlob"
        type       = "blobTrigger"
        direction  = "in"
        path       = "${var.blob_container_name}/{name}"
        connection = "STORAGE_CONNECTION_STRING"
      }
    ]
  })
}

# Local file for function JavaScript code
resource "local_file" "function_index" {
  filename = "${path.module}/function-code/index.js"
  content  = <<-EOT
module.exports = async function (context, myBlob) {
    const fileName = context.bindingData.name;
    const fileSize = myBlob.length;
    const timestamp = new Date().toISOString();
    
    context.log(`🔥 Processing file: $${fileName}`);
    context.log(`📊 File size: $${fileSize} bytes`);
    context.log(`⏰ Processing time: $${timestamp}`);
    
    // Simulate file processing logic based on file type
    if (fileName.toLowerCase().includes('.jpg') || fileName.toLowerCase().includes('.png')) {
        context.log(`🖼️  Image file detected: $${fileName}`);
        context.log(`✅ Image processing completed successfully`);
    } else if (fileName.toLowerCase().includes('.pdf')) {
        context.log(`📄 PDF document detected: $${fileName}`);
        context.log(`✅ PDF processing completed successfully`);
    } else {
        context.log(`📁 Generic file detected: $${fileName}`);
        context.log(`✅ File processing completed successfully`);
    }
    
    // Log processing completion
    context.log(`🎉 File processing workflow completed for: $${fileName}`);
    
    // Return processing results for monitoring
    return {
        fileName: fileName,
        fileSize: fileSize,
        processedAt: timestamp,
        status: 'success'
    };
};
EOT
}

# Data archive for function deployment package
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function-deploy.zip"
  source_dir  = "${path.module}/function-code"

  depends_on = [
    local_file.function_json,
    local_file.function_index
  ]
}

# Function deployment using ZIP package
resource "azurerm_function_app_function" "blob_processor" {
  name            = "BlobProcessor"
  function_app_id = azurerm_linux_function_app.main.id
  language        = title(var.function_app_runtime)
  
  # Function configuration from local files
  config_json = jsonencode({
    bindings = [
      {
        name       = "myBlob"
        type       = "blobTrigger"
        direction  = "in"
        path       = "${var.blob_container_name}/{name}"
        connection = "STORAGE_CONNECTION_STRING"
      }
    ]
  })

  depends_on = [
    data.archive_file.function_code,
    azurerm_role_assignment.function_storage_access
  ]
}
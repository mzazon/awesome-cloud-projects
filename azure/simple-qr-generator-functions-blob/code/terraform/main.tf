# Azure QR Code Generator Infrastructure
# Creates serverless QR code generation using Azure Functions and Blob Storage

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and tagging
locals {
  # Generate unique suffix from random ID
  random_suffix = random_id.suffix.hex
  
  # Resource naming convention
  resource_group_name   = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.random_suffix}"
  storage_account_name  = "st${replace(var.project_name, "-", "")}${var.environment}${local.random_suffix}"
  function_app_name     = "func-${var.project_name}-${var.environment}-${local.random_suffix}"
  app_service_plan_name = "asp-${var.project_name}-${var.environment}-${local.random_suffix}"
  app_insights_name     = "ai-${var.project_name}-${var.environment}-${local.random_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment   = var.environment
    Project      = var.project_name
    ManagedBy    = "Terraform"
    Purpose      = "QR Code Generator"
    CreatedDate  = timestamp()
  }, var.tags)
}

# Create Resource Group for all QR generator resources
resource "azurerm_resource_group" "qr_generator" {
  name     = local.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Storage Account for QR code image storage with security hardening
resource "azurerm_storage_account" "qr_storage" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.qr_generator.name
  location           = azurerm_resource_group.qr_generator.location
  
  # Performance and replication settings
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind            = "StorageV2"
  
  # Security configurations
  min_tls_version                 = var.minimum_tls_version
  allow_nested_items_to_be_public = true
  enable_https_traffic_only       = true
  
  # Network access rules (allow all for demo, restrict in production)
  public_network_access_enabled = true
  
  # Blob properties for lifecycle management
  blob_properties {
    # Enable versioning for blob recovery
    versioning_enabled = false
    
    # Configure soft delete (disabled for demo to avoid costs)
    delete_retention_policy {
      days = 1
    }
    
    # Container delete retention policy
    container_delete_retention_policy {
      days = 1
    }
  }
  
  tags = local.common_tags
  
  # Ensure resource group exists before creating storage account
  depends_on = [azurerm_resource_group.qr_generator]
}

# Blob Container for storing QR code images with public read access
resource "azurerm_storage_container" "qr_codes" {
  name                  = var.blob_container_name
  storage_account_name  = azurerm_storage_account.qr_storage.name
  container_access_type = "blob"  # Public read access to blobs
  
  # Container metadata for organization
  metadata = {
    purpose     = "QR code image storage"
    environment = var.environment
    managed_by  = "terraform"
  }
  
  depends_on = [azurerm_storage_account.qr_storage]
}

# Application Insights for function monitoring and logging
resource "azurerm_application_insights" "qr_generator" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location           = azurerm_resource_group.qr_generator.location
  resource_group_name = azurerm_resource_group.qr_generator.name
  
  application_type    = "web"
  retention_in_days  = var.log_retention_days
  sampling_percentage = 100
  
  # Disable local authentication for enhanced security
  disable_ip_masking = false
  
  tags = local.common_tags
  
  depends_on = [azurerm_resource_group.qr_generator]
}

# App Service Plan for Azure Functions (Consumption/Serverless)
resource "azurerm_service_plan" "qr_generator" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.qr_generator.name
  location           = azurerm_resource_group.qr_generator.location
  
  # Consumption plan for serverless execution
  os_type  = "Linux"
  sku_name = "Y1"  # Consumption plan SKU
  
  tags = local.common_tags
  
  depends_on = [azurerm_resource_group.qr_generator]
}

# Azure Function App for QR code generation
resource "azurerm_linux_function_app" "qr_generator" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.qr_generator.name
  location           = azurerm_resource_group.qr_generator.location
  
  # Link to storage account and service plan
  storage_account_name       = azurerm_storage_account.qr_storage.name
  storage_account_access_key = azurerm_storage_account.qr_storage.primary_access_key
  service_plan_id           = azurerm_service_plan.qr_generator.id
  
  # Security and networking settings
  https_only                 = true
  public_network_access_enabled = true
  
  # Function runtime configuration
  site_config {
    # Runtime stack configuration
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration for web access
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }
    
    # Security headers
    ftps_state        = "Disabled"
    http2_enabled     = true
    minimum_tls_version = var.minimum_tls_version
    
    # Application performance settings
    always_on                         = false  # Not available in Consumption plan
    use_32_bit_worker                = false
    health_check_eviction_time_in_min = 2
  }
  
  # Application settings for function configuration
  app_settings = merge({
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
    # Storage configuration for QR code uploads
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.qr_storage.primary_connection_string
    "BLOB_CONTAINER_NAME"      = azurerm_storage_container.qr_codes.name
    
    # Monitoring configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.qr_generator[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.qr_generator[0].connection_string : ""
    
    # Performance and scaling settings
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.qr_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE" = "${local.function_app_name}-content"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD" = "true"
    
    # Function timeout configuration (in seconds)
    "functionTimeout" = format("00:%02d:00", var.function_timeout)
  }, var.enable_application_insights ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.qr_generator[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.qr_generator[0].connection_string
  } : {})
  
  # Function app identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # Ensure dependencies are created before function app
  depends_on = [
    azurerm_storage_account.qr_storage,
    azurerm_storage_container.qr_codes,
    azurerm_service_plan.qr_generator,
    azurerm_application_insights.qr_generator
  ]
}

# Create the function code deployment package
data "archive_file" "function_app_zip" {
  type        = "zip"
  output_path = "${path.module}/function-app.zip"
  
  source {
    content = jsonencode({
      version = "2.0",
      extensionBundle = {
        id      = "Microsoft.Azure.Functions.ExtensionBundle"
        version = "[4.*, 5.0.0)"
      },
      functionTimeout = "00:${format("%02d", var.function_timeout)}:00"
    })
    filename = "host.json"
  }
  
  source {
    content = join("\n", [
      "azure-functions",
      "azure-storage-blob",
      "qrcode[pil]",
      "pillow"
    ])
    filename = "requirements.txt"
  }
  
  source {
    content = <<-EOT
import azure.functions as func
import logging
import json
import qrcode
import io
import os
from datetime import datetime
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="generate-qr", methods=["POST"])
def generate_qr_code(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('QR Code generation request received.')
    
    try:
        # Parse request body
        req_body = req.get_json()
        if not req_body or 'text' not in req_body:
            return func.HttpResponse(
                json.dumps({"error": "Please provide 'text' in request body"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        text_input = req_body['text']
        if not text_input.strip():
            return func.HttpResponse(
                json.dumps({"error": "Text input cannot be empty"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(text_input)
        qr.make(fit=True)
        
        # Create QR code image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert image to bytes
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        img_bytes.seek(0)
        
        # Generate unique filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"qr_code_{timestamp}.png"
        
        # Upload to blob storage
        connection_string = os.environ.get('STORAGE_CONNECTION_STRING')
        container_name = os.environ.get('BLOB_CONTAINER_NAME', 'qr-codes')
        
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client(
            container=container_name, 
            blob=filename
        )
        
        blob_client.upload_blob(img_bytes.getvalue(), overwrite=True)
        
        # Get blob URL
        blob_url = blob_client.url
        
        logging.info(f'QR code generated and saved: {filename}')
        
        return func.HttpResponse(
            json.dumps({
                "success": True,
                "filename": filename,
                "url": blob_url,
                "text": text_input
            }),
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        logging.error(f'Error generating QR code: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": f"Failed to generate QR code: {str(e)}"}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )
EOT
    filename = "function_app.py"
  }
}

# Deploy the function code using the zip deployment method
resource "azurerm_function_app_function" "generate_qr" {
  name            = "generate-qr"
  function_app_id = azurerm_linux_function_app.qr_generator.id
  language        = "Python"
  
  file {
    name    = "function_app.py"
    content = data.archive_file.function_app_zip.source[2].content
  }
  
  config_json = jsonencode({
    bindings = [
      {
        authLevel = "anonymous"
        type      = "httpTrigger"
        direction = "in"
        name      = "req"
        methods   = ["post"]
        route     = "generate-qr"
      },
      {
        type      = "http"
        direction = "out"
        name      = "$return"
      }
    ]
  })
  
  depends_on = [azurerm_linux_function_app.qr_generator]
}
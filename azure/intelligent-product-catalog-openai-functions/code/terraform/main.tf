# Azure Intelligent Product Catalog Infrastructure
# This Terraform configuration deploys a complete product catalog automation solution
# using Azure Functions, OpenAI Service, and Blob Storage

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Generate resource naming using Azure CAF conventions
resource "azurecaf_name" "resource_group" {
  name          = var.project_name
  resource_type = "azurerm_resource_group"
  suffixes      = [var.environment, random_id.suffix.hex]
}

resource "azurecaf_name" "storage_account" {
  name          = var.project_name
  resource_type = "azurerm_storage_account"
  suffixes      = [var.environment, random_id.suffix.hex]
}

resource "azurecaf_name" "function_app" {
  name          = var.project_name
  resource_type = "azurerm_function_app"
  suffixes      = [var.environment, random_id.suffix.hex]
}

resource "azurecaf_name" "app_service_plan" {
  name          = var.project_name
  resource_type = "azurerm_app_service_plan"
  suffixes      = [var.environment, random_id.suffix.hex]
}

resource "azurecaf_name" "openai_account" {
  name          = var.project_name
  resource_type = "azurerm_cognitive_account"
  suffixes      = [var.environment, random_id.suffix.hex]
}

resource "azurecaf_name" "application_insights" {
  name          = var.project_name
  resource_type = "azurerm_application_insights"
  suffixes      = [var.environment, random_id.suffix.hex]
}

# Create Resource Group
# The resource group contains all resources for the intelligent product catalog solution
resource "azurerm_resource_group" "main" {
  name     = coalesce(var.resource_group_name, azurecaf_name.resource_group.result)
  location = var.location
  tags     = var.tags
}

# Create Storage Account
# Blob Storage provides scalable object storage for product images and catalog results
resource "azurerm_storage_account" "main" {
  name                     = azurecaf_name.storage_account.result
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.storage_access_tier
  account_kind             = "StorageV2"
  
  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Enable blob properties for versioning and change feed
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 7
    
    # Configure CORS for web access if needed
    dynamic "cors_rule" {
      for_each = var.storage_cors_rules
      content {
        allowed_headers    = cors_rule.value.allowed_headers
        allowed_methods    = cors_rule.value.allowed_methods
        allowed_origins    = cors_rule.value.allowed_origins
        exposed_headers    = cors_rule.value.exposed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
      }
    }
    
    # Container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
    
    # Blob delete retention policy
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Create Blob Containers
# Separate containers for input images and output catalog data
resource "azurerm_storage_container" "containers" {
  for_each = {
    for container in var.blob_containers : container.name => container
  }
  
  name                  = each.key
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = each.value.access_type
}

# Create Application Insights
# Provides monitoring and telemetry for the Function App
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = azurecaf_name.application_insights.result
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  application_type   = "web"
  
  # Configure data retention
  retention_in_days = 90
  
  # Disable IP masking for better analytics
  disable_ip_masking = false
  
  tags = var.tags
}

# Create Azure OpenAI Service Account
# Provides access to GPT-4o multimodal AI capabilities
resource "azurerm_cognitive_account" "openai" {
  name                = azurecaf_name.openai_account.result
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  kind               = "OpenAI"
  sku_name           = var.openai_sku_name
  
  # Custom subdomain is required for OpenAI services
  custom_subdomain_name = azurecaf_name.openai_account.result
  
  # Network access configuration
  public_network_access_enabled = true
  
  # Identity configuration for managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Deploy GPT-4o Model
# Deploys the multimodal GPT-4o model for image analysis and text generation
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o-deployment"
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
  
  # Ensure the cognitive account is fully created before deployment
  depends_on = [azurerm_cognitive_account.openai]
}

# Create App Service Plan
# Defines the compute resources for the Function App
resource "azurerm_service_plan" "main" {
  name                = azurecaf_name.app_service_plan.result
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Configure for consumption plan or premium plan based on SKU
  os_type  = "Linux"
  sku_name = var.function_app_plan_sku
  
  tags = var.tags
}

# Create Linux Function App
# Serverless compute platform for automatic image processing
resource "azurerm_linux_function_app" "main" {
  name                = azurecaf_name.function_app.result
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.main.id
  
  # Storage account for function app state and code
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Enable built-in logging and monitoring
  builtin_logging_enabled    = true
  client_certificate_enabled = false
  enabled                   = true
  https_only               = true
  
  # Function App configuration
  site_config {
    # Configure for Python runtime
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Enable Application Insights integration
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    
    # Configure CORS for web access
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    
    # Set function timeout
    pre_warmed_instance_count = 1
    
    # Configure application settings within site_config
    app_service_logs {
      disk_quota_mb         = 25
      retention_period_days = 7
    }
  }
  
  # Application settings for function configuration
  app_settings = {
    # Azure Functions runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    
    # Azure OpenAI Service configuration
    "AZURE_OPENAI_ENDPOINT"   = azurerm_cognitive_account.openai.endpoint
    "AZURE_OPENAI_KEY"        = azurerm_cognitive_account.openai.primary_access_key
    "AZURE_OPENAI_DEPLOYMENT" = azurerm_cognitive_deployment.gpt4o.name
    
    # Storage configuration
    "AzureWebJobsStorage"         = azurerm_storage_account.main.primary_connection_string
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Function-specific settings
    "FUNCTION_TIMEOUT_SECONDS" = var.function_timeout
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE" = "${azurecaf_name.function_app.result}-content"
    
    # Python-specific settings
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
    "PYTHON_ENABLE_WORKER_EXTENSIONS"    = "1"
  }
  
  # Configure managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  # Lifecycle management
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
  
  tags = var.tags
  
  depends_on = [
    azurerm_service_plan.main,
    azurerm_storage_account.main,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.gpt4o
  ]
}

# Storage Account Diagnostic Settings
# Enable logging and monitoring for the storage account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count = var.enable_storage_logging ? 1 : 0
  
  name                       = "storage-diagnostics"
  target_resource_id        = azurerm_storage_account.main.id
  log_analytics_workspace_id = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
  
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }
  
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled = true
  }
}

# Role Assignment - Function App to Storage Account
# Grants the Function App managed identity access to the storage account
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Role Assignment - Function App to OpenAI
# Grants the Function App managed identity access to the OpenAI service
resource "azurerm_role_assignment" "function_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Local file for Function App code (optional - for reference)
# This creates a placeholder for the Python function code
resource "local_file" "function_code" {
  filename = "${path.module}/function_app.py"
  content = <<-EOT
import azure.functions as func
import json
import logging
import base64
from openai import AzureOpenAI
import os
from datetime import datetime

app = func.FunctionApp()

@app.blob_trigger(arg_name="myblob", 
                  path="product-images/{name}",
                  connection="AzureWebJobsStorage")
@app.blob_output(arg_name="outputblob",
                 path="catalog-results/{name}.json",
                 connection="AzureWebJobsStorage")
def ProductCatalogProcessor(myblob: func.InputStream, outputblob: func.Out[str]):
    logging.info(f"Processing blob: {myblob.name}, Size: {myblob.length} bytes")
    
    try:
        # Initialize Azure OpenAI client with latest API version
        client = AzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_KEY"],
            api_version="2024-10-21"
        )
        
        # Read and encode image
        image_data = myblob.read()
        image_base64 = base64.b64encode(image_data).decode('utf-8')
        
        # Create detailed prompt for product analysis
        prompt = '''
        Analyze this product image and provide a comprehensive product catalog entry. 
        Return a JSON object with the following structure:
        {
            "product_name": "Clear, descriptive product name",
            "description": "Detailed 2-3 sentence product description",
            "features": ["List of key features and specifications"],
            "category": "Primary product category",
            "subcategory": "Specific subcategory",
            "colors": ["Identified colors in the product"],
            "materials": ["Detected materials if applicable"],
            "style": "Design style (modern, classic, etc.)",
            "target_audience": "Intended customer demographic",
            "keywords": ["SEO-friendly keywords"],
            "estimated_price_range": "Price range category (budget/mid-range/premium)"
        }
        
        Focus on accuracy and detail. If certain information cannot be determined from the image, use "Not determinable from image".
        '''
        
        # Call GPT-4o with vision
        response = client.chat.completions.create(
            model=os.environ["AZURE_OPENAI_DEPLOYMENT"],
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{image_base64}",
                                "detail": "high"
                            }
                        }
                    ]
                }
            ],
            max_tokens=1000,
            temperature=0.3
        )
        
        # Parse the response
        catalog_data = json.loads(response.choices[0].message.content)
        
        # Add metadata
        catalog_data["processing_timestamp"] = datetime.utcnow().isoformat() + "Z"
        catalog_data["source_image"] = myblob.name
        catalog_data["image_size_bytes"] = myblob.length
        catalog_data["model_used"] = os.environ["AZURE_OPENAI_DEPLOYMENT"]
        
        # Output the catalog data
        outputblob.set(json.dumps(catalog_data, indent=2))
        
        logging.info(f"Successfully processed {myblob.name}")
        
    except Exception as e:
        logging.error(f"Error processing {myblob.name}: {str(e)}")
        
        # Create error output
        error_data = {
            "error": str(e),
            "source_image": myblob.name,
            "processing_timestamp": datetime.utcnow().isoformat() + "Z",
            "status": "failed"
        }
        outputblob.set(json.dumps(error_data, indent=2))
EOT
}

# Local file for requirements.txt (optional - for reference)
resource "local_file" "requirements" {
  filename = "${path.module}/requirements.txt"
  content = <<-EOT
azure-functions
openai>=1.0.0
azure-storage-blob
EOT
}
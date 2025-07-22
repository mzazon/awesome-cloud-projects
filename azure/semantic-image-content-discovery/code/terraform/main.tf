# Main Terraform Configuration for Intelligent Image Content Discovery
# This configuration deploys Azure AI Vision, Azure AI Search, Storage, and Functions
# to create an intelligent image content discovery system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  storage_name    = "${var.project_name}${local.resource_suffix}"
  vision_name     = "aivision-${var.project_name}-${local.resource_suffix}"
  search_name     = "aisearch-${var.project_name}-${local.resource_suffix}"
  function_name   = "func-${var.project_name}-${local.resource_suffix}"
  app_insights_name = "appi-${var.project_name}-${local.resource_suffix}"
  
  # Combined tags for all resources
  tags = merge(var.common_tags, {
    ResourceSuffix = local.resource_suffix
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group for all image discovery components
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# Storage Account for image repository and function app
resource "azurerm_storage_account" "main" {
  name                = local.storage_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Storage configuration
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier             = var.storage_access_tier
  
  # Security settings
  allow_nested_items_to_be_public = var.enable_storage_public_access
  enable_https_traffic_only       = var.enable_https_only
  min_tls_version                 = var.min_tls_version
  
  # Advanced security features
  shared_access_key_enabled = true
  
  # Blob storage properties
  blob_properties {
    versioning_enabled  = false
    change_feed_enabled = false
    
    # Delete retention policy
    delete_retention_policy {
      days = 7
    }
    
    # Container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.tags
}

# Blob container for image storage
resource "azurerm_storage_container" "images" {
  name                  = var.image_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.container_access_type
}

# Azure AI Vision service for image analysis
resource "azurerm_cognitive_account" "vision" {
  name                = local.vision_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind               = var.ai_vision_kind
  sku_name           = var.ai_vision_sku
  
  # Custom subdomain for service endpoint
  custom_subdomain_name = local.vision_name
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.tags
}

# Azure AI Search service for content indexing and discovery
resource "azurerm_search_service" "main" {
  name                = local.search_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  sku                = var.search_sku
  replica_count      = var.search_replica_count
  partition_count    = var.search_partition_count
  
  # Authentication configuration
  allowed_ips                   = []
  authentication_failure_mode  = null
  customer_managed_key_enforcement_enabled = false
  hosting_mode                 = "default"
  local_authentication_enabled = true
  public_network_access_enabled = true
  
  # Identity for secure access to other services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.tags
}

# Application Insights for monitoring (conditional)
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type   = var.application_insights_type
  
  tags = local.tags
}

# App Service Plan for Function App (Consumption plan)
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  os_type            = var.function_app_os_type
  sku_name           = "Y1"  # Consumption plan
  
  tags = local.tags
}

# Function App for image processing automation
resource "azurerm_linux_function_app" "main" {
  name                = local.function_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Service plan and storage configuration
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function runtime configuration
  site_config {
    # Runtime and version
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration for web interface
    cors {
      allowed_origins     = ["*"]  # Configure appropriately for production
      support_credentials = false
    }
    
    # Security headers
    use_32_bit_worker        = false
    ftps_state              = "FtpsOnly"
    http2_enabled           = true
    minimum_tls_version     = "1.2"
    remote_debugging_enabled = false
    scm_use_main_ip_restriction = false
  }
  
  # Application settings for AI service integration
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    
    # AI Vision service configuration
    "VISION_ENDPOINT" = azurerm_cognitive_account.vision.endpoint
    "VISION_KEY"      = azurerm_cognitive_account.vision.primary_access_key
    
    # AI Search service configuration
    "SEARCH_ENDPOINT" = "https://${azurerm_search_service.main.name}.search.windows.net"
    "SEARCH_KEY"      = azurerm_search_service.main.primary_key
    "SEARCH_INDEX"    = var.search_index_name
    
    # Storage configuration
    "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.main.name
    "STORAGE_CONTAINER"    = azurerm_storage_container.images.name
    "AzureWebJobsStorage"  = azurerm_storage_account.main.primary_connection_string
    
    # Application Insights (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Additional configuration
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE" = "${local.function_name}-content"
  }
  
  # Managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.tags
  
  # Ensure proper resource dependencies
  depends_on = [
    azurerm_storage_account.main,
    azurerm_cognitive_account.vision,
    azurerm_search_service.main
  ]
}

# Role assignment for Function App to access Storage
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role assignment for Function App to access AI Vision
resource "azurerm_role_assignment" "function_vision" {
  scope                = azurerm_cognitive_account.vision.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role assignment for Function App to access AI Search
resource "azurerm_role_assignment" "function_search" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Function code deployment (placeholder - requires actual function code)
# In a real deployment, you would use azurerm_function_app_function resources
# or deploy via Azure DevOps/GitHub Actions

# Create a zip file for function deployment (placeholder)
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function.zip"
  
  source {
    content = templatefile("${path.module}/function_template.py", {
      vision_endpoint = azurerm_cognitive_account.vision.endpoint
      search_endpoint = "https://${azurerm_search_service.main.name}.search.windows.net"
      search_index    = var.search_index_name
      storage_account = azurerm_storage_account.main.name
      container_name  = azurerm_storage_container.images.name
    })
    filename = "__init__.py"
  }
  
  source {
    content = jsonencode({
      bindings = [
        {
          name      = "myBlob"
          type      = "blobTrigger"
          direction = "in"
          path      = "${var.image_container_name}/{name}"
          connection = "AzureWebJobsStorage"
        }
      ]
    })
    filename = "function.json"
  }
  
  source {
    content = "azure-functions\nazure-search-documents\nrequests\nazure-storage-blob\nazure-identity"
    filename = "requirements.txt"
  }
}

# Search index creation via REST API (using null_resource)
resource "null_resource" "search_index" {
  # Trigger when search service changes
  triggers = {
    search_service_id = azurerm_search_service.main.id
    index_name       = var.search_index_name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      curl -X POST "https://${azurerm_search_service.main.name}.search.windows.net/indexes?api-version=2024-05-01-preview" \
        -H "Content-Type: application/json" \
        -H "api-key: ${azurerm_search_service.main.primary_key}" \
        -d '{
          "name": "${var.search_index_name}",
          "fields": [
            {
              "name": "id",
              "type": "Edm.String",
              "key": true,
              "searchable": false,
              "filterable": false,
              "sortable": false
            },
            {
              "name": "filename",
              "type": "Edm.String",
              "searchable": true,
              "filterable": true,
              "sortable": true
            },
            {
              "name": "description",
              "type": "Edm.String",
              "searchable": true,
              "filterable": false,
              "sortable": false
            },
            {
              "name": "tags",
              "type": "Collection(Edm.String)",
              "searchable": true,
              "filterable": true,
              "sortable": false
            },
            {
              "name": "objects",
              "type": "Collection(Edm.String)",
              "searchable": true,
              "filterable": true,
              "sortable": false
            },
            {
              "name": "imageUrl",
              "type": "Edm.String",
              "searchable": false,
              "filterable": false,
              "sortable": false
            },
            {
              "name": "contentVector",
              "type": "Collection(Edm.Single)",
              "searchable": true,
              "filterable": false,
              "sortable": false,
              "dimensions": ${var.vector_dimensions},
              "vectorSearchProfile": "default-vector-profile"
            }
          ],
          "vectorSearch": {
            "algorithms": [
              {
                "name": "default-hnsw",
                "kind": "hnsw",
                "hnswParameters": {
                  "metric": "cosine",
                  "m": 4,
                  "efConstruction": 400,
                  "efSearch": 500
                }
              }
            ],
            "profiles": [
              {
                "name": "default-vector-profile",
                "algorithm": "default-hnsw"
              }
            ]
          }
        }'
    EOT
  }
  
  depends_on = [azurerm_search_service.main]
}

# Function template file creation
resource "local_file" "function_template" {
  filename = "${path.module}/function_template.py"
  content = <<-EOT
import azure.functions as func
import json
import os
import requests
import uuid
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential

def main(myBlob: func.InputStream):
    """
    Azure Function triggered by blob upload to process images with AI Vision
    and index the results in Azure AI Search for intelligent content discovery.
    """
    
    # Get configuration from environment variables
    vision_endpoint = os.environ['VISION_ENDPOINT']
    vision_key = os.environ['VISION_KEY']
    search_endpoint = os.environ['SEARCH_ENDPOINT']
    search_key = os.environ['SEARCH_KEY']
    search_index = os.environ['SEARCH_INDEX']
    storage_account = os.environ['STORAGE_ACCOUNT_NAME']
    container_name = os.environ['STORAGE_CONTAINER']
    
    try:
        # Read image data from blob trigger
        image_data = myBlob.read()
        
        # Analyze image with Azure AI Vision
        vision_url = f"{vision_endpoint}/vision/v3.2/analyze"
        headers = {
            'Ocp-Apim-Subscription-Key': vision_key,
            'Content-Type': 'application/octet-stream'
        }
        params = {
            'visualFeatures': 'Tags,Description,Objects,Categories,Adult,Color,ImageType',
            'details': 'Landmarks,Celebrities',
            'language': 'en'
        }
        
        # Call AI Vision API
        response = requests.post(vision_url, headers=headers, params=params, data=image_data)
        response.raise_for_status()
        vision_result = response.json()
        
        # Extract comprehensive metadata from AI Vision analysis
        description = ''
        if 'description' in vision_result and vision_result['description']['captions']:
            description = vision_result['description']['captions'][0]['text']
        
        # Extract tags with confidence filtering
        tags = []
        if 'tags' in vision_result:
            tags = [tag['name'] for tag in vision_result['tags'] if tag.get('confidence', 0) > 0.5]
        
        # Extract detected objects
        objects = []
        if 'objects' in vision_result:
            objects = [obj['object'] for obj in vision_result['objects']]
        
        # Extract categories
        categories = []
        if 'categories' in vision_result:
            categories = [cat['name'] for cat in vision_result['categories'] if cat.get('score', 0) > 0.1]
        
        # Extract color information
        colors = []
        if 'color' in vision_result:
            color_info = vision_result['color']
            if 'dominantColors' in color_info:
                colors = color_info['dominantColors']
        
        # Create comprehensive search document
        document = {
            'id': str(uuid.uuid4()),
            'filename': myBlob.name,
            'description': description,
            'tags': tags,
            'objects': objects,
            'categories': categories,
            'colors': colors,
            'imageUrl': f"https://{storage_account}.blob.core.windows.net/{container_name}/{myBlob.name}",
            'processedDate': func.utcnow().isoformat(),
            'fileSize': len(image_data)
        }
        
        # Add OCR text if available
        if 'readResult' in vision_result:
            ocr_text = []
            for page in vision_result['readResult']['pages']:
                for line in page.get('lines', []):
                    ocr_text.append(line['text'])
            document['ocrText'] = ' '.join(ocr_text)
        
        # Index document in Azure AI Search
        search_client = SearchClient(
            endpoint=search_endpoint,
            index_name=search_index,
            credential=AzureKeyCredential(search_key)
        )
        
        # Upload document to search index
        result = search_client.upload_documents([document])
        
        # Log successful processing
        print(f"Successfully processed and indexed image: {myBlob.name}")
        print(f"Extracted {len(tags)} tags, {len(objects)} objects")
        print(f"Description: {description}")
        
        return func.HttpResponse(
            json.dumps({"status": "success", "document_id": document['id']}),
            status_code=200,
            mimetype="application/json"
        )
        
    except requests.exceptions.RequestException as e:
        error_msg = f"AI Vision API error: {str(e)}"
        print(error_msg)
        return func.HttpResponse(
            json.dumps({"status": "error", "message": error_msg}),
            status_code=500,
            mimetype="application/json"
        )
        
    except Exception as e:
        error_msg = f"Processing error: {str(e)}"
        print(error_msg)
        return func.HttpResponse(
            json.dumps({"status": "error", "message": error_msg}),
            status_code=500,
            mimetype="application/json"
        )
EOT
}
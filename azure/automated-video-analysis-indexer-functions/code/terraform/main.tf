# Main Terraform configuration for automated video analysis with Azure AI Video Indexer and Functions
# This configuration creates a complete serverless video analysis pipeline with AI-powered insights extraction

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Local values for consistent resource naming and tagging
locals {
  # Resource name prefix combining project name and environment
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Unique suffix for globally unique resources
  unique_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment   = var.environment
    Project       = var.project_name
    CreatedBy     = "terraform"
    Purpose       = "video-analysis"
    Recipe        = "automated-video-analysis-indexer-functions"
    LastUpdated   = formatdate("YYYY-MM-DD", timestamp())
  }, var.tags)
  
  # Storage container names
  video_container_name   = "videos"
  insights_container_name = "insights"
  
  # Function App settings
  function_app_settings = {
    # Core Function App configuration
    "FUNCTIONS_EXTENSION_VERSION"           = "~4"
    "FUNCTIONS_WORKER_RUNTIME"             = "python"
    "PYTHON_VERSION"                       = var.python_version
    "AzureWebJobsFeatureFlags"             = "EnableWorkerIndexing"
    
    # Storage configuration
    "AzureWebJobsStorage"                  = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                 = "${local.name_prefix}-func-content"
    "STORAGE_CONNECTION_STRING"            = azurerm_storage_account.main.primary_connection_string
    
    # Video Indexer configuration
    "VIDEO_INDEXER_ACCOUNT_ID"             = azurerm_cognitive_account.video_indexer.custom_subdomain_name
    "VIDEO_INDEXER_ACCESS_KEY"             = azurerm_cognitive_account.video_indexer.primary_access_key
    "VIDEO_INDEXER_LOCATION"               = var.location
    "VIDEO_INDEXER_RESOURCE_GROUP"         = azurerm_resource_group.main.name
    "VIDEO_INDEXER_SUBSCRIPTION_ID"        = data.azurerm_client_config.current.subscription_id
    
    # Application Insights configuration (conditional)
    "APPINSIGHTS_INSTRUMENTATIONKEY"       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    "ApplicationInsightsAgent_EXTENSION_VERSION" = var.enable_application_insights ? "~3" : ""
    
    # Function timeout configuration
    "WEBSITE_TIME_ZONE"                    = "UTC"
    "FUNCTION_APP_TIMEOUT"                 = "${var.function_timeout_minutes}:00:00"
    
    # Debugging configuration (conditional)
    "AZURE_FUNCTIONS_ENVIRONMENT"          = var.enable_debug_logging ? "Development" : "Production"
    "LOGGING_LEVEL"                        = var.enable_debug_logging ? "DEBUG" : "INFO"
    
    # Security configuration
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS"   = "7"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"      = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"       = "true"
  }
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create the main resource group for all video analysis resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}-${local.unique_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Create storage account for video files and analysis results
resource "azurerm_storage_account" "main" {
  name                     = "sa${replace(local.name_prefix, "-", "")}${local.unique_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configuration
  public_network_access_enabled   = var.enable_public_access
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  
  # Enable versioning and change feed for blob storage
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure delete retention policy
    delete_retention_policy {
      days = 7
    }
    
    # Configure container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Configure network access rules if IP restrictions are specified
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_addresses) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_addresses
      bypass         = ["AzureServices"]
    }
  }
  
  tags = local.common_tags
}

# Create blob containers for video processing pipeline
resource "azurerm_storage_container" "videos" {
  name                  = local.video_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_container" "insights" {
  name                  = local.insights_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Configure storage lifecycle management for cost optimization
resource "azurerm_storage_management_policy" "main" {
  count              = var.storage_lifecycle_enabled ? 1 : 0
  storage_account_id = azurerm_storage_account.main.id
  
  rule {
    name    = "video-lifecycle-policy"
    enabled = true
    
    filters {
      prefix_match = ["${local.video_container_name}/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        # Move to cool storage after specified days
        tier_to_cool_after_days_since_modification_greater_than = var.video_archive_days
        # Archive after 90 days to reduce costs further
        tier_to_archive_after_days_since_modification_greater_than = 90
      }
    }
  }
  
  rule {
    name    = "insights-lifecycle-policy"
    enabled = true
    
    filters {
      prefix_match = ["${local.insights_container_name}/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        # Delete insights after specified retention period
        delete_after_days_since_modification_greater_than = var.insights_delete_days
      }
    }
  }
}

# Create Azure AI Video Indexer account (Cognitive Services)
resource "azurerm_cognitive_account" "video_indexer" {
  name                = "vi-${local.name_prefix}-${local.unique_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "VideoIndexer"
  sku_name            = var.video_indexer_sku
  
  # Enable custom subdomain for ARM-based API access
  custom_subdomain_name = "vi-${local.name_prefix}-${local.unique_suffix}"
  
  # Configure public network access
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Create Application Insights for function monitoring (optional)
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "ai-${local.name_prefix}-${local.unique_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "other"
  
  # Configure data retention
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Create App Service Plan for Azure Functions
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.name_prefix}-${local.unique_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Configure for consumption plan or premium plan
  os_type  = "Linux"
  sku_name = var.function_app_plan_sku
  
  tags = local.common_tags
}

# Create Azure Function App for video processing
resource "azurerm_linux_function_app" "main" {
  name                = "func-${local.name_prefix}-${local.unique_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id
  
  # Configure Function App settings
  app_settings = local.function_app_settings
  
  # Configure site configuration
  site_config {
    # Application stack configuration
    application_stack {
      python_version = var.python_version
    }
    
    # Configure minimum TLS version
    minimum_tls_version = "1.2"
    
    # Enable Application Insights (conditional)
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    
    # Configure runtime settings
    always_on                = var.function_app_plan_sku != "Y1" # Only for non-consumption plans
    use_32_bit_worker        = false
    
    # Configure CORS for potential web interface integration
    cors {
      allowed_origins     = []
      support_credentials = false
    }
  }
  
  # Configure identity for accessing other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_service_plan.main,
    azurerm_application_insights.main
  ]
}

# Create function code directory and files
resource "local_file" "function_host_json" {
  filename = "${path.module}/function_code/host.json"
  content = jsonencode({
    version = "2.0"
    extensionBundle = {
      id      = "Microsoft.Azure.Functions.ExtensionBundle"
      version = "[4.0.0, 5.0.0)"
    }
    functionTimeout = "00:${var.function_timeout_minutes}:00"
    logging = {
      logLevel = {
        default = var.enable_debug_logging ? "Debug" : "Information"
      }
    }
  })
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/function_code/requirements.txt"
  content = <<-EOT
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
requests>=2.31.0
azure-functions-worker>=1.2.0
azure-identity>=1.15.0
EOT
}

resource "local_file" "video_analyzer_function_json" {
  filename = "${path.module}/function_code/VideoAnalyzer/function.json"
  content = jsonencode({
    scriptFile = "__init__.py"
    bindings = [
      {
        name       = "myblob"
        type       = "blobTrigger"
        direction  = "in"
        path       = "${local.video_container_name}/{name}"
        connection = "STORAGE_CONNECTION_STRING"
      },
      {
        name       = "outputBlob"
        type       = "blob"
        direction  = "out"
        path       = "${local.insights_container_name}/{name}.json"
        connection = "STORAGE_CONNECTION_STRING"
      }
    ]
  })
}

resource "local_file" "video_analyzer_init_py" {
  filename = "${path.module}/function_code/VideoAnalyzer/__init__.py"
  content = <<-EOT
import logging
import json
import os
import requests
import time
from datetime import datetime, timedelta
from urllib.parse import quote
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.identity import DefaultAzureCredential
import azure.functions as func

def main(myblob: func.InputStream, outputBlob: func.Out[str]):
    """
    Azure Function triggered by blob uploads to process videos with Video Indexer
    
    Args:
        myblob: Input blob stream containing the uploaded video
        outputBlob: Output blob for storing analysis results
    """
    logging.info(f"Processing video: {myblob.name}")
    
    # Get configuration from environment variables
    vi_account_id = os.environ['VIDEO_INDEXER_ACCOUNT_ID']
    vi_access_key = os.environ['VIDEO_INDEXER_ACCESS_KEY']
    vi_location = os.environ['VIDEO_INDEXER_LOCATION']
    storage_connection = os.environ['STORAGE_CONNECTION_STRING']
    subscription_id = os.environ['VIDEO_INDEXER_SUBSCRIPTION_ID']
    resource_group = os.environ['VIDEO_INDEXER_RESOURCE_GROUP']
    
    try:
        # Extract video name from blob path
        video_name = os.path.basename(myblob.name)
        logging.info(f"Processing video: {video_name}")
        
        # Generate access token for Video Indexer ARM-based API
        access_token = get_video_indexer_access_token(
            vi_access_key, vi_location, vi_account_id
        )
        
        if not access_token:
            raise Exception("Failed to obtain Video Indexer access token")
            
        logging.info("Successfully obtained Video Indexer access token")
        
        # Create blob service client and generate SAS URL for video access
        blob_service_client = BlobServiceClient.from_connection_string(storage_connection)
        blob_client = blob_service_client.get_blob_client(
            container="videos", 
            blob=os.path.basename(myblob.name)
        )
        
        # Generate SAS token for Video Indexer to access the video
        account_key = storage_connection.split('AccountKey=')[1].split(';')[0]
        sas_token = generate_blob_sas(
            account_name=blob_client.account_name,
            container_name=blob_client.container_name,
            blob_name=blob_client.blob_name,
            account_key=account_key,
            permission=BlobSasPermissions(read=True),
            expiry=datetime.utcnow() + timedelta(hours=2)
        )
        
        video_url = f"{blob_client.url}?{sas_token}"
        logging.info("Generated SAS URL for video access")
        
        # Upload video to Video Indexer for processing
        video_id = upload_video_to_indexer(
            access_token, vi_location, vi_account_id, video_name, video_url
        )
        
        if not video_id:
            raise Exception("Failed to upload video to Video Indexer")
            
        logging.info(f"Video uploaded successfully. Video ID: {video_id}")
        
        # Poll for processing completion with exponential backoff
        insights_data = wait_for_processing_completion(
            access_token, vi_location, vi_account_id, video_id
        )
        
        if insights_data:
            # Extract and structure insights
            summary = create_insights_summary(video_name, video_id, insights_data)
            
            # Output insights to blob storage
            outputBlob.set(json.dumps(summary, indent=2, ensure_ascii=False))
            logging.info("Video analysis completed and insights saved")
        else:
            # Handle processing timeout or failure
            logging.warning("Video processing did not complete successfully")
            partial_result = {
                'video_name': video_name,
                'video_id': video_id,
                'status': 'processing_timeout',
                'message': 'Processing timeout - check Video Indexer portal for status',
                'timestamp': datetime.utcnow().isoformat()
            }
            outputBlob.set(json.dumps(partial_result, indent=2))
            
    except Exception as e:
        logging.error(f"Error processing video: {str(e)}")
        error_result = {
            'video_name': myblob.name,
            'error': str(e),
            'status': 'failed',
            'timestamp': datetime.utcnow().isoformat()
        }
        outputBlob.set(json.dumps(error_result, indent=2))

def get_video_indexer_access_token(access_key, location, account_id):
    """
    Obtain access token for Video Indexer API using subscription key
    
    Returns:
        str: Access token for API calls
    """
    try:
        token_url = f"https://api.videoindexer.ai/auth/{location}/Accounts/{account_id}/AccessToken"
        headers = {
            'Ocp-Apim-Subscription-Key': access_key,
            'Content-Type': 'application/json'
        }
        params = {'allowEdit': 'true'}
        
        response = requests.get(token_url, headers=headers, params=params)
        
        if response.status_code == 200:
            # Remove quotes from token response
            return response.json().strip('"')
        else:
            logging.error(f"Failed to get access token: {response.text}")
            return None
            
    except Exception as e:
        logging.error(f"Error getting access token: {str(e)}")
        return None

def upload_video_to_indexer(access_token, location, account_id, video_name, video_url):
    """
    Upload video to Video Indexer for processing
    
    Returns:
        str: Video ID from Video Indexer
    """
    try:
        upload_url = f"https://api.videoindexer.ai/{location}/Accounts/{account_id}/Videos"
        params = {
            'accessToken': access_token,
            'name': video_name,
            'videoUrl': video_url,
            'privacy': 'Private',
            'partition': 'default',
            'language': 'auto-detect'
        }
        
        response = requests.post(upload_url, params=params)
        
        if response.status_code == 200:
            return response.json()['id']
        else:
            logging.error(f"Video upload failed: {response.text}")
            return None
            
    except Exception as e:
        logging.error(f"Error uploading video: {str(e)}")
        return None

def wait_for_processing_completion(access_token, location, account_id, video_id, max_attempts=25):
    """
    Poll Video Indexer for processing completion with exponential backoff
    
    Returns:
        dict: Video insights data if processing completed successfully
    """
    processing_state = "Processing"
    attempt = 0
    wait_time = 30
    
    while processing_state in ["Processing", "Uploaded"] and attempt < max_attempts:
        time.sleep(wait_time)
        
        try:
            status_url = f"https://api.videoindexer.ai/{location}/Accounts/{account_id}/Videos/{video_id}/Index"
            params = {'accessToken': access_token}
            
            response = requests.get(status_url, params=params)
            
            if response.status_code == 200:
                status_data = response.json()
                processing_state = status_data.get('state', 'Processing')
                logging.info(f"Processing state: {processing_state} (attempt {attempt + 1})")
                
                # Return insights if processing completed
                if processing_state == "Processed":
                    return status_data
                    
            else:
                logging.warning(f"Status check failed: {response.text}")
                
        except Exception as e:
            logging.warning(f"Error checking processing status: {str(e)}")
        
        attempt += 1
        # Exponential backoff with maximum 120 seconds
        wait_time = min(wait_time * 1.3, 120)
    
    logging.warning(f"Processing did not complete within {max_attempts} attempts")
    return None

def create_insights_summary(video_name, video_id, insights_data):
    """
    Create a structured summary of video insights
    
    Returns:
        dict: Structured insights summary
    """
    return {
        'video_name': video_name,
        'video_id': video_id,
        'processing_completed': datetime.utcnow().isoformat(),
        'duration_seconds': insights_data.get('durationInSeconds', 0),
        'summary_insights': {
            'transcript': extract_transcript(insights_data),
            'faces': extract_faces(insights_data),
            'objects': extract_objects(insights_data),
            'emotions': extract_emotions(insights_data),
            'keywords': extract_keywords(insights_data),
            'topics': extract_topics(insights_data),
            'sentiment': extract_sentiment(insights_data)
        },
        'metadata': {
            'format': insights_data.get('format', 'Unknown'),
            'resolution': insights_data.get('resolution', 'Unknown'),
            'frameRate': insights_data.get('frameRate', 'Unknown')
        },
        'status': 'completed',
        'full_insights': insights_data  # Include complete raw data for advanced use cases
    }

def extract_transcript(insights_data):
    """Extract and format transcript from Video Indexer insights"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            transcript_items = videos[0]['insights'].get('transcript', [])
            return [
                {
                    'text': item.get('text', ''),
                    'confidence': item.get('confidence', 0),
                    'start_time': item.get('instances', [{}])[0].get('start', '0:00:00'),
                    'end_time': item.get('instances', [{}])[0].get('end', '0:00:00'),
                    'speaker_id': item.get('speakerId', 0)
                }
                for item in transcript_items[:100]  # Limit to first 100 entries
            ]
    except Exception as e:
        logging.warning(f"Error extracting transcript: {e}")
    return []

def extract_faces(insights_data):
    """Extract face detection results with confidence scores"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            faces = videos[0]['insights'].get('faces', [])
            return [
                {
                    'name': face.get('name', 'Unknown'),
                    'confidence': face.get('confidence', 0),
                    'description': face.get('description', ''),
                    'thumbnail_id': face.get('thumbnailId', ''),
                    'known_person_id': face.get('knownPersonId', '')
                }
                for face in faces[:20]  # Limit to first 20 faces
            ]
    except Exception as e:
        logging.warning(f"Error extracting faces: {e}")
    return []

def extract_objects(insights_data):
    """Extract object detection and scene analysis results"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            labels = videos[0]['insights'].get('labels', [])
            return [
                {
                    'name': label.get('name', ''),
                    'confidence': label.get('confidence', 0),
                    'language': label.get('language', 'en-US'),
                    'instances_count': len(label.get('instances', []))
                }
                for label in labels[:30]  # Limit to top 30 objects
            ]
    except Exception as e:
        logging.warning(f"Error extracting objects: {e}")
    return []

def extract_emotions(insights_data):
    """Extract emotion analysis results from facial expressions"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            emotions = videos[0]['insights'].get('emotions', [])
            return [
                {
                    'type': emotion.get('type', ''),
                    'confidence': emotion.get('confidence', 0),
                    'instances_count': len(emotion.get('instances', []))
                }
                for emotion in emotions[:10]  # Limit to top 10 emotions
            ]
    except Exception as e:
        logging.warning(f"Error extracting emotions: {e}")
    return []

def extract_keywords(insights_data):
    """Extract keywords and key phrases from video content"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            keywords = videos[0]['insights'].get('keywords', [])
            return [
                {
                    'name': keyword.get('name', ''),
                    'confidence': keyword.get('confidence', 0),
                    'instances_count': len(keyword.get('instances', []))
                }
                for keyword in keywords[:25]  # Limit to top 25 keywords
            ]
    except Exception as e:
        logging.warning(f"Error extracting keywords: {e}")
    return []

def extract_topics(insights_data):
    """Extract topics and themes from video content"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            topics = videos[0]['insights'].get('topics', [])
            return [
                {
                    'name': topic.get('name', ''),
                    'confidence': topic.get('confidence', 0),
                    'iptc_name': topic.get('iptcName', ''),
                    'instances_count': len(topic.get('instances', []))
                }
                for topic in topics[:15]  # Limit to top 15 topics
            ]
    except Exception as e:
        logging.warning(f"Error extracting topics: {e}")
    return []

def extract_sentiment(insights_data):
    """Extract overall sentiment analysis from video content"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            sentiments = videos[0]['insights'].get('sentiments', [])
            if sentiments:
                # Calculate average sentiment
                positive_count = sum(1 for s in sentiments if s.get('sentimentType') == 'Positive')
                negative_count = sum(1 for s in sentiments if s.get('sentimentType') == 'Negative')
                neutral_count = len(sentiments) - positive_count - negative_count
                
                return {
                    'overall_sentiment': 'Positive' if positive_count > negative_count else 'Negative' if negative_count > positive_count else 'Neutral',
                    'positive_percentage': round((positive_count / len(sentiments)) * 100, 2) if sentiments else 0,
                    'negative_percentage': round((negative_count / len(sentiments)) * 100, 2) if sentiments else 0,
                    'neutral_percentage': round((neutral_count / len(sentiments)) * 100, 2) if sentiments else 0,
                    'total_segments': len(sentiments)
                }
    except Exception as e:
        logging.warning(f"Error extracting sentiment: {e}")
    
    return {
        'overall_sentiment': 'Unknown',
        'positive_percentage': 0,
        'negative_percentage': 0,
        'neutral_percentage': 0,
        'total_segments': 0
    }
EOT
}

# Create deployment package for the function
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function_code.zip"
  source_dir  = "${path.module}/function_code"
  
  depends_on = [
    local_file.function_host_json,
    local_file.function_requirements,
    local_file.video_analyzer_function_json,
    local_file.video_analyzer_init_py
  ]
}

# Grant the Function App access to the storage account and Video Indexer
resource "azurerm_role_assignment" "function_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_video_indexer_contributor" {
  scope                = azurerm_cognitive_account.video_indexer.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Create a sample video blob for testing (optional)
resource "azurerm_storage_blob" "sample_video" {
  count                  = var.create_sample_video ? 1 : 0
  name                   = "sample-test-video.mp4"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.videos.name
  type                   = "Block"
  source_content         = "This is a placeholder for a sample video file. Replace with actual video content for testing."
  content_type           = "video/mp4"
}
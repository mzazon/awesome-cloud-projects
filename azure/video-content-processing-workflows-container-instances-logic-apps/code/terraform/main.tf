# Azure Video Processing Workflow Infrastructure
# This Terraform configuration creates an automated video processing pipeline using:
# - Azure Container Instances for FFmpeg video processing
# - Azure Logic Apps for workflow orchestration
# - Azure Event Grid for event-driven automation
# - Azure Blob Storage for video file management

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group for all video processing resources
resource "azurerm_resource_group" "video_workflow" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Component = "resource-group"
  })
}

# Storage Account for video files with optimized configuration
resource "azurerm_storage_account" "video_storage" {
  name                     = "stvideo${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.video_workflow.name
  location                 = azurerm_resource_group.video_workflow.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Enable features for video processing workloads
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob storage features
  blob_properties {
    delete_retention_policy {
      days = var.retention_days
    }
    
    container_delete_retention_policy {
      days = var.retention_days
    }
    
    versioning_enabled = true
    change_feed_enabled = true
  }

  tags = merge(var.tags, {
    Component = "storage"
    Purpose   = "video-files"
  })
}

# Storage container for input videos
resource "azurerm_storage_container" "input_videos" {
  name                  = "input-videos"
  storage_account_name  = azurerm_storage_account.video_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.video_storage]
}

# Storage container for processed output videos
resource "azurerm_storage_container" "output_videos" {
  name                  = "output-videos"
  storage_account_name  = azurerm_storage_account.video_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.video_storage]
}

# Event Grid Topic for video processing events
resource "azurerm_eventgrid_topic" "video_events" {
  name                = "egt-video-events-${random_string.suffix.result}"
  location            = azurerm_resource_group.video_workflow.location
  resource_group_name = azurerm_resource_group.video_workflow.name

  tags = merge(var.tags, {
    Component = "event-grid"
    Purpose   = "video-events"
  })
}

# Application Insights for monitoring (optional)
resource "azurerm_application_insights" "video_monitoring" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "ai-video-${random_string.suffix.result}"
  location            = azurerm_resource_group.video_workflow.location
  resource_group_name = azurerm_resource_group.video_workflow.name
  application_type    = "web"
  retention_in_days   = 30

  tags = merge(var.tags, {
    Component = "monitoring"
    Purpose   = "application-insights"
  })
}

# Logic App for video processing workflow orchestration
resource "azurerm_logic_app_workflow" "video_processor" {
  name                = "la-video-processor-${random_string.suffix.result}"
  location            = azurerm_resource_group.video_workflow.location
  resource_group_name = azurerm_resource_group.video_workflow.name
  
  # Enable integration service environment if needed for high-volume processing
  integration_service_environment_id = null
  
  # Basic workflow definition - will be updated with complete logic
  workflow_schema   = "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  # Workflow parameters for dynamic configuration
  parameters = {
    storageAccountName = azurerm_storage_account.video_storage.name
    storageAccountKey  = azurerm_storage_account.video_storage.primary_access_key
    eventGridTopic     = azurerm_eventgrid_topic.video_events.name
    containerGroupName = "cg-video-ffmpeg-${random_string.suffix.result}"
    videoFormats       = jsonencode(var.video_formats)
    videoResolutions   = jsonencode(var.video_resolutions)
  }

  tags = merge(var.tags, {
    Component = "logic-app"
    Purpose   = "workflow-orchestration"
  })
}

# Event Grid subscription to trigger Logic App on blob creation
resource "azurerm_eventgrid_event_subscription" "blob_created" {
  name  = "video-upload-subscription"
  scope = azurerm_storage_account.video_storage.id

  # Configure webhook endpoint to Logic App
  webhook_endpoint {
    url = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.video_workflow.name}/providers/Microsoft.Logic/workflows/${azurerm_logic_app_workflow.video_processor.name}/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=${random_string.suffix.result}"
  }

  # Filter for blob creation events in input container only
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/input-videos/"
  }

  # Only trigger on blob creation events
  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]

  depends_on = [
    azurerm_logic_app_workflow.video_processor,
    azurerm_storage_container.input_videos
  ]

  labels = {
    Component = "event-subscription"
    Purpose   = "blob-trigger"
  }
}

# User-assigned managed identity for container access to storage
resource "azurerm_user_assigned_identity" "container_identity" {
  name                = "id-video-container-${random_string.suffix.result}"
  location            = azurerm_resource_group.video_workflow.location
  resource_group_name = azurerm_resource_group.video_workflow.name

  tags = merge(var.tags, {
    Component = "identity"
    Purpose   = "container-access"
  })
}

# Role assignment for container identity to access storage
resource "azurerm_role_assignment" "container_storage_access" {
  scope                = azurerm_storage_account.video_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.container_identity.principal_id
}

# Container Group for video processing (template - actual instances created by Logic App)
# This serves as a template configuration for dynamic container creation
locals {
  # FFmpeg processing script embedded in container environment
  ffmpeg_script = base64encode(<<-EOF
#!/bin/bash
set -e

# Environment variables passed from Logic App
INPUT_URL=$1
OUTPUT_CONTAINER="output-videos"
STORAGE_ACCOUNT="${azurerm_storage_account.video_storage.name}"

# Create temporary directories
mkdir -p /tmp/processing/{input,output}

echo "Starting video processing for: $INPUT_URL"

# Download input video
INPUT_FILE="/tmp/processing/input/$(basename $INPUT_URL)"
OUTPUT_BASE="/tmp/processing/output/$(basename $INPUT_URL .mp4)"

curl -H "Authorization: Bearer $AZURE_CLIENT_SECRET" -o "$INPUT_FILE" "$INPUT_URL"

# Process video in multiple formats and resolutions
for format in ${join(" ", var.video_formats)}; do
  for resolution in ${join(" ", var.video_resolutions)}; do
    case $resolution in
      "480p") scale="854:480" ;;
      "720p") scale="1280:720" ;;
      "1080p") scale="1920:1080" ;;
      "4k") scale="3840:2160" ;;
    esac
    
    OUTPUT_FILE="$OUTPUT_BASE-$resolution.$format"
    
    echo "Processing $resolution $format..."
    
    case $format in
      "mp4")
        ffmpeg -i "$INPUT_FILE" \
          -vcodec libx264 -acodec aac \
          -vf scale=$scale \
          -crf 23 -preset medium \
          "/tmp/processing/output/$OUTPUT_FILE"
        ;;
      "webm")
        ffmpeg -i "$INPUT_FILE" \
          -vcodec libvpx-vp9 -acodec libopus \
          -vf scale=$scale \
          -crf 30 -b:v 0 \
          "/tmp/processing/output/$OUTPUT_FILE"
        ;;
    esac
    
    # Upload to storage using Azure CLI
    az storage blob upload \
      --file "/tmp/processing/output/$OUTPUT_FILE" \
      --container-name "$OUTPUT_CONTAINER" \
      --name "$OUTPUT_FILE" \
      --account-name "$STORAGE_ACCOUNT" \
      --auth-mode login
      
    echo "Uploaded: $OUTPUT_FILE"
  done
done

echo "Video processing completed successfully"
EOF
  )
}

# Azure CDN Profile for video distribution (optional)
resource "azurerm_cdn_profile" "video_cdn" {
  count = var.enable_cdn ? 1 : 0
  
  name                = "cdn-video-${random_string.suffix.result}"
  location            = azurerm_resource_group.video_workflow.location
  resource_group_name = azurerm_resource_group.video_workflow.name
  sku                 = "Standard_Microsoft"

  tags = merge(var.tags, {
    Component = "cdn"
    Purpose   = "video-distribution"
  })
}

# CDN Endpoint for output video container
resource "azurerm_cdn_endpoint" "video_distribution" {
  count = var.enable_cdn ? 1 : 0
  
  name                = "cdn-videos-${random_string.suffix.result}"
  profile_name        = azurerm_cdn_profile.video_cdn[0].name
  location            = azurerm_resource_group.video_workflow.location
  resource_group_name = azurerm_resource_group.video_workflow.name

  origin {
    name      = "video-storage"
    host_name = azurerm_storage_account.video_storage.primary_blob_host
  }

  # Optimize for large file delivery
  optimization_type = "LargeFileDownload"
  
  # Configure caching rules for video content
  delivery_rule {
    name  = "video-caching"
    order = 1

    cache_expiration_action {
      behavior = "SetIfMissing"
      duration = "1.00:00:00"  # 1 day cache
    }

    request_uri_condition {
      operator     = "Contains"
      match_values = [".mp4", ".webm"]
    }
  }

  tags = merge(var.tags, {
    Component = "cdn-endpoint"
    Purpose   = "video-delivery"
  })
}

# Action Group for notifications (if email provided)
resource "azurerm_monitor_action_group" "video_notifications" {
  count = var.notification_email != "" ? 1 : 0
  
  name                = "ag-video-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.video_workflow.name
  short_name          = "videoalert"

  email_receiver {
    name          = "admin"
    email_address = var.notification_email
  }

  tags = merge(var.tags, {
    Component = "monitoring"
    Purpose   = "notifications"
  })
}
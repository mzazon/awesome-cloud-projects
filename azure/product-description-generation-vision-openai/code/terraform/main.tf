# Azure Product Description Generation with AI Vision and OpenAI - Main Terraform Configuration
# This configuration creates a complete serverless AI pipeline for generating product descriptions
# from uploaded images using Azure AI Vision and OpenAI services

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_string.suffix.result
  
  # Resource names following Azure naming conventions
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  function_app_name    = "func-${var.project_name}-${var.environment}-${local.resource_suffix}"
  computer_vision_name = "cv-${var.project_name}-${var.environment}-${local.resource_suffix}"
  openai_name         = "oai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_insights_name   = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  service_plan_name   = "asp-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags for all resources
  common_tags = merge(var.common_tags, {
    environment        = var.environment
    project           = var.project_name
    terraform_managed = "true"
    created_date      = timestamp()
  })
}

# Azure Resource Group - Container for all solution resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    ignore_changes = [tags["created_date"]]
  }
}

# Storage Account - Provides blob storage for images and generated descriptions
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_access_tier
  
  # Enable advanced security features
  enable_https_traffic_only       = true
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties for versioning and change feed
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
    change_feed_enabled = true
  }
  
  tags = local.common_tags
}

# Storage Container for Product Images - Input container for image uploads
resource "azurerm_storage_container" "input" {
  name                  = var.input_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Storage Container for Generated Descriptions - Output container for AI-generated content
resource "azurerm_storage_container" "output" {
  name                  = var.output_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Storage Lifecycle Management - Automated cost optimization through tiering
resource "azurerm_storage_management_policy" "lifecycle" {
  count              = var.enable_storage_lifecycle_management ? 1 : 0
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "cost-optimization-rule"
    enabled = true
    
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${var.input_container_name}/", "${var.output_container_name}/"]
    }
    
    actions {
      base_blob {
        # Transition to cool tier for cost savings
        tier_to_cool_after_days_since_modification_greater_than = var.cool_tier_transition_days
        
        # Optionally delete old files to control storage costs
        dynamic "delete_after_days_since_modification_greater_than" {
          for_each = var.delete_after_days > 0 ? [var.delete_after_days] : []
          content {
            delete_after_days_since_modification_greater_than = var.delete_after_days
          }
        }
      }
    }
  }
}

# Computer Vision Service - Azure AI Vision for image analysis
resource "azurerm_cognitive_account" "computer_vision" {
  name                = local.computer_vision_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ComputerVision"
  sku_name            = var.computer_vision_sku
  
  # Enable custom subdomain for enhanced security
  custom_subdomain_name = local.computer_vision_name
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    ip_rules       = []
  }
  
  tags = local.common_tags
}

# OpenAI Service - Azure OpenAI for natural language generation
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku
  
  # Enable custom subdomain for API access
  custom_subdomain_name = local.openai_name
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    ip_rules       = []
  }
  
  tags = local.common_tags
}

# OpenAI Model Deployment - Deploy GPT model for text generation
resource "azurerm_cognitive_deployment" "gpt_model" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  sku {
    name     = "Standard"
    capacity = var.openai_deployment_sku_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Application Insights - Monitoring and telemetry for the Function App
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "other"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Log Analytics Workspace - Backend for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# App Service Plan - Hosting plan for the Function App
resource "azurerm_service_plan" "main" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App - Serverless compute for AI processing pipeline
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage account for function app metadata
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Enable system-assigned managed identity for secure access to Azure services
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }
  
  # Function app configuration
  site_config {
    # Runtime configuration
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Performance and scaling settings
    always_on                              = var.function_app_service_plan_sku != "Y1"
    use_32_bit_worker                     = false
    ftps_state                            = "Disabled"
    http2_enabled                         = true
    minimum_tls_version                   = "1.2"
    scm_minimum_tls_version              = "1.2"
    
    # CORS configuration for web applications
    cors {
      allowed_origins = var.allowed_origins
    }
  }
  
  # Application settings with secure connection strings and API keys
  app_settings = {
    # Runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"        = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"     = "~4"
    "PYTHON_ENABLE_WORKER_EXTENSIONS" = "1"
    
    # AI Service endpoints and keys
    "VISION_ENDPOINT"    = azurerm_cognitive_account.computer_vision.endpoint
    "VISION_KEY"         = azurerm_cognitive_account.computer_vision.primary_access_key
    "OPENAI_ENDPOINT"    = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"         = azurerm_cognitive_account.openai.primary_access_key
    "OPENAI_MODEL_NAME"  = var.openai_model_name
    
    # Storage configuration
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    "INPUT_CONTAINER"          = var.input_container_name
    "OUTPUT_CONTAINER"         = var.output_container_name
    
    # Performance and scaling configuration
    "WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT" = var.max_function_instances
    "AZURE_FUNCTIONS_ENVIRONMENT"               = var.environment
    "SCM_DO_BUILD_DURING_DEPLOYMENT"           = "true"
    
    # Application Insights integration
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_cognitive_account.computer_vision,
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.gpt_model
  ]
}

# Event Grid System Topic - Enables event-driven processing for blob uploads
resource "azurerm_eventgrid_system_topic" "storage_events" {
  count                  = var.enable_event_grid ? 1 : 0
  name                   = "eg-storage-${var.project_name}-${local.resource_suffix}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.main.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  
  tags = local.common_tags
}

# Event Grid Event Subscription - Routes storage events to Function App
resource "azurerm_eventgrid_event_subscription" "function_trigger" {
  count = var.enable_event_grid ? 1 : 0
  name  = "product-image-processor"
  scope = azurerm_storage_account.main.id
  
  # Configure Azure Function as the event destination
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/ProductDescriptionGenerator"
    max_events_per_batch             = 1
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Filter events to only process blob creation in the input container
  included_event_types = var.event_grid_included_event_types
  
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${var.input_container_name}/blobs/"
  }
  
  # Advanced filters to process only image files
  advanced_filter {
    string_contains {
      key    = "data.contentType"
      values = ["image/jpeg", "image/png", "image/gif", "image/bmp", "image/webp"]
    }
  }
  
  # Retry policy for failed event deliveries
  retry_policy {
    event_time_to_live    = 1440  # 24 hours
    max_delivery_attempts = 30
  }
  
  depends_on = [
    azurerm_eventgrid_system_topic.storage_events,
    azurerm_linux_function_app.main
  ]
}

# Role Assignment - Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_storage_access" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Role Assignment - Grant Function App access to Computer Vision
resource "azurerm_role_assignment" "function_vision_access" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_cognitive_account.computer_vision.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Role Assignment - Grant Function App access to OpenAI Service
resource "azurerm_role_assignment" "function_openai_access" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}
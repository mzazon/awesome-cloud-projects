# Simple File Compression with Azure Functions and Storage
# This Terraform configuration creates a serverless file compression solution
# that automatically compresses files uploaded to Azure Blob Storage using Azure Functions

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Data source to get current subscription information
data "azurerm_subscription" "current" {}

# ============================================================================
# RESOURCE GROUP
# ============================================================================

# Create resource group to contain all resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# ============================================================================
# STORAGE ACCOUNT AND CONTAINERS
# ============================================================================

# Create storage account for blob storage with optimal configuration
resource "azurerm_storage_account" "main" {
  name                = "${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Storage configuration
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_replication_type
  account_kind              = "StorageV2"
  access_tier               = var.storage_access_tier
  enable_https_traffic_only = var.enable_https_traffic_only
  min_tls_version           = var.min_tls_version

  # Security configuration
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  shared_access_key_enabled       = true

  # Network rules configuration
  network_rules {
    default_action = var.storage_network_default_action
    bypass         = var.bypass_network_rules
  }

  # Blob properties for versioning and change feed
  blob_properties {
    # Enable versioning for better data protection
    versioning_enabled = true
    
    # Enable change feed for Event Grid integration
    change_feed_enabled = true
    
    # Retention policy for change feed
    change_feed_retention_in_days = 7

    # CORS configuration for web access if needed
    cors_rule {
      allowed_origins    = var.blob_cors_allowed_origins
      allowed_methods    = var.blob_cors_allowed_methods
      allowed_headers    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 86400
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

# Create input container for raw files
resource "azurerm_storage_container" "input" {
  name                  = var.input_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.container_access_type

  depends_on = [azurerm_storage_account.main]
}

# Create output container for compressed files
resource "azurerm_storage_container" "output" {
  name                  = var.output_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = var.container_access_type

  depends_on = [azurerm_storage_account.main]
}

# ============================================================================
# MONITORING AND ANALYTICS
# ============================================================================

# Create Log Analytics workspace for monitoring (optional)
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0

  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = var.tags
}

# Create Application Insights for Function App monitoring (optional)
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0

  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  sampling_percentage = var.application_insights_sampling_percentage

  tags = var.tags
}

# ============================================================================
# FUNCTION APP INFRASTRUCTURE
# ============================================================================

# Create App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_os_type
  sku_name            = var.function_app_service_plan_sku

  tags = var.tags
}

# Create Function App with Python runtime
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  # Storage account configuration
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  # Enable system-assigned managed identity for secure access
  identity {
    type = "SystemAssigned"
  }

  # Function App configuration
  site_config {
    # Application stack configuration
    application_stack {
      python_version = var.function_runtime_version
    }

    # Enable Application Insights if monitoring is enabled
    application_insights_key               = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null

    # CORS configuration for development
    cors {
      allowed_origins = ["*"]
    }

    # Security headers
    use_32_bit_worker_process = false
    always_on                 = var.function_app_service_plan_sku != "Y1" # Disable for Consumption plan
  }

  # Application settings
  app_settings = merge({
    # Function runtime configuration
    "FUNCTIONS_EXTENSION_VERSION" = var.functions_extension_version
    "FUNCTIONS_WORKER_RUNTIME"    = var.function_runtime
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"

    # Storage connection strings for the function
    "AzureWebJobsStorage"         = azurerm_storage_account.main.primary_connection_string
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string

    # Container names for the function to use
    "INPUT_CONTAINER_NAME"        = azurerm_storage_container.input.name
    "OUTPUT_CONTAINER_NAME"       = azurerm_storage_container.output.name

    # Application Insights configuration
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : ""
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"

    # Python specific settings
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
    "PYTHON_ENABLE_WORKER_EXTENSIONS"    = "1"

    # Enable built-in logging
    "AzureWebJobsDashboard" = var.enable_builtin_logging ? azurerm_storage_account.main.primary_connection_string : ""
  }, var.function_app_settings)

  # Lifecycle management
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"]
    ]
  }

  tags = var.tags

  depends_on = [
    azurerm_storage_account.main,
    azurerm_storage_container.input,
    azurerm_storage_container.output,
    azurerm_application_insights.main
  ]
}

# ============================================================================
# RBAC ASSIGNMENTS FOR MANAGED IDENTITY
# ============================================================================

# Assign Storage Blob Data Contributor role to Function App's managed identity
# This allows the function to read from input container and write to output container
resource "azurerm_role_assignment" "function_storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# Assign Storage Queue Data Contributor role for internal function operations
resource "azurerm_role_assignment" "function_storage_queue_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# Assign Storage Table Data Contributor role for function state management
resource "azurerm_role_assignment" "function_storage_table_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# ============================================================================
# EVENT GRID CONFIGURATION
# ============================================================================

# Create Event Grid system topic for storage account events
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "evgt-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.main.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  tags = var.tags

  depends_on = [azurerm_storage_account.main]
}

# Create Event Grid subscription to trigger Function App
resource "azurerm_eventgrid_system_topic_event_subscription" "blob_events" {
  name                = "evgs-blob-compression-${random_string.suffix.result}"
  system_topic        = azurerm_eventgrid_system_topic.storage.name
  resource_group_name = azurerm_resource_group.main.name

  # Configure Azure Function as webhook endpoint
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/BlobTrigger"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  # Event filtering configuration
  included_event_types = var.event_grid_event_types

  # Subject filtering to only process events from input container
  subject_filter {
    subject_begins_with = var.event_grid_subject_filter_begins_with
    subject_ends_with   = var.event_grid_subject_filter_ends_with
  }

  # Advanced filtering for more precise event handling
  advanced_filter {
    string_begins_with {
      key    = "subject"
      values = ["/blobServices/default/containers/${var.input_container_name}/"]
    }
  }

  depends_on = [
    azurerm_eventgrid_system_topic.storage,
    azurerm_linux_function_app.main,
    azurerm_storage_container.input
  ]
}

# ============================================================================
# FUNCTION CODE DEPLOYMENT
# ============================================================================

# Create function code locally for deployment
resource "local_file" "function_code" {
  filename = "${path.module}/function_app.py"
  content  = <<-EOF
import logging
import gzip
import azure.functions as func

app = func.FunctionApp()

@app.blob_trigger(
    arg_name="inputblob",
    path="${var.input_container_name}/{name}",
    connection="STORAGE_CONNECTION_STRING",
    source="EventGrid"
)
@app.blob_output(
    arg_name="outputblob",
    path="${var.output_container_name}/{name}.gz",
    connection="STORAGE_CONNECTION_STRING"
)
def BlobTrigger(inputblob: func.InputStream, outputblob: func.Out[bytes]) -> None:
    """
    Compress uploaded files using gzip compression.
    
    This function is triggered by Event Grid when files are uploaded to the
    ${var.input_container_name} container. It compresses the files using gzip
    and stores them in the ${var.output_container_name} container.
    
    Args:
        inputblob: Input blob from ${var.input_container_name} container
        outputblob: Output blob to ${var.output_container_name} container
    """
    logging.info(f"Processing file: {inputblob.name}")
    
    try:
        # Read the input file content
        file_content = inputblob.read()
        logging.info(f"Read {len(file_content)} bytes from input file")
        
        # Validate file content
        if not file_content:
            logging.warning(f"File {inputblob.name} is empty, skipping compression")
            return
        
        # Compress the content using gzip
        compressed_content = gzip.compress(file_content)
        compression_ratio = len(compressed_content) / len(file_content)
        
        logging.info(f"Compressed to {len(compressed_content)} bytes "
                    f"(ratio: {compression_ratio:.2f})")
        
        # Write compressed content to output blob
        outputblob.set(compressed_content)
        
        # Log success with compression metrics
        space_saved = len(file_content) - len(compressed_content)
        space_saved_percent = (space_saved / len(file_content)) * 100
        
        logging.info(f"Successfully compressed {inputblob.name}. "
                    f"Space saved: {space_saved} bytes ({space_saved_percent:.1f}%)")
        
    except Exception as e:
        logging.error(f"Error compressing file {inputblob.name}: {str(e)}")
        # Re-raise the exception to trigger retry logic
        raise
EOF
}

# Create requirements.txt for function dependencies
resource "local_file" "function_requirements" {
  filename = "${path.module}/requirements.txt"
  content  = <<-EOF
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
EOF
}

# Create host.json for function app configuration
resource "local_file" "function_host_config" {
  filename = "${path.module}/host.json"
  content  = jsonencode({
    version = "2.0"
    logging = {
      applicationInsights = {
        samplingSettings = {
          isEnabled = var.enable_monitoring
          maxTelemetryItemsPerSecond = 20
        }
      }
    }
    functionTimeout = "00:10:00" # 10 minutes timeout for large file processing
    extensionBundle = {
      id      = "Microsoft.Azure.Functions.ExtensionBundle"
      version = "[4.*, 5.0.0)"
    }
    extensions = {
      eventGrid = {
        maxBatchSize = 1
      }
    }
  })
}

# Create deployment package for function code
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function.zip"
  
  source {
    content  = local_file.function_code.content
    filename = "function_app.py"
  }
  
  source {
    content  = local_file.function_requirements.content
    filename = "requirements.txt"
  }
  
  source {
    content  = local_file.function_host_config.content
    filename = "host.json"
  }
  
  depends_on = [
    local_file.function_code,
    local_file.function_requirements,
    local_file.function_host_config
  ]
}

# Deploy function code to Azure Function App
# Note: In practice, you would use CI/CD pipelines for code deployment
# This is included here for completeness of the infrastructure setup
resource "null_resource" "deploy_function" {
  # Trigger deployment when function code changes
  triggers = {
    function_code_hash = data.archive_file.function_code.output_base64sha256
    function_app_id    = azurerm_linux_function_app.main.id
  }

  # Deploy function code using Azure CLI
  provisioner "local-exec" {
    command = <<-EOT
      echo "Deploying function code to ${azurerm_linux_function_app.main.name}..."
      
      # Check if Azure CLI is available
      if ! command -v az &> /dev/null; then
        echo "Azure CLI is not installed. Please install it to deploy function code."
        exit 1
      fi
      
      # Deploy the function code
      az functionapp deployment source config-zip \
        --name "${azurerm_linux_function_app.main.name}" \
        --resource-group "${azurerm_resource_group.main.name}" \
        --src "${data.archive_file.function_code.output_path}" \
        --build-remote true
      
      echo "Function code deployment completed successfully!"
    EOT
  }

  depends_on = [
    azurerm_linux_function_app.main,
    data.archive_file.function_code,
    azurerm_role_assignment.function_storage_blob_contributor
  ]
}

# ============================================================================
# CLEANUP RESOURCES
# ============================================================================

# Clean up local files created during deployment
resource "null_resource" "cleanup_local_files" {
  # This runs when the resources are destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up local deployment files..."
      rm -f ${path.module}/function_app.py
      rm -f ${path.module}/requirements.txt
      rm -f ${path.module}/host.json
      rm -f ${path.module}/function.zip
      echo "Local cleanup completed."
    EOT
  }

  depends_on = [
    local_file.function_code,
    local_file.function_requirements,
    local_file.function_host_config,
    data.archive_file.function_code
  ]
}
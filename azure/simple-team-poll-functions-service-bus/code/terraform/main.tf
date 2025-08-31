# main.tf
# Main Terraform configuration for Simple Team Poll System with Azure Functions and Service Bus

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming
  resource_suffix = random_id.suffix.hex
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Service Bus resources
  service_bus_namespace_name = "sb-${var.project_name}-${local.resource_suffix}"
  service_bus_queue_name     = "votes"
  
  # Storage resources
  storage_account_name = "${var.project_name}${var.environment}${local.resource_suffix}"
  
  # Function App resources
  function_app_name         = "func-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name     = "asp-${var.project_name}-${local.resource_suffix}"
  application_insights_name = "ai-${var.project_name}-${local.resource_suffix}"
  
  # Merged tags
  common_tags = merge(var.tags, {
    ManagedBy     = "Terraform"
    ResourceGroup = local.resource_group_name
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group
# Central container for all poll system resources
resource "azurerm_resource_group" "poll_system" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Service Bus Namespace
# Provides enterprise messaging capabilities for reliable vote processing
resource "azurerm_servicebus_namespace" "poll_namespace" {
  name                = local.service_bus_namespace_name
  location            = azurerm_resource_group.poll_system.location
  resource_group_name = azurerm_resource_group.poll_system.name
  sku                 = var.service_bus_sku
  
  # Premium SKU specific configuration
  capacity                   = var.service_bus_sku == "Premium" ? 1 : null
  premium_messaging_partitions = var.service_bus_sku == "Premium" ? 1 : null
  
  tags = local.common_tags
}

# Service Bus Queue
# Durable message queue for vote submissions with automatic retry capabilities
resource "azurerm_servicebus_queue" "votes_queue" {
  name         = local.service_bus_queue_name
  namespace_id = azurerm_servicebus_namespace.poll_namespace.id
  
  # Queue configuration for reliable message processing
  max_size_in_megabytes                = var.service_bus_queue_max_size_in_megabytes
  default_message_ttl                  = "P14D"  # 14 days
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes
  
  # Enable dead letter queue for failed message handling
  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 10
  
  # Enable duplicate detection to prevent duplicate vote processing
  requires_duplicate_detection = true
  
  depends_on = [azurerm_servicebus_namespace.poll_namespace]
}

# Storage Account
# Required for Azure Functions runtime and serves as vote results storage
resource "azurerm_storage_account" "poll_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.poll_system.name
  location                 = azurerm_resource_group.poll_system.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security and access configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning for data protection
  blob_properties {
    versioning_enabled = true
    
    # Configure container soft delete
    container_delete_retention_policy {
      days = 7
    }
    
    # Configure blob soft delete  
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage Container for Poll Results
# Dedicated container for storing poll results as JSON blobs
resource "azurerm_storage_container" "poll_results" {
  name                  = "poll-results"
  storage_account_name  = azurerm_storage_account.poll_storage.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.poll_storage]
}

# Application Insights
# Provides monitoring, logging, and performance insights for Function App
resource "azurerm_application_insights" "poll_insights" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.poll_system.location
  resource_group_name = azurerm_resource_group.poll_system.name
  application_type    = "web"
  
  # Retention configuration
  retention_in_days = 30
  
  tags = local.common_tags
}

# App Service Plan
# Defines the hosting plan for Azure Functions (Consumption plan for cost optimization)
resource "azurerm_service_plan" "poll_plan" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.poll_system.name
  location            = azurerm_resource_group.poll_system.location
  
  # Use consumption plan for automatic scaling and pay-per-execution pricing
  os_type  = "Linux"
  sku_name = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App
# Serverless compute platform hosting the poll system APIs and processors
resource "azurerm_linux_function_app" "poll_functions" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.poll_system.name
  location            = azurerm_resource_group.poll_system.location
  
  service_plan_id            = azurerm_service_plan.poll_plan.id
  storage_account_name       = azurerm_storage_account.poll_storage.name
  storage_account_access_key = azurerm_storage_account.poll_storage.primary_access_key
  
  # Function App configuration
  site_config {
    # Runtime configuration
    application_stack {
      node_version = var.node_version
    }
    
    # CORS configuration for web browser access
    dynamic "cors" {
      for_each = var.enable_cors ? [1] : []
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
    
    # Security headers
    http2_enabled = true
    
    # Application insights integration
    application_insights_key               = azurerm_application_insights.poll_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.poll_insights.connection_string
  }
  
  # Application settings for Function App runtime and integrations
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~${var.node_version}"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    
    # Service Bus connection for triggers and bindings
    "ServiceBusConnection" = azurerm_servicebus_namespace.poll_namespace.default_primary_connection_string
    
    # Storage connection for poll results storage
    "AzureWebJobsStorage" = azurerm_storage_account.poll_storage.primary_connection_string
    
    # Application Insights for monitoring and logging
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.poll_insights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.poll_insights.connection_string
    
    # Function timeout configuration
    "FUNCTION_TIMEOUT" = "00:0${var.function_timeout_minutes}:00"
    
    # Enable Application Insights monitoring
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
  }
  
  # Identity configuration for Azure AD integration (if needed for future enhancements)
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_service_plan.poll_plan,
    azurerm_storage_account.poll_storage,
    azurerm_servicebus_namespace.poll_namespace,
    azurerm_application_insights.poll_insights
  ]
}

# Function App Function: Vote Submission
# HTTP-triggered function for receiving and queuing vote submissions
resource "azurerm_function_app_function" "submit_vote" {
  name            = "SubmitVote"
  function_app_id = azurerm_linux_function_app.poll_functions.id
  language        = "Javascript"
  
  # Function configuration with HTTP trigger and Service Bus output binding
  config_json = jsonencode({
    bindings = [
      {
        authLevel = "anonymous"
        type      = "httpTrigger"
        direction = "in"
        name      = "req"
        methods   = ["post"]
      },
      {
        type      = "http"
        direction = "out"
        name      = "res"
      },
      {
        type       = "serviceBus"
        direction  = "out"
        name       = "outputSbMsg"
        queueName  = local.service_bus_queue_name
        connection = "ServiceBusConnection"
      }
    ]
  })
  
  # Function implementation for vote submission processing
  file {
    name    = "index.js"
    content = <<-EOT
      module.exports = async function (context, req) {
          try {
              const { pollId, option, voterId } = req.body;
              
              // Validate required fields
              if (!pollId || !option || !voterId) {
                  context.res = {
                      status: 400,
                      headers: {
                          'Content-Type': 'application/json',
                          'Access-Control-Allow-Origin': '*'
                      },
                      body: { error: "Missing required fields: pollId, option, voterId" }
                  };
                  return;
              }
              
              // Create vote message with unique identifier
              const vote = {
                  pollId,
                  option,
                  voterId,
                  timestamp: new Date().toISOString(),
                  id: `$${pollId}-$${voterId}-$${Date.now()}`
              };
              
              // Queue vote for processing via Service Bus
              context.bindings.outputSbMsg = vote;
              
              // Return success response
              context.res = {
                  status: 202,
                  headers: {
                      'Content-Type': 'application/json',
                      'Access-Control-Allow-Origin': '*'
                  },
                  body: { 
                      message: "Vote submitted successfully",
                      voteId: vote.id
                  }
              };
              
              context.log(`Vote submitted for poll $${pollId}: $${option} by $${voterId}`);
              
          } catch (error) {
              context.log.error('Error submitting vote:', error);
              context.res = {
                  status: 500,
                  headers: {
                      'Content-Type': 'application/json',
                      'Access-Control-Allow-Origin': '*'
                  },
                  body: { error: "Internal server error" }
              };
          }
      };
    EOT
  }
  
  depends_on = [azurerm_linux_function_app.poll_functions]
}

# Function App Function: Vote Processing
# Service Bus-triggered function for processing queued votes and updating results
resource "azurerm_function_app_function" "process_vote" {
  name            = "ProcessVote"
  function_app_id = azurerm_linux_function_app.poll_functions.id
  language        = "Javascript"
  
  # Function configuration with Service Bus trigger and Blob output binding
  config_json = jsonencode({
    bindings = [
      {
        name       = "mySbMsg"
        type       = "serviceBusTrigger"
        direction  = "in"
        queueName  = local.service_bus_queue_name
        connection = "ServiceBusConnection"
      },
      {
        name       = "outputBlob"
        type       = "blob"
        direction  = "out"
        path       = "poll-results/{pollId}.json"
        connection = "AzureWebJobsStorage"
      }
    ]
  })
  
  # Function implementation for vote processing and result aggregation
  file {
    name    = "index.js"
    content = <<-EOT
      module.exports = async function (context, mySbMsg) {
          try {
              const vote = mySbMsg;
              const { pollId, option, voterId } = vote;
              
              context.log(`Processing vote for poll $${pollId}: $${option} by $${voterId}`);
              
              // Initialize or load existing poll results
              let results = {};
              try {
                  const { BlobServiceClient } = require('@azure/storage-blob');
                  const blobServiceClient = BlobServiceClient.fromConnectionString(
                      process.env.AzureWebJobsStorage
                  );
                  const containerClient = blobServiceClient.getContainerClient('poll-results');
                  
                  // Ensure container exists
                  await containerClient.createIfNotExists();
                  
                  const blobClient = containerClient.getBlobClient(`$${pollId}.json`);
                  
                  // Load existing results if available
                  if (await blobClient.exists()) {
                      const downloadResponse = await blobClient.download();
                      const downloaded = await streamToString(downloadResponse.readableStreamBody);
                      results = JSON.parse(downloaded);
                  }
              } catch (error) {
                  context.log('No existing results found, creating new poll results');
              }
              
              // Initialize poll structure for new polls
              if (!results.pollId) {
                  results = {
                      pollId,
                      totalVotes: 0,
                      options: {},
                      voters: new Set(),
                      lastUpdated: new Date().toISOString()
                  };
              }
              
              // Convert voters back to Set if it was serialized as array
              results.voters = new Set(results.voters);
              
              // Process vote if not duplicate (prevent double voting)
              if (!results.voters.has(voterId)) {
                  results.voters.add(voterId);
                  results.options[option] = (results.options[option] || 0) + 1;
                  results.totalVotes++;
                  results.lastUpdated = new Date().toISOString();
                  
                  // Convert Set back to Array for JSON serialization
                  const outputResults = {
                      ...results,
                      voters: Array.from(results.voters)
                  };
                  
                  // Update poll results in blob storage
                  context.bindings.outputBlob = JSON.stringify(outputResults, null, 2);
                  context.log(`Vote processed for poll $${pollId}: $${option} by $${voterId}. Total votes: $${results.totalVotes}`);
              } else {
                  context.log(`Duplicate vote ignored for poll $${pollId} by $${voterId}`);
              }
              
          } catch (error) {
              context.log.error('Error processing vote:', error);
              throw error; // Let Service Bus handle retry logic
          }
      };
      
      // Helper function to convert readable stream to string
      async function streamToString(readableStream) {
          return new Promise((resolve, reject) => {
              const chunks = [];
              readableStream.on('data', (data) => {
                  chunks.push(data.toString());
              });
              readableStream.on('end', () => {
                  resolve(chunks.join(''));
              });
              readableStream.on('error', reject);
          });
      }
    EOT
  }
  
  depends_on = [azurerm_linux_function_app.poll_functions]
}

# Function App Function: Get Results
# HTTP-triggered function for retrieving poll results with real-time data
resource "azurerm_function_app_function" "get_results" {
  name            = "GetResults"
  function_app_id = azurerm_linux_function_app.poll_functions.id
  language        = "Javascript"
  
  # Function configuration with HTTP trigger and Blob input binding
  config_json = jsonencode({
    bindings = [
      {
        authLevel = "anonymous"
        type      = "httpTrigger"
        direction = "in"
        name      = "req"
        methods   = ["get"]
        route     = "results/{pollId}"
      },
      {
        type      = "http"
        direction = "out"
        name      = "res"
      },
      {
        name       = "inputBlob"
        type       = "blob"
        direction  = "in"
        path       = "poll-results/{pollId}.json"
        connection = "AzureWebJobsStorage"
      }
    ]
  })
  
  # Function implementation for results retrieval with percentage calculations
  file {
    name    = "index.js"
    content = <<-EOT
      module.exports = async function (context, req) {
          try {
              const pollId = context.bindingData.pollId;
              
              // Check if poll results exist
              if (!context.bindings.inputBlob) {
                  context.res = {
                      status: 404,
                      headers: {
                          'Content-Type': 'application/json',
                          'Access-Control-Allow-Origin': '*'
                      },
                      body: { error: `Poll $${pollId} not found` }
                  };
                  return;
              }
              
              // Parse poll results from storage
              const results = JSON.parse(context.bindings.inputBlob);
              
              // Calculate vote percentages for each option
              const optionsWithPercentages = {};
              Object.keys(results.options).forEach(option => {
                  const count = results.options[option];
                  const percentage = results.totalVotes > 0 
                      ? Math.round((count / results.totalVotes) * 100) 
                      : 0;
                  optionsWithPercentages[option] = {
                      count,
                      percentage
                  };
              });
              
              // Return formatted poll results
              context.res = {
                  status: 200,
                  headers: {
                      'Content-Type': 'application/json',
                      'Access-Control-Allow-Origin': '*',
                      'Cache-Control': 'no-cache, no-store, must-revalidate'
                  },
                  body: {
                      pollId: results.pollId,
                      totalVotes: results.totalVotes,
                      options: optionsWithPercentages,
                      lastUpdated: results.lastUpdated
                  }
              };
              
              context.log(`Results retrieved for poll $${pollId}: $${results.totalVotes} total votes`);
              
          } catch (error) {
              context.log.error('Error retrieving poll results:', error);
              context.res = {
                  status: 500,
                  headers: {
                      'Content-Type': 'application/json',
                      'Access-Control-Allow-Origin': '*'
                  },
                  body: { error: "Error retrieving poll results" }
              };
          }
      };
    EOT
  }
  
  depends_on = [azurerm_linux_function_app.poll_functions]
}

# Package.json for Function App dependencies
# Defines Node.js dependencies required by the poll functions
resource "azurerm_function_app_function" "package_json" {
  name            = "package"
  function_app_id = azurerm_linux_function_app.poll_functions.id
  language        = "Javascript"
  
  # Minimal function configuration (required by provider)
  config_json = jsonencode({
    bindings = []
  })
  
  # Package.json with Azure Storage Blob SDK dependency
  file {
    name    = "package.json"
    content = jsonencode({
      name = "poll-functions"
      version = "1.0.0"
      description = "Simple Team Poll System Functions"
      main = "index.js"
      dependencies = {
        "@azure/storage-blob" = "^12.28.0"
      }
      engines = {
        node = "~${var.node_version}"
      }
    })
  }
  
  depends_on = [azurerm_linux_function_app.poll_functions]
}

# Host.json for Function App runtime configuration
# Configures Function App runtime behavior and Service Bus settings
resource "azurerm_function_app_function" "host_json" {
  name            = "host"
  function_app_id = azurerm_linux_function_app.poll_functions.id
  language        = "Javascript"
  
  # Minimal function configuration (required by provider)
  config_json = jsonencode({
    bindings = []
  })
  
  # Host.json with optimized runtime configuration
  file {
    name    = "host.json"
    content = jsonencode({
      version = "2.0"
      functionTimeout = "00:0${var.function_timeout_minutes}:00"
      extensions = {
        serviceBus = {
          prefetchCount = 100
          autoCompleteMessages = true
          maxConcurrentCalls = 16
        }
        http = {
          routePrefix = "api"
        }
      }
      logging = {
        applicationInsights = {
          samplingSettings = {
            isEnabled = true
            maxTelemetryItemsPerSecond = 20
          }
        }
      }
    })
  }
  
  depends_on = [azurerm_linux_function_app.poll_functions]
}
# Main Terraform configuration for Azure intelligent model selection architecture
# This configuration deploys Event Grid, Azure Functions, AI Foundry, and Application Insights

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.resource_tags
}

# Create Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  # Security configuration
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = var.enable_public_network_access
  allow_nested_items_to_be_public = false

  # Enable blob encryption
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.resource_tags, {
    Component = "Storage"
  })
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = var.application_insights_type
  retention_in_days   = var.application_insights_retention_days

  # Enable daily quota if specified
  dynamic "daily_data_cap" {
    for_each = var.enable_daily_quota ? [1] : []
    content {
      daily_data_cap_in_gb                  = var.daily_quota_gb
      daily_data_cap_notifications_disabled = false
    }
  }

  tags = merge(var.resource_tags, {
    Component = "Monitoring"
  })
}

# Create Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.application_insights_retention_days

  tags = merge(var.resource_tags, {
    Component = "Analytics"
  })
}

# Create Service Plan for Function App (Consumption plan)
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_os_type
  sku_name            = "Y1" # Consumption plan

  tags = merge(var.resource_tags, {
    Component = "Compute"
  })
}

# Create Function App
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan.id

  # Configure runtime and Application Insights
  site_config {
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string

    application_stack {
      python_version = var.function_app_runtime_version
    }

    # Enable CORS for all origins (modify as needed for production)
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
  }

  # Configure application settings
  app_settings = merge(var.function_app_settings, {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "AI_FOUNDRY_ENDPOINT"                  = azurerm_cognitive_account.ai_foundry.endpoint
    "AI_FOUNDRY_KEY"                       = azurerm_cognitive_account.ai_foundry.primary_access_key
    "MODEL_DEPLOYMENT_NAME"                = var.model_deployment_name
    "EVENT_GRID_ENDPOINT"                  = azurerm_eventgrid_topic.main.endpoint
    "EVENT_GRID_KEY"                       = azurerm_eventgrid_topic.main.primary_access_key
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.function_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE"                     = "${var.project_name}-${var.environment}-content"
  })

  # Configure identity for secure access to other resources
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.resource_tags, {
    Component = "Function"
  })

  # Ensure dependencies are created first
  depends_on = [
    azurerm_application_insights.main,
    azurerm_cognitive_account.ai_foundry,
    azurerm_eventgrid_topic.main
  ]
}

# Create Event Grid Topic for AI request orchestration
resource "azurerm_eventgrid_topic" "main" {
  name                = "egt-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = var.event_grid_input_schema

  # Configure public network access
  public_network_access_enabled = var.enable_public_network_access

  # Configure IP filtering if specified
  dynamic "input_mapping_fields" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      topic    = "topic"
      subject  = "subject"
    }
  }

  tags = merge(var.resource_tags, {
    Component = "EventGrid"
  })
}

# Create Azure AI Foundry (Cognitive Services) resource
resource "azurerm_cognitive_account" "ai_foundry" {
  name                  = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "AIServices"
  sku_name              = var.ai_foundry_sku
  custom_subdomain_name = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"

  # Enable identity for secure access
  identity {
    type = "SystemAssigned"
  }

  # Configure network access
  public_network_access_enabled = var.enable_public_network_access

  # Configure IP restrictions if specified
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      dynamic "ip_rules" {
        for_each = var.allowed_ip_ranges
        content {
          ip_range = ip_rules.value
        }
      }
    }
  }

  tags = merge(var.resource_tags, {
    Component = "AI"
  })
}

# Create Model Router deployment in Azure AI Foundry
resource "azurerm_cognitive_deployment" "model_router" {
  name                 = var.model_deployment_name
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id

  model {
    format  = "OpenAI"
    name    = var.model_name
    version = var.model_version
  }

  scale {
    type     = "Standard"
    capacity = var.model_sku_capacity
  }

  rai_policy_name = null

  tags = merge(var.resource_tags, {
    Component = "AIModel"
  })
}

# Create Event Grid subscription to connect with Function App
resource "azurerm_eventgrid_event_subscription" "function_subscription" {
  name  = "ai-router-subscription"
  scope = azurerm_eventgrid_topic.main.id

  # Configure Azure Function endpoint
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/router_function"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  # Configure event types to include
  included_event_types = var.event_subscription_included_event_types

  # Configure retry policy
  retry_policy {
    max_delivery_attempts = var.event_subscription_retry_policy.max_delivery_attempts
    event_time_to_live    = var.event_subscription_retry_policy.event_time_to_live
  }

  # Configure delivery properties
  delivery_identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_eventgrid_topic.main
  ]
}

# Create Function App deployment with intelligent routing code
resource "null_resource" "function_deployment" {
  # Create function code files
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/function_code
      
      # Create function_app.py with intelligent routing logic
      cat > ${path.module}/function_code/function_app.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from datetime import datetime, timezone
import requests
from azure.eventgrid import EventGridPublisherClient
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI

app = func.FunctionApp()

# Initialize AI client
try:
    ai_client = AzureOpenAI(
        api_key=os.environ.get("AI_FOUNDRY_KEY", ""),
        api_version="2024-02-01",
        azure_endpoint=os.environ.get("AI_FOUNDRY_ENDPOINT", "")
    )
except Exception as e:
    logging.error(f"Failed to initialize AI client: {str(e)}")
    ai_client = None

@app.event_grid_trigger(arg_name="azeventgrid")
def router_function(azeventgrid: func.EventGridEvent):
    """Intelligent AI request router using Model Router"""
    
    logging.info(f"Processing Event Grid event: {azeventgrid.event_type}")
    
    try:
        # Extract request data from event
        event_data = azeventgrid.get_json()
        user_prompt = event_data.get("prompt", "")
        request_id = event_data.get("request_id", "unknown")
        
        # Analyze request complexity
        complexity_score = analyze_complexity(user_prompt)
        
        # Route through Model Router if AI client is available
        if ai_client:
            response = ai_client.chat.completions.create(
                model=os.environ.get("MODEL_DEPLOYMENT_NAME", "model-router-deployment"),
                messages=[
                    {"role": "system", "content": "You are a helpful AI assistant."},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.7,
                max_tokens=1000
            )
            
            # Extract selected model from response
            selected_model = response.model
            response_content = response.choices[0].message.content
            
        else:
            # Fallback response if AI client is not available
            selected_model = "fallback"
            response_content = f"AI routing service is currently unavailable. Request complexity score: {complexity_score}"
        
        # Log routing decision
        logging.info(f"Request {request_id}: Complexity {complexity_score}, Selected model: {selected_model}")
        
        # Publish monitoring event
        publish_monitoring_event(request_id, complexity_score, selected_model, len(response_content))
        
        return {
            "request_id": request_id,
            "selected_model": selected_model,
            "response": response_content,
            "complexity_score": complexity_score
        }
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return {
            "error": str(e),
            "request_id": event_data.get("request_id", "unknown") if 'event_data' in locals() else "unknown"
        }

def analyze_complexity(prompt: str) -> float:
    """Analyze prompt complexity for routing decisions"""
    
    if not prompt:
        return 0.0
    
    # Basic complexity indicators
    complexity_indicators = [
        len(prompt.split()) > 100,  # Long prompts
        "analyze" in prompt.lower() or "reasoning" in prompt.lower(),
        "calculate" in prompt.lower() or "compute" in prompt.lower(),
        "explain" in prompt.lower() and "detail" in prompt.lower(),
        prompt.count("?") > 2,  # Multiple questions
    ]
    
    return sum(complexity_indicators) / len(complexity_indicators)

def publish_monitoring_event(request_id: str, complexity: float, model: str, response_length: int):
    """Publish monitoring metrics to Event Grid"""
    
    try:
        event_data = {
            "request_id": request_id,
            "complexity_score": complexity,
            "selected_model": model,
            "response_length": response_length,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        # Log monitoring data (in production, this would publish to a monitoring topic)
        logging.info(f"Monitoring data: {json.dumps(event_data)}")
        
    except Exception as e:
        logging.warning(f"Failed to publish monitoring event: {str(e)}")

@app.function_name(name="health_check")
@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint"""
    return func.HttpResponse("Healthy", status_code=200)
EOF

      # Create requirements.txt
      cat > ${path.module}/function_code/requirements.txt << 'EOF'
azure-functions
azure-eventgrid>=4.9.0
openai>=1.12.0
requests>=2.31.0
azure-core>=1.28.0
EOF

      # Create host.json for function configuration
      cat > ${path.module}/function_code/host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "eventGrid": {
      "maxBatchSize": 1
    }
  },
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  }
}
EOF

      # Create .funcignore file
      cat > ${path.module}/function_code/.funcignore << 'EOF'
.git*
.vscode
local.settings.json
test
.venv
EOF

      # Create deployment package
      cd ${path.module}/function_code
      zip -r ../function.zip .
      cd ..
    EOT
  }

  # Deploy function code using Azure CLI
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Function App to be ready
      sleep 30
      
      # Deploy function code
      az functionapp deployment source config-zip \
        --name ${azurerm_linux_function_app.main.name} \
        --resource-group ${azurerm_resource_group.main.name} \
        --src ${path.module}/function.zip \
        --timeout 600
    EOT
  }

  # Clean up temporary files
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -rf ${path.module}/function_code
      rm -f ${path.module}/function.zip
    EOT
  }

  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_cognitive_deployment.model_router
  ]

  triggers = {
    function_app_id = azurerm_linux_function_app.main.id
    deployment_hash = filebase64sha256("${path.module}/main.tf")
  }
}

# Grant Function App access to AI Foundry resource
resource "azurerm_role_assignment" "function_to_ai" {
  scope                = azurerm_cognitive_account.ai_foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Event Grid topic
resource "azurerm_role_assignment" "function_to_eventgrid" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_to_storage" {
  scope                = azurerm_storage_account.function_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}
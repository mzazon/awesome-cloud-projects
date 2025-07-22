# Main Terraform configuration for Serverless AI Agents with Azure OpenAI Service and Container Instances

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for resource naming and configuration
locals {
  # Generate unique resource names
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${random_string.suffix.result}"
  
  # Common resource naming pattern
  common_tags = merge(var.tags, {
    CreatedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Resource names with consistent naming convention
  openai_name           = "oai-${var.project_name}-${random_string.suffix.result}"
  storage_account_name  = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  container_registry_name = "cr${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  event_grid_topic_name = "egt-${var.project_name}-${random_string.suffix.result}"
  function_app_name     = "func-${var.project_name}-${random_string.suffix.result}"
  app_insights_name     = "appi-${var.project_name}-${random_string.suffix.result}"
  logic_app_name        = "logic-${var.project_name}-${random_string.suffix.result}"
  
  # Container configuration
  container_image_name = "ai-agent"
  container_image_tag  = "latest"
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Storage Account for state management and results
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning for better data management
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create container for storing AI agent results
resource "azurerm_storage_container" "results" {
  name                  = "results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Create Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku
  
  # Custom subdomain is required for OpenAI
  custom_subdomain_name = local.openai_name
  
  # Security configurations
  public_network_access_enabled = true
  
  # Identity configuration for managed service identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Deploy GPT-4 model to OpenAI service
resource "azurerm_cognitive_deployment" "gpt4" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  scale {
    type = "Standard"
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Create Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.enable_container_registry_admin
  
  # Enable vulnerability scanning for Premium SKU
  dynamic "retention_policy" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      days    = 7
      enabled = true
    }
  }
  
  tags = local.common_tags
}

# Create Event Grid Topic for event orchestration
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  input_schema = var.event_grid_topic_input_schema
  
  tags = local.common_tags
}

# Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  # Retention settings
  retention_in_days = 30
  
  tags = local.common_tags
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Create Function App for API Gateway
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration for web apps
    cors {
      allowed_origins = ["*"]
    }
    
    # Application settings
    application_insights_key               = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  }
  
  # Application settings for Function App
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "EVENTGRID_ENDPOINT"          = azurerm_eventgrid_topic.main.endpoint
    "EVENTGRID_KEY"               = azurerm_eventgrid_topic.main.primary_access_key
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string
    "OPENAI_ENDPOINT"             = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"                  = azurerm_cognitive_account.openai.primary_access_key
    "CONTAINER_REGISTRY_SERVER"   = azurerm_container_registry.main.login_server
    "CONTAINER_REGISTRY_USERNAME" = azurerm_container_registry.main.admin_username
    "CONTAINER_REGISTRY_PASSWORD" = azurerm_container_registry.main.admin_password
    "CONTAINER_IMAGE_NAME"        = local.container_image_name
    "CONTAINER_IMAGE_TAG"         = local.container_image_tag
    "CONTAINER_CPU"               = var.container_cpu
    "CONTAINER_MEMORY"            = var.container_memory
  }
  
  tags = local.common_tags
}

# Create Logic App for Container Instance orchestration
resource "azurerm_logic_app_workflow" "aci_orchestrator" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable system-assigned managed identity for accessing other Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Event Grid subscription for Logic App
resource "azurerm_eventgrid_event_subscription" "logic_app" {
  name  = "sub-${local.logic_app_name}"
  scope = azurerm_eventgrid_topic.main.id
  
  # Configure Logic App as webhook endpoint
  webhook_endpoint {
    url = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Logic/workflows/${azurerm_logic_app_workflow.aci_orchestrator.name}/triggers/When_Event_Grid_event_occurs/run?api-version=2016-06-01"
  }
  
  # Filter events for agent task creation
  subject_filter {
    subject_begins_with = "agent/task/"
  }
  
  depends_on = [azurerm_logic_app_workflow.aci_orchestrator]
}

# Role assignment for Logic App to manage Container Instances
resource "azurerm_role_assignment" "logic_app_aci" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_logic_app_workflow.aci_orchestrator.identity[0].principal_id
}

# Role assignment for Logic App to access Container Registry
resource "azurerm_role_assignment" "logic_app_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_logic_app_workflow.aci_orchestrator.identity[0].principal_id
}

# Role assignment for Function App to access OpenAI
resource "azurerm_role_assignment" "function_app_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role assignment for Function App to access Storage Account
resource "azurerm_role_assignment" "function_app_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Create monitoring alerts for agent failures (if monitoring enabled)
resource "azurerm_monitor_metric_alert" "agent_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "alert-agent-failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when agent processing fails"
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  window_size = "PT5M"
  frequency   = "PT1M"
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Create action group for alerts (if monitoring enabled)
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "ag-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "aiagents"
  
  tags = local.common_tags
}

# Output configuration files for container agent
resource "local_file" "agent_dockerfile" {
  filename = "${path.module}/docker/Dockerfile"
  content = <<-EOF
FROM python:3.11-slim

# Install required packages
RUN pip install --no-cache-dir openai==1.3.0 azure-storage-blob==12.19.0 azure-eventgrid==4.9.0

# Copy agent script
COPY agent.py /app/agent.py
WORKDIR /app

# Run the agent
CMD ["python", "agent.py"]
EOF
  
  depends_on = [azurerm_resource_group.main]
}

# Create agent Python script
resource "local_file" "agent_script" {
  filename = "${path.module}/docker/agent.py"
  content = <<-EOF
import os
import json
import openai
from azure.storage.blob import BlobServiceClient
from azure.eventgrid import EventGridPublisherClient, EventGridEvent
from azure.core.credentials import AzureKeyCredential
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_task():
    """Process AI agent task using OpenAI and store results"""
    try:
        # Initialize OpenAI client
        client = openai.AzureOpenAI(
            api_key=os.environ['OPENAI_KEY'],
            api_version="2023-05-15",
            azure_endpoint=os.environ['OPENAI_ENDPOINT']
        )
        
        # Get task details from environment
        task_id = os.environ['TASK_ID']
        task_prompt = os.environ['TASK_PROMPT']
        
        logger.info(f"Processing task {task_id}")
        
        # Process with GPT-4
        response = client.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": task_prompt}],
            temperature=0.7,
            max_tokens=1000
        )
        
        result = response.choices[0].message.content
        
        # Store results in blob storage
        blob_client = BlobServiceClient.from_connection_string(
            os.environ['STORAGE_CONNECTION_STRING']
        ).get_blob_client(
            container="results",
            blob=f"{task_id}.json"
        )
        
        result_data = {
            "task_id": task_id,
            "result": result,
            "status": "completed",
            "timestamp": str(datetime.utcnow())
        }
        
        blob_client.upload_blob(
            json.dumps(result_data, indent=2),
            overwrite=True
        )
        
        logger.info(f"Task {task_id} completed successfully")
        
        # Publish completion event (optional)
        if 'EVENTGRID_ENDPOINT' in os.environ:
            event_client = EventGridPublisherClient(
                os.environ['EVENTGRID_ENDPOINT'],
                AzureKeyCredential(os.environ['EVENTGRID_KEY'])
            )
            
            completion_event = EventGridEvent(
                subject=f"agent/task/{task_id}",
                event_type="Agent.TaskCompleted",
                data=result_data,
                data_version="1.0"
            )
            
            event_client.send(completion_event)
            logger.info(f"Completion event published for task {task_id}")
        
    except Exception as e:
        logger.error(f"Error processing task: {str(e)}")
        # Store error result
        try:
            error_data = {
                "task_id": task_id,
                "error": str(e),
                "status": "failed",
                "timestamp": str(datetime.utcnow())
            }
            
            blob_client.upload_blob(
                json.dumps(error_data, indent=2),
                overwrite=True
            )
        except Exception as blob_error:
            logger.error(f"Failed to store error result: {str(blob_error)}")
        
        raise

if __name__ == "__main__":
    import datetime
    process_task()
EOF
  
  depends_on = [azurerm_resource_group.main]
}

# Create Function App code
resource "local_file" "function_app_code" {
  filename = "${path.module}/function/function_app.py"
  content = <<-EOF
import logging
import json
import uuid
import os
from azure.eventgrid import EventGridPublisherClient, EventGridEvent
from azure.core.credentials import AzureKeyCredential
import azure.functions as func

app = func.FunctionApp()

@app.function_name(name="agent-api")
@app.route(route="agent", methods=["POST"])
def agent_api(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger for submitting AI agent tasks"""
    logging.info('Processing AI agent request')
    
    try:
        # Parse request
        req_body = req.get_json()
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Invalid JSON in request body"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        task_prompt = req_body.get('prompt')
        if not task_prompt:
            return func.HttpResponse(
                json.dumps({"error": "Missing 'prompt' in request"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        # Generate task ID
        task_id = str(uuid.uuid4())
        
        # Publish event to Event Grid
        client = EventGridPublisherClient(
            os.environ['EVENTGRID_ENDPOINT'],
            AzureKeyCredential(os.environ['EVENTGRID_KEY'])
        )
        
        event = EventGridEvent(
            subject="agent/task/new",
            event_type="Agent.TaskCreated",
            data={
                "taskId": task_id,
                "prompt": task_prompt
            },
            data_version="1.0"
        )
        
        client.send(event)
        
        logging.info(f"Task {task_id} submitted successfully")
        
        return func.HttpResponse(
            json.dumps({
                "taskId": task_id,
                "status": "accepted",
                "message": "Task submitted for processing"
            }),
            status_code=202,
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )

@app.function_name(name="agent-status")
@app.route(route="agent/{task_id}", methods=["GET"])
def agent_status(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger for checking task status"""
    logging.info('Checking agent task status')
    
    try:
        task_id = req.route_params.get('task_id')
        if not task_id:
            return func.HttpResponse(
                json.dumps({"error": "Missing task ID"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        # Check task status in blob storage
        from azure.storage.blob import BlobServiceClient
        
        blob_client = BlobServiceClient.from_connection_string(
            os.environ['STORAGE_CONNECTION_STRING']
        ).get_blob_client(
            container="results",
            blob=f"{task_id}.json"
        )
        
        try:
            blob_data = blob_client.download_blob().readall()
            result = json.loads(blob_data.decode('utf-8'))
            
            return func.HttpResponse(
                json.dumps(result),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )
            
        except Exception as e:
            # Task not found or still processing
            return func.HttpResponse(
                json.dumps({
                    "taskId": task_id,
                    "status": "processing",
                    "message": "Task is still being processed"
                }),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )
        
    except Exception as e:
        logging.error(f"Error checking task status: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )
EOF
  
  depends_on = [azurerm_resource_group.main]
}

# Create requirements.txt for Function App
resource "local_file" "function_requirements" {
  filename = "${path.module}/function/requirements.txt"
  content = <<-EOF
azure-functions==1.18.0
azure-eventgrid==4.9.0
azure-storage-blob==12.19.0
azure-core==1.29.0
EOF
  
  depends_on = [azurerm_resource_group.main]
}
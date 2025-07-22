# Azure Self-Healing Infrastructure with Traffic Manager and Load Testing
# This Terraform configuration creates a self-healing infrastructure solution
# using Azure Traffic Manager, Azure Load Testing, and Azure Functions

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Application Insights for comprehensive monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

# App Service Plans for multi-region deployment
resource "azurerm_service_plan" "main" {
  for_each = toset(var.web_app_regions)
  
  name                = "asp-${var.project_name}-${replace(lower(each.value), " ", "")}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = each.value
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = var.tags
}

# Web Apps deployed across multiple regions
resource "azurerm_linux_web_app" "main" {
  for_each = toset(var.web_app_regions)
  
  name                = "webapp-${var.project_name}-${replace(lower(each.value), " ", "")}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = each.value
  service_plan_id     = azurerm_service_plan.main[each.value].id
  tags                = var.tags

  site_config {
    always_on = true
    
    application_stack {
      node_version = "18-lts"
    }
    
    # Health check configuration
    health_check_path = "/"
    health_check_eviction_time_in_min = 2
  }

  app_settings = var.enable_application_insights ? {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"       = azurerm_application_insights.main[0].instrumentation_key
  } : {}

  identity {
    type = "SystemAssigned"
  }
}

# Auto-scaling settings for App Service Plans
resource "azurerm_monitor_autoscale_setting" "main" {
  for_each = var.enable_auto_scaling ? toset(var.web_app_regions) : []
  
  name                = "autoscale-${var.project_name}-${replace(lower(each.value), " ", "")}"
  resource_group_name = azurerm_resource_group.main.name
  location            = each.value
  target_resource_id  = azurerm_service_plan.main[each.value].id
  tags                = var.tags

  profile {
    name = "default"

    capacity {
      default = 1
      minimum = 1
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main[each.value].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main[each.value].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}

# Traffic Manager Profile
resource "azurerm_traffic_manager_profile" "main" {
  name                = "tm-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  traffic_routing_method = var.traffic_manager_routing_method

  dns_config {
    relative_name = "tm-${var.project_name}-${random_string.suffix.result}"
    ttl           = var.traffic_manager_ttl
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/"
    interval_in_seconds         = var.monitor_interval
    timeout_in_seconds          = var.monitor_timeout
    tolerated_number_of_failures = var.monitor_failure_threshold
  }
}

# Traffic Manager Endpoints
resource "azurerm_traffic_manager_azure_endpoint" "main" {
  for_each = toset(var.web_app_regions)
  
  name                = "endpoint-${replace(lower(each.value), " ", "")}"
  profile_id          = azurerm_traffic_manager_profile.main.id
  target_resource_id  = azurerm_linux_web_app.main[each.value].id
  priority            = index(var.web_app_regions, each.value) + 1
  weight              = 100
}

# Azure Load Testing Resource
resource "azurerm_load_test" "main" {
  count               = var.enable_load_testing ? 1 : 0
  name                = "alt-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Function App for self-healing automation
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags

  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_app.id

  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  }

  app_settings = {
    "TRAFFIC_MANAGER_PROFILE"              = azurerm_traffic_manager_profile.main.name
    "RESOURCE_GROUP"                       = azurerm_resource_group.main.name
    "SUBSCRIPTION_ID"                      = data.azurerm_client_config.current.subscription_id
    "FUNCTIONS_WORKER_RUNTIME"             = var.function_app_runtime
    "ENABLE_ORYX_BUILD"                    = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"      = "true"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "asp-func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

# Function App Source Code (placeholder for actual deployment)
data "archive_file" "function_app_zip" {
  type        = "zip"
  output_path = "${path.module}/function_app.zip"
  
  source {
    content = templatefile("${path.module}/function_code.py", {
      traffic_manager_profile = azurerm_traffic_manager_profile.main.name
      resource_group         = azurerm_resource_group.main.name
      subscription_id        = data.azurerm_client_config.current.subscription_id
    })
    filename = "__init__.py"
  }
  
  source {
    content = jsonencode({
      scriptFile = "__init__.py"
      bindings = [
        {
          authLevel = "function"
          type      = "httpTrigger"
          direction = "in"
          name      = "req"
          methods   = ["post"]
        },
        {
          type      = "http"
          direction = "out"
          name      = "$return"
        }
      ]
    })
    filename = "function.json"
  }
  
  source {
    content  = "azure-functions\nazure-mgmt-trafficmanager\nazure-identity\nazure-monitor-query\nrequests"
    filename = "requirements.txt"
  }
}

# Deploy Function App Code
resource "azurerm_function_app_function" "self_healing" {
  name            = "self-healing"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "Python"
  
  file {
    name    = "__init__.py"
    content = templatefile("${path.module}/function_code.py", {
      traffic_manager_profile = azurerm_traffic_manager_profile.main.name
      resource_group         = azurerm_resource_group.main.name
      subscription_id        = data.azurerm_client_config.current.subscription_id
    })
  }
  
  file {
    name = "function.json"
    content = jsonencode({
      scriptFile = "__init__.py"
      bindings = [
        {
          authLevel = "function"
          type      = "httpTrigger"
          direction = "in"
          name      = "req"
          methods   = ["post"]
        },
        {
          type      = "http"
          direction = "out"
          name      = "$return"
        }
      ]
    })
  }
  
  config_json = jsonencode({
    bindings = [
      {
        authLevel = "function"
        type      = "httpTrigger"
        direction = "in"
        name      = "req"
        methods   = ["post"]
      },
      {
        type      = "http"
        direction = "out"
        name      = "$return"
      }
    ]
  })
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "selfheal"
  tags                = var.tags

  azure_function_receiver {
    name                     = "webhook-function"
    function_app_resource_id = azurerm_linux_function_app.main.id
    function_name            = azurerm_function_app_function.self_healing.name
    http_trigger_url         = "https://${azurerm_linux_function_app.main.default_hostname}/api/self-healing"
    use_common_alert_schema  = true
  }
}

# Metric Alert for Response Time
resource "azurerm_monitor_metric_alert" "response_time" {
  for_each = toset(var.web_app_regions)
  
  name                = "alert-response-time-${replace(lower(each.value), " ", "")}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main[each.value].id]
  description         = "Alert when average response time exceeds threshold"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.response_time_threshold
  }

  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Metric Alert for Availability
resource "azurerm_monitor_metric_alert" "availability" {
  for_each = toset(var.web_app_regions)
  
  name                = "alert-availability-${replace(lower(each.value), " ", "")}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main[each.value].id]
  description         = "Alert when request rate drops below threshold"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Requests"
    aggregation      = "Count"
    operator         = "LessThan"
    threshold        = var.availability_threshold
  }

  frequency   = var.alert_evaluation_frequency
  window_size = "PT3M"
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Role Assignment - Traffic Manager Contributor
resource "azurerm_role_assignment" "function_traffic_manager" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Traffic Manager Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment - Monitoring Reader
resource "azurerm_role_assignment" "function_monitoring" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment - Load Test Contributor
resource "azurerm_role_assignment" "function_load_test" {
  count                = var.enable_load_testing ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Load Test Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Create Function Code Template
resource "local_file" "function_code" {
  filename = "${path.module}/function_code.py"
  content = templatefile("${path.module}/function_code.py.tpl", {
    traffic_manager_profile = azurerm_traffic_manager_profile.main.name
    resource_group         = azurerm_resource_group.main.name
    subscription_id        = data.azurerm_client_config.current.subscription_id
  })
  
  depends_on = [
    azurerm_traffic_manager_profile.main,
    azurerm_resource_group.main
  ]
}

# Function Code Template File
resource "local_file" "function_code_template" {
  filename = "${path.module}/function_code.py.tpl"
  content = <<EOF
import azure.functions as func
import json
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.trafficmanager import TrafficManagerManagementClient
from azure.monitor.query import LogsQueryClient
import requests
from datetime import datetime, timedelta

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Self-healing function triggered')
    
    try:
        # Parse alert data
        alert_data = req.get_json()
        logging.info(f'Alert received: {alert_data}')
        
        # Initialize Azure clients
        credential = DefaultAzureCredential()
        subscription_id = '${subscription_id}'
        resource_group = '${resource_group}'
        tm_profile = '${traffic_manager_profile}'
        
        tm_client = TrafficManagerManagementClient(credential, subscription_id)
        
        # Evaluate endpoint health and performance
        unhealthy_endpoints = evaluate_endpoint_health(alert_data)
        
        # Take corrective actions
        actions_taken = []
        for endpoint in unhealthy_endpoints:
            result = disable_endpoint(tm_client, resource_group, tm_profile, endpoint)
            actions_taken.append(result)
            
            # Optionally trigger load test for validation
            trigger_load_test(endpoint)
        
        return func.HttpResponse(
            json.dumps({
                "status": "success", 
                "actions_taken": len(actions_taken),
                "details": actions_taken
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error in self-healing function: {str(e)}')
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

def evaluate_endpoint_health(alert_data):
    """Evaluate endpoint health based on alert data"""
    unhealthy_endpoints = []
    
    # Extract endpoint information from alert data
    if alert_data and 'data' in alert_data:
        alert_context = alert_data['data']
        if 'context' in alert_context:
            resource_name = alert_context['context'].get('resourceName', '')
            if resource_name:
                # Extract region from resource name
                if 'eastus' in resource_name.lower():
                    unhealthy_endpoints.append('endpoint-eastus')
                elif 'westus' in resource_name.lower():
                    unhealthy_endpoints.append('endpoint-westus')
                elif 'westeurope' in resource_name.lower():
                    unhealthy_endpoints.append('endpoint-westeurope')
    
    return unhealthy_endpoints

def disable_endpoint(tm_client, resource_group, profile_name, endpoint_name):
    """Disable unhealthy endpoint in Traffic Manager"""
    try:
        logging.info(f'Disabling endpoint: {endpoint_name}')
        
        # Get current endpoint
        endpoint = tm_client.endpoints.get(
            resource_group,
            profile_name,
            'azureEndpoints',
            endpoint_name
        )
        
        # Update endpoint to disabled status
        endpoint.endpoint_status = 'Disabled'
        
        tm_client.endpoints.create_or_update(
            resource_group,
            profile_name,
            'azureEndpoints',
            endpoint_name,
            endpoint
        )
        
        return f"Successfully disabled endpoint: {endpoint_name}"
        
    except Exception as e:
        logging.error(f'Error disabling endpoint {endpoint_name}: {str(e)}')
        return f"Error disabling endpoint {endpoint_name}: {str(e)}"

def trigger_load_test(endpoint):
    """Trigger load test for recovered endpoint"""
    try:
        logging.info(f'Triggering load test for: {endpoint}')
        # Implement load test triggering logic here
        # This is a placeholder for actual load test integration
        return f"Load test triggered for: {endpoint}"
    except Exception as e:
        logging.error(f'Error triggering load test for {endpoint}: {str(e)}')
        return f"Error triggering load test for {endpoint}: {str(e)}"
EOF
}
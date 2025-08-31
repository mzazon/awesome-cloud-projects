# main.tf
# Main Terraform configuration for Azure Logic Apps schedule reminder solution
# This file defines all the Azure resources needed for automated email reminders

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and tagging
locals {
  # Common naming convention with random suffix
  name_suffix = lower(random_id.suffix.hex)
  base_name   = "${var.project_name}-${var.environment}"
  
  # Resource names following Azure naming conventions
  resource_group_name      = "rg-${local.base_name}-${local.name_suffix}"
  logic_app_name          = "la-${local.base_name}-${local.name_suffix}"
  office365_connection_name = "con-${var.office365_connection_name}-${local.name_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment   = var.environment
    Project      = var.project_name
    Purpose      = "schedule-reminders"
    CreatedBy    = "Terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
    Recipe       = "simple-schedule-reminders-logic-apps-outlook"
  }, var.additional_tags)
  
  # Workflow definition as a structured object for maintainability
  workflow_definition = {
    "$schema"        = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
    "contentVersion" = "1.0.0.0"
    
    # Workflow parameters for connection references
    "parameters" = {
      "$connections" = {
        "defaultValue" = {}
        "type"         = "Object"
      }
    }
    
    # Recurrence trigger configuration
    "triggers" = {
      "Recurrence" = {
        "type" = "Recurrence"
        "recurrence" = {
          "frequency" = var.recurrence_frequency
          "interval"  = var.recurrence_interval
          "schedule" = {
            "hours"    = var.schedule_hours
            "minutes"  = var.schedule_minutes
            "weekDays" = var.recurrence_frequency == "Week" ? var.schedule_weekdays : null
          }
        }
      }
    }
    
    # Email sending action using Office 365 Outlook connector
    "actions" = {
      "Send_an_email_(V2)" = {
        "runAfter" = {}
        "type"     = "ApiConnection"
        "inputs" = {
          "body" = {
            "Body"    = var.email_body
            "Subject" = var.email_subject
            "To"      = var.email_recipient
          }
          "host" = {
            "connection" = {
              "name" = "@parameters('$connections')['office365']['connectionId']"
            }
          }
          "method" = "post"
          "path"   = "/v2/Mail"
        }
      }
    }
    
    # Empty outputs section (can be extended for workflow results)
    "outputs" = {}
  }
}

# Current Azure client configuration for tenant and subscription info
data "azurerm_client_config" "current" {}

# Create the resource group to contain all resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create the Office 365 Outlook API connection for email sending
# Note: This resource requires manual authentication in the Azure portal
resource "azurerm_api_connection" "office365" {
  name                = local.office365_connection_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Reference to the Office 365 Outlook managed API
  managed_api_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/office365"
  
  # Display name for the connection in Azure portal
  display_name = "Office 365 Outlook Connection for Reminders"
  
  tags = local.common_tags
}

# Create the Logic App workflow for scheduled email reminders
resource "azurerm_logic_app_workflow" "reminder" {
  name                = local.logic_app_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Workflow definition with connection parameters
  workflow_schema   = local.workflow_definition["$schema"]
  workflow_version  = local.workflow_definition["contentVersion"]
  
  # Parameters for the workflow including connection references
  parameters = {
    "$connections" = jsonencode({
      "office365" = {
        "connectionId"   = azurerm_api_connection.office365.id
        "connectionName" = azurerm_api_connection.office365.name
        "id"            = azurerm_api_connection.office365.managed_api_id
      }
    })
  }
  
  # Enable or disable the workflow based on variable
  enabled = var.logic_app_state == "Enabled"
  
  # Optional Integration Service Environment for dedicated hosting
  integration_service_environment_id = var.integration_service_environment_id
  
  # Workflow access control for security
  dynamic "access_control" {
    for_each = var.workflow_access_control != {} ? [var.workflow_access_control] : []
    content {
      # Content access control (who can view workflow definition)
      dynamic "contents" {
        for_each = access_control.value.contents != null ? [access_control.value.contents] : []
        content {
          allowed_caller_ip_address_range = contents.value.allowed_caller_ip_address_ranges
        }
      }
      
      # Trigger access control (who can trigger the workflow)
      dynamic "triggers" {
        for_each = access_control.value.triggers != null ? [access_control.value.triggers] : []
        content {
          allowed_caller_ip_address_range = triggers.value.allowed_caller_ip_address_ranges
        }
      }
      
      # Action access control (who can execute actions)
      dynamic "actions" {
        for_each = access_control.value.actions != null ? [access_control.value.actions] : []
        content {
          allowed_caller_ip_address_range = actions.value.allowed_caller_ip_address_ranges
        }
      }
    }
  }
  
  tags = local.common_tags
  
  # Ensure the API connection is created before the Logic App
  depends_on = [azurerm_api_connection.office365]
}

# Create the workflow trigger for the recurrence schedule
resource "azurerm_logic_app_trigger_recurrence" "reminder_schedule" {
  name         = "Recurrence"
  logic_app_id = azurerm_logic_app_workflow.reminder.id
  
  # Schedule configuration
  frequency = var.recurrence_frequency
  interval  = var.recurrence_interval
  
  # Specific schedule details
  schedule {
    hours   = var.schedule_hours
    minutes = var.schedule_minutes
    
    # Weekdays only apply to weekly recurrence
    week_days = var.recurrence_frequency == "Week" ? var.schedule_weekdays : null
  }
}

# Create the workflow action for sending emails
resource "azurerm_logic_app_action_http" "send_email" {
  name         = "Send_an_email_(V2)"
  logic_app_id = azurerm_logic_app_workflow.reminder.id
  
  method = "POST"
  uri    = "https://outlook.office365.com/api/v2.0/Mail"
  
  # Email content body
  body = jsonencode({
    "Body"    = var.email_body
    "Subject" = var.email_subject
    "To"      = var.email_recipient
  })
  
  # Headers for Office 365 API
  headers = {
    "Content-Type" = "application/json"
  }
  
  # Ensure this runs after the trigger
  depends_on = [azurerm_logic_app_trigger_recurrence.reminder_schedule]
}

# Optional: Create a Log Analytics workspace for monitoring (if monitoring is desired)
resource "azurerm_log_analytics_workspace" "monitoring" {
  count = var.environment == "prod" ? 1 : 0
  
  name                = "law-${local.base_name}-${local.name_suffix}"
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = "PerGB2018"
  retention_in_days  = 30
  
  tags = local.common_tags
}

# Optional: Configure diagnostic settings for the Logic App (production environments)
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  count = var.environment == "prod" && length(azurerm_log_analytics_workspace.monitoring) > 0 ? 1 : 0
  
  name               = "diag-${local.logic_app_name}"
  target_resource_id = azurerm_logic_app_workflow.reminder.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.monitoring[0].id
  
  # Enable workflow runtime logs
  enabled_log {
    category = "WorkflowRuntime"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}
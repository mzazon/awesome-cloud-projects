# Azure Email Notifications with Communication Services and Functions
# This Terraform configuration deploys a serverless email notification system

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate resource names with random suffix
  random_suffix      = random_id.suffix.hex
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.random_suffix}"
  
  # Resource naming with consistent patterns
  communication_service_name = "cs-${var.project_name}-${local.random_suffix}"
  email_service_name        = "email-${var.project_name}-${local.random_suffix}"
  storage_account_name      = "st${replace(var.project_name, "-", "")}${local.random_suffix}"
  function_app_name         = "func-${var.project_name}-${local.random_suffix}"
  app_service_plan_name     = "asp-${var.project_name}-${local.random_suffix}"
  app_insights_name         = "appi-${var.project_name}-${local.random_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    ResourceGroup = local.resource_group_name
    CreatedBy     = "Terraform"
    CreatedOn     = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group to contain all email notification resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Communication Services resource for email capabilities
# Provides enterprise-grade email delivery with authentication and compliance
resource "azurerm_communication_service" "main" {
  name                = local.communication_service_name
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.communication_services_data_location
  tags                = local.common_tags
}

# Email Communication Service for managing email domains and sending
# Handles SPF, DKIM, and DMARC configurations automatically
resource "azurerm_email_communication_service" "main" {
  name                = local.email_service_name
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.communication_services_data_location
  tags                = local.common_tags
}

# Azure Managed Domain for immediate email sending without domain verification
# Provides *.azurecomm.net domain with pre-configured authentication
resource "azurerm_email_communication_service_domain" "main" {
  name             = "AzureManagedDomain"
  email_service_id = azurerm_email_communication_service.main.id
  domain_management = "AzureManaged"
  tags             = local.common_tags
}

# Link Communication Services to Email Service for API access
# This connection enables email sending through Communication Services SDK
resource "azurerm_communication_service_email_domain_association" "main" {
  communication_service_id = azurerm_communication_service.main.id
  email_service_domain_id  = azurerm_email_communication_service_domain.main.id
}

# Storage Account for Function App requirements
# Provides backing storage for function execution state and triggers
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  tags = local.common_tags
}

# Application Insights for Function App monitoring and diagnostics
# Provides telemetry, logging, and performance monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "Node.JS"
  retention_in_days   = 90
  
  tags = local.common_tags
}

# App Service Plan for Function App hosting
# Consumption plan provides serverless execution and automatic scaling
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_plan_sku_size
  
  tags = local.common_tags
}

# Function App for serverless email sending logic
# Provides HTTP trigger endpoint for email notification requests
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage account configuration for function requirements
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Function runtime configuration
  site_config {
    # Node.js runtime for Communication Services SDK
    application_stack {
      node_version = var.function_runtime_version
    }
    
    # CORS configuration for web applications
    cors {
      allowed_origins = var.allowed_cors_origins
    }
    
    # Security and performance settings
    use_32_bit_worker        = false
    always_on                = false  # Not available in Consumption plan
    ftps_state              = "Disabled"
    http2_enabled           = true
    minimum_tls_version     = "1.2"
  }
  
  # Application settings for Communication Services integration
  app_settings = merge({
    # Communication Services connection string for email sending
    "COMMUNICATION_SERVICES_CONNECTION_STRING" = azurerm_communication_service.main.primary_connection_string
    
    # Sender email address using Azure managed domain
    "SENDER_ADDRESS" = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_NODE_DEFAULT_VERSION" = var.function_runtime_version
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # Function execution timeout
    "FUNCTION_TIMEOUT" = "${var.function_timeout}:00:00"
    
    # Disable built-in logging to rely on Application Insights
    "AzureWebJobsDashboard" = ""
  }, var.enable_application_insights ? {
    # Application Insights configuration for monitoring
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  # Enable public network access for HTTP triggers
  public_network_access_enabled = true
  
  # Disable built-in authentication (can be enabled for production)
  auth_settings_v2 {
    auth_enabled = false
  }
  
  tags = local.common_tags
  
  # Ensure Communication Services and Email Service are created first
  depends_on = [
    azurerm_communication_service_email_domain_association.main
  ]
}

# Create function code deployment package
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/function-app.zip"
  
  source {
    content = jsonencode({
      version                = "2.0"
      functionTimeout        = "00:0${var.function_timeout}:00"
      logging = {
        applicationInsights = {
          samplingSettings = {
            isEnabled = var.enable_application_insights
          }
        }
      }
    })
    filename = "host.json"
  }
  
  source {
    content = jsonencode({
      name        = "email-notification-function"
      version     = "1.0.0"
      description = "Azure Function for sending email notifications"
      main        = "index.js"
      scripts = {
        start = "func start"
      }
      dependencies = {
        "@azure/communication-email" = "^1.0.0"
        "@azure/functions"           = "^4.0.0"
      }
    })
    filename = "package.json"
  }
  
  source {
    content = jsonencode({
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
          name      = "res"
        }
      ]
    })
    filename = "function.json"
  }
  
  source {
    content = <<-EOT
const { EmailClient } = require("@azure/communication-email");

module.exports = async function (context, req) {
    context.log('Email notification function triggered');

    // Validate request body
    const { to, subject, body } = req.body || {};
    
    if (!to || !subject || !body) {
        context.res = {
            status: 400,
            body: {
                error: "Missing required fields: to, subject, body"
            }
        };
        return;
    }

    try {
        // Initialize email client with Connection String
        const emailClient = new EmailClient(
            process.env.COMMUNICATION_SERVICES_CONNECTION_STRING
        );

        // Prepare email message
        const emailMessage = {
            senderAddress: process.env.SENDER_ADDRESS,
            content: {
                subject: subject,
                plainText: body
            },
            recipients: {
                to: [{ address: to }]
            }
        };

        // Send email via Communication Services
        const poller = await emailClient.beginSend(emailMessage);
        const response = await poller.pollUntilDone();

        context.log(`Email sent successfully. Message ID: $${response.id}`);

        context.res = {
            status: 200,
            body: {
                message: "Email sent successfully",
                messageId: response.id,
                status: response.status
            }
        };

    } catch (error) {
        context.log.error('Error sending email:', error);

        context.res = {
            status: 500,
            body: {
                error: "Failed to send email",
                details: error.message
            }
        };
    }
};
    EOT
    filename = "index.js"
  }
}

# Deploy function code to Function App
# Note: In production, consider using Azure DevOps or GitHub Actions for deployment
resource "azurerm_function_app_function" "email_function" {
  name            = "index"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "Javascript"
  
  file {
    name    = "index.js"
    content = <<-EOT
const { EmailClient } = require("@azure/communication-email");

module.exports = async function (context, req) {
    context.log('Email notification function triggered');

    // Validate request body
    const { to, subject, body } = req.body || {};
    
    if (!to || !subject || !body) {
        context.res = {
            status: 400,
            body: {
                error: "Missing required fields: to, subject, body"
            }
        };
        return;
    }

    try {
        // Initialize email client with Connection String
        const emailClient = new EmailClient(
            process.env.COMMUNICATION_SERVICES_CONNECTION_STRING
        );

        // Prepare email message
        const emailMessage = {
            senderAddress: process.env.SENDER_ADDRESS,
            content: {
                subject: subject,
                plainText: body
            },
            recipients: {
                to: [{ address: to }]
            }
        };

        // Send email via Communication Services
        const poller = await emailClient.beginSend(emailMessage);
        const response = await poller.pollUntilDone();

        context.log(`Email sent successfully. Message ID: $${response.id}`);

        context.res = {
            status: 200,
            body: {
                message: "Email sent successfully",
                messageId: response.id,
                status: response.status
            }
        };

    } catch (error) {
        context.log.error('Error sending email:', error);

        context.res = {
            status: 500,
            body: {
                error: "Failed to send email",
                details: error.message
            }
        };
    }
};
    EOT
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
        name      = "res"
      }
    ]
  })
}
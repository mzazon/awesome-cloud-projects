# Simple Website Uptime Checker with Azure Functions and Application Insights
# This Terraform configuration deploys a serverless monitoring solution for website uptime checking
# using Azure Functions with timer triggers and Application Insights for telemetry and alerting

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for resource naming and tagging
locals {
  # Generate unique resource names with random suffix
  resource_suffix = random_string.suffix.result
  
  # Resource naming following Azure conventions
  resource_group_name  = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${local.resource_suffix}"
  storage_account_name = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  function_app_name    = "func-${var.project_name}-${local.resource_suffix}"
  app_insights_name    = "ai-${var.project_name}-${local.resource_suffix}"
  action_group_name    = "ag-${var.project_name}-${local.resource_suffix}"
  alert_rule_name      = "alert-${var.project_name}-downtime-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment         = var.environment
    Project            = var.project_name
    Purpose            = "uptime-monitoring"
    ManagedBy          = "terraform"
    DeploymentDate     = timestamp()
    CostCenter         = "monitoring"
  }, var.tags)
}

# Create Resource Group to contain all resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Application Insights for monitoring and telemetry collection
# This provides comprehensive observability for the Function App and custom telemetry
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.app_insights_retention_days
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    Service   = "application-insights"
  })
}

# Create Storage Account for Function App (required for Azure Functions)
# Using StorageV2 with appropriate redundancy for function app storage needs
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  
  tags = merge(local.common_tags, {
    Component = "storage"
    Service   = "function-app-storage"
  })
}

# Create App Service Plan for Function App (Consumption plan for serverless)
# Using Y1 (consumption) plan for cost-effective, event-driven execution
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan for serverless computing
  
  tags = merge(local.common_tags, {
    Component = "compute"
    Service   = "app-service-plan"
  })
}

# Create Function App for uptime monitoring logic
# Configured with Node.js runtime and integrated with Application Insights
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Configure storage account connection
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function runtime configuration
  site_config {
    application_stack {
      node_version = "18"  # LTS Node.js version
    }
    
    # Security and performance settings
    ftps_state                             = "Disabled"
    http2_enabled                          = true
    minimum_tls_version                    = "1.2"
    scm_minimum_tls_version               = "1.2"
    use_32_bit_worker                     = false
    
    # CORS configuration for potential web interface
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }
  
  # Application settings including Application Insights integration
  app_settings = {
    # Application Insights configuration
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    
    # Function configuration
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~18"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    
    # Custom application settings for uptime monitoring
    "WEBSITES_TO_MONITOR"     = join(",", var.websites_to_monitor)
    "MONITORING_FREQUENCY"    = var.monitoring_frequency
    "FUNCTION_TIMEOUT_MIN"    = tostring(var.function_timeout)
    "ENVIRONMENT"             = var.environment
    
    # Performance and reliability settings
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"       = "true"
    "WEBSITE_TIME_ZONE"                     = "UTC"
  }
  
  # Enable built-in authentication (optional, can be configured later)
  auth_settings {
    enabled = false
  }
  
  # Configure connection strings if needed
  connection_string {
    name  = "ApplicationInsights"
    type  = "Custom"
    value = azurerm_application_insights.main.connection_string
  }
  
  tags = merge(local.common_tags, {
    Component = "compute"
    Service   = "function-app"
    Runtime   = "nodejs18"
  })
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_application_insights.main,
    azurerm_service_plan.main
  ]
}

# Create Action Group for alert notifications
# This enables notifications when uptime monitoring detects issues
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_alerting ? 1 : 0
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "uptimealrt"
  
  # Email notification configuration (can be extended with additional notification methods)
  email_receiver {
    name          = "uptime-email"
    email_address = "admin@example.com"  # Should be configured via variables in production
  }
  
  # Azure Resource Manager action for potential auto-remediation
  arm_role_receiver {
    name                    = "monitoring-contributor"
    role_id                 = "749f88d5-cbae-40b8-bcfc-e573ddc772fa"  # Monitoring Contributor role
    use_common_alert_schema = true
  }
  
  tags = merge(local.common_tags, {
    Component = "alerting"
    Service   = "action-group"
  })
}

# Create Log Analytics Query Alert Rule for downtime detection
# Monitors Application Insights logs for error patterns indicating website downtime
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "downtime_alert" {
  count               = var.enable_alerting ? 1 : 0
  name                = local.alert_rule_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Alert rule configuration
  description          = "Alert when websites are detected as down by uptime checker"
  enabled              = true
  severity             = var.alert_severity
  auto_mitigation_enabled = false
  
  # Query and evaluation settings
  evaluation_frequency = "PT${var.alert_frequency_minutes}M"
  window_duration     = "PT${var.alert_window_minutes}M"
  
  # Target Application Insights resource
  scopes = [azurerm_application_insights.main.id]
  
  # KQL query to detect downtime events
  criteria {
    query = <<-EOT
      traces
      | where timestamp > ago(${var.alert_window_minutes}m)
      | where message contains "❌"
      | summarize count() by bin(timestamp, 1m)
      | where count_ > 0
    EOT
    
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
    
    # Dimension for grouping alerts
    dimension {
      name     = "timestamp"
      operator = "Include"
      values   = ["*"]
    }
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods            = 1
    }
  }
  
  # Link to action group for notifications
  action {
    action_groups = [azurerm_monitor_action_group.main[0].id]
    
    custom_properties = {
      AlertType    = "UptimeMonitoring"
      Environment  = var.environment
      Project      = var.project_name
    }
  }
  
  tags = merge(local.common_tags, {
    Component = "alerting"
    Service   = "alert-rule"
    AlertType = "downtime-detection"
  })
  
  depends_on = [
    azurerm_application_insights.main,
    azurerm_monitor_action_group.main
  ]
}

# Create Function App Function (UptimeChecker) using archive deployment
# This creates the actual monitoring function with timer trigger
data "archive_file" "function_code" {
  type        = "zip"
  output_path = "${path.module}/uptime-function.zip"
  
  source {
    content = jsonencode({
      version = "2.0"
      extensionBundle = {
        id      = "Microsoft.Azure.Functions.ExtensionBundle"
        version = "[3.*, 4.0.0)"
      }
      functionTimeout = "00:0${var.function_timeout}:00"
    })
    filename = "host.json"
  }
  
  source {
    content = jsonencode({
      bindings = [{
        name      = "timer"
        type      = "timerTrigger"
        direction = "in"
        schedule  = var.monitoring_frequency
      }]
    })
    filename = "UptimeChecker/function.json"
  }
  
  source {
    content = templatefile("${path.module}/function-code.js.tpl", {
      websites = jsonencode(var.websites_to_monitor)
    })
    filename = "UptimeChecker/index.js"
  }
  
  source {
    content = jsonencode({
      name = "uptime-checker"
      version = "1.0.0"
      description = "Simple website uptime checker"
      main = "index.js"
      dependencies = {}
    })
    filename = "package.json"
  }
}

# Upload function code to Function App
resource "azurerm_function_app_function" "uptime_checker" {
  name            = "UptimeChecker"
  function_app_id = azurerm_linux_function_app.main.id
  language        = "Javascript"
  
  file {
    name    = "index.js"
    content = templatefile("${path.module}/function-code.js.tpl", {
      websites = jsonencode(var.websites_to_monitor)
    })
  }
  
  config_json = jsonencode({
    bindings = [{
      authLevel = "function"
      name      = "timer"
      type      = "timerTrigger"
      direction = "in"
      schedule  = var.monitoring_frequency
    }]
  })
  
  depends_on = [azurerm_linux_function_app.main]
}

# Create function code template file
resource "local_file" "function_code_template" {
  content = <<-EOT
const https = require('https');
const http = require('http');
const { URL } = require('url');

// Websites to monitor - configured via Terraform variables
const WEBSITES = $${websites};

module.exports = async function (context, timer) {
    context.log('Uptime checker function started at:', new Date().toISOString());
    
    const results = [];
    
    for (const website of WEBSITES) {
        try {
            const result = await checkWebsite(website, context);
            results.push(result);
            
            // Log successful checks to Application Insights
            context.log(`✅ $${website}: $${result.status} ($${result.responseTime}ms) - Status: $${result.statusCode}`);
            
        } catch (error) {
            const failureResult = {
                url: website,
                status: 'ERROR',
                responseTime: 0,
                statusCode: 0,
                error: error.message,
                timestamp: new Date().toISOString()
            };
            
            results.push(failureResult);
            context.log(`❌ $${website}: $${error.message}`);
        }
    }
    
    // Generate summary telemetry for Application Insights
    const summary = {
        totalChecks: results.length,
        successfulChecks: results.filter(r => r.status === 'UP').length,
        failedChecks: results.filter(r => r.status !== 'UP').length,
        averageResponseTime: calculateAverageResponseTime(results),
        executionTimestamp: new Date().toISOString(),
        environment: process.env.ENVIRONMENT || 'unknown'
    };
    
    context.log('📊 Uptime check summary:', JSON.stringify(summary));
    
    // Log individual results for detailed analysis
    results.forEach(result => {
        context.log('📋 Site result:', JSON.stringify(result));
    });
    
    context.log('Uptime checker function completed successfully');
    return { summary, results };
};

/**
 * Check website availability and response time
 * @param {string} url - Website URL to check
 * @param {object} context - Azure Functions context for logging
 * @returns {Promise<object>} Check result with status, response time, and metadata
 */
async function checkWebsite(url, context) {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();
        const urlObj = new URL(url);
        const client = urlObj.protocol === 'https:' ? https : http;
        
        const options = {
            timeout: 10000,  // 10 second timeout
            headers: {
                'User-Agent': 'Azure-Function-Uptime-Checker/1.0'
            }
        };
        
        const request = client.get(url, options, (response) => {
            const responseTime = Date.now() - startTime;
            const isHealthy = response.statusCode >= 200 && response.statusCode < 300;
            const status = isHealthy ? 'UP' : 'DOWN';
            
            // Consume response data to free up memory
            response.on('data', () => {});
            response.on('end', () => {
                resolve({
                    url: url,
                    status: status,
                    responseTime: responseTime,
                    statusCode: response.statusCode,
                    timestamp: new Date().toISOString(),
                    headers: {
                        contentType: response.headers['content-type'],
                        server: response.headers.server
                    }
                });
            });
        });
        
        request.on('timeout', () => {
            request.destroy();
            reject(new Error('Request timeout after 10 seconds'));
        });
        
        request.on('error', (error) => {
            reject(new Error(`Network error: $${error.message}`));
        });
        
        request.setTimeout(10000);
    });
}

/**
 * Calculate average response time for successful checks
 * @param {Array} results - Array of check results
 * @returns {number} Average response time in milliseconds
 */
function calculateAverageResponseTime(results) {
    const successfulResults = results.filter(r => r.responseTime > 0);
    if (successfulResults.length === 0) return 0;
    
    const totalTime = successfulResults.reduce((sum, r) => sum + r.responseTime, 0);
    return Math.round(totalTime / successfulResults.length);
}
EOT
  filename = "${path.module}/function-code.js.tpl"
}
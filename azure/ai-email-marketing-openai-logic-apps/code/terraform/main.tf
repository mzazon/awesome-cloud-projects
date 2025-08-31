# Main Terraform configuration for AI-powered email marketing solution
# This file creates all Azure resources needed for the email marketing automation system

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent resource naming and configuration
locals {
  # Resource name suffix for uniqueness
  name_suffix = random_string.suffix.result
  
  # Common resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with unique suffixes
  resource_group_name           = "rg-${local.resource_prefix}-${local.name_suffix}"
  openai_service_name          = "openai-${local.resource_prefix}-${local.name_suffix}"
  logic_app_name               = "func-${local.resource_prefix}-${local.name_suffix}"
  communication_service_name   = "comms-${local.resource_prefix}-${local.name_suffix}"
  email_service_name           = "email-${local.resource_prefix}-${local.name_suffix}"
  storage_account_name         = "st${replace(local.resource_prefix, "-", "")}${local.name_suffix}"
  app_service_plan_name        = "plan-${local.resource_prefix}-${local.name_suffix}"
  application_insights_name    = "ai-${local.resource_prefix}-${local.name_suffix}"
  
  # OpenAI deployment configuration
  openai_deployment_name = "gpt-4o-marketing"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    DeployedBy     = "Terraform"
    DeploymentDate = timestamp()
    ResourceGroup  = local.resource_group_name
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all marketing solution resources
resource "azurerm_resource_group" "marketing" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Application Insights for monitoring and analytics
resource "azurerm_application_insights" "marketing" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.application_insights_name
  location            = azurerm_resource_group.marketing.location
  resource_group_name = azurerm_resource_group.marketing.name
  application_type    = "web"
  
  retention_in_days = 90
  
  tags = local.common_tags
}

# Create Azure OpenAI Service for content generation
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_service_name
  location            = azurerm_resource_group.marketing.location
  resource_group_name = azurerm_resource_group.marketing.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku_name
  
  # Enable managed identity for secure access
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  # Configure network access and security
  public_network_access_enabled = true
  
  # Custom subdomain for OpenAI endpoint
  custom_subdomain_name = local.openai_service_name
  
  tags = local.common_tags
}

# Deploy GPT-4o model for marketing content generation
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = local.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  sku {
    name     = "Standard"
    capacity = var.openai_deployment_capacity
  }
}

# Create Storage Account for Function App and Logic Apps runtime
resource "azurerm_storage_account" "marketing" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.marketing.name
  location                 = azurerm_resource_group.marketing.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and blob public access
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  
  # Enable versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Configure network access
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  # Enable advanced threat protection if specified
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
}

# Enable Advanced Threat Protection for Storage Account
resource "azurerm_advanced_threat_protection" "storage" {
  count              = var.enable_advanced_threat_protection ? 1 : 0
  target_resource_id = azurerm_storage_account.marketing.id
  enabled            = true
}

# Create App Service Plan for Function App (Logic Apps Standard)
resource "azurerm_service_plan" "marketing" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.marketing.name
  location            = azurerm_resource_group.marketing.location
  
  os_type  = "Linux"
  sku_name = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Create Function App for Logic Apps Standard workflow orchestration
resource "azurerm_linux_function_app" "marketing" {
  name                = local.logic_app_name
  resource_group_name = azurerm_resource_group.marketing.name
  location            = azurerm_resource_group.marketing.location
  service_plan_id     = azurerm_service_plan.marketing.id
  
  storage_account_name       = azurerm_storage_account.marketing.name
  storage_account_access_key = azurerm_storage_account.marketing.primary_access_key
  
  # Configure runtime and version
  site_config {
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable CORS for development
    cors {
      allowed_origins = ["*"]
    }
    
    # Configure Application Insights if enabled
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.marketing[0].connection_string
      }
    }
    
    # Function app configuration
    always_on = var.function_app_service_plan_sku != "Y1" # Always on not supported for Consumption plan
  }
  
  # Configure application settings for AI integration
  app_settings = {
    # Function runtime settings
    "FUNCTIONS_WORKER_RUNTIME"                   = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"               = "~${var.function_app_runtime_version}"
    "FUNCTIONS_EXTENSION_VERSION"                = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"                   = "1"
    
    # Azure OpenAI configuration
    "OPENAI_ENDPOINT"                           = azurerm_cognitive_account.openai.endpoint
    "OPENAI_KEY"                                = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.openai_key[0].versionless_id})"
    "OPENAI_DEPLOYMENT_NAME"                    = azurerm_cognitive_deployment.gpt4o.name
    
    # Communication Services configuration  
    "COMMUNICATION_CONNECTION_STRING"           = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.communication_string[0].versionless_id})"
    "COMMUNICATION_SERVICE_NAME"                = azurerm_communication_service.marketing.name
    "SENDER_EMAIL"                              = local.sender_email_address
    
    # AI content generation parameters
    "AI_MAX_TOKENS"                             = var.ai_max_tokens
    "AI_TEMPERATURE"                            = var.ai_temperature
    "TEST_EMAIL_RECIPIENT"                      = var.test_email_recipient
    
    # Workflow configuration
    "WORKFLOW_SCHEDULE_FREQUENCY"               = var.workflow_schedule_frequency
    "WORKFLOW_SCHEDULE_INTERVAL"                = var.workflow_schedule_interval
    "WORKFLOW_START_TIME"                       = var.workflow_start_time
    
    # Application Insights configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY"           = var.enable_application_insights ? azurerm_application_insights.marketing[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING"     = var.enable_application_insights ? azurerm_application_insights.marketing[0].connection_string : ""
  }
  
  # Enable managed identity for secure access to other Azure services
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_cognitive_deployment.gpt4o,
    azurerm_communication_service.marketing
  ]
}

# Create Communication Services for email delivery
resource "azurerm_communication_service" "marketing" {
  name                = local.communication_service_name
  resource_group_name = azurerm_resource_group.marketing.name
  data_location       = var.communication_data_location
  
  tags = local.common_tags
}

# Create Email Communication Services for email delivery infrastructure
resource "azurerm_email_communication_service" "marketing" {
  name                = local.email_service_name
  resource_group_name = azurerm_resource_group.marketing.name
  data_location       = var.communication_data_location
  
  tags = local.common_tags
}

# Create Email Communication Service Domain for sender identity
resource "azurerm_email_communication_service_domain" "marketing" {
  name             = "AzureManagedDomain"
  email_service_id = azurerm_email_communication_service.marketing.id
  
  domain_management = var.email_domain_management
  
  tags = local.common_tags
}

# Connect Communication Services with Email Service
resource "azurerm_communication_service_email_domain_association" "marketing" {
  communication_service_id = azurerm_communication_service.marketing.id
  email_service_domain_id  = azurerm_email_communication_service_domain.marketing.id
}

# Create Key Vault for secure storage of connection strings and keys
resource "azurerm_key_vault" "marketing" {
  count = var.enable_managed_identity ? 1 : 0
  
  name                = "kv-${local.resource_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.marketing.location
  resource_group_name = azurerm_resource_group.marketing.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # Configure access policies for the Function App managed identity
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_linux_function_app.marketing.identity[0].principal_id
    
    secret_permissions = [
      "Get",
      "List"
    ]
  }
  
  # Configure access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
  
  tags = local.common_tags
}

# Store OpenAI key in Key Vault
resource "azurerm_key_vault_secret" "openai_key" {
  count = var.enable_managed_identity ? 1 : 0
  
  name         = "openai-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.marketing[0].id
  
  depends_on = [azurerm_key_vault.marketing]
}

# Store Communication Services connection string in Key Vault
resource "azurerm_key_vault_secret" "communication_string" {
  count = var.enable_managed_identity ? 1 : 0
  
  name         = "communication-connection-string"
  value        = azurerm_communication_service.marketing.primary_connection_string
  key_vault_id = azurerm_key_vault.marketing[0].id
  
  depends_on = [azurerm_key_vault.marketing]
}

# Local value for sender email address construction
locals {
  # Construct sender email address from the managed domain
  sender_email_address = "DoNotReply@${azurerm_email_communication_service_domain.marketing.from_sender_domain}"
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "marketing" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "law-${local.resource_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.marketing.location
  resource_group_name = azurerm_resource_group.marketing.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# Create Action Group for alerting
resource "azurerm_monitor_action_group" "marketing" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "ag-${local.resource_prefix}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.marketing.name
  short_name          = "marketing"
  
  email_receiver {
    name          = "admin"
    email_address = var.test_email_recipient
  }
  
  tags = local.common_tags
}

# Create Metric Alert for OpenAI API failures
resource "azurerm_monitor_metric_alert" "openai_failures" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "alert-openai-failures-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.marketing.name
  scopes              = [azurerm_cognitive_account.openai.id]
  description         = "Alert when OpenAI API failures exceed threshold"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "ClientErrors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.marketing[0].id
  }
  
  frequency   = "PT5M"
  window_size = "PT15M"
  
  tags = local.common_tags
}
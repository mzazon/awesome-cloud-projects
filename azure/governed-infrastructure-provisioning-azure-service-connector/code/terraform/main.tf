# Main Terraform configuration for Azure Self-Service Infrastructure Provisioning
# with Azure Deployment Environments and Azure Service Connector

# Data sources for current client and subscription information
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate random password for SQL Server if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_admin_password == "" ? 1 : 0
  length  = 16
  special = true
}

# Local values for consistent naming and configuration
locals {
  suffix = random_string.suffix.result
  
  # Resource names with suffix for uniqueness
  devcenter_name              = var.devcenter_name != "" ? var.devcenter_name : "dc-${var.project_name}-${local.suffix}"
  project_name               = "proj-${var.environment}-${local.suffix}"
  catalog_name               = "catalog-templates-${local.suffix}"
  logic_app_approval_name    = "logic-approval-${local.suffix}"
  logic_app_lifecycle_name   = "logic-lifecycle-${local.suffix}"
  event_grid_topic_name      = "eg-deployment-events-${local.suffix}"
  key_vault_name             = "kv-secrets-${local.suffix}"
  sql_server_name            = "sql-server-${local.suffix}"
  sql_database_name          = "webapp-db"
  webapp_name                = "webapp-${local.suffix}"
  storage_account_name       = "st${replace(local.suffix, "-", "")}"
  
  # SQL admin password (use provided or generated)
  sql_admin_password = var.sql_admin_password != "" ? var.sql_admin_password : random_password.sql_admin_password[0].result
  
  # Common tags merged with provided tags
  common_tags = merge(var.tags, {
    CreatedBy         = "terraform"
    ResourceGroup     = var.resource_group_name
    DeploymentDate    = timestamp()
  })
}

# Create the main resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  enable_rbac_authorization = var.enable_rbac_authorization
  
  # Enable soft delete and purge protection for production environments
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Set to true for production
  
  tags = local.common_tags
}

# Assign Key Vault Administrator role to current user
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Store SQL admin password in Key Vault
resource "azurerm_key_vault_secret" "sql_admin_password" {
  depends_on = [azurerm_role_assignment.keyvault_admin]
  
  name         = "sql-admin-password"
  value        = local.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
}

# Create Event Grid topic for deployment events
resource "azurerm_eventgrid_topic" "deployment_events" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Create Azure DevCenter for managing deployment environments
resource "azurerm_dev_center" "main" {
  name                = local.devcenter_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create environment catalog pointing to Git repository with templates
resource "azurerm_dev_center_catalog" "templates" {
  name           = local.catalog_name
  dev_center_id  = azurerm_dev_center.main.id
  
  catalog_github {
    branch = var.catalog_repo_branch
    path   = var.catalog_repo_path
    uri    = var.catalog_repo_url
  }
  
  tags = local.common_tags
}

# Create DevCenter project for development teams
resource "azurerm_dev_center_project" "development" {
  name               = local.project_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  dev_center_id      = azurerm_dev_center.main.id
  
  maximum_dev_boxes_per_user = var.max_dev_boxes_per_user
  
  tags = local.common_tags
}

# Configure project environment type for development environments
resource "azurerm_dev_center_project_environment_type" "development" {
  name                         = var.project_environment_type
  dev_center_project_id        = azurerm_dev_center_project.development.id
  deployment_target_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"
  status                       = "Enabled"
  
  # Configure user role assignments for the environment type
  user_role_assignment {
    user_id = data.azurerm_client_config.current.object_id
    roles   = ["Contributor"]
  }
  
  tags = local.common_tags
}

# Assign DevCenter Project Admin role to current user
resource "azurerm_role_assignment" "project_admin" {
  scope                = azurerm_dev_center_project.development.id
  role_definition_name = "DevCenter Project Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Create Logic App for approval workflow
resource "azurerm_logic_app_workflow" "approval" {
  name                = local.logic_app_approval_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  workflow_schema = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
  
  parameters = {}
  
  tags = local.common_tags
}

# Create Logic App trigger for approval workflow
resource "azurerm_logic_app_trigger_http_request" "approval_trigger" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.approval.id
  
  schema = jsonencode({
    type = "object"
    properties = {
      environmentName = {
        type = "string"
      }
      projectName = {
        type = "string"
      }
      requestedBy = {
        type = "string"
      }
    }
  })
}

# Create Logic App action for environment approval
resource "azurerm_logic_app_action_http" "approve_environment" {
  name         = "approve_environment"
  logic_app_id = azurerm_logic_app_workflow.approval.id
  
  method = "POST"
  uri    = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.DevCenter/projects/${local.project_name}/environments/approve"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  depends_on = [azurerm_logic_app_trigger_http_request.approval_trigger]
}

# Create Event Grid subscription for deployment events
resource "azurerm_eventgrid_event_subscription" "deployment_approval" {
  name  = "deployment-approval-subscription"
  scope = azurerm_dev_center_project.development.id
  
  webhook_endpoint {
    url = azurerm_logic_app_trigger_http_request.approval_trigger.callback_url
  }
  
  included_event_types = [
    "Microsoft.DevCenter.EnvironmentCreated",
    "Microsoft.DevCenter.EnvironmentDeleted",
    "Microsoft.DevCenter.EnvironmentDeploymentCompleted"
  ]
  
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }
  
  # Configure dead letter storage for failed events
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.events.id
    storage_blob_container_name = azurerm_storage_container.dead_letter.name
  }
  
  depends_on = [azurerm_logic_app_trigger_http_request.approval_trigger]
}

# Create storage account for Event Grid dead letter queue
resource "azurerm_storage_account" "events" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  
  tags = local.common_tags
}

# Create storage container for dead letter events
resource "azurerm_storage_container" "dead_letter" {
  name                  = "dead-letter-events"
  storage_account_name  = azurerm_storage_account.events.name
  container_access_type = "private"
}

# Create SQL Server for sample web application
resource "azurerm_mssql_server" "main" {
  name                = local.sql_server_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  version             = "12.0"
  
  administrator_login          = var.sql_admin_username
  administrator_login_password = local.sql_admin_password
  
  # Enable Azure AD authentication
  azuread_administrator {
    login_username = data.azuread_client_config.current.display_name
    object_id      = data.azurerm_client_config.current.object_id
  }
  
  tags = local.common_tags
}

# Create SQL Database for web application
resource "azurerm_mssql_database" "webapp" {
  name      = local.sql_database_name
  server_id = azurerm_mssql_server.main.id
  sku_name  = var.sql_database_sku
  
  tags = local.common_tags
}

# Configure SQL Server firewall to allow Azure services
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create App Service Plan for sample web application
resource "azurerm_service_plan" "main" {
  name                = "plan-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  os_type  = "Linux"
  sku_name = "B1"
  
  tags = local.common_tags
}

# Create sample web application
resource "azurerm_linux_web_app" "sample" {
  name                = local.webapp_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    application_stack {
      dotnet_version = "6.0"
    }
    
    always_on = false
  }
  
  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }
  
  tags = local.common_tags
}

# Create Service Connector between web app and SQL database
resource "azurerm_app_service_connection" "webapp_sql" {
  name               = "webapp-sql-connection"
  app_service_id     = azurerm_linux_web_app.sample.id
  target_resource_id = azurerm_mssql_database.webapp.id
  
  authentication {
    type = "systemAssignedIdentity"
  }
  
  depends_on = [azurerm_linux_web_app.sample, azurerm_mssql_database.webapp]
}

# Create lifecycle management Logic App (if enabled)
resource "azurerm_logic_app_workflow" "lifecycle" {
  count = var.enable_lifecycle_management ? 1 : 0
  
  name                = local.logic_app_lifecycle_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  workflow_schema = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
  
  parameters = {}
  
  tags = local.common_tags
}

# Create recurrence trigger for lifecycle management
resource "azurerm_logic_app_trigger_recurrence" "lifecycle_trigger" {
  count = var.enable_lifecycle_management ? 1 : 0
  
  name         = "recurrence"
  logic_app_id = azurerm_logic_app_workflow.lifecycle[0].id
  frequency    = var.logic_app_recurrence_frequency
  interval     = var.logic_app_recurrence_interval
}

# Create action to check environment expiry
resource "azurerm_logic_app_action_http" "check_environment_expiry" {
  count = var.enable_lifecycle_management ? 1 : 0
  
  name         = "check_environment_expiry"
  logic_app_id = azurerm_logic_app_workflow.lifecycle[0].id
  
  method = "GET"
  uri    = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.DevCenter/projects/${local.project_name}/environments"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  depends_on = [azurerm_logic_app_trigger_recurrence.lifecycle_trigger]
}

# Assign necessary RBAC roles for DevCenter managed identity
resource "azurerm_role_assignment" "devcenter_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_dev_center.main.identity[0].principal_id
}

# Assign RBAC role for Event Grid to invoke Logic Apps
resource "azurerm_role_assignment" "eventgrid_logicapp" {
  scope                = azurerm_logic_app_workflow.approval.id
  role_definition_name = "Logic App Contributor"
  principal_id         = azurerm_eventgrid_topic.deployment_events.identity[0].principal_id
  
  depends_on = [azurerm_eventgrid_topic.deployment_events]
}

# Create resource tags for environment lifecycle management
resource "azurerm_tag" "environment_expiry" {
  operation = "Replace"
  resource_id = azurerm_resource_group.main.id
  
  tag {
    name  = "environment-expiry"
    value = "${var.environment_expiry_days}days"
  }
  
  tag {
    name  = "auto-cleanup"
    value = "enabled"
  }
  
  tag {
    name  = "cost-center"
    value = var.environment
  }
}
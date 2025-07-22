# Azure Carbon-Aware Cost Optimization Infrastructure
# This Terraform configuration deploys a complete carbon optimization solution
# using Azure Carbon Optimization, Azure Automation, and Azure Logic Apps

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  name_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    Location      = var.location
    CreatedBy     = "Terraform"
    Purpose       = "Carbon Optimization"
    LastModified  = timestamp()
  })
  
  # Resource naming convention
  resource_names = {
    automation_account    = "aa-carbon-opt-${local.name_suffix}"
    key_vault            = "kv-carbon-${local.name_suffix}"
    logic_app            = "la-carbon-optimization-${local.name_suffix}"
    log_analytics        = "law-carbon-opt-${local.name_suffix}"
    storage_account      = "stcarbonopt${local.name_suffix}"
    user_assigned_identity = "id-carbon-opt-${local.name_suffix}"
  }
}

# Resource Group for all carbon optimization resources
resource "azurerm_resource_group" "carbon_optimization" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "carbon_optimization" {
  name                = local.resource_names.log_analytics
  location            = azurerm_resource_group.carbon_optimization.location
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    Service = "Log Analytics"
    Purpose = "Carbon Optimization Monitoring"
  })
}

# Storage Account for Logic Apps and automation workflows
resource "azurerm_storage_account" "carbon_optimization" {
  name                     = local.resource_names.storage_account
  resource_group_name      = azurerm_resource_group.carbon_optimization.name
  location                 = azurerm_resource_group.carbon_optimization.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  tags = merge(local.common_tags, {
    Service = "Storage Account"
    Purpose = "Logic Apps and Automation Storage"
  })
}

# User-assigned managed identity for secure service access
resource "azurerm_user_assigned_identity" "carbon_optimization" {
  location            = azurerm_resource_group.carbon_optimization.location
  name                = local.resource_names.user_assigned_identity
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  
  tags = merge(local.common_tags, {
    Service = "Managed Identity"
    Purpose = "Carbon Optimization Service Access"
  })
}

# Key Vault for secure configuration management
resource "azurerm_key_vault" "carbon_optimization" {
  name                        = local.resource_names.key_vault
  location                    = azurerm_resource_group.carbon_optimization.location
  resource_group_name         = azurerm_resource_group.carbon_optimization.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = var.key_vault_sku
  
  # Enable RBAC for modern access control
  enable_rbac_authorization = true
  
  # Network access configuration
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow" # For demo purposes; restrict in production
  }
  
  tags = merge(local.common_tags, {
    Service = "Key Vault"
    Purpose = "Carbon Optimization Configuration"
  })
}

# Key Vault access policy for current user (needed for secret creation)
resource "azurerm_role_assignment" "key_vault_admin" {
  scope                = azurerm_key_vault.carbon_optimization.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Key Vault access for managed identity
resource "azurerm_role_assignment" "key_vault_managed_identity" {
  scope                = azurerm_key_vault.carbon_optimization.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

# Carbon optimization configuration secrets in Key Vault
resource "azurerm_key_vault_secret" "carbon_threshold_kg" {
  name         = "carbon-threshold-kg"
  value        = tostring(var.carbon_threshold_kg)
  key_vault_id = azurerm_key_vault.carbon_optimization.id
  
  depends_on = [azurerm_role_assignment.key_vault_admin]
  
  tags = {
    Purpose = "Carbon Optimization Threshold"
    Type    = "Configuration"
  }
}

resource "azurerm_key_vault_secret" "cost_threshold_usd" {
  name         = "cost-threshold-usd"
  value        = tostring(var.cost_threshold_usd)
  key_vault_id = azurerm_key_vault.carbon_optimization.id
  
  depends_on = [azurerm_role_assignment.key_vault_admin]
  
  tags = {
    Purpose = "Cost Optimization Threshold"
    Type    = "Configuration"
  }
}

resource "azurerm_key_vault_secret" "min_carbon_reduction_percent" {
  name         = "min-carbon-reduction-percent"
  value        = tostring(var.min_carbon_reduction_percent)
  key_vault_id = azurerm_key_vault.carbon_optimization.id
  
  depends_on = [azurerm_role_assignment.key_vault_admin]
  
  tags = {
    Purpose = "Carbon Reduction Threshold"
    Type    = "Configuration"
  }
}

resource "azurerm_key_vault_secret" "cpu_utilization_threshold" {
  name         = "cpu-utilization-threshold"
  value        = tostring(var.cpu_utilization_threshold)
  key_vault_id = azurerm_key_vault.carbon_optimization.id
  
  depends_on = [azurerm_role_assignment.key_vault_admin]
  
  tags = {
    Purpose = "CPU Utilization Threshold"
    Type    = "Configuration"
  }
}

# Azure Automation Account with managed identity
resource "azurerm_automation_account" "carbon_optimization" {
  name                = local.resource_names.automation_account
  location            = azurerm_resource_group.carbon_optimization.location
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  sku_name            = var.automation_account_sku
  
  # Enable managed identity for secure access
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.carbon_optimization.id]
  }
  
  tags = merge(local.common_tags, {
    Service = "Azure Automation"
    Purpose = "Carbon Optimization Runbooks"
  })
}

# Role assignments for Automation Account managed identity
resource "azurerm_role_assignment" "automation_cost_reader" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

resource "azurerm_role_assignment" "automation_vm_contributor" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

resource "azurerm_role_assignment" "automation_reader" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

# Carbon Optimization PowerShell Runbook
resource "azurerm_automation_runbook" "carbon_optimization" {
  name                    = "CarbonOptimizationRunbook"
  location                = azurerm_resource_group.carbon_optimization.location
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  log_verbose             = true
  log_progress            = true
  description             = "Automated carbon-aware cost optimization based on emissions data"
  runbook_type            = "PowerShell"
  
  content = local_file.carbon_optimization_runbook.content
  
  tags = merge(local.common_tags, {
    Service = "Automation Runbook"
    Purpose = "Carbon Optimization Logic"
  })
  
  depends_on = [local_file.carbon_optimization_runbook]
}

# Daily carbon optimization schedule
resource "azurerm_automation_schedule" "daily_optimization" {
  name                    = "DailyCarbonOptimization"
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  start_time              = "${formatdate("YYYY-MM-DD", timestamp())}T${var.optimization_schedule_time}:00Z"
  description             = "Daily carbon optimization analysis and actions"
}

# Peak carbon intensity optimization schedule
resource "azurerm_automation_schedule" "peak_optimization" {
  name                    = "PeakCarbonOptimization"
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  start_time              = "${formatdate("YYYY-MM-DD", timestamp())}T${var.peak_optimization_schedule_time}:00Z"
  description             = "Optimization during peak carbon intensity periods"
}

# Link schedules to runbook
resource "azurerm_automation_job_schedule" "daily_optimization" {
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  schedule_name           = azurerm_automation_schedule.daily_optimization.name
  runbook_name            = azurerm_automation_runbook.carbon_optimization.name
  
  parameters = {
    SubscriptionId    = data.azurerm_subscription.current.subscription_id
    ResourceGroupName = azurerm_resource_group.carbon_optimization.name
    KeyVaultName      = azurerm_key_vault.carbon_optimization.name
  }
}

resource "azurerm_automation_job_schedule" "peak_optimization" {
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  schedule_name           = azurerm_automation_schedule.peak_optimization.name
  runbook_name            = azurerm_automation_runbook.carbon_optimization.name
  
  parameters = {
    SubscriptionId    = data.azurerm_subscription.current.subscription_id
    ResourceGroupName = azurerm_resource_group.carbon_optimization.name
    KeyVaultName      = azurerm_key_vault.carbon_optimization.name
  }
}

# Logic App for carbon optimization orchestration
resource "azurerm_logic_app_workflow" "carbon_optimization" {
  name                = local.resource_names.logic_app
  location            = azurerm_resource_group.carbon_optimization.location
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  
  # Enable managed identity for secure service access
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.carbon_optimization.id]
  }
  
  # Workflow definition for carbon optimization orchestration
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  # The workflow definition is complex, so we'll use a templatefile
  workflow_parameters = jsonencode({})
  
  tags = merge(local.common_tags, {
    Service = "Logic Apps"
    Purpose = "Carbon Optimization Orchestration"
  })
}

# Role assignments for Logic App managed identity
resource "azurerm_role_assignment" "logic_app_automation_contributor" {
  scope                = azurerm_automation_account.carbon_optimization.id
  role_definition_name = "Automation Contributor"
  principal_id         = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

resource "azurerm_role_assignment" "logic_app_log_analytics_contributor" {
  scope                = azurerm_log_analytics_workspace.carbon_optimization.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

# Diagnostic settings for comprehensive logging (if enabled)
resource "azurerm_monitor_diagnostic_setting" "automation_account" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "automation-diagnostics"
  target_resource_id = azurerm_automation_account.carbon_optimization.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
  
  enabled_log {
    category = "JobLogs"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  enabled_log {
    category = "JobStreams"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "logicapp-diagnostics"
  target_resource_id = azurerm_logic_app_workflow.carbon_optimization.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
  
  enabled_log {
    category = "WorkflowRuntime"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "keyvault-diagnostics"
  target_resource_id = azurerm_key_vault.carbon_optimization.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
  
  enabled_log {
    category = "AuditEvent"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  enabled_log {
    category = "AzurePolicyEvaluationDetails"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Create runbooks directory and file
resource "null_resource" "create_runbooks_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/runbooks"
  }
}

resource "local_file" "carbon_optimization_runbook" {
  filename = "${path.module}/runbooks/carbon-optimization.ps1"
  content = templatefile("${path.module}/templates/carbon-optimization-runbook.ps1.tpl", {
    subscription_id = data.azurerm_subscription.current.subscription_id
  })
  
  # Create directory if it doesn't exist
  depends_on = [null_resource.create_runbooks_dir]
}
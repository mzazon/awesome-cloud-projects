# Main Terraform configuration for Azure Cost Governance with Resource Graph and Power BI
# This configuration creates a comprehensive cost governance solution that leverages
# Azure Resource Graph for real-time resource querying, Azure Cost Management APIs
# for spending data, and Power BI for executive dashboards.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>2.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create resource group for cost governance solution
resource "azurerm_resource_group" "cost_governance" {
  name     = "rg-cost-governance-${random_string.suffix.result}"
  location = var.location

  tags = {
    Purpose     = "cost-governance"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Create storage account for data persistence and Power BI integration
resource "azurerm_storage_account" "cost_governance" {
  name                     = "stcostgov${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.cost_governance.name
  location                 = azurerm_resource_group.cost_governance.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"

  # Network access rules
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = {
    Purpose     = "cost-governance-data"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Create storage containers for different data types
resource "azurerm_storage_container" "resource_graph_data" {
  name                  = "resource-graph-data"
  storage_account_name  = azurerm_storage_account.cost_governance.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "powerbi_datasets" {
  name                  = "powerbi-datasets"
  storage_account_name  = azurerm_storage_account.cost_governance.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "cost_reports" {
  name                  = "cost-reports"
  storage_account_name  = azurerm_storage_account.cost_governance.name
  container_access_type = "private"
}

# Create Key Vault for secure configuration storage
resource "azurerm_key_vault" "cost_governance" {
  name                        = "kv-cost-gov-${random_string.suffix.result}"
  location                    = azurerm_resource_group.cost_governance.location
  resource_group_name         = azurerm_resource_group.cost_governance.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  # Enable RBAC authorization
  enable_rbac_authorization = true

  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = {
    Purpose     = "cost-governance-secrets"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Store cost governance configuration secrets in Key Vault
resource "azurerm_key_vault_secret" "cost_threshold_monthly" {
  name         = "cost-threshold-monthly"
  value        = var.cost_threshold_monthly
  key_vault_id = azurerm_key_vault.cost_governance.id

  depends_on = [azurerm_role_assignment.current_user_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "cost_threshold_daily" {
  name         = "cost-threshold-daily"
  value        = var.cost_threshold_daily
  key_vault_id = azurerm_key_vault.cost_governance.id

  depends_on = [azurerm_role_assignment.current_user_kv_secrets_officer]
}

# Create Logic App for cost monitoring automation
resource "azurerm_logic_app_workflow" "cost_monitoring" {
  name                = "la-cost-governance-${random_string.suffix.result}"
  location            = azurerm_resource_group.cost_governance.location
  resource_group_name = azurerm_resource_group.cost_governance.name

  # Enable managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }

  tags = {
    Purpose     = "cost-governance-automation"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Create Action Group for cost alert notifications
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = "ag-cost-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.cost_governance.name
  short_name          = "CostAlerts"

  # Email notification configuration
  email_receiver {
    name          = "cost-admin"
    email_address = var.alert_email_address
  }

  # Webhook notification for external systems (e.g., Slack, Teams)
  webhook_receiver {
    name        = "cost-webhook"
    service_uri = var.webhook_url
  }

  tags = {
    Purpose     = "cost-governance-alerts"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Create consumption budget for monthly cost threshold monitoring
resource "azurerm_consumption_budget_subscription" "monthly_cost_governance" {
  name            = "monthly-cost-governance"
  subscription_id = data.azurerm_client_config.current.subscription_id

  amount     = var.cost_threshold_monthly
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
    end_date   = var.budget_end_date
  }

  # Notification when actual spend reaches 80% of budget
  notification {
    enabled        = true
    threshold      = 80.0
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [var.alert_email_address]
    contact_roles  = ["Owner"]
    contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
  }

  # Notification when forecasted spend reaches 100% of budget
  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [var.alert_email_address]
    contact_roles  = ["Owner"]
    contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
  }
}

# RBAC Role Assignments for secure access

# Grant Key Vault Secrets Officer role to current user for secret management
resource "azurerm_role_assignment" "current_user_kv_secrets_officer" {
  scope                = azurerm_key_vault.cost_governance.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant Cost Management Reader role to Logic App for cost data access
resource "azurerm_role_assignment" "logic_app_cost_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_logic_app_workflow.cost_monitoring.identity[0].principal_id
}

# Grant Reader role to Logic App for Resource Graph access
resource "azurerm_role_assignment" "logic_app_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_logic_app_workflow.cost_monitoring.identity[0].principal_id
}

# Grant Storage Blob Data Contributor role to Logic App for data storage
resource "azurerm_role_assignment" "logic_app_storage_contributor" {
  scope                = azurerm_storage_account.cost_governance.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.cost_monitoring.identity[0].principal_id
}

# Grant Key Vault Secrets User role to Logic App for secret access
resource "azurerm_role_assignment" "logic_app_kv_secrets_user" {
  scope                = azurerm_key_vault.cost_governance.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_logic_app_workflow.cost_monitoring.identity[0].principal_id
}

# Create local file for Resource Graph cost analysis query
resource "local_file" "cost_analysis_query" {
  filename = "${path.module}/queries/cost-analysis-query.kql"
  content  = <<-EOT
    resources
    | where type in~ [
        'microsoft.compute/virtualmachines',
        'microsoft.storage/storageaccounts',
        'microsoft.sql/servers',
        'microsoft.web/sites',
        'microsoft.containerinstance/containergroups',
        'microsoft.kubernetes/connectedclusters'
    ]
    | extend costCenter = tostring(tags['CostCenter'])
    | extend environment = tostring(tags['Environment'])
    | extend owner = tostring(tags['Owner'])
    | project 
        name,
        type,
        resourceGroup,
        location,
        subscriptionId,
        costCenter,
        environment,
        owner,
        tags
    | where isnotempty(name)
    | order by type, name
  EOT
}

# Create local file for tag compliance analysis query
resource "local_file" "tag_compliance_query" {
  filename = "${path.module}/queries/tag-compliance-query.kql"
  content  = <<-EOT
    resources
    | where type in~ [
        'microsoft.compute/virtualmachines',
        'microsoft.storage/storageaccounts',
        'microsoft.sql/servers'
    ]
    | extend hasOwnerTag = isnotempty(tags['Owner'])
    | extend hasCostCenterTag = isnotempty(tags['CostCenter'])
    | extend hasEnvironmentTag = isnotempty(tags['Environment'])
    | summarize 
        TotalResources = count(),
        ResourcesWithOwner = countif(hasOwnerTag),
        ResourcesWithCostCenter = countif(hasCostCenterTag),
        ResourcesWithEnvironment = countif(hasEnvironmentTag)
    by type, subscriptionId
    | extend 
        OwnerTagCompliance = round(100.0 * ResourcesWithOwner / TotalResources, 2),
        CostCenterTagCompliance = round(100.0 * ResourcesWithCostCenter / TotalResources, 2),
        EnvironmentTagCompliance = round(100.0 * ResourcesWithEnvironment / TotalResources, 2)
  EOT
}

# Create queries directory
resource "local_file" "queries_directory" {
  filename = "${path.module}/queries/.gitkeep"
  content  = "# Resource Graph queries for cost governance\n"
}
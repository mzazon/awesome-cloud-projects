# Main Terraform configuration for Azure AI Foundry and Compute Fleet ML Scaling
# This file creates all the necessary infrastructure for adaptive ML model scaling

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current Azure subscription and tenant information
data "azurerm_client_config" "current" {}

# Local values for computed resource names
locals {
  suffix = random_string.suffix.result
  
  # Computed resource names with defaults
  ai_foundry_hub_name           = var.ai_foundry_hub_name != "" ? var.ai_foundry_hub_name : "aif-adaptive-${local.suffix}"
  ai_foundry_project_name       = var.ai_foundry_project_name != "" ? var.ai_foundry_project_name : "project-${local.suffix}"
  machine_learning_workspace_name = var.machine_learning_workspace_name != "" ? var.machine_learning_workspace_name : "mlw-scaling-${local.suffix}"
  storage_account_name          = var.storage_account_name != "" ? var.storage_account_name : "stmlscaling${local.suffix}"
  key_vault_name               = var.key_vault_name != "" ? var.key_vault_name : "kv-ml-${local.suffix}"
  application_insights_name    = var.application_insights_name != "" ? var.application_insights_name : "ai-ml-${local.suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-ml-${local.suffix}"
  container_registry_name      = var.container_registry_name != "" ? var.container_registry_name : "acrmlscaling${local.suffix}"
  compute_fleet_name           = var.compute_fleet_name != "" ? var.compute_fleet_name : "cf-ml-scaling-${local.suffix}"
  
  # Merge provided tags with default tags
  tags = merge(var.tags, {
    "deployment-id" = local.suffix
    "created-by"    = "terraform"
    "last-updated"  = timestamp()
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# Storage Account for ML workspace
resource "azurerm_storage_account" "ml_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  # Enable hierarchical namespace for Data Lake Storage Gen2
  is_hns_enabled = true
  
  # Security settings
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Network access rules
  network_rules {
    default_action = var.network_configuration.enable_private_endpoints ? "Deny" : "Allow"
    ip_rules       = var.network_configuration.allowed_ip_ranges
    bypass         = ["AzureServices"]
  }
  
  tags = local.tags
}

# Key Vault for secrets management
resource "azurerm_key_vault" "ml_keyvault" {
  name                = local.key_vault_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id          = data.azurerm_client_config.current.tenant_id
  sku_name           = "standard"
  
  # Security settings
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  
  # Network access rules
  network_acls {
    default_action = var.network_configuration.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.network_configuration.allowed_ip_ranges
  }
  
  tags = local.tags
}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.ml_keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Purge"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Recover", "Purge"
  ]
}

# Application Insights for monitoring
resource "azurerm_application_insights" "ml_insights" {
  name                = local.application_insights_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id       = azurerm_log_analytics_workspace.ml_logs.id
  application_type   = "web"
  
  tags = local.tags
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "ml_logs" {
  name                = local.log_analytics_workspace_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = "PerGB2018"
  retention_in_days   = var.monitoring_configuration.metrics_retention_days
  
  tags = local.tags
}

# Container Registry for ML model containers
resource "azurerm_container_registry" "ml_registry" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  sku                = "Basic"
  admin_enabled      = true
  
  tags = local.tags
}

# Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "ml_workspace" {
  name                = local.machine_learning_workspace_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Associated resources
  application_insights_id = azurerm_application_insights.ml_insights.id
  key_vault_id           = azurerm_key_vault.ml_keyvault.id
  storage_account_id     = azurerm_storage_account.ml_storage.id
  container_registry_id  = azurerm_container_registry.ml_registry.id
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Security and compliance
  public_network_access_enabled = !var.network_configuration.enable_private_endpoints
  
  tags = local.tags
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}

# AI Foundry Hub (Azure ML Workspace with Hub kind)
resource "azurerm_machine_learning_workspace" "ai_foundry_hub" {
  name                = local.ai_foundry_hub_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind               = "Hub"
  
  # Associated resources
  application_insights_id = azurerm_application_insights.ml_insights.id
  key_vault_id           = azurerm_key_vault.ml_keyvault.id
  storage_account_id     = azurerm_storage_account.ml_storage.id
  container_registry_id  = azurerm_container_registry.ml_registry.id
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Security and compliance
  public_network_access_enabled = !var.network_configuration.enable_private_endpoints
  description                   = "AI Foundry Hub for ML Scaling and Agent Orchestration"
  
  tags = local.tags
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}

# AI Foundry Project (Azure ML Workspace with Project kind)
resource "azurerm_machine_learning_workspace" "ai_foundry_project" {
  name                = local.ai_foundry_project_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind               = "Project"
  
  # Associate with the hub
  hub_id = azurerm_machine_learning_workspace.ai_foundry_hub.id
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Security and compliance
  public_network_access_enabled = !var.network_configuration.enable_private_endpoints
  description                   = "AI Foundry Project for ML Scaling Agents"
  
  tags = local.tags
}

# Virtual Network for Compute Fleet (if needed for private endpoints)
resource "azurerm_virtual_network" "ml_vnet" {
  count               = var.network_configuration.enable_private_endpoints ? 1 : 0
  name                = "vnet-ml-scaling-${local.suffix}"
  address_space       = ["10.0.0.0/16"]
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.tags
}

# Subnet for Compute Fleet
resource "azurerm_subnet" "compute_subnet" {
  count                = var.network_configuration.enable_private_endpoints ? 1 : 0
  name                 = "subnet-compute-fleet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.ml_vnet[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

# Azure Compute Fleet using AzAPI provider (preview feature)
resource "azapi_resource" "compute_fleet" {
  type      = "Microsoft.AzureFleet/fleets@2024-05-01-preview"
  name      = local.compute_fleet_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  
  body = jsonencode({
    properties = {
      computeProfile = {
        baseVirtualMachineProfile = {
          storageProfile = {
            osDisk = {
              createOption = "FromImage"
              caching      = "ReadWrite"
              managedDisk = {
                storageAccountType = "Standard_LRS"
              }
            }
            imageReference = {
              publisher = "microsoft-dsvm"
              offer     = "aml-workstation"
              sku       = "ubuntu-20"
              version   = "latest"
            }
          }
          osProfile = {
            computerNamePrefix = "mlvm"
            adminUsername      = "azureuser"
            linuxConfiguration = {
              disablePasswordAuthentication = true
              ssh = {
                publicKeys = [
                  {
                    path    = "/home/azureuser/.ssh/authorized_keys"
                    keyData = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC..."
                  }
                ]
              }
            }
          }
          networkProfile = {
            networkInterfaceConfigurations = [
              {
                name = "nic-config"
                properties = {
                  primary = true
                  ipConfigurations = [
                    {
                      name = "ip-config"
                      properties = {
                        subnet = var.network_configuration.enable_private_endpoints ? {
                          id = azurerm_subnet.compute_subnet[0].id
                        } : null
                        publicIPAddressConfiguration = var.network_configuration.enable_private_endpoints ? null : {
                          name = "pip-config"
                          properties = {
                            idleTimeoutInMinutes = 15
                          }
                        }
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
        vmSizesProfile = [
          for vm_size in var.fleet_vm_sizes : {
            name = vm_size.name
            rank = vm_size.rank
          }
        ]
      }
      spotPriorityProfile = {
        capacity                = var.spot_instance_config.capacity
        minCapacity            = var.spot_instance_config.min_capacity
        maxPricePerVM          = var.spot_instance_config.max_price_per_vm
        evictionPolicy         = var.spot_instance_config.eviction_policy
        allocationStrategy     = var.spot_instance_config.allocation_strategy
        maintain               = true
      }
      regularPriorityProfile = {
        capacity           = var.regular_instance_config.capacity
        minCapacity       = var.regular_instance_config.min_capacity
        allocationStrategy = var.regular_instance_config.allocation_strategy
      }
    }
  })
  
  tags = local.tags
  
  depends_on = [
    azurerm_resource_group.main
  ]
}

# Action Group for scaling alerts
resource "azurerm_monitor_action_group" "ml_scaling_actions" {
  name                = "ag-ml-scaling-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "mlscaling"
  
  # Webhook for agent integration
  webhook_receiver {
    name                    = "agent-webhook"
    service_uri            = "https://api.example.com/webhook/scaling"
    use_common_alert_schema = true
  }
  
  tags = local.tags
}

# Monitor Metric Alert for CPU utilization
resource "azurerm_monitor_metric_alert" "cpu_utilization_alert" {
  name                = "alert-cpu-utilization-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_machine_learning_workspace.ml_workspace.id]
  description         = "Alert when ML workspace CPU utilization exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.MachineLearningServices/workspaces"
    metric_name      = "CpuUtilization"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.scaling_configuration.scale_up_threshold * 100
  }
  
  window_size        = var.monitoring_configuration.alert_window_size
  frequency          = var.monitoring_configuration.alert_evaluation_frequency
  severity           = 2
  
  action {
    action_group_id = azurerm_monitor_action_group.ml_scaling_actions.id
  }
  
  tags = local.tags
}

# Monitor Workbook for ML Scaling Dashboard
resource "azurerm_application_insights_workbook" "ml_scaling_dashboard" {
  name                = "workbook-ml-scaling-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  display_name       = "ML Adaptive Scaling Dashboard"
  source_id          = azurerm_application_insights.ml_insights.id
  
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 9
        content = {
          version = "KqlParameterItem/1.0"
          parameters = [
            {
              id = "timeRange"
              version = "KqlParameterItem/1.0"
              name = "TimeRange"
              type = 4
              value = {
                durationMs = 3600000
              }
            }
          ]
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AzureMetrics | where ResourceProvider == \"MICROSOFT.MACHINELEARNINGSERVICES\" | where MetricName in (\"CpuUtilization\", \"MemoryUtilization\") | summarize avg(Average) by bin(TimeGenerated, 5m), MetricName | render timechart"
          size = 0
          title = "ML Compute Utilization"
          timeContext = {
            durationMs = 3600000
          }
        }
      }
    ]
  })
  
  tags = local.tags
}

# Role assignments for ML workspace identity
resource "azurerm_role_assignment" "ml_workspace_storage" {
  scope                = azurerm_storage_account.ml_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.ml_workspace.identity[0].principal_id
}

resource "azurerm_role_assignment" "ml_workspace_keyvault" {
  scope                = azurerm_key_vault.ml_keyvault.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_machine_learning_workspace.ml_workspace.identity[0].principal_id
}

# Role assignments for AI Foundry hub identity
resource "azurerm_role_assignment" "ai_hub_storage" {
  scope                = azurerm_storage_account.ml_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.ai_foundry_hub.identity[0].principal_id
}

resource "azurerm_role_assignment" "ai_hub_keyvault" {
  scope                = azurerm_key_vault.ml_keyvault.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_machine_learning_workspace.ai_foundry_hub.identity[0].principal_id
}

# Store scaling configuration in Key Vault
resource "azurerm_key_vault_secret" "scaling_config" {
  name         = "scaling-configuration"
  value        = jsonencode(var.scaling_configuration)
  key_vault_id = azurerm_key_vault.ml_keyvault.id
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
  
  tags = local.tags
}

# Store agent configuration in Key Vault
resource "azurerm_key_vault_secret" "agent_config" {
  name         = "agent-configuration"
  value        = jsonencode(var.agent_model_configuration)
  key_vault_id = azurerm_key_vault.ml_keyvault.id
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
  
  tags = local.tags
}